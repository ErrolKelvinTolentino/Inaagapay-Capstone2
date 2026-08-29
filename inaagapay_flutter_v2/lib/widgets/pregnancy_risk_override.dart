// lib/widgets/pregnancy_risk_override.dart
//
// The midwife's own call on a pregnancy's risk level.
//
// The app flags risk from cited thresholds — blood pressure, fetal heart rate,
// weight gain, symptoms — but the flag is a screening output, not a judgement.
// A midwife knows things the record does not: how the mother looked, what she
// said at the door, a history the form has no field for. This is where she
// overrides, and her choice is what `pregnancies.pregnancy_risk_level` stores.
//
// It lives here rather than in one screen because the decision is a property
// of the PREGNANCY, not of the encounter that prompted it. A worrying
// ultrasound or an anaemic blood count is as good a reason to raise the level
// as anything found at a checkup, and a midwife who has to reopen a prenatal
// checkup to record that has been given a filing task instead of a clinical
// one.
//
// Deliberately two options. Splitting risk further invites a middle setting
// that means "somewhat", and the referral pathway this feeds has two states.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PregnancyRiskOverride extends StatelessWidget {
  const PregnancyRiskOverride({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Risk Override',
    this.helperText,
  });

  /// `low` or `high`, as stored on the pregnancy.
  final String value;

  final ValueChanged<String> onChanged;
  final String label;

  /// Optional line under the control, for screens that want to say what the
  /// level currently reflects.
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _option(context, 'low', 'Low', AppColors.success),
                const SizedBox(width: 8),
                _option(context, 'high', 'High', AppColors.error),
              ],
            ),
          ],
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText!,
            style: const TextStyle(
              fontSize: 11,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _option(
      BuildContext context, String levelKey, String text, Color color) {
    final isSelected = value.toLowerCase() == levelKey;

    return GestureDetector(
      onTap: () => onChanged(levelKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 13,
              color: isSelected ? color : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
