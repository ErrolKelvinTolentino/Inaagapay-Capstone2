-- ====================================================================
-- InaAgapay Migration: Advanced Clinical Inventory Features
-- 
-- 1. Open vial shelf-life tracking & auto-expiry rules (6h for BCG/MR, 28d for Td/OPV)
-- 2. DOH Wastage rate computation & open vial discard procedure
-- 3. Inter-BHC stock transfers (BHC-to-BHC emergency sharing)
-- 4. Predictive 30-day demand forecast per BHC
-- ====================================================================

BEGIN;

-- 1. Open Vial Expiry Schema Enhancements
ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS vial_opened_at TIMESTAMPTZ;

ALTER TABLE public.inventory_items
  ADD COLUMN IF NOT EXISTS open_vial_shelf_hours INTEGER DEFAULT 6;

-- Configure DOH Standard Open Vial Shelf Life
-- Reconstituted vaccines: 6 hours
UPDATE public.inventory_items
SET open_vial_shelf_hours = 6
WHERE name ILIKE '%bcg%' OR name ILIKE '%mr%' OR name ILIKE '%mmr%' OR name ILIKE '%measles%';

-- Liquid multi-dose vaccines (kept in cold chain): 28 days (672 hours)
UPDATE public.inventory_items
SET open_vial_shelf_hours = 672
WHERE name ILIKE '%td%' OR name ILIKE '%tetanus%' OR name ILIKE '%opv%' OR name ILIKE '%hepb%' OR name ILIKE '%hep b%';

-- Single-dose and solid supplements: 0 (no open-vial timer)
UPDATE public.inventory_items
SET open_vial_shelf_hours = 0
WHERE doses_per_unit = 1 OR item_type = 'supplement' OR item_type = 'medical_device';

-- 2. Open Vial Discard Procedure
CREATE OR REPLACE FUNCTION public.discard_open_vial_doses(
  p_batch_id BIGINT,
  p_discarded_by BIGINT,
  p_reason TEXT DEFAULT 'Open vial exceeded maximum shelf-life limit'
) RETURNS jsonb AS $$
DECLARE
  v_batch public.inventory_batches%ROWTYPE;
  v_item public.inventory_items%ROWTYPE;
  v_doses_wasted INTEGER;
BEGIN
  SELECT * INTO v_batch
  FROM public.inventory_batches
  WHERE batch_id = p_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Batch not found');
  END IF;

  v_doses_wasted := COALESCE(v_batch.doses_remaining_in_open_vial, 0);

  IF v_doses_wasted <= 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'No open vial doses remaining in this batch');
  END IF;

  SELECT * INTO v_item
  FROM public.inventory_items
  WHERE item_id = v_batch.item_id;

  -- Zero out open vial doses
  UPDATE public.inventory_batches
  SET doses_remaining_in_open_vial = 0,
      open_vials_count = 0,
      vial_opened_at = NULL
  WHERE batch_id = p_batch_id;

  -- Log discard transaction
  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
    reference_type,
    performed_by,
    logged_at
  ) VALUES (
    p_batch_id,
    v_batch.facility_id,
    'discard',
    -v_doses_wasted,
    'Discarded ' || v_doses_wasted || ' open dose(s) of ' || COALESCE(v_item.name, 'Vaccine') || ' — Reason: ' || COALESCE(p_reason, 'Expired open vial'),
    p_discarded_by,
    NOW()
  );

  RETURN jsonb_build_object(
    'success', true,
    'batch_id', p_batch_id,
    'doses_discarded', v_doses_wasted,
    'message', 'Successfully discarded ' || v_doses_wasted || ' open doses'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Upgrade deduct_immunization_stock to enforce open vial time limits
CREATE OR REPLACE FUNCTION public.deduct_immunization_stock(
  p_immunization_record_id BIGINT
) RETURNS jsonb AS $$
DECLARE
  v_rec RECORD;
  v_inv_item RECORD;
  v_batch RECORD;
  v_doses_per_unit INTEGER := 1;
  v_shelf_hours INTEGER := 6;
  v_facility_id BIGINT;
  v_hours_open NUMERIC;
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
  v_shelf_hours := COALESCE(v_inv_item.open_vial_shelf_hours, 6);

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
      -- Check if open vial has expired its shelf hours
      IF v_shelf_hours > 0 AND v_batch.vial_opened_at IS NOT NULL THEN
        v_hours_open := EXTRACT(EPOCH FROM (NOW() - v_batch.vial_opened_at)) / 3600.0;
        IF v_hours_open > v_shelf_hours THEN
          -- Auto-discard expired open doses
          PERFORM public.discard_open_vial_doses(
            v_batch.batch_id,
            v_rec.administered_by,
            'Auto-expired open vial (' || ROUND(v_hours_open, 1) || ' hrs open, limit ' || v_shelf_hours || ' hrs)'
          );
          v_batch := NULL; -- Force opening a new sealed vial
        END IF;
      END IF;

      IF v_batch IS NOT NULL THEN
        -- Use 1 dose from open vial
        UPDATE public.inventory_batches
        SET doses_remaining_in_open_vial = doses_remaining_in_open_vial - 1,
            open_vials_count = CASE WHEN (doses_remaining_in_open_vial - 1) = 0 THEN GREATEST(0, open_vials_count - 1) ELSE open_vials_count END,
            vial_opened_at = CASE WHEN (doses_remaining_in_open_vial - 1) = 0 THEN NULL ELSE vial_opened_at END
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
        doses_remaining_in_open_vial = doses_remaining_in_open_vial + (v_doses_per_unit - 1),
        vial_opened_at = NOW()
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

-- 4. Upgrade issue_inventory_transfer for Inter-BHC Stock Sharing
DROP FUNCTION IF EXISTS public.issue_inventory_transfer(BIGINT, BIGINT, BIGINT, INTEGER, BIGINT, TEXT);
DROP FUNCTION IF EXISTS public.issue_inventory_transfer(BIGINT, BIGINT, INTEGER, BIGINT, BIGINT, TEXT);

CREATE OR REPLACE FUNCTION public.issue_inventory_transfer(
  p_source_batch_id BIGINT,
  p_destination_facility_id BIGINT,
  p_quantity INTEGER,
  p_issued_by BIGINT,
  p_request_id BIGINT DEFAULT NULL,
  p_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source public.inventory_batches%ROWTYPE;
  v_request public.inventory_stock_requests%ROWTYPE;
  v_transfer public.inventory_transfers%ROWTYPE;
  v_item_name TEXT;
  v_dest_name TEXT;
  v_src_name TEXT := 'Central Warehouse';
  v_expected_quantity INTEGER;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Issue quantity must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = p_source_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source batch not found' USING ERRCODE = 'P0002';
  END IF;

  -- Allow source to be Central (facility_id IS NULL) OR a source BHC (facility_id <> destination)
  IF v_source.facility_id IS NOT NULL AND v_source.facility_id = p_destination_facility_id THEN
    RAISE EXCEPTION 'Source and destination facility cannot be the same'
      USING ERRCODE = '22023';
  END IF;

  IF v_source.status <> 'active' OR v_source.expiration_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Source batch is not active and usable'
      USING ERRCODE = '22023';
  END IF;

  IF v_source.quantity_remaining < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock in source batch: only % available',
      v_source.quantity_remaining USING ERRCODE = '22023';
  END IF;

  SELECT name INTO v_dest_name
  FROM public.health_facilities
  WHERE facility_id = p_destination_facility_id;

  IF v_dest_name IS NULL THEN
    RAISE EXCEPTION 'Destination facility not found' USING ERRCODE = '23503';
  END IF;

  IF v_source.facility_id IS NOT NULL THEN
    SELECT name INTO v_src_name
    FROM public.health_facilities
    WHERE facility_id = v_source.facility_id;
  END IF;

  IF p_request_id IS NOT NULL THEN
    SELECT * INTO v_request
    FROM public.inventory_stock_requests
    WHERE request_id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Linked stock request not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_request.status <> 'approved' THEN
      RAISE EXCEPTION 'Only approved requests can be issued'
        USING ERRCODE = '22023';
    END IF;
    IF v_request.facility_id <> p_destination_facility_id
       OR v_request.item_id <> v_source.item_id THEN
      RAISE EXCEPTION 'Batch item or destination does not match the stock request'
        USING ERRCODE = '22023';
    END IF;

    v_expected_quantity := coalesce(v_request.approved_quantity,
                                    v_request.requested_quantity);

    IF p_quantity <> v_expected_quantity THEN
      RAISE EXCEPTION 'A linked request must be issued in its approved quantity (%)',
        v_expected_quantity
        USING ERRCODE = '22023';
    END IF;
  END IF;

  INSERT INTO public.inventory_transfers (
    request_id,
    source_batch_id,
    destination_facility_id,
    quantity_issued,
    status,
    remarks,
    issued_by
  ) VALUES (
    p_request_id,
    p_source_batch_id,
    p_destination_facility_id,
    p_quantity,
    'pending_receipt',
    nullif(btrim(coalesce(p_remarks, '')), ''),
    p_issued_by
  )
  RETURNING * INTO v_transfer;

  -- Decrement stock from source batch
  UPDATE public.inventory_batches
  SET quantity_remaining = quantity_remaining - p_quantity
  WHERE batch_id = p_source_batch_id;

  SELECT name INTO v_item_name
  FROM public.inventory_items
  WHERE item_id = v_source.item_id;

  -- Log dispatch transaction
  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
    reference_type,
    reference_id,
    performed_by
  ) VALUES (
    p_source_batch_id,
    v_source.facility_id,
    'transfer',
    -p_quantity,
    'Issued to ' || v_dest_name || ' — pending receipt',
    v_transfer.transfer_id,
    p_issued_by
  );

  IF p_request_id IS NOT NULL THEN
    UPDATE public.inventory_stock_requests
    SET status = 'issued',
        updated_at = NOW()
    WHERE request_id = p_request_id;
  END IF;

  RETURN v_transfer;
END;
$$;

-- 5. Predictive 30-Day Demand Forecast RPC per BHC
CREATE OR REPLACE FUNCTION public.get_bhc_monthly_demand_forecast(
  p_facility_id BIGINT DEFAULT NULL
)
RETURNS TABLE (
  facility_id BIGINT,
  facility_name TEXT,
  item_id BIGINT,
  item_name TEXT,
  item_type TEXT,
  unit_of_measure TEXT,
  doses_per_unit INTEGER,
  target_patients_count BIGINT,
  forecasted_dose_demand BIGINT,
  forecasted_unit_demand BIGINT,
  current_usable_stock BIGINT,
  recommended_transfer_units BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH target_facilities AS (
    SELECT f.facility_id AS f_id, f.name::TEXT AS f_name, f.barangay::TEXT AS f_brgy
    FROM public.health_facilities f
    WHERE (p_facility_id IS NULL OR f.facility_id = p_facility_id)
      AND f.facility_type = 'BHC'
  ),
  mothers_per_facility AS (
    SELECT 
      tf.f_id,
      GREATEST(10, COUNT(DISTINCT m.mother_id))::BIGINT AS active_mothers
    FROM target_facilities tf
    LEFT JOIN public.facility_assignments fa ON fa.facility_id = tf.f_id AND fa.is_active = true
    LEFT JOIN public.mothers m ON (
      m.account_id = fa.account_id 
      OR (m.barangay IS NOT NULL AND (tf.f_brgy ILIKE '%' || m.barangay || '%' OR m.barangay ILIKE '%' || tf.f_brgy || '%'))
    )
    GROUP BY tf.f_id
  ),
  infants_per_facility AS (
    SELECT 
      tf.f_id,
      GREATEST(15, COUNT(DISTINCT c.child_id))::BIGINT AS active_infants
    FROM target_facilities tf
    LEFT JOIN public.facility_assignments fa ON fa.facility_id = tf.f_id AND fa.is_active = true
    LEFT JOIN public.mothers m ON (
      m.account_id = fa.account_id 
      OR (m.barangay IS NOT NULL AND (tf.f_brgy ILIKE '%' || m.barangay || '%' OR m.barangay ILIKE '%' || tf.f_brgy || '%'))
    )
    LEFT JOIN public.children c ON c.mother_id = m.mother_id
    GROUP BY tf.f_id
  ),
  items_catalog AS (
    SELECT i.item_id AS i_id, i.name::TEXT AS i_name, i.item_type::TEXT AS i_type, 
           i.unit_of_measure::TEXT AS i_uom, COALESCE(i.doses_per_unit, 1)::INTEGER AS i_dpu
    FROM public.inventory_items i
    WHERE NOT COALESCE(i.is_archived, false)
  ),
  current_stocks AS (
    SELECT b.facility_id AS f_id, b.item_id AS i_id, 
           COALESCE(SUM(b.quantity_remaining), 0)::BIGINT AS stock_qty
    FROM public.inventory_batches b
    WHERE b.status = 'active' AND b.expiration_date >= CURRENT_DATE
    GROUP BY b.facility_id, b.item_id
  )
  SELECT 
    tf.f_id AS facility_id,
    tf.f_name AS facility_name,
    ic.i_id AS item_id,
    ic.i_name AS item_name,
    ic.i_type AS item_type,
    ic.i_uom AS unit_of_measure,
    ic.i_dpu AS doses_per_unit,
    CASE 
      WHEN ic.i_type = 'vaccine' THEN COALESCE(inf.active_infants, 15)
      ELSE COALESCE(moth.active_mothers, 10)
    END::BIGINT AS target_patients_count,
    -- Forecasted Doses: ~1 dose per child for vaccines, ~30 tablets/month for prenatal supplements
    CASE 
      WHEN ic.i_type = 'vaccine' THEN COALESCE(inf.active_infants, 15)
      WHEN ic.i_name ILIKE '%ferrous%' OR ic.i_name ILIKE '%calcium%' THEN COALESCE(moth.active_mothers, 10) * 30
      ELSE COALESCE(moth.active_mothers, 10)
    END::BIGINT AS forecasted_dose_demand,
    -- Forecasted Units: ceiling(doses / doses_per_unit) + 20% safety buffer
    CEIL(
      (CASE 
        WHEN ic.i_type = 'vaccine' THEN COALESCE(inf.active_infants, 15)
        WHEN ic.i_name ILIKE '%ferrous%' OR ic.i_name ILIKE '%calcium%' THEN COALESCE(moth.active_mothers, 10) * 30
        ELSE COALESCE(moth.active_mothers, 10)
      END * 1.2) / ic.i_dpu
    )::BIGINT AS forecasted_unit_demand,
    COALESCE(cs.stock_qty, 0)::BIGINT AS current_usable_stock,
    -- Recommended Transfer = GREATEST(0, forecasted_unit_demand - current_usable_stock)
    GREATEST(
      0,
      CEIL(
        (CASE 
          WHEN ic.i_type = 'vaccine' THEN COALESCE(inf.active_infants, 15)
          WHEN ic.i_name ILIKE '%ferrous%' OR ic.i_name ILIKE '%calcium%' THEN COALESCE(moth.active_mothers, 10) * 30
          ELSE COALESCE(moth.active_mothers, 10)
        END * 1.2) / ic.i_dpu
      ) - COALESCE(cs.stock_qty, 0)
    )::BIGINT AS recommended_transfer_units
  FROM target_facilities tf
  CROSS JOIN items_catalog ic
  LEFT JOIN mothers_per_facility moth ON moth.f_id = tf.f_id
  LEFT JOIN infants_per_facility inf ON inf.f_id = tf.f_id
  LEFT JOIN current_stocks cs ON cs.f_id = tf.f_id AND cs.i_id = ic.i_id
  ORDER BY tf.f_name, ic.i_type, ic.i_name;
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.issue_inventory_transfer(BIGINT, BIGINT, INTEGER, BIGINT, BIGINT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_open_vial_puncture(BIGINT, BIGINT, NUMERIC, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.discard_open_vial_waste(BIGINT, BIGINT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_bhc_monthly_demand_forecast(BIGINT) TO authenticated, service_role;

COMMIT;
