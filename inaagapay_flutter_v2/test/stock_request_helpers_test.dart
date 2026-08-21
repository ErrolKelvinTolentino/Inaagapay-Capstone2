import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife_inventory/inventory_models.dart';

/// The request sheet's ordering and suggestion rules, extracted here so they can
/// be checked without pumping a 4,900-line page.
///
/// These mirror the private helpers in midwife_inventory_page.dart. If one side
/// changes, this file should fail and be brought back in line.
int restockShortfall(int quantity, int minimumStock) =>
    (minimumStock - quantity).clamp(0, 1 << 30);

int suggestedRequestQuantity(int quantity, int minimumStock) {
  final shortfall = restockShortfall(quantity, minimumStock);
  final base = shortfall > 0 ? shortfall : minimumStock;
  if (base <= 0) return 10;
  if (base <= 10) return base;
  return ((base + 9) ~/ 10) * 10;
}

int urgencyRank(int quantity, int minimumStock) {
  if (quantity <= 0) return 0;
  if (quantity <= minimumStock) return 1;
  return 2;
}

void main() {
  group('suggested quantity', () {
    test('tops the item back up to its reorder level', () {
      // 12 on hand against a reorder level of 200 -> 188, rounded to 190.
      expect(suggestedRequestQuantity(12, 200), 190);
    });

    test('an empty shelf asks for a full reorder level', () {
      expect(suggestedRequestQuantity(0, 200), 200);
    });

    test('an item already above its level still gets a sensible default', () {
      expect(suggestedRequestQuantity(500, 200), 200);
    });

    test('small shortfalls are not rounded away', () {
      expect(suggestedRequestQuantity(45, 50), 5);
      expect(suggestedRequestQuantity(40, 50), 10);
    });

    test('never suggests zero', () {
      expect(suggestedRequestQuantity(0, 0), 10);
      expect(suggestedRequestQuantity(5, 5), greaterThan(0));
    });

    test('rounds up, never down — a request must not undershoot', () {
      for (var onHand = 0; onHand < 200; onHand++) {
        final suggestion = suggestedRequestQuantity(onHand, 200);
        expect(suggestion, greaterThanOrEqualTo(restockShortfall(onHand, 200)));
      }
    });
  });

  group('picker ordering', () {
    test('out of stock outranks low, which outranks healthy', () {
      expect(urgencyRank(0, 50), lessThan(urgencyRank(20, 50)));
      expect(urgencyRank(20, 50), lessThan(urgencyRank(80, 50)));
    });

    test('at exactly the reorder level an item still counts as needing stock', () {
      expect(urgencyRank(50, 50), 1);
      expect(urgencyRank(51, 50), 2);
    });

    test('a catalogue sorts worst-first, then alphabetically', () {
      final items = [
        ('Zinc', 500, 50),
        ('Ascorbic Acid', 10, 50),
        ('BCG Vaccine', 0, 20),
        ('Calcium', 600, 150),
      ];
      final sorted = List.of(items)
        ..sort((a, b) {
          final byRank =
              urgencyRank(a.$2, a.$3).compareTo(urgencyRank(b.$2, b.$3));
          if (byRank != 0) return byRank;
          return a.$1.toLowerCase().compareTo(b.$1.toLowerCase());
        });
      expect(sorted.map((e) => e.$1).toList(),
          ['BCG Vaccine', 'Ascorbic Acid', 'Calcium', 'Zinc']);
    });
  });

  group('supplier label', () {
    test('uses the real parent RHU when the hierarchy knows it', () {
      const ctx = MidwifeInventoryContext(
        accountId: 9,
        midwifeId: 3,
        facilityId: 3,
        facilityName: 'Pinagbarilan BHC',
        displayName: 'Midwife',
        isDemo: false,
        supplierName: 'Baliwag RHU III',
      );
      expect(ctx.supplierLabel, 'Baliwag RHU III');
    });

    test('falls back to generic wording, never to a made-up name', () {
      const ctx = MidwifeInventoryContext(
        accountId: 9,
        midwifeId: 3,
        facilityId: 3,
        facilityName: 'Pinagbarilan BHC',
        displayName: 'Midwife',
        isDemo: false,
      );
      expect(ctx.supplierLabel, 'your RHU');
      expect(ctx.supplierLabel, isNot(contains('Main')));
    });
  });
}
