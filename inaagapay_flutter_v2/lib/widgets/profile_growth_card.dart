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
                      _formatAog(data['aog']),
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
        ],
      ),
    );
  }

  String _formatAog(dynamic aogValue) {
    if (aogValue == null || aogValue.toString() == 'N/A') return 'N/A';
    final double? aogDouble = double.tryParse(aogValue.toString());
    if (aogDouble == null || aogDouble <= 0) return 'N/A';

    final int weeks = aogDouble.floor();
    final int days = ((aogDouble - weeks) * 7).round();

    return '$weeks Week${weeks == 1 ? "" : "s"} $days Day${days == 1 ? "" : "s"}';
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
