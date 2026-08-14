import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/gestational_diabetes_screening.dart';

void main() {
  group('one-step 75g protocol — a single value is enough', () {
    test('all samples below threshold reads as below', () {
      const values = GlucoseValues(fasting: 88, oneHour: 150, twoHour: 140);
      expect(GestationalDiabetesScreening.readValues(values),
          GdmResult.belowThreshold);
    });

    test('fasting exactly at 92 meets the threshold', () {
      const values = GlucoseValues(fasting: 92, oneHour: 150, twoHour: 140);
      expect(GestationalDiabetesScreening.readValues(values),
          GdmResult.meetsThreshold);
    });

    test('the 2-hour sample alone is enough', () {
      const values = GlucoseValues(fasting: 85, oneHour: 150, twoHour: 158);
      expect(GestationalDiabetesScreening.readValues(values),
          GdmResult.meetsThreshold);
    });

    test('one below the cut-point does not meet it', () {
      const values = GlucoseValues(fasting: 91, oneHour: 179, twoHour: 152);
      expect(GestationalDiabetesScreening.readValues(values),
          GdmResult.belowThreshold);
    });
  });

  group('two-step 100g protocol — two values are required', () {
    const twoStep = GdmThresholds.twoStep();

    test('one raised sample alone does not meet the criteria', () {
      const values =
          GlucoseValues(fasting: 98, oneHour: 170, twoHour: 140, threeHour: 120);
      expect(
        GestationalDiabetesScreening.readValues(values, thresholds: twoStep),
        GdmResult.belowThreshold,
      );
    });

    test('two raised samples meet the criteria', () {
      const values =
          GlucoseValues(fasting: 98, oneHour: 190, twoHour: 140, threeHour: 120);
      expect(
        GestationalDiabetesScreening.readValues(values, thresholds: twoStep),
        GdmResult.meetsThreshold,
      );
    });

    test('the 3-hour sample counts only under this protocol', () {
      const values = GlucoseValues(fasting: 90, threeHour: 145);
      // Under two-step the 3-hour sample is read, but one value is not enough.
      expect(
        GestationalDiabetesScreening.readValues(values, thresholds: twoStep),
        GdmResult.belowThreshold,
      );
      // Under one-step there is no 3-hour threshold at all.
      expect(GestationalDiabetesScreening.readValues(values),
          GdmResult.belowThreshold);
    });
  });

  group('an incomplete test is not a negative one', () {
    test('too few samples for the two-step protocol reads as incomplete', () {
      const values = GlucoseValues(fasting: 88);
      expect(
        GestationalDiabetesScreening.readValues(values,
            thresholds: const GdmThresholds.twoStep()),
        GdmResult.incomplete,
      );
    });

    test('nothing recorded is no result, not a pass', () {
      expect(GestationalDiabetesScreening.readValues(const GlucoseValues()),
          GdmResult.noResult);
    });

    test('an incomplete test asks to be repeated', () {
      final result = GestationalDiabetesScreening.assess(
        gestationalWeeks: 26,
        values: const GlucoseValues(fasting: 88),
        thresholds: const GdmThresholds.twoStep(),
      );
      expect(result.action, GdmAction.repeatIncompleteTest);
    });
  });

  group('risk factors come from data already on file', () {
    test('older mother, high BMI and a previous big baby all count', () {
      final risk = GestationalDiabetesScreening.assessRisk(
        maternalAge: 37,
        prePregnancyBmi: 28.4,
        previousBirthWeightsGrams: const [4200, 3100],
      );

      expect(risk.hasRiskFactors, isTrue);
      expect(risk.factors.length, 3);
      expect(risk.factors.any((f) => f.contains('37')), isTrue);
      expect(risk.factors.any((f) => f.contains('4.2kg')), isTrue);
    });

    test('a recorded history of diabetes counts once', () {
      final risk = GestationalDiabetesScreening.assessRisk(
        recordedConditions: const ['Type 2 Diabetes', 'Diabetes'],
      );
      expect(risk.factors.length, 1);
    });

    test('a mother with none carries no factors', () {
      final risk = GestationalDiabetesScreening.assessRisk(
        maternalAge: 24,
        prePregnancyBmi: 21.0,
        previousBirthWeightsGrams: const [3200],
        recordedConditions: const ['Anemia'],
      );
      expect(risk.hasRiskFactors, isFalse);
    });

    test('a normal-weight previous baby is not macrosomia', () {
      final risk = GestationalDiabetesScreening.assessRisk(
        previousBirthWeightsGrams: const [3900],
      );
      expect(risk.hasRiskFactors, isFalse);
    });
  });

  group('the screening pathway', () {
    test('before the window with no risk factors, nothing is due', () {
      final result = GestationalDiabetesScreening.assess(gestationalWeeks: 16);
      expect(result.status, GdmScreeningStatus.notYetDue);
      expect(result.action, GdmAction.none);
    });

    test('risk factors bring screening forward before the window', () {
      final result = GestationalDiabetesScreening.assess(
        gestationalWeeks: 16,
        risk: GestationalDiabetesScreening.assessRisk(
          prePregnancyBmi: 31,
          maternalAge: 38,
        ),
      );
      expect(result.status, GdmScreeningStatus.dueEarly);
      expect(result.action, GdmAction.screenAtNextVisit);
      expect(result.finding, contains('BMI'));
    });

    test('inside weeks 24 to 28 screening is due', () {
      final result = GestationalDiabetesScreening.assess(gestationalWeeks: 25);
      expect(result.status, GdmScreeningStatus.due);
      expect(result.action, GdmAction.screenNow);
    });

    test('past the window with no result is overdue', () {
      final result = GestationalDiabetesScreening.assess(gestationalWeeks: 33);
      expect(result.status, GdmScreeningStatus.overdue);
      expect(result.action, GdmAction.screenNow);
      expect(result.finding, contains('week 33'));
    });

    test('a result on file settles it whatever the week', () {
      final result = GestationalDiabetesScreening.assess(
        gestationalWeeks: 33,
        values: const GlucoseValues(fasting: 85, oneHour: 140, twoHour: 130),
      );
      expect(result.status, GdmScreeningStatus.screened);
      expect(result.action, GdmAction.none);
    });

    test('a result meeting threshold refers, and names which samples', () {
      final result = GestationalDiabetesScreening.assess(
        gestationalWeeks: 26,
        values: const GlucoseValues(fasting: 96, oneHour: 185, twoHour: 140),
      );
      expect(result.needsReferral, isTrue);
      expect(result.action, GdmAction.referForAssessment);
      expect(result.samplesAtOrAboveThreshold, ['fasting', '1-hour']);
      expect(result.finding, contains('fasting'));
    });

    test('unknown gestational age says so rather than guessing', () {
      final result = GestationalDiabetesScreening.assess(gestationalWeeks: null);
      expect(result.finding, contains('unknown'));
      expect(result.action, GdmAction.none);
    });
  });

  group('the output never diagnoses', () {
    test('no action or result label names a condition', () {
      final labels = [
        ...GdmAction.values.map((a) => a.label.toLowerCase()),
        ...GdmResult.values.map((r) => r.label.toLowerCase()),
      ];

      for (final label in labels) {
        for (final banned in [
          'gestational diabetes',
          'diabetic',
          'diagnos',
          'positive',
          'negative',
        ]) {
          expect(label.contains(banned), isFalse,
              reason: '"$label" reads as a diagnosis');
        }
      }
    });

    test('a threshold-meeting finding refers without naming the condition', () {
      final result = GestationalDiabetesScreening.assess(
        gestationalWeeks: 26,
        values: const GlucoseValues(fasting: 99, oneHour: 190, twoHour: 160),
      );

      final finding = result.finding.toLowerCase();
      expect(finding.contains('diabetes'), isFalse);
      expect(finding.contains('diagnos'), isFalse);
      expect(finding, contains('threshold'));
    });
  });

  group('thresholds are configurable', () {
    test('a facility can move a cut-point without touching the rules', () {
      const stricter = GdmThresholds(fasting: 85);
      const values = GlucoseValues(fasting: 88);

      expect(
        GestationalDiabetesScreening.readValues(values, thresholds: stricter),
        GdmResult.meetsThreshold,
      );
      expect(GestationalDiabetesScreening.readValues(values),
          GdmResult.belowThreshold);
    });

    test('the screening window itself can move', () {
      const early = GdmThresholds(screeningOpensWeek: 20);
      final result = GestationalDiabetesScreening.assess(
        gestationalWeeks: 21,
        thresholds: early,
      );
      expect(result.status, GdmScreeningStatus.due);
    });
  });
}
