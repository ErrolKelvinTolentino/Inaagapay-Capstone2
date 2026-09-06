import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife_inventory/inventory_models.dart';

void main() {
  group('Midwife lateral stock transfer safety assessment', () {
    final today = DateTime(2026, 9, 10);
    const itemName = 'Amoxicillin 500mg Capsule';
    const unit = 'capsules';
    const destination = 'Sto. Nino BHC';
    const minThreshold = 50;

    test('prompts to pick an arrival date when date is null', () {
      final assessment = TransferSafetyAssessment.evaluate(
        expectedArrivalDate: null,
        expirationDate: DateTime(2027, 1, 1),
        batchQuantityRemaining: 100,
        totalSourceItemAvailable: 150,
        quantity: 20,
        minimumStockThreshold: minThreshold,
        itemName: itemName,
        unit: unit,
        destinationName: destination,
        now: today,
      );

      expect(assessment.level, TransferSafetyLevel.warning);
      expect(assessment.isBlocked, isFalse);
      expect(assessment.title, contains('Choose expected arrival date'));
      expect(assessment.transitDays, isNull);
    });

    test('blocks when expected arrival date is in the past', () {
      final assessment = TransferSafetyAssessment.evaluate(
        expectedArrivalDate: DateTime(2026, 9, 9),
        expirationDate: DateTime(2027, 1, 1),
        batchQuantityRemaining: 100,
        totalSourceItemAvailable: 150,
        quantity: 20,
        minimumStockThreshold: minThreshold,
        itemName: itemName,
        unit: unit,
        destinationName: destination,
        now: today,
      );

      expect(assessment.level, TransferSafetyLevel.critical);
      expect(assessment.isBlocked, isTrue);
      expect(assessment.title, 'Invalid arrival date');
      expect(assessment.transitDays, -1);
    });

    test('blocks when quantity is zero or negative', () {
      final assessment = TransferSafetyAssessment.evaluate(
        expectedArrivalDate: DateTime(2026, 9, 12),
        expirationDate: DateTime(2027, 1, 1),
        batchQuantityRemaining: 100,
        totalSourceItemAvailable: 150,
        quantity: 0,
        minimumStockThreshold: minThreshold,
        itemName: itemName,
        unit: unit,
        destinationName: destination,
        now: today,
      );

      expect(assessment.level, TransferSafetyLevel.critical);
      expect(assessment.isBlocked, isTrue);
      expect(assessment.title, 'Enter valid quantity');
    });

    test('blocks when quantity exceeds batch available stock', () {
      final assessment = TransferSafetyAssessment.evaluate(
        expectedArrivalDate: DateTime(2026, 9, 12),
        expirationDate: DateTime(2027, 1, 1),
        batchQuantityRemaining: 40,
        totalSourceItemAvailable: 150,
        quantity: 50,
        minimumStockThreshold: minThreshold,
        itemName: itemName,
        unit: unit,
        destinationName: destination,
        now: today,
      );

      expect(assessment.level, TransferSafetyLevel.critical);
      expect(assessment.isBlocked, isTrue);
      expect(assessment.title, contains('exceeds available batch stock'));
    });

    test('blocks when batch expires on or before expected arrival date', () {
      // Expiration is Sept 12, arrival is Sept 12 -> shelf life at arrival = 0
      final assessment = TransferSafetyAssessment.evaluate(
        expectedArrivalDate: DateTime(2026, 9, 12),
        expirationDate: DateTime(2026, 9, 12),
        batchQuantityRemaining: 100,
        totalSourceItemAvailable: 150,
        quantity: 20,
        minimumStockThreshold: minThreshold,
        itemName: itemName,
        unit: unit,
        destinationName: destination,
        now: today,
      );

      expect(assessment.level, TransferSafetyLevel.critical);
      expect(assessment.isBlocked, isTrue);
      expect(assessment.shelfLifeAtArrival, 0);
      expect(assessment.title, contains('expire before or on arrival'));
    });

    test('warns when batch has 30 days or less shelf life remaining at arrival', () {
      // Expiration is Sept 30, arrival is Sept 12 -> shelf life at arrival = 18 days
      final assessment = TransferSafetyAssessment.evaluate(
        expectedArrivalDate: DateTime(2026, 9, 12),
        expirationDate: DateTime(2026, 9, 30),
        batchQuantityRemaining: 100,
        totalSourceItemAvailable: 150,
        quantity: 20,
        minimumStockThreshold: minThreshold,
        itemName: itemName,
        unit: unit,
        destinationName: destination,
        now: today,
      );

      expect(assessment.level, TransferSafetyLevel.warning);
      expect(assessment.isBlocked, isFalse);
      expect(assessment.shelfLifeAtArrival, 18);
      expect(assessment.warnings.any((w) => w.contains('18 days of shelf life')), isTrue);
    });

    test('warns when source BHC is left with 0 stock', () {
      final assessment = TransferSafetyAssessment.evaluate(
        expectedArrivalDate: DateTime(2026, 9, 11),
        expirationDate: DateTime(2027, 6, 1),
        batchQuantityRemaining: 30,
        totalSourceItemAvailable: 30,
        quantity: 30,
        minimumStockThreshold: minThreshold,
        itemName: itemName,
        unit: unit,
        destinationName: destination,
        now: today,
      );

      expect(assessment.level, TransferSafetyLevel.warning);
      expect(assessment.isBlocked, isFalse);
      expect(assessment.sourceRemainingAfter, 0);
      expect(assessment.warnings.any((w) => w.contains('0 capsules')), isTrue);
    });

    test('warns when source BHC drops at or below minimum reorder threshold', () {
      // Available = 70, transfer = 30 -> remaining = 40 <= minThreshold (50)
      final assessment = TransferSafetyAssessment.evaluate(
        expectedArrivalDate: DateTime(2026, 9, 11),
        expirationDate: DateTime(2027, 6, 1),
        batchQuantityRemaining: 70,
        totalSourceItemAvailable: 70,
        quantity: 30,
        minimumStockThreshold: minThreshold,
        itemName: itemName,
        unit: unit,
        destinationName: destination,
        now: today,
      );

      expect(assessment.level, TransferSafetyLevel.warning);
      expect(assessment.isBlocked, isFalse);
      expect(assessment.sourceRemainingAfter, 40);
      expect(assessment.warnings.any((w) => w.contains('at or below minimum reorder level')), isTrue);
    });

    test('passes as safe when all validations succeed without threshold issues', () {
      // Transit = 1 day, shelf life at arrival = 263 days, remaining after = 120 (> 50)
      final assessment = TransferSafetyAssessment.evaluate(
        expectedArrivalDate: DateTime(2026, 9, 11),
        expirationDate: DateTime(2027, 6, 1),
        batchQuantityRemaining: 80,
        totalSourceItemAvailable: 150,
        quantity: 30,
        minimumStockThreshold: minThreshold,
        itemName: itemName,
        unit: unit,
        destinationName: destination,
        now: today,
      );

      expect(assessment.level, TransferSafetyLevel.safe);
      expect(assessment.isBlocked, isFalse);
      expect(assessment.transitDays, 1);
      expect(assessment.shelfLifeAtArrival, 263);
      expect(assessment.sourceRemainingAfter, 120);
      expect(assessment.title, 'Safe to transfer');
      expect(assessment.warnings, isEmpty);
    });
  });

  group('PeerFacility model', () {
    test('parses from database JSON correctly', () {
      final json = {
        'facility_id': 14,
        'name': 'Barangay Subic Health Center',
        'facility_code': 'BHC-SUB',
        'facility_type': 'bhc',
        'parent_facility_id': 2,
      };

      final facility = PeerFacility.fromJson(json);
      expect(facility.facilityId, 14);
      expect(facility.name, 'Barangay Subic Health Center');
      expect(facility.facilityCode, 'BHC-SUB');
      expect(facility.facilityType, 'bhc');
      expect(facility.parentFacilityId, 2);
    });

    test('handles null optional fields with fallbacks', () {
      final json = {
        'facility_id': 20,
      };

      final facility = PeerFacility.fromJson(json);
      expect(facility.facilityId, 20);
      expect(facility.name, 'Barangay Health Center');
      expect(facility.facilityCode, isEmpty);
      expect(facility.facilityType, 'bhc');
      expect(facility.parentFacilityId, isNull);
    });
  });

  group('MidwifeInventoryContext hierarchy', () {
    test('retains parentFacilityId and computes supplierLabel', () {
      const contextWithParent = MidwifeInventoryContext(
        accountId: 5,
        midwifeId: 2,
        facilityId: 10,
        facilityName: 'Tarcan BHC',
        displayName: 'Maria Santos',
        isDemo: false,
        supplierName: 'Baliwag RHU I',
        parentFacilityId: 1,
      );

      expect(contextWithParent.parentFacilityId, 1);
      expect(contextWithParent.supplierName, 'Baliwag RHU I');
      expect(contextWithParent.supplierLabel, 'Baliwag RHU I');

      const contextWithoutParent = MidwifeInventoryContext(
        accountId: 6,
        midwifeId: 3,
        facilityId: 11,
        facilityName: 'Sabang BHC',
        displayName: 'Juana Cruz',
        isDemo: false,
      );

      expect(contextWithoutParent.parentFacilityId, isNull);
      expect(contextWithoutParent.supplierLabel, 'your RHU');
    });
  });
}
