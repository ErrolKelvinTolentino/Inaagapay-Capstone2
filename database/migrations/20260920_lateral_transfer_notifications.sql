-- ===========================================================================
-- 20260920_lateral_transfer_notifications.sql
--
-- Strengthens notification dispatch and reference linking for lateral
-- BHC-to-BHC stock transfers under the same supervising RHU:
--
-- 1. Destination BHC:
--    - Clear, explicit title ('Incoming peer transfer from BHC') instead of
--      generic 'Incoming stocks'.
--    - Detailed message including issuing BHC name, item, quantity, and remarks.
--    - Explicit reference linking ('inventory_transfers', transfer_id).
--
-- 2. Source BHC:
--    - Dispatch confirmation alert ('Peer stock transfer dispatched').
--    - Does not silence the issuing midwife, so she has a confirmed log in
--      her notification feed.
--    - Receipt confirmation alert ('Peer transfer confirmed by destination')
--      when the receiving BHC accepts the shipment.
--
-- 3. Supervising RHU:
--    - Prominent lateral movement alert ('Peer Stock Transfer: BHC A → BHC B')
--      when dispatched.
--    - Completion notice ('Peer transfer completed: BHC A → BHC B') when
--      received.
--    - Includes reference_type = 'inventory_transfers' and reference_id so the
--      Admin Portal's Notification Center links directly to the transfer record.
-- ===========================================================================

-- 1. Updated announce_inventory_transfer() with explicit lateral transfer handling
CREATE OR REPLACE FUNCTION public.announce_inventory_transfer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_item_name   TEXT;
  v_source_id   BIGINT;
  v_source_name TEXT;
  v_dest_name   TEXT;
  v_direction   TEXT := COALESCE(NEW.transfer_direction, 'allocation');
  v_recipients  INTEGER := 0;
BEGIN
  SELECT i.name, b.facility_id
    INTO v_item_name, v_source_id
    FROM public.inventory_batches b
    JOIN public.inventory_items i ON i.item_id = b.item_id
   WHERE b.batch_id = NEW.source_batch_id;

  v_source_id   := COALESCE(NEW.source_facility_id, v_source_id);
  v_source_name := public.audit_facility_label(v_source_id);
  v_dest_name   := public.audit_facility_label(NEW.destination_facility_id);
  v_item_name   := COALESCE(v_item_name, 'stock');

  -- Destination facility notice:
  v_recipients := public.inventory_notify_facility(
    NEW.destination_facility_id,
    CASE v_direction
      WHEN 'lateral' THEN 'Incoming peer transfer from BHC'
      WHEN 'return'  THEN 'Stock returned to you'
      ELSE 'Incoming stocks'
    END,
    format('%s unit(s) of %s from %s are waiting for your receipt confirmation.%s%s',
           NEW.quantity_issued, v_item_name, v_source_name,
           CASE v_direction
             WHEN 'return'  THEN ' This is a return - confirm receipt promptly so the stock is usable again.'
             WHEN 'lateral' THEN ' This is a peer transfer from a neighbouring BHC.'
             ELSE ''
           END,
           CASE
             WHEN NEW.remarks IS NOT NULL AND TRIM(NEW.remarks) <> ''
             THEN ' ' || TRIM(NEW.remarks)
             ELSE ''
           END),
    true,
    NULL,
    'inventory_transfers',
    NEW.transfer_id
  );

  -- Source facility notice:
  -- Note: on lateral transfers, we do not exclude NEW.issued_by so the midwife
  -- who dispatched the shipment gets confirmation in her notification feed.
  PERFORM public.inventory_notify_facility(
    v_source_id,
    CASE v_direction
      WHEN 'lateral' THEN 'Peer stock transfer dispatched'
      ELSE 'Stock dispatched from your facility'
    END,
    format('%s unit(s) of %s were sent to %s (transfer #%s). Stock has left your count and is awaiting confirmation at %s.%s',
           NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id, v_dest_name,
           CASE
             WHEN NEW.remarks IS NOT NULL AND TRIM(NEW.remarks) <> ''
             THEN ' ' || TRIM(NEW.remarks)
             ELSE ''
           END),
    true,
    CASE WHEN v_direction = 'lateral' THEN NULL ELSE NEW.issued_by END,
    'inventory_transfers',
    NEW.transfer_id
  );

  -- Supervising RHU notification:
  IF v_direction IN ('lateral', 'external') THEN
    PERFORM public.inventory_notify_supervisor(
      v_source_id,
      format('Peer Stock Transfer: %s → %s', v_source_name, v_dest_name),
      format('%s dispatched %s unit(s) of %s to %s (transfer #%s).%s',
             v_source_name, NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id,
             CASE
               WHEN NEW.remarks IS NOT NULL AND TRIM(NEW.remarks) <> ''
               THEN ' ' || TRIM(NEW.remarks)
               ELSE ''
             END),
      NEW.issued_by,
      'inventory_transfers',
      NEW.transfer_id
    );
  END IF;

  -- Destination has no staff assigned:
  IF v_recipients = 0 THEN
    PERFORM public.inventory_notify_supervisor(
      NEW.destination_facility_id,
      'Incoming stocks have nobody to receive them',
      format('%s unit(s) of %s were sent to %s (transfer #%s), but no active account is assigned to that facility to confirm receipt.',
             NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id),
      NULL,
      'inventory_transfers',
      NEW.transfer_id
    );
  END IF;

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_announce_inventory_transfer ON public.inventory_transfers;
CREATE TRIGGER trg_announce_inventory_transfer
  AFTER INSERT ON public.inventory_transfers
  FOR EACH ROW EXECUTE FUNCTION public.announce_inventory_transfer();

GRANT EXECUTE ON FUNCTION public.announce_inventory_transfer() TO anon, authenticated;


-- 2. Updated receive_inventory_transfer() with reference IDs on completion notices
CREATE OR REPLACE FUNCTION public.receive_inventory_transfer(
  p_transfer_id BIGINT,
  p_received_by BIGINT
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_transfer             public.inventory_transfers%ROWTYPE;
  v_source               public.inventory_batches%ROWTYPE;
  v_destination_batch_id BIGINT;
  v_stock_location_id    BIGINT;
  v_actor_facility_id    BIGINT;
  v_item_name            TEXT;
  v_facility_name        TEXT;
  v_source_name          TEXT;
  v_direction            TEXT;
BEGIN
  v_actor_facility_id := public.inventory_actor_facility_id(p_received_by);

  IF v_actor_facility_id IS NULL THEN
    RAISE EXCEPTION 'An active midwife or portal account with an assigned facility is required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_transfer
  FROM public.inventory_transfers
  WHERE transfer_id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory transfer not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.inventory_same_place(v_transfer.destination_facility_id, v_actor_facility_id) THEN
    RAISE EXCEPTION 'This transfer belongs to another facility'
      USING ERRCODE = '42501';
  END IF;

  IF v_transfer.status = 'received' THEN
    RETURN v_transfer;
  END IF;
  IF v_transfer.status <> 'pending_receipt' THEN
    RAISE EXCEPTION 'Transfer cannot be received in its current status'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = v_transfer.source_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer source batch no longer exists' USING ERRCODE = 'P0002';
  END IF;
  IF v_source.expiration_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'The issued batch expired before receipt; contact the issuing office for resolution'
      USING ERRCODE = '22023';
  END IF;

  v_source_name := public.audit_facility_label(
                     COALESCE(v_transfer.source_facility_id, v_source.facility_id));
  v_direction   := COALESCE(v_transfer.transfer_direction,
                     public.inventory_transfer_direction(
                       COALESCE(v_transfer.source_facility_id, v_source.facility_id),
                       v_transfer.destination_facility_id));

  v_stock_location_id := public.inventory_stock_location_id(v_transfer.destination_facility_id);

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      v_source.item_id::text || ':' ||
      COALESCE(v_stock_location_id, 0)::text || ':' ||
      v_source.batch_number,
      0
    )
  );

  SELECT batch_id INTO v_destination_batch_id
  FROM public.inventory_batches
  WHERE item_id = v_source.item_id
    AND facility_id IS NOT DISTINCT FROM v_stock_location_id
    AND batch_number = v_source.batch_number
    AND status = 'active'
  ORDER BY batch_id
  LIMIT 1
  FOR UPDATE;

  IF v_destination_batch_id IS NULL THEN
    INSERT INTO public.inventory_batches (
      item_id, facility_id, batch_number, quantity_received, quantity_remaining,
      received_date, expiration_date, manufacturer, status
    ) VALUES (
      v_source.item_id,
      v_stock_location_id,
      v_source.batch_number,
      v_transfer.quantity_issued,
      v_transfer.quantity_issued,
      CURRENT_DATE,
      v_source.expiration_date,
      v_source.manufacturer,
      'active'
    )
    RETURNING batch_id INTO v_destination_batch_id;
  ELSE
    UPDATE public.inventory_batches
       SET quantity_received  = quantity_received  + v_transfer.quantity_issued,
           quantity_remaining = quantity_remaining + v_transfer.quantity_issued
     WHERE batch_id = v_destination_batch_id;
  END IF;

  INSERT INTO public.inventory_transactions (
    batch_id, facility_id, transaction_type, quantity, reference_type, reference_id, performed_by
  ) VALUES (
    v_destination_batch_id,
    v_stock_location_id,
    'transfer',
    v_transfer.quantity_issued,
    format('%s from %s',
           CASE v_direction
             WHEN 'return'  THEN 'Returned upward'
             WHEN 'lateral' THEN 'Received laterally'
             ELSE 'Received'
           END,
           COALESCE(v_source_name, 'the issuing office')),
    v_transfer.transfer_id,
    p_received_by
  );

  UPDATE public.inventory_transfers
     SET status = 'received',
         received_by = p_received_by,
         received_at = now(),
         destination_batch_id = v_destination_batch_id
   WHERE transfer_id = p_transfer_id
  RETURNING * INTO v_transfer;

  IF v_transfer.request_id IS NOT NULL THEN
    UPDATE public.inventory_stock_requests
       SET status = 'received'
     WHERE request_id = v_transfer.request_id;
  END IF;

  SELECT i.name INTO v_item_name
    FROM public.inventory_items i
   WHERE i.item_id = v_source.item_id;

  v_facility_name := public.audit_facility_label(v_transfer.destination_facility_id);

  -- Tell the sending facility (and its midwives) with reference link:
  PERFORM public.inventory_notify_facility(
    COALESCE(v_transfer.source_facility_id, v_source.facility_id),
    CASE v_direction
      WHEN 'lateral' THEN 'Peer transfer confirmed by destination'
      ELSE 'Transfer received'
    END,
    format('%s confirmed receipt of %s unit(s) of %s (transfer #%s). Transfer complete.',
           v_facility_name, v_transfer.quantity_issued,
           COALESCE(v_item_name, 'stock'), p_transfer_id),
    true,
    NULL,
    'inventory_transfers',
    p_transfer_id
  );

  -- Tell the supervising RHU office:
  PERFORM public.inventory_notify_supervisor(
    v_transfer.destination_facility_id,
    CASE v_direction
      WHEN 'lateral' THEN format('Peer transfer completed: %s → %s', COALESCE(v_source_name, 'Source BHC'), v_facility_name)
      ELSE 'Transfer received'
    END,
    format('%s confirmed receipt of %s unit(s) of %s from %s (transfer #%s).',
           v_facility_name, v_transfer.quantity_issued,
           COALESCE(v_item_name, 'stock'),
           COALESCE(v_source_name, 'another facility'), p_transfer_id),
    p_received_by,
    'inventory_transfers',
    p_transfer_id
  );

  RETURN v_transfer;
END
$fn$;

GRANT EXECUTE ON FUNCTION public.receive_inventory_transfer(BIGINT, BIGINT) TO anon, authenticated;
