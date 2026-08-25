
import 'package:flutter/material.dart';

import '../../models/baby_growth_milestone.dart';
import '../../models/pregnancy_growth_stage.dart';
import '../../theme/app_colors.dart';
import 'baby_book_section_components.dart';
import '../../services/baby_book_repository.dart';
import 'baby_growth_timeline.dart';

class BabyGrowthMilestonesSection extends StatefulWidget {
  final List<BabyGrowthMilestone> initialMilestones;
  final CurrentPregnancyState currentPregnancy;

  /// Persists a mark being put on or taken off, returning whether it stuck.
  ///
  /// Optional so the preview and the widget tests can run the section with no
  /// database behind it. Where it is null the mark lives for as long as the
  /// screen does, which is honest for a preview and wrong for a real account
  /// — so the pages that have a pregnancy id supply it.
  final Future<bool> Function(BabyGrowthMilestone milestone, bool markingDone)?
      onToggleCompleted;

  const BabyGrowthMilestonesSection({
    super.key,
    required this.initialMilestones,
    required this.currentPregnancy,
    this.onToggleCompleted,
  });

  @override
  State<BabyGrowthMilestonesSection> createState() =>
      _BabyGrowthMilestonesSectionState();
}

class _BabyGrowthMilestonesSectionState
    extends State<BabyGrowthMilestonesSection> {
  late final List<BabyGrowthMilestone> _milestones;
  bool _showAllMilestones = false;

  bool get _isTwin => widget.currentPregnancy.isTwinPregnancy;

  /// The week a milestone belongs at in the timeline.
  ///
  /// [expectedEndWeek] is consulted before giving up: a recommendation can
  /// have a deadline and no start ("at least one ultrasound before 24 weeks").
  /// Without this it fell through to the sentinel and sorted below the
  /// third-trimester rows — telling a mother that something due by week 24
  /// comes after everything due at week 28.
  int _timelineWeek(BabyGrowthMilestone milestone) =>
      milestone.expectedStartWeek ??
      milestone.expectedEndWeek ??
      milestone.recordedPregnancyWeek ??
      100;

  List<BabyGrowthMilestone> get _sortedMilestones {
    final result = List<BabyGrowthMilestone>.from(_milestones);
    result.sort((a, b) {
      final aWeek = _timelineWeek(a);
      final bWeek = _timelineWeek(b);
      final weekComparison = aWeek.compareTo(bWeek);
      if (weekComparison != 0) return weekComparison;
      return _milestones.indexOf(a).compareTo(_milestones.indexOf(b));
    });
    return result;
  }

  @override
  void initState() {
    super.initState();
    _milestones = List<BabyGrowthMilestone>.from(widget.initialMilestones);
  }

  /// Marks a milestone done, or takes the mark back off.
  ///
  /// A mother can have a checkup anywhere — a private clinic, a lying-in, a
  /// hospital in the next town — and the barangay record will not know. The
  /// mark is how she says so in her own book. It is hers, which is also why
  /// it can be taken off again: a tap meant for the row above should not
  /// leave a permanent claim that something happened.
  ///
  /// The screen updates first and the write follows, so the tap feels
  /// immediate. If the write fails the state is rolled back and she is told,
  /// rather than being left looking at a checkmark that exists nowhere but on
  /// this screen.
  Future<void> _toggleCompleted(BabyGrowthMilestone milestone) async {
    final index = _milestones.indexWhere((item) => item.id == milestone.id);
    if (index == -1) return;

    final previous = _milestones[index];
    final markingDone =
        previous.status != BabyGrowthMilestoneStatus.completed;

    setState(() {
      _milestones[index] = markingDone
          ? previous.copyWith(
              status: BabyGrowthMilestoneStatus.completed,
              completedDate: previous.completedDate ?? DateTime.now(),
              recordedPregnancyWeek: previous.recordedPregnancyWeek ??
                  widget.currentPregnancy.currentWeek,
            )
          : previous.copyWith(
              // Back to whatever it would be with nothing recorded —
              // upcoming, current or not-yet-recorded, depending on the week.
              // Asking the repository rather than guessing here keeps one
              // rule for what a status means; a second copy in the widget
              // would be free to disagree with the one used on load.
              status: BabyBookRepository.statusFor(
                observedOn: null,
                expectedStartWeek: previous.expectedStartWeek,
                expectedEndWeek: previous.expectedEndWeek,
                currentWeek: widget.currentPregnancy.currentWeek,
              ),
              completedDate: null,
              recordedPregnancyWeek: null,
              entryId: null,
            );
    });

    final persist = widget.onToggleCompleted;
    if (persist == null) return;

    final saved = await persist(previous, markingDone);
    if (saved || !mounted) return;

    setState(() => _milestones[index] = previous);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          markingDone
              ? 'Could not save that “${previous.title}” is done. Please try again.'
              : 'Could not remove the mark on “${previous.title}”. Please try again.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _viewDetails(BabyGrowthMilestone milestone) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5DADF),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              milestone.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              milestone.description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.55,
              ),
            ),
            if (milestone.photoBytes != null) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(
                  milestone.photoBytes!,
                  height: 210,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 14),
            // The one place the record-state sentence still appears: she has
            // chosen to open this milestone, so there is room to say what the
            // app knows and who to ask about it.
            Text(
              milestone.recordGuidance,
              key: ValueKey<String>('milestone-guidance-${milestone.id}'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            _DetailRow(label: 'Status', value: milestone.status.label),
            if (milestone.expectedStartWeek != null)
              _DetailRow(
                label: 'General timing',
                value: milestone.expectedStartWeek == milestone.expectedEndWeek
                    ? 'Around week ${milestone.expectedStartWeek}'
                    : 'Weeks ${milestone.expectedStartWeek}–${milestone.expectedEndWeek ?? 'onward'}',
              ),
            if (milestone.recordedPregnancyWeek != null)
              _DetailRow(
                label: 'Recorded week',
                value: 'Week ${milestone.recordedPregnancyWeek}',
              ),
            if (milestone.completedDate != null)
              _DetailRow(
                label: 'Recorded date',
                value: babyBookFormatDate(milestone.completedDate!),
              ),
            if (milestone.note?.isNotEmpty == true)
              _DetailRow(label: 'Note', value: milestone.note!),
            if (milestone.recordedBy?.isNotEmpty == true)
              _DetailRow(label: 'Recorded by', value: milestone.recordedBy!),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey<String>('milestone-detail-toggle'),
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _toggleCompleted(milestone);
              },
              style: FilledButton.styleFrom(
                backgroundColor:
                    milestone.status == BabyGrowthMilestoneStatus.completed
                        ? const Color(0xFF4E9D8E)
                        : AppColors.brandPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: Icon(
                milestone.status == BabyGrowthMilestoneStatus.completed
                    ? Icons.remove_done_rounded
                    : Icons.check_circle_outline_rounded,
              ),
              label: Text(
                milestone.status == BabyGrowthMilestoneStatus.completed
                    ? 'Un-mark as completed'
                    : 'Mark as completed',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedMilestones = _sortedMilestones;
    final visibleMilestones = _showAllMilestones
        ? sortedMilestones
        : sortedMilestones.take(3).toList(growable: false);

    return Semantics(
      container: true,
      label: _isTwin
          ? 'Babies growth milestones section'
          : 'Baby growth milestones section',
      child: Column(
        key: const ValueKey<String>('baby-growth-milestones-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Pregnancy Milestones", not "Baby Growth Milestones".
          //
          // The list underneath is checkups, scans and trimester changes —
          // pregnancy confirmed, first prenatal checkup, first ultrasound,
          // anatomy scan, birth preparation. None of it is a description of
          // how the baby is growing; that is the section above this one. A
          // mother who opened this expecting her baby's growth found a care
          // schedule, and a mother looking for her next checkup would not
          // have thought to look under a heading about her baby's size.
          //
          // The twin wording goes with it. These milestones belong to the
          // pregnancy, not to one baby or two, so there is nothing to
          // pluralise.
          // No "Add Milestone". This list is the recommended prenatal care,
          // and the recommendation comes from the catalogue in the database —
          // it is not something a mother composes. Letting her add rows put
          // her own entries among the recommendations, where a later reader
          // could not tell which ones the app was advising.
          //
          // What she still controls is whether each one has happened, which
          // is the mark, not the row.
          const BabyBookSectionHeader(
            eyebrow: 'CHECKUPS & SCANS',
            title: 'Pregnancy Milestones',
          ),
          if (_isTwin) ...[
            const SizedBox(height: 10),
            const BabyBookTwinPregnancyBadge(light: false),
          ],
          const SizedBox(height: 14),
          // The banner used to promise a keepsake — "Small moments become
          // milestones", memories kept together as the journey grows. What
          // follows it is her checkup schedule, so the banner now says that.
          const BabyBookPictureBanner(
            key: ValueKey<String>('milestone-picture-card'),
            assetPath: 'assets/images/milestone_story_card.png',
            semanticLabel:
                'Pregnant mother recording moments in her pregnancy journal',
            eyebrow: 'YOUR PREGNANCY CARE',
            title: 'Your checkups, in order.',
            subtitle:
                'The visits and scans usually done during pregnancy, and which ones you have had.',
          ),
          // "Your Current Growth Stage" stood here and said the week number,
          // then described the baby's development in the same terms as the
          // growth journey above — a third telling of what the hero card and
          // the month card already say, in the smallest type on the page.
          const SizedBox(height: 16),
          // The "You have not added a milestone of your own yet" panel went
          // with the add button: it invited her to fill a gap that is not a
          // gap. Nothing is missing from a list of recommendations because
          // she has not written in it.
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: BabyGrowthTimeline(
              milestones: visibleMilestones,
              onView: _viewDetails,
              onComplete: _toggleCompleted,
            ),
          ),
          if (sortedMilestones.length > 3) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('milestone-see-all'),
                onPressed: () => setState(
                  () => _showAllMilestones = !_showAllMilestones,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandText,
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: Color(0xFFFFBCD2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: AnimatedRotation(
                  turns: _showAllMilestones ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                label: Text(
                  _showAllMilestones ? 'Show Less' : 'See All',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'The weeks shown are the usual times, not fixed dates. Mark a checkup or scan as done only once it has really happened.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
