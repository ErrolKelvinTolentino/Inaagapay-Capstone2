// lib/services/fetal_heart_rate_reference.dart
//
// One place where the fetal heart rate is judged.
//
// Before this file the app judged it in six places using two different ranges.
// Five said 120–160 and one said 110–160, none cited a source, and the
// disagreement was not academic: the modern baseline is 110–160, so in five of
// the six places a rate of 110–119 — a normal baseline — was reported as a
// finding. The app over-called, on the mother's own record, in the direction
// that alarms rather than reassures.
//
// Built in the shape of `blood_pressure_reference.dart`, and for the same
// reasons:
//
// 1. It does not diagnose. It reports where a rate sits against a published
//    baseline and what to do next. Bradycardia, tachycardia and fetal distress
//    are findings a physician confirms; a midwife auscultates, repeats and
//    refers, and so does this code. The vocabulary is held in [FhrAction] and
//    [FhrCategory] rather than left to whoever writes the next string.
//
// 2. It does not decide the numbers. They are stated once, below, with their
//    source, and every value is overridable through [FhrThresholds].
//
// SCOPE. This reads the *rate*. Fetal heart *tone* — regular, irregular,
// faint, absent — is recorded separately by the midwife and is not
// interpreted here.

/// Where the numbers in [FhrThresholds.standard] come from.
///
/// ⚠️ CONFIRM BEFORE DEFENCE. 110–160 bpm is the normal baseline range in the
/// NICHD fetal monitoring nomenclature, carried into ACOG and FIGO guidance,
/// and it is the range one of the six sites in this app already used. The
/// other five used the older 120–160 textbook range. Verify which the RHU
/// follows, record the exact document and year here, and cite it in the study.
/// If the RHU follows a different reference, change [FhrThresholds] — no other
/// file needs to be touched.
const String kFetalHeartRateSourceNote =
    'Baseline range follows the NICHD fetal heart rate nomenclature '
    '(110–160 bpm), as carried into ACOG and FIGO guidance. Pending '
    'confirmation against the DOH/POGS edition in use at Baliwag City RHU III.';

/// Short form shown in the UI beside a classification, so the app is visibly
/// applying someone else's rule rather than expressing its own opinion.
const String kFetalHeartRateSourceShort = 'NICHD baseline range 110–160 bpm';

/// The cut-points, in one overridable object.
class FhrThresholds {
  const FhrThresholds({
    this.baselineMin = 110,
    this.baselineMax = 160,
    this.plausibleMax = 250,
    this.audibleFromWeeks = 12,
  });

  /// The baseline range. Both ends are inclusive: exactly 110 and exactly 160
  /// are within range. The five sites this replaced excluded 110–119, which is
  /// the whole reason the ranges disagreed.
  final int baselineMin;
  final int baselineMax;

  /// Above this, the entry is a typo rather than a measurement. Matches the
  /// bound the checkup form already validates against, so a value the form
  /// accepts is never called unreadable here and vice versa.
  final int plausibleMax;

  /// A hand-held Doppler cannot reliably pick up the heartbeat before about
  /// this week. Not hearing one earlier is not a finding, and the app should
  /// not present it as one.
  final int audibleFromWeeks;

  static const FhrThresholds standard = FhrThresholds();
}

/// Where one rate sits against the baseline. Descriptive only — none of these
/// names is a diagnosis.
enum FhrCategory {
  /// Missing, or not a plausible measurement.
  unreadable,
  belowRange,
  withinRange,
  aboveRange;

  String get label => switch (this) {
        FhrCategory.unreadable => 'Not recorded',
        FhrCategory.belowRange => 'Below the baseline range',
        FhrCategory.withinRange => 'Within the baseline range',
        FhrCategory.aboveRange => 'Above the baseline range',
      };
}

/// What to do next. The app's output is an action, never a condition — this
/// enum is the vocabulary boundary.
enum FhrAction {
  none,

  /// Outside the baseline range. A single reading is repeated before it is
  /// acted on — rates move with fetal sleep and activity, and a low reading
  /// is sometimes the mother's own pulse — and referred if it persists.
  repeatAndRefer;

  String get label => switch (this) {
        FhrAction.none => 'No action needed',
        FhrAction.repeatAndRefer => 'Repeat, and refer if it persists',
      };
}

/// One fetal heart rate reading, read against the baseline.
class FhrAssessment {
  const FhrAssessment({
    required this.rate,
    required this.category,
    required this.action,
    required this.finding,
    this.note,
  });

  final int? rate;
  final FhrCategory category;
  final FhrAction action;

  /// A plain statement of what was measured and where it sits. Never names a
  /// condition.
  final String finding;

  /// Context that changes how the finding should be read.
  final String? note;

  bool get isOutsideBaseline =>
      category == FhrCategory.belowRange || category == FhrCategory.aboveRange;
}

class FetalHeartRateReference {
  const FetalHeartRateReference._();

  /// Where a single rate sits.
  ///
  /// Both ends of the baseline are inclusive: 110 and 160 are within range.
  static FhrCategory categorise(
    int? rate, {
    FhrThresholds thresholds = FhrThresholds.standard,
  }) {
    if (rate == null || rate <= 0 || rate > thresholds.plausibleMax) {
      return FhrCategory.unreadable;
    }
    if (rate < thresholds.baselineMin) return FhrCategory.belowRange;
    if (rate > thresholds.baselineMax) return FhrCategory.aboveRange;
    return FhrCategory.withinRange;
  }

  /// The reading, with the context needed to read it.
  ///
  /// [gestationalWeeks] only changes the note, never the classification — a
  /// rate is measured against the same baseline throughout pregnancy.
  static FhrAssessment assess(
    int? rate, {
    double? gestationalWeeks,
    FhrThresholds thresholds = FhrThresholds.standard,
  }) {
    final category = categorise(rate, thresholds: thresholds);
    final range = '${thresholds.baselineMin}–${thresholds.baselineMax}';

    final String finding;
    switch (category) {
      case FhrCategory.unreadable:
        finding = 'No fetal heart rate recorded for this visit.';
      case FhrCategory.belowRange:
        finding = 'Fetal heart rate $rate bpm is below the baseline range '
            'of $range.';
      case FhrCategory.aboveRange:
        finding = 'Fetal heart rate $rate bpm is above the baseline range '
            'of $range.';
      case FhrCategory.withinRange:
        finding = 'Fetal heart rate $rate bpm is within the baseline range '
            'of $range.';
    }

    return FhrAssessment(
      rate: category == FhrCategory.unreadable ? null : rate,
      category: category,
      action: category == FhrCategory.withinRange ||
              category == FhrCategory.unreadable
          ? FhrAction.none
          : FhrAction.repeatAndRefer,
      finding: finding,
      note: _noteFor(
        category: category,
        gestationalWeeks: gestationalWeeks,
        thresholds: thresholds,
      ),
    );
  }

  static String? _noteFor({
    required FhrCategory category,
    required double? gestationalWeeks,
    required FhrThresholds thresholds,
  }) {
    // Nothing heard, and it is early enough that nothing is expected to be.
    // Presenting this as a missing measurement invites worry over a Doppler
    // limitation.
    if (category == FhrCategory.unreadable &&
        gestationalWeeks != null &&
        gestationalWeeks < thresholds.audibleFromWeeks) {
      return 'Before week ${thresholds.audibleFromWeeks} a hand-held Doppler '
          'may not pick up the heartbeat. Not hearing one this early is not '
          'itself a finding.';
    }

    // The classic auscultation error, and the reason a low reading is repeated
    // rather than acted on: the maternal pulse sits in the range a low fetal
    // rate would occupy.
    if (category == FhrCategory.belowRange) {
      return 'A rate close to the mother\'s own pulse may be hers rather than '
          'the baby\'s. Check her pulse at the same time before acting on it.';
    }

    return null;
  }
}
