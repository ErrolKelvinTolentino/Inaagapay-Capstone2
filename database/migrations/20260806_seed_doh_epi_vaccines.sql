-- InaAgapay: DOH Expanded Program on Immunization (EPI) childhood schedule
--
-- The `vaccines` table was empty, so the Add Immunization form had nothing to
-- offer and showed "No vaccines found in the database".
--
-- SOURCE
-- ------
-- Transcribed from the DOH immunization card ("Bakuna" / "Doses" columns) that
-- the barangay health centre actually issues to mothers. Names are kept exactly
-- as printed so a midwife can map each row on the paper card to one row in the
-- app without translating anything in her head.
--
--   Bakuna                                    Doses
--   BCG Vaccine                               1   At birth
--   Hepatitis B Vaccine                       1   At birth
--   Pentavalent Vaccine (DPT-Hep B-HIB)       3   1½, 2½, 3½ months
--   Oral Polio Vaccine (OPV)                  3   1½, 2½, 3½ months
--   Inactivated Polio Vaccine (IPV)           2   3½ & 9 months
--   Pneumococcal Conjugate Vaccine (PCV)      3   1½, 2½, 3½ months
--   Measles, Mumps, Rubella Vaccine (MMR)     2   9 months & 1 year
--
-- Plus Rotavirus Vaccine (2 doses, 1½ and 2½ months), which this BHC gives but
-- which is not pre-printed on the card — it goes in one of the blank rows.
--
-- 8 vaccines, 17 doses, birth through 12 months.
--
-- Deliberately NOT included:
--   * Vitamin A — supplementation, recorded separately from immunisation.
--
-- AGE ENCODING
-- ------------
-- recommended_age_months is numeric because the card is written in half months:
--   at birth = 0 | 1½ = 1.5 | 2½ = 2.5 | 3½ = 3.5 | 9 months = 9 | 1 year = 12
--
-- poster_category groups doses by the EPI visit they share, so the roadmap and
-- wall poster can render them in the same order as the card:
--   1 = at birth | 2 = 1½ months | 3 = 2½ months | 4 = 3½ months
--   5 = 9 months | 6 = 1 year

BEGIN;

-- Required by the idempotent upsert below, and stops a dose being defined twice.
CREATE UNIQUE INDEX IF NOT EXISTS unique_vaccine_name_dose
  ON public.vaccines (vaccine_name, dose_number);

INSERT INTO public.vaccines
  (vaccine_name, dose_number, recommended_age_months, target_recipients, notes, poster_category)
VALUES
  -- ── At birth ──────────────────────────────────────────────────────────────
  ('BCG Vaccine', 1, 0, 'child',
   'Protects against tuberculosis. Give within 24 hours of birth.', 1),
  ('Hepatitis B Vaccine', 1, 0, 'child',
   'Monovalent birth dose. Give within 24 hours of birth.', 1),

  -- ── Pentavalent: 1½, 2½, 3½ months ────────────────────────────────────────
  ('Pentavalent Vaccine (DPT-Hep B-HIB)', 1, 1.5, 'child',
   'Diphtheria, pertussis, tetanus, hepatitis B and Haemophilus influenzae type b.', 2),
  ('Pentavalent Vaccine (DPT-Hep B-HIB)', 2, 2.5, 'child',
   'Second dose. Minimum 4-week interval from the previous dose.', 3),
  ('Pentavalent Vaccine (DPT-Hep B-HIB)', 3, 3.5, 'child',
   'Third and final dose of the primary series.', 4),

  -- ── Oral Polio: 1½, 2½, 3½ months ─────────────────────────────────────────
  ('Oral Polio Vaccine (OPV)', 1, 1.5, 'child',
   'First dose.', 2),
  ('Oral Polio Vaccine (OPV)', 2, 2.5, 'child',
   'Second dose. Minimum 4-week interval from the previous dose.', 3),
  ('Oral Polio Vaccine (OPV)', 3, 3.5, 'child',
   'Third and final dose.', 4),

  -- ── Pneumococcal: 1½, 2½, 3½ months ───────────────────────────────────────
  ('Pneumococcal Conjugate Vaccine (PCV)', 1, 1.5, 'child',
   'First dose.', 2),
  ('Pneumococcal Conjugate Vaccine (PCV)', 2, 2.5, 'child',
   'Second dose. Minimum 4-week interval from the previous dose.', 3),
  ('Pneumococcal Conjugate Vaccine (PCV)', 3, 3.5, 'child',
   'Third and final dose.', 4),

  -- ── Rotavirus: 1½ and 2½ months ───────────────────────────────────────────
  -- Given at this BHC but not pre-printed on the card, so it is written into
  -- one of the blank rows.
  --
  -- Rotavirus is the one vaccine here with a hard UPPER age limit: the first
  -- dose must be given before 15 weeks and the series completed by 8 months,
  -- after which it should not be started or continued. The app does not
  -- enforce this — the ceiling is stated here so it reaches the midwife.
  ('Rotavirus Vaccine', 1, 1.5, 'child',
   'Oral. First dose must be given before 15 weeks of age — do not start later.', 2),
  ('Rotavirus Vaccine', 2, 2.5, 'child',
   'Oral. Second and final dose. Complete the series by 8 months of age.', 3),

  -- ── Inactivated Polio: 3½ and 9 months ────────────────────────────────────
  ('Inactivated Polio Vaccine (IPV)', 1, 3.5, 'child',
   'First dose, given alongside OPV 3.', 4),
  ('Inactivated Polio Vaccine (IPV)', 2, 9, 'child',
   'Second dose, given alongside the first MMR dose.', 5),

  -- ── MMR: 9 months and 1 year ──────────────────────────────────────────────
  ('Measles, Mumps, Rubella Vaccine (MMR)', 1, 9, 'child',
   'First measles-containing dose.', 5),
  ('Measles, Mumps, Rubella Vaccine (MMR)', 2, 12, 'child',
   'Second dose at 1 year. Completes the routine infant series.', 6)

ON CONFLICT (vaccine_name, dose_number) DO UPDATE
  SET recommended_age_months = EXCLUDED.recommended_age_months,
      target_recipients      = EXCLUDED.target_recipients,
      notes                  = EXCLUDED.notes,
      poster_category        = EXCLUDED.poster_category;

-- ── Maternal tetanus-diphtheria ──────────────────────────────────────────────
-- Not on the child's card. Included because the prenatal module records Td
-- doses against the mother; target_recipients keeps it out of the child form.

INSERT INTO public.vaccines
  (vaccine_name, dose_number, recommended_age_months, target_recipients, notes, poster_category)
VALUES
  ('Tetanus-Diphtheria (Td)', 1, 0, 'mother', 'As early as possible in pregnancy.', NULL),
  ('Tetanus-Diphtheria (Td)', 2, 0, 'mother', 'At least 4 weeks after Td1.', NULL),
  ('Tetanus-Diphtheria (Td)', 3, 0, 'mother', 'At least 6 months after Td2.', NULL),
  ('Tetanus-Diphtheria (Td)', 4, 0, 'mother', 'At least 1 year after Td3.', NULL),
  ('Tetanus-Diphtheria (Td)', 5, 0, 'mother', 'At least 1 year after Td4.', NULL)
ON CONFLICT (vaccine_name, dose_number) DO UPDATE
  SET target_recipients = EXCLUDED.target_recipients,
      notes             = EXCLUDED.notes;

COMMIT;

-- Verify — should return 17 child rows in card order:
--   SELECT poster_category, recommended_age_months, vaccine_name, dose_number
--     FROM public.vaccines
--    WHERE target_recipients = 'child'
--    ORDER BY recommended_age_months, vaccine_name, dose_number;
