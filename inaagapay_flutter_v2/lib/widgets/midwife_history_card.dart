// lib/widgets/midwife_history_card.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MidwifeHistoryCard extends StatelessWidget {
  final List<MidwifeVisitItem> visits;

  const MidwifeHistoryCard({
    super.key,
    required this.visits,
  });

  @override
  Widget build(BuildContext context) {
    final displayedVisits = visits.take(3).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        children: [
          /// HEADER
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.access_time, color: AppColors.brandPrimary, size: 22),
              SizedBox(width: 8),
              Text(
                'Recent Visits',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          /// VISIT ROWS
          Column(
            children: displayedVisits.map((visit) {
              return _VisitRow(
                visit: visit,
                onTap: visit.onTap,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _VisitRow extends StatelessWidget {
  final MidwifeVisitItem visit;
  final VoidCallback? onTap;

  const _VisitRow({
    required this.visit,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        splashColor: AppColors.brandPrimary.withValues(alpha: 0.08),
        highlightColor: AppColors.brandPrimary.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// LEFT TEXT
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visit.fullName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      visit.visitType,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              /// RIGHT INDICATOR
              _VisitTimeIndicator(label: visit.timeLabel),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisitTimeIndicator extends StatelessWidget {
  final String label;

  const _VisitTimeIndicator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brandPrimary),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.brandPrimary,
        ),
      ),
    );
  }
}

class MidwifeVisitItem {
  final String fullName;
  final String visitType;
  final String timeLabel;
  final VoidCallback? onTap;

  const MidwifeVisitItem({
    required this.fullName,
    required this.visitType,
    required this.timeLabel,
    this.onTap,
  });
}
