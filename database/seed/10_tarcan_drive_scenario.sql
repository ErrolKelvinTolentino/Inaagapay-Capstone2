-- ==============================================================================
-- SEED: 10_tarcan_drive_scenario.sql
--
-- A year of vaccination drives at Tarcan BHC, with ten children and their
-- mothers to fill them, so the drive analytics on the Reports & Analytics page
-- has something real to report.
--
-- THE SCENARIO
--
--   Ten mothers are registered at Tarcan BHC (facility_id 2), each with one
--   infant born between March and April 2026. Every child is at least six weeks
--   old on the date of the first drive, so all ten are genuinely ELIGIBLE for
--   the vaccine that drive offers -- the invitation list is not a list of
--   children who should have been turned away.
--
--   Five drives are scheduled, four past and one still to come:
--
--                                  invited   of them came   turnout   doses
--     15 Jun 2026  Pentavalent 1        10             10      100%      10
--     13 Jul 2026  Pentavalent 2        10              8       80%       8
--     10 Aug 2026  PCV 1                 9              8     88.9%       9
--                                        (+1 walk-in, so 9 children in all)
--     24 Aug 2026  Td (mothers)         10              7       70%       7
--     14 Sep 2026  Pentavalent 3        10              -   upcoming       -
--
--   The dose intervals hold: Penta 1 to Penta 2 is 28 days, Penta 2 to Penta 3
--   is 63. The one child left off the PCV list turns up anyway, which is what
--   the walk-in column on the drive table is for -- a mother who hears about
--   the drive from a neighbour is a success, not a data error.
--
-- WHO ADMINISTERS
--
--   The existing Tarcan midwife account, midwife.tarcan@inaagapay.com. No new
--   account is created; this seed only plants records against the one already
--   there.
--
-- STOCK IS REALLY DEDUCTED
--
--   Each dose is put through public.deduct_immunization_stock() or
--   public.administer_maternal_td_dose() -- the same functions the midwife's
--   phone calls -- rather than being written straight into the table. So the
--   drive analytics and the inventory ledger agree: 34 doses given, 34 doses'
--   worth of stock gone, one Td vial opened with 3 doses left in it, and a
--   ledger row pointing back at each immunization record.
--
--   A dose that cannot be paid for raises and rolls the whole seed back. A
--   silent under-deduction would leave the two halves of the demo contradicting
--   each other, which is the exact thing this is meant to demonstrate working.
--
-- WHERE THE STOCK COMES FROM
--
--   Tarcan already holds 100 units of every vaccine from 03_allocations.sql,
--   which is far more than the 18 Pentavalent, 9 PCV and 1 Td vial this needs.
--   But those batches were received 20 days ago, and the June and July drives
--   predate them -- the ledger would show a June dose drawn from August stock.
--
--   So section 3 lays down a separate delivery received 01 Jun 2026, before the
--   first drive, with an earlier expiry than the general stock so that FEFO
--   picks it first. The 03_allocations.sql batches are left untouched, and
--   re-running that file will not disturb this one: it only refills batches
--   whose number begins MW- / RHU / BHC, and these begin DRIVE-.
--
-- THE TWO TIMESTAMPS THIS FILE CORRECTS
--
--   Both deduction functions hardcode NOW() for the ledger row and for
--   vial_opened_at, because they were written for a midwife recording a dose
--   she has just given. Left alone, 34 stock movements would be stamped today
--   while the immunization records they point at are dated June to August, and
--   the Td vial would read as opened today.
--
--   Section 7 moves both back to the day of the drive. Nothing else about what
--   the functions did is touched -- the batch selection, the open-vial maths
--   and the quantities are all theirs.
--
--   The audit_trail rows those movements raise are NOT backdated. They are
--   right as they stand: the audit trail records when a row was written, and
--   these rows really were written the day you ran this file.
--
--   One consequence worth knowing: the Td vial is backdated to 24 Aug 2026 and
--   an opened Td vial has a 28-day shelf life. Run this more than 28 days after
--   that date and the next Td dose given at Tarcan will correctly auto-discard
--   the 3 doses left in it, and say so in the ledger.
--
-- BEFORE YOU RUN THIS
--
--   1. database/migrations/20260817_drive_invitations.sql   (drive_invitations)
--   2. database/migrations/20260821_inventory_and_td_fixes.sql
--      (deduct_immunization_stock, administer_maternal_td_dose)
--   3. database/migrations/20260912_vaccination_drive_analytics.sql
--      (immunization_records.immunization_schedule_id, and the two views)
--   4. database/migrations/20260913_fix_audit_account_change_type_mismatch.sql
--      Without it the audit trigger raises 42804 on every account write and
--      section 2 cannot create a single mother.
--   5. database/seed/03_allocations.sql, or any other stock at Tarcan -- not
--      strictly required, since section 3 lays down its own delivery, but the
--      centre reading zero for every other item makes for a poor demo.
--
--   The guards below stop you if any of the first four is missing.
--
-- RUNNING TWICE IS SAFE. Accounts, mothers, children, drives, invitations and
-- doses are all matched on their natural keys and skipped when already present.
-- ==============================================================================

-- ---------------------------------------------------------------------------
-- 0. Preconditions
-- ---------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF to_regclass('public.drive_invitations') IS NULL THEN
    RAISE EXCEPTION
      'Run database/migrations/20260817_drive_invitations.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'immunization_records'
       AND column_name  = 'immunization_schedule_id'
  ) THEN
    RAISE EXCEPTION
      'Run database/migrations/20260912_vaccination_drive_analytics.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.health_facilities
     WHERE facility_id = 2 AND name ILIKE 'Tarcan%'
  ) THEN
    RAISE EXCEPTION
      'Tarcan BHC is not facility_id 2 on this database. Check health_facilities before running.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.accounts
     WHERE email_address = 'midwife.tarcan@inaagapay.com'
  ) THEN
    RAISE EXCEPTION
      'midwife.tarcan@inaagapay.com does not exist. Run database/seed_redesigned_accounts.sql first.';
  END IF;

  -- Section 6 hands every dose to these rather than writing the tables itself.
  IF to_regprocedure('public.deduct_immunization_stock(bigint)') IS NULL THEN
    RAISE EXCEPTION
      'public.deduct_immunization_stock is missing. Run database/migrations/20260821_inventory_and_td_fixes.sql first.';
  END IF;

  IF to_regprocedure(
       'public.administer_maternal_td_dose(bigint,text,date,bigint,bigint,text,text,text,text)'
     ) IS NULL THEN
    RAISE EXCEPTION
      'public.administer_maternal_td_dose is missing. Run database/migrations/20260821_inventory_and_td_fixes.sql first.';
  END IF;

  -- 20260826 shipped audit_account_change() with two text[] literals inside a
  -- jsonb CASE, so the trigger raises 42804 on EVERY account write. The ten
  -- mothers in section 2 are usually the first thing to hit it, and the error
  -- that comes back names a line number inside a trigger function -- almost
  -- impossible to connect to this file. Say it plainly instead.
  IF to_regprocedure('public.audit_account_change()') IS NOT NULL
     AND pg_get_functiondef('public.audit_account_change()'::regprocedure)
           LIKE '%''{}''::text[]%' THEN
    RAISE EXCEPTION
      'audit_account_change() still carries the 42804 type mismatch, so no account can be created. Run database/migrations/20260913_fix_audit_account_change_type_mismatch.sql first.';
  END IF;
END
$preflight$;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


BEGIN;

DO $seed$
DECLARE
  c_facility_id CONSTANT BIGINT := 2;              -- Tarcan BHC
  c_barangay    CONSTANT TEXT   := 'Tarcan';
  c_municipality CONSTANT TEXT  := 'Baliwag';
  c_province    CONSTANT TEXT   := 'Bulacan';

  -- Same password the rest of the demo roster uses, so these mothers can be
  -- signed into on the phone if the scenario needs to be shown from her side.
  c_password    CONSTANT TEXT   := 'Password@123';

  -- One row per family. Index i is used everywhere below to decide who came to
  -- which drive, so the order matters and must not be re-sorted.
  m_first  TEXT[] := ARRAY['Aurora','Bernadette','Corazon','Divina','Elena',
                           'Felicidad','Gliceria','Herminia','Imelda','Josefina'];
  m_last   TEXT[] := ARRAY['Bituin','Cuenca','Dalisay','Espiritu','Fajardo',
                           'Gatchalian','Halili','Ignacio','Jacinto','Katigbak'];
  m_born   DATE[] := ARRAY['1996-02-14','1999-07-03','1994-11-22','2001-01-30','1997-05-18',
                           '1993-09-09','2000-03-27','1998-12-06','1995-06-21','2002-04-11']::DATE[];
  m_phone  TEXT[] := ARRAY['09175550101','09175550102','09175550103','09175550104','09175550105',
                           '09175550106','09175550107','09175550108','09175550109','09175550110'];

  c_first  TEXT[] := ARRAY['Mateo','Sofia','Elias','Liana','Gabriel',
                           'Amihan','Rafael','Isabel','Noel','Maricel'];
  c_sex    TEXT[] := ARRAY['male','female','male','female','male',
                           'female','male','female','male','female'];
  -- Every one of these is at least six weeks before 2026-06-15, the first
  -- drive. That is what makes all ten eligible for the vaccine offered.
  c_born   DATE[] := ARRAY['2026-03-06','2026-03-11','2026-03-18','2026-03-24','2026-03-29',
                           '2026-04-02','2026-04-07','2026-04-12','2026-04-16','2026-04-20']::DATE[];
  c_weight NUMERIC[] := ARRAY[3.1,2.9,3.4,3.0,3.6,2.8,3.3,3.2,3.5,2.95];
  c_length NUMERIC[] := ARRAY[49.0,48.0,50.5,48.5,51.0,47.5,49.5,49.0,50.0,48.0];

  v_midwife_id   BIGINT;
  -- Her ACCOUNT id, not her midwife id. accounts.created_by records who created
  -- a login and, since 20260808_created_by_allows_account_ids.sql, its check
  -- constraint admits only NULL, 'self', 'midwife' or a run of digits -- so a
  -- marker like 'seed' would be rejected outright.
  v_midwife_account_id BIGINT;
  v_account_id   BIGINT;
  v_mother_id    BIGINT;
  v_child_id     BIGINT;
  v_email        TEXT;
  i              INT;

  -- The five drives, filled in as they are created.
  d_penta1 BIGINT; d_penta2 BIGINT; d_pcv1 BIGINT; d_td BIGINT; d_penta3 BIGINT;

  v_mother_ids BIGINT[] := ARRAY[]::BIGINT[];
  v_child_ids  BIGINT[] := ARRAY[]::BIGINT[];

  -- Which vaccine row each drive offers. Resolved by name and dose so the seed
  -- survives a re-seeded catalogue with different ids.
  v_vac_penta1 BIGINT; v_vac_penta2 BIGINT; v_vac_penta3 BIGINT;
  v_vac_pcv1   BIGINT; v_vac_td1    BIGINT;

  -- Which of the ten families turned up to each child drive. Held as index
  -- lists rather than counts because the PCV drive is not a prefix: family 9
  -- was invited and did not come, family 10 was not invited and did.
  a_penta1 INT[] := ARRAY[1,2,3,4,5,6,7,8,9,10];
  a_penta2 INT[] := ARRAY[1,2,3,4,5,6,7,8];
  a_pcv1   INT[] := ARRAY[1,2,3,4,5,6,7,8,10];

  -- The child drives, walked in date order in section 6 so the ledger reads in
  -- the order the stock was actually used.
  a_drive_id  BIGINT[];
  a_vaccine   BIGINT[];
  a_dose_no   INT[];
  a_date      DATE[];
  v_attendees INT[];
  j           INT;
  k           INT;

  v_record_id BIGINT;
  v_result    JSONB;

  -- Stock laid down for the drives. One delivery per item, received before the
  -- first drive. Sized generously: the point is that a drive never runs out
  -- mid-scenario, not that the arithmetic is tight.
  s_item     BIGINT[];
  s_units    INT[]  := ARRAY[30, 20, 5];   -- Pentavalent, PCV, Td (10-dose vials)
  v_batch_no TEXT;
  v_batch_id BIGINT;
BEGIN

  ---------------------------------------------------------------------------
  -- 1. Who administers, and what is being given
  ---------------------------------------------------------------------------
  SELECT mw.midwife_id, mw.account_id
    INTO v_midwife_id, v_midwife_account_id
    FROM public.midwives mw
    JOIN public.accounts a ON a.account_id = mw.account_id
   WHERE a.email_address = 'midwife.tarcan@inaagapay.com';

  IF v_midwife_id IS NULL THEN
    RAISE EXCEPTION
      'The Tarcan account exists but has no midwives row. Run database/seed_redesigned_accounts.sql.';
  END IF;

  SELECT vaccine_id INTO v_vac_penta1 FROM public.vaccines
   WHERE vaccine_name ILIKE 'Pentavalent%' AND dose_number = 1 LIMIT 1;
  SELECT vaccine_id INTO v_vac_penta2 FROM public.vaccines
   WHERE vaccine_name ILIKE 'Pentavalent%' AND dose_number = 2 LIMIT 1;
  SELECT vaccine_id INTO v_vac_penta3 FROM public.vaccines
   WHERE vaccine_name ILIKE 'Pentavalent%' AND dose_number = 3 LIMIT 1;
  SELECT vaccine_id INTO v_vac_pcv1   FROM public.vaccines
   WHERE vaccine_name ILIKE '%Pneumococcal%' AND dose_number = 1 LIMIT 1;
  SELECT vaccine_id INTO v_vac_td1    FROM public.vaccines
   WHERE target_recipients = 'mother' AND dose_number = 1 LIMIT 1;

  IF v_vac_penta1 IS NULL OR v_vac_penta2 IS NULL OR v_vac_penta3 IS NULL
     OR v_vac_pcv1 IS NULL OR v_vac_td1 IS NULL THEN
    RAISE EXCEPTION
      'The vaccine catalogue is missing Pentavalent 1-3, PCV 1 or Td 1. Run database/migrations/20260806_seed_doh_epi_vaccines.sql.';
  END IF;

  ---------------------------------------------------------------------------
  -- 2. Ten mothers and ten infants at Tarcan BHC
  ---------------------------------------------------------------------------
  FOR i IN 1..10 LOOP
    v_email := lower(m_first[i]) || '.' || lower(m_last[i]) || '.tarcan@inaagapay.internal';

    -- Account. Matched on e-mail, so a second run finds the same person rather
    -- than creating an eleventh.
    SELECT account_id INTO v_account_id
      FROM public.accounts WHERE email_address = v_email;

    IF v_account_id IS NULL THEN
      INSERT INTO public.accounts (
        email_address, password_hash, account_type, first_name, last_name,
        phone_number, is_verified, status, is_temporary_password, created_by
      ) VALUES (
        v_email, crypt(c_password, gen_salt('bf', 10)), 'mother',
        m_first[i], m_last[i], m_phone[i], true, 'active', false,
        v_midwife_account_id::TEXT
      )
      RETURNING account_id INTO v_account_id;
    END IF;

    -- Her record at the health centre.
    SELECT mother_id INTO v_mother_id
      FROM public.mothers WHERE account_id = v_account_id;

    IF v_mother_id IS NULL THEN
      INSERT INTO public.mothers (
        account_id, birthdate, barangay, city_municipality, province,
        status, gravida, para, living_children, philhealth_status,
        civil_status, assigned_bhc_id, registered_by_midwife_id
      ) VALUES (
        v_account_id, m_born[i], c_barangay, c_municipality, c_province,
        'active', 1, 1, 1, 'Member',
        'Married', c_facility_id, v_midwife_id
      )
      RETURNING mother_id INTO v_mother_id;
    END IF;

    -- Her chart at Tarcan. patient_number (INA-000) is filled in by
    -- trg_facility_assignments_patient_number.
    IF NOT EXISTS (
      SELECT 1 FROM public.facility_assignments
       WHERE account_id = v_account_id
         AND facility_id = c_facility_id
         AND COALESCE(is_active, true)
    ) THEN
      INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
      VALUES (v_account_id, c_facility_id, true);
    END IF;

    -- Her child. child_number (NAK-000) is filled in by
    -- trg_children_child_number from assigned_bhc_id.
    SELECT child_id INTO v_child_id
      FROM public.children
     WHERE mother_id = v_mother_id
       AND first_name = c_first[i]
       AND last_name  = m_last[i];

    IF v_child_id IS NULL THEN
      INSERT INTO public.children (
        mother_id, has_guardian_only, first_name, last_name, sex,
        assigned_bhc_id, registered_by_midwife_id
      ) VALUES (
        v_mother_id, false, c_first[i], m_last[i], c_sex[i],
        c_facility_id, v_midwife_id
      )
      RETURNING child_id INTO v_child_id;
    END IF;

    INSERT INTO public.birth_details (
      child_id, birthplace_facility, birthdate, birth_weight, birth_length,
      birthplace_city_municipality, birthplace_province, delivery_type, apgar_score
    ) VALUES (
      v_child_id, 'Tarcan BHC', c_born[i], c_weight[i], c_length[i],
      c_municipality, c_province, 'Normal Spontaneous Delivery', 9
    )
    ON CONFLICT (child_id) DO NOTHING;

    v_mother_ids := v_mother_ids || v_mother_id;
    v_child_ids  := v_child_ids  || v_child_id;
  END LOOP;

  ---------------------------------------------------------------------------
  -- 3. Stock for the drives
  --
  -- A delivery received 01 Jun 2026, two weeks before the first drive, so that
  -- every dose given below is drawn from stock that had actually arrived.
  --
  -- The expiry is deliberately EARLIER than the 03_allocations.sql batches at
  -- this centre. deduct_immunization_stock() picks FEFO -- earliest expiry
  -- first -- so this is the stock the drives consume, and the general shelf is
  -- left as it was. That is also the correct clinical behaviour: older stock
  -- goes first.
  --
  -- The receipt ledger row mirrors 03_allocations.sql. A receipt, not a
  -- transfer: inventing a dispatch would assert that somebody issued it and
  -- somebody confirmed it, which is the fabricated paperwork that file exists
  -- to avoid.
  ---------------------------------------------------------------------------
  SELECT ARRAY[
    (SELECT inventory_item_id FROM public.vaccines WHERE vaccine_id = v_vac_penta1),
    (SELECT inventory_item_id FROM public.vaccines WHERE vaccine_id = v_vac_pcv1),
    (SELECT inventory_item_id FROM public.vaccines WHERE vaccine_id = v_vac_td1)
  ] INTO s_item;

  IF s_item[1] IS NULL OR s_item[2] IS NULL OR s_item[3] IS NULL THEN
    RAISE EXCEPTION
      'Pentavalent, PCV or Td has no inventory_item_id. Run database/migrations/20260825_vaccine_catalogue_corrections.sql.';
  END IF;

  FOR j IN 1..3 LOOP
    v_batch_no := 'DRIVE-TARCAN-' || s_item[j];

    SELECT batch_id INTO v_batch_id
      FROM public.inventory_batches WHERE batch_number = v_batch_no;

    IF v_batch_id IS NULL THEN
      INSERT INTO public.inventory_batches (
        item_id, facility_id, batch_number, quantity_received, quantity_remaining,
        received_date, expiration_date, manufacturer, status
      ) VALUES (
        s_item[j], c_facility_id, v_batch_no, s_units[j], s_units[j],
        DATE '2026-06-01', DATE '2027-03-31',
        'Municipal Warehouse Allocation', 'active'
      )
      RETURNING batch_id INTO v_batch_id;

      INSERT INTO public.inventory_transactions (
        batch_id, facility_id, transaction_type, quantity,
        reference_type, notes, performed_by, resulting_quantity_remaining, logged_at
      ) VALUES (
        v_batch_id, c_facility_id, 'receipt', s_units[j],
        'Opening Stock',
        'Stock delivered to Tarcan BHC ahead of the barangay immunization drives.',
        v_midwife_account_id, s_units[j],
        TIMESTAMP '2026-06-01 09:00'
      );
    END IF;
  END LOOP;

  ---------------------------------------------------------------------------
  -- 4. The five drives
  --
  -- A drive is a row in immunization_schedule -- facility, vaccine, date -- and
  -- nothing more; that is what the Schedules screen and the drive service both
  -- already use. bhc_id is set alongside facility_id because both columns are
  -- present on this table and the mobile app reads the former.
  ---------------------------------------------------------------------------

  -- Pentavalent 1
  SELECT immunization_schedule_id INTO d_penta1 FROM public.immunization_schedule
   WHERE facility_id = c_facility_id AND vaccine_id = v_vac_penta1
     AND schedule_date = DATE '2026-06-15';
  IF d_penta1 IS NULL THEN
    INSERT INTO public.immunization_schedule (facility_id, bhc_id, vaccine_id, schedule_date, notes)
    VALUES (c_facility_id, c_facility_id, v_vac_penta1, DATE '2026-06-15',
            'Barangay Tarcan infant immunization drive - Pentavalent, first dose.')
    RETURNING immunization_schedule_id INTO d_penta1;
  END IF;

  -- Pentavalent 2
  SELECT immunization_schedule_id INTO d_penta2 FROM public.immunization_schedule
   WHERE facility_id = c_facility_id AND vaccine_id = v_vac_penta2
     AND schedule_date = DATE '2026-07-13';
  IF d_penta2 IS NULL THEN
    INSERT INTO public.immunization_schedule (facility_id, bhc_id, vaccine_id, schedule_date, notes)
    VALUES (c_facility_id, c_facility_id, v_vac_penta2, DATE '2026-07-13',
            'Pentavalent second dose, four weeks after the June drive.')
    RETURNING immunization_schedule_id INTO d_penta2;
  END IF;

  -- PCV 1
  SELECT immunization_schedule_id INTO d_pcv1 FROM public.immunization_schedule
   WHERE facility_id = c_facility_id AND vaccine_id = v_vac_pcv1
     AND schedule_date = DATE '2026-08-10';
  IF d_pcv1 IS NULL THEN
    INSERT INTO public.immunization_schedule (facility_id, bhc_id, vaccine_id, schedule_date, notes)
    VALUES (c_facility_id, c_facility_id, v_vac_pcv1, DATE '2026-08-10',
            'Pneumococcal drive. Until supplies last.')
    RETURNING immunization_schedule_id INTO d_pcv1;
  END IF;

  -- Td for mothers
  SELECT immunization_schedule_id INTO d_td FROM public.immunization_schedule
   WHERE facility_id = c_facility_id AND vaccine_id = v_vac_td1
     AND schedule_date = DATE '2026-08-24';
  IF d_td IS NULL THEN
    INSERT INTO public.immunization_schedule (facility_id, bhc_id, vaccine_id, schedule_date, notes)
    VALUES (c_facility_id, c_facility_id, v_vac_td1, DATE '2026-08-24',
            'Maternal tetanus-diphtheria drive for mothers with no dose on record.')
    RETURNING immunization_schedule_id INTO d_td;
  END IF;

  -- Pentavalent 3, still to come
  SELECT immunization_schedule_id INTO d_penta3 FROM public.immunization_schedule
   WHERE facility_id = c_facility_id AND vaccine_id = v_vac_penta3
     AND schedule_date = DATE '2026-09-14';
  IF d_penta3 IS NULL THEN
    INSERT INTO public.immunization_schedule (facility_id, bhc_id, vaccine_id, schedule_date, notes)
    VALUES (c_facility_id, c_facility_id, v_vac_penta3, DATE '2026-09-14',
            'Pentavalent third dose, completing the primary series.')
    RETURNING immunization_schedule_id INTO d_penta3;
  END IF;

  ---------------------------------------------------------------------------
  -- 5. Who was invited
  --
  -- The child drives invite the child (the appointment is theirs) with the
  -- mother's contacts, because hers is the number on file -- the same shape
  -- vaccination_drive_service.dart writes. The Td drive invites the mother
  -- herself, so child_id stays null.
  --
  -- reminded_at is stamped the day before each past drive, standing in for the
  -- daily reminder job having run.
  ---------------------------------------------------------------------------
  FOR i IN 1..10 LOOP
    v_email := lower(m_first[i]) || '.' || lower(m_last[i]) || '.tarcan@inaagapay.internal';

    -- Pentavalent 1 and 2, and the upcoming Pentavalent 3: all ten.
    INSERT INTO public.drive_invitations (
      immunization_schedule_id, mother_id, child_id, child_name,
      phone_number, email_address, invited_at, reminded_at
    )
    VALUES
      (d_penta1, v_mother_ids[i], v_child_ids[i], c_first[i] || ' ' || m_last[i],
       m_phone[i], v_email, TIMESTAMPTZ '2026-06-09 08:00+08', TIMESTAMPTZ '2026-06-14 08:00+08'),
      (d_penta2, v_mother_ids[i], v_child_ids[i], c_first[i] || ' ' || m_last[i],
       m_phone[i], v_email, TIMESTAMPTZ '2026-07-07 08:00+08', TIMESTAMPTZ '2026-07-12 08:00+08'),
      (d_penta3, v_mother_ids[i], v_child_ids[i], c_first[i] || ' ' || m_last[i],
       m_phone[i], v_email, TIMESTAMPTZ '2026-09-08 08:00+08', NULL)
    ON CONFLICT DO NOTHING;

    -- PCV: the tenth family was missed off the list. She turns up anyway in
    -- section 5, which is what makes the walk-in column non-zero.
    IF i <= 9 THEN
      INSERT INTO public.drive_invitations (
        immunization_schedule_id, mother_id, child_id, child_name,
        phone_number, email_address, invited_at, reminded_at
      ) VALUES (
        d_pcv1, v_mother_ids[i], v_child_ids[i], c_first[i] || ' ' || m_last[i],
        m_phone[i], v_email, TIMESTAMPTZ '2026-08-04 08:00+08', TIMESTAMPTZ '2026-08-09 08:00+08'
      )
      ON CONFLICT DO NOTHING;
    END IF;

    -- Td: the mother is the patient, so no child on the invitation.
    INSERT INTO public.drive_invitations (
      immunization_schedule_id, mother_id, child_id, child_name,
      phone_number, email_address, invited_at, reminded_at
    ) VALUES (
      d_td, v_mother_ids[i], NULL, NULL,
      m_phone[i], v_email, TIMESTAMPTZ '2026-08-18 08:00+08', TIMESTAMPTZ '2026-08-23 08:00+08'
    )
    ON CONFLICT DO NOTHING;
  END LOOP;

  ---------------------------------------------------------------------------
  -- 6. Who came, and what it cost the shelf
  --
  -- immunization_schedule_id is stamped on every dose, so attendance is a
  -- recorded fact here rather than the facility + date inference the analytics
  -- view falls back on for older data.
  --
  -- The record is written first and the dose is then put through
  -- deduct_immunization_stock(), which is the order the app uses -- the ledger
  -- row has to point back at a record that already exists. The function decides
  -- the batch, opens a vial when it must, writes the ledger and flips
  -- inventory_deducted; none of that is duplicated here.
  ---------------------------------------------------------------------------
  a_drive_id := ARRAY[d_penta1,   d_penta2,   d_pcv1];
  a_vaccine  := ARRAY[v_vac_penta1, v_vac_penta2, v_vac_pcv1];
  a_dose_no  := ARRAY[1, 2, 1];
  a_date     := ARRAY[DATE '2026-06-15', DATE '2026-07-13', DATE '2026-08-10'];

  FOR j IN 1..3 LOOP
    v_attendees := CASE j WHEN 1 THEN a_penta1 WHEN 2 THEN a_penta2 ELSE a_pcv1 END;

    FOREACH k IN ARRAY v_attendees LOOP
      SELECT immunization_record_id INTO v_record_id
        FROM public.immunization_records
       WHERE child_id         = v_child_ids[k]
         AND vaccine_id       = a_vaccine[j]
         AND vaccination_date = a_date[j];

      IF v_record_id IS NULL THEN
        INSERT INTO public.immunization_records (
          child_id, vaccine_id, vaccination_date, administered_by, recorded_by,
          dose_number, status, source, administration_place, facility_id,
          immunization_schedule_id, remarks
        ) VALUES (
          v_child_ids[k], a_vaccine[j], a_date[j], v_midwife_id, v_midwife_id,
          a_dose_no[j], 'administered', 'this_bhc', 'local_facility', c_facility_id,
          a_drive_id[j],
          CASE WHEN j = 3 AND k = 10
               THEN 'Walked in on the day of the drive; not on the invitation list.'
               ELSE 'Given at the Tarcan barangay immunization drive.' END
        )
        RETURNING immunization_record_id INTO v_record_id;
      END IF;

      -- Returns mode 'already_deducted' on a second run, so this is safe to
      -- repeat. A failure is fatal: a drive whose doses were never paid for is
      -- exactly the inconsistency this seed exists to avoid.
      v_result := public.deduct_immunization_stock(v_record_id);
      IF NOT COALESCE((v_result->>'success')::BOOLEAN, false) THEN
        RAISE EXCEPTION 'Could not deduct stock for immunization record % (child %, % on %): %',
          v_record_id, v_child_ids[k], a_vaccine[j], a_date[j], v_result->>'error';
      END IF;
    END LOOP;
  END LOOP;

  -- Td -- seven of the ten mothers.
  --
  -- administer_maternal_td_dose() writes the record and deducts in one call,
  -- and works out protection_until and next_due_date from the DOH schedule
  -- rather than having them hardcoded here. It does not know about drives, so
  -- the drive is stamped on afterwards.
  FOR i IN 1..7 LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.maternal_td_records
       WHERE mother_id = v_mother_ids[i] AND dose_number = 'Td1'
    ) THEN
      v_result := public.administer_maternal_td_dose(
        v_mother_ids[i], 'Td1', DATE '2026-08-24', c_facility_id, v_midwife_id,
        'bhc', NULL, 'Given at the Tarcan maternal Td drive.', NULL
      );

      IF NOT COALESCE((v_result->>'success')::BOOLEAN, false) THEN
        RAISE EXCEPTION 'Could not record the Td dose for mother %: %',
          v_mother_ids[i], v_result->>'error';
      END IF;

      -- success alone is not enough here. Unlike deduct_immunization_stock(),
      -- this function reports success as soon as the CLINICAL record is
      -- written, and falls back to mode 'no_deduction' with a null batch when
      -- there is no Td vial to draw from -- the dose is recorded, the shelf is
      -- untouched, and nothing says so. Checking the batch is what turns that
      -- into a failed seed rather than a demo that quietly disagrees with its
      -- own inventory.
      IF v_result->>'batch_id' IS NULL THEN
        RAISE EXCEPTION
          'Td dose for mother % was recorded but drew no stock (mode %). Tarcan has no usable Td vial.',
          v_mother_ids[i], v_result->>'mode';
      END IF;

      UPDATE public.maternal_td_records
         SET immunization_schedule_id = d_td
       WHERE td_record_id = (v_result->>'record_id')::BIGINT;
    END IF;
  END LOOP;

  -- Any Td row that predates this run, or whose record_id the function did not
  -- return, still belongs to the drive if it was given that day at this centre.
  UPDATE public.maternal_td_records
     SET immunization_schedule_id = d_td
   WHERE facility_id      = c_facility_id
     AND vaccination_date = DATE '2026-08-24'
     AND immunization_schedule_id IS NULL;

  ---------------------------------------------------------------------------
  -- 7. Move the stock movements back to the day they happened
  --
  -- Both deduction functions stamp logged_at and vial_opened_at with NOW(),
  -- because they were written for a midwife recording a dose she has just
  -- given. See the header: left alone, every one of these movements would be
  -- dated today while the record it points at is dated June to August.
  --
  -- Only the timestamp is touched. Quantities, batch choice and the open-vial
  -- arithmetic are the functions' and stay exactly as they left them.
  ---------------------------------------------------------------------------
  UPDATE public.inventory_transactions t
     SET logged_at = ir.vaccination_date::timestamp + TIME '09:30'
    FROM public.immunization_records ir
   WHERE t.reference_type = 'Child Immunization'
     AND t.reference_id   = ir.immunization_record_id
     AND ir.immunization_schedule_id IN (d_penta1, d_penta2, d_pcv1)
     AND t.logged_at::date IS DISTINCT FROM ir.vaccination_date;

  UPDATE public.inventory_transactions t
     SET logged_at = td.vaccination_date::timestamp + TIME '09:30'
    FROM public.maternal_td_records td
   WHERE t.reference_type = 'Maternal Td Immunization'
     AND t.reference_id   = td.td_record_id
     AND td.immunization_schedule_id = d_td
     AND t.logged_at::date IS DISTINCT FROM td.vaccination_date;

  -- The Td vial was opened at the drive, not today. Backdating it is what makes
  -- the 28-day open-vial clock run from the right moment -- see the note in the
  -- header about what happens once that window closes.
  UPDATE public.inventory_batches b
     SET vial_opened_at = TIMESTAMP '2026-08-24 09:30'
   WHERE b.vial_opened_at IS NOT NULL
     AND b.vial_opened_at::date IS DISTINCT FROM DATE '2026-08-24'
     AND b.batch_id IN (
       SELECT DISTINCT td.inventory_batch_id
         FROM public.maternal_td_records td
        WHERE td.immunization_schedule_id = d_td
          AND td.inventory_batch_id IS NOT NULL
     );

  RAISE NOTICE 'Tarcan drive scenario seeded. Drives: Penta1=%, Penta2=%, PCV1=%, Td=%, Penta3=%',
    d_penta1, d_penta2, d_pcv1, d_td, d_penta3;
END
$seed$;

COMMIT;


-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- SELECT drive_id, schedule_date, vaccine_name, audience, drive_status,
--        invited_count, attended_count, invited_attended, walk_in_count,
--        no_show_count, turnout_rate, doses_administered
--   FROM public.vaccination_drive_analytics
--  WHERE facility_id = 2
--  ORDER BY schedule_date;
--
-- Expect, in order: 10/10/100.0, 10/8/80.0, 9/9 with 8 invited-attended and
-- 1 walk-in (88.9), 10/7/70.0, and the September row with 10 invited and
-- drive_status = 'upcoming'.
--
-- The stock the drives consumed. Pentavalent and PCV are single-dose units, so
-- 18 and 9 units leave the shelf outright; Td is a 10-dose vial, so one vial is
-- opened for 7 doses and 3 stay in it.
--
-- SELECT b.batch_number, i.name, i.doses_per_unit,
--        b.quantity_received, b.quantity_remaining,
--        b.doses_remaining_in_open_vial, b.vial_opened_at, b.status
--   FROM public.inventory_batches b
--   JOIN public.inventory_items i ON i.item_id = b.item_id
--  WHERE b.batch_number LIKE 'DRIVE-TARCAN-%'
--  ORDER BY i.name;
--
-- Expect  Pentavalent 30 -> 12,  PCV 20 -> 11,  Td 5 -> 4 with 3 doses left in
-- an open vial dated 2026-08-24.
--
-- Every dose must carry a ledger row dated the day of the drive, not today:
--
-- SELECT t.logged_at::date AS moved_on, i.name, t.transaction_type,
--        COUNT(*) AS rows, SUM(t.quantity) AS units
--   FROM public.inventory_transactions t
--   JOIN public.inventory_batches b ON b.batch_id = t.batch_id
--   JOIN public.inventory_items   i ON i.item_id  = b.item_id
--  WHERE b.batch_number LIKE 'DRIVE-TARCAN-%'
--  GROUP BY 1, 2, 3 ORDER BY 1;
--
-- Expect receipts on 2026-06-01 and dispenses on 06-15, 07-13, 08-10 and 08-24.
-- Any row dated today means section 7 did not match -- most likely because a
-- different version of deduct_immunization_stock is installed and writes a
-- reference_type other than 'Child Immunization'.
--
-- Nothing should still be claiming a dose it never paid for:
--
-- SELECT COUNT(*) AS undeducted
--   FROM public.immunization_records
--  WHERE immunization_schedule_id IS NOT NULL
--    AND facility_id = 2
--    AND COALESCE(inventory_deducted, false) = false;
--
-- Expect 0.


-- ============================================================
-- REMOVING THE SCENARIO
--
-- Only ever run this on a demo database.
--
-- Deleting the families removes their immunization records by cascade, but it
-- does NOT put the stock back. The movement ledger is the audit trail for
-- inventory and this file never edits history that has already been written --
-- the same rule 00_reset_inventory.sql observes. Drop the DRIVE-TARCAN- batches
-- as well (statement 3) and the drawn-down stock goes with them; the dispense
-- rows against those batches go too, by cascade from inventory_batches.
--
-- Statement 1 alone is enough to re-run the seed from scratch: section 3 finds
-- its batches still there and reuses them, and the drives are re-created empty.
--
-- Run them in this order. maternal_td_records.inventory_batch_id has no ON
-- DELETE clause, so a Td record still pointing at a batch blocks statement 3
-- outright; statement 1 clears those records first, by cascade from the mother.
-- ============================================================
-- -- 1. The ten families, their children and every dose recorded against them
-- DELETE FROM public.accounts
--  WHERE email_address LIKE '%.tarcan@inaagapay.internal';
--
-- -- 2. The five drives, and their invitations by cascade
-- DELETE FROM public.immunization_schedule
--  WHERE facility_id = 2
--    AND schedule_date IN (DATE '2026-06-15', DATE '2026-07-13',
--                          DATE '2026-08-10', DATE '2026-08-24',
--                          DATE '2026-09-14');
--
-- -- 3. The stock laid down for them, and its ledger
-- DELETE FROM public.inventory_batches
--  WHERE batch_number LIKE 'DRIVE-TARCAN-%';
