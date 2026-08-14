-- InaAgapay: minimum interval between doses
--
-- WHY
-- ---
-- The app decides whether a dose is due from the child's AGE alone. That is
-- correct for a child on schedule and wrong for every catch-up — which is
-- exactly when a midwife needs the guidance.
--
-- Worked example. A ten-month-old is given Pentavalent 1 today. The app then
-- reports Pentavalent 2 as "2½ months · 7 months late", when in truth it is
-- due in four weeks and giving it now would be too early. Doses given below
-- the minimum interval may not count and can need repeating, so the current
-- display does not merely confuse — it points at a real clinical error.
--
-- The due date for a later dose is therefore:
--
--     max( date the child reaches the scheduled age,
--          date of the previous dose + minimum interval )
--
-- The EPI primary series uses a four-week minimum throughout (Pentavalent,
-- OPV, PCV, Rotavirus, IPV, MCV/MMR). The seeded notes already say so —
-- "Minimum 4-week interval from the previous dose" — but nothing read it.
--
-- The value belongs on the LATER dose: it is the wait required before *this*
-- dose may be given. First doses have no predecessor, so they stay null.

BEGIN;

ALTER TABLE public.vaccines
  ADD COLUMN IF NOT EXISTS minimum_interval_weeks INTEGER;

COMMENT ON COLUMN public.vaccines.minimum_interval_weeks IS
  'Weeks that must pass after the previous dose of the same vaccine before this dose may be given. Null on first doses, which have no predecessor.';

UPDATE public.vaccines
   SET minimum_interval_weeks = 4
 WHERE target_recipients = 'child'
   AND dose_number > 1
   AND minimum_interval_weeks IS NULL;

COMMIT;

-- Verify — every dose after the first should carry a 4-week interval:
--   SELECT vaccine_name, dose_number, recommended_age_months, minimum_interval_weeks
--     FROM public.vaccines
--    WHERE target_recipients = 'child'
--    ORDER BY recommended_age_months, vaccine_name, dose_number;
