// lib/widgets/pregnancy_actions_card.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PregnancyActionsCard extends StatelessWidget {
  final VoidCallback onAddCheckup;
  final VoidCallback onUltrasound;
  final VoidCallback onLabTest;
  final VoidCallback onConclude;

  const PregnancyActionsCard({
    super.key,
    required this.onAddCheckup,
    required this.onUltrasound,
    required this.onLabTest,
    required this.onConclude,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quick Actions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _ActionBtn(
                    label: 'Add Checkup',
                    icon: Icons.add,
                    color: AppColors.brandPrimary,
                    onTap: onAddCheckup)),
            const SizedBox(width: 8),
            Expanded(
                child: _ActionBtn(
                    label: 'Ultrasound',
                    icon: Icons.monitor_heart_outlined,
                    color: AppColors.brandAccent,
                    onTap: onUltrasound)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _ActionBtn(
                    label: 'Lab Test',
                    icon: Icons.science_outlined,
                    color: AppColors.warning,
                    onTap: onLabTest)),
            const SizedBox(width: 8),
            Expanded(
                child: _ActionBtn(
                    label: 'Conclude',
                    icon: Icons.flag_outlined,
                    color: AppColors.error,
                    onTap: onConclude)),
          ]),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.08),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 5),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
