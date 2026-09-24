-- ============================================================================
-- MIGRATION: 20260927_account_provisioning.sql
--
-- Who may create which account, and where that account is posted.
--
-- THE RULE
-- --------
--   Municipal Health Office   creates  municipal officers,
--                                      Rural Health Unit administrators,
--                                      barangay health centre administrators
--   RHU administrator         creates  midwives, at any health centre under it
--   BHC administrator         creates  midwives, at its own health centre
--
-- A midwife is always posted to one barangay health centre, and that centre
-- always sits under exactly one Rural Health Unit — so the portal asks for the
-- RHU and the BHC together rather than presenting a flat list of every centre
-- in the municipality.
--
-- WHAT WAS WRONG
-- --------------
-- 1. The matrix lived entirely in account-create.html, as a couple of
--    `style.display = "none"` calls. Hiding a radio button is not a permission:
--    the page talks to PostgREST over the anon key, so any RHU administrator
--    could create a municipal officer by editing one attribute.
--
-- 2. An RHU administrator could create another RHU administrator, which is how
--    an office ends up with administrators nobody remembers appointing.
--
-- 3. There was no such thing as a barangay health centre administrator.
--    assign_portal_account_facility() refused any 'admin' not posted to an RHU,
--    so a health centre could only ever be staffed by midwives.
--
-- 4. The facility assignment was a best-effort call whose failure was written
--    to console.warn. An account created through a failed assignment signs in
--    with no scope at all and sees an empty portal, with nothing anywhere
--    saying why.
--
-- WHAT THIS ADDS
-- --------------
--   assign_portal_account_facility()  relaxed: an 'admin' may sit at an RHU or a BHC
--   admin_provisioning_options()      what this officer may create, and where
--   create_portal_account()           creates account + role row + posting, atomically
--
-- ORDERING
-- --------
-- Requires 20260821_mho_tier.sql. account-create.html detects both new
-- functions and falls back to the flow it has always used when they are
-- absent — minus barangay health centre administrators, which the database
-- cannot hold until this file is applied.
--
-- ⚠ RE-RUN HAZARD
-- assign_portal_account_facility() is redefined here. 20260821_mho_tier.sql
-- carries the older, stricter copy, so re-running that file reverts this change
-- and barangay health centre administrators stop being assignable. If 20260821
-- is ever re-run, run this file again after it.
--
-- Safe to re-run.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. An administrator may run a Rural Health Unit or a health centre
--
-- Only the facility-type check changes; the rest is 20260821's function
-- unaltered, repeated because CREATE OR REPLACE takes the whole body.
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

  -- The relaxation. An administrator runs one office, and that office is
  -- either a Rural Health Unit or one of the barangay health centres under it.
  IF v_type = 'admin' AND v_fac_type NOT IN ('RHU', 'BHC') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'An administrator is assigned to a Rural Health Unit or a barangay health centre');
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
    'facility_name', v_fac_name,
    'facility_type', v_fac_type
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 2. The tier an officer works at
--
-- 'mho', 'rhu' or 'bhc'. account_type cannot answer this on its own now that
-- an 'admin' may run either rung, and both create_portal_account() and the
-- portal need the same answer.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.portal_account_tier(p_account_id BIGINT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_type TEXT;
  v_fac  TEXT;
BEGIN
  SELECT account_type INTO v_type
    FROM public.accounts
   WHERE account_id = p_account_id AND status = 'active';

  IF v_type IS NULL THEN RETURN NULL; END IF;
  IF v_type = 'mho' THEN RETURN 'mho'; END IF;
  IF v_type <> 'admin' THEN RETURN NULL; END IF;

  SELECT hf.facility_type INTO v_fac
    FROM public.health_facilities hf
   WHERE hf.facility_id = public.admin_assigned_facility_id(p_account_id);

  -- An administrator with no posting is treated as an RHU one, which is what
  -- admin_portal_context already assumes for an unassigned account.
  RETURN CASE WHEN v_fac = 'BHC' THEN 'bhc' ELSE 'rhu' END;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 3. What this officer may create, and where
--
-- Returned as one document so the form has a single source of truth for both
-- the role choices and the facility tree behind them. The portal draws exactly
-- what comes back; create_portal_account() enforces the same rules again on
-- the way in, because a drawn form is not a permission.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_provisioning_options(p_actor_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_tier     TEXT;
  v_fac_id   BIGINT;
  v_fac      RECORD;
  v_parent   RECORD;
  v_mho_id   BIGINT;
  v_roles    JSONB := '[]'::jsonb;
  v_tree     JSONB := '[]'::jsonb;
BEGIN
  v_tier := public.portal_account_tier(p_actor_id);
  IF v_tier IS NULL THEN
    RETURN jsonb_build_object('success', false,
      'error', 'This account cannot create other accounts.');
  END IF;

  v_fac_id := public.admin_assigned_facility_id(p_actor_id);
  SELECT * INTO v_fac FROM public.health_facilities WHERE facility_id = v_fac_id;

  -- An administrator with no posting has no branch to hire into, and a form
  -- built from a null facility would offer a health centre list belonging to
  -- nobody. Say so instead.
  IF v_tier <> 'mho' AND v_fac.facility_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'unassigned',
      'error', 'This account is not assigned to a facility yet, so it cannot '
            || 'create staff. Ask the Municipal Health Office to assign it on '
            || 'the Facility Management page.');
  END IF;

  SELECT facility_id INTO v_mho_id
    FROM public.health_facilities
   WHERE facility_type = 'MHO' ORDER BY facility_id LIMIT 1;

  IF v_tier = 'mho' THEN
    -- The municipal office appoints administrators, never midwives: a midwife
    -- belongs to a health centre and is hired by the office that runs it.
    v_roles := jsonb_build_array(
      jsonb_build_object(
        'value', 'admin', 'posting', 'RHU',
        'label', 'RHU Administrator',
        'description', 'Runs one Rural Health Unit and the health centres under it.',
        'icon', 'fa-hospital'),
      jsonb_build_object(
        'value', 'admin', 'posting', 'BHC',
        'label', 'BHC Administrator',
        'description', 'Runs one barangay health centre and the midwives posted there.',
        'icon', 'fa-house-medical'),
      jsonb_build_object(
        'value', 'mho', 'posting', 'MHO',
        'label', 'Municipal Officer',
        'description', 'Municipality-wide access, including facility management.',
        'icon', 'fa-city')
    );

    -- Every Rural Health Unit with its own health centres nested under it, so
    -- the form can ask for the RHU first and the BHC second.
    SELECT COALESCE(jsonb_agg(t ORDER BY t->>'facility_code', t->>'name'), '[]'::jsonb)
      INTO v_tree
      FROM (
        SELECT jsonb_build_object(
                 'facility_id',   r.facility_id,
                 'name',          r.name,
                 'facility_code', r.facility_code,
                 'barangay',      r.barangay,
                 'children', COALESCE((
                   SELECT jsonb_agg(jsonb_build_object(
                            'facility_id',   c.facility_id,
                            'name',          c.name,
                            'facility_code', c.facility_code,
                            'barangay',      c.barangay
                          ) ORDER BY c.name)
                     FROM public.health_facilities c
                    WHERE c.parent_facility_id = r.facility_id
                      AND c.facility_type = 'BHC'
                      AND COALESCE(c.is_active, true)
                 ), '[]'::jsonb)
               ) AS t
          FROM public.health_facilities r
         WHERE r.facility_type = 'RHU'
           AND COALESCE(r.is_active, true)
      ) AS rhu_rows;   -- not `rows`: ROWS is a keyword in this position

  ELSIF v_tier = 'rhu' THEN
    v_roles := jsonb_build_array(
      jsonb_build_object(
        'value', 'midwife', 'posting', 'BHC',
        'label', 'Midwife',
        'description', 'Posted to one barangay health centre under this Rural Health Unit.',
        'icon', 'fa-user-nurse')
    );

    -- One branch: this RHU, and the health centres reporting to it.
    v_tree := jsonb_build_array(jsonb_build_object(
      'facility_id',   v_fac.facility_id,
      'name',          v_fac.name,
      'facility_code', v_fac.facility_code,
      'barangay',      v_fac.barangay,
      'children', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'facility_id',   c.facility_id,
                 'name',          c.name,
                 'facility_code', c.facility_code,
                 'barangay',      c.barangay
               ) ORDER BY c.name)
          FROM public.health_facilities c
         WHERE c.parent_facility_id = v_fac.facility_id
           AND c.facility_type = 'BHC'
           AND COALESCE(c.is_active, true)
      ), '[]'::jsonb)
    ));

  ELSE  -- 'bhc'
    v_roles := jsonb_build_array(
      jsonb_build_object(
        'value', 'midwife', 'posting', 'BHC',
        'label', 'Midwife',
        'description', 'Posted to this barangay health centre.',
        'icon', 'fa-user-nurse')
    );

    -- The parent RHU is named so the form can still show the full posting,
    -- even though neither rung is a choice here. A health centre with no
    -- parent recorded falls back to naming itself rather than showing a blank.
    SELECT * INTO v_parent FROM public.health_facilities
     WHERE facility_id = v_fac.parent_facility_id;

    v_tree := jsonb_build_array(jsonb_build_object(
      'facility_id',   COALESCE(v_parent.facility_id, v_fac.facility_id),
      'name',          COALESCE(v_parent.name, 'Unassigned Rural Health Unit'),
      'facility_code', v_parent.facility_code,
      'barangay',      v_parent.barangay,
      'children', jsonb_build_array(jsonb_build_object(
        'facility_id',   v_fac.facility_id,
        'name',          v_fac.name,
        'facility_code', v_fac.facility_code,
        'barangay',      v_fac.barangay
      ))
    ));
  END IF;

  RETURN jsonb_build_object(
    'success',          true,
    'actor_tier',       v_tier,
    'actor_facility_id',   v_fac_id,
    'actor_facility_name', v_fac.name,
    'actor_facility_type', v_fac.facility_type,
    'mho_facility_id',  v_mho_id,
    'roles',            v_roles,
    'facilities',       v_tree
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 4. Creating the account
--
-- One call, one transaction. The old flow was four separate writes from the
-- browser — accounts, midwives, facility_assignments, then the assignment RPC
-- — with the last three wrapped in try/catch blocks that only wrote to the
-- console. A half-completed create left an account that could sign in and see
-- nothing, and nothing on screen said so.
--
-- The password is hashed in the browser, as it is everywhere else in this
-- portal, and arrives already hashed.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_portal_account(
  p_actor_id       BIGINT,
  p_account_type   TEXT,
  p_first_name     TEXT,
  p_last_name      TEXT,
  p_email          TEXT,
  p_password_hash  TEXT,
  p_facility_id    BIGINT DEFAULT NULL,
  p_middle_name    TEXT   DEFAULT NULL,
  p_extension_name TEXT   DEFAULT NULL,
  p_phone          TEXT   DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_tier      TEXT;
  v_actor_fac BIGINT;
  v_fac       RECORD;
  v_email     TEXT := lower(btrim(COALESCE(p_email, '')));
  v_new_id    BIGINT;
  v_assign    JSONB;
BEGIN
  v_tier := public.portal_account_tier(p_actor_id);
  IF v_tier IS NULL THEN
    RETURN jsonb_build_object('success', false,
      'error', 'This account cannot create other accounts.');
  END IF;

  IF p_account_type NOT IN ('mho', 'admin', 'midwife') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Unknown account type: ' || COALESCE(p_account_type, 'null'));
  END IF;

  /* ── The matrix ──────────────────────────────────────────────────────── */

  IF v_tier IN ('rhu', 'bhc') AND p_account_type <> 'midwife' THEN
    RETURN jsonb_build_object('success', false,
      'error', 'An administrator can only create midwife accounts. '
            || 'Ask the Municipal Health Office to appoint administrators.');
  END IF;

  IF v_tier = 'mho' AND p_account_type = 'midwife' THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Midwives are created by the office that runs their health centre, '
            || 'not by the Municipal Health Office.');
  END IF;

  /* ── Basic fields ────────────────────────────────────────────────────── */

  IF btrim(COALESCE(p_first_name, '')) = '' OR btrim(COALESCE(p_last_name, '')) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'A first and last name are required.');
  END IF;
  IF v_email = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'An e-mail address is required.');
  END IF;
  IF COALESCE(p_password_hash, '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'No password was supplied.');
  END IF;

  IF EXISTS (SELECT 1 FROM public.accounts WHERE lower(email_address) = v_email) THEN
    RETURN jsonb_build_object('success', false, 'code', 'email_taken',
      'error', 'An account with this e-mail address already exists.');
  END IF;

  IF p_phone IS NOT NULL AND btrim(p_phone) <> ''
     AND EXISTS (SELECT 1 FROM public.accounts WHERE phone_number = btrim(p_phone)) THEN
    RETURN jsonb_build_object('success', false, 'code', 'phone_taken',
      'error', 'An account with this phone number already exists.');
  END IF;

  /* ── The posting ─────────────────────────────────────────────────────── */

  IF p_account_type = 'mho' THEN
    -- A municipal officer sits at the Municipal Health Office; there is one,
    -- so it is resolved rather than asked for.
    SELECT * INTO v_fac FROM public.health_facilities
     WHERE facility_type = 'MHO' ORDER BY facility_id LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false,
        'error', 'No Municipal Health Office is registered.');
    END IF;
  ELSE
    IF p_facility_id IS NULL THEN
      RETURN jsonb_build_object('success', false,
        'error', CASE WHEN p_account_type = 'midwife'
                      THEN 'Choose the barangay health centre this midwife will serve.'
                      ELSE 'Choose the office this administrator will run.' END);
    END IF;

    SELECT * INTO v_fac FROM public.health_facilities WHERE facility_id = p_facility_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'That facility was not found.');
    END IF;
    IF COALESCE(v_fac.is_active, true) = false THEN
      RETURN jsonb_build_object('success', false,
        'error', v_fac.name || ' is retired, so nobody new can be posted to it.');
    END IF;

    -- A midwife belongs to a barangay health centre, never to an RHU depot.
    IF p_account_type = 'midwife' AND v_fac.facility_type <> 'BHC' THEN
      RETURN jsonb_build_object('success', false,
        'error', 'A midwife is posted to a barangay health centre, not to a '
              || v_fac.facility_type || '.');
    END IF;
    IF p_account_type = 'admin' AND v_fac.facility_type NOT IN ('RHU', 'BHC') THEN
      RETURN jsonb_build_object('success', false,
        'error', 'An administrator runs a Rural Health Unit or a barangay health centre.');
    END IF;

    -- And it has to be inside the creator's own branch. Without this an RHU
    -- administrator could post a midwife to another Rural Health Unit's centre.
    IF v_tier <> 'mho' THEN
      v_actor_fac := public.admin_assigned_facility_id(p_actor_id);
      IF v_actor_fac IS NULL THEN
        RETURN jsonb_build_object('success', false,
          'error', 'Your account is not assigned to a facility, so it cannot post anyone.');
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM public.facility_subtree_ids(v_actor_fac) AS s(facility_id)
         WHERE s.facility_id = v_fac.facility_id
      ) THEN
        RETURN jsonb_build_object('success', false,
          'error', v_fac.name || ' does not report to your office.');
      END IF;
    END IF;
  END IF;

  /* ── Write ───────────────────────────────────────────────────────────── */

  -- trg_audit_account_change files the audit entry for this INSERT. Nothing
  -- here writes audit_trail by hand; the portal used to, and every created
  -- account was recorded twice.
  INSERT INTO public.accounts (
    email_address, password_hash, account_type,
    first_name, middle_name, last_name, extension_name,
    phone_number, is_verified, status, is_temporary_password, created_by
  ) VALUES (
    v_email, p_password_hash, p_account_type,
    btrim(p_first_name), NULLIF(btrim(COALESCE(p_middle_name, '')), ''),
    btrim(p_last_name), NULLIF(btrim(COALESCE(p_extension_name, '')), ''),
    NULLIF(btrim(COALESCE(p_phone, '')), ''),
    true, 'active', true, p_actor_id::text
  )
  RETURNING account_id INTO v_new_id;

  IF p_account_type = 'midwife' THEN
    INSERT INTO public.midwives (account_id, assigned_bhc_id)
    VALUES (v_new_id, v_fac.facility_id)
    ON CONFLICT (account_id) DO UPDATE SET assigned_bhc_id = EXCLUDED.assigned_bhc_id;

    -- facility_assignments carries the posting for every kind of account; the
    -- midwife screens read midwives.assigned_bhc_id, the scope functions read
    -- this. Both are written, in one transaction, so they cannot disagree.
    INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
    VALUES (v_new_id, v_fac.facility_id, true);
  ELSE
    v_assign := public.assign_portal_account_facility(v_new_id, v_fac.facility_id);
    IF (v_assign->>'success')::boolean IS NOT TRUE THEN
      -- Raising rolls the account back. An administrator who cannot be posted
      -- is an administrator who signs in to an empty portal.
      RAISE EXCEPTION 'Facility assignment failed: %', COALESCE(v_assign->>'error', 'unknown');
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success',       true,
    'account_id',    v_new_id,
    'account_type',  p_account_type,
    'facility_id',   v_fac.facility_id,
    'facility_name', v_fac.name,
    'facility_type', v_fac.facility_type
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.portal_account_tier(BIGINT)            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provisioning_options(BIGINT)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_portal_account(
  BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, TEXT)       TO anon, authenticated;

COMMIT;

-- ============================================================================
-- Verify
--
--   -- What can each officer create?
--   SELECT a.account_id, a.email_address,
--          public.portal_account_tier(a.account_id) AS tier,
--          public.admin_provisioning_options(a.account_id)->'roles' AS roles
--     FROM public.accounts a
--    WHERE a.account_type IN ('mho', 'admin') AND a.status = 'active';
--
--   -- An RHU administrator must be refused a municipal officer.
--   SELECT public.create_portal_account(
--            <rhu_admin_id>, 'mho', 'Test', 'Officer',
--            'test@example.test', 'x', NULL);
--   -- expect: success false, "An administrator can only create midwife accounts..."
--
-- Rollback
--
--   DROP FUNCTION IF EXISTS public.create_portal_account(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, TEXT);
--   DROP FUNCTION IF EXISTS public.admin_provisioning_options(BIGINT);
--   DROP FUNCTION IF EXISTS public.portal_account_tier(BIGINT);
--   -- then re-run section 5 of 20260821_mho_tier.sql to restore the stricter
--   -- assign_portal_account_facility()
-- ============================================================================
