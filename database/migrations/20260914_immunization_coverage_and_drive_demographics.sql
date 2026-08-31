-- ==============================================================================
-- MIGRATION: 20260914_immunization_coverage_and_drive_demographics.sql
--
-- Gives the admin portal a real immunization rate, and tells it what a drive
-- cost the shelf and who actually walked through the door.
--
-- WHY THE IMMUNIZATION RATE READS 0%
--
--   Not a data problem. reports.html computes it as
--
--       immunization_records.status = 'completed'  /  all records
--
--   and 'completed' is not a value that column can hold. Its CHECK constraint
--   admits 'administered', 'missed' and 'scheduled' only, so the numerator is
--   structurally zero and always has been. Three figures were affected: the
--   Immunization Rate scorecard, the Infant Immunization Status chart, and the
--   Immunization Rate column of the BHC comparison table.
--
--   'status' was never the right column anyway. It says what happened to ONE
--   dose. Coverage is a question about a CHILD measured against the schedule
--   for their age, which needs every dose they should have had by now and every
--   dose they did have -- a join, not a filter.
--
-- THE DEFINITION USED HERE
--
--   Deliberately the SAME one the midwife app already applies in
--   lib/services/midwife_analytics_service.dart, rather than a third opinion:
--
--     Fully immunized child  every vaccine row scheduled at or before twelve
--                            months has been received; only asked of children
--                            who have REACHED twelve months, because a younger
--                            child has not had the chance to finish and
--                            counting them would make coverage a measure of the
--                            barangay's birth rate.
--
--     On schedule            no dose whose recommended age has already passed
--                            is missing. This is the one that means something
--                            for an infant.
--
--     Pentavalent dropout    started the series (dose 1) but has not finished
--                            it (dose 3). Low coverage with low dropout is an
--                            access problem; low coverage with high dropout is
--                            a follow-up problem, and they call for different
--                            work.
--
--   In this catalogue every one of the 17 childhood dose rows is scheduled at
--   or before 12 months, so "fully immunized" here means all 17.
--
-- WHAT IS ADDED
--
--   child_immunization_coverage   one row per child: age, sex, what they have
--                                 had, what they are missing, and which of the
--                                 statuses above they are in.
--
--   vaccination_drive_doses       the drive-to-dose mapping, as a view. See the
--                                 note below.
--
--   vaccination_drive_breakdown   per drive: units and vials off the shelf, and
--                                 the sex and age of who attended.
--
-- A NOTE ON THE MAPPING RULE
--
--   Which doses belong to which drive is decided by the rule 20260912 set out:
--   immunization_schedule_id when stamped, otherwise facility + date + vaccine
--   NAME, with only the earliest of colliding calendar rows allowed to claim
--   unstamped doses. vaccination_drive_doses is now the canonical statement of
--   that rule. The two views in 20260912 still carry their own inline copy --
--   they work, and rewriting a working view to chase tidiness is not worth the
--   risk here -- but the next change to either should move it onto this view so
--   there is one copy rather than three.
--
-- ORDERING-SAFE: three new view names, no column added to any table, no
-- function replaced. Nothing an earlier migration installed is rewound.
-- ==============================================================================

-- ---------------------------------------------------------------------------
-- 0. Preconditions
-- ---------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'immunization_records'
       AND column_name  = 'immunization_schedule_id'
  ) THEN
    RAISE EXCEPTION
      'Run database/migrations/20260912_vaccination_drive_analytics.sql first.';
  END IF;

  IF to_regclass('public.birth_details') IS NULL THEN
    RAISE EXCEPTION 'public.birth_details is missing. Run the base schema first.';
  END IF;
END
$preflight$;


BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Where a child stands against the schedule for their age
-- ---------------------------------------------------------------------------
--
-- A child with no recorded birthdate is carried with a NULL age and a
-- coverage_status of 'unknown' rather than dropped. Dropping them would quietly
-- shrink the denominator of every coverage figure, which reads as better
-- coverage rather than as missing data.

CREATE OR REPLACE VIEW public.child_immunization_coverage AS
WITH child AS (
  SELECT
    c.child_id,
    c.first_name,
    c.last_name,
    c.sex,
    c.child_number,
    c.mother_id,
    c.assigned_bhc_id,
    bd.birthdate,
    -- 30.4375 = 365.25/12, the same month length midwife_analytics_service.dart
    -- uses. A different one puts the two apps on opposite sides of the twelve
    -- month boundary for a child born on the wrong day.
    CASE WHEN bd.birthdate IS NOT NULL
         THEN ROUND((CURRENT_DATE - bd.birthdate) / 30.4375, 1)
    END AS age_months
  FROM public.children c
  LEFT JOIN public.birth_details bd ON bd.child_id = c.child_id
),

-- Every dose the DOH schedule expects inside the first year.
required AS (
  SELECT vaccine_id, vaccine_name, dose_number, recommended_age_months
    FROM public.vaccines
   WHERE target_recipients = 'child'
     AND recommended_age_months <= 12
),

-- A dose counts however it was delivered -- at this centre or transcribed from
-- a card brought in from elsewhere. That is the difference between coverage
-- ("is this child protected?") and doses administered ("what did we give?"),
-- and 20260806_immunization_record_source.sql exists to keep them apart.
given AS (
  SELECT ir.child_id, ir.vaccine_id, MIN(ir.vaccination_date) AS given_on
    FROM public.immunization_records ir
   WHERE COALESCE(ir.status, 'administered') = 'administered'
   GROUP BY ir.child_id, ir.vaccine_id
),

tally AS (
  SELECT
    ch.child_id,
    COUNT(r.vaccine_id)                            AS doses_required,
    COUNT(g.vaccine_id)                            AS doses_received,

    -- Missing AND already due for this child's age. A four-month-old missing
    -- the nine-month measles dose is not behind; they are four months old.
    COUNT(*) FILTER (
      WHERE g.vaccine_id IS NULL
        AND ch.age_months IS NOT NULL
        AND r.recommended_age_months <= ch.age_months
    )                                              AS doses_overdue,

    BOOL_OR(r.vaccine_name ILIKE '%penta%'   AND r.dose_number = 1 AND g.vaccine_id IS NOT NULL) AS has_penta1,
    BOOL_OR(r.vaccine_name ILIKE '%penta%'   AND r.dose_number = 3 AND g.vaccine_id IS NOT NULL) AS has_penta3,
    BOOL_OR(r.vaccine_name ILIKE '%measles%' AND r.dose_number = 1 AND g.vaccine_id IS NOT NULL) AS has_mcv1,
    BOOL_OR(r.vaccine_name ILIKE '%bcg%'                          AND g.vaccine_id IS NOT NULL) AS has_bcg,

    MAX(g.given_on)                                AS last_dose_on,

    -- Named, oldest-scheduled first, so a follow-up list reads as a worklist.
    NULLIF(STRING_AGG(
      CASE WHEN g.vaccine_id IS NULL THEN
        r.vaccine_name ||
        CASE WHEN r.dose_number > 1 THEN ' ' || r.dose_number ELSE '' END
      END,
      ', ' ORDER BY r.recommended_age_months, r.vaccine_name, r.dose_number
    ), '')                                         AS missing_doses

  FROM child ch
  CROSS JOIN required r
  LEFT JOIN given g
    ON g.child_id = ch.child_id AND g.vaccine_id = r.vaccine_id
  GROUP BY ch.child_id
)

SELECT
  ch.child_id,
  ch.child_number,
  ch.mother_id,
  ch.assigned_bhc_id,
  ch.sex,
  ch.birthdate,
  ch.age_months,

  CASE
    WHEN ch.age_months IS NULL     THEN 'unknown'
    WHEN ch.age_months < 3         THEN '0-2 months'
    WHEN ch.age_months < 6         THEN '3-5 months'
    WHEN ch.age_months < 12        THEN '6-11 months'
    WHEN ch.age_months < 24        THEN '12-23 months'
    ELSE '24+ months'
  END                                        AS age_band,

  t.doses_required,
  t.doses_received,
  t.doses_overdue,
  t.missing_doses,
  t.last_dose_on,
  COALESCE(t.has_bcg,    false)              AS has_bcg,
  COALESCE(t.has_penta1, false)              AS has_penta1,
  COALESCE(t.has_penta3, false)              AS has_penta3,
  COALESCE(t.has_mcv1,   false)              AS has_mcv1,

  -- Only children who have reached their first birthday can be asked. NULL,
  -- not false: a five-month-old is not an immunization failure.
  CASE
    WHEN ch.age_months IS NULL OR ch.age_months < 12 THEN NULL
    ELSE t.doses_received >= t.doses_required
  END                                        AS is_fully_immunized,

  -- NULL, not true, for a child with no recorded birthdate. Nothing is overdue
  -- for them only because there is no age to measure against, and reporting
  -- that as "on schedule" would count missing data as a good result.
  CASE WHEN ch.age_months IS NULL THEN NULL ELSE (t.doses_overdue = 0) END
                                             AS is_on_schedule,

  -- Started the series and has not finished it. The standard EPI read.
  (COALESCE(t.has_penta1, false) AND NOT COALESCE(t.has_penta3, false))
                                             AS is_penta_dropout,

  CASE
    WHEN ch.age_months IS NULL                       THEN 'unknown'
    WHEN ch.age_months >= 12
     AND t.doses_received >= t.doses_required        THEN 'fully_immunized'
    WHEN ch.age_months >= 12                         THEN 'incomplete'
    WHEN t.doses_overdue > 0                         THEN 'behind'
    ELSE 'on_schedule'
  END                                        AS coverage_status

FROM child ch
JOIN tally t ON t.child_id = ch.child_id;

COMMENT ON VIEW public.child_immunization_coverage IS
  'One row per child: age, sex, doses received against the DOH schedule for '
  'the first year, what is missing, and whether they are fully immunized (only '
  'asked of children aged 12 months or more), on schedule, or a Pentavalent '
  'dropout. Same definition as midwife_analytics_service.dart so the portal and '
  'the midwife app cannot disagree.';


-- ---------------------------------------------------------------------------
-- 2. Which dose belongs to which drive
-- ---------------------------------------------------------------------------
--
-- The rule 20260912 set out, stated once. See the header note.

CREATE OR REPLACE VIEW public.vaccination_drive_doses AS
WITH drive AS (
  SELECT
    s.immunization_schedule_id AS drive_id,
    s.facility_id,
    s.schedule_date,
    v.vaccine_name,
    v.target_recipients,
    s.immunization_schedule_id = MIN(s.immunization_schedule_id) OVER (
      PARTITION BY s.facility_id, s.schedule_date, v.vaccine_name
    ) AS is_canonical
  FROM public.immunization_schedule s
  JOIN public.vaccines v ON v.vaccine_id = s.vaccine_id
)

SELECT
  d.drive_id,
  'child'::TEXT              AS subject_kind,
  ir.child_id                AS subject_id,
  'immunization_records'::TEXT AS record_table,
  ir.immunization_record_id  AS record_id,
  ir.vaccination_date,
  ir.source
FROM public.immunization_records ir
JOIN public.vaccines rv ON rv.vaccine_id = ir.vaccine_id
JOIN drive d
  ON d.target_recipients = 'child'
 AND (
       ir.immunization_schedule_id = d.drive_id
       OR (
            ir.immunization_schedule_id IS NULL
        AND d.is_canonical
        AND ir.facility_id      = d.facility_id
        AND ir.vaccination_date = d.schedule_date
        AND rv.vaccine_name     = d.vaccine_name
       )
     )
WHERE COALESCE(ir.status, 'administered') = 'administered'

UNION ALL

SELECT
  d.drive_id,
  'mother'::TEXT              AS subject_kind,
  td.mother_id                AS subject_id,
  'maternal_td_records'::TEXT AS record_table,
  td.td_record_id             AS record_id,
  td.vaccination_date,
  td.source
FROM public.maternal_td_records td
JOIN drive d
  ON d.target_recipients = 'mother'
 AND (
       td.immunization_schedule_id = d.drive_id
       OR (
            td.immunization_schedule_id IS NULL
        AND d.is_canonical
        AND td.facility_id      = d.facility_id
        AND td.vaccination_date = d.schedule_date
       )
     );

COMMENT ON VIEW public.vaccination_drive_doses IS
  'Every dose attributable to a vaccination drive, as {drive, subject, record}. '
  'Canonical statement of the attribution rule 20260912 introduced.';


-- ---------------------------------------------------------------------------
-- 3. What each drive cost the shelf, and who turned up
-- ---------------------------------------------------------------------------
--
-- Kept apart from vaccination_drive_analytics rather than folded into it, so
-- that neither view is defined in two migrations. The portal reads both and
-- merges on drive_id.
--
-- HOW UNITS AND VIALS ARE COUNTED
--
--   Since 20260822_dose_accounting.sql a dispense row carries the WHOLE UNITS
--   that left the shelf in `quantity`, which is:
--
--     -1  a sealed unit was broken into -- a single-dose ampoule handed over,
--         or a multi-dose vial opened for the first dose out of it
--      0  the dose came out of a vial that was already open, so nothing new
--         left the shelf
--
--   So units_consumed is what the stock count actually fell by, and it is
--   correctly SMALLER than the dose count for a multi-dose vaccine. Seven Td
--   doses out of one 10-dose vial is 1 unit, 1 vial opened, 6 doses drawn from
--   it -- and that is the honest reading, not a discrepancy.

CREATE OR REPLACE VIEW public.vaccination_drive_breakdown AS
WITH ledger AS (
  SELECT
    dd.drive_id,
    t.quantity,
    COALESCE(i.doses_per_unit, 1) AS doses_per_unit
  FROM public.vaccination_drive_doses dd
  JOIN public.inventory_transactions t
    ON t.reference_id = dd.record_id
   AND t.reference_type = CASE dd.subject_kind
                            WHEN 'child' THEN 'Child Immunization'
                            ELSE 'Maternal Td Immunization'
                          END
  JOIN public.inventory_batches b ON b.batch_id = t.batch_id
  JOIN public.inventory_items   i ON i.item_id  = b.item_id
  WHERE t.transaction_type = 'dispense'
),

stock AS (
  SELECT
    drive_id,
    COALESCE(SUM(-quantity), 0)                                        AS units_consumed,
    COUNT(*) FILTER (WHERE quantity < 0 AND doses_per_unit > 1)        AS vials_opened,
    COUNT(*) FILTER (WHERE quantity = 0)                               AS doses_from_open_vials,
    COUNT(*) FILTER (WHERE quantity < 0 AND doses_per_unit = 1)        AS single_dose_units
  FROM ledger
  GROUP BY drive_id
),

-- One row per person, not per dose: a child given two vaccines at one drive is
-- one boy, not two.
subject AS (
  SELECT DISTINCT
    dd.drive_id,
    dd.subject_kind,
    dd.subject_id,
    CASE dd.subject_kind
      WHEN 'child'  THEN LOWER(ch.sex)
      -- Maternal drives are Td in pregnancy. There is no sex column on mothers
      -- because there is nothing to record.
      ELSE 'female'
    END AS sex,
    CASE dd.subject_kind
      WHEN 'child'  THEN ROUND((dd.vaccination_date - bd.birthdate) / 30.4375, 1)
      ELSE ROUND((dd.vaccination_date - mo.birthdate) / 30.4375, 1)
    END AS age_months_at_dose
  FROM public.vaccination_drive_doses dd
  LEFT JOIN public.children      ch ON dd.subject_kind = 'child'  AND ch.child_id  = dd.subject_id
  LEFT JOIN public.birth_details bd ON dd.subject_kind = 'child'  AND bd.child_id  = dd.subject_id
  LEFT JOIN public.mothers       mo ON dd.subject_kind = 'mother' AND mo.mother_id = dd.subject_id
),

demographic AS (
  SELECT
    drive_id,
    COUNT(*)                                          AS subjects,
    COUNT(*) FILTER (WHERE sex = 'male')              AS male_count,
    COUNT(*) FILTER (WHERE sex = 'female')            AS female_count,
    COUNT(*) FILTER (WHERE sex IS NULL)               AS sex_not_recorded,
    ROUND(AVG(age_months_at_dose), 1)                 AS avg_age_months,
    MIN(age_months_at_dose)                           AS youngest_age_months,
    MAX(age_months_at_dose)                           AS oldest_age_months
  FROM subject
  GROUP BY drive_id
)

SELECT
  d.immunization_schedule_id                AS drive_id,
  COALESCE(s.units_consumed, 0)             AS units_consumed,
  COALESCE(s.vials_opened, 0)               AS vials_opened,
  COALESCE(s.doses_from_open_vials, 0)      AS doses_from_open_vials,
  COALESCE(s.single_dose_units, 0)          AS single_dose_units,
  COALESCE(dm.subjects, 0)                  AS subjects,
  COALESCE(dm.male_count, 0)                AS male_count,
  COALESCE(dm.female_count, 0)              AS female_count,
  COALESCE(dm.sex_not_recorded, 0)          AS sex_not_recorded,
  dm.avg_age_months,
  dm.youngest_age_months,
  dm.oldest_age_months
FROM public.immunization_schedule d
LEFT JOIN stock       s  ON s.drive_id  = d.immunization_schedule_id
LEFT JOIN demographic dm ON dm.drive_id = d.immunization_schedule_id;

COMMENT ON VIEW public.vaccination_drive_breakdown IS
  'Per drive: whole units and vials that left the shelf, doses drawn from vials '
  'already open, and the sex and age of the people who attended. units_consumed '
  'is correctly lower than the dose count for a multi-dose vaccine -- see the '
  'note in 20260914 on how dose accounting stores quantity.';


-- ---------------------------------------------------------------------------
-- 4. Grants
-- ---------------------------------------------------------------------------
GRANT SELECT ON public.child_immunization_coverage   TO anon, authenticated, service_role;
GRANT SELECT ON public.vaccination_drive_doses       TO anon, authenticated, service_role;
GRANT SELECT ON public.vaccination_drive_breakdown   TO anon, authenticated, service_role;

COMMIT;


-- ---------------------------------------------------------------------------
-- 5. Verify
-- ---------------------------------------------------------------------------
-- Coverage, the way the scorecard now reads it:
--
--   SELECT coverage_status, COUNT(*)
--     FROM public.child_immunization_coverage
--    WHERE assigned_bhc_id = 2
--    GROUP BY 1 ORDER BY 1;
--
-- The rate itself -- fully immunized over children old enough to be asked:
--
--   SELECT COUNT(*) FILTER (WHERE is_fully_immunized) AS fic,
--          COUNT(*) FILTER (WHERE is_fully_immunized IS NOT NULL) AS eligible
--     FROM public.child_immunization_coverage
--    WHERE assigned_bhc_id = 2;
--
-- What each drive cost, and who came:
--
--   SELECT a.schedule_date, a.vaccine_name, a.doses_administered,
--          b.units_consumed, b.vials_opened, b.doses_from_open_vials,
--          b.male_count, b.female_count, b.avg_age_months
--     FROM public.vaccination_drive_analytics a
--     JOIN public.vaccination_drive_breakdown b USING (drive_id)
--    WHERE a.facility_id = 2
--    ORDER BY a.schedule_date;
--
-- The Td drive should read 7 doses, 1 unit, 1 vial opened, 6 from the open
-- vial, 0 male / 7 female. The Pentavalent and PCV drives are single-dose
-- presentations, so units_consumed equals the dose count and vials_opened is 0.


-- ============================================================
-- ROLLBACK
-- ============================================================
-- DROP VIEW IF EXISTS public.vaccination_drive_breakdown;
-- DROP VIEW IF EXISTS public.vaccination_drive_doses;
-- DROP VIEW IF EXISTS public.child_immunization_coverage;
