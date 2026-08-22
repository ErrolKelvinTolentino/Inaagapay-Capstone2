-- ==============================================================================
-- MIGRATION: 20260824_inventory_integration_fixes.sql
--
-- Repairs the seams between the inventory module and everything around it.
-- Each section stands alone; nothing here changes how stock is counted.
--
--  (1) ROTAVIRUS HAD NO INVENTORY ITEM
--      Rotavirus Vaccine is seeded as a two-dose child vaccine on the DOH
--      schedule, but no seed file ever created a catalogue item for it and no
--      linkage rule mentioned it. vaccines.inventory_item_id stayed null, every
--      name-matching fallback missed, and the immunisation screen read the
--      absence as "none left" — so the one vaccine nobody could record was the
--      one nobody had noticed was unstocked.
--
--  (2) STOCK REQUESTS COULD NOT BE ARCHIVED
--      The portal has an archive button and an Archived filter, but is_archived
--      was only ever added to inventory_items. The column the feature needs did
--      not exist on inventory_stock_requests at all.
--
--  (3) ISSUING STOCK NOTIFIED NOBODY AND AUDITED NOTHING
--      20260818 rewrote issue_inventory_transfer and, in doing so, dropped the
--      notification and audit_trail writes the 20260803 version had. Since then
--      a midwife has only learned that stock was issued to her by opening the
--      app and noticing, and the single most consequential inventory action —
--      moving stock between facilities — left no audit record.
--
--      This is repaired with a trigger rather than another rewrite of a
--      268-line function, so the FEFO, safety-check and approved-quantity work
--      layered into that RPC across four migrations is not disturbed. The
--      trigger also covers the MHO -> RHU leg, where the destination has no
--      midwives and therefore nobody was ever notified.
--
--  (4) INVENTORY NOTIFICATIONS WERE TYPED 'general'
--      The midwife notification centre routes on the type column and looked for
--      'inventory', which nothing ever wrote, so stock alerts were filed as
--      clinical. The type check constraint now admits 'inventory' and a trigger
--      stamps it, giving the app a stable discriminator that does not depend on
--      the English wording of a title.
--
--  (5) THE IMMUNISATION LIVE-REFRESH TRIGGER WAS NEVER CREATED
--      20260804 listed 'immunization_record'. The table is immunization_records.
--      to_regclass returned null, the loop skipped it silently, and recording a
--      dose has never emitted a change event.
--
-- Requires 20260821_mho_tier.sql and 20260823_prenatal_dispense_fixes.sql.
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. Rotavirus: catalogue item, then linkage
-- ---------------------------------------------------------------------------

-- Monovalent human rotavirus vaccine, supplied as a single-dose oral
-- applicator, so one unit is one dose. The threshold matches its EPI peers.
INSERT INTO public.inventory_items
  (name, generic_name, item_type, unit_of_measure, doses_per_unit,
   minimum_stock_threshold, is_archived)
VALUES
  ('Rotavirus Vaccine', 'Human Rotavirus Vaccine (Oral)', 'vaccine',
   'vials', 1, 25, false)
ON CONFLICT (name) DO UPDATE
  SET item_type       = EXCLUDED.item_type,
      generic_name    = COALESCE(inventory_items.generic_name, EXCLUDED.generic_name),
      unit_of_measure = EXCLUDED.unit_of_measure,
      is_archived     = false;

-- Link every vaccine row that still has no catalogue item. The rule list is the
-- union of the three earlier passes plus rotavirus, which each of them omitted.
UPDATE public.vaccines v
   SET inventory_item_id = i.item_id
  FROM public.inventory_items i
 WHERE v.inventory_item_id IS NULL
   AND i.is_archived = false
   AND (
        LOWER(i.name) = LOWER(v.vaccine_name)
     OR (v.vaccine_name ILIKE '%rotavirus%' AND i.name ILIKE '%rotavirus%')
     OR (v.vaccine_name ILIKE '%bcg%'       AND i.name ILIKE '%bcg%')
     OR (v.vaccine_name ILIKE '%opv%'       AND i.name ILIKE '%opv%')
     OR (v.vaccine_name ILIKE '%ipv%'       AND i.name ILIKE '%ipv%')
     OR (v.vaccine_name ILIKE '%penta%'     AND i.name ILIKE '%penta%')
     OR (v.vaccine_name ILIKE '%pcv%'       AND i.name ILIKE '%pcv%')
     OR (v.vaccine_name ILIKE '%measles%'   AND (i.name ILIKE '%mr%' OR i.name ILIKE '%measles%'))
     OR (v.vaccine_name ILIKE '%mmr%'       AND (i.name ILIKE '%mmr%' OR i.name ILIKE '%measles%'))
     OR (v.vaccine_name ILIKE '%hep%'       AND i.name ILIKE '%hep%')
     OR (v.vaccine_name ILIKE '%td%'        AND (i.name ILIKE '%td%' OR i.name ILIKE '%tetanus%'))
     OR (v.vaccine_name ILIKE '%tetanus%'   AND i.name ILIKE '%tetanus%')
   );


-- ---------------------------------------------------------------------------
-- 2. Archiving a stock request
-- ---------------------------------------------------------------------------
ALTER TABLE public.inventory_stock_requests
  ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_inventory_stock_requests_archived
  ON public.inventory_stock_requests(is_archived, created_at DESC);

COMMENT ON COLUMN public.inventory_stock_requests.is_archived IS
  'Hidden from the portal''s active request list. Archiving never changes status.';


-- ---------------------------------------------------------------------------
-- 3. Notification type: admit 'inventory'
-- ---------------------------------------------------------------------------
-- Discovered by name because the original was declared inline, the same way
-- 20260821 handled the account_type and facility_type checks.
DO $do$
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
  LOOP
    EXECUTE format('ALTER TABLE public.notifications DROP CONSTRAINT %I', r.conname);
  END LOOP;
END
$do$;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('checkup_reminder', 'vaccine_reminder', 'general', 'inventory'));


-- ---------------------------------------------------------------------------
-- 4. Stamp inventory notifications with their type
-- ---------------------------------------------------------------------------
-- The four titles below are written by the distribution RPCs. Rather than
-- rewrite each of those functions, this classifies on the way in, so the app
-- can key off a stable column instead of matching English prose.
CREATE OR REPLACE FUNCTION public.tag_inventory_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF NEW.type IS DISTINCT FROM 'inventory'
     AND lower(coalesce(NEW.title, '')) IN (
       'new stock request',
       'stock request approved',
       'stock request update',
       'incoming stocks from rhu main',
       'incoming stocks',
       'low stock after activity'
     )
  THEN
    NEW.type := 'inventory';
  END IF;
  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_tag_inventory_notification ON public.notifications;
CREATE TRIGGER trg_tag_inventory_notification
  BEFORE INSERT OR UPDATE OF title ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.tag_inventory_notification();

-- Existing rows, so a midwife's history is categorised the same as new arrivals.
UPDATE public.notifications
   SET type = 'inventory'
 WHERE type IS DISTINCT FROM 'inventory'
   AND lower(coalesce(title, '')) IN (
     'new stock request',
     'stock request approved',
     'stock request update',
     'incoming stocks from rhu main',
     'incoming stocks',
     'low stock after activity'
   );


-- ---------------------------------------------------------------------------
-- 5. Issuing stock notifies the destination and writes an audit row
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.announce_inventory_transfer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_item_name   TEXT;
  v_dest_name   TEXT;
  v_source_name TEXT;
  v_recipients  INTEGER := 0;
BEGIN
  SELECT i.name
    INTO v_item_name
    FROM public.inventory_batches b
    JOIN public.inventory_items i ON i.item_id = b.item_id
   WHERE b.batch_id = NEW.source_batch_id;

  SELECT name INTO v_dest_name
    FROM public.health_facilities WHERE facility_id = NEW.destination_facility_id;

  SELECT hf.name
    INTO v_source_name
    FROM public.inventory_batches b
    LEFT JOIN public.health_facilities hf ON hf.facility_id = b.facility_id
   WHERE b.batch_id = NEW.source_batch_id;

  -- A batch sitting at facility_id NULL is the municipal warehouse.
  v_source_name := COALESCE(v_source_name, 'the municipal warehouse');
  v_item_name   := COALESCE(v_item_name, 'stock');
  v_dest_name   := COALESCE(v_dest_name, 'your facility');

  -- Midwives at the destination. This is the RHU -> BHC case.
  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT m.account_id,
         'Incoming stocks',
         format('%s units of %s from %s are waiting for your receipt confirmation.',
                NEW.quantity_issued, v_item_name, v_source_name),
         'inventory'
    FROM public.midwives m
    JOIN public.accounts a ON a.account_id = m.account_id
   WHERE m.assigned_bhc_id = NEW.destination_facility_id
     AND a.status = 'active';

  GET DIAGNOSTICS v_recipients = ROW_COUNT;

  -- No midwives means the destination is an RHU receiving a municipal
  -- dispatch. Tell the officers who run that facility instead, or the transfer
  -- arrives with nobody informed.
  IF v_recipients = 0 THEN
    INSERT INTO public.notifications (account_id, title, message, type)
    SELECT DISTINCT a.account_id,
           'Incoming stocks',
           format('%s units of %s from %s are waiting for your receipt confirmation.',
                  NEW.quantity_issued, v_item_name, v_source_name),
           'inventory'
      FROM public.facility_assignments fa
      JOIN public.accounts a ON a.account_id = fa.account_id
     WHERE fa.facility_id = NEW.destination_facility_id
       AND COALESCE(fa.is_active, true)
       AND a.status = 'active'
       AND a.account_type IN ('admin', 'mho');
  END IF;

  INSERT INTO public.audit_trail (
    account_id, action, table_name, description, new_data
  ) VALUES (
    NEW.issued_by,
    'issue_inventory_transfer',
    'inventory_transfers',
    format('Issued %s unit(s) of %s to %s (transfer #%s)',
           NEW.quantity_issued, v_item_name, v_dest_name, NEW.transfer_id),
    to_jsonb(NEW)
  );

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_announce_inventory_transfer ON public.inventory_transfers;

-- Only attach the trigger if the installed issue_inventory_transfer does not
-- already write its own notification. The 20260803 version did; the 20260818
-- rewrite that is expected here does not. Checking rather than assuming means a
-- database that skipped 20260818 gets one notification instead of two.
DO $do$
DECLARE
  v_src TEXT;
BEGIN
  SELECT string_agg(pg_get_functiondef(p.oid), E'\n')
    INTO v_src
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'issue_inventory_transfer';

  IF v_src IS NULL OR position('notifications' in v_src) = 0 THEN
    CREATE TRIGGER trg_announce_inventory_transfer
      AFTER INSERT ON public.inventory_transfers
      FOR EACH ROW EXECUTE FUNCTION public.announce_inventory_transfer();
  ELSE
    RAISE NOTICE
      'issue_inventory_transfer already writes its own notification; '
      'trg_announce_inventory_transfer not attached. Apply '
      '20260818_advanced_inventory_features.sql, then re-run this migration.';
  END IF;
END
$do$;


-- ---------------------------------------------------------------------------
-- 6. The live-refresh trigger that never got created
-- ---------------------------------------------------------------------------
-- 20260804 named 'immunization_record'; the table is immunization_records, so
-- its to_regclass guard skipped it without complaint.
DO $do$
BEGIN
  IF to_regclass('public.immunization_records') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_admin_live_immunization_records ON public.immunization_records;
    CREATE TRIGGER trg_admin_live_immunization_records
      AFTER INSERT OR UPDATE OR DELETE ON public.immunization_records
      FOR EACH STATEMENT EXECUTE FUNCTION public.emit_admin_change_event();
  END IF;
END
$do$;


-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.tag_inventory_notification()    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.announce_inventory_transfer()   TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 8. Verification
-- ---------------------------------------------------------------------------
-- Every child or mother vaccine should now resolve to a catalogue item.
--
--   SELECT vaccine_name, dose_number, inventory_item_id
--     FROM public.vaccines
--    WHERE inventory_item_id IS NULL
--    ORDER BY vaccine_name, dose_number;
--
-- Expect zero rows. Anything listed has no catalogue item under a name the
-- rules above can match, and will read as "stock not tracked" in the app.
