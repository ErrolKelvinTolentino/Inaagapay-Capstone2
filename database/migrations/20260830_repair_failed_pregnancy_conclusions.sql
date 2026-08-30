-- ==============================================================================
-- MIGRATION: 20260830_repair_failed_pregnancy_conclusions.sql
--
-- Cleans up the records left behind by "Conclude Pregnancy" while it was broken.
--
-- WHAT WENT WRONG
--   MotherProfileService.concludePregnancy() inserted into public.deliveries
--   without an encounter_id. That column is NOT NULL and is the table's primary
--   key — a delivery IS a clinical encounter — so every attempt failed with:
--
--     null value in column "encounter_id" of relation "deliveries"
--     violates not-null constraint  (SQLSTATE 23502)
--
--   The failure came last, so the two writes before it had already committed:
--
--     1. public.pregnancies was set to status = 'ended'
--     2. a row was inserted into public.pregnancy_outcomes
--
--   The result is a pregnancy that is closed, has an outcome, and has no
--   delivery — and one extra pregnancy_outcomes row for every time the midwife
--   pressed the button again.
--
--   Those duplicates are not cosmetic. trg_update_ob_history recomputes the
--   mother's OB score by COUNTing pregnancy_outcomes rows, so each retry raised
--   her para by one. A mother who tried twice is recorded as having delivered
--   twice.
--
-- THE CODE FIX (already applied)
--   concludePregnancy now opens a clinical_encounters row of type 'delivery'
--   first and files the delivery against it; it marks the pregnancy ended LAST,
--   so a failure leaves nothing behind; and it updates existing rows for the
--   same fetus instead of inserting again, so retrying is harmless.
--
-- THIS SCRIPT
--   Removes the duplicate outcome rows and re-opens the pregnancies that were
--   closed without a delivery, so the midwife can conclude them again through
--   the fixed screen. It touches no other clinical record.
--
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. What is about to change. Review this before running anything below.
-- ---------------------------------------------------------------------------

-- 1a. Duplicate outcome rows: same pregnancy, same fetus, recorded more than
--     once. Every row past the first is a retry of a failed conclusion.
SELECT
  po.pregnancy_id,
  p.mother_id,
  po.fetus_number,
  count(*)                        AS outcome_rows,
  array_agg(po.outcome_id ORDER BY po.outcome_id) AS outcome_ids,
  array_agg(DISTINCT po.outcome)  AS outcomes_recorded
FROM public.pregnancy_outcomes po
JOIN public.pregnancies p ON p.pregnancy_id = po.pregnancy_id
GROUP BY po.pregnancy_id, p.mother_id, po.fetus_number
HAVING count(*) > 1
ORDER BY count(*) DESC, po.pregnancy_id;

-- 1b. Pregnancies closed with a birth outcome but no delivery on file. These
--     are the ones the failing insert left half-concluded.
SELECT
  p.pregnancy_id,
  p.mother_id,
  p.status,
  p.ended_at,
  p.gestational_age_at_end,
  po.fetus_number,
  po.outcome,
  po.outcome_date
FROM public.pregnancies p
JOIN public.pregnancy_outcomes po ON po.pregnancy_id = p.pregnancy_id
LEFT JOIN public.deliveries d
       ON d.pregnancy_id = po.pregnancy_id
      AND d.fetus_number = po.fetus_number
WHERE p.status = 'ended'
  AND po.outcome IN ('live_birth', 'stillbirth')
  AND d.encounter_id IS NULL
ORDER BY p.pregnancy_id, po.fetus_number;

-- 1c. The OB score these duplicates produced, per affected mother.
SELECT
  m.mother_id,
  m.gravida,
  m.para,
  m.abortus,
  m.living_children,
  count(po.outcome_id) AS outcome_rows_on_file
FROM public.mothers m
JOIN public.pregnancies p        ON p.mother_id = m.mother_id
JOIN public.pregnancy_outcomes po ON po.pregnancy_id = p.pregnancy_id
WHERE p.pregnancy_id IN (
  SELECT pregnancy_id
  FROM public.pregnancy_outcomes
  GROUP BY pregnancy_id, fetus_number
  HAVING count(*) > 1
)
GROUP BY m.mother_id, m.gravida, m.para, m.abortus, m.living_children;


-- ---------------------------------------------------------------------------
-- 2. Remove the duplicate outcome rows, keeping the earliest per fetus.
--
--    The trigger on pregnancy_outcomes fires per deleted row and recomputes
--    gravida/para/abortus for the mother, so the OB score corrects itself.
-- ---------------------------------------------------------------------------
DELETE FROM public.pregnancy_outcomes po
WHERE po.outcome_id IN (
  SELECT outcome_id
  FROM (
    SELECT
      outcome_id,
      row_number() OVER (
        PARTITION BY pregnancy_id, fetus_number
        ORDER BY outcome_id
      ) AS rn
    FROM public.pregnancy_outcomes
  ) ranked
  WHERE ranked.rn > 1
);


-- ---------------------------------------------------------------------------
-- 3. Re-open the half-concluded pregnancies.
--
--    Their remaining outcome row is deleted too, so the midwife can conclude
--    them again from the app and get a complete record: outcome, delivery
--    encounter and delivery row together. Only pregnancies with a birth outcome
--    and no delivery are touched — a miscarriage or an ectopic pregnancy files
--    no delivery by design and is left exactly as it is.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE tmp_half_concluded AS
SELECT DISTINCT p.pregnancy_id
FROM public.pregnancies p
JOIN public.pregnancy_outcomes po ON po.pregnancy_id = p.pregnancy_id
LEFT JOIN public.deliveries d
       ON d.pregnancy_id = po.pregnancy_id
      AND d.fetus_number = po.fetus_number
WHERE p.status = 'ended'
  AND po.outcome IN ('live_birth', 'stillbirth')
  AND d.encounter_id IS NULL;

DELETE FROM public.pregnancy_outcomes
WHERE pregnancy_id IN (SELECT pregnancy_id FROM tmp_half_concluded);

UPDATE public.pregnancies
SET status                 = 'ongoing',
    ended_at               = NULL,
    gestational_age_at_end = NULL
WHERE pregnancy_id IN (SELECT pregnancy_id FROM tmp_half_concluded);

DROP TABLE tmp_half_concluded;


-- ---------------------------------------------------------------------------
-- 4. Confirm. 1a and 1b should both come back empty now, and the OB score
--    below should match what the mother's history actually shows.
-- ---------------------------------------------------------------------------
SELECT
  m.mother_id,
  m.gravida,
  m.para,
  m.abortus,
  m.living_children
FROM public.mothers m
JOIN public.pregnancies p ON p.mother_id = m.mother_id
GROUP BY m.mother_id, m.gravida, m.para, m.abortus, m.living_children
ORDER BY m.mother_id;
