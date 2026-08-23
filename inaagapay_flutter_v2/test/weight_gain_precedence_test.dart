// Pins which yardstick a weight-gain reading is measured against.
//
// A mother can start this app before any midwife has seen her: she completes
// her profile, logs her own weights, and the engine reads them. When she is
// later booked at a health centre, the category her midwife records has to take
// over — her self-logged weights keep appearing in the series, but they stop
// being what the series is judged by.
//
// The order used to place a midwife's stated category *below* a category
// derived from current weight, so it was only consulted when there was no
// weight at all to guess from — in practice, never. The engine's own comment
// says why that fallback is weak: during pregnancy current weight carries the
// gestational gain and reads higher than the true pre-pregnancy category.

import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/weight_gain_models.dart';
import 'package:inaagapay_flutter_v2/services/weight_gain_engine.dart';

/// A woman 1.60 m tall, which puts the Underweight boundary at 47.4 kg and the
/// Overweight boundary at 64.0 kg.
///
/// So 45 kg before pregnancy is Underweight, while 68 kg at 30 weeks reads
/// Overweight on current weight alone — a two-category gap, and exactly why
/// current weight is the wrong thing to categorise a pregnant woman on.
const _heightCm = 160.0;

List<Map<String, dynamic>> _series(List<(double weight, double week)> points) {
  return [
    for (final (weight, week) in points)
      {
        'checkup_weight': weight,
        'age_of_gestation': week,
        'checkup_datetime':
            DateTime(2026, 1, 1).add(Duration(days: (week * 7).round())).toIso8601String(),
      }
  ];
}

void main() {
  group('which category the reading is judged against', () {
    test('a stated pre-pregnancy weight outranks everything', () {
      final result = WeightGainEngine.evaluate(
        currentWeight: 68,
        aogWeeks: 30,
        allCheckups: _series([(45, 8), (68, 30)]),
        prePregnancyWeight: 45,
        heightCm: _heightCm,
        midwifeBmiCategory: 'Obese',
      );

      expect(result.bmiCategory, 'Underweight',
          reason: 'an actual starting weight is the best evidence there is');
    });

    test("a midwife's recorded category beats a guess from current weight", () {
      final result = WeightGainEngine.evaluate(
        currentWeight: 68,
        aogWeeks: 30,
        allCheckups: _series([(62, 12), (68, 30)]),
        heightCm: _heightCm,
        midwifeBmiCategory: 'Underweight',
      );

      // Without the midwife's category this falls to current-weight BMI, which
      // at 68 kg and 1.60 m is 26.6 — Overweight, and wrong.
      expect(result.bmiCategory, 'Underweight',
          reason: 'once a midwife has assessed her, that is the yardstick');
    });

    test('with no midwife assessment she is still given a reading', () {
      final result = WeightGainEngine.evaluate(
        currentWeight: 68,
        aogWeeks: 30,
        allCheckups: _series([(62, 12), (68, 30)]),
        heightCm: _heightCm,
      );

      expect(result.bmiCategory, isNotEmpty,
          reason: 'a self-registered mother must not be left without a chart '
              'just because no midwife has seen her yet');
    });

    test('a category the guidelines do not know is ignored, not trusted', () {
      final result = WeightGainEngine.evaluate(
        currentWeight: 68,
        aogWeeks: 30,
        allCheckups: _series([(62, 12), (68, 30)]),
        prePregnancyWeight: 45,
        heightCm: _heightCm,
        midwifeBmiCategory: 'not-a-category',
      );

      expect(result.bmiCategory, 'Underweight');
      expect(WeightGainEngine.iomGuidelines.containsKey('not-a-category'),
          isFalse);
    });
  });

  group('where the series starts', () {
    test('a stated pre-pregnancy weight is used as given', () {
      final baseline = WeightGainEngine.baselineWeightFor(
        statedPrePregnancyWeight: 54,
        readingsAscending: _series([(58, 10), (63, 22)]),
        heightCm: _heightCm,
      );

      expect(baseline.weight, 54);
      expect(baseline.isEstimated, isFalse);
    });

    test('without one, it is worked back from the earliest reading', () {
      final baseline = WeightGainEngine.baselineWeightFor(
        readingsAscending: _series([(58, 10), (63, 22)]),
        heightCm: _heightCm,
      );

      expect(baseline.weight, isNotNull,
          reason: 'a mother who does not know her starting weight should '
              'still get a chart rather than "analysis may be limited"');
      expect(baseline.isEstimated, isTrue,
          reason: 'a derived figure must be flagged so it can be labelled');
      expect(baseline.weight!, lessThanOrEqualTo(58),
          reason: 'backtracking removes gestational gain, never adds it');
    });

    test('the starting point does not drift as more weights arrive', () {
      // The bug this rules out: backtracking from the *latest* reading would
      // move day zero every time she logs a weight, so her gain would appear
      // to shrink as her pregnancy advanced.
      final early = WeightGainEngine.baselineWeightFor(
        readingsAscending: _series([(58, 10)]),
        heightCm: _heightCm,
      );
      final later = WeightGainEngine.baselineWeightFor(
        readingsAscending: _series([(58, 10), (63, 22), (68, 33)]),
        heightCm: _heightCm,
      );

      expect(later.weight, early.weight,
          reason: 'the earliest reading anchors it, so the anchor is fixed');
    });

    test('nothing to work from yields nothing, rather than a guess', () {
      expect(
        WeightGainEngine.baselineWeightFor(
          readingsAscending: const [],
          heightCm: _heightCm,
        ).weight,
        isNull,
      );
      expect(
        WeightGainEngine.baselineWeightFor(
          readingsAscending: _series([(58, 10)]),
          heightCm: null,
        ).weight,
        isNull,
        reason: 'BMI needs a height; without one there is no estimate to make',
      );
    });
  });

  group('the series keeps every weight, whoever recorded it', () {
    test('self-logged readings after a checkup still count', () {
      // Booked at the health centre in week 20; she keeps logging afterwards.
      final result = WeightGainEngine.evaluate(
        currentWeight: 70,
        aogWeeks: 32,
        allCheckups: _series([(55, 6), (60, 14), (66, 20), (70, 32)]),
        prePregnancyWeight: 54,
        heightCm: _heightCm,
      );

      // Her week-6 self-log, her week-14 self-log, her week-20 checkup and her
      // week-32 self-log all reach the engine — the checkup neither replaces
      // what came before it nor stops what comes after.
      expect(result.baselineWeight, 54,
          reason: 'a stated pre-pregnancy weight anchors a full evaluation');
      expect(result.actualGain, closeTo(70 - 54, 0.001),
          reason: 'gain runs from that anchor to her latest weight, whoever '
              'recorded it');
      expect(result.mode, WeightGainMode.full);
    });
  });
}
