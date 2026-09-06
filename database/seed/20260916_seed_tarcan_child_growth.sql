-- ==============================================================================
-- SEED: 20260916_seed_tarcan_child_growth.sql
--
-- Growth monitoring measurements for the 16 children registered at Tarcan BHC
-- (facility_id 2), so the Child Growth & Nutritional Status panel on
-- reports.html has something to show.
--
-- WHY THIS EXISTS
--
--   The panel computes stunting, underweight and wasting from
--   child_growth_records.*_zscore. Before this file the whole municipality held
--   8 growth records, several of them biologically implausible test rows
--   (one child at 4 kg / 50 cm reads height-for-age -9.87). The panel was
--   correct and empty.
--
-- WHERE THE Z-SCORES COME FROM
--
--   They are not invented. Each one is produced by the same procedure the
--   Flutter app runs when a midwife saves a measurement for a child over 13
--   weeks old (GrowthCalculator.calculateWeightZScore and its siblings):
--
--     month = round(ageInWeeks / 4.345)
--     z     = piecewise-linear interpolation between the WHO SD boundary
--             columns for that month and sex
--
--   The generator parses those reference tables out of the app's own source
--   (growth_calculator.dart, growth_reference_data.dart) rather than retyping
--   them, and round-trips every SD boundary through the function and its
--   inverse before emitting anything. Re-measuring any child in the app should
--   reproduce these numbers.
--
--   Height and BMI were chosen at a target Z; weight is DERIVED from them as
--   BMI x (height/100)^2, and weight-for-age falls where the WHO table puts
--   it. The three z-scores therefore agree with each other and with the stored
--   height and weight — which is a property real data has and fabricated data
--   usually does not.
--
-- WHAT IT PRODUCES  (latest measurement per child, n = 16)
--
--   Stunted   (HAZ < -2)  4  (25%), of which 1 severe (HAZ < -3)
--   Underweight (WAZ < -2)  4  (25%)
--   Wasted    (BAZ < -2)  1  (6%)
--   Implausible values     0
--
--   Those proportions are in the region of the Philippine national figures for
--   under-fives, which is what makes the panel worth looking at rather than a
--   wall of green.
--
-- THIS IS PILOT DATA. It describes no real child. Every row is attributed to
-- the midwife assigned to Tarcan (midwife_id 2). recorded_by references
-- midwives(midwife_id), not accounts; recorded_by_midwife_id is the legacy column
-- 20260805 documents the app wrongly writing to, and is left null as existing rows do.
--
-- Idempotent: re-running inserts nothing already present for the same child
-- and measurement date.
-- ==============================================================================

BEGIN;

WITH seeded (child_id, measurement_date, child_weight, child_height,
             weight_for_age_zscore, height_for_age_zscore, bmi_for_age_zscore,
             recorded_by) AS (
  VALUES
  (5, DATE '2026-06-19', 6.53, 61.2, 0.1625, -0.1000, 0.3564, 2),
  (5, DATE '2026-07-24', 7.58, 65.4, 0.0889, -0.2381, 0.2814, 2),
  (5, DATE '2026-08-21', 7.85, 66.8, -0.0625, -0.3810, 0.1947, 2),
  (6, DATE '2026-06-24', 4.83, 55.4, -1.5286, -2.0952, -0.4419, 2),
  (6, DATE '2026-07-29', 5.61, 59.1, -1.7000, -2.2273, -0.5275, 2),
  (6, DATE '2026-08-26', 5.84, 60.3, -1.8250, -2.4091, -0.5991, 2),
  (7, DATE '2026-06-24', 6.65, 62.6, 0.3125, 0.6000, 0.0464, 2),
  (7, DATE '2026-07-29', 7.21, 64.8, 0.2625, 0.4286, -0.0210, 2),
  (7, DATE '2026-08-26', 7.59, 66.5, 0.1000, 0.2857, -0.0977, 2),
  (8, DATE '2026-07-28', 6.3, 59.8, -0.1429, -1.0476, 0.5733, 2),
  (8, DATE '2026-08-25', 6.64, 61.4, -0.3250, -1.1818, 0.5081, 2),
  (9, DATE '2026-07-26', 5.57, 62.5, -2.0429, -0.6667, -2.2189, 2),
  (9, DATE '2026-08-23', 5.91, 64.2, -2.1286, -0.8095, -2.3009, 2),
  (10, DATE '2026-07-23', 7.43, 63.8, 1.1444, 0.7727, 0.9710, 2),
  (10, DATE '2026-08-20', 7.78, 65.3, 0.9778, 0.5909, 0.9034, 2),
  (11, DATE '2026-07-28', 5.64, 59.8, -1.9333, -1.9524, -1.0218, 2),
  (11, DATE '2026-08-25', 5.97, 61.5, -2.0429, -2.0952, -1.0965, 2),
  (12, DATE '2026-07-26', 6.05, 59.7, 0.3125, -0.0476, 0.3833, 2),
  (12, DATE '2026-08-23', 6.54, 61.7, 0.1556, -0.1818, 0.2996, 2),
  (13, DATE '2026-07-23', 5.43, 58.7, -1.3857, -1.3333, -0.8151, 2),
  (13, DATE '2026-08-20', 5.89, 60.8, -1.5167, -1.4762, -0.9047, 2),
  (14, DATE '2026-07-27', 5.79, 60.3, -0.0167, 0.2381, -0.3175, 2),
  (14, DATE '2026-08-24', 6.25, 62.3, -0.2143, 0.0909, -0.3981, 2),
  (15, DATE '2026-04-11', 6.98, 69.6, -2.6889, -2.8889, -1.2424, 2),
  (15, DATE '2026-06-20', 7.13, 71, -2.8556, -3.0345, -1.3236, 2),
  (15, DATE '2026-08-22', 7.28, 72.2, -3.0222, -3.2000, -1.3950, 2),
  (16, DATE '2026-04-11', 10.63, 77.3, 0.4417, -0.2917, 0.8500, 2),
  (16, DATE '2026-06-20', 10.85, 79, 0.2917, -0.4615, 0.7750, 2),
  (16, DATE '2026-08-22', 11.12, 80.7, 0.1692, -0.5926, 0.6963, 2),
  (17, DATE '2026-04-11', 6.76, 69.2, -2.5500, -2.2963, -1.6527, 2),
  (17, DATE '2026-06-20', 6.93, 70.8, -2.7444, -2.4444, -1.7291, 2),
  (17, DATE '2026-08-22', 7.12, 72.3, -2.8667, -2.5862, -1.7993, 2),
  (18, DATE '2026-04-15', 10.27, 77.4, 0.5583, 0.7083, 0.2450, 2),
  (18, DATE '2026-06-24', 10.62, 79.4, 0.4333, 0.5600, 0.1753, 2),
  (18, DATE '2026-08-26', 11.07, 82.3, 0.2846, 0.4074, 0.1026, 2),
  (19, DATE '2026-04-14', 7.3, 70.8, -1.5000, -0.8000, -1.4473, 2),
  (19, DATE '2026-06-23', 7.54, 72.7, -1.6222, -0.9615, -1.5283, 2),
  (19, DATE '2026-08-25', 7.76, 74.5, -1.8222, -1.1071, -1.5989, 2),
  (20, DATE '2026-04-15', 9.6, 73.3, 0.4000, 0.0000, 0.5482, 2),
  (20, DATE '2026-06-24', 9.93, 75.4, 0.2750, -0.1304, 0.4761, 2),
  (20, DATE '2026-08-26', 10.25, 77.3, 0.1250, -0.2917, 0.3957, 2)
)
INSERT INTO public.child_growth_records (
  child_id, measurement_date, child_weight, child_height,
  weight_for_age_zscore, height_for_age_zscore, bmi_for_age_zscore,
  recorded_by
)
SELECT s.child_id, s.measurement_date, s.child_weight, s.child_height,
       s.weight_for_age_zscore, s.height_for_age_zscore, s.bmi_for_age_zscore,
       s.recorded_by
  FROM seeded s
 WHERE EXISTS (SELECT 1 FROM public.children c
                WHERE c.child_id = s.child_id AND c.assigned_bhc_id = 2)
   AND NOT EXISTS (SELECT 1 FROM public.child_growth_records g
                    WHERE g.child_id = s.child_id
                      AND g.measurement_date = s.measurement_date);

COMMIT;

-- ---------------------------------------------------------------------------
-- Verify: nutritional status at Tarcan, latest measurement per child.
-- ---------------------------------------------------------------------------
WITH latest AS (
  SELECT DISTINCT ON (g.child_id)
         g.child_id, g.measurement_date, g.child_weight, g.child_height,
         g.weight_for_age_zscore AS waz,
         g.height_for_age_zscore AS haz,
         g.bmi_for_age_zscore    AS baz
    FROM public.child_growth_records g
    JOIN public.children c ON c.child_id = g.child_id
   WHERE c.assigned_bhc_id = 2
   ORDER BY g.child_id, g.measurement_date DESC
)
SELECT count(*)                                   AS measured,
       count(*) FILTER (WHERE haz < -2)           AS stunted,
       count(*) FILTER (WHERE haz < -3)           AS severely_stunted,
       count(*) FILTER (WHERE waz < -2)           AS underweight,
       count(*) FILTER (WHERE baz < -2)           AS wasted
  FROM latest;

-- ============================================================
-- ROLLBACK
-- ============================================================
-- DELETE FROM public.child_growth_records g
--  USING public.children c
--  WHERE c.child_id = g.child_id
--    AND c.assigned_bhc_id = 2
--    AND g.measurement_date >= DATE '2026-04-11';
