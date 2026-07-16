// lib/widgets/dialog_box.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'modal_button.dart';

enum DialogType { info, success, warning, error }

class DialogBox extends StatelessWidget {
  final String title;
  final String content;
  final String buttonText;
  final DialogType type;
  final VoidCallback onPressed;

  const DialogBox({
    super.key,
    required this.title,
    required this.content,
    required this.buttonText,
    required this.onPressed,
    this.type = DialogType.info,
  });

  Color get _accentColor {
    switch (type) {
      case DialogType.success:
        return AppColors.success;
      case DialogType.warning:
        return AppColors.warning;
      case DialogType.error:
        return AppColors.error;
      case DialogType.info:
        return AppColors.brandPrimary;
    }
  }

  IconData get _icon {
    switch (type) {
      case DialogType.warning:
        return Icons.warning_amber_rounded;
      case DialogType.error:
        return Icons.close;
      case DialogType.success:
        return Icons.check;
      case DialogType.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.faintWhite,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _accentColor, width: 3),
              ),
              child: Icon(_icon, size: 36, color: _accentColor),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _accentColor,
              ),
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                content,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 28),
            ModalButton(
              label: buttonText,
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }
}
