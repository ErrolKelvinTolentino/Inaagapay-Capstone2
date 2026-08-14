# InaAgapay — Actionable Items

> **Last updated:** 2026-08-12

## Already Done
- [x] All 6 original epics implemented (35/35 acceptance criteria)
- [x] Sprint 2: 43 product improvements
- [x] Sprint 3: 23 bug fixes + enhancements
- [x] 9 quick-win features (baby size, countdown, tips, dark mode, QR, etc.)
- [x] SQL script ran in Supabase (notifications, device_tokens, triggers, vaccines)
- [x] Firebase project created, google-services.json placed
- [x] FCM_PRIVATE_KEY added as Supabase secret
- [x] send-push Edge Function deployed
- [x] .env configured with all API keys
- [x] Caring "ate" AI voice across all prompts
- [x] IOM/ACOG weight interpretation spec embedded
- [x] **SMS is live** — sender name `AGAPAY` approved and working (temporary
      passwords send successfully). The old `INAAGAPAY` name was rejected and
      has been replaced; Infobip is no longer needed.
- [x] Baby Book module built (E7-05), 157 DOH ECCD postnatal milestones seeded
- [x] Research artifacts complete (E10 — ERD, sampling, limitations)
- [x] Midwife dashboard analytics + priority band
- [x] Blood type transcribed from lab results, never typed from memory
- [x] Blood pressure reference module — cited, configurable, unit tested
- [x] Prenatal schedule engine extracted from the checkup screen and tested
- [x] Gestational diabetes screening engine + lab capture + dashboard alerts
- [x] Ultrasound AI reframed as "Explain My Report" (E4-04)
- [x] Vaccination drive scheduling with SMS + email invitations
- [x] Test suite green — 224 passing, 0 failing

---

## Remaining Items

### 🔴 Blocking — do these first

- [ ] **Run the GDM migration in Supabase**
      `database/migrations/20260812_gdm_glucose_values.sql`
      Adds four nullable glucose columns to `lab_tests`. Until this runs, the
      lab form's glucose fields cannot save and the GDM card on the dashboard
      shows a "waiting on the columns" state by design.

- [ ] **Confirm clinical thresholds with the adviser**, then record the exact
      guideline document and year in each file and cite it in the study:
      - GDM protocol — one-step 75g or two-step 100g? → `lib/services/gestational_diabetes_screening.dart`
      - Blood pressure cut-points → `lib/services/blood_pressure_reference.dart`
      - Antenatal visit intervals — conventional or WHO 8-contact? → `lib/services/prenatal_schedule_engine.dart`
      Each file has the numbers in one overridable object, so changing them is
      a one-line edit with no other file touched.

### 🟡 Verify on device (nothing else can confirm these)

Four query bugs were fixed by reading the schema; none has been confirmed running.

- [ ] **Schedules tab** — prenatal checkups should now appear on their dates
      (was selecting `prenatal_checkup_id`, which does not exist)
- [ ] **Dashboard → Recent Visits** — should be populated (same bad column)
- [ ] **Mother vitals page** — blood pressure should show, and the weight chart
      should include midwife measurements, not only self-logged ones
- [ ] **Vaccination drive** — confirm the drive saves and appears on the
      calendar. The insert tries `bhc_id` then falls back to `facility_id`
      because the schema file and the live queries disagree on that column name

### Build & Test on Android
- [ ] **Install Java:**
  ```bash
  brew install --cask temurin
  ```
- [ ] **Install Android SDK** via Android Studio: https://developer.android.com/studio
- [ ] **Accept licenses:**
  ```bash
  flutter doctor --android-licenses
  ```
- [ ] **Build and install:**
  ```bash
  cd inaagapay_flutter_v2
  flutter pub get
  flutter build apk --debug
  ```
  APK at: `build/app/outputs/flutter-apk/app-debug.apk`
- [ ] **Test push notifications** on Android device

### Enable Extensions in Supabase
- [ ] **pg_net** (for push notification trigger):
  ```sql
  CREATE EXTENSION IF NOT EXISTS pg_net;
  ```
- [ ] **pg_cron** (for daily reminders):
  ```sql
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  SELECT cron.schedule('daily-checkup-reminders',  '0 0 * * *', 'SELECT send_upcoming_checkup_reminders()');
  SELECT cron.schedule('daily-vaccine-reminders',   '0 0 * * *', 'SELECT send_vaccine_due_reminders()');
  SELECT cron.schedule('daily-mark-missed-checkups','5 0 * * *', 'SELECT mark_missed_checkups()');
  SELECT cron.schedule('day-before-checkup-sms',    '0 22 * * *', 'SELECT send_day_before_checkup_sms()');
  ```

### Known issues, not yet fixed
- [ ] **Nine competing blood-pressure rule blocks.** Five sit inside
      `add_prenatal_checkup_screen.dart` and disagree: one uses the
      non-pregnancy AHA staging (130/80 = Stage 1) while the card rendered
      directly beneath it uses the pregnancy thresholds, so a reading of 145/95
      displays "HTN Stage 2" and "Hypertension in Pregnancy" side by side. One
      also compares with `>`, so exactly 140/90 classifies differently there
      than in every risk engine. `lib/services/blood_pressure_reference.dart`
      exists to migrate them onto — a refactor worth doing when breaking it is
      survivable.
- [ ] `SmartRiskEngine.buildWatchList` has working 3-visit BP-rise detection
      and zero call sites.

### Security
- [ ] **Change your account password** — shared in conversation
- [ ] **Rotate API keys after thesis** — Groq, Semaphore, Firebase

### Future Features
- [ ] Children's vaccination drive scheduling (mother-side drives are built;
      the same page with `target_recipients = 'child'` and defaulters from
      `ImmunizationSchedule.statusOfVaccine`)
- [ ] GDM postpartum follow-up — the 6–12 week OGTT after delivery
- [ ] Mother-facing jargon audit (E7-02) — "fundal height", "AOG", "edema" and
      "Z-score" still appear on mother-facing screens
- [ ] Chatbot + Speech to text in mother side
- [ ] FAQs page

---

## Running Locally

**Chrome (quick test):**
```bash
cd inaagapay_flutter_v2 && flutter pub get && flutter run -d chrome
```

**Android (all features):**
```bash
cd inaagapay_flutter_v2 && flutter pub get && flutter run
```

**Admin dashboard:**
```bash
cd admin-web && python3 -m http.server 8080
```
Open http://localhost:8080/pages/dashboard.html

**Tests:**
```bash
cd inaagapay_flutter_v2 && flutter test
```
