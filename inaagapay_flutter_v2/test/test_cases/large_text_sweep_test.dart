// TC-Q-USAB-005, the automated part: the main screens at the largest text
// size the app allows, on a 360 x 780 phone, in the font Android draws them
// in.
//
// Android's largest font setting is 2x; the app caps it at [maxTextScale].
// Every screen is scrolled to its end so that every card is laid out, and any
// RenderFlex overflow -- text or content pushed past its box -- is collected
// and reported by file and line rather than stopping at the first.
//
// This does not replace the walkthrough the test case asks for: it cannot see
// text that is clipped without overflowing (a fixed-height box that cuts a
// line off), or content that is laid out correctly but hard to read.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/main.dart' show maxTextScale;
import 'package:inaagapay_flutter_v2/screens/auth/login.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/add_child_step3_child.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/add_child_step4_birth.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/add_growth_step1.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/midwife_add_mother_screen.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/midwife_shell.dart';
import 'package:inaagapay_flutter_v2/screens/mother/add_journal_page.dart';
import 'package:inaagapay_flutter_v2/screens/mother/mother_dashboard_shell.dart';
import 'package:inaagapay_flutter_v2/screens/mother/mother_vitals_page.dart';
import 'package:inaagapay_flutter_v2/screens/mother/notifications_screen.dart';
import 'package:inaagapay_flutter_v2/services/language_service.dart';
import 'package:inaagapay_flutter_v2/theme/app_theme.dart';
import 'package:inaagapay_flutter_v2/widgets/transfer_mother_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_backend.dart';

String _day(DateTime d) => d.toIso8601String().split('T').first;

void _seedMother() {
  final lmp = DateTime.now().subtract(const Duration(days: 140));
  final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
  FakeBackend.tables
    ..['mothers'] = [
      {
        'mother_id': 28, 'account_id': 48, 'assigned_bhc_id': 2, 'height': 156,
        'birthdate': '1998-04-12', 'blood_type': 'O+', 'gravida': 2, 'para': 1,
        'status': 'active', 'barangay': 'Tarcan',
        'account': {'first_name': 'Juana', 'last_name': 'Dela Cruz'},
        'accounts': {'account_id': 48, 'first_name': 'Juana', 'last_name': 'Dela Cruz',
                     'phone_number': '09171234567', 'email_address': 'mother.test01@example.com'},
        'pregnancies': [
          {'pregnancy_id': 900, 'status': 'ongoing', 'last_menstrual_period': _day(lmp),
           'pregnancy_risk_level': 'medium',
           'expected_date_of_delivery': _day(lmp.add(const Duration(days: 280)))},
        ],
      },
    ]
    ..['accounts'] = [
      {'account_id': 48, 'first_name': 'Juana', 'last_name': 'Dela Cruz',
       'email_address': 'mother.test01@example.com', 'phone_number': '09171234567'},
      {'account_id': 41, 'first_name': 'Maria Lourdes', 'last_name': 'Santos-Villanueva'},
    ]
    ..['pregnancies'] = [
      {
        'pregnancy_id': 900, 'mother_id': 28, 'status': 'ongoing',
        'last_menstrual_period': _day(lmp),
        'expected_date_of_delivery': _day(lmp.add(const Duration(days: 280))),
        'pre_pregnancy_weight': 52, 'fetal_count': 1, 'pregnancy_risk_level': 'medium',
      },
    ]
    ..['children'] = [
      {'child_id': 7, 'mother_id': 28, 'first_name': 'Gabriel', 'last_name': 'Dela Cruz',
       'sex': 'Male', 'added_at': '2024-03-05T08:00:00', 'birth_details': {'birthdate': '2024-03-02', 'birth_weight': 3.1}},
    ]
    ..['birth_details'] = [
      {'child_id': 7, 'birthdate': '2024-03-02', 'birth_weight': 3.1},
    ]
    ..['clinical_encounters'] = [
      {
        'encounter_type': 'checkup', 'pregnancy_id': 900, 'encounter_id': 3001,
        'encounter_datetime': yesterday, 'midwife_notes': 'Routine visit, no complaints.',
        'age_of_gestation_weeks': 19, 'age_of_gestation_days': 6, 'is_midwife_approved': true,
        'recorded_by': {'midwife_id': 5, 'account': {'first_name': 'Maria Lourdes', 'last_name': 'Santos-Villanueva'}},
        'checkup': {
          'encounter_id': 3001, 'pregnancy_id': 900, 'td_vaccine_dose': 'TD2',
          'blood_pressure_systolic': 110, 'blood_pressure_diastolic': 70, 'checkup_weight': 58.5,
          'fetal_position': 'Cephalic', 'fetal_heart_tone': 'Present', 'fetal_heart_beat': 142,
          'next_schedule': _day(DateTime.now().add(const Duration(days: 27))),
        },
      },
    ]
    ..['maternal_vitals'] = [
      {'vital_id': 1, 'pregnancy_id': 900, 'recorded_at': yesterday, 'age_of_gestation': 19.9,
       'weight_kg': 58.5, 'height_cm': 156, 'notes': 'Feeling well'},
    ]
    ..['journal_entries'] = [
      {'entry_id': 1, 'mother_id': 28, 'title': 'First kicks', 'content': 'Felt the baby move today.',
       'mood': 'happy', 'entry_date': _day(DateTime.now()), 'created_at': yesterday, 'updated_at': yesterday},
    ]
    ..['notifications'] = [
      {'notification_id': 1, 'account_id': 48, 'title': 'Checkup reminder',
       'message': 'Your next prenatal checkup at Tarcan Barangay Health Center is in 3 days.',
       'type': 'checkup_reminder', 'is_read': false, 'created_at': yesterday},
    ];
}

void _seedMidwife() {
  _seedMother();
  FakeBackend.tables
    ..['midwives'] = [
      {'midwife_id': 5, 'account_id': 41, 'assigned_bhc_id': 2},
    ]
    ..['health_facilities'] = [
      {'facility_id': 2, 'name': 'Tarcan Barangay Health Center', 'barangay': 'Tarcan',
       'facility_type': 'BHC', 'is_active': true, 'city_municipality': 'Baliuag', 'province': 'Bulacan'},
      {'facility_id': 3, 'name': 'Sabang Barangay Health Center', 'barangay': 'Sabang',
       'facility_type': 'BHC', 'is_active': true},
    ];
}

/// A RenderFlex overflow, and where in lib/ it was built.
class _Overflow {
  _Overflow(this.screen, this.message, this.where);
  final String screen;
  final String message;
  final String where;
  @override
  String toString() => '$screen: $message at $where';
}

void main() {
  final found = <_Overflow>[];

  setUpAll(() async {
    await FakeBackend.init(storage: const {});
    await loadPhoneFonts();
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('LARGE TEXT SWEEP: ${found.length} overflow(s)');
    for (final o in found) {
      // ignore: avoid_print
      print('  $o');
    }
  });

  Future<void> sweep(
    WidgetTester tester,
    String name,
    Widget screen, {
    Map<String, String> storage = const {},
    void Function()? seed,
    Future<void> Function(WidgetTester tester)? then,
  }) async {
    FakeBackend.reset(storage: storage);
    seed?.call();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0; // Android's largest
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final original = FlutterError.onError;
    var current = name;
    FlutterError.onError = (details) {
      final text = details.toString();
      if (!text.contains('overflowed')) return original?.call(details);
      final where = RegExp(r'lib/([\w/]+\.dart):(\d+)').firstMatch(text);
      found.add(_Overflow(current, details.exceptionAsString().split('\n').first,
          where == null ? '(unknown)' : '${where.group(1)}:${where.group(2)}'));
    };
    try {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
                textScaler: media.textScaler.clamp(maxScaleFactor: maxTextScale)),
            child: child!,
          );
        },
        home: screen,
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await scrollThrough(tester);
      if (then != null) {
        current = '$name (then)';
        await then(tester);
      }
      await tester.pumpWidget(const SizedBox());
      // The live-update socket the shells open keeps retrying against the
      // fake host; close it so its timers do not outlive the test.
      await tester.runAsync(() async {
        await Supabase.instance.client
            .removeAllChannels()
            .timeout(const Duration(seconds: 2), onTimeout: () => []);
        await Supabase.instance.client.realtime
            .disconnect()
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      });
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    } finally {
      FlutterError.onError = original;
    }
  }

  const mother = {'user_id': '48', 'auth_token': 't', 'mother_id': '28', 'user_role': 'mother'};
  const midwife = {'user_id': '41', 'auth_token': 't', 'user_role': 'midwife'};

  testWidgets('login', (t) => sweep(t, 'Login', const LoginScreen()));

  testWidgets('mother shell, every tab', (t) => sweep(
        t, 'Mother shell', const MotherDashboardShell(),
        storage: mother, seed: _seedMother,
        then: (t) async {
          for (final tab in ['Journal', 'Children', 'Records']) {
            final item = find.text(tab);
            if (item.evaluate().isEmpty) continue;
            await t.tap(item.last);
            for (var i = 0; i < 8; i++) {
              await t.pump(const Duration(seconds: 1));
            }
            await scrollThrough(t);
          }
        },
      ));

  // Filipino runs longer than English; the mother screens are the ones a
  // mother reads in it (TC-Q-USAB-004).
  testWidgets('mother shell, every tab, in Filipino', (t) async {
    LanguageService.selectedLanguage.value = AppLanguage.filipino;
    addTearDown(() => LanguageService.selectedLanguage.value = AppLanguage.english);
    await sweep(
      t, 'Mother shell (Filipino)', const MotherDashboardShell(),
      storage: mother, seed: _seedMother,
      then: (t) async {
        for (final tab in ['Journal', 'Mga Anak', 'Mga Tala']) {
          final item = find.text(tab);
          if (item.evaluate().isEmpty) continue;
          await t.tap(item.last);
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(seconds: 1));
          }
          await scrollThrough(t);
        }
      },
    );
  });

  testWidgets('mother vitals and add-weight sheet, in Filipino', (t) async {
    LanguageService.selectedLanguage.value = AppLanguage.filipino;
    addTearDown(() => LanguageService.selectedLanguage.value = AppLanguage.english);
    await sweep(
      t, 'Mother vitals (Filipino)',
      MotherVitalsPage(motherId: 28, pregnancyId: 900,
          lastMenstrualPeriod: _day(DateTime.now().subtract(const Duration(days: 140)))),
      storage: mother, seed: _seedMother,
      then: (t) async {
        await t.tap(find.text('Idagdag ang timbang'));
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('mother vitals and add-weight sheet', (t) => sweep(
        t, 'Mother vitals',
        MotherVitalsPage(motherId: 28, pregnancyId: 900,
            lastMenstrualPeriod: _day(DateTime.now().subtract(const Duration(days: 140)))),
        storage: mother, seed: _seedMother,
        then: (t) async {
          await t.tap(find.text('Add weight'));
          await t.pumpAndSettle();
        },
      ));

  testWidgets('journal entry', (t) =>
      sweep(t, 'New journal entry', const AddJournalPage(), storage: mother, seed: _seedMother));

  testWidgets('mother notifications', (t) =>
      sweep(t, 'Notifications', const NotificationsScreen(), storage: mother, seed: _seedMother));

  testWidgets('midwife shell, every tab', (t) => sweep(
        t, 'Midwife shell', const MidwifeShell(),
        storage: midwife, seed: _seedMidwife,
        then: (t) async {
          for (final tab in ['Mothers', 'Children', 'Schedules']) {
            final item = find.text(tab);
            if (item.evaluate().isEmpty) continue;
            await t.tap(item.last);
            for (var i = 0; i < 8; i++) {
              await t.pump(const Duration(seconds: 1));
            }
            await scrollThrough(t);
          }
        },
      ));

  testWidgets('add mother, first step', (t) =>
      sweep(t, 'Add mother', const MidwifeAddMotherScreen(), storage: midwife, seed: _seedMidwife));

  testWidgets('add growth record', (t) =>
      sweep(t, 'Add growth', const AddGrowthStep1(childId: 7), storage: midwife, seed: _seedMidwife));

  testWidgets('add child, birth details', (t) => sweep(
        t, 'Add child birth',
        const AddChildStep4Birth(mode: ChildParentMode.newGuardian, firstName: 'Gabriel',
            lastName: 'Dela Cruz', middleName: '', extensionName: '', sex: 'Male'),
        storage: midwife, seed: _seedMidwife));

  testWidgets('transfer sheet', (t) => sweep(
        t, 'Transfer sheet',
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTransferMotherSheet(context,
                  motherId: 28, motherName: 'Juana Dela Cruz', currentBhcId: 2),
              child: const Text('Open'),
            ),
          ),
        ),
        storage: midwife, seed: _seedMidwife,
        then: (t) async {
          await t.tap(find.text('Open'));
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(seconds: 1));
          }
        },
      ));

  test('no overflow at the largest text size', () {
    expect(found, isEmpty, reason: found.join('\n'));
  });
}

/// Scrolls the screen's main list to its end, so every card is laid out.
Future<void> scrollThrough(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;
  for (var i = 0; i < 15; i++) {
    final target = scrollables.evaluate().isEmpty ? null : scrollables.first;
    if (target == null) return;
    await tester.drag(target, const Offset(0, -500), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }
}
