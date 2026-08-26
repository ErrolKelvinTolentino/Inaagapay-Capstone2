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

/// Records what was asked of it, so the screen's behaviour can be checked
/// without a database.
class _SpyRepo extends BabyBookRepository {
  _SpyRepo(this._milestones);

  final List<ChildMilestone> _milestones;
  final List<int> removed = [];
  int recordCount = 0;

  @override
  Future<List<ChildMilestone>> loadChildMilestones({
    required int childId,
    required DateTime? birthdate,
  }) async =>
      _milestones;

  @override
  Future<List<BabyGrowthMilestone>> loadChildPrenatalChapter(
          int childId) async =>
      const [];

  @override
  Future<bool> recordChildMilestone({
    required int childId,
    String? templateKey,
    String? title,
    DateTime? observedOn,
    String? note,
    int? recordedByAccountId,
    int? photoFileId,
  }) async {
    recordCount++;
    return true;
  }

  @override
  Future<bool> removeChildMilestone(int entryId) async {
    removed.add(entryId);
    return true;
  }
}

void main() {
  _birthStoryTests();
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

    testWidgets('a kept milestone can be un-kept, after confirming',
        (tester) async {
      // The first version made kept rows untappable, so a mis-tap was
      // permanent. A keepsake you cannot correct is worse than one with a
      // confirmable undo.
      final spy = _SpyRepo([
        ChildMilestone(
          template: _tpl('a', 'Waves bye-bye', 12, 'language'),
          title: 'Waves bye-bye',
          status: BabyGrowthMilestoneStatus.completed,
          observedOn: DateTime(2026, 3, 1),
          entryId: 55,
        ),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: ChildBabyBookPage(
          childId: 7,
          childName: 'Juan',
          birthdate: DateTime(2022, 3, 10),
          repository: spy,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Waves bye-bye'));
      await tester.pumpAndSettle();

      // Asks first, and nothing is gone yet.
      expect(find.text('Remove this?'), findsOneWidget);
      expect(spy.removed, isEmpty);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(spy.removed, [55]);
    });

    testWidgets('backing out of the confirmation removes nothing',
        (tester) async {
      final spy = _SpyRepo([
        ChildMilestone(
          template: _tpl('a', 'Waves bye-bye', 12, 'language'),
          title: 'Waves bye-bye',
          status: BabyGrowthMilestoneStatus.completed,
          observedOn: DateTime(2026, 3, 1),
          entryId: 55,
        ),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: ChildBabyBookPage(
          childId: 7,
          childName: 'Juan',
          birthdate: DateTime(2022, 3, 10),
          repository: spy,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Waves bye-bye'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(spy.removed, isEmpty);
    });

    testWidgets('saving offers an undo', (tester) async {
      final spy = _SpyRepo([
        ChildMilestone(
          template: _tpl('a', 'Runs', 24, 'motor'),
          title: 'Runs',
          status: BabyGrowthMilestoneStatus.current,
        ),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: ChildBabyBookPage(
          childId: 7,
          childName: 'Juan',
          birthdate: DateTime(2022, 3, 10),
          repository: spy,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Runs'));
      // The screen time-boxes its keystore read, and flutter_secure_storage
      // has no handler under test — so the save waits out that timeout before
      // it happens. pumpAndSettle alone does not advance it.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(spy.recordCount, 1);
      expect(find.text('Undo'), findsOneWidget,
          reason: 'the fix for a wrong tap should be on the confirmation, '
              'not something she has to go looking for');
    });

    testWidgets('shows the child, not a clinical header', (tester) async {
      await tester.pumpWidget(page(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.text('Juan Dela Cruz'), findsWidgets);
    });
  });
}

/// A repository that answers with one birth record and nothing else.
class _BirthRepo extends BabyBookRepository {
  const _BirthRepo(this.birth);

  final Map<String, dynamic>? birth;

  @override
  Future<List<ChildMilestone>> loadChildMilestones({
    required int childId,
    required DateTime? birthdate,
  }) async =>
      const [];

  @override
  Future<List<BabyGrowthMilestone>> loadChildPrenatalChapter(
          int childId) async =>
      const [];

  @override
  Future<Map<String, dynamic>?> loadBirthDetails(int childId) async => birth;
}

Widget _book(BabyBookRepository repo) => MaterialApp(
      home: ChildBabyBookPage(
        childId: 1,
        childName: 'Malachi',
        birthdate: DateTime(2026, 1, 10),
        repository: repo,
      ),
    );

void _birthStoryTests() {
  group('the day you were born', () {
    testWidgets('shows the birth record that was already being stored', (
      tester,
    ) async {
      // Every one of these was in birth_details and displayed nowhere. This is
      // the page a mother re-reads, so the point of the test is that recorded
      // facts actually reach it.
      await tester.pumpWidget(_book(const _BirthRepo(<String, dynamic>{
        'birthdate': '2026-01-10',
        'birth_weight': 3.2,
        'birth_length': 49.5,
        'birthplace_facility': 'Barangay Health Station',
        'birthplace_city_municipality': 'Ligao',
        'birthplace_province': 'Albay',
        'delivery_type': 'Normal Spontaneous Vaginal Delivery',
      })));
      await tester.pumpAndSettle();

      expect(find.text('The day you were born'), findsOneWidget);
      // A date she would read aloud, not an ISO string.
      expect(find.text('January 10, 2026'), findsOneWidget);
      expect(find.text('3.2 kg'), findsOneWidget);
      expect(find.text('49.5 cm'), findsOneWidget);
      expect(
        find.text('Barangay Health Station, Ligao, Albay'),
        findsOneWidget,
      );
      expect(find.textContaining('Normal Spontaneous'), findsOneWidget);
    });

    testWidgets('draws only the facts that exist', (tester) async {
      // A half-filled birth record is normal. A keepsake page gains nothing
      // from a row reading "not recorded", so those rows are simply absent.
      await tester.pumpWidget(_book(const _BirthRepo(<String, dynamic>{
        'birthdate': '2026-01-10',
        'birth_weight': null,
        'birth_length': null,
        'birthplace_facility': null,
        'birthplace_city_municipality': null,
        'birthplace_province': null,
        'delivery_type': null,
      })));
      await tester.pumpAndSettle();

      expect(find.text('The day you were born'), findsOneWidget);
      expect(find.text('January 10, 2026'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.textContaining('cm'), findsNothing);
      expect(find.textContaining('not recorded'), findsNothing);
    });

    testWidgets('the chapter is absent when nothing was recorded at all', (
      tester,
    ) async {
      await tester.pumpWidget(_book(const _BirthRepo(null)));
      await tester.pumpAndSettle();

      expect(find.text('The day you were born'), findsNothing);
    });

    testWidgets('the book opens on a cover carrying the child\'s name', (
      tester,
    ) async {
      await tester.pumpWidget(_book(const _BirthRepo(null)));
      await tester.pumpAndSettle();

      // The name is the largest thing on the page, not a row in a list.
      expect(find.text('BABY BOOK'), findsOneWidget);
      final name = tester.widget<Text>(find.text('Malachi').first);
      expect(name.style?.fontSize, greaterThanOrEqualTo(24));
    });
  });
}
