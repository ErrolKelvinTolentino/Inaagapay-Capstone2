// lib/widgets/main_button.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MainButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool showIcons;
  final IconData? leftIcon;
  final IconData? rightIcon;
  final bool isWhiteVariant;
  final double? fontSize;

  const MainButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.showIcons = true,
    this.leftIcon,
    this.rightIcon,
    this.isWhiteVariant = false,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isWhiteVariant ? Colors.white : AppColors.brandPrimary,
          foregroundColor: isWhiteVariant ? AppColors.brandPrimary : Colors.white,
          elevation: isWhiteVariant ? 0 : 4,
          shadowColor: isWhiteVariant
              ? Colors.transparent
              : AppColors.brandPrimary.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: isWhiteVariant
                ? BorderSide(color: AppColors.brandPrimary, width: 1)
                : BorderSide.none,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showIcons && leftIcon != null) ...[
              Icon(leftIcon, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontSize ?? 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (showIcons && rightIcon != null) ...[
              const SizedBox(width: 8),
              Icon(rightIcon, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
