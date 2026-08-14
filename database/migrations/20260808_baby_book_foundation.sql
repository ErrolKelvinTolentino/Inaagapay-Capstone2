-- InaAgapay: Baby Book data foundation
--
-- WHY
-- ---
-- The Baby Book screens currently render sample data held in Dart:
-- babyGrowthMilestoneSampleData, demoCurrentPregnancy, and a gallery of
-- asset images. Nothing persists. These tables give the feature somewhere
-- to live so the UI can be de-mocked section by section.
--
-- child_milestones and milestone_templates appear in suggested_schema.sql,
-- but that file describes a different database — UUID keys, children(id),
-- mother_profiles. The live schema is BIGSERIAL with child_id / pregnancy_id,
-- so these are written to match active-draftschema.sql instead of copied.
--
--
-- SCOPING: why a milestone attaches to a pregnancy OR a child, never both
-- ---------------------------------------------------------------------
-- A Baby Book spans a transition. Before birth it is about the pregnancy;
-- after birth it is about a person. Twins are what force the distinction:
--
--   * One gestation produces the bump photos, the fetal-growth timeline and
--     the mother's own prenatal care. Copying that into two books would be
--     wrong on the facts and would read as absurd to a mother.
--
--   * Two children then develop separately. One may sit at six months and
--     the other at eight. Merging their firsts destroys the record that the
--     book exists to keep.
--
-- So prenatal rows carry pregnancy_id and postnatal rows carry child_id,
-- enforced by a check constraint rather than by convention. children.
-- pregnancy_id already links the two, so a child's book can open with the
-- pregnancy chapter without duplicating a single row.
--
--
-- WHAT IS DELIBERATELY NOT HERE
-- -----------------------------
-- No table for PregnancyHealthRecord. The mother's supplements and
-- vaccines already have one: mother_medications holds name, frequency,
-- start/end date and an active/completed/stopped status, and
-- given_medications holds what was actually administered. That section of
-- the Baby Book is a read against existing tables, not new storage.
--
-- No stored status column on a milestone. Whether a milestone is upcoming,
-- current or completed follows from observed_on and the child's age or the
-- current gestational week — it is a function of today's date and must be
-- computed on read. Storing it would repeat the immunization defect fixed
-- in 20260807: an "On Time" badge that was a hardcoded literal and so
-- reported every dose as timely, including one given ten months late.
--
-- Photos reference the existing files table rather than carrying a URL, so
-- uploads keep one code path, one bucket convention, and the file_size /
-- mime_type / uploaded_by columns already recorded there.

BEGIN;

-- ---------------------------------------------------------------------------
-- milestone_templates — the catalogue of milestones worth recording
-- ---------------------------------------------------------------------------
-- Prenatal entries are placed by gestational week, postnatal entries by age
-- in months. The categories differ because the phases differ: the prenatal
-- set mirrors the existing BabyGrowthMilestoneCategory enum in Dart, while
-- the postnatal set uses the four standard developmental domains.
--
-- Rows are optional. A mother may add a milestone of her own, which is
-- stored with a null template_id and its own title.

CREATE TABLE IF NOT EXISTS public.milestone_templates (
    template_id BIGSERIAL PRIMARY KEY,
    phase character varying NOT NULL CHECK (
        phase = ANY (ARRAY ['prenatal', 'postnatal'])
    ),
    category character varying NOT NULL,
    title_en character varying NOT NULL,
    title_fil character varying,
    description_en text,
    description_fil text,
    -- Prenatal placement, in completed weeks of gestation.
    expected_start_week integer,
    expected_end_week integer,
    -- Postnatal placement, in completed months since birth.
    age_months_target integer,
    sort_order integer DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT milestone_templates_category_check CHECK (
        (
            phase = 'prenatal'
            AND category = ANY (
                ARRAY ['development', 'movement', 'checkup',
                       'ultrasound', 'trimester', 'personal_memory']
            )
        )
        OR (
            phase = 'postnatal'
            AND category = ANY (
                ARRAY ['motor', 'language', 'social', 'cognitive']
            )
        )
    ),

    -- Each phase is placed on its own timeline, and only its own.
    CONSTRAINT milestone_templates_placement_check CHECK (
        (
            phase = 'prenatal'
            AND expected_start_week IS NOT NULL
            AND age_months_target IS NULL
        )
        OR (
            phase = 'postnatal'
            AND age_months_target IS NOT NULL
            AND expected_start_week IS NULL
            AND expected_end_week IS NULL
        )
    ),

    CONSTRAINT milestone_templates_week_order_check CHECK (
        expected_end_week IS NULL
        OR expected_start_week IS NULL
        OR expected_end_week >= expected_start_week
    )
);

-- ---------------------------------------------------------------------------
-- baby_book_milestones — milestones actually recorded, prenatal or postnatal
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.baby_book_milestones (
    entry_id BIGSERIAL PRIMARY KEY,
    template_id bigint REFERENCES public.milestone_templates(template_id) ON DELETE SET NULL,

    -- Exactly one of these is set. See the scoping note above.
    pregnancy_id bigint REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    child_id bigint REFERENCES public.children(child_id) ON DELETE CASCADE,

    -- Present for a mother's own milestone, or to override a template's wording.
    title character varying,
    description text,

    -- Prenatal only: the gestational week the moment was recorded at.
    recorded_pregnancy_week integer,

    observed_on date,
    note text,
    photo_file_id bigint REFERENCES public.files(file_id) ON DELETE SET NULL,
    recorded_by bigint REFERENCES public.accounts(account_id) ON DELETE SET NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT baby_book_milestones_scope_check CHECK (
        (pregnancy_id IS NOT NULL AND child_id IS NULL)
        OR (pregnancy_id IS NULL AND child_id IS NOT NULL)
    ),

    -- A milestone needs a name from somewhere: a template, or its own title.
    CONSTRAINT baby_book_milestones_named_check CHECK (
        template_id IS NOT NULL
        OR (title IS NOT NULL AND length(btrim(title)) > 0)
    ),

    -- Gestational weeks belong to the prenatal side only.
    CONSTRAINT baby_book_milestones_week_scope_check CHECK (
        recorded_pregnancy_week IS NULL
        OR pregnancy_id IS NOT NULL
    )
);

-- ---------------------------------------------------------------------------
-- baby_memories — the photo keepsakes behind the memory gallery
-- ---------------------------------------------------------------------------
-- Separate from milestones on purpose. A milestone is a dated event on a
-- timeline; a memory is a picture with a caption in a gallery. They are two
-- surfaces in the UI and collapsing them would make both worse.

CREATE TABLE IF NOT EXISTS public.baby_memories (
    memory_id BIGSERIAL PRIMARY KEY,

    -- Same rule as milestones: a memory belongs to the pregnancy or to a child.
    pregnancy_id bigint REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    child_id bigint REFERENCES public.children(child_id) ON DELETE CASCADE,

    title character varying,
    caption text,
    memory_date date NOT NULL DEFAULT CURRENT_DATE,
    photo_file_id bigint REFERENCES public.files(file_id) ON DELETE SET NULL,
    created_by bigint REFERENCES public.accounts(account_id) ON DELETE SET NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT baby_memories_scope_check CHECK (
        (pregnancy_id IS NOT NULL AND child_id IS NULL)
        OR (pregnancy_id IS NULL AND child_id IS NOT NULL)
    )
);

-- ---------------------------------------------------------------------------
-- Indexes — every read is "the book for this pregnancy" or "for this child"
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_baby_book_milestones_pregnancy
    ON public.baby_book_milestones(pregnancy_id) WHERE pregnancy_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_baby_book_milestones_child
    ON public.baby_book_milestones(child_id) WHERE child_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_baby_book_milestones_template
    ON public.baby_book_milestones(template_id);

CREATE INDEX IF NOT EXISTS idx_baby_memories_pregnancy
    ON public.baby_memories(pregnancy_id) WHERE pregnancy_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_baby_memories_child
    ON public.baby_memories(child_id) WHERE child_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_milestone_templates_phase
    ON public.milestone_templates(phase, sort_order);

-- ---------------------------------------------------------------------------
-- The app authenticates against the accounts table with bcrypt rather than
-- Supabase Auth, and reaches Postgres with the anon key, so RLS is disabled
-- here for the same reason it is disabled on notifications and device_tokens
-- (run_this_in_supabase.sql, SECTION 3). This is a capstone-scope decision
-- and belongs in the study's limitations, not in a claim of production
-- readiness.
-- ---------------------------------------------------------------------------

ALTER TABLE public.milestone_templates   DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.baby_book_milestones  DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.baby_memories         DISABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.milestone_templates IS
  'Catalogue of milestones. phase=prenatal is placed by gestational week; '
  'phase=postnatal by age in months.';
COMMENT ON TABLE public.baby_book_milestones IS
  'Recorded milestones. Attaches to a pregnancy (prenatal, shared by twins) '
  'or to a child (postnatal, per child) — never both.';
COMMENT ON TABLE public.baby_memories IS
  'Photo keepsakes for the memory gallery, scoped like baby_book_milestones.';

COMMIT;
