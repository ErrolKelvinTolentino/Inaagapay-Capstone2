// lib/services/blood_pressure_reference.dart
//
// One place where blood pressure in pregnancy is judged.
//
// Before this file the app judged blood pressure in nine different places, and
// they did not agree. Five of them live in the prenatal checkup screen alone:
// one uses the non-pregnancy AHA/ACC staging where 130/80 is already Stage 1,
// while the card rendered directly beneath it uses the pregnancy thresholds of
// 140/90 and 160/110. A reading of 145/95 currently shows "HTN Stage 2" and
// "Hypertension in Pregnancy" side by side. One of them also compares with a
// strict `>`, so exactly 140/90 — the textbook cut-point — is classified as
// Stage 1 there and as high risk everywhere else. None of the nine cites a
// source.
//
// This module does not delete those. It gives the app one rule set to migrate
// them onto, and is the only one used by anything written from here on.
//
// TWO THINGS THIS FILE DELIBERATELY DOES NOT DO
//
// 1. It does not diagnose. It reports which published threshold a reading
//    meets and what the guideline says to do next. Gestational hypertension,
//    pre-eclampsia and chronic hypertension are diagnoses made by a physician;
//    a midwife screens and refers, and so does this code. The vocabulary is
//    held in [BpAction] and [BpCategory] rather than left to whoever writes
//    the next string.
//
// 2. It does not decide the numbers. They are stated once, below, with their
//    source, and every value is overridable through [BpThresholds] so a
//    facility following a different guideline changes one object instead of
//    nine files.

/// Where the numbers in [BpThresholds.standard] come from.
///
/// ⚠️ CONFIRM BEFORE DEFENCE. These are the widely used ACOG cut-points for
/// hypertensive disorders of pregnancy, and they match the values already
/// hard-coded (uncited) throughout this app. They have not been checked
/// against the specific guideline edition Baliwag City RHU III follows. Verify
/// with the clinical adviser, record the exact document and year here, and cite
/// it in the study. If the RHU follows a different reference, change
/// [BpThresholds] — no other file needs to be touched.
const String kBloodPressureSourceNote =
    'Thresholds follow ACOG guidance on hypertensive disorders of pregnancy '
    '(Practice Bulletin 222). Pending confirmation against the DOH/POGS '
    'edition in use at Baliwag City RHU III.';

/// Short form shown in the UI beside a classification, so the app is visibly
/// applying someone else's rule rather than expressing its own opinion.
const String kBloodPressureSourceShort = 'ACOG hypertensive disorders criteria';

/// The cut-points, in one overridable object.
class BpThresholds {
  const BpThresholds({
    this.severeSystolic = 160,
    this.severeDiastolic = 110,
    this.raisedSystolic = 140,
    this.raisedDiastolic = 90,
    this.lowSystolic = 90,
    this.lowDiastolic = 60,
    this.gestationalOnsetWeeks = 20,
    this.occasionsForPattern = 2,
  });

  /// Severe range. Confirmed over minutes rather than at the next visit, and
  /// acted on the same day.
  final int severeSystolic;
  final int severeDiastolic;

  /// The threshold that, met on two occasions, is the criterion for
  /// gestational hypertension.
  final int raisedSystolic;
  final int raisedDiastolic;

  /// Commonly cited hypotension cut-point. Weaker evidence than the raised
  /// thresholds — see [BpAssessment.note], which explains why a low reading in
  /// mid-pregnancy is usually physiology rather than a finding.
  final int lowSystolic;
  final int lowDiastolic;

  /// Raised blood pressure appearing after this week is gestational in origin;
  /// before it, it points to pre-existing hypertension. Different pathway,
  /// different referral.
  final int gestationalOnsetWeeks;

  /// How many separate occasions define the pattern. The clinical criterion is
  /// two — a single raised reading is not hypertension, which is exactly what
  /// the existing single-reading checks in this app get wrong.
  final int occasionsForPattern;

  static const BpThresholds standard = BpThresholds();
}

/// Where one reading sits against the thresholds. Descriptive only — none of
/// these names is a diagnosis.
enum BpCategory {
  /// Missing, or impossible (systolic at or below diastolic).
  unreadable,
  low,
  normal,

  /// At or above the raised threshold, below the severe one.
  raised,
  severe;

  String get label => switch (this) {
        BpCategory.unreadable => 'Not readable',
        BpCategory.low => 'Below usual range',
        BpCategory.normal => 'Within usual range',
        BpCategory.raised => 'At or above threshold',
        BpCategory.severe => 'Severe range',
      };
}

/// What the guideline says to do. The app's output is an action, never a
/// condition — this enum is the vocabulary boundary.
enum BpAction {
  none,

  /// Keep watching; nothing to escalate.
  monitor,

  /// One raised reading. Not a pattern yet, and not hypertension yet.
  repeatNextVisit,

  /// The two-occasion criterion is met.
  referForAssessment,

  /// Severe range.
  referSameDay;

  String get label => switch (this) {
        BpAction.none => 'No action needed',
        BpAction.monitor => 'Continue monitoring',
        BpAction.repeatNextVisit => 'Repeat at next visit',
        BpAction.referForAssessment => 'Refer for assessment',
        BpAction.referSameDay => 'Refer today',
      };
}

/// One blood pressure measurement, with the context needed to judge it.
class BpReading {
  const BpReading({
    required this.systolic,
    required this.diastolic,
    this.takenOn,
    this.gestationalWeeks,
  });

  final int systolic;
  final int diastolic;
  final DateTime? takenOn;
  final double? gestationalWeeks;

  String get formatted => '$systolic/$diastolic';
}

/// The reading history, read as a pattern.
class BpAssessment {
  const BpAssessment({
    required this.latest,
    required this.category,
    required this.action,
    required this.finding,
    required this.raisedRun,
    required this.lowRun,
    this.severeReading,
    this.note,
    this.everMetCriterion = false,
    this.everSevere = false,
    this.priorRaisedEpisode = const [],
  });

  const BpAssessment.noData()
      : latest = null,
        category = BpCategory.unreadable,
        action = BpAction.none,
        finding = 'No blood pressure readings recorded yet.',
        raisedRun = const [],
        lowRun = const [],
        severeReading = null,
        note = null,
        everMetCriterion = false,
        everSevere = false,
        priorRaisedEpisode = const [];

  final BpReading? latest;
  final BpCategory category;
  final BpAction action;

  /// A plain statement of what was measured and which threshold it meets.
  /// Never names a condition.
  final String finding;

  /// The unbroken run of at-or-above-threshold readings ending at the most
  /// recent one. Length ≥ 2 is the two-occasion criterion.
  final List<BpReading> raisedRun;

  /// The same, for readings below the low cut-point.
  final List<BpReading> lowRun;

  /// The most recent severe-range reading, if any.
  final BpReading? severeReading;

  /// Context that changes how the finding should be read — before 20 weeks, or
  /// the normal mid-pregnancy fall.
  final String? note;

  /// True when the two-occasion threshold was met at any point in this
  /// pregnancy, even if the latest reading has since come back down.
  ///
  /// This does not reset. Blood pressure moves with time of day, rest before
  /// the cuff and anxiety at the clinic, so one normal reading is not evidence
  /// that a hypertensive episode resolved — and pre-eclampsia can still
  /// develop after readings that looked fine. A mother who once met the
  /// criterion needs watching more closely afterwards, not less.
  final bool everMetCriterion;

  /// True when any reading in this pregnancy reached the severe range.
  final bool everSevere;

  /// The earlier run that met the criterion, when the latest reading has since
  /// returned to range. Empty while that run is still the current one.
  final List<BpReading> priorRaisedEpisode;

  bool get meetsTwoOccasionCriterion => raisedRun.length >= 2;
  bool get needsReferral =>
      action == BpAction.referForAssessment || action == BpAction.referSameDay;
}

class BloodPressureReference {
  const BloodPressureReference._();

  /// Where a single reading sits.
  ///
  /// Comparisons are `>=` throughout: a reading of exactly 140/90 meets the
  /// threshold. The existing `_bpStatus` in the prenatal checkup screen uses
  /// `>`, which is why the textbook cut-point classifies differently there than
  /// in every risk engine.
  static BpCategory categorise(
    int? systolic,
    int? diastolic, {
    BpThresholds thresholds = BpThresholds.standard,
  }) {
    if (systolic == null || diastolic == null) return BpCategory.unreadable;

    // Systolic must exceed diastolic. A transposed or mistyped pair is not a
    // low reading, and must not be reported as one.
    if (systolic <= diastolic) return BpCategory.unreadable;

    if (systolic >= thresholds.severeSystolic ||
        diastolic >= thresholds.severeDiastolic) {
      return BpCategory.severe;
    }
    if (systolic >= thresholds.raisedSystolic ||
        diastolic >= thresholds.raisedDiastolic) {
      return BpCategory.raised;
    }
    if (systolic < thresholds.lowSystolic ||
        diastolic < thresholds.lowDiastolic) {
      return BpCategory.low;
    }
    return BpCategory.normal;
  }

  /// Reads a history as a pattern rather than as a series of separate moments.
  ///
  /// [readings] must be chronological, oldest first.
  ///
  /// The distinction that matters: a single raised reading and two consecutive
  /// raised readings are clinically different events, and the app has until now
  /// treated them the same — alarming on the first, which trains people to
  /// ignore the alarm.
  static BpAssessment assess(
    List<BpReading> readings, {
    BpThresholds thresholds = BpThresholds.standard,
  }) {
    final usable = readings
        .where((r) =>
            categorise(r.systolic, r.diastolic, thresholds: thresholds) !=
            BpCategory.unreadable)
        .toList();

    if (usable.isEmpty) return const BpAssessment.noData();

    final latest = usable.last;
    final category =
        categorise(latest.systolic, latest.diastolic, thresholds: thresholds);

    // Runs are counted backwards from the most recent reading: what matters is
    // whether she is raised *now and last time*, not whether she ever was.
    final raisedRun = <BpReading>[];
    for (final reading in usable.reversed) {
      final c =
          categorise(reading.systolic, reading.diastolic, thresholds: thresholds);
      if (c == BpCategory.raised || c == BpCategory.severe) {
        raisedRun.insert(0, reading);
      } else {
        break;
      }
    }

    final lowRun = <BpReading>[];
    for (final reading in usable.reversed) {
      final c =
          categorise(reading.systolic, reading.diastolic, thresholds: thresholds);
      if (c == BpCategory.low) {
        lowRun.insert(0, reading);
      } else {
        break;
      }
    }

    BpReading? severeReading;
    for (final reading in usable.reversed) {
      if (categorise(reading.systolic, reading.diastolic,
              thresholds: thresholds) ==
          BpCategory.severe) {
        severeReading = reading;
        break;
      }
    }

    // The whole history, not just the trailing run. A run that met the
    // criterion earlier in the pregnancy still counts once the latest reading
    // has come back down — otherwise a single normal value erases a
    // hypertensive episode from the record the midwife is looking at.
    final episodes = <List<BpReading>>[];
    var current = <BpReading>[];
    for (final reading in usable) {
      final c =
          categorise(reading.systolic, reading.diastolic, thresholds: thresholds);
      if (c == BpCategory.raised || c == BpCategory.severe) {
        current.add(reading);
      } else {
        if (current.length >= thresholds.occasionsForPattern) {
          episodes.add(current);
        }
        current = <BpReading>[];
      }
    }
    if (current.length >= thresholds.occasionsForPattern) episodes.add(current);

    final everMetCriterion = episodes.isNotEmpty;
    final everSevere = severeReading != null;

    // Only a *past* episode — while the run is still current, raisedRun
    // already describes it and repeating it would read as two separate events.
    final priorEpisode = (raisedRun.isEmpty && episodes.isNotEmpty)
        ? episodes.last
        : const <BpReading>[];

    final action = _actionFor(
      category: category,
      raisedRun: raisedRun,
      lowRun: lowRun,
      thresholds: thresholds,
      hasPriorEpisode: priorEpisode.isNotEmpty,
    );

    return BpAssessment(
      latest: latest,
      category: category,
      action: action,
      severeReading: severeReading,
      raisedRun: raisedRun,
      lowRun: lowRun,
      everMetCriterion: everMetCriterion,
      everSevere: everSevere,
      priorRaisedEpisode: priorEpisode,
      finding: _findingFor(
        category: category,
        latest: latest,
        raisedRun: raisedRun,
        lowRun: lowRun,
        thresholds: thresholds,
        priorEpisode: priorEpisode,
        everSevere: everSevere,
      ),
      note: _noteFor(
        category: category,
        latest: latest,
        raisedRun: raisedRun,
        thresholds: thresholds,
        hasPriorEpisode: priorEpisode.isNotEmpty,
      ),
    );
  }

  static BpAction _actionFor({
    required BpCategory category,
    required List<BpReading> raisedRun,
    required List<BpReading> lowRun,
    required BpThresholds thresholds,
    bool hasPriorEpisode = false,
  }) {
    // Severe range outranks everything, including the two-occasion rule. It is
    // confirmed over minutes, not weeks, and waiting for the next visit to see
    // whether it repeats is the wrong move.
    if (category == BpCategory.severe) return BpAction.referSameDay;

    if (raisedRun.length >= thresholds.occasionsForPattern) {
      return BpAction.referForAssessment;
    }
    if (category == BpCategory.raised) return BpAction.repeatNextVisit;

    // Back in range, but she met the threshold earlier in this pregnancy.
    // Not "no action" — keep watching. One normal reading is not evidence a
    // hypertensive episode is over.
    if (hasPriorEpisode) return BpAction.monitor;

    if (lowRun.length >= thresholds.occasionsForPattern) {
      return BpAction.monitor;
    }
    if (category == BpCategory.low) return BpAction.monitor;
    return BpAction.none;
  }

  static String _findingFor({
    required BpCategory category,
    required BpReading latest,
    required List<BpReading> raisedRun,
    required List<BpReading> lowRun,
    required BpThresholds thresholds,
    List<BpReading> priorEpisode = const [],
    bool everSevere = false,
  }) {
    final raised = '${thresholds.raisedSystolic}/${thresholds.raisedDiastolic}';
    final severe = '${thresholds.severeSystolic}/${thresholds.severeDiastolic}';

    if (category == BpCategory.severe) {
      return 'Latest reading ${latest.formatted} is in the severe range '
          '(at or above $severe).';
    }

    if (raisedRun.length >= thresholds.occasionsForPattern) {
      final weeks = raisedRun
          .map((r) => r.gestationalWeeks == null
              ? null
              : 'week ${r.gestationalWeeks!.round()}')
          .whereType<String>()
          .toList();
      final where = weeks.length == raisedRun.length
          ? ' (${weeks.join(' and ')})'
          : '';
      return '${raisedRun.length} consecutive readings at or above $raised$where. '
          'This meets the two-occasion threshold for referral.';
    }

    if (category == BpCategory.raised) {
      return 'Latest reading ${latest.formatted} is at or above $raised. '
          'One reading is not yet a pattern — repeat it at the next visit.';
    }

    // Back in range after an earlier episode. Reporting only the latest value
    // here would hide the episode entirely — the card would read exactly like
    // a mother whose pressure has never been raised.
    if (priorEpisode.isNotEmpty) {
      final weeks = priorEpisode
          .map((r) => r.gestationalWeeks == null
              ? null
              : 'week ${r.gestationalWeeks!.round()}')
          .whereType<String>()
          .toList();
      final where =
          weeks.length == priorEpisode.length ? ' (${weeks.join(' and ')})' : '';

      final severeNote = everSevere
          ? ' One of them reached the severe range.'
          : '';

      return 'Latest reading ${latest.formatted} is back within range, but '
          '${priorEpisode.length} earlier readings met the $raised '
          'threshold$where.$severeNote Blood pressure has not been steady this '
          'pregnancy.';
    }

    if (lowRun.length >= thresholds.occasionsForPattern) {
      return '${lowRun.length} consecutive readings below '
          '${thresholds.lowSystolic}/${thresholds.lowDiastolic}, '
          'most recently ${latest.formatted}.';
    }

    if (category == BpCategory.low) {
      return 'Latest reading ${latest.formatted} is below '
          '${thresholds.lowSystolic}/${thresholds.lowDiastolic}.';
    }

    return 'Latest reading ${latest.formatted} is within the usual range.';
  }

  static String? _noteFor({
    required BpCategory category,
    required BpReading latest,
    required List<BpReading> raisedRun,
    required BpThresholds thresholds,
    bool hasPriorEpisode = false,
  }) {
    final weeks = latest.gestationalWeeks;

    if (hasPriorEpisode) {
      return 'A normal reading does not close an earlier episode — pressure '
          'moves with rest, time of day and anxiety at the clinic. Keep '
          'measuring at every visit.';
    }

    // Raised blood pressure before 20 weeks is not gestational in origin, and
    // the referral question is a different one.
    if ((category == BpCategory.raised || category == BpCategory.severe) &&
        weeks != null &&
        weeks < thresholds.gestationalOnsetWeeks) {
      return 'This is before week ${thresholds.gestationalOnsetWeeks}, so '
          'raised readings here point to pre-existing rather than '
          'pregnancy-related hypertension. Note it for the referring '
          'physician.';
    }

    // Blood pressure falls naturally in the second trimester, bottoming out
    // around weeks 20–24 before climbing back. Flagging that fall as a finding
    // would fire on healthy mothers, so the app says so rather than alarming.
    if (category == BpCategory.low && weeks != null && weeks >= 16 && weeks <= 28) {
      return 'Blood pressure normally falls around this stage of pregnancy. '
          'Worth acting on mainly when she also feels dizzy or faint.';
    }

    return null;
  }
}
