-- Empties the NEW project's public schema so the import can start over.
-- Run only through 2-import-new-project.ps1 -Reset, which checks first that it
-- is connected to the new project and makes you type its ref.
--
-- NEVER run this against the old project: it deletes every table and row.

BEGIN;

-- Scheduled jobs point at functions about to be dropped.
DO $unschedule$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    PERFORM cron.unschedule(jobid) FROM cron.job;
  END IF;
END
$unschedule$;

DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

-- The grants a fresh Supabase project starts with.
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES    TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
