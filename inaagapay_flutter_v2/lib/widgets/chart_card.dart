import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/growth_line_chart.dart';

class ChartCard extends StatelessWidget {
  final String title;
  final IconData? headerIcon;

  // Chart
  final List<double> values;
  final List<String> labels;
  final String unit;
  final Color lineColor;
  final Color? titleColor;
  final List<dynamic> referenceCurves;

  // Records (optional)
  final String? startingLabel;
  final String? startingValue;
  final String? latestLabel;
  final String? latestValue;

  // Insight text
  final String insightText;

  const ChartCard({
    super.key,
    required this.title,
    this.headerIcon,
    this.titleColor,
    required this.values,
    required this.labels,
    required this.unit,
    required this.lineColor,
    this.referenceCurves = const [],
    this.startingLabel,
    this.startingValue,
    this.latestLabel,
    this.latestValue,
    required this.insightText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🏷 HEADER
          Row(
            children: [
              if (headerIcon != null) ...[
                Icon(headerIcon, color: AppColors.brandPrimary, size: 20),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: titleColor ?? AppColors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 📈 CHART
          Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(
      maxWidth: 400, // 👈 keeps chart centered on big screens
    ),
    child: AspectRatio(
      aspectRatio: 1.8, // 👈 adjust if needed (1.6–2.0 range is nice)
      child: GrowthLineChart(
        values: values,
        labels: labels,
        unit: unit,
        lineColor: lineColor,
      ),
    ),
  ),
),

          const SizedBox(height: 16),

          // 📌 STARTING RECORD
          if (startingLabel != null && startingValue != null) ...[
            _RecordPill(
              icon: Icons.flag,
              label: startingLabel!,
              value: startingValue!,
            ),
            const SizedBox(height: 10),
          ],

          // 📌 LATEST RECORD
          if (latestLabel != null && latestValue != null) ...[
            _RecordPill(
              icon: Icons.trending_up,
              label: latestLabel!,
              value: latestValue!,
            ),
            const SizedBox(height: 14),
          ],

          // 💡 INSIGHT
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  insightText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RecordPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brandPrimary),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.brandPrimary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
