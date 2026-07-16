// lib/widgets/headline.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class Headline extends StatelessWidget {
  final String text;
  final double fontSize;

  const Headline({
    super.key,
    required this.text,
    this.fontSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: AppColors.brandPrimary,
        letterSpacing: 0.2,
      ),
    );
  }
}