// lib/services/immunization_schedule.dart
//
// The single place immunization timing is judged.
//
// This exists because the rule was previously not implemented anywhere: the
// "On Time" badge on the child profile and in the mother's app was a hardcoded
// literal, so every dose ever recorded was labelled on time — including one
// given ten months late. A comment on the mother-side version showed the
// reasoning slip plainly:
//
//     // All records in the list are already given
//     // (since they're from immunization_record table)
//     return StatusIndicatorType.onTime;
//
// Every record in that table was given; that is what makes it a record.
// Whether it was *timely* is a different question, and it is the one the badge
// claims to answer.

import '../widgets/status_indicator.dart';

class ImmunizationSchedule {
  /// How late a dose must be before it counts as late rather than on time.
  ///
  /// Four weeks is the minimum interval between doses in the EPI primary
  /// series, so falling more than one interval behind means a missed visit
  /// rather than a late arrival. Shared with the Add Immunization picker so a
  /// dose cannot read "9 months late" on one screen and "On Time" on another.
  static const double lateAfterMonths = 4 / 4.345;

  /// Beyond this, "late" understates it.
  static const double overdueAfterMonths = 3;

  static const double _daysPerMonth = 30.44;

  /// How timely a *recorded* dose was, judged against the age it was scheduled
  /// for and the date it was actually given.
  ///
  /// Returns null when it cannot be judged — no birthdate, or no date on the
  /// record. A missing input is not evidence of timeliness, and defaulting to
  /// "on time" is what produced the original bug.
  static StatusIndicatorType? timelinessOf({
    required DateTime? birthdate,
    required DateTime? givenOn,
    required double? scheduledAtMonths,
  }) {
    if (birthdate == null || givenOn == null || scheduledAtMonths == null) {
      return null;
    }

    final ageAtDoseMonths =
        givenOn.difference(birthdate).inDays / _daysPerMonth;
    final monthsLate = ageAtDoseMonths - scheduledAtMonths;

    if (monthsLate > overdueAfterMonths) return StatusIndicatorType.overdue;
    if (monthsLate > lateAfterMonths) return StatusIndicatorType.late;
    return StatusIndicatorType.onTime;
  }

  /// Same judgement, straight from a joined `immunization_records` row.
  ///
  /// Expects the row to embed its vaccine as `vaccine`, which is how every
  /// screen already queries it.
  static StatusIndicatorType? timelinessOfRecord(
    Map<String, dynamic> record, {
    required DateTime? birthdate,
  }) {
    final vaccine = record['vaccine'] as Map<String, dynamic>?;
    final givenOnRaw = record['vaccination_date']?.toString();

    return timelinessOf(
      birthdate: birthdate,
      givenOn: givenOnRaw == null ? null : DateTime.tryParse(givenOnRaw),
      scheduledAtMonths:
          (vaccine?['recommended_age_months'] as num?)?.toDouble(),
    );
  }

  /// How far past its scheduled age a dose was given, in plain words.
  /// Empty when it was on time or cannot be judged.
  static String describeDelay({
    required DateTime? birthdate,
    required DateTime? givenOn,
    required double? scheduledAtMonths,
  }) {
    if (birthdate == null || givenOn == null || scheduledAtMonths == null) {
      return '';
    }

    final ageAtDoseMonths =
        givenOn.difference(birthdate).inDays / _daysPerMonth;
    final monthsLate = ageAtDoseMonths - scheduledAtMonths;
    if (monthsLate <= lateAfterMonths) return '';

    final weeksLate = (monthsLate * 4.345).round();
    if (weeksLate < 8) return '$weeksLate weeks late';

    final months = monthsLate.floor();
    return months == 1 ? '1 month late' : '$months months late';
  }
}
