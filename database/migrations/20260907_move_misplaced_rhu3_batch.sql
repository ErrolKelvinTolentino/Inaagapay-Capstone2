-- ==============================================================================
-- MIGRATION: 20260907_move_misplaced_rhu3_batch.sql
--
-- Puts batch #235 on the shelf it was actually received onto.
--
-- WHAT HAPPENED
--
--   The Receive Stock modal held one hardcoded destination, value="central",
--   on a disabled select. "central" resolved to NULL unconditionally, and a
--   NULL inventory_batches.facility_id IS the Municipal Warehouse. So every
--   consignment booked in through the portal landed there regardless of who
--   booked it. Fixed in admin-web/pages/inventory.html, which now resolves the
--   sentinel through PortalScope.depotFacilityId.
--
--   This corrects the one row that was written before that fix:
--
--     batch 235  BATCH-CC-1  Calcium Carbonate  3000/3000  2026-08-29
--                received by RHU Three Administrator, filed to the warehouse
--
-- WHY ONLY THIS ONE
--
--   Fourteen other batches also sit at facility_id NULL, and all fourteen
--   belong there: BATCH-CENTRAL-41-01 through -54-01, every one dated
--   2026-07-30 with no created_by. That is the opening stock
--   clean_and_seed_vaccines_supplements.sql seeds INTO the Municipal Warehouse
--   on purpose. Moving them would be inventing a problem.
--
--   Batch 235 is the only one carrying a created_by, and that account
--   administers Baliwag RHU III (facility 9), not the municipal office.
--
-- WHY MOVED RATHER THAN TRANSFERRED
--
--   The stock never physically went to the municipal warehouse. Recording a
--   transfer would assert a movement that did not happen and put a fictional
--   leg in the dose ledger. The record was simply written to the wrong place,
--   so the record is what gets corrected.
--
--   inventory_transactions.facility_id has to move with it. Left behind, the
--   receipt says 3000 units entered the municipal warehouse while the batch
--   says they are at RHU III, and the two disagree permanently.
--
--   Safe to move: quantity_remaining is still 3000 of 3000, the batch has one
--   ledger row and no transfers, so nothing downstream depends on where it sat.
--
--   The audit triggers from 20260826 fire on both updates, so the correction
--   records itself. No audit_trail row is written by hand.
--
-- Idempotent: both updates are conditioned on the wrong value still being
-- there, so a second run matches nothing.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. What is about to move. Run alone first; it changes nothing.
-- ---------------------------------------------------------------------------
SELECT b.batch_id, b.batch_number, i.name AS item,
       b.quantity_remaining || ' of ' || b.quantity_received AS stock,
       b.received_date,
       COALESCE(f.name, 'Municipal Warehouse') AS currently_filed_to,
       a.first_name || ' ' || a.last_name      AS received_by
  FROM public.inventory_batches b
  JOIN public.inventory_items i ON i.item_id = b.item_id
  LEFT JOIN public.health_facilities f ON f.facility_id = b.facility_id
  LEFT JOIN public.accounts a ON a.account_id = b.created_by
 WHERE b.batch_id = 235;


-- ---------------------------------------------------------------------------
-- 2. The correction.
-- ---------------------------------------------------------------------------
BEGIN;

UPDATE public.inventory_batches
   SET facility_id = 9                       -- Baliwag RHU III
 WHERE batch_id = 235
   AND facility_id IS NULL;

UPDATE public.inventory_transactions
   SET facility_id = 9
 WHERE batch_id = 235
   AND facility_id IS NULL;

COMMIT;

-- To rehearse instead, replace the COMMIT above with ROLLBACK. Do not leave the
-- transaction unterminated: the Supabase SQL editor discards an open
-- transaction when the connection returns to the pool, so the update reports
-- success and is then thrown away.


-- ---------------------------------------------------------------------------
-- 3. Confirm. Both rows should read Baliwag RHU III, and the count of
--    warehouse batches should be back to the fourteen seeded ones.
-- ---------------------------------------------------------------------------
SELECT 'batch'       AS row_kind,
       COALESCE(f.name, 'Municipal Warehouse') AS filed_to
  FROM public.inventory_batches b
  LEFT JOIN public.health_facilities f ON f.facility_id = b.facility_id
 WHERE b.batch_id = 235
UNION ALL
SELECT 'ledger #' || t.transaction_id,
       COALESCE(f.name, 'Municipal Warehouse')
  FROM public.inventory_transactions t
  LEFT JOIN public.health_facilities f ON f.facility_id = t.facility_id
 WHERE t.batch_id = 235;

SELECT count(*) AS batches_still_at_the_warehouse
  FROM public.inventory_batches
 WHERE facility_id IS NULL;
