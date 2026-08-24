-- ==============================================================================
-- 00_check_migration_state.sql  —  READ ONLY. Changes nothing.
--
-- Run this FIRST, in the Supabase SQL editor, whenever a migration stops with
-- "Prerequisite missing" or "function ... does not exist".
--
-- WHY THIS EXISTS
--
-- The migrations in this folder are applied by hand, so a database can be
-- missing one from the middle of the run while having later ones. Discovering
-- that one error at a time is slow: each attempt fails on the first thing it
-- happens to touch, and a migration that is not wrapped in BEGIN/COMMIT can
-- leave you unsure how much of it took.
--
-- This script probes for the object each migration creates and prints one row
-- per check: what is missing, and which file supplies it. Nothing is created,
-- altered or dropped, so it is safe to run at any time and as often as you like.
--
-- HOW TO READ THE RESULT
--
--   status = 'OK'      the object is present, nothing to do
--   status = 'MISSING' run the file named in the "supplied_by" column
--
-- Run the MISSING files in the order they are listed (top to bottom), then run
-- this script again until every row says OK.
--
-- NOTE ON THE SUPABASE SQL EDITOR
--
-- The editor sends a whole script as one message, which PostgreSQL runs inside
-- a single implicit transaction. If any statement fails, EVERYTHING in that
-- script is rolled back — including the parts that appeared to succeed before
-- the error. So a migration that stopped with an error has applied nothing, and
-- re-running it after fixing the prerequisite is both safe and necessary.
-- ==============================================================================

WITH checks(sort_order, requirement, supplied_by, present) AS (
  VALUES
    -- ---- foundation -------------------------------------------------------
    (10, 'table accounts',
         'database/supabase_setup.sql (or active-draftschema.sql)',
         to_regclass('public.accounts') IS NOT NULL),
    (11, 'table audit_trail',
         'database/supabase_setup.sql (or active-draftschema.sql)',
         to_regclass('public.audit_trail') IS NOT NULL),
    (12, 'table health_facilities',
         'database/supabase_setup.sql (or active-draftschema.sql)',
         to_regclass('public.health_facilities') IS NOT NULL),
    (13, 'table facility_assignments',
         'database/supabase_setup.sql (or active-draftschema.sql)',
         to_regclass('public.facility_assignments') IS NOT NULL),
    (14, 'table inventory_items / batches / transactions',
         'database/supabase_setup.sql (or active-draftschema.sql)',
         to_regclass('public.inventory_items') IS NOT NULL
         AND to_regclass('public.inventory_batches') IS NOT NULL
         AND to_regclass('public.inventory_transactions') IS NOT NULL),

    -- ---- 20260803 ---------------------------------------------------------
    (20, 'table inventory_stock_requests',
         '20260803_inventory_distribution_workflow.sql',
         to_regclass('public.inventory_stock_requests') IS NOT NULL),
    (21, 'table inventory_transfers',
         '20260803_inventory_distribution_workflow.sql',
         to_regclass('public.inventory_transfers') IS NOT NULL),
    (22, 'function inventory_assert_actor()',
         '20260803_inventory_distribution_workflow.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'inventory_assert_actor')),

    -- ---- 20260804 ---------------------------------------------------------
    -- This is the one that stops 20260824 part-way through section 6.
    (30, 'function emit_admin_change_event()',
         '20260804_admin_web_live_refresh.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'emit_admin_change_event')),
    (31, 'table admin_change_events',
         '20260804_admin_web_live_refresh.sql',
         to_regclass('public.admin_change_events') IS NOT NULL),

    -- ---- 20260806 ---------------------------------------------------------
    (40, 'column inventory_stock_requests.approved_quantity',
         '20260806_inventory_audit_fixes.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='inventory_stock_requests'
                    AND column_name='approved_quantity')),
    (41, 'table inventory_disposals',
         '20260806_inventory_audit_fixes.sql',
         to_regclass('public.inventory_disposals') IS NOT NULL),
    (42, 'columns inventory_items.generic_name / item_code',
         '20260806_inventory_item_details.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='inventory_items'
                    AND column_name='generic_name')),
    -- Checked by function, not by column: this migration adds no columns at
    -- all. It folds the delivery plan into inventory_transfers.remarks as text.
    (43, 'function update_inventory_transfer_delivery()',
         '20260806_inventory_transfer_delivery_updates.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'update_inventory_transfer_delivery')),

    -- ---- 20260808 ---------------------------------------------------------
    (50, 'column inventory_items.is_archived',
         '20260808_inventory_item_archiving.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='inventory_items'
                    AND column_name='is_archived')),

    -- ---- 20260818 / 20260819 ---------------------------------------------
    (60, 'columns inventory_batches.open_vials_count / doses_remaining_in_open_vial',
         '20260819_solidify_multi_dose_open_vial_system.sql (or 20260822)',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='inventory_batches'
                    AND column_name='open_vials_count')),

    -- ---- 20260821 ---------------------------------------------------------
    (70, 'function resolve_actor_account_id()',
         '20260821_inventory_and_td_fixes.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'resolve_actor_account_id')),
    (71, 'function admin_assigned_facility_id()',
         '20260821_mho_tier.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'admin_assigned_facility_id')),

    -- ---- 20260822 ---------------------------------------------------------
    (80, 'column inventory_transactions.dose_quantity',
         '20260822_dose_accounting.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='inventory_transactions'
                    AND column_name='dose_quantity')),
    (81, 'column inventory_items.doses_per_unit',
         '20260822_dose_accounting.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='inventory_items'
                    AND column_name='doses_per_unit')),
    (82, 'function dispense_stock_doses()',
         '20260822_dose_accounting.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'dispense_stock_doses')),

    -- ---- 20260824 ---------------------------------------------------------
    (90, 'column inventory_stock_requests.is_archived',
         '20260824_inventory_integration_fixes.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='inventory_stock_requests'
                    AND column_name='is_archived')),
    (91, 'function announce_inventory_transfer()',
         '20260824_inventory_integration_fixes.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'announce_inventory_transfer')),

    -- ---- 20260826 (the detailed audit trail itself) -----------------------
    (100, 'column audit_trail.narrative',
          '20260826_audit_trail_completeness.sql',
          EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='audit_trail'
                     AND column_name='narrative')),
    (101, 'view audit_trail_detailed',
          '20260826_audit_trail_completeness.sql',
          to_regclass('public.audit_trail_detailed') IS NOT NULL),
    (102, 'trigger trg_audit_inventory_transfer',
          '20260826_audit_trail_completeness.sql',
          EXISTS (SELECT 1 FROM pg_trigger
                   WHERE tgname = 'trg_audit_inventory_transfer' AND NOT tgisinternal)),
    (103, 'trigger trg_audit_inventory_transaction',
          '20260826_audit_trail_completeness.sql',
          EXISTS (SELECT 1 FROM pg_trigger
                   WHERE tgname = 'trg_audit_inventory_transaction' AND NOT tgisinternal))
)
SELECT
  CASE WHEN present THEN 'OK' ELSE 'MISSING' END AS status,
  requirement,
  CASE WHEN present THEN '' ELSE supplied_by END AS run_this_file
FROM checks
ORDER BY present, sort_order;


-- ------------------------------------------------------------------------
-- Once every row above says OK, confirm the audit trail is actually
-- recording. Issue or receive one transfer in the portal, then:
--
--   SELECT action_timestamp, module, severity, action, actor_name,
--          entity_label, description
--     FROM public.audit_trail_detailed
--    ORDER BY audit_id DESC
--    LIMIT 20;
--
-- Expect at least three rows for a single dispatch: the transfer, the ledger
-- movement, and the source batch going down.
-- ------------------------------------------------------------------------
