-- ============================================================================
-- INAAGAPAY: SOLIDIFY MULTI-DOSE PER UNIT & OPEN VIAL INVENTORY SYSTEM
-- Migration: 20260819_solidify_multi_dose_open_vial_system.sql
-- Supports: DOH Multi-Dose Vial Policy (MDVP), Open Vial Expiry, FEFO Auto-Deduction
-- ============================================================================

-- 1. Ensure columns exist on inventory_items
ALTER TABLE public.inventory_items
  ADD COLUMN IF NOT EXISTS doses_per_unit INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS open_vial_shelf_hours INTEGER DEFAULT 6;

-- 2. Ensure columns exist on inventory_batches
ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS doses_remaining_in_open_vial INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS open_vials_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS vial_opened_at TIMESTAMPTZ;

-- 3. Set standard DOH open-vial shelf life and dose capacities
-- BCG: 20-dose vial, 6 hours shelf-life once reconstituted
UPDATE public.inventory_items
SET doses_per_unit = 20, open_vial_shelf_hours = 6
WHERE (name ILIKE '%bcg%' OR generic_name ILIKE '%bcg%')
  AND (doses_per_unit IS NULL OR doses_per_unit = 1);

-- Measles / MR / MMR: 10-dose vial, 6 hours shelf-life once reconstituted
UPDATE public.inventory_items
SET doses_per_unit = 10, open_vial_shelf_hours = 6
WHERE (name ILIKE '%measles%' OR generic_name ILIKE '%measles%' OR name ILIKE '%rubella%' OR name ILIKE '%mr%' OR name ILIKE '%mmr%')
  AND (doses_per_unit IS NULL OR doses_per_unit = 1);

-- Tetanus Diphtheria (Td) / TT: 10-dose vial, 28 days (672 hours) shelf-life under cold chain
UPDATE public.inventory_items
SET doses_per_unit = 10, open_vial_shelf_hours = 672
WHERE (name ILIKE '%td%' OR name ILIKE '%tetanus%' OR generic_name ILIKE '%tetanus%')
  AND (doses_per_unit IS NULL OR doses_per_unit = 1);

-- Oral Polio Vaccine (OPV): 20-dose vial, 28 days (672 hours) shelf-life under cold chain
UPDATE public.inventory_items
SET doses_per_unit = 20, open_vial_shelf_hours = 672
WHERE (name ILIKE '%opv%' OR generic_name ILIKE '%oral polio%' OR name ILIKE '%polio%')
  AND (doses_per_unit IS NULL OR doses_per_unit = 1);

-- Hepatitis B: 10-dose vial or 1-dose vial (set default multi-dose to 10 if multi-dose, 28 days shelf-life)
UPDATE public.inventory_items
SET open_vial_shelf_hours = 672
WHERE (name ILIKE '%hepb%' OR name ILIKE '%hepatitis%' OR generic_name ILIKE '%hepatitis%')
  AND open_vial_shelf_hours = 6;

-- Single-dose vaccines & oral supplements (Penta, IPV, PCV, Iron, Calcium, Vitamin A)
UPDATE public.inventory_items
SET open_vial_shelf_hours = 0
WHERE doses_per_unit = 1 OR item_type != 'vaccine';

-- ============================================================================
-- 4. RPC: DEDUCT IMMUNIZATION STOCK (CHILD IMMUNIZATIONS)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.deduct_immunization_stock(
  p_immunization_record_id INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rec RECORD;
  v_item_id INTEGER;
  v_doses_per_unit INTEGER := 1;
  v_shelf_hours INTEGER := 6;
  v_batch RECORD;
  v_batch_id INTEGER;
  v_batch_number TEXT;
  v_remaining_sealed INTEGER;
  v_remaining_open INTEGER;
  v_open_vials INTEGER;
  v_opened_at TIMESTAMPTZ;
  v_mode TEXT;
  v_doses_left INTEGER;
  v_hours_open NUMERIC;
BEGIN
  -- Get the immunization record details
  SELECT
    ir.immunization_record_id,
    ir.vaccine_id,
    ir.facility_id,
    ir.administered_by,
    ir.source,
    v.vaccine_name,
    v.inventory_item_id
  INTO v_rec
  FROM public.immunization_records ir
  JOIN public.vaccines v ON v.vaccine_id = ir.vaccine_id
  WHERE ir.immunization_record_id = p_immunization_record_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Immunization record not found');
  END IF;

  -- If source is 'outside' or facility is not provided, do not deduct local stock
  IF v_rec.source = 'outside' OR v_rec.facility_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'mode', 'outside', 'message', 'Outside immunization, no stock deducted');
  END IF;

  -- Resolve inventory_item_id
  v_item_id := v_rec.inventory_item_id;
  IF v_item_id IS NULL THEN
    SELECT item_id INTO v_item_id
    FROM public.inventory_items
    WHERE is_archived = false
      AND (
        LOWER(name) = LOWER(v_rec.vaccine_name) 
        OR LOWER(generic_name) = LOWER(v_rec.vaccine_name)
        OR (v_rec.vaccine_name ILIKE '%bcg%' AND (name ILIKE '%bcg%' OR generic_name ILIKE '%bcg%'))
        OR (v_rec.vaccine_name ILIKE '%opv%' AND (name ILIKE '%opv%' OR generic_name ILIKE '%polio%'))
        OR (v_rec.vaccine_name ILIKE '%ipv%' AND (name ILIKE '%ipv%' OR generic_name ILIKE '%polio%'))
        OR (v_rec.vaccine_name ILIKE '%penta%' AND (name ILIKE '%penta%' OR generic_name ILIKE '%pentavalent%'))
        OR (v_rec.vaccine_name ILIKE '%pcv%' AND (name ILIKE '%pcv%' OR generic_name ILIKE '%pneumococcal%'))
        OR (v_rec.vaccine_name ILIKE '%mr%' AND (name ILIKE '%mr%' OR name ILIKE '%measles%' OR generic_name ILIKE '%measles%'))
        OR (v_rec.vaccine_name ILIKE '%mmr%' AND (name ILIKE '%mmr%' OR name ILIKE '%measles%' OR generic_name ILIKE '%measles%'))
        OR (v_rec.vaccine_name ILIKE '%hepb%' AND (name ILIKE '%hepb%' OR name ILIKE '%hepatitis%' OR generic_name ILIKE '%hepatitis%'))
        OR (v_rec.vaccine_name ILIKE '%td%' AND (name ILIKE '%td%' OR name ILIKE '%tetanus%' OR generic_name ILIKE '%tetanus%'))
      )
    ORDER BY 
      CASE WHEN LOWER(name) = LOWER(v_rec.vaccine_name) THEN 1 ELSE 2 END
    LIMIT 1;
  END IF;

  IF v_item_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No matching inventory item found for vaccine: ' || v_rec.vaccine_name);
  END IF;

  -- Get item configuration
  SELECT
    COALESCE(doses_per_unit, 1),
    COALESCE(open_vial_shelf_hours, 6)
  INTO v_doses_per_unit, v_shelf_hours
  FROM public.inventory_items
  WHERE item_id = v_item_id;

  -- Fallback heuristics if DB configuration has doses_per_unit = 1 for known multi-dose vaccines
  IF v_doses_per_unit = 1 THEN
    IF v_rec.vaccine_name ILIKE '%bcg%' OR v_rec.vaccine_name ILIKE '%opv%' THEN
      v_doses_per_unit := 20;
      v_shelf_hours := CASE WHEN v_rec.vaccine_name ILIKE '%bcg%' THEN 6 ELSE 672 END;
    ELSIF v_rec.vaccine_name ILIKE '%mr%' OR v_rec.vaccine_name ILIKE '%measles%' OR v_rec.vaccine_name ILIKE '%mmr%' OR v_rec.vaccine_name ILIKE '%td%' THEN
      v_doses_per_unit := 10;
      v_shelf_hours := CASE WHEN v_rec.vaccine_name ILIKE '%td%' THEN 672 ELSE 6 END;
    END IF;
  END IF;

  -- Case A: Multi-Dose Vaccine (doses_per_unit > 1)
  IF v_doses_per_unit > 1 THEN

    -- Step 1: Look for an existing open vial with doses remaining (FEFO)
    FOR v_batch IN
      SELECT
        batch_id,
        batch_number,
        doses_remaining_in_open_vial,
        open_vials_count,
        vial_opened_at,
        quantity_remaining,
        expiration_date
      FROM public.inventory_batches
      WHERE item_id = v_item_id
        AND facility_id = v_rec.facility_id
        AND status = 'active'
        AND expiration_date >= CURRENT_DATE
        AND doses_remaining_in_open_vial > 0
      ORDER BY expiration_date ASC, batch_id ASC
      FOR UPDATE
    LOOP
      -- Check open-vial shelf life
      IF v_batch.vial_opened_at IS NOT NULL AND v_shelf_hours > 0 THEN
        v_hours_open := EXTRACT(EPOCH FROM (NOW() - v_batch.vial_opened_at)) / 3600;
        IF v_hours_open > v_shelf_hours THEN
          -- Auto-discard expired open vial doses
          UPDATE public.inventory_batches
          SET doses_remaining_in_open_vial = 0,
              open_vials_count = GREATEST(0, COALESCE(open_vials_count, 1) - 1),
              vial_opened_at = NULL,
              status = CASE WHEN quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
          WHERE batch_id = v_batch.batch_id;

          -- Log discard in ledger
          INSERT INTO public.inventory_transactions (
            batch_id,
            facility_id,
            transaction_type,
            quantity,
            reference_type,
            notes,
            performed_by,
            logged_at
          ) VALUES (
            v_batch.batch_id,
            v_rec.facility_id,
            'expiry_disposal',
            0,
            'open_vial_expired',
            'Auto-discarded ' || v_batch.doses_remaining_in_open_vial || ' open doses (exceeded ' || v_shelf_hours || 'h shelf limit)',
            COALESCE(v_rec.administered_by, 1),
            NOW()
          );

          -- Continue to next batch
          CONTINUE;
        END IF;
      END IF;

      -- Active valid open vial found! Deduct 1 dose
      v_doses_left := v_batch.doses_remaining_in_open_vial - 1;
      
      UPDATE public.inventory_batches
      SET doses_remaining_in_open_vial = v_doses_left,
          open_vials_count = CASE WHEN v_doses_left = 0 THEN GREATEST(0, COALESCE(open_vials_count, 1) - 1) ELSE COALESCE(open_vials_count, 1) END,
          vial_opened_at = CASE WHEN v_doses_left = 0 THEN NULL ELSE COALESCE(v_batch.vial_opened_at, NOW()) END,
          status = CASE WHEN v_doses_left = 0 AND quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
      WHERE batch_id = v_batch.batch_id;

      -- Update immunization record with batch used
      UPDATE public.immunization_records
      SET inventory_batch_id = v_batch.batch_id
      WHERE immunization_record_id = p_immunization_record_id;

      -- Log transaction
      INSERT INTO public.inventory_transactions (
        batch_id,
        facility_id,
        transaction_type,
        quantity,
        reference_type,
        notes,
        performed_by,
        logged_at
      ) VALUES (
        v_batch.batch_id,
        v_rec.facility_id,
        'dispense',
        0, -- 0 whole sealed units deducted
        'immunization',
        'Child Dose (' || v_rec.vaccine_name || ') from Open Vial (' || v_doses_left || ' doses left) — Rec #' || p_immunization_record_id,
        COALESCE(v_rec.administered_by, 1),
        NOW()
      );

      RETURN jsonb_build_object(
        'success', true,
        'mode', 'open_vial_dose',
        'batch_id', v_batch.batch_id,
        'batch_number', v_batch.batch_number,
        'doses_left_in_vial', v_doses_left,
        'doses_per_unit', v_doses_per_unit,
        'shelf_hours', v_shelf_hours,
        'message', 'Dose deducted from active open vial'
      );
    END LOOP;

    -- Step 2: No valid open vial. Open a new sealed vial from earliest expiring batch (FEFO)
    SELECT
      batch_id,
      batch_number,
      quantity_remaining,
      doses_remaining_in_open_vial,
      open_vials_count
    INTO v_batch
    FROM public.inventory_batches
    WHERE item_id = v_item_id
      AND facility_id = v_rec.facility_id
      AND status = 'active'
      AND expiration_date >= CURRENT_DATE
      AND quantity_remaining > 0
    ORDER BY expiration_date ASC, batch_id ASC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Out of stock: No active batches with usable inventory for ' || v_rec.vaccine_name);
    END IF;

    -- Deduct 1 sealed unit, set doses remaining to (v_doses_per_unit - 1), mark opened
    v_doses_left := v_doses_per_unit - 1;
    
    UPDATE public.inventory_batches
    SET quantity_remaining = quantity_remaining - 1,
        open_vials_count = COALESCE(open_vials_count, 0) + 1,
        doses_remaining_in_open_vial = COALESCE(doses_remaining_in_open_vial, 0) + v_doses_left,
        vial_opened_at = NOW(),
        status = CASE WHEN (quantity_remaining - 1) <= 0 AND v_doses_left <= 0 THEN 'depleted' ELSE 'active' END
    WHERE batch_id = v_batch.batch_id;

    -- Update immunization record with batch used
    UPDATE public.immunization_records
    SET inventory_batch_id = v_batch.batch_id
    WHERE immunization_record_id = p_immunization_record_id;

    -- Log transaction for newly opened vial
    INSERT INTO public.inventory_transactions (
      batch_id,
      facility_id,
      transaction_type,
      quantity,
      reference_type,
      notes,
      performed_by,
      logged_at
    ) VALUES (
      v_batch.batch_id,
      v_rec.facility_id,
      'dispense',
      -1, -- 1 whole sealed unit deducted from reserve
      'immunization',
      'Opened ' || v_doses_per_unit || '-dose vial for ' || v_rec.vaccine_name || ' (' || v_doses_left || ' doses left in vial) — Child Rec #' || p_immunization_record_id,
      COALESCE(v_rec.administered_by, 1),
      NOW()
    );

    RETURN jsonb_build_object(
      'success', true,
      'mode', 'new_vial_opened',
      'batch_id', v_batch.batch_id,
      'batch_number', v_batch.batch_number,
      'doses_left_in_vial', v_doses_left,
      'doses_per_unit', v_doses_per_unit,
      'shelf_hours', v_shelf_hours,
      'message', 'Opened fresh sealed vial'
    );

  ELSE
    -- Case B: Single-Dose Vaccine (doses_per_unit = 1)
    SELECT
      batch_id,
      batch_number,
      quantity_remaining
    INTO v_batch
    FROM public.inventory_batches
    WHERE item_id = v_item_id
      AND facility_id = v_rec.facility_id
      AND status = 'active'
      AND expiration_date >= CURRENT_DATE
      AND quantity_remaining > 0
    ORDER BY expiration_date ASC, batch_id ASC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Out of stock: No usable single-dose batch for ' || v_rec.vaccine_name);
    END IF;

    UPDATE public.inventory_batches
    SET quantity_remaining = quantity_remaining - 1,
        status = CASE WHEN (quantity_remaining - 1) <= 0 THEN 'depleted' ELSE 'active' END
    WHERE batch_id = v_batch.batch_id;

    UPDATE public.immunization_records
    SET inventory_batch_id = v_batch.batch_id
    WHERE immunization_record_id = p_immunization_record_id;

    INSERT INTO public.inventory_transactions (
      batch_id,
      facility_id,
      transaction_type,
      quantity,
      reference_type,
      notes,
      performed_by,
      logged_at
    ) VALUES (
      v_batch.batch_id,
      v_rec.facility_id,
      'dispense',
      -1,
      'immunization',
      'Dispensed 1 single-dose unit of ' || v_rec.vaccine_name || ' — Child Rec #' || p_immunization_record_id,
      COALESCE(v_rec.administered_by, 1),
      NOW()
    );

    RETURN jsonb_build_object(
      'success', true,
      'mode', 'single_dose',
      'batch_id', v_batch.batch_id,
      'batch_number', v_batch.batch_number,
      'doses_left_in_vial', 0,
      'doses_per_unit', 1,
      'message', 'Single-dose unit dispensed'
    );
  END IF;

END;
$$;

-- ============================================================================
-- 5. RPC: DISCARD OPEN VIAL DOSES
-- ============================================================================
CREATE OR REPLACE FUNCTION public.discard_open_vial_doses(
  p_batch_id INTEGER,
  p_discarded_by INTEGER DEFAULT 1,
  p_reason TEXT DEFAULT 'Open vial expired per DOH shelf-life guidelines'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_batch RECORD;
  v_doses_discarded INTEGER;
BEGIN
  SELECT
    b.batch_id,
    b.batch_number,
    b.facility_id,
    b.quantity_remaining,
    b.doses_remaining_in_open_vial,
    b.open_vials_count,
    b.vial_opened_at,
    i.name AS item_name
  INTO v_batch
  FROM public.inventory_batches b
  LEFT JOIN public.inventory_items i ON i.item_id = b.item_id
  WHERE b.batch_id = p_batch_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Batch not found');
  END IF;

  v_doses_discarded := COALESCE(v_batch.doses_remaining_in_open_vial, 0);

  IF v_doses_discarded <= 0 THEN
    RETURN jsonb_build_object('success', true, 'message', 'No active open doses in this vial', 'doses_discarded', 0);
  END IF;

  -- Reset open vial state
  UPDATE public.inventory_batches
  SET doses_remaining_in_open_vial = 0,
      open_vials_count = 0,
      vial_opened_at = NULL,
      status = CASE WHEN quantity_remaining <= 0 THEN 'depleted' ELSE status END
  WHERE batch_id = p_batch_id;

  -- Log audit transaction
  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
    reference_type,
    notes,
    performed_by,
    logged_at
  ) VALUES (
    p_batch_id,
    v_batch.facility_id,
    'expiry_disposal',
    0,
    'open_vial_discard',
    COALESCE(p_reason, 'Discarded remaining open vial doses') || ' (' || v_doses_discarded || ' doses discarded from ' || COALESCE(v_batch.item_name, 'batch') || ' #' || v_batch.batch_number || ')',
    p_discarded_by,
    NOW()
  );

  RETURN jsonb_build_object(
    'success', true,
    'batch_id', p_batch_id,
    'batch_number', v_batch.batch_number,
    'doses_discarded', v_doses_discarded,
    'message', 'Discarded ' || v_doses_discarded || ' open doses'
  );
END;
$$;

-- ============================================================================
-- 6. RPC: DEDUCT PRENATAL ENCOUNTER INVENTORY (MATERNAL TD + SUPPLEMENTS)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.deduct_prenatal_encounter_inventory(
  p_encounter_id INTEGER,
  p_facility_id INTEGER,
  p_performed_by INTEGER DEFAULT 1,
  p_deduct_td BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pc RECORD;
  v_results JSONB := '[]'::jsonb;
  v_td_item_id INTEGER;
  v_td_batch RECORD;
  v_td_doses_left INTEGER;
  v_shelf_hours INTEGER := 672; -- 28 days for Td
  v_hours_open NUMERIC;
BEGIN
  SELECT
    encounter_id,
    mother_id,
    td_vaccine_dose,
    facility_id
  INTO v_pc
  FROM public.prenatal_checkups
  WHERE encounter_id = p_encounter_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Prenatal encounter not found');
  END IF;

  -- Deduct Maternal Td if requested and administered
  IF p_deduct_td AND v_pc.td_vaccine_dose IS NOT NULL AND v_pc.td_vaccine_dose != '' AND p_facility_id IS NOT NULL THEN
    -- Find Td inventory item
    SELECT item_id INTO v_td_item_id
    FROM public.inventory_items
    WHERE (name ILIKE '%td%' OR name ILIKE '%tetanus%' OR generic_name ILIKE '%tetanus%')
      AND is_archived = false
    LIMIT 1;

    IF v_td_item_id IS NOT NULL THEN
      -- Step 1: Check existing open vial
      FOR v_td_batch IN
        SELECT
          batch_id,
          batch_number,
          doses_remaining_in_open_vial,
          open_vials_count,
          vial_opened_at,
          quantity_remaining
        FROM public.inventory_batches
        WHERE item_id = v_td_item_id
          AND facility_id = p_facility_id
          AND status = 'active'
          AND expiration_date >= CURRENT_DATE
          AND doses_remaining_in_open_vial > 0
        ORDER BY expiration_date ASC, batch_id ASC
      LOOP
        -- Shelf life validation (28 days / 672 hours)
        IF v_td_batch.vial_opened_at IS NOT NULL THEN
          v_hours_open := EXTRACT(EPOCH FROM (NOW() - v_td_batch.vial_opened_at)) / 3600;
          IF v_hours_open > v_shelf_hours THEN
            -- Expired, discard and continue
            PERFORM public.discard_open_vial_doses(v_td_batch.batch_id, p_performed_by, 'Td open vial expired (>28 days)');
            CONTINUE;
          END IF;
        END IF;

        -- Valid open vial
        v_td_doses_left := v_td_batch.doses_remaining_in_open_vial - 1;
        UPDATE public.inventory_batches
        SET doses_remaining_in_open_vial = v_td_doses_left,
            open_vials_count = CASE WHEN v_td_doses_left = 0 THEN GREATEST(0, COALESCE(open_vials_count, 1) - 1) ELSE COALESCE(open_vials_count, 1) END,
            vial_opened_at = CASE WHEN v_td_doses_left = 0 THEN NULL ELSE COALESCE(v_td_batch.vial_opened_at, NOW()) END,
            status = CASE WHEN v_td_doses_left = 0 AND quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
        WHERE batch_id = v_td_batch.batch_id;

        INSERT INTO public.inventory_transactions (
          batch_id,
          facility_id,
          transaction_type,
          quantity,
          reference_type,
          notes,
          performed_by,
          logged_at
        ) VALUES (
          v_td_batch.batch_id,
          p_facility_id,
          'dispense',
          0,
          'prenatal_td',
          'Maternal ' || v_pc.td_vaccine_dose || ' from Open Vial (' || v_td_doses_left || ' doses left) — Encounter #' || p_encounter_id,
          p_performed_by,
          NOW()
        );

        v_results := v_results || jsonb_build_object(
          'item', 'Td Vaccine',
          'mode', 'open_vial_dose',
          'batch_number', v_td_batch.batch_number,
          'doses_left', v_td_doses_left
        );

        EXIT; -- Finished Td deduction
      END LOOP;

      -- If no open vial was used, open a new sealed vial
      IF jsonb_array_length(v_results) = 0 THEN
        SELECT
          batch_id,
          batch_number,
          quantity_remaining
        INTO v_td_batch
        FROM public.inventory_batches
        WHERE item_id = v_td_item_id
          AND facility_id = p_facility_id
          AND status = 'active'
          AND expiration_date >= CURRENT_DATE
          AND quantity_remaining > 0
        ORDER BY expiration_date ASC, batch_id ASC
        LIMIT 1;

        IF FOUND THEN
          v_td_doses_left := 9; -- 10 - 1
          UPDATE public.inventory_batches
          SET quantity_remaining = quantity_remaining - 1,
              open_vials_count = COALESCE(open_vials_count, 0) + 1,
              doses_remaining_in_open_vial = COALESCE(doses_remaining_in_open_vial, 0) + v_td_doses_left,
              vial_opened_at = NOW(),
              status = CASE WHEN (quantity_remaining - 1) <= 0 AND v_td_doses_left <= 0 THEN 'depleted' ELSE 'active' END
          WHERE batch_id = v_td_batch.batch_id;

          INSERT INTO public.inventory_transactions (
            batch_id,
            facility_id,
            transaction_type,
            quantity,
            reference_type,
            notes,
            performed_by,
            logged_at
          ) VALUES (
            v_td_batch.batch_id,
            p_facility_id,
            'dispense',
            -1,
            'prenatal_td',
            'Opened 10-dose Td vial for Maternal ' || v_pc.td_vaccine_dose || ' (9 doses left) — Encounter #' || p_encounter_id,
            p_performed_by,
            NOW()
          );

          v_results := v_results || jsonb_build_object(
            'item', 'Td Vaccine',
            'mode', 'new_vial_opened',
            'batch_number', v_td_batch.batch_number,
            'doses_left', 9
          );
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'deductions', v_results);
END;
$$;
