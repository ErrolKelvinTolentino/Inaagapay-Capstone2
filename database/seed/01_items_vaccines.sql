-- ==============================================================================
-- SEED 01 — INVENTORY CATALOGUE: VACCINES
--
-- The full DOH EPI childhood series plus maternal Td. This is the catalogue —
-- what a batch can be a batch OF. Physical stock arrives in 03_allocations.sql.
--
-- THE TWO COLUMNS THAT MATTER
--
--   doses_per_unit         how many doses come out of one vial
--   open_vial_shelf_hours  how long the rest of the vial is usable once pierced
--
--   These are not decoration. Leave doses_per_unit at 1 on a 20-dose BCG vial
--   and giving one dose destroys the whole vial: the portal's dispense path
--   subtracts a unit, the open-vial tracker never sees it, and nineteen doses
--   leave the system with no record they existed. That is the failure
--   20260831_dose_presentation_single_source.sql was written to end.
--
--   The shelf-life figures are DOH policy, not arbitrary:
--     6 hours    BCG, MR, MMR, Rotavirus — discard at the end of the session
--     672 hours  OPV, IPV, Td — 28 days, the multi-dose vial policy
--     0          single-dose presentations, nothing is left to keep
--
-- minimum_stock_threshold drives the low-stock alerts, and through them whether
-- the portal offers Issue or Request. 03_allocations.sql also scales every
-- quantity off it, so these numbers decide how much stock the seed lays down.
--
-- Keyed on name, which is UNIQUE. Ids are left to the sequence — nothing in the
-- app refers to an item by id.
--
-- Safe to run more than once.
-- ==============================================================================

BEGIN;

INSERT INTO public.inventory_items (
  name, generic_name, item_type, unit_of_measure,
  doses_per_unit, open_vial_shelf_hours, minimum_stock_threshold, is_archived
) VALUES
  ('BCG Vaccine',                     'Bacillus Calmette-Guérin (Tuberculosis)', 'vaccine', 'vials', 20,   6, 20, false),
  ('Hepatitis B Vaccine',             'Hepatitis B (Pediatric Birth Dose)',      'vaccine', 'vials',  1,   0, 25, false),
  ('Pentavalent Vaccine',             'DPT-HepB-Hib Combination',                'vaccine', 'vials',  1,   0, 30, false),
  ('OPV Polio Vaccine',               'Oral Polio Vaccine (bOPV)',               'vaccine', 'vials', 20, 672, 30, false),
  ('IPV Polio Vaccine',               'Inactivated Polio Vaccine',               'vaccine', 'vials', 20, 672, 20, false),
  ('PCV-13 Vaccine',                  'Pneumococcal Conjugate 13-Valent',        'vaccine', 'vials',  1,   0, 25, false),
  ('MR Vaccine',                      'Measles-Rubella Vaccine',                 'vaccine', 'vials', 10,   6, 20, false),
  ('MMR Vaccine',                     'Measles-Mumps-Rubella Vaccine',           'vaccine', 'vials', 10,   6, 20, false),
  ('Rotavirus Vaccine',               'Human Rotavirus Vaccine (Oral)',          'vaccine', 'vials',  1,   6, 25, false),
  ('Tetanus Diphtheria (Td) Vaccine', 'Tetanus-Diphtheria Toxoid (Maternal)',    'vaccine', 'vials', 10, 672, 30, false)
ON CONFLICT (name) DO UPDATE SET
  generic_name            = EXCLUDED.generic_name,
  item_type               = EXCLUDED.item_type,
  unit_of_measure         = EXCLUDED.unit_of_measure,
  doses_per_unit          = EXCLUDED.doses_per_unit,
  open_vial_shelf_hours   = EXCLUDED.open_vial_shelf_hours,
  minimum_stock_threshold = EXCLUDED.minimum_stock_threshold,
  is_archived             = EXCLUDED.is_archived;

-- Reconnect the immunisation schedule to the catalogue it draws from. 00 unlinks
-- this before dropping the items; without it every schedule row points at
-- nothing and the app cannot tell which vaccine a dose consumes.
UPDATE public.vaccines v
   SET inventory_item_id = i.item_id
  FROM public.inventory_items i
 WHERE v.inventory_item_id IS NULL
   AND (
        (v.vaccine_name ILIKE '%BCG%'          AND i.name = 'BCG Vaccine')
     OR (v.vaccine_name ILIKE '%Hepatitis B%'  AND i.name = 'Hepatitis B Vaccine')
     OR (v.vaccine_name ILIKE '%Pentavalent%'  AND i.name = 'Pentavalent Vaccine')
     OR (v.vaccine_name ILIKE '%OPV%'          AND i.name = 'OPV Polio Vaccine')
     OR (v.vaccine_name ILIKE '%IPV%'          AND i.name = 'IPV Polio Vaccine')
     OR (v.vaccine_name ILIKE '%PCV%'          AND i.name = 'PCV-13 Vaccine')
     OR (v.vaccine_name ILIKE '%MMR%'          AND i.name = 'MMR Vaccine')
     OR (v.vaccine_name ILIKE '%Rotavirus%'    AND i.name = 'Rotavirus Vaccine')
     OR (v.vaccine_name ILIKE '%Measles%' AND v.vaccine_name NOT ILIKE '%Mumps%'
                                               AND i.name = 'MR Vaccine')
     OR (v.vaccine_name ILIKE '%Td%'           AND i.name = 'Tetanus Diphtheria (Td) Vaccine')
   );

COMMIT;


-- ---------------------------------------------------------------------------
-- Verify. draws_from should be filled for every schedule row.
-- ---------------------------------------------------------------------------
SELECT name, unit_of_measure, doses_per_unit, open_vial_shelf_hours,
       minimum_stock_threshold
  FROM public.inventory_items
 WHERE item_type = 'vaccine'
 ORDER BY name;

SELECT v.vaccine_name, v.dose_number, i.name AS draws_from
  FROM public.vaccines v
  LEFT JOIN public.inventory_items i ON i.item_id = v.inventory_item_id
 ORDER BY v.vaccine_name, v.dose_number;
