-- ===========================================================================
-- 20260929_profile_photo_storage.sql
--
-- Fixes: a profile photo never uploads. The midwife's My Profile screen says
-- "Could not upload the photo. Please try again." every time, and a mother's
-- photo from her own profile fails the same way without saying so.
--
-- THE BUG -- two walls, one behind the other
--
--   1. There is no storage bucket to upload into. Every photo goes to a bucket
--      named "files" (SupabaseService.uploadAccountProfilePicture and
--      uploadProfilePicture), and on the live project that bucket does not
--      exist as a public bucket: asking for any object in it answers
--      "Bucket not found". The upload throws before anything else runs.
--
--      The other screens that upload met the same wall and routed around it.
--      Ultrasound and lab attachments fall back to base64 stored inline in the
--      row, which is how a single ultrasound came to be 3 MB of table data.
--      Baby book photos have no fallback and simply do not save.
--
--   2. Behind it, public.files is closed to the app. It was created with row
--      level security on and three policies:
--
--        "Users can read own files"                  uploaded_by = get_current_account_id()
--        "Midwives and admins can read all files"    has_role(...)
--        "Authenticated users can upload files"      auth.role() = 'authenticated'
--
--      The mobile app does not use Supabase Auth -- it signs in against
--      public.accounts itself and talks to PostgREST with the anon key -- so
--      its role is anon. None of those policies match anon: it reads zero rows
--      and cannot insert one, and with no UPDATE or DELETE policy nobody can
--      replace an old photo either. This is the same trap maternal_td_records
--      fell into (20260924).
--
-- THE FIX
--
--   1. A public bucket named "files". Public because the app stores and shows
--      getPublicUrl() links; a private bucket would need signed URLs the app
--      never asks for. If a private "files" bucket already exists and already
--      holds objects, the preflight stops rather than publish them -- see
--      below.
--
--   2. Policies on storage.objects letting anon and authenticated read, add,
--      replace and remove objects in that one bucket. All four are needed:
--      the app uploads with upsert, which Storage checks as INSERT plus SELECT
--      plus UPDATE, and it removes the previous photo, which is SELECT plus
--      DELETE.
--
--   3. public.files brought in line with every other table the app uses:
--      policies dropped, row level security off, explicit grants to anon and
--      authenticated, the id sequence included. Authorisation stays where it
--      is for the rest of this project, in the application and in SECURITY
--      DEFINER RPCs.
--
-- WHAT ELSE STARTS WORKING
--
--   The bucket is shared. Once it exists, baby book photos save, and new
--   ultrasound and lab attachments go to storage instead of into the row. Old
--   records keep their inline images; the viewer (RecordImage) reads both.
--
-- PRIVACY NOTE
--
--   Anything in a public bucket can be fetched by whoever has its URL, and the
--   SELECT policy lets any holder of the anon key list the bucket. That is no
--   wider than today: every clinical table, inline images included, is already
--   readable with the anon key. It is recorded here so that moving to Supabase
--   Auth later remembers to close this too.
--
-- Nothing in the app changes; it already asks for exactly this. Idempotent.
-- Depends on nothing but the base schema.
-- ===========================================================================

BEGIN;

DO $preflight$
DECLARE
  v_public   BOOLEAN;
  v_objects  BIGINT;
BEGIN
  IF to_regclass('public.files') IS NULL THEN
    RAISE EXCEPTION 'public.files does not exist. Create the base schema first.';
  END IF;

  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'Supabase Storage tables not found. Run this in the SQL Editor '
                    'of the Supabase project itself.';
  END IF;

  -- Making a bucket public publishes what is already in it. The app has never
  -- been able to write here, so a private "files" bucket with contents was put
  -- there by someone else, for some other reason. Stop and let a person look.
  SELECT b.public INTO v_public FROM storage.buckets b WHERE b.id = 'files';
  IF FOUND AND NOT v_public THEN
    SELECT count(*) INTO v_objects FROM storage.objects WHERE bucket_id = 'files';
    IF v_objects > 0 THEN
      RAISE EXCEPTION 'A private "files" bucket already exists and holds % object(s). '
                      'This migration would make them public. Check what they are, '
                      'then either empty the bucket or make it public yourself, and '
                      'run this again.', v_objects;
    END IF;
  END IF;
END
$preflight$;


-- ---------------------------------------------------------------------------
-- 1. The bucket
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('files', 'files', true)
ON CONFLICT (id) DO UPDATE SET public = true;


-- ---------------------------------------------------------------------------
-- 2. Who may use it
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "InaAgapay app reads the files bucket"    ON storage.objects;
DROP POLICY IF EXISTS "InaAgapay app uploads to the files bucket" ON storage.objects;
DROP POLICY IF EXISTS "InaAgapay app replaces in the files bucket" ON storage.objects;
DROP POLICY IF EXISTS "InaAgapay app removes from the files bucket" ON storage.objects;

CREATE POLICY "InaAgapay app reads the files bucket"
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id = 'files');

CREATE POLICY "InaAgapay app uploads to the files bucket"
  ON storage.objects FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id = 'files');

CREATE POLICY "InaAgapay app replaces in the files bucket"
  ON storage.objects FOR UPDATE TO anon, authenticated
  USING (bucket_id = 'files')
  WITH CHECK (bucket_id = 'files');

CREATE POLICY "InaAgapay app removes from the files bucket"
  ON storage.objects FOR DELETE TO anon, authenticated
  USING (bucket_id = 'files');


-- ---------------------------------------------------------------------------
-- 3. public.files, the row that says where each upload went
-- ---------------------------------------------------------------------------
DO $files$
DECLARE
  r      RECORD;
  v_seq  TEXT := pg_get_serial_sequence('public.files', 'file_id');
BEGIN
  -- Every policy, not just the three the draft schema names: with row level
  -- security off they would do nothing, and left behind they only mislead.
  FOR r IN
    SELECT policyname FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'files'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.files', r.policyname);
    RAISE NOTICE 'Dropped policy on public.files: %', r.policyname;
  END LOOP;

  ALTER TABLE public.files DISABLE ROW LEVEL SECURITY;

  GRANT SELECT, INSERT, UPDATE, DELETE ON public.files TO anon, authenticated;

  -- Without this an INSERT fails on nextval() although the table is writable.
  IF v_seq IS NOT NULL THEN
    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO anon, authenticated', v_seq);
  END IF;
END
$files$;

COMMIT;


-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- The bucket exists and is public:
--
--   SELECT id, public FROM storage.buckets WHERE id = 'files';   -- files | true
--
-- Four app policies on storage.objects:
--
--   SELECT policyname, cmd, roles FROM pg_policies
--    WHERE schemaname = 'storage' AND tablename = 'objects'
--      AND policyname LIKE 'InaAgapay app%';                      -- 4 rows
--
-- public.files open to the app:
--
--   SELECT relrowsecurity FROM pg_class
--    WHERE oid = 'public.files'::regclass;                        -- false
--   SELECT has_table_privilege('anon', 'public.files', 'INSERT'); -- true
--
-- Then change a photo from the midwife app's My Profile. It should say
-- "Profile photo updated.", and this should return the new row:
--
--   SELECT file_id, uploaded_by, file_path, created_at FROM public.files
--    WHERE reference_type = 'profile_photo' ORDER BY file_id DESC LIMIT 5;
