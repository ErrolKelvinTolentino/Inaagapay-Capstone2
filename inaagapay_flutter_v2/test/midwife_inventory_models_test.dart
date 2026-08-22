import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife_inventory/inventory_models.dart';

void main() {
  const catalog = InventoryCatalogRecord(
    itemId: 7,
    name: 'Iron + Folic Acid Tablet',
    genericName: 'Ferrous Sulfate + Folic Acid',
    itemCode: 'SUP-IFA-TAB',
    strengthDescription: '60 mg + 400 mcg',
    dosageForm: 'Tablet',
    itemType: 'supplement',
    unit: 'tablets',
    minimumStock: 100,
  );

  InventoryBatchRecord batch({
    required int id,
    required int quantity,
    required String expiration,
    String status = 'active',
  }) {
    return InventoryBatchRecord.fromJson({
      'batch_id': id,
      'item_id': catalog.itemId,
      'facility_id': 3,
      'batch_number': 'IFA-$id',
      'quantity_received': quantity,
      'quantity_remaining': quantity,
      'received_date': '2026-01-01',
      'expiration_date': expiration,
      'status': status,
    });
  }

  group('BHC usable stock', () {
    final today = DateTime(2026, 8, 11);

    test('excludes batches expiring today and past dates', () {
      final stock = FacilityInventoryRecord(
        catalog: catalog,
        batches: [
          batch(id: 1, quantity: 10, expiration: '2026-08-10'),
          batch(id: 2, quantity: 20, expiration: '2026-08-11'),
          batch(id: 3, quantity: 30, expiration: '2026-08-12'),
        ],
      );

      expect(stock.quantityOn(today), 30);
      expect(stock.expiredQuantityOn(today), 30);
    });

    test('uses earliest-expiring usable batch first (FEFO)', () {
      final stock = FacilityInventoryRecord(
        catalog: catalog,
        batches: [
          batch(id: 10, quantity: 50, expiration: '2027-04-01'),
          batch(id: 11, quantity: 25, expiration: '2026-10-01'),
          batch(id: 12, quantity: 15, expiration: '2026-08-11'),
        ],
      );

      final usable = stock.usableBatchesOn(today);
      expect(usable.map((value) => value.batchId), [11, 10]);
    });

    test('counts only usable stock inside the 90-day expiry window', () {
      final stock = FacilityInventoryRecord(
        catalog: catalog,
        batches: [
          batch(id: 20, quantity: 25, expiration: '2026-08-21'),
          batch(id: 21, quantity: 40, expiration: '2026-11-20'),
          batch(id: 22, quantity: 5, expiration: '2026-08-10'),
        ],
      );

      expect(stock.expiringQuantityOn(90, today), 25);
    });

    test('treats a legacy null batch status as unusable', () {
      final legacyBatch = InventoryBatchRecord.fromJson({
        'batch_id': 30,
        'item_id': catalog.itemId,
        'facility_id': 3,
        'batch_number': 'IFA-30',
        'quantity_received': 50,
        'quantity_remaining': 50,
        'received_date': '2026-01-01',
        'expiration_date': '2027-01-01',
        'status': null,
      });
      final stock = FacilityInventoryRecord(
        catalog: catalog,
        batches: [legacyBatch],
      );

      expect(legacyBatch.status, 'unknown');
      expect(stock.quantityOn(today), 0);
    });

    test('correctly evaluates open vial expiry after 6 hours', () {
      final openedAt = DateTime.now().subtract(const Duration(hours: 7));
      final batch = InventoryBatchRecord(
        batchId: 99,
        itemId: 1,
        facilityId: 3,
        batchNumber: 'BCG-OPEN',
        quantityReceived: 10,
        quantityRemaining: 5,
        receivedDate: DateTime.now(),
        expirationDate: DateTime.now().add(const Duration(days: 100)),
        manufacturer: 'DOH',
        status: 'active',
        dosesRemainingInOpenVial: 14,
        openVialsCount: 1,
        vialOpenedAt: openedAt,
      );

      expect(batch.isOpenVialExpired(DateTime.now(), 6), isTrue);
      expect(batch.isOpenVialExpired(DateTime.now(), 24), isFalse);
    });

    test('calculates total available doses combining sealed units and open vials', () {
      const vaccineCatalog = InventoryCatalogRecord(
        itemId: 1,
        name: 'BCG Vaccine',
        genericName: 'BCG',
        itemCode: 'VAC-BCG',
        strengthDescription: '0.05mL',
        dosageForm: 'Vial',
        itemType: 'vaccine',
        unit: 'vials',
        minimumStock: 10,
        dosesPerUnit: 20,
      );

      final stock = FacilityInventoryRecord(
        catalog: vaccineCatalog,
        batches: [
          InventoryBatchRecord(
            batchId: 101,
            itemId: 1,
            facilityId: 3,
            batchNumber: 'BCG-101',
            quantityReceived: 5,
            quantityRemaining: 3, // 3 sealed vials * 20 doses = 60 doses
            receivedDate: DateTime.now(),
            expirationDate: DateTime.now().add(const Duration(days: 200)),
            manufacturer: 'DOH',
            status: 'active',
            dosesRemainingInOpenVial: 12, // 12 doses left in open vial
            openVialsCount: 1,
          ),
        ],
      );

      expect(stock.availableDosesOn(), 72); // 60 + 12 = 72 available doses
    });
  });

  // The titles below are written by the distribution RPCs in SQL. Classification
  // used to be exact string equality against them, so rewording one in a
  // migration dropped the notification out of the midwife's inventory feed with
  // no error anywhere — invisible to the analyzer and to every other test.
  group('inventory notifications survive a reworded title', () {
    InventoryNotificationRecord? parse(String title, String message) {
      return InventoryNotificationRecord.tryFromJson({
        'notification_id': 1,
        'account_id': 9,
        'title': title,
        'message': message,
        'is_read': false,
        'created_at': '2026-08-24T09:00:00Z',
      });
    }

    test('an approval is recognised', () {
      final record = parse(
        'Stock request approved',
        'Your stock request #12 was approved by RHU Main.',
      );
      expect(record?.kind, InventoryNotificationKind.approved);
    });

    test('a rejection is told apart from an approval by its message', () {
      final record = parse(
        'Stock request update',
        'Your stock request #12 was not approved. Out of stock at the depot.',
      );
      expect(record?.kind, InventoryNotificationKind.rejected);
    });

    test('the original issue title is still recognised', () {
      final record = parse(
        'Incoming stocks from RHU Main',
        '40 units of BCG Vaccine are waiting for your receipt confirmation.',
      );
      expect(record?.kind, InventoryNotificationKind.issued);
    });

    test('the tier-neutral issue title is recognised too', () {
      final record = parse(
        'Incoming stocks',
        '40 units of BCG Vaccine from Baliwag RHU III are waiting for your '
        'receipt confirmation.',
      );
      expect(record?.kind, InventoryNotificationKind.issued);
    });

    test('a low-stock warning is recognised', () {
      final record = parse(
        'Low stock after activity',
        'BCG Vaccine is now below its reorder level.',
      );
      expect(record?.kind, InventoryNotificationKind.lowStock);
    });

    test('the admin-facing new-request alert stays out of the midwife feed', () {
      final record = parse(
        'New stock request',
        'Pinagbarilan BHC requested 40 units of BCG Vaccine.',
      );
      expect(record, isNull);
    });

    test('an unrelated notification is not swept in', () {
      final record = parse(
        'Checkup reminder',
        'Maria has a prenatal checkup tomorrow.',
      );
      expect(record, isNull);
    });
  });
}
