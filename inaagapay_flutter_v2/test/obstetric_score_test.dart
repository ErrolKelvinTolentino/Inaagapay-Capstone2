import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/obstetric_score.dart';

void main() {
  group('ObstetricScore Calculation Tests', () {
    test('First pregnancy (currently pregnant, zero past pregnancies)', () {
      final score = ObstetricScore.calculate(
        pastPregnancies: [],
        isCurrentlyPregnant: true,
      );

      expect(score.gravida, 1);
      expect(score.para, 0);
      expect(score.abortus, 0);
      expect(score.livingChildren, 0);
      expect(score.formattedGpal, 'G1 P0 A0 L0');
    });

    test('Serialized past pregnancies with nested outcomes array (4 entries)', () {
      final score = ObstetricScore.calculate(
        pastPregnancies: [
          {
            'fetal_count': 1,
            'gestational_age_at_end': 39.0,
            'outcomes': [
              {
                'outcome': 'live_birth',
                'outcome_date': '2018-01-15',
              }
            ]
          },
          {
            'fetal_count': 2,
            'gestational_age_at_end': 37.0,
            'outcomes': [
              {
                'outcome': 'live_birth',
                'outcome_date': '2020-03-20',
              },
              {
                'outcome': 'live_birth',
                'outcome_date': '2020-03-20',
              }
            ]
          },
          {
            'fetal_count': 1,
            'gestational_age_at_end': 8.0,
            'outcomes': [
              {
                'outcome': 'miscarriage',
                'outcome_date': '2021-11-10',
              }
            ]
          },
          {
            'fetal_count': 1,
            'gestational_age_at_end': 32.0,
            'outcomes': [
              {
                'outcome': 'stillbirth',
                'outcome_date': '2023-08-05',
              }
            ]
          }
        ],
        isCurrentlyPregnant: true,
      );

      expect(score.gravida, 5);
      expect(score.para, 3);
      expect(score.abortus, 1);
      expect(score.livingChildren, 3);
      expect(score.formattedGpal, 'G5 P3 A1 L3');
    });
  });
}
