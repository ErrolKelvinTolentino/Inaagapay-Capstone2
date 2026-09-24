// lib/services/report_export_service.dart
//
// One report, two formats. A report is described once as a [ReportDocument] —
// a title, the facility and period it covers, and one or more blocks of rows —
// and rendered to a paginated PDF for printing and filing, or to an .xlsx
// workbook for anyone who needs to sort, total or re-cut the numbers.
//
// Describing it once is the point: the PDF and the spreadsheet a midwife hands
// the Municipal Health Office cannot disagree about a single row.
//
// Pure Dart plus the pdf and excel packages — no widgets, no Supabase — so
// every report can be built and checked in a unit test.

import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One titled table, with the sentences that explain it.
class ReportBlock {
  const ReportBlock({
    required this.title,
    required this.columns,
    required this.rows,
    this.lead = const [],
    this.notes = const [],
    this.columnFlex,
    this.numericColumns = const {},
    this.emptyText = 'No records for this period.',
  });

  final String title;

  /// Said before the table — a headline figure, a reading of it.
  final List<String> lead;

  final List<String> columns;

  /// Cells may be String, num, DateTime, bool or null.
  final List<List<Object?>> rows;

  /// Caveats said after the table.
  final List<String> notes;

  /// Relative PDF column widths. Even when absent.
  final List<double>? columnFlex;

  /// Columns right-aligned in the PDF.
  final Set<int> numericColumns;

  final String emptyText;
}

class ReportDocument {
  ReportDocument({
    required this.title,
    required this.facilityName,
    required this.periodLabel,
    required this.preparedBy,
    required this.blocks,
    this.landscape = true,
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now();

  final String title;
  final String facilityName;
  final String periodLabel;
  final String preparedBy;
  final List<ReportBlock> blocks;
  final bool landscape;
  final DateTime generatedAt;

  /// "prenatal-checkups_pinagbarilan-bhc_2026-09" — safe on every platform.
  String fileName(String extension) {
    String slug(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp = DateFormat('yyyy-MM-dd').format(generatedAt);
    return '${slug(title)}_${slug(facilityName)}_$stamp.$extension';
  }
}

class ReportExportService {
  const ReportExportService._();

  static final DateFormat _date = DateFormat('MMM d, yyyy');
  static final DateFormat _stamp = DateFormat('MMM d, yyyy h:mm a');

  static const _brand = PdfColor.fromInt(0xFFC73578);
  static const _brandSoft = PdfColor.fromInt(0xFFFCE7F1);
  static const _ink = PdfColor.fromInt(0xFF1F1F1F);
  static const _muted = PdfColor.fromInt(0xFF6B6B6B);
  static const _rule = PdfColor.fromInt(0xFFDDDDDD);
  static const _zebra = PdfColor.fromInt(0xFFF7F7F7);

  /// How a cell reads on paper.
  static String cellText(Object? value) {
    if (value == null) return '';
    if (value is DateTime) return _date.format(value);
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is double) {
      return value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(1);
    }
    return value.toString();
  }

  // ==========================================================================
  // PDF
  // ==========================================================================

  static Future<Uint8List> toPdf(ReportDocument doc) async {
    final pdf = pw.Document(
      title: '${doc.title} - ${doc.facilityName}',
      author: 'InaAgapay MCHIS',
      creator: 'InaAgapay MCHIS',
    );

    final format = doc.landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
        header: (context) => context.pageNumber == 1
            ? _pdfTitleBlock(doc)
            : _pdfRunningHeader(doc),
        footer: (context) => _pdfFooter(doc, context),
        build: (context) => [
          for (final block in doc.blocks) ..._pdfBlock(context, block),
          pw.SizedBox(height: 24),
          _pdfSignatures(doc),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pdfTitleBlock(ReportDocument doc) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _brand, width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'INAAGAPAY MATERNAL AND CHILD HEALTH INFORMATION SYSTEM',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: _muted,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  doc.title,
                  style: pw.TextStyle(
                    fontSize: 17,
                    color: _ink,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  doc.facilityName,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    color: _brand,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _pdfMeta('Period', doc.periodLabel),
              _pdfMeta('Prepared by', doc.preparedBy),
              _pdfMeta('Generated', _stamp.format(doc.generatedAt)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfMeta(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 1.5),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(
                fontSize: 8,
                color: _muted,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.TextSpan(
              text: value,
              style: const pw.TextStyle(fontSize: 8, color: _ink),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pdfRunningHeader(ReportDocument doc) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(doc.title,
              style: pw.TextStyle(
                  fontSize: 8, color: _ink, fontWeight: pw.FontWeight.bold)),
          pw.Text('${doc.facilityName}  |  ${doc.periodLabel}',
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ],
      ),
    );
  }

  static pw.Widget _pdfFooter(ReportDocument doc, pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Confidential patient information. Handle under the Data Privacy '
            'Act of 2012 (RA 10173).',
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _pdfBlock(pw.Context context, ReportBlock block) {
    final widgets = <pw.Widget>[
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 10, bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: const pw.BoxDecoration(
          color: _brandSoft,
          border: pw.Border(left: pw.BorderSide(color: _brand, width: 3)),
        ),
        child: pw.Text(
          block.title,
          style: pw.TextStyle(
            fontSize: 11,
            color: _ink,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      for (final line in block.lead)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(line,
              style: const pw.TextStyle(fontSize: 9, color: _ink)),
        ),
      if (block.lead.isNotEmpty) pw.SizedBox(height: 4),
    ];

    if (block.rows.isEmpty) {
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Text(
          block.emptyText,
          style: pw.TextStyle(
              fontSize: 9, color: _muted, fontStyle: pw.FontStyle.italic),
        ),
      ));
    } else {
      final flex = block.columnFlex;
      widgets.add(pw.TableHelper.fromTextArray(
        context: context,
        headers: block.columns,
        data: [
          for (final row in block.rows) [for (final cell in row) cellText(cell)],
        ],
        border: pw.TableBorder.all(color: _rule, width: 0.5),
        headerDecoration: const pw.BoxDecoration(color: _brand),
        headerStyle: pw.TextStyle(
          fontSize: 8,
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: const pw.TextStyle(fontSize: 8, color: _ink),
        oddRowDecoration: const pw.BoxDecoration(color: _zebra),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        headerAlignment: pw.Alignment.centerLeft,
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {
          for (final i in block.numericColumns) i: pw.Alignment.centerRight,
        },
        columnWidths: flex == null
            ? null
            : {
                for (int i = 0; i < flex.length; i++)
                  i: pw.FlexColumnWidth(flex[i]),
              },
      ));
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: pw.Text(
          '${block.rows.length} ${block.rows.length == 1 ? 'row' : 'rows'}',
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
      ));
    }

    for (final note in block.notes) {
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Text(note,
            style: pw.TextStyle(
                fontSize: 7.5, color: _muted, fontStyle: pw.FontStyle.italic)),
      ));
    }
    return widgets;
  }

  static pw.Widget _pdfSignatures(ReportDocument doc) {
    pw.Widget line(String caption, String name, String role) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(caption,
                  style: const pw.TextStyle(fontSize: 8, color: _muted)),
              pw.SizedBox(height: 22),
              // Fixed height so an unnamed line sits level with a named one.
              pw.Container(
                width: 200,
                height: 14,
                alignment: pw.Alignment.bottomLeft,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.6)),
                ),
                child: pw.Text(name,
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 2),
              pw.Text(role,
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            ],
          ),
        );

    return pw.Row(children: [
      line('Prepared and certified correct by:', doc.preparedBy,
          'Midwife-in-Charge, ${doc.facilityName}'),
      pw.SizedBox(width: 24),
      line('Noted by:', '', 'Public Health Nurse / Municipal Health Officer'),
    ]);
  }

  // ==========================================================================
  // XLSX
  // ==========================================================================

  static Uint8List toXlsx(ReportDocument doc) {
    final book = xl.Excel.createExcel();
    final defaultSheet = book.getDefaultSheet() ?? 'Sheet1';
    final sheetName = _sheetName(doc.title);
    book.rename(defaultSheet, sheetName);
    book.setDefaultSheet(sheetName);
    final sheet = book[sheetName];

    final titleStyle = xl.CellStyle(bold: true, fontSize: 14);
    final metaLabel = xl.CellStyle(
        bold: true, fontColorHex: xl.ExcelColor.fromHexString('FF6B6B6B'));
    final blockStyle = xl.CellStyle(
      bold: true,
      fontSize: 12,
      backgroundColorHex: xl.ExcelColor.fromHexString('FFFCE7F1'),
    );
    final thin = xl.Border(
      borderStyle: xl.BorderStyle.Thin,
      borderColorHex: xl.ExcelColor.fromHexString('FFBDBDBD'),
    );
    final headerStyle = xl.CellStyle(
      bold: true,
      fontColorHex: xl.ExcelColor.white,
      backgroundColorHex: xl.ExcelColor.fromHexString('FFC73578'),
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
      textWrapping: xl.TextWrapping.WrapText,
      verticalAlign: xl.VerticalAlign.Center,
    );
    final bodyStyle = xl.CellStyle(
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
      verticalAlign: xl.VerticalAlign.Top,
    );
    final dateStyle = xl.CellStyle(
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
      verticalAlign: xl.VerticalAlign.Top,
      numberFormat: const xl.CustomDateTimeNumFormat(formatCode: 'yyyy-mm-dd'),
    );
    final noteStyle = xl.CellStyle(
        italic: true, fontColorHex: xl.ExcelColor.fromHexString('FF6B6B6B'));

    int row = 0;
    final widths = <int, int>{};

    void put(int col, xl.CellValue? value, xl.CellStyle style) {
      sheet.updateCell(
        xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        value,
        cellStyle: style,
      );
    }

    void measure(int col, String text) {
      final longest = text
          .split('\n')
          .fold<int>(0, (m, line) => line.length > m ? line.length : m);
      if ((widths[col] ?? 0) < longest) widths[col] = longest;
    }

    put(0, xl.TextCellValue(doc.title), titleStyle);
    row++;
    for (final meta in [
      ['Facility', doc.facilityName],
      ['Period', doc.periodLabel],
      ['Prepared by', doc.preparedBy],
      ['Generated', _stamp.format(doc.generatedAt)],
    ]) {
      put(0, xl.TextCellValue(meta[0]), metaLabel);
      put(1, xl.TextCellValue(meta[1]), xl.CellStyle());
      row++;
    }

    for (final block in doc.blocks) {
      row++;
      put(0, xl.TextCellValue(block.title), blockStyle);
      for (int c = 1; c < block.columns.length; c++) {
        put(c, null, blockStyle);
      }
      row++;
      for (final line in block.lead) {
        put(0, xl.TextCellValue(line), xl.CellStyle());
        row++;
      }

      for (int c = 0; c < block.columns.length; c++) {
        put(c, xl.TextCellValue(block.columns[c]), headerStyle);
        measure(c, block.columns[c]);
      }
      row++;

      if (block.rows.isEmpty) {
        put(0, xl.TextCellValue(block.emptyText), noteStyle);
        row++;
      }
      for (final cells in block.rows) {
        for (int c = 0; c < cells.length; c++) {
          final value = cells[c];
          put(c, _xlValue(value), value is DateTime ? dateStyle : bodyStyle);
          measure(c, value is DateTime ? '2026-12-31' : cellText(value));
        }
        row++;
      }
      for (final note in block.notes) {
        put(0, xl.TextCellValue(note), noteStyle);
        row++;
      }
    }

    for (final entry in widths.entries) {
      final width = (entry.value + 2).clamp(10, 60).toDouble();
      sheet.setColumnWidth(entry.key, width);
    }

    final bytes = book.encode();
    if (bytes == null) {
      throw StateError('The spreadsheet could not be generated.');
    }
    return Uint8List.fromList(bytes);
  }

  static xl.CellValue? _xlValue(Object? value) {
    if (value == null) return null;
    if (value is int) return xl.IntCellValue(value);
    if (value is double) return xl.DoubleCellValue(value);
    if (value is num) return xl.DoubleCellValue(value.toDouble());
    if (value is DateTime) {
      return xl.DateCellValue(
          year: value.year, month: value.month, day: value.day);
    }
    return xl.TextCellValue(cellText(value));
  }

  /// Excel refuses sheet names over 31 characters or containing []:*?/\
  static String _sheetName(String title) {
    final clean = title.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    return clean.length <= 31 ? clean : clean.substring(0, 31).trim();
  }
}
