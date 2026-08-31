-- ==============================================================================
-- MIGRATION: 20260913_fix_audit_account_change_type_mismatch.sql
--
-- Unbreaks every write to public.accounts.
--
-- THE BUG
--
--   20260826_audit_trail_completeness.sql builds the audit detail rows for an
--   account change by concatenating audit_kv() calls, and hides a mother's
--   contact details from the log:
--
--     || CASE WHEN v_row.account_type = 'mother'
--             THEN '{}'::text[]
--             ELSE public.audit_kv('E-mail', v_row.email_address) END
--
--   audit_kv() returns JSONB -- a jsonb array, empty as '[]'::jsonb. The two
--   '{}'::text[] literals are left over from an earlier text[] design that was
--   converted to jsonb everywhere else in that file. Postgres cannot reconcile
--   the two branches:
--
--     ERROR: 42804: CASE types jsonb and text[] cannot be matched
--
--   This is NOT a mothers-only fault. A CASE expression is typed when the
--   statement is planned, not per row, so the assignment fails for every
--   account_type. Since 20260826 was applied, no account could be created or
--   updated at all -- the trigger raises and takes the whole transaction with
--   it. Account Management in the admin portal, self-registration, password
--   changes and status changes were all affected.
--
-- THE FIX
--
--   The two literals become '[]'::jsonb, which is exactly what audit_kv()
--   itself returns for an absent value, so an omitted row disappears from the
--   detail list rather than rendering blank. Nothing else in the function is
--   touched, and the redaction it was written to perform still happens: a
--   mother's e-mail and phone number stay out of the audit detail.
--
-- WHY THIS IS A SEPARATE FILE
--
--   Fixing it in place and re-running 20260826 would rewind four functions that
--   20260829 and 20260911 replaced -- announce_inventory_transfer,
--   audit_inventory_transfer, audit_inventory_transaction and audit_qty. This
--   replaces one function at its existing signature and touches nothing else.
--
--   Corollary: re-running 20260826 after this file REINTRODUCES the bug. If you
--   ever have to, run this one again afterwards.
--
-- Idempotent, and safe to run at any point after 20260826.
-- ==============================================================================

DO $preflight$
BEGIN
  IF to_regprocedure('public.audit_kv(text,text)') IS NULL THEN
    RAISE EXCEPTION
      'public.audit_kv is missing. Run database/migrations/20260826_audit_trail_completeness.sql first.';
  END IF;
END
$preflight$;


BEGIN;

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

    -- A login is already written by the portal with the detail it has; a second
    -- row from here would just be noise.
    IF v_action = 'login' THEN
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

  PERFORM public.audit_write(
    NULL, v_action, 'accounts', v_row.account_id::text, v_name, v_summary, v_narr,
    public.audit_section('Account', v_rows),
    jsonb_build_object('account_id', v_row.account_id, 'account_type', v_row.account_type),
    CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
    NULL, lower(TG_OP)
  );

  RETURN NULL;
END
$fn$;

-- CREATE OR REPLACE keeps the grants already on the function; this is stated
-- explicitly so a fresh database that has only ever run this file is not left
-- with the trigger unable to execute it.
GRANT EXECUTE ON FUNCTION public.audit_account_change() TO anon, authenticated;

COMMIT;


-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- The broken literal must be gone from the installed body. (The legitimate
-- v_sensitive CONSTANT TEXT[] declaration stays; this looks for the literal
-- itself, not for the word.)
--
--   SELECT pg_get_functiondef('public.audit_account_change()'::regprocedure)
--            LIKE '%''{}''::text[]%' AS should_be_false;
--
-- And an account write should now succeed. This one rolls itself back:
--
--   BEGIN;
--   INSERT INTO public.accounts (email_address, account_type, first_name, last_name, status)
--   VALUES ('audit.smoketest@example.invalid', 'mother', 'Audit', 'Smoketest', 'active');
--   ROLLBACK;
--
-- Before this migration that INSERT raises 42804. After it, it succeeds and the
-- ROLLBACK discards both the account and its audit row.
