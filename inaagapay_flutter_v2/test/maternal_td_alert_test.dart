// What a mother is told about her Td series, on Home and in her bell.
//
// These rules decide whether a clinical notice appears at all, so they are
// pinned here: a missing notice is a missed dose, and a wrong one tells a
// protected mother her baby is at risk.

import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/maternal_td_alert.dart';
import 'package:inaagapay_flutter_v2/services/maternal_td_service.dart';

/// Builds a status from `{doseKey: daysAgo}`.
MaternalTdStatus statusOf(Map<String, int> given, {bool readFailed = false}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return MaternalTdStatus(
    readFailed: readFailed,
    doses: {
      for (final e in given.entries)
        e.key: MaternalTdRecord(
          doseKey: e.key,
          date: today.subtract(Duration(days: e.value)),
          source: 'bhc',
        ),
    },
  );
}

void main() {
  group('nothing to say', () {
    test('a failed read is silence, never "unprotected"', () {
      final alert = MaternalTdAlert.evaluate(statusOf({}, readFailed: true),
          isPregnant: true, week: 36);
      expect(alert, isNull);
    });

    test('a fully immunized mother gets no notice', () {
      final s = statusOf(
          {'Td1': 2000, 'Td2': 1900, 'Td3': 1500, 'Td4': 1000, 'Td5': 400});
      expect(MaternalTdAlert.evaluate(s, isPregnant: true, week: 30), isNull);
    });

    test('Td1 is not pressed on a mother who is not pregnant', () {
      expect(MaternalTdAlert.evaluate(statusOf({}), isPregnant: false),
          isNull);
    });

    test('a dose weeks away is not announced yet', () {
      // Td3 opens 180 days after Td2; 100 days in leaves 80 to go.
      final s = statusOf({'Td1': 200, 'Td2': 100});
      expect(MaternalTdAlert.evaluate(s, isPregnant: true, week: 20), isNull);
    });

    test('a record with a dateless earlier dose is the midwife\'s to fix', () {
      final s = MaternalTdStatus(doses: {
        'Td1': const MaternalTdRecord(doseKey: 'Td1', date: null, source: 'bhc'),
      });
      expect(s.nextAction, TdNextAction.missingPrevious);
      expect(MaternalTdAlert.evaluate(s, isPregnant: true, week: 30), isNull);
    });
  });

  group('due', () {
    test('Td1 is due early in pregnancy', () {
      final alert =
          MaternalTdAlert.evaluate(statusOf({}), isPregnant: true, week: 12)!;
      expect(alert.level, TdAlertLevel.due);
      expect(alert.doseKey, 'Td1');
      expect(alert.doseLabel, 'Td 1');
    });

    test('Td2 is due once 28 days have passed since Td1', () {
      final alert = MaternalTdAlert.evaluate(statusOf({'Td1': 30}),
          isPregnant: true, week: 20)!;
      expect(alert.level, TdAlertLevel.due);
      expect(alert.doseKey, 'Td2');
    });

    test('a due dose between pregnancies is still due', () {
      final alert = MaternalTdAlert.evaluate(
          statusOf({'Td1': 400, 'Td2': 370}),
          isPregnant: false)!;
      expect(alert.level, TdAlertLevel.due);
      expect(alert.doseKey, 'Td3');
    });
  });

  group('urgent', () {
    test('third trimester without protection at birth', () {
      final alert = MaternalTdAlert.evaluate(statusOf({'Td1': 40}),
          isPregnant: true, week: MaternalTdAlert.urgentFromWeek)!;
      expect(alert.level, TdAlertLevel.urgent);
      expect(alert.doseKey, 'Td2');
    });

    test('not before the third trimester', () {
      final alert = MaternalTdAlert.evaluate(statusOf({'Td1': 40}),
          isPregnant: true, week: MaternalTdAlert.urgentFromWeek - 1)!;
      expect(alert.level, TdAlertLevel.due);
    });

    test('not when her baby is already protected at birth', () {
      // Td3 due, but Td2 already protects this baby.
      final alert = MaternalTdAlert.evaluate(
          statusOf({'Td1': 400, 'Td2': 370}),
          isPregnant: true, week: 34)!;
      expect(alert.level, TdAlertLevel.due);
    });
  });

  group('soon', () {
    test('within two weeks of the next dose opening', () {
      // Td2 opens on day 28; day 20 leaves 8 days.
      final alert = MaternalTdAlert.evaluate(statusOf({'Td1': 20}),
          isPregnant: true, week: 16)!;
      expect(alert.level, TdAlertLevel.soon);
      expect(alert.doseKey, 'Td2');
      expect(alert.opensOn, isNotNull);
    });
  });

  group('read state', () {
    test('is kept per dose and per level', () {
      final dueTd2 = MaternalTdAlert.evaluate(statusOf({'Td1': 30}),
          isPregnant: true, week: 20)!;
      final urgentTd2 = MaternalTdAlert.evaluate(statusOf({'Td1': 30}),
          isPregnant: true, week: 32)!;
      final dueTd3 = MaternalTdAlert.evaluate(
          statusOf({'Td1': 400, 'Td2': 370}),
          isPregnant: true, week: 20)!;

      expect(dueTd2.noticeType, 'td_due_Td2');
      // Escalating reaches her again; the next dose is a new notice.
      expect(urgentTd2.noticeType, isNot(dueTd2.noticeType));
      expect(dueTd3.noticeType, isNot(dueTd2.noticeType));
      // The notifications screen recognises its own by this prefix.
      for (final a in [dueTd2, urgentTd2, dueTd3]) {
        expect(a.noticeType.startsWith('td_'), isTrue);
      }
    });
  });

  group('weekFromLmp', () {
    test('counts like Home does, and is 0 without an LMP', () {
      expect(MaternalTdAlert.weekFromLmp(null), 0);
      final lmp = DateTime.now().subtract(const Duration(days: 7 * 20 + 3));
      expect(MaternalTdAlert.weekFromLmp(lmp), 20);
    });
  });
}
