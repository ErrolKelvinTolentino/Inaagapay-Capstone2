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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              /// LEFT TEXT
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            visit.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brandPrimary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.brandPrimary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            visit.displayId,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandPrimary,
                            ),
                          ),
                        ),
                      ],
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
              const SizedBox(width: 8),

              /// RIGHT INDICATOR
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _VisitTimeIndicator(label: visit.timeLabel),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
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
  final String name;
  final String displayId;
  final String visitType;
  final String timeLabel;
  final VoidCallback? onTap;

  const MidwifeVisitItem({
    required this.name,
    required this.displayId,
    required this.visitType,
    required this.timeLabel,
    this.onTap,
  });
}
