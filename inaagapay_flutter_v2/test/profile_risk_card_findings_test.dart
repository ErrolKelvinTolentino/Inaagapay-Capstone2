// Guards the risk sheet against two failures that neither the analyzer nor a
// rendering test would catch.
//
// The first is silent evidence loss. `considerableFactors` — the ultrasound,
// laboratory and check-up entries marked for closer monitoring — was built from
// all three record types, sorted by date, and passed into the sheet, which then
// rendered only the registration factors and dropped it. Dart does not warn on
// an unused parameter, so the sheet showed half its evidence and looked
// complete doing it.
//
// The second is vocabulary. This widget summarises records it is not entitled
// to interpret; "abnormal" and "elevated" are judgements a clinician makes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/widgets/profile_risk_card.dart';

const _riskCard = 'lib/widgets/profile_risk_card.dart';

List<String> _collapse(List<String> rows) {
  final working = [...rows];
  RiskFactorRows.collapseInPlace(working);
  return working;
}

/// The file's source with `//` comments stripped.
///
/// The widget explains in comments exactly which words were removed and why,
/// and that explanation must not fail the scan that enforces it.
String _codeOf(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue,
      reason: '$path not found — run tests from the package root');
  return file.readAsLinesSync().map((line) {
    final comment = line.indexOf('//');
    return comment == -1 ? line : line.substring(0, comment);
  }).join('\n');
}

void main() {
  group('one row per finding', () {
    test('the three maternal-age wordings collapse to one', () {
      // Exactly what a 17-year-old's sheet showed: the add-mother form's row,
      // the prenatal check-up's row, and a repeat of the check-up's row.
      final rows = _collapse([
        'Maternal age below 19 years',
        'High blood pressure (>=140/90) (high)',
        'Maternal age factor (17 years) (low)',
        'Maternal age factor (17 years) (low)',
        'Allergy to Fish',
      ]);

      expect(rows.where((r) => r.toLowerCase().contains('maternal age')).length,
          1,
          reason: 'three rows describe one finding and should collapse to one');
      expect(rows.length, 3);
    });

    test('the surviving age row keeps her age, not the cut-point', () {
      final rows = _collapse([
        'Maternal age below 19 years',
        'Maternal age factor (17 years) (low)',
      ]);

      expect(rows.single, 'Maternal age 17 (low)',
          reason: '"17 years" is what a midwife acts on; "below 19" is only '
              'the rule she fell outside of');
    });

    test('order of arrival does not change which row wins', () {
      const withValue = 'Maternal age factor (17 years) (low)';
      const withThreshold = 'Maternal age below 19 years';

      expect(_collapse([withValue, withThreshold]).single, 'Maternal age 17 (low)');
      expect(_collapse([withThreshold, withValue]).single, 'Maternal age 17 (low)');
    });

    test('a threshold-only age row is left alone rather than misread', () {
      // The 19 here is the cut-point. Rewriting this to "Maternal age 19"
      // would put an age on her record that nobody measured.
      expect(_collapse(['Maternal age below 19 years']).single,
          'Maternal age below 19 years');
    });

    test('young and advanced maternal age stay separate findings', () {
      final rows = _collapse([
        'Maternal age factor (17 years) (low)',
        'Maternal age ≥ 35 — closer prenatal monitoring recommended',
      ]);
      expect(rows.length, 2);
    });

    test('distinct findings are never merged', () {
      final rows = _collapse([
        'High blood pressure (>=140/90) (high)',
        'Allergy to Fish',
        'Condition: Asthma',
      ]);
      expect(rows.length, 3);
    });

    test('an exact duplicate of any finding collapses', () {
      final rows = _collapse([
        'Allergy to Fish',
        'Allergy to Fish',
      ]);
      expect(rows, ['Allergy to Fish']);
    });
  });

  group('record findings reach the sheet', () {
    test('the compiled findings are rendered, not just passed in', () {
      final source = _codeOf(_riskCard);

      expect(source, contains('_buildRecordFindingsSection'),
          reason: 'the sheet must render the ultrasound and lab findings');

      // Definition plus at least one call site. One occurrence means the
      // section exists but nothing shows it — the exact shape of the original
      // defect.
      final uses = '_buildRecordFindingsSection'.allMatches(source).length;
      expect(uses, greaterThanOrEqualTo(2),
          reason: 'findings section is defined but never called — the sheet '
              'is dropping its ultrasound and lab evidence again');
    });

    test('every record type still feeds the findings list', () {
      final source = _codeOf(_riskCard);
      for (final source_ in ['ultrasounds', 'lab_tests', 'checkups']) {
        expect(source, contains(source_),
            reason: 'the sheet no longer reads $source_ into its findings');
      }
    });

    test('a sugar test is judged on its numbers, not on prose about it', () {
      final source = _codeOf(_riskCard);

      // The keyword scan cannot see an OGTT: the query loading this pregnancy
      // selects neither `remarks` nor `lab_test_id`, so the text it searches is
      // always empty and the AI lookup has no ids. The glucose columns are
      // selected, so the values must be read directly.
      expect(source, contains('GestationalDiabetesScreening.assess'),
          reason: 'OGTT results must go through the cited screening module');
      for (final column in [
        'fasting_glucose_mg_dl',
        'glucose_1hr_mg_dl',
        'glucose_2hr_mg_dl',
      ]) {
        expect(source, contains(column),
            reason: 'the sheet must read $column to see a sugar test at all');
      }
    });
  });

  group('the sheet reports records without interpreting them', () {
    test('no diagnostic verdict in the wording shown to a user', () {
      final source = _codeOf(_riskCard).toLowerCase();

      for (final banned in [
        'abnormal levels',
        'elevated risk parameters',
        'diagnosis of',
        'diagnosed with',
        'pre-eclampsia',
        'preeclampsia',
        'gestational diabetes',
        'anemia',
        'anaemia',
      ]) {
        expect(source.contains(banned), isFalse,
            reason: '$_riskCard states a clinical verdict ("$banned"). This '
                'card reports what a record says and who recorded it — the '
                'interpretation belongs to the clinician reading it.');
      }
    });

    test('findings point back at the record they came from', () {
      final source = _codeOf(_riskCard);

      // Each row carries its own provenance: the record type and the date it
      // was taken. Without both, the list reads as the app's own conclusions.
      expect(source, contains('factor.type'),
          reason: 'a finding must name the record it came from');
      expect(source, contains('factor.date'),
          reason: 'a finding must carry the date it was recorded');
      expect(source, contains('Marked for review'),
          reason: 'flagged results should say they were flagged, not what '
              'they mean');
    });
  });
}
