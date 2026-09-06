-- ==============================================================================
-- MIGRATION: 20260917_inventory_physical_count.sql
--
-- Physical stock count, with variance held for approval.
--
-- THE HOLE THIS FILLS
--
--   This system can tell you everything about stock that MOVED. Receipts,
--   dispenses to a named patient, transfers in three directions, disposals,
--   open-vial draws down to the dose — all of it lands in
--   inventory_transactions and all of it is audited.
--
--   What it has never been able to say is whether any of that matches the
--   shelf. There is no way to record what somebody actually counted, and
--   therefore no way to discover that the ledger says 40 and the cupboard holds
--   37. Every figure in the portal is derived from movements the system was
--   told about; nothing has ever checked that against the physical world.
--
--   For an inventory system that is the one structural omission. A count is
--   what turns a movement log into stock control.
--
-- WHY VARIANCE IS NOT POSTED IMMEDIATELY
--
--   The tempting design is: type what you counted, the batch updates, done.
--   That makes the ledger self-correcting and unauditable in the same stroke —
--   a shortage of 12 vials and a typo of 12 vials are indistinguishable
--   afterwards, and the person who caused the first can hide it as the second.
--
--   So a count moves through states. The facility counts and submits; the
--   office above posts. Only posting touches stock, and posting writes one
--   'adjustment' row per varying batch, so the correction appears in the same
--   ledger as every other movement and is narrated by the same audit trigger.
--
--     open ──submit──> review ──post──> posted
--       └────────────── cancel ────────> cancelled
--
--   Separation of duties is RECORDED but not ENFORCED. Requiring a different
--   person to post would deadlock a barangay health centre staffed by one
--   midwife, which is most of them. Both actor ids are stored, so the trail
--   shows whether the same person did both — an auditor can ask; the system
--   does not pretend nobody ever will.
--
-- THE GUARD THAT MAKES IT HONEST
--
--   A count takes time. If a batch is dispensed from between the snapshot and
--   the posting, the variance on file was computed against a quantity that is
--   no longer current, and posting it would silently erase a real dispense.
--
--   post_inventory_count() therefore refuses to post any line whose batch has
--   moved since the count opened, and names the batches. Those lines have to be
--   recounted. This is the difference between a stock count and a stock
--   overwrite.
--
-- WHAT IT REUSES RATHER THAN REBUILDS
--
--   * inventory_transactions — variance becomes 'adjustment' rows, signed the
--     way the rest of the ledger is signed (negative is stock leaving), with
--     reference_type pointing back at the count.
--   * trg_audit_inventory_transaction — already narrates 'adjustment' at
--     'warning' severity, so every posted variance is audited with no new
--     audit code at all.
--   * audit_write() — used only for the session lifecycle (opened, submitted,
--     posted, cancelled), which no trigger covers because these are new tables.
--   * admin_change_events — the two new tables join the watch list so the
--     portal's live refresh notices a count without a second mechanism.
--
-- Requires 20260803_inventory_distribution_workflow.sql,
-- 20260821_mho_tier.sql and 20260826_audit_trail_completeness.sql.
-- Safe to run more than once. Defines no function any earlier migration
-- defines.
-- ==============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Preflight.
-- ---------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF to_regclass('public.inventory_batches') IS NULL THEN
    RAISE EXCEPTION
      'Prerequisite missing: public.inventory_batches. Run 20260803_inventory_distribution_workflow.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'inventory_transactions'
       AND column_name = 'resulting_quantity_remaining'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: inventory_transactions.resulting_quantity_remaining. Run 20260822_dose_accounting.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'audit_write'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: public.audit_write(). Run 20260826_audit_trail_completeness.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'audit_facility_label'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: public.audit_facility_label(). Run 20260826_audit_trail_completeness.sql first.';
  END IF;
END
$preflight$;


-- ---------------------------------------------------------------------------
-- 1. The count session.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory_count_sessions (
  count_id      BIGSERIAL PRIMARY KEY,
  facility_id   BIGINT REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL,
  status        TEXT NOT NULL DEFAULT 'open'
                CHECK (status IN ('open', 'review', 'posted', 'cancelled')),
  notes         TEXT,

  opened_by     BIGINT REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  opened_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  submitted_by  BIGINT REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  submitted_at  TIMESTAMPTZ,
  posted_by     BIGINT REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  posted_at     TIMESTAMPTZ,
  cancelled_by  BIGINT REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  cancelled_at  TIMESTAMPTZ,
  cancel_reason TEXT
);

-- Repair pass, for a table that already exists in some other shape. Same
-- reasoning as 20260915: CREATE TABLE IF NOT EXISTS matches on the name and
-- skips the whole block, and everything after it then fails on a missing
-- column with an error that points at the wrong line.
ALTER TABLE public.inventory_count_sessions
  ADD COLUMN IF NOT EXISTS facility_id   BIGINT,
  ADD COLUMN IF NOT EXISTS status        TEXT NOT NULL DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS notes         TEXT,
  ADD COLUMN IF NOT EXISTS opened_by     BIGINT,
  ADD COLUMN IF NOT EXISTS opened_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS submitted_by  BIGINT,
  ADD COLUMN IF NOT EXISTS submitted_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS posted_by     BIGINT,
  ADD COLUMN IF NOT EXISTS posted_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_by  BIGINT,
  ADD COLUMN IF NOT EXISTS cancelled_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancel_reason TEXT;

-- One live count per shelf. Two people counting the same cupboard against two
-- snapshots is how a count becomes fiction.
CREATE UNIQUE INDEX IF NOT EXISTS uq_inventory_count_open_per_facility
  ON public.inventory_count_sessions (COALESCE(facility_id, -1))
  WHERE status IN ('open', 'review');

CREATE INDEX IF NOT EXISTS idx_inventory_count_sessions_status
  ON public.inventory_count_sessions (status, opened_at DESC);

COMMENT ON TABLE public.inventory_count_sessions IS
  'One physical stock count of one facility. Variance is not applied until the '
  'session is posted, which is a separate act from counting.';


-- ---------------------------------------------------------------------------
-- 2. One line per batch on the shelf when the count opened.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory_count_lines (
  count_line_id    BIGSERIAL PRIMARY KEY,
  count_id         BIGINT NOT NULL
                   REFERENCES public.inventory_count_sessions(count_id) ON DELETE CASCADE,
  batch_id         BIGINT NOT NULL
                   REFERENCES public.inventory_batches(batch_id) ON DELETE CASCADE,

  -- What the system believed when the count opened. Frozen on purpose: it is
  -- the number the variance was computed against and the number the posting
  -- guard re-checks.
  system_quantity  INTEGER NOT NULL,
  counted_quantity INTEGER,
  variance         INTEGER GENERATED ALWAYS AS (counted_quantity - system_quantity) STORED,

  reason           TEXT,
  counted_by       BIGINT REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  counted_at       TIMESTAMPTZ,

  CONSTRAINT chk_count_line_nonneg CHECK (counted_quantity IS NULL OR counted_quantity >= 0),
  CONSTRAINT uq_count_line UNIQUE (count_id, batch_id)
);

ALTER TABLE public.inventory_count_lines
  ADD COLUMN IF NOT EXISTS system_quantity  INTEGER,
  ADD COLUMN IF NOT EXISTS counted_quantity INTEGER,
  ADD COLUMN IF NOT EXISTS reason           TEXT,
  ADD COLUMN IF NOT EXISTS counted_by       BIGINT,
  ADD COLUMN IF NOT EXISTS counted_at       TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_inventory_count_lines_count
  ON public.inventory_count_lines (count_id);

COMMENT ON COLUMN public.inventory_count_lines.system_quantity IS
  'Batch quantity_remaining at the moment the count opened. Frozen: the '
  'posting guard compares it against the live quantity to detect stock that '
  'moved mid-count.';


-- ---------------------------------------------------------------------------
-- 3. Who may do what.
--
--    Written here rather than reusing inventory_assert_actor(), which takes a
--    single exact role. Counting is done by whoever holds the shelf — a midwife
--    at a barangay health centre, an officer at a depot — and posting belongs
--    to the portal tier.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_assert_count_actor(p_account_id BIGINT)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.accounts
     WHERE account_id = p_account_id
       AND status = 'active'
       AND account_type IN ('midwife', 'admin', 'mho')
  ) THEN
    RAISE EXCEPTION 'An active midwife, RHU or MHO account is required to count stock'
      USING ERRCODE = '42501';
  END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION public.inventory_assert_posting_actor(p_account_id BIGINT)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.accounts
     WHERE account_id = p_account_id
       AND status = 'active'
       AND account_type IN ('admin', 'mho')
  ) THEN
    RAISE EXCEPTION 'Only an RHU or MHO account may post a stock count'
      USING ERRCODE = '42501';
  END IF;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 4. Open a count: snapshot the shelf.
--
--    Every ACTIVE batch is listed, including ones the system believes are
--    empty. A count that only lists what the system expects to find cannot
--    discover stock the system lost track of, which is half the point.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.open_inventory_count(
  p_facility_id BIGINT,
  p_actor_id    BIGINT,
  p_notes       TEXT DEFAULT NULL
)
RETURNS public.inventory_count_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_session public.inventory_count_sessions%ROWTYPE;
  v_lines   INTEGER;
BEGIN
  PERFORM public.inventory_assert_count_actor(p_actor_id);

  IF EXISTS (
    SELECT 1 FROM public.inventory_count_sessions
     WHERE COALESCE(facility_id, -1) = COALESCE(p_facility_id, -1)
       AND status IN ('open', 'review')
  ) THEN
    RAISE EXCEPTION 'A stock count is already in progress at %',
      public.audit_facility_label(p_facility_id)
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.inventory_count_sessions (facility_id, opened_by, notes)
  VALUES (p_facility_id, p_actor_id, nullif(btrim(coalesce(p_notes, '')), ''))
  RETURNING * INTO v_session;

  INSERT INTO public.inventory_count_lines (count_id, batch_id, system_quantity)
  SELECT v_session.count_id, b.batch_id, COALESCE(b.quantity_remaining, 0)
    FROM public.inventory_batches b
   WHERE b.status = 'active'
     AND b.facility_id IS NOT DISTINCT FROM p_facility_id;

  GET DIAGNOSTICS v_lines = ROW_COUNT;

  IF v_lines = 0 THEN
    -- Nothing to count is not an error, but it is worth saying out loud rather
    -- than handing back an empty sheet that looks like a loading failure.
    RAISE NOTICE 'No active batches at %; the count sheet is empty.',
      public.audit_facility_label(p_facility_id);
  END IF;

  PERFORM public.audit_write(
    p_actor_id, 'inventory_count_opened', 'inventory_count_sessions',
    v_session.count_id::text,
    format('Stock count #%s', v_session.count_id),
    format('Opened a stock count at %s', public.audit_facility_label(p_facility_id)),
    format('A physical stock count was opened at %s covering %s active batch(es). '
           'Counted quantities do not affect stock until the count is posted.',
           public.audit_facility_label(p_facility_id), v_lines),
    '[]'::jsonb,
    jsonb_build_object('count_id', v_session.count_id, 'facility_id', p_facility_id),
    NULL, to_jsonb(v_session), 'notice', 'count'
  );

  RETURN v_session;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 5. Record what was on the shelf.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_inventory_count(
  p_count_id         BIGINT,
  p_batch_id         BIGINT,
  p_counted_quantity INTEGER,
  p_actor_id         BIGINT,
  p_reason           TEXT DEFAULT NULL
)
RETURNS public.inventory_count_lines
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_status TEXT;
  v_line   public.inventory_count_lines%ROWTYPE;
BEGIN
  PERFORM public.inventory_assert_count_actor(p_actor_id);

  IF p_counted_quantity IS NULL OR p_counted_quantity < 0 THEN
    RAISE EXCEPTION 'Counted quantity must be zero or more' USING ERRCODE = '22023';
  END IF;

  SELECT status INTO v_status
    FROM public.inventory_count_sessions WHERE count_id = p_count_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock count not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'open' THEN
    RAISE EXCEPTION 'Counts can only be entered while the session is open (this one is %)', v_status
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_count_lines
     SET counted_quantity = p_counted_quantity,
         reason           = nullif(btrim(coalesce(p_reason, '')), ''),
         counted_by       = p_actor_id,
         counted_at       = now()
   WHERE count_id = p_count_id AND batch_id = p_batch_id
  RETURNING * INTO v_line;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That batch is not on this count sheet' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_line;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 6. Submit for review. Nothing has touched stock yet.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_inventory_count(
  p_count_id BIGINT,
  p_actor_id BIGINT
)
RETURNS public.inventory_count_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_session public.inventory_count_sessions%ROWTYPE;
  v_missing INTEGER;
  v_varied  INTEGER;
BEGIN
  PERFORM public.inventory_assert_count_actor(p_actor_id);

  SELECT * INTO v_session FROM public.inventory_count_sessions
   WHERE count_id = p_count_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock count not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Only an open count can be submitted (this one is %)', v_session.status
      USING ERRCODE = '22023';
  END IF;

  SELECT count(*) INTO v_missing
    FROM public.inventory_count_lines
   WHERE count_id = p_count_id AND counted_quantity IS NULL;

  IF v_missing > 0 THEN
    RAISE EXCEPTION '% batch(es) on this sheet have not been counted yet', v_missing
      USING ERRCODE = '22023';
  END IF;

  SELECT count(*) INTO v_varied
    FROM public.inventory_count_lines
   WHERE count_id = p_count_id AND variance <> 0;

  UPDATE public.inventory_count_sessions
     SET status = 'review', submitted_by = p_actor_id, submitted_at = now()
   WHERE count_id = p_count_id
  RETURNING * INTO v_session;

  PERFORM public.audit_write(
    p_actor_id, 'inventory_count_submitted', 'inventory_count_sessions',
    p_count_id::text,
    format('Stock count #%s', p_count_id),
    format('Submitted stock count #%s for review', p_count_id),
    format('The count at %s was submitted with %s batch(es) differing from the '
           'recorded quantity. Stock is unchanged until the count is posted.',
           public.audit_facility_label(v_session.facility_id), v_varied),
    '[]'::jsonb,
    jsonb_build_object('count_id', p_count_id, 'facility_id', v_session.facility_id),
    NULL, to_jsonb(v_session),
    CASE WHEN v_varied > 0 THEN 'warning' ELSE 'notice' END,
    'count'
  );

  RETURN v_session;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 7. Post: the only step that changes stock.
-- ---------------------------------------------------------------------------
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

    UPDATE public.inventory_batches
       SET quantity_remaining = v_line.counted_quantity
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


-- ---------------------------------------------------------------------------
-- 8. Cancel. Nothing is deleted; the sheet stays readable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_inventory_count(
  p_count_id BIGINT,
  p_actor_id BIGINT,
  p_reason   TEXT
)
RETURNS public.inventory_count_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_session public.inventory_count_sessions%ROWTYPE;
BEGIN
  PERFORM public.inventory_assert_count_actor(p_actor_id);

  IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A reason is required to cancel a stock count' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_session FROM public.inventory_count_sessions
   WHERE count_id = p_count_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock count not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_session.status NOT IN ('open', 'review') THEN
    RAISE EXCEPTION 'A % count cannot be cancelled', v_session.status
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_count_sessions
     SET status = 'cancelled', cancelled_by = p_actor_id, cancelled_at = now(),
         cancel_reason = btrim(p_reason)
   WHERE count_id = p_count_id
  RETURNING * INTO v_session;

  PERFORM public.audit_write(
    p_actor_id, 'inventory_count_cancelled', 'inventory_count_sessions',
    p_count_id::text,
    format('Stock count #%s', p_count_id),
    format('Cancelled stock count #%s', p_count_id),
    format('The count at %s was cancelled without being posted. Reason: %s',
           public.audit_facility_label(v_session.facility_id), btrim(p_reason)),
    '[]'::jsonb,
    jsonb_build_object('count_id', p_count_id, 'facility_id', v_session.facility_id),
    NULL, to_jsonb(v_session), 'notice', 'count'
  );

  RETURN v_session;
END
$fn$;


-- ---------------------------------------------------------------------------
-- 9. What the portal reads.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_inventory_count_summary AS
SELECT s.count_id,
       s.facility_id,
       public.audit_facility_label(s.facility_id) AS facility_label,
       s.status,
       s.notes,
       s.opened_by, s.opened_at,
       s.submitted_by, s.submitted_at,
       s.posted_by, s.posted_at,
       s.cancelled_by, s.cancelled_at, s.cancel_reason,
       count(l.*)                                          AS lines_total,
       count(l.*) FILTER (WHERE l.counted_quantity IS NOT NULL) AS lines_counted,
       count(l.*) FILTER (WHERE l.variance <> 0)           AS lines_varied,
       COALESCE(sum(l.variance) FILTER (WHERE l.variance > 0), 0) AS units_gained,
       COALESCE(-sum(l.variance) FILTER (WHERE l.variance < 0), 0) AS units_lost
  FROM public.inventory_count_sessions s
  LEFT JOIN public.inventory_count_lines l ON l.count_id = s.count_id
 GROUP BY s.count_id;

COMMENT ON VIEW public.v_inventory_count_summary IS
  'One row per stock count with its progress and variance totals, so the portal '
  'does not have to aggregate count lines in the browser.';


-- ---------------------------------------------------------------------------
-- 10. Grants.
--
--     Same posture as the rest of the inventory RPCs: the portal authenticates
--     with account ids against the anon key, and each function asserts the
--     actor's role itself rather than trusting the caller.
-- ---------------------------------------------------------------------------
ALTER TABLE public.inventory_count_sessions DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_count_lines    DISABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.inventory_count_sessions TO anon, authenticated;
GRANT SELECT ON public.inventory_count_lines    TO anon, authenticated;
GRANT SELECT ON public.v_inventory_count_summary TO anon, authenticated;

REVOKE ALL ON FUNCTION public.inventory_assert_count_actor(BIGINT)   FROM PUBLIC;
REVOKE ALL ON FUNCTION public.inventory_assert_posting_actor(BIGINT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.open_inventory_count(BIGINT, BIGINT, TEXT)                TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_inventory_count(BIGINT, BIGINT, INTEGER, BIGINT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_inventory_count(BIGINT, BIGINT)                    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.post_inventory_count(BIGINT, BIGINT)                      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_inventory_count(BIGINT, BIGINT, TEXT)              TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 11. Join the live-refresh watch list (20260804), so a count opened on one
--     screen shows up on another without a second mechanism.
-- ---------------------------------------------------------------------------
DO $live$
DECLARE
  t TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'emit_admin_change_event'
  ) THEN
    RAISE NOTICE 'admin_change_events not installed; skipping live-refresh triggers.';
    RETURN;
  END IF;

  FOREACH t IN ARRAY ARRAY['inventory_count_sessions', 'inventory_count_lines'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_admin_live_%I ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_admin_live_%I AFTER INSERT OR UPDATE OR DELETE ON public.%I '
      'FOR EACH STATEMENT EXECUTE FUNCTION public.emit_admin_change_event()', t, t);
  END LOOP;
END
$live$;

COMMIT;


-- ---------------------------------------------------------------------------
-- Verify.
-- ---------------------------------------------------------------------------

-- A dry run against one facility, end to end:
--
--   SELECT * FROM public.open_inventory_count(2, <admin_account_id>, 'Monthly count');
--   SELECT batch_id, system_quantity FROM public.inventory_count_lines WHERE count_id = <id>;
--   SELECT * FROM public.record_inventory_count(<id>, <batch>, 37, <account>, 'Two boxes water damaged');
--   SELECT * FROM public.submit_inventory_count(<id>, <account>);
--   SELECT * FROM public.post_inventory_count(<id>, <admin_account_id>);
--
-- The adjustment rows it wrote, and the audit entries they produced:
--
--   SELECT transaction_id, batch_id, quantity, resulting_quantity_remaining, notes
--     FROM public.inventory_transactions
--    WHERE reference_type = 'inventory_count_sessions' ORDER BY transaction_id DESC;

SELECT count_id, facility_label, status, lines_total, lines_counted,
       lines_varied, units_gained, units_lost
  FROM public.v_inventory_count_summary
 ORDER BY count_id DESC
 LIMIT 20;


-- ============================================================
-- ROLLBACK
-- ============================================================
-- DROP VIEW IF EXISTS public.v_inventory_count_summary;
-- DROP FUNCTION IF EXISTS public.cancel_inventory_count(BIGINT, BIGINT, TEXT);
-- DROP FUNCTION IF EXISTS public.post_inventory_count(BIGINT, BIGINT);
-- DROP FUNCTION IF EXISTS public.submit_inventory_count(BIGINT, BIGINT);
-- DROP FUNCTION IF EXISTS public.record_inventory_count(BIGINT, BIGINT, INTEGER, BIGINT, TEXT);
-- DROP FUNCTION IF EXISTS public.open_inventory_count(BIGINT, BIGINT, TEXT);
-- DROP FUNCTION IF EXISTS public.inventory_assert_posting_actor(BIGINT);
-- DROP FUNCTION IF EXISTS public.inventory_assert_count_actor(BIGINT);
-- DROP TABLE IF EXISTS public.inventory_count_lines;
-- DROP TABLE IF EXISTS public.inventory_count_sessions;
--
-- Adjustment rows already posted are deliberately NOT removed: they are real
-- stock movements that other figures now depend on.
