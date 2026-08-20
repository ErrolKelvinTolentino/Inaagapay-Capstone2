-- ==============================================================================
-- MIGRATION: 20260821_mho_tier.sql
--
-- Adds the Municipal Health Office tier above the Rural Health Units:
--
--     Municipal Health Office (admin web)
--       -> RHU I .. RHU IV        (admin web, one portal account per RHU)
--            -> Barangay Health Centres (midwife mobile app)
--
-- Nothing about how stock moves changes. issue_inventory_transfer already
-- accepts any source batch and any destination facility, so the same engine
-- that moved stock RHU -> BHC now also moves it MHO -> RHU. What this migration
-- adds is the shape of the hierarchy, the scoping rules that follow from it,
-- and a receive path for RHU administrators.
--
-- WHERE STOCK LIVES AFTER THIS MIGRATION
--   inventory_batches.facility_id IS NULL  ->  the MHO municipal warehouse.
--     This is exactly what the portal already called "Central Warehouse", so no
--     existing batch moves and no existing quantity changes. DOH and supplier
--     deliveries still land here; the MHO now allocates them down to the RHUs.
--   inventory_batches.facility_id = <RHU>  ->  that RHU's own depot.
--   inventory_batches.facility_id = <BHC>  ->  that barangay health centre.
--
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. Facility hierarchy
-- ---------------------------------------------------------------------------
ALTER TABLE public.health_facilities
  ADD COLUMN IF NOT EXISTS parent_facility_id BIGINT
    REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS facility_code VARCHAR(20),
  ADD COLUMN IF NOT EXISTS address_detail TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_health_facilities_parent
  ON public.health_facilities(parent_facility_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_health_facilities_code
  ON public.health_facilities(upper(facility_code))
  WHERE facility_code IS NOT NULL;

-- A facility cannot be its own parent.
ALTER TABLE public.health_facilities
  DROP CONSTRAINT IF EXISTS chk_health_facilities_parent_not_self;
ALTER TABLE public.health_facilities
  ADD CONSTRAINT chk_health_facilities_parent_not_self
  CHECK (parent_facility_id IS NULL OR parent_facility_id <> facility_id);

-- facility_type must now also accept 'MHO'. Discovered by name because the
-- original was declared inline.
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
       AND t.relname = 'health_facilities'
       AND c.contype = 'c'
       AND pg_get_constraintdef(c.oid) ILIKE '%facility_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.health_facilities DROP CONSTRAINT %I', r.conname);
  END LOOP;
END
$do$;

ALTER TABLE public.health_facilities
  ADD CONSTRAINT health_facilities_facility_type_check
  CHECK (facility_type IN ('MHO', 'RHU', 'BHC', 'District Hospital', 'Clinic', 'General Hospital'));


-- ---------------------------------------------------------------------------
-- 2. The 'mho' account type
-- ---------------------------------------------------------------------------
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
       AND t.relname = 'accounts'
       AND c.contype = 'c'
       AND pg_get_constraintdef(c.oid) ILIKE '%account_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.accounts DROP CONSTRAINT %I', r.conname);
  END LOOP;
END
$do$;

ALTER TABLE public.accounts
  ADD CONSTRAINT accounts_account_type_check
  CHECK (account_type IN ('mho', 'admin', 'midwife', 'mother'));

COMMENT ON COLUMN public.accounts.account_type IS
  'mho = Municipal Health Office portal; admin = one Rural Health Unit portal; midwife = BHC mobile app; mother = patient app.';


-- ---------------------------------------------------------------------------
-- 3. Seed the Baliwag municipal office and its four Rural Health Units
-- ---------------------------------------------------------------------------
INSERT INTO public.health_facilities
  (name, facility_type, facility_code, barangay, address_street, address_detail, municipality, province)
VALUES
  ('Baliwag Municipal Health Office', 'MHO', 'MHO',
   'Poblacion', NULL, 'Municipal Health Office, Baliwag', 'Baliwag', 'Bulacan')
ON CONFLICT (name) DO UPDATE
  SET facility_type = EXCLUDED.facility_type,
      facility_code = EXCLUDED.facility_code,
      municipality  = EXCLUDED.municipality,
      province      = EXCLUDED.province;

INSERT INTO public.health_facilities
  (name, facility_type, facility_code, barangay, address_street, address_detail, municipality, province, parent_facility_id)
SELECT v.name, 'RHU', v.code, v.barangay, v.street, v.detail, 'Baliwag', 'Bulacan', mho.facility_id
FROM (VALUES
    ('Baliwag RHU I',   'RHU1', 'Bagong Nayon', 'B.S. Aquino Avenue', 'RHU I - Bagong Nayon, B.S. Aquino Avenue'),
    ('Baliwag RHU II',  'RHU2', 'Sto. Nino',    NULL,                 'RHU II - Sto. Nino'),
    ('Baliwag RHU III', 'RHU3', 'San Jose',     'J.P. Rizal Street',  'RHU III - San Jose, J.P. Rizal Street'),
    ('Baliwag RHU IV',  'RHU4', 'Poblacion',    NULL,                 'RHU IV - Barangay Poblacion')
  ) AS v(name, code, barangay, street, detail)
CROSS JOIN LATERAL (
  SELECT facility_id FROM public.health_facilities WHERE facility_type = 'MHO' ORDER BY facility_id LIMIT 1
) AS mho
ON CONFLICT (name) DO UPDATE
  SET facility_type      = EXCLUDED.facility_type,
      facility_code      = EXCLUDED.facility_code,
      barangay           = EXCLUDED.barangay,
      address_street     = EXCLUDED.address_street,
      address_detail     = EXCLUDED.address_detail,
      municipality       = EXCLUDED.municipality,
      province           = EXCLUDED.province,
      parent_facility_id = EXCLUDED.parent_facility_id;

-- Every RHU reports to the municipal office, including any created by hand.
UPDATE public.health_facilities rhu
   SET parent_facility_id = mho.facility_id
  FROM (
    SELECT facility_id FROM public.health_facilities WHERE facility_type = 'MHO' ORDER BY facility_id LIMIT 1
  ) AS mho
 WHERE rhu.facility_type = 'RHU'
   AND rhu.parent_facility_id IS DISTINCT FROM mho.facility_id;

-- The existing barangay health centre rows spell the town "Baliuag", the older
-- form; the town has been Baliwag since its 2024 charter and that is what the
-- new rows use. Normalise the old ones so grouping by municipality does not
-- split the same town in two.
UPDATE public.health_facilities
   SET municipality = 'Baliwag'
 WHERE municipality ILIKE 'Baliuag';

-- Existing barangay health centres start under RHU I. The MHO reassigns them
-- from the Facilities page; this only fills in what is currently null so a later
-- reassignment is never undone by re-running the migration.
UPDATE public.health_facilities bhc
   SET parent_facility_id = rhu1.facility_id
  FROM (
    SELECT facility_id FROM public.health_facilities
     WHERE facility_type = 'RHU' ORDER BY facility_code, facility_id LIMIT 1
  ) AS rhu1
 WHERE bhc.facility_type = 'BHC'
   AND bhc.parent_facility_id IS NULL;


-- ---------------------------------------------------------------------------
-- 4. Scope helpers
-- ---------------------------------------------------------------------------

-- Every facility at or below the given one.
CREATE OR REPLACE FUNCTION public.facility_subtree_ids(p_facility_id BIGINT)
RETURNS TABLE (facility_id BIGINT)
LANGUAGE sql
STABLE
AS $fn$
  WITH RECURSIVE tree AS (
    SELECT hf.facility_id
      FROM public.health_facilities hf
     WHERE hf.facility_id = p_facility_id
    UNION ALL
    SELECT child.facility_id
      FROM public.health_facilities child
      JOIN tree ON child.parent_facility_id = tree.facility_id
  )
  SELECT tree.facility_id FROM tree;
$fn$;

-- The single facility a portal account administers. Portal accounts are scoped
-- through facility_assignments, the same table midwives and mothers use.
CREATE OR REPLACE FUNCTION public.admin_assigned_facility_id(p_account_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_facility_id BIGINT;
BEGIN
  SELECT fa.facility_id
    INTO v_facility_id
    FROM public.facility_assignments fa
    JOIN public.health_facilities hf ON hf.facility_id = fa.facility_id
   WHERE fa.account_id = p_account_id
     AND COALESCE(fa.is_active, true)
     AND hf.facility_type IN ('MHO', 'RHU')
   ORDER BY fa.assigned_at DESC NULLS LAST, fa.facility_assignment_id DESC
   LIMIT 1;

  RETURN v_facility_id;
END
$fn$;

-- One call the portal makes at login: who this account is, which facility it
-- runs, what sits under it, and which depot it draws stock from.
CREATE OR REPLACE FUNCTION public.admin_portal_context(p_account_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_account      RECORD;
  v_facility     RECORD;
  v_role         TEXT;
  v_child_type   TEXT;
  v_depot_id     BIGINT;
  v_depot_name   TEXT;
  v_children     JSONB;
  v_bhcs         JSONB;
  v_scope        JSONB;
BEGIN
  SELECT account_id, account_type, first_name, last_name, status
    INTO v_account
    FROM public.accounts
   WHERE account_id = p_account_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Account not found');
  END IF;

  IF v_account.account_type NOT IN ('mho', 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not a portal account');
  END IF;

  v_role := CASE WHEN v_account.account_type = 'mho' THEN 'mho' ELSE 'rhu' END;

  SELECT hf.* INTO v_facility
    FROM public.health_facilities hf
   WHERE hf.facility_id = public.admin_assigned_facility_id(p_account_id);

  -- Unassigned accounts fall back to the obvious facility for their role, so a
  -- portal login is never left without a scope.
  IF NOT FOUND THEN
    IF v_role = 'mho' THEN
      SELECT hf.* INTO v_facility FROM public.health_facilities hf
       WHERE hf.facility_type = 'MHO' ORDER BY hf.facility_id LIMIT 1;
    ELSE
      SELECT hf.* INTO v_facility FROM public.health_facilities hf
       WHERE hf.facility_type = 'RHU' ORDER BY hf.facility_code, hf.facility_id LIMIT 1;
    END IF;
  END IF;

  IF v_role = 'mho' THEN
    v_child_type := 'RHU';
    v_depot_id   := NULL;                      -- the municipal warehouse
    v_depot_name := 'Municipal Warehouse';
  ELSE
    v_child_type := 'BHC';
    v_depot_id   := v_facility.facility_id;    -- the RHU's own depot
    v_depot_name := COALESCE(v_facility.name, 'RHU') || ' Depot';
  END IF;

  SELECT COALESCE(jsonb_agg(
           jsonb_build_object(
             'facility_id',    c.facility_id,
             'name',           c.name,
             'facility_code',  c.facility_code,
             'facility_type',  c.facility_type,
             'barangay',       c.barangay,
             'address_detail', c.address_detail,
             'is_active',      COALESCE(c.is_active, true)
           ) ORDER BY c.facility_code NULLS LAST, c.name
         ), '[]'::jsonb)
    INTO v_children
    FROM public.health_facilities c
   WHERE c.facility_type = v_child_type
     AND (v_role = 'mho' OR c.parent_facility_id = v_facility.facility_id)
     AND COALESCE(c.is_active, true);

  -- Everything this account may read: its own facility and all descendants.
  SELECT COALESCE(jsonb_agg(s.facility_id ORDER BY s.facility_id), '[]'::jsonb)
    INTO v_scope
    FROM public.facility_subtree_ids(v_facility.facility_id) AS s(facility_id);

  -- The barangay health centres beneath this office, however deep. Patient,
  -- midwife and report screens key off assigned_bhc_id, so they need the leaves
  -- rather than the immediate children.
  SELECT COALESCE(jsonb_agg(
           jsonb_build_object(
             'facility_id', hf.facility_id,
             'name',        hf.name,
             'barangay',    hf.barangay,
             'parent_facility_id', hf.parent_facility_id
           ) ORDER BY hf.name
         ), '[]'::jsonb)
    INTO v_bhcs
    FROM public.health_facilities hf
    JOIN public.facility_subtree_ids(v_facility.facility_id) AS s(facility_id)
      ON s.facility_id = hf.facility_id
   WHERE hf.facility_type = 'BHC'
     AND COALESCE(hf.is_active, true);

  RETURN jsonb_build_object(
    'success',            true,
    'account_id',         v_account.account_id,
    'account_type',       v_account.account_type,
    'role',               v_role,
    'facility_id',        v_facility.facility_id,
    'facility_name',      v_facility.name,
    'facility_code',      v_facility.facility_code,
    'facility_type',      v_facility.facility_type,
    'address_detail',     v_facility.address_detail,
    'depot_facility_id',  v_depot_id,
    'depot_name',         v_depot_name,
    'child_facility_type', v_child_type,
    'child_facilities',   v_children,
    'scope_facility_ids', v_scope,
    'bhc_facilities',     v_bhcs
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 5. Assigning portal accounts to a facility
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_portal_account_facility(
  p_account_id  BIGINT,
  p_facility_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_type     TEXT;
  v_fac_type TEXT;
  v_fac_name TEXT;
BEGIN
  SELECT account_type INTO v_type FROM public.accounts WHERE account_id = p_account_id;
  IF v_type IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Account not found');
  END IF;
  IF v_type NOT IN ('mho', 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only portal accounts are assigned to an office');
  END IF;

  SELECT facility_type, name INTO v_fac_type, v_fac_name
    FROM public.health_facilities WHERE facility_id = p_facility_id;
  IF v_fac_type IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Facility not found');
  END IF;

  IF v_type = 'mho' AND v_fac_type <> 'MHO' THEN
    RETURN jsonb_build_object('success', false, 'error', 'A municipal account must be assigned to the Municipal Health Office');
  END IF;
  IF v_type = 'admin' AND v_fac_type <> 'RHU' THEN
    RETURN jsonb_build_object('success', false, 'error', 'An RHU administrator must be assigned to a Rural Health Unit');
  END IF;

  -- One active office per portal account.
  UPDATE public.facility_assignments
     SET is_active = false, ended_at = COALESCE(ended_at, now())
   WHERE account_id = p_account_id
     AND COALESCE(is_active, true)
     AND facility_id <> p_facility_id;

  IF EXISTS (
    SELECT 1 FROM public.facility_assignments
     WHERE account_id = p_account_id AND facility_id = p_facility_id
  ) THEN
    UPDATE public.facility_assignments
       SET is_active = true, ended_at = NULL
     WHERE account_id = p_account_id AND facility_id = p_facility_id;
  ELSE
    INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
    VALUES (p_account_id, p_facility_id, true);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'account_id', p_account_id,
    'facility_id', p_facility_id,
    'facility_name', v_fac_name
  );
END
$fn$;

-- Existing RHU administrators keep working: park anyone unassigned at RHU I.
INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
SELECT a.account_id, rhu1.facility_id, true
  FROM public.accounts a
 CROSS JOIN LATERAL (
   SELECT facility_id FROM public.health_facilities
    WHERE facility_type = 'RHU' ORDER BY facility_code, facility_id LIMIT 1
 ) AS rhu1
 WHERE a.account_type = 'admin'
   AND public.admin_assigned_facility_id(a.account_id) IS NULL;


-- ---------------------------------------------------------------------------
-- 6. Moving a facility under a different parent (MHO reassigns a BHC)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_facility_parent(
  p_facility_id BIGINT,
  p_parent_id   BIGINT,
  p_actor_id    BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_child  RECORD;
  v_parent RECORD;
BEGIN
  SELECT * INTO v_child FROM public.health_facilities WHERE facility_id = p_facility_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Facility not found');
  END IF;

  SELECT * INTO v_parent FROM public.health_facilities WHERE facility_id = p_parent_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Parent facility not found');
  END IF;

  IF v_child.facility_type = 'BHC' AND v_parent.facility_type <> 'RHU' THEN
    RETURN jsonb_build_object('success', false, 'error', 'A barangay health centre reports to a Rural Health Unit');
  END IF;
  IF v_child.facility_type = 'RHU' AND v_parent.facility_type <> 'MHO' THEN
    RETURN jsonb_build_object('success', false, 'error', 'A Rural Health Unit reports to the Municipal Health Office');
  END IF;

  -- Refuse a cycle: the proposed parent must not sit inside the child's subtree.
  IF EXISTS (
    SELECT 1 FROM public.facility_subtree_ids(p_facility_id) AS s(facility_id)
     WHERE s.facility_id = p_parent_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'That would place the facility under itself');
  END IF;

  UPDATE public.health_facilities
     SET parent_facility_id = p_parent_id
   WHERE facility_id = p_facility_id;

  INSERT INTO public.audit_trail (account_id, action, table_name, description, new_data)
  VALUES (
    p_actor_id,
    'reassign_facility',
    'health_facilities',
    format('%s reassigned to %s', v_child.name, v_parent.name),
    jsonb_build_object('facility_id', p_facility_id, 'parent_facility_id', p_parent_id)
  );

  RETURN jsonb_build_object('success', true, 'facility_id', p_facility_id, 'parent_facility_id', p_parent_id);
END
$fn$;


-- ---------------------------------------------------------------------------
-- 7. Receiving a transfer as an RHU administrator
--
-- receive_inventory_transfer required a midwife, because until now the only
-- destination was a BHC. An MHO -> RHU allocation is received by the RHU's own
-- portal account instead, so the actor check now accepts either: a midwife
-- whose BHC is the destination, or a portal account whose facility is.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_actor_facility_id(p_account_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_type       TEXT;
  v_facility_id BIGINT;
BEGIN
  SELECT account_type INTO v_type
    FROM public.accounts
   WHERE account_id = p_account_id AND status = 'active';

  IF v_type IS NULL THEN
    RETURN NULL;
  END IF;

  IF v_type = 'midwife' THEN
    RETURN public.inventory_midwife_facility_id(p_account_id);
  END IF;

  IF v_type IN ('mho', 'admin') THEN
    RETURN public.admin_assigned_facility_id(p_account_id);
  END IF;

  RETURN NULL;
END
$fn$;


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
  v_actor_facility_id    BIGINT;
  v_item_name            TEXT;
  v_facility_name        TEXT;
  v_source_name          TEXT := 'the Municipal Warehouse';
  v_parent_id            BIGINT;
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

  IF v_transfer.destination_facility_id <> v_actor_facility_id THEN
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

  IF v_source.facility_id IS NOT NULL THEN
    SELECT name INTO v_source_name FROM public.health_facilities WHERE facility_id = v_source.facility_id;
  END IF;

  -- Serialize receipts for the same item/batch/facility so concurrent taps or
  -- multiple devices cannot create duplicate destination batches.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      v_source.item_id::text || ':' ||
      v_transfer.destination_facility_id::text || ':' ||
      v_source.batch_number,
      0
    )
  );

  SELECT batch_id INTO v_destination_batch_id
  FROM public.inventory_batches
  WHERE item_id = v_source.item_id
    AND facility_id = v_transfer.destination_facility_id
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
      v_transfer.destination_facility_id,
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
    v_transfer.destination_facility_id,
    'transfer',
    v_transfer.quantity_issued,
    'Received from ' || COALESCE(v_source_name, 'the issuing office'),
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

  SELECT i.name, hf.name, hf.parent_facility_id
    INTO v_item_name, v_facility_name, v_parent_id
  FROM public.inventory_items i
  CROSS JOIN public.health_facilities hf
  WHERE i.item_id = v_source.item_id
    AND hf.facility_id = v_transfer.destination_facility_id;

  -- Tell the office that issued it, not every administrator in the municipality.
  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT fa.account_id,
         v_facility_name || ' received issued stocks',
         format('%s confirmed receipt of %s units of %s.',
                v_facility_name, v_transfer.quantity_issued, v_item_name),
         'general'
    FROM public.facility_assignments fa
    JOIN public.accounts a ON a.account_id = fa.account_id
   WHERE COALESCE(fa.is_active, true)
     AND a.status = 'active'
     AND a.account_type IN ('mho', 'admin')
     AND fa.facility_id = COALESCE(v_parent_id, fa.facility_id)
     AND (v_parent_id IS NOT NULL OR a.account_type = 'mho');

  INSERT INTO public.audit_trail (account_id, action, table_name, description, new_data)
  VALUES (
    p_received_by,
    'receive_inventory_transfer',
    'inventory_transfers',
    format('%s received transfer #%s (%s units of "%s")',
           v_facility_name, p_transfer_id, v_transfer.quantity_issued, v_item_name),
    to_jsonb(v_transfer)
  );

  RETURN v_transfer;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 8. A flat view of the tree, for the portal's Facilities page
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_facility_tree AS
SELECT
  hf.facility_id,
  hf.name,
  hf.facility_type,
  hf.facility_code,
  hf.barangay,
  hf.address_street,
  hf.address_detail,
  hf.municipality,
  hf.province,
  hf.parent_facility_id,
  parent.name          AS parent_name,
  parent.facility_code AS parent_code,
  parent.facility_type AS parent_type,
  COALESCE(hf.is_active, true) AS is_active,
  (SELECT count(*) FROM public.health_facilities c WHERE c.parent_facility_id = hf.facility_id) AS child_count
FROM public.health_facilities hf
LEFT JOIN public.health_facilities parent ON parent.facility_id = hf.parent_facility_id;


-- ---------------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------------
GRANT SELECT ON public.v_facility_tree TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.facility_subtree_ids(BIGINT)                          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_assigned_facility_id(BIGINT)                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_portal_context(BIGINT)                           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assign_portal_account_facility(BIGINT, BIGINT)          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_facility_parent(BIGINT, BIGINT, BIGINT)             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.inventory_actor_facility_id(BIGINT)                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.receive_inventory_transfer(BIGINT, BIGINT)              TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE ON public.health_facilities    TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.facility_assignments TO anon, authenticated;

-- The portal reads and writes these two tables directly over the anon key, the
-- same way it already does for accounts and inventory. Any RLS left over from
-- the original draft schema would silently return zero facilities, which is what
-- made the inventory page fall back to its hardcoded BHC list.
ALTER TABLE public.health_facilities    DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_assignments DISABLE ROW LEVEL SECURITY;


-- ---------------------------------------------------------------------------
-- 10. Route stock requests to the right Rural Health Unit
--
-- submit_inventory_stock_request notified every active admin account. With one
-- RHU that was correct; with four it means each RHU is paged about requests
-- belonging to the other three. A request now reaches the administrators of the
-- RHU the requesting barangay health centre reports to, and falls back to
-- everyone only when the centre has no parent yet.
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
  v_facility_id   BIGINT;
  v_facility_name TEXT;
  v_parent_id     BIGINT;
  v_request       public.inventory_stock_requests%ROWTYPE;
  v_item_name     TEXT;
BEGIN
  PERFORM public.inventory_assert_actor(p_requested_by, 'midwife');

  v_facility_id := public.inventory_midwife_facility_id(p_requested_by);
  IF v_facility_id IS NULL THEN
    RAISE EXCEPTION 'Midwife has no valid BHC inventory assignment'
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

  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT a.account_id,
         'New stock request',
         format('%s requested %s units of %s.', v_facility_name, p_requested_quantity, v_item_name),
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

  INSERT INTO public.audit_trail (
    account_id, action, table_name, description, new_data
  ) VALUES (
    p_requested_by,
    'submit_inventory_stock_request',
    'inventory_stock_requests',
    format('Submitted stock request #%s for %s units of "%s"',
      v_request.request_id, p_requested_quantity, v_item_name),
    to_jsonb(v_request)
  );

  RETURN v_request;
END
$fn$;

GRANT EXECUTE ON FUNCTION public.submit_inventory_stock_request(BIGINT, BIGINT, INTEGER, TEXT, TEXT)
  TO anon, authenticated;
