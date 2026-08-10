import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/baby_growth_milestone.dart';
import 'package:inaagapay_flutter_v2/models/milestone_template.dart';
import 'package:inaagapay_flutter_v2/screens/mother/child_baby_book_page.dart';
import 'package:inaagapay_flutter_v2/services/baby_book_repository.dart';

MilestoneTemplate _tpl(String key, String title, int months, String category) =>
    MilestoneTemplate(
      key: key,
      templateId: key.hashCode,
      phase: MilestonePhase.postnatal,
      category: category,
      titleEn: title,
      ageMonthsTarget: months,
    );

class _FakeRepo extends BabyBookRepository {
  const _FakeRepo({this.milestones = const [], this.chapter = const []});

  final List<ChildMilestone> milestones;
  final List<BabyGrowthMilestone> chapter;

  @override
  Future<List<ChildMilestone>> loadChildMilestones({
    required int childId,
    required DateTime? birthdate,
  }) async =>
      milestones;

  @override
  Future<List<BabyGrowthMilestone>> loadChildPrenatalChapter(
          int childId) async =>
      chapter;
}

void main() {
  group('ageInMonths', () {
    test('counts completed months, not started ones', () {
      final born = DateTime(2026, 1, 15);
      expect(
          BabyBookRepository.ageInMonths(born, asOf: DateTime(2026, 4, 14)), 2,
          reason: 'a day short of three months is still two');
      expect(
          BabyBookRepository.ageInMonths(born, asOf: DateTime(2026, 4, 15)), 3);
    });

    test('handles a birthday later in the month than today', () {
      expect(
        BabyBookRepository.ageInMonths(DateTime(2026, 1, 31),
            asOf: DateTime(2026, 3, 1)),
        1,
      );
    });

    test('never returns a negative age', () {
      expect(
        BabyBookRepository.ageInMonths(DateTime(2026, 6, 1),
            asOf: DateTime(2026, 1, 1)),
        0,
      );
    });
  });

  group('postnatalStatusFor', () {
    BabyGrowthMilestoneStatus status(
            {DateTime? on, int? target, required int age}) =>
        BabyBookRepository.postnatalStatusFor(
            observedOn: on, targetMonths: target, childAgeMonths: age);

    test('anything recorded is completed', () {
      expect(status(on: DateTime(2026, 5, 1), target: 6, age: 24),
          BabyGrowthMilestoneStatus.completed);
    });

    test('before the checkpoint is upcoming', () {
      expect(status(target: 12, age: 4), BabyGrowthMilestoneStatus.upcoming);
    });

    test('around the checkpoint is current, with a few months of room', () {
      expect(status(target: 12, age: 12), BabyGrowthMilestoneStatus.current);
      expect(status(target: 12, age: 15), BabyGrowthMilestoneStatus.current);
    });

    test('well past the checkpoint is "not recorded", never missed', () {
      // The DOH book frames these as what a caregiver may expect and points
      // the parent at their health worker. Telling a mother her child failed
      // is not this screen's job.
      final s = status(target: 12, age: 30);
      expect(s, BabyGrowthMilestoneStatus.notRecorded);
      expect(s.label.toLowerCase(), isNot(contains('miss')));
      expect(s.label.toLowerCase(), isNot(contains('late')));
    });
  });

  group('ageLabel', () {
    test('reads as a mother would say it', () {
      expect(ChildMilestone.ageLabel(2), '2 months');
      expect(ChildMilestone.ageLabel(12), '1 year');
      expect(ChildMilestone.ageLabel(24), '2 years');
      expect(ChildMilestone.ageLabel(30), '2 years 6 months');
      expect(ChildMilestone.ageLabel(60), '5 years');
    });

    test('a mother\'s own entry belongs to no checkpoint', () {
      expect(ChildMilestone.ageLabel(null), 'Our own moments');
    });
  });

  group('the screen', () {
    // Deliberately an age that cannot collide with any section heading used
    // below: the header renders the child's age with the same ageLabel the
    // headings use, so a one-year-old would make "1 year" ambiguous and the
    // assertion would be testing the wrong widget.
    Widget page(BabyBookRepository repo) => MaterialApp(
          home: ChildBabyBookPage(
            childId: 7,
            childName: 'Juan Dela Cruz',
            birthdate: DateTime(2022, 3, 10),
            repository: repo,
          ),
        );

    testWidgets('groups milestones under age headings', (tester) async {
      await tester.pumpWidget(page(_FakeRepo(milestones: [
        ChildMilestone(
          template: _tpl('a', 'Rolls from tummy to back', 6, 'motor'),
          title: 'Rolls from tummy to back',
          status: BabyGrowthMilestoneStatus.completed,
          observedOn: DateTime(2026, 2, 1),
        ),
        ChildMilestone(
          template: _tpl('b', 'Waves bye-bye', 12, 'language'),
          title: 'Waves bye-bye',
          status: BabyGrowthMilestoneStatus.current,
        ),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('6 months'), findsOneWidget);
      expect(find.text('1 year'), findsOneWidget);
      expect(find.text('Rolls from tummy to back'), findsOneWidget);
      expect(find.text('Waves bye-bye'), findsOneWidget);
    });

    testWidgets('labels domains in plain language, not clinical terms',
        (tester) async {
      await tester.pumpWidget(page(_FakeRepo(milestones: [
        ChildMilestone(
          template: _tpl('a', 'Laughs', 6, 'social'),
          title: 'Laughs',
          status: BabyGrowthMilestoneStatus.current,
        ),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('Playing and feelings'), findsOneWidget);
      expect(find.textContaining('socio'), findsNothing);
      expect(find.textContaining('emotional'), findsNothing);
    });

    testWidgets('the shared chapter is present but folded', (tester) async {
      await tester.pumpWidget(page(_FakeRepo(chapter: const [
        BabyGrowthMilestone(
          id: 'heart-activity',
          title: 'Heart activity documented',
          description: '',
          category: BabyGrowthMilestoneCategory.development,
          status: BabyGrowthMilestoneStatus.completed,
        ),
      ])));
      await tester.pumpAndSettle();

      // The page should open on the child, not on the pregnancy.
      expect(find.text('Before you were born'), findsOneWidget);
      expect(find.text('Heart activity documented'), findsNothing);

      await tester.tap(find.text('Before you were born'));
      await tester.pumpAndSettle();
      expect(find.text('Heart activity documented'), findsOneWidget);
    });

    testWidgets('states each domain once, not once per row', (tester) async {
      // The first version put the domain on every row, so four motor
      // milestones under one age printed "Moving and playing" four times.
      await tester.pumpWidget(page(_FakeRepo(milestones: [
        for (final t in ['Rolls over', 'Sits up', 'Pushes up', 'Leans'])
          ChildMilestone(
            template: _tpl(t, t, 6, 'motor'),
            title: t,
            status: BabyGrowthMilestoneStatus.current,
          ),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('Moving and playing'), findsOneWidget);
      for (final t in ['Rolls over', 'Sits up', 'Pushes up', 'Leans']) {
        expect(find.text(t), findsOneWidget);
      }
    });

    testWidgets('each domain carries its own icon', (tester) async {
      await tester.pumpWidget(page(_FakeRepo(milestones: [
        ChildMilestone(
          template: _tpl('a', 'Runs', 24, 'motor'),
          title: 'Runs',
          status: BabyGrowthMilestoneStatus.current,
        ),
        ChildMilestone(
          template: _tpl('b', 'Says two words together', 24, 'language'),
          title: 'Says two words together',
          status: BabyGrowthMilestoneStatus.current,
        ),
        ChildMilestone(
          template: _tpl('c', 'Eats with a spoon', 24, 'self_help'),
          title: 'Eats with a spoon',
          status: BabyGrowthMilestoneStatus.current,
        ),
      ])));
      await tester.pumpAndSettle();

      // Distinct pictures, so walking and talking are told apart without
      // reading either word.
      expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
      expect(find.byIcon(Icons.record_voice_over_rounded), findsOneWidget);
      expect(find.byIcon(Icons.front_hand_rounded), findsOneWidget);
    });

    testWidgets('a book with nothing in it says so kindly', (tester) async {
      await tester.pumpWidget(page(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.text('This book is just starting'), findsOneWidget);
    });

    testWidgets('shows the child, not a clinical header', (tester) async {
      await tester.pumpWidget(page(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.text('Juan Dela Cruz'), findsWidgets);
    });
  });
}
