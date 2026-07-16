# InaAgapay — Actionable Items

## Already Done
- [x] All 6 epics implemented (35/35 acceptance criteria)
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

## Remaining Items

### Build & Test on Android (20 minutes)
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

### Enable Extensions in Supabase (5 minutes)
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

### Fix SMS (waiting on provider)
- [ ] **Semaphore:** Apply for new sender name at https://semaphore.co (current "INAAGAPAY" is banned)
- [ ] **Infobip:** Whitelist test numbers at https://portal.infobip.com
- [ ] **Update .env** with new sender name once approved:
  ```
  SEMAPHORE_SENDER_NAME=YourNewName
  ```

### Security
- [ ] **Change your account password** — shared in conversation
- [ ] **Rotate API keys after thesis** — Groq, Semaphore, Infobip, Firebase

### Future Features
- [ ] Chatbot + Speech to text in mother side
- [ ] FAQs page

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
