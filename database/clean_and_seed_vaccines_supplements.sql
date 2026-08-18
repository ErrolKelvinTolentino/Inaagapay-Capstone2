-- ====================================================================
-- InaAgapay — Clean Inventory & Seed Vaccines + Prenatal Supplements
-- Clean up all inventory tables and re-populate only Vaccines and
-- Maternal/Prenatal Checkup Supplements connected to health facilities.
-- Run this in the Supabase SQL Editor.
-- ====================================================================

BEGIN;

-- 0. Ensure required schema columns exist
ALTER TABLE public.inventory_items ADD COLUMN IF NOT EXISTS generic_name VARCHAR(255);
ALTER TABLE public.inventory_items ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.inventory_items ADD COLUMN IF NOT EXISTS doses_per_unit INTEGER NOT NULL DEFAULT 1;
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS doses_remaining_in_open_vial INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS open_vials_count INTEGER NOT NULL DEFAULT 0;

-- 1. Wipe existing inventory movement ledger, requests, transfers, batches, and items
TRUNCATE TABLE public.inventory_transactions CASCADE;
TRUNCATE TABLE public.inventory_transfers CASCADE;
TRUNCATE TABLE public.inventory_stock_requests CASCADE;
TRUNCATE TABLE public.inventory_batches CASCADE;
DELETE FROM public.inventory_items;

-- 2. Insert ONLY Vaccines and Prenatal / Checkup Supplements into inventory_items
INSERT INTO public.inventory_items (name, generic_name, item_type, unit_of_measure, doses_per_unit, minimum_stock_threshold, is_archived)
VALUES
  -- DOH Child & Maternal Vaccines
  ('BCG Vaccine', 'Bacillus Calmette-Guérin (Tuberculosis)', 'vaccine', 'vials', 20, 20, false),
  ('Hepatitis B Vaccine', 'Hepatitis B (Pediatric Birth Dose)', 'vaccine', 'vials', 1, 25, false),
  ('Pentavalent Vaccine', 'DPT-HepB-Hib Combination', 'vaccine', 'vials', 1, 30, false),
  ('OPV Polio Vaccine', 'Oral Polio Vaccine (bOPV)', 'vaccine', 'vials', 20, 30, false),
  ('IPV Polio Vaccine', 'Inactivated Polio Vaccine', 'vaccine', 'vials', 1, 20, false),
  ('PCV-13 Vaccine', 'Pneumococcal Conjugate 13-Valent', 'vaccine', 'vials', 1, 25, false),
  ('MR Vaccine', 'Measles-Rubella Vaccine', 'vaccine', 'vials', 10, 20, false),
  ('MMR Vaccine', 'Measles-Mumps-Rubella Vaccine', 'vaccine', 'vials', 10, 20, false),
  ('Tetanus Diphtheria (Td) Vaccine', 'Tetanus-Diphtheria Toxoid (Maternal)', 'vaccine', 'vials', 10, 30, false),

  -- Prenatal & Maternal Checkup Supplements
  ('Ferrous Sulfate + Folic Acid', 'Iron 60mg + Folic Acid 400mcg', 'supplement', 'tablets', 1, 200, false),
  ('Calcium Carbonate', 'Elemental Calcium 500mg (Prenatal)', 'supplement', 'tablets', 1, 150, false),
  ('Vitamin A 200,000 IU', 'Retinol Palmitate High-Dose', 'supplement', 'capsules', 1, 100, false),
  ('Micronutrient Powder (MNP)', 'Multiple Micronutrient Sachets', 'supplement', 'sachets', 1, 150, false),
  ('Ascorbic Acid (Vitamin C)', 'Vitamin C 500mg Tablet', 'supplement', 'tablets', 1, 100, false);

-- 3. Seed Central Warehouse Batches for all items (facility_id IS NULL)
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  item_id, 
  NULL, 
  'BATCH-CENTRAL-' || item_id || '-01', 
  500, 
  500, 
  CURRENT_DATE - INTERVAL '15 days', 
  CURRENT_DATE + INTERVAL '365 days', 
  'DOH Central Supply Depot', 
  'active'
FROM public.inventory_items;

-- 4. Seed Active BHC Stock Batches for each BHC facility
-- Connects inventory to all active Barangay Health Centers in public.health_facilities
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  i.item_id, 
  hf.facility_id, 
  'BATCH-BHC' || hf.facility_id || '-' || i.item_id, 
  100, 
  100, 
  CURRENT_DATE - INTERVAL '10 days', 
  CURRENT_DATE + INTERVAL '300 days', 
  'DOH Regional Distribution Hub', 
  'active'
FROM public.inventory_items i
CROSS JOIN public.health_facilities hf
WHERE hf.facility_type = 'BHC';

-- Fallback: If health_facilities table has no BHC records, insert default batches for BHC IDs 1..5
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  i.item_id, 
  f.bhc_id, 
  'BATCH-BHC' || f.bhc_id || '-' || i.item_id, 
  100, 
  100, 
  CURRENT_DATE - INTERVAL '10 days', 
  CURRENT_DATE + INTERVAL '300 days', 
  'DOH Regional Distribution Hub', 
  'active'
FROM public.inventory_items i
CROSS JOIN (VALUES (1), (2), (3), (4), (5)) AS f(bhc_id)
WHERE NOT EXISTS (SELECT 1 FROM public.health_facilities WHERE facility_type = 'BHC');

-- 5. Record Initial Receipt Transactions in Movement Ledger
INSERT INTO public.inventory_transactions (batch_id, facility_id, transaction_type, quantity, reference_type, performed_by, logged_at)
SELECT 
  batch_id, 
  facility_id, 
  'receipt', 
  quantity_received, 
  'Initial DOH Vaccine & Prenatal Supplement Allocation', 
  1, 
  CURRENT_TIMESTAMP - INTERVAL '10 days'
FROM public.inventory_batches;

-- 6. Link Clinical Vaccines table to Physical Inventory Items
ALTER TABLE public.vaccines 
ADD COLUMN IF NOT EXISTS inventory_item_id BIGINT REFERENCES public.inventory_items(item_id) ON DELETE SET NULL;

ALTER TABLE public.immunization_records 
ADD COLUMN IF NOT EXISTS administration_place VARCHAR(30) DEFAULT 'local_facility' CHECK (administration_place IN ('local_facility', 'external_facility')),
ADD COLUMN IF NOT EXISTS facility_id BIGINT REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS inventory_batch_id BIGINT REFERENCES public.inventory_batches(batch_id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS inventory_deducted BOOLEAN DEFAULT false;

-- Map clinical vaccine entries to physical inventory items
UPDATE public.vaccines v
SET inventory_item_id = i.item_id
FROM public.inventory_items i
WHERE (v.vaccine_name ILIKE '%bcg%' AND i.name ILIKE '%bcg%')
   OR (v.vaccine_name ILIKE '%penta%' AND i.name ILIKE '%penta%')
   OR (v.vaccine_name ILIKE '%pcv%' AND i.name ILIKE '%pcv%')
   OR (v.vaccine_name ILIKE '%opv%' AND i.name ILIKE '%opv%')
   OR (v.vaccine_name ILIKE '%ipv%' AND i.name ILIKE '%ipv%')
   OR (v.vaccine_name ILIKE '%measles%' AND (i.name ILIKE '%mr%' OR i.name ILIKE '%measles%'))
   OR (v.vaccine_name ILIKE '%mmr%' AND (i.name ILIKE '%mr%' OR i.name ILIKE '%mmr%'))
   OR (v.vaccine_name ILIKE '%hep%' AND i.name ILIKE '%hep%')
   OR (v.vaccine_name ILIKE '%tetanus%' AND i.name ILIKE '%tetanus%')
   OR (v.vaccine_name ILIKE '%td%' AND i.name ILIKE '%td%');

-- 7. Stored Procedure for Automatic Multi-Dose & Single-Dose FEFO Stock Deduction
CREATE OR REPLACE FUNCTION public.deduct_immunization_stock(
  p_immunization_record_id BIGINT
) RETURNS jsonb AS $$
DECLARE
  v_rec RECORD;
  v_inv_item RECORD;
  v_batch RECORD;
  v_doses_per_unit INTEGER := 1;
  v_facility_id BIGINT;
BEGIN
  SELECT ir.*, v.inventory_item_id, v.vaccine_name, m.assigned_bhc_id
  INTO v_rec
  FROM public.immunization_records ir
  JOIN public.vaccines v ON v.vaccine_id = ir.vaccine_id
  LEFT JOIN public.midwives m ON m.midwife_id = ir.administered_by
  WHERE ir.immunization_record_id = p_immunization_record_id;

  IF v_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Record not found');
  END IF;

  IF v_rec.administration_place = 'external_facility' OR v_rec.inventory_deducted = true THEN
    RETURN jsonb_build_object('success', true, 'message', 'No stock deduction required for outside administration');
  END IF;

  v_facility_id := COALESCE(v_rec.facility_id, v_rec.assigned_bhc_id, 1);

  IF v_rec.inventory_item_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Vaccine item not mapped to inventory catalog');
  END IF;

  SELECT * INTO v_inv_item
  FROM public.inventory_items
  WHERE item_id = v_rec.inventory_item_id;

  v_doses_per_unit := COALESCE(v_inv_item.doses_per_unit, 1);

  IF v_doses_per_unit > 1 THEN
    SELECT * INTO v_batch
    FROM public.inventory_batches
    WHERE item_id = v_rec.inventory_item_id
      AND facility_id = v_facility_id
      AND status = 'active'
      AND expiration_date >= CURRENT_DATE
      AND doses_remaining_in_open_vial > 0
    ORDER BY expiration_date ASC, batch_id ASC
    LIMIT 1
    FOR UPDATE;

    IF v_batch IS NOT NULL THEN
      UPDATE public.inventory_batches
      SET doses_remaining_in_open_vial = doses_remaining_in_open_vial - 1,
          open_vials_count = CASE WHEN (doses_remaining_in_open_vial - 1) = 0 THEN GREATEST(0, open_vials_count - 1) ELSE open_vials_count END
      WHERE batch_id = v_batch.batch_id;

      INSERT INTO public.inventory_transactions (
        batch_id, facility_id, transaction_type, quantity, reference_type, logged_at
      ) VALUES (
        v_batch.batch_id,
        v_facility_id,
        'dispense',
        -1,
        'Child Dose (' || v_rec.vaccine_name || ') from Open Vial — Rec #' || p_immunization_record_id,
        NOW()
      );

      UPDATE public.immunization_records
      SET inventory_batch_id = v_batch.batch_id,
          facility_id = v_facility_id,
          inventory_deducted = true
      WHERE immunization_record_id = p_immunization_record_id;

      RETURN jsonb_build_object(
        'success', true, 
        'batch_number', v_batch.batch_number, 
        'mode', 'open_vial_dose', 
        'doses_left_in_vial', v_batch.doses_remaining_in_open_vial - 1
      );
    END IF;
  END IF;

  SELECT * INTO v_batch
  FROM public.inventory_batches
  WHERE item_id = v_rec.inventory_item_id
    AND facility_id = v_facility_id
    AND status = 'active'
    AND quantity_remaining > 0
    AND expiration_date >= CURRENT_DATE
  ORDER BY expiration_date ASC, batch_id ASC
  LIMIT 1
  FOR UPDATE;

  IF v_batch IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Out of stock at facility');
  END IF;

  IF v_doses_per_unit > 1 THEN
    UPDATE public.inventory_batches
    SET quantity_remaining = quantity_remaining - 1,
        open_vials_count = open_vials_count + 1,
        doses_remaining_in_open_vial = doses_remaining_in_open_vial + (v_doses_per_unit - 1)
    WHERE batch_id = v_batch.batch_id;

    INSERT INTO public.inventory_transactions (
      batch_id, facility_id, transaction_type, quantity, reference_type, logged_at
    ) VALUES (
      v_batch.batch_id,
      v_facility_id,
      'dispense',
      -1,
      'Opened ' || v_doses_per_unit || '-dose vial for ' || v_rec.vaccine_name || ' — Child Rec #' || p_immunization_record_id,
      NOW()
    );
  ELSE
    UPDATE public.inventory_batches
    SET quantity_remaining = quantity_remaining - 1
    WHERE batch_id = v_batch.batch_id;

    INSERT INTO public.inventory_transactions (
      batch_id, facility_id, transaction_type, quantity, reference_type, logged_at
    ) VALUES (
      v_batch.batch_id,
      v_facility_id,
      'dispense',
      -1,
      'Dispensed ' || v_rec.vaccine_name || ' — Child Rec #' || p_immunization_record_id,
      NOW()
    );
  END IF;

  UPDATE public.immunization_records
  SET inventory_batch_id = v_batch.batch_id,
      facility_id = v_facility_id,
      inventory_deducted = true
  WHERE immunization_record_id = p_immunization_record_id;

  RETURN jsonb_build_object(
    'success', true, 
    'batch_number', v_batch.batch_number, 
    'mode', CASE WHEN v_doses_per_unit > 1 THEN 'new_vial_opened' ELSE 'single_dose' END,
    'doses_left_in_vial', CASE WHEN v_doses_per_unit > 1 THEN v_doses_per_unit - 1 ELSE 0 END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Stored Procedure for Prenatal Checkup Inventory Deduction (Supplements & Td Vaccine)
CREATE OR REPLACE FUNCTION public.deduct_prenatal_encounter_inventory(
  p_encounter_id BIGINT,
  p_facility_id BIGINT DEFAULT NULL,
  p_performed_by BIGINT DEFAULT NULL,
  p_deduct_td BOOLEAN DEFAULT TRUE
) RETURNS jsonb AS $$
DECLARE
  v_enc RECORD;
  v_pc RECORD;
  v_med RECORD;
  v_batch RECORD;
  v_facility_id BIGINT;
  v_item_id BIGINT;
  v_qty_needed INTEGER;
  v_td_item_id BIGINT;
  v_td_doses_per_unit INTEGER := 10;
  v_deductions_count INTEGER := 0;
  v_warnings TEXT[] := ARRAY[]::TEXT[];
BEGIN
  SELECT ce.*, m.assigned_bhc_id
  INTO v_enc
  FROM public.clinical_encounters ce
  JOIN public.mothers m ON m.mother_id = ce.mother_id
  WHERE ce.encounter_id = p_encounter_id;

  IF v_enc IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Encounter not found');
  END IF;

  v_facility_id := COALESCE(p_facility_id, v_enc.assigned_bhc_id, 1);

  SELECT * INTO v_pc
  FROM public.prenatal_checkups
  WHERE encounter_id = p_encounter_id;

  FOR v_med IN 
    SELECT gm.* 
    FROM public.given_medications gm 
    WHERE (gm.encounter_id = p_encounter_id OR (gm.mother_id = v_enc.mother_id AND gm.date_given = v_enc.encounter_date::date))
  LOOP
    v_qty_needed := v_med.quantity;
    IF v_qty_needed > 0 THEN
      SELECT item_id INTO v_item_id
      FROM public.inventory_items
      WHERE (v_med.given_medication_name ILIKE '%ferrous%' AND (name ILIKE '%ferrous%' OR generic_name ILIKE '%iron%'))
         OR (v_med.given_medication_name ILIKE '%calcium%' AND (name ILIKE '%calcium%' OR generic_name ILIKE '%calcium%'))
         OR (name ILIKE '%' || v_med.given_medication_name || '%')
      LIMIT 1;

      IF v_item_id IS NOT NULL THEN
        SELECT * INTO v_batch
        FROM public.inventory_batches
        WHERE item_id = v_item_id
          AND facility_id = v_facility_id
          AND status = 'active'
          AND quantity_remaining >= v_qty_needed
          AND expiration_date >= CURRENT_DATE
        ORDER BY expiration_date ASC
        LIMIT 1
        FOR UPDATE;

        IF v_batch IS NOT NULL THEN
          UPDATE public.inventory_batches
          SET quantity_remaining = quantity_remaining - v_qty_needed
          WHERE batch_id = v_batch.batch_id;

          UPDATE public.given_medications
          SET inventory_batch_id = v_batch.batch_id
          WHERE given_medication_id = v_med.given_medication_id;

          INSERT INTO public.inventory_transactions (
            batch_id, facility_id, transaction_type, quantity, reference_type, reference_id, performed_by, logged_at
          ) VALUES (
            v_batch.batch_id,
            v_facility_id,
            'dispense',
            -v_qty_needed,
            'Prenatal Dispense: ' || v_med.given_medication_name || ' (' || v_qty_needed || ' tabs)',
            p_encounter_id,
            p_performed_by,
            NOW()
          );

          v_deductions_count := v_deductions_count + 1;
        ELSE
          v_warnings := array_append(v_warnings, 'Insufficient stock for ' || v_med.given_medication_name || ' (' || v_qty_needed || ' units)');
        END IF;
      END IF;
    END IF;
  END LOOP;

  IF p_deduct_td AND v_pc IS NOT NULL AND v_pc.td_vaccine_dose IS NOT NULL AND v_pc.td_vaccine_dose <> '-' AND v_pc.td_vaccine_dose <> 'none' THEN
    SELECT item_id, doses_per_unit INTO v_td_item_id, v_td_doses_per_unit
    FROM public.inventory_items
    WHERE name ILIKE '%td%' OR name ILIKE '%tetanus%'
    LIMIT 1;

    IF v_td_item_id IS NOT NULL THEN
      SELECT * INTO v_batch
      FROM public.inventory_batches
      WHERE item_id = v_td_item_id
        AND facility_id = v_facility_id
        AND status = 'active'
        AND expiration_date >= CURRENT_DATE
        AND doses_remaining_in_open_vial > 0
      ORDER BY expiration_date ASC
      LIMIT 1
      FOR UPDATE;

      IF v_batch IS NOT NULL THEN
        UPDATE public.inventory_batches
        SET doses_remaining_in_open_vial = doses_remaining_in_open_vial - 1,
            open_vials_count = CASE WHEN (doses_remaining_in_open_vial - 1) = 0 THEN GREATEST(0, open_vials_count - 1) ELSE open_vials_count END
        WHERE batch_id = v_batch.batch_id;

        INSERT INTO public.inventory_transactions (
          batch_id, facility_id, transaction_type, quantity, reference_type, reference_id, performed_by, logged_at
        ) VALUES (
          v_batch.batch_id,
          v_facility_id,
          'dispense',
          -1,
          'Maternal ' || v_pc.td_vaccine_dose || ' from Open Vial — Prenatal Encounter #' || p_encounter_id,
          p_encounter_id,
          p_performed_by,
          NOW()
        );

        v_deductions_count := v_deductions_count + 1;
      ELSE
        SELECT * INTO v_batch
        FROM public.inventory_batches
        WHERE item_id = v_td_item_id
          AND facility_id = v_facility_id
          AND status = 'active'
          AND quantity_remaining > 0
          AND expiration_date >= CURRENT_DATE
        ORDER BY expiration_date ASC
        LIMIT 1
        FOR UPDATE;

        IF v_batch IS NOT NULL THEN
          UPDATE public.inventory_batches
          SET quantity_remaining = quantity_remaining - 1,
              open_vials_count = open_vials_count + 1,
              doses_remaining_in_open_vial = doses_remaining_in_open_vial + (COALESCE(v_td_doses_per_unit, 10) - 1)
          WHERE batch_id = v_batch.batch_id;

          INSERT INTO public.inventory_transactions (
            batch_id, facility_id, transaction_type, quantity, reference_type, reference_id, performed_by, logged_at
          ) VALUES (
            v_batch.batch_id,
            v_facility_id,
            'dispense',
            -1,
            'Opened Td Vial for Maternal ' || v_pc.td_vaccine_dose || ' — Prenatal Encounter #' || p_encounter_id,
            p_encounter_id,
            p_performed_by,
            NOW()
          );

          v_deductions_count := v_deductions_count + 1;
        ELSE
          v_warnings := array_append(v_warnings, 'Td vaccine out of stock at facility');
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'deductions_count', v_deductions_count,
    'warnings', v_warnings
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
