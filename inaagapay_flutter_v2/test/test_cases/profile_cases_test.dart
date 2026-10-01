// Executes profile test cases from InaAgapay Test Case.xlsx on the real
// screens, against the fake backend.
//
//   TC-MOB-PROF-008  five wrong codes lock the pending change

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/contact_change_service.dart';
import 'package:inaagapay_flutter_v2/widgets/contact_change_sheet.dart';
import 'package:inaagapay_flutter_v2/widgets/otp_input_field.dart';

import '../support/fake_backend.dart';

const _mother = {'user_id': '48', 'auth_token': 't', 'mother_id': '28', 'user_role': 'mother'};

void main() {
  setUpAll(() async {
    await FakeBackend.init(storage: _mother);
    await loadPhoneFonts();
  });

  testWidgets('TC-MOB-PROF-008 the fifth wrong code discards the change',
      (tester) async {
    FakeBackend.reset(storage: _mother);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    FakeBackend.tables['accounts'] = [
      {'account_id': 48, 'email_address': 'mother.test01@example.com'},
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showContactChangeSheet(context,
                accountId: 48,
                kind: ContactKind.email,
                currentValue: 'mother.test01@example.com'),
            child: const Text('Change email'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Change email'));
    await tester.pumpAndSettle();

    // 1. Request a code.
    await tester.enterText(find.byType(TextField), 'juana.new@example.com');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.text('We sent a 6-digit code to juana.new@example.com.'), findsOneWidget);
    expect(FakeBackend.requests.where((r) => r.startsWith('POST /rest/v1/email_queue')),
        hasLength(1), reason: 'the code went out');

    // 2. Enter a wrong code five times.
    final boxes = find.descendant(
        of: find.byType(OtpInputField), matching: find.byType(TextField));
    for (var i = 0; i < 6; i++) {
      await tester.enterText(boxes.at(i), '1');
    }
    await tester.pump();

    final expected = <String>[
      'That code is not right. 4 tries left.',
      'That code is not right. 3 tries left.',
      'That code is not right. 2 tries left.',
      'That code is not right. 1 try left.',
      'Too many wrong codes. Start again to get a new one.',
    ];
    for (final message in expected) {
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
    }

    // The pending change is gone: the sheet is back at step one, a sixth try
    // is not possible, and the account was never written.
    expect(find.byType(OtpInputField), findsNothing);
    expect(find.text('Send code'), findsOneWidget);
    expect(
        (await ContactChangeService.confirm(accountId: 48, code: '111111')).message,
        'Start again: no change is pending.');
    expect(FakeBackend.requests.where((r) => r.startsWith('PATCH /rest/v1/accounts')), isEmpty);

    await tester.pump(const Duration(seconds: 61));
  });
}
