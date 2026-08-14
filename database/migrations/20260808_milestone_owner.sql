-- InaAgapay: split milestones by whose story they belong to
--
-- WHY
-- ---
-- The catalogue was organised by *when* — prenatal or postnatal. That put
-- the mother's first prenatal checkup and her birth plan in something
-- called a Baby Book, alongside her iron and folic acid.
--
-- When is the wrong axis. An anatomy scan produces two things on the same
-- afternoon: a clinical report, which is hers, and a first picture of the
-- baby, which is his. They belong in different books despite sharing a
-- date.
--
-- So `phase` keeps doing what it is good at — placing an entry on a
-- timeline, by gestational week or by age in months — and a new `owner`
-- column answers the separate question of which book it appears in.
--
--     phase  = where on the timeline
--     owner  = whose story it is
--
-- The two are independent. A prenatal entry can belong to either book; a
-- postnatal entry is almost always the baby's, but the column does not
-- assume it, because postpartum care is the mother's and will need a home.
--
-- Default is 'baby'. Postnatal templates, which do not exist yet, are the
-- child's by nature, and defaulting the common case keeps their seed
-- simple. The nine prenatal rows are assigned explicitly below.

BEGIN;

ALTER TABLE public.milestone_templates
  ADD COLUMN IF NOT EXISTS owner character varying NOT NULL DEFAULT 'baby';

-- Added separately from the column so re-running cannot stack duplicates.
ALTER TABLE public.milestone_templates
  DROP CONSTRAINT IF EXISTS milestone_templates_owner_check;

ALTER TABLE public.milestone_templates
  ADD CONSTRAINT milestone_templates_owner_check
  CHECK (owner = ANY (ARRAY ['mother', 'baby']));

COMMENT ON COLUMN public.milestone_templates.owner IS
  'Which book this appears in. ''mother'' = her care (Mother Book), '
  '''baby'' = the child''s story (Baby Book). Independent of phase, which '
  'only places the entry on a timeline.';

CREATE INDEX IF NOT EXISTS idx_milestone_templates_owner_phase
  ON public.milestone_templates(owner, phase, sort_order);

-- ---------------------------------------------------------------------------
-- Re-sort the nine prenatal templates
-- ---------------------------------------------------------------------------
-- Read the test as: if the baby could one day read this book, is this line
-- about him, or about his mother's care?
--
--   pregnancy-confirmed     baby    the day she learned about him
--   first-ultrasound        baby    his first picture
--   heart-activity          baby    his heartbeat
--   first-movement          baby    his first kick
--   anatomy-scan            baby    his picture; the report stays hers
--
--   first-prenatal-checkup  mother  her care
--   second-trimester        mother  her pregnancy progressing
--   third-trimester         mother  her pregnancy progressing
--   birth-preparation       mother  her birth plan

UPDATE public.milestone_templates
   SET owner = 'mother'
 WHERE template_key IN (
    'first-prenatal-checkup',
    'second-trimester',
    'third-trimester',
    'birth-preparation'
 );

UPDATE public.milestone_templates
   SET owner = 'baby'
 WHERE template_key IN (
    'pregnancy-confirmed',
    'first-ultrasound',
    'heart-activity',
    'first-movement',
    'anatomy-scan'
 );

COMMIT;
