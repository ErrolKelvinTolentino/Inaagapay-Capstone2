-- ==============================================================================
-- MIGRATION: 20260829_inventory_transfer_directions.sql
--
-- Makes a stock transfer a movement between TWO named places instead of a
-- delivery to one, and lets stock travel back up the hierarchy.
--
-- WHY
--
--  (1) A TRANSFER ONLY EVER RECORDED WHERE IT WAS GOING
--      inventory_transfers has destination_facility_id and no source. Where the
--      stock came FROM was recoverable only by joining the source batch, and a
--      batch that has since been depleted, archived or re-received tells a
--      different story than the one at dispatch time. Every consumer paid for
--      that: the mobile app filters transfers on destination_facility_id alone,
--      so a barangay health centre that SENDS stock to a neighbour sees nothing
--      at all - the units simply vanish off its shelf with no record on the
--      screen the midwife actually reads. The same hole exists RHU -> RHU.
--
--      source_facility_id is now a column, stamped by a trigger and backfilled
--      for history. NULL means the municipal warehouse, exactly as it does on
--      inventory_batches.facility_id.
--
--  (2) STOCK COULD ONLY MOVE DOWNWARD
--      MHO -> RHU -> BHC was the only supported flow. Real health centres move
--      stock the other way during a brownout, a freezer failure or a broken
--      cold chain: the vaccines go UP to the RHU (or on to the municipal
--      warehouse) precisely so they do not spoil. The distribution engine never
--      forbade it, but nothing named it, nothing routed the notification, and
--      the portal offered no destination above the current facility.
--
--      Transfers are now classified as allocation (downward), lateral (between
--      peers) or return (upward), and all three are first-class.
--
--  (3) A FACILITY COULD TRANSFER TO ITSELF
--      The only guard was "source batch's facility <> destination", which does
--      not fire when the source is the depot sentinel. Selecting the same
--      facility at both ends produced a real transfer that debited and credited
--      the same shelf and left a permanent phantom "in transit" quantity.
--      Both ends are now compared as PLACES, with the municipal warehouse and
--      the MHO facility row treated as the one place they are.
--
--  (4) ONLY THE RECEIVING END WAS EVER TOLD ANYTHING
--      The sending facility got no notification when stock left, none when it
--      arrived, and none when a dispatch was cancelled. For a downward
--      allocation that is survivable - the office issuing it is the one
--      clicking the button. For a lateral or return move the sender is a
--      different facility from the operator, and it was told nothing.
--
--  (5) THE MUNICIPAL OFFICE COULD NOT RE-PLAN A DELIVERY
--      update_inventory_transfer_delivery() asserts the actor is account_type
--      'admin' exactly. Under the MHO tier a municipal officer is 'mho', so the
--      one account responsible for every MHO -> RHU dispatch could not revise
--      the arrival date on any of them. It also notified midwives at the
--      destination and nobody else, which tells nobody at all when the
--      destination is an RHU, and never told the sending facility.
--
--  (6) CANCELLING A TRANSFER LEFT THE LEDGER LYING
--      The portal cancelled in two separate writes with no transaction around
--      them, and wrote no inventory_transactions row. The ledger therefore
--      showed the stock leaving and never coming back, while the batch quantity
--      quietly went up. cancel_inventory_transfer() now does the whole thing
--      atomically and posts the reversing ledger row.
--
-- Requires 20260826_audit_trail_completeness.sql.
-- Safe to run more than once. Every statement is idempotent.
-- ==============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF to_regclass('public.inventory_transfers') IS NULL THEN
    RAISE EXCEPTION
      'Prerequisite missing: table public.inventory_transfers does not exist. Run 20260803_inventory_distribution_workflow.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'health_facilities'
       AND column_name = 'parent_facility_id'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: health_facilities.parent_facility_id. Run 20260821_mho_tier.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'audit_write'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: function public.audit_write(). Run 20260826_audit_trail_completeness.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'inventory_actor_facility_id'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: function public.inventory_actor_facility_id(). Run 20260821_mho_tier.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.health_facilities WHERE facility_type = 'MHO'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: no facility of type MHO exists. Run 20260821_mho_tier.sql first — the municipal office is what "up the hierarchy" means.';
  END IF;
END
$preflight$;

-- Every notification this file writes is typed 'inventory'. On a database that
-- skipped 20260824 the check constraint still refuses that value, and the first
-- transfer would fail inside a trigger with a constraint violation rather than
-- anything a reader could act on. Widening it here is the same idempotent DO
-- block 20260824 uses, so running both in either order is safe.
DO $notif_type$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
     WHERE t.relname = 'notifications'
       AND c.contype = 'c'
       AND pg_get_constraintdef(c.oid) ILIKE '%checkup_reminder%'
       AND pg_get_constraintdef(c.oid) NOT ILIKE '%inventory%'
  LOOP
    EXECUTE format('ALTER TABLE public.notifications DROP CONSTRAINT %I', r.conname);
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
     WHERE t.relname = 'notifications' AND c.contype = 'c'
       AND pg_get_constraintdef(c.oid) ILIKE '%inventory%'
  ) THEN
    ALTER TABLE public.notifications
      ADD CONSTRAINT notifications_type_check
      CHECK (type IN ('checkup_reminder', 'vaccine_reminder', 'general', 'inventory'));
  END IF;
END
$notif_type$;


-- ---------------------------------------------------------------------------
-- 1. Where a transfer came from, and which way it went
--
-- Both are derivable today - source from the batch, direction from the two
-- facilities' places in the tree - and both are stored anyway, for the same
-- reason the audit trail snapshots the actor's name: they describe the world at
-- dispatch time, and the world moves. A barangay health centre can be
-- reassigned to a different RHU next month, and a transfer issued today must
-- still read as the lateral move it was.
-- ---------------------------------------------------------------------------
ALTER TABLE public.inventory_transfers
  ADD COLUMN IF NOT EXISTS source_facility_id BIGINT
    REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS transfer_direction TEXT,
  ADD COLUMN IF NOT EXISTS cancel_reason TEXT;

COMMENT ON COLUMN public.inventory_transfers.source_facility_id IS
  'Facility the stock left. NULL means the municipal warehouse, the same convention inventory_batches.facility_id uses. Stamped at insert; never derived at read time.';
COMMENT ON COLUMN public.inventory_transfers.transfer_direction IS
  'allocation = down the hierarchy, lateral = between peers, return = up the hierarchy (spoilage rescue), external = neither end is related to the other.';
COMMENT ON COLUMN public.inventory_transfers.cancel_reason IS
  'Why a dispatch was called off. NULL unless status is cancelled.';

CREATE INDEX IF NOT EXISTS idx_inventory_transfers_source_facility
  ON public.inventory_transfers(source_facility_id, status, issued_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_transfers_direction
  ON public.inventory_transfers(transfer_direction, issued_at DESC);


-- ---------------------------------------------------------------------------
-- 2. Places, not facility ids
--
-- The municipal warehouse is one place with two spellings: batches sitting
-- there carry facility_id NULL, while a transfer addressed to it names the MHO
-- row in health_facilities. Every comparison in this file goes through
-- inventory_place_id() so those two can never be read as different shelves -
-- which is exactly the bug that let the MHO transfer to itself.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_mho_facility_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $fn$
  SELECT facility_id
    FROM public.health_facilities
   WHERE facility_type = 'MHO'
   ORDER BY facility_id
   LIMIT 1;
$fn$;

-- Canonical id for a shelf. The municipal warehouse resolves to the MHO row, so
-- NULL and that id compare equal. Everything else is itself.
CREATE OR REPLACE FUNCTION public.inventory_place_id(p_facility_id BIGINT)
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $fn$
  SELECT COALESCE(p_facility_id, public.inventory_mho_facility_id());
$fn$;

-- Where stock addressed to a facility physically lands. A dispatch to the
-- municipal office lands in the warehouse, which is facility_id NULL - the
-- rows the portal has always shown as "Central Warehouse". Without this an
-- upward RHU -> MHO transfer would create a batch filed against the MHO row
-- that the municipal portal's own depot view would never look at.
CREATE OR REPLACE FUNCTION public.inventory_stock_location_id(p_facility_id BIGINT)
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $fn$
  SELECT CASE
           WHEN p_facility_id IS NULL THEN NULL
           WHEN p_facility_id = public.inventory_mho_facility_id() THEN NULL
           ELSE p_facility_id
         END;
$fn$;

CREATE OR REPLACE FUNCTION public.inventory_same_place(p_a BIGINT, p_b BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $fn$
  SELECT public.inventory_place_id(p_a) IS NOT DISTINCT FROM public.inventory_place_id(p_b);
$fn$;

-- allocation / lateral / return / external, from the two facilities' places in
-- the tree. "return" is the one this migration exists for: a barangay health
-- centre sending vaccines up to its RHU because the freezer has no power.
CREATE OR REPLACE FUNCTION public.inventory_transfer_direction(
  p_source_facility_id BIGINT,
  p_destination_facility_id BIGINT
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_src        BIGINT := public.inventory_place_id(p_source_facility_id);
  v_dst        BIGINT := public.inventory_place_id(p_destination_facility_id);
  v_src_parent BIGINT;
  v_dst_parent BIGINT;
BEGIN
  IF v_src IS NULL OR v_dst IS NULL THEN
    RETURN 'external';
  END IF;
  IF v_src = v_dst THEN
    RETURN 'internal';
  END IF;

  SELECT parent_facility_id INTO v_src_parent
    FROM public.health_facilities WHERE facility_id = v_src;
  SELECT parent_facility_id INTO v_dst_parent
    FROM public.health_facilities WHERE facility_id = v_dst;

  -- Direct line first: parent -> child is an allocation, child -> parent a
  -- return. Checking the full subtree afterwards catches MHO -> BHC, which
  -- skips the RHU rung but is still unambiguously downward.
  IF v_dst_parent = v_src THEN RETURN 'allocation'; END IF;
  IF v_src_parent = v_dst THEN RETURN 'return';     END IF;

  IF EXISTS (SELECT 1 FROM public.facility_subtree_ids(v_src) s WHERE s.facility_id = v_dst) THEN
    RETURN 'allocation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.facility_subtree_ids(v_dst) s WHERE s.facility_id = v_src) THEN
    RETURN 'return';
  END IF;

  IF v_src_parent IS NOT NULL AND v_src_parent = v_dst_parent THEN
    RETURN 'lateral';
  END IF;

  RETURN 'external';
END
$fn$;

-- Readable form for a notification or a narrative.
CREATE OR REPLACE FUNCTION public.inventory_direction_label(p_direction TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE COALESCE(p_direction, 'external')
    WHEN 'allocation' THEN 'Allocation (downward)'
    WHEN 'lateral'    THEN 'Lateral transfer (between peers)'
    WHEN 'return'     THEN 'Return (upward)'
    WHEN 'internal'   THEN 'Same facility'
    ELSE 'Cross-branch transfer'
  END;
$fn$;


-- ---------------------------------------------------------------------------
-- 3. Stamp every transfer, whoever wrote it
--
-- A BEFORE trigger rather than a line inside issue_inventory_transfer(), so the
-- columns are correct even on a database where some other path - an older copy
-- of the RPC, a manual INSERT during a demo, a restore - creates the row. This
-- is the same reason the audit coverage in 20260826 lives in triggers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_transfer_stamp_route()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_source_facility BIGINT;
  v_resolved        BOOLEAN := false;
  v_restamp         BOOLEAN;
BEGIN
  -- OLD is unassigned on INSERT, so the two cases are tested separately rather
  -- than leaning on OR short-circuiting inside a PL/pgSQL condition.
  IF TG_OP = 'INSERT' THEN
    v_restamp := true;
  ELSE
    v_restamp := NEW.source_batch_id IS DISTINCT FROM OLD.source_batch_id;
  END IF;

  IF v_restamp THEN
    SELECT b.facility_id, true
      INTO v_source_facility, v_resolved
      FROM public.inventory_batches b
     WHERE b.batch_id = NEW.source_batch_id;

    -- A resolved NULL is the municipal warehouse and must be kept; only an
    -- unresolvable batch leaves whatever the caller supplied in place.
    IF v_resolved THEN
      NEW.source_facility_id := v_source_facility;
    END IF;
  END IF;

  NEW.transfer_direction := public.inventory_transfer_direction(
    NEW.source_facility_id, NEW.destination_facility_id);

  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_inventory_transfer_stamp_route ON public.inventory_transfers;
CREATE TRIGGER trg_inventory_transfer_stamp_route
  BEFORE INSERT OR UPDATE OF source_batch_id, destination_facility_id
  ON public.inventory_transfers
  FOR EACH ROW EXECUTE FUNCTION public.inventory_transfer_stamp_route();

-- History. The source batch is still the best answer available for rows issued
-- before the column existed; it is only unreliable for batches that have since
-- been deleted, and those are already gone from every other report too.
UPDATE public.inventory_transfers t
   SET source_facility_id = b.facility_id
  FROM public.inventory_batches b
 WHERE b.batch_id = t.source_batch_id
   AND t.source_facility_id IS NULL
   AND b.facility_id IS NOT NULL;

UPDATE public.inventory_transfers t
   SET transfer_direction = public.inventory_transfer_direction(
         t.source_facility_id, t.destination_facility_id)
 WHERE t.transfer_direction IS NULL;


-- ---------------------------------------------------------------------------
-- 4. Who may move stock
--
-- 20260818 removed the actor check from issue_inventory_transfer entirely while
-- rewriting it for inter-BHC sharing, so since then any account id at all could
-- be passed as the issuer. This restores a check without reintroducing the
-- single-role assumption that made the old one wrong under the MHO tier: a
-- portal officer may move anything inside the branch they run, and a midwife
-- may only send stock OUT OF their own barangay health centre.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_assert_may_transfer(
  p_account_id BIGINT,
  p_source_facility_id BIGINT
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_type     TEXT;
  v_actor_fc BIGINT;
  v_source   BIGINT := public.inventory_place_id(p_source_facility_id);
BEGIN
  SELECT account_type INTO v_type
    FROM public.accounts
   WHERE account_id = p_account_id AND status = 'active';

  IF v_type IS NULL THEN
    RAISE EXCEPTION 'An active account is required to move stock'
      USING ERRCODE = '42501';
  END IF;

  IF v_type NOT IN ('mho', 'admin', 'midwife') THEN
    RAISE EXCEPTION 'This account type may not move inventory'
      USING ERRCODE = '42501';
  END IF;

  v_actor_fc := public.inventory_actor_facility_id(p_account_id);

  -- An account with no facility on file is left alone rather than blocked: the
  -- seeded demo portal logins predate facility_assignments and would otherwise
  -- lose the ability to issue anything.
  IF v_actor_fc IS NULL THEN
    RETURN;
  END IF;

  IF v_type = 'midwife' THEN
    IF v_source IS DISTINCT FROM v_actor_fc THEN
      RAISE EXCEPTION 'A midwife may only send stock out of their own health centre'
        USING ERRCODE = '42501';
    END IF;
    RETURN;
  END IF;

  -- Portal officers: the source must sit inside the branch they administer.
  -- The municipal warehouse belongs to the MHO, and inventory_place_id has
  -- already resolved it to the MHO row, so the subtree test covers it.
  IF NOT EXISTS (
    SELECT 1 FROM public.facility_subtree_ids(v_actor_fc) s
     WHERE s.facility_id = v_source
  ) THEN
    RAISE EXCEPTION 'That stock sits outside the facilities this account administers'
      USING ERRCODE = '42501';
  END IF;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 5. Notification plumbing
--
-- Two helpers so every path in this file addresses a FACILITY rather than
-- guessing at a role. Who staffs a facility differs by tier - midwives at a
-- barangay health centre, portal officers at an RHU or the municipal office -
-- and the previous code encoded that guess at four separate call sites.
-- ---------------------------------------------------------------------------

-- Signatures gained p_exclude_account_id after first being written without it.
-- Dropping the old shape rather than letting CREATE OR REPLACE add an overload
-- keeps a re-run of this file from leaving two versions behind.
DROP FUNCTION IF EXISTS public.inventory_notify_facility(BIGINT, TEXT, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.inventory_notify_supervisor(BIGINT, TEXT, TEXT);

-- Everyone who works at a facility, whichever tier it belongs to. Returns the
-- number of accounts notified so a caller can tell when a facility is unstaffed.
--
-- p_exclude_account_id is who NOT to tell, and it exists because the commonest
-- movement in the system is an officer issuing stock out of their own depot.
-- Notifying the source facility of that would send the officer a message about
-- the button they just pressed, on every routine allocation. A person whose
-- notification list is mostly their own actions stops reading it, which is
-- exactly the list the lateral and return notices have to arrive in.
CREATE OR REPLACE FUNCTION public.inventory_notify_facility(
  p_facility_id BIGINT,
  p_title TEXT,
  p_message TEXT,
  p_include_portal BOOLEAN DEFAULT true,
  p_exclude_account_id BIGINT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_target  BIGINT := public.inventory_place_id(p_facility_id);
  -- Used as a plain account_id, deliberately not through
  -- resolve_actor_account_id(): that helper tries the midwife_id reading FIRST,
  -- which is right for the clinical tables that store one but wrong here. Every
  -- caller passes a column that already references accounts(account_id), and a
  -- mis-resolve would silently silence the wrong person.
  v_exclude BIGINT := p_exclude_account_id;
  v_count   INTEGER := 0;
BEGIN
  IF v_target IS NULL THEN
    RETURN 0;
  END IF;

  -- One statement covers both tiers, so an account that is somehow both a
  -- midwife and a portal assignee at the same facility is notified once rather
  -- than twice, and the count is a count of people rather than of rows matched.
  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT DISTINCT a.account_id, p_title, p_message, 'inventory'
    FROM public.accounts a
   WHERE a.status = 'active'
     AND (v_exclude IS NULL OR a.account_id <> v_exclude)
     AND (
          EXISTS (SELECT 1 FROM public.midwives m
                   WHERE m.account_id = a.account_id
                     AND m.assigned_bhc_id = v_target)
       OR (p_include_portal
           AND a.account_type IN ('admin', 'mho')
           AND EXISTS (SELECT 1 FROM public.facility_assignments fa
                        WHERE fa.account_id = a.account_id
                          AND fa.facility_id = v_target
                          AND COALESCE(fa.is_active, true)))
     );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END
$fn$;

-- The office one rung above a facility. A lateral move between two barangay
-- health centres is invisible to the RHU that supervises both unless somebody
-- tells it, and that RHU is who has to answer for the stock.
CREATE OR REPLACE FUNCTION public.inventory_notify_supervisor(
  p_facility_id BIGINT,
  p_title TEXT,
  p_message TEXT,
  p_exclude_account_id BIGINT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_parent BIGINT;
BEGIN
  SELECT parent_facility_id INTO v_parent
    FROM public.health_facilities
   WHERE facility_id = public.inventory_place_id(p_facility_id);

  IF v_parent IS NULL THEN
    RETURN 0;
  END IF;

  RETURN public.inventory_notify_facility(
    v_parent, p_title, p_message, true, p_exclude_account_id);
END
$fn$;


-- ---------------------------------------------------------------------------
-- 6. Issuing a transfer, in any direction
--
-- Same signature as before, so the portal keeps calling it unchanged. What is
-- new: the self-transfer guard compares PLACES rather than raw ids, upward and
-- lateral moves are accepted and named, the destination is checked for being
-- active, and an actor check is restored (20260818 dropped it while rewriting
-- this function for inter-BHC sharing, so since then any account id at all
-- could be passed as the issuer).
--
-- An ALREADY-EXPIRED batch is still refused in every direction. A return exists
-- so stock is used before it spoils, not after: the receiving end refuses an
-- expired batch too, so allowing the dispatch would only strand the units in
-- transit, counted at neither facility, until somebody cancelled it.
--
-- Notifications deliberately stay OUT of this function. 20260824 moved them to
-- trg_announce_inventory_transfer precisely so this 200-line body would stop
-- being rewritten, and that trigger only attaches itself when this function
-- does not write its own. Keeping that contract is why the word "notifications"
-- does not appear below.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.issue_inventory_transfer(
  p_source_batch_id BIGINT,
  p_destination_facility_id BIGINT,
  p_quantity INTEGER,
  p_issued_by BIGINT,
  p_request_id BIGINT DEFAULT NULL,
  p_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_source            public.inventory_batches%ROWTYPE;
  v_request           public.inventory_stock_requests%ROWTYPE;
  v_transfer          public.inventory_transfers%ROWTYPE;
  v_dest_name         TEXT;
  v_dest_active       BOOLEAN;
  v_src_name          TEXT;
  v_direction         TEXT;
  v_expected_quantity INTEGER;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Issue quantity must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = p_source_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source batch not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT name, COALESCE(is_active, true)
    INTO v_dest_name, v_dest_active
    FROM public.health_facilities
   WHERE facility_id = p_destination_facility_id;

  IF v_dest_name IS NULL THEN
    RAISE EXCEPTION 'Destination facility not found' USING ERRCODE = '23503';
  END IF;
  IF NOT v_dest_active THEN
    RAISE EXCEPTION '% is not an active facility and cannot receive stock', v_dest_name
      USING ERRCODE = '22023';
  END IF;

  -- The bug this replaces: the old guard was
  --   v_source.facility_id IS NOT NULL AND v_source.facility_id = destination
  -- which never fired for the depot, and never noticed that "the municipal
  -- warehouse" and "the MHO facility row" are the same shelf. Comparing places
  -- catches BHC 1 -> BHC 1 and warehouse -> MHO alike.
  IF public.inventory_same_place(v_source.facility_id, p_destination_facility_id) THEN
    RAISE EXCEPTION 'A facility cannot transfer stock to itself: % is both the source and the destination',
      COALESCE(public.audit_facility_label(v_source.facility_id), v_dest_name)
      USING ERRCODE = '22023';
  END IF;

  IF v_source.status <> 'active' THEN
    RAISE EXCEPTION 'Source batch is not active and usable'
      USING ERRCODE = '22023';
  END IF;
  IF v_source.expiration_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Source batch expired on % and cannot be transferred; dispose of it instead',
      to_char(v_source.expiration_date, 'FMDD FMMonth YYYY')
      USING ERRCODE = '22023';
  END IF;

  IF v_source.quantity_remaining < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock in source batch: only % available',
      v_source.quantity_remaining USING ERRCODE = '22023';
  END IF;

  PERFORM public.inventory_assert_may_transfer(p_issued_by, v_source.facility_id);

  v_src_name  := public.audit_facility_label(v_source.facility_id);
  v_direction := public.inventory_transfer_direction(
                   v_source.facility_id, p_destination_facility_id);

  IF p_request_id IS NOT NULL THEN
    SELECT * INTO v_request
    FROM public.inventory_stock_requests
    WHERE request_id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Linked stock request not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_request.status <> 'approved' THEN
      RAISE EXCEPTION 'Only approved requests can be issued'
        USING ERRCODE = '22023';
    END IF;
    IF v_request.facility_id <> p_destination_facility_id
       OR v_request.item_id <> v_source.item_id THEN
      RAISE EXCEPTION 'Batch item or destination does not match the stock request'
        USING ERRCODE = '22023';
    END IF;

    v_expected_quantity := COALESCE(v_request.approved_quantity,
                                    v_request.requested_quantity);

    IF p_quantity <> v_expected_quantity THEN
      RAISE EXCEPTION 'A linked request must be issued in its approved quantity (%)',
        v_expected_quantity
        USING ERRCODE = '22023';
    END IF;
  END IF;

  INSERT INTO public.inventory_transfers (
    request_id,
    source_batch_id,
    source_facility_id,
    destination_facility_id,
    quantity_issued,
    status,
    remarks,
    issued_by
  ) VALUES (
    p_request_id,
    p_source_batch_id,
    v_source.facility_id,
    p_destination_facility_id,
    p_quantity,
    'pending_receipt',
    nullif(btrim(coalesce(p_remarks, '')), ''),
    p_issued_by
  )
  RETURNING * INTO v_transfer;

  UPDATE public.inventory_batches
     SET quantity_remaining = quantity_remaining - p_quantity
   WHERE batch_id = p_source_batch_id;

  -- The ledger row names both ends. Before this it said only "Issued to Sto.
  -- Nino BHC", which read the same whether the stock was leaving this shelf or
  -- somebody else's — the row's own facility_id was the only clue, and a reader
  -- scanning a column of movements does not have it in front of them.
  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
    reference_type,
    reference_id,
    performed_by
  ) VALUES (
    p_source_batch_id,
    v_source.facility_id,
    'transfer',
    -p_quantity,
    format('%s: %s to %s - pending receipt',
           CASE v_direction
             WHEN 'return'  THEN 'Returned upward'
             WHEN 'lateral' THEN 'Lateral transfer'
             ELSE 'Issued'
           END,
           v_src_name, v_dest_name),
    v_transfer.transfer_id,
    p_issued_by
  );

  IF p_request_id IS NOT NULL THEN
    UPDATE public.inventory_stock_requests
       SET status = 'issued',
           updated_at = NOW()
     WHERE request_id = p_request_id;
  END IF;

  RETURN v_transfer;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 7. Receiving, including at the municipal warehouse
--
-- One change of substance over the 20260821 version: where the stock lands.
-- A transfer addressed to the municipal office is credited to facility_id
-- NULL, because that is what "the municipal warehouse" means everywhere else
-- in this schema. Crediting it to the MHO's health_facilities row instead
-- would file the returned stock somewhere no depot view has ever looked.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.receive_inventory_transfer(
  p_transfer_id BIGINT,
  p_received_by BIGINT
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_transfer             public.inventory_transfers%ROWTYPE;
  v_source               public.inventory_batches%ROWTYPE;
  v_destination_batch_id BIGINT;
  v_stock_location_id    BIGINT;
  v_actor_facility_id    BIGINT;
  v_item_name            TEXT;
  v_facility_name        TEXT;
  v_source_name          TEXT;
  v_direction            TEXT;
BEGIN
  v_actor_facility_id := public.inventory_actor_facility_id(p_received_by);

  IF v_actor_facility_id IS NULL THEN
    RAISE EXCEPTION 'An active midwife or portal account with an assigned facility is required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_transfer
  FROM public.inventory_transfers
  WHERE transfer_id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory transfer not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.inventory_same_place(v_transfer.destination_facility_id, v_actor_facility_id) THEN
    RAISE EXCEPTION 'This transfer belongs to another facility'
      USING ERRCODE = '42501';
  END IF;

  -- Safe retry for a slow network or an accidental double tap.
  IF v_transfer.status = 'received' THEN
    RETURN v_transfer;
  END IF;
  IF v_transfer.status <> 'pending_receipt' THEN
    RAISE EXCEPTION 'Transfer cannot be received in its current status'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = v_transfer.source_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer source batch no longer exists' USING ERRCODE = 'P0002';
  END IF;
  IF v_source.expiration_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'The issued batch expired before receipt; contact the issuing office for resolution'
      USING ERRCODE = '22023';
  END IF;

  v_source_name := public.audit_facility_label(
                     COALESCE(v_transfer.source_facility_id, v_source.facility_id));
  v_direction   := COALESCE(v_transfer.transfer_direction,
                     public.inventory_transfer_direction(
                       COALESCE(v_transfer.source_facility_id, v_source.facility_id),
                       v_transfer.destination_facility_id));

  -- Municipal office -> the warehouse rows every depot view reads.
  v_stock_location_id := public.inventory_stock_location_id(v_transfer.destination_facility_id);

  -- Serialize receipts for the same item/batch/facility so concurrent taps or
  -- multiple devices cannot create duplicate destination batches.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      v_source.item_id::text || ':' ||
      COALESCE(v_stock_location_id, 0)::text || ':' ||
      v_source.batch_number,
      0
    )
  );

  SELECT batch_id INTO v_destination_batch_id
  FROM public.inventory_batches
  WHERE item_id = v_source.item_id
    AND facility_id IS NOT DISTINCT FROM v_stock_location_id
    AND batch_number = v_source.batch_number
    AND status = 'active'
  ORDER BY batch_id
  LIMIT 1
  FOR UPDATE;

  IF v_destination_batch_id IS NULL THEN
    INSERT INTO public.inventory_batches (
      item_id, facility_id, batch_number, quantity_received, quantity_remaining,
      received_date, expiration_date, manufacturer, status
    ) VALUES (
      v_source.item_id,
      v_stock_location_id,
      v_source.batch_number,
      v_transfer.quantity_issued,
      v_transfer.quantity_issued,
      CURRENT_DATE,
      v_source.expiration_date,
      v_source.manufacturer,
      'active'
    )
    RETURNING batch_id INTO v_destination_batch_id;
  ELSE
    UPDATE public.inventory_batches
       SET quantity_received  = quantity_received + v_transfer.quantity_issued,
           quantity_remaining = quantity_remaining + v_transfer.quantity_issued
     WHERE batch_id = v_destination_batch_id;
  END IF;

  INSERT INTO public.inventory_transactions (
    batch_id, facility_id, transaction_type, quantity, reference_type, reference_id, performed_by
  ) VALUES (
    v_destination_batch_id,
    v_stock_location_id,
    'transfer',
    v_transfer.quantity_issued,
    format('%s from %s',
           CASE v_direction
             WHEN 'return'  THEN 'Returned upward'
             WHEN 'lateral' THEN 'Received laterally'
             ELSE 'Received'
           END,
           COALESCE(v_source_name, 'the issuing office')),
    v_transfer.transfer_id,
    p_received_by
  );

  UPDATE public.inventory_transfers
     SET status = 'received',
         received_by = p_received_by,
         received_at = now(),
         destination_batch_id = v_destination_batch_id
   WHERE transfer_id = p_transfer_id
  RETURNING * INTO v_transfer;

  IF v_transfer.request_id IS NOT NULL THEN
    UPDATE public.inventory_stock_requests
       SET status = 'received'
     WHERE request_id = v_transfer.request_id;
  END IF;

  SELECT i.name INTO v_item_name
    FROM public.inventory_items i
   WHERE i.item_id = v_source.item_id;

  v_facility_name := public.audit_facility_label(v_transfer.destination_facility_id);

  -- Tell the facility that sent it. Under a downward allocation that is the
  -- office running the portal, which already knew; under a lateral or upward
  -- move it is a different health centre, and this is the only confirmation it
  -- ever gets that the stock it gave up actually arrived.
  PERFORM public.inventory_notify_facility(
    COALESCE(v_transfer.source_facility_id, v_source.facility_id),
    'Transfer received',
    format('%s confirmed receipt of %s unit(s) of %s (transfer #%s).',
           v_facility_name, v_transfer.quantity_issued,
           COALESCE(v_item_name, 'stock'), p_transfer_id),
    true, p_received_by
  );

  -- And the office above the destination, so a lateral move between two
  -- barangay health centres is visible to the RHU that supervises both.
  PERFORM public.inventory_notify_supervisor(
    v_transfer.destination_facility_id,
    'Transfer received',
    format('%s confirmed receipt of %s unit(s) of %s from %s (transfer #%s).',
           v_facility_name, v_transfer.quantity_issued,
           COALESCE(v_item_name, 'stock'),
           COALESCE(v_source_name, 'another facility'), p_transfer_id),
    p_received_by
  );

  RETURN v_transfer;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 8. Announcing a dispatch to BOTH ends
--
-- Replaces the 20260826 version, which told the destination and nobody else.
-- The sending facility now gets a "stock left your shelf" notice, which is what
-- makes a lateral or upward move legible to the health centre that gave the
-- stock up - previously the units simply disappeared from its count.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.announce_inventory_transfer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_item_name   TEXT;
  v_source_id   BIGINT;
  v_source_name TEXT;
  v_dest_name   TEXT;
  v_direction   TEXT := COALESCE(NEW.transfer_direction, 'allocation');
  v_recipients  INTEGER := 0;
BEGIN
  SELECT i.name, b.facility_id
    INTO v_item_name, v_source_id
    FROM public.inventory_batches b
    JOIN public.inventory_items i ON i.item_id = b.item_id
   WHERE b.batch_id = NEW.source_batch_id;

  v_source_id   := COALESCE(NEW.source_facility_id, v_source_id);
  v_source_name := public.audit_facility_label(v_source_id);
  v_dest_name   := public.audit_facility_label(NEW.destination_facility_id);
  v_item_name   := COALESCE(v_item_name, 'stock');

  -- Destination: this is the one that has to act.
  v_recipients := public.inventory_notify_facility(
    NEW.destination_facility_id,
    CASE v_direction
      WHEN 'return' THEN 'Stock returned to you'
      ELSE 'Incoming stocks'
    END,
    format('%s unit(s) of %s from %s are waiting for your receipt confirmation.%s',
           NEW.quantity_issued, v_item_name, v_source_name,
           CASE v_direction
             WHEN 'return'  THEN ' This is a return - confirm receipt promptly so the stock is usable again.'
             WHEN 'lateral' THEN ' This came from a neighbouring facility.'
             ELSE ''
           END),
    true
  );

  -- Source: what left, and that it is not theirs any more until it is either
  -- confirmed at the other end or cancelled back.
  --
  -- Excluding the issuer is the whole difference between a useful notice and
  -- noise. On a routine allocation the source IS the office that just pressed
  -- the button, and telling them about it would put a message in the list for
  -- every dispatch they make. Colleagues at that facility still hear about it,
  -- and on a lateral or upward move — where the sending facility is not the one
  -- operating the portal — everybody there hears about it.
  PERFORM public.inventory_notify_facility(
    v_source_id,
    'Stock dispatched from your facility',
    format('%s unit(s) of %s were sent to %s (transfer #%s). They have already left your count and are awaiting confirmation at the other end.',
           NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id),
    true, NEW.issued_by
  );

  -- A move that is not a straight allocation is reported upward as well.
  IF v_direction IN ('lateral', 'external') THEN
    PERFORM public.inventory_notify_supervisor(
      v_source_id,
      'Facilities moved stock between themselves',
      format('%s sent %s unit(s) of %s to %s (transfer #%s).',
             v_source_name, NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id),
      NEW.issued_by
    );
  END IF;

  -- Nobody at all is assigned to the destination. The stock is sitting in
  -- transit against a facility with no staff to confirm it, which is a stuck
  -- transfer waiting to happen, so the office above it is told instead.
  --
  -- Nobody is excluded here, issuer included: this one says the dispatch they
  -- just made cannot be received by anyone, which is precisely the thing they
  -- need to hear back about their own action.
  IF v_recipients = 0 THEN
    PERFORM public.inventory_notify_supervisor(
      NEW.destination_facility_id,
      'Incoming stocks have nobody to receive them',
      format('%s unit(s) of %s were sent to %s (transfer #%s), but no active account is assigned to that facility to confirm receipt.',
             NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id)
    );
  END IF;

  -- The audit row for this event is written by trg_audit_inventory_transfer.
  RETURN NULL;
END
$fn$;

-- 20260824 attached this conditionally, on whether the installed
-- issue_inventory_transfer wrote its own notification. The version in section 5
-- deliberately does not, so the trigger is attached outright here.
DROP TRIGGER IF EXISTS trg_announce_inventory_transfer ON public.inventory_transfers;
CREATE TRIGGER trg_announce_inventory_transfer
  AFTER INSERT ON public.inventory_transfers
  FOR EACH ROW EXECUTE FUNCTION public.announce_inventory_transfer();


-- ---------------------------------------------------------------------------
-- 9. Cancelling a dispatch, atomically
--
-- The portal did this in two unrelated writes - flip the status, then read the
-- batch and add the quantity back - with no transaction around them and no
-- ledger row at all. A failure between the two left stock destroyed; a
-- successful pair still left the movement ledger showing an issue with no
-- return, which is the one place an auditor looks.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_inventory_transfer(
  p_transfer_id BIGINT,
  p_cancelled_by BIGINT,
  p_reason TEXT DEFAULT NULL
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_transfer  public.inventory_transfers%ROWTYPE;
  v_source    public.inventory_batches%ROWTYPE;
  v_item_name TEXT;
  v_reason    TEXT := nullif(btrim(coalesce(p_reason, '')), '');
  v_src_name  TEXT;
  v_dest_name TEXT;
BEGIN
  SELECT * INTO v_transfer
  FROM public.inventory_transfers
  WHERE transfer_id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory transfer not found' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotent for a double tap, the same way receiving is.
  IF v_transfer.status = 'cancelled' THEN
    RETURN v_transfer;
  END IF;
  IF v_transfer.status <> 'pending_receipt' THEN
    RAISE EXCEPTION 'Only a transfer still awaiting receipt can be cancelled'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = v_transfer.source_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The source batch no longer exists, so this stock cannot be returned to it'
      USING ERRCODE = 'P0002';
  END IF;

  PERFORM public.inventory_assert_may_transfer(
    p_cancelled_by, COALESCE(v_transfer.source_facility_id, v_source.facility_id));

  UPDATE public.inventory_batches
     SET quantity_remaining = quantity_remaining + v_transfer.quantity_issued
   WHERE batch_id = v_transfer.source_batch_id;

  UPDATE public.inventory_transfers
     SET status = 'cancelled',
         cancelled_by = p_cancelled_by,
         cancelled_at = now(),
         cancel_reason = v_reason
   WHERE transfer_id = p_transfer_id
  RETURNING * INTO v_transfer;

  IF v_transfer.request_id IS NOT NULL THEN
    UPDATE public.inventory_stock_requests
       SET status = 'approved',
           updated_at = now()
     WHERE request_id = v_transfer.request_id
       AND status = 'issued';
  END IF;

  SELECT name INTO v_item_name FROM public.inventory_items WHERE item_id = v_source.item_id;
  v_src_name  := public.audit_facility_label(
                   COALESCE(v_transfer.source_facility_id, v_source.facility_id));
  v_dest_name := public.audit_facility_label(v_transfer.destination_facility_id);

  -- The reversing ledger row. Without it the movement history reads as a
  -- one-way loss forever.
  INSERT INTO public.inventory_transactions (
    batch_id, facility_id, transaction_type, quantity,
    reference_type, reference_id, performed_by
  ) VALUES (
    v_transfer.source_batch_id,
    COALESCE(v_transfer.source_facility_id, v_source.facility_id),
    'transfer',
    v_transfer.quantity_issued,
    format('Transfer #%s to %s cancelled - stock returned to shelf%s',
           p_transfer_id, v_dest_name,
           COALESCE(' (' || v_reason || ')', '')),
    p_transfer_id,
    p_cancelled_by
  );

  -- Both ends, minus whoever pressed cancel.
  PERFORM public.inventory_notify_facility(
    v_transfer.destination_facility_id,
    'Incoming transfer cancelled',
    format('Transfer #%s (%s unit(s) of %s from %s) was cancelled and is no longer on its way.%s',
           p_transfer_id, v_transfer.quantity_issued, COALESCE(v_item_name, 'stock'),
           v_src_name, COALESCE(' Reason: ' || v_reason || '.', '')),
    true, p_cancelled_by
  );

  PERFORM public.inventory_notify_facility(
    COALESCE(v_transfer.source_facility_id, v_source.facility_id),
    'Dispatch cancelled - stock returned',
    format('Transfer #%s to %s was cancelled. %s unit(s) of %s are back on your shelf.%s',
           p_transfer_id, v_dest_name, v_transfer.quantity_issued,
           COALESCE(v_item_name, 'stock'),
           COALESCE(' Reason: ' || v_reason || '.', '')),
    true, p_cancelled_by
  );

  RETURN v_transfer;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 9b. Re-planning a delivery
--
-- Two things were wrong with the 20260806 version, and both only became
-- visible once stock could move in more than one direction:
--
--   (1) It asserts the actor is account_type 'admin' exactly. Under the MHO
--       tier a municipal officer is 'mho', so the one account responsible for
--       every MHO -> RHU dispatch could not re-plan any of them.
--   (2) It notified midwives at the destination and nobody else. An RHU
--       destination has no midwives, so a re-planned municipal delivery told
--       nobody at all; and the SENDING facility — which on a lateral or upward
--       move is a different health centre — was never told either.
--
-- Everything else is carried over unchanged, including the remarks format the
-- audit trigger and the portal both parse.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_inventory_transfer_delivery(
  p_transfer_id BIGINT,
  p_expected_arrival_date DATE,
  p_situation TEXT,
  p_note TEXT,
  p_updated_by BIGINT
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_before          public.inventory_transfers%ROWTYPE;
  v_after           public.inventory_transfers%ROWTYPE;
  v_source          public.inventory_batches%ROWTYPE;
  v_item_name       TEXT;
  v_dest_name       TEXT;
  v_source_name     TEXT;
  v_situation       TEXT := lower(btrim(coalesce(p_situation, '')));
  v_situation_label TEXT;
  v_note            TEXT;
  v_reference       TEXT;
  v_delivery_plan   TEXT;
  v_delivery_update TEXT;
  v_plan_days       INTEGER;
  v_shelf_days      INTEGER;
  v_message         TEXT;
BEGIN
  IF p_expected_arrival_date IS NULL OR p_expected_arrival_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Expected arrival must be today or a future date'
      USING ERRCODE = '22023';
  END IF;

  IF v_situation NOT IN (
    'on_schedule', 'delayed', 'rescheduled',
    'transport_issue', 'facility_coordination', 'other'
  ) THEN
    RAISE EXCEPTION 'Select a valid delivery situation' USING ERRCODE = '22023';
  END IF;

  IF char_length(btrim(coalesce(p_note, ''))) > 500 THEN
    RAISE EXCEPTION 'Delivery note must be 500 characters or fewer'
      USING ERRCODE = '22023';
  END IF;

  -- Keep notification and audit text compact even if a textarea contains
  -- multiple lines or repeated spaces.
  v_note := nullif(
    regexp_replace(btrim(coalesce(p_note, '')), '[[:space:]]+', ' ', 'g'), '');

  SELECT * INTO v_before
  FROM public.inventory_transfers
  WHERE transfer_id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory transfer not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_before.status <> 'pending_receipt' THEN
    RAISE EXCEPTION 'Only a transfer awaiting receipt can be updated'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = v_before.source_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer source batch no longer exists' USING ERRCODE = 'P0002';
  END IF;

  -- The same rule as issuing: whoever administers the branch the stock left may
  -- speak for the delivery. This is what replaces the 'admin'-only assertion.
  PERFORM public.inventory_assert_may_transfer(
    p_updated_by, COALESCE(v_before.source_facility_id, v_source.facility_id));

  v_plan_days  := GREATEST(0, p_expected_arrival_date - v_before.issued_at::date);
  v_shelf_days := v_source.expiration_date - p_expected_arrival_date;

  IF (v_situation <> 'on_schedule' OR v_shelf_days <= 0) AND v_note IS NULL THEN
    RAISE EXCEPTION 'Add a note explaining this delivery change'
      USING ERRCODE = '22023';
  END IF;

  v_situation_label := CASE v_situation
    WHEN 'on_schedule'          THEN 'On schedule'
    WHEN 'delayed'              THEN 'Delayed'
    WHEN 'rescheduled'          THEN 'Rescheduled'
    WHEN 'transport_issue'      THEN 'Transport issue'
    WHEN 'facility_coordination' THEN 'Facility coordination'
    ELSE 'Other situation'
  END;

  -- Strip this function's own previous plan and update lines, keeping whatever
  -- the operator typed when the stock was sent. The portal's own "Expected
  -- delivery:" line is deliberately left alone: it is the original promise, and
  -- the portal prefers the re-planned date over it when both are present.
  v_reference := regexp_replace(
    coalesce(v_before.remarks, ''),
    E'Delivery plan:[[:space:]]*expected[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*\\([0-9]+-day estimate\\)(;[[:space:]]*batch expires[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2};[[:space:]]*-?[0-9]+[[:space:]]*days? of shelf life at arrival)?\\.?',
    '', 'gi');
  v_reference := regexp_replace(v_reference, '[[:space:]]*Delivery update:.*$', '', 'i');
  v_reference := nullif(btrim(v_reference), '');

  v_delivery_plan := format(
    'Delivery plan: expected %s (%s-day estimate); batch expires %s; %s day%s of shelf life at arrival.',
    p_expected_arrival_date, v_plan_days, v_source.expiration_date, v_shelf_days,
    CASE WHEN abs(v_shelf_days) = 1 THEN '' ELSE 's' END);

  v_delivery_update := format('Delivery update: %s on %s. %s',
    v_situation_label, CURRENT_DATE,
    coalesce(v_note, 'Expected arrival confirmed.'));

  UPDATE public.inventory_transfers
     SET remarks = concat_ws(E'\n', v_reference, v_delivery_plan, v_delivery_update)
   WHERE transfer_id = p_transfer_id
  RETURNING * INTO v_after;

  SELECT name INTO v_item_name FROM public.inventory_items WHERE item_id = v_source.item_id;
  v_dest_name   := public.audit_facility_label(v_before.destination_facility_id);
  v_source_name := public.audit_facility_label(
                     COALESCE(v_before.source_facility_id, v_source.facility_id));

  v_message := format('Transfer #%s for %s is now expected on %s. %s%s',
    p_transfer_id, coalesce(v_item_name, 'inventory stock'), p_expected_arrival_date,
    v_situation_label,
    CASE WHEN v_note IS NULL THEN '.' ELSE ': ' || v_note END);

  -- Whoever staffs the destination, at whatever tier — and the sender, who is a
  -- different facility whenever this is not a straight allocation. Not the
  -- officer who just typed the new date.
  PERFORM public.inventory_notify_facility(
    v_before.destination_facility_id, 'Delivery plan updated', v_message,
    true, p_updated_by);
  PERFORM public.inventory_notify_facility(
    COALESCE(v_before.source_facility_id, v_source.facility_id),
    'Delivery plan updated',
    format('%s Destination: %s.', v_message, v_dest_name),
    true, p_updated_by);

  -- The audit row for this event is written by trg_audit_inventory_transfer,
  -- which detects the re-plan from the remarks it just wrote. 20260806 wrote its
  -- own row here; that is now the redundant one, and audit_trail_enrich folds it
  -- away, so it is simply not written.
  RETURN v_after;
END
$fn$;

COMMENT ON FUNCTION public.update_inventory_transfer_delivery(
  BIGINT, DATE, TEXT, TEXT, BIGINT
) IS 'Re-plan the expected arrival of an in-transit transfer. Open to any portal account that administers the branch the stock left, and notifies both ends.';


-- ---------------------------------------------------------------------------
-- 10. Notification typing
--
-- tag_inventory_notification matches on title. The titles this file introduces
-- are added to its list so the mobile notification centre files them under
-- Inventory rather than as clinical reminders. The inserts above already set
-- type explicitly; this is for anything that reaches the table another way.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tag_inventory_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF NEW.type IS DISTINCT FROM 'inventory'
     AND lower(coalesce(NEW.title, '')) IN (
       'new stock request',
       'stock request approved',
       'stock request update',
       'incoming stocks from rhu main',
       'incoming stocks',
       'low stock after activity',
       'stock returned to you',
       'stock dispatched from your facility',
       'transfer received',
       'incoming transfer cancelled',
       'dispatch cancelled - stock returned',
       'facilities moved stock between themselves',
       'incoming stocks have nobody to receive them',
       'delivery plan updated'
     )
  THEN
    NEW.type := 'inventory';
  END IF;
  RETURN NEW;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 11. The audit narrative learns which way the stock went
--
-- Wraps rather than replaces the 20260826 trigger body: everything it recorded
-- is still recorded, plus the route, the direction, and - for a return - the
-- reason a facility would send stock upward at all, which is the fact an
-- auditor reading a spoilage incident actually needs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_transfer_route_rows(
  p_source_facility_id BIGINT,
  p_destination_facility_id BIGINT,
  p_direction TEXT
)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $fn$
  SELECT public.audit_kv('Direction', public.inventory_direction_label(p_direction))
      || public.audit_kv('Route',
           public.audit_facility_label(p_source_facility_id) || '  ->  ' ||
           public.audit_facility_label(p_destination_facility_id))
      || public.audit_kv('Why this direction is allowed',
           CASE p_direction
             WHEN 'return'
               THEN 'Stock moving up the hierarchy is a spoilage rescue - power interruption, cold-chain failure or a facility that cannot use it before expiry.'
             WHEN 'lateral'
               THEN 'Peer facilities may share stock directly; the supervising office is notified rather than asked to approve.'
             WHEN 'external'
               THEN 'Neither facility sits in the other''s branch. Recorded, but worth a second look.'
             ELSE NULL
           END);
$fn$;

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
  v_src_fac    BIGINT;
  v_direction  TEXT;
  v_dir_label  TEXT;
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
  v_src_fac   := COALESCE(NEW.source_facility_id, (v_src->>'facility_id')::bigint);
  v_direction := COALESCE(NEW.transfer_direction,
                   public.inventory_transfer_direction(v_src_fac, NEW.destination_facility_id));
  v_dir_label := public.inventory_direction_label(v_direction);

  v_item := COALESCE(v_src->>'item_name', 'Stock item');
  v_unit := COALESCE(v_src->>'unit', 'unit');
  v_from := public.audit_facility_label(v_src_fac);
  v_to   := public.audit_facility_label(NEW.destination_facility_id);
  v_doses := NEW.quantity_issued * GREATEST(1, COALESCE((v_src->>'doses_per_unit')::int, 1));
  v_entity := format('Transfer #%s - %s', NEW.transfer_id, public.audit_batch_label(v_src));

  IF NEW.request_id IS NOT NULL THEN
    SELECT * INTO v_req FROM public.inventory_stock_requests WHERE request_id = NEW.request_id;
  END IF;

  -- There is no expected_arrival_date COLUMN anywhere in this schema.
  -- update_inventory_transfer_delivery() (20260806) takes the date as a
  -- parameter and folds the whole plan into inventory_transfers.remarks as two
  -- text lines, so the re-plan is detected on remarks and its facts are read
  -- back out of that text.
  v_plan_new := substring(COALESCE(NEW.remarks, '')
                          from 'Delivery plan: expected ([0-9]{4}-[0-9]{2}-[0-9]{2})');
  IF TG_OP = 'UPDATE' THEN
    v_plan_old := substring(COALESCE(OLD.remarks, '')
                            from 'Delivery plan: expected ([0-9]{4}-[0-9]{2}-[0-9]{2})');
  END IF;

  -- Shared "where it came from / where it is going" block.
  v_rows := public.audit_kv('Transfer number', '#' || NEW.transfer_id)
         || public.audit_kv('Item', v_item)
         || public.audit_transfer_route_rows(v_src_fac, NEW.destination_facility_id, v_direction)
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
      || public.audit_kv('Against stock request',
           CASE v_direction
             WHEN 'return'  THEN 'None - a return is initiated by the sending facility, not requested by the receiver'
             WHEN 'lateral' THEN 'None - peer facilities share stock without a formal request'
             ELSE 'None - issued at the administrator''s discretion'
           END);
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_actor  := NEW.issued_by;
    v_action := CASE v_direction
                  WHEN 'return'  THEN 'return_inventory_transfer'
                  WHEN 'lateral' THEN 'lateral_inventory_transfer'
                  ELSE 'issue_inventory_transfer'
                END;
    v_summary := format('%s: %s of %s from %s to %s',
                        v_dir_label, public.audit_qty(NEW.quantity_issued, v_unit),
                        v_item, v_from, v_to);
    v_narrative := format(
      'Stock was DISPATCHED (%s). %s of %s was taken out of batch %s at %s and sent to %s under transfer #%s, issued by %s on %s. '
      'The source batch was debited immediately; the destination is NOT credited until somebody at %s confirms receipt, so '
      'these units are currently in transit and counted at neither end. %s%s%s%s',
      lower(v_dir_label),
      public.audit_qty(NEW.quantity_issued, v_unit),
      v_item,
      COALESCE(v_src->>'batch_number', 'an unrecorded batch'),
      v_from, v_to, NEW.transfer_id,
      (public.audit_actor(NEW.issued_by))->>'name',
      public.audit_ts(NEW.issued_at),
      v_to,
      CASE v_direction
        WHEN 'return'  THEN format('This is a RETURN: %s sits below %s in the hierarchy, so stock is travelling back up. Returns are used when a facility cannot keep stock safely - a power interruption, a cold-chain failure, or stock it will not use before expiry - and the point of them is to have the units used somewhere rather than disposed of. ', v_from, v_to)
        WHEN 'lateral' THEN format('This is a LATERAL move between peer facilities: %s and %s report to the same office, which is notified rather than asked to approve. ', v_from, v_to)
        WHEN 'external' THEN 'Neither facility sits inside the other''s branch, which is unusual enough to be worth checking. '
        ELSE ''
      END,
      CASE WHEN v_req.request_id IS NOT NULL
           THEN format('This dispatch settles stock request #%s, which asked for %s and was approved for %s by %s on %s. ',
                       v_req.request_id,
                       public.audit_qty(v_req.requested_quantity, v_unit),
                       public.audit_qty(COALESCE(v_req.approved_quantity, v_req.requested_quantity), v_unit),
                       (public.audit_actor(v_req.reviewed_by))->>'name',
                       public.audit_ts(v_req.reviewed_at))
           ELSE 'No stock request is linked. ' END,
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
        'Stock ARRIVED and was confirmed. %s at %s confirmed receipt of transfer #%s on %s: %s of %s, dispatched from %s on %s as %s. '
        'The units were credited to batch %s at the receiving facility%s. %s The chain for these units is now complete: '
        'requested %s, approved %s, dispatched %s, received %s.',
        COALESCE((public.audit_actor(NEW.received_by))->>'name', 'A staff member'),
        v_to, NEW.transfer_id, public.audit_ts(NEW.received_at),
        public.audit_qty(NEW.quantity_issued, v_unit), v_item, v_from, public.audit_ts(NEW.issued_at),
        lower(v_dir_label),
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
             || public.audit_kv('Credited at', public.audit_facility_label((v_dst->>'facility_id')::bigint))
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
        'The units never reached %s; they are returned to batch %s at %s and are available there again. %s'
        'Anything counting this stock as en route should stop doing so from this point.',
        NEW.transfer_id, public.audit_qty(NEW.quantity_issued, v_unit), v_item, v_from, v_to,
        public.audit_ts(NEW.issued_at),
        COALESCE((public.audit_actor(NEW.cancelled_by))->>'name', 'an unrecorded account'),
        public.audit_ts(v_cancelled),
        v_to, COALESCE(v_src->>'batch_number', 'its source batch'), v_from,
        COALESCE('Reason given: "' || NEW.cancel_reason || '". ', '')
      );
      v_rows := v_rows
             || public.audit_kv('Cancelled by', (public.audit_actor(NEW.cancelled_by))->>'name')
             || public.audit_kv('Cancelled on', public.audit_ts(v_cancelled))
             || public.audit_kv('Reason for cancellation', NEW.cancel_reason)
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
      'source_facility_id', v_src_fac,
      'destination_facility_id', NEW.destination_facility_id,
      'transfer_direction', v_direction,
      'issued_by', NEW.issued_by, 'received_by', NEW.received_by,
      'cancelled_by', NEW.cancelled_by),
    CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END,
    to_jsonb(NEW), NULL, NEW.status
  );

  RETURN NULL;
END
$fn$;



-- ---------------------------------------------------------------------------
-- 12. Grants
-- ---------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.inventory_mho_facility_id()                      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.inventory_place_id(BIGINT)                       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.inventory_stock_location_id(BIGINT)              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.inventory_same_place(BIGINT, BIGINT)             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.inventory_transfer_direction(BIGINT, BIGINT)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.inventory_direction_label(TEXT)                  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.inventory_transfer_stamp_route()                 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.announce_inventory_transfer()                    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tag_inventory_notification()                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_transfer_route_rows(BIGINT, BIGINT, TEXT)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_inventory_transfer()                       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.issue_inventory_transfer(BIGINT, BIGINT, INTEGER, BIGINT, BIGINT, TEXT)
  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.receive_inventory_transfer(BIGINT, BIGINT)       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_inventory_transfer(BIGINT, BIGINT, TEXT)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_inventory_transfer_delivery(BIGINT, DATE, TEXT, TEXT, BIGINT)
  TO anon, authenticated;

-- These three are authorization and plumbing helpers, not client calls.
REVOKE ALL ON FUNCTION public.inventory_assert_may_transfer(BIGINT, BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.inventory_notify_facility(BIGINT, TEXT, TEXT, BOOLEAN, BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.inventory_notify_supervisor(BIGINT, TEXT, TEXT, BIGINT) FROM PUBLIC;

COMMIT;


-- ---------------------------------------------------------------------------
-- 13. Verification
--
-- Every transfer now names both ends and which way it went:
--
--   SELECT transfer_id, transfer_direction,
--          public.audit_facility_label(source_facility_id)      AS moved_from,
--          public.audit_facility_label(destination_facility_id) AS moved_to,
--          quantity_issued, status
--     FROM public.inventory_transfers
--    ORDER BY transfer_id DESC LIMIT 20;
--
-- Nothing should be left unclassified, and nothing should read 'internal' -
-- that value only exists so the self-transfer guard has something to name:
--
--   SELECT transfer_direction, count(*)
--     FROM public.inventory_transfers GROUP BY 1 ORDER BY 1;
--
-- A self-transfer must now be refused. Against any active batch:
--
--   SELECT public.issue_inventory_transfer(
--            <batch at facility X>, <facility X>, 1, <account>, NULL, 'should fail');
--
-- Expect: "A facility cannot transfer stock to itself".
--
-- After issuing a lateral BHC -> BHC move, both ends should have been told:
--
--   SELECT n.title, n.message, a.account_type, a.first_name
--     FROM public.notifications n
--     JOIN public.accounts a ON a.account_id = n.account_id
--    ORDER BY n.notification_id DESC LIMIT 10;
--
-- Expect one "Incoming stocks" at the destination, one "Stock dispatched from
-- your facility" at the source, and one supervisor notice at the RHU above.
--
-- NOT EXPECTED, AND NOT A BUG: a notification addressed to the account that
-- performed the action. Every notify call here except the destination one and
-- the unstaffed-destination warning passes the actor as p_exclude_account_id.
-- Without that, an officer issuing a routine allocation out of their own depot
-- would be notified about the button they had just pressed, on every dispatch —
-- and a list that is mostly your own actions is a list nobody reads, which is
-- the same list the lateral and return notices have to arrive in. Colleagues at
-- the same facility are still told. Confirm with:
--
--   SELECT n.title, n.account_id, t.issued_by
--     FROM public.notifications n
--     JOIN public.inventory_transfers t
--       ON n.message LIKE '%transfer #' || t.transfer_id || '%'
--    WHERE n.account_id = t.issued_by
--      AND n.title = 'Stock dispatched from your facility';
--
-- Expect zero rows.
-- ---------------------------------------------------------------------------
