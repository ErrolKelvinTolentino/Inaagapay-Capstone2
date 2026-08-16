import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/blood_pressure_reference.dart';

BpReading r(int sys, int dia, {double? weeks}) =>
    BpReading(systolic: sys, diastolic: dia, gestationalWeeks: weeks);

void main() {
  group('categorise — single reading', () {
    test('exactly 140/90 meets the threshold', () {
      // The existing _bpStatus in add_prenatal_checkup_screen.dart compares
      // with `>`, so it calls this reading "Stage 1" while every risk engine
      // calls it high. The cut-point is inclusive.
      expect(BloodPressureReference.categorise(140, 90), BpCategory.raised);
      expect(BloodPressureReference.categorise(139, 89), BpCategory.normal);
    });

    test('either number alone is enough to reach a threshold', () {
      expect(BloodPressureReference.categorise(142, 78), BpCategory.raised);
      expect(BloodPressureReference.categorise(128, 94), BpCategory.raised);
    });

    test('exactly 160/110 is severe, and severe outranks raised', () {
      expect(BloodPressureReference.categorise(160, 95), BpCategory.severe);
      expect(BloodPressureReference.categorise(145, 110), BpCategory.severe);
      expect(BloodPressureReference.categorise(159, 109), BpCategory.raised);
    });

    test('below 90/60 is low', () {
      expect(BloodPressureReference.categorise(88, 65), BpCategory.low);
      expect(BloodPressureReference.categorise(100, 58), BpCategory.low);
      expect(BloodPressureReference.categorise(90, 60), BpCategory.normal);
    });

    test('an impossible pair is unreadable, never low', () {
      // A transposed entry — 80/120 — must not be reported as hypotension.
      expect(BloodPressureReference.categorise(80, 120), BpCategory.unreadable);
      expect(BloodPressureReference.categorise(100, 100), BpCategory.unreadable);
    });

    test('missing values are unreadable', () {
      expect(BloodPressureReference.categorise(null, 90), BpCategory.unreadable);
      expect(BloodPressureReference.categorise(120, null), BpCategory.unreadable);
      expect(BloodPressureReference.categorise(null, null), BpCategory.unreadable);
    });
  });

  group('assess — one reading is not a pattern', () {
    test('a single raised reading asks for a repeat, not a referral', () {
      final result = BloodPressureReference.assess([
        r(118, 76, weeks: 24),
        r(144, 92, weeks: 28),
      ]);

      expect(result.category, BpCategory.raised);
      expect(result.raisedRun.length, 1);
      expect(result.meetsTwoOccasionCriterion, isFalse);
      expect(result.action, BpAction.repeatNextVisit);
      expect(result.needsReferral, isFalse);
    });

    test('two consecutive raised readings meet the criterion', () {
      final result = BloodPressureReference.assess([
        r(118, 76, weeks: 24),
        r(144, 92, weeks: 28),
        r(146, 94, weeks: 32),
      ]);

      expect(result.raisedRun.length, 2);
      expect(result.meetsTwoOccasionCriterion, isTrue);
      expect(result.action, BpAction.referForAssessment);
      expect(result.finding, contains('week 28'));
      expect(result.finding, contains('week 32'));
    });

    test('a normal reading between raised ones breaks the run', () {
      final result = BloodPressureReference.assess([
        r(144, 92, weeks: 24),
        r(120, 78, weeks: 28),
        r(142, 91, weeks: 32),
      ]);

      expect(result.raisedRun.length, 1);
      expect(result.meetsTwoOccasionCriterion, isFalse);
      expect(result.action, BpAction.repeatNextVisit);
    });

    test('an episode that has normalised stops referring but is not forgotten',
        () {
      // The scenario that exposed this: two raised readings met the criterion,
      // then one normal reading reset the card to "within the usual range" and
      // no action — as though the episode had never happened. Pressure moves
      // with rest and time of day, so one normal value is not evidence a
      // hypertensive episode resolved.
      final result = BloodPressureReference.assess([
        r(120, 80, weeks: 16),
        r(120, 80, weeks: 17),
        r(110, 90, weeks: 18),
        r(110, 90, weeks: 19),
        r(120, 80, weeks: 20),
      ]);

      expect(result.category, BpCategory.normal);
      expect(result.raisedRun, isEmpty, reason: 'not currently raised');
      expect(result.everMetCriterion, isTrue, reason: 'but it happened');
      expect(result.priorRaisedEpisode.length, 2);

      // Watching, not nothing — and not still referring either.
      expect(result.action, BpAction.monitor);
      expect(result.needsReferral, isFalse);

      expect(result.finding, contains('back within range'));
      expect(result.finding, contains('week 18'));
      expect(result.finding, contains('not been steady'));
      expect(result.note, contains('does not close an earlier episode'));
    });

    test('a single earlier raised reading is not treated as an episode', () {
      // One raised reading was never a pattern, so it must not become a
      // permanent flag either — that is the over-calling this design avoids.
      final result = BloodPressureReference.assess([
        r(144, 92, weeks: 20),
        r(122, 78, weeks: 24),
        r(120, 80, weeks: 28),
      ]);

      expect(result.everMetCriterion, isFalse);
      expect(result.priorRaisedEpisode, isEmpty);
      expect(result.action, BpAction.none);
      expect(result.finding, contains('within the usual range'));
    });

    test('a past severe reading is named even once pressure settles', () {
      final result = BloodPressureReference.assess([
        r(164, 112, weeks: 30),
        r(150, 96, weeks: 31),
        r(124, 80, weeks: 32),
      ]);

      expect(result.everSevere, isTrue);
      expect(result.action, BpAction.monitor);
      expect(result.finding, contains('severe range'));
    });

    test('a current run still reads as current, not as history', () {
      final result = BloodPressureReference.assess([
        r(120, 80, weeks: 20),
        r(144, 92, weeks: 24),
        r(146, 94, weeks: 28),
      ]);

      expect(result.priorRaisedEpisode, isEmpty,
          reason: 'the run is ongoing, so it is not a past episode');
      expect(result.everMetCriterion, isTrue);
      expect(result.action, BpAction.referForAssessment);
    });
  });

  group('assess — severe range does not wait for a second occasion', () {
    test('one severe reading refers the same day', () {
      final result = BloodPressureReference.assess([
        r(118, 76, weeks: 24),
        r(164, 108, weeks: 28),
      ]);

      expect(result.category, BpCategory.severe);
      expect(result.action, BpAction.referSameDay);
      expect(result.severeReading?.formatted, '164/108');
      expect(result.finding, contains('severe range'));
    });

    test('severe outranks the two-occasion pattern', () {
      final result = BloodPressureReference.assess([
        r(144, 92, weeks: 28),
        r(168, 112, weeks: 32),
      ]);

      expect(result.meetsTwoOccasionCriterion, isTrue);
      expect(result.action, BpAction.referSameDay);
    });
  });

  group('assess — context notes', () {
    test('raised before 20 weeks points to pre-existing hypertension', () {
      final result = BloodPressureReference.assess([r(146, 94, weeks: 14)]);
      expect(result.note, contains('pre-existing'));
    });

    test('raised after 20 weeks carries no pre-existing note', () {
      final result = BloodPressureReference.assess([r(146, 94, weeks: 30)]);
      expect(result.note, isNull);
    });

    test('a low reading mid-pregnancy is explained, not alarmed about', () {
      // Blood pressure falls naturally around weeks 20-24. A purely numeric
      // rule would fire on healthy mothers here.
      final result = BloodPressureReference.assess([r(86, 58, weeks: 22)]);
      expect(result.category, BpCategory.low);
      expect(result.action, BpAction.monitor);
      expect(result.note, contains('normally falls'));
      expect(result.needsReferral, isFalse);
    });
  });

  group('assess — edge cases', () {
    test('no readings reports no data rather than a normal result', () {
      final result = BloodPressureReference.assess([]);
      expect(result.latest, isNull);
      expect(result.action, BpAction.none);
      expect(result.finding, contains('No blood pressure readings'));
    });

    test('unreadable rows are skipped, not treated as findings', () {
      final result = BloodPressureReference.assess([
        r(80, 120, weeks: 20),
        r(118, 76, weeks: 24),
      ]);

      expect(result.latest?.formatted, '118/76');
      expect(result.category, BpCategory.normal);
    });

    test('thresholds are overridable without touching the rules', () {
      const stricter = BpThresholds(raisedSystolic: 130, raisedDiastolic: 80);
      expect(
        BloodPressureReference.categorise(132, 78, thresholds: stricter),
        BpCategory.raised,
      );
      expect(BloodPressureReference.categorise(132, 78), BpCategory.normal);
    });

    test('the number of occasions defining a pattern is configurable', () {
      const threeNeeded = BpThresholds(occasionsForPattern: 3);
      final readings = [r(144, 92, weeks: 28), r(146, 94, weeks: 32)];

      expect(BloodPressureReference.assess(readings).action,
          BpAction.referForAssessment);
      expect(
        BloodPressureReference.assess(readings, thresholds: threeNeeded).action,
        BpAction.repeatNextVisit,
      );
    });
  });

  group('vocabulary stays non-diagnostic', () {
    test('no action or category names a condition', () {
      final words = [
        ...BpAction.values.map((a) => a.label.toLowerCase()),
        ...BpCategory.values.map((c) => c.label.toLowerCase()),
      ];

      for (final word in words) {
        for (final banned in [
          'hypertension',
          'hypotension',
          'preeclampsia',
          'pre-eclampsia',
          'eclampsia',
          'diagnos',
          'stage 1',
          'stage 2',
          'crisis',
        ]) {
          expect(word.contains(banned), isFalse,
              reason: '"$word" names a condition; the app must not diagnose');
        }
      }
    });

    test('findings describe readings and thresholds, not conditions', () {
      final result = BloodPressureReference.assess([
        r(144, 92, weeks: 28),
        r(146, 94, weeks: 32),
      ]);

      final finding = result.finding.toLowerCase();
      expect(finding.contains('hypertension'), isFalse);
      expect(finding.contains('preeclampsia'), isFalse);
      expect(finding, contains('140/90'));
    });
  });
}
