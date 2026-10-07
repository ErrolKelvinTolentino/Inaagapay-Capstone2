-- Manual acknowledgement for admin dispensing. No scheduler or automatic
-- write-off. Existing signatures and execution permissions are retained.
-- Requires the 20260831 dose presentation/dispensing implementation.
BEGIN;

DO $migration$
DECLARE
  v_function REGPROCEDURE := to_regprocedure('public.dispense_stock_doses(bigint,integer,bigint,text)');
  v_definition TEXT;
  v_anchor TEXT := '  v_actor       := public.resolve_actor_account_id(p_actor);';
  v_guard TEXT := $guard$
  -- MANUAL_OPEN_VIAL_DISPOSAL_REQUIRED
  -- The batch was locked above. Refuse the entire batch until the officer
  -- explicitly records the open-dose discard, including its reason/witness.
  IF COALESCE(v_batch.doses_remaining_in_open_vial, 0) > 0
     AND (v_batch.expiration_date <= CURRENT_DATE
       OR (v_shelf_hours > 0 AND (v_batch.vial_opened_at IS NULL
         OR v_batch.vial_opened_at + make_interval(hours => v_shelf_hours) <= NOW()))) THEN
    RETURN jsonb_build_object('success', false, 'code', 'OPEN_VIAL_DISPOSAL_REQUIRED',
      'error', 'Record disposal of the spoiled open doses before dispensing from batch ' || v_batch.batch_number,
      'batch_id', p_batch_id);
  END IF;

  v_actor       := public.resolve_actor_account_id(p_actor);$guard$;
BEGIN
  IF v_function IS NULL THEN RAISE EXCEPTION 'Install the dose-aware dispensing migration first.'; END IF;
  v_definition := pg_get_functiondef(v_function);
  IF position('MANUAL_OPEN_VIAL_DISPOSAL_REQUIRED' IN v_definition) = 0 THEN
    IF position(v_anchor IN v_definition) = 0 THEN
      RAISE EXCEPTION 'The installed dispensing implementation differs from the expected migration. No function was changed.';
    END IF;
    -- Preserve any existing accounting improvements in the installed function
    -- instead of replacing its entire body with an older copy.
    EXECUTE replace(v_definition, v_anchor, v_guard);
  END IF;
END;
$migration$;

-- The same manual discard action, with open doses distinct from sealed units.
CREATE OR REPLACE FUNCTION public.discard_open_vial_doses(
  p_batch_id BIGINT,
  p_discarded_by BIGINT DEFAULT NULL,
  p_reason TEXT DEFAULT 'Open vial exceeded its maximum shelf life'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_batch public.inventory_batches%ROWTYPE;
  v_item_name TEXT;
  v_doses_wasted INTEGER;
  v_actor BIGINT;
BEGIN
  SELECT * INTO v_batch FROM public.inventory_batches WHERE batch_id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','Batch not found'); END IF;
  v_doses_wasted := COALESCE(v_batch.doses_remaining_in_open_vial,0);
  IF v_doses_wasted <= 0 THEN
    RETURN jsonb_build_object('success',false,'error','This batch has no open-vial doses left to discard');
  END IF;
  v_actor := public.resolve_actor_account_id(p_discarded_by);
  IF v_actor IS NULL OR NULLIF(btrim(COALESCE(p_reason,'')),'') IS NULL THEN
    RETURN jsonb_build_object('success',false,'error','A responsible officer and discard reason are required');
  END IF;
  SELECT name INTO v_item_name FROM public.inventory_items WHERE item_id=v_batch.item_id;
  UPDATE public.inventory_batches
     SET doses_remaining_in_open_vial=0,open_vials_count=0,vial_opened_at=NULL,
         status=CASE WHEN COALESCE(quantity_remaining,0)<=0 THEN 'depleted' ELSE status END
   WHERE batch_id=p_batch_id;
  INSERT INTO public.inventory_transactions (batch_id,facility_id,transaction_type,quantity,dose_quantity,
    reference_type,reference_id,notes,performed_by,resulting_quantity_remaining,resulting_open_vial_doses,logged_at)
  VALUES (p_batch_id,v_batch.facility_id,'discard',0,-v_doses_wasted,
    'Open Vial Discard',p_batch_id,
    'Discarded ' || v_doses_wasted || ' open dose(s) of ' || COALESCE(v_item_name,'vaccine') ||
      ' from Batch #' || v_batch.batch_number || ' - ' || p_reason,
    v_actor,v_batch.quantity_remaining,0,NOW());
  RETURN jsonb_build_object('success',true,'batch_id',p_batch_id,'doses_discarded',v_doses_wasted,
    'message','Discarded ' || v_doses_wasted || ' open dose(s)');
END;
$fn$;

COMMIT;
NOTIFY pgrst, 'reload schema';
