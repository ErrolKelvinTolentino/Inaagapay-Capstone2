-- ==============================================================================
-- MIGRATION: 20260908_remove_test_inventory_item.sql
--
-- Removes the catalogue row named "Test" (item_id 55), left behind from trying
-- the Add Item form. It is not a vaccine, and it appears in every item picker,
-- every stock matrix column and the low-stock alert list as though it were one.
--
-- SAFE TO DELETE RATHER THAN ARCHIVE
--
--   Nothing points at it. Checked before writing this:
--
--     inventory_batches      (item_id, CASCADE)   0 rows
--     inventory_transactions (via batch, CASCADE) 0 rows
--     inventory_stock_requests (item_id, RESTRICT) 0 rows -- the one open
--                              request is for Calcium Carbonate
--     vaccines (inventory_item_id, SET NULL)      0 rows
--
--   RESTRICT on inventory_stock_requests is the one that would have blocked
--   this; it is clear. With no batches there is no stock to strand and no ledger
--   history to lose, which is what would otherwise argue for archiving instead.
--
--   Archiving remains the right move for any item that HAS been used: is_archived
--   hides it from every picker while keeping its batches and their movements
--   readable. Delete only what never had any.
--
-- Matched on name rather than id: the catalogue's ids belong to a sequence and
-- 55 is only what this row happens to hold here.
--
-- Idempotent: a second run matches nothing.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. What is about to go, and what would stop it. Run alone first.
--    every count must be 0.
-- ---------------------------------------------------------------------------
SELECT i.item_id,
       i.name,
       i.item_type,
       (SELECT count(*) FROM public.inventory_batches b
         WHERE b.item_id = i.item_id)                         AS batches,
       (SELECT count(*) FROM public.inventory_stock_requests r
         WHERE r.item_id = i.item_id)                         AS stock_requests,
       (SELECT count(*) FROM public.vaccines v
         WHERE v.inventory_item_id = i.item_id)               AS schedule_rows
  FROM public.inventory_items i
 WHERE btrim(lower(i.name)) = 'test';


-- ---------------------------------------------------------------------------
-- 2. Remove it, but only while nothing depends on it.
--
-- The NOT EXISTS clauses are not decoration: if stock or a request has appeared
-- since the check above, this deletes nothing rather than failing on a foreign
-- key halfway through. Re-read the report and archive it instead.
-- ---------------------------------------------------------------------------
BEGIN;

DELETE FROM public.inventory_items i
 WHERE btrim(lower(i.name)) = 'test'
   AND NOT EXISTS (SELECT 1 FROM public.inventory_batches b
                    WHERE b.item_id = i.item_id)
   AND NOT EXISTS (SELECT 1 FROM public.inventory_stock_requests r
                    WHERE r.item_id = i.item_id);

COMMIT;


-- ---------------------------------------------------------------------------
-- 3. Confirm. The catalogue should read 15 items: 10 vaccines, 5 supplements.
-- ---------------------------------------------------------------------------
SELECT item_type, count(*) AS items
  FROM public.inventory_items
 WHERE NOT is_archived
 GROUP BY item_type
 ORDER BY item_type;

SELECT count(*) AS test_rows_remaining
  FROM public.inventory_items
 WHERE btrim(lower(name)) = 'test';
