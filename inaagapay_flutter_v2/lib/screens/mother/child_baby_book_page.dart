import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/baby_growth_milestone.dart';
import '../../models/milestone_template.dart';
import '../../services/auth_storage.dart';
import '../../services/baby_book_repository.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/baby_book/baby_book_section_components.dart';
import '../../widgets/baby_book/baby_care_guide_book.dart';
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
  Map<String, dynamic>? _birth;
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
    final birth = await _repo.loadBirthDetails(widget.childId);
    if (!mounted) return;
    setState(() {
      _milestones = milestones;
      _prenatalChapter = chapter;
      _birth = birth;
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
            // The header names the book; the cover names the child.
            //
            // Both used to carry her name, one directly above the other, which
            // is the same duplication the pregnancy book had between its
            // header and its hero card.
            SecondaryHeader(
              title: _t('Baby Book', 'Aklat ng Sanggol'),
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

                          // Her story in the order it happened: the pregnancy
                          // she was carried through, the day she arrived, then
                          // everything since.
                          if (_prenatalChapter.isNotEmpty) ...[
                            _beforeYouWereBorn(),
                            const SizedBox(height: 20),
                          ],
                          if (_birthStory() case final story?) ...[
                            story,
                            const SizedBox(height: 20),
                          ],
                          ..._ageSections(),
                          if (_milestones.isEmpty) _emptyState(),

                          // The DOH/UNICEF care guide, moved here from the
                          // pregnancy baby book. Its eight pages are about
                          // feeding, first days, safety and checkups — a baby
                          // who has been born — so they belong in the book of
                          // a child who has been.
                          const SizedBox(height: 30),
                          const BabyCareGuideBook(),
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

    // A cover, the way the pregnancy book has one.
    //
    // This was a small white row with an icon — the child's book opened on
    // something that looked like a list item. A book should open on its
    // cover, and the child's name should be the largest thing on it.
    return Container(
      width: double.infinity,
      // Content drives the height, with a floor.
      //
      // A fixed 168 overflowed by 12px as soon as a name wrapped to two lines
      // — and long names are ordinary here. The same mistake the Home banner
      // made, caught the same way.
      constraints: const BoxConstraints(minHeight: 168),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFF8FBC), Color(0xFFE6398D)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandAccent.withValues(alpha: 0.26),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // The artwork sits behind the words rather than beside them, and is
          // faded so white type stays readable over it whatever the drawing.
          Positioned(
            right: -14,
            bottom: -10,
            child: Opacity(
              opacity: 0.32,
              child: Image.asset(
                'assets/images/baby.png',
                height: 168,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _t('BABY BOOK', 'AKLAT NG SANGGOL'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.childName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    age == null
                        ? _t('Birthday not recorded yet',
                            'Wala pang naitalang kaarawan')
                        : ChildMilestone.ageLabel(age),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
  /// "The day you were born" — the birth record, read as a page of a book.
  ///
  /// Every figure here was already in `birth_details` and shown nowhere: the
  /// weight and length she was born at, where it happened, how. For a mother
  /// this is the most re-read page of a paper baby book, and the app was
  /// holding it and saying nothing.
  ///
  /// Only the facts that exist are drawn. A birth record filled in halfway is
  /// normal, and a row reading "not recorded" adds nothing to a keepsake.
  Widget? _birthStory() {
    final birth = _birth;
    if (birth == null) return null;

    final born = DateTime.tryParse(birth['birthdate']?.toString() ?? '');
    final weight = (birth['birth_weight'] as num?)?.toDouble();
    final length = (birth['birth_length'] as num?)?.toDouble();
    final delivery = birth['delivery_type']?.toString().trim();

    final place = <String>[
      birth['birthplace_facility']?.toString().trim() ?? '',
      birth['birthplace_city_municipality']?.toString().trim() ?? '',
      birth['birthplace_province']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).join(', ');

    final facts = <({IconData icon, String label, String value})>[
      if (born != null)
        (
          icon: Icons.cake_outlined,
          label: _t('Born on', 'Ipinanganak noong'),
          value: _longDate(born),
        ),
      if (weight != null && weight > 0)
        (
          icon: Icons.monitor_weight_outlined,
          label: _t('Weight at birth', 'Timbang nang isilang'),
          value: '${weight.toStringAsFixed(weight % 1 == 0 ? 0 : 1)} kg',
        ),
      if (length != null && length > 0)
        (
          icon: Icons.straighten_rounded,
          label: _t('Length at birth', 'Haba nang isilang'),
          value: '${length.toStringAsFixed(length % 1 == 0 ? 0 : 1)} cm',
        ),
      if (place.isNotEmpty)
        (
          icon: Icons.place_outlined,
          label: _t('Born at', 'Ipinanganak sa'),
          value: place,
        ),
      if (delivery != null && delivery.isNotEmpty)
        (
          icon: Icons.favorite_outline_rounded,
          label: _t('How you arrived', 'Paano ka dumating'),
          value: delivery,
        ),
    ];

    // Nothing recorded, nothing to show. An empty chapter heading over a blank
    // card is worse than the chapter simply not being there yet.
    if (facts.isEmpty) return null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFDFEB)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69243F).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFFFF8FBC), AppColors.brandPrimary],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t('The day you were born', 'Ang araw na ipinanganak ka'),
                  style: const TextStyle(
                    color: AppColors.headingSoft,
                    fontSize: 18,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < facts.length; index++)
            Padding(
              padding: EdgeInsets.only(
                  bottom: index == facts.length - 1 ? 0 : 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFAFC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(facts[index].icon,
                        size: 20, color: AppColors.brandText),
                    const SizedBox(width: 12),
                    Text(
                      facts[index].label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.inputText,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        facts[index].value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.headingSoft,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A date a mother would read aloud, not an ISO string.
  String _longDate(DateTime date) {
    const monthsEn = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const monthsFil = <String>[
      'Enero', 'Pebrero', 'Marso', 'Abril', 'Mayo', 'Hunyo',
      'Hulyo', 'Agosto', 'Setyembre', 'Oktubre', 'Nobyembre', 'Disyembre',
    ];
    final month = _t(monthsEn[date.month - 1], monthsFil[date.month - 1]);
    return '$month ${date.day}, ${date.year}';
  }

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
