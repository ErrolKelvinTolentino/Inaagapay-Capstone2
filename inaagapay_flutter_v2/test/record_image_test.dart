import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/widgets/record_image.dart';

void main() {
  group('splitSources — a data URI contains a comma of its own', () {
    test('one embedded image stays one attachment', () {
      // The defect this exists for: splitting on a bare comma turned a single
      // image into "data:image/jpeg;base64" plus an orphaned payload, and the
      // record reported two files, neither of which could load.
      const one = 'data:image/jpeg;base64,AAECAwQFBg==';
      expect(RecordImage.splitSources(one), [one]);
    });

    test('two embedded images split into two', () {
      const a = 'data:image/jpeg;base64,AAEC';
      const b = 'data:image/png;base64,ZZZZ';
      expect(RecordImage.splitSources('$a,$b'), [a, b]);
    });

    test('urls still split, and mix with data uris', () {
      const url = 'https://x.supabase.co/storage/v1/object/public/files/a.jpg';
      const data = 'data:image/jpeg;base64,QUJD';
      expect(RecordImage.splitSources('$url,$data'), [url, data]);
    });

    test('empty and null yield nothing rather than a blank attachment', () {
      expect(RecordImage.splitSources(null), isEmpty);
      expect(RecordImage.splitSources('   '), isEmpty);
    });
  });

  group('reading an attachment', () {
    test('a data uri is recognised as inline', () {
      expect(RecordImage.isInline('data:image/jpeg;base64,AAEC'), isTrue);
      expect(RecordImage.isInline('https://example.com/a.jpg'), isFalse);
    });

    test('pdfs are identified rather than handed to an image decoder', () {
      expect(RecordImage.isPdf('data:application/pdf;base64,AAEC'), isTrue);
      expect(RecordImage.isPdf('https://example.com/result.pdf'), isTrue);
      expect(RecordImage.isPdf('data:image/jpeg;base64,AAEC'), isFalse);
    });

    test('an unreadable payload returns null instead of throwing', () {
      expect(RecordImage.decodeInline('data:image/jpeg;base64,!!!not-base64!!!'),
          isNull);
      expect(RecordImage.decodeInline('no-comma-at-all'), isNull);
    });

    test('a valid payload decodes to its bytes', () {
      final bytes = RecordImage.decodeInline('data:image/jpeg;base64,QUJD');
      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!), 'ABC');
    });
  });
}
