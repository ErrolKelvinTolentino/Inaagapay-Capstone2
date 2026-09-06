-- ===========================================================================
-- 20260923_auth_session_audit.sql
--
-- Fixes: the audit trail records no sign-in and no sign-out for anybody using
-- the mobile app, which is every midwife and every mother.
--
-- THE BUG
--
--   audit_account_change() detects a login -- an UPDATE that moves nothing but
--   last_login_at -- and then deliberately drops it, on the grounds that the
--   admin portal writes its own 'login' row from the browser. That reasoning
--   only ever held for the portal. The Flutter app updates last_login_at the
--   same way and writes nothing else, so a midwife signing in on her phone
--   produced no audit row at all.
--
--   Signing out was never recorded from anywhere. Logout in the app clears the
--   secure storage and navigates away; no table is touched, so no trigger can
--   see it.
--
-- THE FIX
--
--   1. audit_account_change() writes the login row for the surface that had
--      none. The two are told apart by what they write: the app rotates
--      last_login_token on sign-in, the portal moves last_login_at alone and
--      keeps writing its own row from the browser. A time window would not do
--      here -- the portal fires its accounts update and its audit insert as
--      two parallel requests in separate transactions, so neither can see the
--      other's uncommitted row and both logins would be recorded twice.
--
--      Nothing in admin-web changes, and portal logins keep the row they
--      already had, so this file is safe to apply before or after any deploy.
--
--   2. record_auth_event() gives the app one call for the events no trigger can
--      observe: signing out, and a failed sign-in against a known account. It
--      is SECURITY DEFINER and granted to anon, matching how every other RPC
--      the phone calls is set up in this project.
--
-- Idempotent. CREATE OR REPLACE only; no schema change, and the grants on the
-- existing function survive the replace.
--
-- Depends on: 20260826_audit_trail_completeness.sql,
--             20260913_fix_audit_account_change_type_mismatch.sql
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Account trigger: a login is recorded now, whichever surface caused it.
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

GRANT EXECUTE ON FUNCTION public.audit_account_change() TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 2. The events no trigger can see: signing out, and a failed sign-in.
--
-- The app calls this directly. Signing out touches no table, and a failed
-- sign-in touches nothing either -- the password is compared and the attempt
-- ends -- so neither leaves anything for a trigger to notice.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_auth_event(
  p_account_id BIGINT,
  p_event      TEXT,
  p_detail     TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_acct  public.accounts%ROWTYPE;
  v_name  TEXT;
  v_event TEXT := lower(btrim(COALESCE(p_event, '')));
  v_label TEXT;
BEGIN
  IF v_event NOT IN ('login', 'logout', 'login_failed', 'session_expired') THEN
    RAISE EXCEPTION 'Unknown authentication event: %', p_event
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_acct FROM public.accounts WHERE account_id = p_account_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No account numbered %', p_account_id USING ERRCODE = 'P0002';
  END IF;

  -- A mother is named by number in the audit trail, never by name: the same
  -- redaction audit_actor() and audit_account_change() already apply.
  IF v_acct.account_type = 'mother' THEN
    v_name := 'Patient #' || v_acct.account_id;
  ELSE
    v_name := COALESCE(
      nullif(btrim(concat_ws(' ', v_acct.first_name, v_acct.last_name)), ''),
      'Account #' || v_acct.account_id);
  END IF;

  -- A login is already written by the account trigger when last_login_at moves.
  -- Accepting the event and folding it here keeps the app free to call this on
  -- every sign-in without having to know that.
  IF v_event = 'login' AND EXISTS (
       SELECT 1 FROM public.audit_trail
        WHERE account_id = v_acct.account_id
          AND action = 'login'
          AND action_timestamp > now() - INTERVAL '10 seconds'
     ) THEN
    RETURN NULL;
  END IF;

  v_label := CASE v_event
    WHEN 'login'           THEN 'signed in'
    WHEN 'logout'          THEN 'signed out'
    WHEN 'login_failed'    THEN 'failed to sign in'
    WHEN 'session_expired' THEN 'had a session expire'
  END;

  RETURN public.audit_write(
    v_acct.account_id, v_event, 'accounts', v_acct.account_id::text, v_name,
    format('%s %s', v_name, v_label),
    format('%s (%s) %s at %s.%s',
           v_name, v_acct.account_type, v_label, public.audit_ts(now()),
           COALESCE(' ' || nullif(btrim(p_detail), ''), '')),
    public.audit_section('Session',
      public.audit_kv('Account holder', v_name)
      || public.audit_kv('Account number', '#' || v_acct.account_id)
      || public.audit_kv('Role', v_acct.account_type)
      || public.audit_kv('Event', initcap(replace(v_event, '_', ' ')))
      || public.audit_kv('Recorded at', public.audit_ts(now()))
      || public.audit_kv('Detail', nullif(btrim(p_detail), ''))),
    jsonb_build_object('account_id', v_acct.account_id,
                       'account_type', v_acct.account_type),
    NULL, NULL,
    CASE WHEN v_event = 'login_failed' THEN 'warning' ELSE NULL END,
    v_event
  );
END
$fn$;

GRANT EXECUTE ON FUNCTION public.record_auth_event(BIGINT, TEXT, TEXT)
  TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- Sign in on the phone, then sign out. Two rows, both under module 'Security',
-- both naming the midwife:
--
--   SELECT action_timestamp, action, actor_name, actor_role, module, description
--     FROM public.audit_trail
--    WHERE action IN ('login', 'logout', 'login_failed')
--    ORDER BY audit_id DESC LIMIT 20;
--
-- Sign in to the admin portal and confirm the count goes up by one, not two:
--
--   SELECT count(*) FROM public.audit_trail
--    WHERE action = 'login' AND action_timestamp > now() - INTERVAL '1 minute';
