-- Final revisions: remove ONLY explicit QA fixtures, in one transaction.
-- Keeps the named demonstration families, Tarcan drives and clinical history.
-- Does not reset sequences, refill batches or delete non-QA audit history.
BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '45s';

CREATE TEMP TABLE revision_qa_accounts ON COMMIT DROP AS
SELECT account_id FROM public.accounts WHERE lower(email_address) LIKE '%@qa.test';
CREATE TEMP TABLE revision_qa_mothers ON COMMIT DROP AS
SELECT mother_id FROM public.mothers WHERE account_id IN (SELECT account_id FROM revision_qa_accounts);
CREATE TEMP TABLE revision_qa_children ON COMMIT DROP AS
SELECT child_id FROM public.children
 WHERE mother_id IN (SELECT mother_id FROM revision_qa_mothers);
CREATE TEMP TABLE revision_qa_items ON COMMIT DROP AS
SELECT item_id FROM public.inventory_items WHERE name LIKE 'Codex QA %';
CREATE TEMP TABLE revision_qa_batches ON COMMIT DROP AS
SELECT batch_id FROM public.inventory_batches
 WHERE item_id IN (SELECT item_id FROM revision_qa_items)
    OR batch_number ILIKE 'CODEX-MW-QA-%'
    OR batch_number ILIKE 'QA-CODEX-%';
CREATE TEMP TABLE revision_qa_vaccines ON COMMIT DROP AS
SELECT vaccine_id FROM public.vaccines WHERE inventory_item_id IN (SELECT item_id FROM revision_qa_items);
CREATE TEMP TABLE revision_qa_requests ON COMMIT DROP AS
SELECT request_id FROM public.inventory_stock_requests
 WHERE item_id IN (SELECT item_id FROM revision_qa_items)
    OR requested_by IN (SELECT account_id FROM revision_qa_accounts);
CREATE TEMP TABLE revision_protected_accounts ON COMMIT DROP AS
SELECT account_id FROM public.accounts
 WHERE account_id NOT IN (SELECT account_id FROM revision_qa_accounts);
CREATE TEMP TABLE revision_protected_batches ON COMMIT DROP AS
SELECT batch_id, to_jsonb(b) AS original_row FROM public.inventory_batches b
 WHERE batch_id NOT IN (SELECT batch_id FROM revision_qa_batches);
CREATE TEMP TABLE revision_qa_entities ON COMMIT DROP AS
SELECT 'accounts'::text AS table_name,account_id::text AS row_id FROM revision_qa_accounts
UNION ALL SELECT 'mothers',mother_id::text FROM revision_qa_mothers
UNION ALL SELECT 'children',child_id::text FROM revision_qa_children
UNION ALL SELECT 'inventory_items',item_id::text FROM revision_qa_items
UNION ALL SELECT 'inventory_batches',batch_id::text FROM revision_qa_batches
UNION ALL SELECT 'vaccines',vaccine_id::text FROM revision_qa_vaccines
UNION ALL SELECT 'inventory_transactions',transaction_id::text FROM public.inventory_transactions
 WHERE batch_id IN (SELECT batch_id FROM revision_qa_batches)
UNION ALL SELECT 'inventory_transfers',transfer_id::text FROM public.inventory_transfers
 WHERE source_batch_id IN (SELECT batch_id FROM revision_qa_batches)
    OR destination_batch_id IN (SELECT batch_id FROM revision_qa_batches)
UNION ALL SELECT 'inventory_stock_requests',request_id::text FROM public.inventory_stock_requests
 WHERE request_id IN (SELECT request_id FROM revision_qa_requests)
UNION ALL SELECT 'immunization_schedule',COALESCE(to_jsonb(s)->>'immunization_schedule_id',to_jsonb(s)->>'schedule_id') FROM public.immunization_schedule s
 WHERE vaccine_id IN (SELECT vaccine_id FROM revision_qa_vaccines)
    OR notes LIKE 'Codex QA %' OR notes LIKE 'QA-CODEX-%';

-- Reviewable manifest: identities are selected by explicit fixture markers,
-- never by a guessed numeric ID or a broad occurrence of the word "test".
SELECT 'QA accounts' AS kind, count(*) AS records FROM revision_qa_accounts
UNION ALL SELECT 'QA mothers', count(*) FROM revision_qa_mothers
UNION ALL SELECT 'QA children', count(*) FROM revision_qa_children
UNION ALL SELECT 'QA items', count(*) FROM revision_qa_items
UNION ALL SELECT 'QA batches', count(*) FROM revision_qa_batches;

-- Refuse to detach genuine clinical records from QA stock. If a cross-link
-- exists, investigate it instead of silently removing an inventory pointer.
DO $guard$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.given_medications g
     WHERE g.inventory_batch_id IN (SELECT batch_id FROM revision_qa_batches)
       AND NOT EXISTS (SELECT 1 FROM revision_qa_mothers m WHERE m.mother_id=g.mother_id)
  ) OR EXISTS (
    SELECT 1 FROM public.maternal_td_records td
     WHERE td.inventory_batch_id IN (SELECT batch_id FROM revision_qa_batches)
       AND NOT EXISTS (SELECT 1 FROM revision_qa_mothers m WHERE m.mother_id=td.mother_id)
  ) OR EXISTS (
    SELECT 1 FROM public.immunization_records ir
     WHERE (ir.inventory_batch_id IN (SELECT batch_id FROM revision_qa_batches)
         OR ir.vaccine_id IN (SELECT vaccine_id FROM revision_qa_vaccines))
       AND NOT EXISTS (SELECT 1 FROM revision_qa_children c WHERE c.child_id=ir.child_id)
  ) OR EXISTS (
    SELECT 1 FROM public.inventory_transfers t
     WHERE (t.source_batch_id IN (SELECT batch_id FROM revision_qa_batches)
       AND t.destination_batch_id IS NOT NULL
       AND t.destination_batch_id NOT IN (SELECT batch_id FROM revision_qa_batches))
       OR (t.source_batch_id NOT IN (SELECT batch_id FROM revision_qa_batches)
       AND t.destination_batch_id IN (SELECT batch_id FROM revision_qa_batches))
       OR (t.issued_by IN (SELECT account_id FROM revision_qa_accounts)
         AND t.source_batch_id NOT IN (SELECT batch_id FROM revision_qa_batches))
       OR (t.request_id IN (SELECT request_id FROM revision_qa_requests)
         AND t.source_batch_id NOT IN (SELECT batch_id FROM revision_qa_batches))
  ) THEN
    RAISE EXCEPTION 'QA cleanup aborted: a non-QA clinical record uses QA stock or vaccines.';
  END IF;
  IF to_regclass('public.inventory_unusable_stock_reports') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.inventory_unusable_stock_reports r
      WHERE (to_jsonb(r)->>'reported_by')::bigint IN (SELECT account_id FROM revision_qa_accounts)
        AND r.batch_id NOT IN (SELECT batch_id FROM revision_qa_batches)) THEN
      RAISE EXCEPTION 'QA cleanup aborted: a QA account reported unusable non-QA stock.';
    END IF;
  END IF;
END;
$guard$;

-- Child dependants cascade. Mothers' clinical dependants cascade on profile
-- removal. Delete profiles explicitly because their children use SET NULL.
DELETE FROM public.children WHERE child_id IN (SELECT child_id FROM revision_qa_children);
DELETE FROM public.mothers WHERE mother_id IN (SELECT mother_id FROM revision_qa_mothers);

-- Drives using a QA vaccine are themselves QA; named clinical drive seeds stay.
DELETE FROM public.immunization_schedule
 WHERE vaccine_id IN (SELECT vaccine_id FROM revision_qa_vaccines)
    OR notes LIKE 'Codex QA %' OR notes LIKE 'QA-CODEX-%';
DELETE FROM public.vaccines WHERE vaccine_id IN (SELECT vaccine_id FROM revision_qa_vaccines);

DELETE FROM public.inventory_transfers
 WHERE source_batch_id IN (SELECT batch_id FROM revision_qa_batches)
    OR destination_batch_id IN (SELECT batch_id FROM revision_qa_batches);
DELETE FROM public.inventory_stock_requests WHERE request_id IN (SELECT request_id FROM revision_qa_requests);

DO $optional$
BEGIN
  IF to_regclass('public.inventory_count_lines') IS NOT NULL THEN
    -- Only a count made entirely of QA batches is removed. A mixed count is
    -- preserved, with its QA lines removed before their batches disappear.
    EXECUTE 'DELETE FROM public.inventory_count_sessions s
      WHERE EXISTS (SELECT 1 FROM public.inventory_count_lines l WHERE l.count_id=s.count_id
        AND l.batch_id IN (SELECT batch_id FROM revision_qa_batches))
        AND NOT EXISTS (SELECT 1 FROM public.inventory_count_lines l WHERE l.count_id=s.count_id
        AND l.batch_id NOT IN (SELECT batch_id FROM revision_qa_batches))';
    EXECUTE 'DELETE FROM public.inventory_count_lines WHERE batch_id IN (SELECT batch_id FROM revision_qa_batches)';
  END IF;
  IF to_regclass('public.inventory_disposals') IS NOT NULL THEN
    EXECUTE 'DELETE FROM public.inventory_disposals WHERE batch_id IN (SELECT batch_id FROM revision_qa_batches)';
  END IF;
  IF to_regclass('public.inventory_unusable_stock_reports') IS NOT NULL THEN
    EXECUTE 'DELETE FROM public.inventory_unusable_stock_reports WHERE batch_id IN (SELECT batch_id FROM revision_qa_batches)';
  END IF;
END;
$optional$;

DELETE FROM public.inventory_batches WHERE batch_id IN (SELECT batch_id FROM revision_qa_batches);
DELETE FROM public.inventory_items WHERE item_id IN (SELECT item_id FROM revision_qa_items);
DELETE FROM public.accounts WHERE account_id IN (SELECT account_id FROM revision_qa_accounts);

-- Remove the selected fixtures' activity history too, including delete events
-- just emitted by audit triggers. Ordinary movements retain their audit trail.
DELETE FROM public.audit_trail a
 WHERE EXISTS (SELECT 1 FROM revision_qa_entities e
                WHERE e.table_name=a.table_name AND e.row_id=a.row_id::text)
    OR a.old_data->>'mother_id' IN (SELECT mother_id::text FROM revision_qa_mothers)
    OR a.new_data->>'mother_id' IN (SELECT mother_id::text FROM revision_qa_mothers)
    OR a.old_data->>'child_id' IN (SELECT child_id::text FROM revision_qa_children)
    OR a.new_data->>'child_id' IN (SELECT child_id::text FROM revision_qa_children);

-- These assertions run before COMMIT: any accidental loss of another account
-- or change to ordinary stock rolls back the entire cleanup.
DO $preservation$
BEGIN
  IF EXISTS (SELECT 1 FROM revision_protected_accounts p
    WHERE NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.account_id=p.account_id)) THEN
    RAISE EXCEPTION 'QA cleanup aborted: an account outside the QA selection was removed.';
  END IF;
  IF EXISTS (SELECT 1 FROM revision_protected_batches p LEFT JOIN public.inventory_batches b USING(batch_id)
    WHERE b.batch_id IS NULL OR to_jsonb(b) IS DISTINCT FROM p.original_row) THEN
    RAISE EXCEPTION 'QA cleanup aborted: ordinary inventory changed.';
  END IF;
END;
$preservation$;

COMMIT;

SELECT
  (SELECT count(*) FROM public.inventory_items WHERE name LIKE 'Codex QA %') AS remaining_qa_items,
  (SELECT count(*) FROM public.accounts WHERE lower(email_address) LIKE '%@qa.test') AS remaining_qa_accounts,
  (SELECT count(*) FROM public.child_immunization_coverage WHERE birthdate IS NULL) AS children_without_birthdates;
