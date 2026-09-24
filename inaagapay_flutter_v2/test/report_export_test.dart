import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/midwife_analytics.dart';
import 'package:inaagapay_flutter_v2/services/midwife_analytics_service.dart';
import 'package:inaagapay_flutter_v2/services/midwife_report_service.dart';
import 'package:inaagapay_flutter_v2/services/report_export_service.dart';

final _now = DateTime(2026, 9, 24, 10, 30);

ReportDocument _checkupDoc({int copies = 1}) {
  final rows = <Map<String, dynamic>>[
    for (int i = 0; i < copies; i++) ...[
      {
        'encounter_datetime': '2026-09-03T01:30:00Z',
        'mother_id': 1,
        'age_of_gestation_weeks': 24,
        'age_of_gestation_days': 3,
        'midwife_notes': 'Advised iron with vitamin C; return in 4 weeks.',
        'checkup': [
          {
            'checkup_weight': 58.4,
            'blood_pressure_systolic': 110,
            'blood_pressure_diastolic': 70,
            'fetal_heart_beat': 144,
            'fetal_heart_tone': 'regular',
            'fetal_position': 'cephalic',
            'edema': 'none',
            'td_vaccine_dose': 'Td2',
            'next_schedule': '2026-10-01',
          }
        ],
      },
      {
        'encounter_datetime': '2026-09-15T02:00:00Z',
        'mother_id': 2,
        'age_of_gestation_weeks': 33,
        'midwife_notes': null,
        'checkup': {
          'checkup_weight': 66,
          'blood_pressure_systolic': 142,
          'blood_pressure_diastolic': 92,
          'fetal_heart_beat': 150,
          'td_vaccine_dose': null,
        },
      },
    ],
  ];
  const names = {1: 'Dela Cruz, Maria', 2: 'Peñaflor, Ana'};
  return ReportDocument(
    title: 'Prenatal Checkup Records',
    facilityName: 'Pinagbarilan BHC',
    periodLabel: MidwifeReportService.periodLabel(DateTimeRange(
        start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30))),
    preparedBy: 'Juana Santos',
    generatedAt: _now,
    blocks: [
      MidwifeReportService.checkupBlock(
          rows, (row) => names[row['mother_id']] ?? ''),
    ],
  );
}

ReportDocument _statsDoc() {
  final section = AnalyticsSection(title: 'Mothers', metrics: [
    MidwifeAnalyticsService.pregnancyStageCard([
      {'last_menstrual_period': '2026-02-01', 'status': 'ongoing'},
      {'last_menstrual_period': '2026-06-01', 'status': 'ongoing'},
      {'status': 'ongoing'},
    ], _now),
    const AnalyticsMetric(
      title: 'Td protection',
      kind: AnalyticsChartKind.coverage,
      headline: '7',
      headlineCaption: 'of 9 protected',
      covered: 7,
      eligible: 9,
      insight: AnalyticsInsight('Two mothers are due a Td dose.',
          tone: AnalyticsTone.watch),
    ),
    const AnalyticsMetric.empty(
        title: 'Weight gain', message: 'No weight gain assessed yet.'),
  ]);
  return MidwifeReportService.statisticsDocument(
    section,
    title: 'Mother Statistics',
    facilityName: 'Pinagbarilan BHC',
    preparedBy: 'Juana Santos',
    now: _now,
  );
}

void main() {
  test('period labels read as a month when they cover one', () {
    expect(
      MidwifeReportService.periodLabel(DateTimeRange(
          start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30))),
      'September 2026',
    );
    expect(
      MidwifeReportService.periodLabel(DateTimeRange(
          start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 24))),
      'Sep 1, 2026 - Sep 24, 2026',
    );
  });

  test('checkup rows carry every clinical column, blanks left blank', () {
    final block = _checkupDoc().blocks.single;
    expect(block.columns.length, 12);
    expect(block.rows.length, 2);
    final first = block.rows.first;
    expect(first[1], 'Dela Cruz, Maria');
    expect(first[2], '24w 3d');
    expect(first[4], '110/70');
    expect(first[9], 'Td2');
    // An embedded row may come back as a map rather than a list.
    expect(block.rows.last[4], '142/92');
    expect(block.rows.last[2], '33w');
  });

  test('file names are safe on every platform', () {
    expect(_checkupDoc().fileName('pdf'),
        'prenatal-checkup-records_pinagbarilan-bhc_2026-09-24.pdf');
  });

  test('statistics blocks keep the headline, reading and caveat', () {
    final doc = _statsDoc();
    expect(doc.blocks.length, 3);
    final coverage = doc.blocks[1];
    expect(coverage.lead, contains('Coverage: 7 of 9.'));
    expect(coverage.lead.any((l) => l.startsWith('Reading: Two mothers')),
        isTrue);
    expect(doc.blocks[2].rows, isEmpty);
    expect(doc.blocks[2].emptyText, 'No weight gain assessed yet.');
  });

  test('the workbook holds the same rows as the PDF', () {
    final bytes = ReportExportService.toXlsx(_checkupDoc());
    final book = xl.Excel.decodeBytes(bytes);
    final sheet = book['Prenatal Checkup Records'];
    final values = [
      for (final row in sheet.rows)
        [for (final cell in row) cell?.value?.toString() ?? '']
    ];
    final header = values.indexWhere((r) => r.isNotEmpty && r.first == 'Date');
    expect(header, greaterThan(0));
    expect(values[header + 1][1], 'Dela Cruz, Maria');
    expect(values[header + 2][1], 'Peñaflor, Ana');
    expect(values[header + 1][4], '110/70');
  });

  test('PDFs render, including one long enough to span pages', () async {
    final outDir = Platform.environment['REPORT_SAMPLE_DIR'];
    final samples = {
      'checkups': _checkupDoc(),
      'checkups_long': _checkupDoc(copies: 40),
      'statistics': _statsDoc(),
    };
    for (final entry in samples.entries) {
      final pdf = await ReportExportService.toPdf(entry.value);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      final xlsx = ReportExportService.toXlsx(entry.value);
      expect(xlsx.length, greaterThan(1000));
      if (outDir != null) {
        File('$outDir/${entry.key}.pdf').writeAsBytesSync(pdf);
        File('$outDir/${entry.key}.xlsx').writeAsBytesSync(xlsx);
      }
    }
  });
}
