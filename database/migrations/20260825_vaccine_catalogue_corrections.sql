-- ============================================================================
-- InaAgapay — Vaccine catalogue corrections
--
-- Four data fixes, no schema changes. Safe to run more than once, and safe to
-- run on a database that has already had some of them applied by hand.
--
-- Run this AFTER 20260819_fix_open_vial_deduction_and_linkage.sql and after any
-- re-run of database/clean_and_seed_vaccines_supplements.sql. That migration
-- sets dose capacities by matching item names, and one of its patterns is
-- wrong; section 1 below is what puts the affected row back.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. IPV is a 5-dose vial, not a 20-dose one
--
-- The OPV rule in 20260819_fix_open_vial_deduction_and_linkage.sql reads
--
--     WHERE (name ILIKE '%opv%' OR generic_name ILIKE '%oral polio%'
--            OR name ILIKE '%polio%')
--
-- and "IPV Polio Vaccine" contains "Polio", so it took OPV's 20 doses. The
-- correction three statements below it never fired, because it is guarded by
-- `AND doses_per_unit IS NULL` and the value was 20 by then, not null.
--
-- The Philippine EPI buys IPV as a 5-dose vial (10-dose exists; 20-dose does
-- not). The 28-day shelf life it also inherited is correct for that vial —
-- IPV is preservative-containing and liquid, WHO multi-dose vial policy
-- Group 1 — so only the dose count is wrong.
--
-- At 20 doses/vial the portal was reporting IPV stock at four times its real
-- dose count.
-- ---------------------------------------------------------------------------
UPDATE public.inventory_items
   SET doses_per_unit = 5
 WHERE item_type = 'vaccine'
   AND name ILIKE '%ipv%'
   AND doses_per_unit <> 5;

-- An IPV vial opened while the capacity was still 20 would be carrying more
-- remaining doses than a 5-dose vial can hold. Opening a vial consumes one
-- dose immediately, so the ceiling is capacity - 1. No such vial existed when
-- this migration was written; the clamp is here so running it later is still
-- safe.
UPDATE public.inventory_batches b
   SET doses_remaining_in_open_vial = GREATEST(i.doses_per_unit - 1, 0)
  FROM public.inventory_items i
 WHERE b.item_id = i.item_id
   AND i.name ILIKE '%ipv%'
   AND b.doses_remaining_in_open_vial > GREATEST(i.doses_per_unit - 1, 0);

-- ---------------------------------------------------------------------------
-- 2. Retire the "Test" catalogue entry
--
-- Created through the portal UI, never part of any seed. It holds no batches,
-- so it read as a permanent stockout: a row in every catalogue and matrix
-- view and a standing count against the low-stock alert. Archived rather than
-- deleted, because the audit trail may reference it and the portal already
-- hides archived items everywhere.
-- ---------------------------------------------------------------------------
UPDATE public.inventory_items
   SET is_archived = true
 WHERE name = 'Test'
   AND is_archived = false;

-- ---------------------------------------------------------------------------
-- 3. Point MMR immunizations at MMR stock
--
-- Both MMR schedule rows — dose 1 at 9 months, dose 2 at 12 — were deducting
-- from "MR Vaccine" instead. The auto-link rule in
-- 20260819_fix_open_vial_deduction_and_linkage.sql matches
--
--     v.vaccine_name ILIKE '%measles%' AND i.name ILIKE '%mr%'
--
-- and "MR Vaccine" satisfies '%mr%', so it won the join and "MMR Vaccine" was
-- left linked to nothing.
--
-- Note if you intend the Philippine EPI split — MR for the 9-month dose, MMR
-- at 12 months — that is a change to the `vaccines` catalogue names, not to
-- this link. As the rows are named today, both say MMR, so both point at MMR.
-- ---------------------------------------------------------------------------
UPDATE public.vaccines v
   SET inventory_item_id = i.item_id
  FROM public.inventory_items i
 WHERE v.vaccine_name ILIKE '%mmr%'
   AND i.name ILIKE '%mmr%'
   AND i.is_archived = false
   AND v.inventory_item_id IS DISTINCT FROM i.item_id;

-- ---------------------------------------------------------------------------
-- 4. Give Rotavirus an inventory item
--
-- Both Rotavirus schedule rows carried inventory_item_id = NULL, so those
-- immunizations could never deduct stock — the catalogue scheduled a vaccine
-- the inventory did not know about. Supplied as a single-dose oral applicator,
-- so there is no open-vial window.
--
-- It arrives with no batches, which means it will show as out of stock until
-- you receive some. That is the true picture, not a defect.
-- ---------------------------------------------------------------------------
INSERT INTO public.inventory_items
       (name, generic_name, item_type, unit_of_measure,
        doses_per_unit, open_vial_shelf_hours, minimum_stock_threshold, is_archived)
SELECT 'Rotavirus Vaccine', 'Live Attenuated Human Rotavirus (Oral)', 'vaccine', 'doses',
       1, 0, 25, false
 WHERE NOT EXISTS (
   SELECT 1 FROM public.inventory_items WHERE name ILIKE '%rotavirus%'
 );

UPDATE public.vaccines v
   SET inventory_item_id = i.item_id
  FROM public.inventory_items i
 WHERE v.vaccine_name ILIKE '%rotavirus%'
   AND i.name ILIKE '%rotavirus%'
   AND i.is_archived = false
   AND v.inventory_item_id IS NULL;

COMMIT;

-- ============================================================================
-- Verification — run separately and read the output
-- ============================================================================
-- SELECT item_id, name, doses_per_unit, open_vial_shelf_hours, is_archived
--   FROM public.inventory_items
--  WHERE item_type = 'vaccine'
--  ORDER BY name;
--
-- SELECT v.vaccine_id, v.vaccine_name, v.dose_number, i.name AS deducts_from
--   FROM public.vaccines v
--   LEFT JOIN public.inventory_items i ON i.item_id = v.inventory_item_id
--  ORDER BY v.vaccine_id;
