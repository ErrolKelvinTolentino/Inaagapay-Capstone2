// lib/services/td_record_export.dart
//
// A mother's tetanus-diphtheria record as a document: her protection status
// and all five doses of the DOH series, given or still to come — the same
// thing her paper Td card carries, for filing, referral, or a mother who
// transfers to another health center.

import 'package:intl/intl.dart';

import 'maternal_td_service.dart';
import 'report_export_service.dart';

class TdRecordExport {
  const TdRecordExport._();

  static final DateFormat _day = DateFormat('MMM d, yyyy');

  static String sourceLabel(String source) {
    switch (source) {
      case 'bhc':
        return 'Given at the health center';
      case 'outside':
        return 'Given at another facility';
      case 'historical_record':
        return 'From her vaccination card';
      default:
        return source.replaceAll('_', ' ');
    }
  }

  /// What comes next, in one line.
  static String nextStep(MaternalTdStatus status) {
    final next = status.nextDoseKey;
    switch (status.nextAction) {
      case TdNextAction.complete:
        return 'Series complete (fully immunized)';
      case TdNextAction.eligibleNow:
        return '$next is due now';
      case TdNextAction.waiting:
        final on = status.nextEligibleDate;
        return on == null ? '$next' : '$next from ${_day.format(on)}';
      case TdNextAction.missingPrevious:
        return '$next, after the ${status.blockingDoseKey} date is recorded';
    }
  }

  static ReportDocument document({
    required MaternalTdStatus status,
    required String motherName,
    String? patientNumber,
    required String facilityName,
    required String preparedBy,
    DateTime? now,
  }) {
    final asOf = now ?? DateTime.now();
    final until = status.protectionUntil;

    return ReportDocument(
      title: 'Tetanus-Diphtheria (Td) Vaccination Record',
      facilityName: facilityName,
      periodLabel: 'As of ${_day.format(asOf)}',
      periodCaption: 'Record',
      preparedBy: preparedBy,
      generatedAt: asOf,
      landscape: true,
      blocks: [
        ReportBlock(
          title: 'Patient',
          columns: const ['Field', 'Value'],
          columnFlex: const [1, 3],
          showRowCount: false,
          rows: [
            ['Name', motherName],
            if ((patientNumber ?? '').trim().isNotEmpty)
              ['Patient number', patientNumber!.trim()],
          ],
        ),
        ReportBlock(
          title: 'Protection status',
          columns: const ['Measure', 'Status'],
          columnFlex: const [1, 3],
          showRowCount: false,
          rows: [
            ['Doses recorded', '${status.completedCount} of 5'],
            ['Baby protected at birth', status.isProtectedAtBirth ? 'Yes' : 'No'],
            ['Fully immunized (Td5)', status.isFim ? 'Yes' : 'No'],
            if (until != null) ['Protected until', until],
            ['Next dose', nextStep(status)],
          ],
        ),
        ReportBlock(
          title: 'Doses',
          columns: const [
            'Dose', 'Date given', 'Where given', 'Source',
            'Protected until', 'Next dose due', 'Remarks',
          ],
          columnFlex: const [1.3, 1.0, 1.6, 1.4, 1.0, 1.0, 2.2],
          showRowCount: false,
          rows: [
            for (final def in MaternalTdService.doseDefs)
              () {
                final r = status.recordFor(def.key);
                if (r == null) {
                  return <Object?>[
                    def.title,
                    'Not yet given',
                    '',
                    '',
                    null,
                    null,
                    'When: ${def.timing}',
                  ];
                }
                return <Object?>[
                  def.title,
                  r.date ?? 'Date not recorded',
                  r.facilityName,
                  sourceLabel(r.source),
                  r.protectionUntil,
                  r.nextDueDate,
                  r.remarks,
                ];
              }(),
          ],
          notes: [
            'DOH schedule: '
                '${MaternalTdService.doseDefs.map((d) => '${d.key}: ${d.minIntervalLabel}').join('; ')}.',
          ],
        ),
      ],
    );
  }
}
