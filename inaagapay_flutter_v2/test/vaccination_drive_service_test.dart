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
}
