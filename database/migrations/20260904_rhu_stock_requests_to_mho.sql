-- ==============================================================================
-- MIGRATION: 20260904_rhu_stock_requests_to_mho.sql
--
-- Lets a Rural Health Unit ask the Municipal Health Office for stock, the same
-- way a barangay health centre already asks its RHU, and lets the MHO act on
-- what it is asked.
--
-- WHAT WAS ALREADY THERE
--
--   Most of it. inventory_stock_requests.facility_id has always meant "the
--   facility doing the asking", with no tier baked in; inventory_transfers has
--   carried source and destination since 20260829, which classifies MHO -> RHU
--   as a first-class allocation; issue_inventory_transfer guards with
--   inventory_assert_may_transfer, which already accepts 'mho'; and the portal
--   builds its "Deliver it to" list from PortalScope.childFacilities, which for
--   a municipal officer is the Rural Health Units.
--
--   Two role gates were all that stood in the way, and they are the whole of
--   this migration.
--
--  (1) ONLY A MIDWIFE COULD ASK FOR STOCK
--      submit_inventory_stock_request opened with
--      inventory_assert_actor(p_requested_by, 'midwife') and resolved the
--      facility with inventory_midwife_facility_id. An RHU administrator is
--      account_type 'admin', so the call raised 42501 before it read its
--      arguments. There was no way for an RHU to ask the MHO for anything.
--
--      The actor may now be a midwife, an RHU administrator or a municipal
--      officer, and the facility comes from inventory_actor_facility_id, which
--      has resolved all three tiers since 20260821. A request travels upward,
--      so the requesting facility needs an office above it: a BHC has its RHU,
--      an RHU has the MHO, and the MHO has nobody -- now a clear error rather
--      than a request addressed to no one.
--
--  (2) ONLY AN 'admin' COULD APPROVE OR REJECT
--      approve_inventory_stock_request, its _with_quantity successor and
--      reject_inventory_stock_request all assert account_type = 'admin'
--      exactly. A municipal officer is 'mho', so the one office that RHU
--      requests are addressed to could not act on them -- the same defect
--      20260829 fixed for update_inventory_transfer_delivery.
--
--      Rather than restate four function bodies here and leave four more copies
--      to drift, inventory_assert_actor itself now treats a requirement of
--      'admin' as satisfied by 'mho'. Under the MHO tier a municipal officer
--      sits above an RHU administrator, so every guard that accepts one should
--      accept the other. Requirements of 'midwife' are untouched.
--
-- ALSO: submit_inventory_stock_request hand-wrote an audit_trail row. 20260826
-- put trg_audit_inventory_stock_request on that table, so every submission has
-- been audited twice since. The hand-written INSERT is gone; the trigger writes
-- the fuller of the two.
--
-- AND (3) A FACILITY COULD DECIDE ITS OWN REQUEST
--      None of the approve or reject functions check that the reviewer's office
--      is the one the request was addressed to. That was harmless while only a
--      facility below could raise one -- an RHU administrator has no account at
--      a barangay health centre. Letting an RHU raise its own request makes it
--      reachable: the portal shows every request inside PortalScope, so an RHU
--      sees the one it sent the municipal office, and nothing in the database
--      stopped it approving and issuing against it.
--
--      Guarded here with a trigger rather than by restating three function
--      bodies, for the same reason as (2). It fires only on the transition out
--      of 'pending', so it costs nothing on any other write, and it skips the
--      check when the actor's facility cannot be resolved -- a database without
--      20260821_mho_tier.sql behaves exactly as before.
--
--      Still open, and wider than this: any active administrator may decide any
--      OTHER facility's request, not merely its own children's. Closing that
--      means resolving the requesting facility's parent and requiring the actor
--      to be assigned to it. Worth doing; it is a bigger change than this one
--      and does not block the feature.
--
-- Requires 20260821_mho_tier.sql (inventory_actor_facility_id, the 'mho'
-- account type) and 20260826_audit_trail_completeness.sql.
--
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. A requirement of 'admin' is satisfied by 'mho'.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_assert_actor(
  p_account_id BIGINT,
  p_required_role TEXT
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM public.accounts
     WHERE account_id = p_account_id
       AND status = 'active'
       AND (
         account_type = p_required_role
         -- A municipal officer outranks an RHU administrator. Every guard that
         -- was written to mean "an office that administers stock" predates the
         -- MHO tier and spelled that 'admin'.
         OR (p_required_role = 'admin' AND account_type = 'mho')
       )
  ) THEN
    RAISE EXCEPTION 'Active % account required', p_required_role
      USING ERRCODE = '42501';
  END IF;
END;
$fn$;


-- ---------------------------------------------------------------------------
-- 2. Any tier with an office above it may ask that office for stock.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_inventory_stock_request(
  p_requested_by BIGINT,
  p_item_id BIGINT,
  p_requested_quantity INTEGER,
  p_reason TEXT,
  p_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_type          TEXT;
  v_facility_id   BIGINT;
  v_facility_name TEXT;
  v_parent_id     BIGINT;
  v_request       public.inventory_stock_requests%ROWTYPE;
  v_item_name     TEXT;
BEGIN
  SELECT account_type INTO v_type
    FROM public.accounts
   WHERE account_id = p_requested_by AND status = 'active';

  IF v_type IS NULL OR v_type NOT IN ('midwife', 'admin', 'mho') THEN
    RAISE EXCEPTION 'An active midwife, RHU or municipal account is required to request stock'
      USING ERRCODE = '42501';
  END IF;

  v_facility_id := public.inventory_actor_facility_id(p_requested_by);
  IF v_facility_id IS NULL THEN
    RAISE EXCEPTION 'This account has no facility assignment, so it has no shelf to request stock onto'
      USING ERRCODE = '23503';
  END IF;

  IF p_requested_quantity IS NULL OR p_requested_quantity <= 0 THEN
    RAISE EXCEPTION 'Requested quantity must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Request reason is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT name INTO v_item_name FROM public.inventory_items WHERE item_id = p_item_id;
  IF v_item_name IS NULL THEN
    RAISE EXCEPTION 'Inventory item not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT name, parent_facility_id
    INTO v_facility_name, v_parent_id
    FROM public.health_facilities
   WHERE facility_id = v_facility_id;

  -- A request travels upward. A BHC has its RHU and an RHU has the municipal
  -- office; the municipal office has nobody above it and cannot request from
  -- itself. Checked only for 'mho', so a database that has not run
  -- 20260821_mho_tier.sql -- where parent_facility_id is null everywhere --
  -- keeps its old behaviour of notifying every administrator.
  IF v_parent_id IS NULL AND v_type = 'mho' THEN
    RAISE EXCEPTION
      '% is the highest office in the municipality and has nowhere to request stock from. Record a receipt instead.',
      COALESCE(v_facility_name, 'This office')
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.inventory_stock_requests (
    facility_id, item_id, requested_quantity, reason, remarks, status, requested_by
  ) VALUES (
    v_facility_id,
    p_item_id,
    p_requested_quantity,
    btrim(p_reason),
    nullif(btrim(coalesce(p_remarks, '')), ''),
    'pending',
    p_requested_by
  )
  RETURNING * INTO v_request;

  -- Addressed to the office above when one is recorded; to every administrator
  -- otherwise, which is what this did before the hierarchy existed.
  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT a.account_id,
         'New stock request',
         format('%s requested %s units of %s.',
                COALESCE(v_facility_name, 'A facility'), p_requested_quantity, v_item_name),
         'general'
    FROM public.accounts a
   WHERE a.status = 'active'
     AND a.account_type IN ('admin', 'mho')
     AND (
       v_parent_id IS NULL
       OR EXISTS (
         SELECT 1 FROM public.facility_assignments fa
          WHERE fa.account_id = a.account_id
            AND fa.facility_id = v_parent_id
            AND COALESCE(fa.is_active, true)
       )
     );

  -- No audit_trail INSERT here. trg_audit_inventory_stock_request (20260826)
  -- writes a fuller row from the inserted record; the hand-written one was a
  -- duplicate of it.

  RETURN v_request;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.submit_inventory_stock_request(BIGINT, BIGINT, INTEGER, TEXT, TEXT)
  TO anon, authenticated;

COMMENT ON FUNCTION public.submit_inventory_stock_request(BIGINT, BIGINT, INTEGER, TEXT, TEXT) IS
  'Raises a pending stock request from the actor''s own facility to the office above it: '
  'BHC -> RHU, or RHU -> Municipal Health Office. Notifies the accounts assigned to that office.';


-- ---------------------------------------------------------------------------
-- 3. No office decides its own request.
--
-- approve_inventory_stock_request, its _with_quantity successor and
-- reject_inventory_stock_request all stamp reviewed_by and move status off
-- 'pending'. Catching it here covers all three, and any future writer, without
-- copying a line of them.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_stock_request_block_self_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_actor_facility BIGINT;
  v_facility_name  TEXT;
BEGIN
  -- Only the moment a decision is recorded.
  IF OLD.status IS DISTINCT FROM 'pending'
     OR NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.reviewed_by IS NULL THEN
    RETURN NEW;
  END IF;

  v_actor_facility := public.inventory_actor_facility_id(NEW.reviewed_by);

  -- Unresolvable actor: a database without the hierarchy. Leave it alone rather
  -- than block a workflow that worked before this migration.
  IF v_actor_facility IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_actor_facility = NEW.facility_id THEN
    SELECT name INTO v_facility_name
      FROM public.health_facilities WHERE facility_id = NEW.facility_id;

    RAISE EXCEPTION
      'Request #% was raised by % and cannot be decided there. It is for the office above to approve or reject.',
      NEW.request_id, COALESCE(v_facility_name, 'this office')
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_stock_request_block_self_review
  ON public.inventory_stock_requests;

CREATE TRIGGER trg_stock_request_block_self_review
  BEFORE UPDATE ON public.inventory_stock_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.inventory_stock_request_block_self_review();
