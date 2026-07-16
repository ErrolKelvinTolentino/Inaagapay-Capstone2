// lib/widgets/profile_quick_stats.dart
// Quick stat row showing Age, Children count, and Pregnancies count.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProfileQuickStats extends StatelessWidget {
  final int age;
  final int childrenCount;
  final int pregnanciesCount;

  const ProfileQuickStats({
    super.key,
    required this.age,
    required this.childrenCount,
    required this.pregnanciesCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
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
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              value: age.toString(),
              label: 'Age',
              icon: Icons.cake_outlined,
              color: AppColors.brandPrimary,
            ),
          ),
          _buildDivider(),
          Expanded(
            child: _StatTile(
              value: childrenCount.toString(),
              label: 'Children',
              icon: Icons.child_care_outlined,
              color: AppColors.info,
            ),
          ),
          _buildDivider(),
          Expanded(
            child: _StatTile(
              value: pregnanciesCount.toString(),
              label: 'Pregnancies',
              icon: Icons.pregnant_woman_outlined,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 36,
      width: 1,
      color: AppColors.borderPrimary,
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
