// lib/widgets/growth_summary_card.dart
//
// The single growth-and-development view, shared by the midwife and mother
// apps so the two can never disagree about the same child.
//
// Design intent
// -------------
// Weight-for-age and height-for-age lead, because those are the indicators
// Philippine growth monitoring is built on — underweight and stunting. BMI is
// shown as "body proportion" and sits last: it is derived from the other two
// and is primarily a school-age indicator, so presenting it as a headline
// finding for an under-five overstates it.
//
// The three verdicts are visible without a tap. Only the chart changes when
// the metric toggle is used, so the answer to "is this child growing well?"
// never leaves the screen.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/growth_calculator.dart';
import '../theme/app_colors.dart';

/// One growth record, reduced to what this card needs.
class GrowthMeasurement {
  final DateTime takenAt;
  final double heightCm;
  final double weightKg;
  final int ageWeeks;

  const GrowthMeasurement({
    required this.takenAt,
    required this.heightCm,
    required this.weightKg,
    required this.ageWeeks,
  });

  double get bmi {
    if (heightCm <= 0) return 0;
    final heightM = heightCm / 100.0;
    return weightKg / (heightM * heightM);
  }

  double valueFor(GrowthMetric metric) => switch (metric) {
        GrowthMetric.weightForAge => weightKg,
        GrowthMetric.heightForAge => heightCm,
        GrowthMetric.bmiForAge => bmi,
      };
}

class GrowthSummaryCard extends StatefulWidget {
  final String childFirstName;

  /// 'male' or 'female' — drives which WHO reference table is used.
  final String sex;

  /// Chronological, oldest first.
  final List<GrowthMeasurement> measurements;

  final bool isFilipino;

  /// Approved AI narrative, shown on the **mother's** app only.
  ///
  /// Midwives get the rule-based summary instead: it states the same findings
  /// without the reassurance framing, which is written for a parent rather
  /// than for someone deciding whether to act.
  final String? aiInsight;

  /// Name of the midwife who approved the assessment, if any.
  final String? approvedBy;

  final VoidCallback? onViewHistory;

  const GrowthSummaryCard({
    super.key,
    required this.childFirstName,
    required this.sex,
    required this.measurements,
    this.isFilipino = false,
    this.aiInsight,
    this.approvedBy,
    this.onViewHistory,
  });

  @override
  State<GrowthSummaryCard> createState() => _GrowthSummaryCardState();
}

class _GrowthSummaryCardState extends State<GrowthSummaryCard> {
  GrowthMetric _selected = GrowthMetric.weightForAge;
  bool _numbersExpanded = false;

  GrowthMeasurement? get _latest =>
      widget.measurements.isEmpty ? null : widget.measurements.last;

  String _t(String english, String filipino) =>
      widget.isFilipino ? filipino : english;

  double? _zFor(GrowthMetric metric) {
    final latest = _latest;
    if (latest == null) return null;
    return GrowthCalculator.zScoreFor(
      metric,
      latest.valueFor(metric),
      latest.ageWeeks,
      widget.sex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final latest = _latest;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (latest == null)
            _buildEmptyState()
          else ...[
            _buildVerdictRow(),
            const SizedBox(height: 18),
            _buildMetricToggle(),
            const SizedBox(height: 14),
            _buildChart(),
            const SizedBox(height: 14),
            _buildInsight(),
            const SizedBox(height: 4),
            _buildNumbersPanel(),
            _buildDisclaimerAndReferences(),
            _buildFooter(),
          ],
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.trending_up_rounded,
            color: AppColors.brandPrimary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _t('GROWTH & DEVELOPMENT', 'PAGLAKI AT PAG-UNLAD'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Color(0xFF5A5A5A),
            ),
          ),
        ),
        if (_latest != null)
          Text(
            _t('Week ${_latest!.ageWeeks}', 'Linggo ${_latest!.ageWeeks}'),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 110,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.show_chart_rounded, size: 26, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              _t('No growth records yet.',
                  'Wala pang naitalang sukat ng paglaki.'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Verdict row: three indicators, no tap required ────────────────────────

  Widget _buildVerdictRow() {
    return Column(
      children: [
        for (final metric in GrowthMetric.values) ...[
          _VerdictChip(
            label: widget.isFilipino ? metric.labelFilipino : metric.label,
            band: GrowthCalculator.bandForZScore(_zFor(metric)),
            isFilipino: widget.isFilipino,
            isSelected: _selected == metric,
            onTap: () => setState(() => _selected = metric),
          ),
          if (metric != GrowthMetric.values.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  // ── Metric toggle ─────────────────────────────────────────────────────────

  Widget _buildMetricToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          for (final metric in GrowthMetric.values)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selected = metric),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _selected == metric
                        ? AppColors.brandPrimary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    metric.shortLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _selected == metric
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

  // ── Chart ─────────────────────────────────────────────────────────────────

  Widget _buildChart() {
    final measurements = widget.measurements;

    if (measurements.length < 2) {
      return Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.show_chart_rounded,
                  size: 26, color: Colors.grey),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _t(
                    'Two check-ups are needed before a growth line can be drawn.',
                    'Kailangan ng dalawang pagsusuri bago maipakita ang linya ng paglaki.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // x is the record's position, not its age: two check-ups in the same week
    // share an age and would otherwise stack into a vertical line.
    final actual = <FlSpot>[];
    final minBand = <FlSpot>[];
    final maxBand = <FlSpot>[];

    for (var i = 0; i < measurements.length; i++) {
      final m = measurements[i];
      actual.add(FlSpot(i.toDouble(), m.valueFor(_selected)));

      final range =
          GrowthCalculator.standardRangeAt(_selected, m.ageWeeks, widget.sex);
      if (range != null) {
        minBand.add(FlSpot(i.toDouble(), range['min']!));
        maxBand.add(FlSpot(i.toDouble(), range['max']!));
      }
    }

    final all = [...actual, ...minBand, ...maxBand];
    final rawMin = all.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final rawMax = all.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final pad = ((rawMax - rawMin) * 0.12).clamp(0.5, 6.0);
    final minY = rawMin - pad;
    final maxY = rawMax + pad;
    final yInterval = ((maxY - minY) / 4).clamp(0.5, 20.0);
    final yDecimals = yInterval < 1.5 ? 1 : 0;
    final labelEvery = (measurements.length / 5).ceil().clamp(1, 999);

    return SizedBox(
      height: 170,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (measurements.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: yInterval,
            verticalInterval: labelEvery.toDouble(),
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey.shade100, strokeWidth: 1),
            getDrawingVerticalLine: (_) =>
                FlLine(color: Colors.grey.shade100, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: labelEvery.toDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= measurements.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'W${measurements[i].ageWeeks}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: yInterval,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(yDecimals),
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: actual,
              isCurved: true,
              color: AppColors.brandPrimary,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 4,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: AppColors.brandPrimary,
                ),
              ),
            ),
            if (minBand.isNotEmpty)
              LineChartBarData(
                spots: minBand,
                isCurved: true,
                color: Colors.grey.shade400,
                barWidth: 1.5,
                dashArray: [5, 5],
                dotData: const FlDotData(show: false),
              ),
            if (maxBand.isNotEmpty)
              LineChartBarData(
                spots: maxBand,
                isCurved: true,
                color: Colors.grey.shade400,
                barWidth: 1.5,
                dashArray: [5, 5],
                dotData: const FlDotData(show: false),
              ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((spot) {
                final i = spot.x.round();
                final week = i >= 0 && i < measurements.length
                    ? measurements[i].ageWeeks
                    : 0;
                final prefix = switch (spot.barIndex) {
                  0 => '',
                  1 => '-2 SD  ',
                  _ => '+2 SD  ',
                };
                return LineTooltipItem(
                  '${prefix}W$week\n${spot.y.toStringAsFixed(1)} ${_selected.unit}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Insight ───────────────────────────────────────────────────────────────

  Widget _buildInsight() {
    final ai = _aiInsightForLanguage();
    final text = ai ?? _buildFallbackInsight();

    final anyOutside = GrowthMetric.values
        .any((m) => !GrowthCalculator.bandForZScore(_zFor(m)).isWithin);

    if (!anyOutside) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.5,
          color: Colors.grey.shade700,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 17, color: AppColors.warning),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The AI narrative for the reader's language, or null when there is none.
  ///
  /// The stored text is bilingual, written as "## English ... ## Filipino ...".
  /// Only the reader's own language is shown — rendering both leaves the raw
  /// markdown headers on screen and asks a mother to skip past a language she
  /// did not choose.
  String? _aiInsightForLanguage() {
    final raw = widget.aiInsight?.trim();
    if (raw == null || raw.isEmpty) return null;

    final normalized = raw.replaceAll('\r\n', '\n');
    final wanted = widget.isFilipino ? 'filipino' : 'english';
    final alternate = widget.isFilipino ? 'english' : 'filipino';

    final buffer = <String>[];
    var capturing = false;

    for (final line in normalized.split('\n')) {
      final heading = line.trim().toLowerCase().replaceAll('#', '').trim();
      if (heading == wanted || heading == 'tagalog' && widget.isFilipino) {
        capturing = true;
        continue;
      }
      if (heading == alternate || (heading == 'tagalog' && !widget.isFilipino)) {
        capturing = false;
        continue;
      }
      if (capturing) buffer.add(line);
    }

    final section = buffer.join('\n').trim();
    if (section.isNotEmpty) return section;

    // No language headers found — return the text as-is, minus any stray
    // markdown headings, rather than dropping the insight entirely.
    return normalized
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n')
        .trim();
  }

  /// Plain-language summary of all three indicators at once.
  ///
  /// One paragraph rather than three, because the three findings come from two
  /// measurements — separate narratives would repeat themselves and can drift
  /// apart, which is exactly what happened when each screen wrote its own.
  ///
  /// Every indicator the card shows a verdict chip for gets a sentence here.
  /// Body proportion previously had none: a child could be flagged "Above
  /// standard range" in the row of chips and find nothing in the paragraph
  /// explaining it. The word "also" was likewise baked into the height
  /// sentence, so whenever weight was fine the paragraph opened on "Height is
  /// also…" with nothing for "also" to refer back to.
  String _buildFallbackInsight() {
    final name = widget.childFirstName.trim().isEmpty
        ? _t('Your child', 'Ang iyong anak')
        : widget.childFirstName.trim();

    final within = <GrowthMetric>[];
    final findings = <String>[];

    for (final metric in GrowthMetric.values) {
      final band = GrowthCalculator.bandForZScore(_zFor(metric));
      if (band.isWithin) {
        within.add(metric);
      } else {
        findings.add(_outsideSentence(metric, band, name));
      }
    }

    if (findings.isEmpty) {
      return _t(
        '$name is growing well. Weight, height and body proportion are all '
            'within the standard range for this age.',
        'Maganda ang paglaki ni $name. Nasa tamang saklaw ang timbang, tangkad '
            'at hubog ng katawan para sa edad niya.',
      );
    }

    // What needs attention leads; what is fine follows as reassurance. Both are
    // said — a mother told only what is wrong cannot tell whether the rest was
    // checked at all.
    final parts = <String>[...findings];

    if (within.isNotEmpty) {
      final english = _joinWords(within.map(_plainLabelEnglish).toList(), 'and');
      final filipino = _joinWords(within.map(_plainLabelFilipino).toList(), 'at');
      parts.add(_t(
        '${_capitalise(english)} ${within.length == 1 ? 'is' : 'are'} within '
            'the standard range for this age.',
        'Nasa tamang saklaw naman ang $filipino para sa edad niya.',
      ));
    }

    parts.add(_t(
      'Keep up regular check-ups so growth can be followed closely.',
      'Ipagpatuloy ang regular na pagpapatingin upang masubaybayang mabuti ang paglaki.',
    ));

    return parts.join(' ');
  }

  /// What one indicator sitting outside the standard range means, in words a
  /// mother can act on. No severity grading and no condition names — "stunted",
  /// "wasted" and "overweight" are assessments a clinician makes, not labels a
  /// card applies.
  String _outsideSentence(GrowthMetric metric, GrowthBand band, String name) {
    final isBelow = band == GrowthBand.below;
    return switch (metric) {
      GrowthMetric.weightForAge => isBelow
          ? _t(
              '$name weighs less than most children this age.',
              'Mas magaan si $name kaysa sa karamihan ng bata sa edad niya.',
            )
          : _t(
              '$name weighs more than most children this age.',
              'Mas mabigat si $name kaysa sa karamihan ng bata sa edad niya.',
            ),
      GrowthMetric.heightForAge => isBelow
          ? _t(
              '$name is shorter than most children this age.',
              'Mas maikli si $name kaysa sa karamihan ng bata sa edad niya.',
            )
          : _t(
              '$name is taller than most children this age.',
              'Mas matangkad si $name kaysa sa karamihan ng bata sa edad niya.',
            ),
      // Deliberately plainer than the other two. Body proportion is BMI-for-age
      // and its meaning depends on the height it is measured against, so
      // restating it as a weight sentence beside the weight sentence above
      // would read as a contradiction to anyone who is not a clinician.
      GrowthMetric.bmiForAge => isBelow
          ? _t(
              'Body proportion is below the usual range for this age.',
              'Mababa sa karaniwang saklaw ang hubog ng katawan para sa edad niya.',
            )
          : _t(
              'Body proportion is above the usual range for this age.',
              'Mataas sa karaniwang saklaw ang hubog ng katawan para sa edad niya.',
            ),
    };
  }

  static String _plainLabelEnglish(GrowthMetric metric) => switch (metric) {
        GrowthMetric.weightForAge => 'weight',
        GrowthMetric.heightForAge => 'height',
        GrowthMetric.bmiForAge => 'body proportion',
      };

  static String _plainLabelFilipino(GrowthMetric metric) => switch (metric) {
        GrowthMetric.weightForAge => 'timbang',
        GrowthMetric.heightForAge => 'tangkad',
        GrowthMetric.bmiForAge => 'hubog ng katawan',
      };

  static String _joinWords(List<String> items, String conjunction) {
    if (items.length <= 1) return items.isEmpty ? '' : items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} '
        '$conjunction ${items.last}';
  }

  static String _capitalise(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  // ── Numbers, on demand ────────────────────────────────────────────────────

  Widget _buildNumbersPanel() {
    final latest = _latest!;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          _t('See the numbers', 'Tingnan ang mga numero'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.brandPrimary,
          ),
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 2, bottom: 6),
        dense: true,
        onExpansionChanged: (v) => setState(() => _numbersExpanded = v),
        trailing: Icon(
          _numbersExpanded ? Icons.expand_less : Icons.expand_more,
          size: 20,
          color: AppColors.brandPrimary,
        ),
        children: [
          for (final metric in GrowthMetric.values)
            _buildNumberRow(metric, latest),
          const SizedBox(height: 10),
          Text(
            _t(
              'Ranges follow the WHO Child Growth Standards (±2 SD for age and sex). This is a guide for monitoring, not a diagnosis.',
              'Ang saklaw ay batay sa WHO Child Growth Standards (±2 SD ayon sa edad at kasarian). Gabay ito sa pagsubaybay, hindi diagnosis.',
            ),
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  /// One indicator: the child's actual measurement beside the standard range
  /// for their age.
  ///
  /// No z-scores and no severity wording. "z = -3.4" and "severe" are clinical
  /// shorthand that reads as a diagnosis; the measurement next to the expected
  /// range says the same thing in numbers anyone can check.
  Widget _buildNumberRow(GrowthMetric metric, GrowthMeasurement latest) {
    final range =
        GrowthCalculator.standardRangeAt(metric, latest.ageWeeks, widget.sex);
    final value = latest.valueFor(metric);
    final band = GrowthCalculator.bandForZScore(_zFor(metric));
    final color = band.isWithin ? AppColors.success : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isFilipino ? metric.labelFilipino : metric.label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _numberCell(
                  _t('This check-up', 'Ngayong pagsusuri'),
                  '${value.toStringAsFixed(1)} ${metric.unit}',
                  color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _numberCell(
                  _t('Standard for age', 'Pamantayan sa edad'),
                  range == null
                      ? '—'
                      : '${range['min']!.toStringAsFixed(1)}–${range['max']!.toStringAsFixed(1)} ${metric.unit}',
                  Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numberCell(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Disclaimer & references ───────────────────────────────────────────────

  /// The standard this card judges by, and the boundary of what it claims.
  ///
  /// Same treatment as the weight-gain and blood pressure cards: a reading
  /// should always show whose rule it was measured against, and the full
  /// wording sits behind a tap rather than in the way. Until now the only
  /// attribution was one line buried inside "See the numbers", which a reader
  /// had to open the panel to find.
  Widget _buildDisclaimerAndReferences() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          _t('Clinical Disclaimer & References',
              'Clinical Disclaimer at Sanggunian'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.brandPrimary,
          ),
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 2, bottom: 6),
        dense: true,
        // The sibling tile two methods up sets a pink trailing icon; this one
        // did not, so it fell back to the theme default and drew the only
        // black chevron on the card, directly under a pink one.
        iconColor: AppColors.brandPrimary,
        collapsedIconColor: AppColors.brandPrimary,
        children: [
          Text(
            _t(
              'Disclaimer: This card compares a measurement against the WHO '
                  'Child Growth Standards for the child\'s age and sex and '
                  'reports which band it falls in. It does not diagnose '
                  'undernutrition, stunting, wasting or overweight — those are '
                  'assessments made by a clinician. It is for growth monitoring '
                  'support only and does not replace professional assessment.',
              'Paalala: Inihahambing lamang ng card na ito ang sukat sa WHO '
                  'Child Growth Standards ayon sa edad at kasarian ng bata, at '
                  'ipinapakita kung saang saklaw ito nahuhulog. Hindi ito '
                  'nagbibigay ng diagnosis ng malnutrisyon, stunting, wasting o '
                  'sobrang timbang — ang mga iyon ay pagsusuri ng doktor o '
                  'midwife. Gabay lamang ito sa pagsubaybay ng paglaki at hindi '
                  'kapalit ng propesyonal na pagsusuri.',
            ),
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'Bands: a measurement is reported as within the standard range '
                  'when it sits inside ±2 SD of the WHO median for age and sex, '
                  'and below or above the range outside that. Body proportion '
                  'is BMI-for-age; for under-fives it is supporting context, '
                  'while weight-for-age and height-for-age are the indicators '
                  'routine growth monitoring is built on.',
              'Saklaw: itinuturing na nasa tamang saklaw ang sukat kapag nasa '
                  'loob ito ng ±2 SD ng WHO median ayon sa edad at kasarian, at '
                  'mababa o mataas kung lampas doon. Ang hubog ng katawan ay '
                  'BMI-for-age; para sa wala pang limang taon, karagdagang '
                  'konteksto lamang ito, samantalang ang timbang sa edad at '
                  'tangkad sa edad ang batayan ng regular na pagsubaybay.',
            ),
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'References:\n'
            '• WHO Multicentre Growth Reference Study Group. (2006). WHO Child '
            'Growth Standards: Length/height-for-age, weight-for-age, '
            'weight-for-length, weight-for-height and body mass index-for-age: '
            'Methods and development. Geneva: World Health Organization.\n'
            '• World Health Organization. (2006). WHO Child Growth Standards: '
            'Simplified field tables (z-scores), birth to 5 years. '
            'https://www.who.int/tools/child-growth-standards/standards',
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'Values in this app are read from the WHO simplified field tables '
                  'for weight-for-age, length/height-for-age and BMI-for-age, '
                  'with separate tables for boys and girls.',
              'Ang mga halaga sa app na ito ay mula sa WHO simplified field '
                  'tables para sa timbang sa edad, tangkad sa edad at '
                  'BMI-for-age, na may magkahiwalay na talahanayan para sa mga '
                  'batang lalaki at babae.',
            ),
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final hasApprover = widget.approvedBy?.trim().isNotEmpty == true;
    if (!hasApprover && widget.onViewHistory == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          if (hasApprover)
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.verified_outlined,
                      size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _t('Reviewed by ${widget.approvedBy}',
                          'Sinuri ni ${widget.approvedBy}'),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const Spacer(),
          if (widget.onViewHistory != null)
            GestureDetector(
              onTap: widget.onViewHistory,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _t('View history', 'Tingnan ang kasaysayan'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 14, color: AppColors.brandPrimary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One indicator's verdict. Tapping it also selects that metric in the chart,
/// so the chip and the chart stay in step.
class _VerdictChip extends StatelessWidget {
  final String label;
  final GrowthBand band;
  final bool isFilipino;
  final bool isSelected;
  final VoidCallback onTap;

  const _VerdictChip({
    required this.label,
    required this.band,
    required this.isFilipino,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Amber, not red: a value outside ±2 SD warrants a closer look, not alarm.
    // Reserving red keeps it meaningful for genuine emergencies elsewhere.
    final color = band.isWithin ? AppColors.success : AppColors.warning;
    final statusText = isFilipino ? band.labelFilipino : band.label;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.35)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
