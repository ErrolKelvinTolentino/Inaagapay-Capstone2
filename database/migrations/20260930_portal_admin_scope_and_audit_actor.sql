-- ============================================================================
-- MIGRATION: 20260930_portal_admin_scope_and_audit_actor.sql
--
-- Barangay health centre administrators get a facility, and the audit trail
-- names the right person for account changes.
--
-- Found while working through the test cases left "In Progress" on 2026-09-30.
--
-- WHAT WAS WRONG
-- --------------
-- 1. A BHC administrator had no facility. 20260927 let the Municipal Health
--    Office appoint one, but admin_assigned_facility_id() still looked only at
--    MHO and RHU postings. So for a BHC administrator:
--      * create_portal_account() and admin_provisioning_options() said the
--        account "is not assigned to a facility yet" -- it could create no
--        midwife at all (TC-WEB-ACCT-005 could not be run);
--      * admin_portal_context() fell back to the first Rural Health Unit and
--        handed the account that RHU's whole branch: every health centre,
--        mother and midwife under RHU I.
--
-- 2. Account changes were filed under "System". audit_account_change() passes
--    no actor, so the trail could not say who suspended, archived or deleted
--    an account -- and for a deletion nothing else remembers (TC-WEB-ACCT-016).
--
-- 3. Hand-written audit rows could name the wrong person. audit_trail_enrich()
--    looked the row's account_id up through audit_actor(), which tries it as a
--    midwife_id first. On the live data two administrator accounts (1 and 5)
--    share their number with a midwife_id, so a facility edit or a transfer by
--    either one was recorded as done by that midwife.
--
-- 4. Deleting an account named on stock requests, issued transfers or
--    unusable-stock reports (all ON DELETE RESTRICT) failed with Postgres's own
--    foreign-key message in the portal.
--
-- WHAT THIS DOES
-- --------------
--   admin_assigned_facility_id()  counts BHC postings; an MHO/RHU one still wins
--   audit_account_actor()         new: an actor snapshot by account_id only
--   audit_trail_enrich()          uses it
--   audit_account_change()        names the actor: session setting, then
--                                 status_changed_by, then created_by
--   admin_delete_account()        records the actor; refuses cleanly on RESTRICT
--   admin_archive_account()       records the actor for both of its writes
--
-- ⚠ RE-RUN HAZARD
-- ---------------
-- This file redefines functions that older files also define:
--   admin_assigned_facility_id  20260821_mho_tier.sql
--   audit_trail_enrich          20260826_audit_trail_completeness.sql
--   audit_account_change        20260826, 20260913, 20260923
--   admin_delete_account,
--   admin_archive_account       20260925_account_lifecycle.sql
-- Re-running any of those puts the old body back without a word. If one is
-- ever re-run, run this file again after it.
--
-- ORDERING
-- --------
-- No portal or app change depends on this file, and none of it changes a
-- function's signature. Requires 20260826, 20260925 and 20260927.
--
-- Safe to re-run.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'audit_write'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: public.audit_write(). Run 20260826_audit_trail_completeness.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_archive_account'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: public.admin_archive_account(). Run 20260925_account_lifecycle.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'create_portal_account'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: public.create_portal_account(). Run 20260927_account_provisioning.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'audit_trail'
       AND column_name = 'actor_name'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: audit_trail.actor_name. Run 20260826_audit_trail_completeness.sql first.';
  END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Which office a portal account runs -- health centres included
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_assigned_facility_id(p_account_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_facility_id BIGINT;
BEGIN
  -- A barangay health centre posting counts now: 20260927 made BHC
  -- administrators, but this still looked only at MHO and RHU postings, so a
  -- BHC administrator had no facility at all -- create_portal_account() refused
  -- to let one post a midwife, and admin_portal_context() fell back to the
  -- first Rural Health Unit and showed that RHU's whole branch.
  --
  -- An MHO or RHU posting still wins over a BHC one, so an RHU administrator
  -- with a stray health-centre row (20260821_dedupe_facility_assignments.sql
  -- is not applied everywhere) keeps the office it has always had.
  SELECT fa.facility_id
    INTO v_facility_id
    FROM public.facility_assignments fa
    JOIN public.health_facilities hf ON hf.facility_id = fa.facility_id
   WHERE fa.account_id = p_account_id
     AND COALESCE(fa.is_active, true)
     AND hf.facility_type IN ('MHO', 'RHU', 'BHC')
   ORDER BY (hf.facility_type IN ('MHO', 'RHU')) DESC,
            fa.assigned_at DESC NULLS LAST,
            fa.facility_assignment_id DESC
   LIMIT 1;

  RETURN v_facility_id;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 2. An actor looked up by account_id, never by midwife_id
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.audit_account_actor(p_account_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_name        TEXT;
  v_role        TEXT;
  v_facility_id BIGINT;
  v_facility    TEXT;
BEGIN
  IF p_account_id IS NULL THEN
    RETURN jsonb_build_object('account_id', NULL, 'name', 'System',
                              'role', 'system', 'facility_id', NULL,
                              'facility_name', NULL);
  END IF;

  SELECT CASE
           WHEN a.account_type = 'mother' THEN 'Patient #' || a.account_id::text
           ELSE nullif(btrim(concat_ws(' ', a.first_name, a.last_name)), '')
         END,
         a.account_type
    INTO v_name, v_role
    FROM public.accounts a
   WHERE a.account_id = p_account_id;

  -- No such account (deleted since): keep the number, name nobody, and do not
  -- hand back an id the audit_trail foreign key would refuse.
  IF v_role IS NULL THEN
    RETURN jsonb_build_object('account_id', NULL,
                              'name', 'Account #' || p_account_id,
                              'role', 'unknown', 'facility_id', NULL,
                              'facility_name', NULL);
  END IF;

  SELECT fa.facility_id, hf.name
    INTO v_facility_id, v_facility
    FROM public.facility_assignments fa
    JOIN public.health_facilities hf ON hf.facility_id = fa.facility_id
   WHERE fa.account_id = p_account_id
     AND COALESCE(fa.is_active, true)
   ORDER BY fa.assigned_at DESC NULLS LAST, fa.facility_assignment_id DESC
   LIMIT 1;

  RETURN jsonb_build_object(
    'account_id',    p_account_id,
    'name',          COALESCE(v_name, 'Account #' || p_account_id),
    'role',          v_role,
    'facility_id',   v_facility_id,
    'facility_name', v_facility
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 3. Hand-written audit rows: name the right person
-- ---------------------------------------------------------------------------

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
    -- audit_trail.account_id is an account_id by definition (it is a foreign
    -- key to accounts), so it is looked up as one. audit_actor() would try it
    -- as a midwife_id first and could name the wrong person.
    v_actor := public.audit_account_actor(NEW.account_id);
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


-- ---------------------------------------------------------------------------
-- 4. Account changes: name the officer who made them
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
  v_setting TEXT;
  v_actor   BIGINT;
  v_audit   BIGINT;
  v_who     JSONB;
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

  IF v_row.account_type = 'mother' THEN
    v_name := 'Patient #' || v_row.account_id;
  ELSE
    v_name := COALESCE(nullif(btrim(concat_ws(' ', v_row.first_name, v_row.last_name)), ''),
                       'Account #' || v_row.account_id);
  END IF;

  -- is_temporary_password and created_by are later additions
  -- (add_temporary_password_columns.sql, 20260808_created_by_allows_account_ids).
  -- Read through jsonb so signing in cannot be broken by this trigger on a
  -- database that has not applied them.
  v_json := to_jsonb(v_row);

  -- Who did this. A trigger sees only the row, so every entry used to read
  -- "System" -- including the deletion of an account, where the row is gone
  -- and nothing else remembers who removed it. In order of certainty:
  --   1. inaagapay.actor_id, set for this transaction by the lifecycle
  --      functions (admin_delete_account, admin_archive_account);
  --   2. status_changed_by, when the status is what changed;
  --   3. created_by, for an account an officer or a midwife created.
  -- Each is an account_id. None is ever a midwife_id, which is why the
  -- snapshot below is taken with audit_account_actor() and not audit_actor().
  v_setting := current_setting('inaagapay.actor_id', true);
  IF v_setting ~ '^[0-9]+$' THEN
    v_actor := v_setting::bigint;
  ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status
        AND (v_json->>'status_changed_by') ~ '^[0-9]+$' THEN
    v_actor := (v_json->>'status_changed_by')::bigint;
  ELSIF TG_OP = 'INSERT' AND (v_json->>'created_by') ~ '^[0-9]+$' THEN
    v_actor := (v_json->>'created_by')::bigint;
  END IF;
  -- An account is never its own actor on a delete: the row is already gone,
  -- and audit_trail.account_id could not point at it.
  IF TG_OP = 'DELETE' AND v_actor = OLD.account_id THEN
    v_actor := NULL;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_action  := 'create_account';
    IF NEW.account_type = 'mother' THEN
      v_summary := format('Created patient account for Patient #%s', NEW.account_id);
      v_narr := format(
        'A new patient account was registered for Patient #%s with status "%s" on %s%s.',
        NEW.account_id, NEW.status,
        public.audit_ts(COALESCE(public.audit_utc(NEW.created_at), now())),
        COALESCE(' by ' || (v_json->>'created_by'), ''));
    ELSE
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
    END IF;

  ELSIF TG_OP = 'DELETE' THEN
    v_action  := 'delete_account';
    IF OLD.account_type = 'mother' THEN
      v_summary := format('Deleted patient account Patient #%s', OLD.account_id);
      v_narr := format(
        'A patient account was PERMANENTLY DELETED. Patient #%s held a patient account with status "%s", created %s.',
        OLD.account_id, OLD.status,
        public.audit_ts(public.audit_utc(OLD.created_at)));
    ELSE
      v_summary := format('Deleted the %s account of %s', OLD.account_type, v_name);
      v_narr := format(
        'An account was PERMANENTLY DELETED. %s held a %s account (%s) with the status "%s", created %s. '
        'The account row no longer exists. Audit rows this account produced keep the name recorded here, because '
        'the actor name is snapshotted at the time of each action rather than joined at read time.',
        v_name, OLD.account_type, COALESCE(OLD.email_address, 'no e-mail on file'), OLD.status,
        public.audit_ts(public.audit_utc(OLD.created_at)));
    END IF;

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

    -- A login used to be dropped here on the grounds that the admin portal
    -- writes its own row from the browser. That reasoning only ever held for
    -- the portal. The Flutter app updates last_login_at the same way and writes
    -- no audit row of its own, so every midwife and mother login since this
    -- trigger was written has gone unrecorded.
    --
    -- The two surfaces are told apart by what they write, which is the only
    -- signal a trigger has: the app rotates last_login_token on every sign-in,
    -- and the portal updates last_login_at by itself. A time window would not
    -- do -- the portal fires its accounts update and its audit insert as two
    -- parallel requests in separate transactions, so neither can see the
    -- other's uncommitted row and both would be written.
    --
    -- Read through jsonb, like the rest of this function, so a database that
    -- has not got the column cannot be stopped from signing anybody in.
    IF v_action = 'login' THEN
      IF to_jsonb(OLD)->>'last_login_token'
         IS NOT DISTINCT FROM to_jsonb(NEW)->>'last_login_token' THEN
        RETURN NULL;  -- portal shape: its own insert is the record of this
      END IF;

      -- Belt and braces. If a caller ever writes both, one row still wins.
      IF EXISTS (
        SELECT 1 FROM public.audit_trail
         WHERE account_id = v_row.account_id
           AND action = 'login'
           AND action_timestamp > now() - INTERVAL '10 seconds'
      ) THEN
        RETURN NULL;
      END IF;

      PERFORM public.audit_write(
        v_row.account_id, 'login', 'accounts', v_row.account_id::text, v_name,
        format('%s signed in', v_name),
        format('%s (%s) signed in at %s. The account status at the time was "%s".',
               v_name, v_row.account_type,
               public.audit_ts(public.audit_utc(NEW.last_login_at)),
               v_row.status),
        public.audit_section('Session',
          public.audit_kv('Account holder', v_name)
          || public.audit_kv('Account number', '#' || v_row.account_id)
          || public.audit_kv('Role', v_row.account_type)
          || public.audit_kv('Signed in at',
               public.audit_ts(public.audit_utc(NEW.last_login_at)))
          || public.audit_kv('Account status', v_row.status)),
        jsonb_build_object('account_id', v_row.account_id,
                           'account_type', v_row.account_type),
        NULL, NULL, NULL, 'login'
      );

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
      'An account record changed. %s holds a %s account%s whose status is now "%s". %s%s',
      v_name, NEW.account_type,
      CASE WHEN NEW.account_type = 'mother' THEN '' ELSE COALESCE(' (' || NEW.email_address || ')', '') END,
      NEW.status,
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
         || CASE WHEN v_row.account_type = 'mother' THEN '[]'::jsonb ELSE public.audit_kv('E-mail', v_row.email_address) END
         || CASE WHEN v_row.account_type = 'mother' THEN '[]'::jsonb ELSE public.audit_kv('Contact number', v_row.phone_number) END
         || public.audit_kv('Status', v_row.status)
         || public.audit_kv('Verified', CASE WHEN v_row.is_verified THEN 'Yes' ELSE 'No' END)
         || public.audit_kv('Temporary password in force',
              CASE WHEN COALESCE((v_json->>'is_temporary_password')::boolean, false) THEN 'Yes' ELSE 'No' END)
         || public.audit_kv('Account created', public.audit_ts(public.audit_utc(v_row.created_at)))
         || public.audit_kv('Fields changed', nullif(v_changes, ''));

  v_audit := public.audit_write(
    NULL, v_action, 'accounts', v_row.account_id::text, v_name, v_summary, v_narr,
    public.audit_section('Account', v_rows),
    jsonb_build_object('account_id', v_row.account_id, 'account_type', v_row.account_type),
    CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
    NULL, lower(TG_OP)
  );

  -- Named afterwards rather than passed to audit_write(): that function reads
  -- its actor through resolve_actor_account_id(), which tries midwife_id first,
  -- and an administrator whose account_id equals some midwife's midwife_id
  -- would be filed under that midwife's name.
  IF v_actor IS NOT NULL AND v_audit IS NOT NULL THEN
    v_who := public.audit_account_actor(v_actor);
    IF v_who->>'account_id' IS NOT NULL THEN
      UPDATE public.audit_trail
         SET account_id          = (v_who->>'account_id')::bigint,
             actor_name          = v_who->>'name',
             actor_role          = v_who->>'role',
             actor_facility_id   = nullif(v_who->>'facility_id', '')::bigint,
             actor_facility_name = v_who->>'facility_name'
       WHERE audit_id = v_audit;
    END IF;
  END IF;

  RETURN NULL;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 5. Deleting: remember who, and refuse cleanly when records remain
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

  -- Read by trg_audit_account_change, so the deletion is filed under the
  -- officer who made it. Local to this transaction.
  IF p_actor_id IS NOT NULL THEN
    PERFORM set_config('inaagapay.actor_id', p_actor_id::text, true);
  END IF;

  BEGIN
    DELETE FROM public.accounts WHERE account_id = p_account_id;
  EXCEPTION WHEN foreign_key_violation THEN
    -- Stock requests, issued transfers and unusable-stock reports name their
    -- author with ON DELETE RESTRICT. Those are records too; say so in the
    -- portal's own terms instead of passing Postgres's message through.
    RETURN jsonb_build_object(
      'success', false,
      'code', 'has_records',
      'error', 'This account is named on inventory records, which must be kept. Archive it instead.'
    );
  END;

  RETURN jsonb_build_object('success', true, 'account_id', p_account_id, 'deleted', true);
END
$fn$;


-- ---------------------------------------------------------------------------
-- 6. Archiving: both writes filed under the officer
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
  -- Both writes below -- the status change and archived_at -- are filed under
  -- this officer. Without it the second read as a change made by "System".
  IF p_actor_id IS NOT NULL THEN
    PERFORM set_config('inaagapay.actor_id', p_actor_id::text, true);
  END IF;

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


COMMIT;
-- To rehearse instead of applying, replace the COMMIT above with ROLLBACK.
-- (A BEGIN with no COMMIT in the Supabase SQL editor reports success and then
-- discards everything.)

-- ============================================================================
-- Verify
--
--   -- A BHC administrator now resolves to its health centre and the 'bhc' tier.
--   SELECT a.account_id, a.email_address,
--          public.admin_assigned_facility_id(a.account_id) AS facility_id,
--          public.portal_account_tier(a.account_id)        AS tier
--     FROM public.accounts a
--    WHERE a.account_type = 'admin' AND a.status = 'active';
--
--   -- An RHU administrator is unchanged: its RHU, tier 'rhu'.
--
--   -- Account changes made after this file name an officer, not "System".
--   SELECT audit_id, action, actor_name, actor_role, description
--     FROM public.audit_trail
--    WHERE table_name = 'accounts'
--    ORDER BY audit_id DESC
--    LIMIT 10;
--
--   -- Administrators 1 and 5 are named as themselves on hand-written rows.
--   SELECT public.audit_account_actor(1)->>'name', public.audit_account_actor(5)->>'name';
-- ============================================================================
