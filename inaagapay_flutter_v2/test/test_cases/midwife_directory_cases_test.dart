// Executes the app side of the midwife directory test cases in
// InaAgapay Test Case.xlsx, against the fake backend.
//
//   TC-MW-MDIR-004  a mother from another BHC is not reachable
//   TC-MW-XFER-004  after a transfer, the original midwife no longer sees her
//
// The fake backend applies the screen's own `assigned_bhc_id=eq.` filter, so
// these show what the screen asks for and what it keeps on screen -- including
// across a change of midwife on the same phone, which is where the list used
// to leak another health center's mothers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/midwife_mothers_screen.dart';
import 'package:inaagapay_flutter_v2/services/supabase_service.dart';

import '../support/fake_backend.dart';

Map<String, dynamic> _mother(int id, int accountId, int bhc, String first, String last) => {
      'mother_id': id,
      'account_id': accountId,
      'assigned_bhc_id': bhc,
      'birthdate': '1998-04-12',
      'barangay': bhc == 2 ? 'Tarcan' : 'Sabang',
      'accounts': {
        'first_name': first,
        'last_name': last,
        'phone_number': '0917123${id.toString().padLeft(4, '0')}',
        'email_address': '${first.toLowerCase()}@example.com',
      },
      'pregnancies': <Map<String, dynamic>>[],
    };

void main() {
  setUpAll(() async {
    await FakeBackend.init(storage: {'user_id': '41', 'auth_token': 't'});
    await loadPhoneFonts();
  });

  void seed() {
    SupabaseService.clearMidwifeContextCache();
    FakeBackend.tables
      ..['midwives'] = [
        {'midwife_id': 5, 'account_id': 41, 'assigned_bhc_id': 2}, // Tarcan
        {'midwife_id': 6, 'account_id': 42, 'assigned_bhc_id': 3}, // Sabang
      ]
      ..['health_facilities'] = [
        {'facility_id': 2, 'name': 'Tarcan BHC'},
        {'facility_id': 3, 'name': 'Sabang BHC'},
      ]
      ..['mothers'] = [
        _mother(28, 48, 2, 'Juana', 'Dela Cruz'),
        _mother(29, 49, 3, 'Rosa', 'Reyes'),
      ];
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('TC-MW-MDIR-004 a mother at another BHC is not listed or found',
      (tester) async {
    FakeBackend.reset(storage: {'user_id': '41', 'auth_token': 't'});
    seed();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // The Tarcan midwife.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MidwifeMothersScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Juana Dela Cruz'), findsOneWidget);
    expect(find.text('Rosa Reyes'), findsNothing);
    expect(
      FakeBackend.requests.where((r) => r.startsWith('GET /rest/v1/mothers')).every(
          (r) => r.contains('assigned_bhc_id=eq.2')),
      isTrue,
      reason: 'the list is asked for her own health center only',
    );

    await search(tester, 'Rosa');
    expect(find.text('Rosa Reyes'), findsNothing);
    expect(find.text('No matching mothers found'), findsOneWidget);

    // The Sabang midwife signs in on the same phone. The list she sees is
    // Sabang's -- not what the Tarcan midwife had on screen.
    await tester.pumpWidget(const SizedBox());
    FakeBackend.reset(storage: {'user_id': '42', 'auth_token': 't'});
    seed();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MidwifeMothersScreen())));
    await tester.pump();
    expect(find.text('Juana Dela Cruz'), findsNothing,
        reason: 'not even for a frame, from the previous midwife\'s cache');
    await tester.pumpAndSettle();
    expect(find.text('Rosa Reyes'), findsOneWidget);
    expect(find.text('Juana Dela Cruz'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TC-MW-XFER-004 a transferred mother leaves the old BHC list',
      (tester) async {
    FakeBackend.reset(storage: {'user_id': '41', 'auth_token': 't'});
    seed();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final reopened = ValueNotifier<int>(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MidwifeMothersScreen(refreshSignal: reopened)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Juana Dela Cruz'), findsOneWidget);

    // Juana is transferred to Sabang (the database side is TC-MW-XFER-001),
    // and the Tarcan midwife comes back to the Mothers tab.
    FakeBackend.tables['mothers']!.first['assigned_bhc_id'] = 3;
    reopened.value++;
    await tester.pumpAndSettle();
    expect(find.text('Juana Dela Cruz'), findsNothing);

    await search(tester, 'Juana');
    expect(find.text('Juana Dela Cruz'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
