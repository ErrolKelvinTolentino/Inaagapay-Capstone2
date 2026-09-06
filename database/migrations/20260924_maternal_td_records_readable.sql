-- ===========================================================================
-- 20260924_maternal_td_records_readable.sql
--
-- Fixes: a Td dose recorded in the Td module does not come back. The Supplements
-- and Td card on Add Prenatal Checkup keeps reading UNPROTECTED, and the Td
-- screen keeps showing the dose as missing, however many times it is entered.
--
-- THE BUG
--
--   maternal_td_records is the one table in this project that was created with
--   row level security enabled, policed by two policies granted TO authenticated:
--
--     CREATE POLICY "Allow authenticated read maternal_td_records"
--       ON public.maternal_td_records FOR SELECT TO authenticated USING (true);
--
--   The mobile app does not use Supabase Auth. It authenticates against
--   public.accounts itself and talks to PostgREST with the anon key, so its
--   Postgres role is anon, not authenticated. Under those policies anon matches
--   nothing, and RLS answers a SELECT with zero rows rather than an error --
--   so MaternalTdService.fetchStatus() reads an empty list, catches nothing,
--   and reports a mother with a full Td history as having no doses at all.
--
--   20260821_inventory_and_td_fixes.sql section 2 already found and fixed this.
--   It is back because 20260819_maternal_td_records_and_sync.sql re-creates
--   both policies and re-enables RLS every time it runs, and it has to be
--   re-runnable for the backfill it carries. Running that file again after
--   20260821 silently rewinds the fix.
--
-- THE FIX
--
--   Re-assert the state 20260821 established, in a file dated after the one
--   that undoes it, so the last-applied migration is the correct one. The
--   project's pattern everywhere else is RLS off, explicit grants to anon and
--   authenticated, and authorisation enforced in the application and in
--   SECURITY DEFINER RPCs; this brings the table back in line with it.
--
--   Nothing here depends on the app, and the app needs no change: this is a
--   grant-level fix only.
--
-- Idempotent, and safe to run whenever a Td dose goes missing again after
-- somebody re-runs 20260819.
--
-- Depends on: 20260819_maternal_td_records_and_sync.sql
-- ===========================================================================

DO $do$
BEGIN
  IF to_regclass('public.maternal_td_records') IS NULL THEN
    RAISE NOTICE 'maternal_td_records does not exist; nothing to do.';
    RETURN;
  END IF;

  DROP POLICY IF EXISTS "Allow authenticated read maternal_td_records"
    ON public.maternal_td_records;
  DROP POLICY IF EXISTS "Allow authenticated write maternal_td_records"
    ON public.maternal_td_records;

  ALTER TABLE public.maternal_td_records DISABLE ROW LEVEL SECURITY;

  GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.maternal_td_records TO anon, authenticated;

  -- The sequence grant matters as much as the table grant: without it an
  -- INSERT fails on nextval() even though the table itself is writable.
  IF to_regclass('public.maternal_td_records_td_record_id_seq') IS NOT NULL THEN
    GRANT USAGE, SELECT
      ON SEQUENCE public.maternal_td_records_td_record_id_seq TO anon, authenticated;
  END IF;

  RAISE NOTICE 'maternal_td_records is readable by anon again.';
END
$do$;


-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- No policies, and RLS off:
--
--   SELECT relrowsecurity FROM pg_class
--    WHERE oid = 'public.maternal_td_records'::regclass;   -- expect false
--
--   SELECT policyname FROM pg_policies
--    WHERE tablename = 'maternal_td_records';              -- expect no rows
--
-- anon can read:
--
--   SELECT has_table_privilege('anon', 'public.maternal_td_records', 'SELECT');
--
-- And the doses are there to be read. If this returns rows but the app still
-- shows the mother as having none, the fault is no longer in the grants:
--
--   SELECT mother_id, dose_number, vaccination_date, protection_until, source
--     FROM public.maternal_td_records
--    ORDER BY mother_id, dose_number;
