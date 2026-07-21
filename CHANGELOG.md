# InaAgapay Capstone — Changelog

**Date:** May 19-20, 2026
**Authors:** Jim Mikael Carpio + Claude (AI pair programming)
**Stats:** 55 commits, 63 files changed, +8,742 / -1,447 lines

---

## Sprint 1: Epic Implementation (35/35 acceptance criteria)

### EPIC-01: Core Maternal Health & Prenatal Workflows

**EPIC-01-001: Pre-Pregnancy Weight & Address Customization**
- Added separate optional "Pre-Pregnancy Weight (kg)" field to mother registration
- Stored in `pregnancies.pre_pregnancy_weight` column
- IOM evaluation prefers pre-pregnancy weight, falls back to current weight
- Address customization was already implemented

**EPIC-01-002: LMP Constraints & Optional Email**
- LMP validation: rejects future dates or >43 weeks past
- Early pregnancy warning (<4 weeks): serum hCG dialog with mounted check
- Email optional: auto-generates `name.phone.timestamp@inaagapay.internal`
- Success message shows temporary password when no email

**EPIC-01-003: Mandatory Prenatal Checkup Progression**
- PopScope blocks back navigation after registration
- Warning dialog to skip initial checkup
- AppBar back button hidden during initial flow

**EPIC-01-004: Streamline Prenatal Checkup Data Entry**
- Removed fetal position dropdown (30 lines)
- Removed medication plan/prescription sections (443 lines)
- Kept Supplements (Ferrous + FA, Calcium) and TD Vaccine
- AI summary uses bulleted lists (was already done)

**EPIC-01-005: IOM 2009 Weight Gain Evaluation**
- Errol's WeightGainEngine (696 lines) handles FULL + TREND modes
- Twin pregnancy support, pattern detection (weight loss, plateau, spikes)
- Results fed into AI prompt for interpretive analysis

### EPIC-02: Extended Immunization (0-12 Months)
- Vaccine schedule expanded: 6mo (Vitamin A), 9mo (MCV1), 12mo (MCV2, MMR, Vitamin A)
- 10 vaccines seeded: PCV, Rotavirus, IPV, Vitamin A, Measles 2nd, MMR
- UI is DB-driven — renders automatically

### EPIC-03: Extended Growth Monitoring (0-5 Years)
- WHO LMS data already implemented (0-60 months)
- Added WHO reference curves (median, ±2SD, ±3SD) to growth charts
- ReferenceCurve class, _buildWhoCurves method

### EPIC-04: AI-Assisted Interpretative Functionalities
- OCR extraction: patient name, clinic location, attending professional
- Added to both ultrasound and lab prompts + reasoning prompts
- Auto-populates health worker fields (only when empty)
- Child growth interpretation already implemented (English/Filipino)

### EPIC-05: Administrative Web Dashboard
- New reports.html with date range, Maternal/Child report types
- CSV download via Blob API, preview table, record count
- Reports nav link added to all 6 admin pages
- Queries through accounts table for correct name resolution

### EPIC-06: Automated Reminder & Notification System
- `notifications` table + `device_tokens` table
- 3 triggers: checkup scheduled, vaccine recorded, auto-schedule from checkup
- 3 pg_cron functions: upcoming checkups, vaccine reminders, missed checkups
- Day-before SMS reminder function
- NotificationsScreen: pull-to-refresh, type icons, read/unread states
- Bell icon with realtime unread badge (Supabase Realtime)
- FCM v1 push via Edge Function + service account JWT
- PushNotificationService: web-safe, token management, logout cleanup

---

## Sprint 2: Product Improvements (43 items)

### Prenatal Checkup Flow
- Edema moved to symptoms step
- Fetal count starts as null (unconfirmed until ultrasound)
- Checkup date locked to current datetime
- Hypertension warning for high BP (non-blocking)
- Weight autofill uses latest checkup (DESC order)
- Summary shows actual symptom names, not counts

### AI Improvements
- Caring "ate" (trusted older sister) voice across all prompts
- Filipino cultural context: malunggay, kangkong, dilis recommendations
- Structured output: SUMMARY, KEY FINDINGS, RECOMMENDATIONS
- Trimester, checkup count, weight trend added to context
- IOM/ACOG weight interpretation spec embedded in all prompts
- Banned phrases: "ideal weight", "perfect weight", "required weight"
- Soft wording: "commonly expected range", "appears within range"
- Pre-pregnancy weight disclaimer when unavailable
- Mandatory medical disclaimer on all interpretations
- AI specifies actual measured values in explanations

### Lab/Ultrasound Analyzer
- Health worker metadata optional
- Recommendations in distinct green-tinted UI section
- Reduced overly strict validation
- Copy-to-clipboard report export

### Weight Gain Dashboard (Mother Profile)
- BMI category badge, actual vs expected gain, status indicator
- Weight trend chart (fl_chart)
- Log Weight button for mother self-reporting
- Uses Errol's WeightGainEngine

### Mother Profile & Dashboard
- Pregnancy stage card (trimester, weeks, EDD countdown)
- Dynamic profile editing (conditions, allergies add/remove)
- Controller refresh after save
- Emergency hotlines (moved to dedicated nav tab)
- Read-only mode for mother's own profile view

### Vaccination Workflow
- Full immunization roadmap with status indicators
- Age-based vaccine filtering
- Sequential dose prerequisite enforcement
- Roadmap separated from add-record form

### Child Registration
- Clear cancel/back path
- Guardian phone required, cleaner form UX
- Birth weight/height validation with warnings
- Navigate to child profile after registration

### Record Viewing
- Color-coded cards (AI=purple, recommendations=green, risk=red)
- AI analysis separated from provider notes
- Records list with type badges, dates, summaries
- Loading state with "Loading records..." text

### Validation Audit
- Discard confirmation dialogs on back navigation (6 screens)
- Error messages for missing vaccine/date selection
- PopScope blocks back for all modes when data entered

---

## Sprint 3: Bug Fixes & Enhancements (23 items)

### Critical Bug Fixes
- View profile in mother side no longer opens midwife screen (readOnly mode)
- Fetal count removed from checkup form (read-only, edit via ultrasound)
- Edema restored as dropdown in symptoms step
- Duplicate recommendations fixed in lab record viewing
- "At birth - At birth" text duplication fixed in immunization
- Growth charts show "Not enough data" when <2 records
- "More info" week progress now dynamic (was hardcoded at week 10)
- Loading screen shows "Loading records..." text

### UI/UX Improvements
- Comprehensive summary screen in prenatal checkup (all actual values)
- English/Filipino toggle for AI insights (default from language setting)
- Removed suggested actions from risk assessment
- "AI Generated" / "Reviewed by Midwife" chip in risk assessment
- Option to skip AI analysis (not forced)
- Lab parsing: only Overall Assessment, Lab Results, Recommendations
- FAB modal: "Existing Mother" / "New Guardian" labels
- Immunization roadmap on list page, add-record form standalone
- Schedule view shows next checkups, weekends blocked in date picker
- Hotlines moved to dedicated bottom nav tab (6 PH emergency numbers)
- "More info" personalization: real symptoms, allergy-filtered nutrition, gentler warnings
- Checklist tab removed, statistics tab removed

### New Features (Quick Wins)
- Baby size comparison: fruit images by gestational week (weeks 4-40)
- Pregnancy countdown: days remaining, progress bar, EDD date
- Weekly pregnancy tips: gestational-week-based caring advice
- Quick vitals entry: lightweight weight+BP recording for midwives
- Report export: clipboard copy with structured text format
- Dark mode: toggle in settings, persisted
- QR code: mother profile QR for quick midwife scanning
- Day-before SMS reminder: pg_cron notification function
- Offline mode indicator: red banner when no internet

---

## Setup Required

### 1. Run SQL in Supabase
```bash
cat database/run_this_in_supabase.sql | pbcopy
```
Paste in Supabase Dashboard → SQL Editor → Run.

### 2. API Keys (.env)
```
SUPABASE_URL=https://buvseyqcdacctlupznya.supabase.co
SUPABASE_ANON_KEY=<key>
GROQ_API_KEY=<key>
SEMAPHORE_API_KEY=<key>
SEMAPHORE_BASE_URL=https://api.semaphore.co/api/v4
INFOBIP_API_KEY=<key>
INFOBIP_BASE_URL=<url>
```

### 3. Push Notifications
1. Firebase project created, google-services.json in android/app/
2. FCM_PRIVATE_KEY added as Supabase Edge Function secret
3. send-push Edge Function deployed
4. Enable pg_net: `CREATE EXTENSION IF NOT EXISTS pg_net;`

### 4. Daily Reminders
```sql
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('daily-checkup-reminders',  '0 0 * * *', 'SELECT send_upcoming_checkup_reminders()');
SELECT cron.schedule('daily-vaccine-reminders',   '0 0 * * *', 'SELECT send_vaccine_due_reminders()');
SELECT cron.schedule('daily-mark-missed-checkups','5 0 * * *', 'SELECT mark_missed_checkups()');
SELECT cron.schedule('day-before-checkup-sms',    '0 22 * * *', 'SELECT send_day_before_checkup_sms()');
```

### 5. Running Locally
```bash
cd inaagapay_flutter_v2
flutter pub get
flutter run -d chrome    # web (most features)
flutter run              # android (all features)
```

### 6. Admin Dashboard
```bash
cd admin-web && python3 -m http.server 8080
```
Open http://localhost:8080/pages/dashboard.html

---

## Future Improvements
- Chatbot + Speech to text in mother side
- FAQs page
- Full SMS integration (pending Semaphore sender name approval)
- Infobip SMS (pending number whitelisting)
