import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/data/baby_growth_milestone_data.dart';
import 'package:inaagapay_flutter_v2/widgets/baby_book/baby_care_guide_book.dart';
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

    // SecondaryHeader, not MainHeader — the baby book is always pushed from
    // the Children page and needs a back arrow, which the shell header does
    // not have. SecondaryHeader also does not uppercase its title.
    expect(find.text('Baby Book'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget,
        reason: 'a pushed page must offer a way back');
    expect(find.text('20 Weeks Pregnant'), findsOneWidget);
    // Once, not twice. The week, the month, the trimester, the due date and
    // the progress percentage used to be repeated across a cover card, a
    // stats card and the growth journey. A mother reading down the page met
    // the same three numbers three times and had to work out whether they
    // disagreed. They are now stated once, in the hero card.
    expect(find.text('Month 5 • Second Trimester'), findsOneWidget);
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
    // The pill carries the weeks, and carries them once. There is no longer a
    // large dark heading repeating what the pill above it just said.
    expect(find.text('WEEKS 18–22'), findsOneWidget);
    expect(find.text('Weeks 18–22'), findsNothing);
    expect(find.text('YOUR CURRENT STAGE'), findsNothing);
    // The trimester sits beside the pill and is stated once.
    expect(find.text('Second Trimester'), findsOneWidget);
    // Progress belongs to the hero card, not to this browsable section.
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('the guide disclaimer is one tap from the stage card', (
    tester,
  ) async {
    // Phone-sized, not the 800x600 default: the sheet is sized against the
    // viewport, and on the short default its button sits on the clipped edge.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_pregnancyJourney());
    await tester.pumpAndSettle();

    // Not on the page by default — it used to sit permanently at the bottom
    // of the section in 10pt amber text.
    expect(find.textContaining('Every pregnancy is different'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pregnancy-guide-disclaimer')));
    await tester.pumpAndSettle();

    expect(find.text('About this guide'), findsOneWidget);
    expect(
      find.textContaining('does not take the place'),
      findsOneWidget,
      reason: 'the guide must still say it is not a substitute for her midwife',
    );

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('About this guide'), findsNothing);
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
    expect(find.text('WEEKS 14–17'), findsOneWidget);
    expect(find.text('Second Trimester'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pregnancy-next')));
    await tester.pumpAndSettle();
    expect(find.text('WEEKS 18–22'), findsOneWidget);
    expect(find.text('Second Trimester'), findsOneWidget);
  });

  testWidgets('pregnancy month navigation stops at Month 1 and Month 9', (
    tester,
  ) async {
    await tester.pumpWidget(_pregnancyJourney());
    await tester.pumpAndSettle();

    // Three months at a time, the selected one in the middle. She starts on
    // month 5, so the window is 4-5-6 and nothing else is on screen.
    final previousButton = find.byKey(const ValueKey('pregnancy-previous'));
    final nextButton = find.byKey(const ValueKey('pregnancy-next'));
    await tester.ensureVisible(previousButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pregnancy-month-dot-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-3')), findsNothing);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-7')), findsNothing);

    // Re-scroll before each tap: the stage card is a different height for
    // every month, so the navigator moves under the viewport as she pages.
    for (var tap = 0; tap < 4; tap++) {
      await tester.ensureVisible(previousButton);
      await tester.pumpAndSettle();
      await tester.tap(previousButton);
      await tester.pumpAndSettle();
    }

    // At month 1 the window cannot centre, so it clamps to 1-2-3 rather than
    // shrinking — the arrows must not move as she pages.
    expect(find.byKey(const ValueKey('pregnancy-month-dot-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-4')), findsNothing);
    expect(
      tester.widget<IconButton>(previousButton).onPressed,
      isNull,
      reason: 'there is no month before the first',
    );

    for (var tap = 0; tap < 8; tap++) {
      await tester.ensureVisible(nextButton);
      await tester.pumpAndSettle();
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }

    expect(find.byKey(const ValueKey('pregnancy-month-dot-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-9')), findsOneWidget);
    expect(find.byKey(const ValueKey('pregnancy-month-dot-6')), findsNothing);
    expect(
      tester.widget<IconButton>(nextButton).onPressed,
      isNull,
      reason: 'there is no month after the ninth',
    );

    // The caption that used to sit between the arrows is gone; the circles
    // themselves carry the position now.
    expect(find.textContaining('of 9'), findsNothing);
  });

  testWidgets('twin pregnancy adapts headings, guidance, and visual state', (
    tester,
  ) async {
    await tester.pumpWidget(_pregnancyJourney(numberOfBabies: 2));
    await tester.pumpAndSettle();

    expect(find.text('Your Babies’ Growth Journey'), findsOneWidget);
    // One badge, in the growth journey. The second one lived on the cover
    // card that the journey no longer draws.
    expect(find.text('Twin Pregnancy'), findsOneWidget);
    expect(find.text('Your Babies This Month'), findsOneWidget);
    expect(find.text('TWIN VIEW'), findsOneWidget);
    expect(
      find.textContaining('Both babies are becoming more active'),
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

    // The heading names what the list actually holds: checkups, scans and
    // trimester changes. It used to promise the baby's growth, which is the
    // section above this one.
    expect(find.text('Pregnancy Milestones'), findsOneWidget);
    expect(find.text('Baby Growth Milestones'), findsNothing);
    // "Your Current Growth Stage" told her the week and then described the
    // baby's development a third time. Both are gone.
    expect(find.text('Your Current Growth Stage'), findsNothing);
    expect(find.text('Week 20 of approximately 40 weeks'), findsNothing);
    expect(
      find.byKey(const ValueKey('milestone-picture-card')),
      findsOneWidget,
    );
    // The catalogue comes from the database. Nothing here invites her to add
    // her own row among the recommendations.
    expect(find.text('Add Milestone'), findsNothing);
    expect(
      find.textContaining('not added a milestone of your own'),
      findsNothing,
    );
    // The pink category line under each title is gone; it restated a word
    // already in the title.
    expect(find.text('Ultrasound'), findsNothing);
    expect(find.text('Checkup'), findsNothing);
    // One timing pill, and no "Month 1" beside a range that ends at week 24.
    expect(find.textContaining('Recommended'), findsWidgets);
    expect(find.textContaining('Commonly weeks'), findsNothing);
    expect(find.textContaining('Month 1'), findsNothing);
    // The first three recommended care milestones, in week order.
    expect(
      find.byKey(const ValueKey('milestone-card-first-prenatal-checkup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('milestone-card-haemoglobin-test')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('milestone-card-blood-typing')),
      findsOneWidget,
    );
    // Each lab test is its own row, so a mother who had one and not the
    // others has something honest to mark.
    expect(
      find.byKey(const ValueKey('milestone-card-early-pregnancy-labs')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('milestone-card-gestational-diabetes-screening')),
      findsNothing,
      reason: 'the later milestones are behind See All',
    );
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    // Developmental moments are not care she can attend, so they no longer
    // share the list with her checkups. They belong to the growth journey.
    expect(find.textContaining('first movement'), findsNothing);
    expect(find.textContaining('Heart activity'), findsNothing);
    expect(find.textContaining('Entered second trimester'), findsNothing);

    final seeAll = find.byKey(const ValueKey('milestone-see-all'));
    await tester.ensureVisible(seeAll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();
    expect(find.text('Show Less'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('milestone-card-gestational-diabetes-screening')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('milestone-card-third-trimester-checkups')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.schedule_rounded), findsWidgets);

    await tester.ensureVisible(seeAll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();
    expect(find.text('See All'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('milestone-card-gestational-diabetes-screening')),
      findsNothing,
    );
  });

  testWidgets('what the record says is on the milestone she opens, not on '
      'every card', (tester) async {
    await tester.pumpWidget(_growthMilestones());
    await tester.pumpAndSettle();

    // Not on the cards. Nine rows each carrying the sentence turned a list
    // she should be able to scan into a wall of paragraphs.
    expect(find.textContaining('not yet recorded in InaAgapay'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('milestone-card-haemoglobin-test')),
    );
    await tester.pumpAndSettle();

    // Not recorded: say so, and send her to her midwife rather than deciding
    // whether it was done elsewhere or still needs booking.
    final guidance = tester.widget<Text>(
      find.byKey(const ValueKey('milestone-guidance-haemoglobin-test')),
    );
    expect(guidance.data, contains('not yet recorded in InaAgapay'));
    expect(guidance.data, contains('ask your midwife'));
  });

  testWidgets('a mother can mark a checkup done and take the mark off again', (
    tester,
  ) async {
    // She may have had the checkup anywhere — a private clinic, a hospital in
    // the next town — and the barangay record will not know. The mark is how
    // she says so, and it has to come off again for a mistap.
    final calls = <({String id, bool markingDone})>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BabyGrowthMilestonesSection(
              currentPregnancy: demoCurrentPregnancy,
              initialMilestones: babyGrowthMilestoneSampleData,
              onToggleCompleted: (milestone, markingDone) async {
                calls.add((id: milestone.id, markingDone: markingDone));
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menu = find.byKey(const ValueKey('milestone-menu-haemoglobin-test'));
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();

    // Editing and deleting a recommended milestone were never hers to do.
    expect(find.text('Edit milestone'), findsNothing);
    expect(find.text('Delete milestone'), findsNothing);
    expect(find.text('Mark as completed'), findsOneWidget);

    await tester.tap(find.text('Mark as completed'));
    await tester.pumpAndSettle();
    expect(calls, [(id: 'haemoglobin-test', markingDone: true)]);

    // The same menu now offers to take it back off.
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Un-mark as completed'), findsOneWidget);
    expect(find.text('Mark as completed'), findsNothing);

    await tester.tap(find.text('Un-mark as completed'));
    await tester.pumpAndSettle();
    expect(calls.last, (id: 'haemoglobin-test', markingDone: false));
  });

  testWidgets('a mark that fails to save is rolled back, not left showing', (
    tester,
  ) async {
    // The failure this guards is the quiet one: a checkmark that lives on
    // screen and nowhere else, gone the next time she opens the page.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BabyGrowthMilestonesSection(
              currentPregnancy: demoCurrentPregnancy,
              initialMilestones: babyGrowthMilestoneSampleData,
              onToggleCompleted: (milestone, markingDone) async => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menu = find.byKey(const ValueKey('milestone-menu-haemoglobin-test'));
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as completed'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not save'),
      findsOneWidget,
      reason: 'a failed write must be visible, not swallowed',
    );

    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(
      find.text('Mark as completed'),
      findsOneWidget,
      reason: 'the row went back to unmarked when the write failed',
    );
  });

  testWidgets('the recommended milestones stay non-prescriptive', (
    tester,
  ) async {
    // The list names the usual weeks and the usual tests, and stops there.
    // Deciding that a particular test applies to a particular pregnancy is
    // the midwife's call, and the copy must not drift into making it.
    for (final milestone in babyGrowthMilestoneSampleData) {
      final text = '${milestone.title} ${milestone.description}'.toLowerCase();
      for (final forbidden in const <String>[
        'you must',
        'you need to',
        'you are overdue',
        'diagnos',
        'abnormal',
        'at risk',
      ]) {
        expect(
          text.contains(forbidden),
          isFalse,
          reason: '"${milestone.title}" should not say "$forbidden"',
        );
      }
    }
  });

  testWidgets('twin milestone mode uses babies wording and shared badge', (
    tester,
  ) async {
    await tester.pumpWidget(_growthMilestones(numberOfBabies: 2));
    await tester.pumpAndSettle();

    // No twin variant of the heading any more: checkups and scans belong to
    // the pregnancy, not to one baby or two, so there is nothing to pluralise.
    expect(find.text('Pregnancy Milestones'), findsOneWidget);
    expect(find.text('Babies’ Growth Milestones'), findsNothing);
    expect(find.text('Twin Pregnancy'), findsOneWidget);
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

  testWidgets('the care guide is not in the pregnancy book', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BabyBookMockupPage()));
    await tester.pumpAndSettle();

    // Its eight pages are about a baby who has been born — first days,
    // feeding through the first year, home safety. Showing them to a mother
    // who is still pregnant put the wrong half of her life on the page. The
    // guide now lives in the baby book of a registered child.
    expect(find.text('Read the book, page by page'), findsNothing);
    expect(find.text('How to use this baby book'), findsNothing);
    expect(find.text('Feeding through the first year'), findsNothing);
  });

  testWidgets('guide pages move forward and back with arrow controls', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: BabyCareGuideBook()),
      ),
    ));
    await tester.pumpAndSettle();

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

    await tester.ensureVisible(find.text('Pregnancy Milestones'));
    await tester.pumpAndSettle();
    // The Add Milestone button that used to be measured here is gone: the
    // catalogue is read from the database and is not hers to write to. The
    // section still has to fit the phone, which is what the sweep below and
    // the exception check either side of it cover.
    final milestoneCard = tester.getRect(
      find.byKey(const ValueKey('milestone-card-first-prenatal-checkup')),
    );
    expect(milestoneCard.left, greaterThanOrEqualTo(0));
    expect(milestoneCard.right, lessThanOrEqualTo(390));
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
