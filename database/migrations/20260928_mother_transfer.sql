-- ==============================================================================
-- MIGRATION: 20260928_mother_transfer.sql
--
-- Moving a mother to another barangay health centre.
--
-- WHY
--
--   A mother who moves house belongs to a different health centre, and until
--   now nothing could say so. mothers.assigned_bhc_id was written once, at
--   registration, and never again. Her new midwife could not see her, her old
--   midwife kept counting her, and set_facility_active (20260926) refuses to
--   retire a centre that still has mothers assigned while offering no way to
--   reassign them.
--
-- WHAT A TRANSFER DOES, in one transaction
--
--   1. mothers.assigned_bhc_id -> the new centre (and her barangay, if given).
--   2. Her active facility_assignments row is ended and a new one opened at the
--      new centre. set_patient_number gives her the next patient number there;
--      the old row keeps the old number, so her history still reads correctly.
--   3. Her children move with her, each given the next child number at the new
--      centre. Children recorded elsewhere on purpose can be left behind with
--      p_move_children = false.
--   4. An audit row, and a notification to the midwives at both centres.
--
--   Clinical history does not move. Every checkup, dose and lab result keeps
--   the facility where it actually happened.
--
-- WHO MAY TRANSFER
--
--   * the Municipal Health Office, anyone, anywhere;
--   * an administrator, a mother at any centre in their own part of the tree;
--   * a midwife, a mother at her own centre.
--
--   The destination may be any active barangay health centre: a mother who
--   moves to the next municipality's catchment still has to be handed over.
--
-- Requires 20260821_mho_tier.sql (facility_subtree_ids,
-- admin_assigned_facility_id) and 20260909 (notifications.reference_type).
-- Idempotent.
-- ==============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.transfer_mother(
  p_actor_id        BIGINT,
  p_mother_id       BIGINT,
  p_to_bhc_id       BIGINT,
  p_reason          TEXT    DEFAULT NULL,
  p_move_children   BOOLEAN DEFAULT true,
  p_new_barangay    TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_actor        RECORD;
  v_mother       RECORD;
  v_from         RECORD;
  v_to           RECORD;
  v_name         TEXT;
  v_allowed      BOOLEAN := false;
  v_patient_no   INTEGER;
  v_child        RECORD;
  v_children     INTEGER := 0;
  v_next_child   INTEGER;
  v_reason       TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  SELECT account_id, account_type, status, first_name, last_name
    INTO v_actor
    FROM public.accounts WHERE account_id = p_actor_id;
  IF NOT FOUND OR v_actor.status <> 'active' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Your account cannot make transfers.');
  END IF;

  SELECT m.mother_id, m.account_id, m.assigned_bhc_id, m.barangay,
         a.first_name, a.last_name
    INTO v_mother
    FROM public.mothers m
    JOIN public.accounts a ON a.account_id = m.account_id
   WHERE m.mother_id = p_mother_id
   FOR UPDATE OF m;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mother not found.');
  END IF;
  v_name := btrim(COALESCE(v_mother.first_name, '') || ' ' || COALESCE(v_mother.last_name, ''));

  SELECT facility_id, name, facility_type, COALESCE(is_active, true) AS is_active
    INTO v_to
    FROM public.health_facilities WHERE facility_id = p_to_bhc_id;
  IF NOT FOUND OR v_to.facility_type <> 'BHC' THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Choose a barangay health center to transfer her to.');
  END IF;
  IF NOT v_to.is_active THEN
    RETURN jsonb_build_object('success', false,
      'error', format('%s is retired and cannot take new mothers.', v_to.name));
  END IF;
  IF v_mother.assigned_bhc_id = p_to_bhc_id THEN
    RETURN jsonb_build_object('success', false,
      'error', format('%s is already assigned to %s.', v_name, v_to.name));
  END IF;

  SELECT facility_id, name INTO v_from
    FROM public.health_facilities WHERE facility_id = v_mother.assigned_bhc_id;

  -- Who may move her.
  IF v_actor.account_type = 'mho' THEN
    v_allowed := true;
  ELSIF v_actor.account_type = 'admin' THEN
    v_allowed := v_mother.assigned_bhc_id IS NULL
      OR v_mother.assigned_bhc_id IN (
           SELECT facility_id FROM public.facility_subtree_ids(
             public.admin_assigned_facility_id(p_actor_id)));
  ELSIF v_actor.account_type = 'midwife' THEN
    v_allowed := EXISTS (
      SELECT 1 FROM public.midwives
       WHERE account_id = p_actor_id
         AND assigned_bhc_id = v_mother.assigned_bhc_id);
  END IF;
  IF NOT v_allowed THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only the Municipal Health Office, her RHU, or her own midwife can transfer this mother.');
  END IF;

  -- 1. The mother.
  UPDATE public.mothers
     SET assigned_bhc_id = p_to_bhc_id,
         barangay = COALESCE(NULLIF(btrim(COALESCE(p_new_barangay, '')), ''), barangay)
   WHERE mother_id = p_mother_id;

  -- 2. Her posting. The trigger numbers the new row.
  UPDATE public.facility_assignments
     SET is_active = false, ended_at = COALESCE(ended_at, now())
   WHERE account_id = v_mother.account_id AND COALESCE(is_active, true);

  INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
  VALUES (v_mother.account_id, p_to_bhc_id, true)
  RETURNING patient_number INTO v_patient_no;

  -- 3. Her children, numbered at the new centre.
  IF p_move_children THEN
    FOR v_child IN
      SELECT child_id FROM public.children
       WHERE mother_id = p_mother_id
         AND assigned_bhc_id IS DISTINCT FROM p_to_bhc_id
       ORDER BY child_id
       FOR UPDATE
    LOOP
      SELECT COALESCE(MAX(child_number), 0) + 1 INTO v_next_child
        FROM public.children
       WHERE assigned_bhc_id = p_to_bhc_id AND child_number IS NOT NULL;

      UPDATE public.children
         SET assigned_bhc_id = p_to_bhc_id, child_number = v_next_child
       WHERE child_id = v_child.child_id;
      v_children := v_children + 1;
    END LOOP;
  END IF;

  -- 4. The record of it.
  INSERT INTO public.audit_trail (account_id, action, table_name, description, new_data)
  VALUES (
    p_actor_id,
    'transfer_mother',
    'mothers',
    format('Transferred %s from %s to %s%s%s',
           v_name,
           COALESCE(v_from.name, 'no health center'),
           v_to.name,
           CASE WHEN v_children > 0
                THEN format(' with %s %s', v_children, CASE WHEN v_children = 1 THEN 'child' ELSE 'children' END)
                ELSE '' END,
           CASE WHEN v_reason IS NOT NULL THEN '. Reason: ' || v_reason ELSE '' END),
    jsonb_build_object(
      'mother_id', p_mother_id,
      'from_bhc_id', v_mother.assigned_bhc_id,
      'to_bhc_id', p_to_bhc_id,
      'patient_number', v_patient_no,
      'children_moved', v_children,
      'reason', v_reason)
  );

  INSERT INTO public.notifications (account_id, title, message, type, reference_type, reference_id)
  SELECT mw.account_id,
         'Mother transferred in',
         format('%s is now assigned to %s (patient no. %s)%s.',
                v_name, v_to.name, COALESCE(v_patient_no::text, '-'),
                CASE WHEN v_from.name IS NOT NULL THEN ', transferred from ' || v_from.name ELSE '' END),
         'general', 'mothers', p_mother_id
    FROM public.midwives mw
    JOIN public.accounts a ON a.account_id = mw.account_id AND a.status = 'active'
   WHERE mw.assigned_bhc_id = p_to_bhc_id AND mw.account_id <> p_actor_id;

  IF v_from.facility_id IS NOT NULL THEN
    INSERT INTO public.notifications (account_id, title, message, type, reference_type, reference_id)
    SELECT mw.account_id,
           'Mother transferred out',
           format('%s has been transferred to %s. Her records now appear there.', v_name, v_to.name),
           'general', 'mothers', p_mother_id
      FROM public.midwives mw
      JOIN public.accounts a ON a.account_id = mw.account_id AND a.status = 'active'
     WHERE mw.assigned_bhc_id = v_from.facility_id AND mw.account_id <> p_actor_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'mother_id', p_mother_id,
    'from_bhc_id', v_mother.assigned_bhc_id,
    'from_name', v_from.name,
    'to_bhc_id', p_to_bhc_id,
    'to_name', v_to.name,
    'patient_number', v_patient_no,
    'children_moved', v_children);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.transfer_mother(BIGINT, BIGINT, BIGINT, TEXT, BOOLEAN, TEXT)
  TO anon, authenticated;

COMMIT;

-- Verify:
--
--   SELECT public.transfer_mother(<mho_account_id>, <mother_id>, <other_bhc_id>, 'Moved house');
--
-- Expect success: true, a new patient_number, and children_moved equal to her
-- children at the old centre. Then:
--
--   SELECT assigned_bhc_id FROM public.mothers WHERE mother_id = <mother_id>;
--   SELECT facility_id, patient_number, is_active FROM public.facility_assignments
--    WHERE account_id = (SELECT account_id FROM public.mothers WHERE mother_id = <mother_id>)
--    ORDER BY assigned_at;
