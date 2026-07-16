// lib/widgets/pregnancy_stats_card.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PregnancyStatsCard extends StatelessWidget {
  final int? gestWeeks;
  final int? daysToEdd;
  final int checkupCount;
  final String? riskLevel;

  const PregnancyStatsCard({
    super.key,
    this.gestWeeks,
    this.daysToEdd,
    required this.checkupCount,
    this.riskLevel,
  });

  String _eddText() {
    if (daysToEdd == null) return '-';
    if (daysToEdd! < 0) return 'Past Due';
    final m = daysToEdd! ~/ 30;
    final w = (daysToEdd! % 30) ~/ 7;
    final d = daysToEdd! % 7;
    if (m > 0) return '${m}m ${w}w';
    return '${w}w ${d}d';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
        children: [
          Row(
            children: [
              Expanded(
                child: Column(children: [
                  Text(gestWeeks != null ? '$gestWeeks' : '-',
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandPrimary)),
                  const SizedBox(height: 2),
                  const Text('Weeks',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500)),
                ]),
              ),
              Container(height: 40, width: 1, color: AppColors.borderPrimary),
              Expanded(
                child: Column(children: [
                  Text(_eddText(),
                      style: TextStyle(
                          fontSize:
                              daysToEdd != null && daysToEdd! < 0 ? 18 : 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandPrimary)),
                  const SizedBox(height: 2),
                  const Text('Time to EDD',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.borderPrimary),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Row(children: [
                  const Icon(Icons.fact_check_outlined,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(checkupCount.toString(),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const Text('Checkups',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                      ]),
                ]),
              ),
              Expanded(
                child: Row(children: [
                  Icon(Icons.shield_outlined,
                      size: 16,
                      color: riskLevel == 'high' ? AppColors.error : AppColors.success),
                  const SizedBox(width: 6),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(riskLevel?.toUpperCase() ?? '-',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: riskLevel == 'high'
                                    ? AppColors.error
                                    : AppColors.success)),
                        const Text('Risk Level',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                      ]),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
