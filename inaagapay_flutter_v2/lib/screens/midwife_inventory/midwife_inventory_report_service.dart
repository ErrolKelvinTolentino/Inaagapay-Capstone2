import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext, DateTimeRange;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'inventory_models.dart';

/// Service for generating official, printable BHC inventory and stock movement reports in PDF format.
class MidwifeInventoryReportService {
  static final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('MMM dd, yyyy hh:mm a');
  static final DateFormat _timeFormat = DateFormat('hh:mm a');

  /// Resolves the concrete [DateTimeRange] for a given preset.
  static DateTimeRange? resolveDateRange(String preset, {DateTimeRange? customRange, DateTime? now}) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);

    switch (preset) {
      case 'today':
        return DateTimeRange(
          start: today,
          end: DateTime(current.year, current.month, current.day, 23, 59, 59, 999),
        );
      case 'this_week':
        // Monday as first day of week
        final daysFromMonday = (today.weekday - DateTime.monday) % 7;
        final monday = today.subtract(Duration(days: daysFromMonday));
        final sunday = monday.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59, milliseconds: 999));
        return DateTimeRange(start: monday, end: sunday);
      case 'last_week':
        final daysFromMonday = (today.weekday - DateTime.monday) % 7;
        final lastMonday = today.subtract(Duration(days: daysFromMonday + 7));
        final lastSunday = lastMonday.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59, milliseconds: 999));
        return DateTimeRange(start: lastMonday, end: lastSunday);
      case 'this_month':
        final startOfMonth = DateTime(current.year, current.month, 1);
        final nextMonth = current.month == 12 ? DateTime(current.year + 1, 1, 1) : DateTime(current.year, current.month + 1, 1);
        final endOfMonth = nextMonth.subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: startOfMonth, end: endOfMonth);
      case 'last_month':
        final prevYear = current.month == 1 ? current.year - 1 : current.year;
        final prevMonth = current.month == 1 ? 12 : current.month - 1;
        final startOfLastMonth = DateTime(prevYear, prevMonth, 1);
        final startOfThisMonth = DateTime(current.year, current.month, 1);
        final endOfLastMonth = startOfThisMonth.subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: startOfLastMonth, end: endOfLastMonth);
      case 'custom':
        return customRange;
      case 'all':
      default:
        return null;
    }
  }

  /// Builds a human-readable description of the reporting period.
  static String formatPeriodLabel(String preset, {DateTimeRange? range}) {
    if (preset == 'all' || (range == null && preset != 'today')) {
      return 'All Recorded History';
    }
    if (preset == 'today' && range != null) {
      return 'Today (${_dateFormat.format(range.start)})';
    }
    if (preset == 'this_week' && range != null) {
      return 'This Week (${_dateFormat.format(range.start)} – ${_dateFormat.format(range.end)})';
    }
    if (preset == 'last_week' && range != null) {
      return 'Last Week (${_dateFormat.format(range.start)} – ${_dateFormat.format(range.end)})';
    }
    if (preset == 'this_month' && range != null) {
      return '${DateFormat('MMMM yyyy').format(range.start)} (This Month)';
    }
    if (preset == 'last_month' && range != null) {
      return '${DateFormat('MMMM yyyy').format(range.start)} (Last Month)';
    }
    if (range != null) {
      return '${_dateFormat.format(range.start)} – ${_dateFormat.format(range.end)}';
    }
    return 'Selected Period';
  }

  /// Generates the PDF document byte array for printing or saving.
  static Future<Uint8List> generateReportPdf({
    required String facilityName,
    required String midwifeName,
    required String periodLabel,
    required List<InventoryTransactionRecord> transactions,
    String categoryFilter = 'all',
  }) async {
    final pdf = pw.Document(
      title: 'InaAgapay Inventory Report - $facilityName',
      author: 'InaAgapay MCHIS',
    );

    // Compute summary KPIs
    final totalMovements = transactions.length;
    int dispensedDoses = 0;
    int replenishedUnits = 0;
    int unusableLossDoses = 0;

    for (final t in transactions) {
      final type = t.transactionType.toLowerCase();
      if (type == 'dispense' || t.isAdministration) {
        dispensedDoses += t.dosesMoved;
      } else if (type == 'receipt' || (type == 'transfer' && (t.doseQuantity ?? t.quantity) > 0)) {
        replenishedUnits += t.quantity.abs();
      } else if (type == 'expiry_disposal' || type == 'discard') {
        unusableLossDoses += t.dosesMoved;
      }
    }

    final nowStr = _dateTimeFormat.format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Republic of the Philippines | Department of Health',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'RURAL HEALTH UNIT & BARANGAY HEALTH CENTER INVENTORY LEDGER',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blueGrey900,
                        ),
                      ),
                      pw.Text(
                        'Facility: $facilityName',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.pink700,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          'OFFICIAL AUDIT REPORT',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Generated: $nowStr',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 6),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'InaAgapay Maternal & Child Health Information System | Immutable Stock Traceability Ledger',
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // Metadata & Executive Summary Row
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Report Info Box
                pw.Expanded(
                  flex: 5,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildMetaRow('Reporting Period:', periodLabel),
                        _buildMetaRow('Category Scope:', categoryFilter.toUpperCase()),
                        _buildMetaRow('Prepared By:', '$midwifeName (Midwife-in-Charge)'),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                // Executive KPI Cards
                pw.Expanded(
                  flex: 6,
                  child: pw.Row(
                    children: [
                      _buildKpiCard('TOTAL MOVEMENTS', '$totalMovements', PdfColors.blueGrey800, PdfColors.grey100),
                      pw.SizedBox(width: 6),
                      _buildKpiCard('DISPENSED DOSES', '$dispensedDoses', PdfColors.pink800, PdfColors.pink50),
                      pw.SizedBox(width: 6),
                      _buildKpiCard('REPLENISHED UNITS', '+$replenishedUnits', PdfColors.green800, PdfColors.green50),
                      pw.SizedBox(width: 6),
                      _buildKpiCard('LOSS / EXPIRED', '-$unusableLossDoses', PdfColors.red800, PdfColors.red50),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // Movements Table
            if (transactions.isEmpty)
              pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.all(32),
                child: pw.Text(
                  'No inventory movements recorded for the selected period and criteria.',
                  style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
                ),
              )
            else
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(85), // Timestamp
                  1: const pw.FlexColumnWidth(2.2), // Item & Batch
                  2: const pw.FlexColumnWidth(1.6), // Movement Type
                  3: const pw.FixedColumnWidth(65), // Delta
                  4: const pw.FixedColumnWidth(85), // Balance After
                  5: const pw.FixedColumnWidth(65), // Patient / Ref
                  6: const pw.FlexColumnWidth(1.5), // Performed By
                  7: const pw.FlexColumnWidth(2.0), // Notes / Reference
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
                    children: [
                      _buildTableHeaderCell('DATE & TIME'),
                      _buildTableHeaderCell('ITEM & BATCH'),
                      _buildTableHeaderCell('MOVEMENT TYPE'),
                      _buildTableHeaderCell('DELTA', align: pw.TextAlign.right),
                      _buildTableHeaderCell('BALANCE AFTER', align: pw.TextAlign.right),
                      _buildTableHeaderCell('PATIENT'),
                      _buildTableHeaderCell('PERFORMED BY'),
                      _buildTableHeaderCell('REFERENCE / NOTES'),
                    ],
                  ),
                  // Table Rows
                  ...transactions.map((t) {
                    final isPositive = (t.doseQuantity ?? t.quantity) > 0;
                    final deltaStr = _formatDelta(t);
                    final balanceStr = _formatBalance(t);

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: t.transactionId % 2 == 0 ? PdfColors.white : PdfColors.grey50,
                      ),
                      children: [
                        _buildTableCell('${_dateFormat.format(t.loggedAt)}\n${_timeFormat.format(t.loggedAt)}', fontSize: 7.5),
                        _buildTableCell('${t.itemName}\nBatch: ${t.batchNumber}', isBold: true, fontSize: 8),
                        _buildTableCell(_formatMovementType(t), fontSize: 8),
                        _buildTableCell(
                          deltaStr,
                          align: pw.TextAlign.right,
                          color: isPositive ? PdfColors.green800 : PdfColors.pink800,
                          isBold: true,
                          fontSize: 8.5,
                        ),
                        _buildTableCell(balanceStr, align: pw.TextAlign.right, fontSize: 8),
                        _buildTableCell(t.hasPatient ? (t.patientLabel ?? '-') : '-', fontSize: 8),
                        _buildTableCell('${t.performedByName ?? "Staff"}\n(${_formatRole(t.performedByRole)})', fontSize: 7.5),
                        _buildTableCell(_formatNotes(t), fontSize: 7.5),
                      ],
                    );
                  }),
                ],
              ),

            pw.SizedBox(height: 24),

            // Sign-off / Certification Section
            pw.Container(
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Prepared & Certified Correct:', style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800)),
                        pw.SizedBox(height: 28),
                        pw.Container(
                          width: 200,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 1)),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.SizedBox(height: 3),
                              pw.Text(midwifeName.toUpperCase(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              pw.Text('Midwife-in-Charge / Health Center Officer', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Verified & Received by:', style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800)),
                        pw.SizedBox(height: 28),
                        pw.Container(
                          width: 220,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 1)),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.SizedBox(height: 3),
                              pw.Text('MUNICIPAL HEALTH OFFICER / SUPERVISOR', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              pw.Text('Rural Health Unit (RHU)', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Opens the system print/save preview dialog.
  static Future<void> previewAndPrintReport({
    required BuildContext context,
    required String facilityName,
    required String midwifeName,
    required String periodLabel,
    required List<InventoryTransactionRecord> transactions,
    String categoryFilter = 'all',
  }) async {
    final pdfBytes = await generateReportPdf(
      facilityName: facilityName,
      midwifeName: midwifeName,
      periodLabel: periodLabel,
      transactions: transactions,
      categoryFilter: categoryFilter,
    );

    final cleanFileName = 'inaagapay_inventory_report_${DateTime.now().millisecondsSinceEpoch}.pdf';

    await Printing.layoutPdf(
      name: cleanFileName,
      onLayout: (PdfPageFormat format) async => pdfBytes,
    );
  }

  // --- Helper methods for PDF formatting ---

  static pw.Widget _buildMetaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 95,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildKpiCard(String label, String value, PdfColor textColor, PdfColor bgColor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: pw.BoxDecoration(
          color: bgColor,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: textColor.shade(0.3)),
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: textColor),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              label,
              maxLines: 1,
              style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildTableHeaderCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor color = PdfColors.black,
    bool isBold = false,
    double fontSize = 8,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  static String _formatDelta(InventoryTransactionRecord t) {
    final doses = t.dosesMoved;
    final qty = t.quantity;
    final isPos = (t.doseQuantity ?? qty) > 0;
    final sign = isPos ? '+' : '-';

    if (t.isAdministration) {
      return '$sign$doses dose${doses == 1 ? '' : 's'}';
    }
    if (doses > 0 && t.dosesPerUnit > 1) {
      return '$sign$doses dose${doses == 1 ? '' : 's'}';
    }
    return '$sign${qty.abs()} ${t.unit}${qty.abs() == 1 ? '' : 's'}';
  }

  static String _formatBalance(InventoryTransactionRecord t) {
    final remUnits = t.resultingQuantityRemaining;
    final remDoses = t.resultingOpenVialDoses;
    if (remUnits == null && remDoses == null) return '-';

    final parts = <String>[];
    if (remUnits != null) {
      parts.add('$remUnits ${t.unit}${remUnits == 1 ? '' : 's'}');
    }
    if (remDoses != null && remDoses > 0) {
      parts.add('($remDoses open dose${remDoses == 1 ? '' : 's'})');
    }
    return parts.join(' ');
  }

  static String _formatMovementType(InventoryTransactionRecord t) {
    final type = t.transactionType.toLowerCase();
    switch (type) {
      case 'dispense':
        return t.isAdministration ? 'Patient Dispense' : 'General Dispense';
      case 'receipt':
        return 'Stock Replenishment';
      case 'expiry_disposal':
        return 'Expired Write-off';
      case 'discard':
        return 'Open Vial Discard';
      case 'transfer':
        return (t.doseQuantity ?? t.quantity) > 0 ? 'Inbound Transfer' : 'Outbound Transfer';
      case 'adjustment':
        return 'Stock Adjustment';
      default:
        return type.toUpperCase();
    }
  }

  static String _formatRole(String? role) {
    if (role == null || role.isEmpty) return 'Staff';
    final clean = role.replaceAll('_', ' ');
    return clean[0].toUpperCase() + clean.substring(1);
  }

  static String _formatNotes(InventoryTransactionRecord t) {
    final parts = <String>[];
    if (t.referenceType.isNotEmpty && t.referenceType != '-' && t.referenceType != '—') parts.add(t.referenceType);
    if (t.notes.isNotEmpty) parts.add(t.notes);
    if (parts.isEmpty) return '-';
    return parts.join(' | ');
  }
}
