-- ===========================================================================
-- 20260921_count_overage_raises_received.sql
--
-- Fixes: new row for relation "inventory_batches" violates check constraint
-- "chk_batch_quantities" - raised when posting a physical count that found
-- more units than the batch was booked in with.
--
-- chk_batch_quantities requires quantity_remaining <= quantity_received.
-- post_inventory_count() wrote the counted figure straight into
-- quantity_remaining and left quantity_received alone, so any batch counted
-- above its received quantity aborted the posting. The whole post runs in one
-- transaction, so a single overage line also threw away every other corrected
-- line in that session.
--
-- Finding more than was booked in is an ordinary shelf outcome (stock returned
-- unused, a delivery under-recorded on arrival), so the count now raises
-- quantity_received to the counted figure instead of refusing the correction.
-- Shortfalls are untouched: quantity_received stays the ceiling it always was,
-- not a running total.
--
-- Idempotent. CREATE OR REPLACE only - no schema or data change, and grants on
-- post_inventory_count survive the replace.
--
-- Depends on: 20260917_inventory_physical_count.sql
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.post_inventory_count(
  p_count_id BIGINT,
  p_actor_id BIGINT
)
RETURNS TABLE (
  count_id        BIGINT,
  lines_total     INTEGER,
  lines_adjusted  INTEGER,
  units_gained    INTEGER,
  units_lost      INTEGER
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_session public.inventory_count_sessions%ROWTYPE;
  v_moved   TEXT;
  -- NOT named `l`. PL/pgSQL identifiers are case-insensitive, so a variable
  -- called L is the same name as the table alias l used below, and every
  -- `l.system_quantity` in this function resolves to the unassigned record
  -- instead of the column: "record l is not assigned yet", SQLSTATE 55000.
  v_line    RECORD;
BEGIN
  PERFORM public.inventory_assert_posting_actor(p_actor_id);

  SELECT * INTO v_session FROM public.inventory_count_sessions
   WHERE inventory_count_sessions.count_id = p_count_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock count not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_session.status <> 'review' THEN
    RAISE EXCEPTION 'Only a submitted count can be posted (this one is %)', v_session.status
      USING ERRCODE = '22023';
  END IF;

  -- The guard. A batch that moved between the snapshot and now has a variance
  -- computed against a quantity that is no longer true, and posting it would
  -- overwrite a real dispense with a stale number.
  SELECT string_agg(format('%s (sheet said %s, shelf now %s)',
                           COALESCE(b.batch_number, '#' || b.batch_id),
                           l.system_quantity, b.quantity_remaining), '; ')
    INTO v_moved
    FROM public.inventory_count_lines l
    JOIN public.inventory_batches b ON b.batch_id = l.batch_id
   WHERE l.count_id = p_count_id
     AND COALESCE(b.quantity_remaining, 0) <> l.system_quantity;

  IF v_moved IS NOT NULL THEN
    RAISE EXCEPTION
      'Stock moved during this count and it can no longer be posted as counted. Recount: %',
      v_moved
      USING ERRCODE = '40001';
  END IF;

  lines_total := 0; lines_adjusted := 0; units_gained := 0; units_lost := 0;

  FOR v_line IN
    SELECT l.*, b.facility_id AS batch_facility_id
      FROM public.inventory_count_lines l
      JOIN public.inventory_batches b ON b.batch_id = l.batch_id
     WHERE l.count_id = p_count_id
     ORDER BY l.count_line_id
  LOOP
    lines_total := lines_total + 1;
    CONTINUE WHEN COALESCE(v_line.variance, 0) = 0;

    -- chk_batch_quantities forbids quantity_remaining > quantity_received, so a
    -- sheet that counts more units than the batch was booked in with used to
    -- abort the whole posting with a raw constraint error. An overage is a real
    -- outcome, not bad data: units come back to the shelf, or a delivery was
    -- under-recorded on arrival. Raise quantity_received to the new high-water
    -- mark so the correction posts. A shortfall leaves it alone, so the batch
    -- keeps the true figure for how much ever arrived and the received column
    -- stays a ceiling rather than a running total.
    UPDATE public.inventory_batches
       SET quantity_remaining = v_line.counted_quantity,
           quantity_received  = GREATEST(quantity_received, v_line.counted_quantity)
     WHERE batch_id = v_line.batch_id;

    -- Signed the way the rest of this ledger is signed: negative is stock
    -- leaving the shelf. trg_audit_inventory_transaction narrates it.
    INSERT INTO public.inventory_transactions (
      batch_id, facility_id, transaction_type, quantity,
      reference_type, reference_id, performed_by,
      resulting_quantity_remaining, notes
    ) VALUES (
      v_line.batch_id, v_line.batch_facility_id, 'adjustment', v_line.variance,
      'inventory_count_sessions', p_count_id, p_actor_id,
      v_line.counted_quantity,
      format('Physical count #%s: recorded %s, counted %s.%s',
             p_count_id, v_line.system_quantity, v_line.counted_quantity,
             CASE WHEN v_line.reason IS NULL THEN '' ELSE ' ' || v_line.reason END)
    );

    lines_adjusted := lines_adjusted + 1;
    IF v_line.variance > 0 THEN units_gained := units_gained + v_line.variance;
                           ELSE units_lost   := units_lost   - v_line.variance;
    END IF;
  END LOOP;

  UPDATE public.inventory_count_sessions
     SET status = 'posted', posted_by = p_actor_id, posted_at = now()
   WHERE inventory_count_sessions.count_id = p_count_id
  RETURNING * INTO v_session;

  PERFORM public.audit_write(
    p_actor_id, 'inventory_count_posted', 'inventory_count_sessions',
    p_count_id::text,
    format('Stock count #%s', p_count_id),
    format('Posted stock count #%s', p_count_id),
    format('The count at %s was posted. %s of %s batch(es) were corrected: '
           '%s unit(s) found, %s unit(s) missing. %s',
           public.audit_facility_label(v_session.facility_id),
           lines_adjusted, lines_total, units_gained, units_lost,
           CASE WHEN v_session.submitted_by IS NOT DISTINCT FROM p_actor_id
                THEN 'The same account counted and posted this session.'
                ELSE 'Counted and posted by different accounts.' END),
    '[]'::jsonb,
    jsonb_build_object('count_id', p_count_id, 'facility_id', v_session.facility_id,
                       'lines_adjusted', lines_adjusted),
    NULL, to_jsonb(v_session),
    CASE WHEN lines_adjusted > 0 THEN 'warning' ELSE 'notice' END,
    'count'
  );

  count_id := p_count_id;
  RETURN NEXT;
END
$fn$;
