-- ====================================================================
-- InaAgapay Migration: Comprehensive Inventory Upgrades & Clinical Integration
-- 
-- 1. Multi-dose vial support (doses_per_unit, open vial dose tracking)
-- 2. Enhanced child immunization multi-dose FEFO deduction
-- 3. Prenatal checkup inventory deduction (Td vaccine & maternal supplements)
-- 4. Central-only supplier receipt safeguards
-- ====================================================================

BEGIN;

-- 1. Multi-Dose Vial and Packaging Schema Enhancements
ALTER TABLE public.inventory_items
  ADD COLUMN IF NOT EXISTS doses_per_unit INTEGER NOT NULL DEFAULT 1;

ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS doses_remaining_in_open_vial INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS open_vials_count INTEGER NOT NULL DEFAULT 0;

-- Update standard DOH doses per vial/packaging
UPDATE public.inventory_items
SET doses_per_unit = 20
WHERE name ILIKE '%bcg%' OR name ILIKE '%opv%';

UPDATE public.inventory_items
SET doses_per_unit = 10
WHERE name ILIKE '%mr%' OR name ILIKE '%mmr%' OR name ILIKE '%measles%' OR name ILIKE '%tetanus%' OR name ILIKE '%td%';

UPDATE public.inventory_items
SET doses_per_unit = 1
WHERE name ILIKE '%penta%' OR name ILIKE '%pcv%' OR name ILIKE '%hep%' OR name ILIKE '%ipv%'
   OR item_type = 'supplement';

-- 2. Ensure clinical vaccines and inventory items are linked
ALTER TABLE public.vaccines 
  ADD COLUMN IF NOT EXISTS inventory_item_id BIGINT REFERENCES public.inventory_items(item_id) ON DELETE SET NULL;

UPDATE public.vaccines v
SET inventory_item_id = i.item_id
FROM public.inventory_items i
WHERE v.inventory_item_id IS NULL
  AND ((v.vaccine_name ILIKE '%bcg%' AND i.name ILIKE '%bcg%')
    OR (v.vaccine_name ILIKE '%penta%' AND i.name ILIKE '%penta%')
    OR (v.vaccine_name ILIKE '%pcv%' AND i.name ILIKE '%pcv%')
    OR (v.vaccine_name ILIKE '%opv%' AND i.name ILIKE '%opv%')
    OR (v.vaccine_name ILIKE '%ipv%' AND i.name ILIKE '%ipv%')
    OR (v.vaccine_name ILIKE '%measles%' AND (i.name ILIKE '%mr%' OR i.name ILIKE '%measles%'))
    OR (v.vaccine_name ILIKE '%mmr%' AND (i.name ILIKE '%mr%' OR i.name ILIKE '%mmr%'))
    OR (v.vaccine_name ILIKE '%hep%' AND i.name ILIKE '%hep%')
    OR (v.vaccine_name ILIKE '%tetanus%' AND i.name ILIKE '%tetanus%')
    OR (v.vaccine_name ILIKE '%td%' AND i.name ILIKE '%td%'));

-- 3. Immunization Record multi-dose stock deduction RPC
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
  -- Fetch immunization record details
  SELECT ir.*, v.inventory_item_id, v.vaccine_name, m.assigned_bhc_id
  INTO v_rec
  FROM public.immunization_records ir
  JOIN public.vaccines v ON v.vaccine_id = ir.vaccine_id
  LEFT JOIN public.midwives m ON m.midwife_id = ir.administered_by
  WHERE ir.immunization_record_id = p_immunization_record_id;

  IF v_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Record not found');
  END IF;

  -- Skip if external facility or already deducted
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

  -- Multi-dose handling: Check for an active batch with an open vial first (FEFO)
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
      -- Use 1 dose from open vial
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

  -- No open vial with doses available: find sealed batch expiring earliest (FEFO)
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
    -- Open 1 new sealed vial: deduct 1 vial from sealed quantity, credit remaining doses to open vial pool
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
    -- Single-dose item: deduct 1 unit directly
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

  RETURN jsonb_build_object('success', true, 'batch_number', v_batch.batch_number, 'mode', 'new_vial_opened');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. Stored Procedure for Prenatal Checkup Inventory Deduction (Supplements & Td Vaccine)
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
  -- Get clinical encounter and prenatal checkup details
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

  -- 4A. Deduct Given Supplements (Ferrous Sulfate + Folic Acid, Calcium Carbonate, etc.)
  FOR v_med IN 
    SELECT gm.* 
    FROM public.given_medications gm 
    WHERE (gm.encounter_id = p_encounter_id OR (gm.mother_id = v_enc.mother_id AND gm.date_given = v_enc.encounter_date::date))
  LOOP
    v_qty_needed := v_med.quantity;
    IF v_qty_needed > 0 THEN
      -- Resolve inventory item id based on medication name
      SELECT item_id INTO v_item_id
      FROM public.inventory_items
      WHERE (v_med.given_medication_name ILIKE '%ferrous%' AND (name ILIKE '%ferrous%' OR generic_name ILIKE '%iron%'))
         OR (v_med.given_medication_name ILIKE '%calcium%' AND (name ILIKE '%calcium%' OR generic_name ILIKE '%calcium%'))
         OR (name ILIKE '%' || v_med.given_medication_name || '%')
      LIMIT 1;

      IF v_item_id IS NOT NULL THEN
        -- Find active batch at facility expiring earliest (FEFO)
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

  -- 4B. Deduct Td Vaccine (if administered on-site during this checkup)
  IF p_deduct_td AND v_pc IS NOT NULL AND v_pc.td_vaccine_dose IS NOT NULL AND v_pc.td_vaccine_dose <> '-' AND v_pc.td_vaccine_dose <> 'none' THEN
    SELECT item_id, doses_per_unit INTO v_td_item_id, v_td_doses_per_unit
    FROM public.inventory_items
    WHERE name ILIKE '%td%' OR name ILIKE '%tetanus%'
    LIMIT 1;

    IF v_td_item_id IS NOT NULL THEN
      -- First check for open Td vial at this facility
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
        -- Open a new sealed Td vial (FEFO)
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
