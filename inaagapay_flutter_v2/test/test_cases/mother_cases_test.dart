// Executes mother test cases from InaAgapay Test Case.xlsx on the real
// screens, against the fake backend.
//
//   TC-MO-SELF-004  letters typed into the weight field
//   TC-MO-JRNL-005  saving a journal entry with no connection
//   TC-MO-REC-007   opening Records with no connection, then reconnecting
//   TC-MO-HOME-005  a pregnancy with no height or pre-pregnancy weight
//   TC-MOB-REG-015  a mother not linked to a BHC (as reworded 2026-10-01)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/mother/add_journal_page.dart';
import 'package:inaagapay_flutter_v2/screens/mother/mother_dashboard.dart';
import 'package:inaagapay_flutter_v2/screens/mother/mother_vitals_page.dart';
import 'package:inaagapay_flutter_v2/screens/mother/notifications_screen.dart';
import 'package:inaagapay_flutter_v2/screens/mother/records_screen.dart';
import 'package:inaagapay_flutter_v2/services/language_service.dart';
import 'package:inaagapay_flutter_v2/widgets/app_input_field.dart';

import '../support/fake_backend.dart';

const _mother = {'user_id': '48', 'auth_token': 't', 'mother_id': '28', 'user_role': 'mother'};

/// The text box inside the app's labelled input with this hint.
Finder field(String hint) => find.descendant(
      of: find.byWidgetPredicate((w) => w is AppInputField && w.hintText == hint),
      matching: find.byType(TextField),
    );

/// A 360 x 780 phone rather than the test default of 800 x 600.
void phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Advances time a second at a time until [finder] shows, covering the
/// Supabase client's own retries (1 s, 2 s, 4 s) on a failed read.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {int seconds = 15}) async {
  for (var i = 0; i < seconds && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  setUpAll(() async {
    await FakeBackend.init(storage: _mother);
    await loadPhoneFonts();
  });
  tearDown(() => LanguageService.selectedLanguage.value = AppLanguage.english);

  testWidgets('TC-MO-SELF-004 "sixty" in the weight field asks for a number',
      (tester) async {
    FakeBackend.reset(storage: _mother);
    phoneScreen(tester);
    FakeBackend.tables['pregnancies'] = [
      {'pregnancy_id': 900, 'pre_pregnancy_weight': 55, 'fetal_count': 1},
    ];
    FakeBackend.tables['mothers'] = [
      {'mother_id': 28, 'height': 156, 'assigned_bhc_id': 2},
    ];
    FakeBackend.tables['clinical_encounters'] = [];
    FakeBackend.tables['maternal_vitals'] = [];

    await tester.pumpWidget(MaterialApp(
      home: MotherVitalsPage(
        motherId: 28,
        pregnancyId: 900,
        lastMenstrualPeriod: DateTime.now()
            .subtract(const Duration(days: 140))
            .toIso8601String()
            .split('T')
            .first,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add weight'));
    await tester.pumpAndSettle();

    await tester.enterText(field('e.g. 58.5'), 'sixty');
    await tester.pump();
    expect(find.text('Enter a valid number'), findsOneWidget);

    // Pressing Save next keeps the same message, rather than "Weight is
    // required" for a field she did type in.
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a valid number'), findsOneWidget);
    expect(find.text('Weight is required'), findsNothing);
    expect(FakeBackend.requests.where((r) => r.startsWith('POST /rest/v1/maternal_vitals')),
        isEmpty,
        reason: 'nothing is saved');
  });

  testWidgets('TC-MO-JRNL-005 a save made offline keeps the entry and says why',
      (tester) async {
    FakeBackend.reset(storage: _mother);
    phoneScreen(tester);
    LanguageService.selectedLanguage.value = AppLanguage.filipino;

    await tester.pumpWidget(const MaterialApp(home: AddJournalPage()));
    await tester.pumpAndSettle();

    const entry = 'Sumipa si baby ngayong umaga.';
    await tester.enterText(find.byType(TextField).last, entry);
    FakeBackend.offline = true;
    await tester.tap(find.text('I-save ang tala ko'));
    await pumpUntilFound(tester,
        find.text('Hindi na-save ang iyong tala. Pakisuri ang koneksyon at subukan muli.'));

    expect(find.text('Hindi na-save ang iyong tala. Pakisuri ang koneksyon at subukan muli.'),
        findsOneWidget);
    expect(find.text(entry), findsOneWidget, reason: 'the text is kept on screen');
    await tester.scrollUntilVisible(find.text('I-save ang tala ko'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('I-save ang tala ko'), findsOneWidget, reason: 'she can try again');
  });

  testWidgets('TC-MO-REC-007 Records offline shows a connection message, then loads',
      (tester) async {
    FakeBackend.reset(storage: _mother);
    phoneScreen(tester);
    FakeBackend.tables['mothers'] = [
      {'mother_id': 28, 'assigned_bhc_id': 2, 'birthdate': '1998-04-12', 'blood_type': 'O+',
       'gravida': 1, 'para': 0, 'account': {'first_name': 'Juana', 'last_name': 'Dela Cruz'}},
    ];
    FakeBackend.tables['pregnancies'] = [];
    FakeBackend.offline = true;

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecordsScreen())));
    await pumpUntilFound(tester, find.text('No Internet Connection'));

    expect(find.text('No Internet Connection'), findsOneWidget);
    expect(find.text('No internet connection. Please check your connection and try again.'),
        findsOneWidget);
    // Nothing incorrect: no exception text, and no records claimed.
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('host lookup'), findsNothing);
    expect(find.text('Current Records'), findsNothing);

    // Back online.
    FakeBackend.offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No Internet Connection'), findsNothing);
    expect(find.text('Current Records'), findsOneWidget);

    // Leave the screen, which stops its reconnect timer.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TC-MO-HOME-005 missing baseline vitals ask for the setup',
      (tester) async {
    FakeBackend.reset(storage: _mother);
    phoneScreen(tester);
    final lmp = DateTime.now().subtract(const Duration(days: 98));
    String day(DateTime d) => d.toIso8601String().split('T').first;
    FakeBackend.tables
      ..['mothers'] = [
        {'mother_id': 28, 'account_id': 48, 'assigned_bhc_id': 2, 'height': null},
      ]
      ..['accounts'] = [
        {'account_id': 48, 'first_name': 'Juana', 'last_name': 'Dela Cruz'},
      ]
      ..['pregnancies'] = [
        {
          'pregnancy_id': 900, 'mother_id': 28, 'status': 'ongoing',
          'last_menstrual_period': day(lmp),
          'expected_date_of_delivery': day(lmp.add(const Duration(days: 280))),
          'pre_pregnancy_weight': null, 'fetal_count': 1,
        },
      ];

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MotherDashboard())));
    await pumpUntilFound(tester, find.text('Action Required: Complete Vitals Setup'));
    expect(find.text('Action Required: Complete Vitals Setup'), findsOneWidget);

    // It leads to the vitals setup.
    await tester.scrollUntilVisible(find.text('Complete Vitals Setup'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Complete Vitals Setup'));
    await tester.pumpAndSettle();
    expect(find.text('Height (cm)'), findsOneWidget);
    expect(find.text('Current Weight (kg)'), findsOneWidget);
    expect(find.text('Pre-pregnancy Weight (kg)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('TC-MOB-REG-015 an unlinked mother is shown how to link, on Home and Notifications',
      (tester) async {
    FakeBackend.reset(storage: _mother);
    phoneScreen(tester);
    FakeBackend.tables
      ..['mothers'] = [
        {'mother_id': 28, 'account_id': 48, 'assigned_bhc_id': null, 'height': 156},
      ]
      ..['accounts'] = [
        {'account_id': 48, 'first_name': 'Juana', 'last_name': 'Dela Cruz'},
      ]
      ..['pregnancies'] = []
      ..['notifications'] = [];

    // Home: the row at the bottom of the page.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MotherDashboard())));
    await pumpUntilFound(tester, find.text('Juana Dela Cruz'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Individual Mode (Unlinked)'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Individual Mode (Unlinked)'), findsOneWidget);
    await tester.tap(find.text('Individual Mode (Unlinked)'));
    await tester.pumpAndSettle();
    expect(find.text('How to Link to a BHC'), findsOneWidget);

    // Notifications: the Action Required card, opening the same instructions.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
    await pumpUntilFound(tester, find.text('Action Required: Link BHC'));
    expect(find.text('Action Required: Link BHC'), findsOneWidget);
    await tester.tap(find.text('Action Required: Link BHC'));
    await tester.pumpAndSettle();
    expect(find.text('How to Link to a BHC'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
