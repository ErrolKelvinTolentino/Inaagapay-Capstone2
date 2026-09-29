-- Read only. Used by the export and import scripts; not meant to be run by hand.
-- One result per \o target below.

\o server.csv
SELECT current_setting('server_version_num')::int / 10000 AS major,
       current_setting('server_version') AS version;

\o extensions.csv
SELECT e.extname AS name, n.nspname AS schema_name, e.extversion AS version
  FROM pg_extension e
  JOIN pg_namespace n ON n.oid = e.extnamespace
 ORDER BY 1;

\o realtime_tables.csv
SELECT schemaname AS schema_name, tablename AS table_name
  FROM pg_publication_tables
 WHERE pubname = 'supabase_realtime'
 ORDER BY 1, 2;

-- Row level security, table by table. The app talks to the database as anon,
-- so a table whose RLS state changes in the move starts returning zero rows
-- without an error.
\o rls.csv
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
 ORDER BY 1;

-- What the API roles may do to each table and view.
\o privileges.csv
SELECT c.relname AS table_name,
       r.rolname AS role_name,
       has_table_privilege(r.oid, c.oid, 'SELECT') AS can_select,
       has_table_privilege(r.oid, c.oid, 'INSERT') AS can_insert,
       has_table_privilege(r.oid, c.oid, 'UPDATE') AS can_update,
       has_table_privilege(r.oid, c.oid, 'DELETE') AS can_delete
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 CROSS JOIN pg_roles r
 WHERE n.nspname = 'public'
   AND c.relkind IN ('r', 'p', 'v', 'm')
   AND r.rolname IN ('anon', 'authenticated', 'service_role')
 ORDER BY 1, 2;

-- Exact row counts, the yardstick for "everything arrived".
\o row_counts.csv
SELECT c.relname AS table_name,
       (xpath('/row/c/text()',
              query_to_xml(format('SELECT count(*) AS c FROM public.%I', c.relname),
                           false, true, '')))[1]::text::bigint AS row_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
 ORDER BY 1;

\o object_counts.csv
SELECT 'tables' AS kind, count(*) AS total
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
UNION ALL
SELECT 'views', count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('v', 'm')
UNION ALL
SELECT 'sequences', count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'S'
UNION ALL
SELECT 'indexes', count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'i'
UNION ALL
SELECT 'functions', count(*)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND NOT EXISTS (SELECT 1 FROM pg_depend d
                    WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
UNION ALL
SELECT 'triggers', count(*)
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND NOT t.tgisinternal
UNION ALL
SELECT 'policies', count(*) FROM pg_policies WHERE schemaname = 'public'
UNION ALL
SELECT 'check_and_fk_constraints', count(*)
  FROM pg_constraint k
  JOIN pg_namespace n ON n.oid = k.connamespace
 WHERE n.nspname = 'public';

-- Functions that call out over HTTP or name a Supabase project. These carry
-- URLs and keys the move has to rewrite.
\o http_functions.csv
SELECT p.proname AS function_name,
       (p.prosrc ~ 'net\.http_') AS calls_pg_net,
       (p.prosrc ~* '''apikey''') AS sends_apikey,
       array_to_string(ARRAY(
         SELECT DISTINCT m[1]
           FROM regexp_matches(p.prosrc, '([a-z0-9]{20})\.supabase\.co', 'g') AS m
       ), ' ') AS project_refs
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND (p.prosrc ~ 'net\.http_' OR p.prosrc ~ 'supabase\.co')
 ORDER BY 1;

-- Triggers on public tables that call a function outside public, such as the
-- Database Webhooks helper supabase_functions.http_request.
\o external_triggers.csv
SELECT c.relname AS table_name, t.tgname AS trigger_name,
       pn.nspname || '.' || p.proname AS calls
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_namespace pn ON pn.oid = p.pronamespace
 WHERE n.nspname = 'public' AND NOT t.tgisinternal AND pn.nspname <> 'public'
 ORDER BY 1, 2;

\o
