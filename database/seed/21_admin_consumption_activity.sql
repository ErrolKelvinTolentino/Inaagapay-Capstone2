-- Fictional capstone activity for the previous and current calendar months.
-- Uses the existing dispensing RPC so balances and movement history agree.
-- Adds dedicated batches; preserves all other stock and patient records.
BEGIN;

DO $seed$
DECLARE
  v_tarcan public.health_facilities%ROWTYPE;
  v_fac RECORD;
  v_item RECORD;
  v_actor BIGINT;
  v_batch BIGINT;
  v_number TEXT;
  v_reference TEXT;
  v_result JSONB;
  v_month DATE := date_trunc('month', CURRENT_DATE)::date;
  v_previous DATE := (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date;
  v_day DATE;
  v_time TIME;
  v_units INTEGER;
  v_count INTEGER;
  v_doses INTEGER;
  v_n INTEGER;
  v_days INTEGER[] := ARRAY[1,3,5,8,10,12,17,19,22,24,26,28];
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('inaagapay-admin-defense-activity'));
  IF to_regprocedure('public.dispense_stock_doses(bigint,integer,bigint,text)') IS NULL THEN
    RAISE EXCEPTION 'Install the dose-aware inventory migrations before seeding activity.';
  END IF;
  SELECT * INTO v_tarcan FROM public.health_facilities
   WHERE facility_type = 'BHC' AND COALESCE(is_active, true)
     AND (lower(COALESCE(barangay,'')) = 'tarcan' OR name ILIKE '%tarcan%')
   ORDER BY facility_id LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'An active Tarcan BHC is required.'; END IF;
  SELECT account_id INTO v_actor FROM public.accounts
   WHERE status = 'active' AND account_type IN ('mho','admin')
     AND lower(email_address) NOT LIKE '%@qa.test'
   ORDER BY CASE WHEN account_type = 'mho' THEN 0 ELSE 1 END, account_id LIMIT 1;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'An active non-QA portal account is required.'; END IF;
  IF (SELECT count(*) FROM public.inventory_items
       WHERE NOT is_archived AND name IN ('Ferrous Sulfate + Folic Acid','Calcium Carbonate')
         AND doses_per_unit = 1) <> 2 THEN
    RAISE EXCEPTION 'The two standard single-unit supplement catalogue entries are required.';
  END IF;

  FOR v_fac IN
    SELECT f.* FROM public.health_facilities f
     WHERE f.facility_type = 'BHC' AND COALESCE(f.is_active, true)
       AND (f.facility_id = v_tarcan.facility_id
         OR (v_tarcan.parent_facility_id IS NOT NULL AND f.parent_facility_id = v_tarcan.parent_facility_id))
     ORDER BY (f.facility_id = v_tarcan.facility_id) DESC, f.facility_id LIMIT 3
  LOOP
    FOR v_item IN
      SELECT * FROM public.inventory_items WHERE NOT is_archived
       AND name IN ('Ferrous Sulfate + Folic Acid','Calcium Carbonate') ORDER BY item_id
    LOOP
      v_units := CASE WHEN v_item.name = 'Calcium Carbonate' THEN 800
        WHEN v_fac.facility_id = v_tarcan.facility_id THEN 2130 ELSE 1000 END;
      v_count := CASE WHEN v_item.name = 'Calcium Carbonate' THEN 10
        WHEN v_fac.facility_id = v_tarcan.facility_id THEN 30 ELSE 15 END;
      v_doses := CASE WHEN v_item.name = 'Ferrous Sulfate + Folic Acid'
        AND v_fac.facility_id = v_tarcan.facility_id THEN 60 ELSE 30 END;
      v_number := 'DEFENSE-' || to_char(v_month,'YYYYMM') || '-F' || v_fac.facility_id || '-I' || v_item.item_id;

      SELECT batch_id INTO v_batch FROM public.inventory_batches WHERE batch_number = v_number;
      IF v_batch IS NULL THEN
        INSERT INTO public.inventory_batches (item_id,facility_id,batch_number,
          quantity_received,quantity_remaining,received_date,expiration_date,manufacturer,status)
        VALUES (v_item.item_id,v_fac.facility_id,v_number,v_units,v_units,
          v_previous-1,(v_month+INTERVAL '1 year')::date,'Capstone demonstration supply','active')
        RETURNING batch_id INTO v_batch;
        INSERT INTO public.inventory_transactions (batch_id,facility_id,transaction_type,
          quantity,dose_quantity,reference_type,reference_id,notes,performed_by,
          resulting_quantity_remaining,resulting_open_vial_doses,logged_at)
        VALUES (v_batch,v_fac.facility_id,'receipt',v_units,v_units,'Defense demo receipt',v_batch,
          'Fictional capstone batch. Opening supply before recorded demonstration dispensing.',v_actor,
          v_units,0,((v_previous-1)+TIME '09:00') AT TIME ZONE 'Asia/Manila');
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.inventory_batches WHERE batch_id=v_batch
        AND item_id=v_item.item_id AND facility_id=v_fac.facility_id) THEN
        RAISE EXCEPTION 'The existing defense batch % has different item/facility ownership.',v_number;
      END IF;

      -- Tarcan iron: six 60-unit records on day 15; two on each of twelve
      -- other dates. Other scopes have different recorded volumes.
      FOR v_n IN 1..v_count LOOP
        v_day := v_previous + CASE WHEN v_count=30 THEN
          CASE WHEN v_n>24 THEN 14 ELSE v_days[((v_n-1)/2)+1]-1 END
          ELSE v_n-1 END;
        v_time := CASE v_n%5 WHEN 0 THEN TIME '13:00' WHEN 1 THEN TIME '08:30'
          WHEN 2 THEN TIME '09:00' WHEN 3 THEN TIME '09:30' ELSE TIME '10:00' END;
        v_reference := 'Defense demo ' || v_number || ' previous-' || v_n;
        IF NOT EXISTS (SELECT 1 FROM public.inventory_transactions
          WHERE batch_id=v_batch AND transaction_type='dispense' AND reference_type=v_reference) THEN
          v_result := public.dispense_stock_doses(v_batch,v_doses,v_actor,v_reference);
          IF COALESCE((v_result->>'success')::boolean,false) IS NOT TRUE THEN
            RAISE EXCEPTION 'Defense dispense failed: %',v_result;
          END IF;
          UPDATE public.inventory_transactions
             SET logged_at=(v_day+v_time) AT TIME ZONE 'Asia/Manila',
                 notes=notes || '. Fictional capstone activity; no patient visit is asserted.'
           WHERE batch_id=v_batch AND transaction_type='dispense' AND reference_type=v_reference;
        END IF;
      END LOOP;

      -- Never write future activity. Rehearsal on October 7 records Oct 1, 2
      -- and 6; the same seed works against the actual calendar when rerun.
      FOREACH v_n IN ARRAY ARRAY[1,2,6] LOOP
        v_day := v_month+v_n-1;
        IF v_day>=CURRENT_DATE THEN CONTINUE; END IF;
        v_reference := 'Defense demo ' || v_number || ' current-' || v_n;
        IF NOT EXISTS (SELECT 1 FROM public.inventory_transactions
          WHERE batch_id=v_batch AND transaction_type='dispense' AND reference_type=v_reference) THEN
          v_result := public.dispense_stock_doses(v_batch,v_doses,v_actor,v_reference);
          IF COALESCE((v_result->>'success')::boolean,false) IS NOT TRUE THEN
            RAISE EXCEPTION 'Defense dispense failed: %',v_result;
          END IF;
          UPDATE public.inventory_transactions
             SET logged_at=(v_day+TIME '09:00') AT TIME ZONE 'Asia/Manila',
                 notes=notes || '. Fictional capstone activity; no patient visit is asserted.'
           WHERE batch_id=v_batch AND transaction_type='dispense' AND reference_type=v_reference;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END;
$seed$;

COMMIT;

-- Confirm receipts - dispenses = remaining for the new batches only.
SELECT f.name AS facility,i.name AS item,b.batch_number,b.quantity_received,
  b.quantity_remaining,COALESCE(sum(t.quantity),0) AS ledger_balance,
  count(*) FILTER (WHERE t.transaction_type='dispense') AS dispensing_records
 FROM public.inventory_batches b
 JOIN public.inventory_items i USING (item_id)
 JOIN public.health_facilities f USING (facility_id)
 LEFT JOIN public.inventory_transactions t USING (batch_id)
 WHERE b.batch_number LIKE 'DEFENSE-' || to_char(CURRENT_DATE,'YYYYMM') || '-%'
 GROUP BY f.name,i.name,b.batch_number,b.quantity_received,b.quantity_remaining
 ORDER BY f.name,i.name;
