// Executes midwife test cases from InaAgapay Test Case.xlsx that need a whole
// screen or a platform failure, against the fake backend.
//
//   TC-MW-LOGS-003  opening a visit record while offline
//   TC-MW-EXP-006   exporting when the file cannot be created

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/midwife_dashboard.dart';
import 'package:inaagapay_flutter_v2/services/export_actions.dart';

import '../support/fake_backend.dart';

const _midwife = {'user_id': '41', 'auth_token': 't', 'user_role': 'midwife'};

/// A 360 x 780 phone rather than the test default of 800 x 600.
void phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Advances time a second at a time until [finder] shows, covering the
/// Supabase client's own retries (1 s, 2 s, 4 s) on a failed read.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {int seconds = 20}) async {
  for (var i = 0; i < seconds && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// The phone's save sheet, failing the way a full phone or a refused
/// permission does.
class _StorageFull extends FilePicker {
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async =>
      throw PlatformException(
        code: 'ENOSPC',
        message: 'Error while saving file: No space left on device',
      );
}

void main() {
  setUpAll(() async {
    await FakeBackend.init(storage: _midwife);
    await loadPhoneFonts();
  });

  testWidgets('TC-MW-LOGS-003 a visit record opened offline says it failed',
      (tester) async {
    FakeBackend.reset(storage: _midwife);
    phoneScreen(tester);
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
    FakeBackend.tables
      ..['midwives'] = [
        {'midwife_id': 5, 'account_id': 41, 'assigned_bhc_id': 2},
      ]
      ..['health_facilities'] = [
        {'facility_id': 2, 'name': 'Tarcan BHC', 'facility_type': 'BHC', 'is_active': true},
      ]
      ..['accounts'] = [
        {'account_id': 41, 'first_name': 'Maria', 'last_name': 'Santos'},
      ]
      ..['mothers'] = [
        {
          'mother_id': 28, 'account_id': 48, 'birthdate': '1998-04-12',
          'assigned_bhc_id': 2, 'status': 'active',
          'accounts': {
            'account_id': 48, 'first_name': 'Juana', 'last_name': 'Dela Cruz',
            'phone_number': '09171234567', 'email_address': 'mother.test01@example.com',
          },
        },
      ]
      ..['pregnancies'] = [
        {'pregnancy_id': 900, 'mother_id': 28, 'status': 'ongoing',
         'last_menstrual_period': '2026-05-20', 'expected_date_of_delivery': '2027-02-24'},
      ]
      ..['clinical_encounters'] = [
        {
          'encounter_type': 'checkup',
          'pregnancy_id': 900,
          'encounter_datetime': yesterday,
          'midwife_notes': 'Routine visit',
          'age_of_gestation_weeks': 19,
          'age_of_gestation_days': 1,
          'is_midwife_approved': true,
          'recorded_by': {'midwife_id': 5, 'account': {'first_name': 'Maria', 'last_name': 'Santos'}},
          'checkup': {
            'encounter_id': 3001, 'pregnancy_id': 900, 'td_vaccine_dose': null,
            'blood_pressure_systolic': 110, 'blood_pressure_diastolic': 70,
            'checkup_weight': 58.5, 'fetal_position': null, 'fetal_heart_tone': null,
            'fetal_heart_beat': 142, 'next_schedule': null,
          },
        },
      ];

    await tester.pumpWidget(const MaterialApp(home: MidwifeDashboard()));
    await pumpUntilFound(tester, find.text('Juana Dela Cruz'));
    await tester.scrollUntilVisible(find.text('Juana Dela Cruz'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Juana Dela Cruz'), findsOneWidget, reason: 'the visit is listed');

    // Lose the connection, then open the entry.
    FakeBackend.offline = true;
    await tester.tap(find.text('Juana Dela Cruz'));
    await pumpUntilFound(tester, find.textContaining('Failed to load checkup details'));

    expect(find.textContaining('Failed to load checkup details'), findsOneWidget);
    // Not the record with blanks where the readings should be.
    expect(find.text('Conducted by'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'no crash');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('TC-MW-EXP-006 a file that cannot be written gives a plain message',
      (tester) async {
    FakeBackend.reset(storage: _midwife);
    phoneScreen(tester);
    FilePicker.platform = _StorageFull();

    for (final action in [ExportAction.savePdf, ExportAction.saveExcel]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ExportActions.run(
                context,
                action,
                fileStem: 'inaagapay_checkup_dela-cruz-juana_2026-10-01',
                buildPdf: () async => Uint8List.fromList(List.filled(64, 1)),
                buildExcel: () async => Uint8List.fromList(List.filled(64, 1)),
              ),
              child: const Text('Export'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      expect(find.text('Could not create the file. Please try again.'), findsOneWidget,
          reason: '$action');
      expect(find.textContaining('ENOSPC'), findsNothing);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.byType(Dialog), findsNothing, reason: 'the "preparing" dialog is closed');

      // Let the snackbar go before the next format.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    }
  });
}
