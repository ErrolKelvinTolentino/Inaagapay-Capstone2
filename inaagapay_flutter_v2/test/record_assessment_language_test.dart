import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/shared/record_detail_screen.dart';

/// The assessment a mother reads is written once, in Tagalog. These guard the
/// one rule that decides which words reach her — including for records saved
/// back when the same column held two languages at once.
void main() {
  group('tagalogAssessmentText', () {
    test('a plain Tagalog summary comes back whole', () {
      const text = 'Buod ng Checkup — Linggo 24 ng AOG\n\n'
          'Ang fetal heart rate (140 bpm) ay nasa karaniwang inaasahang antas.';
      expect(RecordDetailScreen.tagalogAssessmentText(text), text);
    });

    test('an older bilingual record shows the Tagalog half only', () {
      const text = '=== FILIPINO ===\n'
          'Ang blood pressure ay naitala sa 120/80 mmHg.\n\n'
          '=== ENGLISH ===\n'
          'Blood pressure was recorded at 120/80 mmHg.';
      final result = RecordDetailScreen.tagalogAssessmentText(text);
      expect(result, 'Ang blood pressure ay naitala sa 120/80 mmHg.');
      expect(result, isNot(contains('Blood pressure was recorded')));
    });

    test('the growth card\'s "## English / ## Filipino" style splits too', () {
      const text = '## English\n'
          'Your baby is growing steadily.\n\n'
          '## Filipino\n'
          'Maayos ang paglaki ng inyong sanggol.';
      expect(
        RecordDetailScreen.tagalogAssessmentText(text),
        'Maayos ang paglaki ng inyong sanggol.',
      );
    });

    test('English first, Tagalog second still yields the Tagalog', () {
      const text = '=== ENGLISH ===\n'
          'Fetal heart rate is within expected range.\n\n'
          '=== FILIPINO ===\n'
          'Nasa karaniwang antas ang fetal heart rate.';
      expect(
        RecordDetailScreen.tagalogAssessmentText(text),
        'Nasa karaniwang antas ang fetal heart rate.',
      );
    });

    test('an English-only record is still shown rather than blanked', () {
      // Better an English sentence than an empty assessment card: the midwife
      // can rewrite it, but nothing at all reads as a missing record.
      const text = '=== ENGLISH ===\nBlood pressure was recorded at 120/80 mmHg.';
      expect(
        RecordDetailScreen.tagalogAssessmentText(text),
        'Blood pressure was recorded at 120/80 mmHg.',
      );
    });

    test('an empty Tagalog section falls through to the English one', () {
      const text = '=== FILIPINO ===\n\n=== ENGLISH ===\nSteady progress this visit.';
      expect(
        RecordDetailScreen.tagalogAssessmentText(text),
        'Steady progress this visit.',
      );
    });

    test('windows line endings do not defeat the split', () {
      const text = '=== FILIPINO ===\r\nMaayos ang lahat.\r\n\r\n'
          '=== ENGLISH ===\r\nEverything looks fine.';
      expect(RecordDetailScreen.tagalogAssessmentText(text), 'Maayos ang lahat.');
    });
  });
}
