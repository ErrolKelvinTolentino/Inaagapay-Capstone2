// A prenatal checkup recorded at 1:52 PM showed in the mother's notifications
// as 5:52 AM. notifications.created_at is `timestamp without time zone` filled
// by the database clock, which is UTC; parsed as-is, Dart took it for local
// time and the list ran eight hours behind in Manila.

import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/db_timestamp.dart';

void main() {
  group('parseDbTimestamp', () {
    test('a zone-less value is read as UTC', () {
      final parsed = parseDbTimestamp('2026-09-28T05:52:10.123456');
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isFalse, reason: 'returned in local time');
      expect(parsed.toUtc(), DateTime.utc(2026, 9, 28, 5, 52, 10, 123, 456));
    });

    test('a value with Z or an offset is converted as given', () {
      expect(parseDbTimestamp('2026-09-28T05:52:10Z')!.toUtc(),
          DateTime.utc(2026, 9, 28, 5, 52, 10));
      expect(parseDbTimestamp('2026-09-28T13:52:10+08:00')!.toUtc(),
          DateTime.utc(2026, 9, 28, 5, 52, 10));
    });

    test('the space-separated form Postgres prints is accepted too', () {
      expect(parseDbTimestamp('2026-09-28 05:52:10')!.toUtc(),
          DateTime.utc(2026, 9, 28, 5, 52, 10));
    });

    test('nothing to parse gives null', () {
      expect(parseDbTimestamp(null), isNull);
      expect(parseDbTimestamp(''), isNull);
      expect(parseDbTimestamp('not a date'), isNull);
    });
  });
}
