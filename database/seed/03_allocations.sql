-- ==============================================================================
-- SEED 03 — ALLOCATIONS: STOCK ON EVERY SHELF
--
-- Puts physical stock at all three tiers and writes the receipt ledger that
-- accounts for it. Run after 01 and 02, which create the catalogue this draws
-- from.
--
-- THREE TIERS, NOT TWO
--
--   Stock flows Municipal Warehouse -> Rural Health Unit depot -> barangay
--   health centre. The middle rung is the one that gets forgotten: fill the
--   warehouse and the health centres only, and every per-RHU figure in the
--   municipal portal reads zero while the stock apparently teleports past them.
--
--     Municipal Warehouse (facility_id IS NULL)   25x threshold
--     Rural Health Unit depot                      8x threshold
--     Barangay health centre                       3x threshold
--
--   Quantities scale off each item's own minimum_stock_threshold rather than a
--   flat number. A flat 100 at a health centre sits below the 150-200 threshold
--   of every supplement, so the database would open with all five supplements
--   reading LOW at all five centres, and the alert hub full of warnings about a
--   database nobody has touched yet. Scaling keeps each tier comfortably above
--   its own line, and stays right if a threshold is edited later.
--
--   Received dates step down the chain (60 / 40 / 20 days ago) so the movement
--   ledger reads in the order the stock actually travelled.
--
-- NO FABRICATED TRANSFERS
--
--   Each tier gets a receipt, not a transfer from the tier above. A transfer
--   asserts a dispatch that somebody issued and somebody confirmed, with a
--   source batch drawn down to pay for it. Inventing that chain would put five
--   facilities' worth of fictional paperwork in the audit trail. The stock is
--   simply booked in where it sits, which is what a receipt means.
--
-- REQUIRES the facilities to exist. If health_facilities holds no RHU or BHC
-- rows this aborts rather than seeding a warehouse in isolation.
--
-- Safe to run more than once: batches are keyed on (item, facility) through
-- their generated batch_number, and re-running refreshes quantities in place.
-- ==============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Guard: the hierarchy has to be there.
-- ---------------------------------------------------------------------------
DO $guard$
DECLARE
  v_items INTEGER;
  v_rhus  INTEGER;
  v_bhcs  INTEGER;
BEGIN
  SELECT count(*) INTO v_items FROM public.inventory_items WHERE NOT is_archived;
  SELECT count(*) INTO v_rhus  FROM public.health_facilities WHERE facility_type = 'RHU';
  SELECT count(*) INTO v_bhcs  FROM public.health_facilities WHERE facility_type = 'BHC';

  IF v_items = 0 THEN
    RAISE EXCEPTION 'No catalogue items. Run 01_items_vaccines.sql and 02_items_supplements.sql first.';
  END IF;

  IF v_rhus = 0 OR v_bhcs = 0 THEN
    RAISE EXCEPTION
      'This database has % RHU(s) and % barangay health centre(s). Allocations need '
      'the facility hierarchy -- run migrations/20260821_mho_tier.sql and make sure '
      'the facilities exist before seeding stock onto them.', v_rhus, v_bhcs;
  END IF;
END
$guard$;


-- ---------------------------------------------------------------------------
-- 1. The Municipal Warehouse. facility_id IS NULL *is* the warehouse -- that is
--    the convention the whole portal reads, not a missing value.
-- ---------------------------------------------------------------------------
INSERT INTO public.inventory_batches (
  item_id, facility_id, batch_number, quantity_received, quantity_remaining,
  received_date, expiration_date, manufacturer, status
)
SELECT
  i.item_id,
  NULL,
  'MW-' || i.item_id || '-01',
  i.minimum_stock_threshold * 25,
  i.minimum_stock_threshold * 25,
  CURRENT_DATE - INTERVAL '60 days',
  CURRENT_DATE + CASE WHEN i.item_type = 'vaccine'
                      THEN INTERVAL '18 months' ELSE INTERVAL '30 months' END,
  'DOH Central Supply Depot',
  'active'
  FROM public.inventory_items i
 WHERE NOT i.is_archived
   AND NOT EXISTS (SELECT 1 FROM public.inventory_batches b
                    WHERE b.batch_number = 'MW-' || i.item_id || '-01');


-- ---------------------------------------------------------------------------
-- 2. Each Rural Health Unit depot.
-- ---------------------------------------------------------------------------
INSERT INTO public.inventory_batches (
  item_id, facility_id, batch_number, quantity_received, quantity_remaining,
  received_date, expiration_date, manufacturer, status
)
SELECT
  i.item_id,
  hf.facility_id,
  'RHU' || hf.facility_id || '-' || i.item_id || '-01',
  i.minimum_stock_threshold * 8,
  i.minimum_stock_threshold * 8,
  CURRENT_DATE - INTERVAL '40 days',
  CURRENT_DATE + CASE WHEN i.item_type = 'vaccine'
                      THEN INTERVAL '15 months' ELSE INTERVAL '24 months' END,
  'Municipal Warehouse Allocation',
  'active'
  FROM public.inventory_items i
 CROSS JOIN public.health_facilities hf
 WHERE NOT i.is_archived
   AND hf.facility_type = 'RHU'
   AND COALESCE(hf.is_active, true)
   AND NOT EXISTS (SELECT 1 FROM public.inventory_batches b
                    WHERE b.batch_number = 'RHU' || hf.facility_id || '-' || i.item_id || '-01');


-- ---------------------------------------------------------------------------
-- 3. Each barangay health centre.
-- ---------------------------------------------------------------------------
INSERT INTO public.inventory_batches (
  item_id, facility_id, batch_number, quantity_received, quantity_remaining,
  received_date, expiration_date, manufacturer, status
)
SELECT
  i.item_id,
  hf.facility_id,
  'BHC' || hf.facility_id || '-' || i.item_id || '-01',
  i.minimum_stock_threshold * 3,
  i.minimum_stock_threshold * 3,
  CURRENT_DATE - INTERVAL '20 days',
  CURRENT_DATE + CASE WHEN i.item_type = 'vaccine'
                      THEN INTERVAL '12 months' ELSE INTERVAL '20 months' END,
  'RHU Depot Allocation',
  'active'
  FROM public.inventory_items i
 CROSS JOIN public.health_facilities hf
 WHERE NOT i.is_archived
   AND hf.facility_type = 'BHC'
   AND COALESCE(hf.is_active, true)
   AND NOT EXISTS (SELECT 1 FROM public.inventory_batches b
                    WHERE b.batch_number = 'BHC' || hf.facility_id || '-' || i.item_id || '-01');


-- ---------------------------------------------------------------------------
-- 4. Re-running refreshes quantities rather than stacking new batches.
--
-- Note this puts every seeded batch back to FULL. That is the point on a demo
-- database being reset before a run-through, but it does mean running this file
-- on its own discards whatever has since been dispensed from these batches. The
-- ledger keeps the movements; the counts go back to opening stock.
--
-- Only rows this file created are touched -- the batch_number prefixes are the
-- marker. Anything received through the portal is left alone.
-- ---------------------------------------------------------------------------
UPDATE public.inventory_batches b
   SET quantity_received  = i.minimum_stock_threshold * CASE
                              WHEN b.batch_number LIKE 'MW-%'  THEN 25
                              WHEN b.batch_number LIKE 'RHU%'  THEN 8
                              ELSE 3
                            END,
       quantity_remaining = i.minimum_stock_threshold * CASE
                              WHEN b.batch_number LIKE 'MW-%'  THEN 25
                              WHEN b.batch_number LIKE 'RHU%'  THEN 8
                              ELSE 3
                            END,
       status             = 'active'
  FROM public.inventory_items i
 WHERE b.item_id = i.item_id
   AND (b.batch_number LIKE 'MW-%' OR b.batch_number LIKE 'RHU%' OR b.batch_number LIKE 'BHC%');


-- ---------------------------------------------------------------------------
-- 5. The receipt ledger.
--
-- A batch whose quantity appeared with no movement behind it makes physical
-- stock and the ledger disagree from the first day. performed_by is resolved
-- rather than hardcoded to account 1 -- the municipal officer if there is one,
-- otherwise the lowest active portal account, because that column is a foreign
-- key to accounts and a guessed id is an FK violation waiting to happen.
-- ---------------------------------------------------------------------------
INSERT INTO public.inventory_transactions (
  batch_id, facility_id, transaction_type, quantity,
  reference_type, notes, performed_by, resulting_quantity_remaining, logged_at
)
SELECT
  b.batch_id,
  b.facility_id,
  'receipt',
  b.quantity_received,
  'Opening Stock',
  CASE
    WHEN b.facility_id IS NULL THEN 'Opening stock received into the Municipal Warehouse.'
    ELSE 'Opening stock allocated to ' || hf.name || '.'
  END,
  (SELECT a.account_id FROM public.accounts a
    WHERE a.status = 'active' AND a.account_type IN ('mho', 'admin')
    ORDER BY CASE WHEN a.account_type = 'mho' THEN 0 ELSE 1 END, a.account_id
    LIMIT 1),
  b.quantity_remaining,
  b.received_date::timestamp + TIME '09:00'
  FROM public.inventory_batches b
  LEFT JOIN public.health_facilities hf ON hf.facility_id = b.facility_id
 WHERE NOT EXISTS (SELECT 1 FROM public.inventory_transactions t
                    WHERE t.batch_id = b.batch_id AND t.transaction_type = 'receipt');

COMMIT;


-- ---------------------------------------------------------------------------
-- Verify: every tier holding every item, and nothing below its own threshold.
-- ---------------------------------------------------------------------------
SELECT COALESCE(hf.name, 'Municipal Warehouse') AS facility,
       COALESCE(hf.facility_type, 'MHO')        AS tier,
       count(*)                                 AS items_held,
       sum(b.quantity_remaining)                AS units
  FROM public.inventory_batches b
  LEFT JOIN public.health_facilities hf ON hf.facility_id = b.facility_id
 GROUP BY hf.name, hf.facility_type
 ORDER BY tier, facility;

SELECT count(*) AS items_below_threshold
  FROM public.inventory_items i
  JOIN public.inventory_batches b ON b.item_id = i.item_id
 WHERE b.quantity_remaining <= i.minimum_stock_threshold;
