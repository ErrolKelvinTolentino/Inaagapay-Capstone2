-- Synthetic demonstration data for the 22 Baliwag barangays in RHU I-IV.
-- Run in the Supabase SQL editor AFTER the migrations through 20261001 and
-- database/migrations/20260806_seed_doh_epi_vaccines.sql. Demo/staging only.
-- This script uses the application's tables: immunization_schedule is a drive.
-- Existing accounts are never given a new password. Re-running is safe.
-- New RHU admins: rhu{1..4}.baliwag@inaagapay.ph / RHU{1..4}@123
-- New midwives and mothers: *@seed.inaagapay.test / SeedDemo@2026!
-- RHU admins must change their temporary password at first sign-in.
-- The .test domain and Demo surname make these fictional people identifiable.

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
BEGIN;

DROP TABLE IF EXISTS pg_temp.ina_seed_barangays;
CREATE TEMP TABLE ina_seed_barangays (
  ordinal integer PRIMARY KEY,
  rhu_code text NOT NULL,
  barangay text NOT NULL,
  slug text NOT NULL UNIQUE,
  legacy_name text
) ON COMMIT DROP;

INSERT INTO ina_seed_barangays VALUES
  ( 1, 'RHU1', 'Bagong Nayon',       'bagong_nayon',       NULL),
  ( 2, 'RHU1', 'Concepcion',         'concepcion',         NULL),
  ( 3, 'RHU1', 'Santo Cristo',       'santo_cristo',       NULL),
  ( 4, 'RHU1', 'Virgen delos Flores','virgen_delos_flores',NULL),
  ( 5, 'RHU2', 'Barangca',           'barangca',           NULL),
  ( 6, 'RHU2', 'Hinukay',            'hinukay',            NULL),
  ( 7, 'RHU2', 'Paitan',             'paitan',             NULL),
  ( 8, 'RHU2', 'Piel',               'piel',               NULL),
  ( 9, 'RHU2', 'San Roque',          'san_roque',          NULL),
  (10, 'RHU2', 'Santo Niño',         'santo_nino',         'Sto. Nino BHC'),
  (11, 'RHU2', 'Sulivan',            'sulivan',            NULL),
  (12, 'RHU2', 'Tangos',             'tangos',             NULL),
  (13, 'RHU2', 'Tilapayong',         'tilapayong',         NULL),
  (14, 'RHU3', 'Makinabang',         'makinabang',         NULL),
  (15, 'RHU3', 'San Jose',           'san_jose',           NULL),
  (16, 'RHU3', 'Santa Barbara',      'santa_barbara',      'Sta. Barbara BHC'),
  (17, 'RHU3', 'Tarcan',             'tarcan',             NULL),
  (18, 'RHU3', 'Tiaong',             'tiaong',             NULL),
  (19, 'RHU4', 'Poblacion',          'poblacion',          NULL),
  (20, 'RHU4', 'Sabang',             'sabang',             NULL),
  (21, 'RHU4', 'Subic',              'subic',              NULL),
  (22, 'RHU4', 'Tibag',              'tibag',              NULL);

DROP TABLE IF EXISTS pg_temp.ina_seed_drives;
CREATE TEMP TABLE ina_seed_drives (
  facility_id bigint NOT NULL,
  drive_key text NOT NULL,
  schedule_id bigint NOT NULL,
  PRIMARY KEY (facility_id, drive_key)
) ON COMMIT DROP;

DO $seed$
DECLARE
  r record;
  d record;
  a record;
  i integer;
  visit integer;
  v_rhu_id bigint;
  v_bhc_id bigint;
  v_account_id bigint;
  v_midwife_account_id bigint;
  v_midwife_id bigint;
  v_mother_id bigint;
  v_pregnancy_id bigint;
  v_encounter_id bigint;
  v_child_id bigint;
  v_vaccine_id bigint;
  v_schedule_id bigint;
  v_lmp date;
  v_visit_date date;
  v_birthdate date;
  v_email text;
  v_phone text;
  v_child_name text;
  v_td text;
  v_score_index integer;
  v_waz numeric;
  v_haz numeric;
  v_baz numeric;
  v_result jsonb;
  v_has_mother_registrar boolean;
  v_has_drive_bhc boolean;
  v_demo_hash text := crypt('SeedDemo@2026!', gen_salt('bf', 10));
  v_mother_names text[] := ARRAY['Ana', 'Bea', 'Carla', 'Diana', 'Elisa'];
  v_child_names text[] := ARRAY['Noah', 'Mia', 'Liam', 'Zoe', 'Eli'];
BEGIN
  IF to_regprocedure('public.assign_portal_account_facility(bigint,bigint)') IS NULL
     OR to_regclass('public.drive_invitations') IS NULL
     OR to_regclass('public.maternal_td_records') IS NULL THEN
    RAISE EXCEPTION 'Apply the MHO, drive invitation, and maternal Td migrations first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'immunization_records'
                    AND column_name = 'immunization_schedule_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'child_growth_records'
                       AND column_name = 'bmi_for_age_zscore') THEN
    RAISE EXCEPTION 'Apply the drive analytics and child growth migrations first.';
  END IF;
  IF (SELECT count(*) FROM public.health_facilities
       WHERE facility_code IN ('RHU1','RHU2','RHU3','RHU4') AND facility_type = 'RHU') <> 4 THEN
    RAISE EXCEPTION 'All four RHU facilities are required; run 20260821_mho_tier.sql first.';
  END IF;
  IF (SELECT count(*) FROM public.vaccines
       WHERE (vaccine_name, dose_number) IN (
         ('Tetanus-Diphtheria (Td)',1),
         ('Measles, Mumps, Rubella Vaccine (MMR)',1),
         ('Measles, Mumps, Rubella Vaccine (MMR)',2),
         ('Pentavalent Vaccine (DPT-Hep B-HIB)',1),
         ('BCG Vaccine',1), ('Hepatitis B Vaccine',1))) <> 6 THEN
    RAISE EXCEPTION 'Run 20260806_seed_doh_epi_vaccines.sql first.';
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'mothers'
       AND column_name = 'registered_by_midwife_id'
  ) INTO v_has_mother_registrar;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'immunization_schedule'
       AND column_name = 'bhc_id'
  ) INTO v_has_drive_bhc;

  -- The admin portal scopes each administrator through facility_assignments.
  FOR a IN SELECT * FROM (VALUES
      ('RHU1', 'rhu1.baliwag@inaagapay.ph', 'RHU One',   'RHU1@123'),
      ('RHU2', 'rhu2.baliwag@inaagapay.ph', 'RHU Two',   'RHU2@123'),
      ('RHU3', 'rhu3.baliwag@inaagapay.ph', 'RHU Three', 'RHU3@123'),
      ('RHU4', 'rhu4.baliwag@inaagapay.ph', 'RHU Four',  'RHU4@123')
    ) AS x(code, email, first_name, password)
  LOOP
    SELECT facility_id INTO STRICT v_rhu_id FROM public.health_facilities
      WHERE facility_code = a.code AND facility_type = 'RHU';
    INSERT INTO public.accounts
      (email_address, password_hash, account_type, first_name, last_name,
       is_verified, status, is_temporary_password, created_by)
    VALUES (a.email, crypt(a.password, gen_salt('bf', 10)), 'admin',
            a.first_name, 'Administrator', true, 'active', true, 'self')
    ON CONFLICT (email_address) DO NOTHING;
    SELECT account_id INTO STRICT v_account_id FROM public.accounts
      WHERE email_address = a.email AND account_type = 'admin';
    v_result := public.assign_portal_account_facility(v_account_id, v_rhu_id);
    IF (v_result->>'success')::boolean IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Could not assign %: %', a.email, v_result;
    END IF;
  END LOOP;

  FOR r IN SELECT * FROM ina_seed_barangays ORDER BY ordinal LOOP
    SELECT facility_id INTO STRICT v_rhu_id FROM public.health_facilities
      WHERE facility_code = r.rhu_code AND facility_type = 'RHU';

    -- Reuse existing BHC rows, including the old Santa Barbara spelling.
    SELECT facility_id INTO v_bhc_id
      FROM public.health_facilities
     WHERE facility_type = 'BHC'
       AND (lower(name) = lower(r.barangay || ' BHC')
            OR lower(name) = lower(r.legacy_name)
            OR lower(barangay) = lower(r.barangay))
     ORDER BY CASE WHEN lower(name) = lower(r.barangay || ' BHC') THEN 0
                   WHEN lower(name) = lower(r.legacy_name) THEN 1 ELSE 2 END,
              facility_id
     LIMIT 1;
    IF v_bhc_id IS NULL THEN
      INSERT INTO public.health_facilities
        (name, facility_type, facility_code, barangay, municipality, province,
         parent_facility_id, is_active)
      VALUES (r.barangay || ' BHC', 'BHC',
              'BHC' || lpad(r.ordinal::text, 2, '0'), r.barangay,
              'Baliwag', 'Bulacan', v_rhu_id, true)
      RETURNING facility_id INTO v_bhc_id;
    ELSE
      UPDATE public.health_facilities
         SET barangay = r.barangay, municipality = 'Baliwag', province = 'Bulacan',
             parent_facility_id = v_rhu_id, is_active = true
       WHERE facility_id = v_bhc_id;
    END IF;

    v_email := 'midwife.' || r.slug || '@seed.inaagapay.test';
    INSERT INTO public.accounts
      (email_address, password_hash, account_type, first_name, last_name,
       phone_number, is_verified, status, is_temporary_password, created_by)
    VALUES (v_email, v_demo_hash, 'midwife', 'Midwife', r.barangay || ' Demo',
            '0918' || lpad(r.ordinal::text, 7, '0'), true, 'active', false, 'self')
    ON CONFLICT (email_address) DO NOTHING;
    SELECT account_id INTO STRICT v_account_id FROM public.accounts
      WHERE email_address = v_email AND account_type = 'midwife';
    v_midwife_account_id := v_account_id;
    INSERT INTO public.midwives (account_id, assigned_bhc_id, position)
    VALUES (v_account_id, v_bhc_id, 'Barangay Midwife')
    ON CONFLICT (account_id) DO UPDATE
      SET assigned_bhc_id = EXCLUDED.assigned_bhc_id;
    SELECT midwife_id INTO STRICT v_midwife_id FROM public.midwives
      WHERE account_id = v_account_id;
    UPDATE public.facility_assignments
       SET is_active = false, ended_at = COALESCE(ended_at, now())
     WHERE account_id = v_midwife_account_id
       AND facility_id <> v_bhc_id AND COALESCE(is_active, true);
    INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
    SELECT v_midwife_account_id, v_bhc_id, true
     WHERE NOT EXISTS (SELECT 1 FROM public.facility_assignments
                        WHERE account_id = v_midwife_account_id
                          AND facility_id = v_bhc_id
                          AND COALESCE(is_active, true));

    -- Five drives per BHC: three held and two upcoming at the seed date.
    FOR d IN SELECT * FROM (VALUES
        ('td1_aug',   'Tetanus-Diphtheria (Td)',                 1, DATE '2026-08-12'),
        ('mmr1_sep',  'Measles, Mumps, Rubella Vaccine (MMR)',   1, DATE '2026-09-03'),
        ('td2_sep',   'Tetanus-Diphtheria (Td)',                 1, DATE '2026-09-16'),
        ('mmr2_oct',  'Measles, Mumps, Rubella Vaccine (MMR)',   2, DATE '2026-10-21'),
        ('penta_oct', 'Pentavalent Vaccine (DPT-Hep B-HIB)',    1, DATE '2026-10-22')
      ) AS x(drive_key, vaccine_name, dose_number, drive_date)
    LOOP
      SELECT vaccine_id INTO STRICT v_vaccine_id FROM public.vaccines
        WHERE vaccine_name = d.vaccine_name AND dose_number = d.dose_number;
      IF v_has_drive_bhc THEN
        INSERT INTO public.immunization_schedule
          (facility_id, bhc_id, vaccine_id, schedule_date, notes)
        SELECT v_bhc_id, v_bhc_id, v_vaccine_id, d.drive_date,
               '[InaAgapay demo] ' || d.drive_key
         WHERE NOT EXISTS (
           SELECT 1 FROM public.immunization_schedule s
            WHERE s.facility_id = v_bhc_id
              AND s.notes = '[InaAgapay demo] ' || d.drive_key);
      ELSE
        INSERT INTO public.immunization_schedule
          (facility_id, vaccine_id, schedule_date, notes)
        SELECT v_bhc_id, v_vaccine_id, d.drive_date,
               '[InaAgapay demo] ' || d.drive_key
         WHERE NOT EXISTS (
           SELECT 1 FROM public.immunization_schedule s
            WHERE s.facility_id = v_bhc_id
              AND s.notes = '[InaAgapay demo] ' || d.drive_key);
      END IF;
      SELECT immunization_schedule_id INTO STRICT v_schedule_id
        FROM public.immunization_schedule
       WHERE facility_id = v_bhc_id
         AND notes = '[InaAgapay demo] ' || d.drive_key;
      IF v_has_drive_bhc THEN
        UPDATE public.immunization_schedule
           SET bhc_id = v_bhc_id
         WHERE immunization_schedule_id = v_schedule_id
           AND bhc_id IS DISTINCT FROM v_bhc_id;
      END IF;
      INSERT INTO ina_seed_drives VALUES (v_bhc_id, d.drive_key, v_schedule_id);
    END LOOP;

    FOR i IN 1..5 LOOP
      v_email := 'mother.' || r.slug || '.' || i || '@seed.inaagapay.test';
      v_phone := '0917' || lpad((r.ordinal * 100 + i)::text, 7, '0');
      v_child_name := v_child_names[i];
      v_lmp := DATE '2026-04-01' + (i - 1) * 7;
      v_birthdate := DATE '2024-07-15' + (i - 1) * 30;

      INSERT INTO public.accounts
        (email_address, password_hash, account_type, first_name, last_name,
         phone_number, is_verified, status, is_temporary_password, created_by)
      VALUES (v_email, v_demo_hash, 'mother', v_mother_names[i], 'Demo',
              v_phone, true, 'active', false, v_midwife_account_id::text)
      ON CONFLICT (email_address) DO NOTHING;
      SELECT account_id INTO STRICT v_account_id FROM public.accounts
        WHERE email_address = v_email AND account_type = 'mother';

      INSERT INTO public.mothers
        (account_id, assigned_bhc_id, birthdate, house_number, street,
         barangay, city_municipality, province, height, weight, blood_type,
         status, gravida, para, abortus, living_children, philhealth_status,
         is_four_ps, civil_status)
      VALUES (v_account_id, v_bhc_id, make_date(1991 + i, 2, 10 + i),
              (100 + i)::text, 'Demo Street', r.barangay, 'Baliwag', 'Bulacan',
              155 + i, 55 + i, CASE WHEN i % 2 = 0 THEN 'A+' ELSE 'O+' END,
              'active', 2, 1, 0, 1,
              CASE WHEN i % 2 = 0 THEN 'Dependent' ELSE 'Member' END,
              i = 5, 'Married')
      ON CONFLICT (account_id) DO NOTHING;
      SELECT mother_id INTO STRICT v_mother_id FROM public.mothers
        WHERE account_id = v_account_id AND assigned_bhc_id = v_bhc_id;
      IF v_has_mother_registrar THEN
        EXECUTE 'UPDATE public.mothers SET registered_by_midwife_id = $1
                  WHERE mother_id = $2 AND registered_by_midwife_id IS NULL'
          USING v_midwife_id, v_mother_id;
      END IF;
      INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
      SELECT v_account_id, v_bhc_id, true
       WHERE NOT EXISTS (SELECT 1 FROM public.facility_assignments
                          WHERE account_id = v_account_id
                            AND facility_id = v_bhc_id
                            AND COALESCE(is_active, true));

      INSERT INTO public.emergency_contacts
        (mother_id, first_name, last_name, phone_number, affiliation,
         barangay, city_municipality, province)
      SELECT v_mother_id, 'Contact', 'Demo',
             '0920' || lpad((r.ordinal * 100 + i)::text, 7, '0'),
             'Spouse', r.barangay, 'Baliwag', 'Bulacan'
       WHERE NOT EXISTS (SELECT 1 FROM public.emergency_contacts
                          WHERE mother_id = v_mother_id AND last_name = 'Demo');
      IF i = 2 THEN
        INSERT INTO public.allergies
          (mother_id, allergen, remarks, status)
        SELECT v_mother_id, 'Penicillin', 'Synthetic history for demo', 'active'
         WHERE NOT EXISTS (SELECT 1 FROM public.allergies
                            WHERE mother_id = v_mother_id AND allergen = 'Penicillin');
      ELSIF i = 4 THEN
        INSERT INTO public.medical_conditions
          (mother_id, condition_name, remarks, status)
        SELECT v_mother_id, 'Anemia', 'Synthetic history for demo', 'active'
         WHERE NOT EXISTS (SELECT 1 FROM public.medical_conditions
                            WHERE mother_id = v_mother_id AND condition_name = 'Anemia');
      END IF;

      INSERT INTO public.pregnancies
        (mother_id, pre_pregnancy_weight, height_cm, fetal_count,
         pregnancy_risk_level, last_menstrual_period, expected_date_of_delivery,
         status)
      SELECT v_mother_id, 54 + i, 155 + i, '1', 'low', v_lmp,
             v_lmp + 280, 'ongoing'
       WHERE NOT EXISTS (SELECT 1 FROM public.pregnancies
                          WHERE mother_id = v_mother_id
                            AND last_menstrual_period = v_lmp);
      SELECT pregnancy_id INTO STRICT v_pregnancy_id FROM public.pregnancies
        WHERE mother_id = v_mother_id AND last_menstrual_period = v_lmp;

      FOR visit IN 1..2 LOOP
        v_visit_date := CASE WHEN visit = 1 THEN DATE '2026-08-12'
                             ELSE DATE '2026-09-16' END;
        v_td := CASE WHEN visit = 1 AND i <= 4 THEN 'Td1'
                     WHEN visit = 2 AND i <= 3 THEN 'Td2'
                     ELSE NULL END;
        INSERT INTO public.clinical_encounters
          (pregnancy_id, mother_id, recorded_by, facility_id, encounter_type,
           encounter_datetime, age_of_gestation_weeks, age_of_gestation_days,
           risk_status, midwife_notes, is_midwife_approved)
        SELECT v_pregnancy_id, v_mother_id, v_midwife_id, v_bhc_id,
               'checkup', v_visit_date + TIME '09:00',
               (v_visit_date - v_lmp) / 7, (v_visit_date - v_lmp) % 7,
               'low', 'Synthetic demo prenatal visit', true
         WHERE NOT EXISTS (SELECT 1 FROM public.clinical_encounters
                            WHERE pregnancy_id = v_pregnancy_id
                              AND encounter_type = 'checkup'
                              AND encounter_datetime::date = v_visit_date);
        SELECT encounter_id INTO STRICT v_encounter_id
          FROM public.clinical_encounters
         WHERE pregnancy_id = v_pregnancy_id AND encounter_type = 'checkup'
           AND encounter_datetime::date = v_visit_date;
        INSERT INTO public.prenatal_checkups
          (encounter_id, pregnancy_id, checkup_weight,
           blood_pressure_systolic, blood_pressure_diastolic,
           fetal_heart_beat, fundal_height_cm, td_vaccine_dose,
           edema, next_schedule)
        VALUES (v_encounter_id, v_pregnancy_id, 58 + i + visit,
                110 + i, 70 + i, 140 + i,
                CASE WHEN visit = 1 THEN 19 + i ELSE 23 + i END,
                v_td, 'none',
                CASE WHEN visit = 1 THEN DATE '2026-09-16'
                     ELSE DATE '2026-10-14' END)
        ON CONFLICT (encounter_id) DO NOTHING;
      END LOOP;

      -- The prenatal trigger normally writes these. The insert also covers a
      -- database where that optional sync trigger has not been installed.
      FOR visit IN 1..2 LOOP
        IF (visit = 1 AND i <= 4) OR (visit = 2 AND i <= 3) THEN
          SELECT schedule_id INTO STRICT v_schedule_id FROM ina_seed_drives
           WHERE facility_id = v_bhc_id
             AND drive_key = CASE WHEN visit = 1 THEN 'td1_aug' ELSE 'td2_sep' END;
          v_visit_date := CASE WHEN visit = 1 THEN DATE '2026-08-12'
                               ELSE DATE '2026-09-16' END;
          INSERT INTO public.maternal_td_records
            (mother_id, dose_number, vaccination_date, facility_id,
             facility_name, source, administered_by, inventory_deducted,
             immunization_schedule_id, remarks)
          VALUES (v_mother_id, 'Td' || visit, v_visit_date, v_bhc_id,
                  r.barangay || ' BHC', 'bhc', v_midwife_id, false,
                  v_schedule_id, 'Synthetic demo dose; no inventory deducted')
          ON CONFLICT (mother_id, dose_number) DO NOTHING;
          UPDATE public.maternal_td_records
             SET immunization_schedule_id = COALESCE(immunization_schedule_id, v_schedule_id),
                 facility_name = COALESCE(facility_name, r.barangay || ' BHC')
           WHERE mother_id = v_mother_id AND dose_number = 'Td' || visit
             AND vaccination_date = v_visit_date;
        END IF;
      END LOOP;

      INSERT INTO public.children
        (mother_id, assigned_bhc_id, registered_by_midwife_id,
         first_name, last_name, sex, has_guardian_only)
      SELECT v_mother_id, v_bhc_id, v_midwife_id, v_child_name, 'Demo',
             CASE WHEN i % 2 = 0 THEN 'female' ELSE 'male' END, false
       WHERE NOT EXISTS (SELECT 1 FROM public.children
                          WHERE mother_id = v_mother_id
                            AND first_name = v_child_name AND last_name = 'Demo');
      SELECT child_id INTO STRICT v_child_id FROM public.children
       WHERE mother_id = v_mother_id AND first_name = v_child_name
         AND last_name = 'Demo';
      INSERT INTO public.birth_details
        (child_id, birthplace_facility, birthdate, birth_weight, birth_length,
         birthplace_city_municipality, birthplace_province, delivery_type,
         apgar_score)
      VALUES (v_child_id, 'Demo birth facility', v_birthdate,
              3.1 + i * 0.04, 49 + i * 0.3,
              'Baliwag', 'Bulacan', 'Normal Spontaneous Delivery', 9)
      ON CONFLICT (child_id) DO NOTHING;

      -- Two measurements for each child. Z-scores are populated below from
      -- values calculated with the Flutter WHO reference data.
      FOR visit IN 1..2 LOOP
        v_visit_date := CASE WHEN visit = 1 THEN DATE '2026-08-15'
                             ELSE DATE '2026-09-15' END;
        v_score_index := (i - 1) * 2 + visit;
        v_waz := (ARRAY[-0.0714, 0.0625, -0.2308, -0.1429, -0.2308,
                         -0.1429, -0.2308, -0.1538, -0.0833, -0.0769]::numeric[])[v_score_index];
        v_haz := (ARRAY[-0.1613, -0.1563, -0.2813, -0.3030, -0.4667,
                         -0.2667, -0.5161, -0.5313, -0.2143, -0.2667]::numeric[])[v_score_index];
        v_baz := (ARRAY[0.0502, 0.1859, -0.0962, -0.0042, 0.1576,
                         0.0864, 0.1265, 0.2710, 0.0506, 0.2000]::numeric[])[v_score_index];
        INSERT INTO public.child_growth_records
          (child_id, measurement_date, child_weight, child_height,
           head_circumference_cm, weight_for_age_zscore,
           height_for_age_zscore, bmi_for_age_zscore,
           recorded_by, notes, created_at, updated_at)
        SELECT v_child_id, v_visit_date,
               (ARRAY[12.3,11.2,11.7,10.8,11.4]::numeric[])[i]
                 + (visit - 1) * 0.3,
               (ARRAY[87.5,84.8,85.5,83.0,84.5]::numeric[])[i]
                 + (visit - 1) * 0.8,
               (ARRAY[48.0,47.0,48.2,46.8,48.0]::numeric[])[i]
                 + (visit - 1) * 0.2,
               v_waz, v_haz, v_baz, v_midwife_id,
               'Synthetic demo measurement',
               v_visit_date + TIME '10:00', v_visit_date + TIME '10:00'
         WHERE NOT EXISTS (SELECT 1 FROM public.child_growth_records
                            WHERE child_id = v_child_id
                              AND measurement_date = v_visit_date);
      END LOOP;

      -- Birth doses were recorded elsewhere; the September MMR catch-up was
      -- delivered at the BHC to three invited children.
      FOR d IN SELECT * FROM (VALUES
          ('BCG Vaccine',          v_birthdate),
          ('Hepatitis B Vaccine',  v_birthdate)
        ) AS x(vaccine_name, dose_date)
      LOOP
        SELECT vaccine_id INTO STRICT v_vaccine_id FROM public.vaccines
         WHERE vaccine_name = d.vaccine_name AND dose_number = 1;
        INSERT INTO public.immunization_records
          (child_id, vaccine_id, vaccination_date, dose_number, status,
           source, facility_name, recorded_by, remarks)
        SELECT v_child_id, v_vaccine_id, d.dose_date, 1, 'administered',
               'outside', 'Demo birth facility', v_midwife_id,
               'Synthetic historical birth dose'
         WHERE NOT EXISTS (SELECT 1 FROM public.immunization_records
                            WHERE child_id = v_child_id AND vaccine_id = v_vaccine_id);
      END LOOP;
      IF i = 4 THEN
        -- One fully immunized child per BHC supplies a coverage comparison.
        -- These card doses occurred before this demo child was registered.
        FOR d IN SELECT vaccine_id, dose_number, recommended_age_months
                   FROM public.vaccines
                  WHERE target_recipients = 'child'
                    AND recommended_age_months <= 12
        LOOP
          INSERT INTO public.immunization_records
            (child_id, vaccine_id, vaccination_date, dose_number, status,
             source, facility_name, recorded_by, remarks)
          SELECT v_child_id, d.vaccine_id,
                 v_birthdate + round(d.recommended_age_months * 30.4375)::integer,
                 d.dose_number, 'administered', 'outside',
                 'Demo birth facility', v_midwife_id,
                 'Synthetic historical immunization card dose'
           WHERE NOT EXISTS (SELECT 1 FROM public.immunization_records
                              WHERE child_id = v_child_id
                                AND vaccine_id = d.vaccine_id);
        END LOOP;
      END IF;
      IF i <= 3 THEN
        SELECT vaccine_id INTO STRICT v_vaccine_id FROM public.vaccines
         WHERE vaccine_name = 'Measles, Mumps, Rubella Vaccine (MMR)'
           AND dose_number = 1;
        SELECT schedule_id INTO STRICT v_schedule_id FROM ina_seed_drives
         WHERE facility_id = v_bhc_id AND drive_key = 'mmr1_sep';
        INSERT INTO public.immunization_records
          (child_id, vaccine_id, vaccination_date, administered_by,
           recorded_by, dose_number, status, source, facility_id,
           immunization_schedule_id, remarks)
        SELECT v_child_id, v_vaccine_id, DATE '2026-09-03', v_midwife_id,
               v_midwife_id, 1, 'administered', 'this_bhc', v_bhc_id,
               v_schedule_id, 'Synthetic demo drive dose; no inventory deducted'
         WHERE NOT EXISTS (SELECT 1 FROM public.immunization_records
                            WHERE child_id = v_child_id AND vaccine_id = v_vaccine_id);
      END IF;

      -- Invitations let the admin reports show attendance and no-shows.
      FOR d IN SELECT * FROM ina_seed_drives WHERE facility_id = v_bhc_id LOOP
        -- A second dose requires the first. Child 4 is already complete;
        -- child 5 has not yet received MMR1. Everyone lacks Td1 initially.
        CONTINUE WHEN (d.drive_key = 'td2_sep' AND i = 5)
                   OR (d.drive_key = 'mmr1_sep' AND i = 4)
                   OR (d.drive_key = 'mmr2_oct' AND i >= 4)
                   OR (d.drive_key = 'penta_oct' AND i = 4);
        INSERT INTO public.drive_invitations
          (immunization_schedule_id, mother_id, child_id, child_name,
           phone_number, email_address, invited_at)
        VALUES (d.schedule_id, v_mother_id,
                CASE WHEN d.drive_key LIKE 'td%' THEN NULL ELSE v_child_id END,
                CASE WHEN d.drive_key LIKE 'td%' THEN NULL ELSE v_child_name || ' Demo' END,
                v_phone, v_email,
                CASE d.drive_key
                  WHEN 'td1_aug'   THEN TIMESTAMPTZ '2026-08-05 09:00+08'
                  WHEN 'mmr1_sep'  THEN TIMESTAMPTZ '2026-08-27 09:00+08'
                  WHEN 'td2_sep'   THEN TIMESTAMPTZ '2026-09-09 09:00+08'
                  ELSE TIMESTAMPTZ '2026-10-07 09:00+08'
                END)
        ON CONFLICT DO NOTHING;
      END LOOP;
    END LOOP;
  END LOOP;
END
$seed$;

COMMIT;

-- Verify: each of the 22 BHCs should show 1 seeded midwife, 5 seeded mothers,
-- 5 seeded children and 5 seeded drives. RHU totals: 20 / 45 / 25 / 20 mothers.
SELECT r.facility_code AS rhu, b.barangay,
       (SELECT count(*) FROM public.midwives mw JOIN public.accounts a USING (account_id)
         WHERE mw.assigned_bhc_id = b.facility_id
           AND a.email_address LIKE '%@seed.inaagapay.test') AS midwives,
       (SELECT count(*) FROM public.mothers m JOIN public.accounts a USING (account_id)
         WHERE m.assigned_bhc_id = b.facility_id
           AND a.email_address LIKE '%@seed.inaagapay.test') AS mothers,
       (SELECT count(*) FROM public.children c JOIN public.mothers m USING (mother_id)
          JOIN public.accounts a ON a.account_id = m.account_id
         WHERE c.assigned_bhc_id = b.facility_id
           AND a.email_address LIKE '%@seed.inaagapay.test') AS children,
       (SELECT count(*) FROM public.immunization_schedule s
         WHERE s.facility_id = b.facility_id
           AND s.notes LIKE '[InaAgapay demo]%') AS drives
  FROM public.health_facilities b
  JOIN public.health_facilities r ON r.facility_id = b.parent_facility_id
 WHERE b.facility_type = 'BHC'
   AND b.barangay IN (SELECT barangay FROM (VALUES
     ('Bagong Nayon'),('Concepcion'),('Santo Cristo'),('Virgen delos Flores'),
     ('Barangca'),('Hinukay'),('Paitan'),('Piel'),('San Roque'),('Santo Niño'),
     ('Sulivan'),('Tangos'),('Tilapayong'),('Makinabang'),('San Jose'),
     ('Santa Barbara'),('Tarcan'),('Tiaong'),('Poblacion'),('Sabang'),
     ('Subic'),('Tibag')) AS x(barangay))
 ORDER BY r.facility_code, b.barangay;

SELECT a.email_address, a.status, a.is_temporary_password,
       hf.facility_code AS assigned_rhu, hf.name AS assigned_office
  FROM public.accounts a
  JOIN public.facility_assignments fa ON fa.account_id = a.account_id
    AND COALESCE(fa.is_active, true)
  JOIN public.health_facilities hf ON hf.facility_id = fa.facility_id
 WHERE a.email_address IN (
   'rhu1.baliwag@inaagapay.ph', 'rhu2.baliwag@inaagapay.ph',
   'rhu3.baliwag@inaagapay.ph', 'rhu4.baliwag@inaagapay.ph')
 ORDER BY hf.facility_code;
