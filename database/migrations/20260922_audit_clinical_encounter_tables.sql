-- ===========================================================================
-- 20260922_audit_clinical_encounter_tables.sql
--
-- Fixes: nothing recorded on a lab test, prenatal checkup, ultrasound or
-- delivery has ever reached the audit trail.
--
-- THE BUG
--
--   20260826_audit_trail_completeness.sql attaches trg_audit_clinical_<table>
--   from a list of (table, primary key, label) triples, and skips any table
--   whose named key column is missing rather than attaching a trigger that
--   would log NULL ids. That guard is right; the list it guards is wrong.
--
--   Four of the nine entries name a key that does not exist. The live schema
--   made prenatal_checkups, lab_tests, ultrasounds and deliveries 1:1
--   extensions of clinical_encounters keyed on encounter_id, while the list
--   still asks for prenatal_checkup_id, lab_test_id, ultrasound_id and
--   delivery_id. (supabase_setup.sql, the superseded schema, does define those
--   columns, which is where the list came from.) All four were therefore
--   skipped with a NOTICE nobody was watching for, and no audit row has ever
--   been written for any of them.
--
-- THE FIX
--
--   Resolve each table's key column against the database instead of assuming
--   it: the first candidate that actually exists wins. A database still on the
--   older shape keeps its <table>_id key, this one gets encounter_id, and both
--   end up audited.
--
--   audit_clinical_change also gains an actor fallback. These four tables carry
--   no recorded_by / administered_by of their own -- who performed the
--   encounter lives on the parent clinical_encounters row -- so without it
--   every one of these audit rows would be attributed to "System".
--
-- Idempotent: CREATE OR REPLACE plus DROP TRIGGER IF EXISTS. Re-running is
-- safe, and the five tables that were already audited are left untouched.
--
-- Depends on: 20260826_audit_trail_completeness.sql
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The trigger function, with the parent-encounter actor fallback.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.audit_clinical_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_row     RECORD;
  v_pk      TEXT := TG_ARGV[0];
  v_label   TEXT := TG_ARGV[1];
  v_actor   BIGINT;
  v_action  TEXT;
  v_id      TEXT;
  v_fields  TEXT := '';
  v_count   INTEGER := 0;
  k         TEXT;
  v_json    JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_row := OLD;
  ELSE
    v_row := NEW;
  END IF;

  v_json := to_jsonb(v_row);
  v_id   := v_json->>v_pk;

  IF TG_OP = 'UPDATE' AND to_jsonb(OLD) = to_jsonb(NEW) THEN
    RETURN NULL;
  END IF;

  -- Whichever of these the table happens to carry. audit_bigint rather than a
  -- cast: created_by is a VARCHAR that can hold 'self', and a failed cast here
  -- would abort the caller's write.
  v_actor := COALESCE(
    public.audit_bigint(v_json->>'recorded_by'),
    public.audit_bigint(v_json->>'administered_by'),
    public.audit_bigint(v_json->>'created_by'),
    public.audit_bigint(v_json->>'midwife_id'),
    public.audit_bigint(v_json->>'performed_by')
  );

  -- The four encounter extension tables (prenatal_checkups, lab_tests,
  -- ultrasounds, deliveries) carry none of those columns: who performed the
  -- encounter is recorded once, on the parent clinical_encounters row. Without
  -- this fallback the audit row for a lab test names no one, which is most of
  -- the point of auditing it. recorded_by holds a midwife_id; audit_actor
  -- resolves either that or an account_id through resolve_actor_account_id.
  IF v_actor IS NULL AND v_json ? 'encounter_id' THEN
    SELECT ce.recorded_by INTO v_actor
      FROM public.clinical_encounters ce
     WHERE ce.encounter_id = public.audit_bigint(v_json->>'encounter_id');
  END IF;

  v_action := CASE TG_OP
                WHEN 'INSERT' THEN 'create_' || v_label
                WHEN 'DELETE' THEN 'delete_' || v_label
                ELSE 'update_' || v_label
              END;

  IF TG_OP = 'UPDATE' THEN
    FOR k IN SELECT jsonb_object_keys(to_jsonb(NEW)) LOOP
      IF to_jsonb(OLD)->k IS DISTINCT FROM to_jsonb(NEW)->k THEN
        v_count  := v_count + 1;
        v_fields := v_fields || replace(k, '_', ' ') || ', ';
      END IF;
    END LOOP;
    v_fields := rtrim(v_fields, ', ');
  END IF;

  PERFORM public.audit_write(
    v_actor, v_action, TG_TABLE_NAME, v_id,
    format('%s #%s', initcap(replace(v_label, '_', ' ')), v_id),
    format('%s %s #%s',
           initcap(replace(v_label, '_', ' ')),
           CASE TG_OP WHEN 'INSERT' THEN 'recorded' WHEN 'DELETE' THEN 'deleted' ELSE 'amended' END,
           v_id),
    format(
      'A %s record was %s. The record is #%s in %s. %s%s The clinical values themselves are held in the '
      'before and after snapshots on this entry and are shown only to accounts cleared to read patient data.',
      replace(v_label, '_', ' '),
      CASE TG_OP WHEN 'INSERT' THEN 'created' WHEN 'DELETE' THEN 'deleted' ELSE 'amended' END,
      v_id, TG_TABLE_NAME,
      format('Recorded by %s on %s.',
             COALESCE((public.audit_actor(v_actor))->>'name', 'an unrecorded account'),
             public.audit_ts(now())),
      CASE WHEN TG_OP = 'UPDATE'
           THEN format(' %s field(s) changed: %s.', v_count, v_fields)
           ELSE '' END),
    public.audit_section('Record',
      public.audit_kv('Record type', initcap(replace(v_label, '_', ' ')))
      || public.audit_kv('Record number', '#' || v_id)
      || public.audit_kv('Table', TG_TABLE_NAME)
      || public.audit_kv('Recorded by', (public.audit_actor(v_actor))->>'name')
      || public.audit_kv('Fields changed', nullif(v_fields, ''))),
    jsonb_build_object('record_id', v_id, 'table', TG_TABLE_NAME,
                       'mother_id', v_json->>'mother_id',
                       'child_id', v_json->>'child_id',
                       'pregnancy_id', v_json->>'pregnancy_id'),
    CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
    NULL, lower(TG_OP)
  );

  RETURN NULL;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 2. Attach the trigger to the four encounter extension tables.
--
-- Attached by name, and by whichever key column is really there, so a database
-- missing any one of these tables still applies the rest.
-- ---------------------------------------------------------------------------
DO $do$
DECLARE
  r    RECORD;
  v_pk TEXT;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('prenatal_checkups', ARRAY['prenatal_checkup_id', 'encounter_id'], 'prenatal_checkup'),
      ('lab_tests',         ARRAY['lab_test_id',         'encounter_id'], 'lab_test'),
      ('ultrasounds',       ARRAY['ultrasound_id',       'encounter_id'], 'ultrasound'),
      ('deliveries',        ARRAY['delivery_id',         'encounter_id'], 'delivery')
    ) AS t(tbl, pks, label)
  LOOP
    IF to_regclass(format('public.%I', r.tbl)) IS NULL THEN
      RAISE NOTICE 'Skipping audit trigger: table % does not exist', r.tbl;
      CONTINUE;
    END IF;

    -- First candidate that exists wins, so the older <table>_id shape and the
    -- current encounter_id shape are both handled by this one file.
    SELECT want.name INTO v_pk
      FROM unnest(r.pks) WITH ORDINALITY AS want(name, ord)
      JOIN information_schema.columns c
        ON c.table_schema = 'public'
       AND c.table_name   = r.tbl
       AND c.column_name  = want.name
     ORDER BY want.ord
     LIMIT 1;

    IF v_pk IS NULL THEN
      RAISE NOTICE 'Skipping audit trigger on %: none of % exist as columns',
        r.tbl, r.pks;
      CONTINUE;
    END IF;

    EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_clinical_%I ON public.%I',
                   r.tbl, r.tbl);
    EXECUTE format(
      'CREATE TRIGGER trg_audit_clinical_%I AFTER INSERT OR UPDATE OR DELETE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.audit_clinical_change(%L, %L)',
      r.tbl, r.tbl, v_pk, r.label);

    RAISE NOTICE 'Audit trigger on % keyed by %', r.tbl, v_pk;
  END LOOP;
END
$do$;

GRANT EXECUTE ON FUNCTION public.audit_clinical_change() TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- All nine clinical tables should now carry a trigger, these four included:
--
--   SELECT c.relname AS table_name, t.tgname
--     FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
--    WHERE t.tgname LIKE 'trg_audit_clinical_%'
--    ORDER BY 1;
--
-- And a lab test recorded from the phone should leave a row naming the midwife
-- who recorded it rather than "System":
--
--   SELECT action_timestamp, action, table_name, row_id, actor_name, description
--     FROM public.audit_trail
--    WHERE table_name IN ('lab_tests','ultrasounds','deliveries','prenatal_checkups')
--    ORDER BY audit_id DESC LIMIT 20;
