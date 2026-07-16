// lib/widgets/progressive_step_indicator.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProgressiveStepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const ProgressiveStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (index) {
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index <= currentStep
                ? AppColors.brandAccent
                : AppColors.textSecondary.withValues(alpha: 0.3),
          ),
        );
      }),
    );
  }
}