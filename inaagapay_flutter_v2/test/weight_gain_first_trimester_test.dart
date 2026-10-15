import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/weight_gain_models.dart';
import 'package:inaagapay_flutter_v2/services/weight_gain_engine.dart';

void main() {
  test('first-trimester profile evaluation handles an obese BMI', () {
    // These inputs previously threw ArgumentError: 1.0 while the profile
    // built its weight-gain analysis, before any record could be viewed.
    final result = WeightGainEngine.evaluate(
      currentWeight: 80.5,
      prePregnancyWeight: 80,
      heightCm: 160,
      aogWeeks: 8,
      allCheckups: const [],
    );

    expect(result.bmiCategory, 'Obese');
    expect(result.mode, WeightGainMode.full);
    expect(result.expectedGainMin, 0);
    expect(result.expectedGainMax, closeTo(0.91, 1e-9));
    expect(result.status, WeightGainStatus.normal);
  });

  test('every BMI and fetal count has a finite ordered first-trimester range',
      () {
    for (final fetalCount in [1, 2]) {
      final guidelines = fetalCount == 1
          ? WeightGainEngine.iomGuidelines
          : WeightGainEngine.iomTwinGuidelines;
      for (final category in guidelines.keys) {
        for (final week in [0.0, 1.0, 8.0, 12.9, 13.0, 13.1, 40.0, 42.0]) {
          final range = WeightGainEngine.getExpectedGainAt(
            aogWeeks: week,
            bmiCategory: category,
            fetalCount: fetalCount,
          );

          expect(range.values.every((value) => value.isFinite), isTrue);
          expect(range['min']!, lessThanOrEqualTo(range['mid']!));
          expect(range['mid']!, lessThanOrEqualTo(range['max']!));
          if (week <= 13) {
            expect(range['min'], 0);
            expect(
                range['max']!,
                lessThanOrEqualTo(
                    guidelines[category]!['first_trimester']! * 1.3));
          }
        }
      }
    }
  });

  test('later chart can use an obese first-trimester baseline', () {
    final range = WeightGainEngine.getExpectedRangeAt(
      aogWeeks: 20,
      bmiCategory: 'Obese',
      baselineWeight: 80,
      baselineWeek: 8,
    );

    expect(range['min']!, greaterThanOrEqualTo(80));
    expect(range['max']!, greaterThanOrEqualTo(range['min']!));
  });

  test('existing valid first-trimester ranges retain their bounds', () {
    final early = WeightGainEngine.getExpectedGainAt(
      aogWeeks: 1,
      bmiCategory: 'Normal',
    );
    final end = WeightGainEngine.getExpectedGainAt(
      aogWeeks: 13,
      bmiCategory: 'Normal',
    );

    expect(early['max'], 1.0);
    expect(end['max'], closeTo(2.08, 1e-9));
  });
}
