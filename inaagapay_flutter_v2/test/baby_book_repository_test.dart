import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/baby_growth_milestone.dart';
import 'package:inaagapay_flutter_v2/services/baby_book_repository.dart';

/// Covers the parts of BabyBookRepository that are pure computation: how a
/// pregnancies row becomes a header, and how a milestone's status is derived.
///
/// Status especially, because the whole point of deriving it is that it stays
/// true as time passes. A test is the only thing keeping it that way.
void main() {
  String isoDaysAgo(int days) => DateTime.now()
      .subtract(Duration(days: days))
      .toIso8601String()
      .split('T')
      .first;

  group('gestationalWeek', () {
    final lmp = DateTime(2026, 1, 1);

    test('counts completed weeks since LMP', () {
      expect(
        BabyBookRepository.gestationalWeek(lmp,
            asOf: lmp.add(const Duration(days: 140))),
        20,
      );
    });

    test('does not round a partial week up', () {
      expect(
        BabyBookRepository.gestationalWeek(lmp,
            asOf: lmp.add(const Duration(days: 146))),
        20,
      );
    });

    test('clamps past 42 weeks rather than running off the timeline', () {
      expect(
        BabyBookRepository.gestationalWeek(lmp,
            asOf: lmp.add(const Duration(days: 400))),
        42,
      );
    });

    test('clamps a future LMP to zero instead of going negative', () {
      expect(
        BabyBookRepository.gestationalWeek(lmp,
            asOf: lmp.subtract(const Duration(days: 30))),
        0,
      );
    });
  });

  group('stageForWeek', () {
    test('week 20 is month 5, second trimester', () {
      final stage = BabyBookRepository.stageForWeek(20);
      expect(stage?.month, 5);
      expect(stage?.trimester, 'Second Trimester');
    });

    test('boundaries land in the expected month', () {
      expect(BabyBookRepository.stageForWeek(4)?.month, 1);
      expect(BabyBookRepository.stageForWeek(5)?.month, 2);
      expect(BabyBookRepository.stageForWeek(28)?.month, 7);
      expect(BabyBookRepository.stageForWeek(40)?.month, 9);
    });

    test('outside the timeline clamps to an end rather than returning null', () {
      expect(BabyBookRepository.stageForWeek(0)?.month, 1);
      expect(BabyBookRepository.stageForWeek(42)?.month, 9);
    });
  });

  group('currentPregnancyFromRow', () {
    test('builds a header from LMP', () {
      final state = BabyBookRepository.currentPregnancyFromRow({
        'last_menstrual_period': isoDaysAgo(140),
        'expected_date_of_delivery': null,
        'fetal_count': '1',
      });

      expect(state, isNotNull);
      expect(state!.currentWeek, 20);
      expect(state.currentMonth, 5);
      expect(state.trimester, 'Second Trimester');
      expect(state.numberOfBabies, 1);
      expect(state.pregnancyProgress, closeTo(0.5, 0.001));
    });

    test('recovers LMP from EDD when LMP is missing', () {
      // EDD is LMP + 280 days, so an EDD 140 days out implies week 20.
      final edd = DateTime.now().add(const Duration(days: 140));
      final state = BabyBookRepository.currentPregnancyFromRow({
        'last_menstrual_period': null,
        'expected_date_of_delivery': edd.toIso8601String().split('T').first,
        'fetal_count': '1',
      });

      expect(state?.currentWeek, 20);
    });

    test('returns null when neither date is present', () {
      final state = BabyBookRepository.currentPregnancyFromRow({
        'last_menstrual_period': null,
        'expected_date_of_delivery': null,
        'fetal_count': '1',
      });

      expect(state, isNull,
          reason: 'no gestational age is better than a guessed one');
    });

    test('reads a twin pregnancy from fetal_count', () {
      final state = BabyBookRepository.currentPregnancyFromRow({
        'last_menstrual_period': isoDaysAgo(140),
        'fetal_count': '2',
      });

      expect(state?.numberOfBabies, 2);
      expect(state?.isTwinPregnancy, isTrue);
    });

    test('falls back to a singleton when fetal_count is unparseable', () {
      final state = BabyBookRepository.currentPregnancyFromRow({
        'last_menstrual_period': isoDaysAgo(140),
        'fetal_count': 'Unknown',
      });

      expect(state?.numberOfBabies, 1);
    });

    test('progress never exceeds 1 for a post-term pregnancy', () {
      final state = BabyBookRepository.currentPregnancyFromRow({
        'last_menstrual_period': isoDaysAgo(300),
        'fetal_count': '1',
      });

      expect(state!.pregnancyProgress, lessThanOrEqualTo(1.0));
    });
  });

  group('statusFor', () {
    BabyGrowthMilestoneStatus status({
      DateTime? observedOn,
      int? start,
      int? end,
      required int week,
    }) =>
        BabyBookRepository.statusFor(
          observedOn: observedOn,
          expectedStartWeek: start,
          expectedEndWeek: end,
          currentWeek: week,
        );

    test('anything recorded is completed, whenever it happened', () {
      expect(
        status(observedOn: DateTime(2026, 5, 1), start: 18, end: 22, week: 39),
        BabyGrowthMilestoneStatus.completed,
      );
    });

    test('before the window is upcoming', () {
      expect(status(start: 18, end: 22, week: 12),
          BabyGrowthMilestoneStatus.upcoming);
    });

    test('inside the window is current', () {
      expect(status(start: 18, end: 22, week: 20),
          BabyGrowthMilestoneStatus.current);
      expect(status(start: 18, end: 22, week: 18),
          BabyGrowthMilestoneStatus.current);
      expect(status(start: 18, end: 22, week: 22),
          BabyGrowthMilestoneStatus.current);
    });

    test('a single-week window still reads as current on that week', () {
      expect(status(start: 14, week: 14), BabyGrowthMilestoneStatus.current);
    });

    test('past the window with nothing recorded is "not recorded", not missed',
        () {
      // Many of these depend on a provider documenting something. Calling it
      // missed would blame the mother for a record that was never hers to make.
      expect(status(start: 18, end: 22, week: 30),
          BabyGrowthMilestoneStatus.notRecorded);
    });

    test('a milestone with no window cannot be early or late', () {
      expect(status(week: 20), BabyGrowthMilestoneStatus.notRecorded);
    });
  });
}
