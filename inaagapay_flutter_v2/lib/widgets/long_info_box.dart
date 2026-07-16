// lib/widgets/long_info_box.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class LongInfoBox extends StatelessWidget {
  final IconData icon;
  final List<InlineSpan> text;
  final Color? borderColor;
  final Color? iconColor;

  const LongInfoBox({
    super.key,
    required this.icon,
    required this.text,
    this.borderColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? AppColors.brandPrimary,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 36,
            color: iconColor ?? AppColors.brandPrimary,
          ),
          const SizedBox(width: 12),

          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                ),
                children: text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}