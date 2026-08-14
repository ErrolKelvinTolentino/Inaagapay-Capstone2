import 'package:flutter/material.dart';

import '../../models/baby_growth_milestone.dart';
import '../../theme/app_colors.dart';
import 'baby_book_section_components.dart';

class BabyGrowthMilestoneCard extends StatelessWidget {
  final BabyGrowthMilestone milestone;
  final Color statusColor;
  final IconData statusIcon;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const BabyGrowthMilestoneCard({
    super.key,
    required this.milestone,
    required this.statusColor,
    required this.statusIcon,
    required this.onView,
    required this.onEdit,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final weekRange =
        switch ((milestone.expectedStartWeek, milestone.expectedEndWeek)) {
      (final int start, final int end) when start == end =>
        'Around week $start',
      (final int start, final int end) => 'Commonly weeks $start–$end',
      (final int start, null) => 'From around week $start',
      _ => null,
    };

    return BabyBookPanel(
      color: milestone.status == BabyGrowthMilestoneStatus.current
          ? const Color(0xFFFFF4F8)
          : Colors.white,
      borderColor: milestone.status == BabyGrowthMilestoneStatus.current
          ? const Color(0xFFFFC7DB)
          : const Color(0xFFF5E8ED),
      padding: const EdgeInsets.all(14),
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        milestone.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        milestone.category.label,
                        style: const TextStyle(
                          color: AppColors.brandText,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey<String>('milestone-menu-${milestone.id}'),
                  tooltip: 'Milestone actions',
                  color: Colors.white,
                  onSelected: (action) {
                    switch (action) {
                      case 'view':
                        onView();
                      case 'edit':
                        onEdit();
                      case 'complete':
                        onComplete();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'view', child: Text('View details')),
                    PopupMenuItem(value: 'edit', child: Text('Edit milestone')),
                    PopupMenuItem(
                      value: 'complete',
                      child: Text('Mark as completed'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete milestone'),
                    ),
                  ],
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              milestone.description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                height: 1.5,
              ),
            ),
            if (milestone.photoBytes != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  milestone.photoBytes!,
                  width: double.infinity,
                  height: 128,
                  fit: BoxFit.cover,
                  semanticLabel: 'Photo attached to ${milestone.title}',
                ),
              ),
            ],
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                BabyBookStatusPill(
                  label: milestone.status.label,
                  color: statusColor,
                  icon: statusIcon,
                ),
                if (weekRange != null)
                  BabyBookStatusPill(
                    label: weekRange,
                    color: const Color(0xFF8A6780),
                    icon: Icons.calendar_month_outlined,
                  ),
                if (milestone.pregnancyMonth != null)
                  BabyBookStatusPill(
                    label: 'Month ${milestone.pregnancyMonth}',
                    color: const Color(0xFF8055A6),
                    icon: Icons.auto_stories_outlined,
                  ),
              ],
            ),
            if (milestone.note?.isNotEmpty == true ||
                milestone.recordedBy?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (milestone.note?.isNotEmpty == true) milestone.note!,
                  if (milestone.recordedBy?.isNotEmpty == true)
                    'Recorded by ${milestone.recordedBy}',
                ].join(' • '),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 9,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
