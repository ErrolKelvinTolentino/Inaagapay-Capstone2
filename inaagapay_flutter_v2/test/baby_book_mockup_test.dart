import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/main.dart';
import 'package:inaagapay_flutter_v2/widgets/main_bottom_navigation.dart';

void main() {
  testWidgets('opens directly to the baby book mockup', (tester) async {
    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();

    expect(find.text('BABY BOOK'), findsOneWidget);
    expect(find.text('Hello, I am'), findsOneWidget);
    expect(find.text('Amara! 👋'), findsOneWidget);
    expect(find.text('Tagalog'), findsNothing);
    expect(find.byType(MainBottomNavigation), findsNothing);
    expect(find.text('Login'), findsNothing);
  });

  testWidgets('milestone checklist updates within the single-page mockup',
      (tester) async {
    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Crawls or tries to crawl'));
    await tester.pumpAndSettle();

    expect(find.text('3 of 4 achieved'), findsOneWidget);
    await tester.tap(find.text('Crawls or tries to crawl'));
    await tester.pumpAndSettle();
    expect(find.text('4 of 4 achieved'), findsOneWidget);
  });

  testWidgets('guide pages move forward and back with arrow controls',
      (tester) async {
    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Read the book, page by page'), findsOneWidget);
    expect(find.text('PAGE 1'), findsOneWidget);
    expect(find.text('How to use this baby book'), findsOneWidget);
    expect(find.text('Page 1 of 8'), findsOneWidget);
    expect(find.text('PAGE 8'), findsNothing);

    for (var page = 2; page <= 8; page++) {
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Page $page of 8'), findsOneWidget);
    }

    expect(find.text('PAGE 8'), findsOneWidget);
    expect(find.text('Care is a team effort'), findsOneWidget);

    await tester.ensureVisible(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE 7'), findsOneWidget);
    expect(find.textContaining('Kumusta'), findsNothing);
  });

  testWidgets('shows official baby book reference labels', (tester) async {
    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();

    expect(find.text('Mother and Baby Book'), findsOneWidget);
    expect(find.text('World Health Organization'), findsOneWidget);
    expect(find.text('Download PDF'), findsNWidgets(2));
  });

  testWidgets('favorite moment slideshow rotates through gallery memories',
      (tester) async {
    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();

    expect(find.text('First time crawling! ✨'), findsOneWidget);
    expect(find.text('SLIDESHOW 1/2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Safe in Mama’s arms'), findsOneWidget);
    expect(find.text('SLIDESHOW 2/2'), findsOneWidget);
  });

  testWidgets('opens the dedicated memory gallery and photo viewer',
      (tester) async {
    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();

    final galleryButton = find.byKey(const ValueKey('view-memory-gallery'));
    await tester.ensureVisible(galleryButton);
    await tester.pumpAndSettle();
    await tester.tap(galleryButton);
    await tester.pumpAndSettle();

    expect(find.text('MEMORY GALLERY'), findsOneWidget);
    expect(find.text('2 memories • Tap a photo to view it'), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-add-photo')), findsOneWidget);

    await tester.tap(find.text('First time crawling! ✨'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('From the play mat to Mama—you were so fast!'),
        findsOneWidget);
  });

  testWidgets('bundles both downloadable official PDFs', (tester) async {
    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();

    final dohPdf = await rootBundle.load('assets/pdf/DOH.pdf');
    final whoPdf = await rootBundle.load('assets/pdf/WHO.pdf');

    expect(dohPdf.lengthInBytes, greaterThan(0));
    expect(whoPdf.lengthInBytes, greaterThan(0));
  });

  testWidgets('bundles the mother and baby hero artwork', (tester) async {
    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();

    final heroArtwork =
        await rootBundle.load('assets/images/mother_baby_hero.png');
    expect(heroArtwork.lengthInBytes, greaterThan(0));
  });

  testWidgets('bundles a visual illustration for every guide page',
      (tester) async {
    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();

    for (var page = 1; page <= 8; page++) {
      final artwork =
          await rootBundle.load('assets/images/baby_guide_page_$page.png');
      expect(artwork.lengthInBytes, greaterThan(0));
    }
  });

  testWidgets('renders the complete page without overflow on a compact phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const InaagapayApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2400),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read or download the official guides'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
