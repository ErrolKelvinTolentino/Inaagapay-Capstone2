// Executes midwife test cases from InaAgapay Test Case.xlsx on the real
// screens, against the fake backend.
//
//   TC-MW-CHILD-008   atypical birth length warning
//   TC-MW-GROW-006    weight below 0.5 kg or above 120 kg
//   TC-MON-GROW-005   height-for-age below range, named stunting
//   TC-MW-XFER-003    transfer reason missing
//   TC-MW-PREG-005    initial prenatal checkup skipped

import 'package:flutter/material.dart';
import 'package:inaagapay_flutter_v2/widgets/app_dropdown_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/add_child_step3_child.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/add_child_step4_birth.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/add_growth_step1.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/add_prenatal_checkup_screen.dart';
import 'package:inaagapay_flutter_v2/widgets/app_input_field.dart';
import 'package:inaagapay_flutter_v2/widgets/transfer_mother_sheet.dart';

import '../support/fake_backend.dart';

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

Future<void> settle(WidgetTester tester) async {
  // Real time for the fake backend's futures, then frames.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => FakeBackend.init(storage: {'user_id': '41', 'auth_token': 't'}));

  testWidgets('TC-MW-CHILD-008 birth length outside 30-60 cm is flagged',
      (tester) async {
    FakeBackend.reset(storage: {'user_id': '41', 'auth_token': 't'});
    await tester.pumpWidget(const MaterialApp(
      home: AddChildStep4Birth(
        mode: ChildParentMode.newGuardian,
        firstName: 'Baby',
        lastName: 'Lopez',
        middleName: '',
        extensionName: '',
        sex: 'Male',
      ),
    ));
    await settle(tester);

    await tester.enterText(field('Birth Length (cm)'), '65');
    await tester.pump();
    expect(find.text('Typical birth length is 30 - 60 cm. Please verify.'), findsOneWidget);

    await tester.enterText(field('Birth Length (cm)'), '50');
    await tester.pump();
    expect(find.text('Typical birth length is 30 - 60 cm. Please verify.'), findsNothing);
  });

  Future<void> openGrowthForm(WidgetTester tester) async {
    FakeBackend.reset(storage: {'user_id': '41', 'auth_token': 't'});
    // A boy of six months, the test case's own data.
    final birthdate = DateTime.now().subtract(const Duration(days: 183));
    FakeBackend.tables['children'] = [
      {'child_id': 7, 'first_name': 'Baby', 'last_name': 'Lopez', 'sex': 'Male'},
    ];
    FakeBackend.tables['birth_details'] = [
      {'child_id': 7, 'birthdate': birthdate.toIso8601String().split('T').first},
    ];
    FakeBackend.tables['child_growth_records'] = [];
    await tester.pumpWidget(const MaterialApp(home: AddGrowthStep1(childId: 7)));
    await settle(tester);
  }

  testWidgets('TC-MW-GROW-006 weight 0.4 and 121 kg are refused', (tester) async {
    await openGrowthForm(tester);
    const message = 'Weight must be between 0.5 kg and 120 kg.';

    await tester.enterText(field('Weight (kg)'), '0.4');
    await tester.pump();
    expect(find.text(message), findsOneWidget);

    await tester.enterText(field('Weight (kg)'), '121');
    await tester.pump();
    expect(find.text(message), findsOneWidget);

    await tester.enterText(field('Weight (kg)'), '7.5');
    await tester.pump();
    expect(find.text(message), findsNothing);
  });

  testWidgets('TC-MON-GROW-005 a 60 cm six-month-old boy reads as stunting',
      (tester) async {
    await openGrowthForm(tester);
    await tester.enterText(field('Height (cm)'), '60');
    await tester.enterText(field('Weight (kg)'), '7.5');
    await tester.pump();

    expect(find.text('Height for age'), findsOneWidget);
    expect(find.text('Below standard range · stunting'), findsOneWidget);
  });

  testWidgets('TC-MW-XFER-003 a transfer with no reason is blocked',
      (tester) async {
    FakeBackend.reset(storage: {'user_id': '41', 'auth_token': 't'});
    phoneScreen(tester);
    FakeBackend.tables['health_facilities'] = [
      {'facility_id': 2, 'name': 'Tarcan BHC', 'barangay': 'Tarcan', 'is_active': true, 'facility_type': 'BHC'},
      {'facility_id': 3, 'name': 'Sabang BHC', 'barangay': 'Sabang', 'is_active': true, 'facility_type': 'BHC'},
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTransferMotherSheet(context,
                motherId: 28, motherName: 'Juana Dela Cruz', currentBhcId: 2),
            child: const Text('Open transfer'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open transfer'));
    await settle(tester);

    // Choose the destination, leave the reason blank, confirm.
    await tester.tap(find.byType(AppDropdownField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Sabang BHC').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer mother'));
    await tester.pumpAndSettle();

    expect(find.text('Say briefly why she is being transferred.'), findsOneWidget);
    expect(FakeBackend.requests.where((r) => r.contains('rpc/transfer_mother')), isEmpty,
        reason: 'the transfer must not be sent');
  });

  testWidgets('TC-MW-PREG-005 leaving without the initial checkup keeps no pregnancy',
      (tester) async {
    FakeBackend.reset(storage: {'user_id': '41', 'auth_token': 't'});
    FakeBackend.tables['clinical_encounters'] = [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddPrenatalCheckupScreen(
                  motherId: 28,
                  pregnancyId: 900,
                  lmp: DateTime.now().subtract(const Duration(days: 70)),
                  completesNewPregnancy: true,
                ),
              ),
            ),
            child: const Text('Start pregnancy'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Start pregnancy'));
    await settle(tester);

    // Try to finish without the checkup.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new).first);
    await tester.pumpAndSettle();
    expect(find.text('Initial Checkup Required'), findsOneWidget);
    expect(
      find.textContaining('The initial prenatal checkup is required to complete the pregnancy record.'),
      findsOneWidget,
    );

    // Discarding takes the pregnancy back rather than keeping it without one.
    await tester.tap(find.text('Discard Pregnancy'));
    await settle(tester);
    expect(FakeBackend.requests.any((r) => r.startsWith('DELETE /rest/v1/pregnancies')), isTrue);
    expect(find.text('Start pregnancy'), findsOneWidget, reason: 'back on the profile');
  });
}
