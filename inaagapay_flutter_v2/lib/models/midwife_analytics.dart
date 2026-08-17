// lib/models/midwife_analytics.dart
//
// What the midwife dashboard's analytics section reads.
//
// Everything the section shows is one type — [AnalyticsMetric] — on purpose.
// A dashboard where each card invents its own layout is a dashboard the
// midwife has to re-learn at every scroll position, so the chart kind varies
// while the anatomy does not: headline, visual, one plain-language reading of
// *why*, one action. Adding a metric therefore means adding data, never a new
// card design.
//
// These types carry no Flutter imports. Severity and action are stated as
// clinical intent ("this is alarming", "send them to the mother list") and the
// widget layer decides what that looks like, so the same metric could be
// printed, exported, or tested without a widget tree.

/// How worrying a value is, in clinical terms rather than colour terms.
enum AnalyticsSeverity {
  /// Where you want the number to be.
  good,

  /// Not wrong, but worth watching.
  watch,

  /// Needs the midwife to do something.
  alert,

  /// Ordinary category with no clinical direction — an age band, say.
  neutral,

  /// Not measured, not assessed, not recorded. Deliberately distinct from
  /// [good]: an unassessed pregnancy is not a low-risk one.
  unknown,
}

/// The tone of a diagnostic sentence. Same three levels as severity, minus the
/// categorical ones, because an insight always leans somewhere.
enum AnalyticsTone { neutral, good, watch, alert }

/// Where a card's action button sends the midwife.
///
/// Named as destinations rather than routes so the dashboard owns navigation
/// and this file stays free of route strings.
enum AnalyticsAction {
  none,
  viewMothers,
  viewChildren,
  viewSchedules,
  viewInventory,
}

/// The glyph beside a card's title.
///
/// Named by subject rather than by icon, so the model still carries no Flutter
/// types and the widget layer picks the actual glyph. Swapping the icon set
/// later touches one map instead of thirteen call sites.
enum AnalyticsIcon {
  mothers,
  risk,
  riskFactors,
  vaccine,
  supplement,
  weight,
  screening,
  children,
  growth,
  immunization,
  stock,
  expiry,
  demand,
}

/// Which visual a metric wants. The card shell is identical either way.
enum AnalyticsChartKind {
  /// Ordered categories side by side — age bands, month buckets.
  bars,

  /// Parts of one whole — risk mix, growth status.
  donut,

  /// Unordered categories that compete for attention, longest first — risk
  /// drivers, stock levels.
  rankedBars,

  /// One number over its denominator, against a target — coverage.
  coverage,
}

/// One slice, bar, or row.
class AnalyticsBand {
  const AnalyticsBand({
    required this.label,
    required this.count,
    this.shortLabel,
    this.severity = AnalyticsSeverity.neutral,
    this.detail,
    this.fraction,
  });

  final String label;

  /// Axis-sized version of [label]. Falls back to [label] when absent.
  final String? shortLabel;

  final int count;
  final AnalyticsSeverity severity;

  /// Trailing note on the row — "2 severe", "expires Mar 4".
  final String? detail;

  /// How full to draw the bar, 0 to 1, when length should not come from
  /// [count].
  ///
  /// Needed wherever one chart holds more than one unit: 640 tablets beside 18
  /// vials, drawn by count, hides the vials entirely and hides the item that is
  /// actually about to run out. Stock draws against its reorder level instead,
  /// and expiry draws against how soon it is — both comparable across units.
  final double? fraction;

  String get axisLabel => shortLabel ?? label;
}

/// This period against the one before it.
///
/// The second pair is what keeps the comparison honest: a count that fell
/// because the caseload fell is not the same finding as a count that fell
/// while the caseload held, and a dashboard that shows only the first number
/// invites the wrong conclusion.
class AnalyticsComparison {
  const AnalyticsComparison({
    required this.currentLabel,
    required this.currentValue,
    required this.previousLabel,
    required this.previousValue,
    required this.unit,
    this.currentEligible,
    this.previousEligible,
  });

  final String currentLabel;
  final int currentValue;
  final String previousLabel;
  final int previousValue;

  /// What is being counted — "doses", "visits".
  final String unit;

  /// How many people could have received it in each period.
  final int? currentEligible;
  final int? previousEligible;

  int get change => currentValue - previousValue;
  bool get hasEligible => currentEligible != null && previousEligible != null;
}

/// The diagnostic layer: one sentence saying why the picture looks like this.
///
/// Written by rules over recorded data, never inferred prose — see
/// `MidwifeAnalyticsService`. [evidence] names the rows the sentence rests on
/// so a midwife who doubts it can go and look.
class AnalyticsInsight {
  const AnalyticsInsight(this.text, {this.tone = AnalyticsTone.neutral, this.evidence});

  final String text;
  final AnalyticsTone tone;
  final String? evidence;
}

/// The prescriptive layer: the one thing to do about it.
class AnalyticsPrescription {
  const AnalyticsPrescription({required this.label, required this.action});

  final String label;
  final AnalyticsAction action;
}

/// One card.
class AnalyticsMetric {
  const AnalyticsMetric({
    required this.title,
    required this.kind,
    this.icon = AnalyticsIcon.mothers,
    this.headline,
    this.headlineCaption,
    this.bands = const [],
    this.covered,
    this.eligible,
    this.comparison,
    this.insight,
    this.prescription,
    this.footnote,
    this.periodLabel,
    this.emptyMessage,
  });

  /// A card that has nothing to show yet, in the same shell as every other
  /// card. Hiding it instead would leave the midwife wondering whether the
  /// metric is missing or merely empty.
  const AnalyticsMetric.empty({
    required this.title,
    required String message,
    this.kind = AnalyticsChartKind.bars,
    this.icon = AnalyticsIcon.mothers,
    this.periodLabel,
  })  : headline = null,
        headlineCaption = null,
        bands = const [],
        covered = null,
        eligible = null,
        comparison = null,
        insight = null,
        prescription = null,
        footnote = null,
        emptyMessage = message;

  final String title;
  final AnalyticsChartKind kind;
  final AnalyticsIcon icon;

  /// The number the card is about, already formatted.
  final String? headline;

  /// What the headline is out of — "of 18 active pregnancies".
  final String? headlineCaption;

  final List<AnalyticsBand> bands;

  /// Coverage numerator and denominator.
  final int? covered;
  final int? eligible;

  final AnalyticsComparison? comparison;
  final AnalyticsInsight? insight;
  final AnalyticsPrescription? prescription;

  /// Caveats — missing birthdates, sample data, matching assumptions.
  final String? footnote;

  /// The window this card covers, shown beside the title: "Last 30 days".
  final String? periodLabel;

  final String? emptyMessage;

  bool get hasData => emptyMessage == null;

  int get total => bands.fold(0, (sum, band) => sum + band.count);

  /// Coverage as a whole percent, or null when it would mislead.
  ///
  /// Under ten people a percentage swings by double digits per person, which
  /// reads as precision the number does not have. Small denominators are shown
  /// as "3 of 8" instead.
  int? get coveragePercent {
    final numerator = covered;
    final denominator = eligible;
    if (numerator == null || denominator == null || denominator < 10) {
      return null;
    }
    return ((numerator / denominator) * 100).round();
  }
}

/// A row in the Today band.
class AnalyticsPriority {
  const AnalyticsPriority({
    required this.title,
    required this.detail,
    required this.severity,
    this.action = AnalyticsAction.none,
    this.sortKey = 0,
  });

  final String title;
  final String detail;
  final AnalyticsSeverity severity;
  final AnalyticsAction action;

  /// Lower sorts first. Days until due, or negative days overdue.
  final int sortKey;
}

/// One tab of the analytics section.
class AnalyticsSection {
  const AnalyticsSection({required this.title, required this.metrics});

  final String title;
  final List<AnalyticsMetric> metrics;
}

/// Everything the dashboard's analytics section needs, for one health centre.
class MidwifeAnalytics {
  const MidwifeAnalytics({
    required this.mothers,
    required this.children,
    required this.supplies,
    required this.priorities,
    this.suppliesAreSample = false,
  });

  const MidwifeAnalytics.empty()
      : mothers = const AnalyticsSection(title: 'Mothers', metrics: []),
        children = const AnalyticsSection(title: 'Children', metrics: []),
        supplies = const AnalyticsSection(title: 'Supplies', metrics: []),
        priorities = const [],
        suppliesAreSample = false;

  final AnalyticsSection mothers;
  final AnalyticsSection children;
  final AnalyticsSection supplies;
  final List<AnalyticsPriority> priorities;

  /// True when the inventory figures are the seeded demonstration set rather
  /// than this centre's stock. Surfaced in the UI — an invented number that
  /// looks measured is worse than no number.
  final bool suppliesAreSample;

  List<AnalyticsSection> get sections => [mothers, children, supplies];

  bool get isEmpty =>
      mothers.metrics.isEmpty &&
      children.metrics.isEmpty &&
      supplies.metrics.isEmpty;
}
