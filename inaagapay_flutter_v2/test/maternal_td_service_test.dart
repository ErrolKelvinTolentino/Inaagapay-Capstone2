import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/maternal_td_service.dart';

/// Builds a status from `{doseKey: daysAgo}`.
MaternalTdStatus statusOf(Map<String, int?> given) {
  final today = DateTime.now();
  return MaternalTdStatus(
    doses: {
      for (final e in given.entries)
        e.key: MaternalTdRecord(
          doseKey: e.key,
          date: e.value == null
              ? null
              : DateTime(today.year, today.month, today.day)
                  .subtract(Duration(days: e.value!)),
          source: 'bhc',
        ),
    },
  );
}

void main() {
  group('normalizeDoseKey', () {
    test('collapses every spelling the database has held', () {
      // The legacy prenatal column used 'TD 2'; maternal_td_records uses 'Td2'.
      // Both must land on the same key or the two screens disagree.
      for (final raw in ['Td2', 'TD 2', 'td-2', 'TD2', '2', 'Dose 2', ' td 2 ']) {
        expect(MaternalTdService.normalizeDoseKey(raw), 'Td2',
            reason: 'failed for "$raw"');
      }
    });

    test('rejects empty and out-of-range values', () {
      for (final raw in [null, '', '-', 'none', 'None', 'Td0', 'Td6', 'abc']) {
        expect(MaternalTdService.normalizeDoseKey(raw), isNull,
            reason: 'failed for "$raw"');
      }
    });
  });

  group('completion and protection', () {
    test('no doses means unprotected, Td1 is next', () {
      final s = statusOf({});
      expect(s.highestCompletedDose, 0);
      expect(s.isProtectedAtBirth, isFalse);
      expect(s.nextDoseKey, 'Td1');
      expect(s.nextAction, TdNextAction.eligibleNow);
    });

    test('Td1 alone does not confer PAB', () {
      final s = statusOf({'Td1': 40});
      expect(s.highestCompletedDose, 1);
      expect(s.isProtectedAtBirth, isFalse);
    });

    test('Td2 completes the series', () {
      final s = statusOf({'Td1': 60, 'Td2': 19});
      expect(s.highestCompletedDose, 2);
      expect(s.isProtectedAtBirth, isTrue);
      expect(s.isFim, isTrue);
    });

    test('Td2 is complete and needs nothing further', () {
      final s = statusOf({
        'Td1': 200, 'Td2': 100,
      });
      expect(s.isFim, isTrue);
      expect(s.nextDoseKey, isNull);
      expect(s.nextAction, TdNextAction.complete);
      expect(s.canAdministerToday, isFalse);
    });
  });

  group('eligibility', () {
    test('Td1 given 10 days ago blocks Td2 until 28 days', () {
      final s = statusOf({'Td1': 10});

      expect(s.nextDoseKey, 'Td2');
      expect(s.nextAction, TdNextAction.waiting);
      expect(s.canAdministerToday, isFalse,
          reason: 'the form must not be offered - interval not met');
      // Td2 requires 28 days after Td1; 10 elapsed leaves 18.
      expect(s.daysUntilEligible, 18);
    });

    test('becomes eligible exactly on the interval boundary', () {
      expect(statusOf({'Td1': 28}).canAdministerToday, isTrue);
      expect(statusOf({'Td1': 27}).canAdministerToday, isFalse);
    });

    test('Td2 opens 28 days after Td1', () {
      expect(statusOf({'Td1': 27}).daysUntilEligible, 1);
      expect(statusOf({'Td1': 28}).canAdministerToday, isTrue);
    });

    test('a dateless registration-reported dose cannot anchor an interval', () {
      final s = statusOf({'Td1': null});
      expect(s.nextDoseKey, 'Td2');
      expect(s.nextAction, TdNextAction.missingPrevious);
      expect(s.canAdministerToday, isFalse);
    });

    test('nextEligibleDate is the previous dose plus the DOH interval', () {
      final s = statusOf({'Td1': 10});
      final td1 = s.recordFor('Td1')!.date!;
      expect(s.nextDoseKey, 'Td2');
      expect(s.nextEligibleDate, td1.add(const Duration(days: 28)));
    });
  });

  group('selectableDoseKeys', () {
    test('offers only the due dose, and nothing while waiting', () {
      expect(statusOf({'Td1': 30}).selectableDoseKeys, ['Td2']);
      expect(statusOf({'Td1': 10}).selectableDoseKeys, isEmpty);
      expect(
        statusOf({
          'Td1': 200, 'Td2': 100,
        }).selectableDoseKeys,
        isEmpty,
      );
    });
  });
}
