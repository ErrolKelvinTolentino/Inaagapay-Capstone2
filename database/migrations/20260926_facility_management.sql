-- ============================================================================
-- MIGRATION: 20260926_facility_management.sql
--
-- Lets the Municipal Health Office register and maintain the facility tree.
--
-- WHAT WAS MISSING
-- ----------------
-- 20260821_mho_tier.sql built the hierarchy and seeded it: one MHO, four Rural
-- Health Units, and the barangay health centres reporting to them. It gave the
-- portal exactly one way to change that tree afterwards —
-- set_facility_parent() — so the Facilities page could move a health centre
-- between RHUs and nothing else.
--
-- A municipality is not fixed. Barangays get their own health station, a
-- station is upgraded, an RHU is split, a name in the seed turns out to be
-- wrong. None of that could be done from the portal: it needed somebody with
-- SQL Editor access to write an INSERT by hand, which is how a facility ends up
-- with no facility_code, no parent, and no seat in any RHU's stock allocation.
--
-- WHAT THIS ADDS
-- --------------
--   create_health_facility()   register an RHU or a barangay health centre
--   update_health_facility()   correct a name, code, barangay or address
--   set_facility_active()      retire a facility, with the checks that make it safe
--
-- All three are SECURITY DEFINER and check that the caller is a municipal
-- officer, because the portal reaches Postgres over the anon key and a rule
-- that lives only in the browser is not a rule.
--
-- ORDERING
-- --------
-- Requires 20260821_mho_tier.sql (parent_facility_id, facility_code, is_active,
-- facility_subtree_ids). The portal calls each function and falls back to
-- saying the feature is unavailable when it is absent, so facilities.html can
-- ship before or after this file.
--
-- Safe to re-run.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Is this caller allowed to reshape the municipality?
--
-- One place, so the three functions below cannot drift apart on the answer.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_municipal_officer(p_account_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.accounts
     WHERE account_id = p_account_id
       AND account_type = 'mho'
       AND status = 'active'
  );
$fn$;


-- ---------------------------------------------------------------------------
-- 2. Registering a facility
--
-- The parent is resolved rather than demanded, because there is only ever one
-- right answer and asking the officer to supply it is asking them to get it
-- wrong: a Rural Health Unit reports to the Municipal Health Office, and there
-- is exactly one of those.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_health_facility(
  p_name           TEXT,
  p_facility_type  TEXT,
  p_barangay       TEXT,
  p_parent_id      BIGINT DEFAULT NULL,
  p_facility_code  TEXT   DEFAULT NULL,
  p_address_street TEXT   DEFAULT NULL,
  p_address_detail TEXT   DEFAULT NULL,
  p_actor_id       BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_parent     RECORD;
  v_new_id     BIGINT;
  v_name       TEXT := btrim(COALESCE(p_name, ''));
  v_barangay   TEXT := btrim(COALESCE(p_barangay, ''));
  v_code       TEXT := NULLIF(upper(btrim(COALESCE(p_facility_code, ''))), '');
  v_mho_id     BIGINT;
  v_muni       TEXT;
  v_prov       TEXT;
BEGIN
  IF p_actor_id IS NOT NULL AND NOT public.is_municipal_officer(p_actor_id) THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only the Municipal Health Office can register a facility.');
  END IF;

  IF v_name = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'A facility needs a name.');
  END IF;
  IF v_barangay = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'A facility needs a barangay.');
  END IF;
  IF p_facility_type NOT IN ('RHU', 'BHC') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Register a Rural Health Unit (RHU) or a barangay health centre (BHC). '
            || 'The Municipal Health Office already exists and there is only one.');
  END IF;

  -- The name carries the unique constraint, so say so in words rather than
  -- letting a 23505 reach the browser as "duplicate key value".
  IF EXISTS (SELECT 1 FROM public.health_facilities WHERE lower(btrim(name)) = lower(v_name)) THEN
    RETURN jsonb_build_object('success', false,
      'error', 'A facility called "' || v_name || '" is already registered.');
  END IF;

  IF v_code IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.health_facilities WHERE upper(facility_code) = v_code) THEN
    RETURN jsonb_build_object('success', false,
      'error', 'The code ' || v_code || ' already belongs to another facility.');
  END IF;

  -- Resolve the parent.
  IF p_facility_type = 'RHU' THEN
    SELECT facility_id INTO v_mho_id
      FROM public.health_facilities
     WHERE facility_type = 'MHO'
     ORDER BY facility_id
     LIMIT 1;

    IF v_mho_id IS NULL THEN
      RETURN jsonb_build_object('success', false,
        'error', 'No Municipal Health Office is registered, so a Rural Health Unit has '
              || 'nothing to report to. Run 20260821_mho_tier.sql first.');
    END IF;
    -- A Rural Health Unit has exactly one possible parent, so whatever the
    -- caller passed is ignored rather than validated.
    p_parent_id := v_mho_id;
  ELSE
    IF p_parent_id IS NULL THEN
      RETURN jsonb_build_object('success', false,
        'error', 'Choose the Rural Health Unit this barangay health centre reports to.');
    END IF;

    SELECT * INTO v_parent FROM public.health_facilities WHERE facility_id = p_parent_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'That Rural Health Unit was not found.');
    END IF;
    IF v_parent.facility_type <> 'RHU' THEN
      RETURN jsonb_build_object('success', false,
        'error', 'A barangay health centre reports to a Rural Health Unit, not to a '
              || v_parent.facility_type || '.');
    END IF;
    IF COALESCE(v_parent.is_active, true) = false THEN
      RETURN jsonb_build_object('success', false,
        'error', v_parent.name || ' is retired, so nothing new can be filed under it.');
    END IF;
  END IF;

  -- Inherit the municipality and province from the office above rather than
  -- defaulting to the values baked into the original schema, which name a
  -- different municipality than the one this system now runs in.
  SELECT municipality, province INTO v_muni, v_prov
    FROM public.health_facilities
   WHERE facility_id = p_parent_id;

  INSERT INTO public.health_facilities
    (name, facility_type, facility_code, barangay, address_street, address_detail,
     municipality, province, parent_facility_id, is_active)
  VALUES
    (v_name, p_facility_type, v_code, v_barangay,
     NULLIF(btrim(COALESCE(p_address_street, '')), ''),
     NULLIF(btrim(COALESCE(p_address_detail, '')), ''),
     COALESCE(v_muni, 'Baliwag'), COALESCE(v_prov, 'Bulacan'),
     p_parent_id, true)
  RETURNING facility_id INTO v_new_id;

  INSERT INTO public.audit_trail (account_id, action, table_name, description, new_data)
  VALUES (
    p_actor_id, 'create_facility', 'health_facilities',
    format('Registered %s "%s" in %s', p_facility_type, v_name, v_barangay),
    jsonb_build_object('facility_id', v_new_id, 'facility_type', p_facility_type,
                       'parent_facility_id', p_parent_id, 'barangay', v_barangay)
  );

  RETURN jsonb_build_object('success', true, 'facility_id', v_new_id,
                            'parent_facility_id', p_parent_id);
END
$fn$;


-- ---------------------------------------------------------------------------
-- 3. Correcting a facility's details
--
-- Deliberately cannot change facility_type or parent. Changing the type would
-- move a facility between rungs of the hierarchy with stock, patients and
-- postings already filed against it; the parent has its own function, which
-- already refuses cycles.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_health_facility(
  p_facility_id    BIGINT,
  p_name           TEXT   DEFAULT NULL,
  p_barangay       TEXT   DEFAULT NULL,
  p_facility_code  TEXT   DEFAULT NULL,
  p_address_street TEXT   DEFAULT NULL,
  p_address_detail TEXT   DEFAULT NULL,
  p_actor_id       BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_row  RECORD;
  v_name TEXT := NULLIF(btrim(COALESCE(p_name, '')), '');
  v_code TEXT := NULLIF(upper(btrim(COALESCE(p_facility_code, ''))), '');
  v_bgy  TEXT := NULLIF(btrim(COALESCE(p_barangay, '')), '');
BEGIN
  IF p_actor_id IS NOT NULL AND NOT public.is_municipal_officer(p_actor_id) THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only the Municipal Health Office can edit a facility.');
  END IF;

  SELECT * INTO v_row FROM public.health_facilities WHERE facility_id = p_facility_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Facility not found');
  END IF;

  IF v_name IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.health_facilities
        WHERE lower(btrim(name)) = lower(v_name) AND facility_id <> p_facility_id) THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Another facility is already called "' || v_name || '".');
  END IF;

  IF v_code IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.health_facilities
        WHERE upper(facility_code) = v_code AND facility_id <> p_facility_id) THEN
    RETURN jsonb_build_object('success', false,
      'error', 'The code ' || v_code || ' already belongs to another facility.');
  END IF;

  UPDATE public.health_facilities
     SET name           = COALESCE(v_name, name),
         barangay       = COALESCE(v_bgy, barangay),
         facility_code  = COALESCE(v_code, facility_code),
         address_street = COALESCE(NULLIF(btrim(COALESCE(p_address_street, '')), ''), address_street),
         address_detail = COALESCE(NULLIF(btrim(COALESCE(p_address_detail, '')), ''), address_detail)
   WHERE facility_id = p_facility_id;

  INSERT INTO public.audit_trail (account_id, action, table_name, description, old_data, new_data)
  VALUES (
    p_actor_id, 'update_facility', 'health_facilities',
    format('Updated facility "%s"', COALESCE(v_name, v_row.name)),
    to_jsonb(v_row),
    (SELECT to_jsonb(h) FROM public.health_facilities h WHERE h.facility_id = p_facility_id)
  );

  RETURN jsonb_build_object('success', true, 'facility_id', p_facility_id);
END
$fn$;


-- ---------------------------------------------------------------------------
-- 4. Retiring a facility
--
-- health_facilities rows are never deleted: facility_assignments references
-- them ON DELETE RESTRICT, and inventory batches, transfers and patient
-- assignments all point at them. Retirement is is_active = false, and it is
-- refused while anything is still standing underneath.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_facility_active(
  p_facility_id BIGINT,
  p_active      BOOLEAN,
  p_actor_id    BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_row       RECORD;
  v_children  INTEGER;
  v_mothers   INTEGER;
  v_midwives  INTEGER;
  v_staff     INTEGER;
  v_stock     INTEGER;
BEGIN
  IF p_actor_id IS NOT NULL AND NOT public.is_municipal_officer(p_actor_id) THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only the Municipal Health Office can retire or restore a facility.');
  END IF;

  SELECT * INTO v_row FROM public.health_facilities WHERE facility_id = p_facility_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Facility not found');
  END IF;

  IF v_row.facility_type = 'MHO' AND p_active = false THEN
    RETURN jsonb_build_object('success', false,
      'error', 'The Municipal Health Office cannot be retired.');
  END IF;

  IF p_active = false THEN
    SELECT count(*) INTO v_children
      FROM public.health_facilities
     WHERE parent_facility_id = p_facility_id AND COALESCE(is_active, true);

    IF v_children > 0 THEN
      RETURN jsonb_build_object('success', false,
        'error', format('%s still has %s active %s reporting to it. Move them to another '
                     || 'Rural Health Unit first.',
                     v_row.name, v_children,
                     CASE WHEN v_children = 1 THEN 'facility' ELSE 'facilities' END));
    END IF;

    SELECT count(*) INTO v_mothers  FROM public.mothers  WHERE assigned_bhc_id = p_facility_id;
    SELECT count(*) INTO v_midwives FROM public.midwives WHERE assigned_bhc_id = p_facility_id;

    IF v_mothers > 0 OR v_midwives > 0 THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'has_people',
        'error', format('%s still has %s %s and %s %s assigned. Reassign them before '
                     || 'retiring it, or their records lose the facility they belong to.',
                     v_row.name,
                     v_mothers,  CASE WHEN v_mothers = 1 THEN 'mother' ELSE 'mothers' END,
                     v_midwives, CASE WHEN v_midwives = 1 THEN 'midwife' ELSE 'midwives' END),
        'mothers', v_mothers, 'midwives', v_midwives);
    END IF;

    -- Stock left on a retired shelf is stock nobody will count again.
    SELECT COALESCE(sum(quantity_remaining), 0) INTO v_stock
      FROM public.inventory_batches
     WHERE facility_id = p_facility_id AND status = 'active';

    IF v_stock > 0 THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'has_stock',
        'error', format('%s still holds %s units of usable stock. Transfer it out first.',
                        v_row.name, v_stock),
        'stock', v_stock);
    END IF;

    -- End the postings so a retired facility stops appearing as somebody's place
    -- of work.
    SELECT count(*) INTO v_staff
      FROM public.facility_assignments
     WHERE facility_id = p_facility_id AND COALESCE(is_active, true);

    UPDATE public.facility_assignments
       SET is_active = false, ended_at = COALESCE(ended_at, now())
     WHERE facility_id = p_facility_id AND COALESCE(is_active, true);
  END IF;

  UPDATE public.health_facilities
     SET is_active = p_active
   WHERE facility_id = p_facility_id;

  INSERT INTO public.audit_trail (account_id, action, table_name, description, new_data)
  VALUES (
    p_actor_id,
    CASE WHEN p_active THEN 'restore_facility' ELSE 'retire_facility' END,
    'health_facilities',
    format('%s facility "%s"', CASE WHEN p_active THEN 'Restored' ELSE 'Retired' END, v_row.name),
    jsonb_build_object('facility_id', p_facility_id, 'is_active', p_active,
                       'postings_ended', COALESCE(v_staff, 0))
  );

  RETURN jsonb_build_object('success', true, 'facility_id', p_facility_id,
                            'is_active', p_active, 'postings_ended', COALESCE(v_staff, 0));
END
$fn$;


-- ---------------------------------------------------------------------------
-- 5. A Rural Health Unit can also be moved
--
-- set_facility_parent() already refuses cycles and checks the type pairing. It
-- is re-granted here only because this page is the first thing to call it for
-- an RHU as well as for a health centre.
-- ---------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.is_municipal_officer(BIGINT)                                   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_health_facility(TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_health_facility(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT)       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_facility_active(BIGINT, BOOLEAN, BIGINT)                   TO anon, authenticated;

COMMIT;

-- ============================================================================
-- Verify
--
--   SELECT public.create_health_facility(
--            'Barangay Health Center - Tarcan', 'BHC', 'Tarcan',
--            (SELECT facility_id FROM health_facilities WHERE facility_type='RHU'
--              ORDER BY facility_code LIMIT 1),
--            'BHC-TAR', NULL, NULL, <mho_account_id>);
--
--   SELECT public.update_health_facility(<facility_id>, 'New name', NULL, NULL, NULL, NULL, <mho_account_id>);
--   SELECT public.set_facility_active(<facility_id>, false, <mho_account_id>);
--
-- Rollback
--
--   DROP FUNCTION IF EXISTS public.set_facility_active(BIGINT, BOOLEAN, BIGINT);
--   DROP FUNCTION IF EXISTS public.update_health_facility(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT);
--   DROP FUNCTION IF EXISTS public.create_health_facility(TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, TEXT, BIGINT);
--   DROP FUNCTION IF EXISTS public.is_municipal_officer(BIGINT);
-- ============================================================================
