-- ==============================================================================
-- database/tools/dump_live_schema.sql
--
-- Reads the schema out of the live database so active-draftschema.sql can be
-- rebuilt from what is actually there, rather than from what the migrations
-- were supposed to have done. Those are not the same thing: migrations here are
-- hand-run in the SQL editor, so any one of them may have been skipped, half
-- applied, or amended by hand in the table editor, and nothing records that.
--
-- Read-only. Creates nothing, changes nothing.
--
-- HOW TO USE
--   Run each of the three queries below in the Supabase SQL editor. Each
--   returns a single text cell. Use the result pane's Download CSV, or copy the
--   cell, and save the three as:
--
--       database/tools/live_tables.txt
--       database/tools/live_indexes.txt
--       database/tools/live_routines.txt
--
--   They are inputs for rebuilding the schema file, not files to run.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. Tables: columns, types, defaults, nullability, and every constraint.
-- ---------------------------------------------------------------------------
WITH cols AS (
  SELECT c.oid, c.relname,
         string_agg(
           '    ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
           || COALESCE(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '')
           || CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END,
           E',\n' ORDER BY a.attnum) AS coldef
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
   WHERE n.nspname = 'public' AND c.relkind = 'r'
   GROUP BY c.oid, c.relname
),
cons AS (
  SELECT conrelid AS oid,
         string_agg('    CONSTRAINT ' || conname || ' ' || pg_get_constraintdef(oid),
                    E',\n' ORDER BY contype, conname) AS condef
    FROM pg_constraint
   WHERE connamespace = 'public'::regnamespace
     AND contype IN ('p','f','u','c')
   GROUP BY conrelid
)
SELECT string_agg(
         'CREATE TABLE public.' || cols.relname || E' (\n'
         || cols.coldef
         || COALESCE(E',\n' || cons.condef, '')
         || E'\n);',
         E'\n\n' ORDER BY cols.relname) AS live_tables
  FROM cols
  LEFT JOIN cons ON cons.oid = cols.oid;


-- ---------------------------------------------------------------------------
-- 2. Indexes. Primary-key and unique-constraint indexes are omitted; they are
--    already carried by the constraints in query 1.
-- ---------------------------------------------------------------------------
SELECT string_agg(pg_get_indexdef(i.indexrelid) || ';', E'\n' ORDER BY t.relname, ic.relname) AS live_indexes
  FROM pg_index i
  JOIN pg_class ic ON ic.oid = i.indexrelid
  JOIN pg_class t  ON t.oid  = i.indrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
 WHERE n.nspname = 'public'
   AND NOT i.indisprimary
   AND NOT EXISTS (SELECT 1 FROM pg_constraint c
                    WHERE c.conindid = i.indexrelid AND c.contype = 'u');



-- ---------------------------------------------------------------------------
-- 3. Routines and triggers, by name and signature only.
--
--    Function bodies are deliberately excluded. They are redefined constantly
--    by migrations; copying them into the schema file guarantees the copy goes
--    stale, which is how deduct_prenatal_encounter_inventory ended up wrong in
--    four files at once. The schema file should name what exists and let the
--    migrations own the bodies.
-- ---------------------------------------------------------------------------
SELECT
  (SELECT string_agg('  ' || p.oid::regprocedure::text, E'\n' ORDER BY p.proname)
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f')
  || E'\n\n-- TRIGGERS\n'
  || (SELECT string_agg('  ' || t.tgname || ' ON ' || t.tgrelid::regclass::text
                        || ' -> ' || p.proname || '()', E'\n' ORDER BY t.tgrelid::regclass::text, t.tgname)
        FROM pg_trigger t
        JOIN pg_proc p ON p.oid = t.tgfoid
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND NOT t.tgisinternal)
  AS live_routines;
