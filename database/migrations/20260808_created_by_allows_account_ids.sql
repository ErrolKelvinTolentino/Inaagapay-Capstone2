-- InaAgapay: let accounts.created_by hold the creator's account id
--
-- WHY
-- ---
-- accounts_created_by_check admits only the two original literals, 'self'
-- and 'midwife'. The application outgrew that. created_by now records *who*
-- created the row, not merely what kind of actor did:
--
--     'self'                — self-registered, before an id was available
--     the row's own id      — self-registered, stamped just after insert
--     another account's id  — created by that midwife
--     'midwife'             — midwife whose account id could not be resolved
--
-- Registration inserts with 'self', reads back the new account_id, then
-- stamps it (supabase_service.dart, registerWithOTP). That second write is
-- what the constraint rejects, so **creating a brand-new self-registered
-- account fails outright** — insert succeeds, update raises 23514, and the
-- row is left behind unverified. Existing-account paths never re-stamp
-- created_by, which is why this stayed hidden: only first-time
-- self-registration touches it.
--
-- run_this_in_supabase.sql:42 carries a bare DROP for this constraint, but
-- it was never applied to the live database. Dropping outright also gives
-- up the check entirely, which is more than the situation calls for.
--
-- FIX
-- ---
-- Replace it with one that admits the values actually written: the two
-- literals, or a string of digits. That unblocks registration, keeps a
-- guard against junk, and states the convention in the schema instead of
-- leaving it to be reverse-engineered from three call sites.
--
-- Reading it back is SupabaseService.isMidwifeCreated(), which treats
-- 'self' and the row's own id as self-registered and anything else as
-- midwife-created.
--
-- NULL is permitted: the column is nullable, and a CHECK passes on NULL.

BEGIN;

ALTER TABLE public.accounts
  DROP CONSTRAINT IF EXISTS accounts_created_by_check;

ALTER TABLE public.accounts
  ADD CONSTRAINT accounts_created_by_check
  CHECK (
    created_by IS NULL
    OR created_by IN ('self', 'midwife')
    OR created_by ~ '^[0-9]+$'
  );

COMMENT ON COLUMN public.accounts.created_by IS
  'Provenance: ''self'' or the row''s own account_id for self-registration; '
  'another account''s id (or ''midwife'') when a midwife created it. '
  'Read via SupabaseService.isMidwifeCreated().';

COMMIT;
