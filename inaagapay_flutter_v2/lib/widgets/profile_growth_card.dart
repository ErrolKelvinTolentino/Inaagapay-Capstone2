// lib/widgets/profile_growth_card.dart
// Latest growth data card (height, weight, BMI) for the Overview tab.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'profile_helpers.dart';

class ProfileGrowthCard extends StatelessWidget {
  final bool isLoading;
  final Map<String, dynamic>? growthData;

  const ProfileGrowthCard({
    super.key,
    required this.isLoading,
    this.growthData,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildShell(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brandPrimary,
              ),
            ),
          ),
        ),
      );
    }

    if (growthData == null) {
      return _buildShell(
        child: const Column(
          children: [
            SizedBox(height: 8),
            Icon(Icons.bar_chart_outlined,
                size: 40, color: AppColors.textSecondary),
            SizedBox(height: 8),
            Text('No growth data yet',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
            SizedBox(height: 4),
            Text(
              'Growth data will appear after the first prenatal checkup',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
          ],
        ),
      );
    }

    final data = growthData!;
    final bmiStatusStr = data['bmi_status'] as String? ?? 'Normal';
    final bmiStatusColor = getBMIStatusColor(bmiStatusStr);

    return _buildShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date + AOG badge row
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 14, color: AppColors.brandPrimary),
                    const SizedBox(width: 6),
                    Text(
                      formatProfileDate(data['date']),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                if (data['aog'] != 'N/A')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${data['aog']} weeks',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Metrics row (Height & Weight equal-sized)
          Row(
            children: [
              Expanded(
                child: _GrowthMetricTile(
                  icon: Icons.height,
                  label: 'Height',
                  value: (data['height'] as double) > 0
                      ? '${(data['height'] as double).toStringAsFixed(1)} cm'
                      : 'N/R',
                  color: AppColors.brandPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GrowthMetricTile(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Weight',
                  value: (data['weight'] as double) > 0
                      ? '${(data['weight'] as double).toStringAsFixed(1)} kg'
                      : 'N/R',
                  color: AppColors.info,
                ),
              ),
            ],
          ),

          // BMI row (placed on another row, pill-like classification badge)
          if (data['bmi'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bmiStatusColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: bmiStatusColor.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calculate_outlined,
                      size: 16, color: bmiStatusColor),
                  const SizedBox(width: 8),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      children: [
                        const TextSpan(text: 'BMI: '),
                        TextSpan(
                          text: (data['bmi'] as double).toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: bmiStatusColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      bmiStatusStr,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calculate_outlined,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'BMI: Not computed',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.show_chart_rounded,
                    size: 16, color: AppColors.brandPrimary),
              ),
              const SizedBox(width: 8),
              const Text(
                'Latest Growth Records',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Single metric tile ────────────────────────────────────────────────────

class _GrowthMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const _GrowthMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
