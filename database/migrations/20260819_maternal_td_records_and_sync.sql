-- ==============================================================================
-- MIGRATION: 20260819_maternal_td_records_and_sync.sql
-- Dedicated Maternal Td (Tetanus-Diphtheria) Immunization System
-- Supports lifetime 5-dose tracking, historical backfills, DOH minimum intervals,
-- FEFO open-vial inventory deduction, and protection status calculations.
-- ==============================================================================

-- 0. Ensure inventory_transactions has notes column if not already present
ALTER TABLE public.inventory_transactions ADD COLUMN IF NOT EXISTS notes TEXT;

-- 1. Create maternal_td_records table
CREATE TABLE IF NOT EXISTS public.maternal_td_records (
  td_record_id BIGSERIAL PRIMARY KEY,
  mother_id BIGINT NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
  dose_number TEXT NOT NULL CHECK (dose_number IN ('Td1', 'Td2', 'Td3', 'Td4', 'Td5')),
  vaccination_date DATE NOT NULL,
  facility_id BIGINT REFERENCES public.health_facilities(facility_id),
  facility_name TEXT,
  source TEXT NOT NULL DEFAULT 'bhc' CHECK (source IN ('bhc', 'outside', 'historical_record')),
  administered_by BIGINT REFERENCES public.midwives(midwife_id),
  inventory_batch_id BIGINT REFERENCES public.inventory_batches(batch_id),
  inventory_deducted BOOLEAN NOT NULL DEFAULT false,
  next_due_date DATE,
  protection_until DATE,
  remarks TEXT,
  evidence TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_mother_td_dose UNIQUE(mother_id, dose_number)
);

CREATE INDEX IF NOT EXISTS idx_maternal_td_mother ON public.maternal_td_records(mother_id);
CREATE INDEX IF NOT EXISTS idx_maternal_td_date ON public.maternal_td_records(vaccination_date);

-- Enable Row Level Security (RLS)
ALTER TABLE public.maternal_td_records ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'maternal_td_records' AND policyname = 'Allow authenticated read maternal_td_records'
  ) THEN
    CREATE POLICY "Allow authenticated read maternal_td_records"
      ON public.maternal_td_records FOR SELECT TO authenticated USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'maternal_td_records' AND policyname = 'Allow authenticated write maternal_td_records'
  ) THEN
    CREATE POLICY "Allow authenticated write maternal_td_records"
      ON public.maternal_td_records FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 2. Backfill existing Td doses from prenatal_checkups into maternal_td_records if any exist
DO $$
DECLARE
  v_rec RECORD;
  v_prot DATE;
  v_next DATE;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'prenatal_checkups') THEN
    FOR v_rec IN
      SELECT 
        ce.mother_id,
        pc.td_vaccine_dose,
        COALESCE(ce.encounter_datetime::DATE, ce.created_at::DATE, CURRENT_DATE) AS v_date,
        ce.facility_id,
        ce.recorded_by
      FROM public.prenatal_checkups pc
      JOIN public.clinical_encounters ce ON ce.encounter_id = pc.encounter_id
      WHERE pc.td_vaccine_dose IS NOT NULL 
        AND pc.td_vaccine_dose IN ('Td1', 'Td2', 'Td3', 'Td4', 'Td5')
      ORDER BY ce.created_at ASC
    LOOP
      IF v_rec.td_vaccine_dose = 'Td1' THEN
        v_prot := NULL;
        v_next := v_rec.v_date + INTERVAL '28 days';
      ELSIF v_rec.td_vaccine_dose = 'Td2' THEN
        v_prot := v_rec.v_date + INTERVAL '3 years';
        v_next := v_rec.v_date + INTERVAL '180 days';
      ELSIF v_rec.td_vaccine_dose = 'Td3' THEN
        v_prot := v_rec.v_date + INTERVAL '5 years';
        v_next := v_rec.v_date + INTERVAL '365 days';
      ELSIF v_rec.td_vaccine_dose = 'Td4' THEN
        v_prot := v_rec.v_date + INTERVAL '10 years';
        v_next := v_rec.v_date + INTERVAL '365 days';
      ELSIF v_rec.td_vaccine_dose = 'Td5' THEN
        v_prot := v_rec.v_date + INTERVAL '50 years';
        v_next := NULL;
      END IF;

      INSERT INTO public.maternal_td_records (
        mother_id,
        dose_number,
        vaccination_date,
        facility_id,
        source,
        administered_by,
        inventory_deducted,
        protection_until,
        next_due_date,
        remarks
      ) VALUES (
        v_rec.mother_id,
        v_rec.td_vaccine_dose,
        v_rec.v_date,
        v_rec.facility_id,
        'bhc',
        v_rec.recorded_by,
        true,
        v_prot,
        v_next,
        'Migrated from prenatal checkup encounter'
      )
      ON CONFLICT (mother_id, dose_number) DO UPDATE
      SET vaccination_date = EXCLUDED.vaccination_date,
          protection_until = EXCLUDED.protection_until,
          next_due_date = EXCLUDED.next_due_date;
    END LOOP;
  END IF;
END $$;

-- 3. RPC: ADMINISTER MATERNAL TD DOSE
-- Enforces DOH intervals, performs FEFO open-vial inventory deduction, computes protection.
CREATE OR REPLACE FUNCTION public.administer_maternal_td_dose(
  p_mother_id BIGINT,
  p_dose_number TEXT,
  p_vaccination_date DATE,
  p_facility_id BIGINT,
  p_administered_by BIGINT,
  p_source TEXT DEFAULT 'bhc',
  p_facility_name TEXT DEFAULT NULL,
  p_remarks TEXT DEFAULT NULL,
  p_evidence TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item_id BIGINT;
  v_doses_per_unit INTEGER := 10;
  v_shelf_hours INTEGER := 672; -- 28 days DOH standard for opened Td vial
  v_batch RECORD;
  v_batch_id BIGINT;
  v_batch_number TEXT;
  v_doses_left INTEGER;
  v_hours_open NUMERIC;
  v_protection_until DATE;
  v_next_due DATE;
  v_prev_dose RECORD;
  v_days_since_prev INTEGER;
  v_min_interval_days INTEGER := 0;
  v_record_id BIGINT;
  v_mode TEXT := 'no_deduction';
  v_account_id BIGINT;
BEGIN
  -- 1. Validate Dose Sequence & Minimum Intervals
  IF p_dose_number = 'Td1' THEN
    v_protection_until := NULL;
    v_next_due := p_vaccination_date + INTERVAL '28 days';
  ELSIF p_dose_number = 'Td2' THEN
    v_min_interval_days := 28; -- 4 weeks
    v_protection_until := p_vaccination_date + INTERVAL '3 years';
    v_next_due := p_vaccination_date + INTERVAL '180 days';
  ELSIF p_dose_number = 'Td3' THEN
    v_min_interval_days := 180; -- 6 months
    v_protection_until := p_vaccination_date + INTERVAL '5 years';
    v_next_due := p_vaccination_date + INTERVAL '365 days';
  ELSIF p_dose_number = 'Td4' THEN
    v_min_interval_days := 365; -- 1 year
    v_protection_until := p_vaccination_date + INTERVAL '10 years';
    v_next_due := p_vaccination_date + INTERVAL '365 days';
  ELSIF p_dose_number = 'Td5' THEN
    v_min_interval_days := 365; -- 1 year
    v_protection_until := p_vaccination_date + INTERVAL '50 years';
    v_next_due := NULL; -- Lifetime protection achieved
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Invalid dose number: ' || p_dose_number);
  END IF;

  -- Check previous dose if applicable
  IF p_dose_number IN ('Td2', 'Td3', 'Td4', 'Td5') THEN
    SELECT vaccination_date INTO v_prev_dose
    FROM public.maternal_td_records
    WHERE mother_id = p_mother_id
      AND dose_number = CASE 
        WHEN p_dose_number = 'Td2' THEN 'Td1'
        WHEN p_dose_number = 'Td3' THEN 'Td2'
        WHEN p_dose_number = 'Td4' THEN 'Td3'
        WHEN p_dose_number = 'Td5' THEN 'Td4'
      END;

    IF v_prev_dose.vaccination_date IS NOT NULL THEN
      v_days_since_prev := p_vaccination_date - v_prev_dose.vaccination_date;
      IF v_days_since_prev < v_min_interval_days THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'DOH interval requirement not met: ' || p_dose_number || ' requires at least ' || v_min_interval_days || ' days after previous dose (' || v_days_since_prev || ' days elapsed).'
        );
      END IF;
    END IF;
  END IF;

  -- Resolve account_id from midwife_id if available for inventory transactions
  IF p_administered_by IS NOT NULL THEN
    SELECT account_id INTO v_account_id FROM public.midwives WHERE midwife_id = p_administered_by;
  END IF;

  -- 2. If administered at BHC, perform inventory deduction
  IF p_source = 'bhc' AND p_facility_id IS NOT NULL THEN
    SELECT item_id, COALESCE(doses_per_unit, 10), COALESCE(open_vial_shelf_hours, 672)
    INTO v_item_id, v_doses_per_unit, v_shelf_hours
    FROM public.inventory_items
    WHERE is_archived = false
      AND (name ILIKE '%td%' OR name ILIKE '%tetanus%' OR generic_name ILIKE '%tetanus%')
    LIMIT 1;

    IF v_item_id IS NOT NULL THEN
      -- Step A: Check for existing usable open vial
      FOR v_batch IN
        SELECT
          batch_id,
          batch_number,
          COALESCE(doses_remaining_in_open_vial, 0) AS doses_remaining_in_open_vial,
          COALESCE(open_vials_count, 0) AS open_vials_count,
          vial_opened_at,
          quantity_remaining,
          expiration_date
        FROM public.inventory_batches
        WHERE item_id = v_item_id
          AND facility_id = p_facility_id
          AND status = 'active'
          AND expiration_date >= CURRENT_DATE
          AND COALESCE(doses_remaining_in_open_vial, 0) > 0
        ORDER BY expiration_date ASC, batch_id ASC
        FOR UPDATE
      LOOP
        -- Check open-vial shelf life (28 days = 672 hours)
        IF v_batch.vial_opened_at IS NOT NULL AND v_shelf_hours > 0 THEN
          v_hours_open := EXTRACT(EPOCH FROM (NOW() - v_batch.vial_opened_at)) / 3600;
          IF v_hours_open > v_shelf_hours THEN
            -- Auto-discard expired open vial
            UPDATE public.inventory_batches
            SET doses_remaining_in_open_vial = 0,
                open_vials_count = GREATEST(0, COALESCE(open_vials_count, 1) - 1),
                vial_opened_at = NULL,
                status = CASE WHEN quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
            WHERE batch_id = v_batch.batch_id;

            INSERT INTO public.inventory_transactions (
              batch_id, facility_id, transaction_type, quantity, reference_type, notes, performed_by, logged_at
            ) VALUES (
              v_batch.batch_id, p_facility_id, 'expiry_disposal', 0, 'open_vial_expired',
              'Auto-discarded ' || v_batch.doses_remaining_in_open_vial || ' expired Td open doses (> ' || v_shelf_hours || 'h limit)',
              v_account_id, NOW()
            );

            CONTINUE;
          END IF;
        END IF;

        -- Valid open vial found! Deduct 1 dose
        v_doses_left := v_batch.doses_remaining_in_open_vial - 1;
        v_batch_id := v_batch.batch_id;
        v_batch_number := v_batch.batch_number;
        v_mode := 'open_vial_dose';

        UPDATE public.inventory_batches
        SET doses_remaining_in_open_vial = v_doses_left,
            open_vials_count = CASE WHEN v_doses_left <= 0 THEN GREATEST(0, COALESCE(open_vials_count, 1) - 1) ELSE COALESCE(open_vials_count, 1) END,
            vial_opened_at = CASE WHEN v_doses_left <= 0 THEN NULL ELSE COALESCE(v_batch.vial_opened_at, NOW()) END,
            status = CASE WHEN v_doses_left <= 0 AND quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
        WHERE batch_id = v_batch.batch_id;

        INSERT INTO public.inventory_transactions (
          batch_id, facility_id, transaction_type, quantity, reference_type, notes, performed_by, logged_at
        ) VALUES (
          v_batch.batch_id, p_facility_id, 'dispense', 0, 'maternal_td',
          'Maternal ' || p_dose_number || ' from Open Vial (' || v_doses_left || ' doses left, Batch #' || v_batch.batch_number || ')',
          v_account_id, NOW()
        );

        EXIT;
      END LOOP;

      -- Step B: If no open vial was used, open a new sealed vial
      IF v_batch_id IS NULL THEN
        SELECT
          batch_id,
          batch_number,
          quantity_remaining,
          COALESCE(doses_remaining_in_open_vial, 0) AS doses_remaining_in_open_vial,
          COALESCE(open_vials_count, 0) AS open_vials_count
        INTO v_batch
        FROM public.inventory_batches
        WHERE item_id = v_item_id
          AND facility_id = p_facility_id
          AND status = 'active'
          AND expiration_date >= CURRENT_DATE
          AND quantity_remaining > 0
        ORDER BY expiration_date ASC, batch_id ASC
        LIMIT 1
        FOR UPDATE;

        IF v_batch.batch_id IS NOT NULL THEN
          v_doses_left := v_doses_per_unit - 1;
          v_batch_id := v_batch.batch_id;
          v_batch_number := v_batch.batch_number;
          v_mode := 'new_vial_opened';

          UPDATE public.inventory_batches
          SET quantity_remaining = quantity_remaining - 1,
              open_vials_count = COALESCE(open_vials_count, 0) + 1,
              doses_remaining_in_open_vial = COALESCE(doses_remaining_in_open_vial, 0) + v_doses_left,
              vial_opened_at = NOW(),
              status = CASE WHEN (quantity_remaining - 1) <= 0 AND v_doses_left <= 0 THEN 'depleted' ELSE 'active' END
          WHERE batch_id = v_batch.batch_id;

          INSERT INTO public.inventory_transactions (
            batch_id, facility_id, transaction_type, quantity, reference_type, notes, performed_by, logged_at
          ) VALUES (
            v_batch.batch_id, p_facility_id, 'dispense', -1, 'maternal_td',
            'Opened ' || v_doses_per_unit || '-dose Td vial for ' || p_dose_number || ' (' || v_doses_left || ' doses left in open vial, Batch #' || v_batch.batch_number || ')',
            v_account_id, NOW()
          );
        END IF;
      END IF;
    END IF;
  END IF;

  -- 3. Upsert record into maternal_td_records
  INSERT INTO public.maternal_td_records (
    mother_id,
    dose_number,
    vaccination_date,
    facility_id,
    facility_name,
    source,
    administered_by,
    inventory_batch_id,
    inventory_deducted,
    protection_until,
    next_due_date,
    remarks,
    evidence
  ) VALUES (
    p_mother_id,
    p_dose_number,
    p_vaccination_date,
    p_facility_id,
    p_facility_name,
    p_source,
    p_administered_by,
    v_batch_id,
    (v_batch_id IS NOT NULL),
    v_protection_until,
    v_next_due,
    p_remarks,
    p_evidence
  )
  ON CONFLICT (mother_id, dose_number) DO UPDATE
  SET vaccination_date = EXCLUDED.vaccination_date,
      facility_id = EXCLUDED.facility_id,
      facility_name = EXCLUDED.facility_name,
      source = EXCLUDED.source,
      administered_by = EXCLUDED.administered_by,
      inventory_batch_id = COALESCE(EXCLUDED.inventory_batch_id, maternal_td_records.inventory_batch_id),
      inventory_deducted = COALESCE(EXCLUDED.inventory_deducted, maternal_td_records.inventory_deducted),
      protection_until = EXCLUDED.protection_until,
      next_due_date = EXCLUDED.next_due_date,
      remarks = EXCLUDED.remarks,
      evidence = EXCLUDED.evidence
  RETURNING td_record_id INTO v_record_id;

  RETURN jsonb_build_object(
    'success', true,
    'record_id', v_record_id,
    'mode', v_mode,
    'batch_id', v_batch_id,
    'batch_number', v_batch_number,
    'doses_left_in_vial', COALESCE(v_doses_left, 0),
    'protection_until', v_protection_until,
    'next_due_date', v_next_due,
    'is_pab', (p_dose_number IN ('Td2', 'Td3', 'Td4', 'Td5') AND (v_protection_until IS NULL OR v_protection_until >= CURRENT_DATE)),
    'is_fim', (p_dose_number = 'Td5')
  );
END;
$$;

-- 4. RPC: BACKFILL MATERNAL TD HISTORY (FROM PAPER CARDS / PAST PREGNANCIES)
CREATE OR REPLACE FUNCTION public.backfill_maternal_td_history(
  p_mother_id BIGINT,
  p_records JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_elem JSONB;
  v_dose TEXT;
  v_date DATE;
  v_fac_name TEXT;
  v_remarks TEXT;
  v_prot DATE;
  v_next DATE;
  v_inserted_count INTEGER := 0;
  v_prev_date DATE;
  v_min_int INTEGER;
  v_arr JSONB;
BEGIN
  IF jsonb_typeof(p_records) = 'array' THEN
    v_arr := p_records;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Invalid records format: Expected JSON array');
  END IF;

  FOR v_elem IN SELECT * FROM jsonb_array_elements(v_arr)
  LOOP
    v_dose := v_elem->>'dose_number';
    v_date := (v_elem->>'vaccination_date')::DATE;
    v_fac_name := v_elem->>'facility_name';
    v_remarks := v_elem->>'remarks';

    IF v_dose IS NULL OR v_date IS NULL THEN
      CONTINUE;
    END IF;

    -- Interval and sequence check against existing earlier doses in DB
    IF v_dose IN ('Td2', 'Td3', 'Td4', 'Td5') THEN
      SELECT vaccination_date INTO v_prev_date
      FROM public.maternal_td_records
      WHERE mother_id = p_mother_id
        AND dose_number = CASE 
          WHEN v_dose = 'Td2' THEN 'Td1'
          WHEN v_dose = 'Td3' THEN 'Td2'
          WHEN v_dose = 'Td4' THEN 'Td3'
          WHEN v_dose = 'Td5' THEN 'Td4'
        END;

      IF v_prev_date IS NOT NULL THEN
        v_min_int := CASE 
          WHEN v_dose = 'Td2' THEN 28
          WHEN v_dose = 'Td3' THEN 180
          ELSE 365
        END;

        IF (v_date - v_prev_date) < v_min_int THEN
          RETURN jsonb_build_object(
            'success', false,
            'error', 'DOH Interval Violation: ' || v_dose || ' (' || v_date || ') must be at least ' || v_min_int || ' days after previous dose (' || v_prev_date || ').'
          );
        END IF;
      END IF;
    END IF;

    IF v_dose = 'Td1' THEN
      v_prot := NULL;
      v_next := v_date + INTERVAL '28 days';
    ELSIF v_dose = 'Td2' THEN
      v_prot := v_date + INTERVAL '3 years';
      v_next := v_date + INTERVAL '180 days';
    ELSIF v_dose = 'Td3' THEN
      v_prot := v_date + INTERVAL '5 years';
      v_next := v_date + INTERVAL '365 days';
    ELSIF v_dose = 'Td4' THEN
      v_prot := v_date + INTERVAL '10 years';
      v_next := v_date + INTERVAL '365 days';
    ELSIF v_dose = 'Td5' THEN
      v_prot := v_date + INTERVAL '50 years';
      v_next := NULL;
    END IF;

    INSERT INTO public.maternal_td_records (
      mother_id,
      dose_number,
      vaccination_date,
      facility_name,
      source,
      inventory_deducted,
      protection_until,
      next_due_date,
      remarks
    ) VALUES (
      p_mother_id,
      v_dose,
      v_date,
      v_fac_name,
      'historical_record',
      false,
      v_prot,
      v_next,
      v_remarks
    )
    ON CONFLICT (mother_id, dose_number) DO UPDATE
    SET vaccination_date = EXCLUDED.vaccination_date,
        facility_name = EXCLUDED.facility_name,
        protection_until = EXCLUDED.protection_until,
        next_due_date = EXCLUDED.next_due_date,
        remarks = EXCLUDED.remarks;

    v_inserted_count := v_inserted_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'saved_count', v_inserted_count
  );
END;
$$;
