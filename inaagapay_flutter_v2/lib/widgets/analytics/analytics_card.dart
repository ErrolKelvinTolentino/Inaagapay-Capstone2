// lib/widgets/analytics/analytics_card.dart
//
// The single analytics card, and the two containers around it.
//
// Every metric renders through [AnalyticsCard] — there is no second card
// design. The anatomy is fixed top to bottom:
//
//     title · period            what this is, and over what window
//     headline · caption        the number, and what it is out of
//     visual                    descriptive
//     comparison                this period against the last
//     insight                   diagnostic — why it looks like this
//     footnote                  what the data cannot tell you
//     action                    prescriptive — the one thing to do
//
// Anything a card cannot say is simply omitted, and the rest closes up. That
// is what keeps twelve metrics from becoming twelve layouts.

import 'package:flutter/material.dart';

import '../../models/midwife_analytics.dart';
import '../../theme/app_colors.dart';
import 'analytics_charts.dart';
import 'analytics_theme.dart';

class AnalyticsCard extends StatelessWidget {
  const AnalyticsCard({super.key, required this.metric, this.onAction});

  final AnalyticsMetric metric;
  final void Function(AnalyticsAction action)? onAction;

  @override
  Widget build(BuildContext context) {
    return AnalyticsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          if (!metric.hasData) ...[
            const SizedBox(height: 16),
            _emptyState(context),
          ] else ...[
            if (metric.headline != null) ...[
              const SizedBox(height: 12),
              _headline(),
            ],
            const SizedBox(height: 18),
            _visual(),
            if (metric.comparison != null) ...[
              const SizedBox(height: 16),
              AnalyticsComparisonStrip(comparison: metric.comparison!),
            ],
            if (metric.insight != null) ...[
              const SizedBox(height: 14),
              _InsightStrip(insight: metric.insight!),
            ],
            if (metric.footnote != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 13,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      metric.footnote!,
                      style: AnalyticsTheme.footnoteStyle,
                    ),
                  ),
                ],
              ),
            ],
            if (metric.prescription != null &&
                metric.prescription!.action != AnalyticsAction.none) ...[
              const SizedBox(height: 6),
              _actionButton(metric.prescription!),
            ],
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(metric.title, style: AnalyticsTheme.titleStyle),
        ),
        if (metric.periodLabel != null) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(metric.periodLabel!, style: AnalyticsTheme.periodStyle),
          ),
        ],
      ],
    );
  }

  Widget _headline() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(metric.headline!, style: AnalyticsTheme.headlineStyle),
        if (metric.headlineCaption != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                metric.headlineCaption!,
                style: AnalyticsTheme.captionStyle,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _visual() {
    switch (metric.kind) {
      case AnalyticsChartKind.donut:
        return AnalyticsDonut(bands: metric.bands);
      case AnalyticsChartKind.bars:
        return AnalyticsVerticalBars(bands: metric.bands);
      case AnalyticsChartKind.rankedBars:
        return AnalyticsRankedBars(bands: metric.bands);
      case AnalyticsChartKind.coverage:
        return AnalyticsCoverageMeter(
          covered: metric.covered ?? 0,
          eligible: metric.eligible ?? 0,
          coveredLabel: 'covered',
          remainderLabel: 'still to reach',
          percent: metric.coveragePercent,
        );
    }
  }

  Widget _emptyState(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.insights_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            metric.emptyMessage ?? 'Not enough records yet.',
            style: AnalyticsTheme.captionStyle,
          ),
        ),
      ],
    );
  }

  Widget _actionButton(AnalyticsPrescription prescription) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onAction == null ? null : () => onAction!(prescription.action),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(prescription.label, style: AnalyticsTheme.actionStyle),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: AppColors.brandPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The diagnostic sentence, in a wash of its own tone.
class _InsightStrip extends StatelessWidget {
  const _InsightStrip({required this.insight});

  final AnalyticsInsight insight;

  @override
  Widget build(BuildContext context) {
    final color = AnalyticsTheme.toneColor(insight.tone);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnalyticsTheme.tint(color, 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AnalyticsTheme.tint(color, 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 16, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(insight.text, style: AnalyticsTheme.insightStyle),
                if (insight.evidence != null) ...[
                  const SizedBox(height: 4),
                  Text(insight.evidence!, style: AnalyticsTheme.footnoteStyle),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The tab strip above the cards.
///
/// Three groups, one visible at a time. The alternative — every metric in one
/// column — is the same information at four times the scroll, which is how
/// dashboards stop being read.
class AnalyticsSegmentedControl extends StatelessWidget {
  const AnalyticsSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == selectedIndex
                        ? AppColors.brandPrimary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: i == selectedIndex
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The band at the top of the dashboard: what needs doing, most urgent first.
class AnalyticsPriorityBoard extends StatelessWidget {
  const AnalyticsPriorityBoard({
    super.key,
    required this.priorities,
    this.isLoading = false,
    this.maxVisible = 4,
    this.onAction,
  });

  final List<AnalyticsPriority> priorities;
  final bool isLoading;
  final int maxVisible;
  final void Function(AnalyticsAction action)? onAction;

  @override
  Widget build(BuildContext context) {
    final visible = priorities.take(maxVisible).toList();
    final hidden = priorities.length - visible.length;

    return AnalyticsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.push_pin_outlined,
                size: 18,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Needs attention', style: AnalyticsTheme.titleStyle),
              ),
              if (priorities.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AnalyticsTheme.tint(AppColors.brandPrimary),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${priorities.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandText,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Checking your caseload…',
                      style: AnalyticsTheme.captionStyle),
                ],
              ),
            )
          else if (visible.isEmpty)
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AnalyticsTheme.tint(AppColors.success, 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Nothing overdue today. Checkups, doses and stock are all '
                    'within range.',
                    style: AnalyticsTheme.captionStyle,
                  ),
                ),
              ],
            )
          else ...[
            for (int i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _PriorityRow(priority: visible[i], onAction: onAction),
            ],
            if (hidden > 0) ...[
              const SizedBox(height: 12),
              Text(
                '+$hidden more waiting',
                style: AnalyticsTheme.footnoteStyle,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({required this.priority, this.onAction});

  final AnalyticsPriority priority;
  final void Function(AnalyticsAction action)? onAction;

  IconData get _icon {
    switch (priority.severity) {
      case AnalyticsSeverity.alert:
        return Icons.warning_amber_rounded;
      case AnalyticsSeverity.watch:
        return Icons.schedule_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AnalyticsTheme.severityColor(priority.severity);
    final tappable =
        onAction != null && priority.action != AnalyticsAction.none;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: tappable ? () => onAction!(priority.action) : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AnalyticsTheme.tint(color, 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AnalyticsTheme.tint(color, 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AnalyticsTheme.tint(color, 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      priority.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      priority.detail,
                      style: AnalyticsTheme.footnoteStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (tappable)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
