-- InaAgapay: hold a registrant's password until the OTP is verified
--
-- WHY
-- ---
-- Registration wrote the new password straight into accounts.password_hash
-- and *then* sent the OTP. The one-time code gated is_verified; it never
-- gated the password.
--
-- The consequence is on the re-registration path. When someone registers
-- with a contact that already has an unverified account, the code updates
-- that existing row in place:
--
--     UPDATE accounts SET password_hash = <new>, verification_code = <otp>
--      WHERE phone_number = <contact>
--
-- Nothing there proves the person at the keyboard holds the phone. Knowing
-- an unverified account's number is enough to overwrite its password hash,
-- and the real owner's password stops working — without the attacker ever
-- receiving the code.
--
-- Login blocks unverified accounts, so this squats an account rather than
-- taking it over. That distinction disappears the moment anything else
-- flips is_verified, so it is not a distinction worth resting on.
--
-- FIX
-- ---
-- Park the hash in pending_password_hash at registration and promote it to
-- password_hash only inside verifyCode, once the OTP has been matched and
-- found unexpired. Holding the phone becomes a precondition for setting the
-- password rather than a later formality.
--
-- A brand-new registrant therefore has a NULL password_hash until she
-- verifies. That is already safe: _verifyPassword returns false on an empty
-- hash before reaching bcrypt (supabase_service.dart:35).
--
-- Existing rows need no backfill. A NULL pending_password_hash means
-- "nothing staged", which is the correct state for every account that
-- completed registration before this migration.

BEGIN;

ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS pending_password_hash character varying;

COMMENT ON COLUMN public.accounts.pending_password_hash IS
  'Bcrypt hash staged during registration, promoted to password_hash only '
  'after the OTP is verified. NULL means nothing is staged. Never read for '
  'authentication.';

COMMIT;
