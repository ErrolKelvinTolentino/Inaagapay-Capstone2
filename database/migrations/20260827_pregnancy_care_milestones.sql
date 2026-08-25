-- InaAgapay: replace the prenatal milestone catalogue with recommended care
--
-- WHY
-- ---
-- The nine templates seeded by 20260808_baby_book_prenatal_templates mixed
-- two different kinds of thing:
--
--   care she can attend      first prenatal checkup, ultrasound, birth prep
--   things that just happen  heart activity, baby's first movement,
--                            entered second trimester, entered third
--
-- In one list they cannot be acted on. A mother reading the timeline could
-- not tell which rows were hers to do something about, and "Entered second
-- trimester" sitting between two checkups implied it was an appointment.
--
-- Fetal development already has a home: the growth journey above this
-- section, month by month. What belongs in a *milestone* list is the prenatal
-- care a pregnancy is generally expected to receive — which is what this
-- migration seeds, in the order it is usually given.
--
--
-- THE OLD ROWS ARE RETIRED, NOT DELETED
-- -------------------------------------
-- baby_book_milestones.template_id references this table ON DELETE SET NULL,
-- so deleting a template would silently sever every milestone already
-- recorded against it — a mother's recorded anatomy scan would survive as a
-- row with no name. Setting is_active = false hides them from the catalogue
-- (loadPrenatalTemplates filters on it) while every recorded entry keeps
-- pointing at the row that explains what it was.
--
--
-- OWNER
-- -----
-- All six are 'mother': they are her appointments, her bloods, her screening.
-- The previous split — some templates owned by the baby, so the Baby Book
-- could show "the baby's story" and leave her care to the Records tab — no
-- longer describes what this section is. It is now titled "Pregnancy
-- Milestones" and is explicitly about recommended procedures, so the call
-- sites that fetched owner = 'baby' fetch 'mother' with this change.
--
--
-- WEEK RANGES AND NAMED TESTS NEED SIGN-OFF
-- -----------------------------------------
-- The windows below (first visit within 12 weeks, an ultrasound before 24,
-- GDM screening at 24-28) and the tests named in the laboratory entry
-- (haemoglobin, blood group and Rh typing, HIV screening) follow common
-- prenatal practice, but they are not yet checked against the DOH schedule
-- with a citation. They must be confirmed by the project adviser before this
-- is shown to real mothers. Nothing here decides that a test applies to a
-- particular pregnancy — every entry ends by pointing at her midwife.
--
--
-- FILIPINO TRANSLATIONS ARE STILL NULL
-- ------------------------------------
-- Same reason as the migration this replaces: a clumsy translation of text a
-- mother reads about her own pregnancy is worse than an English fallback.
-- These need someone who speaks the register the app is aiming for.

BEGIN;

-- Retire the templates that are not recommended care. first-prenatal-checkup
-- is absent from this list on purpose: it survives, and is updated below.
UPDATE public.milestone_templates
   SET is_active = false
 WHERE phase = 'prenatal'
   AND template_key IN (
    'pregnancy-confirmed',
    'first-ultrasound',
    'heart-activity',
    'second-trimester',
    'first-movement',
    'anatomy-scan',
    'third-trimester',
    'birth-preparation'
 );

INSERT INTO public.milestone_templates (
    template_key, phase, category, owner, title_en, description_en,
    expected_start_week, expected_end_week, sort_order, is_active
) VALUES
    ('first-prenatal-checkup', 'prenatal', 'checkup', 'mother',
     'First prenatal checkup',
     'A first prenatal checkup is recommended within the first 12 weeks of pregnancy.',
     1, 12, 10, true),

    ('early-pregnancy-labs', 'prenatal', 'checkup', 'mother',
     'Early-pregnancy laboratory tests',
     'Haemoglobin testing, blood group and Rh typing, and HIV screening are commonly recommended during early prenatal care. Ask your midwife which tests are right for you.',
     1, 12, 20, true),

    -- Weeks 1-24 rather than a bare deadline of 24: the window is what she
    -- can act in. Carrying only the deadline sorts the row to where it is
    -- due instead of where it becomes possible, filing an ultrasound she
    -- could have today below her third-trimester checkups.
    ('ultrasound-record', 'prenatal', 'ultrasound', 'mother',
     'Ultrasound record',
     'At least one ultrasound is recommended before 24 weeks of pregnancy.',
     1, 24, 30, true),

    ('second-trimester-checkups', 'prenatal', 'checkup', 'mother',
     'Second-trimester prenatal checkups',
     'Prenatal checkups continue through the second trimester. Follow the schedule your midwife gives you.',
     13, 27, 40, true),

    ('gestational-diabetes-screening', 'prenatal', 'checkup', 'mother',
     'Gestational-diabetes screening',
     'Screening for gestational diabetes is generally recommended between 24 and 28 weeks of pregnancy. Ask your midwife whether it is right for your pregnancy.',
     24, 28, 50, true),

    -- Open-ended end week: checkups continue to birth, so there is no week
    -- at which this stops being true.
    ('third-trimester-checkups', 'prenatal', 'checkup', 'mother',
     'Third-trimester prenatal checkups',
     'Prenatal checkups continue from 28 weeks and may become more frequent. Follow the schedule your midwife gives you.',
     28, NULL, 60, true)

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
