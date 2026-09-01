-- ==============================================================================
-- MIGRATION: 20260915_inventory_alert_notifications.sql
--
-- Makes low stock, expiry and open-vial alerts exist WHEN NOBODY IS LOOKING.
--
-- WHAT WAS WRONG
-- --------------
--   The portal has a good Alert Center. It has never been a notification
--   system. Every alert it shows is computed in the browser, from rows
--   inventory.html happens to have loaded, at the moment somebody opens that
--   one page. Close the tab and the alerts stop existing. Nobody opens the
--   tab on a Saturday, and a vial does not wait for Monday.
--
--   Meanwhile `notifications` — which the midwife app reads, and which
--   inventory_notify_facility() already writes to for transfers — has never
--   received a single row about stock running out or a batch going off.
--
-- WHAT THIS ADDS
-- --------------
--   A scan (public.scan_inventory_alerts) that states the three rules once,
--   in SQL, as a plain read. A writer (public.raise_inventory_alerts) that
--   turns what the scan found into notifications for the people responsible.
--   A state table so the writer can tell a NEW problem from one it already
--   reported yesterday. And a daily schedule, because that is the entire
--   point of the file.
--
-- WHY A STATE TABLE AND NOT A COOLDOWN TIMESTAMP
-- ----------------------------------------------
--   The easy version re-notifies anything still true after N hours. Run that
--   daily against a shortage nobody can fix this week and you have taught
--   five midwives to swipe the inventory notifications away without reading
--   them — at which point the one that mattered goes with them.
--
--   So each alert is a row with a lifecycle. It is raised once when it
--   appears, again only when it ESCALATES (expiring in 30 days is not the
--   same warning as expired yesterday), again if it cleared and came back,
--   and otherwise at most once a week as a standing reminder. When the
--   condition stops being true the row is marked resolved rather than
--   deleted, so "this centre has run out of Ferrous four times this quarter"
--   is a question the data can answer later.
--
-- WHY THE OFFICE ABOVE IS NOT ALWAYS TOLD
-- ---------------------------------------
--   inventory_notify_supervisor() is called only for the severities that
--   need somebody else's stock to fix: a stockout and an expired batch. A
--   30-day expiry watch at four barangay health centres is four notifications
--   the RHU officer cannot act on and will start ignoring. Escalation that
--   fires on everything is escalation that means nothing.
--
-- WHY ONLY PAIRS THE FACILITY HAS HELD
-- ------------------------------------
--   Low stock is scanned over (item, facility) pairs that have EVER had a
--   batch, not over the cross product of the catalogue and the municipality.
--   A health centre that does not stock contraceptives is not short of them.
--   The cross product would have opened with roughly 300 shortages on day
--   one, most of them fictional, which is the fastest known way to get a
--   notification feature switched off.
--
-- REQUIRES
--   20260824_inventory_integration_fixes.sql   (notifications type 'inventory')
--   20260829_inventory_transfer_directions.sql (inventory_place_id, notify fns)
--   20260909_notification_reference_ids.sql    (reference_type / reference_id)
--
--   The open-vial rule additionally needs the columns added by
--   20260818/20260819. Their absence is detected at run time and that one
--   rule is skipped, rather than the whole scan failing — RUN_ORDER.md
--   describes a live database that is part-migrated, and a maintenance job
--   that dies on a missing column is a job nobody notices has died.
--
-- Safe to run more than once.
-- ==============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Preconditions that can be repaired here rather than refused.
--
-- The type constraint is widened by both 20260824 and 20260829. Repeating the
-- block means this file also works on a database where neither has been run,
-- instead of writing every alert into a CHECK violation.
-- ---------------------------------------------------------------------------
DO $notif_type$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
     WHERE t.relname = 'notifications'
       AND c.contype = 'c'
       AND pg_get_constraintdef(c.oid) ILIKE '%checkup_reminder%'
       AND pg_get_constraintdef(c.oid) NOT ILIKE '%inventory%'
  LOOP
    EXECUTE format('ALTER TABLE public.notifications DROP CONSTRAINT %I', r.conname);
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
     WHERE t.relname = 'notifications' AND c.contype = 'c'
       AND pg_get_constraintdef(c.oid) ILIKE '%inventory%'
  ) THEN
    ALTER TABLE public.notifications
      ADD CONSTRAINT notifications_type_check
      CHECK (type IN ('checkup_reminder', 'vaccine_reminder', 'general', 'inventory'));
  END IF;
END
$notif_type$;

-- The reference columns, in case 20260909 has not been run here. Same two
-- lines it uses; ADD COLUMN IF NOT EXISTS makes the overlap harmless.
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS reference_type TEXT,
  ADD COLUMN IF NOT EXISTS reference_id BIGINT;


-- ---------------------------------------------------------------------------
-- 1. Naming a place, and ranking a severity.
--
-- facility_id NULL means the municipal warehouse everywhere else in this
-- schema (see inventory_batches.facility_id), and it has to read as a place
-- rather than as a blank in the middle of a sentence a midwife receives.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_place_label(p_facility_id BIGINT)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $fn$
  SELECT COALESCE(
    (SELECT f.name FROM public.health_facilities f
      WHERE f.facility_id = p_facility_id),
    'the Municipal Warehouse'
  );
$fn$;

-- Ordered so an escalation is an inequality rather than a chain of ORs.
CREATE OR REPLACE FUNCTION public.inventory_alert_rank(p_severity TEXT)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE p_severity
           WHEN 'watch'    THEN 1
           WHEN 'low'      THEN 2
           WHEN 'urgent'   THEN 3
           WHEN 'critical' THEN 4
           WHEN 'expired'  THEN 5
           ELSE 0
         END;
$fn$;

-- One text key per distinct thing that can be wrong, so the state table gets a
-- real primary key. A composite key over four nullable columns would need
-- COALESCE sentinels in the key, in every ON CONFLICT, and in every lookup;
-- building the sentinel once here keeps it in one place.
CREATE OR REPLACE FUNCTION public.inventory_alert_key(
  p_kind TEXT, p_facility_id BIGINT, p_item_id BIGINT, p_batch_id BIGINT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT p_kind
      || '|' || COALESCE(p_facility_id::text, 'depot')
      || '|' || COALESCE(p_item_id::text, '-')
      || '|' || COALESCE(p_batch_id::text, '-');
$fn$;


-- ---------------------------------------------------------------------------
-- 2. What has already been reported.
--
-- resolved_at is set rather than the row deleted: an alert that clears and
-- returns is a different event from one that never went away, the writer below
-- needs to tell them apart, and the history is worth more than the space.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory_alert_state (
  alert_key        TEXT PRIMARY KEY,
  alert_kind       TEXT NOT NULL,
  facility_id      BIGINT,
  item_id          BIGINT,
  batch_id         BIGINT,
  severity         TEXT NOT NULL,
  times_raised     INTEGER NOT NULL DEFAULT 0,
  first_raised_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_raised_at   TIMESTAMPTZ,
  last_seen_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_inventory_alert_state_open
  ON public.inventory_alert_state(alert_kind, facility_id)
  WHERE resolved_at IS NULL;

ALTER TABLE public.inventory_alert_state DISABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.inventory_alert_state FROM anon, authenticated;
GRANT SELECT ON public.inventory_alert_state TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 3. The rules, stated once, as a read.
--
-- Nothing here writes. preview_inventory_alerts() and raise_inventory_alerts()
-- both call it, so the thing an officer previews is by construction the thing
-- the job will act on — rather than two copies of the thresholds drifting
-- apart, which is how the portal ended up with three different opinions about
-- what "low" means in the first place.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.scan_inventory_alerts()
RETURNS TABLE (
  alert_kind     TEXT,
  severity       TEXT,
  facility_id    BIGINT,
  item_id        BIGINT,
  batch_id       BIGINT,
  title          TEXT,
  message        TEXT,
  reference_type TEXT,
  reference_id   BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_has_open_vial BOOLEAN;
BEGIN
  -- ---- Rule 1: low stock and stockout, per item per place -----------------
  RETURN QUERY
  WITH carried AS (
    -- Pairs this place actually stocks. See the header note on why this is not
    -- the cross product of the catalogue and the municipality.
    SELECT DISTINCT b.item_id, b.facility_id
      FROM public.inventory_batches b
  ),
  on_hand AS (
    SELECT c.item_id,
           c.facility_id,
           COALESCE(SUM(b.quantity_remaining) FILTER (
             WHERE b.status = 'active'
               AND b.expiration_date >= CURRENT_DATE
           ), 0)::INTEGER AS available
      FROM carried c
      LEFT JOIN public.inventory_batches b
             ON b.item_id = c.item_id
            -- IS NOT DISTINCT FROM, because the depot's facility_id is NULL
            -- and `= NULL` would silently drop every warehouse row.
            AND b.facility_id IS NOT DISTINCT FROM c.facility_id
     GROUP BY c.item_id, c.facility_id
  )
  SELECT
    'low_stock'::TEXT,
    CASE WHEN h.available = 0 THEN 'critical' ELSE 'low' END::TEXT,
    h.facility_id,
    h.item_id,
    NULL::BIGINT,
    (CASE WHEN h.available = 0
          THEN 'Out of stock: ' ELSE 'Low stock: ' END || i.name)::TEXT,
    (i.name || ' at ' || public.inventory_place_label(h.facility_id)
       || CASE WHEN h.available = 0
               THEN ' has run out.'
               ELSE ' is down to ' || h.available || ' ' || i.unit_of_measure || '.' END
       || ' The reorder threshold is ' || COALESCE(i.minimum_stock_threshold, 50)
       || ' ' || i.unit_of_measure || '.')::TEXT,
    'inventory_items'::TEXT,
    h.item_id
  FROM on_hand h
  JOIN public.inventory_items i ON i.item_id = h.item_id
  WHERE COALESCE(i.is_archived, false) = false
    AND h.available <= COALESCE(i.minimum_stock_threshold, 50);

  -- ---- Rule 2: batches expiring, and batches already expired --------------
  --
  -- quantity_remaining > 0 is part of the rule, not an optimisation: an empty
  -- batch going off is not a loss and not worth anybody's attention.
  RETURN QUERY
  SELECT
    'expiring'::TEXT,
    CASE
      WHEN b.expiration_date <= CURRENT_DATE           THEN 'expired'
      WHEN b.expiration_date <= CURRENT_DATE + 7       THEN 'urgent'
      ELSE 'watch'
    END::TEXT,
    b.facility_id,
    b.item_id,
    b.batch_id,
    (CASE
       WHEN b.expiration_date <= CURRENT_DATE     THEN 'Expired stock: '
       WHEN b.expiration_date <= CURRENT_DATE + 7 THEN 'Expiring this week: '
       ELSE 'Expiring soon: '
     END || i.name)::TEXT,
    (b.quantity_remaining || ' ' || i.unit_of_measure || ' of ' || i.name
       || ' (batch ' || b.batch_number || ') at '
       || public.inventory_place_label(b.facility_id)
       || CASE
            WHEN b.expiration_date <= CURRENT_DATE
              THEN ' expired on ' || to_char(b.expiration_date, 'DD Mon YYYY')
                   || ' and must be withdrawn and recorded as disposal.'
            ELSE ' expires on ' || to_char(b.expiration_date, 'DD Mon YYYY')
                   || ' (' || (b.expiration_date - CURRENT_DATE) || ' days). Use or redistribute it first.'
          END)::TEXT,
    'inventory_batches'::TEXT,
    b.batch_id
  FROM public.inventory_batches b
  JOIN public.inventory_items i ON i.item_id = b.item_id
  WHERE b.status = 'active'
    AND b.quantity_remaining > 0
    AND b.expiration_date <= CURRENT_DATE + 30;

  -- ---- Rule 3: open vials past their shelf life ---------------------------
  --
  -- Guarded, because these columns arrive in 20260818/20260819 and RUN_ORDER.md
  -- describes a live database that is part-migrated. A maintenance job that
  -- aborts on a missing column is a job that stops running and says nothing.
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'inventory_batches'
       AND column_name = 'doses_remaining_in_open_vial'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'inventory_batches'
       AND column_name = 'vial_opened_at'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'inventory_items'
       AND column_name = 'open_vial_shelf_hours'
  ) INTO v_has_open_vial;

  IF v_has_open_vial THEN
    RETURN QUERY EXECUTE $sql$
      SELECT
        'open_vial'::TEXT,
        'urgent'::TEXT,
        b.facility_id,
        b.item_id,
        b.batch_id,
        ('Open vial past its shelf limit: ' || i.name)::TEXT,
        (b.doses_remaining_in_open_vial || ' dose(s) of ' || i.name
           || ' (batch ' || b.batch_number || ') at '
           || public.inventory_place_label(b.facility_id)
           || ' have been open since '
           || to_char(b.vial_opened_at AT TIME ZONE 'Asia/Manila', 'DD Mon YYYY HH24:MI')
           || ', past the ' || i.open_vial_shelf_hours
           || '-hour limit. Discard the vial and record it so the wastage rate stays true.')::TEXT,
        'inventory_batches'::TEXT,
        b.batch_id
      FROM public.inventory_batches b
      JOIN public.inventory_items i ON i.item_id = b.item_id
      WHERE b.status = 'active'
        AND COALESCE(b.doses_remaining_in_open_vial, 0) > 0
        AND b.vial_opened_at IS NOT NULL
        AND COALESCE(i.open_vial_shelf_hours, 0) > 0
        AND b.vial_opened_at + make_interval(hours => i.open_vial_shelf_hours) < now()
    $sql$;
  END IF;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 4. Turning what the scan found into notifications.
--
-- Returns a summary rather than void so a manual run says what it did, and so
-- the cron job's own history is readable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.raise_inventory_alerts(
  -- How long a standing, unchanged problem waits before it is mentioned again.
  p_reminder_interval INTERVAL DEFAULT INTERVAL '7 days'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  a                RECORD;
  v_key            TEXT;
  v_prior          public.inventory_alert_state%ROWTYPE;
  v_should_notify  BOOLEAN;
  v_reason         TEXT;
  v_recipients     INTEGER;
  v_seen           TEXT[] := ARRAY[]::TEXT[];
  v_found          INTEGER := 0;
  v_notified       INTEGER := 0;
  v_people         INTEGER := 0;
  v_resolved       INTEGER := 0;
  v_started        TIMESTAMPTZ := clock_timestamp();
BEGIN
  FOR a IN SELECT * FROM public.scan_inventory_alerts() LOOP
    v_found := v_found + 1;
    v_key := public.inventory_alert_key(
      a.alert_kind, a.facility_id, a.item_id, a.batch_id);
    v_seen := v_seen || v_key;

    SELECT * INTO v_prior
      FROM public.inventory_alert_state
     WHERE alert_key = v_key;

    IF NOT FOUND THEN
      v_should_notify := true;
      v_reason := 'new';
    ELSIF v_prior.resolved_at IS NOT NULL THEN
      -- It cleared and came back. That is news, whatever the severity.
      v_should_notify := true;
      v_reason := 'returned';
    ELSIF public.inventory_alert_rank(a.severity)
          > public.inventory_alert_rank(v_prior.severity) THEN
      v_should_notify := true;
      v_reason := 'escalated';
    ELSIF v_prior.last_raised_at IS NULL
          OR v_prior.last_raised_at < now() - p_reminder_interval THEN
      v_should_notify := true;
      v_reason := 'reminder';
    ELSE
      v_should_notify := false;
      v_reason := 'already reported';
    END IF;

    IF v_should_notify THEN
      v_recipients := COALESCE(public.inventory_notify_facility(
        a.facility_id, a.title, a.message, true, NULL,
        a.reference_type, a.reference_id), 0);

      -- Only the severities somebody upstairs can actually do something about.
      -- See the header note on escalation that fires on everything.
      IF a.severity IN ('critical', 'expired') THEN
        v_recipients := v_recipients + COALESCE(public.inventory_notify_supervisor(
          a.facility_id, a.title, a.message, NULL,
          a.reference_type, a.reference_id), 0);
      END IF;

      v_notified := v_notified + 1;
      v_people   := v_people + v_recipients;
    END IF;

    INSERT INTO public.inventory_alert_state AS s (
      alert_key, alert_kind, facility_id, item_id, batch_id, severity,
      times_raised, first_raised_at, last_raised_at, last_seen_at, resolved_at
    ) VALUES (
      v_key, a.alert_kind, a.facility_id, a.item_id, a.batch_id, a.severity,
      CASE WHEN v_should_notify THEN 1 ELSE 0 END,
      now(),
      CASE WHEN v_should_notify THEN now() ELSE NULL END,
      now(),
      NULL
    )
    ON CONFLICT (alert_key) DO UPDATE SET
      severity       = EXCLUDED.severity,
      last_seen_at   = now(),
      -- A returning alert starts its clock again; otherwise the original
      -- first_raised_at is how long this has been going on.
      first_raised_at = CASE WHEN s.resolved_at IS NOT NULL
                             THEN now() ELSE s.first_raised_at END,
      times_raised   = s.times_raised + CASE WHEN v_should_notify THEN 1 ELSE 0 END,
      last_raised_at = CASE WHEN v_should_notify THEN now() ELSE s.last_raised_at END,
      resolved_at    = NULL;
  END LOOP;

  -- Anything open that the scan no longer returns has been fixed: restocked,
  -- disposed of, transferred away, or the vial discarded.
  UPDATE public.inventory_alert_state
     SET resolved_at = now()
   WHERE resolved_at IS NULL
     AND NOT (alert_key = ANY (v_seen));
  GET DIAGNOSTICS v_resolved = ROW_COUNT;

  RETURN jsonb_build_object(
    'success',            true,
    'ran_at',             now(),
    'duration_ms',        round(EXTRACT(EPOCH FROM clock_timestamp() - v_started) * 1000),
    'alerts_found',       v_found,
    'alerts_notified',    v_notified,
    'notifications_sent', v_people,
    'alerts_resolved',    v_resolved
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 5. Looking without touching.
--
-- Rehearse before trusting it, the same way 20260817 asks you to:
--
--   select * from public.preview_inventory_alerts();   -- what it would say
--   select public.raise_inventory_alerts();            -- actually notify
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.preview_inventory_alerts()
RETURNS TABLE (
  alert_kind     TEXT,
  severity       TEXT,
  facility_id    BIGINT,
  facility_name  TEXT,
  item_id        BIGINT,
  batch_id       BIGINT,
  title          TEXT,
  message        TEXT,
  already_open   BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT s.alert_kind,
         s.severity,
         s.facility_id,
         public.inventory_place_label(s.facility_id),
         s.item_id,
         s.batch_id,
         s.title,
         s.message,
         EXISTS (
           SELECT 1 FROM public.inventory_alert_state st
            WHERE st.alert_key = public.inventory_alert_key(
                    s.alert_kind, s.facility_id, s.item_id, s.batch_id)
              AND st.resolved_at IS NULL
         )
    FROM public.scan_inventory_alerts() s
   ORDER BY public.inventory_alert_rank(s.severity) DESC, s.alert_kind, s.facility_id;
$fn$;


-- ---------------------------------------------------------------------------
-- 6. Who may call what.
--
-- The portal is allowed to LOOK at the computed alert list — that is a read,
-- and it is how a "check now" button can be honest about server-side state.
-- It is not allowed to RAISE. This app authenticates with account ids against
-- the anon key, so an exposed writer is a button anybody can press to put a
-- notification in every midwife's inbox. Raising belongs to the schedule.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.raise_inventory_alerts(INTERVAL) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.preview_inventory_alerts()   TO anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.scan_inventory_alerts()      TO anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.inventory_place_label(BIGINT) TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 7. The schedule — the entire point of the file.
--
-- 22:00 UTC is 06:00 the next morning in Manila, so the alerts are waiting
-- when the health centre opens rather than arriving overnight.
--
-- Unlike 20260817 this needs no Edge Function and no service-role key: it
-- writes in-app notifications only, and that is a plain INSERT this database
-- can do to itself. Nothing here spends SMS credits. The existing manual
-- "Send SMS Alert" button in the portal stays the only thing that does.
-- ---------------------------------------------------------------------------
-- CREATE EXTENSION lives inside the guard on purpose. Outside it, an instance
-- where pg_cron is not available fails the statement, which aborts the
-- transaction and takes the six working functions above down with it — the
-- automation would be missing AND so would everything else.
--
-- cron.schedule() replaces a job of the same name in pg_cron 1.4+, so this is
-- re-runnable without an unschedule step.
DO $sched$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;

  PERFORM cron.schedule(
    'inaagapay-inventory-alerts',
    '0 22 * * *',
    $job$SELECT public.raise_inventory_alerts()$job$
  );

  RAISE NOTICE 'Scheduled inaagapay-inventory-alerts daily at 22:00 UTC (06:00 Asia/Manila).';
EXCEPTION WHEN OTHERS THEN
  -- pg_cron is not enabled on every plan or local instance. The functions are
  -- still installed and callable; only the automation is missing, and saying so
  -- beats failing the migration.
  RAISE NOTICE 'Could not schedule inaagapay-inventory-alerts (%). Enable pg_cron (Supabase: Database -> Extensions) and re-run this file, or call raise_inventory_alerts() from your own scheduler.', SQLERRM;
END
$sched$;

COMMIT;

-- ==============================================================================
-- AFTER RUNNING
--
--   select * from public.preview_inventory_alerts();
--
-- The first real run will notify on everything currently true, which on a
-- seeded database is a lot. That is correct — none of it has ever been
-- reported — but run the preview first so it is not a surprise.
--
-- To check the schedule took:
--   select jobname, schedule, active from cron.job
--    where jobname = 'inaagapay-inventory-alerts';
-- ==============================================================================
