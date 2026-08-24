-- ==============================================================================
-- 01_verify_audit_trail.sql  —  SAFE. Writes nothing permanent.
--
-- Everything below runs inside BEGIN ... ROLLBACK, so every row it touches is
-- discarded when it finishes. Run it after
-- 20260826_audit_trail_completeness.sql to confirm the triggers fire, produce
-- readable notes, and — the part that actually matters — cannot abort the
-- write that triggered them.
--
-- WHY THE SECOND POINT MATTERS
--
-- These are AFTER triggers. An unhandled error inside one does not just lose an
-- audit row: it rolls back the statement that fired it. The accounts trigger
-- runs on every sign-in, so a fault there would lock everyone out of the
-- portal. This script exercises that path first, deliberately.
--
-- HOW TO READ THE RESULT
--
-- The final SELECT lists every audit row the test produced. Expect roughly six.
-- If the script raises an error instead, the message names the trigger at
-- fault and nothing has been changed.
--
-- The ROLLBACK at the end is not optional and not a formality. Do not replace
-- it with COMMIT.
-- ==============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The sign-in path.
--
-- Touching only last_login_at / updated_at is what logging in looks like. The
-- trigger recognises that shape and deliberately writes NOTHING, because the
-- portal already logs its own 'login' row with the detail it has. Two rows for
-- one sign-in would be noise.
--
-- So the pass condition here is the ABSENCE of a row, plus the absence of an
-- error.
-- ---------------------------------------------------------------------------
UPDATE public.accounts
   SET last_login_at = now(),
       updated_at    = now()
 WHERE account_id = (SELECT MIN(account_id) FROM public.accounts);


-- ---------------------------------------------------------------------------
-- 2. A real account change. This one SHOULD produce a row.
--
-- phone_number is used because it is harmless, visible, and not a credential.
-- Note what the audit row does with it: the value is recorded, because a phone
-- number is not a secret. Had this been password_hash, audit_redact() would
-- have stored '[redacted]' instead.
-- ---------------------------------------------------------------------------
UPDATE public.accounts
   SET phone_number = COALESCE(phone_number, '') || '-AUDITTEST'
 WHERE account_id = (SELECT MIN(account_id) FROM public.accounts);


-- ---------------------------------------------------------------------------
-- 3. The catalogue.
-- ---------------------------------------------------------------------------
UPDATE public.inventory_items
   SET minimum_stock_threshold = COALESCE(minimum_stock_threshold, 0) + 1
 WHERE item_id = (SELECT MIN(item_id) FROM public.inventory_items);


-- ---------------------------------------------------------------------------
-- 4. A batch losing stock.
-- ---------------------------------------------------------------------------
UPDATE public.inventory_batches
   SET quantity_remaining = quantity_remaining - 1
 WHERE batch_id = (
   SELECT MIN(batch_id) FROM public.inventory_batches WHERE quantity_remaining > 0
 );


-- ---------------------------------------------------------------------------
-- 5. The movement ledger — the entry the whole exercise was about.
--
-- Written as a SELECT rather than VALUES so it inserts nothing when there is no
-- usable batch, instead of failing on a null foreign key.
-- ---------------------------------------------------------------------------
INSERT INTO public.inventory_transactions
  (batch_id, facility_id, transaction_type, quantity, reference_type, performed_by)
SELECT b.batch_id,
       b.facility_id,
       'adjustment',
       -1,
       'AUDIT SELF-TEST (rolled back)',
       (SELECT MIN(account_id) FROM public.accounts)
  FROM public.inventory_batches b
 WHERE b.quantity_remaining > 0
 ORDER BY b.batch_id
 LIMIT 1;


-- ---------------------------------------------------------------------------
-- 6. An application-written row, the way admin-web and the Flutter app write.
--
-- It arrives with four columns and no context. The enrichment trigger should
-- give it an actor snapshot, a module, a severity and a narrative on the way
-- in, without the caller changing at all.
-- ---------------------------------------------------------------------------
INSERT INTO public.audit_trail (account_id, action, table_name, description)
VALUES (
  (SELECT MIN(account_id) FROM public.accounts),
  'login',
  'accounts',
  'AUDIT SELF-TEST: application-style row with no context supplied'
);


-- ---------------------------------------------------------------------------
-- 7. What the triggers produced.
--
-- event_txid is stamped with txid_current(), so this transaction can ask for
-- exactly its own rows and nothing else.
-- ---------------------------------------------------------------------------
SELECT
  module,
  severity,
  action,
  actor_name,
  COALESCE(actor_facility_name, '-')                         AS acting_from,
  COALESCE(entity_label, '-')                                AS record,
  source,
  left(COALESCE(narrative, description, ''), 160) || '...'   AS note_opening,
  jsonb_array_length(COALESCE(details->'sections', '[]'::jsonb)) AS detail_sections
FROM public.audit_trail
WHERE event_txid = txid_current()
ORDER BY audit_id;


-- ---------------------------------------------------------------------------
-- 8. Read one note in full, to see what the printed record will say.
-- ---------------------------------------------------------------------------
SELECT narrative
FROM public.audit_trail
WHERE event_txid = txid_current()
  AND module = 'Inventory'
ORDER BY audit_id DESC
LIMIT 1;


-- ---------------------------------------------------------------------------
-- 9. Confirm no credential VALUE is stored anywhere in the audit trail.
--
-- Deliberately scans the whole table, not just this transaction, so it also
-- proves the backfill scrubbed the rows written before redaction existed.
--
-- Testing for the key alone would flag every clean row: audit_redact() keeps
-- the key and replaces the value, precisely so a reader can see that the field
-- took part in the change. What must not appear is a value other than
-- '[redacted]'.
--
-- Expect ZERO rows. Anything here means a writer is getting past
-- audit_redact() — stop and report it.
-- ---------------------------------------------------------------------------
WITH secret_keys(k) AS (
  VALUES ('password_hash'), ('password'), ('pending_password_hash'),
         ('temporary_password'), ('verification_code'), ('reset_code'),
         ('last_login_token')
)
SELECT t.audit_id,
       t.action,
       t.action_timestamp,
       'CREDENTIAL VALUE STORED IN AUDIT TRAIL' AS problem
FROM public.audit_trail t
-- The type guard sits on the ARGUMENT, not in the WHERE: a set-returning
-- function in FROM is evaluated before the WHERE clause, so filtering there
-- would not stop jsonb_each_text() choking on a non-object. Passing NULL
-- instead yields zero rows, because the function is strict.
WHERE EXISTS (
        SELECT 1
          FROM jsonb_each_text(
                 CASE WHEN jsonb_typeof(t.old_data) = 'object' THEN t.old_data END
               ) AS kv(k, v)
         WHERE kv.k IN (SELECT k FROM secret_keys)
           AND kv.v IS DISTINCT FROM '[redacted]'
      )
   OR EXISTS (
        SELECT 1
          FROM jsonb_each_text(
                 CASE WHEN jsonb_typeof(t.new_data) = 'object' THEN t.new_data END
               ) AS kv(k, v)
         WHERE kv.k IN (SELECT k FROM secret_keys)
           AND kv.v IS DISTINCT FROM '[redacted]'
      );


ROLLBACK;

-- ==============================================================================
-- Everything above is now discarded.
--
-- WHAT A PASS LOOKS LIKE
--
--   * No error was raised.
--   * Step 7 lists rows for the account change, the catalogue change, the batch
--     change, the ledger movement, and the application-style row — the last of
--     which has an actor_name, a module and a severity it never supplied.
--   * There is NO row for step 1. The sign-in path is deliberately silent.
--   * Step 8 prints a paragraph a person can read without knowing the schema.
--   * Step 9 returns nothing.
--
-- THEN TEST IT FOR REAL, IN THE PORTAL
--
--   1. Sign out and back in. This is the path a broken accounts trigger would
--      block, and it is worth confirming against the live app rather than only
--      against this script.
--   2. Issue a transfer from Inventory Management.
--   3. Open Activity Log. Expect at least three new Inventory entries for that
--      one dispatch: the transfer, the ledger movement, and the source batch
--      going down. Open the transfer entry and read the note: it should name
--      both facilities, the batch, the approval and the quantities.
--   4. Press "Print this record" and check the page preview.
-- ==============================================================================
