// lib/widgets/growth_line_chart.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_colors.dart';

class GrowthLineChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color lineColor;
  final String unit;

  const GrowthLineChart({
    super.key,
    required this.values,
    required this.labels,
    required this.unit,
    this.lineColor = AppColors.brandPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.6,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
  show: true,
  drawVerticalLine: true,
  horizontalInterval: 1,
  getDrawingHorizontalLine: (value) {
    return FlLine(
      strokeWidth: 1,
      color: Colors.grey.withValues(alpha: 0.2),
      dashArray: [5, 5],
    );
  },
  getDrawingVerticalLine: (value) {
    return FlLine(
      strokeWidth: 1,
      color: Colors.grey.withValues(alpha: 0.2),
      dashArray: [5, 5],
    );
  },
),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
              ),
            ),
            bottomTitles: AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    interval: 1, // 👈 VERY IMPORTANT
    getTitlesWidget: (value, meta) {
      if (value % 1 != 0) {
        return const SizedBox.shrink(); // 👈 skip decimals
      }

      final index = value.toInt();
      if (index < 0 || index >= labels.length) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          labels[index],
          style: const TextStyle(fontSize: 10),
        ),
      );
    },
  ),
),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                values.length,
                (i) => FlSpot(i.toDouble(), values[i]),
              ),
              isCurved: true,
              color: lineColor,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: lineColor.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
