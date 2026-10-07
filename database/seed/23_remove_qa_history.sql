-- Remove remaining explicitly marked QA/Codex audit history and QA email records.
-- Run after 20 and 22. Embedded image bytes and credentials are not QA evidence.
-- Preserves every other public row, except normal audit change notifications.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '45s';

CREATE OR REPLACE FUNCTION pg_temp.qa_marker_text(p_value jsonb)
RETURNS text LANGUAGE sql IMMUTABLE AS $marker$
WITH RECURSIVE nodes(value,key) AS (
  SELECT p_value,NULL::text
  UNION ALL
  SELECT child.value,child.key FROM nodes n CROSS JOIN LATERAL (
    SELECT e.value,e.key FROM jsonb_each(CASE WHEN jsonb_typeof(n.value)='object' THEN n.value ELSE '{}'::jsonb END) e
    UNION ALL
    SELECT e.value,NULL::text FROM jsonb_array_elements(CASE WHEN jsonb_typeof(n.value)='array' THEN n.value ELSE '[]'::jsonb END) e
  ) child
  WHERE COALESCE(child.key,'') !~* '(password|token|secret|verification_code|reset_code|api_key)'
)
SELECT COALESCE(string_agg(value#>>'{}',' '),'') FROM nodes
WHERE jsonb_typeof(value)='string' AND (value#>>'{}') !~* '^data:[^,]*;base64,';
$marker$;

CREATE TEMP TABLE history_qa_audits ON COMMIT DROP AS
SELECT audit_id FROM public.audit_trail a
WHERE pg_temp.qa_marker_text(to_jsonb(a)) ~* '\m(codex|qa)\M|@qa[.]test';
CREATE TEMP TABLE history_qa_emails ON COMMIT DROP AS
SELECT email_id FROM public.email_queue WHERE recipient ~* '@qa[.]test$';

CREATE TEMP TABLE history_protected_rows (
  table_name text PRIMARY KEY, row_count bigint, fingerprint text
) ON COMMIT DROP;
DO $snapshot$
DECLARE t record; n bigint; digest text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE contype='f'
    AND confrelid IN ('public.audit_trail'::regclass,'public.email_queue'::regclass)) THEN
    RAISE EXCEPTION 'QA history cleanup aborted: history tables have referencing foreign keys.';
  END IF;
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='public'
    AND tablename NOT IN ('audit_trail','email_queue','admin_change_events')
  LOOP
    EXECUTE format('SELECT count(*), md5(COALESCE(string_agg(md5(to_jsonb(r)::text),'''' ORDER BY md5(to_jsonb(r)::text)),'''')) FROM public.%I r',t.tablename)
      INTO n,digest;
    INSERT INTO history_protected_rows VALUES(t.tablename,n,digest);
  END LOOP;
END;
$snapshot$;
CREATE TEMP TABLE history_protected_audits ON COMMIT DROP AS
SELECT audit_id,to_jsonb(a) AS original_row FROM public.audit_trail a
WHERE audit_id NOT IN (SELECT audit_id FROM history_qa_audits);
CREATE TEMP TABLE history_protected_emails ON COMMIT DROP AS
SELECT email_id,to_jsonb(e) AS original_row FROM public.email_queue e
WHERE email_id NOT IN (SELECT email_id FROM history_qa_emails);

-- All target rows are frozen before deletion. The application audit trigger
-- emits its usual admin refresh notification and prunes expired notifications.
DELETE FROM public.email_queue WHERE email_id IN (SELECT email_id FROM history_qa_emails);
DELETE FROM public.audit_trail WHERE audit_id IN (SELECT audit_id FROM history_qa_audits);

DO $verify$
DECLARE t record; n bigint; digest text;
BEGIN
  FOR t IN SELECT * FROM history_protected_rows LOOP
    EXECUTE format('SELECT count(*), md5(COALESCE(string_agg(md5(to_jsonb(r)::text),'''' ORDER BY md5(to_jsonb(r)::text)),'''')) FROM public.%I r',t.table_name)
      INTO n,digest;
    IF n IS DISTINCT FROM t.row_count OR digest IS DISTINCT FROM t.fingerprint THEN
      RAISE EXCEPTION 'QA history cleanup aborted: protected table % changed.',t.table_name;
    END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM history_protected_audits p FULL JOIN public.audit_trail a USING(audit_id)
    WHERE p.original_row IS DISTINCT FROM to_jsonb(a)) OR
    EXISTS(SELECT 1 FROM history_protected_emails p FULL JOIN public.email_queue e USING(email_id)
    WHERE p.original_row IS DISTINCT FROM to_jsonb(e)) THEN
    RAISE EXCEPTION 'QA history cleanup aborted: ordinary history or email changed.';
  END IF;
END;
$verify$;
SELECT (SELECT count(*) FROM history_qa_audits) AS removed_qa_audits,
       (SELECT count(*) FROM history_qa_emails) AS removed_qa_emails;
COMMIT;
