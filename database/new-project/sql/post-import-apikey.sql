-- Run by 2-import-new-project.ps1 against the NEW project, after the restore.
--
-- The new project has no JWT keys, only sb_publishable_... and sb_secret_...
-- Supabase accepts one of those in "Authorization: Bearer" only when the
-- request's apikey header carries the same value. Database functions that call
-- an Edge Function through pg_net were written for JWT keys and send only the
-- bearer, so each gets a matching apikey header here:
--
--   'Authorization', 'Bearer ' || v_key
--     becomes
--   'apikey', v_key, 'Authorization', 'Bearer ' || v_key
--
-- A function that builds its headers some other way is reported, not touched.
-- Harmless where a legacy JWT is still in use: apikey accepts that too.

DO $apikey$
DECLARE
  r      RECORD;
  v_def  TEXT;
  v_new  TEXT;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prosrc ~ 'net\.http_post'
       AND p.prosrc !~* '''apikey'''
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := regexp_replace(
      v_def,
      '''Authorization''(\s*),(\s*)''Bearer ''\s*\|\|\s*([A-Za-z_][A-Za-z0-9_.]*)',
      '''apikey'',\1\2\3,\2''Authorization'',\1\2''Bearer '' || \3',
      'g');
    IF v_new <> v_def THEN
      EXECUTE v_new;
      RAISE NOTICE 'apikey header added to %()', r.proname;
    ELSE
      RAISE WARNING '%() calls pg_net but not with an "Authorization: Bearer <variable>" header; check it by hand', r.proname;
    END IF;
  END LOOP;
END
$apikey$;

-- PostgREST caches the schema; tell it to look again.
NOTIFY pgrst, 'reload schema';
