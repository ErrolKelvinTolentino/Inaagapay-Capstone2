import 'package:flutter/material.dart';

import '../../models/baby_growth_milestone.dart';
import '../../models/milestone_template.dart';
import '../../services/auth_storage.dart';
import '../../services/baby_book_repository.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';

/// One child's Baby Book — the postnatal half.
///
/// Opens with the chapter inherited from the pregnancy that carried them, then
/// their own milestones grouped by age. Twins get one book each; the opening
/// chapter is read through `children.pregnancy_id` rather than copied, so it
/// is the same chapter in both books rather than two of it.
///
/// Built to the rural-mother rules in mother_and_baby_book_design.md: an
/// illustration or icon carries every row, headings are short, status is a
/// shape and a word rather than colour alone, and nothing tells a mother her
/// child is behind.
class ChildBabyBookPage extends StatefulWidget {
  const ChildBabyBookPage({
    super.key,
    required this.childId,
    required this.childName,
    this.birthdate,
    this.repository,
  });

  final int childId;
  final String childName;
  final DateTime? birthdate;

  /// Overridable for tests, as on the pregnancy banner.
  @visibleForTesting
  final BabyBookRepository? repository;

  @override
  State<ChildBabyBookPage> createState() => _ChildBabyBookPageState();
}

class _ChildBabyBookPageState extends State<ChildBabyBookPage> {
  BabyBookRepository get _repo =>
      widget.repository ?? const BabyBookRepository();

  bool _loading = true;
  List<ChildMilestone> _milestones = const [];
  List<BabyGrowthMilestone> _prenatalChapter = const [];
  bool _chapterOpen = false;

  String _t(String en, String fil) => LanguageService.translate(en, fil);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final milestones = await _repo.loadChildMilestones(
      childId: widget.childId,
      birthdate: widget.birthdate,
    );
    final chapter = await _repo.loadChildPrenatalChapter(widget.childId);
    if (!mounted) return;
    setState(() {
      _milestones = milestones;
      _prenatalChapter = chapter;
      _loading = false;
    });
  }

  Future<void> _toggle(ChildMilestone m) async {
    // Only recording is offered, never un-recording by mistake: tapping an
    // entry that is already kept opens nothing destructive.
    if (m.isRecorded || m.template == null) return;

    final accountId = await AuthStorage.getUserId();
    final ok = await _repo.recordChildMilestone(
      childId: widget.childId,
      templateKey: m.template!.key,
      recordedByAccountId: accountId,
    );
    if (!mounted) return;
    if (ok) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Saved to the Baby Book', 'Nai-save sa Baby Book')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Milestones grouped by age checkpoint, in order.
  Map<int?, List<ChildMilestone>> get _byAge {
    final map = <int?, List<ChildMilestone>>{};
    for (final m in _milestones) {
      map.putIfAbsent(m.ageMonths, () => []).add(m);
    }
    final keys = map.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1; // her own moments last
        if (b == null) return -1;
        return a.compareTo(b);
      });
    return {for (final k in keys) k: map[k]!};
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) => Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: Column(
          children: [
            SecondaryHeader(
              title: widget.childName.isEmpty
                  ? _t('Baby Book', 'Baby Book')
                  : widget.childName,
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.brandPrimary,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        children: [
                          _ageHeader(),
                          const SizedBox(height: 16),
                          if (_prenatalChapter.isNotEmpty) ...[
                            _beforeYouWereBorn(),
                            const SizedBox(height: 20),
                          ],
                          ..._ageSections(),
                          if (_milestones.isEmpty) _emptyState(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ageHeader() {
    final b = widget.birthdate;
    final age = b == null
        ? null
        : BabyBookRepository.ageInMonths(b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.child_care_rounded,
                color: AppColors.brandPrimary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.childName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  age == null
                      ? _t('Birthday not recorded yet',
                          'Wala pang naitalang kaarawan')
                      : ChildMilestone.ageLabel(age),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The shared chapter, collapsed by default.
  ///
  /// It belongs to the pregnancy, not to this child, so it opens the book
  /// rather than sitting among their own milestones — and it stays folded so
  /// the page starts on the child a mother came to see.
  Widget _beforeYouWereBorn() {
    final kept = _prenatalChapter
        .where((m) => m.status == BabyGrowthMilestoneStatus.completed)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandSecondary,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _chapterOpen = !_chapterOpen),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.favorite_rounded,
                      color: AppColors.brandPrimary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('Before you were born',
                              'Bago ka pa isilang'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t('${kept.length} moments kept',
                              '${kept.length} alaalang naitala'),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _chapterOpen
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.brandPrimary,
                  ),
                ],
              ),
            ),
          ),
          if (_chapterOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: [
                  for (final m in _prenatalChapter)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            m.status == BabyGrowthMilestoneStatus.completed
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 16,
                            color: m.status ==
                                    BabyGrowthMilestoneStatus.completed
                                ? AppColors.success
                                : AppColors.textSecondary
                                    .withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              m.title,
                              style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _ageSections() {
    final groups = _byAge;
    return [
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                ChildMilestone.ageLabel(entry.key),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 1,
                  color: AppColors.brandPrimary.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
        for (final m in entry.value) _milestoneRow(m),
        const SizedBox(height: 18),
      ],
    ];
  }

  Widget _milestoneRow(ChildMilestone m) {
    final kept = m.isRecorded;
    final upcoming = m.status == BabyGrowthMilestoneStatus.upcoming;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: kept ? null : () => _toggle(m),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: kept
                  ? AppColors.success.withValues(alpha: 0.35)
                  : AppColors.brandPrimary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A shape as well as a colour: a filled tick and an empty circle
              // differ without relying on green being visible.
              Icon(
                kept
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: kept
                    ? AppColors.success
                    : AppColors.brandPrimary.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: kept ? FontWeight.w700 : FontWeight.w500,
                        color: upcoming
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      m.domainLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.brandPrimary.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (upcoming)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _t('Soon', 'Malapit na'),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_stories_rounded,
                size: 38, color: AppColors.brandPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            _t('This book is just starting', 'Nagsisimula pa lang ang aklat'),
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            _t('Milestones appear here as your baby grows.',
                'Lalabas dito ang mga milestone habang lumalaki ang iyong baby.'),
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
