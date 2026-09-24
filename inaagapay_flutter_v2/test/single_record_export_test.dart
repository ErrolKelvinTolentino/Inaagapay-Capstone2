import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/shared/record_detail_screen.dart';
import 'package:inaagapay_flutter_v2/services/maternal_td_service.dart';
import 'package:inaagapay_flutter_v2/services/report_export_service.dart';
import 'package:inaagapay_flutter_v2/services/td_record_export.dart';
import 'package:inaagapay_flutter_v2/widgets/export_menu_button.dart';

final _outDir = Platform.environment['REPORT_SAMPLE_DIR'];

List<List<String>> _sheetRows(List<int> bytes) {
  final book = xl.Excel.decodeBytes(bytes);
  final sheet = book.tables.values.first;
  return [
    for (final row in sheet.rows)
      [for (final cell in row) cell?.value?.toString() ?? '']
  ];
}

void main() {
  group('a single lab test', () {
    Widget screen() => const MaterialApp(
          home: RecordDetailScreen(
            title: 'Laboratory Test',
            subtitle: 'Conducted Sep 3, 2026',
            icon: Icons.biotech_outlined,
            rows: [
              MapEntry('Test type', 'Complete blood count'),
              MapEntry('Laboratory', 'Baliwag District Hospital'),
            ],
            resultsTitle: 'Blood Count',
            resultRows: [
              MapEntry('Hemoglobin', '10.2 g/dL'),
              MapEntry('Hematocrit', '31 %'),
            ],
            patient: RecordPatient(
              name: 'Dela Cruz, Maria',
              idLabel: 'INA-012',
              age: '24 years',
              bloodType: 'O+',
            ),
            approvedByName: 'Juana Santos',
          ),
        );

    testWidgets('offers PDF and Excel from the record', (tester) async {
      await tester.pumpWidget(screen());
      await tester.pump();
      expect(find.byType(ExportMenuButton), findsOneWidget);

      await tester.tap(find.byType(ExportMenuButton));
      await tester.pumpAndSettle();
      expect(find.text('Save as PDF'), findsOneWidget);
      expect(find.text('Save as Excel'), findsOneWidget);
      expect(find.text('Share PDF'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
    });

    testWidgets('the workbook carries the results and whose record it is',
        (tester) async {
      await tester.pumpWidget(screen());
      await tester.pump();
      final state = tester.state(find.byType(RecordDetailScreen)) as dynamic;

      final doc = state.recordDocumentForTest() as ReportDocument;
      final titles = doc.blocks.map((b) => b.title).toList();
      expect(titles, containsAll(['Patient', 'Blood Count']));
      final results = doc.blocks.firstWhere((b) => b.title == 'Blood Count');
      expect(results.rows.first, ['Hemoglobin', '10.2 g/dL']);

      final rows = _sheetRows(ReportExportService.toXlsx(doc));
      final flat = rows.expand((r) => r).toList();
      expect(flat, containsAll(['Dela Cruz, Maria', 'INA-012', 'Hemoglobin', '10.2 g/dL']));

      await tester.runAsync(() async {
        final pdf = await state.buildPdfForTest() as List<int>;
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        if (_outDir != null) {
          File('$_outDir/lab_record.pdf').writeAsBytesSync(pdf);
          File('$_outDir/lab_record.xlsx')
              .writeAsBytesSync(ReportExportService.toXlsx(doc));
        }
      });
    });
  });

  group('a mother\'s Td record', () {
    final status = MaternalTdStatus(doses: {
      'Td1': MaternalTdRecord(
        doseKey: 'Td1',
        date: DateTime(2026, 5, 4),
        source: 'bhc',
        facilityName: 'Pinagbarilan BHC',
        nextDueDate: DateTime(2026, 6, 1),
      ),
      'Td2': MaternalTdRecord(
        doseKey: 'Td2',
        date: DateTime(2026, 6, 8),
        source: 'outside',
        facilityName: 'Baliwag District Hospital',
        protectionUntil: DateTime(2029, 6, 8),
        nextDueDate: DateTime(2026, 12, 5),
        remarks: 'Card seen',
      ),
    });

    test('lists all five doses, given or not, with her protection', () async {
      final doc = TdRecordExport.document(
        status: status,
        motherName: 'Dela Cruz, Maria',
        patientNumber: 'INA-012',
        facilityName: 'Pinagbarilan BHC',
        preparedBy: 'Juana Santos',
        now: DateTime(2026, 9, 24),
      );

      final protection = doc.blocks.firstWhere((b) => b.title == 'Protection status');
      expect(protection.rows, anyElement(equals(['Doses recorded', '2 of 5'])));
      expect(protection.rows, anyElement(equals(['Baby protected at birth', 'Yes'])));

      final doses = doc.blocks.firstWhere((b) => b.title == 'Doses');
      expect(doses.rows, hasLength(5));
      expect(doses.rows[1][3], 'Given at another facility');
      expect(doses.rows[2][1], 'Not yet given');

      final pdf = await ReportExportService.toPdf(doc);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      final flat = _sheetRows(ReportExportService.toXlsx(doc)).expand((r) => r).toList();
      expect(flat, containsAll(['Dela Cruz, Maria', 'INA-012', 'Card seen']));

      if (_outDir != null) {
        File('$_outDir/td_record.pdf').writeAsBytesSync(pdf);
        File('$_outDir/td_record.xlsx')
            .writeAsBytesSync(ReportExportService.toXlsx(doc));
      }
    });

    test('says what comes next in plain words', () {
      expect(TdRecordExport.nextStep(status), startsWith('Td3 from'));
      expect(TdRecordExport.nextStep(MaternalTdStatus.empty), 'Td1 is due now');
    });
  });
}
