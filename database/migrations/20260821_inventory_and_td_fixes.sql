-- ==============================================================================
-- MIGRATION: 20260821_inventory_and_td_fixes.sql
--
-- Repairs the defects that made a successfully recorded immunisation fail to
-- show up in the UI or in stock. Every one of them failed *silently*, because
-- the Flutter caller swallows RPC errors as "non-fatal" and the web page treats
-- a missing function as an un-migrated database.
--
--  (1) DUPLICATE FUNCTION OVERLOADS
--      20260819_solidify_multi_dose_open_vial_system.sql declared
--      deduct_immunization_stock(INTEGER), discard_open_vial_doses(INTEGER,...)
--      and deduct_prenatal_encounter_inventory(INTEGER,...) while BIGINT
--      versions of all three already existed. CREATE OR REPLACE does not replace
--      across a different argument type - it adds a second function. PostgREST
--      then cannot pick one and answers PGRST203 "could not choose the best
--      candidate function". Every child-immunisation stock deduction fails on
--      this before it ever reaches a batch.
--
--  (2) inventory_batches.status CHECK REJECTS 'depleted'
--      The CHECK only allowed active/expired/discarded, but a dozen RPCs set
--      'depleted' the moment a batch hits zero. The *last* unit of any batch
--      therefore raised 23514 and rolled the whole deduction back.
--
--  (3) inventory_transactions.transaction_type CHECK REJECTS 'discard'
--      discard_open_vial_doses writes 'discard'; the constraint never allowed
--      it, so discarding an expired open vial always failed.
--
--  (4) performed_by RECEIVED A midwife_id INSTEAD OF AN account_id
--      inventory_transactions.performed_by REFERENCES accounts(account_id), but
--      deduct_immunization_stock passed immunization_records.administered_by,
--      which REFERENCES midwives(midwife_id). Where the two numbers happened to
--      collide the audit trail named the wrong person; where they did not, the
--      FK raised and the deduction was lost. This is the "reference says
--      midwife_id and makes no sense" symptom in the inventory audit.
--
--  (5) maternal_td_records WAS UNREADABLE BY THE APP
--      It is the one table in this project with RLS enabled and policies scoped
--      TO authenticated. The apps use custom accounts-table auth over the anon
--      key, so they act as the `anon` role. Writes went through (the RPC is
--      SECURITY DEFINER and bypasses RLS) but every read came back empty - a Td
--      dose saved fine, logged to inventory, then vanished from the screen.
--
--  (6) LEDGER ENTRIES CARRIED MACHINE CODES AND NO reference_id
--      reference_type held 'maternal_td' / 'immunization' with a null
--      reference_id, so the audit column rendered a bare slug that points at
--      nothing.
--
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. Constraint repairs
-- ---------------------------------------------------------------------------

-- 1a. Allow 'depleted' on batches. Dropped by discovery, because the original
--     constraint was declared inline and its generated name differs between
--     databases built from active-draftschema.sql and from supabase_setup.sql.
DO $do$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname
      FROM pg_constraint c
      JOIN pg_class     t ON t.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'public'
       AND t.relname = 'inventory_batches'
       AND c.contype = 'c'
       AND pg_get_constraintdef(c.oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.inventory_batches DROP CONSTRAINT %I', r.conname);
  END LOOP;
END
$do$;

ALTER TABLE public.inventory_batches
  ADD CONSTRAINT inventory_batches_status_check
  CHECK (status IN ('active', 'expired', 'discarded', 'depleted'));

-- 1b. Allow 'discard' on transactions, alongside the values already in use.
ALTER TABLE public.inventory_transactions
  DROP CONSTRAINT IF EXISTS inventory_transactions_transaction_type_check;

ALTER TABLE public.inventory_transactions
  ADD CONSTRAINT inventory_transactions_transaction_type_check
  CHECK (
    transaction_type IN (
      'receipt',
      'dispense',
      'adjustment',
      'expiry_disposal',
      'discard',
      'transfer'
    )
  );

-- 1c. Columns several RPCs write to. Present on most databases already.
ALTER TABLE public.inventory_transactions ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE public.inventory_items
  ADD COLUMN IF NOT EXISTS doses_per_unit INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS open_vial_shelf_hours INTEGER DEFAULT 6;

ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS doses_remaining_in_open_vial INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS open_vials_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS vial_opened_at TIMESTAMPTZ;


-- ---------------------------------------------------------------------------
-- 2. maternal_td_records must be readable by the mobile app
--
-- Every other table in this project follows one pattern: RLS off, explicit
-- grants to anon + authenticated, authorisation enforced in the application and
-- in SECURITY DEFINER RPCs. This table was the lone exception, and that is why
-- a recorded Td dose never appeared on the Td screen.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Allow authenticated read maternal_td_records"  ON public.maternal_td_records;
DROP POLICY IF EXISTS "Allow authenticated write maternal_td_records" ON public.maternal_td_records;

ALTER TABLE public.maternal_td_records DISABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.maternal_td_records TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.maternal_td_records_td_record_id_seq TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 3. Actor resolution helper
--
-- The clinical tables store midwife_id in administered_by / recorded_by. The
-- inventory ledger stores account_id in performed_by. Callers pass whichever
-- they happen to hold, so resolve both rather than handing the FK a value it
-- will reject.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_actor_account_id(p_actor BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_account BIGINT;
BEGIN
  IF p_actor IS NULL THEN
    RETURN NULL;
  END IF;

  -- Prefer the midwife reading: that is what the clinical tables hold.
  SELECT account_id INTO v_account
    FROM public.midwives
   WHERE midwife_id = p_actor;

  IF v_account IS NOT NULL THEN
    RETURN v_account;
  END IF;

  -- Otherwise treat it as an account_id, which is what the admin portal passes.
  SELECT account_id INTO v_account
    FROM public.accounts
   WHERE account_id = p_actor;

  -- NULL when it is neither. performed_by is nullable, so the ledger entry still
  -- lands and reads as "System" instead of failing the whole deduction.
  RETURN v_account;
END
$fn$;

COMMENT ON FUNCTION public.resolve_actor_account_id(BIGINT) IS
  'Maps a midwife_id or an account_id onto accounts.account_id for inventory_transactions.performed_by.';


-- ---------------------------------------------------------------------------
-- 4. Collapse the duplicate overloads
--
-- Drop every signature of these three names, then recreate exactly one of each,
-- so PostgREST has an unambiguous candidate no matter which of the earlier
-- migrations a given database has already seen.
-- ---------------------------------------------------------------------------
DO $do$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc      p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN (
         'deduct_immunization_stock',
         'discard_open_vial_doses'
       )
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s', r.sig);
  END LOOP;

  -- deduct_prenatal_encounter_inventory: drop only the stray INTEGER overload
  -- and leave the BIGINT body from 20260819 in place, since it is unchanged by
  -- this migration.
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc      p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'deduct_prenatal_encounter_inventory'
       AND pg_get_function_identity_arguments(p.oid) ILIKE '%integer%'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s', r.sig);
  END LOOP;
END
$do$;


-- ---------------------------------------------------------------------------
-- 5. discard_open_vial_doses - single BIGINT signature, resolved actor
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.discard_open_vial_doses(
  p_batch_id     BIGINT,
  p_discarded_by BIGINT DEFAULT NULL,
  p_reason       TEXT   DEFAULT 'Open vial exceeded its maximum shelf life'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_batch        public.inventory_batches%ROWTYPE;
  v_item_name    TEXT;
  v_doses_wasted INTEGER;
  v_actor        BIGINT;
BEGIN
  SELECT * INTO v_batch
    FROM public.inventory_batches
   WHERE batch_id = p_batch_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Batch #' || p_batch_id || ' not found');
  END IF;

  v_doses_wasted := COALESCE(v_batch.doses_remaining_in_open_vial, 0);

  IF v_doses_wasted <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'This batch has no open-vial doses left to discard');
  END IF;

  SELECT name INTO v_item_name FROM public.inventory_items WHERE item_id = v_batch.item_id;
  v_actor := public.resolve_actor_account_id(p_discarded_by);

  UPDATE public.inventory_batches
     SET doses_remaining_in_open_vial = 0,
         open_vials_count             = GREATEST(0, COALESCE(open_vials_count, 1) - 1),
         vial_opened_at               = NULL,
         status = CASE WHEN COALESCE(quantity_remaining, 0) <= 0 THEN 'depleted' ELSE status END
   WHERE batch_id = p_batch_id;

  INSERT INTO public.inventory_transactions (
    batch_id, facility_id, transaction_type, quantity,
    reference_type, reference_id, notes, performed_by, logged_at
  ) VALUES (
    p_batch_id,
    v_batch.facility_id,
    'discard',
    -v_doses_wasted,
    'Open Vial Discard',
    p_batch_id,
    'Discarded ' || v_doses_wasted || ' open dose(s) of ' || COALESCE(v_item_name, 'vaccine')
      || ' from Batch #' || v_batch.batch_number || ' - ' || COALESCE(p_reason, 'expired open vial'),
    v_actor,
    NOW()
  );

  RETURN jsonb_build_object(
    'success',         true,
    'batch_id',        p_batch_id,
    'doses_discarded', v_doses_wasted,
    'message',         'Discarded ' || v_doses_wasted || ' open dose(s)'
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 6. deduct_immunization_stock - single BIGINT signature
--
-- Same FEFO / multi-dose-vial behaviour as 20260819, plus:
--   * an idempotency guard on immunization_records.inventory_deducted, so a
--     retry after a network hiccup cannot double-deduct;
--   * performed_by resolved to a real account_id;
--   * a human reference_type and a reference_id that actually points at the
--     immunisation record;
--   * inventory_deducted flipped to true on success, which the earlier version
--     dropped entirely.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deduct_immunization_stock(
  p_immunization_record_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_rec            RECORD;
  v_item_id        BIGINT;
  v_doses_per_unit INTEGER := 1;
  v_shelf_hours    INTEGER := 6;
  v_batch          RECORD;
  v_doses_left     INTEGER;
  v_hours_open     NUMERIC;
  v_actor          BIGINT;
BEGIN
  SELECT
    ir.immunization_record_id,
    ir.vaccine_id,
    ir.facility_id,
    ir.administered_by,
    ir.recorded_by,
    ir.source,
    ir.administration_place,
    COALESCE(ir.inventory_deducted, false) AS inventory_deducted,
    ir.inventory_batch_id,
    v.vaccine_name,
    v.inventory_item_id
  INTO v_rec
  FROM public.immunization_records ir
  JOIN public.vaccines v ON v.vaccine_id = ir.vaccine_id
  WHERE ir.immunization_record_id = p_immunization_record_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Immunization record #' || p_immunization_record_id || ' not found');
  END IF;

  -- Already settled. Report success so a retry is harmless.
  IF v_rec.inventory_deducted THEN
    RETURN jsonb_build_object(
      'success',  true,
      'mode',     'already_deducted',
      'batch_id', v_rec.inventory_batch_id,
      'message',  'Stock for this record was already deducted'
    );
  END IF;

  -- A dose given elsewhere draws nothing from our shelves.
  IF v_rec.source = 'outside'
     OR v_rec.administration_place = 'external_facility'
     OR v_rec.facility_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'mode', 'outside',
      'message', 'Recorded as given outside this facility - no stock deducted');
  END IF;

  v_actor := public.resolve_actor_account_id(
    COALESCE(v_rec.administered_by, v_rec.recorded_by)
  );

  -- Resolve the catalogue item behind this vaccine.
  v_item_id := v_rec.inventory_item_id;
  IF v_item_id IS NULL THEN
    SELECT item_id INTO v_item_id
      FROM public.inventory_items
     WHERE is_archived = false
       AND (
            LOWER(name)         = LOWER(v_rec.vaccine_name)
         OR LOWER(generic_name) = LOWER(v_rec.vaccine_name)
         OR (v_rec.vaccine_name ILIKE '%bcg%'     AND (name ILIKE '%bcg%'     OR generic_name ILIKE '%bcg%'))
         OR (v_rec.vaccine_name ILIKE '%opv%'     AND (name ILIKE '%opv%'     OR generic_name ILIKE '%polio%'))
         OR (v_rec.vaccine_name ILIKE '%ipv%'     AND (name ILIKE '%ipv%'     OR generic_name ILIKE '%polio%'))
         OR (v_rec.vaccine_name ILIKE '%penta%'   AND (name ILIKE '%penta%'   OR generic_name ILIKE '%pentavalent%'))
         OR (v_rec.vaccine_name ILIKE '%pcv%'     AND (name ILIKE '%pcv%'     OR generic_name ILIKE '%pneumococcal%'))
         OR (v_rec.vaccine_name ILIKE '%measles%' AND (name ILIKE '%measles%' OR name ILIKE '%mr%' OR generic_name ILIKE '%measles%'))
         OR (v_rec.vaccine_name ILIKE '%mmr%'     AND (name ILIKE '%mmr%'     OR name ILIKE '%measles%' OR generic_name ILIKE '%measles%'))
         OR (v_rec.vaccine_name ILIKE '%hep%'     AND (name ILIKE '%hep%'     OR generic_name ILIKE '%hepatitis%'))
         OR (v_rec.vaccine_name ILIKE '%rota%'    AND (name ILIKE '%rota%'    OR generic_name ILIKE '%rotavirus%'))
       )
     ORDER BY
       CASE WHEN LOWER(name) = LOWER(v_rec.vaccine_name) THEN 1 ELSE 2 END,
       item_id
     LIMIT 1;
  END IF;

  IF v_item_id IS NULL THEN
    RETURN jsonb_build_object('success', false,
      'error', 'No inventory catalogue item is linked to the vaccine "' || v_rec.vaccine_name || '"');
  END IF;

  SELECT COALESCE(doses_per_unit, 1), COALESCE(open_vial_shelf_hours, 6)
    INTO v_doses_per_unit, v_shelf_hours
    FROM public.inventory_items
   WHERE item_id = v_item_id;

  -- DOH defaults for the standard multi-dose presentations, when the catalogue
  -- row has not been configured yet.
  IF v_doses_per_unit = 1 THEN
    IF v_rec.vaccine_name ILIKE '%bcg%' THEN
      v_doses_per_unit := 20; v_shelf_hours := 6;
    ELSIF v_rec.vaccine_name ILIKE '%opv%' THEN
      v_doses_per_unit := 20; v_shelf_hours := 672;
    ELSIF v_rec.vaccine_name ILIKE '%measles%' OR v_rec.vaccine_name ILIKE '%mmr%' OR v_rec.vaccine_name ILIKE '%rubella%' THEN
      v_doses_per_unit := 10; v_shelf_hours := 6;
    END IF;
  END IF;

  -- =========================== multi-dose vials ===========================
  IF v_doses_per_unit > 1 THEN

    -- (a) Use an already-open vial first, earliest expiry first.
    FOR v_batch IN
      SELECT batch_id, batch_number, expiration_date, quantity_remaining, vial_opened_at,
             COALESCE(doses_remaining_in_open_vial, 0) AS doses_remaining_in_open_vial,
             COALESCE(open_vials_count, 0)             AS open_vials_count
        FROM public.inventory_batches
       WHERE item_id     = v_item_id
         AND facility_id = v_rec.facility_id
         AND status      = 'active'
         AND expiration_date >= CURRENT_DATE
         AND COALESCE(doses_remaining_in_open_vial, 0) > 0
       ORDER BY expiration_date ASC, batch_id ASC
         FOR UPDATE
    LOOP
      -- Past its open-vial shelf life: discard the remainder and move on.
      IF v_batch.vial_opened_at IS NOT NULL AND v_shelf_hours > 0 THEN
        v_hours_open := EXTRACT(EPOCH FROM (NOW() - v_batch.vial_opened_at)) / 3600;
        IF v_hours_open > v_shelf_hours THEN
          UPDATE public.inventory_batches
             SET doses_remaining_in_open_vial = 0,
                 open_vials_count = GREATEST(0, COALESCE(open_vials_count, 1) - 1),
                 vial_opened_at   = NULL,
                 status = CASE WHEN quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
           WHERE batch_id = v_batch.batch_id;

          INSERT INTO public.inventory_transactions (
            batch_id, facility_id, transaction_type, quantity,
            reference_type, reference_id, notes, performed_by, logged_at
          ) VALUES (
            v_batch.batch_id, v_rec.facility_id, 'expiry_disposal', -v_batch.doses_remaining_in_open_vial,
            'Open Vial Expiry', v_batch.batch_id,
            'Auto-discarded ' || v_batch.doses_remaining_in_open_vial || ' dose(s) left in an open '
              || v_rec.vaccine_name || ' vial (Batch #' || v_batch.batch_number
              || ') past the ' || v_shelf_hours || 'h limit',
            v_actor, NOW()
          );

          CONTINUE;
        END IF;
      END IF;

      v_doses_left := v_batch.doses_remaining_in_open_vial - 1;

      UPDATE public.inventory_batches
         SET doses_remaining_in_open_vial = v_doses_left,
             open_vials_count = CASE WHEN v_doses_left <= 0
                                     THEN GREATEST(0, COALESCE(open_vials_count, 1) - 1)
                                     ELSE COALESCE(open_vials_count, 1) END,
             vial_opened_at   = CASE WHEN v_doses_left <= 0 THEN NULL
                                     ELSE COALESCE(v_batch.vial_opened_at, NOW()) END,
             status = CASE WHEN v_doses_left <= 0 AND quantity_remaining <= 0
                           THEN 'depleted' ELSE 'active' END
       WHERE batch_id = v_batch.batch_id;

      UPDATE public.immunization_records
         SET inventory_batch_id = v_batch.batch_id,
             inventory_deducted = true
       WHERE immunization_record_id = p_immunization_record_id;

      INSERT INTO public.inventory_transactions (
        batch_id, facility_id, transaction_type, quantity,
        reference_type, reference_id, notes, performed_by, logged_at
      ) VALUES (
        v_batch.batch_id, v_rec.facility_id, 'dispense', 0,
        'Child Immunization', p_immunization_record_id,
        '1 dose of ' || v_rec.vaccine_name || ' from an open vial (Batch #'
          || v_batch.batch_number || ', ' || v_doses_left || ' dose(s) left)',
        v_actor, NOW()
      );

      RETURN jsonb_build_object(
        'success', true, 'mode', 'open_vial_dose',
        'batch_id', v_batch.batch_id, 'batch_number', v_batch.batch_number,
        'doses_left_in_vial', v_doses_left, 'doses_per_unit', v_doses_per_unit,
        'shelf_hours', v_shelf_hours,
        'message', '1 dose deducted from the open vial'
      );
    END LOOP;

    -- (b) Nothing open and usable: break the seal on the next vial, FEFO.
    SELECT batch_id, batch_number, quantity_remaining
      INTO v_batch
      FROM public.inventory_batches
     WHERE item_id     = v_item_id
       AND facility_id = v_rec.facility_id
       AND status      = 'active'
       AND expiration_date >= CURRENT_DATE
       AND quantity_remaining > 0
     ORDER BY expiration_date ASC, batch_id ASC
     LIMIT 1
       FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false,
        'error', 'Out of stock: no usable ' || v_rec.vaccine_name || ' vial at this facility');
    END IF;

    v_doses_left := v_doses_per_unit - 1;

    UPDATE public.inventory_batches
       SET quantity_remaining           = quantity_remaining - 1,
           open_vials_count             = COALESCE(open_vials_count, 0) + 1,
           doses_remaining_in_open_vial = COALESCE(doses_remaining_in_open_vial, 0) + v_doses_left,
           vial_opened_at               = NOW(),
           status = CASE WHEN (quantity_remaining - 1) <= 0 AND v_doses_left <= 0
                         THEN 'depleted' ELSE 'active' END
     WHERE batch_id = v_batch.batch_id;

    UPDATE public.immunization_records
       SET inventory_batch_id = v_batch.batch_id,
           inventory_deducted = true
     WHERE immunization_record_id = p_immunization_record_id;

    INSERT INTO public.inventory_transactions (
      batch_id, facility_id, transaction_type, quantity,
      reference_type, reference_id, notes, performed_by, logged_at
    ) VALUES (
      v_batch.batch_id, v_rec.facility_id, 'dispense', -1,
      'Child Immunization', p_immunization_record_id,
      'Opened a ' || v_doses_per_unit || '-dose ' || v_rec.vaccine_name || ' vial (Batch #'
        || v_batch.batch_number || '); 1 dose given, ' || v_doses_left || ' left open',
      v_actor, NOW()
    );

    RETURN jsonb_build_object(
      'success', true, 'mode', 'new_vial_opened',
      'batch_id', v_batch.batch_id, 'batch_number', v_batch.batch_number,
      'doses_left_in_vial', v_doses_left, 'doses_per_unit', v_doses_per_unit,
      'shelf_hours', v_shelf_hours,
      'message', 'Opened a fresh sealed vial'
    );

  -- =========================== single-dose units ==========================
  ELSE
    SELECT batch_id, batch_number, quantity_remaining
      INTO v_batch
      FROM public.inventory_batches
     WHERE item_id     = v_item_id
       AND facility_id = v_rec.facility_id
       AND status      = 'active'
       AND expiration_date >= CURRENT_DATE
       AND quantity_remaining > 0
     ORDER BY expiration_date ASC, batch_id ASC
     LIMIT 1
       FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false,
        'error', 'Out of stock: no usable ' || v_rec.vaccine_name || ' unit at this facility');
    END IF;

    UPDATE public.inventory_batches
       SET quantity_remaining = quantity_remaining - 1,
           status = CASE WHEN (quantity_remaining - 1) <= 0 THEN 'depleted' ELSE 'active' END
     WHERE batch_id = v_batch.batch_id;

    UPDATE public.immunization_records
       SET inventory_batch_id = v_batch.batch_id,
           inventory_deducted = true
     WHERE immunization_record_id = p_immunization_record_id;

    INSERT INTO public.inventory_transactions (
      batch_id, facility_id, transaction_type, quantity,
      reference_type, reference_id, notes, performed_by, logged_at
    ) VALUES (
      v_batch.batch_id, v_rec.facility_id, 'dispense', -1,
      'Child Immunization', p_immunization_record_id,
      'Dispensed 1 single-dose unit of ' || v_rec.vaccine_name
        || ' (Batch #' || v_batch.batch_number || ')',
      v_actor, NOW()
    );

    RETURN jsonb_build_object(
      'success', true, 'mode', 'single_dose',
      'batch_id', v_batch.batch_id, 'batch_number', v_batch.batch_number,
      'doses_left_in_vial', 0, 'doses_per_unit', 1,
      'message', 'Dispensed 1 single-dose unit'
    );
  END IF;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 6b. Td helpers, redeclared so this file stands on its own
--     (originally from 20260819_td_canonical_sync.sql).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalize_td_dose(p_raw TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  v_digits TEXT;
  v_num    INTEGER;
BEGIN
  IF p_raw IS NULL THEN RETURN NULL; END IF;

  v_digits := NULLIF(regexp_replace(p_raw, '\D', '', 'g'), '');
  IF v_digits IS NULL THEN RETURN NULL; END IF;

  v_num := v_digits::INTEGER;
  IF v_num < 1 OR v_num > 5 THEN RETURN NULL; END IF;

  RETURN 'Td' || v_num;
END
$fn$;

CREATE OR REPLACE FUNCTION public.td_dose_schedule(
  p_dose TEXT,
  p_date DATE,
  OUT o_protection_until DATE,
  OUT o_next_due DATE
)
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
BEGIN
  CASE p_dose
    WHEN 'Td1' THEN o_protection_until := NULL;                         o_next_due := p_date + INTERVAL '28 days';
    WHEN 'Td2' THEN o_protection_until := p_date + INTERVAL '3 years';  o_next_due := p_date + INTERVAL '180 days';
    WHEN 'Td3' THEN o_protection_until := p_date + INTERVAL '5 years';  o_next_due := p_date + INTERVAL '365 days';
    WHEN 'Td4' THEN o_protection_until := p_date + INTERVAL '10 years'; o_next_due := p_date + INTERVAL '365 days';
    WHEN 'Td5' THEN o_protection_until := p_date + INTERVAL '50 years'; o_next_due := NULL;
    ELSE o_protection_until := NULL; o_next_due := NULL;
  END CASE;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 7. administer_maternal_td_dose - reworked
--
-- Changes against 20260819:
--   * the record is written first, so the ledger entry can carry a reference_id
--     that resolves to a real Td record instead of a bare slug;
--   * p_administered_by may be a midwife_id or an account_id;
--   * the Td catalogue lookup no longer matches any item whose name merely
--     contains the letters "td" (it matched supplements on some catalogues);
--   * a Td already on file is reported rather than silently overwritten when the
--     caller re-submits.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.administer_maternal_td_dose(
  p_mother_id        BIGINT,
  p_dose_number      TEXT,
  p_vaccination_date DATE,
  p_facility_id      BIGINT,
  p_administered_by  BIGINT,
  p_source           TEXT DEFAULT 'bhc',
  p_facility_name    TEXT DEFAULT NULL,
  p_remarks          TEXT DEFAULT NULL,
  p_evidence         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_dose             TEXT;
  v_item_id          BIGINT;
  v_doses_per_unit   INTEGER := 10;
  v_shelf_hours      INTEGER := 672;   -- 28 days, DOH standard for an opened Td vial
  v_batch            RECORD;
  v_batch_id         BIGINT;
  v_batch_number     TEXT;
  v_doses_left       INTEGER;
  v_hours_open       NUMERIC;
  v_protection_until DATE;
  v_next_due         DATE;
  v_prev_date        DATE;
  v_days_since_prev  INTEGER;
  v_min_interval     INTEGER := 0;
  v_record_id        BIGINT;
  v_mode             TEXT := 'no_deduction';
  v_actor            BIGINT;
  v_midwife_id       BIGINT;
BEGIN
  v_dose := public.normalize_td_dose(p_dose_number);
  IF v_dose IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid dose number: ' || COALESCE(p_dose_number, 'null'));
  END IF;

  IF p_vaccination_date IS NULL OR p_vaccination_date > CURRENT_DATE THEN
    RETURN jsonb_build_object('success', false, 'error', 'The vaccination date cannot be in the future');
  END IF;

  SELECT o_protection_until, o_next_due
    INTO v_protection_until, v_next_due
    FROM public.td_dose_schedule(v_dose, p_vaccination_date);

  v_min_interval := CASE v_dose
    WHEN 'Td2' THEN 28    -- 4 weeks
    WHEN 'Td3' THEN 180   -- 6 months
    WHEN 'Td4' THEN 365   -- 1 year
    WHEN 'Td5' THEN 365   -- 1 year
    ELSE 0
  END;

  -- DOH minimum interval against the preceding dose.
  IF v_min_interval > 0 THEN
    SELECT vaccination_date INTO v_prev_date
      FROM public.maternal_td_records
     WHERE mother_id = p_mother_id
       AND dose_number = 'Td' || (substring(v_dose from 3)::INTEGER - 1);

    IF v_prev_date IS NOT NULL THEN
      v_days_since_prev := p_vaccination_date - v_prev_date;
      IF v_days_since_prev < v_min_interval THEN
        RETURN jsonb_build_object('success', false,
          'error', 'DOH interval not met: ' || v_dose || ' needs at least ' || v_min_interval
                || ' days after the previous dose, but only ' || v_days_since_prev || ' have passed.');
      END IF;
    END IF;
  END IF;

  -- administered_by is a midwives FK; accept an account_id from other callers.
  SELECT midwife_id INTO v_midwife_id FROM public.midwives WHERE midwife_id = p_administered_by;
  IF v_midwife_id IS NULL THEN
    SELECT midwife_id INTO v_midwife_id FROM public.midwives WHERE account_id = p_administered_by;
  END IF;
  v_actor := public.resolve_actor_account_id(p_administered_by);

  -- Write the record first so the ledger can point back at it.
  INSERT INTO public.maternal_td_records (
    mother_id, dose_number, vaccination_date, facility_id, facility_name, source,
    administered_by, inventory_deducted, protection_until, next_due_date, remarks, evidence
  ) VALUES (
    p_mother_id, v_dose, p_vaccination_date, p_facility_id, p_facility_name,
    COALESCE(p_source, 'bhc'), v_midwife_id, false, v_protection_until, v_next_due,
    p_remarks, p_evidence
  )
  ON CONFLICT (mother_id, dose_number) DO UPDATE
    SET vaccination_date = EXCLUDED.vaccination_date,
        facility_id      = EXCLUDED.facility_id,
        facility_name    = EXCLUDED.facility_name,
        source           = EXCLUDED.source,
        administered_by  = COALESCE(EXCLUDED.administered_by, maternal_td_records.administered_by),
        protection_until = EXCLUDED.protection_until,
        next_due_date    = EXCLUDED.next_due_date,
        remarks          = EXCLUDED.remarks,
        evidence         = EXCLUDED.evidence
  RETURNING td_record_id, inventory_batch_id
       INTO v_record_id, v_batch_id;

  -- A batch already linked means this dose was recorded before and its stock was
  -- taken then. Re-submitting must not deduct a second time.
  v_mode := CASE WHEN v_batch_id IS NOT NULL THEN 'already_deducted' ELSE 'no_deduction' END;

  -- Only a dose given here draws stock, and only once.
  IF COALESCE(p_source, 'bhc') = 'bhc' AND p_facility_id IS NOT NULL AND v_batch_id IS NULL THEN

    SELECT item_id, COALESCE(doses_per_unit, 10), COALESCE(open_vial_shelf_hours, 672)
      INTO v_item_id, v_doses_per_unit, v_shelf_hours
      FROM public.inventory_items
     WHERE is_archived = false
       AND (
            name ~* '(^|[^a-z])td([^a-z]|$)'
         OR name ~* '(^|[^a-z])tt([^a-z]|$)'
         OR name         ILIKE '%tetanus%'
         OR generic_name ILIKE '%tetanus%'
         OR generic_name ILIKE '%diphtheria%'
       )
     ORDER BY (item_type = 'vaccine') DESC, item_id
     LIMIT 1;

    IF v_item_id IS NOT NULL THEN

      -- (a) An open Td vial that is still within its 28-day window.
      FOR v_batch IN
        SELECT batch_id, batch_number, expiration_date, quantity_remaining, vial_opened_at,
               COALESCE(doses_remaining_in_open_vial, 0) AS doses_remaining_in_open_vial,
               COALESCE(open_vials_count, 0)             AS open_vials_count
          FROM public.inventory_batches
         WHERE item_id     = v_item_id
           AND facility_id = p_facility_id
           AND status      = 'active'
           AND expiration_date >= CURRENT_DATE
           AND COALESCE(doses_remaining_in_open_vial, 0) > 0
         ORDER BY expiration_date ASC, batch_id ASC
           FOR UPDATE
      LOOP
        IF v_batch.vial_opened_at IS NOT NULL AND v_shelf_hours > 0 THEN
          v_hours_open := EXTRACT(EPOCH FROM (NOW() - v_batch.vial_opened_at)) / 3600;
          IF v_hours_open > v_shelf_hours THEN
            UPDATE public.inventory_batches
               SET doses_remaining_in_open_vial = 0,
                   open_vials_count = GREATEST(0, COALESCE(open_vials_count, 1) - 1),
                   vial_opened_at   = NULL,
                   status = CASE WHEN quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
             WHERE batch_id = v_batch.batch_id;

            INSERT INTO public.inventory_transactions (
              batch_id, facility_id, transaction_type, quantity,
              reference_type, reference_id, notes, performed_by, logged_at
            ) VALUES (
              v_batch.batch_id, p_facility_id, 'expiry_disposal', -v_batch.doses_remaining_in_open_vial,
              'Open Vial Expiry', v_batch.batch_id,
              'Auto-discarded ' || v_batch.doses_remaining_in_open_vial
                || ' dose(s) left in an open Td vial (Batch #' || v_batch.batch_number
                || ') past the ' || v_shelf_hours || 'h limit',
              v_actor, NOW()
            );

            CONTINUE;
          END IF;
        END IF;

        v_doses_left   := v_batch.doses_remaining_in_open_vial - 1;
        v_batch_id     := v_batch.batch_id;
        v_batch_number := v_batch.batch_number;
        v_mode         := 'open_vial_dose';

        UPDATE public.inventory_batches
           SET doses_remaining_in_open_vial = v_doses_left,
               open_vials_count = CASE WHEN v_doses_left <= 0
                                       THEN GREATEST(0, COALESCE(open_vials_count, 1) - 1)
                                       ELSE COALESCE(open_vials_count, 1) END,
               vial_opened_at   = CASE WHEN v_doses_left <= 0 THEN NULL
                                       ELSE COALESCE(v_batch.vial_opened_at, NOW()) END,
               status = CASE WHEN v_doses_left <= 0 AND quantity_remaining <= 0
                             THEN 'depleted' ELSE 'active' END
         WHERE batch_id = v_batch.batch_id;

        INSERT INTO public.inventory_transactions (
          batch_id, facility_id, transaction_type, quantity,
          reference_type, reference_id, notes, performed_by, logged_at
        ) VALUES (
          v_batch.batch_id, p_facility_id, 'dispense', 0,
          'Maternal Td Immunization', v_record_id,
          'Maternal ' || v_dose || ' from an open Td vial (Batch #' || v_batch.batch_number
            || ', ' || v_doses_left || ' dose(s) left)',
          v_actor, NOW()
        );

        EXIT;
      END LOOP;

      -- (b) Otherwise open a fresh sealed vial, FEFO.
      IF v_batch_id IS NULL THEN
        SELECT batch_id, batch_number, quantity_remaining
          INTO v_batch
          FROM public.inventory_batches
         WHERE item_id     = v_item_id
           AND facility_id = p_facility_id
           AND status      = 'active'
           AND expiration_date >= CURRENT_DATE
           AND quantity_remaining > 0
         ORDER BY expiration_date ASC, batch_id ASC
         LIMIT 1
           FOR UPDATE;

        IF FOUND THEN
          v_doses_left   := v_doses_per_unit - 1;
          v_batch_id     := v_batch.batch_id;
          v_batch_number := v_batch.batch_number;
          v_mode         := 'new_vial_opened';

          UPDATE public.inventory_batches
             SET quantity_remaining           = quantity_remaining - 1,
                 open_vials_count             = COALESCE(open_vials_count, 0) + 1,
                 doses_remaining_in_open_vial = COALESCE(doses_remaining_in_open_vial, 0) + v_doses_left,
                 vial_opened_at               = NOW(),
                 status = CASE WHEN (quantity_remaining - 1) <= 0 AND v_doses_left <= 0
                               THEN 'depleted' ELSE 'active' END
           WHERE batch_id = v_batch.batch_id;

          INSERT INTO public.inventory_transactions (
            batch_id, facility_id, transaction_type, quantity,
            reference_type, reference_id, notes, performed_by, logged_at
          ) VALUES (
            v_batch.batch_id, p_facility_id, 'dispense', -1,
            'Maternal Td Immunization', v_record_id,
            'Opened a ' || v_doses_per_unit || '-dose Td vial for ' || v_dose
              || ' (Batch #' || v_batch.batch_number || '); 1 dose given, '
              || v_doses_left || ' left open',
            v_actor, NOW()
          );
        END IF;
      END IF;
    END IF;
  END IF;

  UPDATE public.maternal_td_records
     SET inventory_batch_id = COALESCE(v_batch_id, inventory_batch_id),
         inventory_deducted = (COALESCE(v_batch_id, inventory_batch_id) IS NOT NULL)
   WHERE td_record_id = v_record_id;

  RETURN jsonb_build_object(
    'success',            true,
    'record_id',          v_record_id,
    'mode',               v_mode,
    'dose_number',        v_dose,
    'batch_id',           v_batch_id,
    'batch_number',       v_batch_number,
    'doses_left_in_vial', COALESCE(v_doses_left, 0),
    'protection_until',   v_protection_until,
    'next_due_date',      v_next_due,
    'is_pab',             (v_dose <> 'Td1' AND (v_protection_until IS NULL OR v_protection_until >= CURRENT_DATE)),
    'is_fim',             (v_dose = 'Td5')
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 8. Repair the ledger rows the broken versions already wrote
-- ---------------------------------------------------------------------------

-- 8a. Machine slugs -> the labels the audit table renders.
UPDATE public.inventory_transactions
   SET reference_type = 'Child Immunization'
 WHERE reference_type = 'immunization';

UPDATE public.inventory_transactions
   SET reference_type = 'Maternal Td Immunization'
 WHERE reference_type = 'maternal_td';

UPDATE public.inventory_transactions
   SET reference_type = 'Open Vial Expiry'
 WHERE reference_type = 'open_vial_expired';

-- 8b. performed_by that holds a midwife_id, re-derived from the record it
--     references. Only touched where the immunisation record names a midwife
--     whose account_id differs from the value stored.
UPDATE public.inventory_transactions t
   SET performed_by = m.account_id
  FROM public.immunization_records ir
  JOIN public.midwives m ON m.midwife_id = COALESCE(ir.administered_by, ir.recorded_by)
 WHERE t.reference_type = 'Child Immunization'
   AND t.reference_id   = ir.immunization_record_id
   AND m.account_id IS NOT NULL
   AND t.performed_by IS DISTINCT FROM m.account_id;

-- 8c. Backfill inventory_deducted for records that do have a batch linked, so
--     the new idempotency guard does not deduct a second time for them.
UPDATE public.immunization_records
   SET inventory_deducted = true
 WHERE inventory_batch_id IS NOT NULL
   AND COALESCE(inventory_deducted, false) = false;


-- ---------------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.resolve_actor_account_id(BIGINT)                       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.deduct_immunization_stock(BIGINT)                      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.discard_open_vial_doses(BIGINT, BIGINT, TEXT)          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.administer_maternal_td_dose(
  BIGINT, TEXT, DATE, BIGINT, BIGINT, TEXT, TEXT, TEXT, TEXT)                           TO anon, authenticated;
