import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/vaccination_drive_service.dart';

DriveRecipient at(int dose, {DateTime? lastDose}) => DriveRecipient(
      motherId: 1,
      accountId: 1,
      name: 'Test Mother',
      currentDose: dose,
      lastDoseOn: lastDose,
    );

void main() {
  final driveDay = DateTime(2026, 8, 20);

  group('the series runs to five doses, not two', () {
    test('a mother with TD2 is still invited — she needs TD3', () {
      // The original rule stopped at TD2 and left most of the caseload
      // uninvited. TD2 protects the newborn; TD3-TD5 extend protection toward
      // lifetime, and a drive is when they get given.
      final mother = at(2, lastDose: DateTime(2025, 1, 1));
      expect(VaccinationDriveService.isDueBy(mother, driveDay), isTrue);
      expect(mother.nextDose, 3);
    });

    test('TD3 and TD4 are still invited', () {
      expect(
        VaccinationDriveService.isDueBy(at(3, lastDose: DateTime(2024, 1, 1)),
            driveDay),
        isTrue,
      );
      expect(
        VaccinationDriveService.isDueBy(at(4, lastDose: DateTime(2024, 1, 1)),
            driveDay),
        isTrue,
      );
    });

    test('a completed series is not invited', () {
      expect(VaccinationDriveService.isDueBy(at(5), driveDay), isFalse);
    });

    test('no dose on record means TD1 is due now', () {
      expect(VaccinationDriveService.isDueBy(at(0), driveDay), isTrue);
      expect(at(0).nextDose, 1);
    });
  });

  group('minimum intervals — a dose given too soon does not count', () {
    test('TD2 needs four weeks after TD1', () {
      final threeWeeks = at(1, lastDose: driveDay.subtract(const Duration(days: 21)));
      final fiveWeeks = at(1, lastDose: driveDay.subtract(const Duration(days: 35)));

      expect(VaccinationDriveService.isDueBy(threeWeeks, driveDay), isFalse);
      expect(VaccinationDriveService.isDueBy(fiveWeeks, driveDay), isTrue);
    });

    test('TD3 needs six months after TD2', () {
      final threeMonths = at(2, lastDose: driveDay.subtract(const Duration(days: 90)));
      final sevenMonths = at(2, lastDose: driveDay.subtract(const Duration(days: 210)));

      expect(VaccinationDriveService.isDueBy(threeMonths, driveDay), isFalse);
      expect(VaccinationDriveService.isDueBy(sevenMonths, driveDay), isTrue);
    });

    test('TD4 and TD5 each need a year', () {
      final sixMonths = at(3, lastDose: driveDay.subtract(const Duration(days: 180)));
      final twoYears = at(3, lastDose: driveDay.subtract(const Duration(days: 730)));

      expect(VaccinationDriveService.isDueBy(sixMonths, driveDay), isFalse);
      expect(VaccinationDriveService.isDueBy(twoYears, driveDay), isTrue);
    });

    test('eligibility follows the drive date, not today', () {
      // Her last dose was recent, so she is not due on the 20th — but a drive
      // held later in the year finds her ready.
      final mother = at(2, lastDose: DateTime(2026, 6, 1));

      expect(VaccinationDriveService.isDueBy(mother, DateTime(2026, 8, 20)),
          isFalse);
      expect(VaccinationDriveService.isDueBy(mother, DateTime(2026, 12, 20)),
          isTrue);
    });

    test('a dose with no date recorded is treated as due', () {
      // An undated record is not evidence that the interval has not elapsed.
      // Surfacing her lets the midwife check the card; hiding her cannot.
      expect(VaccinationDriveService.isDueBy(at(2), driveDay), isTrue);
    });
  });

  group('dose labels say what she needs next', () {
    test('names the next dose, not just the last one', () {
      expect(at(0).doseLabel, contains('needs TD1'));
      expect(at(2).doseLabel, contains('Has TD2'));
      expect(at(2).doseLabel, contains('needs TD3'));
    });
  });

  group('dose numbers are read however they were written', () {
    test('reads the common spellings', () {
      expect(VaccinationDriveService.parseDoseNumber('TD 2'), 2);
      expect(VaccinationDriveService.parseDoseNumber('TD2'), 2);
      expect(VaccinationDriveService.parseDoseNumber('2'), 2);
      expect(VaccinationDriveService.parseDoseNumber('second dose'), 2);
      expect(VaccinationDriveService.parseDoseNumber('Fifth'), 5);
    });

    test('an unreadable dose is null, and callers treat that as none', () {
      expect(VaccinationDriveService.parseDoseNumber('given'), isNull);
      expect(VaccinationDriveService.parseDoseNumber(''), isNull);
      expect(VaccinationDriveService.parseDoseNumber(null), isNull);
    });
  });

  group('an invitation is recorded so she can be reminded tomorrow', () {
    Map<String, dynamic> rowFor(DriveRecipient r) =>
        VaccinationDriveService.invitationRows(
          scheduleId: 77,
          recipients: [r],
        ).single;

    test('a maternal invitation names no child', () {
      final row = rowFor(const DriveRecipient(
        motherId: 5,
        accountId: 9,
        name: 'Ana Cruz',
        currentDose: 1,
        phoneNumber: '09171234567',
      ));

      expect(row['immunization_schedule_id'], 77);
      expect(row['mother_id'], 5);
      expect(row.containsKey('child_id'), isFalse);
      expect(row.containsKey('child_name'), isFalse);
      expect(row['phone_number'], '09171234567');
    });

    test('a child invitation records the child, not only the mother', () {
      // The mother is who gets texted, but the appointment belongs to the
      // child — and a mother with two children due is invited twice.
      final row = rowFor(const DriveRecipient(
        motherId: 5,
        accountId: 9,
        name: 'Ana Cruz',
        currentDose: 0,
        childId: 42,
        childName: 'Baby Cruz',
      ));

      expect(row['child_id'], 42);
      expect(row['child_name'], 'Baby Cruz');
    });

    test('blank contact details are left out, not stored empty', () {
      // Tomorrow's reminder decides who to text by asking whether a number is
      // there. An empty string is there.
      final row = rowFor(const DriveRecipient(
        motherId: 5,
        accountId: 9,
        name: 'Ana Cruz',
        currentDose: 1,
        phoneNumber: '   ',
        email: '',
      ));

      expect(row.containsKey('phone_number'), isFalse);
      expect(row.containsKey('email_address'), isFalse);
    });

    test('an unreachable mother is still recorded as invited', () {
      // "She was due and we could not reach her" is worth knowing, and is
      // invisible today.
      final rows = VaccinationDriveService.invitationRows(
        scheduleId: 77,
        recipients: [
          const DriveRecipient(
            motherId: 5,
            accountId: null,
            name: 'Ana Cruz',
            currentDose: 1,
          ),
        ],
      );

      expect(rows, hasLength(1));
      expect(rows.single['mother_id'], 5);
    });

    test('every recipient gets a row against the same drive', () {
      final rows = VaccinationDriveService.invitationRows(
        scheduleId: 77,
        recipients: [
          const DriveRecipient(
              motherId: 1, accountId: 1, name: 'A', currentDose: 1),
          const DriveRecipient(
              motherId: 2, accountId: 2, name: 'B', currentDose: 2),
        ],
      );

      expect(rows, hasLength(2));
      expect(
        rows.every((r) => r['immunization_schedule_id'] == 77),
        isTrue,
      );
    });
  });

  group('child drives — age is not the only thing that makes a dose due', () {
    // Pentavalent as the catalogue holds it: three doses at 1½, 2½ and 3½
    // months, each needing four weeks since the one before.
    const penta = DriveVaccine(
      name: 'Pentavalent',
      forChildren: true,
      stock: 50,
      doses: [
        DriveDose(vaccineId: 11, doseNumber: 1, recommendedAgeMonths: 1.5),
        DriveDose(
            vaccineId: 12,
            doseNumber: 2,
            recommendedAgeMonths: 2.5,
            minimumIntervalWeeks: 4),
        DriveDose(
            vaccineId: 13,
            doseNumber: 3,
            recommendedAgeMonths: 3.5,
            minimumIntervalWeeks: 4),
      ],
    );

    final driveDay = DateTime(2026, 8, 20);
    // Old enough for all three doses by age alone.
    final bornLongAgo = DateTime(2026, 1, 1);

    DriveDose? due(Map<int, DateTime?> given, {DateTime? on, DateTime? born}) =>
        VaccinationDriveService.dueDoseFor(
          vaccine: penta,
          birthdate: born ?? bornLongAgo,
          given: given,
          driveDate: on ?? driveDay,
        );

    test('a child with no doses is due for the first', () {
      expect(due(const {})?.doseNumber, 1);
    });

    test('a dose given last week does not make the next one due', () {
      // The defect this closes. She is old enough for dose 2 and has not had
      // it, so age alone said "invite her" — but a dose given inside the
      // four-week interval may not count and can need repeating.
      final lastWeek = driveDay.subtract(const Duration(days: 7));
      expect(due({11: lastWeek}), isNull);
    });

    test('the same child is due once the interval has passed', () {
      final fiveWeeksAgo = driveDay.subtract(const Duration(days: 35));
      expect(due({11: fiveWeeksAgo})?.doseNumber, 2);
    });

    test('exactly four weeks is enough', () {
      final fourWeeksAgo = driveDay.subtract(const Duration(days: 28));
      expect(due({11: fourWeeksAgo})?.doseNumber, 2);
    });

    test('the interval is measured to the drive date, not to today', () {
      // A drive three weeks out should invite a child whose interval elapses
      // before it, and this is the whole reason eligibility takes a date.
      final givenOn = DateTime(2026, 8, 18);
      final laterDrive = DateTime(2026, 9, 20);

      expect(due({11: givenOn}), isNull);
      expect(due({11: givenOn}, on: laterDrive)?.doseNumber, 2);
    });

    test('a series in progress moves to the dose actually next', () {
      final old = driveDay.subtract(const Duration(days: 90));
      final alsoOld = driveDay.subtract(const Duration(days: 40));
      expect(due({11: old, 12: alsoOld})?.doseNumber, 3);
    });

    test('a completed series invites nobody', () {
      final old = driveDay.subtract(const Duration(days: 120));
      expect(due({11: old, 12: old, 13: old}), isNull);
    });

    test('a dose with no recorded date still counts as given', () {
      // The record is unreadable, not absent. It cannot hold the next dose
      // back on interval, but it must not be re-offered either.
      expect(due({11: null})?.doseNumber, 2);
    });

    test('too young for the first dose is not invited', () {
      final newborn = driveDay.subtract(const Duration(days: 10));
      expect(due(const {}, born: newborn), isNull);
    });

    test('an unknown birthdate is not invited', () {
      expect(
        VaccinationDriveService.dueDoseFor(
          vaccine: penta,
          birthdate: null,
          given: const {},
          driveDate: driveDay,
        ),
        isNull,
      );
    });

    test('a dose past its age ceiling is skipped, not offered', () {
      // Rotavirus is the one series in the DOH schedule with an upper limit.
      const rota = DriveVaccine(
        name: 'Rotavirus',
        forChildren: true,
        stock: 20,
        doses: [
          DriveDose(
              vaccineId: 21,
              doseNumber: 1,
              recommendedAgeMonths: 1.5,
              maximumAgeMonths: 4),
        ],
      );

      final tooOld = VaccinationDriveService.dueDoseFor(
        vaccine: rota,
        birthdate: DateTime(2025, 1, 1),
        given: const {},
        driveDate: driveDay,
      );
      expect(tooOld, isNull);
    });
  });
}
