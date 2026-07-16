import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class TrimesterCard extends StatelessWidget {
  final int value;
  final String title;
  final Color? backgroundColor;

  const TrimesterCard({
    super.key,
    required this.value,
    required this.title,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 18,
        horizontal: 16,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.bgSecondary, // default soft pink
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.borderPrimary,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 22, // slightly smaller than overview stats
              fontWeight: FontWeight.w600,
              color: AppColors.brandText,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.3,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
