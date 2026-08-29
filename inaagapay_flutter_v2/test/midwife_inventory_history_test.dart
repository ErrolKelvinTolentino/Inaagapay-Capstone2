import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife_inventory/inventory_models.dart';

void main() {
  group('Midwife Inventory History & Audit Trail Movement Models', () {
    final sampleTransactions = [
      InventoryTransactionRecord.fromJson({
        'transaction_id': 101,
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
        'performed_by_role': 'midwife',
        'patient_kind': 'child',
        'patient_number': 'NAK-004',
      }),
      InventoryTransactionRecord.fromJson({
        'transaction_id': 102,
        'batch_id': 20,
        'facility_id': 3,
        'transaction_type': 'receipt',
        'quantity': 50,
        'dose_quantity': 500,
        'doses_per_unit': 10,
        'resulting_quantity_remaining': 50,
        'reference_type': 'Stock Replenishment from RHU Main',
        'item_id': 6,
        'item_name': 'Td Vaccine',
        'unit_of_measure': 'vial',
        'batch_number': 'TD-99201',
        'logged_at': '2026-08-25T14:00:00Z',
        'performed_by_name': 'Carlos Mendoza',
        'performed_by_role': 'admin',
      }),
      InventoryTransactionRecord.fromJson({
        'transaction_id': 103,
        'batch_id': 21,
        'facility_id': 3,
        'transaction_type': 'expiry_disposal',
        'quantity': -10,
        'dose_quantity': -100,
        'doses_per_unit': 10,
        'resulting_quantity_remaining': 0,
        'reference_type': 'BHC unusable report - Expired',
        'activity_reason': 'expired',
        'notes': 'Expired in quarantine shelf',
        'item_id': 7,
        'item_name': 'Hepatitis B Vaccine',
        'unit_of_measure': 'vial',
        'batch_number': 'HEP-001',
        'logged_at': '2026-08-24T11:30:00Z',
        'performed_by_name': 'Ana Reyes',
        'performed_by_role': 'midwife',
      }),
      InventoryTransactionRecord.fromJson({
        'transaction_id': 104,
        'batch_id': 12,
        'facility_id': 3,
        'transaction_type': 'discard',
        'quantity': 0,
        'dose_quantity': -7,
        'doses_per_unit': 20,
        'resulting_open_vial_doses': 0,
        'resulting_quantity_remaining': 4,
        'reference_type': 'Open Vial Discard',
        'notes': 'Passed 6h shelf life',
        'item_id': 5,
        'item_name': 'BCG Vaccine',
        'unit_of_measure': 'vial',
        'batch_number': 'BCG-2026A',
        'logged_at': '2026-08-26T16:00:00Z',
        'performed_by_name': 'Ana Reyes',
      }),
      InventoryTransactionRecord.fromJson({
        'transaction_id': 105,
        'batch_id': 30,
        'facility_id': 3,
        'transaction_type': 'transfer',
        'quantity': -5,
        'resulting_quantity_remaining': 15,
        'reference_type': 'Issued to Concepcion BHC — lateral transfer',
        'item_id': 8,
        'item_name': 'Iron + Folic Acid Tablet',
        'unit_of_measure': 'bottle',
        'batch_number': 'IFA-2026B',
        'logged_at': '2026-08-23T10:00:00Z',
        'performed_by_name': 'Ana Reyes',
      }),
      InventoryTransactionRecord.fromJson({
        'transaction_id': 106,
        'batch_id': 30,
        'facility_id': 3,
        'transaction_type': 'adjustment',
        'quantity': 2,
        'resulting_quantity_remaining': 17,
        'reference_type': 'Physical inventory reconciliation',
        'notes': 'Found 2 extra sealed bottles during monthly count',
        'item_id': 8,
        'item_name': 'Iron + Folic Acid Tablet',
        'unit_of_measure': 'bottle',
        'batch_number': 'IFA-2026B',
        'logged_at': '2026-08-22T17:00:00Z',
        'performed_by_name': 'Ana Reyes',
      }),
    ];

    test('correctly counts movements by type', () {
      final dispenses = sampleTransactions
          .where((t) => t.transactionType.toLowerCase() == 'dispense' || t.isAdministration)
          .toList();
      final replenishments = sampleTransactions
          .where(
            (t) =>
                t.transactionType.toLowerCase() == 'receipt' ||
                (t.transactionType.toLowerCase() == 'transfer' &&
                    (t.doseQuantity ?? t.quantity) > 0),
          )
          .toList();
      final unsuables = sampleTransactions
          .where(
            (t) =>
                t.transactionType.toLowerCase() == 'expiry_disposal' ||
                t.transactionType.toLowerCase() == 'discard',
          )
          .toList();
      final transfers = sampleTransactions
          .where((t) => t.transactionType.toLowerCase() == 'transfer')
          .toList();
      final adjustments = sampleTransactions
          .where((t) => t.transactionType.toLowerCase() == 'adjustment')
          .toList();

      expect(sampleTransactions.length, 6);
      expect(dispenses.length, 1);
      expect(replenishments.length, 1);
      expect(unsuables.length, 2);
      expect(transfers.length, 1);
      expect(adjustments.length, 1);
    });

    test('search query matches item name, batch number, patient chart number, and notes', () {
      bool matchesQuery(InventoryTransactionRecord t, String q) {
        final query = q.trim().toLowerCase();
        if (query.isEmpty) return true;
        return t.itemName.toLowerCase().contains(query) ||
            t.batchNumber.toLowerCase().contains(query) ||
            (t.patientNumber ?? '').toLowerCase().contains(query) ||
            (t.performedByName ?? '').toLowerCase().contains(query) ||
            t.referenceType.toLowerCase().contains(query) ||
            t.notes.toLowerCase().contains(query) ||
            t.transactionType.toLowerCase().contains(query);
      }

      // Match item name
      expect(
        sampleTransactions.where((t) => matchesQuery(t, 'bcg')).length,
        2,
      );

      // Match batch number
      expect(
        sampleTransactions.where((t) => matchesQuery(t, 'TD-99201')).length,
        1,
      );

      // Match patient number
      expect(
        sampleTransactions.where((t) => matchesQuery(t, 'NAK-004')).length,
        1,
      );

      // Match performer name
      expect(
        sampleTransactions.where((t) => matchesQuery(t, 'Mendoza')).length,
        1,
      );

      // Match notes
      expect(
        sampleTransactions.where((t) => matchesQuery(t, 'quarantine')).length,
        1,
      );
    });

    test('preserves running balance and dose accounting details across movements', () {
      final administration = sampleTransactions.first;
      expect(administration.resultingQuantityRemaining, 4);
      expect(administration.resultingOpenVialDoses, 7);
      expect(administration.dosesMoved, 1);
      expect(administration.hasPatient, isTrue);
      expect(administration.patientLabel, 'NAK-004');

      final discard = sampleTransactions[3];
      expect(discard.resultingQuantityRemaining, 4);
      expect(discard.resultingOpenVialDoses, 0);
      expect(discard.dosesMoved, 7);
      expect(discard.hasPatient, isFalse);

      final transfer = sampleTransactions[4];
      expect(transfer.quantity, -5);
      expect(transfer.resultingQuantityRemaining, 15);

      final adjustment = sampleTransactions[5];
      expect(adjustment.quantity, 2);
      expect(adjustment.resultingQuantityRemaining, 17);
    });

    test('sorts movements by date, name, and quantity moved', () {
      final list = List<InventoryTransactionRecord>.from(sampleTransactions);

      // Newest first
      list.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
      expect(list.first.transactionId, 104); // 2026-08-26 16:00:00Z
      expect(list.last.transactionId, 106); // 2026-08-22 17:00:00Z

      // Oldest first
      list.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
      expect(list.first.transactionId, 106);
      expect(list.last.transactionId, 104);

      // Name A-Z
      list.sort((a, b) => a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase()));
      expect(list.first.itemName, 'BCG Vaccine');
      expect(list.last.itemName, 'Td Vaccine');

      // Quantity / Doses moved highest first
      list.sort((a, b) => b.dosesMoved.compareTo(a.dosesMoved));
      expect(list.first.dosesMoved, 500); // Td Vaccine receipt (500 doses)
      expect(list.last.dosesMoved, 1); // BCG dose (1 dose)
    });

    test('filters movements within specified date range', () {
      final start = DateTime.utc(2026, 8, 24, 0, 0, 0);
      final end = DateTime.utc(2026, 8, 25, 23, 59, 59);

      final inRange = sampleTransactions.where((t) {
        return !t.loggedAt.isBefore(start) && !t.loggedAt.isAfter(end);
      }).toList();

      // Transaction 102 (Aug 25) and 103 (Aug 24) should be included
      expect(inRange.length, 2);
      expect(inRange.map((t) => t.transactionId), containsAll([102, 103]));
    });
  });
}
