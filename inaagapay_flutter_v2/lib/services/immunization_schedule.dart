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

/// Where a scheduled dose stands for a particular child, right now.
///
/// Shared by the Add Immunization picker and the roadmap so the same dose
/// cannot read "9 months late" on one screen and "Recommended" on another.
enum DoseStatus {
  given,
  pastDue,
  due,

  /// Old enough by age, but the previous dose was too recent. Giving it now
  /// would break the minimum interval, so it waits rather than being offered.
  dueSoon,

  notYetDue,

  /// Past the vaccine's upper age limit — should no longer be given at all.
  /// Only Rotavirus has such a limit in the DOH childhood schedule.
  noLongerGiven;

  String get label => switch (this) {
        DoseStatus.given => 'Given',
        DoseStatus.pastDue => 'Past due',
        DoseStatus.due => 'Due now',
        DoseStatus.dueSoon => 'Due soon',
        DoseStatus.notYetDue => 'Not yet due',
        DoseStatus.noLongerGiven => 'No longer given',
      };
}

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

  /// The scheduled age exactly as the DOH card prints it.
  ///
  /// The primary series runs in half months — 1½, 2½, 3½ — so rounding to
  /// whole months showed IPV at "4 months" when the card says 3½, putting
  /// three of the four primary visits on ages the midwife could not find on
  /// paper.
  static String formatScheduledAge(double? months) {
    if (months == null) return '';
    if (months == 0) return 'At birth';
    if (months == 12) return '1 year';

    final whole = months.floor();
    final hasHalf = (months - whole) >= 0.5;

    if (whole == 0) return '½ month';
    return hasHalf ? '$whole½ months' : '$whole months';
  }

  /// The earliest date this dose may be given.
  ///
  /// Two constraints, whichever falls later:
  ///   * the child must reach the scheduled age, and
  ///   * the minimum interval since the previous dose must have elapsed.
  ///
  /// The second is what makes catch-up work. After a late first dose the
  /// second is not "months overdue" — it is due a few weeks after the one just
  /// given. Returns null when there is nothing to compute from.
  static DateTime? earliestAllowedDate({
    required DateTime? birthdate,
    required double scheduledAtMonths,
    DateTime? previousDoseGivenOn,
    int? minimumIntervalWeeks,
  }) {
    DateTime? byAge;
    if (birthdate != null) {
      byAge = birthdate.add(
        Duration(days: (scheduledAtMonths * _daysPerMonth).round()),
      );
    }

    DateTime? byInterval;
    if (previousDoseGivenOn != null && minimumIntervalWeeks != null) {
      byInterval =
          previousDoseGivenOn.add(Duration(days: minimumIntervalWeeks * 7));
    }

    if (byAge == null) return byInterval;
    if (byInterval == null) return byAge;
    return byAge.isAfter(byInterval) ? byAge : byInterval;
  }

  /// Where a scheduled dose stands for this child.
  ///
  /// Precedence matters. An age ceiling outranks everything — past it the dose
  /// should not be given at all. A pending minimum interval outranks lateness,
  /// because a dose that cannot yet be given is not overdue however long ago
  /// its scheduled age passed.
  static DoseStatus statusOfDose({
    required bool alreadyGiven,
    required double childAgeMonths,
    required double scheduledAtMonths,
    double? maximumAgeMonths,
    bool ageIsKnown = true,
    DateTime? earliestAllowed,
    DateTime? today,
  }) {
    if (alreadyGiven) return DoseStatus.given;

    if (ageIsKnown &&
        maximumAgeMonths != null &&
        childAgeMonths > maximumAgeMonths) {
      return DoseStatus.noLongerGiven;
    }

    if (earliestAllowed != null) {
      final now = today ?? DateTime.now();
      if (earliestAllowed.isAfter(now)) {
        // Not yet reachable. Which of the two constraints is holding it back
        // decides how it reads: waiting on an interval is imminent, waiting on
        // age may be months away.
        return ageIsKnown && childAgeMonths >= scheduledAtMonths
            ? DoseStatus.dueSoon
            : DoseStatus.notYetDue;
      }
    }

    if (!ageIsKnown) return DoseStatus.due;
    if (childAgeMonths < scheduledAtMonths) return DoseStatus.notYetDue;

    return childAgeMonths - scheduledAtMonths > lateAfterMonths
        ? DoseStatus.pastDue
        : DoseStatus.due;
  }

  /// Same judgement, straight from a `vaccines` row.
  static DoseStatus statusOfVaccine(
    Map<String, dynamic> vaccine, {
    required bool alreadyGiven,
    required double childAgeMonths,
    required bool ageIsKnown,
    DateTime? birthdate,
    DateTime? previousDoseGivenOn,
  }) {
    final scheduledAt =
        (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0;

    return statusOfDose(
      alreadyGiven: alreadyGiven,
      childAgeMonths: childAgeMonths,
      scheduledAtMonths: scheduledAt,
      maximumAgeMonths: (vaccine['maximum_age_months'] as num?)?.toDouble(),
      ageIsKnown: ageIsKnown,
      earliestAllowed: earliestAllowedDate(
        birthdate: birthdate,
        scheduledAtMonths: scheduledAt,
        previousDoseGivenOn: previousDoseGivenOn,
        minimumIntervalWeeks:
            (vaccine['minimum_interval_weeks'] as num?)?.toInt(),
      ),
    );
  }

  /// How far past its scheduled age an outstanding dose now is, in plain
  /// words. Empty when it is not yet late.
  static String describeOverdue({
    required double childAgeMonths,
    required double scheduledAtMonths,
  }) {
    final monthsLate = childAgeMonths - scheduledAtMonths;
    if (monthsLate <= lateAfterMonths) return '';

    final weeksLate = (monthsLate * 4.345).round();
    if (weeksLate < 8) return '$weeksLate weeks late';

    final months = monthsLate.floor();
    return months == 1 ? '1 month late' : '$months months late';
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
