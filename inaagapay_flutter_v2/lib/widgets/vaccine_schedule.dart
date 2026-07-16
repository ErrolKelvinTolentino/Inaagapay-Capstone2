import 'package:flutter/material.dart';


enum VaccineScheduleStatus {
  overdue,
  onSchedule,
}


class VaccineScheduleStatusBadge extends StatelessWidget {
  final VaccineScheduleStatus status;


  const VaccineScheduleStatusBadge({
    super.key,
    required this.status,
  });


  @override
  Widget build(BuildContext context) {
    final bool isOverdue = status == VaccineScheduleStatus.overdue;


    final Color bgColor = isOverdue
        ? const Color(0xFFF06A6A) // soft red
        : const Color(0xFF6ED3B2); // mint green


    final String label =
        isOverdue ? 'Vaccine overdue' : 'Vaccine on schedule';


    final IconData icon =
        isOverdue ? Icons.vaccines : Icons.vaccines_outlined;


    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // 👈 keeps it SMALL
        children: [
          Icon(
            icon,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}



