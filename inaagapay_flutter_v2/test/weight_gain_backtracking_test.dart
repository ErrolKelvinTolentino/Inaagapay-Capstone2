import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/weight_gain_models.dart';
import 'package:inaagapay_flutter_v2/services/weight_gain_engine.dart';

/// The back-calculated pre-pregnancy weight must never be fed back in as if it
/// were measured.
///
/// It is derived by subtracting the expected gain from the current weight, so
/// using it as the baseline makes "actual gain" equal the expectation by
/// construction. Every mother then reads as gaining normally, including one
/// who is underweight — which is when a midwife most needs to be told
/// something.
void main() {
  // The case that exposed this: 148 cm, 40 kg, 15 weeks, pre-pregnancy weight
  // unknown.
  const heightCm = 148.0;
  const currentWeight = 40.0;
  const aog = 15.0;

  group('the estimate itself', () {
    final estimate = WeightGainEngine.estimatePrePregnancyBMI(
      currentWeightKg: currentWeight,
      heightCm: heightCm,
      aogWeeks: aog.round(),
    );

    test('back-calculates an underweight baseline', () {
      expect(estimate['category'], 'Underweight');
      expect(estimate['isEstimated'], isTrue);
      expect(estimate['method'], 'backtracked');
    });

    test('is honest that it is an estimate', () {
      // A midwife reading a BMI needs to know whether it was measured. This
      // is the flag the UI relies on to say so.
      expect(estimate['isEstimated'], isTrue);
      expect(estimate['confidence'], isNot('high'));
    });
  });

  group('when two categories both fit', () {
    // Roughly 8% of realistic combinations are consistent with more than one
    // category. 140 cm at 41 kg and 20 weeks fits both Normal and Underweight.
    final ambiguous = WeightGainEngine.estimatePrePregnancyBMI(
      currentWeightKg: 41,
      heightCm: 140,
      aogWeeks: 20,
    );

    test('takes the more cautious reading, not the first in the list', () {
      // Ordering used to begin with Normal and return the first hit, so every
      // ambiguous mother resolved to Normal — hiding the underweight one, and
      // handing her the lower expected-gain range as well.
      expect(ambiguous['category'], 'Underweight');
    });

    test('says so, instead of presenting a guess as settled', () {
      expect(ambiguous['ambiguous'], isTrue);
      expect(ambiguous['confidence'], 'low');
      expect(ambiguous['alternativeCategories'], contains('Normal'));
    });

    test('an unambiguous estimate is not marked ambiguous', () {
      final clear = WeightGainEngine.estimatePrePregnancyBMI(
        currentWeightKg: 75,
        heightCm: 160,
        aogWeeks: 20,
      );
      expect(clear['ambiguous'], isFalse);
    });
  });

  group('feeding the estimate back in', () {
    test('produces a gain that sits exactly on the expectation', () {
      final estimated =
          (WeightGainEngine.estimatePrePregnancyBMI(
        currentWeightKg: currentWeight,
        heightCm: heightCm,
        aogWeeks: aog.round(),
      )['estimatedWeight'] as num)
              .toDouble();

      final result = WeightGainEngine.evaluate(
        currentWeight: currentWeight,
        aogWeeks: aog,
        allCheckups: const [],
        prePregnancyWeight: estimated,
        heightCm: heightCm,
      );

      // The circularity, demonstrated: the gain lands inside the expected
      // range because it *is* the expected gain. This is why the estimate is
      // no longer written to pre_pregnancy_weight.
      expect(result.status, WeightGainStatus.normal);
      expect(result.actualGain, isNotNull);
      expect(result.expectedGainMin, isNotNull);
      expect(result.actualGain!,
          inInclusiveRange(result.expectedGainMin!, result.expectedGainMax!));
    });
  });

  group('leaving it null, as the form now does', () {
    test('does not claim to have evaluated her gain', () {
      final result = WeightGainEngine.evaluate(
        currentWeight: currentWeight,
        aogWeeks: aog,
        allCheckups: const [],
        prePregnancyWeight: null,
        heightCm: heightCm,
      );

      // Trend mode: no baseline was measured, so nothing is asserted about
      // how much she has gained.
      expect(result.mode, WeightGainMode.trend);
      expect(result.status, isNot(WeightGainStatus.normal),
          reason: 'reporting "normal" without a measured baseline is the '
              'defect this test exists to prevent');
    });

    test('still knows she is underweight', () {
      // The category survives without the fake baseline — it is what selects
      // the IOM range, and it is a risk factor in its own right.
      final result = WeightGainEngine.evaluate(
        currentWeight: currentWeight,
        aogWeeks: aog,
        allCheckups: const [],
        prePregnancyWeight: null,
        heightCm: heightCm,
      );

      expect(result.bmiCategory.toLowerCase(), contains('under'));
    });

    test('uses the earliest real checkup weight once one exists', () {
      final result = WeightGainEngine.evaluate(
        currentWeight: currentWeight,
        aogWeeks: aog,
        allCheckups: const [
          {'checkup_weight': 38.0, 'age_of_gestation': 10.0},
          {'checkup_weight': 39.0, 'age_of_gestation': 13.0},
        ],
        prePregnancyWeight: null,
        heightCm: heightCm,
      );

      // Two real measurements are a comparison worth making; the guideline
      // never entered into producing either of them.
      expect(result.baselineWeight, 38.0);
      expect(result.mode, WeightGainMode.trend);
    });
  });

  group('the case reported from the prenatal checkup screen', () {
    // 148 cm, 42.5 kg at 15 weeks, no reported pre-pregnancy weight. The
    // screen showed "Within expected weight gain … current gain +3.0 kg"
    // because its baseline resolver back-calculated 39.5 kg first.
    test('the old backtracked baseline forced a normal verdict', () {
      final backtracked =
          (WeightGainEngine.estimatePrePregnancyBMI(
        currentWeightKg: 42.5,
        heightCm: 148,
        aogWeeks: 15,
      )['estimatedWeight'] as num)
              .toDouble();

      // This is where the 39.5 on the screen came from.
      expect(backtracked, closeTo(39.5, 0.1));

      final result = WeightGainEngine.evaluate(
        currentWeight: 42.5,
        aogWeeks: 15,
        allCheckups: const [],
        prePregnancyWeight: backtracked,
        heightCm: 148,
      );
      expect(result.status, WeightGainStatus.normal);
    });

    test('with no reported baseline it now declines to judge', () {
      final result = WeightGainEngine.evaluate(
        currentWeight: 42.5,
        aogWeeks: 15,
        allCheckups: const [],
        prePregnancyWeight: null,
        heightCm: 148,
      );

      expect(result.mode, WeightGainMode.trend);
      expect(result.status, isNot(WeightGainStatus.normal));
    });
  });

  group('a measured pre-pregnancy weight is still evaluated properly', () {
    test('flags a mother genuinely gaining too little', () {
      // Reported 37 kg before pregnancy and now 37.5 at 15 weeks: half a kilo
      // where 2.9–3.2 was expected. This is the signal the circular version
      // could never produce.
      final result = WeightGainEngine.evaluate(
        currentWeight: 37.5,
        aogWeeks: aog,
        allCheckups: const [],
        prePregnancyWeight: 37.0,
        heightCm: heightCm,
      );

      expect(result.status, WeightGainStatus.low);
    });
  });
}
