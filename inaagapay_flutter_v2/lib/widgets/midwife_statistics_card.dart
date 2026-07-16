// lib/widgets/midwife_statistics_card.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MidwifeStatisticsCard extends StatelessWidget {
  final int totalPregnancies;
  final int firstTrimester;
  final int secondTrimester;
  final int thirdTrimester;

  const MidwifeStatisticsCard({
    super.key,
    required this.totalPregnancies,
    required this.firstTrimester,
    required this.secondTrimester,
    required this.thirdTrimester,
  });

  @override
  Widget build(BuildContext context) {
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
          /// MAIN NUMBER
          Text(
            totalPregnancies.toString(),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.brandPrimary,
            ),
          ),

          const SizedBox(height: 8),

          /// HEADER (icon + title)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.pregnant_woman, color: AppColors.brandPrimary, size: 22),
              SizedBox(width: 8),
              Text(
                'Active Pregnancies',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          /// TRIMESTER CARDS
          Row(
            children: [
              Expanded(
                child: _TrimesterCard(
                  value: firstTrimester,
                  title: '1st\nTrimester',
                  backgroundColor: const Color(0xFFFFF0F5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TrimesterCard(
                  value: secondTrimester,
                  title: '2nd\nTrimester',
                  backgroundColor: const Color(0xFFFFF0F5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TrimesterCard(
                  value: thirdTrimester,
                  title: '3rd\nTrimester',
                  backgroundColor: const Color(0xFFFFF0F5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrimesterCard extends StatelessWidget {
  final int value;
  final String title;
  final Color? backgroundColor;

  const _TrimesterCard({
    required this.value,
    required this.title,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 18,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              height: 1.3,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
