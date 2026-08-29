// lib/widgets/branded_date_picker.dart
//
// The app's single date picker. Extracted from the Add Mother wizard so every
// form gets the same brand-themed calendar instead of the default Material one.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Shows the InaAgapay-themed date picker.
///
/// [initialDate] is clamped into the [firstDate]-[lastDate] range, because
/// showDatePicker asserts rather than degrades when it falls outside.
Future<DateTime?> showBrandedDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  DateTime clampedInitial = initialDate;
  if (clampedInitial.isBefore(firstDate)) {
    clampedInitial = firstDate;
  } else if (clampedInitial.isAfter(lastDate)) {
    clampedInitial = lastDate;
  }

  return showDatePicker(
    context: context,
    initialDate: clampedInitial,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.brandPrimary,
            onPrimary: Colors.white,
            onSurface: AppColors.brandText,
            secondary: AppColors.brandPrimary,
            surface: Colors.white,
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            backgroundColor: Colors.white,
            elevation: 4,
            surfaceTintColor: Colors.transparent,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandPrimary,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            headerBackgroundColor: Colors.white,
            headerForegroundColor: AppColors.brandText,
            headerHeadlineStyle: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.brandText,
            ),
            headerHelpStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.brandPrimary,
            ),
            // The rule between the header and the calendar.
            //
            // Material draws it in the theme's outline colour, which lands as
            // a hard black bar edge-to-edge — the heaviest thing in a dialog
            // that is otherwise all soft pink. Dropped to the same hairline
            // every card in the app uses, so it still separates the date being
            // edited from the grid without being the first thing seen.
            dividerColor: AppColors.borderPrimary,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        child: child!,
      );
    },
  );
}

/// Shows the InaAgapay-themed date range picker.
Future<DateTimeRange?> showBrandedDateRangePicker({
  required BuildContext context,
  DateTimeRange? initialDateRange,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
  String? saveText,
  String? cancelText,
}) {
  return showDateRangePicker(
    context: context,
    initialDateRange: initialDateRange,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
    saveText: saveText,
    cancelText: cancelText,
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.brandPrimary,
            onPrimary: Colors.white,
            onSurface: AppColors.brandText,
            secondary: AppColors.brandPrimary,
            surface: Colors.white,
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            backgroundColor: Colors.white,
            elevation: 4,
            surfaceTintColor: Colors.transparent,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandPrimary,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            headerBackgroundColor: Colors.white,
            headerForegroundColor: AppColors.brandText,
            headerHeadlineStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.brandText,
            ),
            headerHelpStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.brandPrimary,
            ),
            dividerColor: AppColors.borderPrimary,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        child: child!,
      );
    },
  );
}
