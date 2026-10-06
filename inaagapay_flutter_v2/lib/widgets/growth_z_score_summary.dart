import 'package:flutter/material.dart';
import '../services/growth_record_scores.dart';
import '../services/language_service.dart';
import '../theme/app_colors.dart';

class GrowthZScoreSummary extends StatelessWidget {
  const GrowthZScoreSummary(
      {super.key,
      required this.record,
      required this.birthdate,
      required this.sex});
  final Map<String, dynamic> record;
  final DateTime? birthdate;
  final String? sex;

  @override
  Widget build(BuildContext context) {
    final scores =
        GrowthRecordScores(record: record, birthdate: birthdate, sex: sex);
    final t = LanguageService.translate;
    Widget line(String label, double? z) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label: ${GrowthRecordScores.value(z)}',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(GrowthRecordScores.interpretation(z),
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondaryOf(context))),
          ]),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.bgSecondaryOf(context),
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        line(t('Weight-for-age Z score', 'Z score ng timbang sa edad'),
            scores.weightZ),
        line(t('Height-for-age Z score', 'Z score ng tangkad sa edad'),
            scores.heightZ),
      ]),
    );
  }
}
