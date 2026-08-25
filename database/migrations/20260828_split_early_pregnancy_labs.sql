-- InaAgapay: split the early-pregnancy laboratory tests into four
--
-- WHY
-- ---
-- 20260827 seeded one row, 'early-pregnancy-labs', naming haemoglobin
-- testing, blood group and Rh typing, and HIV screening together.
--
-- A milestone is marked done as a whole, so bundled tests can only be
-- recorded as a set. A mother who had her blood typed but no HIV screening
-- had nothing honest to tap: mark it and she claims three tests she has not
-- had, leave it and the two she did have go unrecorded. They are ordered
-- separately, reported separately and outstanding separately, so they are
-- four rows.
--
-- Urinalysis is added at the same time. It was missing from the bundle and
-- belongs with the rest of routine early prenatal screening.
--
--
-- SAME RULES AS 20260827
-- ----------------------
-- The retired row is deactivated rather than deleted, because
-- baby_book_milestones.template_id is ON DELETE SET NULL and any milestone
-- already recorded against it would survive as a row with no name. Any
-- mother who had marked the bundle keeps that record pointing at a row that
-- still explains what it meant; she will see the four new rows unmarked
-- alongside it and can mark the ones she has actually had.
--
-- All four are owner = 'mother'. Descriptions say what the test is for in
-- plain words and stop there — none of them decides that a test applies to a
-- particular pregnancy.
--
-- The tests named here still need the project adviser's sign-off against the
-- DOH prenatal schedule, with a citation, before this is shown to real
-- mothers. That was true of 20260827 and is not resolved by this migration.

BEGIN;

UPDATE public.milestone_templates
   SET is_active = false
 WHERE phase = 'prenatal'
   AND template_key = 'early-pregnancy-labs';

INSERT INTO public.milestone_templates (
    template_key, phase, category, owner, title_en, description_en,
    expected_start_week, expected_end_week, sort_order, is_active
) VALUES
    ('haemoglobin-test', 'prenatal', 'checkup', 'mother',
     'Haemoglobin test',
     'A haemoglobin test checks for anaemia, which is common in pregnancy and treatable. It is commonly done during early prenatal care.',
     1, 12, 20, true),

    ('blood-typing', 'prenatal', 'checkup', 'mother',
     'Blood group and Rh typing',
     'This finds your blood type and whether you are Rh positive or negative. It is commonly done once during early prenatal care.',
     1, 12, 21, true),

    ('hiv-screening', 'prenatal', 'checkup', 'mother',
     'HIV screening',
     'HIV screening is commonly offered during early prenatal care. Your midwife can explain what the test involves and what happens next.',
     1, 12, 22, true),

    ('urinalysis', 'prenatal', 'checkup', 'mother',
     'Urinalysis',
     'A urine test checks for infection and for protein in the urine. It is commonly done during early prenatal care.',
     1, 12, 23, true)

ON CONFLICT (template_key) DO UPDATE SET
    phase               = EXCLUDED.phase,
    category            = EXCLUDED.category,
    owner               = EXCLUDED.owner,
    title_en            = EXCLUDED.title_en,
    description_en      = EXCLUDED.description_en,
    expected_start_week = EXCLUDED.expected_start_week,
    expected_end_week   = EXCLUDED.expected_end_week,
    sort_order          = EXCLUDED.sort_order,
    is_active           = EXCLUDED.is_active;

COMMIT;
