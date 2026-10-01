// Executes the app side of the sign-in test cases in InaAgapay Test Case.xlsx
// against the fake backend: the real screens, driven through the steps.
//
//   TC-MOB-LOGIN-011  suspended account attempts sign-in
//   TC-MOB-LOGIN-013  account suspended while the user is signed in
//   TC-MOB-LOGIN-014  account archived while the user is signed in

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/auth/login.dart';
import 'package:inaagapay_flutter_v2/services/account_status_guard.dart';

import '../support/fake_backend.dart';

const _password = 'Str0ng!Pass';

Map<String, dynamic> _motherAccount({required String status, String? archivedAt}) => {
      'account_id': 48,
      'email_address': 'mother.test01@example.com',
      'phone_number': '09171234567',
      'password_hash': BCrypt.hashpw(_password, BCrypt.gensalt()),
      'account_type': 'mother',
      'is_verified': true,
      'status': status,
      'status_reason': null,
      'archived_at': archivedAt,
      'first_name': 'Juana',
      'middle_name': null,
      'last_name': 'Dela Cruz',
      'extension_name': null,
      'created_at': '2026-08-01T00:00:00',
      'is_temporary_password': false,
      'created_by': '41',
    };

void main() {
  setUpAll(() => FakeBackend.init());

  testWidgets('TC-MOB-LOGIN-011 suspended account is refused at sign-in',
      (tester) async {
    FakeBackend.reset();
    FakeBackend.tables['accounts'] = [_motherAccount(status: 'suspended')];

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    // Identifier first, password second -- the order on the screen.
    await tester.enterText(find.byType(TextField).at(0), 'mother.test01@example.com');
    await tester.enterText(find.byType(TextField).at(1), _password);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('This account is suspended. Please contact your health center.'),
        findsOneWidget);
  });

  Future<void> signedInThenChanged(
    WidgetTester tester, {
    required String status,
    String? archivedAt,
  }) async {
    FakeBackend.reset(storage: {
      'auth_token': 'session-token',
      'user_id': '48',
      'user_role': 'mother',
    });
    FakeBackend.tables['accounts'] = [
      _motherAccount(status: status, archivedAt: archivedAt),
    ];

    await tester.pumpWidget(MaterialApp(
      navigatorKey: AccountStatusGuard.navigatorKey,
      home: const Scaffold(body: Text('Mother home')),
      routes: {'/login': (_) => const LoginScreen()},
    ));
    expect(find.text('Mother home'), findsOneWidget);

    // What the app does when it returns to the foreground.
    final ended = await tester.runAsync(() => AccountStatusGuard.enforce(force: true));
    await tester.pumpAndSettle();
    expect(ended, isTrue);
  }

  testWidgets('TC-MOB-LOGIN-013 suspension signs the user out with a notice',
      (tester) async {
    await signedInThenChanged(tester, status: 'suspended');
    expect(find.textContaining('Your account has been suspended, so you were signed out.'),
        findsOneWidget);
    expect(find.text('Mother home'), findsNothing);
  });

  testWidgets('TC-MOB-LOGIN-014 archived account signs the user out with a notice',
      (tester) async {
    await signedInThenChanged(tester,
        status: 'inactive', archivedAt: '2026-10-01T08:00:00');
    expect(find.textContaining('This account no longer exists, so you were signed out.'),
        findsOneWidget);
  });
}
