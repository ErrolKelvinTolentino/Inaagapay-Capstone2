import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/baby_book_repository.dart';

/// Two rows on a mother's Prenatal Checkup that read "Not inputted" for
/// reasons that had nothing to do with what her midwife recorded.
///
/// **Symptoms.** `_checkupSymptomSummaries` is built by keying every
/// `pregnancy_symptoms` row on its `encounter_id`. The detail sheet looked the
/// summary up by `prenatal_checkup_id` instead. Where those two ids differ the
/// lookup misses, falls back to `-1`, and reports no symptoms — for a checkup
/// whose symptoms had just been fetched successfully one screen earlier. A map
/// miss returns null rather than complaining, so nothing surfaced.
///
/// **Age of gestation.** There is no age-of-gestation column on a prenatal
/// checkup, so the sheet was asking the row for a key it does not carry. It is
/// derived instead, by the same arithmetic the midwife's checkup form uses.
void main() {
  final recordsScreen = File('lib/screens/mother/records_screen.dart');

  test('symptoms are looked up by the id they were keyed on', () {
    expect(recordsScreen.existsSync(), isTrue);
    final source = recordsScreen.readAsStringSync();

    final summariesBuiltOnEncounterId =
        source.contains("final checkupId = _toInt(symbol['encounter_id']);");
    expect(
      summariesBuiltOnEncounterId,
      isTrue,
      reason: 'the summaries map is keyed on encounter_id; if that changes, '
          'the lookup below has to change with it',
    );

    // The lookup and the map must agree. This is the whole defect: two ids
    // that both read plausibly, one of which silently finds nothing.
    final lookupIndex = source.indexOf('_checkupSymptomSummaries[');
    expect(lookupIndex, isNot(-1));
    final lookup = source.substring(lookupIndex, lookupIndex + 200);
    expect(
      lookup.contains("record['encounter_id']"),
      isTrue,
      reason: 'symptoms are stored against the encounter, so the detail sheet '
          'has to ask for the encounter id',
    );
    expect(
      lookup.contains("record['prenatal_checkup_id']"),
      isFalse,
      reason: 'this key does not match how the summaries were keyed, so every '
          'checkup reported no symptoms',
    );
  });

  test('encounter-level fields are fetched and carried onto the checkup', () {
    final source = recordsScreen.readAsStringSync();

    // Age of gestation and the midwife's notes live on clinical_encounters,
    // not on prenatal_checkups. The sheet read them off the checkup row, where
    // they have never been, so both printed "Not inputted" for every checkup —
    // including the ones where the midwife had written a note.
    for (final column in const <String>[
      'age_of_gestation_weeks',
      'age_of_gestation_days',
      'midwife_notes',
    ]) {
      expect(
        source.contains(column),
        isTrue,
        reason: '$column has to be selected from the encounter, or the row '
            'below it can never show anything',
      );
    }

    expect(
      source.contains("checkupMap['remarks'] = enc['midwife_notes'];"),
      isTrue,
      reason: 'the midwife-side screens make the same handover',
    );
  });

  test('age of gestation prefers what was recorded, then derives', () {
    final source = recordsScreen.readAsStringSync();

    // What the midwife wrote down wins, because they may have corrected it
    // against a scan. Deriving is the fallback for older records saved before
    // the encounter carried a gestational age.
    expect(
      source.contains('String? _recordedGestationalAge('),
      isTrue,
      reason: 'the recorded value is read first',
    );
    expect(
      source.contains('int? _gestationalWeeksAt('),
      isTrue,
      reason: 'and the LMP derivation is the fallback',
    );
    expect(
      source.contains('BabyBookRepository.gestationalWeek('),
      isTrue,
      reason: 'derived through the one implementation of the rule, so the '
          'record and the Baby Book cannot disagree about a week number',
    );
  });

  test('a record shows what was measured, not what was not', () {
    final source = recordsScreen.readAsStringSync();

    // Rows with nothing to report are dropped before the sheet is built, and
    // RecordDetailScreen already drops a section once it has no rows — so an
    // empty "Fetal Assessment" card disappears with its contents rather than
    // announcing that nothing was measured.
    expect(source.contains('_withRecordedValuesOnly('), isTrue);
    expect(
      source.contains('rows: _withRecordedValuesOnly(rows),'),
      isTrue,
      reason: 'every mother-side record sheet goes through this funnel',
    );

    // Filtered here rather than in RecordDetailScreen, which the midwife
    // shares — a blank field is worth seeing in a working document.
    final sharedScreen = File('lib/screens/shared/record_detail_screen.dart');
    expect(
      sharedScreen.readAsStringSync().contains('_withRecordedValuesOnly'),
      isFalse,
      reason: 'the midwife view must keep showing blanks',
    );
  });

  group('the derivation matches the midwife checkup form', () {
    // The form floors whole weeks between LMP and the checkup date. The
    // mother's record has to produce the same number, or she reads one
    // gestational age while her weight-gain evaluation was made against
    // another.
    final lmp = DateTime(2026, 1, 1);

    test('whole weeks, floored — a day short does not round up', () {
      expect(
        BabyBookRepository.gestationalWeek(lmp, asOf: DateTime(2026, 1, 1)),
        0,
      );
      // Thirteen days.
      expect(
        BabyBookRepository.gestationalWeek(lmp, asOf: DateTime(2026, 1, 14)),
        1,
      );
      // Fourteen.
      expect(
        BabyBookRepository.gestationalWeek(lmp, asOf: DateTime(2026, 1, 15)),
        2,
      );
    });

    test('a past checkup reads as it was then, not as it is now', () {
      // The value belongs to the day of the visit. Using "today" would make
      // every historical checkup claim the current gestational age.
      final atTheVisit =
          BabyBookRepository.gestationalWeek(lmp, asOf: DateTime(2026, 5, 21));
      expect(atTheVisit, 20);
      expect(
        BabyBookRepository.gestationalWeek(lmp, asOf: DateTime(2026, 8, 25)),
        greaterThan(atTheVisit),
      );
    });

    test('past term is clamped rather than counted on', () {
      expect(
        BabyBookRepository.gestationalWeek(
          DateTime(2025, 1, 1),
          asOf: DateTime(2026, 1, 1),
        ),
        42,
      );
    });
  });
}
