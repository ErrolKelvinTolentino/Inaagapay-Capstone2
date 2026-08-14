-- ====================================================================
-- InaAgapay Migration: Link Child Vaccinations with Inventory Management
-- ====================================================================

-- 1. Add Foreign Key linking clinical vaccines table to physical inventory catalog
ALTER TABLE public.vaccines 
ADD COLUMN IF NOT EXISTS inventory_item_id BIGINT REFERENCES public.inventory_items(item_id) ON DELETE SET NULL;

-- 2. Add administration context & inventory tracking to immunization_records
ALTER TABLE public.immunization_records 
ADD COLUMN IF NOT EXISTS administration_place VARCHAR(30) DEFAULT 'local_facility' 
  CHECK (administration_place IN ('local_facility', 'external_facility')),
ADD COLUMN IF NOT EXISTS facility_id BIGINT REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS inventory_batch_id BIGINT REFERENCES public.inventory_batches(batch_id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS inventory_deducted BOOLEAN DEFAULT false;

-- 3. Map clinical vaccine items to physical DOH inventory items catalog
UPDATE public.vaccines v
SET inventory_item_id = i.item_id
FROM public.inventory_items i
WHERE (v.vaccine_name ILIKE '%bcg%' AND i.name ILIKE '%bcg%')
   OR (v.vaccine_name ILIKE '%penta%' AND i.name ILIKE '%penta%')
   OR (v.vaccine_name ILIKE '%pcv%' AND i.name ILIKE '%pcv%')
   OR (v.vaccine_name ILIKE '%opv%' AND i.name ILIKE '%opv%')
   OR (v.vaccine_name ILIKE '%measles%' AND (i.name ILIKE '%mr%' OR i.name ILIKE '%measles%'))
   OR (v.vaccine_name ILIKE '%mmr%' AND (i.name ILIKE '%mr%' OR i.name ILIKE '%mmr%'))
   OR (v.vaccine_name ILIKE '%rotavirus%' AND i.name ILIKE '%rotavirus%');

-- 4. Stored Procedure for Automatic FEFO Stock Deduction
CREATE OR REPLACE FUNCTION public.deduct_immunization_stock(
  p_immunization_record_id BIGINT
) RETURNS jsonb AS $$
DECLARE
  v_rec RECORD;
  v_inv_item_id BIGINT;
  v_selected_batch RECORD;
BEGIN
  -- Fetch immunization record details
  SELECT ir.*, v.inventory_item_id, m.assigned_bhc_id
  INTO v_rec
  FROM immunization_records ir
  JOIN vaccines v ON v.vaccine_id = ir.vaccine_id
  LEFT JOIN midwives m ON m.midwife_id = ir.administered_by
  WHERE ir.immunization_record_id = p_immunization_record_id;

  IF v_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Record not found');
  END IF;

  -- Skip if external facility or already deducted
  IF v_rec.administration_place = 'external_facility' OR v_rec.inventory_deducted = true THEN
    RETURN jsonb_build_object('success', true, 'message', 'No stock deduction required');
  END IF;

  -- Determine facility ID
  v_rec.facility_id := COALESCE(v_rec.facility_id, v_rec.assigned_bhc_id, 1);
  v_inv_item_id := v_rec.inventory_item_id;

  IF v_inv_item_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Vaccine item not mapped in catalog');
  END IF;

  -- Find active batch at facility expiring earliest (FEFO)
  SELECT * INTO v_selected_batch
  FROM inventory_batches
  WHERE item_id = v_inv_item_id
    AND (facility_id = v_rec.facility_id OR (facility_id IS NULL AND v_rec.facility_id IS NULL))
    AND status = 'active'
    AND quantity_remaining > 0
    AND expiration_date >= CURRENT_DATE
  ORDER BY expiration_date ASC
  LIMIT 1;

  IF v_selected_batch IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Out of stock at facility');
  END IF;

  -- Decrement stock by 1 dose
  UPDATE inventory_batches
  SET quantity_remaining = quantity_remaining - 1
  WHERE batch_id = v_selected_batch.batch_id;

  -- Log audit transaction ledger entry
  INSERT INTO inventory_transactions (
    batch_id, facility_id, transaction_type, quantity, reference_type, logged_at
  ) VALUES (
    v_selected_batch.batch_id,
    v_rec.facility_id,
    'dispense',
    -1,
    'Auto-dispensed for Child Immunization Record #' || p_immunization_record_id,
    NOW()
  );

  -- Update record with batch reference and status
  UPDATE immunization_records
  SET inventory_batch_id = v_selected_batch.batch_id,
      facility_id = v_rec.facility_id,
      inventory_deducted = true
  WHERE immunization_record_id = p_immunization_record_id;

  RETURN jsonb_build_object('success', true, 'batch_number', v_selected_batch.batch_number);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
