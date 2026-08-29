-- ==============================================================================
-- SEED 02 — INVENTORY CATALOGUE: SUPPLEMENTS
--
-- What prenatal and child visits hand over: the iron and calcium a mother
-- leaves a checkup with, and the micronutrients given at child visits.
--
-- Single-dose by definition, so doses_per_unit is 1 and there is no open-vial
-- clock. A tablet is a dose.
--
-- TWO NAMES THAT ARE LOAD-BEARING
--
--   deduct_prenatal_encounter_inventory finds the item to deduct by MATCHING ON
--   NAME, not by id:
--
--       v_med.given_medication_name ILIKE '%ferrous%'
--       v_med.given_medication_name ILIKE '%calcium%'
--
--   So 'Ferrous Sulfate + Folic Acid' and 'Calcium Carbonate' must keep the
--   words "Ferrous" and "Calcium" in them. Rename either and prenatal deduction
--   stops finding it -- the checkup still saves, the tablets still leave the
--   shelf, and the stock count simply never moves. It fails silently, which is
--   how it went unnoticed for the whole life of the feature.
--
-- minimum_stock_threshold drives the low-stock alerts, and 03_allocations.sql
-- scales every quantity off it. The supplements carry higher thresholds than
-- the vaccines because they leave in tablets, not doses: a single prenatal visit
-- takes 30-60 tablets, where an immunisation takes one dose.
--
-- Keyed on name, which is UNIQUE. Ids are left to the sequence.
--
-- Safe to run more than once.
-- ==============================================================================

BEGIN;

INSERT INTO public.inventory_items (
  name, generic_name, item_type, unit_of_measure,
  doses_per_unit, open_vial_shelf_hours, minimum_stock_threshold, is_archived
) VALUES
  ('Ferrous Sulfate + Folic Acid', 'Iron 60mg + Folic Acid 400mcg',      'supplement', 'tablets',  1, 0, 200, false),
  ('Calcium Carbonate',            'Elemental Calcium 500mg (Prenatal)', 'supplement', 'tablets',  1, 0, 150, false),
  ('Vitamin A 200,000 IU',         'Retinol Palmitate High-Dose',        'supplement', 'capsules', 1, 0, 100, false),
  ('Micronutrient Powder (MNP)',   'Multiple Micronutrient Sachets',     'supplement', 'sachets',  1, 0, 150, false),
  ('Ascorbic Acid (Vitamin C)',    'Vitamin C 500mg Tablet',             'supplement', 'tablets',  1, 0, 100, false)
ON CONFLICT (name) DO UPDATE SET
  generic_name            = EXCLUDED.generic_name,
  item_type               = EXCLUDED.item_type,
  unit_of_measure         = EXCLUDED.unit_of_measure,
  doses_per_unit          = EXCLUDED.doses_per_unit,
  open_vial_shelf_hours   = EXCLUDED.open_vial_shelf_hours,
  minimum_stock_threshold = EXCLUDED.minimum_stock_threshold,
  is_archived             = EXCLUDED.is_archived;

COMMIT;


-- ---------------------------------------------------------------------------
-- Verify. The first two must still contain "Ferrous" and "Calcium".
-- ---------------------------------------------------------------------------
SELECT name, generic_name, unit_of_measure, minimum_stock_threshold
  FROM public.inventory_items
 WHERE item_type = 'supplement'
 ORDER BY name;
