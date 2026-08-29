import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife_inventory/inventory_models.dart';

/// The rows here are the ones Supabase actually returns: the flat shape of
/// `inventory_dose_ledger` (20260830_dose_traceability.sql), and the nested
/// shape the base-table fallback produces on a database that has not run it.
/// If either changes, this is where it should be noticed.
void main() {
  group('inventory_dose_ledger rows', () {
    test('a dose from an already-open vial is one dose, not zero units', () {
      // The row that broke the old activity feed: a dose drawn from a vial that
      // was already open moves no whole unit, so quantity is 0. Reading the unit
      // column alone rendered "0 vial • BCG".
      final row = InventoryTransactionRecord.fromJson({
        'transaction_id': 91,
        'batch_id': 12,
        'facility_id': 3,
        'transaction_type': 'dispense',
        'quantity': 0,
        'dose_quantity': -1,
        'doses_per_unit': 20,
        'resulting_open_vial_doses': 7,
        'resulting_quantity_remaining': 4,
        'reference_type': 'Child Immunization',
        'reference_id': 57,
        'item_id': 5,
        'item_name': 'BCG Vaccine',
        'unit_of_measure': 'vial',
        'batch_number': 'BCG-2026A',
        'logged_at': '2026-08-26T09:14:00Z',
        'performed_by_name': 'Ana Reyes',
        'patient_kind': 'child',
        'patient_number': 'NAK-004',
      });

      expect(row.quantity, 0);
      expect(row.dosesMoved, 1, reason: 'one dose left the vial');
      expect(row.isMultiDose, isTrue);
      expect(row.resultingOpenVialDoses, 7);
      expect(row.isAdministration, isTrue);
      expect(row.hasPatient, isTrue);
      expect(row.patientLabel, 'NAK-004');
      expect(row.performedByName, 'Ana Reyes');
    });

    test('a maternal dose is labelled with the INA number', () {
      final row = InventoryTransactionRecord.fromJson({
        'transaction_id': 92,
        'batch_id': 20,
        'transaction_type': 'dispense',
        'quantity': -1,
        'dose_quantity': -1,
        'doses_per_unit': 10,
        'resulting_open_vial_doses': 9,
        'reference_type': 'Maternal Td Immunization',
        'item_name': 'Td Vaccine',
        'unit_of_measure': 'vial',
        'batch_number': 'TD-99201',
        'logged_at': '2026-08-26T10:02:00Z',
        'patient_kind': 'mother',
        'patient_number': 'INA-012',
      });

      expect(row.patientLabel, 'INA-012');
      expect(row.isAdministration, isTrue);
      expect(row.dosesMoved, 1);
    });

    test('a receipt moves units and has no patient', () {
      final row = InventoryTransactionRecord.fromJson({
        'transaction_id': 93,
        'batch_id': 21,
        'transaction_type': 'receipt',
        'quantity': 5,
        'dose_quantity': 50,
        'doses_per_unit': 10,
        'reference_type': 'Stock Receipt from DOH',
        'item_name': 'Td Vaccine',
        'unit_of_measure': 'vial',
        'batch_number': 'TD-99202',
        'logged_at': '2026-08-20T08:00:00Z',
      });

      expect(row.dosesMoved, 50);
      expect(row.isAdministration, isFalse);
      expect(row.hasPatient, isFalse);
      expect(row.patientLabel, isNull);
    });

    test('a patient with no chart number keeps an id pseudonym', () {
      // The view falls back to 'Child #<id>' / 'Patient #<id>' so a patient
      // registered before a number was assigned still leaves an unbroken
      // trail, instead of the row reading as though nobody received the dose.
      final row = InventoryTransactionRecord.fromJson({
        'transaction_id': 94,
        'batch_id': 12,
        'transaction_type': 'dispense',
        'quantity': 0,
        'dose_quantity': -1,
        'reference_type': 'Child Immunization',
        'patient_kind': 'child',
        'patient_number': 'Child #83',
        'logged_at': '2026-08-26T11:00:00Z',
      });
      expect(row.patientLabel, 'Child #83');
      expect(row.hasPatient, isTrue);
    });

    test('the recipient is never carried as a name', () {
      // Data minimisation, enforced at the model: the ledger identifies a
      // patient by chart number and nothing else. A name arriving on the row —
      // from a stale view, or a hand-built map — must not reach the screen.
      // See inventory_dose_ledger in 20260830_dose_traceability.sql.
      final row = InventoryTransactionRecord.fromJson({
        'transaction_id': 96,
        'batch_id': 12,
        'transaction_type': 'dispense',
        'quantity': 0,
        'dose_quantity': -1,
        'reference_type': 'Child Immunization',
        'patient_kind': 'child',
        'patient_number': 'NAK-009',
        'patient_name': 'Should Not Appear',
        'logged_at': '2026-08-26T11:05:00Z',
      });
      expect(row.patientLabel, 'NAK-009');
      expect(row.patientLabel, isNot(contains('Should Not Appear')));
    });
  });

  group('base-table fallback', () {
    // What the repository reads when inventory_dose_ledger is absent: the
    // nested PostgREST join, with no dose, patient or performer columns at all.
    Map<String, dynamic> legacyRow({
      required int quantity,
      required String referenceType,
    }) =>
        {
          'transaction_id': 40,
          'batch_id': 12,
          'facility_id': 3,
          'transaction_type': 'dispense',
          'quantity': quantity,
          'reference_type': referenceType,
          'reference_id': 57,
          'logged_at': '2026-08-26T09:14:00Z',
          'inventory_batches': {
            'batch_id': 12,
            'item_id': 5,
            'batch_number': 'BCG-2026A',
            'inventory_items': {
              'item_id': 5,
              'name': 'BCG Vaccine',
              'unit_of_measure': 'vial',
            },
          },
        };

    test('nested item and batch are still resolved', () {
      final row = InventoryTransactionRecord.fromJson(
        legacyRow(quantity: -1, referenceType: 'Child Immunization'),
      );
      expect(row.itemId, 5);
      expect(row.itemName, 'BCG Vaccine');
      expect(row.batchNumber, 'BCG-2026A');
      expect(row.unit, 'vial');
    });

    test('the missing half reads as absent, never as zero or empty', () {
      final row = InventoryTransactionRecord.fromJson(
        legacyRow(quantity: -1, referenceType: 'Child Immunization'),
      );
      expect(row.doseQuantity, isNull);
      expect(row.resultingOpenVialDoses, isNull,
          reason: 'an un-migrated database cannot answer this');
      expect(row.performedByName, isNull);
      expect(row.patientLabel, isNull);
      expect(row.hasPatient, isFalse);
    });

    test('an administration still counts as one dose without dose_quantity', () {
      // quantity is 0 on the commonest row of all. Falling back to units would
      // report the dose as nothing having moved.
      final fromOpenVial = InventoryTransactionRecord.fromJson(
        legacyRow(quantity: 0, referenceType: 'Child Immunization'),
      );
      expect(fromOpenVial.dosesMoved, 1);

      final brokeSeal = InventoryTransactionRecord.fromJson(
        legacyRow(quantity: -1, referenceType: 'Child Immunization'),
      );
      expect(brokeSeal.dosesMoved, 1);
    });

    test('a non-administration falls back to units x doses per unit', () {
      final row = InventoryTransactionRecord.fromJson(
        legacyRow(quantity: 3, referenceType: 'Stock Receipt'),
      );
      expect(row.isAdministration, isFalse);
      // The catalogue record supplies doses_per_unit when the row cannot.
      final withCatalogue = InventoryTransactionRecord.fromJson(
        legacyRow(quantity: 3, referenceType: 'Stock Receipt'),
        item: const InventoryCatalogRecord(
          itemId: 5,
          name: 'BCG Vaccine',
          genericName: 'BCG',
          itemCode: 'BCG',
          strengthDescription: '',
          dosageForm: 'vial',
          itemType: 'vaccine',
          unit: 'vial',
          minimumStock: 10,
          dosesPerUnit: 20,
        ),
      );
      expect(row.dosesMoved, 3, reason: 'single-dose until told otherwise');
      expect(withCatalogue.dosesMoved, 60);
    });
  });

  _openVialClockTests();
}

/// The open-vial shelf-life clock.
///
/// `vial_opened_at` used to be parsed with `_asDate`, which truncates to
/// midnight. The clock is measured in hours, so a vial opened at 2pm read as
/// fourteen hours old immediately and every same-day BCG vial showed EXPIRED
/// against its 6h limit — the app telling midwives to throw away good vaccine.
void _openVialClockTests() {
  group('open-vial clock', () {
    InventoryBatchRecord batchOpenedAt(String openedAt, {int doses = 7}) =>
        InventoryBatchRecord.fromJson({
          'batch_id': 12,
          'item_id': 5,
          'batch_number': 'BCG-2026A',
          'quantity_received': 10,
          'quantity_remaining': 4,
          'expiration_date': '2027-01-01',
          'status': 'active',
          'doses_remaining_in_open_vial': doses,
          'open_vials_count': 1,
          'vial_opened_at': openedAt,
        });

    test('the time of day survives parsing', () {
      final b = batchOpenedAt('2026-08-26T14:00:00Z');
      expect(b.vialOpenedAt, isNotNull);
      expect(b.vialOpenedAt!.toUtc().hour, 14,
          reason: 'truncating to midnight is what caused the false expiries');
    });

    test('a vial opened two hours ago has four hours left, not none', () {
      final opened = DateTime.now().toUtc().subtract(const Duration(hours: 2));
      final b = batchOpenedAt(opened.toIso8601String());
      expect(b.isExpiredOpenVial(6), isFalse);
      final left = b.openVialTimeLeft(6)!;
      expect(left.inMinutes, closeTo(240, 2));
    });

    test('forty minutes left is not expired', () {
      // The case whole-hour arithmetic got wrong: inHours floors 0h40m to 0.
      final opened = DateTime.now().toUtc().subtract(const Duration(hours: 5, minutes: 20));
      final b = batchOpenedAt(opened.toIso8601String());
      expect(b.isExpiredOpenVial(6), isFalse);
      expect(b.openVialTimeLeft(6)!.inMinutes, closeTo(40, 2));
    });

    test('past the limit it is expired and reports how far past', () {
      final opened = DateTime.now().toUtc().subtract(const Duration(hours: 7));
      final b = batchOpenedAt(opened.toIso8601String());
      expect(b.isExpiredOpenVial(6), isTrue);
      expect(b.openVialTimeLeft(6)!.isNegative, isTrue);
      expect((-b.openVialTimeLeft(6)!).inMinutes, closeTo(60, 2));
    });

    test('a 28-day OPV vial is not judged against six hours', () {
      final now = DateTime.now().toUtc();
      final opened = now.subtract(const Duration(days: 3));
      final b = batchOpenedAt(opened.toIso8601String());
      expect(b.isExpiredOpenVial(672, now), isFalse);
      expect(b.openVialTimeLeft(672, now)!.inDays, 25);
    });

    test('nothing open means no clock at all', () {
      final b = batchOpenedAt(DateTime.now().toUtc().toIso8601String(), doses: 0);
      expect(b.openVialTimeLeft(6), isNull);
      expect(b.openVialExpiresAt(6), isNull);
      expect(b.isExpiredOpenVial(6), isFalse);
    });

    test('an item with no shelf-life policy has no clock', () {
      final b = batchOpenedAt(DateTime.now().toUtc().toIso8601String());
      expect(b.openVialTimeLeft(0), isNull);
      expect(b.isExpiredOpenVial(0), isFalse,
          reason: 'a 0h policy means unpolicied, not instantly expired');
    });
  });
}
