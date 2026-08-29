-- ==============================================================================
-- SEED 00 — RESET THE INVENTORY
--
-- Clears every inventory row so 01-03 can lay down a clean catalogue and a full
-- set of allocations. Run this first, or run nothing at all: 01-03 assume they
-- are starting from an empty inventory.
--
-- WHAT IT CLEARS
--   inventory_transactions      the whole movement ledger
--   inventory_transfers         dispatches between facilities
--   inventory_stock_requests    requests and their approvals
--   inventory_disposals         expiry and discard records, where present
--   inventory_batches           all physical stock, at every facility
--   inventory_items             the catalogue itself
--
-- WHAT IT KEEPS
--   Facilities, accounts, midwives, mothers, pregnancies, encounters,
--   immunisation records, prenatal checkups. Nothing clinical is touched.
--
-- WHAT IT COSTS, AND IT IS NOT NOTHING
--   The movement ledger is the audit trail for stock. Clearing it discards the
--   record of every receipt, dispatch and dispense this database has ever held,
--   including the prenatal deductions and the 150-unit reconciliation. The
--   clinical records survive -- a checkup still says which tablets were handed
--   over -- but the stock side of that story is gone and cannot be rebuilt.
--
--   Sensible on a demo or a database being prepared for a defence. Not
--   something to run against a live health centre.
--
-- WHY THE UNLINKING COMES FIRST
--   Three clinical tables point at batches, and they do not all allow the batch
--   to vanish underneath them:
--
--     given_medications.inventory_batch_id     ON DELETE RESTRICT
--     maternal_td_records.inventory_batch_id   no ON DELETE clause (NO ACTION)
--     immunization_records.inventory_batch_id  ON DELETE SET NULL
--
--   The first two block the delete outright. So every link is cleared first,
--   which keeps the clinical row and drops only its pointer to stock that is
--   about to stop existing. vaccines.inventory_item_id is unlinked for the same
--   reason before the catalogue goes.
--
-- Safe to run more than once.
-- ==============================================================================

BEGIN;

-- 1. Unlink clinical records from the stock they drew on -----------------------
UPDATE public.given_medications    SET inventory_batch_id = NULL WHERE inventory_batch_id IS NOT NULL;
UPDATE public.maternal_td_records  SET inventory_batch_id = NULL WHERE inventory_batch_id IS NOT NULL;
UPDATE public.immunization_records SET inventory_batch_id = NULL WHERE inventory_batch_id IS NOT NULL;

-- maternal_td_records.inventory_deducted means "stock moved for this dose", and
-- the stock is about to be gone. Leaving it true would assert a deduction with
-- no batch and no ledger row behind it -- exactly what 20260905 fixed.
UPDATE public.maternal_td_records SET inventory_deducted = false WHERE inventory_deducted;

-- 2. The workflow tables -------------------------------------------------------
-- Order matters: transfers and reports reference batches with RESTRICT.
DELETE FROM public.inventory_transactions;
DELETE FROM public.inventory_transfers;
DELETE FROM public.inventory_stock_requests;

-- Two tables that exist only on databases that ran the later migrations.
-- Guarded so this file works either way.
DO $opt$
BEGIN
  IF to_regclass('public.inventory_unusable_stock_reports') IS NOT NULL THEN
    EXECUTE 'DELETE FROM public.inventory_unusable_stock_reports';
  END IF;
  IF to_regclass('public.inventory_disposals') IS NOT NULL THEN
    EXECUTE 'DELETE FROM public.inventory_disposals';
  END IF;
END
$opt$;

-- 3. Stock, then the catalogue -------------------------------------------------
DELETE FROM public.inventory_batches;

UPDATE public.vaccines SET inventory_item_id = NULL WHERE inventory_item_id IS NOT NULL;
DELETE FROM public.inventory_items;

-- 4. Sequences back to the start so the new catalogue numbers from 1 -----------
SELECT setval(pg_get_serial_sequence('public.inventory_items',        'item_id'),        1, false);
SELECT setval(pg_get_serial_sequence('public.inventory_batches',      'batch_id'),       1, false);
SELECT setval(pg_get_serial_sequence('public.inventory_transactions', 'transaction_id'), 1, false);

COMMIT;


-- ---------------------------------------------------------------------------
-- Everything should read 0. Then run 01, 02 and 03 in order.
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.inventory_items)          AS items,
  (SELECT count(*) FROM public.inventory_batches)        AS batches,
  (SELECT count(*) FROM public.inventory_transactions)   AS ledger_rows,
  (SELECT count(*) FROM public.inventory_transfers)      AS transfers,
  (SELECT count(*) FROM public.inventory_stock_requests) AS requests;
