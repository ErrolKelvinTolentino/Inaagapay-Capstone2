-- InaAgapay transfer delivery-plan updates
--
-- Lets an RHU administrator revise the expected arrival and record a delivery
-- situation while stock is still in transit. The transfer quantity, batch,
-- destination, and receipt status remain immutable through this function.

BEGIN;

CREATE OR REPLACE FUNCTION public.update_inventory_transfer_delivery(
  p_transfer_id BIGINT,
  p_expected_arrival_date DATE,
  p_situation TEXT,
  p_note TEXT,
  p_updated_by BIGINT
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_before public.inventory_transfers%ROWTYPE;
  v_after public.inventory_transfers%ROWTYPE;
  v_source public.inventory_batches%ROWTYPE;
  v_item_name TEXT;
  v_facility_name TEXT;
  v_situation TEXT := lower(btrim(coalesce(p_situation, '')));
  v_situation_label TEXT;
  v_note TEXT;
  v_reference TEXT;
  v_delivery_plan TEXT;
  v_delivery_update TEXT;
  v_plan_days INTEGER;
  v_shelf_days INTEGER;
BEGIN
  PERFORM public.inventory_assert_actor(p_updated_by, 'admin');

  IF p_expected_arrival_date IS NULL OR p_expected_arrival_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Expected arrival must be today or a future date'
      USING ERRCODE = '22023';
  END IF;

  IF v_situation NOT IN (
    'on_schedule',
    'delayed',
    'rescheduled',
    'transport_issue',
    'facility_coordination',
    'other'
  ) THEN
    RAISE EXCEPTION 'Select a valid delivery situation'
      USING ERRCODE = '22023';
  END IF;

  IF char_length(btrim(coalesce(p_note, ''))) > 500 THEN
    RAISE EXCEPTION 'Delivery note must be 500 characters or fewer'
      USING ERRCODE = '22023';
  END IF;

  -- Keep notification and audit text compact even if a textarea contains
  -- multiple lines or repeated spaces.
  v_note := nullif(
    regexp_replace(btrim(coalesce(p_note, '')), '[[:space:]]+', ' ', 'g'),
    ''
  );

  SELECT * INTO v_before
  FROM public.inventory_transfers
  WHERE transfer_id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory transfer not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_before.status <> 'pending_receipt' THEN
    RAISE EXCEPTION 'Only a transfer awaiting receipt can be updated'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = v_before.source_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer source batch no longer exists'
      USING ERRCODE = 'P0002';
  END IF;

  v_plan_days := GREATEST(0, p_expected_arrival_date - v_before.issued_at::date);
  v_shelf_days := v_source.expiration_date - p_expected_arrival_date;

  IF (v_situation <> 'on_schedule' OR v_shelf_days <= 0) AND v_note IS NULL THEN
    RAISE EXCEPTION 'Add a note explaining this delivery change'
      USING ERRCODE = '22023';
  END IF;

  v_situation_label := CASE v_situation
    WHEN 'on_schedule' THEN 'On schedule'
    WHEN 'delayed' THEN 'Delayed'
    WHEN 'rescheduled' THEN 'Rescheduled'
    WHEN 'transport_issue' THEN 'Transport issue'
    WHEN 'facility_coordination' THEN 'Facility coordination'
    ELSE 'Other situation'
  END;

  -- Remove the machine-readable plan and the previous update while preserving
  -- any original reference entered when the stock was sent.
  v_reference := regexp_replace(
    coalesce(v_before.remarks, ''),
    E'Delivery plan:[[:space:]]*expected[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*\\([0-9]+-day estimate\\)(;[[:space:]]*batch expires[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2};[[:space:]]*-?[0-9]+[[:space:]]*days? of shelf life at arrival)?\\.?',
    '',
    'gi'
  );
  v_reference := regexp_replace(
    v_reference,
    '[[:space:]]*Delivery update:.*$',
    '',
    'i'
  );
  v_reference := nullif(btrim(v_reference), '');

  v_delivery_plan := format(
    'Delivery plan: expected %s (%s-day estimate); batch expires %s; %s day%s of shelf life at arrival.',
    p_expected_arrival_date,
    v_plan_days,
    v_source.expiration_date,
    v_shelf_days,
    CASE WHEN abs(v_shelf_days) = 1 THEN '' ELSE 's' END
  );
  v_delivery_update := format(
    'Delivery update: %s on %s. %s',
    v_situation_label,
    CURRENT_DATE,
    coalesce(v_note, 'Expected arrival confirmed.')
  );

  UPDATE public.inventory_transfers
  SET remarks = concat_ws(E'\n', v_reference, v_delivery_plan, v_delivery_update)
  WHERE transfer_id = p_transfer_id
  RETURNING * INTO v_after;

  SELECT i.name, hf.name
    INTO v_item_name, v_facility_name
  FROM public.inventory_items i
  CROSS JOIN public.health_facilities hf
  WHERE i.item_id = v_source.item_id
    AND hf.facility_id = v_before.destination_facility_id;

  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT
    m.account_id,
    'Delivery plan updated',
    format(
      'Transfer #%s for %s is now expected on %s. %s%s',
      p_transfer_id,
      coalesce(v_item_name, 'inventory stock'),
      p_expected_arrival_date,
      v_situation_label,
      CASE WHEN v_note IS NULL THEN '.' ELSE ': ' || v_note END
    ),
    'general'
  FROM public.midwives m
  JOIN public.health_facilities hf ON hf.facility_id = m.assigned_bhc_id
  JOIN public.accounts a ON a.account_id = m.account_id
  WHERE hf.facility_id = v_before.destination_facility_id
    AND a.status = 'active';

  INSERT INTO public.audit_trail (
    account_id,
    action,
    table_name,
    description,
    old_data,
    new_data
  ) VALUES (
    p_updated_by,
    'update_inventory_transfer_delivery',
    'inventory_transfers',
    format(
      'Updated delivery plan for transfer #%s to %s: %s, expected %s',
      p_transfer_id,
      coalesce(v_facility_name, 'health center'),
      v_situation_label,
      p_expected_arrival_date
    ),
    to_jsonb(v_before),
    to_jsonb(v_after)
  );

  RETURN v_after;
END;
$$;

REVOKE ALL ON FUNCTION public.update_inventory_transfer_delivery(
  BIGINT, DATE, TEXT, TEXT, BIGINT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.update_inventory_transfer_delivery(
  BIGINT, DATE, TEXT, TEXT, BIGINT
) TO anon, authenticated;

COMMENT ON FUNCTION public.update_inventory_transfer_delivery(
  BIGINT, DATE, TEXT, TEXT, BIGINT
) IS 'Admin-only update of the expected arrival and delivery situation for an in-transit inventory transfer.';

COMMIT;
