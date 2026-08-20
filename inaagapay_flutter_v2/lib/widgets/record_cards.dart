// lib/widgets/record_cards.dart
// Checkup, Ultrasound, and Lab Test card widgets used in both
// Current Pregnancy and History tabs.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/language_service.dart';
import 'profile_helpers.dart';

// Helper for date comparison
bool _isSameDay(dynamic dateVal1, dynamic dateVal2) {
  if (dateVal1 == null || dateVal2 == null) return false;
  try {
    var d1 = DateTime.tryParse(dateVal1.toString());
    var d2 = DateTime.tryParse(dateVal2.toString());
    if (d1 == null || d2 == null) return false;
    d1 = d1.toLocal();
    d2 = d2.toLocal();
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  } catch (_) {
    return false;
  }
}

// ── Checkup Card ──────────────────────────────────────────────────────────

class CheckupRecordCard extends StatelessWidget {
  final Map<String, dynamic> checkup;
  final VoidCallback onTap;

  const CheckupRecordCard({
    super.key,
    required this.checkup,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateCreated = formatProfileDateTime(
        checkup['created_at'] ?? checkup['createdAt'] ?? checkup['checkup_datetime']);

    return _RecordCardShell(
      accentColor: AppColors.brandPrimary,
      icon: Icons.medical_services_outlined,
      title: 'Prenatal Checkup',
      subtitle: dateCreated,
      badges: const [],
      onTap: onTap,
    );
  }
}

// ── Ultrasound Card ───────────────────────────────────────────────────────

class UltrasoundRecordCard extends StatelessWidget {
  final Map<String, dynamic> ultrasound;
  final VoidCallback onTap;
  final String? addedDate;

  const UltrasoundRecordCard({
    super.key,
    required this.ultrasound,
    required this.onTap,
    this.addedDate,
  });

  @override
  Widget build(BuildContext context) {
    final dateCreated = formatProfileDateTime(ultrasound['created_at'] ?? ultrasound['createdAt']);
    final dateConducted = formatProfileDate(ultrasound['ultrasound_date']);

    final sameDay = _isSameDay(
      ultrasound['created_at'] ?? ultrasound['createdAt'],
      ultrasound['ultrasound_date'],
    );

    final String? secondaryText = sameDay
        ? null
        : LanguageService.translate(
            'Conducted on $dateConducted',
            'Isinagawa noong $dateConducted',
          );

    return _RecordCardShell(
      accentColor: AppColors.brandPrimary,
      icon: Icons.monitor_heart_outlined,
      title: 'Ultrasound',
      subtitle: dateCreated,
      secondarySubtitle: secondaryText,
      badges: const [],
      onTap: onTap,
    );
  }
}

// ── Lab Test Card ─────────────────────────────────────────────────────────

class LabTestRecordCard extends StatelessWidget {
  final Map<String, dynamic> labTest;
  final VoidCallback onTap;
  final String? addedDate;

  const LabTestRecordCard({
    super.key,
    required this.labTest,
    required this.onTap,
    this.addedDate,
  });

  @override
  Widget build(BuildContext context) {
    final dateCreated = formatProfileDateTime(labTest['created_at'] ?? labTest['createdAt']);
    final dateConducted = formatProfileDate(labTest['lab_test_date']);
    final type = labTest['lab_test_type']?.toString() ?? 'Lab Test';

    final sameDay = _isSameDay(
      labTest['created_at'] ?? labTest['createdAt'],
      labTest['lab_test_date'],
    );

    final String? secondaryText = sameDay
        ? null
        : LanguageService.translate(
            'Conducted on $dateConducted',
            'Isinagawa noong $dateConducted',
          );

    return _RecordCardShell(
      accentColor: AppColors.brandPrimary,
      icon: Icons.science_outlined,
      title: type,
      subtitle: dateCreated,
      secondarySubtitle: secondaryText,
      badges: const [],
      onTap: onTap,
    );
  }
}

// ── Maternal Vital Card ───────────────────────────────────────────────────

class MaternalVitalRecordCard extends StatelessWidget {
  final Map<String, dynamic> vital;
  final VoidCallback onTap;

  const MaternalVitalRecordCard({
    super.key,
    required this.vital,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateCreated = formatProfileDateTime(
        vital['created_at'] ?? vital['createdAt'] ?? vital['recorded_at']);

    return _RecordCardShell(
      accentColor: AppColors.brandPrimary,
      icon: Icons.monitor_weight_outlined,
      title: 'Self-logged Vitals',
      subtitle: dateCreated,
      badges: const [],
      onTap: onTap,
    );
  }
}


// ── Shared record card shell ──────────────────────────────────────────────

// One accent for every record type.
//
// These cards used four: pink for a checkup, a second pink for an ultrasound,
// AMBER for a lab test and TEAL for self-logged vitals. None of it encoded
// anything — each card already carries its own icon and its own title, which
// is what tells the types apart. The amber was actively misleading: amber in
// this app means "at or above threshold, repeat it", which is what the blood
// pressure card says with the same colour. A lab test is not a warning.
class _RecordCardShell extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? secondarySubtitle;
  final List<_Badge> badges;
  final VoidCallback onTap;

  const _RecordCardShell({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.secondarySubtitle,
    required this.badges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.borderPrimary,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Left accent strip
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                  ),

                  // Icon
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: accentColor, size: 18),
                    ),
                  ),

                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (secondarySubtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              secondarySubtitle!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          if (badges.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: badges,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Chevron
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.chevron_right,
                        color: AppColors.textSecondary, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Badge chip ────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Sort row ──────────────────────────────────────────────────────────────

class RecordSortRow extends StatelessWidget {
  final String currentValue;
  final ValueChanged<String?> onChanged;

  const RecordSortRow({
    super.key,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text(
          'Sort:',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.brandPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.brandPrimary.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentValue,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: Colors.white,
              elevation: 4,
              icon: const Icon(
                Icons.expand_more,
                size: 16,
                color: AppColors.brandPrimary,
              ),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.brandPrimary,
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'desc',
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text('Newest'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'asc',
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text('Oldest'),
                  ),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Load-more button ──────────────────────────────────────────────────────

class RecordLoadMoreButton extends StatelessWidget {
  final int current;
  final int total;
  final int pageSize;
  final VoidCallback onPressed;

  const RecordLoadMoreButton({
    super.key,
    required this.current,
    required this.total,
    required this.pageSize,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = total - current;
    final nextBatch = remaining > pageSize ? pageSize : remaining;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.expand_more, size: 18),
          label: Text(
            'Load More ($nextBatch of $remaining remaining)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandPrimary,
            side: BorderSide(
                color: AppColors.brandPrimary.withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
      ),
    );
  }
}

class HistoryRecordSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final String emptyMessage;
  final List<Widget> children;

  const HistoryRecordSection({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.emptyMessage,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: color.withValues(alpha: 0.05),
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          iconColor: color,
          collapsedIconColor: color.withValues(alpha: 0.7),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          title: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: count > 0
                      ? color.withValues(alpha: 0.10)
                      : AppColors.bgSecondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: count > 0
                        ? color.withValues(alpha: 0.25)
                        : AppColors.borderPrimary,
                    width: 1,
                  ),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: count > 0 ? color : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: count == 0
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: AppColors.bgSecondary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderPrimary),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: color.withValues(alpha: 0.6)),
                          const SizedBox(width: 8),
                          Text(
                            emptyMessage,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(children: children),
            ),
          ],
        ),
      ),
    );
  }
}
