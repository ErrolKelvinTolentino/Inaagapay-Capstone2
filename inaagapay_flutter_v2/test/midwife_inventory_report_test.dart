import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife_inventory/inventory_models.dart';
import 'package:inaagapay_flutter_v2/screens/midwife_inventory/midwife_inventory_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MidwifeInventoryReportService Date Range & Reporting Periods', () {
    final fixedNow = DateTime.utc(2026, 8, 27, 14, 30, 0); // Thursday, Aug 27, 2026

    test('resolves "today" range correctly', () {
      final range = MidwifeInventoryReportService.resolveDateRange('today', now: fixedNow);
      expect(range, isNotNull);
      expect(range!.start, DateTime(2026, 8, 27));
      expect(range.end.day, 27);
      expect(range.end.hour, 23);
    });

    test('resolves "this_week" range starting on Monday and ending on Sunday', () {
      final range = MidwifeInventoryReportService.resolveDateRange('this_week', now: fixedNow);
      expect(range, isNotNull);
      // Monday of this week is Aug 24, 2026
      expect(range!.start.day, 24);
      expect(range.start.month, 8);
      // Sunday of this week is Aug 30, 2026
      expect(range.end.day, 30);
      expect(range.end.month, 8);
    });

    test('resolves "last_week" range accurately', () {
      final range = MidwifeInventoryReportService.resolveDateRange('last_week', now: fixedNow);
      expect(range, isNotNull);
      // Monday of last week is Aug 17, 2026
      expect(range!.start.day, 17);
      expect(range.start.month, 8);
      // Sunday of last week is Aug 23, 2026
      expect(range.end.day, 23);
      expect(range.end.month, 8);
    });

    test('resolves "this_month" range accurately', () {
      final range = MidwifeInventoryReportService.resolveDateRange('this_month', now: fixedNow);
      expect(range, isNotNull);
      expect(range!.start.day, 1);
      expect(range.start.month, 8);
      expect(range.end.month, 8);
      expect(range.end.day, 31);
    });

    test('resolves "last_month" range accurately', () {
      final range = MidwifeInventoryReportService.resolveDateRange('last_month', now: fixedNow);
      expect(range, isNotNull);
      expect(range!.start.day, 1);
      expect(range.start.month, 7);
      expect(range.end.month, 7);
      expect(range.end.day, 31);
    });

    test('formats period labels clearly for human reporting', () {
      final thisWeekRange = MidwifeInventoryReportService.resolveDateRange('this_week', now: fixedNow);
      final label = MidwifeInventoryReportService.formatPeriodLabel('this_week', range: thisWeekRange);
      expect(label, contains('This Week'));
      expect(label, contains('Aug 24, 2026'));

      final allLabel = MidwifeInventoryReportService.formatPeriodLabel('all');
      expect(allLabel, 'All Recorded History');
    });
  });

  group('MidwifeInventoryReportService PDF Document Generation', () {
    final sampleLedger = [
      InventoryTransactionRecord.fromJson({
        'transaction_id': 201,
        'batch_id': 10,
        'facility_id': 2,
        'transaction_type': 'dispense',
        'quantity': 0,
        'dose_quantity': -1,
        'doses_per_unit': 10,
        'resulting_open_vial_doses': 8,
        'resulting_quantity_remaining': 5,
        'reference_type': 'Child Immunization',
        'item_id': 1,
        'item_name': 'Pentavalent Vaccine',
        'unit_of_measure': 'vial',
        'batch_number': 'PENTA-2026B',
        'logged_at': '2026-08-26T10:00:00Z',
        'performed_by_name': 'Maria Santos',
        'performed_by_role': 'midwife',
        'patient_number': 'NAK-001',
      }),
      InventoryTransactionRecord.fromJson({
        'transaction_id': 202,
        'batch_id': 15,
        'facility_id': 2,
        'transaction_type': 'receipt',
        'quantity': 20,
        'dose_quantity': 200,
        'doses_per_unit': 10,
        'resulting_quantity_remaining': 20,
        'reference_type': 'RHU Main Dispatch #109',
        'item_id': 2,
        'item_name': 'Hepatitis B Vaccine',
        'unit_of_measure': 'vial',
        'batch_number': 'HEP-9901',
        'logged_at': '2026-08-25T11:00:00Z',
        'performed_by_name': 'Juan dela Cruz',
        'performed_by_role': 'admin',
      }),
      InventoryTransactionRecord.fromJson({
        'transaction_id': 203,
        'batch_id': 10,
        'facility_id': 2,
        'transaction_type': 'expiry_disposal',
        'quantity': -2,
        'dose_quantity': -20,
        'doses_per_unit': 10,
        'resulting_quantity_remaining': 3,
        'reference_type': 'Expired stock report',
        'notes': 'Unusable due to storage temperature excursion',
        'item_id': 1,
        'item_name': 'Pentavalent Vaccine',
        'unit_of_measure': 'vial',
        'batch_number': 'PENTA-2026B',
        'logged_at': '2026-08-24T15:00:00Z',
        'performed_by_name': 'Maria Santos',
        'performed_by_role': 'midwife',
      }),
    ];

    test('generates valid non-empty PDF byte stream with full metadata', () async {
      final pdfBytes = await MidwifeInventoryReportService.generateReportPdf(
        facilityName: 'Pinagbarilan Barangay Health Center',
        midwifeName: 'Maria Santos',
        periodLabel: 'August 24, 2026 – August 30, 2026 (This Week)',
        transactions: sampleLedger,
        categoryFilter: 'all',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      // PDF documents start with %PDF header (0x25, 0x50, 0x44, 0x46)
      expect(pdfBytes[0], 0x25);
      expect(pdfBytes[1], 0x50);
      expect(pdfBytes[2], 0x44);
      expect(pdfBytes[3], 0x46);
    });

    test('generates PDF correctly when transactions list is empty', () async {
      final pdfBytes = await MidwifeInventoryReportService.generateReportPdf(
        facilityName: 'Pinagbarilan Barangay Health Center',
        midwifeName: 'Maria Santos',
        periodLabel: 'Last Month',
        transactions: const [],
        categoryFilter: 'all',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
    });
  });
}
