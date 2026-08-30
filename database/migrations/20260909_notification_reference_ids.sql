-- ==============================================================================
-- MIGRATION: 20260909_notification_reference_ids.sql
--
-- Gives a notification a stable pointer back to the row it is about, so the
-- app can tell when a raw notification and a richer, live-derived alert are
-- both describing the SAME event.
--
-- THE DUPLICATE
--
--   The midwife notification centre shows two different kinds of card from
--   two different sources: one it derives itself from live data (a stock
--   request that is currently 'approved', a transfer currently awaiting
--   receipt), and one it reads straight from the `notifications` table, which
--   RHU-side actions ALSO write a row into. For a single approval, a midwife
--   sees both "Stock Request Approved" (derived, with a working action) and a
--   second, separate "Stock request approved" (raw, until the last change had
--   no action at all) -- one event, two cards.
--
--   `notifications` carries only a title and a message. There has never been
--   a column saying WHICH request or transfer a row is about, so the app had
--   no way to recognise the two as the same event short of parsing English
--   sentences -- which is exactly the class of fix this codebase has already
--   rejected once (20260824's own words: "a stable column instead of matching
--   English prose").
--
-- THE FIX
--
--   Two nullable columns, reference_type / reference_id, populated at the four
--   places that write a notification about a specific request or transfer:
--   the two approve functions, reject, and the destination-facing half of
--   announce_inventory_transfer. The app can then ask "is there already a
--   derived alert for inventory_stock_requests #12" before adding a second
--   card for the same thing -- and only suppress the raw one while that
--   derived twin is actually present this load, so an approval or shipment
--   old enough to have dropped out of the live-derived view still surfaces
--   through its own row rather than silently vanishing.
--
--   inventory_notify_facility / inventory_notify_supervisor gain the two
--   columns as new, defaulted, TRAILING parameters. Every one of their nine
--   other call sites keeps compiling unchanged and keeps writing NULL
--   references, exactly as before; only the one call this migration touches
--   (the destination notice in announce_inventory_transfer) is asked to pass
--   them.
--
-- WHAT THIS DOES NOT FIX
--
--   Historical rows. A stock-request notification's message contains the
--   request number in plain text ("...request #12...") and is backfilled
--   below by pattern; a transfer notification's message never printed the
--   transfer's id anywhere, so there is nothing reliable to extract it from,
--   and pre-existing "Incoming stocks" rows are left with no reference. They
--   keep showing as their own card, same as before this migration -- which is
--   the same "do not guess" choice made throughout this file.
--
-- Requires 20260821_inventory_and_td_fixes.sql, 20260824_inventory_integration_fixes.sql
-- and 20260829_inventory_transfer_directions.sql.
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. The columns.
-- ---------------------------------------------------------------------------
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS reference_type TEXT,
  ADD COLUMN IF NOT EXISTS reference_id BIGINT;

CREATE INDEX IF NOT EXISTS idx_notifications_reference
  ON public.notifications(reference_type, reference_id)
  WHERE reference_id IS NOT NULL;

COMMENT ON COLUMN public.notifications.reference_type IS
  'Table the notification is about, e.g. inventory_stock_requests or '
  'inventory_transfers. Lets a reader match this row to a richer, live-derived '
  'view of the same event instead of parsing the message text.';

COMMENT ON COLUMN public.notifications.reference_id IS
  'Primary key in reference_type this notification is about. Null on rows '
  'written before this migration, and on notifications with no single row '
  'behind them (a general announcement, a low-stock notice).';


-- ---------------------------------------------------------------------------
-- 2. Stock-request outcomes. Same signatures, so nothing that calls these
--    changes; only the notification INSERT gains two more columns.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_inventory_stock_request(
  p_request_id BIGINT,
  p_admin_id BIGINT,
  p_admin_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_request public.inventory_stock_requests%ROWTYPE;
BEGIN
  PERFORM public.inventory_assert_actor(p_admin_id, 'admin');

  SELECT * INTO v_request
  FROM public.inventory_stock_requests
  WHERE request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending requests can be approved'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_stock_requests
  SET status = 'approved',
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      admin_remarks = nullif(btrim(coalesce(p_admin_remarks, '')), '')
  WHERE request_id = p_request_id
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (
    account_id, title, message, type, reference_type, reference_id
  )
  VALUES (
    v_request.requested_by,
    'Stock request approved',
    format('Your stock request #%s was approved by RHU Main.', p_request_id),
    'general',
    'inventory_stock_requests',
    p_request_id
  );

  RETURN v_request;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.approve_inventory_stock_request_with_quantity(
  p_request_id BIGINT,
  p_admin_id BIGINT,
  p_approved_quantity INTEGER,
  p_admin_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_request public.inventory_stock_requests%ROWTYPE;
BEGIN
  PERFORM public.inventory_assert_actor(p_admin_id, 'admin');

  IF p_approved_quantity IS NULL OR p_approved_quantity <= 0 THEN
    RAISE EXCEPTION 'Approved quantity must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_request
  FROM public.inventory_stock_requests
  WHERE request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending requests can be approved'
      USING ERRCODE = '22023';
  END IF;
  IF p_approved_quantity > v_request.requested_quantity THEN
    RAISE EXCEPTION 'Approved quantity (%) cannot exceed the requested quantity (%)',
      p_approved_quantity, v_request.requested_quantity
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_stock_requests
  SET status = 'approved',
      approved_quantity = p_approved_quantity,
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      admin_remarks = nullif(btrim(coalesce(p_admin_remarks, '')), '')
  WHERE request_id = p_request_id
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (
    account_id, title, message, type, reference_type, reference_id
  )
  VALUES (
    v_request.requested_by,
    'Stock request approved',
    CASE
      WHEN p_approved_quantity < v_request.requested_quantity THEN
        format('Your stock request #%s was partially approved by RHU Main: %s of %s units.',
               p_request_id, p_approved_quantity, v_request.requested_quantity)
      ELSE
        format('Your stock request #%s was approved by RHU Main.', p_request_id)
    END,
    'general',
    'inventory_stock_requests',
    p_request_id
  );

  RETURN v_request;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.reject_inventory_stock_request(
  p_request_id BIGINT,
  p_admin_id BIGINT,
  p_admin_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_request public.inventory_stock_requests%ROWTYPE;
BEGIN
  PERFORM public.inventory_assert_actor(p_admin_id, 'admin');

  SELECT * INTO v_request
  FROM public.inventory_stock_requests
  WHERE request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'This request can no longer be rejected'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_stock_requests
  SET status = 'rejected',
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      admin_remarks = nullif(btrim(coalesce(p_admin_remarks, '')), '')
  WHERE request_id = p_request_id
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (
    account_id, title, message, type, reference_type, reference_id
  )
  VALUES (
    v_request.requested_by,
    'Stock request update',
    format('Your stock request #%s was not approved.%s',
      p_request_id,
      CASE
        WHEN v_request.admin_remarks IS NULL THEN ''
        ELSE ' ' || v_request.admin_remarks
      END),
    'general',
    'inventory_stock_requests',
    p_request_id
  );

  RETURN v_request;
END;
$fn$;


-- ---------------------------------------------------------------------------
-- 3. The two shared notify helpers gain the same two columns as new,
--    defaulted, TRAILING parameters -- every existing call keeps compiling
--    and keeps writing NULL references; nothing about who gets notified or
--    what the message says changes.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_notify_facility(
  p_facility_id BIGINT,
  p_title TEXT,
  p_message TEXT,
  p_include_portal BOOLEAN DEFAULT true,
  p_exclude_account_id BIGINT DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id BIGINT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_target  BIGINT := public.inventory_place_id(p_facility_id);
  -- Used as a plain account_id, deliberately not through
  -- resolve_actor_account_id(): that helper tries the midwife_id reading FIRST,
  -- which is right for the clinical tables that store one but wrong here. Every
  -- caller passes a column that already references accounts(account_id), and a
  -- mis-resolve would silently silence the wrong person.
  v_exclude BIGINT := p_exclude_account_id;
  v_count   INTEGER := 0;
BEGIN
  IF v_target IS NULL THEN
    RETURN 0;
  END IF;

  -- One statement covers both tiers, so an account that is somehow both a
  -- midwife and a portal assignee at the same facility is notified once rather
  -- than twice, and the count is a count of people rather than of rows matched.
  INSERT INTO public.notifications (
    account_id, title, message, type, reference_type, reference_id
  )
  SELECT DISTINCT a.account_id, p_title, p_message, 'inventory',
         p_reference_type, p_reference_id
    FROM public.accounts a
   WHERE a.status = 'active'
     AND (v_exclude IS NULL OR a.account_id <> v_exclude)
     AND (
          EXISTS (SELECT 1 FROM public.midwives m
                   WHERE m.account_id = a.account_id
                     AND m.assigned_bhc_id = v_target)
       OR (p_include_portal
           AND a.account_type IN ('admin', 'mho')
           AND EXISTS (SELECT 1 FROM public.facility_assignments fa
                        WHERE fa.account_id = a.account_id
                          AND fa.facility_id = v_target
                          AND COALESCE(fa.is_active, true)))
     );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END
$fn$;

CREATE OR REPLACE FUNCTION public.inventory_notify_supervisor(
  p_facility_id BIGINT,
  p_title TEXT,
  p_message TEXT,
  p_exclude_account_id BIGINT DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id BIGINT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_parent BIGINT;
BEGIN
  SELECT parent_facility_id INTO v_parent
    FROM public.health_facilities
   WHERE facility_id = public.inventory_place_id(p_facility_id);

  IF v_parent IS NULL THEN
    RETURN 0;
  END IF;

  RETURN public.inventory_notify_facility(
    v_parent, p_title, p_message, true, p_exclude_account_id,
    p_reference_type, p_reference_id);
END
$fn$;


-- ---------------------------------------------------------------------------
-- 4. The one call site this migration actually cares about: the notice sent
--    to the RECEIVING facility when a transfer is issued. This is the half a
--    midwife reads, and the half the notification centre's derived alert
--    (once its dead status check is fixed alongside this) will now recognise.
--
--    Everything else in this function -- the sender's own notice, the
--    supervisor escalation, the "nobody to receive it" case -- is untouched
--    text-for-text; only the first call gains two trailing arguments.
-- ---------------------------------------------------------------------------
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

  -- Destination: this is the one that has to act, and the one the
  -- notification centre now dedupes against inventory_transfers #<id>.
  v_recipients := public.inventory_notify_facility(
    NEW.destination_facility_id,
    CASE v_direction
      WHEN 'return' THEN 'Stock returned to you'
      ELSE 'Incoming stocks'
    END,
    format('%s unit(s) of %s from %s are waiting for your receipt confirmation.%s',
           NEW.quantity_issued, v_item_name, v_source_name,
           CASE v_direction
             WHEN 'return'  THEN ' This is a return - confirm receipt promptly so the stock is usable again.'
             WHEN 'lateral' THEN ' This came from a neighbouring facility.'
             ELSE ''
           END),
    true,
    NULL,
    'inventory_transfers',
    NEW.transfer_id
  );

  -- Source: what left, and that it is not theirs any more until it is either
  -- confirmed at the other end or cancelled back.
  --
  -- Excluding the issuer is the whole difference between a useful notice and
  -- noise. On a routine allocation the source IS the office that just pressed
  -- the button, and telling them about it would put a message in the list for
  -- every dispatch they make. Colleagues at that facility still hear about it,
  -- and on a lateral or upward move — where the sending facility is not the one
  -- operating the portal — everybody there hears about it.
  PERFORM public.inventory_notify_facility(
    v_source_id,
    'Stock dispatched from your facility',
    format('%s unit(s) of %s were sent to %s (transfer #%s). They have already left your count and are awaiting confirmation at the other end.',
           NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id),
    true, NEW.issued_by
  );

  -- A move that is not a straight allocation is reported upward as well.
  IF v_direction IN ('lateral', 'external') THEN
    PERFORM public.inventory_notify_supervisor(
      v_source_id,
      'Facilities moved stock between themselves',
      format('%s sent %s unit(s) of %s to %s (transfer #%s).',
             v_source_name, NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id),
      NEW.issued_by
    );
  END IF;

  -- Nobody at all is assigned to the destination. The stock is sitting in
  -- transit against a facility with no staff to confirm it, which is a stuck
  -- transfer waiting to happen, so the office above it is told instead.
  --
  -- Nobody is excluded here, issuer included: this one says the dispatch they
  -- just made cannot be received by anyone, which is precisely the thing they
  -- need to hear back about their own action.
  IF v_recipients = 0 THEN
    PERFORM public.inventory_notify_supervisor(
      NEW.destination_facility_id,
      'Incoming stocks have nobody to receive them',
      format('%s unit(s) of %s were sent to %s (transfer #%s), but no active account is assigned to that facility to confirm receipt.',
             NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id)
    );
  END IF;

  -- The audit row for this event is written by trg_audit_inventory_transfer.
  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_announce_inventory_transfer ON public.inventory_transfers;
CREATE TRIGGER trg_announce_inventory_transfer
  AFTER INSERT ON public.inventory_transfers
  FOR EACH ROW EXECUTE FUNCTION public.announce_inventory_transfer();


-- ---------------------------------------------------------------------------
-- 5. Backfill what history can honestly support: the request number is
--    printed in plain text in every stock-request notification's message.
--    A transfer's id was never printed anywhere in its notification, so
--    pre-existing "Incoming stocks" rows are left alone rather than guessed.
-- ---------------------------------------------------------------------------
UPDATE public.notifications
   SET reference_type = 'inventory_stock_requests',
       reference_id = (regexp_match(message, '#(\d+)'))[1]::bigint
 WHERE reference_type IS NULL
   AND title IN ('Stock request approved', 'Stock request update')
   AND message ~ '#\d+';


-- ---------------------------------------------------------------------------
-- Verify.
-- ---------------------------------------------------------------------------
SELECT reference_type, count(*) AS rows,
       count(*) FILTER (WHERE reference_id IS NOT NULL) AS with_reference_id
  FROM public.notifications
 WHERE title IN ('Stock request approved', 'Stock request update',
                  'Incoming stocks', 'Incoming stocks from RHU Main',
                  'Stock returned to you')
 GROUP BY reference_type
 ORDER BY reference_type NULLS FIRST;
