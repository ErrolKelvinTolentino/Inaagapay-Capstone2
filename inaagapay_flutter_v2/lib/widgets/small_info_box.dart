// lib/widgets/small_info_box.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SmallInfoBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? borderColor;
  final Color? iconColor;

  const SmallInfoBox({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.borderColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? AppColors.brandPrimary,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: iconColor ?? AppColors.brandPrimary,
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            softWrap: true,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            softWrap: true,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
