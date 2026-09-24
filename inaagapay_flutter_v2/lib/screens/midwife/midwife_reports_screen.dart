// lib/screens/midwife/midwife_reports_screen.dart
//
// Reports & Export: every record a midwife keeps, and the statistics the
// dashboard draws from them, as a PDF to print and file or an Excel workbook
// to hand on. One period picker drives the record reports; the statistics are
// a snapshot of today's caseload and say so.

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../services/export_file_saver.dart';
import '../../services/midwife_report_service.dart';
import '../../services/report_export_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/secondary_header.dart';
import '../midwife_inventory/inventory_repository.dart';

enum _Format { pdf, excel, print }

class _ReportDef {
  const _ReportDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.build,
    this.usesPeriod = true,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool usesPeriod;
  final Future<ReportDocument> Function(
      MidwifeReportScope scope, DateTimeRange range) build;
}

class MidwifeReportsScreen extends StatefulWidget {
  const MidwifeReportsScreen({super.key});

  @override
  State<MidwifeReportsScreen> createState() => _MidwifeReportsScreenState();
}

class _MidwifeReportsScreenState extends State<MidwifeReportsScreen> {
  late Future<MidwifeReportScope> _scope = MidwifeReportService.resolveScope();

  String _preset = 'this_month';
  late DateTimeRange _range = _rangeFor('this_month');
  String? _busy;

  static final _records = <_ReportDef>[
    _ReportDef(
      id: 'checkups',
      title: 'Prenatal checkups',
      subtitle: 'Weight, blood pressure, fetal heart, Td dose, next visit',
      icon: Icons.monitor_heart_outlined,
      build: MidwifeReportService.checkups,
    ),
    _ReportDef(
      id: 'ultrasounds',
      title: 'Ultrasounds',
      subtitle: 'Findings, classification, where it was done',
      icon: Icons.graphic_eq_rounded,
      build: MidwifeReportService.ultrasounds,
    ),
    _ReportDef(
      id: 'labs',
      title: 'Laboratory tests',
      subtitle: 'Hemoglobin, urinalysis, HBsAg, glucose',
      icon: Icons.biotech_outlined,
      build: MidwifeReportService.labTests,
    ),
    _ReportDef(
      id: 'td',
      title: 'Td vaccinations',
      subtitle: 'Every tetanus-diphtheria dose given to mothers',
      icon: Icons.vaccines_outlined,
      build: MidwifeReportService.tdVaccinations,
    ),
  ];

  static final _statistics = <_ReportDef>[
    _ReportDef(
      id: 'mother-stats',
      title: 'Mother statistics',
      subtitle: 'Age, stage of pregnancy, risk, Td protection, supplements',
      icon: Icons.pregnant_woman_outlined,
      usesPeriod: false,
      build: (scope, _) =>
          MidwifeReportService.statistics(scope, mothers: true),
    ),
    _ReportDef(
      id: 'child-stats',
      title: 'Children statistics',
      subtitle: 'Growth, vaccination status, drives',
      icon: Icons.child_care_outlined,
      usesPeriod: false,
      build: (scope, _) =>
          MidwifeReportService.statistics(scope, mothers: false),
    ),
  ];

  static final _inventory = <_ReportDef>[
    _ReportDef(
      id: 'inventory',
      title: 'Monthly inventory',
      subtitle: 'Stock on hand, movements and losses for the period',
      icon: Icons.inventory_2_outlined,
      build: (scope, range) async {
        final repository = InventoryRepository();
        final context = await repository.resolveContext();
        final snapshot = await repository.loadSnapshot(context);
        return MidwifeReportService.inventoryDocument(
          scope: scope,
          range: range,
          inventory: snapshot.inventory,
          transactions: snapshot.transactions,
        );
      },
    ),
  ];

  static DateTimeRange _rangeFor(String preset, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    DateTime endOfMonth(int year, int month) => DateTime(year, month + 1, 0);
    switch (preset) {
      case 'last_month':
        final start = DateTime(day.year, day.month - 1, 1);
        return DateTimeRange(start: start, end: endOfMonth(start.year, start.month));
      case 'last_3_months':
        return DateTimeRange(
            start: DateTime(day.year, day.month - 2, 1),
            end: endOfMonth(day.year, day.month));
      case 'this_year':
        return DateTimeRange(
            start: DateTime(day.year, 1, 1), end: DateTime(day.year, 12, 31));
      case 'this_month':
      default:
        return DateTimeRange(
            start: DateTime(day.year, day.month, 1),
            end: endOfMonth(day.year, day.month));
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _preset = 'custom';
      _range = picked;
    });
  }

  Future<void> _export(_ReportDef report, _Format format) async {
    if (_busy != null) return;
    setState(() => _busy = '${report.id}:${format.name}');
    try {
      final scope = await _scope;
      final doc = await report.build(scope, _range);

      switch (format) {
        case _Format.print:
          final bytes = await ReportExportService.toPdf(doc);
          await Printing.layoutPdf(
            name: doc.fileName('pdf'),
            onLayout: (_) async => bytes,
          );
          return;
        case _Format.pdf:
          final bytes = await ReportExportService.toPdf(doc);
          final result = await ExportFileSaver.save(
            bytes: bytes,
            fileName: doc.fileName('pdf'),
            mimeType: ExportFileSaver.pdfMime,
          );
          _announce(result, 'PDF');
          return;
        case _Format.excel:
          final bytes = ReportExportService.toXlsx(doc);
          final result = await ExportFileSaver.save(
            bytes: bytes,
            fileName: doc.fileName('xlsx'),
            mimeType: ExportFileSaver.xlsxMime,
          );
          _announce(result, 'Excel file');
          return;
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      AppSnackbar.error(context, 'Could not create the report. $message');
      // A failed scope lookup is retried on the next tap rather than cached.
      _scope = MidwifeReportService.resolveScope();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _announce(ExportSaveResult result, String what) {
    if (!mounted || !result.saved) return;
    AppSnackbar.success(
      context,
      result.location == null ? '$what saved.' : '$what saved: ${result.location}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Reports & Export',
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<MidwifeReportScope>(
        future: _scope,
        builder: (context, snapshot) {
          final scope = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (snapshot.hasError)
                _Notice(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.error,
                  text: snapshot.error
                      .toString()
                      .replaceFirst('Exception: ', ''),
                  actionLabel: 'Try again',
                  onAction: () => setState(
                      () => _scope = MidwifeReportService.resolveScope()),
                )
              else
                _Notice(
                  icon: Icons.local_hospital_outlined,
                  color: AppColors.brandText,
                  text: scope == null
                      ? 'Finding your health center...'
                      : 'Reports cover ${scope.facilityName} only.',
                ),
              const SizedBox(height: 16),
              _sectionTitle('Period'),
              const SizedBox(height: 8),
              _periodPicker(),
              const SizedBox(height: 6),
              Text(
                MidwifeReportService.periodLabel(_range),
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Records'),
              for (final report in _records) _tile(report),
              const SizedBox(height: 12),
              _sectionTitle('Statistics'),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'A snapshot of today\'s caseload, the same figures as the '
                  'dashboard. The period above does not apply.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              for (final report in _statistics) _tile(report),
              const SizedBox(height: 12),
              _sectionTitle('Inventory'),
              for (final report in _inventory) _tile(report),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
      );

  Widget _periodPicker() {
    const presets = {
      'this_month': 'This month',
      'last_month': 'Last month',
      'last_3_months': 'Last 3 months',
      'this_year': 'This year',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in presets.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: _preset == entry.key,
            selectedColor: AppColors.brandPrimary.withValues(alpha: 0.16),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _preset == entry.key
                  ? AppColors.brandText
                  : AppColors.textPrimary,
            ),
            onSelected: (_) => setState(() {
              _preset = entry.key;
              _range = _rangeFor(entry.key);
            }),
          ),
        ChoiceChip(
          avatar: const Icon(Icons.date_range_rounded, size: 16),
          label: const Text('Custom'),
          selected: _preset == 'custom',
          selectedColor: AppColors.brandPrimary.withValues(alpha: 0.16),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _preset == 'custom'
                ? AppColors.brandText
                : AppColors.textPrimary,
          ),
          onSelected: (_) => _pickCustomRange(),
        ),
      ],
    );
  }

  Widget _tile(_ReportDef report) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.bgSecondary,
                  shape: BoxShape.circle,
                ),
                child: Icon(report.icon, size: 20, color: AppColors.brandText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      report.subtitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _button(report, _Format.pdf, 'PDF',
                    Icons.picture_as_pdf_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _button(report, _Format.excel, 'Excel',
                    Icons.table_chart_outlined),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Print or preview',
                onPressed: _busy == null
                    ? () => _export(report, _Format.print)
                    : null,
                icon: _busy == '${report.id}:print'
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined,
                        color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _button(
      _ReportDef report, _Format format, String label, IconData icon) {
    final busy = _busy == '${report.id}:${format.name}';
    return OutlinedButton.icon(
      onPressed: _busy == null ? () => _export(report, format) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brandText,
        side: const BorderSide(color: AppColors.brandPrimary),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
