import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/widgets/my_pregnancy_banner.dart';

/// The banner shipped with an 8-pixel bottom overflow. It was invisible to the
/// suite because the banner lived inside MotherDashboard, which needs Supabase
/// and renders only a spinner under test — so a test that pumped the dashboard
/// passed while proving nothing.
///
/// These cases render the banner itself, at the narrow screens and enlarged
/// text this app actually meets.
void main() {
  const phoneWidths = [320.0, 360.0, 390.0, 412.0];
  const textScales = [1.0, 1.15, 1.3, 1.5];

  Widget harness(double scale) => MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MyPregnancyBanner(onTap: () {}),
            ),
          ),
        ),
      );

  testWidgets('never overflows across phone widths and text sizes',
      (tester) async {
    for (final width in phoneWidths) {
      for (final scale in textScales) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(harness(scale));
        await tester.pump();

        // Proves the banner is actually on screen — without this the loop
        // could pass on an empty tree, which is how the original bug hid.
        expect(find.byType(MyPregnancyBanner), findsOneWidget);

        expect(tester.takeException(), isNull,
            reason: 'overflow at width $width, text scale $scale');
      }
    }
  });

  testWidgets('grows taller instead of clipping when text is enlarged',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness(1.0));
    final normal = tester.getSize(find.byType(MyPregnancyBanner)).height;

    await tester.pumpWidget(harness(1.5));
    await tester.pump();
    final enlarged = tester.getSize(find.byType(MyPregnancyBanner)).height;

    expect(enlarged, greaterThan(normal),
        reason: 'a fixed height would clip rather than grow');
  });

  testWidgets('keeps its minimum presence at normal text size',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness(1.0));

    // It is the main destination on Home; it should not shrink to a thin row.
    expect(tester.getSize(find.byType(MyPregnancyBanner)).height,
        greaterThanOrEqualTo(132));
  });

  testWidgets('reads as a destination, not a submit action', (tester) async {
    await tester.pumpWidget(harness(1.0));

    expect(find.text('MY PREGNANCY'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);

    // No ElevatedButton/FilledButton: the visual promise of a filled button is
    // that tapping submits something, and this only opens a page.
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('the whole banner is tappable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MyPregnancyBanner(onTap: () => taps++)),
    ));

    await tester.tap(find.byType(MyPregnancyBanner));
    expect(taps, 1);
  });
}
