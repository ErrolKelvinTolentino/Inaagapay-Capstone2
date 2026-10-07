-- Remove explicitly named Codex QA facilities from both facility tables.
-- Includes unused synthetic revision stock at those facilities; keeps the
-- regular catalogue, all accounts, clinical records and other facilities.
-- Refuses linked operational records or consumed stock rather than cascading
-- into them. Run after 20_remove_qa_fixtures.sql. Safe to re-run.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '45s';

CREATE TEMP TABLE facility_qa_targets ON COMMIT DROP AS
SELECT facility_id FROM public.health_facilities
WHERE name ~* '^Codex (MW )?QA ';
CREATE TEMP TABLE facility_qa_bhc_targets ON COMMIT DROP AS
SELECT bhc_id FROM public.bhc WHERE bhc_name ~* '^Codex (MW )?QA ';
CREATE TEMP TABLE facility_qa_batches ON COMMIT DROP AS
SELECT batch_id FROM public.inventory_batches
WHERE facility_id IN (SELECT facility_id FROM facility_qa_targets);
CREATE TEMP TABLE facility_qa_transactions ON COMMIT DROP AS
SELECT transaction_id FROM public.inventory_transactions
WHERE batch_id IN (SELECT batch_id FROM facility_qa_batches);

CREATE TEMP TABLE facility_protected_accounts ON COMMIT DROP AS
SELECT account_id FROM public.accounts;
CREATE TEMP TABLE facility_protected_rows ON COMMIT DROP AS
SELECT facility_id, to_jsonb(f) AS original_row FROM public.health_facilities f
WHERE facility_id NOT IN (SELECT facility_id FROM facility_qa_targets);
CREATE TEMP TABLE facility_protected_bhc ON COMMIT DROP AS
SELECT bhc_id, to_jsonb(b) AS original_row FROM public.bhc b
WHERE bhc_id NOT IN (SELECT bhc_id FROM facility_qa_bhc_targets);
CREATE TEMP TABLE facility_protected_stock ON COMMIT DROP AS
SELECT batch_id, to_jsonb(b) AS original_row FROM public.inventory_batches b
WHERE batch_id NOT IN (SELECT batch_id FROM facility_qa_batches);

DO $guard$
DECLARE
  v_fk RECORD;
  v_linked BOOLEAN;
BEGIN
  -- No parent, assignment, clinical or other operational reference is removed
  -- simply because its facility is a fixture. Only the inspected stock rows
  -- and receipt ledger are permitted below.
  FOR v_fk IN
    SELECT c.conrelid::regclass AS table_name, a.attname AS column_name
    FROM pg_constraint c JOIN pg_attribute a
      ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
    WHERE c.contype='f' AND c.confrelid='public.health_facilities'::regclass
      AND c.conrelid NOT IN ('public.health_facilities'::regclass,
        'public.inventory_batches'::regclass, 'public.inventory_transactions'::regclass)
  LOOP
    EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE %I IN (SELECT facility_id FROM facility_qa_targets))',
      v_fk.table_name,v_fk.column_name) INTO v_linked;
    IF v_linked THEN
      RAISE EXCEPTION 'QA facility cleanup aborted: % still references a selected facility.',v_fk.table_name;
    END IF;
  END LOOP;
  FOR v_fk IN
    SELECT c.conrelid::regclass AS table_name, a.attname AS column_name
    FROM pg_constraint c JOIN pg_attribute a
      ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
    WHERE c.contype='f' AND c.confrelid='public.bhc'::regclass
  LOOP
    EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE %I IN (SELECT bhc_id FROM facility_qa_bhc_targets))',
      v_fk.table_name,v_fk.column_name) INTO v_linked;
    IF v_linked THEN
      RAISE EXCEPTION 'QA facility cleanup aborted: % still references a selected legacy BHC.',v_fk.table_name;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.health_facilities f
    WHERE f.parent_facility_id IN (SELECT facility_id FROM facility_qa_targets)
      AND f.facility_id NOT IN (SELECT facility_id FROM facility_qa_targets)) THEN
    RAISE EXCEPTION 'QA facility cleanup aborted: an ordinary facility has a QA parent.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.inventory_batches b
    WHERE b.batch_id IN (SELECT batch_id FROM facility_qa_batches)
      AND (b.batch_number NOT LIKE 'REV-20261007-%'
        AND b.batch_number NOT ILIKE 'CODEX-MW-QA-%'
        AND b.batch_number NOT ILIKE 'QA-CODEX-%'))
    OR EXISTS (SELECT 1 FROM public.inventory_batches b
      WHERE b.batch_id IN (SELECT batch_id FROM facility_qa_batches)
        AND (b.quantity_remaining IS DISTINCT FROM b.quantity_received
          OR COALESCE(b.doses_remaining_in_open_vial,0)<>0)) THEN
    RAISE EXCEPTION 'QA facility cleanup aborted: facility stock is unmarked or has been consumed.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.inventory_transactions t
    WHERE (t.facility_id IN (SELECT facility_id FROM facility_qa_targets)
      AND t.batch_id NOT IN (SELECT batch_id FROM facility_qa_batches))
      OR (t.batch_id IN (SELECT batch_id FROM facility_qa_batches)
        AND t.transaction_type<>'receipt')) THEN
    RAISE EXCEPTION 'QA facility cleanup aborted: the stock ledger contains operational movements.';
  END IF;
  FOR v_fk IN
    SELECT c.conrelid::regclass AS table_name, a.attname AS column_name
    FROM pg_constraint c JOIN pg_attribute a
      ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
    WHERE c.contype='f' AND c.confrelid='public.inventory_batches'::regclass
      AND c.conrelid<>'public.inventory_transactions'::regclass
  LOOP
    EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE %I IN (SELECT batch_id FROM facility_qa_batches))',
      v_fk.table_name,v_fk.column_name) INTO v_linked;
    IF v_linked THEN
      RAISE EXCEPTION 'QA facility cleanup aborted: % still uses fixture stock.',v_fk.table_name;
    END IF;
  END LOOP;
END;
$guard$;

DELETE FROM public.inventory_transactions WHERE transaction_id IN (SELECT transaction_id FROM facility_qa_transactions);
DELETE FROM public.inventory_batches WHERE batch_id IN (SELECT batch_id FROM facility_qa_batches);
DELETE FROM public.bhc WHERE bhc_id IN (SELECT bhc_id FROM facility_qa_bhc_targets);
DELETE FROM public.health_facilities WHERE facility_id IN (SELECT facility_id FROM facility_qa_targets);
DELETE FROM public.audit_trail a
WHERE (a.table_name='health_facilities' AND a.row_id::text IN (SELECT facility_id::text FROM facility_qa_targets))
   OR (a.table_name='bhc' AND a.row_id::text IN (SELECT bhc_id::text FROM facility_qa_bhc_targets))
   OR (a.table_name='inventory_batches' AND a.row_id::text IN (SELECT batch_id::text FROM facility_qa_batches))
   OR (a.table_name='inventory_transactions' AND a.row_id::text IN (SELECT transaction_id::text FROM facility_qa_transactions));

DO $preserve$
BEGIN
  IF EXISTS (SELECT 1 FROM facility_protected_accounts p
    WHERE NOT EXISTS(SELECT 1 FROM public.accounts a WHERE a.account_id=p.account_id))
    OR EXISTS (SELECT 1 FROM facility_protected_rows p LEFT JOIN public.health_facilities f USING(facility_id)
      WHERE f.facility_id IS NULL OR to_jsonb(f) IS DISTINCT FROM p.original_row)
    OR EXISTS (SELECT 1 FROM facility_protected_bhc p LEFT JOIN public.bhc b USING(bhc_id)
      WHERE b.bhc_id IS NULL OR to_jsonb(b) IS DISTINCT FROM p.original_row)
    OR EXISTS (SELECT 1 FROM facility_protected_stock p LEFT JOIN public.inventory_batches b USING(batch_id)
      WHERE b.batch_id IS NULL OR to_jsonb(b) IS DISTINCT FROM p.original_row) THEN
    RAISE EXCEPTION 'QA facility cleanup aborted: a protected account, facility or batch changed.';
  END IF;
END;
$preserve$;
COMMIT;

SELECT (SELECT count(*) FROM public.bhc WHERE bhc_name ~* '^Codex (MW )?QA ') AS remaining_qa_bhc,
  (SELECT count(*) FROM public.health_facilities WHERE name ~* '^Codex (MW )?QA ') AS remaining_qa_facilities,
  (SELECT count(*) FROM public.accounts) AS remaining_accounts;
