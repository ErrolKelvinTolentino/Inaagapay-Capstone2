import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/fetal_heart_rate_reference.dart';

void main() {
  group('categorise — the baseline range', () {
    test('both ends are inclusive', () {
      // The five sites this replaced used 120–160, so 110 through 119 — normal
      // baseline rates — were reported as findings on the mother's record.
      expect(FetalHeartRateReference.categorise(110), FhrCategory.withinRange);
      expect(FetalHeartRateReference.categorise(160), FhrCategory.withinRange);
    });

    test('110 to 119 is within range, not below it', () {
      for (final rate in [110, 112, 115, 119]) {
        expect(FetalHeartRateReference.categorise(rate),
            FhrCategory.withinRange,
            reason: '$rate bpm is a normal baseline');
      }
    });

    test('outside the range is named by which side', () {
      expect(FetalHeartRateReference.categorise(109), FhrCategory.belowRange);
      expect(FetalHeartRateReference.categorise(161), FhrCategory.aboveRange);
    });

    test('missing or implausible values are unreadable', () {
      expect(FetalHeartRateReference.categorise(null), FhrCategory.unreadable);
      expect(FetalHeartRateReference.categorise(0), FhrCategory.unreadable);
      expect(FetalHeartRateReference.categorise(-5), FhrCategory.unreadable);
      expect(FetalHeartRateReference.categorise(251), FhrCategory.unreadable);
      // The bound matches the one the checkup form validates against, so a
      // value the form accepts is never called unreadable here.
      expect(FetalHeartRateReference.categorise(250), FhrCategory.aboveRange);
    });

    test('the range is overridable without touching the rules', () {
      const older = FhrThresholds(baselineMin: 120);
      expect(FetalHeartRateReference.categorise(115, thresholds: older),
          FhrCategory.belowRange);
      expect(FetalHeartRateReference.categorise(115), FhrCategory.withinRange);
    });
  });

  group('assess — finding, action and context', () {
    test('a rate in range needs no action', () {
      final result = FetalHeartRateReference.assess(140);
      expect(result.category, FhrCategory.withinRange);
      expect(result.action, FhrAction.none);
      expect(result.isOutsideBaseline, isFalse);
      expect(result.finding, contains('140 bpm'));
      expect(result.finding, contains('110–160'));
    });

    test('a rate outside the range is repeated before it is acted on', () {
      for (final rate in [104, 172]) {
        final result = FetalHeartRateReference.assess(rate);
        expect(result.action, FhrAction.repeatAndRefer);
        expect(result.isOutsideBaseline, isTrue);
      }
    });

    test('a low rate warns that it may be the mother\'s pulse', () {
      final result = FetalHeartRateReference.assess(96);
      expect(result.note, isNotNull);
      expect(result.note!.toLowerCase(), contains('pulse'));
    });

    test('nothing heard early is explained, not reported as missing data', () {
      final result =
          FetalHeartRateReference.assess(null, gestationalWeeks: 9);
      expect(result.category, FhrCategory.unreadable);
      expect(result.action, FhrAction.none);
      expect(result.note, isNotNull);
      expect(result.note!.toLowerCase(), contains('doppler'));
    });

    test('nothing heard later carries no Doppler excuse', () {
      final result =
          FetalHeartRateReference.assess(null, gestationalWeeks: 28);
      expect(result.note, isNull);
    });

    test('gestation changes the note but never the classification', () {
      for (final weeks in [8.0, 20.0, 39.0]) {
        expect(
          FetalHeartRateReference.assess(105, gestationalWeeks: weeks).category,
          FhrCategory.belowRange,
        );
      }
    });

    test('an unreadable reading reports no rate rather than a stray number',
        () {
      expect(FetalHeartRateReference.assess(300).rate, isNull);
    });
  });

  group('vocabulary stays non-diagnostic', () {
    test('no action or category names a condition', () {
      final words = [
        ...FhrAction.values.map((a) => a.label.toLowerCase()),
        ...FhrCategory.values.map((c) => c.label.toLowerCase()),
      ];

      for (final word in words) {
        for (final banned in [
          'bradycard',
          'tachycard',
          'distress',
          'hypoxia',
          'abnormal',
          'diagnos',
        ]) {
          expect(word.contains(banned), isFalse,
              reason: '"$word" names a condition; the app must not diagnose');
        }
      }
    });

    test('findings describe the rate and the range, not a condition', () {
      for (final rate in [96, 140, 180]) {
        final finding =
            FetalHeartRateReference.assess(rate).finding.toLowerCase();
        for (final banned in ['bradycard', 'tachycard', 'distress', 'abnormal']) {
          expect(finding.contains(banned), isFalse);
        }
      }
    });
  });

  group('no screen or engine keeps a range of its own', () {
    // The same guard the blood pressure rules carry. Six sites held two
    // different ranges before this module; this fails if a seventh appears.
    //
    // Comments are stripped before the scan, so the files may still describe
    // what was removed.
    const sources = [
      'lib/screens/midwife/add_prenatal_checkup_screen.dart',
      'lib/screens/mother/mother_profile_page.dart',
      'lib/services/risk_engine.dart',
    ];

    String codeOf(String path) {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path not found — run tests from the package root');
      return file.readAsLinesSync().map((line) {
        final comment = line.indexOf('//');
        return comment == -1 ? line : line.substring(0, comment);
      }).join('\n');
    }

    test('no file compares a rate against a literal bound', () {
      // Deliberately not keyed to a variable name. The copy that prompted this
      // guard was `v >= 110 && v <= 160`, inside a colour callback under the
      // input field — a name-based pattern walked straight past it, and the
      // field went on quoting its own range regardless of the rule.
      // Matches a *range* check — a lower bound and 160 within a short span —
      // rather than any lone comparison. A fetal heart range always states
      // both ends. The earlier pattern also flagged "years < 120" in an age
      // sanity check in another file, and a guard that cries wolf is a guard
      // somebody deletes.
      final comparison =
          RegExp(r'[<>]=?\s*(110|120)\b[\s\S]{0,80}?[<>]=?\s*160\b');
      for (final path in sources) {
        final match = comparison.firstMatch(codeOf(path));
        expect(match, isNull,
            reason: '$path compares against a literal bound '
                '("${match?.group(0)}"). The range belongs to '
                'FetalHeartRateReference');
      }
    });

    test('no file spells the range out in its own text', () {
      // A hint reading "Normal range: 110 – 160 bpm" is a second copy of the
      // rule wearing a label. Build the text from FhrThresholds so the number
      // shown and the number applied cannot part ways.
      final spelledOut = RegExp(r'(110|120)\s*[–-]\s*160');
      for (final path in sources) {
        final match = spelledOut.firstMatch(codeOf(path));
        expect(match, isNull,
            reason: '$path prints the range as literal text '
                '("${match?.group(0)}") instead of building it from '
                'FhrThresholds');
      }
    });

    test('every file that judges a rate reads the shared range', () {
      for (final path in sources) {
        expect(codeOf(path), contains('FetalHeartRateReference'),
            reason: '$path judges a fetal heart rate without the cited range');
      }
    });
  });
}
