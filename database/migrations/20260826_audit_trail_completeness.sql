-- ==============================================================================
-- MIGRATION: 20260826_audit_trail_completeness.sql
--
-- Turns the audit trail from a thin action log into a complete, printable
-- record of what happened, who did it, where, and to what.
--
-- WHY
--
--  (1) MOVEMENTS OF STOCK WERE THE LEAST DOCUMENTED THING IN THE SYSTEM
--      A transfer is the one inventory action with two facilities, two
--      timestamps, an approval, a quantity that can differ from the quantity
--      asked for, and four different people touching it. What the audit trail
--      recorded was a single sentence written at issue time. Nothing said where
--      the stock came from, when it was approved or by whom, how much was
--      approved against how much was requested, when it arrived, who confirmed
--      it, or which batch it landed in. Receipt, cancellation, delivery
--      re-planning, disposal, batch adjustment and open-vial discard wrote
--      nothing at all on most code paths.
--
--  (2) COVERAGE DEPENDED ON THE CODE PATH, NOT ON THE EVENT
--      audit_trail rows were written by hand at whichever call sites happened
--      to remember: some RPCs, some browser handlers, no mobile paths. The same
--      event audited or did not audit depending on which screen triggered it.
--      Coverage is now enforced by TRIGGERS on the tables themselves, so an
--      event is recorded because the data changed, not because a caller
--      remembered to say so.
--
--  (3) A ROW COULD NOT BE READ WITHOUT THE READER ALREADY KNOWING THE SCHEMA
--      description was one line and the rest was raw jsonb of the changed row,
--      full of foreign keys. audit_trail now carries a resolved actor snapshot,
--      a facility, a module, a severity, a named entity, a structured detail
--      breakdown, and a long-form narrative written for a person to read and
--      print.
--
-- WHAT IT ADDS
--
--   1. Context columns on audit_trail + an enrichment trigger that fills them
--      for EVERY writer, including the existing browser and mobile inserts that
--      this file does not change.
--   2. Narrative builders shared by every trigger.
--   3. Movement triggers over the whole inventory chain: request -> approval ->
--      issue -> delivery plan -> receipt -> dispense / adjust / discard ->
--      disposal.
--   4. Account, security, facility and clinical triggers.
--   5. Suppression of the now-redundant hand-written rows, whose operator
--      wording is merged into the trigger row rather than discarded.
--   6. audit_trail_detailed view for the portal, and a backfill of history.
--
-- Requires 20260824_inventory_integration_fixes.sql.
-- Safe to run more than once. Every statement is idempotent.
-- ==============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF to_regclass('public.audit_trail') IS NULL THEN
    RAISE EXCEPTION
      'Prerequisite missing: table public.audit_trail does not exist.';
  END IF;

  IF to_regclass('public.inventory_transactions') IS NULL THEN
    RAISE EXCEPTION
      'Prerequisite missing: table public.inventory_transactions does not exist. Run the inventory migrations first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'resolve_actor_account_id'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: function public.resolve_actor_account_id() does not exist. Run 20260821_inventory_and_td_fixes.sql first.';
  END IF;

  -- The stock-request trigger reads both of these as record fields, which fails
  -- at run time rather than here if they are absent. Say so now instead.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'inventory_stock_requests'
       AND column_name = 'approved_quantity'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: inventory_stock_requests.approved_quantity. Run 20260806_inventory_audit_fixes.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'inventory_stock_requests'
       AND column_name = 'is_archived'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: inventory_stock_requests.is_archived. Run 20260824_inventory_integration_fixes.sql first.';
  END IF;
END
$preflight$;


-- ---------------------------------------------------------------------------
-- 1. Context columns
--
-- All nullable and all additive: every existing INSERT keeps working untouched,
-- and the enrichment trigger in section 4 fills these in behind it.
--
-- The actor columns are SNAPSHOTS, deliberately denormalised. audit_trail
-- references accounts ON DELETE SET NULL, so removing an account today erases
-- the identity of everything that account ever did. A snapshot survives the
-- delete, which is the entire point of an audit trail.
-- ---------------------------------------------------------------------------
ALTER TABLE public.audit_trail
  ADD COLUMN IF NOT EXISTS actor_name           TEXT,
  ADD COLUMN IF NOT EXISTS actor_role           TEXT,
  ADD COLUMN IF NOT EXISTS actor_facility_id    BIGINT,
  ADD COLUMN IF NOT EXISTS actor_facility_name  TEXT,
  ADD COLUMN IF NOT EXISTS module               TEXT,
  ADD COLUMN IF NOT EXISTS severity             TEXT,
  ADD COLUMN IF NOT EXISTS entity_label         TEXT,
  ADD COLUMN IF NOT EXISTS narrative            TEXT,
  ADD COLUMN IF NOT EXISTS details              JSONB,
  ADD COLUMN IF NOT EXISTS related_ids          JSONB,
  ADD COLUMN IF NOT EXISTS source               TEXT,
  ADD COLUMN IF NOT EXISTS event_key            TEXT,
  ADD COLUMN IF NOT EXISTS event_txid           BIGINT;

COMMENT ON COLUMN public.audit_trail.actor_name IS
  'Full name of the actor as it was when the action happened. A snapshot, not a join: it outlives the account.';
COMMENT ON COLUMN public.audit_trail.actor_role IS
  'admin / mho / midwife / mother / system, snapshotted at action time.';
COMMENT ON COLUMN public.audit_trail.actor_facility_name IS
  'Facility the actor was operating from. A snapshot, for the same reason as actor_name.';
COMMENT ON COLUMN public.audit_trail.module IS
  'Top-level grouping for the portal filter: Inventory, Accounts, Security, Clinical, Facilities, AI, System.';
COMMENT ON COLUMN public.audit_trail.severity IS
  'info | notice | warning | critical. Drives the portal indicator and the needs-review figure.';
COMMENT ON COLUMN public.audit_trail.entity_label IS
  'Human name of the thing acted on, e.g. Td Vaccine - Batch TD-2026-014.';
COMMENT ON COLUMN public.audit_trail.narrative IS
  'Long-form prose account of the event, written to be read and printed on its own.';
COMMENT ON COLUMN public.audit_trail.details IS
  'Structured breakdown: {"sections":[{"title":..,"rows":[{"label":..,"value":..}]}]}. Rendered as-is by the portal.';
COMMENT ON COLUMN public.audit_trail.related_ids IS
  'Every identifier the event touched, so one row traces back to request, transfer, batch, item and facilities.';
COMMENT ON COLUMN public.audit_trail.source IS
  'database_trigger | admin_portal | mobile_app | system. Where the row was written from.';
COMMENT ON COLUMN public.audit_trail.event_key IS
  'Stable identity of the underlying event, e.g. inventory_transfers:42:received. Set only by the triggers in this file.';
COMMENT ON COLUMN public.audit_trail.event_txid IS
  'Transaction that produced the row. Used to fold a hand-written duplicate into the trigger row.';

CREATE INDEX IF NOT EXISTS idx_audit_trail_module
  ON public.audit_trail(module, action_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_trail_severity
  ON public.audit_trail(severity, action_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_trail_event_txid
  ON public.audit_trail(event_txid) WHERE event_txid IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_trail_event_key
  ON public.audit_trail(event_key) WHERE event_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_trail_table_row
  ON public.audit_trail(table_name, row_id);


-- ---------------------------------------------------------------------------
-- 1b. Two missing actor columns
--
-- Almost every inventory write reaches the database through an RPC that takes
-- the acting account and stores it: reviewed_by, issued_by, received_by,
-- performed_by, disposed_by. Two do not.
--
--   * Booking in a new batch is a plain INSERT from the portal, and
--     inventory_batches had nowhere to put the officer who did it.
--   * Cancelling a transfer is a plain UPDATE of status, and
--     inventory_transfers recorded who issued and who received but never who
--     called it off.
--
-- Both are exactly the "who did this" the audit trail is being asked for, and
-- no trigger can reconstruct an actor the row never carried. So the row carries
-- it now. Nullable, because history has no answer for them.
-- ---------------------------------------------------------------------------
ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS created_by BIGINT
    REFERENCES public.accounts(account_id) ON DELETE SET NULL;

ALTER TABLE public.inventory_transfers
  ADD COLUMN IF NOT EXISTS cancelled_by BIGINT
    REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

COMMENT ON COLUMN public.inventory_batches.created_by IS
  'Account that booked this batch in. NULL on batches created before 20260826 and on batches created by a transfer receipt, where inventory_transfers.received_by is the actor.';
COMMENT ON COLUMN public.inventory_transfers.cancelled_by IS
  'Account that cancelled the dispatch. NULL unless status is cancelled.';


-- ---------------------------------------------------------------------------
-- 2. Small builders
--
-- audit_kv returns an ARRAY, always, and an empty one when the value is blank.
-- That lets a caller write
--     audit_kv('Batch', v_batch) || audit_kv('Expiry', v_expiry)
-- and have absent facts disappear instead of rendering as "Expiry: -". Same
-- idea for audit_section, so a section with nothing in it is never emitted.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_kv(p_label TEXT, p_value TEXT)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE
           WHEN p_value IS NULL OR btrim(p_value) = '' THEN '[]'::jsonb
           ELSE jsonb_build_array(
                  jsonb_build_object('label', p_label, 'value', btrim(p_value)))
         END;
$fn$;

CREATE OR REPLACE FUNCTION public.audit_section(p_title TEXT, p_rows JSONB)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE
           WHEN p_rows IS NULL OR jsonb_array_length(p_rows) = 0 THEN '[]'::jsonb
           ELSE jsonb_build_array(
                  jsonb_build_object('title', p_title, 'rows', p_rows))
         END;
$fn$;

-- Every timestamp a person reads in this system is Asia/Manila. Converting
-- here means no trigger has to remember to.
CREATE OR REPLACE FUNCTION public.audit_ts(p_ts TIMESTAMPTZ)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $fn$
  SELECT CASE
           WHEN p_ts IS NULL THEN NULL
           ELSE to_char(p_ts AT TIME ZONE 'Asia/Manila',
                        'FMDay, FMDD FMMonth YYYY') || ' at ' ||
                to_char(p_ts AT TIME ZONE 'Asia/Manila', 'FMHH12:MI AM')
         END;
$fn$;

CREATE OR REPLACE FUNCTION public.audit_date(p_date DATE)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE
           WHEN p_date IS NULL THEN NULL
           ELSE to_char(p_date, 'FMDD FMMonth YYYY')
         END;
$fn$;

-- "3 units" / "1 unit", and the same for doses. Grammar matters in a document
-- somebody prints and files.
CREATE OR REPLACE FUNCTION public.audit_qty(p_qty NUMERIC, p_unit TEXT DEFAULT 'unit')
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE
           WHEN p_qty IS NULL THEN NULL
           ELSE trim(to_char(abs(p_qty), 'FM999G999G990')) || ' ' ||
                p_unit || CASE WHEN abs(p_qty) = 1 THEN '' ELSE 's' END
         END;
$fn$;

-- A cast that cannot take a trigger down with it.
--
-- The generic clinical trigger reads whichever actor column its table happens
-- to have, and accounts.created_by is a VARCHAR that legitimately holds 'self'
-- (see 20260808_created_by_allows_account_ids.sql). A bare ::bigint on that
-- value raises 22P02 inside an AFTER trigger, which would abort the caller's
-- insert - auditing must never be able to do that.
CREATE OR REPLACE FUNCTION public.audit_bigint(p_value TEXT)
RETURNS BIGINT
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE
           WHEN p_value ~ '^-?[0-9]{1,18}$' THEN p_value::bigint
           ELSE NULL
         END;
$fn$;

-- audit_trail.action_timestamp is TIMESTAMP WITHOUT TIME ZONE holding UTC, the
-- convention the admin portal already reads it with. Spell the interpretation
-- out here so a session running in another timezone cannot shift the record.
CREATE OR REPLACE FUNCTION public.audit_utc(p_ts TIMESTAMP)
RETURNS TIMESTAMPTZ
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT p_ts AT TIME ZONE 'UTC';
$fn$;

-- Strip secrets out of a row snapshot.
--
-- The account triggers snapshot whole rows with to_jsonb(), and accounts holds
-- a password hash, a verification code, a reset code and a login token. Storing
-- those in audit_trail would put every credential the system has ever issued
-- into the one table designed to be read, exported and printed by
-- administrators - and the portal's PDF export would carry them off the
-- premises. The FACT that a credential changed is auditable and is recorded in
-- the narrative; the VALUE is not.
--
-- Marked rather than deleted, so a reader can see that the field took part in
-- the change instead of wondering why the diff looks empty.
CREATE OR REPLACE FUNCTION public.audit_redact(p_data JSONB)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE
    WHEN p_data IS NULL OR jsonb_typeof(p_data) <> 'object' THEN p_data
    ELSE COALESCE(
      (
        SELECT jsonb_object_agg(
                 key,
                 CASE WHEN key IN ('password_hash', 'password', 'pending_password_hash',
                                   'temporary_password', 'verification_code', 'reset_code',
                                   'last_login_token', 'auth_id')
                      THEN to_jsonb('[redacted]'::text)
                      ELSE value
                 END)
          FROM jsonb_each(p_data)
      ),
      -- jsonb_object_agg over zero rows is NULL, not '{}'. An empty snapshot
      -- must stay an empty snapshot rather than becoming "nothing recorded".
      '{}'::jsonb
    )
  END;
$fn$;


-- ---------------------------------------------------------------------------
-- 3. Resolvers
-- ---------------------------------------------------------------------------

-- The actor, resolved once. Accepts either an account_id or a midwife_id,
-- because the clinical tables store the latter and the inventory ledger the
-- former, and a trigger cannot know which one it was handed.
CREATE OR REPLACE FUNCTION public.audit_actor(p_actor BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_account_id  BIGINT;
  v_name        TEXT;
  v_role        TEXT;
  v_facility_id BIGINT;
  v_facility    TEXT;
BEGIN
  IF p_actor IS NULL THEN
    RETURN jsonb_build_object('account_id', NULL, 'name', 'System',
                              'role', 'system', 'facility_id', NULL,
                              'facility_name', NULL);
  END IF;

  v_account_id := public.resolve_actor_account_id(p_actor);

  SELECT nullif(btrim(concat_ws(' ', a.first_name, a.last_name)), ''),
         a.account_type
    INTO v_name, v_role
    FROM public.accounts a
   WHERE a.account_id = v_account_id;

  IF v_name IS NULL AND v_role IS NULL THEN
    RETURN jsonb_build_object('account_id', v_account_id,
                              'name', 'Account #' || COALESCE(v_account_id, p_actor),
                              'role', 'unknown', 'facility_id', NULL,
                              'facility_name', NULL);
  END IF;

  SELECT fa.facility_id, hf.name
    INTO v_facility_id, v_facility
    FROM public.facility_assignments fa
    JOIN public.health_facilities hf ON hf.facility_id = fa.facility_id
   WHERE fa.account_id = v_account_id
     AND COALESCE(fa.is_active, true)
   ORDER BY fa.assigned_at DESC NULLS LAST, fa.facility_assignment_id DESC
   LIMIT 1;

  RETURN jsonb_build_object(
    'account_id',    v_account_id,
    'name',          COALESCE(v_name, 'Account #' || v_account_id),
    'role',          COALESCE(v_role, 'unknown'),
    'facility_id',   v_facility_id,
    'facility_name', v_facility
  );
END
$fn$;

-- "Sto. Nino BHC (BHC)". A NULL facility_id on a batch means the municipal
-- warehouse, which is a real place in this system but not a row in
-- health_facilities, so it gets named rather than left blank.
CREATE OR REPLACE FUNCTION public.audit_facility_label(p_facility_id BIGINT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_name TEXT;
  v_type TEXT;
BEGIN
  IF p_facility_id IS NULL THEN
    RETURN 'Central / Municipal Warehouse';
  END IF;

  SELECT name, facility_type INTO v_name, v_type
    FROM public.health_facilities WHERE facility_id = p_facility_id;

  IF v_name IS NULL THEN
    RETURN 'Facility #' || p_facility_id;
  END IF;

  RETURN v_name || COALESCE(' (' || v_type || ')', '');
END
$fn$;

-- Everything a movement row needs to know about the batch it moved, resolved
-- in one query instead of five lookups per trigger.
CREATE OR REPLACE FUNCTION public.audit_batch_context(p_batch_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v JSONB;
BEGIN
  IF p_batch_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT jsonb_build_object(
           'batch_id',        b.batch_id,
           'batch_number',    b.batch_number,
           'item_id',         i.item_id,
           'item_name',       i.name,
           'item_type',       i.item_type,
           'unit',            COALESCE(i.unit_of_measure, 'unit'),
           'doses_per_unit',  GREATEST(1, COALESCE(i.doses_per_unit, 1)),
           'facility_id',     b.facility_id,
           'facility_label',  public.audit_facility_label(b.facility_id),
           'expiration_date', b.expiration_date,
           'manufacturer',    b.manufacturer,
           'status',          b.status,
           'remaining',       b.quantity_remaining,
           'received',        b.quantity_received
         )
    INTO v
    FROM public.inventory_batches b
    JOIN public.inventory_items   i ON i.item_id = b.item_id
   WHERE b.batch_id = p_batch_id;

  RETURN COALESCE(v, jsonb_build_object('batch_id', p_batch_id));
END
$fn$;

-- "Td Vaccine - Batch TD-2026-014 (exp. 30 June 2027)"
CREATE OR REPLACE FUNCTION public.audit_batch_label(p_ctx JSONB)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $fn$
  SELECT COALESCE(p_ctx->>'item_name', 'Stock item')
      || COALESCE(' - Batch ' || (p_ctx->>'batch_number'), '')
      || COALESCE(' (exp. ' || public.audit_date((p_ctx->>'expiration_date')::date) || ')', '');
$fn$;

CREATE OR REPLACE FUNCTION public.audit_module_for(p_table TEXT, p_action TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE
    WHEN COALESCE(p_table, '') LIKE 'inventory%'                              THEN 'Inventory'
    WHEN p_action ILIKE '%inventory%' OR p_action ILIKE '%stock%'
      OR p_action ILIKE '%batch%'     OR p_action ILIKE '%transfer%'
      OR p_action ILIKE '%vial%'      OR p_action ILIKE '%dispos%'            THEN 'Inventory'
    WHEN p_action ILIKE '%password%'  OR p_action ILIKE '%login%'
      OR p_action ILIKE '%logout%'    OR p_action ILIKE '%session%'
      OR p_action ILIKE '%verif%'                                            THEN 'Security'
    WHEN COALESCE(p_table, '') IN ('accounts', 'password_history')
      OR p_action ILIKE '%account%'                                          THEN 'Accounts'
    WHEN COALESCE(p_table, '') IN ('health_facilities', 'facility_assignments', 'midwives')
      OR p_action ILIKE '%facility%'  OR p_action ILIKE '%midwife%'           THEN 'Facilities'
    WHEN COALESCE(p_table, '') IN ('ai_responses', 'ai_edit_history', 'ai_prompt_logs')
      OR lower(left(COALESCE(p_action, ''), 3)) = 'ai_'                       THEN 'AI'
    WHEN p_action ILIKE '%backup%'    OR p_action ILIKE '%restore%'           THEN 'System'
    WHEN COALESCE(p_table, '') IN ('mothers', 'children', 'pregnancies', 'prenatal_checkups',
                                   'clinical_encounters', 'immunization_records', 'lab_tests',
                                   'ultrasounds', 'deliveries', 'child_growth_records',
                                   'maternal_vitals', 'given_medications')    THEN 'Clinical'
    ELSE 'Activity'
  END;
$fn$;

-- Severity is about what a reviewer must not miss, not about how the action
-- felt to the person doing it. Anything that destroys stock, removes an
-- account, restores the database or fails a login is raised.
CREATE OR REPLACE FUNCTION public.audit_severity_for(p_action TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE
    -- database_restore rather than a bare %restore%: restoring an archived
    -- catalogue item is routine, and overwriting the database is not.
    WHEN p_action ILIKE '%delete%'          OR p_action ILIKE '%purge%'
      OR p_action ILIKE '%database_restore%' OR p_action ILIKE '%remove_account%' THEN 'critical'
    WHEN p_action ILIKE '%dispos%'  OR p_action ILIKE '%discard%'
      OR p_action ILIKE '%expire%'  OR p_action ILIKE '%cancel%'
      OR p_action ILIKE '%reject%'  OR p_action ILIKE '%fail%'
      OR p_action ILIKE '%suspend%' OR p_action ILIKE '%shortfall%'
      OR p_action ILIKE '%adjust%'                                           THEN 'warning'
    WHEN p_action ILIKE '%approve%' OR p_action ILIKE '%transfer%'
      OR p_action ILIKE '%backup%'  OR p_action ILIKE '%assign%'
      OR p_action ILIKE '%issue%'   OR p_action ILIKE '%receive%'
      OR p_action ILIKE '%create_account%' OR p_action ILIKE '%update_account%'
      OR p_action ILIKE '%password%'                                         THEN 'notice'
    ELSE 'info'
  END;
$fn$;


-- ---------------------------------------------------------------------------
-- 4. The central writer, and enrichment for everybody else
-- ---------------------------------------------------------------------------

-- One insert path for every trigger below. Resolves the actor snapshot, picks
-- the module and severity, and stamps the transaction id so a hand-written
-- duplicate arriving later in the same transaction can be folded into this row
-- rather than filed beside it.
CREATE OR REPLACE FUNCTION public.audit_write(
  p_actor        BIGINT,
  p_action       TEXT,
  p_table        TEXT,
  p_row_id       TEXT,
  p_entity       TEXT,
  p_summary      TEXT,
  p_narrative    TEXT,
  p_sections     JSONB   DEFAULT '[]'::jsonb,
  p_related      JSONB   DEFAULT '{}'::jsonb,
  p_old          JSONB   DEFAULT NULL,
  p_new          JSONB   DEFAULT NULL,
  p_severity     TEXT    DEFAULT NULL,
  p_event_suffix TEXT    DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_actor    JSONB := public.audit_actor(p_actor);
  v_audit_id BIGINT;
BEGIN
  INSERT INTO public.audit_trail (
    account_id, action, table_name, row_id, old_data, new_data, description,
    actor_name, actor_role, actor_facility_id, actor_facility_name,
    module, severity, entity_label, narrative, details, related_ids,
    source, event_key, event_txid
  ) VALUES (
    nullif(v_actor->>'account_id', '')::bigint,
    p_action,
    p_table,
    p_row_id,
    public.audit_redact(p_old),
    public.audit_redact(p_new),
    p_summary,
    v_actor->>'name',
    v_actor->>'role',
    nullif(v_actor->>'facility_id', '')::bigint,
    v_actor->>'facility_name',
    public.audit_module_for(p_table, p_action),
    COALESCE(p_severity, public.audit_severity_for(p_action)),
    p_entity,
    p_narrative,
    jsonb_build_object('sections', COALESCE(p_sections, '[]'::jsonb)),
    COALESCE(p_related, '{}'::jsonb),
    'database_trigger',
    concat_ws(':', p_table, p_row_id, COALESCE(p_event_suffix, p_action)),
    txid_current()
  )
  RETURNING audit_id INTO v_audit_id;

  RETURN v_audit_id;
END
$fn$;

-- Runs BEFORE INSERT on audit_trail, so it upgrades rows this migration never
-- sees: the browser handlers in admin-web, the Flutter screens, and the audit
-- writes still embedded in older RPC bodies.
--
-- Two jobs.
--
--   Fill.  A row that arrives with only account_id / action / description comes
--          out the other side with an actor snapshot, a facility, a module, a
--          severity and a readable narrative. No caller has to change.
--
--   Fold.  A trigger in section 5 has usually already written a far richer row
--          for the same change, in the same transaction, before the RPC that
--          made the change gets to its own INSERT. Keeping both files the same
--          event twice. So a legacy row is dropped when a trigger row for the
--          same table already exists in this transaction - but its wording is
--          appended to that row first, because the operator's own sentence
--          ("Disposed batch TD-2026-014 via incineration") is context the
--          trigger could not have known to write.
CREATE OR REPLACE FUNCTION public.audit_trail_enrich()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_actor    JSONB;
  v_existing public.audit_trail%ROWTYPE;
BEGIN
  -- Fold: only ever applies to a row that did not come from audit_write().
  IF NEW.event_key IS NULL AND NEW.table_name IS NOT NULL THEN
    SELECT * INTO v_existing
      FROM public.audit_trail
     WHERE event_txid = txid_current()
       AND event_key IS NOT NULL
       AND table_name = NEW.table_name
     ORDER BY audit_id DESC
     LIMIT 1;

    IF FOUND THEN
      IF nullif(btrim(COALESCE(NEW.description, '')), '') IS NOT NULL
         AND COALESCE(v_existing.description, '') <> NEW.description THEN
        UPDATE public.audit_trail
           SET details = jsonb_set(
                 COALESCE(details, jsonb_build_object('sections', '[]'::jsonb)),
                 '{sections}',
                 COALESCE(details->'sections', '[]'::jsonb) ||
                 public.audit_section('Operator note',
                   public.audit_kv('Recorded by the app as', NEW.description))
               )
         WHERE audit_id = v_existing.audit_id;
      END IF;

      RETURN NULL;  -- the trigger row already covers this event
    END IF;
  END IF;

  -- Fill.
  --
  -- Redaction runs for every writer, not only audit_write: the portal's own
  -- account handlers also snapshot rows into old_data / new_data, and a
  -- credential must not reach this table by any route.
  NEW.old_data   := public.audit_redact(NEW.old_data);
  NEW.new_data   := public.audit_redact(NEW.new_data);
  NEW.event_txid := COALESCE(NEW.event_txid, txid_current());
  NEW.source     := COALESCE(NEW.source, 'application');
  NEW.module     := COALESCE(NEW.module, public.audit_module_for(NEW.table_name, NEW.action));
  NEW.severity   := COALESCE(NEW.severity, public.audit_severity_for(NEW.action));

  IF NEW.actor_name IS NULL THEN
    v_actor := public.audit_actor(NEW.account_id);
    NEW.actor_name          := v_actor->>'name';
    NEW.actor_role          := v_actor->>'role';
    NEW.actor_facility_id   := nullif(v_actor->>'facility_id', '')::bigint;
    NEW.actor_facility_name := v_actor->>'facility_name';
  END IF;

  IF NEW.narrative IS NULL THEN
    NEW.narrative := format(
      '%s (%s) performed the action "%s"%s on %s. %s',
      COALESCE(NEW.actor_name, 'System'),
      COALESCE(NEW.actor_role, 'system'),
      NEW.action,
      COALESCE(' against ' || NEW.table_name, ''),
      COALESCE(public.audit_ts(public.audit_utc(NEW.action_timestamp)),
               public.audit_ts(now())),
      COALESCE(NEW.description, 'No further detail was recorded by the application.')
    );
  END IF;

  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_audit_trail_enrich ON public.audit_trail;
CREATE TRIGGER trg_audit_trail_enrich
  BEFORE INSERT ON public.audit_trail
  FOR EACH ROW EXECUTE FUNCTION public.audit_trail_enrich();


-- ---------------------------------------------------------------------------
-- 5. Inventory: the movement chain
--
-- Six triggers cover every state an item of stock can pass through. Together
-- they answer, for any unit in the system: who asked for it, who approved it
-- and for how much against how much was asked, which batch it left, which
-- facility it left, which facility it arrived at, who confirmed the arrival,
-- which batch it landed in, and what finally happened to it.
-- ---------------------------------------------------------------------------

-- 5a. Stock requests --------------------------------------------------------
--
-- One trigger for the whole lifecycle. On UPDATE it audits the STATUS
-- TRANSITION rather than the row, because "approved" and "rejected" are
-- different events with different reviewers and different consequences, and
-- filing them both as "request updated" is how the old trail lost them.
CREATE OR REPLACE FUNCTION public.audit_inventory_stock_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_item      TEXT;
  v_unit      TEXT;
  v_facility  TEXT;
  v_actor     BIGINT;
  v_action    TEXT;
  v_summary   TEXT;
  v_narrative TEXT;
  v_sections  JSONB := '[]'::jsonb;
  v_rows      JSONB := '[]'::jsonb;
  v_approved  INTEGER;
  v_entity    TEXT;
BEGIN
  SELECT name, COALESCE(unit_of_measure, 'unit')
    INTO v_item, v_unit
    FROM public.inventory_items WHERE item_id = NEW.item_id;

  v_item     := COALESCE(v_item, 'Item #' || NEW.item_id);
  v_unit     := COALESCE(v_unit, 'unit');
  v_facility := public.audit_facility_label(NEW.facility_id);
  v_approved := COALESCE(NEW.approved_quantity, NEW.requested_quantity);
  v_entity   := format('Stock request #%s - %s', NEW.request_id, v_item);

  IF TG_OP = 'INSERT' THEN
    v_actor  := NEW.requested_by;
    v_action := 'submit_inventory_stock_request';
    v_summary := format('%s requested %s of %s',
                        v_facility, public.audit_qty(NEW.requested_quantity, v_unit), v_item);
    v_narrative := format(
      'A stock request was raised by %s. The facility is asking the Rural Health Unit for %s of %s. '
      'The reason given was: "%s". The request was logged as #%s on %s and now sits with RHU Main for review. '
      'No stock has moved and no batch has been touched at this point - this row records the ask only.',
      v_facility,
      public.audit_qty(NEW.requested_quantity, v_unit),
      v_item,
      COALESCE(NEW.reason, 'not stated'),
      NEW.request_id,
      public.audit_ts(NEW.created_at)
    );

    v_rows := public.audit_kv('Request number', '#' || NEW.request_id)
           || public.audit_kv('Requesting facility', v_facility)
           || public.audit_kv('Item', v_item)
           || public.audit_kv('Quantity requested', public.audit_qty(NEW.requested_quantity, v_unit))
           || public.audit_kv('Reason', NEW.reason)
           || public.audit_kv('Remarks from requester', NEW.remarks)
           || public.audit_kv('Submitted on', public.audit_ts(NEW.created_at))
           || public.audit_kv('Status', 'Pending review');
    v_sections := public.audit_section('Request', v_rows);

  ELSIF TG_OP = 'UPDATE' THEN
    -- Archiving is a display preference, not a movement. Audit it, quietly.
    IF NEW.status = OLD.status AND COALESCE(NEW.is_archived, false) IS DISTINCT FROM COALESCE(OLD.is_archived, false) THEN
      PERFORM public.audit_write(
        NEW.reviewed_by,
        CASE WHEN NEW.is_archived THEN 'archive_stock_request' ELSE 'unarchive_stock_request' END,
        'inventory_stock_requests', NEW.request_id::text, v_entity,
        format('Stock request #%s was %s', NEW.request_id,
               CASE WHEN NEW.is_archived THEN 'archived' ELSE 'restored to the active list' END),
        format('Stock request #%s (%s for %s) was %s. Archiving only hides the request from the active list; '
               'its status remains "%s" and no stock is affected.',
               NEW.request_id, v_facility, v_item,
               CASE WHEN NEW.is_archived THEN 'archived' ELSE 'restored to the active list' END,
               NEW.status),
        public.audit_section('Request',
          public.audit_kv('Request number', '#' || NEW.request_id)
          || public.audit_kv('Facility', v_facility)
          || public.audit_kv('Item', v_item)
          || public.audit_kv('Workflow status', NEW.status)),
        jsonb_build_object('request_id', NEW.request_id, 'item_id', NEW.item_id,
                           'facility_id', NEW.facility_id),
        to_jsonb(OLD), to_jsonb(NEW), 'info',
        CASE WHEN NEW.is_archived THEN 'archived' ELSE 'unarchived' END
      );
      RETURN NULL;
    END IF;

    IF NEW.status = OLD.status THEN
      RETURN NULL;   -- nothing a reader would call an event
    END IF;

    v_actor := COALESCE(NEW.reviewed_by, OLD.reviewed_by, NEW.requested_by);

    v_action := CASE NEW.status
                  WHEN 'approved'  THEN 'approve_stock_request'
                  WHEN 'rejected'  THEN 'reject_stock_request'
                  WHEN 'issued'    THEN 'issue_stock_request'
                  WHEN 'received'  THEN 'receive_stock_request'
                  WHEN 'completed' THEN 'complete_stock_request'
                  WHEN 'cancelled' THEN 'cancel_stock_request'
                  ELSE 'update_stock_request'
                END;

    v_summary := format('Stock request #%s for %s moved from %s to %s',
                        NEW.request_id, v_item, OLD.status, NEW.status);

    v_narrative := CASE NEW.status
      WHEN 'approved' THEN format(
        'Stock request #%s from %s was APPROVED on %s. %s of %s was asked for and %s was approved%s. '
        'Approval authorises the issue but does not itself move stock: the units stay in their source batch '
        'until a transfer is issued against this request. Administrator remarks: "%s".',
        NEW.request_id, v_facility, public.audit_ts(NEW.reviewed_at),
        public.audit_qty(NEW.requested_quantity, v_unit), v_item,
        public.audit_qty(v_approved, v_unit),
        CASE WHEN v_approved < NEW.requested_quantity
             THEN format(', a shortfall of %s against the request',
                         public.audit_qty(NEW.requested_quantity - v_approved, v_unit))
             ELSE ' in full' END,
        COALESCE(NEW.admin_remarks, 'none recorded'))
      WHEN 'rejected' THEN format(
        'Stock request #%s from %s for %s of %s was REJECTED on %s. No stock was reserved or moved. '
        'The reason the facility originally gave was "%s". Administrator remarks: "%s".',
        NEW.request_id, v_facility, public.audit_qty(NEW.requested_quantity, v_unit), v_item,
        public.audit_ts(NEW.reviewed_at), COALESCE(NEW.reason, 'not stated'),
        COALESCE(NEW.admin_remarks, 'none recorded'))
      WHEN 'issued' THEN format(
        'Stock request #%s from %s reached ISSUED. %s of %s has left its source batch and is in transit to the '
        'requesting facility, awaiting a receipt confirmation there. The matching transfer record carries the '
        'batch, the source facility and the dispatch time.',
        NEW.request_id, v_facility, public.audit_qty(v_approved, v_unit), v_item)
      WHEN 'received' THEN format(
        'Stock request #%s from %s was marked RECEIVED. %s of %s has arrived at the facility and been credited to '
        'a batch there. The request is now closed as fulfilled.',
        NEW.request_id, v_facility, public.audit_qty(v_approved, v_unit), v_item)
      WHEN 'cancelled' THEN format(
        'Stock request #%s from %s for %s of %s was CANCELLED while in "%s". Any stock already deducted for it is '
        'returned by the matching transfer cancellation, which is audited separately.',
        NEW.request_id, v_facility, public.audit_qty(NEW.requested_quantity, v_unit), v_item, OLD.status)
      ELSE format(
        'Stock request #%s from %s for %s of %s changed status from "%s" to "%s" on %s.',
        NEW.request_id, v_facility, public.audit_qty(NEW.requested_quantity, v_unit), v_item,
        OLD.status, NEW.status, public.audit_ts(COALESCE(NEW.updated_at, now())))
    END;

    v_rows := public.audit_kv('Request number', '#' || NEW.request_id)
           || public.audit_kv('Requesting facility', v_facility)
           || public.audit_kv('Item', v_item)
           || public.audit_kv('Status before', OLD.status)
           || public.audit_kv('Status after', NEW.status)
           || public.audit_kv('Quantity requested', public.audit_qty(NEW.requested_quantity, v_unit))
           || public.audit_kv('Quantity approved',
                CASE WHEN NEW.status IN ('approved','issued','received','completed')
                     THEN public.audit_qty(v_approved, v_unit) END)
           || public.audit_kv('Shortfall against request',
                CASE WHEN NEW.status IN ('approved','issued','received','completed')
                      AND v_approved < NEW.requested_quantity
                     THEN public.audit_qty(NEW.requested_quantity - v_approved, v_unit) END)
           || public.audit_kv('Reviewed by', (public.audit_actor(NEW.reviewed_by))->>'name')
           || public.audit_kv('Reviewed on', public.audit_ts(NEW.reviewed_at))
           || public.audit_kv('Administrator remarks', NEW.admin_remarks)
           || public.audit_kv('Original reason for request', NEW.reason);
    v_sections := public.audit_section('Request and decision', v_rows);
  END IF;

  PERFORM public.audit_write(
    v_actor, v_action, 'inventory_stock_requests', NEW.request_id::text, v_entity,
    v_summary, v_narrative, v_sections,
    jsonb_build_object('request_id', NEW.request_id, 'item_id', NEW.item_id,
                       'facility_id', NEW.facility_id,
                       'requested_by', NEW.requested_by, 'reviewed_by', NEW.reviewed_by),
    CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END,
    to_jsonb(NEW), NULL, NEW.status
  );

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_audit_inventory_stock_request ON public.inventory_stock_requests;
CREATE TRIGGER trg_audit_inventory_stock_request
  AFTER INSERT OR UPDATE ON public.inventory_stock_requests
  FOR EACH ROW EXECUTE FUNCTION public.audit_inventory_stock_request();


-- 5b. Transfers -------------------------------------------------------------
--
-- The event the user could not trace. Every transfer row now produces a record
-- at issue, at receipt, at cancellation and at each delivery re-plan, and each
-- one carries BOTH ends of the movement, the linked request with its approval,
-- and the batch on either side.
CREATE OR REPLACE FUNCTION public.audit_inventory_transfer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_src        JSONB := public.audit_batch_context(NEW.source_batch_id);
  v_dst        JSONB;
  v_unit       TEXT;
  v_item       TEXT;
  v_from       TEXT;
  v_to         TEXT;
  v_req        public.inventory_stock_requests%ROWTYPE;
  v_actor      BIGINT;
  v_action     TEXT;
  v_summary    TEXT;
  v_narrative  TEXT;
  v_rows       JSONB := '[]'::jsonb;
  v_sections   JSONB := '[]'::jsonb;
  v_entity     TEXT;
  v_doses      INTEGER;
  v_transit    TEXT;
  v_plan_old   TEXT;
  v_plan_new   TEXT;
  v_situation  TEXT;
  v_note       TEXT;
  v_shelf      TEXT;
  v_cancelled  TIMESTAMPTZ;
BEGIN
  v_item := COALESCE(v_src->>'item_name', 'Stock item');
  v_unit := COALESCE(v_src->>'unit', 'unit');
  v_from := COALESCE(v_src->>'facility_label', 'an unrecorded location');
  v_to   := public.audit_facility_label(NEW.destination_facility_id);
  v_doses := NEW.quantity_issued * GREATEST(1, COALESCE((v_src->>'doses_per_unit')::int, 1));
  v_entity := format('Transfer #%s - %s', NEW.transfer_id, public.audit_batch_label(v_src));

  IF NEW.request_id IS NOT NULL THEN
    SELECT * INTO v_req FROM public.inventory_stock_requests WHERE request_id = NEW.request_id;
  END IF;

  -- There is no expected_arrival_date COLUMN anywhere in this schema.
  -- update_inventory_transfer_delivery() (20260806) takes the date as a
  -- parameter and folds the whole plan into inventory_transfers.remarks as two
  -- text lines:
  --
  --   Delivery plan: expected 2026-09-01 (7-day estimate); batch expires
  --                  2027-06-30; 302 days of shelf life at arrival.
  --   Delivery update: Delayed on 2026-08-25. Truck broke down at Pagsanjan.
  --
  -- So the re-plan is detected on remarks and its facts are read back out of
  -- that text, which is the only place they exist.
  v_plan_new := substring(COALESCE(NEW.remarks, '')
                          from 'Delivery plan: expected ([0-9]{4}-[0-9]{2}-[0-9]{2})');
  IF TG_OP = 'UPDATE' THEN
    v_plan_old := substring(COALESCE(OLD.remarks, '')
                            from 'Delivery plan: expected ([0-9]{4}-[0-9]{2}-[0-9]{2})');
  END IF;

  -- Shared "where it came from / where it is going" block.
  v_rows := public.audit_kv('Transfer number', '#' || NEW.transfer_id)
         || public.audit_kv('Item', v_item)
         || public.audit_kv('Source batch', v_src->>'batch_number')
         || public.audit_kv('Batch expiry', public.audit_date((v_src->>'expiration_date')::date))
         || public.audit_kv('Manufacturer', v_src->>'manufacturer')
         || public.audit_kv('MOVED FROM', v_from)
         || public.audit_kv('MOVED TO', v_to)
         || public.audit_kv('Quantity issued', public.audit_qty(NEW.quantity_issued, v_unit))
         || public.audit_kv('Equivalent clinical doses',
              CASE WHEN v_doses <> NEW.quantity_issued THEN public.audit_qty(v_doses, 'dose') END)
         || public.audit_kv('Issued by', (public.audit_actor(NEW.issued_by))->>'name')
         || public.audit_kv('Issued on', public.audit_ts(NEW.issued_at))
         || public.audit_kv('Remarks on dispatch', NEW.remarks);

  IF NEW.request_id IS NOT NULL AND v_req.request_id IS NOT NULL THEN
    v_rows := v_rows
      || public.audit_kv('Against stock request', '#' || v_req.request_id)
      || public.audit_kv('Quantity originally requested',
           public.audit_qty(v_req.requested_quantity, v_unit))
      || public.audit_kv('Quantity approved',
           public.audit_qty(COALESCE(v_req.approved_quantity, v_req.requested_quantity), v_unit))
      || public.audit_kv('Approved by', (public.audit_actor(v_req.reviewed_by))->>'name')
      || public.audit_kv('Approved on', public.audit_ts(v_req.reviewed_at))
      || public.audit_kv('Approval remarks', v_req.admin_remarks);
  ELSE
    v_rows := v_rows
      || public.audit_kv('Against stock request', 'None - issued at the administrator''s discretion');
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_actor  := NEW.issued_by;
    v_action := 'issue_inventory_transfer';
    v_summary := format('Issued %s of %s from %s to %s',
                        public.audit_qty(NEW.quantity_issued, v_unit), v_item, v_from, v_to);
    v_narrative := format(
      'Stock was DISPATCHED. %s of %s was taken out of batch %s at %s and sent to %s under transfer #%s, issued by %s on %s. '
      'The source batch was debited immediately; the destination is NOT credited until somebody at %s confirms receipt, so '
      'these units are currently in transit and counted at neither end. %s%s%s',
      public.audit_qty(NEW.quantity_issued, v_unit),
      v_item,
      COALESCE(v_src->>'batch_number', 'an unrecorded batch'),
      v_from, v_to, NEW.transfer_id,
      (public.audit_actor(NEW.issued_by))->>'name',
      public.audit_ts(NEW.issued_at),
      v_to,
      CASE WHEN v_req.request_id IS NOT NULL
           THEN format('This dispatch settles stock request #%s, which asked for %s and was approved for %s by %s on %s. ',
                       v_req.request_id,
                       public.audit_qty(v_req.requested_quantity, v_unit),
                       public.audit_qty(COALESCE(v_req.approved_quantity, v_req.requested_quantity), v_unit),
                       (public.audit_actor(v_req.reviewed_by))->>'name',
                       public.audit_ts(v_req.reviewed_at))
           ELSE 'No stock request is linked: this was issued at the administrator''s own discretion. ' END,
      CASE WHEN v_doses <> NEW.quantity_issued
           THEN format('That is %s once the vials are opened. ', public.audit_qty(v_doses, 'dose'))
           ELSE '' END,
      COALESCE('Dispatch remarks: "' || NEW.remarks || '".', '')
    );
    v_sections := public.audit_section('Movement', v_rows);

  ELSIF TG_OP = 'UPDATE' THEN
    -- Receipt.
    IF NEW.status = 'received' AND OLD.status <> 'received' THEN
      v_dst    := public.audit_batch_context(NEW.destination_batch_id);
      v_actor  := NEW.received_by;
      v_action := 'receive_inventory_transfer';
      v_transit := CASE
        WHEN NEW.received_at IS NULL OR NEW.issued_at IS NULL THEN NULL
        ELSE public.audit_qty(GREATEST(0, EXTRACT(EPOCH FROM (NEW.received_at - NEW.issued_at)) / 86400)::int, 'day')
      END;
      v_summary := format('%s confirmed receipt of %s of %s from %s',
                          v_to, public.audit_qty(NEW.quantity_issued, v_unit), v_item, v_from);
      v_narrative := format(
        'Stock ARRIVED and was confirmed. %s at %s confirmed receipt of transfer #%s on %s: %s of %s, dispatched from %s on %s. '
        'The units were credited to batch %s at the receiving facility%s. %s The chain for these units is now complete: '
        'requested %s, approved %s, dispatched %s, received %s.',
        COALESCE((public.audit_actor(NEW.received_by))->>'name', 'A staff member'),
        v_to, NEW.transfer_id, public.audit_ts(NEW.received_at),
        public.audit_qty(NEW.quantity_issued, v_unit), v_item, v_from, public.audit_ts(NEW.issued_at),
        COALESCE(v_dst->>'batch_number', 'a new batch record'),
        COALESCE(', which now holds ' || public.audit_qty((v_dst->>'remaining')::numeric, v_unit), ''),
        COALESCE('The stock spent ' || v_transit || ' in transit. ', ''),
        COALESCE(public.audit_ts(v_req.created_at), 'n/a'),
        COALESCE(public.audit_ts(v_req.reviewed_at), 'n/a'),
        COALESCE(public.audit_ts(NEW.issued_at), 'n/a'),
        COALESCE(public.audit_ts(NEW.received_at), 'n/a')
      );
      v_rows := v_rows
             || public.audit_kv('Received by', (public.audit_actor(NEW.received_by))->>'name')
             || public.audit_kv('Received on', public.audit_ts(NEW.received_at))
             || public.audit_kv('Time in transit', v_transit)
             || public.audit_kv('Credited to batch', v_dst->>'batch_number')
             || public.audit_kv('Destination batch holds now',
                  public.audit_qty((v_dst->>'remaining')::numeric, v_unit));
      v_sections := public.audit_section('Movement', v_rows);

    -- Cancellation.
    ELSIF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
      v_cancelled := COALESCE(NEW.cancelled_at, NEW.updated_at, now());
      v_actor     := COALESCE(NEW.cancelled_by, NEW.received_by, NEW.issued_by);
      v_action    := 'cancel_inventory_transfer';
      v_summary := format('Cancelled transfer #%s; %s of %s returned to %s',
                          NEW.transfer_id, public.audit_qty(NEW.quantity_issued, v_unit), v_item, v_from);
      v_narrative := format(
        'A dispatch was CANCELLED before it was received. Transfer #%s - %s of %s sent from %s to %s on %s - was cancelled by %s on %s. '
        'The units never reached %s; they are returned to batch %s at %s and are available there again. '
        'Anything counting this stock as en route should stop doing so from this point.',
        NEW.transfer_id, public.audit_qty(NEW.quantity_issued, v_unit), v_item, v_from, v_to,
        public.audit_ts(NEW.issued_at),
        COALESCE((public.audit_actor(NEW.cancelled_by))->>'name', 'an unrecorded account'),
        public.audit_ts(v_cancelled),
        v_to, COALESCE(v_src->>'batch_number', 'its source batch'), v_from
      );
      v_rows := v_rows
             || public.audit_kv('Cancelled by', (public.audit_actor(NEW.cancelled_by))->>'name')
             || public.audit_kv('Cancelled on', public.audit_ts(v_cancelled))
             || public.audit_kv('Quantity returned to source',
                  public.audit_qty(NEW.quantity_issued, v_unit));
      v_sections := public.audit_section('Movement', v_rows);

    -- Delivery plan revised, or the dispatch remarks otherwise amended, while
    -- the stock is still in transit.
    ELSIF NEW.remarks IS DISTINCT FROM OLD.remarks THEN
      v_situation := substring(COALESCE(NEW.remarks, '')
                     from 'Delivery update: ([^.]*?) on [0-9]{4}-[0-9]{2}-[0-9]{2}');
      v_note      := substring(COALESCE(NEW.remarks, '')
                     from 'Delivery update: [^.]*? on [0-9]{4}-[0-9]{2}-[0-9]{2}\. (.*)$');
      v_shelf     := substring(COALESCE(NEW.remarks, '')
                     from 'batch expires [0-9-]+; (-?[0-9]+) days? of shelf life');

      v_actor := NEW.issued_by;

      IF v_plan_new IS NOT NULL THEN
        v_action  := 'update_inventory_transfer_delivery';
        v_summary := format('Delivery plan for transfer #%s revised to %s%s',
                            NEW.transfer_id,
                            COALESCE(public.audit_date(v_plan_new::date), 'no date'),
                            COALESCE(' (' || v_situation || ')', ''));
        v_narrative := format(
          'The delivery plan changed while the stock was still in transit. Transfer #%s carries %s of %s from %s to %s. '
          'The expected arrival moved from %s to %s. Reported situation: %s. Note: "%s". %s'
          'The quantity, the batch, the destination and the receipt status are untouched by a re-plan - only the '
          'expectation of when it lands.',
          NEW.transfer_id, public.audit_qty(NEW.quantity_issued, v_unit), v_item, v_from, v_to,
          COALESCE(public.audit_date(v_plan_old::date), 'not previously recorded'),
          COALESCE(public.audit_date(v_plan_new::date), 'not set'),
          COALESCE(v_situation, 'not stated'),
          COALESCE(v_note, 'none recorded'),
          CASE WHEN v_shelf IS NOT NULL
               THEN format('At that arrival date the batch would still hold %s of shelf life%s. ',
                           public.audit_qty(v_shelf::numeric, 'day'),
                           CASE WHEN v_shelf::numeric <= 0
                                THEN ', meaning it would arrive already expired' ELSE '' END)
               ELSE '' END
        );
        v_rows := v_rows
               || public.audit_kv('Expected arrival before', public.audit_date(v_plan_old::date))
               || public.audit_kv('Expected arrival after',  public.audit_date(v_plan_new::date))
               || public.audit_kv('Delivery situation', v_situation)
               || public.audit_kv('Delivery note', v_note)
               || public.audit_kv('Shelf life left on arrival',
                    CASE WHEN v_shelf IS NOT NULL
                         THEN public.audit_qty(v_shelf::numeric, 'day') END);
      ELSE
        -- A remarks edit with no delivery plan in it. Still a change to the
        -- dispatch record, so it is still audited, just described honestly.
        v_action  := 'update_inventory_transfer_remarks';
        v_summary := format('Remarks on transfer #%s were amended', NEW.transfer_id);
        v_narrative := format(
          'The remarks on transfer #%s were amended while %s of %s was in transit from %s to %s. '
          'Remarks before: "%s". Remarks after: "%s". No quantity, batch, destination or receipt status changed.',
          NEW.transfer_id, public.audit_qty(NEW.quantity_issued, v_unit), v_item, v_from, v_to,
          COALESCE(OLD.remarks, 'none'), COALESCE(NEW.remarks, 'none'));
        v_rows := v_rows
               || public.audit_kv('Remarks before', OLD.remarks)
               || public.audit_kv('Remarks after',  NEW.remarks);
      END IF;

      v_sections := public.audit_section('Movement', v_rows);
    ELSE
      RETURN NULL;
    END IF;
  END IF;

  PERFORM public.audit_write(
    v_actor, v_action, 'inventory_transfers', NEW.transfer_id::text, v_entity,
    v_summary, v_narrative, v_sections,
    jsonb_build_object(
      'transfer_id', NEW.transfer_id, 'request_id', NEW.request_id,
      'source_batch_id', NEW.source_batch_id, 'destination_batch_id', NEW.destination_batch_id,
      'item_id', v_src->>'item_id',
      'source_facility_id', v_src->>'facility_id',
      'destination_facility_id', NEW.destination_facility_id,
      'issued_by', NEW.issued_by, 'received_by', NEW.received_by),
    CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END,
    to_jsonb(NEW), NULL, NEW.status
  );

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_audit_inventory_transfer ON public.inventory_transfers;
CREATE TRIGGER trg_audit_inventory_transfer
  AFTER INSERT OR UPDATE ON public.inventory_transfers
  FOR EACH ROW EXECUTE FUNCTION public.audit_inventory_transfer();

-- 20260824 attached an audit write to the notification trigger, as the least
-- invasive repair available at the time. This file supersedes it with a far
-- more complete record on the same event, so the notification trigger goes back
-- to doing only what its name says. Rewritten rather than dropped: it is still
-- the only thing that tells the destination facility stock is coming.
CREATE OR REPLACE FUNCTION public.announce_inventory_transfer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_item_name   TEXT;
  v_source_name TEXT;
  v_recipients  INTEGER := 0;
BEGIN
  SELECT i.name
    INTO v_item_name
    FROM public.inventory_batches b
    JOIN public.inventory_items i ON i.item_id = b.item_id
   WHERE b.batch_id = NEW.source_batch_id;

  SELECT hf.name
    INTO v_source_name
    FROM public.inventory_batches b
    LEFT JOIN public.health_facilities hf ON hf.facility_id = b.facility_id
   WHERE b.batch_id = NEW.source_batch_id;

  v_source_name := COALESCE(v_source_name, 'the municipal warehouse');
  v_item_name   := COALESCE(v_item_name, 'stock');

  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT m.account_id,
         'Incoming stocks',
         format('%s units of %s from %s are waiting for your receipt confirmation.',
                NEW.quantity_issued, v_item_name, v_source_name),
         'inventory'
    FROM public.midwives m
    JOIN public.accounts a ON a.account_id = m.account_id
   WHERE m.assigned_bhc_id = NEW.destination_facility_id
     AND a.status = 'active';

  GET DIAGNOSTICS v_recipients = ROW_COUNT;

  IF v_recipients = 0 THEN
    INSERT INTO public.notifications (account_id, title, message, type)
    SELECT DISTINCT a.account_id,
           'Incoming stocks',
           format('%s units of %s from %s are waiting for your receipt confirmation.',
                  NEW.quantity_issued, v_item_name, v_source_name),
           'inventory'
      FROM public.facility_assignments fa
      JOIN public.accounts a ON a.account_id = fa.account_id
     WHERE fa.facility_id = NEW.destination_facility_id
       AND COALESCE(fa.is_active, true)
       AND a.status = 'active'
       AND a.account_type IN ('admin', 'mho');
  END IF;

  -- The audit row for this event is written by trg_audit_inventory_transfer.
  RETURN NULL;
END
$fn$;


-- 5c. The movement ledger ---------------------------------------------------
--
-- inventory_transactions is the one table every stock path writes to, whichever
-- screen or RPC drove it. Auditing here is what makes coverage independent of
-- the caller: a movement that reaches the ledger reaches the audit trail, and a
-- movement that does not reach the ledger was already a bug.
CREATE OR REPLACE FUNCTION public.audit_inventory_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_ctx       JSONB := public.audit_batch_context(NEW.batch_id);
  v_unit      TEXT;
  v_item      TEXT;
  v_where     TEXT;
  v_dir       TEXT;
  v_kind      TEXT;
  v_action    TEXT;
  v_summary   TEXT;
  v_narrative TEXT;
  v_rows      JSONB;
  v_counter   TEXT;
  v_transfer  public.inventory_transfers%ROWTYPE;
  v_ref       TEXT := COALESCE(NEW.reference_type, '');
  -- dose_quantity, notes and resulting_quantity_remaining arrive with 20260811
  -- / 20260822. Read through jsonb so this trigger also works on a database
  -- that has not applied them yet.
  v_json      JSONB := to_jsonb(NEW);
  v_doses     NUMERIC;
  v_balance   NUMERIC;
  v_note      TEXT;
  v_when      TIMESTAMPTZ;
BEGIN
  v_doses   := COALESCE(public.audit_bigint(v_json->>'dose_quantity'), NEW.quantity);
  v_balance := public.audit_bigint(v_json->>'resulting_quantity_remaining');
  v_note    := nullif(btrim(COALESCE(v_json->>'notes', '')), '');
  v_when    := COALESCE(public.audit_utc(NEW.logged_at), now());

  v_unit  := COALESCE(v_ctx->>'unit', 'unit');
  v_item  := COALESCE(v_ctx->>'item_name', 'Stock item');
  v_where := COALESCE(public.audit_facility_label(NEW.facility_id), v_ctx->>'facility_label');
  v_dir   := CASE WHEN COALESCE(NEW.quantity, 0) < 0 THEN 'out'
                  WHEN COALESCE(NEW.quantity, 0) > 0 THEN 'in'
                  ELSE 'internal' END;

  -- Name the movement the way a storekeeper would.
  v_kind := CASE
    WHEN v_ref IN ('Open Vial Discard', 'Open Vial Expiry', 'open_vial_expired')
      THEN 'Open-vial discard'
    WHEN v_ref = 'Child Immunization'         THEN 'Dose given to a child'
    WHEN v_ref = 'Maternal Td Immunization'   THEN 'Td dose given to a mother'
    WHEN v_ref ILIKE 'Prenatal%'              THEN 'Dispensed at a prenatal encounter'
    WHEN NEW.transaction_type = 'transfer' AND v_dir = 'out' THEN 'Dispatched to another facility'
    WHEN NEW.transaction_type = 'transfer' AND v_dir = 'in'  THEN 'Received from another facility'
    WHEN NEW.transaction_type = 'receipt'         THEN 'Stock received into the facility'
    WHEN NEW.transaction_type = 'expiry_disposal' THEN 'Disposed of'
    WHEN NEW.transaction_type = 'dispense'        THEN 'Dispensed'
    WHEN NEW.transaction_type = 'adjustment'      THEN 'Stock adjustment'
    ELSE initcap(replace(COALESCE(NEW.transaction_type, 'movement'), '_', ' '))
  END;

  v_action := 'inventory_movement_' || COALESCE(NEW.transaction_type, 'other');

  -- The other end of the movement, when there is one.
  IF NEW.transaction_type = 'transfer' AND NEW.reference_id IS NOT NULL THEN
    SELECT * INTO v_transfer FROM public.inventory_transfers
     WHERE transfer_id = NEW.reference_id;
    IF FOUND THEN
      v_counter := CASE WHEN v_dir = 'out'
                        THEN public.audit_facility_label(v_transfer.destination_facility_id)
                        ELSE COALESCE(
                               (public.audit_batch_context(v_transfer.source_batch_id))->>'facility_label',
                               'another facility')
                   END;
    END IF;
  END IF;

  v_summary := format('%s: %s of %s at %s',
                      v_kind, public.audit_qty(NEW.quantity, v_unit), v_item, v_where);

  v_narrative := format(
    'A stock movement was posted to the ledger. %s. Item: %s, from batch %s%s. '
    'Quantity moved: %s (%s), which is %s in clinical terms. The movement was recorded %s %s. '
    '%s%sThe batch holds %s after this movement. Recorded by %s on %s.%s',
    v_kind,
    v_item,
    COALESCE(v_ctx->>'batch_number', 'unrecorded'),
    COALESCE(', expiring ' || public.audit_date((v_ctx->>'expiration_date')::date), ''),
    public.audit_qty(NEW.quantity, v_unit),
    CASE v_dir WHEN 'out' THEN 'leaving stock'
               WHEN 'in'  THEN 'entering stock'
               ELSE 'no whole unit moved - drawn from a vial already open' END,
    public.audit_qty(v_doses, 'dose'),
    CASE v_dir WHEN 'in' THEN 'into' ELSE 'at' END,
    v_where,
    CASE WHEN v_counter IS NOT NULL
         THEN format('The other end of this movement is %s. ', v_counter) ELSE '' END,
    CASE WHEN nullif(v_ref, '') IS NOT NULL
         THEN format('Reference recorded against it: "%s". ', v_ref) ELSE '' END,
    COALESCE(public.audit_qty(COALESCE(v_balance, (v_ctx->>'remaining')::numeric), v_unit),
             'an unrecorded balance'),
    COALESCE((public.audit_actor(NEW.performed_by))->>'name', 'System'),
    public.audit_ts(v_when),
    COALESCE(' Note: ' || v_note || '.', '')
  );

  v_rows := public.audit_kv('Movement', v_kind)
         || public.audit_kv('Ledger entry', '#' || NEW.transaction_id)
         || public.audit_kv('Item', v_item)
         || public.audit_kv('Item type', initcap(replace(COALESCE(v_ctx->>'item_type', ''), '_', ' ')))
         || public.audit_kv('Batch', v_ctx->>'batch_number')
         || public.audit_kv('Batch expiry', public.audit_date((v_ctx->>'expiration_date')::date))
         || public.audit_kv('Manufacturer', v_ctx->>'manufacturer')
         || public.audit_kv('Location', v_where)
         || public.audit_kv('Direction',
              CASE v_dir WHEN 'out' THEN 'Stock left this facility'
                         WHEN 'in'  THEN 'Stock entered this facility'
                         ELSE 'Drawn from an already-open vial - no whole unit moved' END)
         || public.audit_kv('Other end of the movement', v_counter)
         || public.audit_kv('Quantity in units', public.audit_qty(NEW.quantity, v_unit))
         || public.audit_kv('Quantity in doses', public.audit_qty(v_doses, 'dose'))
         || public.audit_kv('Balance in batch after',
              public.audit_qty(COALESCE(v_balance, (v_ctx->>'remaining')::numeric), v_unit))
         || public.audit_kv('Reference', nullif(v_ref, ''))
         || public.audit_kv('Linked record id', NEW.reference_id::text)
         || public.audit_kv('Note', v_note)
         || public.audit_kv('Recorded by', (public.audit_actor(NEW.performed_by))->>'name')
         || public.audit_kv('Recorded on', public.audit_ts(v_when));

  PERFORM public.audit_write(
    NEW.performed_by, v_action, 'inventory_transactions', NEW.transaction_id::text,
    public.audit_batch_label(v_ctx), v_summary, v_narrative,
    public.audit_section('Stock movement', v_rows),
    jsonb_build_object(
      'transaction_id', NEW.transaction_id, 'batch_id', NEW.batch_id,
      'item_id', v_ctx->>'item_id', 'facility_id', NEW.facility_id,
      'reference_type', nullif(v_ref, ''), 'reference_id', NEW.reference_id,
      'transfer_id', CASE WHEN NEW.transaction_type = 'transfer' THEN NEW.reference_id END),
    NULL, to_jsonb(NEW),
    CASE
      WHEN NEW.transaction_type = 'expiry_disposal' THEN 'warning'
      WHEN v_ref IN ('Open Vial Discard', 'Open Vial Expiry', 'open_vial_expired') THEN 'warning'
      WHEN NEW.transaction_type = 'adjustment' THEN 'warning'
      WHEN NEW.transaction_type = 'transfer' THEN 'notice'
      ELSE 'info'
    END,
    'movement'
  );

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_audit_inventory_transaction ON public.inventory_transactions;
CREATE TRIGGER trg_audit_inventory_transaction
  AFTER INSERT ON public.inventory_transactions
  FOR EACH ROW EXECUTE FUNCTION public.audit_inventory_transaction();


-- 5d. Batches ---------------------------------------------------------------
--
-- The ledger says stock moved; this says the batch itself changed. Both matter:
-- a batch can expire, be discarded or have a vial opened without any ledger row
-- describing a transfer, and until now none of that was recorded anywhere a
-- reviewer would look.
CREATE OR REPLACE FUNCTION public.audit_inventory_batch()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_ctx       JSONB;
  v_unit      TEXT;
  v_item      TEXT;
  v_where     TEXT;
  v_action    TEXT;
  v_summary   TEXT;
  v_narrative TEXT;
  v_rows      JSONB;
  v_delta     INTEGER;
  v_actor     BIGINT;
  -- Open-vial tracking arrived with 20260819/20260822. Read through jsonb so a
  -- database without those columns audits the rest of the batch normally.
  v_vials_old INTEGER;
  v_vials_new INTEGER;
  v_doses_old INTEGER;
  v_doses_new INTEGER;
BEGIN
  v_ctx   := public.audit_batch_context(NEW.batch_id);
  v_unit  := COALESCE(v_ctx->>'unit', 'unit');
  v_item  := COALESCE(v_ctx->>'item_name', 'Stock item');
  v_where := public.audit_facility_label(NEW.facility_id);

  v_vials_new := COALESCE(public.audit_bigint(to_jsonb(NEW)->>'open_vials_count'), 0);
  v_doses_new := COALESCE(public.audit_bigint(to_jsonb(NEW)->>'doses_remaining_in_open_vial'), 0);
  IF TG_OP = 'UPDATE' THEN
    v_vials_old := COALESCE(public.audit_bigint(to_jsonb(OLD)->>'open_vials_count'), 0);
    v_doses_old := COALESCE(public.audit_bigint(to_jsonb(OLD)->>'doses_remaining_in_open_vial'), 0);
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_actor   := NEW.created_by;
    v_action  := 'create_inventory_batch';
    v_summary := format('New batch %s of %s (%s) booked in at %s',
                        NEW.batch_number, v_item,
                        public.audit_qty(NEW.quantity_received, v_unit), v_where);
    v_narrative := format(
      'A new batch entered the system. Batch %s of %s was booked in at %s by %s, with %s received and %s currently on hand. '
      'It was received on %s and expires on %s%s. Each unit carries %s. From this point every dispatch, dispense and '
      'discard against this batch is traceable to this record.',
      NEW.batch_number, v_item, v_where,
      COALESCE((public.audit_actor(NEW.created_by))->>'name', 'an unrecorded account'),
      public.audit_qty(NEW.quantity_received, v_unit),
      public.audit_qty(NEW.quantity_remaining, v_unit),
      public.audit_date(NEW.received_date), public.audit_date(NEW.expiration_date),
      COALESCE(', supplied by ' || NEW.manufacturer, ''),
      public.audit_qty(GREATEST(1, COALESCE((v_ctx->>'doses_per_unit')::int, 1)), 'dose')
    );
    v_rows := public.audit_kv('Batch number', NEW.batch_number)
           || public.audit_kv('Item', v_item)
           || public.audit_kv('Held at', v_where)
           || public.audit_kv('Booked in by', (public.audit_actor(NEW.created_by))->>'name')
           || public.audit_kv('Quantity received', public.audit_qty(NEW.quantity_received, v_unit))
           || public.audit_kv('Quantity on hand', public.audit_qty(NEW.quantity_remaining, v_unit))
           || public.audit_kv('Doses per unit', (v_ctx->>'doses_per_unit'))
           || public.audit_kv('Received on', public.audit_date(NEW.received_date))
           || public.audit_kv('Expires on', public.audit_date(NEW.expiration_date))
           || public.audit_kv('Manufacturer', NEW.manufacturer)
           || public.audit_kv('Status', NEW.status);

  ELSE
    v_delta := COALESCE(NEW.quantity_remaining, 0) - COALESCE(OLD.quantity_remaining, 0);

    -- Nothing a reader would call an event.
    IF v_delta = 0
       AND NEW.status IS NOT DISTINCT FROM OLD.status
       AND v_doses_new = v_doses_old
       AND v_vials_new = v_vials_old
       AND NEW.facility_id IS NOT DISTINCT FROM OLD.facility_id THEN
      RETURN NULL;
    END IF;

    v_action := CASE
      WHEN NEW.status = 'discarded' AND OLD.status <> 'discarded' THEN 'discard_inventory_batch'
      WHEN NEW.status = 'expired'   AND OLD.status <> 'expired'   THEN 'expire_inventory_batch'
      WHEN NEW.facility_id IS DISTINCT FROM OLD.facility_id       THEN 'relocate_inventory_batch'
      WHEN v_delta < 0                                            THEN 'inventory_batch_decrease'
      WHEN v_delta > 0                                            THEN 'inventory_batch_increase'
      ELSE 'update_inventory_batch'
    END;

    v_summary := CASE
      WHEN NEW.status = 'discarded' AND OLD.status <> 'discarded'
        THEN format('Batch %s of %s was discarded at %s', NEW.batch_number, v_item, v_where)
      WHEN NEW.status = 'expired' AND OLD.status <> 'expired'
        THEN format('Batch %s of %s marked expired at %s', NEW.batch_number, v_item, v_where)
      WHEN NEW.facility_id IS DISTINCT FROM OLD.facility_id
        THEN format('Batch %s of %s moved from %s to %s', NEW.batch_number, v_item,
                    public.audit_facility_label(OLD.facility_id), v_where)
      ELSE format('Batch %s of %s changed by %s%s at %s', NEW.batch_number, v_item,
                  CASE WHEN v_delta > 0 THEN '+' ELSE '-' END,
                  public.audit_qty(v_delta, v_unit), v_where)
    END;

    v_narrative := format(
      'Batch %s of %s at %s changed. On-hand quantity went from %s to %s, a change of %s%s. Status went from "%s" to "%s". '
      '%s%sThe batch expires on %s%s. Every movement that produced this change is recorded separately in the stock '
      'movement ledger and can be matched to this batch by its number.',
      NEW.batch_number, v_item, v_where,
      public.audit_qty(OLD.quantity_remaining, v_unit),
      public.audit_qty(NEW.quantity_remaining, v_unit),
      CASE WHEN v_delta > 0 THEN '+' WHEN v_delta < 0 THEN '-' ELSE '' END,
      public.audit_qty(v_delta, v_unit),
      OLD.status, NEW.status,
      CASE WHEN NEW.facility_id IS DISTINCT FROM OLD.facility_id
           THEN format('The batch was relocated from %s to %s. ',
                       public.audit_facility_label(OLD.facility_id), v_where)
           ELSE '' END,
      CASE WHEN v_vials_new <> v_vials_old OR v_doses_new <> v_doses_old
           THEN format('Open-vial tracking moved from %s open vial(s) holding %s to %s open vial(s) holding %s. ',
                       v_vials_old, public.audit_qty(v_doses_old, 'dose'),
                       v_vials_new, public.audit_qty(v_doses_new, 'dose'))
           ELSE '' END,
      public.audit_date(NEW.expiration_date),
      COALESCE(', supplied by ' || NEW.manufacturer, '')
    );

    v_rows := public.audit_kv('Batch number', NEW.batch_number)
           || public.audit_kv('Item', v_item)
           || public.audit_kv('Held at', v_where)
           || public.audit_kv('Previously held at',
                CASE WHEN NEW.facility_id IS DISTINCT FROM OLD.facility_id
                     THEN public.audit_facility_label(OLD.facility_id) END)
           || public.audit_kv('On hand before', public.audit_qty(OLD.quantity_remaining, v_unit))
           || public.audit_kv('On hand after', public.audit_qty(NEW.quantity_remaining, v_unit))
           || public.audit_kv('Net change',
                CASE WHEN v_delta <> 0 THEN
                  (CASE WHEN v_delta > 0 THEN '+' ELSE '-' END) || public.audit_qty(v_delta, v_unit) END)
           || public.audit_kv('Status before', OLD.status)
           || public.audit_kv('Status after', NEW.status)
           || public.audit_kv('Open vials before', NULLIF(v_vials_old, 0)::text)
           || public.audit_kv('Open vials after',  NULLIF(v_vials_new, 0)::text)
           || public.audit_kv('Doses left in open vial', NULLIF(v_doses_new, 0)::text)
           || public.audit_kv('Expires on', public.audit_date(NEW.expiration_date))
           || public.audit_kv('Manufacturer', NEW.manufacturer);
  END IF;

  PERFORM public.audit_write(
    v_actor, v_action, 'inventory_batches', NEW.batch_id::text,
    public.audit_batch_label(v_ctx), v_summary, v_narrative,
    public.audit_section('Batch', v_rows),
    jsonb_build_object('batch_id', NEW.batch_id, 'item_id', NEW.item_id,
                       'facility_id', NEW.facility_id),
    CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END,
    to_jsonb(NEW), NULL, NEW.status
  );

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_audit_inventory_batch ON public.inventory_batches;
CREATE TRIGGER trg_audit_inventory_batch
  AFTER INSERT OR UPDATE ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION public.audit_inventory_batch();


-- 5e. Disposals -------------------------------------------------------------
--
-- The disposal certificate is a document the RHU has to be able to produce on
-- demand. Its audit row now carries every fact printed on the certificate, so
-- the trail and the certificate cannot drift apart.
-- The function is created unconditionally: a trigger function's body is not
-- checked against the tables it names until it runs, so this is safe even where
-- inventory_disposals is absent. Only the CREATE TRIGGER needs the guard.
CREATE OR REPLACE FUNCTION public.audit_inventory_disposal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
  DECLARE
    v_ctx  JSONB := public.audit_batch_context(NEW.batch_id);
    v_unit TEXT;
    v_item TEXT;
    v_where TEXT;
    v_doses INTEGER;
  BEGIN
    v_unit  := COALESCE(v_ctx->>'unit', 'unit');
    v_item  := COALESCE(v_ctx->>'item_name', 'Stock item');
    v_where := public.audit_facility_label(NEW.facility_id);
    v_doses := NEW.quantity_disposed * GREATEST(1, COALESCE((v_ctx->>'doses_per_unit')::int, 1));

    PERFORM public.audit_write(
      NEW.disposed_by, 'dispose_inventory_batch', 'inventory_disposals',
      NEW.disposal_id::text, public.audit_batch_label(v_ctx),
      format('Disposed %s of %s from batch %s at %s',
             public.audit_qty(NEW.quantity_disposed, v_unit), v_item,
             COALESCE(v_ctx->>'batch_number', 'unrecorded'), v_where),
      format(
        'Stock was DESTROYED and permanently removed from the system. %s of %s from batch %s at %s was disposed of by %s on %s, '
        'witnessed by authorised officer %s. Disposal method: %s. That is %s taken out of circulation. '
        'The batch was zeroed and its status set to discarded; a matching entry sits in the movement ledger. '
        'Certificate reference %s covers this disposal and can be reprinted from these facts. %s',
        public.audit_qty(NEW.quantity_disposed, v_unit), v_item,
        COALESCE(v_ctx->>'batch_number', 'unrecorded'), v_where,
        COALESCE((public.audit_actor(NEW.disposed_by))->>'name', 'an unrecorded account'),
        public.audit_ts(NEW.disposed_at), NEW.officer_name, NEW.disposal_method,
        public.audit_qty(v_doses, 'dose'),
        COALESCE(NEW.certificate_no, 'not yet assigned'),
        COALESCE('Notes recorded at disposal: "' || NEW.notes || '".', 'No further notes were recorded.')
      ),
      public.audit_section('Disposal',
        public.audit_kv('Certificate number', NEW.certificate_no)
        || public.audit_kv('Item', v_item)
        || public.audit_kv('Batch', v_ctx->>'batch_number')
        || public.audit_kv('Batch expiry', public.audit_date((v_ctx->>'expiration_date')::date))
        || public.audit_kv('Manufacturer', v_ctx->>'manufacturer')
        || public.audit_kv('Held at', v_where)
        || public.audit_kv('Quantity destroyed', public.audit_qty(NEW.quantity_disposed, v_unit))
        || public.audit_kv('Doses destroyed', public.audit_qty(v_doses, 'dose'))
        || public.audit_kv('Disposal method', NEW.disposal_method)
        || public.audit_kv('Authorised officer', NEW.officer_name)
        || public.audit_kv('Carried out by', (public.audit_actor(NEW.disposed_by))->>'name')
        || public.audit_kv('Carried out on', public.audit_ts(NEW.disposed_at))
        || public.audit_kv('Notes', NEW.notes)),
      jsonb_build_object('disposal_id', NEW.disposal_id, 'batch_id', NEW.batch_id,
                         'item_id', v_ctx->>'item_id', 'facility_id', NEW.facility_id),
      NULL, to_jsonb(NEW), 'critical', 'disposed'
    );

    RETURN NULL;
  END
$fn$;

DO $do$
BEGIN
  IF to_regclass('public.inventory_disposals') IS NULL THEN
    RAISE NOTICE 'inventory_disposals not present; skipping its audit trigger. Run 20260806_inventory_audit_fixes.sql, then re-run this file.';
  ELSE
    EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_inventory_disposal ON public.inventory_disposals';
    EXECUTE 'CREATE TRIGGER trg_audit_inventory_disposal '
            'AFTER INSERT ON public.inventory_disposals '
            'FOR EACH ROW EXECUTE FUNCTION public.audit_inventory_disposal()';
  END IF;
END
$do$;


-- 5f. The catalogue ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_inventory_item()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_action  TEXT;
  v_summary TEXT;
  v_changes TEXT := '';
  v_rows    JSONB;
  k         TEXT;
  -- generic_name and item_code arrive with 20260806_inventory_item_details,
  -- is_archived with 20260808_inventory_item_archiving and doses_per_unit with
  -- 20260822. Read through jsonb, so a catalogue write on a database that has
  -- not applied those cannot be aborted by this trigger.
  v_new     JSONB := to_jsonb(NEW);
  v_old     JSONB;
  v_arch_new BOOLEAN;
  v_arch_old BOOLEAN;
BEGIN
  v_arch_new := COALESCE((v_new->>'is_archived')::boolean, false);

  IF TG_OP = 'INSERT' THEN
    v_action  := 'create_inventory_item';
    v_summary := format('Added "%s" to the stock catalogue', NEW.name);
  ELSE
    v_old := to_jsonb(OLD);
    IF v_old = v_new THEN
      RETURN NULL;
    END IF;

    v_arch_old := COALESCE((v_old->>'is_archived')::boolean, false);

    v_action := CASE
      WHEN v_arch_new AND NOT v_arch_old       THEN 'archive_inventory_item'
      WHEN NOT v_arch_new AND v_arch_old       THEN 'restore_inventory_item'
      ELSE 'update_inventory_item'
    END;
    v_summary := format('Catalogue entry "%s" was %s', NEW.name,
      CASE v_action
        WHEN 'archive_inventory_item' THEN 'archived'
        WHEN 'restore_inventory_item' THEN 'restored'
        ELSE 'updated' END);

    -- Spell out what actually changed, field by field.
    FOR k IN SELECT jsonb_object_keys(v_new) LOOP
      IF v_old->k IS DISTINCT FROM v_new->k THEN
        v_changes := v_changes || format('%s changed from "%s" to "%s"; ',
          replace(k, '_', ' '),
          COALESCE(v_old->>k, 'not set'),
          COALESCE(v_new->>k, 'not set'));
      END IF;
    END LOOP;
  END IF;

  v_rows := public.audit_kv('Item name', NEW.name)
         || public.audit_kv('Generic name', v_new->>'generic_name')
         || public.audit_kv('Item code', v_new->>'item_code')
         || public.audit_kv('Type', initcap(replace(COALESCE(NEW.item_type, ''), '_', ' ')))
         || public.audit_kv('Unit of measure', NEW.unit_of_measure)
         || public.audit_kv('Doses per unit', v_new->>'doses_per_unit')
         || public.audit_kv('Reorder threshold', NEW.minimum_stock_threshold::text)
         || public.audit_kv('Archived', CASE WHEN v_arch_new THEN 'Yes' ELSE 'No' END)
         || public.audit_kv('Fields changed', nullif(v_changes, ''));

  PERFORM public.audit_write(
    NULL, v_action, 'inventory_items', NEW.item_id::text, NEW.name, v_summary,
    format('The stock catalogue changed. Item "%s"%s was %s on %s. %s%s',
           NEW.name,
           COALESCE(' (' || (v_new->>'generic_name') || ')', ''),
           CASE v_action
             WHEN 'create_inventory_item'  THEN 'added to the catalogue'
             WHEN 'archive_inventory_item' THEN 'archived, so it no longer appears for new stock entry or requests'
             WHEN 'restore_inventory_item' THEN 'restored to the active catalogue'
             ELSE 'updated' END,
           public.audit_ts(now()),
           CASE WHEN v_changes <> '' THEN 'Specifically: ' || v_changes ELSE '' END,
           'Existing batches of this item keep their own history regardless of this change.'),
    public.audit_section('Catalogue entry', v_rows),
    jsonb_build_object('item_id', NEW.item_id),
    v_old, v_new, NULL, NULL
  );

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_audit_inventory_item ON public.inventory_items;
CREATE TRIGGER trg_audit_inventory_item
  AFTER INSERT OR UPDATE ON public.inventory_items
  FOR EACH ROW EXECUTE FUNCTION public.audit_inventory_item();


-- ---------------------------------------------------------------------------
-- 6. Accounts, access and facilities
--
-- The other half of "who did what". The portal wrote an audit row when an
-- administrator used the Accounts screen; nothing was written when an account
-- changed by any other route, and a password or status change - the two things
-- a reviewer most wants to see - was invisible unless a handler remembered.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_account_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_row     RECORD;
  v_json    JSONB;
  v_action  TEXT;
  v_name    TEXT;
  v_summary TEXT;
  v_narr    TEXT;
  v_rows    JSONB;
  v_changes TEXT := '';
  k         TEXT;
  v_sensitive CONSTANT TEXT[] := ARRAY[
    'password_hash', 'verification_code', 'reset_code', 'last_login_token'
  ];
BEGIN
  -- Assigned by branch rather than COALESCE(NEW, OLD): NEW is unassigned in a
  -- DELETE trigger and OLD is unassigned in an INSERT, and reading either one
  -- there is an error rather than a NULL.
  IF TG_OP = 'DELETE' THEN
    v_row := OLD;
  ELSE
    v_row := NEW;
  END IF;

  v_name := COALESCE(nullif(btrim(concat_ws(' ', v_row.first_name, v_row.last_name)), ''),
                     'Account #' || v_row.account_id);

  -- is_temporary_password and created_by are later additions
  -- (add_temporary_password_columns.sql, 20260808_created_by_allows_account_ids).
  -- Read through jsonb so signing in cannot be broken by this trigger on a
  -- database that has not applied them.
  v_json := to_jsonb(v_row);

  IF TG_OP = 'INSERT' THEN
    v_action  := 'create_account';
    v_summary := format('Created %s account for %s', NEW.account_type, v_name);
    v_narr := format(
      'A new account was created. %s was registered as a %s account with the e-mail address %s and the status "%s". '
      'The account was created on %s%s. %s',
      v_name, NEW.account_type, COALESCE(NEW.email_address, 'none on file'), NEW.status,
      public.audit_ts(COALESCE(public.audit_utc(NEW.created_at), now())),
      COALESCE(' by ' || (v_json->>'created_by'), ''),
      CASE WHEN COALESCE((v_json->>'is_temporary_password')::boolean, false)
           THEN 'It was issued a temporary password that must be changed at first sign-in.'
           ELSE 'The account set its own password.' END);

  ELSIF TG_OP = 'DELETE' THEN
    v_action  := 'delete_account';
    v_summary := format('Deleted the %s account of %s', OLD.account_type, v_name);
    v_narr := format(
      'An account was PERMANENTLY DELETED. %s held a %s account (%s) with the status "%s", created %s. '
      'The account row no longer exists. Audit rows this account produced keep the name recorded here, because '
      'the actor name is snapshotted at the time of each action rather than joined at read time.',
      v_name, OLD.account_type, COALESCE(OLD.email_address, 'no e-mail on file'), OLD.status,
      public.audit_ts(public.audit_utc(OLD.created_at)));

  ELSE
    IF to_jsonb(OLD) = to_jsonb(NEW) THEN
      RETURN NULL;
    END IF;

    v_action := CASE
      WHEN OLD.password_hash IS DISTINCT FROM NEW.password_hash        THEN 'change_password'
      WHEN OLD.status IS DISTINCT FROM NEW.status
           AND NEW.status = 'suspended'                                THEN 'suspend_account'
      WHEN OLD.status IS DISTINCT FROM NEW.status                      THEN 'change_account_status'
      WHEN OLD.account_type IS DISTINCT FROM NEW.account_type          THEN 'change_account_role'
      WHEN OLD.last_login_at IS DISTINCT FROM NEW.last_login_at
           AND to_jsonb(OLD) - 'last_login_at' - 'last_login_token' - 'updated_at'
             = to_jsonb(NEW) - 'last_login_at' - 'last_login_token' - 'updated_at'
                                                                        THEN 'login'
      ELSE 'update_account'
    END;

    -- A login is already written by the portal with the detail it has; a second
    -- row from here would just be noise.
    IF v_action = 'login' THEN
      RETURN NULL;
    END IF;

    FOR k IN SELECT jsonb_object_keys(to_jsonb(NEW)) LOOP
      IF to_jsonb(OLD)->k IS DISTINCT FROM to_jsonb(NEW)->k THEN
        IF k = ANY (v_sensitive) THEN
          v_changes := v_changes || format('%s was changed (value not recorded); ', replace(k, '_', ' '));
        ELSE
          v_changes := v_changes || format('%s changed from "%s" to "%s"; ',
            replace(k, '_', ' '),
            COALESCE(to_jsonb(OLD)->>k, 'not set'),
            COALESCE(to_jsonb(NEW)->>k, 'not set'));
        END IF;
      END IF;
    END LOOP;

    v_summary := format('%s account of %s was updated',
                        initcap(replace(v_action, '_', ' ')), v_name);
    v_narr := format(
      'An account record changed. %s holds a %s account (%s) whose status is now "%s". %s%s',
      v_name, NEW.account_type, COALESCE(NEW.email_address, 'no e-mail on file'), NEW.status,
      CASE WHEN v_changes <> '' THEN 'What changed: ' || v_changes ELSE 'No visible field changed. ' END,
      CASE WHEN v_action = 'change_password'
           THEN 'The password itself is never recorded in the audit trail - only the fact that it changed, and when.'
           WHEN v_action = 'suspend_account'
           THEN 'A suspended account cannot sign in until an administrator reactivates it.'
           ELSE '' END);
  END IF;

  v_rows := public.audit_kv('Account holder', v_name)
         || public.audit_kv('Account number', '#' || v_row.account_id)
         || public.audit_kv('Role', v_row.account_type)
         || public.audit_kv('E-mail', v_row.email_address)
         || public.audit_kv('Contact number', v_row.phone_number)
         || public.audit_kv('Status', v_row.status)
         || public.audit_kv('Verified', CASE WHEN v_row.is_verified THEN 'Yes' ELSE 'No' END)
         || public.audit_kv('Temporary password in force',
              CASE WHEN COALESCE((v_json->>'is_temporary_password')::boolean, false) THEN 'Yes' ELSE 'No' END)
         || public.audit_kv('Account created', public.audit_ts(public.audit_utc(v_row.created_at)))
         || public.audit_kv('Fields changed', nullif(v_changes, ''));

  PERFORM public.audit_write(
    NULL, v_action, 'accounts', v_row.account_id::text, v_name, v_summary, v_narr,
    public.audit_section('Account', v_rows),
    jsonb_build_object('account_id', v_row.account_id, 'account_type', v_row.account_type),
    CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
    NULL, lower(TG_OP)
  );

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_audit_account_change ON public.accounts;
CREATE TRIGGER trg_audit_account_change
  AFTER INSERT OR UPDATE OR DELETE ON public.accounts
  FOR EACH ROW EXECUTE FUNCTION public.audit_account_change();


CREATE OR REPLACE FUNCTION public.audit_facility_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_row     RECORD;
  v_who     JSONB;
  v_action  TEXT;
  v_to      TEXT;
  v_from    TEXT;
  v_verb    TEXT;
  -- facility_assignments carries mothers as well as staff: patient_number is
  -- only ever set for a mother. A patient being enrolled at a health centre and
  -- a midwife being posted to one are different events and read differently.
  v_patient BOOLEAN;
  v_noun    TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_row := OLD;
  ELSE
    v_row := NEW;
  END IF;

  v_who     := public.audit_actor(v_row.account_id);
  v_to      := public.audit_facility_label(v_row.facility_id);
  v_patient := (v_who->>'role') = 'mother';
  v_noun    := CASE WHEN v_patient THEN 'patient enrolment' ELSE 'staff posting' END;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.facility_id IS NOT DISTINCT FROM NEW.facility_id
       AND COALESCE(OLD.is_active, true) IS NOT DISTINCT FROM COALESCE(NEW.is_active, true) THEN
      RETURN NULL;
    END IF;
    v_from := public.audit_facility_label(OLD.facility_id);
  END IF;

  v_action := CASE
    WHEN TG_OP = 'DELETE' THEN 'remove_facility_assignment'
    WHEN TG_OP = 'UPDATE' AND NOT COALESCE(NEW.is_active, true) THEN 'end_facility_assignment'
    WHEN TG_OP = 'UPDATE' THEN 'reassign_facility'
    ELSE 'assign_facility'
  END;

  v_verb := CASE v_action
              WHEN 'assign_facility'         THEN CASE WHEN v_patient THEN 'enrolled at' ELSE 'assigned to' END
              WHEN 'reassign_facility'       THEN CASE WHEN v_patient THEN 'transferred to' ELSE 'reassigned to' END
              WHEN 'end_facility_assignment' THEN CASE WHEN v_patient THEN 'discharged from' ELSE 'stood down from' END
              ELSE 'unassigned from'
            END;

  PERFORM public.audit_write(
    NULL, v_action, 'facility_assignments', v_row.facility_assignment_id::text,
    format('%s at %s', v_who->>'name', v_to),
    format('%s was %s %s', v_who->>'name', v_verb, v_to),
    format(
      'A %s changed. %s, a %s account, was %s %s%s on %s. %s',
      v_noun, v_who->>'name', v_who->>'role', v_verb, v_to,
      COALESCE(', having previously been at ' || v_from, ''),
      public.audit_ts(now()),
      CASE WHEN v_patient
           THEN 'The enrolling facility is the one whose midwives hold this mother''s records and whose stock is drawn on for her care.'
           ELSE 'Facility postings determine which patients, which stock and which requests this account can see and act on, '
                'so this change alters the scope of everything the account does from here.' END),
    public.audit_section(CASE WHEN v_patient THEN 'Enrolment' ELSE 'Posting' END,
      public.audit_kv(CASE WHEN v_patient THEN 'Patient' ELSE 'Staff member' END, v_who->>'name')
      || public.audit_kv('Role', v_who->>'role')
      || public.audit_kv('Facility', v_to)
      || public.audit_kv('Previous facility', v_from)
      || public.audit_kv('Patient number at this facility', v_row.patient_number::text)
      || public.audit_kv('Assignment active',
           CASE WHEN COALESCE(v_row.is_active, true) THEN 'Yes' ELSE 'No' END)),
    jsonb_build_object('account_id', v_row.account_id, 'facility_id', v_row.facility_id),
    CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
    NULL, lower(TG_OP)
  );

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_audit_facility_assignment ON public.facility_assignments;
CREATE TRIGGER trg_audit_facility_assignment
  AFTER INSERT OR UPDATE OR DELETE ON public.facility_assignments
  FOR EACH ROW EXECUTE FUNCTION public.audit_facility_assignment();


-- ---------------------------------------------------------------------------
-- 7. Clinical records
--
-- One generic trigger, attached to each clinical table by name. These rows do
-- NOT copy clinical values into the narrative: the audit trail is read by
-- administrators who may have no business seeing a patient's readings. It
-- records that a record was created or amended, by whom, when, and which
-- fields moved - which is what an audit trail is for - and leaves the values
-- themselves in old_data/new_data where the existing access rules apply.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_clinical_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_row     RECORD;
  v_pk      TEXT := TG_ARGV[0];
  v_label   TEXT := TG_ARGV[1];
  v_actor   BIGINT;
  v_action  TEXT;
  v_id      TEXT;
  v_fields  TEXT := '';
  v_count   INTEGER := 0;
  k         TEXT;
  v_json    JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_row := OLD;
  ELSE
    v_row := NEW;
  END IF;

  v_json := to_jsonb(v_row);
  v_id   := v_json->>v_pk;

  IF TG_OP = 'UPDATE' AND to_jsonb(OLD) = to_jsonb(NEW) THEN
    RETURN NULL;
  END IF;

  -- Whichever of these the table happens to carry. audit_bigint rather than a
  -- cast: created_by is a VARCHAR that can hold 'self', and a failed cast here
  -- would abort the caller's write.
  v_actor := COALESCE(
    public.audit_bigint(v_json->>'recorded_by'),
    public.audit_bigint(v_json->>'administered_by'),
    public.audit_bigint(v_json->>'created_by'),
    public.audit_bigint(v_json->>'midwife_id'),
    public.audit_bigint(v_json->>'performed_by')
  );

  v_action := CASE TG_OP
                WHEN 'INSERT' THEN 'create_' || v_label
                WHEN 'DELETE' THEN 'delete_' || v_label
                ELSE 'update_' || v_label
              END;

  IF TG_OP = 'UPDATE' THEN
    FOR k IN SELECT jsonb_object_keys(to_jsonb(NEW)) LOOP
      IF to_jsonb(OLD)->k IS DISTINCT FROM to_jsonb(NEW)->k THEN
        v_count  := v_count + 1;
        v_fields := v_fields || replace(k, '_', ' ') || ', ';
      END IF;
    END LOOP;
    v_fields := rtrim(v_fields, ', ');
  END IF;

  PERFORM public.audit_write(
    v_actor, v_action, TG_TABLE_NAME, v_id,
    format('%s #%s', initcap(replace(v_label, '_', ' ')), v_id),
    format('%s %s #%s',
           initcap(replace(v_label, '_', ' ')),
           CASE TG_OP WHEN 'INSERT' THEN 'recorded' WHEN 'DELETE' THEN 'deleted' ELSE 'amended' END,
           v_id),
    format(
      'A %s record was %s. The record is #%s in %s. %s%s The clinical values themselves are held in the '
      'before and after snapshots on this entry and are shown only to accounts cleared to read patient data.',
      replace(v_label, '_', ' '),
      CASE TG_OP WHEN 'INSERT' THEN 'created' WHEN 'DELETE' THEN 'deleted' ELSE 'amended' END,
      v_id, TG_TABLE_NAME,
      format('Recorded by %s on %s.',
             COALESCE((public.audit_actor(v_actor))->>'name', 'an unrecorded account'),
             public.audit_ts(now())),
      CASE WHEN TG_OP = 'UPDATE'
           THEN format(' %s field(s) changed: %s.', v_count, v_fields)
           ELSE '' END),
    public.audit_section('Record',
      public.audit_kv('Record type', initcap(replace(v_label, '_', ' ')))
      || public.audit_kv('Record number', '#' || v_id)
      || public.audit_kv('Table', TG_TABLE_NAME)
      || public.audit_kv('Recorded by', (public.audit_actor(v_actor))->>'name')
      || public.audit_kv('Fields changed', nullif(v_fields, ''))),
    jsonb_build_object('record_id', v_id, 'table', TG_TABLE_NAME,
                       'mother_id', v_json->>'mother_id',
                       'child_id', v_json->>'child_id',
                       'pregnancy_id', v_json->>'pregnancy_id'),
    CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
    NULL, lower(TG_OP)
  );

  RETURN NULL;
END
$fn$;

-- Attached by name so a database missing any one of these tables still applies
-- the rest, which is the pattern 20260804 already uses for the live feed.
DO $do$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('immunization_records', 'immunization_record_id', 'immunization'),
      ('prenatal_checkups',    'prenatal_checkup_id',    'prenatal_checkup'),
      ('pregnancies',          'pregnancy_id',           'pregnancy'),
      ('mothers',              'mother_id',              'mother_record'),
      ('children',             'child_id',               'child_record'),
      ('lab_tests',            'lab_test_id',            'lab_test'),
      ('ultrasounds',          'ultrasound_id',          'ultrasound'),
      ('deliveries',           'delivery_id',            'delivery'),
      ('child_growth_records', 'child_details_id',       'growth_record')
    ) AS t(tbl, pk, label)
  LOOP
    IF to_regclass(format('public.%I', r.tbl)) IS NULL THEN
      CONTINUE;
    END IF;

    -- Skip a table whose primary key column is named differently here than the
    -- list assumes, rather than attaching a trigger that would log NULL ids.
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = r.tbl AND column_name = r.pk
    ) THEN
      RAISE NOTICE 'Skipping audit trigger on %: no column %', r.tbl, r.pk;
      CONTINUE;
    END IF;

    EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_clinical_%I ON public.%I', r.tbl, r.tbl);
    EXECUTE format(
      'CREATE TRIGGER trg_audit_clinical_%I AFTER INSERT OR UPDATE OR DELETE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.audit_clinical_change(%L, %L)',
      r.tbl, r.tbl, r.pk, r.label);
  END LOOP;
END
$do$;


-- ---------------------------------------------------------------------------
-- 8. The read model
--
-- One view the portal can select from, with the actor resolved for historical
-- rows that predate the snapshot columns and a printable title per row.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.audit_trail_detailed AS
SELECT
  t.audit_id,
  t.action_timestamp,
  t.action,
  t.table_name,
  t.row_id,
  t.description,
  t.narrative,
  t.details,
  t.related_ids,
  t.entity_label,
  t.module,
  t.severity,
  t.source,
  t.event_key,
  t.ip_address,
  t.old_data,
  t.new_data,
  t.account_id,
  COALESCE(
    t.actor_name,
    nullif(btrim(concat_ws(' ', a.first_name, a.last_name)), ''),
    'System'
  )                                            AS actor_name,
  COALESCE(t.actor_role, a.account_type, 'system') AS actor_role,
  COALESCE(t.actor_facility_name,
           public.audit_facility_label(t.actor_facility_id)) AS actor_facility_name,
  a.email_address                              AS actor_email
FROM public.audit_trail t
LEFT JOIN public.accounts a ON a.account_id = t.account_id;

COMMENT ON VIEW public.audit_trail_detailed IS
  'Read model for the Activity Log. Prefers the snapshotted actor and falls back to the live account for rows written before 20260826.';


-- ---------------------------------------------------------------------------
-- 9. Backfill
--
-- History gets the same columns, derived from what those rows do carry. The
-- narrative is honest about being reconstructed: it is assembled from the
-- action and description that were recorded at the time, not invented detail.
-- ---------------------------------------------------------------------------
UPDATE public.audit_trail t
   SET module   = COALESCE(t.module,   public.audit_module_for(t.table_name, t.action)),
       severity = COALESCE(t.severity, public.audit_severity_for(t.action)),
       source   = COALESCE(t.source,   'legacy')
 WHERE t.module IS NULL OR t.severity IS NULL OR t.source IS NULL;

UPDATE public.audit_trail t
   SET actor_name = COALESCE(
         nullif(btrim(concat_ws(' ', a.first_name, a.last_name)), ''),
         'Account #' || t.account_id),
       actor_role = a.account_type
  FROM public.accounts a
 WHERE a.account_id = t.account_id
   AND t.actor_name IS NULL;

UPDATE public.audit_trail t
   SET actor_name = 'System',
       actor_role = 'system'
 WHERE t.actor_name IS NULL;

-- Scrub credentials out of history too. Rows written before this migration went
-- through no redaction at all, so any account change already on file may be
-- carrying a password hash into every export of this table.
UPDATE public.audit_trail t
   SET old_data = public.audit_redact(t.old_data),
       new_data = public.audit_redact(t.new_data)
 WHERE (t.old_data ?| ARRAY['password_hash','password','pending_password_hash',
                            'temporary_password','verification_code','reset_code',
                            'last_login_token','auth_id'])
    OR (t.new_data ?| ARRAY['password_hash','password','pending_password_hash',
                            'temporary_password','verification_code','reset_code',
                            'last_login_token','auth_id']);

UPDATE public.audit_trail t
   SET narrative = format(
         '%s (%s) performed "%s"%s on %s. %s',
         t.actor_name,
         COALESCE(t.actor_role, 'system'),
         t.action,
         COALESCE(' against ' || t.table_name, ''),
         COALESCE(public.audit_ts(public.audit_utc(t.action_timestamp)), 'an unrecorded date'),
         COALESCE(t.description,
                  'This entry predates detailed audit narratives; only the action and the actor were recorded at the time.'))
 WHERE t.narrative IS NULL;


-- ---------------------------------------------------------------------------
-- 10. Grants
--
-- Matching how the rest of this schema is exposed to the portal's anon client.
-- ---------------------------------------------------------------------------
GRANT SELECT ON public.audit_trail_detailed TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.audit_kv(TEXT, TEXT)                   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_section(TEXT, JSONB)             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_ts(TIMESTAMPTZ)                  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_date(DATE)                       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_qty(NUMERIC, TEXT)               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_bigint(TEXT)                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_utc(TIMESTAMP)                   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_redact(JSONB)                    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_inventory_disposal()             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_actor(BIGINT)                    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_facility_label(BIGINT)           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_batch_context(BIGINT)            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_batch_label(JSONB)               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_module_for(TEXT, TEXT)           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_severity_for(TEXT)               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_trail_enrich()                   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_inventory_stock_request()        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_inventory_transfer()             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_inventory_transaction()          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_inventory_batch()                TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_inventory_item()                 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_account_change()                 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_facility_assignment()            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_clinical_change()                TO anon, authenticated;

-- audit_write is SECURITY DEFINER and is only ever called from a trigger body.
-- No client needs it, so no client gets it.
REVOKE ALL ON FUNCTION public.audit_write(
  BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB, JSONB, TEXT, TEXT
) FROM PUBLIC, anon, authenticated;

COMMIT;


-- ---------------------------------------------------------------------------
-- 11. Verification
--
-- Issue a transfer, then confirm the whole chain landed:
--
--   SELECT action_timestamp, module, severity, action, actor_name,
--          entity_label, description
--     FROM public.audit_trail_detailed
--    WHERE module = 'Inventory'
--    ORDER BY audit_id DESC
--    LIMIT 20;
--
-- Expect at least three rows per issue: the transfer, the ledger movement, and
-- the batch decrease. Receipt adds three more at the other end.
--
-- Read one in full:
--
--   SELECT narrative, jsonb_pretty(details) FROM public.audit_trail
--    ORDER BY audit_id DESC LIMIT 1;
--
-- Nothing should be left uncategorised:
--
--   SELECT module, severity, count(*) FROM public.audit_trail
--    GROUP BY 1, 2 ORDER BY 1, 2;
-- ---------------------------------------------------------------------------
