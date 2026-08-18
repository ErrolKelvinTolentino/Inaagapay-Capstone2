-- ==============================================================================
-- MIGRATION: 20260819_prenatal_td_and_supplements_inventory_sync.sql
-- Synchronize Maternal Td Vaccine & Supplements with BHC Inventory
-- Multi-Dose Vial Tracking + FEFO Batch Dispensing for Prenatal Checkups
-- ==============================================================================

-- 1. Ensure given_medications has encounter_id, facility_id, and inventory_batch_id
ALTER TABLE IF EXISTS public.given_medications 
  ADD COLUMN IF NOT EXISTS encounter_id BIGINT REFERENCES public.clinical_encounters(encounter_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS facility_id BIGINT REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS inventory_batch_id BIGINT REFERENCES public.inventory_batches(batch_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_given_medications_encounter ON public.given_medications(encounter_id);
CREATE INDEX IF NOT EXISTS idx_given_medications_batch ON public.given_medications(inventory_batch_id);

-- 2. Comprehensive Prenatal Checkup Inventory Deduction RPC
CREATE OR REPLACE FUNCTION public.deduct_prenatal_encounter_inventory(
  p_encounter_id BIGINT,
  p_facility_id BIGINT DEFAULT NULL,
  p_performed_by BIGINT DEFAULT NULL,
  p_deduct_td BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_enc RECORD;
  v_pc RECORD;
  v_med RECORD;
  v_batch RECORD;
  v_facility_id BIGINT;
  v_item_id BIGINT;
  v_qty_needed INTEGER;
  v_td_item_id BIGINT;
  v_td_dpu INTEGER := 10;
  v_shelf_hours INTEGER := 672; -- 28 days (28 * 24 = 672 hrs) DOH standard for opened Td
  v_hours_open NUMERIC;
  v_doses_left INTEGER;
  v_results JSONB := '[]'::jsonb;
  v_warnings JSONB := '[]'::jsonb;
BEGIN
  -- 1. Retrieve Clinical Encounter & Mother Context
  SELECT ce.*, m.assigned_bhc_id
  INTO v_enc
  FROM public.clinical_encounters ce
  JOIN public.mothers m ON m.mother_id = ce.mother_id
  WHERE ce.encounter_id = p_encounter_id;

  IF NOT FOUND THEN
    -- Fallback to direct prenatal_checkups table if clinical_encounters is not present
    SELECT pc.*, m.assigned_bhc_id
    INTO v_pc
    FROM public.prenatal_checkups pc
    JOIN public.mothers m ON m.mother_id = pc.mother_id
    WHERE pc.encounter_id = p_encounter_id;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Prenatal encounter #' || p_encounter_id || ' not found');
    END IF;
    v_facility_id := COALESCE(p_facility_id, v_pc.assigned_bhc_id, 1);
  ELSE
    SELECT * INTO v_pc
    FROM public.prenatal_checkups
    WHERE encounter_id = p_encounter_id;
    v_facility_id := COALESCE(p_facility_id, v_enc.assigned_bhc_id, 1);
  END IF;

  -- 2. Deduct Given Supplements (Ferrous Sulfate + Folic Acid, Calcium Carbonate, etc.)
  FOR v_med IN
    SELECT gm.*
    FROM public.given_medications gm
    WHERE gm.encounter_id = p_encounter_id
       OR (v_enc.mother_id IS NOT NULL AND gm.mother_id = v_enc.mother_id AND gm.date_given = COALESCE(v_enc.encounter_date::date, CURRENT_DATE))
       OR (v_pc.mother_id IS NOT NULL AND gm.mother_id = v_pc.mother_id AND gm.date_given = CURRENT_DATE)
  LOOP
    v_qty_needed := COALESCE(v_med.quantity, 0);
    IF v_qty_needed > 0 THEN
      -- Resolve Item ID
      SELECT item_id INTO v_item_id
      FROM public.inventory_items
      WHERE is_archived = false
        AND (
          (v_med.given_medication_name ILIKE '%ferrous%' AND (name ILIKE '%ferrous%' OR generic_name ILIKE '%iron%'))
          OR (v_med.given_medication_name ILIKE '%calcium%' AND (name ILIKE '%calcium%' OR generic_name ILIKE '%calcium%'))
          OR (name ILIKE '%' || v_med.given_medication_name || '%')
          OR (generic_name ILIKE '%' || v_med.given_medication_name || '%')
        )
      ORDER BY 
        CASE 
          WHEN name ILIKE '%' || v_med.given_medication_name || '%' THEN 1
          WHEN generic_name ILIKE '%' || v_med.given_medication_name || '%' THEN 2
          ELSE 3
        END
      LIMIT 1;

      IF v_item_id IS NOT NULL THEN
        -- Find FEFO active batch with sufficient quantity
        SELECT * INTO v_batch
        FROM public.inventory_batches
        WHERE item_id = v_item_id
          AND facility_id = v_facility_id
          AND status = 'active'
          AND quantity_remaining >= v_qty_needed
          AND expiration_date >= CURRENT_DATE
        ORDER BY expiration_date ASC, batch_id ASC
        LIMIT 1
        FOR UPDATE;

        IF FOUND THEN
          UPDATE public.inventory_batches
          SET quantity_remaining = quantity_remaining - v_qty_needed,
              status = CASE WHEN (quantity_remaining - v_qty_needed) <= 0 THEN 'depleted' ELSE 'active' END
          WHERE batch_id = v_batch.batch_id;

          UPDATE public.given_medications
          SET inventory_batch_id = v_batch.batch_id,
              facility_id = v_facility_id
          WHERE given_medication_id = v_med.given_medication_id;

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
            v_facility_id,
            'dispense',
            -v_qty_needed,
            'prenatal_encounter',
            p_encounter_id,
            'Dispensed ' || v_qty_needed || ' tabs of ' || v_med.given_medication_name || ' (Batch #' || v_batch.batch_number || ') for Prenatal Encounter #' || p_encounter_id,
            p_performed_by,
            NOW()
          );

          v_results := v_results || jsonb_build_object(
            'item_type', 'supplement',
            'medication', v_med.given_medication_name,
            'quantity', v_qty_needed,
            'batch_number', v_batch.batch_number,
            'remaining_stock', v_batch.quantity_remaining - v_qty_needed
          );
        ELSE
          -- Partial batch fallback: check if any stock exists
          SELECT * INTO v_batch
          FROM public.inventory_batches
          WHERE item_id = v_item_id
            AND facility_id = v_facility_id
            AND status = 'active'
            AND quantity_remaining > 0
            AND expiration_date >= CURRENT_DATE
          ORDER BY expiration_date ASC, batch_id ASC
          LIMIT 1
          FOR UPDATE;

          IF FOUND THEN
            DECLARE
              v_avail INTEGER := v_batch.quantity_remaining;
            BEGIN
              UPDATE public.inventory_batches
              SET quantity_remaining = 0,
                  status = 'depleted'
              WHERE batch_id = v_batch.batch_id;

              UPDATE public.given_medications
              SET inventory_batch_id = v_batch.batch_id,
                  facility_id = v_facility_id
              WHERE given_medication_id = v_med.given_medication_id;

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
                v_facility_id,
                'dispense',
                -v_avail,
                'prenatal_encounter',
                p_encounter_id,
                'Partial dispense: ' || v_avail || ' of ' || v_qty_needed || ' tabs ' || v_med.given_medication_name || ' (Batch #' || v_batch.batch_number || ') — Encounter #' || p_encounter_id,
                p_performed_by,
                NOW()
              );

              v_results := v_results || jsonb_build_object(
                'item_type', 'supplement',
                'medication', v_med.given_medication_name,
                'quantity', v_avail,
                'batch_number', v_batch.batch_number,
                'remaining_stock', 0,
                'note', 'Partial dispense (' || v_avail || ' of ' || v_qty_needed || ' available)'
              );
            END;
          ELSE
            v_warnings := v_warnings || to_jsonb('Insufficient stock at BHC for ' || v_med.given_medication_name || ' (' || v_qty_needed || ' tabs requested)'::text);
          END IF;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- 3. Deduct Maternal Td Vaccine (Multi-Dose per Unit Logic)
  IF p_deduct_td AND v_pc.td_vaccine_dose IS NOT NULL AND v_pc.td_vaccine_dose <> '' AND v_pc.td_vaccine_dose <> '-' AND v_pc.td_vaccine_dose <> 'none' THEN
    SELECT item_id, COALESCE(doses_per_unit, 10), COALESCE(open_vial_shelf_hours, 672)
    INTO v_td_item_id, v_td_dpu, v_shelf_hours
    FROM public.inventory_items
    WHERE (name ILIKE '%td%' OR name ILIKE '%tetanus%' OR generic_name ILIKE '%tetanus%')
      AND is_archived = false
    ORDER BY CASE WHEN name ILIKE 'td%' THEN 1 ELSE 2 END
    LIMIT 1;

    IF v_td_item_id IS NOT NULL THEN
      DECLARE
        v_td_found BOOLEAN := false;
      BEGIN
        -- Step 3A: Check for active Open Multi-Dose Vial at facility
        FOR v_batch IN
          SELECT *
          FROM public.inventory_batches
          WHERE item_id = v_td_item_id
            AND facility_id = v_facility_id
            AND status = 'active'
            AND expiration_date >= CURRENT_DATE
            AND doses_remaining_in_open_vial > 0
          ORDER BY expiration_date ASC, batch_id ASC
          FOR UPDATE
        LOOP
          -- Shelf-life validation (28 days / 672 hours)
          IF v_batch.vial_opened_at IS NOT NULL THEN
            v_hours_open := EXTRACT(EPOCH FROM (NOW() - v_batch.vial_opened_at)) / 3600;
            IF v_hours_open > v_shelf_hours THEN
              -- Discard expired open vial doses
              UPDATE public.inventory_batches
              SET doses_remaining_in_open_vial = 0,
                  open_vials_count = GREATEST(0, COALESCE(open_vials_count, 1) - 1),
                  vial_opened_at = NULL,
                  status = CASE WHEN quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
              WHERE batch_id = v_batch.batch_id;

              INSERT INTO public.inventory_transactions (
                batch_id, facility_id, transaction_type, quantity, reference_type, notes, performed_by, logged_at
              ) VALUES (
                v_batch.batch_id, v_facility_id, 'unusable', 0, 'open_vial_expired',
                'Discarded ' || v_batch.doses_remaining_in_open_vial || ' expired doses in open vial (Batch #' || v_batch.batch_number || ') >28d shelf limit',
                p_performed_by, NOW()
              );

              CONTINUE;
            END IF;
          END IF;

          -- Deduct 1 dose from open vial
          v_doses_left := v_batch.doses_remaining_in_open_vial - 1;
          UPDATE public.inventory_batches
          SET doses_remaining_in_open_vial = v_doses_left,
              open_vials_count = CASE WHEN v_doses_left = 0 THEN GREATEST(0, COALESCE(open_vials_count, 1) - 1) ELSE COALESCE(open_vials_count, 1) END,
              vial_opened_at = CASE WHEN v_doses_left = 0 THEN NULL ELSE COALESCE(v_batch.vial_opened_at, NOW()) END,
              status = CASE WHEN v_doses_left = 0 AND quantity_remaining <= 0 THEN 'depleted' ELSE 'active' END
          WHERE batch_id = v_batch.batch_id;

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
            v_facility_id,
            'dispense',
            0,
            'prenatal_encounter',
            p_encounter_id,
            'Deducted 1 dose from Open Vial (' || v_doses_left || ' doses left, Batch #' || v_batch.batch_number || ') for Maternal ' || v_pc.td_vaccine_dose || ' — Encounter #' || p_encounter_id,
            p_performed_by,
            NOW()
          );

          v_results := v_results || jsonb_build_object(
            'item_type', 'vaccine',
            'vaccine', 'Td Vaccine',
            'dose', v_pc.td_vaccine_dose,
            'mode', 'open_vial_dose',
            'batch_number', v_batch.batch_number,
            'doses_remaining_in_vial', v_doses_left
          );

          v_td_found := true;
          EXIT;
        END LOOP;

        -- Step 3B: If no open vial available, open 1 new sealed vial
        IF NOT v_td_found THEN
          SELECT * INTO v_batch
          FROM public.inventory_batches
          WHERE item_id = v_td_item_id
            AND facility_id = v_facility_id
            AND status = 'active'
            AND expiration_date >= CURRENT_DATE
            AND quantity_remaining > 0
          ORDER BY expiration_date ASC, batch_id ASC
          LIMIT 1
          FOR UPDATE;

          IF FOUND THEN
            v_doses_left := v_td_dpu - 1;
            UPDATE public.inventory_batches
            SET quantity_remaining = quantity_remaining - 1,
                open_vials_count = COALESCE(open_vials_count, 0) + 1,
                doses_remaining_in_open_vial = COALESCE(doses_remaining_in_open_vial, 0) + v_doses_left,
                vial_opened_at = NOW(),
                status = CASE WHEN (quantity_remaining - 1) <= 0 AND v_doses_left <= 0 THEN 'depleted' ELSE 'active' END
            WHERE batch_id = v_batch.batch_id;

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
              v_facility_id,
              'dispense',
              -1,
              'prenatal_encounter',
              p_encounter_id,
              'Opened sealed ' || v_td_dpu || '-dose vial (Batch #' || v_batch.batch_number || ', ' || v_doses_left || ' doses left in open vial) for Maternal ' || v_pc.td_vaccine_dose || ' — Encounter #' || p_encounter_id,
              p_performed_by,
              NOW()
            );

            v_results := v_results || jsonb_build_object(
              'item_type', 'vaccine',
              'vaccine', 'Td Vaccine',
              'dose', v_pc.td_vaccine_dose,
              'mode', 'new_sealed_vial_opened',
              'batch_number', v_batch.batch_number,
              'sealed_vials_left', v_batch.quantity_remaining - 1,
              'doses_remaining_in_vial', v_doses_left
            );

            v_td_found := true;
          ELSE
            v_warnings := v_warnings || to_jsonb('Td vaccine out of stock at BHC for Maternal ' || v_pc.td_vaccine_dose::text);
          END IF;
        END IF;
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'deductions', v_results,
    'warnings', v_warnings
  );
END;
$$;
