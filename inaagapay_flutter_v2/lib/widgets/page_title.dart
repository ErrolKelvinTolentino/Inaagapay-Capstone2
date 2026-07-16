// lib/widgets/page_title.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PageTitle extends StatelessWidget {
  final String title;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final Color? color;

  const PageTitle({
    super.key,
    required this.title,
    this.leadingIcon,
    this.trailingIcon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = color ?? AppColors.brandText;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leadingIcon != null) ...[
          Icon(
            leadingIcon,
            color: textColor,
            size: 24,
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            title.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(
            trailingIcon,
            color: textColor,
            size: 24,
          ),
        ],
      ],
    );
  }
}
