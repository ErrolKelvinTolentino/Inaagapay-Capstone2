-- ==============================================================================
-- SEED: 11_tarcan_child_immunization.sql
--
-- Gives six of the ten Tarcan mothers an older child, each with a real
-- immunization history, so that the Immunization Rate scorecard and the Infant
-- Immunization Status chart have something to measure.
--
-- WHY OLDER CHILDREN ARE NEEDED AT ALL
--
--   The ten infants from 10_tarcan_drive_scenario.sql were born in March and
--   April 2026. They are around five months old, and "fully immunized" is a
--   question about a child who has REACHED twelve months -- see the note in
--   20260914. Asking it of a five-month-old would count every newborn in the
--   barangay as an immunization failure.
--
--   So the coverage figure needs children old enough to have finished. These
--   six were born in 2025 and are 14 to 19 months old.
--
-- THE SPREAD
--
--   Deliberately not all complete. A rate of 100% demonstrates nothing, and the
--   three ways a child falls short are each a different piece of work for the
--   midwife:
--
--     Diwata Bituin       19 mo  female  all 17 doses      fully immunized
--     Emman Cuenca        18 mo  male    all 17 doses      fully immunized
--     Kiara Dalisay       17 mo  female  all 17 doses      fully immunized
--     Tomas Espiritu      17 mo  male    6 doses           Pentavalent dropout
--     Bianca Fajardo      15 mo  female  15 doses          measles gap
--     Ismael Gatchalian   15 mo  male    2 doses           never came back
--
--   That is 3 of 6 fully immunized -- 50% -- against the ten infants who are
--   too young to be asked and are reported separately as on-schedule or behind.
--
--     Tomas   started the series and stopped. Penta 1 but no Penta 3 is the
--             standard EPI dropout read: he reached the centre once, so this is
--             a follow-up problem, not an access one.
--     Bianca  had everything except measles. The commonest real gap, and the
--             one that causes outbreaks.
--     Ismael  had his birth doses in hospital and was never brought back. An
--             access problem, and a different conversation entirely.
--
--   Three boys and three girls, which with the ten infants leaves Tarcan at
--   eight of each -- so the sex breakdown on the reports page is not an
--   artefact of the seed.
--
-- THESE DOSES DRAW NO STOCK, AND THAT IS DELIBERATE
--
--   Every dose here is written as source = 'outside' with evidence =
--   'immunization_card': the history a mother brings in on the child's card
--   when she enrols. That is what 20260806_immunization_record_source.sql
--   exists to express, and it is the honest reading -- these doses were given
--   before the family was on Tarcan's books, and inventing ninety units of
--   2025 stock movement to pay for them would corrupt every inventory figure
--   on the portal to no purpose.
--
--   It also puts the distinction the RHU actually reports on the screen:
--
--     immunization coverage   counts every dose, wherever it was given
--     doses administered      counts only what this centre delivered
--
--   The drives in file 10 are the second number and really do move stock. This
--   file is the first. Both are true at once, which is the point.
--
--   Dose dates are computed from each child's birthdate and the catalogue's own
--   recommended_age_months, so the histories follow the DOH schedule rather
--   than dates picked by hand.
--
-- BEFORE YOU RUN THIS
--
--   1. database/seed/10_tarcan_drive_scenario.sql   (the ten mothers)
--   2. database/migrations/20260914_immunization_coverage_and_drive_demographics.sql
--      Not required to insert the rows, but nothing reads them until it is run.
--
-- RUNNING TWICE IS SAFE. Children are matched on mother and name, doses on
-- child, vaccine and date.
-- ==============================================================================

-- ---------------------------------------------------------------------------
-- 0. Preconditions
-- ---------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.accounts
     WHERE email_address = 'aurora.bituin.tarcan@inaagapay.internal'
  ) THEN
    RAISE EXCEPTION
      'The ten Tarcan mothers are missing. Run database/seed/10_tarcan_drive_scenario.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.vaccines
     WHERE target_recipients = 'child' AND recommended_age_months <= 12
  ) THEN
    RAISE EXCEPTION
      'The childhood vaccine catalogue is empty. Run database/migrations/20260806_seed_doh_epi_vaccines.sql first.';
  END IF;
END
$preflight$;


BEGIN;

DO $seed$
DECLARE
  c_facility_id CONSTANT BIGINT := 2;              -- Tarcan BHC
  c_municipality CONSTANT TEXT  := 'Baliwag';
  c_province    CONSTANT TEXT   := 'Bulacan';

  -- Which of the ten mothers gets an older child, by the name file 10 gave her.
  m_first TEXT[] := ARRAY['Aurora','Bernadette','Corazon','Divina','Elena','Felicidad'];
  m_last  TEXT[] := ARRAY['Bituin','Cuenca','Dalisay','Espiritu','Fajardo','Gatchalian'];

  s_first TEXT[] := ARRAY['Diwata','Emman','Kiara','Tomas','Bianca','Ismael'];
  s_sex   TEXT[] := ARRAY['female','male','female','male','female','male'];
  s_born  DATE[] := ARRAY['2025-01-18','2025-02-22','2025-03-15',
                          '2025-04-09','2025-05-20','2025-06-11']::DATE[];

  -- How far each child got. Read by the CASE in the dose loop below.
  s_plan  TEXT[] := ARRAY['complete','complete','complete',
                          'penta_dropout','measles_gap','birth_only'];

  s_weight NUMERIC[] := ARRAY[3.2, 3.5, 2.9, 3.4, 3.0, 3.6];
  s_length NUMERIC[] := ARRAY[49.5, 50.0, 48.0, 50.0, 48.5, 51.0];

  v_midwife_id BIGINT;
  v_mother_id  BIGINT;
  v_child_id   BIGINT;
  v_email      TEXT;
  v_date       DATE;
  v_include    BOOLEAN;
  v_planted    INT := 0;
  i            INT;
  v_vac        RECORD;
BEGIN

  -- The midwife records the card; she did not give these doses, so she is the
  -- recorder and not the administrator. immunization_records_outside_has_no_
  -- administrator enforces exactly that.
  SELECT mw.midwife_id INTO v_midwife_id
    FROM public.midwives mw
    JOIN public.accounts a ON a.account_id = mw.account_id
   WHERE a.email_address = 'midwife.tarcan@inaagapay.com';

  FOR i IN 1..6 LOOP
    v_email := lower(m_first[i]) || '.' || lower(m_last[i]) || '.tarcan@inaagapay.internal';

    SELECT m.mother_id INTO v_mother_id
      FROM public.mothers m
      JOIN public.accounts a ON a.account_id = m.account_id
     WHERE a.email_address = v_email;

    IF v_mother_id IS NULL THEN
      RAISE EXCEPTION 'Mother % is missing. Run database/seed/10_tarcan_drive_scenario.sql first.', v_email;
    END IF;

    -------------------------------------------------------------------------
    -- The older sibling
    -------------------------------------------------------------------------
    SELECT child_id INTO v_child_id
      FROM public.children
     WHERE mother_id = v_mother_id
       AND first_name = s_first[i]
       AND last_name  = m_last[i];

    IF v_child_id IS NULL THEN
      INSERT INTO public.children (
        mother_id, has_guardian_only, first_name, last_name, sex,
        assigned_bhc_id, registered_by_midwife_id
      ) VALUES (
        v_mother_id, false, s_first[i], m_last[i], s_sex[i],
        c_facility_id, v_midwife_id
      )
      RETURNING child_id INTO v_child_id;
    END IF;

    INSERT INTO public.birth_details (
      child_id, birthplace_facility, birthdate, birth_weight, birth_length,
      birthplace_city_municipality, birthplace_province, delivery_type, apgar_score
    ) VALUES (
      v_child_id, 'Baliwag District Hospital', s_born[i], s_weight[i], s_length[i],
      c_municipality, c_province, 'Normal Spontaneous Delivery', 9
    )
    ON CONFLICT (child_id) DO NOTHING;

    -- She now has two living children rather than the one file 10 recorded.
    UPDATE public.mothers
       SET gravida = GREATEST(COALESCE(gravida, 0), 2),
           para    = GREATEST(COALESCE(para, 0), 2),
           living_children = GREATEST(COALESCE(living_children, 0), 2)
     WHERE mother_id = v_mother_id;

    -------------------------------------------------------------------------
    -- The card
    --
    -- One pass over the catalogue's own first-year schedule. Each dose is dated
    -- from the child's birthdate and the age that dose is recommended at, so a
    -- "complete" history is complete by the same rule the coverage view checks
    -- rather than by a list typed out here.
    -------------------------------------------------------------------------
    FOR v_vac IN
      SELECT vaccine_id, vaccine_name, dose_number, recommended_age_months
        FROM public.vaccines
       WHERE target_recipients = 'child'
         AND recommended_age_months <= 12
       ORDER BY recommended_age_months, vaccine_name, dose_number
    LOOP
      v_include := CASE s_plan[i]
        WHEN 'complete'      THEN true
        -- Reached the centre for the six-week visit and never came again.
        WHEN 'penta_dropout' THEN v_vac.recommended_age_months <= 1.5
        -- Everything on time except the measles-containing doses at 9 and 12
        -- months.
        WHEN 'measles_gap'   THEN v_vac.vaccine_name NOT ILIKE '%measles%'
        -- Birth doses in hospital, then nothing.
        WHEN 'birth_only'    THEN v_vac.recommended_age_months = 0
        ELSE false
      END;

      CONTINUE WHEN NOT v_include;

      -- 30.4375 = 365.25/12, the month length the coverage view and the midwife
      -- app both use.
      v_date := s_born[i] + ROUND(v_vac.recommended_age_months * 30.4375)::INT;

      INSERT INTO public.immunization_records (
        child_id, vaccine_id, vaccination_date, dose_number, status,
        source, administration_place, facility_name, evidence,
        administered_by, recorded_by, inventory_deducted, remarks
      )
      SELECT
        v_child_id, v_vac.vaccine_id, v_date, v_vac.dose_number, 'administered',
        -- 'outside' forbids an administrator and a batch, which is precisely
        -- the shape of a dose read off a card.
        'outside', 'external_facility',
        'Not stated - card presented at enrolment', 'immunization_card',
        NULL, v_midwife_id, false,
        'Transcribed from the child immunization card at enrolment.'
      WHERE NOT EXISTS (
        SELECT 1 FROM public.immunization_records
         WHERE child_id = v_child_id
           AND vaccine_id = v_vac.vaccine_id
      );

      v_planted := v_planted + 1;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Six older siblings seeded at Tarcan; % dose rows considered.', v_planted;
END
$seed$;

COMMIT;


-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- Needs 20260914_immunization_coverage_and_drive_demographics.sql.
--
-- SELECT c.first_name || ' ' || c.last_name AS child,
--        v.age_months, v.sex, v.doses_received || '/' || v.doses_required AS doses,
--        v.coverage_status, v.is_penta_dropout, v.missing_doses
--   FROM public.child_immunization_coverage v
--   JOIN public.children c ON c.child_id = v.child_id
--  WHERE v.assigned_bhc_id = 2
--  ORDER BY v.age_months DESC NULLS LAST;
--
-- Expect the six older children at 17/17, 17/17, 17/17, 6/17, 15/17 and 2/17,
-- and the ten infants below them with coverage_status 'on_schedule' or
-- 'behind' -- never 'incomplete', which is reserved for children old enough to
-- have finished.
--
-- The rate the scorecard shows:
--
-- SELECT COUNT(*) FILTER (WHERE is_fully_immunized)          AS fully_immunized,
--        COUNT(*) FILTER (WHERE is_fully_immunized IS NOT NULL) AS old_enough_to_ask,
--        ROUND(100.0 * COUNT(*) FILTER (WHERE is_fully_immunized)
--                    / NULLIF(COUNT(*) FILTER (WHERE is_fully_immunized IS NOT NULL), 0), 1) AS rate
--   FROM public.child_immunization_coverage
--  WHERE assigned_bhc_id = 2;
--
-- Expect 3 of 6, 50.0%.
--
-- And that no stock moved for any of it:
--
-- SELECT COUNT(*) AS should_be_zero
--   FROM public.immunization_records
--  WHERE evidence = 'immunization_card'
--    AND (inventory_deducted OR inventory_batch_id IS NOT NULL);


-- ============================================================
-- REMOVING THE SCENARIO
--
-- Deletes the six older children and their transcribed doses. The ten mothers
-- and their infants from file 10 are left alone; their living_children stays at
-- 2, which is now wrong, so reset it too if that matters. Demo databases only.
-- ============================================================
-- DELETE FROM public.children
--  WHERE assigned_bhc_id = 2
--    AND first_name IN ('Diwata','Emman','Kiara','Tomas','Bianca','Ismael');
--
-- UPDATE public.mothers SET gravida = 1, para = 1, living_children = 1
--  WHERE assigned_bhc_id = 2;
