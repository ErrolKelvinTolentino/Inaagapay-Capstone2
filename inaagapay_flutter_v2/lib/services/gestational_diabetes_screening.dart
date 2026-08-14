// lib/services/gestational_diabetes_screening.dart
//
// Who should be screened for gestational diabetes, when, and what the numbers
// mean when they come back.
//
// WHAT GESTATIONAL DIABETES IS, SO THE CODE MATCHES THE CONDITION
//
// It is glucose intolerance first recognised in pregnancy, driven by placental
// hormones creating insulin resistance the pancreas cannot fully compensate
// for. It is *not* caused by cravings or by eating sweets — diet affects
// control, not causation, which is why slim mothers with no cravings still
// develop it.
//
// The fact that shapes every design decision here: it is usually
// ASYMPTOMATIC. There is nothing to notice and nothing to ask about. The
// symptoms it can produce — thirst, frequent urination, tiredness — are also
// ordinary pregnancy. That is precisely why universal screening at 24-28 weeks
// exists, and why this module is built around *screening*, never around
// symptom detection.
//
// THIS MODULE DOES NOT DIAGNOSE
//
// In a barangay health centre a midwife screens and refers; diagnosis and
// management of gestational diabetes belong to a physician. So the terminal
// state here is "refer", not "diagnosed". The vocabulary is held in
// [GdmAction] and [GdmResult] so a condition name cannot be typed into an
// output string later, and a test asserts it.
//
// A recorded diagnosis of gestational diabetes may still be stored in
// `medical_conditions` — but only ever as a transcription of a physician's
// decision, entered by a person, the same way a blood type is transcribed from
// a lab report. Nothing in this file writes one.

/// Where the thresholds come from.
///
/// ⚠️ CONFIRM BEFORE DEFENCE — this is the specific research the adviser
/// asked for. Two protocols are in use and they are not interchangeable:
///
///   ONE-STEP  (IADPSG 2010 / WHO 2013, adopted by UNITE for Diabetes
///             Philippines): 75g OGTT, and **one** value at or above threshold
///             is enough.
///   TWO-STEP  (Carpenter-Coustan): a 50g glucose challenge, then a 100g OGTT
///             where **two** values must be at or above threshold.
///
/// The default below is the one-step protocol. Confirm which one Baliwag City
/// RHU III follows, record the guideline document and year here, cite it in the
/// study, and state the choice in the limitations section. Changing protocol
/// means changing [GdmThresholds] — no other file.
const String kGdmSourceNote =
    'One-step 75g OGTT thresholds (IADPSG 2010 / WHO 2013, adopted by UNITE '
    'for Diabetes Philippines). Two-step Carpenter-Coustan values also '
    'provided. Pending confirmation of which protocol Baliwag City RHU III '
    'follows.';

const String kGdmSourceShort = 'IADPSG/WHO 75g OGTT criteria';

/// Which screening protocol the facility uses.
enum GdmProtocol {
  /// 75g OGTT. One value at or above threshold meets the criteria.
  oneStep75g,

  /// 100g OGTT. Two values at or above threshold meet the criteria.
  twoStep100g,
}

/// Thresholds in mg/dL, in one overridable object.
class GdmThresholds {
  const GdmThresholds({
    this.protocol = GdmProtocol.oneStep75g,
    this.fasting = 92,
    this.oneHour = 180,
    this.twoHour = 153,
    this.threeHour,
    this.valuesRequired = 1,
    this.screeningOpensWeek = 24,
    this.screeningClosesWeek = 28,
  });

  /// The two-step protocol, for facilities that use it.
  const GdmThresholds.twoStep()
      : protocol = GdmProtocol.twoStep100g,
        fasting = 95,
        oneHour = 180,
        twoHour = 155,
        threeHour = 140,
        valuesRequired = 2,
        screeningOpensWeek = 24,
        screeningClosesWeek = 28;

  final GdmProtocol protocol;

  final num fasting;
  final num oneHour;
  final num twoHour;

  /// Only the two-step protocol takes a 3-hour sample.
  final num? threeHour;

  /// How many samples must reach threshold for the result to meet criteria.
  /// One under the one-step protocol, two under the two-step.
  final int valuesRequired;

  /// The routine screening window. Screening earlier is for mothers carrying
  /// risk factors — see [assessRisk].
  final int screeningOpensWeek;
  final int screeningClosesWeek;

  static const GdmThresholds standard = GdmThresholds();
}

/// The glucose samples from one test. Any may be absent.
class GlucoseValues {
  const GlucoseValues({
    this.fasting,
    this.oneHour,
    this.twoHour,
    this.threeHour,
  });

  final num? fasting;
  final num? oneHour;
  final num? twoHour;
  final num? threeHour;

  bool get isEmpty =>
      fasting == null && oneHour == null && twoHour == null && threeHour == null;
}

/// What a completed test showed. Descriptive — none of these is a diagnosis.
enum GdmResult {
  /// Nothing recorded to judge.
  noResult,

  /// Some samples present, but too few for the protocol to be read.
  incomplete,

  /// Every recorded sample sits below its threshold.
  belowThreshold,

  /// Enough samples reached threshold to meet the screening criteria.
  meetsThreshold;

  String get label => switch (this) {
        GdmResult.noResult => 'No result recorded',
        GdmResult.incomplete => 'Incomplete test',
        GdmResult.belowThreshold => 'Below screening thresholds',
        GdmResult.meetsThreshold => 'Meets screening thresholds',
      };
}

/// Where a pregnancy stands in the screening pathway.
enum GdmScreeningStatus {
  /// Not yet in the window and carrying no risk factors.
  notYetDue,

  /// Risk factors present — screening is recommended without waiting.
  dueEarly,

  /// Inside the routine window.
  due,

  /// Past the window with nothing recorded.
  overdue,

  /// A result is on file.
  screened,
}

/// What to do next. The output is always an action, never a condition.
enum GdmAction {
  none,
  screenAtNextVisit,
  screenNow,
  referForAssessment,
  repeatIncompleteTest;

  String get label => switch (this) {
        GdmAction.none => 'No action needed',
        GdmAction.screenAtNextVisit => 'Arrange screening at next visit',
        GdmAction.screenNow => 'Screening is due',
        GdmAction.referForAssessment => 'Refer for assessment',
        GdmAction.repeatIncompleteTest => 'Repeat the incomplete test',
      };
}

/// Why this mother might be screened before the routine window.
///
/// Every factor here is read from data the app already stores. Nothing new is
/// asked of the midwife.
class GdmRiskProfile {
  const GdmRiskProfile({required this.factors});

  final List<String> factors;

  bool get hasRiskFactors => factors.isNotEmpty;
}

/// The screening picture for one pregnancy.
class GdmAssessment {
  const GdmAssessment({
    required this.status,
    required this.result,
    required this.action,
    required this.finding,
    required this.risk,
    this.samplesAtOrAboveThreshold = const [],
  });

  final GdmScreeningStatus status;
  final GdmResult result;
  final GdmAction action;

  /// A plain statement of what is known. Never names a condition.
  final String finding;

  final GdmRiskProfile risk;

  /// Which samples reached threshold, named — "fasting", "2-hour".
  final List<String> samplesAtOrAboveThreshold;

  bool get needsReferral => action == GdmAction.referForAssessment;
}

class GestationalDiabetesScreening {
  const GestationalDiabetesScreening._();

  /// Weight above which a previous baby counts as macrosomic, in grams.
  ///
  /// ⚠️ Confirm alongside the thresholds. 4000g is the commonly used cut-point;
  /// some references use 4500g.
  static const int macrosomiaGrams = 4000;

  /// Pre-pregnancy BMI at or above which weight is a screening risk factor.
  /// Asian populations are often screened at a lower cut-point than 25 —
  /// another item for the adviser.
  static const num overweightBmi = 25;

  /// Maternal age at or above which age is a screening risk factor.
  static const int olderMotherAge = 35;

  /// Reads the risk factors already present in a mother's record.
  ///
  /// [previousBirthWeightsGrams] comes from birth_details on her earlier
  /// children; [recordedConditions] from medical_conditions.
  ///
  /// Family history of diabetes is a recognised risk factor and the app does
  /// not capture it anywhere. That gap is deliberate to surface rather than
  /// silently ignore — see the note returned to the UI.
  static GdmRiskProfile assessRisk({
    int? maternalAge,
    num? prePregnancyBmi,
    List<num> previousBirthWeightsGrams = const [],
    List<String> recordedConditions = const [],
  }) {
    final factors = <String>[];

    if (maternalAge != null && maternalAge >= olderMotherAge) {
      factors.add('Aged $maternalAge');
    }

    if (prePregnancyBmi != null && prePregnancyBmi >= overweightBmi) {
      factors.add(
          'Pre-pregnancy BMI ${prePregnancyBmi.toStringAsFixed(1)}');
    }

    final macrosomic = previousBirthWeightsGrams
        .where((grams) => grams >= macrosomiaGrams)
        .toList();
    if (macrosomic.isNotEmpty) {
      final heaviest =
          macrosomic.reduce((a, b) => a > b ? a : b) / 1000;
      factors.add(
          'Previous baby ${heaviest.toStringAsFixed(1)}kg at birth');
    }

    for (final condition in recordedConditions) {
      final lower = condition.toLowerCase();
      if (lower.contains('diabet')) {
        factors.add('History of diabetes on record');
        break;
      }
    }

    return GdmRiskProfile(factors: factors);
  }

  /// Reads a set of glucose samples against the protocol's thresholds.
  static GdmResult readValues(
    GlucoseValues values, {
    GdmThresholds thresholds = GdmThresholds.standard,
  }) {
    if (values.isEmpty) return GdmResult.noResult;

    final reached = _samplesAtOrAboveThreshold(values, thresholds);

    if (reached.length >= thresholds.valuesRequired) {
      return GdmResult.meetsThreshold;
    }

    // A test that cannot yet meet the criteria because samples are missing is
    // not a negative result. Under the two-step protocol one recorded value
    // below threshold says nothing about the two that were never taken.
    final recorded = [
      values.fasting,
      values.oneHour,
      values.twoHour,
      values.threeHour,
    ].where((v) => v != null).length;

    if (recorded < thresholds.valuesRequired) return GdmResult.incomplete;

    return GdmResult.belowThreshold;
  }

  /// The full picture: where she is in the pathway, what the result says, and
  /// the single next action.
  static GdmAssessment assess({
    double? gestationalWeeks,
    GlucoseValues? values,
    GdmRiskProfile risk = const GdmRiskProfile(factors: []),
    GdmThresholds thresholds = GdmThresholds.standard,
  }) {
    final result = values == null
        ? GdmResult.noResult
        : readValues(values, thresholds: thresholds);

    final reached = values == null
        ? <String>[]
        : _samplesAtOrAboveThreshold(values, thresholds);

    // A result on file settles the question, whatever the gestational age.
    if (result == GdmResult.meetsThreshold) {
      return GdmAssessment(
        status: GdmScreeningStatus.screened,
        result: result,
        action: GdmAction.referForAssessment,
        risk: risk,
        samplesAtOrAboveThreshold: reached,
        finding: '${reached.length} of the recorded samples '
            '(${reached.join(', ')}) reached the screening threshold.',
      );
    }

    if (result == GdmResult.belowThreshold) {
      return GdmAssessment(
        status: GdmScreeningStatus.screened,
        result: result,
        action: GdmAction.none,
        risk: risk,
        finding: 'Screening recorded, with every sample below its threshold.',
      );
    }

    if (result == GdmResult.incomplete) {
      return GdmAssessment(
        status: GdmScreeningStatus.screened,
        result: result,
        action: GdmAction.repeatIncompleteTest,
        risk: risk,
        finding: 'Some glucose samples are recorded but too few to read '
            'against the ${_protocolName(thresholds)} protocol.',
      );
    }

    // Nothing on file — where is she in the pathway?
    final weeks = gestationalWeeks;

    if (weeks == null) {
      return GdmAssessment(
        status: GdmScreeningStatus.notYetDue,
        result: result,
        action: GdmAction.none,
        risk: risk,
        finding: 'Gestational age is unknown, so the screening window cannot '
            'be worked out.',
      );
    }

    if (weeks > thresholds.screeningClosesWeek) {
      return GdmAssessment(
        status: GdmScreeningStatus.overdue,
        result: result,
        action: GdmAction.screenNow,
        risk: risk,
        finding: 'Now at week ${weeks.round()}, past the '
            '${thresholds.screeningOpensWeek}-${thresholds.screeningClosesWeek} '
            'week window, with no glucose result on file.',
      );
    }

    if (weeks >= thresholds.screeningOpensWeek) {
      return GdmAssessment(
        status: GdmScreeningStatus.due,
        result: result,
        action: GdmAction.screenNow,
        risk: risk,
        finding: 'Inside the routine screening window '
            '(weeks ${thresholds.screeningOpensWeek}-'
            '${thresholds.screeningClosesWeek}), with no result yet.',
      );
    }

    // Before the window. Risk factors bring it forward rather than waiting.
    if (risk.hasRiskFactors) {
      return GdmAssessment(
        status: GdmScreeningStatus.dueEarly,
        result: result,
        action: GdmAction.screenAtNextVisit,
        risk: risk,
        finding: 'Carrying ${risk.factors.length} screening risk '
            '${risk.factors.length == 1 ? 'factor' : 'factors'} '
            '(${risk.factors.join('; ')}), so screening is worth arranging '
            'without waiting for week ${thresholds.screeningOpensWeek}.',
      );
    }

    return GdmAssessment(
      status: GdmScreeningStatus.notYetDue,
      result: result,
      action: GdmAction.none,
      risk: risk,
      finding: 'Routine screening falls due at week '
          '${thresholds.screeningOpensWeek}.',
    );
  }

  static List<String> _samplesAtOrAboveThreshold(
    GlucoseValues values,
    GdmThresholds thresholds,
  ) {
    final reached = <String>[];

    if (values.fasting != null && values.fasting! >= thresholds.fasting) {
      reached.add('fasting');
    }
    if (values.oneHour != null && values.oneHour! >= thresholds.oneHour) {
      reached.add('1-hour');
    }
    if (values.twoHour != null && values.twoHour! >= thresholds.twoHour) {
      reached.add('2-hour');
    }
    final threeHourThreshold = thresholds.threeHour;
    if (threeHourThreshold != null &&
        values.threeHour != null &&
        values.threeHour! >= threeHourThreshold) {
      reached.add('3-hour');
    }

    return reached;
  }

  static String _protocolName(GdmThresholds thresholds) =>
      thresholds.protocol == GdmProtocol.oneStep75g ? '75g one-step' : '100g two-step';
}
