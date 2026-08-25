import 'package:flutter/material.dart';

import '../../models/baby_growth_milestone.dart';
import '../../theme/app_colors.dart';
import 'baby_book_section_components.dart';

class BabyGrowthMilestoneCard extends StatelessWidget {
  final BabyGrowthMilestone milestone;
  final Color statusColor;
  final IconData statusIcon;
  final VoidCallback onView;
  final VoidCallback onComplete;

  const BabyGrowthMilestoneCard({
    super.key,
    required this.milestone,
    required this.statusColor,
    required this.statusIcon,
    required this.onView,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted =
        milestone.status == BabyGrowthMilestoneStatus.completed;

    // One timing pill, phrased as a recommendation.
    //
    // This used to be two: "Commonly weeks 1–24" beside "Month 1". The month
    // was the calendar month the *window opened* in, which is not a fact
    // about anything a mother would recognise — it read as "do this in month
    // 1" next to a range ending at week 24, and the two appeared to disagree.
    //
    // A window that opens at week 1 is not really a range either. Nothing is
    // being recommended *from* week 1; there is a date by which it should
    // have happened, so that is what it now says.
    final timing =
        switch ((milestone.expectedStartWeek, milestone.expectedEndWeek)) {
      (final int start, final int end) when start <= 1 && end > 1 =>
        'Recommended before week $end',
      (final int start, final int end) when start == end =>
        'Recommended around week $start',
      (final int start, final int end) => 'Recommended weeks $start–$end',
      (final int start, null) => 'Recommended from week $start',
      (null, final int end) => 'Recommended before week $end',
      _ => null,
    };

    return BabyBookPanel(
      // Completed stays white with a green edge, so a done milestone reads as
      // settled next to the pink one she is currently in.
      color: switch (milestone.status) {
        BabyGrowthMilestoneStatus.current => const Color(0xFFFFF4F8),
        _ => Colors.white,
      },
      borderColor: switch (milestone.status) {
        BabyGrowthMilestoneStatus.current => const Color(0xFFFFC7DB),
        BabyGrowthMilestoneStatus.completed => const Color(0xFFBFE3DA),
        _ => const Color(0xFFF5E8ED),
      },
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
                      // Title only. The pink category line beneath it —
                      // "Ultrasound", "Checkup" — restated a word already in
                      // the title, in the smallest type on the card, and
                      // sorted milestones into buckets a mother has no use
                      // for. She is looking for what to do, not for a
                      // taxonomy.
                      Text(
                        milestone.title,
                        style: const TextStyle(
                          color: AppColors.headingSoft,
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                // Two actions, not five. Editing or deleting a recommended
                // milestone was never hers to do — the catalogue comes from
                // the database — and offering it invited her to remove a
                // checkup from her own schedule by accident.
                //
                // Styled to match the midwife-side dropdowns: elevation 8,
                // a 20pt radius, white, and roomy rows. The old menu was the
                // default Material sheet, with a hard black divider.
                PopupMenuButton<String>(
                  key: ValueKey<String>('milestone-menu-${milestone.id}'),
                  tooltip: 'Milestone actions',
                  color: Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: AppColors.borderPrimary),
                  ),
                  position: PopupMenuPosition.under,
                  onSelected: (action) {
                    switch (action) {
                      case 'view':
                        onView();
                      case 'complete':
                        onComplete();
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'view',
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: _MenuRow(
                        icon: Icons.article_outlined,
                        label: 'View details',
                      ),
                    ),
                    PopupMenuItem<String>(
                      key: ValueKey<String>(
                        'milestone-toggle-${milestone.id}',
                      ),
                      value: 'complete',
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: _MenuRow(
                        icon: isCompleted
                            ? Icons.remove_done_rounded
                            : Icons.check_circle_outline_rounded,
                        label: isCompleted
                            ? 'Un-mark as completed'
                            : 'Mark as completed',
                        emphasised: !isCompleted,
                      ),
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
                color: AppColors.inputText,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            // The record-state sentence ("This is not yet recorded in
            // InaAgapay. You may ask your midwife whether…") used to sit here
            // under every card. Nine cards each carrying two paragraphs turned
            // a list she should be able to scan into a wall, and the sentence
            // repeated what the status pill below already says. It now appears
            // once, on the milestone she opens.
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
                if (timing != null)
                  BabyBookStatusPill(
                    label: timing,
                    color: const Color(0xFF8A6780),
                    icon: Icons.calendar_month_outlined,
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

/// One row inside the milestone menu.
///
/// Icon plus label, sized to match the midwife-side dropdown rows rather than
/// the default Material menu item, which is smaller and unlabelled.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasised;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = emphasised ? AppColors.brandText : AppColors.inputText;
    // Flexible, not a bare Text. A popup menu lays its rows out against a
    // bounded width, and "Un-mark as completed" at 14pt beside an icon runs
    // past it — the label has to be allowed to wrap rather than overflow.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 11),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
