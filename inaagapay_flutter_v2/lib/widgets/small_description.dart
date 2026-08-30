import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SmallDescription extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  final TextAlign? textAlign;
  final MainAxisAlignment rowAlignment;

  const SmallDescription({
    super.key,
    required this.text,
    this.icon,
    this.color,
    this.textAlign,
    this.rowAlignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = color ?? AppColors.textSecondary;

    return Row(
      mainAxisAlignment: rowAlignment,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 18,
            color: textColor,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            textAlign: textAlign,
            style: TextStyle(
              fontSize: 13,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}
