-- ============================================================================
-- MIGRATION: 20260925_account_lifecycle.sql
--
-- Makes suspend, deactivate and delete mean three different things.
--
-- WHAT WAS WRONG
-- --------------
-- 1. All three portal buttons wrote the same row. "Deactivate" and "Suspend"
--    were one UPDATE to accounts.status with no reason, no actor and no
--    timestamp, so nobody could answer "who suspended this midwife, and why?"
--    a week later. The audit trail recorded that status changed; it could not
--    record a reason that was never captured.
--
-- 2. Delete was a hard DELETE over the anon key. `mothers` and `midwives`
--    reference accounts ON DELETE CASCADE, `pregnancies` references mothers
--    ON DELETE CASCADE, and `clinical_encounters` references pregnancies the
--    same way. So deleting one mother's account silently destroyed every
--    pregnancy, every prenatal encounter and every risk assessment belonging
--    to her — behind a one-line confirm box. audit_trail.account_id is
--    ON DELETE SET NULL, so the trail of who did it went blank at the same
--    moment.
--
--    In a system holding maternal and child health records this is not a
--    delete, it is destruction of a clinical record. DOH retention rules and
--    RA 10173's own accuracy principle both assume the record survives the
--    account.
--
-- 3. Nothing stopped an RHU administrator from suspending the Municipal Health
--    Officer, or from suspending the last active administrator at their own
--    facility and locking the office out of the portal entirely.
--
-- WHAT THIS DOES
-- --------------
--   * columns to record why a status changed, who changed it and when
--   * admin_account_dependents()  — what would be destroyed by a delete
--   * admin_set_account_status()  — the role and last-administrator rules
--   * admin_delete_account()      — refuses when clinical records exist
--
-- ORDERING
-- --------
-- The portal is deployed separately from this file and must work either way.
-- accounts.html calls each function and falls back to the plain UPDATE it has
-- always done when the function is absent (PGRST202 / 42883), so the two can
-- ship in either order. Nothing here is required by any other migration.
--
-- Safe to re-run.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Why a status changed
--
-- A suspension without a recorded reason is indistinguishable from a mistake,
-- and it is the one status an account cannot lift for itself.
-- ---------------------------------------------------------------------------

ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS status_reason      TEXT,
  ADD COLUMN IF NOT EXISTS status_changed_at  TIMESTAMP WITHOUT TIME ZONE,
  ADD COLUMN IF NOT EXISTS status_changed_by  BIGINT,
  -- Set when an account is retired but its clinical records are kept. Distinct
  -- from status: an archived account is always inactive, but most inactive
  -- accounts are simply staff on leave and are expected back.
  ADD COLUMN IF NOT EXISTS archived_at        TIMESTAMP WITHOUT TIME ZONE;

DO $$
BEGIN
  -- ON DELETE SET NULL rather than CASCADE: losing the actor is bad, losing the
  -- account row that records the suspension would be worse.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'accounts_status_changed_by_fkey'
       AND conrelid = 'public.accounts'::regclass
  ) THEN
    ALTER TABLE public.accounts
      ADD CONSTRAINT accounts_status_changed_by_fkey
      FOREIGN KEY (status_changed_by)
      REFERENCES public.accounts(account_id) ON DELETE SET NULL;
  END IF;
END
$$;

COMMENT ON COLUMN public.accounts.status_reason IS
  'Why this account was last deactivated, suspended or reactivated. Required for a suspension.';
COMMENT ON COLUMN public.accounts.archived_at IS
  'Set when the account was retired in place of deletion because clinical records depend on it.';

CREATE INDEX IF NOT EXISTS idx_accounts_status_type
  ON public.accounts (status, account_type);


-- ---------------------------------------------------------------------------
-- 2. What a delete would take with it
--
-- Called before the confirm box is drawn, so the officer is told what is at
-- stake in numbers rather than in the words "cannot be undone".
--
-- Counts follow the cascade as the schema actually declares it:
--     accounts -> mothers      (CASCADE)
--       mothers -> pregnancies (CASCADE)
--         pregnancies -> clinical_encounters (CASCADE)
--       mothers -> children    (SET NULL — orphaned, not deleted)
--     accounts -> midwives     (CASCADE)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_account_dependents(p_account_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_account       RECORD;
  v_mother_id     BIGINT;
  v_midwife_id    BIGINT;
  v_pregnancies   INTEGER := 0;
  v_encounters    INTEGER := 0;
  v_children      INTEGER := 0;
  v_immunizations INTEGER := 0;
  v_growth        INTEGER := 0;
  v_given_care    INTEGER := 0;
  v_assignments   INTEGER := 0;
BEGIN
  SELECT * INTO v_account FROM public.accounts WHERE account_id = p_account_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Account not found');
  END IF;

  SELECT mother_id  INTO v_mother_id  FROM public.mothers  WHERE account_id = p_account_id;
  SELECT midwife_id INTO v_midwife_id FROM public.midwives WHERE account_id = p_account_id;

  IF v_mother_id IS NOT NULL THEN
    SELECT count(*) INTO v_pregnancies FROM public.pregnancies WHERE mother_id = v_mother_id;

    SELECT count(*) INTO v_encounters
      FROM public.clinical_encounters ce
      JOIN public.pregnancies p ON p.pregnancy_id = ce.pregnancy_id
     WHERE p.mother_id = v_mother_id;

    SELECT count(*) INTO v_children FROM public.children WHERE mother_id = v_mother_id;

    SELECT count(*) INTO v_immunizations
      FROM public.immunization_records ir
      JOIN public.children c ON c.child_id = ir.child_id
     WHERE c.mother_id = v_mother_id;

    SELECT count(*) INTO v_growth
      FROM public.child_growth_records g
      JOIN public.children c ON c.child_id = g.child_id
     WHERE c.mother_id = v_mother_id;
  END IF;

  IF v_midwife_id IS NOT NULL THEN
    -- A midwife's account does not own these rows, but it is the only record of
    -- who gave the dose. Deleting it blanks the attribution.
    SELECT count(*) INTO v_given_care
      FROM public.immunization_records WHERE administered_by = v_midwife_id;
  END IF;

  SELECT count(*) INTO v_assignments
    FROM public.facility_assignments
   WHERE account_id = p_account_id AND COALESCE(is_active, true);

  RETURN jsonb_build_object(
    'success', true,
    'account_id', p_account_id,
    'account_type', v_account.account_type,
    'is_mother', v_mother_id IS NOT NULL,
    'is_midwife', v_midwife_id IS NOT NULL,
    'pregnancies', v_pregnancies,
    'encounters', v_encounters,
    'children', v_children,
    'immunizations', v_immunizations,
    'growth_records', v_growth,
    'doses_administered', v_given_care,
    'active_assignments', v_assignments,
    -- The single question the portal actually asks. Anything above zero means
    -- a delete would destroy or orphan a clinical record.
    'clinical_records', v_pregnancies + v_encounters + v_children
                        + v_immunizations + v_growth + v_given_care,
    'deletable', (v_pregnancies + v_encounters + v_children
                  + v_immunizations + v_growth + v_given_care) = 0
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 3. Changing a status, with the rules that were only ever in the browser
--
-- Rules, in the order they are checked:
--   * an account may never change its own status
--   * only the Municipal Health Office may act on 'mho' or 'admin' accounts
--   * an RHU administrator may act only inside its own facility subtree
--   * the last active municipal officer cannot be disabled
--   * the last active administrator at a facility cannot be disabled
--   * a suspension must carry a reason
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_set_account_status(
  p_account_id BIGINT,
  p_status     TEXT,
  p_reason     TEXT DEFAULT NULL,
  p_actor_id   BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_target      RECORD;
  v_actor       RECORD;
  v_actor_fac   BIGINT;
  v_target_fac  BIGINT;
  v_remaining   INTEGER;
BEGIN
  IF p_status NOT IN ('active', 'inactive', 'suspended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unknown status: ' || p_status);
  END IF;

  SELECT * INTO v_target FROM public.accounts WHERE account_id = p_account_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Account not found');
  END IF;

  IF p_actor_id IS NOT NULL THEN
    SELECT * INTO v_actor FROM public.accounts WHERE account_id = p_actor_id;
  END IF;

  -- An officer locking themselves out cannot undo it from the login screen.
  IF p_actor_id IS NOT NULL AND p_actor_id = p_account_id THEN
    RETURN jsonb_build_object('success', false,
      'error', 'An account cannot change its own status.');
  END IF;

  -- Portal accounts are municipal business.
  IF v_target.account_type IN ('mho', 'admin')
     AND v_actor.account_id IS NOT NULL
     AND v_actor.account_type <> 'mho' THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only the Municipal Health Office can change the status of a portal account.');
  END IF;

  -- An RHU administrator acts only within its own branch.
  IF v_actor.account_id IS NOT NULL AND v_actor.account_type = 'admin' THEN
    v_actor_fac := public.admin_assigned_facility_id(p_actor_id);

    SELECT COALESCE(
             (SELECT assigned_bhc_id FROM public.mothers  WHERE account_id = p_account_id),
             (SELECT assigned_bhc_id FROM public.midwives WHERE account_id = p_account_id),
             (SELECT facility_id FROM public.facility_assignments
               WHERE account_id = p_account_id AND COALESCE(is_active, true)
               ORDER BY assigned_at DESC LIMIT 1)
           )
      INTO v_target_fac;

    IF v_actor_fac IS NULL THEN
      RETURN jsonb_build_object('success', false,
        'error', 'Your account is not assigned to a facility, so it cannot manage other accounts.');
    END IF;

    IF v_target_fac IS NULL OR NOT EXISTS (
         SELECT 1 FROM public.facility_subtree_ids(v_actor_fac) AS s(facility_id)
          WHERE s.facility_id = v_target_fac
       ) THEN
      RETURN jsonb_build_object('success', false,
        'error', 'That account belongs to another Rural Health Unit.');
    END IF;
  END IF;

  -- Do not let the municipality lose its last way in.
  IF p_status <> 'active' AND v_target.status = 'active' THEN
    IF v_target.account_type = 'mho' THEN
      SELECT count(*) INTO v_remaining
        FROM public.accounts
       WHERE account_type = 'mho' AND status = 'active' AND account_id <> p_account_id;
      IF v_remaining = 0 THEN
        RETURN jsonb_build_object('success', false,
          'error', 'This is the only active Municipal Health Office account. '
                || 'Create or reactivate another before disabling this one.');
      END IF;
    ELSIF v_target.account_type = 'admin' THEN
      SELECT facility_id INTO v_target_fac
        FROM public.facility_assignments
       WHERE account_id = p_account_id AND COALESCE(is_active, true)
       ORDER BY assigned_at DESC LIMIT 1;

      IF v_target_fac IS NOT NULL THEN
        SELECT count(*) INTO v_remaining
          FROM public.facility_assignments fa
          JOIN public.accounts a ON a.account_id = fa.account_id
         WHERE fa.facility_id = v_target_fac
           AND COALESCE(fa.is_active, true)
           AND a.account_type = 'admin'
           AND a.status = 'active'
           AND a.account_id <> p_account_id;
        IF v_remaining = 0 THEN
          RETURN jsonb_build_object('success', false,
            'error', 'This is the only active administrator at that Rural Health Unit. '
                  || 'Assign another administrator before disabling this one.');
        END IF;
      END IF;
    END IF;
  END IF;

  -- A suspension is a sanction; it has to say what for.
  IF p_status = 'suspended' AND COALESCE(btrim(p_reason), '') = '' THEN
    RETURN jsonb_build_object('success', false,
      'error', 'A suspension needs a recorded reason.');
  END IF;

  -- The audit trail is written by trg_audit_account_change on this UPDATE.
  -- Nothing here inserts into audit_trail: doing so would file the same event
  -- twice, once from the trigger and once by hand.
  UPDATE public.accounts
     SET status            = p_status,
         status_reason     = NULLIF(btrim(COALESCE(p_reason, '')), ''),
         status_changed_at = now(),
         status_changed_by = p_actor_id,
         -- Reactivating clears an archive; it is the same decision reversed.
         archived_at       = CASE WHEN p_status = 'active' THEN NULL ELSE archived_at END,
         updated_at        = now()
   WHERE account_id = p_account_id;

  RETURN jsonb_build_object(
    'success', true,
    'account_id', p_account_id,
    'status', p_status,
    'previous_status', v_target.status
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 4. Deleting, or refusing to
--
-- Permanent deletion stays available for what it is actually for: an account
-- typed in wrongly ten minutes ago that has never been used. The moment a
-- clinical record hangs off it, the answer is to archive instead, and the
-- function says so rather than doing something destructive quietly.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_delete_account(
  p_account_id BIGINT,
  p_actor_id   BIGINT DEFAULT NULL,
  p_reason     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_target RECORD;
  v_actor  RECORD;
  v_deps   JSONB;
BEGIN
  SELECT * INTO v_target FROM public.accounts WHERE account_id = p_account_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Account not found');
  END IF;

  IF p_actor_id IS NOT NULL THEN
    SELECT * INTO v_actor FROM public.accounts WHERE account_id = p_actor_id;
  END IF;

  IF p_actor_id IS NOT NULL AND p_actor_id = p_account_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'An account cannot delete itself.');
  END IF;

  IF v_target.account_type IN ('mho', 'admin')
     AND v_actor.account_id IS NOT NULL
     AND v_actor.account_type <> 'mho' THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only the Municipal Health Office can delete a portal account.');
  END IF;

  v_deps := public.admin_account_dependents(p_account_id);

  IF (v_deps->>'deletable')::boolean IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'has_clinical_records',
      'error', 'This account holds clinical records, which must be kept. Archive it instead.',
      'dependents', v_deps
    );
  END IF;

  DELETE FROM public.accounts WHERE account_id = p_account_id;

  RETURN jsonb_build_object('success', true, 'account_id', p_account_id, 'deleted', true);
END
$fn$;


-- ---------------------------------------------------------------------------
-- 5. Archiving: what to do instead of deleting
--
-- Keeps every row, blocks every login, and records that this was a retirement
-- rather than a spell of leave.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_archive_account(
  p_account_id BIGINT,
  p_reason     TEXT DEFAULT NULL,
  p_actor_id   BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_result JSONB;
BEGIN
  v_result := public.admin_set_account_status(
    p_account_id, 'inactive',
    COALESCE(NULLIF(btrim(COALESCE(p_reason, '')), ''), 'Account retired'),
    p_actor_id);

  IF (v_result->>'success')::boolean IS NOT TRUE THEN
    RETURN v_result;
  END IF;

  UPDATE public.accounts
     SET archived_at = now()
   WHERE account_id = p_account_id;

  -- End the facility posting. An archived midwife left on a roster keeps
  -- appearing in assignment screens and in every "who covers this barangay"
  -- count, which is how a retired member of staff ends up looking like cover
  -- that does not exist.
  UPDATE public.facility_assignments
     SET is_active = false,
         ended_at  = COALESCE(ended_at, now())
   WHERE account_id = p_account_id
     AND COALESCE(is_active, true);

  RETURN jsonb_build_object('success', true, 'account_id', p_account_id, 'archived', true);
END
$fn$;


-- ---------------------------------------------------------------------------
-- 6. Grants
--
-- The portal talks to Postgres over the anon key, exactly as it does for
-- accounts and inventory today. These functions are SECURITY DEFINER so that
-- the rules above are applied in the database rather than only in the browser,
-- which is the point of moving them here.
-- ---------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.admin_account_dependents(BIGINT)                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_account_status(BIGINT, TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_account(BIGINT, BIGINT, TEXT)           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_archive_account(BIGINT, TEXT, BIGINT)          TO anon, authenticated;

COMMIT;

-- ============================================================================
-- Verify
--
--   SELECT public.admin_account_dependents(<account_id>);
--   SELECT public.admin_set_account_status(<account_id>, 'suspended',
--            'Left without notice', <actor_id>);
--   SELECT public.admin_delete_account(<account_id>, <actor_id>);
--
-- Rollback
--
--   DROP FUNCTION IF EXISTS public.admin_archive_account(BIGINT, TEXT, BIGINT);
--   DROP FUNCTION IF EXISTS public.admin_delete_account(BIGINT, BIGINT, TEXT);
--   DROP FUNCTION IF EXISTS public.admin_set_account_status(BIGINT, TEXT, TEXT, BIGINT);
--   DROP FUNCTION IF EXISTS public.admin_account_dependents(BIGINT);
--   -- the columns are additive and safe to leave in place
-- ============================================================================
