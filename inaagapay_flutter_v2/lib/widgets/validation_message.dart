// lib/widgets/validation_message.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum ValidationType { info, success, error }

class ValidationMessage extends StatelessWidget {
  final String message;
  final ValidationType type;
  final IconData? icon;

  const ValidationMessage({
    super.key,
    required this.message,
    this.type = ValidationType.error,
    this.icon,
  });

  Color get _color {
    switch (type) {
      case ValidationType.success:
        return AppColors.success;
      case ValidationType.error:
        return AppColors.error;
      case ValidationType.info:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            icon ??
                (type == ValidationType.error
                    ? Icons.error_outline
                    : Icons.info_outline),
            color: _color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: _color,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
