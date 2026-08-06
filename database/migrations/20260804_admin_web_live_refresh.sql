-- Sanitized realtime change feed for the hosted admin portal.
--
-- This migration never copies row contents into the feed. It publishes only
-- the changed table name, operation, and timestamp, which lets each admin page
-- re-run its existing filtered Supabase queries without exposing medical or
-- account records through Realtime payloads.

BEGIN;

CREATE TABLE IF NOT EXISTS public.admin_change_events (
  event_id BIGSERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_change_events_changed_at
  ON public.admin_change_events(changed_at DESC);

ALTER TABLE public.admin_change_events DISABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_change_events FROM anon, authenticated;
GRANT SELECT ON public.admin_change_events TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.emit_admin_change_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.admin_change_events(table_name, operation)
  VALUES (TG_TABLE_NAME, TG_OP);

  DELETE FROM public.admin_change_events
  WHERE changed_at < now() - interval '7 days';
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.emit_admin_change_event() FROM PUBLIC;

DO $$
DECLARE
  watched_table TEXT;
BEGIN
  FOREACH watched_table IN ARRAY ARRAY[
    'accounts',
    'audit_trail',
    'bhc',
    'health_facilities',
    'facility_assignments',
    'midwives',
    'mothers',
    'pregnancies',
    'prenatal_checkups',
    'ultrasounds',
    'lab_tests',
    'children',
    'birth_details',
    'immunization_record',
    'inventory_items',
    'inventory_batches',
    'inventory_transactions',
    'inventory_stock_requests',
    'inventory_transfers',
    'notifications'
  ] LOOP
    IF to_regclass(format('public.%I', watched_table)) IS NOT NULL THEN
      EXECUTE format(
        'DROP TRIGGER IF EXISTS trg_admin_live_%I ON public.%I',
        watched_table,
        watched_table
      );
      EXECUTE format(
        'CREATE TRIGGER trg_admin_live_%I '
        'AFTER INSERT OR UPDATE OR DELETE ON public.%I '
        'FOR EACH STATEMENT EXECUTE FUNCTION public.emit_admin_change_event()',
        watched_table,
        watched_table
      );
    END IF;
  END LOOP;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'admin_change_events'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.admin_change_events;
  END IF;
END;
$$;

COMMIT;
