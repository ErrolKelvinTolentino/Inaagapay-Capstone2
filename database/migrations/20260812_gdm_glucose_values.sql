-- 20260812_gdm_glucose_values.sql
--
-- Adds plasma glucose columns to lab_tests so gestational diabetes screening
-- results can be stored as numbers instead of prose.
--
-- WHY
-- lab_tests already stores discrete values for the tests the app interprets:
-- hemoglobin_g_dl, hematocrit_pct, wbc_count, platelet_count,
-- urinalysis_protein, urinalysis_glucose. Glucose tolerance results had no
-- such home, so an OGTT could only ever land in the free-text remarks field.
-- Text cannot be compared against a threshold, counted in analytics, charted,
-- or used to raise a reminder — which is the whole of what was asked for.
--
-- Note that urinalysis_glucose is NOT a substitute. That is a urine dipstick
-- result recorded as a category; these are plasma glucose measurements in
-- mg/dL. Glycosuria is a prompt to test properly, not a test result.
--
-- WHY FOUR COLUMNS
-- Two screening protocols are in use in the Philippines and the choice has not
-- been confirmed with the clinical adviser yet:
--
--   One-step  — 75g OGTT, samples at fasting / 1 hour / 2 hours
--   Two-step  — 50g glucose challenge, then 100g OGTT with a 3-hour sample
--
-- Covering the 3-hour sample now means confirming the protocol later needs no
-- second migration. Unused columns stay NULL and cost nothing.
--
-- IMPACT
-- Purely additive. No existing column is altered or dropped, no existing row
-- is rewritten, and every column is nullable, so every current INSERT and
-- SELECT continues to work untouched. Reversible — see the rollback at the
-- bottom.
--
-- UNITS
-- mg/dL, matching how Philippine laboratories report. If a report is in
-- mmol/L the value must be converted before storage (mmol/L x 18.0182), and
-- the app must not guess which unit it was given.

ALTER TABLE public.lab_tests
    ADD COLUMN IF NOT EXISTS fasting_glucose_mg_dl numeric,
    ADD COLUMN IF NOT EXISTS glucose_1hr_mg_dl numeric,
    ADD COLUMN IF NOT EXISTS glucose_2hr_mg_dl numeric,
    ADD COLUMN IF NOT EXISTS glucose_3hr_mg_dl numeric;

COMMENT ON COLUMN public.lab_tests.fasting_glucose_mg_dl IS
    'Fasting plasma glucose in mg/dL. Used by both the 75g and 100g OGTT protocols.';
COMMENT ON COLUMN public.lab_tests.glucose_1hr_mg_dl IS
    'Plasma glucose 1 hour after the glucose load, mg/dL. Also holds the 50g glucose challenge screening result.';
COMMENT ON COLUMN public.lab_tests.glucose_2hr_mg_dl IS
    'Plasma glucose 2 hours after the glucose load, mg/dL.';
COMMENT ON COLUMN public.lab_tests.glucose_3hr_mg_dl IS
    'Plasma glucose 3 hours after the glucose load, mg/dL. Two-step 100g protocol only; NULL under the one-step protocol.';

-- Sanity bounds rather than clinical thresholds. These reject transcription
-- errors (a decimal in the wrong place, or a mmol/L figure entered as mg/dL)
-- without expressing any opinion about what counts as diabetes — that
-- judgement belongs in lib/services/gestational_diabetes_screening.dart, where
-- it is cited and configurable, not frozen into the database.
ALTER TABLE public.lab_tests
    DROP CONSTRAINT IF EXISTS chk_glucose_plausible;

ALTER TABLE public.lab_tests
    ADD CONSTRAINT chk_glucose_plausible CHECK (
        (fasting_glucose_mg_dl IS NULL OR (fasting_glucose_mg_dl >= 20 AND fasting_glucose_mg_dl <= 600))
        AND (glucose_1hr_mg_dl IS NULL OR (glucose_1hr_mg_dl >= 20 AND glucose_1hr_mg_dl <= 600))
        AND (glucose_2hr_mg_dl IS NULL OR (glucose_2hr_mg_dl >= 20 AND glucose_2hr_mg_dl <= 600))
        AND (glucose_3hr_mg_dl IS NULL OR (glucose_3hr_mg_dl >= 20 AND glucose_3hr_mg_dl <= 600))
    );

-- Finding pregnancies with a glucose result is a "has any value" question, so
-- the index covers the fasting sample, which every protocol records.
CREATE INDEX IF NOT EXISTS idx_lab_tests_fasting_glucose
    ON public.lab_tests (pregnancy_id)
    WHERE fasting_glucose_mg_dl IS NOT NULL;

-- ============================================================
-- ROLLBACK — run only if this migration must be undone.
-- Dropping these columns destroys any glucose values already recorded.
-- ============================================================
-- DROP INDEX IF EXISTS idx_lab_tests_fasting_glucose;
-- ALTER TABLE public.lab_tests DROP CONSTRAINT IF EXISTS chk_glucose_plausible;
-- ALTER TABLE public.lab_tests
--     DROP COLUMN IF EXISTS fasting_glucose_mg_dl,
--     DROP COLUMN IF EXISTS glucose_1hr_mg_dl,
--     DROP COLUMN IF EXISTS glucose_2hr_mg_dl,
--     DROP COLUMN IF EXISTS glucose_3hr_mg_dl;
