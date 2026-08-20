-- ==============================================================================
-- SEED: seed_portal_accounts.sql
--
-- Creates the Municipal Health Office account and one administrator per Rural
-- Health Unit, then binds each to the office it runs.
--
-- BEFORE YOU RUN THIS
--   1. Apply database/migrations/20260821_mho_tier.sql first. It creates the
--      'mho' account type, the four RHU facilities, and the assignment RPC this
--      script calls. The guard below stops you if it has not been run.
--   2. Edit the five rows in section 2: put in the real e-mail addresses and
--      names, and change every password.
--
-- ABOUT THE PASSWORDS
--   Each account is created with is_temporary_password = true, so the portal
--   forces a change on first sign-in and these values stop working the moment
--   the person logs in. They are still worth treating as secrets until then:
--   the Supabase SQL editor keeps your query history, so clear this tab
--   afterwards, and do not commit this file with real passwords in it.
--
--   The hash is computed by Postgres, so no plaintext password is ever stored.
--
-- Running twice is safe: existing accounts are left exactly as they are, and
-- only the office assignment is refreshed.
-- ==============================================================================

-- ---------------------------------------------------------------------------
-- 1. Preconditions
-- ---------------------------------------------------------------------------
DO $do$
BEGIN
  IF to_regprocedure('public.assign_portal_account_facility(bigint,bigint)') IS NULL THEN
    RAISE EXCEPTION
      'Run database/migrations/20260821_mho_tier.sql before this script.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.health_facilities WHERE facility_type = 'MHO') THEN
    RAISE EXCEPTION
      'No Municipal Health Office facility found. Run 20260821_mho_tier.sql first.';
  END IF;
END
$do$;

-- bcrypt lives in pgcrypto. Supabase ships it in the extensions schema, which is
-- already on the search path; this line is a no-op when it is present.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


-- ---------------------------------------------------------------------------
-- 2. The accounts to create  <<< EDIT THIS BLOCK >>>
--
--   facility_code links each account to its office:
--     'MHO'  -> Baliwag Municipal Health Office
--     'RHU1' -> Baliwag RHU I    (Bagong Nayon, B.S. Aquino Avenue)
--     'RHU2' -> Baliwag RHU II   (Sto. Nino)
--     'RHU3' -> Baliwag RHU III  (San Jose, J.P. Rizal Street)
--     'RHU4' -> Baliwag RHU IV   (Barangay Poblacion)
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS pg_temp.portal_seed;
CREATE TEMP TABLE portal_seed (
  email         TEXT,
  first_name    TEXT,
  last_name     TEXT,
  acct_type     TEXT,
  facility_code TEXT,
  temp_password TEXT
);

INSERT INTO portal_seed (email, first_name, last_name, acct_type, facility_code, temp_password) VALUES
  ('mho.baliwag@inaagapay.ph',  'Municipal', 'Health Officer',   'mho',   'MHO',  'ChangeMe-MHO-2026!'),
  ('rhu1.baliwag@inaagapay.ph', 'RHU One',   'Administrator',    'admin', 'RHU1', 'ChangeMe-RHU1-2026!'),
  ('rhu2.baliwag@inaagapay.ph', 'RHU Two',   'Administrator',    'admin', 'RHU2', 'ChangeMe-RHU2-2026!'),
  ('rhu3.baliwag@inaagapay.ph', 'RHU Three', 'Administrator',    'admin', 'RHU3', 'ChangeMe-RHU3-2026!'),
  ('rhu4.baliwag@inaagapay.ph', 'RHU Four',  'Administrator',    'admin', 'RHU4', 'ChangeMe-RHU4-2026!');


-- ---------------------------------------------------------------------------
-- 3. Create them
--
-- is_verified and status are both checked at login, and is_temporary_password
-- sends the account straight to the change-password screen on first sign-in.
-- phone_number is left NULL: the column is UNIQUE, and NULLs do not collide.
-- ---------------------------------------------------------------------------
INSERT INTO public.accounts (
  email_address,
  password_hash,
  account_type,
  first_name,
  last_name,
  is_verified,
  status,
  is_temporary_password,
  created_by
)
SELECT
  lower(btrim(s.email)),
  crypt(s.temp_password, gen_salt('bf', 10)),
  s.acct_type,
  s.first_name,
  s.last_name,
  true,
  'active',
  true,
  NULL
FROM portal_seed s
ON CONFLICT (email_address) DO NOTHING;


-- ---------------------------------------------------------------------------
-- 4. Bind each account to its office
--
-- Portal accounts are scoped through facility_assignments, the same table
-- midwives and mothers use. Without this an account signs in with no scope and
-- falls back to the first RHU.
-- ---------------------------------------------------------------------------
SELECT
  a.email_address,
  a.account_type,
  hf.name AS assigned_office,
  public.assign_portal_account_facility(a.account_id, hf.facility_id) AS result
FROM portal_seed s
JOIN public.accounts a
  ON a.email_address = lower(btrim(s.email))
JOIN public.health_facilities hf
  ON upper(hf.facility_code) = upper(s.facility_code)
ORDER BY s.facility_code;


-- ---------------------------------------------------------------------------
-- 5. Confirm what was created
-- ---------------------------------------------------------------------------
SELECT
  a.account_id,
  a.email_address,
  a.account_type,
  a.status,
  a.is_verified,
  a.is_temporary_password AS must_change_password,
  hf.name        AS office,
  hf.facility_code,
  CASE WHEN a.password_hash ~ '^\$2[aby]\$' THEN 'bcrypt ok' ELSE 'NOT A BCRYPT HASH' END AS password_format
FROM public.accounts a
LEFT JOIN public.facility_assignments fa
  ON fa.account_id = a.account_id AND COALESCE(fa.is_active, true)
LEFT JOIN public.health_facilities hf
  ON hf.facility_id = fa.facility_id
WHERE a.account_type IN ('mho', 'admin')
ORDER BY a.account_type DESC, hf.facility_code NULLS LAST, a.account_id;

DROP TABLE IF EXISTS pg_temp.portal_seed;
