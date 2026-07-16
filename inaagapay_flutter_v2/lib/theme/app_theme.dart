import 'app_colors.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'DM Sans',
    scaffoldBackgroundColor: AppColors.bgPrimary,
    colorScheme: ColorScheme.light(
      primary: AppColors.brandPrimary,
      onPrimary: AppColors.textOnColor,
      secondary: AppColors.brandAccent,
      onSecondary: AppColors.textOnColor,
      surface: AppColors.bgSecondary,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: AppColors.textOnColor,
    ),
  );
}
