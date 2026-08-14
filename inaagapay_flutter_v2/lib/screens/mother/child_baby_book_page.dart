import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/baby_growth_milestone.dart';
import '../../models/milestone_template.dart';
import '../../services/auth_storage.dart';
import '../../services/baby_book_repository.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/baby_book/baby_book_section_components.dart';
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
    if (m.template == null) return;
    if (m.isRecorded) return _confirmRemove(m);

    // recorded_by is nullable, so failing to read the account id is not a
    // reason to refuse the save. Losing who logged it is a smaller loss than
    // losing the milestone.
    //
    // Time-boxed rather than merely wrapped in try/catch: this reads the
    // device keystore, which can hang rather than fail — it does exactly that
    // under test, where the platform channel has no handler, and a tap on a
    // milestone simply did nothing. A keystore that is slow on an old phone
    // would have produced the same silence.
    int? accountId;
    try {
      accountId = await AuthStorage.getUserId()
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      accountId = null;
    }

    final ok = await _repo.recordChildMilestone(
      childId: widget.childId,
      templateKey: m.template!.key,
      recordedByAccountId: accountId,
    );
    if (!mounted) return;
    if (!ok) return;

    await _load();
    if (!mounted) return;

    // Undo on the confirmation itself, which catches the common mistake — a
    // wrong tap — without making her hunt for how to fix it.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('Saved to the Baby Book', 'Nai-save sa Baby Book')),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: _t('Undo', 'Ibalik'),
          onPressed: () async {
            final fresh = _milestones.firstWhere(
              (x) => x.template?.key == m.template!.key,
              orElse: () => m,
            );
            if (fresh.entryId != null) {
              await _repo.removeChildMilestone(fresh.entryId!);
              await _load();
            }
          },
        ),
      ),
    );
  }

  /// Removing something from a keepsake deserves a question first.
  ///
  /// Phrased as a plain choice rather than a warning: she is correcting a
  /// record, not doing something dangerous, and a red alarm over a mis-tapped
  /// milestone would be out of proportion.
  Future<void> _confirmRemove(ChildMilestone m) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _t('Remove this?', 'Alisin ito?'),
          style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ),
        content: Text(
          _t('"${m.title}" will be taken out of the Baby Book. You can add it '
              'again anytime.',
              'Aalisin sa Baby Book ang "${m.title}". Maaari mo itong idagdag '
              'ulit anumang oras.'),
          style: const TextStyle(
              fontSize: 14, height: 1.4, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Keep it', 'Panatilihin')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPrimary),
            child: Text(_t('Remove', 'Alisin')),
          ),
        ],
      ),
    );

    if (yes != true || m.entryId == null || !mounted) return;
    await _repo.removeChildMilestone(m.entryId!);
    await _load();
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
        // The eyebrow-and-title header from the pregnancy book, so both halves
        // read as one book rather than two screens that happen to be linked.
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BabyBookSectionHeader(
            eyebrow: _t('AT THIS AGE', 'SA EDAD NA ITO'),
            title: ChildMilestone.ageLabel(entry.key),
            description: _keptSummary(entry.value),
          ),
        ),
        ..._domainGroups(entry.value),
        const SizedBox(height: 22),
      ],
    ];
  }

  String _keptSummary(List<ChildMilestone> milestones) {
    final kept = milestones.where((m) => m.isRecorded).length;
    return _t('$kept of ${milestones.length} kept so far',
        '$kept sa ${milestones.length} ang naitala');
  }

  /// Milestones of one age, grouped under their domain.
  ///
  /// The first version repeated the domain on every row, so "Moving and
  /// playing" appeared four times running under a single age. One heading per
  /// group says it once, and gives the icon somewhere to live.
  List<Widget> _domainGroups(List<ChildMilestone> milestones) {
    final byDomain = <String, List<ChildMilestone>>{};
    for (final m in milestones) {
      byDomain.putIfAbsent(m.template?.category ?? '_own', () => []).add(m);
    }

    return [
      for (final group in byDomain.entries) ...[
        // One panel per domain rather than per milestone. The mockup gave each
        // milestone its own panel, which works for nine prenatal entries and
        // would be a very long scroll for a hundred and fifty-seven.
        BabyBookPanel(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _domainHeader(group.value.first),
              for (final m in group.value) _milestoneRow(m),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _domainHeader(ChildMilestone sample) {
    final t = sample.template;
    final colour = t?.postnatalDomainColour ?? AppColors.brandPrimary;
    final label = t == null
        ? _t('Our own moments', 'Aming mga alaala')
        : (LanguageService.isFilipino
            ? t.postnatalDomainLabelFil
            : t.postnatalDomainLabel);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(
              t?.postnatalDomainIcon ?? Icons.auto_awesome_rounded,
              size: 17,
              color: colour,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }

  Widget _milestoneRow(ChildMilestone m) {
    final kept = m.isRecorded;
    final upcoming = m.status == BabyGrowthMilestoneStatus.upcoming;

    final domainColour =
        m.template?.postnatalDomainColour ?? AppColors.brandPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Kept rows are tappable too — that is how a mis-tap gets undone.
        onTap: () => _toggle(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            // The mockup's treatment for a current item: a soft pink fill so
            // the thing happening now stands out inside its group without
            // needing a badge.
            color: m.status == BabyGrowthMilestoneStatus.current && !kept
                ? const Color(0xFFFFF4F8)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A shape as well as a colour: a filled tick and an empty circle
              // differ without relying on green being visible. The empty one
              // takes the domain's hue so a row still belongs to its group
              // when scrolled away from the heading.
              Icon(
                kept
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: kept
                    ? AppColors.success
                    : domainColour.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 11),
              // The domain is on the group heading now, so the row carries the
              // milestone alone — one idea per row, and four fewer repeated
              // labels under every age.
              Expanded(
                child: Text(
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
              ),
              // The mockup's status pill, at a size a mother can actually
              // read. Theirs is 8px; on a cheap screen in daylight that is
              // decoration rather than information.
              if (kept)
                const _Pill(
                  label: 'Kept',
                  labelFil: 'Naitala',
                  colour: AppColors.success,
                  icon: Icons.check_rounded,
                )
              else if (upcoming)
                const _Pill(
                  label: 'Soon',
                  labelFil: 'Malapit na',
                  colour: Color(0xFF8A6780),
                  icon: Icons.schedule_rounded,
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

/// The mockup's BabyBookStatusPill, resized.
///
/// Same shape and the same 12%-tint treatment, but at 11px rather than 8.
/// Eight-point type is decoration on a cheap screen in daylight, and the
/// design doc's rules exist because that is the screen this app meets.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.labelFil,
    required this.colour,
    required this.icon,
  });

  final String label;
  final String labelFil;
  final Color colour;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colour),
          const SizedBox(width: 4),
          Text(
            LanguageService.translate(label, labelFil),
            style: TextStyle(
              color: colour,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
