// lib/widgets/analytics/analytics_charts.dart
//
// The four visuals the analytics section is allowed to draw.
//
// Four, not more. Every chart here shares the same bar radius, the same label
// type scale and the same palette, so the eye moves between cards without
// re-calibrating. Each one also always prints its counts as digits next to the
// shape: a bar whose height must be estimated against a missing axis is
// decoration, and a midwife acting on "about a third" is acting on a guess.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/midwife_analytics.dart';
import '../../theme/app_colors.dart';
import 'analytics_theme.dart';

/// Parts of one whole. Used where the bands genuinely sum to something
/// meaningful — a risk mix, a growth status split.
class AnalyticsDonut extends StatelessWidget {
  const AnalyticsDonut({
    super.key,
    required this.bands,
    this.centerValue,
    this.centerLabel,
  });

  final List<AnalyticsBand> bands;
  final String? centerValue;
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final visible = bands.where((band) => band.count > 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 148,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 44,
                  startDegreeOffset: -90,
                  sections: [
                    for (int i = 0; i < visible.length; i++)
                      PieChartSectionData(
                        value: visible[i].count.toDouble(),
                        color: AnalyticsTheme.bandColor(
                          visible[i],
                          bands.indexOf(visible[i]),
                          bands.length,
                        ),
                        radius: 22,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              if (centerValue != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerValue!,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (centerLabel != null)
                      Text(
                        centerLabel!,
                        textAlign: TextAlign.center,
                        style: AnalyticsTheme.axisStyle,
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AnalyticsLegend(bands: bands),
      ],
    );
  }
}

/// Dot, label, count. Shared by the donut and anything else that needs to name
/// its colours, so a legend never renders two ways in one screen.
class AnalyticsLegend extends StatelessWidget {
  const AnalyticsLegend({super.key, required this.bands});

  final List<AnalyticsBand> bands;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: [
        for (int i = 0; i < bands.length; i++)
          if (bands[i].count > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AnalyticsTheme.bandColor(bands[i], i, bands.length),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(bands[i].label, style: AnalyticsTheme.bandLabelStyle),
                const SizedBox(width: 5),
                Text('${bands[i].count}', style: AnalyticsTheme.bandValueStyle),
              ],
            ),
      ],
    );
  }
}

/// Ordered categories — age bands, month buckets. Order carries meaning here,
/// so the bars stay in the order given and are never re-sorted by size.
class AnalyticsVerticalBars extends StatelessWidget {
  const AnalyticsVerticalBars({super.key, required this.bands});

  final List<AnalyticsBand> bands;

  static const double _plotHeight = 92;

  @override
  Widget build(BuildContext context) {
    if (bands.isEmpty) return const SizedBox.shrink();

    final maxCount = bands.fold<int>(0, (max, b) => b.count > max ? b.count : max);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (int i = 0; i < bands.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == bands.length - 1 ? 0 : 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${bands[i].count}', style: AnalyticsTheme.bandValueStyle),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: _plotHeight,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.bgSecondary,
                            borderRadius: BorderRadius.circular(
                              AnalyticsTheme.barRadius,
                            ),
                          ),
                        ),
                        Container(
                          // An empty band keeps a sliver of height so the
                          // chart reads as "none here" rather than as a gap
                          // where a bar failed to draw.
                          height: maxCount == 0
                              ? 3
                              : (3 + (_plotHeight - 3) * (bands[i].count / maxCount)),
                          decoration: BoxDecoration(
                            color: AnalyticsTheme.bandColor(
                              bands[i],
                              i,
                              bands.length,
                            ),
                            borderRadius: BorderRadius.circular(
                              AnalyticsTheme.barRadius,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    bands[i].axisLabel,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AnalyticsTheme.axisStyle,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Categories competing for attention, largest first — risk drivers, stock
/// levels. Horizontal because these labels are words, not numbers, and words
/// under a vertical bar either truncate or turn sideways.
class AnalyticsRankedBars extends StatelessWidget {
  const AnalyticsRankedBars({super.key, required this.bands, this.valueSuffix});

  final List<AnalyticsBand> bands;

  /// Unit printed after each count — "doses", "left".
  final String? valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (bands.isEmpty) return const SizedBox.shrink();

    final maxCount = bands.fold<int>(0, (max, b) => b.count > max ? b.count : max);

    return Column(
      children: [
        for (int i = 0; i < bands.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bands[i].label,
                      style: AnalyticsTheme.bandLabelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    valueSuffix == null
                        ? '${bands[i].count}'
                        : '${bands[i].count} $valueSuffix',
                    style: AnalyticsTheme.bandValueStyle,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, constraints) {
                  final fraction = bands[i].fraction ??
                      (maxCount == 0 ? 0.0 : bands[i].count / maxCount);
                  return Stack(
                    children: [
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.bgSecondary,
                          borderRadius: BorderRadius.circular(
                            AnalyticsTheme.barRadius,
                          ),
                        ),
                      ),
                      Container(
                        height: 10,
                        width: (constraints.maxWidth * fraction)
                            .clamp(6.0, constraints.maxWidth),
                        decoration: BoxDecoration(
                          // Ramp inverted against the row order so the longest
                          // bar is also the deepest: in a ranked list the top
                          // row is the finding, and the palest shade belongs at
                          // the bottom with the smallest.
                          color: AnalyticsTheme.bandColor(
                            bands[i],
                            bands.length - 1 - i,
                            bands.length,
                          ),
                          borderRadius: BorderRadius.circular(
                            AnalyticsTheme.barRadius,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (bands[i].detail != null) ...[
                const SizedBox(height: 5),
                Text(bands[i].detail!, style: AnalyticsTheme.footnoteStyle),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// One number over its denominator.
///
/// The uncovered remainder is labelled as loudly as the covered part, because
/// the remainder is the work: "31 of 38 on iron" and "7 mothers not on iron"
/// are the same fact, but only the second one can be acted on.
class AnalyticsCoverageMeter extends StatelessWidget {
  const AnalyticsCoverageMeter({
    super.key,
    required this.covered,
    required this.eligible,
    required this.coveredLabel,
    required this.remainderLabel,
    this.percent,
  });

  final int covered;
  final int eligible;
  final String coveredLabel;
  final String remainderLabel;
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final remainder = (eligible - covered).clamp(0, eligible);
    final fraction = eligible == 0 ? 0.0 : covered / eligible;

    // Under half covered is a finding, not a milestone. The meter says so
    // without needing the midwife to read the caption first.
    final Color fillColor = fraction >= 0.8
        ? AppColors.success
        : (fraction >= 0.5 ? AppColors.warning : AppColors.error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(AnalyticsTheme.barRadius),
                  ),
                ),
                Container(
                  height: 14,
                  width: eligible == 0
                      ? 0
                      : (constraints.maxWidth * fraction)
                          .clamp(covered == 0 ? 0.0 : 8.0, constraints.maxWidth),
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(AnalyticsTheme.barRadius),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _MeterKey(color: fillColor, label: coveredLabel, value: covered),
            const SizedBox(width: 18),
            _MeterKey(
              color: AnalyticsTheme.unknownColor,
              label: remainderLabel,
              value: remainder,
            ),
            const Spacer(),
            if (percent != null)
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fillColor,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MeterKey extends StatelessWidget {
  const _MeterKey({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$value', style: AnalyticsTheme.bandValueStyle),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: AnalyticsTheme.axisStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Last period against this one, with the caseload that could have received
/// the service printed underneath.
///
/// This pairing is the whole diagnostic idea in one strip: fewer doses given
/// is only a service problem if the number of mothers who needed them held
/// steady.
class AnalyticsComparisonStrip extends StatelessWidget {
  const AnalyticsComparisonStrip({super.key, required this.comparison});

  final AnalyticsComparison comparison;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Period(
              label: comparison.previousLabel,
              value: comparison.previousValue,
              eligible: comparison.previousEligible,
              unit: comparison.unit,
              emphasised: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              comparison.change < 0
                  ? Icons.trending_down
                  : (comparison.change > 0 ? Icons.trending_up : Icons.trending_flat),
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: _Period(
              label: comparison.currentLabel,
              value: comparison.currentValue,
              eligible: comparison.currentEligible,
              unit: comparison.unit,
              emphasised: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _Period extends StatelessWidget {
  const _Period({
    required this.label,
    required this.value,
    required this.unit,
    required this.emphasised,
    this.eligible,
  });

  final String label;
  final int value;
  final String unit;
  final bool emphasised;
  final int? eligible;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AnalyticsTheme.axisStyle),
        const SizedBox(height: 3),
        Text(
          '$value $unit',
          style: TextStyle(
            fontSize: emphasised ? 15 : 14,
            fontWeight: emphasised ? FontWeight.w700 : FontWeight.w600,
            color: emphasised ? AppColors.brandText : AppColors.textSecondary,
          ),
        ),
        if (eligible != null) ...[
          const SizedBox(height: 2),
          Text('from $eligible pregnant', style: AnalyticsTheme.footnoteStyle),
        ],
      ],
    );
  }
}
