-- ============================================================================
-- MIGRATION: 20261001_mother_transfer_patient_numbers.sql
--
-- Transferring a mother failed on the live data. Found while re-running the
-- test cases on 2026-10-01 against a copy of the live project.
--
-- WHAT WAS WRONG
-- --------------
-- transfer_mother() moved the mother row first. That fires
-- trg_sync_mother_facility, and sync_mother_facility_assignment() answered by
-- UPDATING her active facility_assignments row to the new centre -- keeping
-- the patient number the old centre had issued. Every centre numbers its
-- patients from 1, so that number was usually already taken at the new
-- centre, the unique constraint (facility_id, patient_number) fired, and the
-- whole transfer rolled back with Postgres's "duplicate key" message.
--
-- The same trigger does the same thing to any other write that changes
-- mothers.assigned_bhc_id for a mother who already has a posting.
--
-- WHAT THIS DOES
-- --------------
--   sync_mother_facility_assignment()  a change of centre ends the old posting
--                                      and opens a new, newly numbered one;
--                                      if she is already posted there, it only
--                                      tidies up
--   transfer_mother()                  posts her to the new centre before it
--                                      moves the mother row
--
-- Old postings are ended, not deleted, so her history keeps the number the
-- old centre gave her.
--
-- ⚠ RE-RUN HAZARD
-- ---------------
-- transfer_mother() is also defined in 20260928_mother_transfer.sql, and
-- sync_mother_facility_assignment() in database/seed_redesigned_accounts.sql.
-- Re-running either puts the broken version back; run this file again after.
--
-- Requires 20260928_mother_transfer.sql. No portal or app change needed; the
-- signature is unchanged. Safe to re-run.
-- ============================================================================

BEGIN;

DO $preflight$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'transfer_mother'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: public.transfer_mother(). Run 20260928_mother_transfer.sql first.';
  END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Changing a mother's centre opens a new posting instead of moving the old
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_mother_facility_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF NEW.assigned_bhc_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.assigned_bhc_id IS NOT DISTINCT FROM NEW.assigned_bhc_id THEN
    RETURN NEW;
  END IF;

  -- Already posted to that centre (transfer_mother posts her before it moves
  -- the mother row): only make sure nothing else is left active.
  IF EXISTS (
    SELECT 1 FROM public.facility_assignments
     WHERE account_id = NEW.account_id
       AND COALESCE(is_active, true)
       AND facility_id = NEW.assigned_bhc_id
  ) THEN
    UPDATE public.facility_assignments
       SET is_active = false, ended_at = COALESCE(ended_at, now())
     WHERE account_id = NEW.account_id
       AND COALESCE(is_active, true)
       AND facility_id <> NEW.assigned_bhc_id;
    RETURN NEW;
  END IF;

  -- A patient number belongs to the centre that issued it. Moving the old row
  -- to the new centre carried its number across, where the same number was
  -- usually taken, and the unique constraint (facility_id, patient_number)
  -- refused the change. So the old posting is ended and a new one opened;
  -- set_patient_number numbers it at the new centre.
  UPDATE public.facility_assignments
     SET is_active = false, ended_at = COALESCE(ended_at, now())
   WHERE account_id = NEW.account_id
     AND COALESCE(is_active, true);

  INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
  VALUES (NEW.account_id, NEW.assigned_bhc_id, true);

  RETURN NEW;
END
$fn$;

-- The trigger exists on the live database; recreated so a database that
-- lacks it gets the same behaviour.
DROP TRIGGER IF EXISTS trg_sync_mother_facility ON public.mothers;
CREATE TRIGGER trg_sync_mother_facility
AFTER INSERT OR UPDATE OF assigned_bhc_id ON public.mothers
FOR EACH ROW EXECUTE FUNCTION public.sync_mother_facility_assignment();

-- ---------------------------------------------------------------------------
-- 2. The transfer posts her before it moves her
-- ---------------------------------------------------------------------------

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

  -- 1. Her posting, first. The old one is ended and a new one opened at the
  --    new centre, where set_patient_number gives her that centre's next
  --    number.
  --
  --    This used to come after the mothers UPDATE below. That UPDATE fires
  --    trg_sync_mother_facility, whose old body moved her active posting to the
  --    new centre *with its old patient number* -- a number the new centre had
  --    usually issued already, since every centre counts from 1. The unique
  --    constraint (facility_id, patient_number) then aborted the whole
  --    transfer: TC-MW-XFER-001 and -004 could not pass on the live data.
  UPDATE public.facility_assignments
     SET is_active = false, ended_at = COALESCE(ended_at, now())
   WHERE account_id = v_mother.account_id AND COALESCE(is_active, true);

  INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
  VALUES (v_mother.account_id, p_to_bhc_id, true)
  RETURNING patient_number INTO v_patient_no;

  -- 2. The mother. The sync trigger finds her already posted to the new centre
  --    and leaves the posting alone.
  UPDATE public.mothers
     SET assigned_bhc_id = p_to_bhc_id,
         barangay = COALESCE(NULLIF(btrim(COALESCE(p_new_barangay, '')), ''), barangay)
   WHERE mother_id = p_mother_id;

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
-- To rehearse instead of applying, replace the COMMIT above with ROLLBACK.

-- ============================================================================
-- Verify
--
--   -- No account may hold two active postings.
--   SELECT account_id, count(*) FROM public.facility_assignments
--    WHERE COALESCE(is_active, true) GROUP BY account_id HAVING count(*) > 1;
--
--   -- Then transfer a mother from the portal (Account Management -> Transfer)
--   -- or the app: it should succeed and report a new patient number.
-- ============================================================================
