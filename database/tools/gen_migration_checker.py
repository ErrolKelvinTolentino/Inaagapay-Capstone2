"""Generates database/migrations/00_check_migration_state.sql.

    python database/tools/gen_migration_checker.py

Re-run it after adding a migration, and commit the regenerated file.

One read-only query, one row per migration file. Every probe is derived from
what the file itself creates; function replacements are detected by a line of
the function body that no earlier version contains.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIG = os.path.join(ROOT, 'migrations')

files = sorted(f for f in os.listdir(MIG) if f.endswith('.sql') and not f.startswith('0'))
dated = [f for f in files if re.match(r'\d{8}_', f)]
undated = [f for f in files if f not in dated]
ORDER = undated + dated

strip_comments = lambda s: re.sub(r'--[^\n]*', '', s)
fnre = re.compile(r'create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?(\w+)"?\s*\(.*?\bas\s+(\$\w*\$)(.*?)\2', re.I | re.S)
pat = {
    'table': re.compile(r'create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?(\w+)', re.I),
    'column': re.compile(r'alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?(?:public\.)?(\w+)\s+add\s+column\s+(?:if\s+not\s+exists\s+)?(\w+)', re.I),
    'view': re.compile(r'create\s+(?:or\s+replace\s+)?(?:materialized\s+)?view\s+(?:public\.)?(\w+)', re.I),
    'trigger': re.compile(r'create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+(\w+)', re.I),
    'index': re.compile(r'create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?(\w+)', re.I),
    'cron': re.compile(r"cron\.schedule\(\s*'([^']+)'", re.I),
}

src = {f: open(os.path.join(MIG, f), encoding='utf-8', errors='ignore').read() for f in ORDER}

# ---- function versions ------------------------------------------------------
versions = {}
for f in ORDER:
    seen = {}
    for m in fnre.finditer(src[f]):
        seen[m.group(1).lower()] = m.group(3)      # last definition in a file wins
    for name, body in seen.items():
        versions.setdefault(name, []).append((f, body))

# Hand-picked where no single line tells a version from the ones before it.
# ('+', text): body contains text.  ('-', text): body lacks text.  None: exists.
MANUAL = {
    ('20260807_issue_respects_approved_quantity.sql', 'issue_inventory_transfer'):
        ('+', 'in its approved quantity (%)'),
    ('20260815_fix_deduct_immunization_stock_performed_by.sql', 'deduct_immunization_stock'):
        ('+', "Log audit transaction ledger entry with performing midwife"),
    ('20260821_inventory_and_td_fixes.sql', 'normalize_td_dose'): None,  # whitespace-only change
    ('20260823_prenatal_dispense_fixes.sql', 'deduct_prenatal_encounter_inventory'):
        ('+', 'v_outstanding  INTEGER;'),
    ('20260826_audit_trail_completeness.sql', 'announce_inventory_transfer'):
        ('-', 'INSERT INTO public.audit_trail'),
    ('20260829_inventory_transfer_directions.sql', 'announce_inventory_transfer'):
        ('+', 'COALESCE(NEW.transfer_direction'),
    ('20260909_notification_reference_ids.sql', 'announce_inventory_transfer'):
        ('+', 'notification centre now dedupes against inventory_transfers'),
    ('20260905_maternal_td_deduction_flag_truthful.sql', 'sync_prenatal_td_to_maternal_records'):
        ('+', 'trg_maternal_td_mark_deducted flips this when a vial actually moves'),
    ('20260913_fix_audit_account_change_type_mismatch.sql', 'audit_account_change'):
        ('+', "THEN '[]'::jsonb ELSE public.audit_kv('E-mail'"),
}

BS = chr(92)


def body_lines(b):
    out = []
    for raw in b.split('\n'):
        t = re.sub(r'\s+--.*$', '', raw.strip()).strip()
        if len(t) >= 14 and not t.startswith('--') and BS not in t:
            out.append(t)
    return out


def marker_for(name, k):
    vs = versions[name]
    f, body = vs[k]
    if (f, name) in MANUAL:
        mk = MANUAL[(f, name)]
    elif k == 0:
        mk = None
    else:
        earlier = [b for j, (f2, b) in enumerate(vs) if j < k]
        cand = [l for l in body_lines(body) if not any(l in e for e in earlier)]
        if not cand:
            sys.exit(f'no marker for {name} in {f}')
        cand.sort(key=lambda l: -min(len(l), 70))
        mk = ('+', cand[0][:90])
    # Verify against the bodies it must distinguish.
    if mk:
        sign, text = mk
        if sign == '+':
            assert text in body, (f, name, text)
            assert not any(text in b for j, (f2, b) in enumerate(vs) if j < k), (f, name, text)
        else:
            assert text not in body, (f, name, text)
            assert text in vs[k - 1][1], (f, name, text)
    return mk


def q(s):
    return "'" + s.replace("'", "''") + "'"


def fn_expr(name, k):
    """This version of the function, or any later one, is live."""
    parts = []
    for j in range(k, len(versions[name])):
        mk = marker_for(name, j)
        if mk is None:
            return f"EXISTS (SELECT 1 FROM procs WHERE proname = {q(name)})"
        sign, text = mk
        op = '> 0' if sign == '+' else '= 0'
        parts.append(f"EXISTS (SELECT 1 FROM procs WHERE proname = {q(name)} AND position({q(text)} IN prosrc) {op})")
    return '(' + '\n            OR '.join(parts) + ')'


def guarded(tables, expr):
    """A data check that must not fail to parse when a table is missing."""
    cond = ' OR '.join(f"to_regclass({q(t)}) IS NULL" for t in tables)
    return (f"CASE WHEN {cond} THEN false ELSE (xpath('/row/b/text()', query_to_xml(\n"
            f"              $q$SELECT ({expr}) AS b$q$, false, true, '')))[1]::text = 'true' END")


DATA = {
    '20260803_inventory_notifications_realtime.sql': [
        ('notifications in the realtime publication',
         "EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' "
         "AND schemaname = 'public' AND tablename = 'notifications')")],
    '20260808_created_by_allows_account_ids.sql': [
        ('accounts_created_by_check accepts account ids',
         "EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'accounts_created_by_check' "
         "AND position('[0-9]' IN pg_get_constraintdef(oid)) > 0)")],
    '20260809_postnatal_milestones_doh.sql': [
        ('157 DOH postnatal milestone templates (data)',
         guarded(['public.milestone_templates'],
                 "SELECT count(*) >= 157 FROM public.milestone_templates WHERE template_key LIKE 'pn-%'"))],
    '20260821_dedupe_facility_assignments.sql': [
        ('one active facility assignment per account (data)',
         guarded(['public.facility_assignments'],
                 "NOT EXISTS (SELECT 1 FROM public.facility_assignments WHERE COALESCE(is_active, true) "
                 "GROUP BY account_id HAVING count(*) > 1)"))],
    '20260825_vaccine_catalogue_corrections.sql': [
        ('IPV is a 5-dose vial and Rotavirus is stocked (data)',
         guarded(['public.inventory_items'],
                 "NOT EXISTS (SELECT 1 FROM public.inventory_items WHERE item_type = 'vaccine' "
                 "AND name ILIKE '%ipv%' AND doses_per_unit <> 5) AND EXISTS (SELECT 1 FROM "
                 "public.inventory_items WHERE name ILIKE '%rotavirus%')"))],
    '20260827_pregnancy_care_milestones.sql': [
        ('prenatal care milestone templates (data)',
         guarded(['public.milestone_templates'],
                 "EXISTS (SELECT 1 FROM public.milestone_templates WHERE template_key = 'gestational-diabetes-screening')"))],
    '20260828_split_early_pregnancy_labs.sql': [
        ('early pregnancy labs split into separate templates (data)',
         guarded(['public.milestone_templates'],
                 "EXISTS (SELECT 1 FROM public.milestone_templates WHERE template_key = 'hiv-screening')"))],
    '20260830_repair_failed_pregnancy_conclusions.sql': [
        ('no duplicate pregnancy outcome rows (data)',
         guarded(['public.pregnancy_outcomes'],
                 "NOT EXISTS (SELECT 1 FROM public.pregnancy_outcomes GROUP BY pregnancy_id, fetus_number HAVING count(*) > 1)"))],
    '20260902_backfill_undeducted_prenatal_supplements.sql': [
        ('no supplement dispensed before 2026-08-30 still undeducted (data)',
         guarded(['public.given_medications'],
                 "NOT EXISTS (SELECT 1 FROM public.given_medications WHERE encounter_id IS NOT NULL "
                 "AND inventory_batch_id IS NULL AND date_given < DATE '2026-08-30')"))],
    '20260903_drop_legacy_given_medication_deduct_trigger.sql': [
        ('legacy trigger trg_deduct_inventory_medication removed',
         "NOT EXISTS (SELECT 1 FROM trgs WHERE tgname = 'trg_deduct_inventory_medication')")],
    '20260907_move_misplaced_rhu3_batch.sql': [
        ('batch #235 is no longer filed to the warehouse (data)',
         guarded(['public.inventory_batches'],
                 "NOT EXISTS (SELECT 1 FROM public.inventory_batches WHERE batch_id = 235 AND facility_id IS NULL)"))],
    '20260908_remove_test_inventory_item.sql': [
        ('no active inventory item named "Test" (data)',
         guarded(['public.inventory_items'],
                 "NOT EXISTS (SELECT 1 FROM public.inventory_items WHERE btrim(lower(name)) = 'test' AND NOT COALESCE(is_archived, false))"))],
    '20260924_maternal_td_records_readable.sql': [
        ('maternal_td_records readable (row level security off)',
         "COALESCE((SELECT NOT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.maternal_td_records')), false)")],
}


def probes_for(f):
    s = strip_comments(src[f])
    out = []
    seen = set()

    def add(label, expr):
        if label not in seen:
            seen.add(label)
            out.append((label, expr))

    for m in pat['table'].finditer(s):
        t = m.group(1)
        add(f'table {t}', f"to_regclass({q('public.' + t)}) IS NOT NULL")
    for m in pat['column'].finditer(s):
        t, c = m.group(1), m.group(2)
        add(f'column {t}.{c}', f"EXISTS (SELECT 1 FROM cols WHERE table_name = {q(t)} AND column_name = {q(c)})")
    for m in pat['view'].finditer(s):
        v = m.group(1)
        add(f'view {v}', f"to_regclass({q('public.' + v)}) IS NOT NULL")
    names = []
    for m in fnre.finditer(src[f]):
        n = m.group(1).lower()
        if n not in names:
            names.append(n)
    for n in names:
        k = [j for j, (f2, _) in enumerate(versions[n]) if f2 == f][0]
        label = f'function {n}()' if len(versions[n]) == 1 or k == 0 else f'function {n}() at this version'
        add(label, fn_expr(n, k))
    for m in pat['trigger'].finditer(s):
        t = m.group(1)
        if t.endswith('_'):
            continue  # built dynamically per table
        add(f'trigger {t}', f"EXISTS (SELECT 1 FROM trgs WHERE tgname = {q(t)})")
    for m in pat['index'].finditer(s):
        i = m.group(1)
        add(f'index {i}', f"to_regclass({q('public.' + i)}) IS NOT NULL")
    for m in pat['cron'].finditer(s):
        j = m.group(1)
        add(f'scheduled job {j}',
            f"CASE WHEN to_regclass('cron.job') IS NULL THEN false ELSE (xpath('/row/b/text()', query_to_xml(\n"
            f"              $q$SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = {q(j)}) AS b$q$, false, true, '')))[1]::text = 'true' END")
    for label, expr in DATA.get(f, []):
        add(label, expr)
    if not out:
        sys.exit(f'no probe for {f}')
    return out


rows = [
    (0, 'baseline schema', 'table accounts', "to_regclass('public.accounts') IS NOT NULL"),
    (0, 'baseline schema', 'table health_facilities', "to_regclass('public.health_facilities') IS NOT NULL"),
    (0, 'baseline schema', 'table facility_assignments', "to_regclass('public.facility_assignments') IS NOT NULL"),
    (0, 'baseline schema', 'table mothers', "to_regclass('public.mothers') IS NOT NULL"),
    (0, 'baseline schema', 'table inventory_items', "to_regclass('public.inventory_items') IS NOT NULL"),
    (0, 'baseline schema', 'table inventory_batches', "to_regclass('public.inventory_batches') IS NOT NULL"),
    (0, 'baseline schema', 'table inventory_transactions', "to_regclass('public.inventory_transactions') IS NOT NULL"),
]
for i, f in enumerate(ORDER, start=1):
    for j, (label, expr) in enumerate(probes_for(f)):
        rows.append((i * 100 + j, f, label, expr))

values = ',\n'.join(f"    ({so}, {q(f)}, {q(label)},\n          {expr})" for so, f, label, expr in rows)

HEADER = """\
-- ==============================================================================
-- 00_check_migration_state.sql  --  READ ONLY. Changes nothing.
--
-- GENERATED by database/tools/gen_migration_checker.py. Do not edit by hand;
-- add the migration, re-run the generator, commit both.
--
-- WHAT IT ANSWERS
--
-- "Has every migration in this folder been run?" There is no migration ledger
-- in this project -- everything is applied by hand in the SQL Editor -- so the
-- database itself is the only record. This probes for what each file creates
-- and prints ONE ROW PER MIGRATION FILE.
--
-- HOW EACH FILE IS DETECTED
--
--   tables, columns, views, indexes, triggers, scheduled jobs
--       present by name
--   functions
--       a function that several files redefine is checked by a line of its
--       body that no earlier version contains, so the probe tells the 20260823
--       deduct_prenatal_encounter_inventory from the 20260819 one. A file whose
--       function a later file has since replaced counts as OK: its effect is
--       live, carried forward.
--   data-only files (seeds, repairs, backfills)
--       checked by the state they leave behind, marked "(data)". Data can
--       change after a file runs, so a MISSING here means "look", not
--       necessarily "never run".
--
-- HOW TO READ THE RESULT
--
--   status = 'OK'        everything the file creates is present
--   status = 'MISSING'   what_is_missing lists what is absent; run that file
--
-- MISSING rows come first, in the order the files should be run. Run them top
-- to bottom, then run this again until every row says OK.
--
-- NOTE ON THE SUPABASE SQL EDITOR
--
-- The editor sends a whole script as one message, which PostgreSQL runs inside
-- a single implicit transaction. If any statement fails, EVERYTHING in that
-- script is rolled back -- including the parts that appeared to succeed before
-- the error. So a migration that stopped with an error has applied nothing, and
-- re-running it after fixing the prerequisite is both safe and necessary.
--
-- clean_and_seed_vaccines_supplements.sql carries older copies of
-- deduct_immunization_stock and deduct_prenatal_encounter_inventory. Running
-- it after the migrations shows up here as 20260821 / 20260901 MISSING; see
-- RUN_ORDER.md.
-- ==============================================================================
"""
sql = HEADER + f"""
WITH procs AS (
  SELECT p.proname::text AS proname, p.prosrc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
),
cols AS (
  SELECT table_name::text AS table_name, column_name::text AS column_name
    FROM information_schema.columns WHERE table_schema = 'public'
),
trgs AS (
  SELECT tgname::text AS tgname FROM pg_trigger WHERE NOT tgisinternal
),
checks(sort_order, migration, requirement, present) AS (
  VALUES
{values}
),
per_file AS (
  SELECT migration,
         min(sort_order) AS sort_order,
         bool_and(present) AS all_present,
         count(*) AS checks,
         count(*) FILTER (WHERE NOT present) AS missing_checks,
         string_agg(requirement, '; ' ORDER BY sort_order) FILTER (WHERE NOT present) AS missing
    FROM checks
   GROUP BY migration
)
SELECT CASE WHEN all_present THEN 'OK' ELSE 'MISSING' END AS status,
       migration,
       missing_checks || ' of ' || checks AS failed_checks,
       COALESCE(missing, '') AS what_is_missing
  FROM per_file
 ORDER BY all_present, sort_order;
"""
out_path = os.path.join(MIG, '00_check_migration_state.sql')
with open(out_path, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write(sql)
print(f'{len(ORDER)} migration files, {len(rows)} probes -> {out_path}')
