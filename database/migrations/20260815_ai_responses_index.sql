-- 20260815_ai_responses_index.sql
--
-- Indexes the lookups that were timing out the mother profile.
--
-- SYMPTOM
-- Opening a mother's profile returned
--   PostgrestException(message: canceling statement due to statement timeout,
--                      code: 57014)
-- intermittently at first, then every time for the mothers with the most
-- records.
--
-- CAUSE
-- ai_responses has no index of any kind. The profile reads it with
--
--   .eq('reference_table', 'prenatal_checkups')
--   .eq('response_type', 'risk_assessment')
--   .inFilter('reference_id', checkupIds)
--
-- which is a sequential scan over the whole table. That table gains rows with
-- every AI call — every ultrasound analysis, lab interpretation and risk
-- assessment — so the scan lengthens as the system is used, and a demo session
-- full of OCR runs is exactly what pushes it past the statement timeout. The
-- failure therefore arrives suddenly and gets worse, never better.
--
-- The other tables the profile touches are already covered: see
-- idx_clinical_encounters_pregnancy and idx_pregnancy_risk_pregnancy in
-- active-draftschema.sql.
--
-- IMPACT
-- Purely additive. No table is altered, no row is rewritten, no query needs
-- changing. Postgres begins using these on the next query. Building them locks
-- the table only briefly at this data size; CONCURRENTLY is noted below for a
-- production-sized table.
--
-- Note the app was also made to survive this independently: the profile now
-- degrades to loading without AI commentary rather than failing whole. The
-- index removes the reason it would need to.

-- The exact shape the profile filters by. Column order matters: the two
-- equality predicates come first so the index can seek straight to the
-- matching block, then reference_id narrows within it.
CREATE INDEX IF NOT EXISTS idx_ai_responses_reference
    ON public.ai_responses (reference_table, response_type, reference_id);

-- Other screens look a response up by its record alone, without naming the
-- response type — the midwife dashboard's record detail does this.
CREATE INDEX IF NOT EXISTS idx_ai_responses_reference_id
    ON public.ai_responses (reference_id);

-- pregnancy_risk_factors is read by pregnancy_risk_id on the same screen and
-- has no index either. Smaller table, same shape of problem as it grows.
CREATE INDEX IF NOT EXISTS idx_pregnancy_risk_factors_risk
    ON public.pregnancy_risk_factors (pregnancy_risk_id);

-- ============================================================
-- If this is ever run against a large, live table, prefer the
-- non-blocking form instead (cannot run inside a transaction):
--
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_responses_reference
--       ON public.ai_responses (reference_table, response_type, reference_id);
--
-- ROLLBACK
--   DROP INDEX IF EXISTS idx_ai_responses_reference;
--   DROP INDEX IF EXISTS idx_ai_responses_reference_id;
--   DROP INDEX IF EXISTS idx_pregnancy_risk_factors_risk;
-- ============================================================
