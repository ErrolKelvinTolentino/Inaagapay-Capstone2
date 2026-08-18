import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/maternal_td_screen.dart';

/// The Td screen degrades to an empty-status view when Supabase is not
/// initialised, which is exactly the widest layout: five dose chips, the hero
/// card, and the administration form all on screen at once. That makes it a
/// usable smoke test for overflow on small handsets.
Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(
      home: MaternalTdScreen(motherId: 1, motherName: 'Test Mother'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders without overflow on a small handset', (tester) async {
    await _pumpAt(tester, const Size(320, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflow at 375x812', (tester) async {
    await _pumpAt(tester, const Size(375, 812));
    expect(tester.takeException(), isNull);

    // The dose progress strip shows all five doses.
    for (final key in ['Td1', 'Td2', 'Td3', 'Td4', 'Td5']) {
      expect(find.text(key), findsWidgets, reason: '$key chip missing');
    }
  });

  testWidgets('backfill is reachable from the administer tab', (tester) async {
    await _pumpAt(tester, const Size(375, 812));

    // Backfill is a first-class action, not buried in the history tab.
    expect(find.text('Backfill Past Doses'), findsOneWidget);
    expect(find.text('Doses given somewhere else?'), findsOneWidget);
  });

  testWidgets('no outside-clinic option is offered', (tester) async {
    await _pumpAt(tester, const Size(375, 812));

    // Doses given elsewhere are recorded through backfill instead.
    expect(find.text('Outside Clinic'), findsNothing);
    expect(find.text('Administration Source'), findsNothing);
  });

  testWidgets('history tab lists the full DOH timeline', (tester) async {
    await _pumpAt(tester, const Size(375, 812));

    await tester.tap(find.text('Lifetime History'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('DOH 5-Dose Td Timeline'), findsOneWidget);
    expect(find.textContaining('of 5 doses recorded'), findsOneWidget);
  });
}
