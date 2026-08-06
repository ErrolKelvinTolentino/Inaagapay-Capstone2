-- InaAgapay: upper age limit for vaccines that have one
--
-- WHY THIS IS NEEDED BEFORE "PAST DUE"
-- ------------------------------------
-- The immunization picker is gaining a "Past due" group, which tells the
-- midwife to catch a child up on doses they should already have had.
--
-- That is correct for every vaccine in the DOH schedule except Rotavirus.
-- Rotavirus has a hard upper age limit -- the first dose must not be started
-- after 15 weeks, and the series must not continue past 8 months, because of
-- intussusception risk in older infants. Labelling it "Past due" for a
-- 10-month-old would be telling the midwife to give something contraindicated:
-- worse than saying nothing at all.
--
-- recommended_age_months is a floor; this adds the matching ceiling, so a
-- vaccine that is no longer appropriate can be shown as such rather than as a
-- catch-up target.
--
-- Null means no upper limit, which is true of every other vaccine here.

BEGIN;

ALTER TABLE public.vaccines
  ADD COLUMN IF NOT EXISTS maximum_age_months NUMERIC;

COMMENT ON COLUMN public.vaccines.maximum_age_months IS
  'Age after which this dose should no longer be given. Null = no upper limit. Only Rotavirus has one in the DOH childhood schedule.';

-- Rotavirus, per DOH/WHO guidance:
--   dose 1 must be started before 15 weeks  (15 / 4.345 = 3.45 months)
--   the series must be completed by 8 months
UPDATE public.vaccines
   SET maximum_age_months = 3.45
 WHERE vaccine_name = 'Rotavirus Vaccine'
   AND dose_number = 1;

UPDATE public.vaccines
   SET maximum_age_months = 8
 WHERE vaccine_name = 'Rotavirus Vaccine'
   AND dose_number = 2;

COMMIT;

-- Verify — only the two Rotavirus rows should have a ceiling:
--   SELECT vaccine_name, dose_number, recommended_age_months, maximum_age_months
--     FROM public.vaccines
--    WHERE maximum_age_months IS NOT NULL;
