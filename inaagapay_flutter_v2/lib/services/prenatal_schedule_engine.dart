// lib/services/prenatal_schedule_engine.dart
//
// When the next prenatal visit should be offered.
//
// The rules here are not new. They were already running, correctly, inside
// `_calculateRecommendedNextSchedule()` in add_prenatal_checkup_screen.dart —
// a 5,000-line widget where they could not be unit tested, could not be cited,
// and could not be reused. Gestational diabetes screening at weeks 24–28 is
// the same kind of question and would have had to duplicate the arithmetic.
//
// So this is a move, not a redesign. The intervals below produce the same
// dates the app already proposes. What is added is a source, configurability,
// a delivery cap, and tests.
//
// WHAT THIS IS NOT
//
// It proposes; it does not schedule. Every date it returns lands in an
// editable field the midwife confirms or overrides, and the reason is shown
// beside it so she can see why. A recommended date is not a clinical decision
// about one mother — she is, and her judgement outranks the interval.
//
// It also has no idea what day the health centre is open. Proposed dates
// ignore holidays, closures, non-working days and clinic capacity; the midwife
// resolves those. That limitation belongs in the study's limitations section.

/// Where the intervals come from.
///
/// ⚠️ CONFIRM BEFORE DEFENCE. The 4-weekly / 2-weekly / weekly pattern is the
/// conventional antenatal schedule and matches what this app already proposes.
/// WHO's 2016 antenatal care model instead recommends **eight contacts** at
/// roughly weeks 12, 20, 26, 30, 34, 36, 38 and 40, which is a different
/// model — not merely different numbers.
///
/// Decide with the clinical adviser which one Baliwag City RHU III follows,
/// record the document and year here, and cite it in the study. Whichever it
/// is, change [PrenatalVisitIntervals] — nothing else needs to be touched.
///
/// Note for the write-up: the schedule in the Defense 1 notes ("every two days
/// in the final weeks") is post-term or high-risk surveillance, not routine
/// care, and is deliberately not encoded as a default.
const String kPrenatalScheduleSourceNote =
    'Interval model: conventional antenatal schedule — 4-weekly to 28 weeks, '
    '2-weekly to 36 weeks, weekly thereafter. Pending confirmation against the '
    'DOH/POGS guidance in use at Baliwag City RHU III. WHO 2016 recommends an '
    'alternative 8-contact model.';

/// The intervals, in one overridable object.
class PrenatalVisitIntervals {
  const PrenatalVisitIntervals({
    this.earlyPregnancyDays = 28,
    this.thirdTrimesterDays = 14,
    this.lateTermDays = 7,
    this.postTermDays = 3,
    this.highRiskEarlyDays = 14,
    this.highRiskLateDays = 7,
    this.secondIntervalFromWeek = 28,
    this.thirdIntervalFromWeek = 36,
    this.postTermFromWeek = 40,
    this.maximumGestationWeeks = 42,
  });

  /// Up to [secondIntervalFromWeek]: every four weeks.
  final int earlyPregnancyDays;

  /// From [secondIntervalFromWeek] to [thirdIntervalFromWeek]: every two weeks.
  final int thirdTrimesterDays;

  /// From [thirdIntervalFromWeek] onward: weekly.
  final int lateTermDays;

  /// Past [postTermFromWeek]: close surveillance.
  final int postTermDays;

  /// High-risk pregnancies are seen more often at every stage. These are the
  /// values the app already used; they are clinical practice rather than a
  /// cited interval, so they are the first thing to check with the adviser.
  final int highRiskEarlyDays;
  final int highRiskLateDays;

  final int secondIntervalFromWeek;
  final int thirdIntervalFromWeek;
  final int postTermFromWeek;

  /// Nothing is proposed beyond this gestation. A visit date at week 45 is an
  /// arithmetic result, not a plan.
  final int maximumGestationWeeks;

  static const PrenatalVisitIntervals standard = PrenatalVisitIntervals();
}

/// A proposed next visit, and why.
class PrenatalScheduleProposal {
  const PrenatalScheduleProposal({
    required this.date,
    required this.intervalDays,
    required this.reason,
    this.cappedAtTerm = false,
  });

  /// Date only — no time. Prenatal visits at a barangay health centre run as
  /// a walk-in morning clinic, so naming an hour would promise precision the
  /// service does not offer.
  final DateTime date;

  final int intervalDays;

  /// Shown next to the date so the midwife can see the rule that produced it.
  final String reason;

  /// True when the proposal was pulled back to the end of the safe window
  /// rather than following the interval.
  final bool cappedAtTerm;
}

class PrenatalScheduleEngine {
  const PrenatalScheduleEngine._();

  /// The next visit date to offer after a checkup on [lastVisit].
  ///
  /// [gestationalWeeks] null means gestation is unknown — usually a missing
  /// LMP. The interval then falls back to the early-pregnancy spacing, which
  /// is what the existing screen does, because proposing nothing leaves the
  /// midwife with an empty field and no prompt at all.
  static PrenatalScheduleProposal propose({
    required DateTime lastVisit,
    double? gestationalWeeks,
    bool isHighRisk = false,
    DateTime? expectedDateOfDelivery,
    PrenatalVisitIntervals intervals = PrenatalVisitIntervals.standard,
  }) {
    final base = DateTime(lastVisit.year, lastVisit.month, lastVisit.day);
    final weeks = gestationalWeeks ?? 0;

    late final int days;
    late final String reason;

    if (weeks > intervals.postTermFromWeek) {
      // Past the due date the question changes from routine care to
      // surveillance, and it outranks the risk level.
      days = intervals.postTermDays;
      reason = 'Post-term monitoring (+${intervals.postTermDays} days)';
    } else if (isHighRisk) {
      final late = weeks >= intervals.secondIntervalFromWeek;
      days = late ? intervals.highRiskLateDays : intervals.highRiskEarlyDays;
      reason = late
          ? 'High-risk weekly monitoring (+1 week)'
          : 'High-risk fortnightly monitoring (+2 weeks)';
    } else if (weeks < intervals.secondIntervalFromWeek) {
      days = intervals.earlyPregnancyDays;
      reason =
          'Routine schedule up to week ${intervals.secondIntervalFromWeek} '
          '(+4 weeks)';
    } else if (weeks < intervals.thirdIntervalFromWeek) {
      days = intervals.thirdTrimesterDays;
      reason = 'Routine schedule, weeks ${intervals.secondIntervalFromWeek}–'
          '${intervals.thirdIntervalFromWeek - 1} (+2 weeks)';
    } else {
      days = intervals.lateTermDays;
      reason = 'Routine schedule from week ${intervals.thirdIntervalFromWeek} '
          '(+1 week)';
    }

    final proposed = base.add(Duration(days: days));

    // Never propose a routine visit past the end of a plausible pregnancy.
    // Without this the arithmetic happily books week 45.
    final latest = _latestSensibleDate(
      base: base,
      gestationalWeeks: gestationalWeeks,
      expectedDateOfDelivery: expectedDateOfDelivery,
      intervals: intervals,
    );

    if (latest != null && proposed.isAfter(latest)) {
      return PrenatalScheduleProposal(
        date: latest,
        intervalDays: latest.difference(base).inDays,
        reason: 'Brought forward — a routine visit at the usual interval '
            'would fall after week ${intervals.maximumGestationWeeks}',
        cappedAtTerm: true,
      );
    }

    return PrenatalScheduleProposal(
      date: proposed,
      intervalDays: days,
      reason: reason,
    );
  }

  /// The last date a routine visit still makes sense, from whichever of
  /// gestational age or expected delivery date is known.
  static DateTime? _latestSensibleDate({
    required DateTime base,
    required double? gestationalWeeks,
    required DateTime? expectedDateOfDelivery,
    required PrenatalVisitIntervals intervals,
  }) {
    if (gestationalWeeks != null && gestationalWeeks > 0) {
      final weeksLeft = intervals.maximumGestationWeeks - gestationalWeeks;
      if (weeksLeft <= 0) return null; // Already past it; surveillance rules.
      return base.add(Duration(days: (weeksLeft * 7).round()));
    }

    if (expectedDateOfDelivery != null) {
      // Two weeks past the due date is week 42 by definition.
      final edd = DateTime(
        expectedDateOfDelivery.year,
        expectedDateOfDelivery.month,
        expectedDateOfDelivery.day,
      );
      final limit = edd.add(const Duration(days: 14));
      return limit.isAfter(base) ? limit : null;
    }

    return null;
  }
}
