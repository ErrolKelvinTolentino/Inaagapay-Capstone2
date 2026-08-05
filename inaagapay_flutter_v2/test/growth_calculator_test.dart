// Pins the growth engine to the WHO Child Growth Standards.
//
// Expected values are taken from the WHO expanded z-score tables at
// https://www.who.int/tools/child-growth-standards/standards — the same source
// the reference tables in growth_calculator.dart were generated from.
//
// These exist because the height and BMI tables were previously wrong: WHO's
// ±2 SD values sat in the ±3 SD slots, so the app reported a band up to 3.7 cm
// narrower than WHO's and over-flagged stunting in 2-5 year olds. A silent
// numeric regression like that is invisible in the UI, so it needs a test.

import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/growth_calculator.dart';

/// WHO tables are published to one decimal place, so a value sitting exactly on
/// a published boundary lands within a few hundredths of the whole z-score.
const _zTolerance = 0.05;

void main() {
  group('WHO length/height-for-age — girls', () {
    // month: [-2 SD, median, +2 SD]
    const cases = {
      0: [45.4, 49.1, 52.9],
      12: [68.9, 74.0, 79.2],
      24: [79.3, 85.7, 92.2],
      36: [87.4, 95.1, 102.7],
      60: [99.9, 109.4, 118.9],
    };

    cases.forEach((month, values) {
      test('month $month boundaries match WHO', () {
        final week = (month * 4.345).round();
        final range =
            GrowthCalculator.standardRangeAt(GrowthMetric.heightForAge, week, 'female');

        expect(range, isNotNull, reason: 'no reference data at month $month');
        expect(range!['min'], closeTo(values[0], 0.35));
        expect(range['max'], closeTo(values[2], 0.35));
      });

      test('month $month median scores near zero', () {
        final week = (month * 4.345).round();
        final z = GrowthCalculator.calculateHeightZScore(values[1], week, 'female');
        expect(z, isNotNull);
        expect(z!, closeTo(0, 0.15));
      });
    });
  });

  group('WHO weight-for-age — girls', () {
    // The well-known 12-month figures: -2 SD 7.0, median 8.9, +2 SD 11.5.
    test('month 12 boundaries match WHO', () {
      final range =
          GrowthCalculator.standardRangeAt(GrowthMetric.weightForAge, 52, 'female');
      expect(range, isNotNull);
      expect(range!['min'], closeTo(7.0, 0.2));
      expect(range['max'], closeTo(11.5, 0.2));
    });

    test('median weight scores near zero at 12 months', () {
      final z = GrowthCalculator.calculateWeightZScore(8.9, 52, 'female');
      expect(z, isNotNull);
      expect(z!, closeTo(0, 0.15));
    });
  });

  group('band classification', () {
    test('uses the WHO ±2 SD cut-off, not ±1', () {
      // A z of -1.5 is common among healthy children and must not be flagged.
      expect(GrowthCalculator.bandForZScore(-1.5), GrowthBand.within);
      expect(GrowthCalculator.bandForZScore(1.5), GrowthBand.within);
      expect(GrowthCalculator.bandForZScore(-2.5), GrowthBand.below);
      expect(GrowthCalculator.bandForZScore(2.5), GrowthBand.above);
    });

    test('missing or non-finite scores do not raise a false alarm', () {
      expect(GrowthCalculator.bandForZScore(null), GrowthBand.within);
      expect(GrowthCalculator.bandForZScore(double.nan), GrowthBand.within);
      expect(GrowthCalculator.bandForZScore(double.infinity), GrowthBand.within);
    });
  });

  group('reference band round-trips through the z-score', () {
    // The chart draws the band from standardRangeAt and colours the verdict
    // from the z-score. If the two disagree, a point can sit inside the dashed
    // lines while being labelled out of range.
    for (final metric in GrowthMetric.values) {
      for (final week in [4, 13, 26, 52, 130, 260]) {
        test('${metric.name} at week $week', () {
          final range = GrowthCalculator.standardRangeAt(metric, week, 'female');
          if (range == null) return; // no reference data at this age

          final zMin = GrowthCalculator.zScoreFor(metric, range['min']!, week, 'female');
          final zMax = GrowthCalculator.zScoreFor(metric, range['max']!, week, 'female');

          expect(zMin, isNotNull);
          expect(zMax, isNotNull);
          expect(zMin!, closeTo(-2.0, _zTolerance),
              reason: 'lower bound should score exactly -2 SD');
          expect(zMax!, closeTo(2.0, _zTolerance),
              reason: 'upper bound should score exactly +2 SD');
        });
      }
    }
  });

  group('regression guards', () {
    test('height SD widens with age, as WHO does', () {
      // The old table kept ~2.5 cm across every age. WHO widens from roughly
      // 1.9 cm at birth to 4.6 cm at five years; a flat spread means the table
      // has been replaced with interpolated anchors again.
      double sdAt(int month) {
        final week = (month * 4.345).round();
        final range =
            GrowthCalculator.standardRangeAt(GrowthMetric.heightForAge, week, 'female')!;
        return (range['max']! - range['min']!) / 4;
      }

      expect(sdAt(60), greaterThan(sdAt(12) * 1.5),
          reason: 'spread at 5 years should be far wider than at 1 year');
    });

    test('a 101 cm five-year-old girl is within range', () {
      // The specific false positive the old table produced: it put -2 SD at
      // 103.6 cm when WHO puts it at 99.9 cm.
      final z = GrowthCalculator.calculateHeightZScore(101, 261, 'female');
      expect(z, isNotNull);
      expect(GrowthCalculator.bandForZScore(z), GrowthBand.within);
    });
  });
}
