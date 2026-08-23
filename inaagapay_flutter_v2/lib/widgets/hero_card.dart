// lib/widgets/hero_card.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/language_service.dart';

class HeroCard extends StatelessWidget {
  final ImageProvider? image;
  final String? title;
  final String? subtitle;
  final String? sex;
  final int? week;
  final bool showWeekBadge;
  final bool showHeartRow;

  const HeroCard({
    super.key,
    this.image,
    this.title,
    this.subtitle,
    this.sex,
    this.week,
    this.showWeekBadge = false,
    this.showHeartRow = true,
  });

  Widget _buildSexBadge(String sexValue) {
    final cleanSex = sexValue.trim().toLowerCase();
    final isFemale = cleanSex == 'female';
    final isMale = cleanSex == 'male';
    
    if (!isFemale && !isMale) {
      return Text(
        sexValue,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      );
    }

    final color = isFemale ? const Color(0xFFDE3A53) : const Color(0xFF0288D1);
    final icon = isFemale ? Icons.female_rounded : Icons.male_rounded;
    final label = isFemale ? 'Female' : 'Male';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDashboardArtwork = title == null && subtitle == null;

    if (isDashboardArtwork) {
      // The card a mother sees first, sized like it.
      //
      // At a 60px image inside 12px of padding it was smaller than the baby
      // size card further down the page — the illustration that is the reason
      // she opened the app was the least prominent thing on screen. The
      // artwork is now 116px in a circle with room around it, which is what
      // makes it read as a hero rather than a row.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: AppColors.bgPrimary,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.bgSecondary,
                    ),
                    child: image != null
                        ? Image(image: image!, height: 116, fit: BoxFit.contain)
                        : const Icon(
                            Icons.person,
                            size: 72,
                            color: AppColors.brandPrimary,
                          ),
                  ),
                ),
                if (showWeekBadge && week != null)
                  Positioned(
                    top: 10,
                    right: 0,
                    child: _WeekBadge(week: week!),
                  ),
              ],
            ),
            if (showHeartRow) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite,
                      size: 18, color: AppColors.brandPrimary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      LanguageService.translate(
                        'Your baby is growing beautifully!',
                        'Maganda ang paglaki ng iyong sanggol!',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    // Compact Row layout for child profiles/schedules
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgPrimary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgSecondary,
                ),
                alignment: Alignment.center,
                child: image != null
                    ? ClipOval(
                        child: Image(
                          image: image!,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(
                        Icons.person,
                        size: 30,
                        color: AppColors.brandPrimary,
                      ),
              ),
              const SizedBox(width: 14),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null && title!.isNotEmpty)
                      Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (sex != null && sex!.trim().isNotEmpty)
                          _buildSexBadge(sex!),
                        if (showWeekBadge && week != null)
                          _WeekBadge(week: week!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showHeartRow) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 0.5, color: AppColors.bgSecondary),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.favorite,
                    size: 14, color: AppColors.brandPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    LanguageService.translate(
                      'Your baby is growing beautifully!',
                      'Maganda ang paglaki ng iyong sanggol!',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekBadge extends StatelessWidget {
  final int week;

  const _WeekBadge({required this.week});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${LanguageService.translate('Week', 'Linggo')} $week',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textOnColor,
        ),
      ),
    );
  }
}
