import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife_inventory/inventory_models.dart';
import 'package:inaagapay_flutter_v2/screens/midwife_inventory/midwife_inventory_page.dart';

void main() {
  final now = DateTime(2026, 10, 8, 6);

  InventoryBatchRecord batch({
    int id = 1,
    int sealed = 10,
    int doses = 7,
    DateTime? openedAt,
    DateTime? expiration,
    String status = 'active',
  }) => InventoryBatchRecord(
    batchId: id, itemId: 1, facilityId: 3, batchNumber: 'BATCH-$id',
    quantityReceived: 10, quantityRemaining: sealed,
    receivedDate: DateTime(2026, 1, 1),
    expirationDate: expiration ?? DateTime(2037, 1, 1),
    manufacturer: 'DOH', status: status,
    dosesRemainingInOpenVial: doses, openVialsCount: doses > 0 ? 1 : 0,
    vialOpenedAt: openedAt,
  );

  InventoryItem item(List<InventoryBatchRecord> batches, {
    int hours = 672,
    int dpu = 10,
  }) => InventoryItem(
    itemId: 1, name: 'Vaccine', genericName: '', itemCode: '',
    strengthDescription: '', dosageForm: 'Vial', category: 'Vaccine',
    unit: 'vials', quantity: 10, minimumStock: 2, batchNumber: 'BATCH-1',
    batches: batches, icon: Icons.vaccines_outlined,
    dosesPerUnit: dpu, openVialShelfHours: hours,
  );

  test('Td open clock creates an alert despite distant printed batch expiry', () {
    final stock = item([batch(openedAt: now.subtract(const Duration(hours: 8)))]);
    expect(stock.expiringSoonQuantity, 0);
    expect(stock.openVialExpiryBatchesOn(now).map((b) => b.batchId), [1]);
    expect(stock.expiryAttentionTimeLeftOn(now), const Duration(days: 27, hours: 16));
    expect(stock.hasExpiredExpiryAttentionOn(now), false);
    expect(stock.quantity, 10);
    expect(stock.openVialDoses, 7);
    expect(stock.totalAvailableDoses, 107);
  });

  test('BCG alerts at 5h 58m remaining even with no sealed stock', () {
    final stock = item([batch(sealed: 0, doses: 19,
      openedAt: now.subtract(const Duration(minutes: 2)))], hours: 6, dpu: 20);
    expect(stock.expiringSoonQuantity, 0);
    expect(stock.openVialExpiryBatchesOn(now).length, 1);
    expect(stock.expiryAttentionTimeLeftOn(now), const Duration(hours: 5, minutes: 58));
    expect(stock.hasExpiredExpiryAttentionOn(now), false);
  });

  test('open vial becomes expired exactly at its shelf-life boundary', () {
    final stock = item([batch(openedAt: now.subtract(const Duration(hours: 6)))], hours: 6);
    expect(stock.expiryAttentionTimeLeftOn(now), Duration.zero);
    expect(stock.hasExpiredExpiryAttentionOn(now), true);
    expect(stock.expiryAttentionTimeLeftOn(now.add(const Duration(minutes: 1))), const Duration(minutes: -1));
  });

  test('discarded, inactive and empty open vials do not create alerts', () {
    final stock = item([
      batch(id: 1, openedAt: now, status: 'discarded'),
      batch(id: 2, openedAt: now, status: 'depleted'),
      batch(id: 3, openedAt: now, doses: 0),
    ]);
    expect(stock.openVialExpiryBatchesOn(now), isEmpty);
    expect(stock.expiryAttentionTimeLeftOn(now), isNull);
  });

  test('unknown opening time and disabled shelf-life policy are not invented', () {
    expect(item([batch()]).openVialExpiryBatchesOn(now), isEmpty);
    expect(item([batch(openedAt: now)], hours: 0).openVialExpiryBatchesOn(now), isEmpty);
    expect(item([batch(openedAt: now)], dpu: 1).openVialExpiryBatchesOn(now), isEmpty);
  });

  test('90-day window includes its boundary and excludes a later open limit', () {
    expect(item([batch(openedAt: now)], hours: 90 * 24).openVialExpiryBatchesOn(now).length, 1);
    expect(item([batch(openedAt: now.add(const Duration(seconds: 1)))], hours: 90 * 24)
        .openVialExpiryBatchesOn(now), isEmpty);
  });

  test('multiple open batches stay distinct and sort by their opening deadlines', () {
    final batches = [batch(id: 1, openedAt: now),
      batch(id: 2, openedAt: now.subtract(const Duration(days: 1)))];
    final stock = item(batches);
    expect(stock.openVialExpiryBatchesOn(now).map((b) => b.batchId), [2, 1]);
    expect(batches.map((b) => b.batchId), [1, 2]);
    expect(stock.expiryAttentionTimeLeftOn(now), const Duration(days: 27));
  });

  test('printed expiry still takes precedence when it is earlier than open limit', () {
    final stock = item([batch(openedAt: now,
      expiration: DateTime(2026, 10, 9))]);
    expect(stock.expiryAttentionTimeLeftOn(now), const Duration(hours: 18));
    expect(stock.hasExpiredExpiryAttentionOn(now), false);
    expect(stock.hasExpiredExpiryAttentionOn(DateTime(2026, 10, 9)), true);
  });

  test('sealed-only batch alerts continue to use printed expiry', () {
    final stock = item([batch(doses: 0, expiration: DateTime(2026, 10, 28))]);
    expect(stock.openVialExpiryBatchesOn(now), isEmpty);
    expect(stock.expiryAttentionTimeLeftOn(now), const Duration(days: 20));
  });
}
