// lib/widgets/password_strength_indicator.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/password_strength.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final PasswordStrength strength;

  const PasswordStrengthIndicator({super.key, required this.strength});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    double value;

    switch (strength) {
      case PasswordStrength.weak:
        text = 'Weak';
        color = AppColors.error;
        value = 0.33;
        break;
      case PasswordStrength.medium:
        text = 'Medium';
        color = AppColors.warning;
        value = 0.66;
        break;
      case PasswordStrength.strong:
        text = 'Strong';
        color = AppColors.success;
        value = 1.0;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 100,
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
