import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/data/baby_growth_milestone_data.dart';
import 'package:inaagapay_flutter_v2/data/pregnancy_growth_data.dart';
import 'package:inaagapay_flutter_v2/data/pregnancy_health_sample_data.dart';
import 'package:inaagapay_flutter_v2/models/baby_growth_milestone.dart';
import 'package:inaagapay_flutter_v2/models/pregnancy_health_record.dart';
import 'package:inaagapay_flutter_v2/screens/baby_book_mockup_page.dart';
import 'package:inaagapay_flutter_v2/widgets/baby_book/baby_growth_milestones_section.dart';
import 'package:inaagapay_flutter_v2/widgets/baby_book/pregnancy_health_records_section.dart';
import 'package:inaagapay_flutter_v2/widgets/main_bottom_navigation.dart';
import 'package:inaagapay_flutter_v2/widgets/pregnancy_growth_journey.dart';

Widget _pregnancyJourney({int numberOfBabies = 1}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: PregnancyGrowthJourney(
            currentPregnancy: demoCurrentPregnancy.copyWith(
              numberOfBabies: numberOfBabies,
            ),
            stages: pregnancyGrowthStages,
          ),
        ),
      ),
    ),
  );
}

Widget _healthRecords({List<PregnancyHealthRecord>? records}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: PregnancyHealthRecordsSection(
            initialRecords: records ?? pregnancyHealthSampleRecords,
          ),
        ),
      ),
    ),
  );
}

Widget _growthMilestones({
  int numberOfBabies = 1,
  List<BabyGrowthMilestone>? milestones,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: BabyGrowthMilestonesSection(
            currentPregnancy: demoCurrentPregnancy.copyWith(
              numberOfBabies: numberOfBabies,
            ),
            initialMilestones: milestones ?? babyGrowthMilestoneSampleData,
          ),
        ),
      ),
    ),
  );
}

/// The filled button carrying [text], matched by subtype rather than exact
/// runtime type.
///
/// These buttons are built with FilledButton.icon, whose runtime type is the
/// private _FilledButtonWithIcon. find.byType compares runtime types exactly,
/// so widgetWithText(FilledButton, ...) misses them even though the button is
/// on screen and hit-testable. The assertions below are about layout — width
/// and horizontal bounds — so matching the subtype is what was meant.
Finder _filledButtonWithText(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );

void main() {
  testWidgets('renders the prenatal baby book in its default state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    expect(find.text('BABY BOOK'), findsOneWidget);
    expect(find.text('20 Weeks Pregnant'), findsOneWidget);
    expect(find.text('Month 5 • Second Trimester'), findsNWidgets(2));
    expect(find.text('Amara! 👋'), findsNothing);
    expect(find.text('8 months old'), findsNothing);
    expect(find.text('Tagalog'), findsNothing);
    expect(find.byType(MainBottomNavigation), findsNothing);
    expect(find.text('Login'), findsNothing);
  });

  testWidgets('shows current Month 5 and Week 20 pregnancy stage', (
    tester,
  ) async {
    await tester.pumpWidget(_pregnancyJourney());
    await tester.pumpAndSettle();

    expect(find.text('Your Baby’s Growth Journey'), findsOneWidget);
    // The journey no longer restates the week. The page states how far along
    // she is once, in the cover card; this section is for browsing months.
    expect(find.textContaining('Weeks Pregnant'), findsNothing);
    expect(find.byKey(const ValueKey('pregnancy-month-5')), findsOneWidget);
    expect(find.text('Month 5 — Weeks 18–22'), findsOneWidget);
    expect(find.text('YOUR CURRENT STAGE'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('pregnancy previous and next arrows change the selected month', (
    tester,
  ) async {
    await tester.pumpWidget(_pregnancyJourney());
    await tester.pumpAndSettle();

    final previousButton = find.byKey(const ValueKey('pregnancy-previous'));
    await tester.ensureVisible(previousButton);
    await tester.pumpAndSettle();
    await tester.tap(previousButton);
    await tester.pumpAndSettle();
    expect(find.text('Month 4 — Weeks 14–17'), findsOneWidget);
    expect(find.text('PREGNANCY GUIDE PREVIEW'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pregnancy-next')));
    await tester.pumpAndSettle();
    expect(find.text('Month 5 — Weeks 18–22'), findsOneWidget);
    expect(find.text('YOUR CURRENT STAGE'), findsOneWidget);
  });

  testWidgets('pregnancy month navigation stops at Month 1 and Month 9', (
    tester,
  ) async {
    await tester.pumpWidget(_pregnancyJourney());
    await tester.pumpAndSettle();

    final monthOne = find.byKey(const ValueKey('pregnancy-month-dot-1'));
    await tester.ensureVisible(monthOne);
    await tester.pumpAndSettle();
    await tester.tap(monthOne);
    await tester.pumpAndSettle();
    expect(find.text('Month 1 of 9'), findsOneWidget);
    final previous = tester.widget<IconButton>(
      find.byKey(const ValueKey('pregnancy-previous')),
    );
    expect(previous.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('pregnancy-month-dot-9')));
    await tester.pumpAndSettle();
    expect(find.text('Month 9 of 9'), findsOneWidget);
    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('pregnancy-next')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('twin pregnancy adapts headings, guidance, and visual state', (
    tester,
  ) async {
    await tester.pumpWidget(_pregnancyJourney(numberOfBabies: 2));
    await tester.pumpAndSettle();

    expect(find.text('Your Babies’ Growth Journey'), findsOneWidget);
    expect(find.text('Twin Pregnancy'), findsNWidgets(2));
    expect(find.text('Your Babies This Month'), findsOneWidget);
    expect(find.text('TWIN VIEW'), findsOneWidget);
    expect(
      find.textContaining('Both fetuses are becoming more active'),
      findsOneWidget,
    );
  });

  testWidgets('replaces duplicate Quick Look cards with the new sections', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    expect(find.text('QUICK LOOK'), findsNothing);
    expect(
      find.byKey(const ValueKey('baby-growth-milestones-section')),
      findsOneWidget,
    );

    // Her vaccines and supplements are the Mother Book's, not the baby's, and
    // records_screen already shows them. The section widget still exists and
    // is covered on its own further down; it is simply not on this page.
    expect(
      find.byKey(const ValueKey('pregnancy-health-records-section')),
      findsNothing,
    );
  });

  testWidgets('health-record filters show provider-recorded sample data', (
    tester,
  ) async {
    await tester.pumpWidget(_healthRecords());
    await tester.pumpAndSettle();

    expect(find.text('Vaccinations and Supplements'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('health-records-picture-card')),
      findsOneWidget,
    );
    expect(find.text('Tetanus-containing Vaccine'), findsOneWidget);
    expect(find.text('SAMPLE DATA'), findsOneWidget);
    expect(find.text('Iron and Folic Acid'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('health-filter-supplement')));
    await tester.pumpAndSettle();
    expect(find.text('Iron and Folic Acid'), findsOneWidget);
    expect(find.text('Tetanus-containing Vaccine'), findsNothing);
  });

  testWidgets('health-record form validates and adds a record', (tester) async {
    await tester.pumpWidget(_healthRecords(records: const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Record').first);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('health-save-record'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Record name is required.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('health-record-name')),
      'Provider-recorded vaccine',
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Provider-recorded vaccine'), findsOneWidget);
  });

  testWidgets('health records can be edited, completed, and deleted', (
    tester,
  ) async {
    final record = PregnancyHealthRecord(
      id: 'editable-health-record',
      type: PregnancyRecordType.vaccination,
      name: 'Original health record',
      recordDate: DateTime(2026, 7, 1),
      status: PregnancyRecordStatus.upcoming,
    );
    await tester.pumpWidget(_healthRecords(records: [record]));
    await tester.pumpAndSettle();

    final menu = find.byKey(
      const ValueKey('health-record-menu-editable-health-record'),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit record'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('health-record-name')),
      'Edited health record',
    );
    final save = find.byKey(const ValueKey('health-save-record'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Edited health record'), findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as completed'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete record'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this record?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('health-confirm-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Edited health record'), findsNothing);
  });

  testWidgets('milestone timeline highlights current and status indicators', (
    tester,
  ) async {
    await tester.pumpWidget(_growthMilestones());
    await tester.pumpAndSettle();

    expect(find.text('Baby Growth Milestones'), findsOneWidget);
    expect(find.text('Your Current Growth Stage'), findsOneWidget);
    expect(
      find.text('Week 20 of approximately 40 weeks'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('milestone-picture-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('milestone-card-pregnancy-confirmed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('milestone-card-first-prenatal-checkup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('milestone-card-first-ultrasound')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('milestone-card-heart-activity')),
      findsNothing,
    );
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    expect(find.textContaining('your baby continues'), findsOneWidget);

    final seeAll = find.byKey(const ValueKey('milestone-see-all'));
    await tester.ensureVisible(seeAll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();
    expect(find.text('Show Less'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('milestone-card-heart-activity')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.schedule_rounded), findsWidgets);

    await tester.ensureVisible(seeAll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();
    expect(find.text('See All'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('milestone-card-heart-activity')),
      findsNothing,
    );
  });

  testWidgets('a personal pregnancy milestone can be added', (tester) async {
    await tester.pumpWidget(_growthMilestones());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Milestone'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('milestone-title')),
      'I felt movement today',
    );
    final save = find.byKey(const ValueKey('milestone-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final seeAll = find.byKey(const ValueKey('milestone-see-all'));
    await tester.ensureVisible(seeAll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();
    expect(find.text('I felt movement today'), findsOneWidget);
    expect(
      find.text('No personal pregnancy milestone has been recorded yet.'),
      findsNothing,
    );
  });

  testWidgets('a personal milestone can be edited and deleted', (tester) async {
    final custom = BabyGrowthMilestone(
      id: 'custom-test-milestone',
      title: 'Original milestone',
      description: 'A personal pregnancy moment.',
      recordedPregnancyWeek: 20,
      pregnancyMonth: 5,
      completedDate: DateTime(2026, 7, 20),
      category: BabyGrowthMilestoneCategory.personalMemory,
      status: BabyGrowthMilestoneStatus.completed,
      isCustom: true,
    );
    await tester.pumpWidget(_growthMilestones(milestones: [custom]));
    await tester.pumpAndSettle();

    final menu = find.byKey(
      const ValueKey('milestone-menu-custom-test-milestone'),
    );
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit milestone'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('milestone-title')),
      'Edited personal milestone',
    );
    final save = find.byKey(const ValueKey('milestone-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Edited personal milestone'), findsOneWidget);

    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete milestone'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this milestone?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('milestone-confirm-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Edited personal milestone'), findsNothing);
  });

  testWidgets('twin milestone mode uses babies wording and shared badge', (
    tester,
  ) async {
    await tester.pumpWidget(_growthMilestones(numberOfBabies: 2));
    await tester.pumpAndSettle();

    expect(find.text('Babies’ Growth Milestones'), findsOneWidget);
    expect(find.text('Twin Pregnancy'), findsOneWidget);
    expect(find.textContaining('your babies continue'), findsOneWidget);
    expect(find.textContaining('baby name'), findsNothing);
  });

  testWidgets('bundles artwork for pregnancy and care picture cards', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    final artwork = await rootBundle.load(
      'assets/images/current_pregnancy_card.png',
    );
    final milestoneArtwork = await rootBundle.load(
      'assets/images/milestone_story_card.png',
    );
    final healthArtwork = await rootBundle.load(
      'assets/images/health_records_card.png',
    );
    expect(artwork.lengthInBytes, greaterThan(0));
    expect(milestoneArtwork.lengthInBytes, greaterThan(0));
    expect(healthArtwork.lengthInBytes, greaterThan(0));
    expect(
      find.byKey(const ValueKey('current-pregnancy-card-artwork')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('milestone-picture-card')),
      findsOneWidget,
    );
    // health_records_card.png stays bundled — the Mother Book will use it —
    // but its card is no longer on the baby's page.
    expect(
      find.byKey(const ValueKey('health-records-picture-card')),
      findsNothing,
    );
  });

  testWidgets('guide pages move forward and back with arrow controls', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
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
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    expect(find.text('Mother and Baby Book'), findsOneWidget);
    expect(find.text('World Health Organization'), findsOneWidget);
    expect(find.text('Download PDF'), findsNWidgets(2));
  });

  testWidgets('favorite moment slideshow rotates through gallery memories', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    expect(find.text('Our first ultrasound ✨'), findsOneWidget);
    expect(find.text('SLIDESHOW 1/2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Five-month bump photo'), findsOneWidget);
    expect(find.text('SLIDESHOW 2/2'), findsOneWidget);
  });

  testWidgets('opens the dedicated memory gallery and photo viewer', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    final galleryButton = find.byKey(const ValueKey('view-memory-gallery'));
    await tester.ensureVisible(galleryButton);
    await tester.pumpAndSettle();
    await tester.tap(galleryButton);
    await tester.pumpAndSettle();

    expect(find.text('MEMORY GALLERY'), findsOneWidget);
    expect(find.text('2 memories • Tap a photo to view it'), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-add-photo')), findsOneWidget);

    await tester.tap(find.text('Our first ultrasound ✨'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2'), findsOneWidget);
    expect(
      find.text('The first little glimpse of our growing baby.'),
      findsOneWidget,
    );
  });

  testWidgets('bundles both downloadable official PDFs', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    final dohPdf = await rootBundle.load('assets/pdf/DOH.pdf');
    final whoPdf = await rootBundle.load('assets/pdf/WHO.pdf');

    expect(dohPdf.lengthInBytes, greaterThan(0));
    expect(whoPdf.lengthInBytes, greaterThan(0));
  });

  testWidgets('bundles the mother and baby hero artwork', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    final heroArtwork = await rootBundle.load(
      'assets/images/mother_baby_hero.png',
    );
    expect(heroArtwork.lengthInBytes, greaterThan(0));
  });

  testWidgets('bundles a visual illustration for every guide page', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    for (var page = 1; page <= 8; page++) {
      final artwork = await rootBundle.load(
        'assets/images/baby_guide_page_$page.png',
      );
      expect(artwork.lengthInBytes, greaterThan(0));
    }
  });

  testWidgets('bundles a visual illustration for every pregnancy month', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    for (var month = 1; month <= 9; month++) {
      final artwork = await rootBundle.load(
        'assets/images/fetal_growth/month_$month.png',
      );
      expect(artwork.lengthInBytes, greaterThan(0));
    }
  });

  testWidgets('renders the complete page without overflow on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Baby Growth Milestones'));
    await tester.pumpAndSettle();
    expect(find.text('Add Milestone').hitTestable(), findsOneWidget);
    final milestoneButton = tester.getRect(
      _filledButtonWithText('Add Milestone'),
    );
    expect(milestoneButton.width, greaterThan(100));
    expect(milestoneButton.left, greaterThanOrEqualTo(20));
    expect(milestoneButton.right, lessThanOrEqualTo(370));
    expect(tester.takeException(), isNull);

    // The Vaccinations and Supplements section moved to the Mother Book. Its
    // own layout is covered by the _healthRecords() cases above.
    expect(find.text('Vaccinations and Supplements'), findsNothing);

    await tester.ensureVisible(
      find.text('Read or download the official guides'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read or download the official guides'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
