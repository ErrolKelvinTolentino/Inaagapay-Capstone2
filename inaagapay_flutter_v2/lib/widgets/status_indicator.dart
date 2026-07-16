// lib/widgets/status_indicator.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum StatusIndicatorType {
  normal,
  underweight,
  overweight,
  obese,
  overdue,
  late,
  onTime,
  pending,
  ongoing,
}

class StatusIndicator extends StatelessWidget {
  final StatusIndicatorType status;

  const StatusIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final _StatusStyle style = _statusStyle(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (style.icon != null) ...[
            Icon(style.icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            style.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

_StatusStyle _statusStyle(StatusIndicatorType status) {
  switch (status) {
    case StatusIndicatorType.normal:
      return _StatusStyle(
        label: 'Normal',
        backgroundColor: AppColors.success,
        icon: Icons.check_circle_rounded,
      );

    case StatusIndicatorType.onTime:
      return _StatusStyle(
        label: 'On Time',
        backgroundColor: AppColors.success,
        icon: Icons.schedule_rounded,
      );

    case StatusIndicatorType.underweight:
      return _StatusStyle(
        label: 'Underweight',
        backgroundColor: AppColors.warning,
        icon: Icons.trending_down_rounded,
      );

    case StatusIndicatorType.overweight:
      return _StatusStyle(
        label: 'Overweight',
        backgroundColor: AppColors.warning,
        icon: Icons.trending_up_rounded,
      );

    case StatusIndicatorType.obese:
      return _StatusStyle(
        label: 'Obese',
        backgroundColor: AppColors.error,
        icon: Icons.warning_rounded,
      );

    case StatusIndicatorType.overdue:
      return _StatusStyle(
        label: 'Overdue',
        backgroundColor: AppColors.error,
        icon: Icons.error_rounded,
      );

    case StatusIndicatorType.late:
      return _StatusStyle(
        label: 'Late',
        backgroundColor: AppColors.error,
        icon: Icons.schedule_rounded,
      );

    case StatusIndicatorType.pending:
      return _StatusStyle(
        label: 'Pending',
        backgroundColor: AppColors.warning,
      );

    case StatusIndicatorType.ongoing:
      return _StatusStyle(
        label: 'Ongoing',
        backgroundColor: AppColors.warning,
      );
  }
}

class _StatusStyle {
  final String label;
  final Color backgroundColor;
  final IconData? icon;

  const _StatusStyle({
    required this.label,
    required this.backgroundColor,
    this.icon,
  });
}