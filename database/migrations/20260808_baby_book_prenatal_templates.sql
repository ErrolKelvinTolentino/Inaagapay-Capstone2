-- InaAgapay: seed the prenatal milestone catalogue
--
-- WHY
-- ---
-- These nine milestones already exist, hardcoded in Dart as
-- babyGrowthMilestoneSampleData. Moving them into milestone_templates is
-- what lets a recorded milestone point at a catalogue row instead of a
-- string literal, and what lets a mother's own additions sit alongside the
-- standard ones.
--
-- The wording is carried over as-is. Several entries deliberately say
-- "record it when documented by a healthcare provider" rather than
-- asserting a clinical finding — that phrasing belongs to the same rule the
-- rest of the app follows, and is not softened here.
--
--
-- template_key
-- ------------
-- Added by this migration rather than the previous one because it exists to
-- serve seeding: it is the stable natural key that makes re-running safe
-- (ON CONFLICT DO UPDATE) and gives the app an identifier that survives a
-- re-seed. The values match the existing Dart ids, so the mapping from
-- catalogue row to the current sample data is one-to-one and obvious.
--
--
-- FILIPINO TRANSLATIONS ARE INTENTIONALLY NULL
-- --------------------------------------------
-- The app is bilingual via the _t('English','Filipino') pattern, so the
-- columns exist. They are left empty rather than machine-translated: these
-- strings are read by mothers about their own pregnancy, and a clumsy
-- translation is worse here than an English fallback. They should be filled
-- in by someone who speaks the register the app is aiming for.
--
--
-- POSTNATAL TEMPLATES ARE NOT SEEDED HERE
-- ---------------------------------------
-- The child-scoped set — motor, language, social, cognitive by age in
-- months — needs DOH/WHO sourcing with citations before it goes in. Seeding
-- invented developmental norms would put unsourced clinical claims in front
-- of mothers, which is exactly what the AI positioning in this project is
-- careful to avoid.

BEGIN;

-- Stable natural key, so this migration is safe to run more than once.
ALTER TABLE public.milestone_templates
  ADD COLUMN IF NOT EXISTS template_key character varying;

CREATE UNIQUE INDEX IF NOT EXISTS idx_milestone_templates_key
  ON public.milestone_templates(template_key);

COMMENT ON COLUMN public.milestone_templates.template_key IS
  'Stable slug matching the Dart milestone ids. Used for idempotent seeding '
  'and for referring to a catalogue entry across re-seeds.';

INSERT INTO public.milestone_templates (
    template_key, phase, category, title_en, description_en,
    expected_start_week, expected_end_week, sort_order
) VALUES
    ('pregnancy-confirmed', 'prenatal', 'checkup',
     'Pregnancy confirmed',
     'Recorded after confirmation by a healthcare provider.',
     4, 6, 10),

    ('first-prenatal-checkup', 'prenatal', 'checkup',
     'First prenatal checkup',
     'A prenatal visit was added to this pregnancy record.',
     6, 10, 20),

    ('first-ultrasound', 'prenatal', 'ultrasound',
     'First ultrasound recorded',
     'An ultrasound record was added by the healthcare team.',
     6, 12, 30),

    ('heart-activity', 'prenatal', 'development',
     'Heart activity documented',
     'Mark this milestone only when it is documented by a healthcare provider.',
     6, 12, 40),

    ('second-trimester', 'prenatal', 'trimester',
     'Entered second trimester',
     'The pregnancy record reached the second-trimester range.',
     14, 14, 50),

    ('first-movement', 'prenatal', 'movement',
     'Baby’s first movement',
     'Movement may be noticed during this period. Record it when personally felt.',
     16, 24, 60),

    ('anatomy-scan', 'prenatal', 'ultrasound',
     'Anatomy scan recorded',
     'An ultrasound may be recorded around this stage depending on the healthcare plan.',
     18, 22, 70),

    ('third-trimester', 'prenatal', 'trimester',
     'Entered third trimester',
     'This stage is commonly reached around week 28.',
     28, 28, 80),

    ('birth-preparation', 'prenatal', 'checkup',
     'Birth preparation stage',
     'Birth planning may happen during this period with the healthcare team.',
     32, 40, 90)

ON CONFLICT (template_key) DO UPDATE SET
    phase               = EXCLUDED.phase,
    category            = EXCLUDED.category,
    title_en            = EXCLUDED.title_en,
    description_en      = EXCLUDED.description_en,
    expected_start_week = EXCLUDED.expected_start_week,
    expected_end_week   = EXCLUDED.expected_end_week,
    sort_order          = EXCLUDED.sort_order;

COMMIT;
