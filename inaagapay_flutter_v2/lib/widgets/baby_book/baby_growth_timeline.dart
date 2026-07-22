import 'package:flutter/material.dart';

import '../../models/baby_growth_milestone.dart';
import 'baby_growth_milestone_card.dart';

class BabyGrowthTimeline extends StatelessWidget {
  final List<BabyGrowthMilestone> milestones;
  final ValueChanged<BabyGrowthMilestone> onView;
  final ValueChanged<BabyGrowthMilestone> onEdit;
  final ValueChanged<BabyGrowthMilestone> onComplete;
  final ValueChanged<BabyGrowthMilestone> onDelete;

  const BabyGrowthTimeline({
    super.key,
    required this.milestones,
    required this.onView,
    required this.onEdit,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < milestones.length; index++)
          _TimelineEntry(
            milestone: milestones[index],
            isFirst: index == 0,
            isLast: index == milestones.length - 1,
            onView: () => onView(milestones[index]),
            onEdit: () => onEdit(milestones[index]),
            onComplete: () => onComplete(milestones[index]),
            onDelete: () => onDelete(milestones[index]),
          ),
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final BabyGrowthMilestone milestone;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _TimelineEntry({
    required this.milestone,
    required this.isFirst,
    required this.isLast,
    required this.onView,
    required this.onEdit,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final visual = _milestoneVisual(milestone.status);

    return Padding(
      key: ValueKey<String>('milestone-card-${milestone.id}'),
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 30,
              child: Column(
                children: [
                  if (!isFirst)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: const Color(0xFFFFD7E5),
                      ),
                    )
                  else
                    const Spacer(),
                  Semantics(
                    label: '${milestone.status.label} milestone',
                    child: Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(
                        color: visual.color,
                        shape: BoxShape.circle,
                        border: milestone.status ==
                                BabyGrowthMilestoneStatus.current
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: milestone.status ==
                                BabyGrowthMilestoneStatus.current
                            ? [
                                BoxShadow(
                                  color: visual.color.withValues(alpha: 0.3),
                                  blurRadius: 0,
                                  spreadRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        visual.icon,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: const Color(0xFFFFD7E5),
                      ),
                    )
                  else
                    const Spacer(),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BabyGrowthMilestoneCard(
                milestone: milestone,
                statusColor: visual.color,
                statusIcon: visual.icon,
                onView: onView,
                onEdit: onEdit,
                onComplete: onComplete,
                onDelete: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({Color color, IconData icon}) _milestoneVisual(
  BabyGrowthMilestoneStatus status,
) {
  return switch (status) {
    BabyGrowthMilestoneStatus.completed => (
        color: const Color(0xFF4E9D8E),
        icon: Icons.check_rounded,
      ),
    BabyGrowthMilestoneStatus.current => (
        color: const Color(0xFFF05C91),
        icon: Icons.favorite_rounded,
      ),
    BabyGrowthMilestoneStatus.upcoming => (
        color: const Color(0xFF9C93A0),
        icon: Icons.schedule_rounded,
      ),
    BabyGrowthMilestoneStatus.notRecorded => (
        color: const Color(0xFFD38A43),
        icon: Icons.radio_button_unchecked_rounded,
      ),
  };
}
