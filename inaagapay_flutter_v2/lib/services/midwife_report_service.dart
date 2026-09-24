// lib/services/midwife_report_service.dart
//
// The records and statistics a midwife exports, as [ReportDocument]s scoped to
// her own health centre. Everything here reads; nothing writes.
//
// Record reports cover the chosen period. Statistics reports are a snapshot of
// the caseload as it stands today, because that is what the dashboard shows
// and what the figures mean — "three of eight children behind schedule" is a
// fact about now, not about last March.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/midwife_analytics.dart';
import '../screens/midwife_inventory/inventory_models.dart';
import '../screens/midwife_inventory/midwife_inventory_report_service.dart';
import 'auth_storage.dart';
import 'midwife_analytics_service.dart';
import 'report_export_service.dart';
import 'supabase_service.dart';

/// Who is exporting, and for which centre.
class MidwifeReportScope {
  const MidwifeReportScope({
    required this.bhcId,
    required this.facilityName,
    required this.preparedBy,
  });

  final int bhcId;
  final String facilityName;
  final String preparedBy;
}

class MidwifeReportService {
  const MidwifeReportService._();

  static final DateFormat _monthYear = DateFormat('MMMM yyyy');
  static final DateFormat _day = DateFormat('MMM d, yyyy');

  static SupabaseClient get _db => SupabaseService.client;

  static Future<MidwifeReportScope> resolveScope() async {
    final accountId = await AuthStorage.getUserId();
    if (accountId == null) throw Exception('You are not signed in.');

    final ctx = await SupabaseService.getMidwifeContext(accountId);
    final bhcId = ctx['assigned_bhc_id'] as int?;
    if (ctx['success'] != true || bhcId == null) {
      throw Exception(ctx['message'] ?? 'Could not confirm your health center.');
    }

    String preparedBy = 'Midwife-in-Charge';
    try {
      final account = await _db
          .from('accounts')
          .select('first_name, last_name')
          .eq('account_id', accountId)
          .maybeSingle();
      final name = [account?['first_name'], account?['last_name']]
          .whereType<Object>()
          .map((part) => part.toString().trim())
          .where((part) => part.isNotEmpty)
          .join(' ');
      if (name.isNotEmpty) preparedBy = name;
    } catch (_) {}

    return MidwifeReportScope(
      bhcId: bhcId,
      facilityName: ctx['bhc_name']?.toString() ?? 'Barangay Health Center',
      preparedBy: preparedBy,
    );
  }

  /// "September 2026", or "Sep 1, 2026 - Sep 24, 2026" for anything else.
  static String periodLabel(DateTimeRange range) {
    final start = range.start;
    final end = range.end;
    final lastOfMonth = DateTime(start.year, start.month + 1, 0);
    if (start.day == 1 &&
        end.year == start.year &&
        end.month == start.month &&
        end.day == lastOfMonth.day) {
      return _monthYear.format(start);
    }
    return '${_day.format(start)} - ${_day.format(end)}';
  }

  // ==========================================================================
  // CASELOAD
  // ==========================================================================

  static Future<_Caseload> _caseload(int bhcId) async {
    final mothers = await _db
        .from('mothers')
        .select('mother_id, accounts!inner (first_name, last_name)')
        .eq('assigned_bhc_id', bhcId);

    final names = <int, String>{};
    for (final row in mothers) {
      final id = (row['mother_id'] as num?)?.toInt();
      if (id == null) continue;
      final account = _first(row['accounts']);
      names[id] = [account?['last_name'], account?['first_name']]
          .whereType<Object>()
          .map((part) => part.toString().trim())
          .where((part) => part.isNotEmpty)
          .join(', ');
    }

    final pregnancyMother = <int, int>{};
    if (names.isNotEmpty) {
      final pregnancies = await _db
          .from('pregnancies')
          .select('pregnancy_id, mother_id')
          .inFilter('mother_id', names.keys.toList());
      for (final row in pregnancies) {
        final pid = (row['pregnancy_id'] as num?)?.toInt();
        final mid = (row['mother_id'] as num?)?.toInt();
        if (pid != null && mid != null) pregnancyMother[pid] = mid;
      }
    }
    return _Caseload(names, pregnancyMother);
  }

  // ==========================================================================
  // RECORD REPORTS
  // ==========================================================================

  static Future<ReportDocument> checkups(
      MidwifeReportScope scope, DateTimeRange range) async {
    final caseload = await _caseload(scope.bhcId);
    final rows = caseload.pregnancyIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('clinical_encounters')
            .select('''
              encounter_datetime, mother_id, pregnancy_id,
              age_of_gestation_weeks, age_of_gestation_days, midwife_notes,
              checkup:prenatal_checkups (
                checkup_weight, blood_pressure_systolic,
                blood_pressure_diastolic, fetal_heart_beat, fetal_heart_tone,
                fetal_position, edema, td_vaccine_dose, next_schedule
              )
            ''')
            .inFilter('pregnancy_id', caseload.pregnancyIds)
            .eq('encounter_type', 'checkup')
            .gte('encounter_datetime', _startIso(range))
            .lt('encounter_datetime', _endExclusiveIso(range))
            .order('encounter_datetime');

    return _single(
      scope,
      range,
      title: 'Prenatal Checkup Records',
      block: checkupBlock(rows, caseload.motherName),
    );
  }

  @visibleForTesting
  static ReportBlock checkupBlock(
    List<Map<String, dynamic>> rows,
    String Function(Map<String, dynamic> row) motherName,
  ) {
    return ReportBlock(
      title: 'Prenatal checkups',
      columns: const [
        'Date', 'Mother', 'AOG', 'Weight (kg)', 'BP (mmHg)', 'FHR (bpm)',
        'Heart tone', 'Position', 'Edema', 'Td dose', 'Next visit', 'Notes',
      ],
      columnFlex: const [1.1, 1.8, 0.8, 0.8, 0.9, 0.7, 0.9, 0.9, 0.7, 0.7, 1.0, 2.2],
      numericColumns: const {3, 5},
      rows: [
        for (final row in rows)
          () {
            final c = _first(row['checkup']) ?? const {};
            final sys = c['blood_pressure_systolic'];
            final dia = c['blood_pressure_diastolic'];
            return <Object?>[
              _date(row['encounter_datetime']),
              motherName(row),
              _aog(row['age_of_gestation_weeks'], row['age_of_gestation_days']),
              _num(c['checkup_weight']),
              sys == null || dia == null ? null : '$sys/$dia',
              _num(c['fetal_heart_beat']),
              _label(c['fetal_heart_tone']),
              _label(c['fetal_position']),
              _label(c['edema']),
              c['td_vaccine_dose'],
              _date(c['next_schedule']),
              row['midwife_notes'],
            ];
          }(),
      ],
    );
  }

  static Future<ReportDocument> ultrasounds(
      MidwifeReportScope scope, DateTimeRange range) async {
    final caseload = await _caseload(scope.bhcId);
    final rows = caseload.pregnancyIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('ultrasounds')
            .select('ultrasound_date, pregnancy_id, ultrasound_location, '
                'findings_summary, monitoring_classification, '
                'health_worker_name, health_worker_institution, '
                'health_worker_profession')
            .inFilter('pregnancy_id', caseload.pregnancyIds)
            .gte('ultrasound_date', _isoDate(range.start))
            .lte('ultrasound_date', _isoDate(range.end))
            .order('ultrasound_date');

    return _single(
      scope,
      range,
      title: 'Ultrasound Records',
      block: ReportBlock(
        title: 'Ultrasounds',
        columns: const [
          'Date', 'Mother', 'Where done', 'Findings', 'Classification',
          'Health worker', 'Institution',
        ],
        columnFlex: const [1.0, 1.7, 1.4, 3.2, 1.1, 1.4, 1.5],
        rows: [
          for (final row in rows)
            [
              _date(row['ultrasound_date']),
              caseload.motherName(row),
              row['ultrasound_location'],
              row['findings_summary'],
              _label(row['monitoring_classification']),
              _withRole(row['health_worker_name'], row['health_worker_profession']),
              row['health_worker_institution'],
            ],
        ],
      ),
    );
  }

  static const _labColumns =
      'encounter_id, pregnancy_id, lab_test_type, hemoglobin_g_dl, '
      'hematocrit_pct, wbc_count, platelet_count, urinalysis_protein, '
      'urinalysis_glucose, hepatitis_b_status, lab_test_location, created_at';
  static const _glucoseColumns =
      ', fasting_glucose_mg_dl, glucose_1hr_mg_dl, glucose_2hr_mg_dl';

  static Future<ReportDocument> labTests(
      MidwifeReportScope scope, DateTimeRange range) async {
    final caseload = await _caseload(scope.bhcId);
    var rows = const <Map<String, dynamic>>[];
    final encounterDates = <int, DateTime>{};
    bool hasGlucose = true;

    if (caseload.pregnancyIds.isNotEmpty) {
      // The lab date lives on the parent encounter; created_at is only when
      // the row was typed in.
      final encounters = await _db
          .from('clinical_encounters')
          .select('encounter_id, encounter_datetime')
          .inFilter('pregnancy_id', caseload.pregnancyIds)
          .eq('encounter_type', 'lab_test')
          .gte('encounter_datetime', _startIso(range))
          .lt('encounter_datetime', _endExclusiveIso(range));
      for (final e in encounters) {
        final id = (e['encounter_id'] as num?)?.toInt();
        final when = _date(e['encounter_datetime']);
        if (id != null && when != null) encounterDates[id] = when;
      }

      if (encounterDates.isNotEmpty) {
        try {
          rows = await _db
              .from('lab_tests')
              .select(_labColumns + _glucoseColumns)
              .inFilter('encounter_id', encounterDates.keys.toList());
        } on PostgrestException catch (e) {
          // Glucose columns arrive with 20260812_gdm_glucose_values.sql.
          if (e.code != '42703') rethrow;
          hasGlucose = false;
          rows = await _db
              .from('lab_tests')
              .select(_labColumns)
              .inFilter('encounter_id', encounterDates.keys.toList());
        }
      }
    }

    DateTime? when(Map<String, dynamic> row) =>
        encounterDates[(row['encounter_id'] as num?)?.toInt()] ??
        _date(row['created_at']);
    final sorted = [...rows]..sort((a, b) =>
        (when(a) ?? DateTime(0)).compareTo(when(b) ?? DateTime(0)));

    return _single(
      scope,
      range,
      title: 'Laboratory Test Records',
      block: ReportBlock(
        title: 'Laboratory tests',
        columns: [
          'Date', 'Mother', 'Test', 'Hb (g/dL)', 'Hct (%)', 'WBC', 'Platelets',
          'Urine protein', 'Urine glucose', 'HBsAg',
          if (hasGlucose) ...['FBS (mg/dL)', 'OGTT 1h', 'OGTT 2h'],
          'Where done',
        ],
        numericColumns: {3, 4, 5, 6, if (hasGlucose) ...{10, 11, 12}},
        rows: [
          for (final row in sorted)
            [
              when(row),
              caseload.motherName(row),
              _label(row['lab_test_type']),
              _num(row['hemoglobin_g_dl']),
              _num(row['hematocrit_pct']),
              _num(row['wbc_count']),
              _num(row['platelet_count']),
              _label(row['urinalysis_protein']),
              _label(row['urinalysis_glucose']),
              _label(row['hepatitis_b_status']),
              if (hasGlucose) ...[
                _num(row['fasting_glucose_mg_dl']),
                _num(row['glucose_1hr_mg_dl']),
                _num(row['glucose_2hr_mg_dl']),
              ],
              row['lab_test_location'],
            ],
        ],
        notes: hasGlucose
            ? const []
            : const [
                'Glucose values are not shown: the database update that adds '
                    'them (20260812) has not been run.',
              ],
      ),
    );
  }

  static Future<ReportDocument> tdVaccinations(
      MidwifeReportScope scope, DateTimeRange range) async {
    final caseload = await _caseload(scope.bhcId);
    final rows = caseload.names.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('maternal_td_records')
            .select('mother_id, dose_number, vaccination_date, facility_name, '
                'source, protection_until, next_due_date, inventory_deducted, '
                'remarks')
            .inFilter('mother_id', caseload.names.keys.toList())
            .gte('vaccination_date', _isoDate(range.start))
            .lte('vaccination_date', _isoDate(range.end))
            .order('vaccination_date');

    final byDose = <String, int>{};
    for (final row in rows) {
      final dose = row['dose_number']?.toString() ?? '?';
      byDose[dose] = (byDose[dose] ?? 0) + 1;
    }
    final doseSummary = (byDose.keys.toList()..sort())
        .map((dose) => '$dose: ${byDose[dose]}')
        .join(', ');

    return _single(
      scope,
      range,
      title: 'Tetanus-Diphtheria (Td) Vaccination Record',
      landscape: true,
      block: ReportBlock(
        title: 'Td doses given to mothers',
        lead: rows.isEmpty
            ? const []
            : ['${rows.length} ${rows.length == 1 ? 'dose' : 'doses'} recorded'
                '${doseSummary.isEmpty ? '' : ' ($doseSummary)'}.'],
        columns: const [
          'Date', 'Mother', 'Dose', 'Where given', 'Source',
          'Protected until', 'Next dose due', 'Stock deducted', 'Remarks',
        ],
        columnFlex: const [1.0, 1.8, 0.6, 1.5, 0.9, 1.0, 1.0, 0.8, 2.0],
        rows: [
          for (final row in rows)
            [
              _date(row['vaccination_date']),
              caseload.names[(row['mother_id'] as num?)?.toInt()] ?? '',
              row['dose_number'],
              row['facility_name'],
              _label(row['source']),
              _date(row['protection_until']),
              _date(row['next_due_date']),
              row['inventory_deducted'] == true,
              row['remarks'],
            ],
        ],
      ),
    );
  }

  // ==========================================================================
  // STATISTICS
  // ==========================================================================

  static Future<ReportDocument> statistics(
    MidwifeReportScope scope, {
    required bool mothers,
  }) async {
    final analytics = await MidwifeAnalyticsService.load(bhcId: scope.bhcId);
    return statisticsDocument(
      mothers ? analytics.mothers : analytics.children,
      title: mothers ? 'Mother Statistics' : 'Children Statistics',
      facilityName: scope.facilityName,
      preparedBy: scope.preparedBy,
    );
  }

  /// A dashboard section as a report: each card becomes a block with its
  /// headline and reading above, its categories as rows, its caveat below.
  static ReportDocument statisticsDocument(
    AnalyticsSection section, {
    required String title,
    required String facilityName,
    required String preparedBy,
    DateTime? now,
  }) {
    final asOf = now ?? DateTime.now();
    return ReportDocument(
      title: title,
      facilityName: facilityName,
      periodLabel: 'As of ${_day.format(asOf)}',
      preparedBy: preparedBy,
      generatedAt: asOf,
      landscape: false,
      blocks: [for (final metric in section.metrics) metricBlock(metric)],
    );
  }

  static ReportBlock metricBlock(AnalyticsMetric metric) {
    final title = metric.periodLabel == null
        ? metric.title
        : '${metric.title} (${metric.periodLabel})';

    if (!metric.hasData) {
      return ReportBlock(
        title: title,
        columns: const ['Category', 'Count', 'Share', 'Note'],
        rows: const [],
        emptyText: metric.emptyMessage ?? 'Nothing recorded yet.',
      );
    }

    final lead = <String>[];
    if (metric.headline != null) {
      lead.add([metric.headline, metric.headlineCaption]
          .whereType<String>()
          .join(' '));
    }
    if (metric.covered != null && metric.eligible != null) {
      final percent = metric.coveragePercent;
      lead.add('Coverage: ${metric.covered} of ${metric.eligible}'
          '${percent == null ? '' : ' ($percent%)'}.');
    }
    final comparison = metric.comparison;
    if (comparison != null) {
      lead.add('${comparison.previousLabel}: ${comparison.previousValue} '
          '${comparison.unit}; ${comparison.currentLabel}: '
          '${comparison.currentValue} ${comparison.unit}.');
    }
    final insight = metric.insight;
    if (insight != null) {
      lead.add('Reading: ${insight.text}');
      if (insight.evidence != null) lead.add(insight.evidence!);
    }
    final prescription = metric.prescription;
    if (prescription != null) lead.add('Suggested action: ${prescription.label}.');

    final total = metric.total;
    final covered = metric.covered;
    final eligible = metric.eligible;
    String share(int count, int of) =>
        of > 0 ? '${(count / of * 100).round()}%' : '-';

    final rows = <List<Object?>>[
      for (final band in metric.bands)
        [
          band.label,
          band.count,
          band.fraction != null
              ? '${(band.fraction! * 100).round()}%'
              : share(band.count, total),
          band.detail ?? (band.count > 0 ? _severityNote(band.severity) : ''),
        ],
    ];
    // A coverage card draws a meter, not categories; its two halves are the
    // rows.
    if (rows.isEmpty && covered != null && eligible != null) {
      rows.addAll([
        ['Covered', covered, share(covered, eligible), ''],
        ['Not yet covered', eligible - covered, share(eligible - covered, eligible),
            eligible > covered ? 'Needs action' : ''],
      ]);
    }

    return ReportBlock(
      title: title,
      lead: lead,
      columns: const ['Category', 'Count', 'Share', 'Note'],
      columnFlex: const [2.4, 0.8, 0.8, 2.6],
      numericColumns: const {1, 2},
      rows: rows,
      notes: [if (metric.footnote != null) metric.footnote!],
      emptyText: 'No categories to show.',
    );
  }

  static String _severityNote(AnalyticsSeverity severity) {
    switch (severity) {
      case AnalyticsSeverity.alert:
        return 'Needs action';
      case AnalyticsSeverity.watch:
        return 'Watch';
      case AnalyticsSeverity.good:
        return 'On target';
      case AnalyticsSeverity.unknown:
        return 'Not recorded';
      case AnalyticsSeverity.neutral:
        return '';
    }
  }

  // ==========================================================================
  // INVENTORY
  // ==========================================================================

  /// Stock on hand today, then every movement in the period — the same rows
  /// the printable inventory report lists, so the two formats agree.
  static ReportDocument inventoryDocument({
    required MidwifeReportScope scope,
    required DateTimeRange range,
    required List<FacilityInventoryRecord> inventory,
    required List<InventoryTransactionRecord> transactions,
  }) {
    final inPeriod = transactions
        .where((t) =>
            !t.loggedAt.isBefore(range.start) && !t.loggedAt.isAfter(range.end))
        .toList()
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

    int dispensed = 0, received = 0, lost = 0;
    for (final t in inPeriod) {
      final type = t.transactionType.toLowerCase();
      if (type == 'dispense' || t.isAdministration) {
        dispensed += t.dosesMoved;
      } else if (type == 'receipt' ||
          (type == 'transfer' && (t.doseQuantity ?? t.quantity) > 0)) {
        received += t.quantity.abs();
      } else if (type == 'expiry_disposal' || type == 'discard') {
        lost += t.dosesMoved;
      }
    }

    final stockRows = <List<Object?>>[];
    final items = [...inventory]
      ..sort((a, b) => a.catalog.name.compareTo(b.catalog.name));
    for (final item in items) {
      final usable = item.usableBatchesOn();
      if (usable.isEmpty) {
        stockRows.add([item.catalog.name, '-', 0, item.catalog.unit, null,
            item.catalog.minimumStock, 'Out of stock']);
        continue;
      }
      for (final batch in usable) {
        stockRows.add([
          item.catalog.name,
          batch.batchNumber,
          batch.quantityRemaining,
          item.catalog.unit,
          batch.expirationDate,
          item.catalog.minimumStock,
          item.quantity < item.catalog.minimumStock ? 'Below reorder level' : '',
        ]);
      }
    }

    return ReportDocument(
      title: 'Monthly Inventory Report',
      facilityName: scope.facilityName,
      periodLabel: periodLabel(range),
      preparedBy: scope.preparedBy,
      blocks: [
        ReportBlock(
          title: 'Summary for the period',
          columns: const ['Measure', 'Value'],
          numericColumns: const {1},
          columnFlex: const [3, 1],
          rows: [
            ['Stock movements recorded', inPeriod.length],
            ['Doses dispensed to patients', dispensed],
            ['Units received', received],
            ['Doses lost (expired or discarded)', lost],
          ],
        ),
        ReportBlock(
          title: 'Stock on hand today',
          columns: const [
            'Item', 'Batch', 'Quantity', 'Unit', 'Expires', 'Reorder level',
            'Status',
          ],
          columnFlex: const [2.2, 1.2, 0.8, 0.8, 1.0, 0.9, 1.3],
          numericColumns: const {2, 5},
          rows: stockRows,
          emptyText: 'No stock is recorded at this health center.',
        ),
        ReportBlock(
          title: 'Stock movements',
          columns: const [
            'Date & time', 'Item', 'Batch', 'Movement', 'Change',
            'Balance after', 'Performed by', 'Reference / notes',
          ],
          columnFlex: const [1.3, 1.6, 1.0, 1.3, 0.9, 1.2, 1.3, 2.4],
          rows: [
            for (final t in inPeriod)
              [
                DateFormat('yyyy-MM-dd HH:mm').format(t.loggedAt),
                t.itemName,
                t.batchNumber,
                MidwifeInventoryReportService.formatMovementType(t),
                MidwifeInventoryReportService.formatDelta(t),
                MidwifeInventoryReportService.formatBalance(t),
                t.performedByName ?? '',
                MidwifeInventoryReportService.formatNotes(t),
              ],
          ],
        ),
      ],
    );
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  static ReportDocument _single(
    MidwifeReportScope scope,
    DateTimeRange range, {
    required String title,
    required ReportBlock block,
    bool landscape = true,
  }) {
    return ReportDocument(
      title: title,
      facilityName: scope.facilityName,
      periodLabel: periodLabel(range),
      preparedBy: scope.preparedBy,
      landscape: landscape,
      blocks: [block],
    );
  }

  static Map<String, dynamic>? _first(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

  static num? _num(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }

  static String? _aog(Object? weeks, Object? days) {
    if (weeks == null) return null;
    final d = (days as num?)?.toInt() ?? 0;
    return d > 0 ? '${weeks}w ${d}d' : '${weeks}w';
  }

  /// "cephalic" -> "Cephalic", "not_done" -> "Not done".
  static String? _label(Object? value) {
    if (value == null) return null;
    final text = value.toString().replaceAll('_', ' ').trim();
    if (text.isEmpty) return null;
    return text[0].toUpperCase() + text.substring(1);
  }

  static String? _withRole(Object? name, Object? role) {
    final n = name?.toString().trim() ?? '';
    final r = role?.toString().trim() ?? '';
    if (n.isEmpty) return r.isEmpty ? null : r;
    return r.isEmpty ? n : '$n ($r)';
  }

  static String _isoDate(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value);

  // Local midnight, sent as UTC, so a checkup at 7 a.m. Manila time on the
  // first of the month is not read as the last day of the previous one.
  static String _startIso(DateTimeRange range) =>
      DateTime(range.start.year, range.start.month, range.start.day)
          .toUtc()
          .toIso8601String();

  static String _endExclusiveIso(DateTimeRange range) =>
      DateTime(range.end.year, range.end.month, range.end.day + 1)
          .toUtc()
          .toIso8601String();
}

class _Caseload {
  _Caseload(this.names, this.pregnancyMother);

  /// mother_id -> "Last, First"
  final Map<int, String> names;

  /// pregnancy_id -> mother_id
  final Map<int, int> pregnancyMother;

  List<int> get pregnancyIds => pregnancyMother.keys.toList();

  String motherName(Map<String, dynamic> row) {
    final motherId = (row['mother_id'] as num?)?.toInt() ??
        pregnancyMother[(row['pregnancy_id'] as num?)?.toInt()];
    return names[motherId] ?? '';
  }
}
