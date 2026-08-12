import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/prenatal_schedule_engine.dart';

void main() {
  final visit = DateTime(2026, 3, 10);

  PrenatalScheduleProposal at(double weeks,
          {bool highRisk = false, DateTime? edd}) =>
      PrenatalScheduleEngine.propose(
        lastVisit: visit,
        gestationalWeeks: weeks,
        isHighRisk: highRisk,
        expectedDateOfDelivery: edd,
      );

  group('routine intervals match the conventional schedule', () {
    test('before 28 weeks — every 4 weeks', () {
      expect(at(12).intervalDays, 28);
      expect(at(27.9).intervalDays, 28);
      expect(at(12).date, DateTime(2026, 4, 7));
    });

    test('28 to 35 weeks — every 2 weeks', () {
      expect(at(28).intervalDays, 14);
      expect(at(35.9).intervalDays, 14);
      expect(at(28).date, DateTime(2026, 3, 24));
    });

    test('36 weeks onward — weekly', () {
      expect(at(36).intervalDays, 7);
      expect(at(39).intervalDays, 7);
      expect(at(36).date, DateTime(2026, 3, 17));
    });

    test('band boundaries are inclusive at the lower edge', () {
      // 28 weeks exactly belongs to the fortnightly band, not the monthly one.
      expect(at(27.99).intervalDays, 28);
      expect(at(28.0).intervalDays, 14);
      expect(at(35.99).intervalDays, 14);
      expect(at(36.0).intervalDays, 7);
    });
  });

  group('high risk shortens every interval', () {
    test('before 28 weeks — fortnightly instead of monthly', () {
      expect(at(20, highRisk: true).intervalDays, 14);
      expect(at(20).intervalDays, 28);
    });

    test('from 28 weeks — weekly', () {
      expect(at(30, highRisk: true).intervalDays, 7);
      expect(at(30).intervalDays, 14);
    });

    test('the reason names the risk level, so the date is explainable', () {
      expect(at(30, highRisk: true).reason, contains('High-risk'));
      expect(at(30).reason, contains('Routine'));
    });
  });

  group('post-term outranks everything', () {
    test('past 40 weeks tightens to close surveillance', () {
      expect(at(41).intervalDays, 3);
      expect(at(41).reason, contains('Post-term'));
    });

    test('post-term applies even when not flagged high risk', () {
      expect(at(41, highRisk: false).intervalDays, 3);
      expect(at(41, highRisk: true).intervalDays, 3);
    });
  });

  group('nothing is proposed past a plausible pregnancy', () {
    test('no routine band ever needs capping', () {
      // Each interval is comfortably shorter than the window remaining in its
      // own band, so the cap is a guard rail rather than part of normal
      // scheduling. If this starts failing, an interval has grown too long
      // for the stage of pregnancy it serves.
      for (final weeks in [12.0, 20.0, 27.9, 28.0, 34.0, 36.0, 39.0, 40.0]) {
        expect(at(weeks).cappedAtTerm, isFalse,
            reason: 'week $weeks should not need capping');
      }
    });

    test('deep post-term is pulled back instead of running past week 42', () {
      final late = at(41.9);
      expect(late.cappedAtTerm, isTrue);
      expect(late.reason, contains('Brought forward'));
      expect(late.date.difference(visit).inDays, lessThan(3));
    });

    test('the cap uses the due date when gestation is unknown', () {
      final result = PrenatalScheduleEngine.propose(
        lastVisit: visit,
        gestationalWeeks: null,
        expectedDateOfDelivery: DateTime(2026, 3, 15),
      );

      expect(result.cappedAtTerm, isTrue);
      expect(result.date, DateTime(2026, 3, 29)); // due date + 14 days
    });

    test('an ordinary mid-pregnancy proposal is never capped', () {
      final result = at(20, edd: DateTime(2026, 8, 1));
      expect(result.cappedAtTerm, isFalse);
      expect(result.intervalDays, 28);
    });
  });

  group('missing gestational age still produces a prompt', () {
    test('falls back to the early-pregnancy interval rather than nothing', () {
      final result = PrenatalScheduleEngine.propose(
        lastVisit: visit,
        gestationalWeeks: null,
      );
      expect(result.intervalDays, 28);
      expect(result.date, DateTime(2026, 4, 7));
    });
  });

  group('the proposal is a date, never a time', () {
    test('time components are stripped', () {
      final result = PrenatalScheduleEngine.propose(
        lastVisit: DateTime(2026, 3, 10, 14, 37, 12),
        gestationalWeeks: 30,
      );
      expect(result.date.hour, 0);
      expect(result.date.minute, 0);
      expect(result.date.second, 0);
      expect(result.date, DateTime(2026, 3, 24));
    });
  });

  group('intervals are configurable without touching the rules', () {
    test('a facility on a different schedule changes one object', () {
      const weekly = PrenatalVisitIntervals(earlyPregnancyDays: 21);
      final result = PrenatalScheduleEngine.propose(
        lastVisit: visit,
        gestationalWeeks: 12,
        intervals: weekly,
      );
      expect(result.intervalDays, 21);
      expect(at(12).intervalDays, 28);
    });

    test('the band boundaries themselves can move', () {
      const early = PrenatalVisitIntervals(secondIntervalFromWeek: 24);
      final result = PrenatalScheduleEngine.propose(
        lastVisit: visit,
        gestationalWeeks: 25,
        intervals: early,
      );
      expect(result.intervalDays, 14);
      expect(at(25).intervalDays, 28);
    });
  });
}
