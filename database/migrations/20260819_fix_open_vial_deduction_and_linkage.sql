-- ==============================================================================
-- MIGRATION: 20260819_fix_open_vial_deduction_and_linkage.sql
-- Fix Child Immunization & Maternal Td Open Vial Deduction System
-- Resolves column typos, NULL handling on open vial doses, and multi-dose catalog
-- ==============================================================================

-- 1. Ensure columns exist on inventory_items and inventory_batches with NOT NULL defaults
ALTER TABLE IF EXISTS public.inventory_items
  ADD COLUMN IF NOT EXISTS doses_per_unit INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS open_vial_shelf_hours INTEGER DEFAULT 6;

ALTER TABLE IF EXISTS public.inventory_batches
  ADD COLUMN IF NOT EXISTS doses_remaining_in_open_vial INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS open_vials_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS vial_opened_at TIMESTAMPTZ;

-- Clean up any NULL values in existing batch rows
UPDATE public.inventory_batches
SET doses_remaining_in_open_vial = 0
WHERE doses_remaining_in_open_vial IS NULL;

UPDATE public.inventory_batches
SET open_vials_count = 0
WHERE open_vials_count IS NULL;

-- 2. Ensure standard DOH multi-dose capacities and shelf lives are set in inventory_items
-- BCG: 20 doses/vial, 6h shelf life once opened/reconstituted
UPDATE public.inventory_items
SET doses_per_unit = 20, open_vial_shelf_hours = 6
WHERE (name ILIKE '%bcg%' OR generic_name ILIKE '%bcg%');

-- OPV (Oral Polio): 20 doses/vial, 28 days (672h) shelf life under cold chain
UPDATE public.inventory_items
SET doses_per_unit = 20, open_vial_shelf_hours = 672
WHERE (name ILIKE '%opv%' OR generic_name ILIKE '%oral polio%' OR name ILIKE '%polio%');

-- Measles / MR / MMR: 10 doses/vial, 6h shelf life once opened/reconstituted
UPDATE public.inventory_items
SET doses_per_unit = 10, open_vial_shelf_hours = 6
WHERE (name ILIKE '%measles%' OR generic_name ILIKE '%measles%' OR name ILIKE '%mr%' OR name ILIKE '%mmr%' OR name ILIKE '%rubella%');

-- Td (Tetanus Diphtheria) / TT: 10 doses/vial, 28 days (672h) shelf life
UPDATE public.inventory_items
SET doses_per_unit = 10, open_vial_shelf_hours = 672
WHERE (name ILIKE '%td%' OR name ILIKE '%tetanus%' OR generic_name ILIKE '%tetanus%');

-- Single-dose vaccines (Penta, IPV, PCV, HepB single-dose)
UPDATE public.inventory_items
SET doses_per_unit = 1, open_vial_shelf_hours = 0
WHERE (name ILIKE '%penta%' OR name ILIKE '%ipv%' OR name ILIKE '%pcv%')
  AND doses_per_unit IS NULL;

-- 3. Link vaccine catalogue items to inventory items if inventory_item_id is NULL
UPDATE public.vaccines v
SET inventory_item_id = i.item_id
FROM public.inventory_items i
WHERE v.inventory_item_id IS NULL
  AND i.is_archived = false
  AND (
    LOWER(i.name) = LOWER(v.vaccine_name)
    OR (v.vaccine_name ILIKE '%bcg%' AND i.name ILIKE '%bcg%')
    OR (v.vaccine_name ILIKE '%opv%' AND i.name ILIKE '%opv%')
    OR (v.vaccine_name ILIKE '%ipv%' AND i.name ILIKE '%ipv%')
    OR (v.vaccine_name ILIKE '%penta%' AND i.name ILIKE '%penta%')
    OR (v.vaccine_name ILIKE '%pcv%' AND i.name ILIKE '%pcv%')
    OR (v.vaccine_name ILIKE '%measles%' AND (i.name ILIKE '%mr%' OR i.name ILIKE '%measles%'))
    OR (v.vaccine_name ILIKE '%mmr%' AND (i.name ILIKE '%mmr%' OR i.name ILIKE '%measles%'))
    OR (v.vaccine_name ILIKE '%hepb%' AND (i.name ILIKE '%hepb%' OR i.name ILIKE '%hepatitis%'))
  );

-- 4. Definitive and robust deduct_immunization_stock RPC for Child Immunizations
CREATE OR REPLACE FUNCTION public.deduct_immunization_stock(
  p_immunization_record_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rec RECORD;
  v_item_id BIGINT;
  v_doses_per_unit INTEGER := 1;
  v_shelf_hours INTEGER := 6;
  v_batch RECORD;
  v_doses_left INTEGER;
  v_hours_open NUMERIC;
BEGIN
  -- 1. Get the immunization record details using exact primary key: immunization_record_id
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
    RETURN jsonb_build_object('success', false, 'error', 'Immunization record #' || p_immunization_record_id || ' not found');
  END IF;

  -- 2. Outside immunizations do not deduct BHC stock
  IF v_rec.source = 'outside' OR v_rec.facility_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'mode', 'outside', 'message', 'Outside immunization recorded (no stock deducted)');
  END IF;

  -- 3. Resolve inventory item ID
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
    RETURN jsonb_build_object('success', false, 'error', 'No inventory catalog item found for vaccine: ' || v_rec.vaccine_name);
  END IF;

  -- 4. Get item configuration
  SELECT
    COALESCE(doses_per_unit, 1),
    COALESCE(open_vial_shelf_hours, 6)
  INTO v_doses_per_unit, v_shelf_hours
  FROM public.inventory_items
  WHERE item_id = v_item_id;

  -- Heuristics fallback for standard multi-dose vaccines
  IF v_doses_per_unit = 1 THEN
    IF v_rec.vaccine_name ILIKE '%bcg%' OR v_rec.vaccine_name ILIKE '%opv%' THEN
      v_doses_per_unit := 20;
      v_shelf_hours := CASE WHEN v_rec.vaccine_name ILIKE '%bcg%' THEN 6 ELSE 672 END;
    ELSIF v_rec.vaccine_name ILIKE '%mr%' OR v_rec.vaccine_name ILIKE '%measles%' OR v_rec.vaccine_name ILIKE '%mmr%' OR v_rec.vaccine_name ILIKE '%td%' THEN
      v_doses_per_unit := 10;
      v_shelf_hours := CASE WHEN v_rec.vaccine_name ILIKE '%td%' THEN 672 ELSE 6 END;
    END IF;
  END IF;

  -- 5. Multi-Dose per Unit Logic
  IF v_doses_per_unit > 1 THEN

    -- Step 5A: Look for an active Open Multi-Dose Vial at facility (FEFO)
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
        AND facility_id = v_rec.facility_id
        AND status = 'active'
        AND expiration_date >= CURRENT_DATE
        AND COALESCE(doses_remaining_in_open_vial, 0) > 0
      ORDER BY expiration_date ASC, batch_id ASC
      FOR UPDATE
    LOOP
      -- Check open-vial shelf life limit
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
            v_batch.batch_id, v_rec.facility_id, 'expiry_disposal', 0, 'open_vial_expired',
            'Auto-discarded ' || v_batch.doses_remaining_in_open_vial || ' expired doses in open vial (Batch #' || v_batch.batch_number || ') > ' || v_shelf_hours || 'h limit',
            COALESCE(v_rec.administered_by, 1), NOW()
          );

          CONTINUE; -- Try next batch
        END IF;
      END IF;

      -- Active valid open vial found: Deduct 1 dose
      v_doses_left := v_batch.doses_remaining_in_open_vial - 1;
      
      UPDATE public.inventory_batches
      SET doses_remaining_in_open_vial = v_doses_left,
          open_vials_count = CASE WHEN v_doses_left <= 0 THEN GREATEST(0, COALESCE(open_vials_count, 1) - 1) ELSE COALESCE(open_vials_count, 1) END,
          vial_opened_at = CASE WHEN v_doses_left <= 0 THEN NULL ELSE COALESCE(v_batch.vial_opened_at, NOW()) END,
          status = CASE WHEN v_doses_left <= 0 AND quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
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
        reference_id,
        notes,
        performed_by,
        logged_at
      ) VALUES (
        v_batch.batch_id,
        v_rec.facility_id,
        'dispense',
        0,
        'immunization',
        p_immunization_record_id,
        'Child Dose (' || v_rec.vaccine_name || ') from Open Vial (' || v_doses_left || ' doses left, Batch #' || v_batch.batch_number || ') — Rec #' || p_immunization_record_id,
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
        'message', '1 dose deducted from open vial'
      );
    END LOOP;

    -- Step 5B: No open vial available. Open 1 new sealed vial (FEFO)
    SELECT
      batch_id,
      batch_number,
      quantity_remaining,
      COALESCE(doses_remaining_in_open_vial, 0) AS doses_remaining_in_open_vial,
      COALESCE(open_vials_count, 0) AS open_vials_count
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
      RETURN jsonb_build_object('success', false, 'error', 'Out of stock: No active sealed or open batches available at BHC for ' || v_rec.vaccine_name);
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

    UPDATE public.immunization_records
    SET inventory_batch_id = v_batch.batch_id
    WHERE immunization_record_id = p_immunization_record_id;

    INSERT INTO public.inventory_transactions (
      batch_id,
      facility_id,
      transaction_type,
      quantity,
      reference_type,
      reference_id,
      notes,
      performed_by,
      logged_at
    ) VALUES (
      v_batch.batch_id,
      v_rec.facility_id,
      'dispense',
      -1,
      'immunization',
      p_immunization_record_id,
      'Opened ' || v_doses_per_unit || '-dose vial for ' || v_rec.vaccine_name || ' (' || v_doses_left || ' doses left in open vial, Batch #' || v_batch.batch_number || ') — Rec #' || p_immunization_record_id,
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
      'message', 'Opened 1 fresh sealed vial'
    );

  ELSE
    -- Step 6: Single-Dose Vaccine (doses_per_unit = 1)
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
      reference_id,
      notes,
      performed_by,
      logged_at
    ) VALUES (
      v_batch.batch_id,
      v_rec.facility_id,
      'dispense',
      -1,
      'immunization',
      p_immunization_record_id,
      'Dispensed 1 single-dose unit of ' || v_rec.vaccine_name || ' (Batch #' || v_batch.batch_number || ') — Rec #' || p_immunization_record_id,
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
      'message', 'Dispensed 1 single-dose unit'
    );
  END IF;
END;
$$;
