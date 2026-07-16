import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/vaccine_schedule.dart';
import 'status_indicator.dart';

class VaccineList extends StatelessWidget {
  final Map<String, VaccineStatus> statuses;
  final int childAgeInWeeks;

  const VaccineList({
    super.key,
    required this.statuses,
    required this.childAgeInWeeks,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: vaccineSchedule.map((group) {
        return _VaccineGroupCard(
          group: group,
          statuses: statuses,
          childAgeInWeeks: childAgeInWeeks,
        );
      }).toList(),
    );
  }
}

class _VaccineGroupCard extends StatelessWidget {
  final VaccineAgeGroup group;
  final Map<String, VaccineStatus> statuses;
  final int childAgeInWeeks;

  const _VaccineGroupCard({
    required this.group,
    required this.statuses,
    required this.childAgeInWeeks,
  });

  @override
  Widget build(BuildContext context) {
    // 🧠 determine if age is reached
    final bool ageReached = childAgeInWeeks >= group.week;

    // 🧠 determine vaccine completion
    final bool allDone = group.vaccines.every(
      (v) => statuses[v.key] == VaccineStatus.done,
    );

    Color headerColor;
    IconData headerIcon;

    if (!ageReached) {
      headerColor = AppColors.brandPrimary;
      headerIcon = Icons.radio_button_unchecked;
    } else if (allDone) {
      headerColor = AppColors.success;
      headerIcon = Icons.check_circle;
    } else {
      headerColor = AppColors.warning;
      headerIcon = Icons.circle;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🏷 HEADER
            Row(
              children: [
                Icon(headerIcon, color: headerColor),
                const SizedBox(width: 8),
                Text(
                  group.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: headerColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 💉 VACCINES
            ...group.vaccines.map((vaccine) {
              final status = statuses[vaccine.key] ??
                  (ageReached ? VaccineStatus.pending : VaccineStatus.locked);

              return _VaccineRow(
                name: vaccine.name,
                status: status,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _VaccineRow extends StatelessWidget {
  final String name;
  final VaccineStatus status;

  const _VaccineRow({
    required this.name,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    Widget trailing;

    switch (status) {
      case VaccineStatus.done:
        color = AppColors.success;
        trailing = TextButton(
          onPressed: () {},
          child: const Text('View Details'),
        );
        break;

      case VaccineStatus.pending:
        color = AppColors.warning;
        trailing = Container(
          child: const StatusIndicator(
            status: StatusIndicatorType.pending,
          ),
        );
        break;

      case VaccineStatus.locked:
        color = AppColors.brandPrimary;
        trailing = const SizedBox();
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            status == VaccineStatus.done
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 14,
                color: color,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
