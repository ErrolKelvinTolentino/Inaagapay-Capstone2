# Moving InaAgapay to a new Supabase project

The old project (`krooorixhjwygcsdoomg`) shuts down on **September 30**. These
scripts copy it, whole, into a new project on a new account, and then point
the app and the portal at it.

**What comes across:** every table and every row, all functions, triggers,
views, policies, grants and row level security, sequences, extensions, the
scheduled jobs, the realtime tables, and the Edge Functions. Every account and
password stays the same, so everyone signs in exactly as before.

**Do steps 0, 1 and 4a today, while the old project is still up.** After it
shuts down, only what you exported can be recovered. Everything from step 2
on can happen later from the files on this computer.

> **Two things are not "just change the URL and key":**
>
> 1. **New Supabase projects have no `anon` or `service_role` key any more.**
>    They have a *publishable* key (`sb_publishable_…`), which takes the anon
>    key's place, and a *secret* key (`sb_secret_…`), which takes the service
>    role's. The code has already been changed to work with them (list at the
>    bottom), and still works with the old keys too.
> 2. **The Android app has to be rebuilt.** The URL and key are compiled into
>    the APK. Phones with the old APK stop working when the old project shuts
>    down, so everyone installs the new one (step 5).

Plan on about an hour. Every script stops with a plain explanation if
something is wrong, and every script is safe to run again.

---

## Step 0 — Install the tools (5 minutes)

**PostgreSQL 17 command line tools** (for `pg_dump` and `psql`):

```powershell
winget install --id PostgreSQL.PostgreSQL.17 -e --interactive
```

In the installer, tick **only "Command Line Tools"**: untick PostgreSQL
Server, pgAdmin and Stack Builder. Then close and reopen your terminal.

**Node.js** is already installed on this computer (the Edge Function step uses
`npx` to run the Supabase CLI; nothing else to install).

Every command below starts with `powershell -ExecutionPolicy Bypass -File`, so
you do not need to change any system setting to run the scripts.

---

## Step 1 — Export the old project (5 minutes) · TODAY

```powershell
cd database\new-project
copy settings.example.env settings.env
notepad settings.env
```

Fill in the two `OLD_…` lines:

- `OLD_DB_URL`: in the **old** project's dashboard click **Connect** (top bar)
  and copy the **Session pooler** URI. Keep `[YOUR-PASSWORD]` in it as it is.
  Do not use "Direct connection" (it usually times out on home internet), and
  do not use "Transaction pooler".
- Forgot the database password? **Project Settings → Database → Reset database
  password.** Resetting it on the old project is fine.

Then:

```powershell
powershell -ExecutionPolicy Bypass -File .\1-export-old-project.ps1
```

It asks for the old database password, then writes `export\old\`: the schema,
all the data, and an inventory of what the project has. Read the summary it
prints (also saved as `export\old\SUMMARY.txt`). Anything marked `note` needs
a moment of your attention before step 3.

`export\` holds every patient record. It is gitignored; keep it on this
computer and delete it when you are done (step 7).

---

## Step 2 — Create the new project (5 minutes)

On the **new** Supabase account: **New project**.

| Setting | Value |
|---|---|
| Name | `inaagapay` (anything) |
| Database password | Generate one and save it somewhere safe |
| Region | The same as the old project. Your `OLD_DB_URL` shows it: `ap-southeast-1` is Southeast Asia (Singapore) |
| Postgres version | The default |
| Security options | Keep **Data API** enabled. If there is an option to turn row level security on automatically for new tables, leave it **off** (the import corrects it either way) |

When the project is ready, fill in the four `NEW_…` lines of `settings.env`:

| Setting | Where |
|---|---|
| `NEW_PROJECT_REF` | The random part of the project URL, `https://<ref>.supabase.co` |
| `NEW_DB_URL` | **Connect → Session pooler**, same as step 1 |
| `NEW_SUPABASE_URL` | **Project Settings → Data API → Project URL** |
| `NEW_PUBLISHABLE_KEY` | **Project Settings → API Keys → Publishable key** (`sb_publishable_…`) |

If the step 1 summary said the old project used **Database Webhooks**, open
**Database → Webhooks** in the new project and click **Enable webhooks** now.

---

## Step 3 — Import into the new project (10 minutes)

```powershell
powershell -ExecutionPolicy Bypass -File .\2-import-new-project.ps1
```

It asks for the new database password and the new **secret key**
(**Project Settings → API Keys → Secret keys**, reveal the `default` one).
Neither is saved anywhere.

What it does, in order:

1. Rewrites the export for the new project. The old URL becomes the new URL,
   the old anon key becomes the publishable key, and the old service key
   (kept by the daily reminder job) becomes the secret key.
2. Turns on the extensions the old project had (`pg_cron`, `pg_net`, …).
3. Loads the schema, then the data, each in one transaction. The data goes in
   with **triggers switched off**, so the audit trail is not written twice
   and no notification is pushed to anyone's phone again.
4. Restores the realtime tables, row level security, grants and scheduled
   jobs exactly as they were. It also adds an `apikey` header to the
   database functions that call Edge Functions, which the new keys need.
5. Compares the new project with the old one, table by table and row by row.
6. Applies `20260929_profile_photo_storage.sql`, so profile photos work from
   day one. This is the one deliberate difference from the old project.
7. Calls the new API with the publishable key, as the app will.

It ends with either **"the new project matches the old one table for table"**
or a list of differences (also in `export\IMPORT-REPORT.txt`).

If it stops partway, the message names the first error. Fix that, then run
it again: it picks up where it left off. To start over from an empty project:

```powershell
powershell -ExecutionPolicy Bypass -File .\2-import-new-project.ps1 -Reset
```

---

## Step 4 — Edge Functions (10 minutes)

The old project has two: `send-sms` (called by the portal) and
`send-reminders` (called by the daily cron job). Only those two are deployed
to the new project. There is no `send-email` or `send-push` to move:

- **Email** goes out through a database trigger, not an Edge Function.
  `trg_process_email_queue` on `email_queue` posts each row to a Google Apps
  Script web app through the `http` extension, so it comes across with the
  import. The portal's call to `send-email` is a fallback that fails harmlessly.
- **Nothing calls `send-push`**: not the database, the app or the portal.

The download still matters: it records the old project's list of functions and
secret names while the old project is still up.

**4a. Download · TODAY.** Sign in to supabase.com as the **old** account, open
<https://supabase.com/dashboard/account/tokens>, generate a token, then:

```powershell
powershell -ExecutionPolicy Bypass -File .\3-edge-functions.ps1 -DownloadOnly
```

This saves every deployed function under `export\functions\old\`, and the
names of the old project's secrets in `export\functions\old-secret-names.txt`.

**4b. Deploy.** Sign in as the **new** account and generate a token there.
Then:

```powershell
powershell -ExecutionPolicy Bypass -File .\3-edge-functions.ps1 -DeployOnly
```

The first run creates `functions.secrets.env`, fills in what it can from
`inaagapay_flutter_v2\.env`, and stops. Check it and fill in any blanks.
Supabase never shows a secret's value again, so the values come from the
providers themselves:

- **Semaphore** (SMS): your Semaphore dashboard, API key. This is the one
  that matters: the old project's only secrets were `SEMAPHORE_API_KEY` and
  `SEMAPHORE_SENDER_NAME`
- **ALLOWED_ORIGIN**: the portal's address, e.g. `https://your-portal.vercel.app`
- `BREVO_API_KEY` and `FCM_PRIVATE_KEY`: leave empty. They belong to
  `send-email` and `send-push`, which are not deployed

Then run the same command again. It sets the secrets and deploys the functions
the old project had, with **JWT verification off**, which the new keys need.
`send-reminders` checks its callers itself, so it still refuses anyone
without the secret key.

---

## Step 5 — Point the app and the portal at the new project (15 minutes)

```powershell
powershell -ExecutionPolicy Bypass -File .\4-switch-app-config.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\4-switch-app-config.ps1
```

This changes 18 files: `inaagapay_flutter_v2\.env`, the 13 portal pages and
scripts that hold the URL and key, both `vercel.json` files (the portal's
security header only allows the project it names), `supabase\config.toml` and
`database\backups\backup.js`. Then it checks nothing else still names the old
project.

**Portal:** commit and push. Vercel redeploys it. The publishable key is
public by design and committed the same way the anon key was.

**App:** rebuild the APK and publish it where the portal's download page
points (the latest GitHub release, file name `inaagapay.apk`):

```powershell
cd ..\..\inaagapay_flutter_v2
flutter build apk --release
# upload build\app\outputs\flutter-apk\app-release.apk as inaagapay.apk
# to a new release on GitHub
```

Everyone installs the new APK. The old one cannot reach the new project.

---

## Step 6 — Check it works (10 minutes)

```powershell
cd ..\database\new-project
powershell -ExecutionPolicy Bypass -File .\5-verify.ps1
```

It checks the API, the storage bucket and each Edge Function, and runs the
daily reminder job as a dry run. Nothing is sent to anyone.

Then by hand:

1. **Portal:** sign in as an administrator; the dashboard, accounts and
   inventory show the same numbers as before.
2. **App, midwife:** sign in; the mothers list is the same; open a mother.
3. **App, mother:** sign in as a test mother; her records and notifications
   are there.
4. Record a prenatal checkup for a **test** mother. She gets the in-app
   notification.
5. Change a profile photo.
6. Create a test account in the portal; the email and SMS arrive.

---

## Step 7 — After the switch

- **Stop the old project's scheduled jobs**, so reminders do not go out twice
  while both projects are alive. In the **old** project's SQL Editor:

  ```sql
  UPDATE cron.job SET active = false;
  ```

- **Anything recorded on the old project after step 1 is not in the new
  one.** Do steps 1 to 5 in one sitting and ask the midwives not to record
  anything meanwhile. If something was recorded anyway, run step 1 again, then
  step 3 with `-Reset`.
- **Delete `database\new-project\export\`** once the new project is verified.
  It holds every patient record and the secret key.
- The new project is on the free plan too: 500 MB database, 5 GB egress per
  month, and it **pauses after 7 days without activity**. Open it before a
  demo.

---

## Daily reminders

The day-before reminder job reads its target from `public.job_settings`. The
import points it at the new project automatically **if it was set up on the
old one**. If the step 3 report says `job_settings` still holds placeholders,
the job was never switched on and still is not. To switch it on (this sends
real SMS every day at 6 AM Manila time), run this in the new project's SQL
Editor:

```sql
UPDATE public.job_settings SET value = 'https://<new-ref>.supabase.co' WHERE key = 'project_url';
UPDATE public.job_settings SET value = '<sb_secret_… key>'            WHERE key = 'service_role_key';
```

---

## When something goes wrong

| What you see | What to do |
|---|---|
| `pg_dump` / `psql` not found | Step 0, then open a new terminal |
| Connection timed out | You used the Direct connection. Use **Connect → Session pooler** |
| `password authentication failed` | Reset the database password in that project's dashboard |
| `server version mismatch` | Install the PostgreSQL tools of the version the error names |
| Schema load stops on an extension | Enable it under **Database → Extensions**, run step 3 again |
| The app or the portal shows empty lists | Run step 3 again: it re-applies row level security and grants, then compares |
| Portal says "Invalid API key" | Hard-refresh (Ctrl+F5); check the Vercel deployment finished |
| An Edge Function answers `Invalid JWT` | It was deployed with verification on: run `3-edge-functions.ps1 -DeployOnly` again |
| Notifications do not update live | Realtime reconnects on its own; the list is always current when opened |

---

## What changed in the code for the new keys

These work with both the old JWT keys and the new ones, so they are safe to
ship before the switch:

- `supabase/functions/send-reminders/index.ts`: reads the server key from
  `SUPABASE_SECRET_KEYS` (new projects) or `SUPABASE_SERVICE_ROLE_KEY` (old),
  and admits only a caller presenting that exact key, in either header. It
  no longer trusts the role inside a JWT: with verification off, nothing
  checks that JWT's signature, so the role claim could be forged
- `inaagapay_flutter_v2/supabase/functions/send-push/index.ts`: the same key
  lookup for its database reads
- `admin-web/pages/account-create.html`: sends `apikey` alongside
  `Authorization`, as Supabase requires for a publishable key
- `database/migrations/20260817_daily_reminder_job.sql`: the reminder job
  sends `apikey` too, so re-running that file keeps it working
- `supabase/config.toml`: JWT verification off for the functions

The Flutter app needed no code change: `supabase_flutter` 2.17 already
handles the new keys.

## The files here

| File | Does |
|---|---|
| `settings.example.env` | Template for `settings.env` (gitignored) |
| `1-export-old-project.ps1` | pg_dump of schema and data, plus an inventory. Read only |
| `2-import-new-project.ps1` | Loads everything into the new project and compares |
| `3-edge-functions.ps1` | Downloads, deploys and configures the Edge Functions |
| `4-switch-app-config.ps1` | Points the app, the portal and the tooling at the new project |
| `5-verify.ps1` | End-to-end checks, sending nothing |
| `functions.secrets.example.env` | Template for the function secrets (gitignored copy) |
| `common.ps1`, `sql/` | Shared by the scripts |
