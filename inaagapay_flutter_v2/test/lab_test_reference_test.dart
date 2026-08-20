import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/lab_test_reference.dart';

void main() {
  group('panelFor — matching a test type', () {
    test('the four types actually uploaded at this RHU are recognised', () {
      expect(LabTestReference.panelFor('OGTT (Oral Glucose Tolerance Test)')!.title,
          'Glucose Tolerance');
      expect(LabTestReference.panelFor('Urinalysis')!.title, 'Urinalysis');
      expect(LabTestReference.panelFor('Complete Blood Count (CBC)')!.title,
          'Blood Count');
      expect(LabTestReference.panelFor('HBsAg (Hepatitis B)')!.title,
          'Hepatitis B');
    });

    test('the same test written three ways lands on one panel', () {
      // The type comes from a dropdown, but OCR can propose it too.
      for (final written in [
        'OGTT',
        'OGTT (Oral Glucose Tolerance Test)',
        'Oral Glucose Tolerance Test',
      ]) {
        expect(LabTestReference.panelFor(written)!.title, 'Glucose Tolerance',
            reason: '"$written" should resolve to the OGTT panel');
      }
    });

    test('OGTT is not mistaken for a plain blood sugar', () {
      // Both mention glucose. Matching order is what keeps a four-sample test
      // from reporting a single fasting value.
      final ogtt = LabTestReference.panelFor('OGTT')!;
      expect(ogtt.fields, hasLength(4));
      expect(LabTestReference.panelFor('Fasting Blood Sugar (FBS)')!.fields,
          hasLength(1));
    });

    test('a type with no structured fields returns null', () {
      expect(LabTestReference.panelFor('Stool Exam'), isNull);
      expect(LabTestReference.panelFor('Other'), isNull);
      expect(LabTestReference.panelFor(null), isNull);
      expect(LabTestReference.panelFor(''), isNull);
    });
  });

  group('resultRows — only what the record holds', () {
    test('a partial OGTT shows the samples taken, not the ones missing', () {
      final rows = LabTestReference.resultRows(
        'OGTT (Oral Glucose Tolerance Test)',
        {'fasting_glucose_mg_dl': 92, 'glucose_2hr_mg_dl': 141},
      );

      expect(rows, hasLength(2));
      expect(rows.first.key, 'Fasting');
      expect(rows.first.value, '92 mg/dL');
      expect(rows.last.key, '2 hours');
    });

    test('nulls and empty strings are dropped, zero is kept', () {
      final rows = LabTestReference.resultRows('CBC', {
        'hemoglobin_g_dl': 11.2,
        'hematocrit_pct': null,
        'wbc_count': '',
        'platelet_count': 0,
      });

      expect(rows.map((r) => r.key), ['Haemoglobin', 'Platelets']);
      // Zero is a measurement. Only absence is absence.
      expect(rows.last.value, '0');
    });

    test('units are appended only where laboratories agree on one', () {
      final rows = LabTestReference.resultRows(
        'Complete Blood Count (CBC)',
        {'hemoglobin_g_dl': 11.2, 'wbc_count': 8200},
      );

      expect(rows.first.value, '11.2 g/dL');
      // WBC is reported per microlitre by some labs and as 10^9/L by others,
      // so no unit is asserted.
      expect(rows.last.value, '8200');
    });

    test('a test with no panel yields no rows rather than throwing', () {
      expect(LabTestReference.resultRows('Stool Exam', {'anything': 1}),
          isEmpty);
    });

    test('urinalysis and hepatitis carry their qualitative results', () {
      expect(
        LabTestReference.resultRows('Urinalysis', {'urinalysis_protein': 'trace'}).single.value,
        'trace',
      );
      expect(
        LabTestReference.resultRows('HBsAg (Hepatitis B)', {'hepatitis_b_status': 'Non-reactive'}).single.key,
        'HBsAg',
      );
    });
  });

  group('the registry states no thresholds', () {
    test('no field carries a reference range', () {
      // Pregnancy shifts haemoglobin and glucose cut-points, and this project
      // does not hard-code a threshold without a cited source beside it. The
      // registry reports values; interpretation waits on the adviser.
      for (final type in ['OGTT', 'CBC', 'Urinalysis', 'HBsAg']) {
        final panel = LabTestReference.panelFor(type)!;
        for (final field in panel.fields) {
          expect(field.label.toLowerCase(), isNot(contains('normal')));
          expect(field.label.toLowerCase(), isNot(contains('high')));
          expect(field.label.toLowerCase(), isNot(contains('low')));
        }
      }
    });
  });
}
