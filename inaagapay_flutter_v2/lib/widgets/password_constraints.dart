// lib/widgets/password_constraints.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/language_service.dart';

class PasswordConstraints extends StatelessWidget {
  final String password;

  const PasswordConstraints({
    super.key,
    required this.password,
  });

  bool get hasMinLength => password.length >= 8;
  bool get hasNumber => RegExp(r'\d').hasMatch(password);
  bool get hasUppercase => RegExp(r'[A-Z]').hasMatch(password);
  bool get hasLowercase => RegExp(r'[a-z]').hasMatch(password);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ConstraintItem(
            label: LanguageService.translate('At least eight characters long',
                'Hindi bababa sa walong character'),
            isValid: hasMinLength),
        _ConstraintItem(
            label: LanguageService.translate(
                'At least one number', 'May kahit isang numero'),
            isValid: hasNumber),
        _ConstraintItem(
            label: LanguageService.translate('At least one uppercase letter',
                'May kahit isang malaking titik'),
            isValid: hasUppercase),
        _ConstraintItem(
            label: LanguageService.translate('At least one lowercase letter',
                'May kahit isang maliit na titik'),
            isValid: hasLowercase),
      ],
    );
  }
}

class _ConstraintItem extends StatelessWidget {
  final String label;
  final bool isValid;

  const _ConstraintItem({required this.label, required this.isValid});

  @override
  Widget build(BuildContext context) {
    final Color color = isValid ? AppColors.success : AppColors.brandPrimary.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.circle : Icons.radio_button_unchecked,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
