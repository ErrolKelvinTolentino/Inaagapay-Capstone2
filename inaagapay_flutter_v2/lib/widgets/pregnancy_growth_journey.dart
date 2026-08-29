import 'package:flutter/material.dart';

import '../models/pregnancy_growth_stage.dart';
import '../theme/app_colors.dart';
import 'baby_book/baby_book_section_components.dart';

class PregnancyGrowthJourney extends StatefulWidget {
  final CurrentPregnancyState currentPregnancy;
  final List<PregnancyGrowthStage> stages;

  const PregnancyGrowthJourney({
    super.key,
    required this.currentPregnancy,
    required this.stages,
  });

  @override
  State<PregnancyGrowthJourney> createState() => _PregnancyGrowthJourneyState();
}

class _PregnancyGrowthJourneyState extends State<PregnancyGrowthJourney> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = (widget.currentPregnancy.currentMonth - 1).clamp(
      0,
      widget.stages.length - 1,
    );
  }

  @override
  void didUpdateWidget(covariant PregnancyGrowthJourney oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPregnancy.currentMonth !=
        widget.currentPregnancy.currentMonth) {
      _selectedIndex = (widget.currentPregnancy.currentMonth - 1).clamp(
        0,
        widget.stages.length - 1,
      );
    }
  }

  void _showPreviousMonth() {
    if (_selectedIndex == 0) return;
    setState(() => _selectedIndex--);
  }

  void _showNextMonth() {
    if (_selectedIndex == widget.stages.length - 1) return;
    setState(() => _selectedIndex++);
  }

  void _selectMonth(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pregnancy = widget.currentPregnancy;
    final selectedStage = widget.stages[_selectedIndex];
    final isCurrentStage = selectedStage.month == pregnancy.currentMonth;
    final plural = pregnancy.isMultiplePregnancy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Badge and title, nothing else. The eyebrow said "PREGNANCY GROWTH"
        // directly above a title that says the same thing in her own words,
        // and the line beneath explained a row of numbered circles that is
        // plainer to look at than to read about.
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFFFF8FBC), AppColors.brandPrimary],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.brandPrimary.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                plural ? Icons.child_care_rounded : Icons.spa_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                plural
                    ? 'Your Babies’ Growth Journey'
                    : 'Your Baby’s Growth Journey',
                style: const TextStyle(
                  color: AppColors.headingSoft,
                  fontSize: 22,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.45,
                ),
              ),
            ),
          ],
        ),
        // The pregnancy card moved to the top of the Baby Book, where it is
        // now the cover. Drawn here as well, a mother scrolling this page met
        // the same photograph, the same due date and the same 28% twice.
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.035, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: _PregnancyStageCard(
            key: ValueKey<int>(selectedStage.month),
            stage: selectedStage,
            pregnancy: pregnancy,
            isCurrentStage: isCurrentStage,
          ),
        ),
        const SizedBox(height: 12),
        _MonthNavigation(
          currentIndex: _selectedIndex,
          currentPregnancyMonth: pregnancy.currentMonth,
          totalMonths: widget.stages.length,
          onPrevious: _selectedIndex == 0 ? null : _showPreviousMonth,
          onNext: _selectedIndex == widget.stages.length - 1
              ? null
              : _showNextMonth,
          onSelect: _selectMonth,
        ),
        // The disclaimer used to sit here as an amber block of 10pt text at
        // the very bottom of the section. It is now behind the (i) in the
        // corner of the stage card, where it is one tap away and legible when
        // it is read, instead of being permanently on screen at a size that
        // discouraged reading it at all.
      ],
    );
  }
}

/// The wording behind the (i) on the stage card.
///
/// Kept as one constant so the sheet and any future placement cannot drift
/// apart — this is the sentence that keeps the guide a guide.
const String pregnancyGuideDisclaimer =
    'Every pregnancy is different. What you read here is a general guide for '
    'most pregnancies, not a description of yours. It does not take the place '
    'of your doctor or midwife — they know your record and can answer for '
    'your pregnancy.';

/// Opens the guide disclaimer as a bottom sheet.
Future<void> showPregnancyGuideDisclaimer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    // Scroll-controlled and scrollable. The default sheet is capped at a
    // fraction of the screen, which clipped the last lines of the disclaimer
    // on a small phone — and a disclaimer that is cut off is worse than one
    // that is merely small. It now sizes to its text and scrolls if a mother
    // has her system font enlarged.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (context) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        22,
        4,
        22,
        30 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFD78C28),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'About this guide',
                  style: TextStyle(
                    color: AppColors.headingSoft,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            pregnancyGuideDisclaimer,
            style: TextStyle(
              color: AppColors.inputText,
              fontSize: 15,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Got it',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PregnancyCoverCard extends StatelessWidget {
  final CurrentPregnancyState pregnancy;

  /// Extra room at the top of the card's text, for a control laid over it.
  ///
  /// Used where the card stands in for a page header and a back arrow sits in
  /// its corner: without this the arrow lands on top of "CURRENT PREGNANCY".
  /// Zero everywhere else, so the Baby Book's cover is unchanged.
  final double contentTopInset;

  const PregnancyCoverCard({
    super.key,
    required this.pregnancy,
    this.contentTopInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (pregnancy.pregnancyProgress * 100).round();

    return BabyBookPictureCardShell(
      key: const ValueKey<String>('current-pregnancy-picture-card'),
      assetPath: 'assets/images/current_pregnancy_card.png',
      semanticLabel: 'Pregnant mother holding her growing belly',
      height: 262 + contentTopInset,
      imageKey: const ValueKey('current-pregnancy-card-artwork'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(17, 17 + contentTopInset, 17, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'CURRENT PREGNANCY',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.05,
                  ),
                ),
                const Spacer(),
                if (pregnancy.isTwinPregnancy)
                  const BabyBookTwinPregnancyBadge(light: true),
              ],
            ),
            // This card is now the top of the Baby Book, so it carries the
            // headline it used to sit beneath. The page previously said
            // "11 Weeks Pregnant", "Month 3 • First Trimester", the due date
            // and "28%" across three separate cards; all of it is here once.
            const SizedBox(height: 8),
            Text(
              pregnancy.currentWeek <= 0
                  ? 'Your pregnancy'
                  : '${pregnancy.currentWeek} Weeks Pregnant',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27.5,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Month ${pregnancy.currentMonth} • ${pregnancy.trimester}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Pregnancy progress',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '$percentage%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: pregnancy.pregnancyProgress,
                backgroundColor: Colors.white.withValues(alpha: 0.24),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                const Icon(
                  Icons.event_available_outlined,
                  color: Colors.white,
                  size: 17,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Estimated due date: ${babyBookFormatDate(pregnancy.estimatedDueDate)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PregnancyStageCard extends StatelessWidget {
  final PregnancyGrowthStage stage;
  final CurrentPregnancyState pregnancy;
  final bool isCurrentStage;

  const _PregnancyStageCard({
    super.key,
    required this.stage,
    required this.pregnancy,
    required this.isCurrentStage,
  });

  @override
  Widget build(BuildContext context) {
    final plural = pregnancy.isMultiplePregnancy;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFDFEB)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69243F).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // The pill is the heading now. The weeks used to be said
                    // twice — once in a pill labelled "YOUR CURRENT STAGE"
                    // and again underneath in large dark type — so the pill
                    // took the room without carrying the information.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrentStage
                            ? AppColors.brandPrimary
                            : const Color(0xFFFFEDF4),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Semantics(
                        // Nothing on the card now says in words whether this
                        // is her own month or one she is reading ahead to —
                        // that is left to the pill's colour and to the ringed
                        // circle in the navigator. Colour reaches neither a
                        // screen reader nor a colourblind mother, so the
                        // spoken label still carries it.
                        label: isCurrentStage
                            ? '${stage.weekRange}, ${stage.trimester}, your current month'
                            : '${stage.weekRange}, ${stage.trimester}, previewing this month',
                        child: Text(
                          stage.weekRange.toUpperCase(),
                          key:
                              ValueKey<String>('pregnancy-month-${stage.month}'),
                          style: TextStyle(
                            color: isCurrentStage
                                ? Colors.white
                                : AppColors.brandText,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      stage.trimester,
                      style: const TextStyle(
                        color: AppColors.brandText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (pregnancy.isTwinPregnancy)
                const Padding(
                  padding: EdgeInsets.only(left: 6, top: 4),
                  child: BabyBookTwinPregnancyBadge(light: false),
                ),
              Semantics(
                button: true,
                label: 'About this guide',
                child: IconButton(
                  key: const ValueKey('pregnancy-guide-disclaimer'),
                  tooltip: 'About this guide',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showPregnancyGuideDisclaimer(context),
                  icon: const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFD78C28),
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _FetalGrowthVisual(
            stage: stage,
            numberOfBabies: pregnancy.numberOfBabies,
          ),
          // The approximate length, weight and fruit comparison used to sit
          // here as three tinted tiles. They are averages for a month, not
          // measurements of her baby, and presented as three hard figures
          // beside her own record they read as though someone had measured.
          // The month's description below says what is developing, which is
          // what the section is for.
          const SizedBox(height: 17),
          _GrowthTextSection(
            icon: plural ? Icons.groups_2_outlined : Icons.favorite_outline,
            title: plural ? 'Your Babies This Month' : 'Your Baby This Month',
            child: Text(
              stage.developmentFor(pregnancy.numberOfBabies),
              style: const TextStyle(
                color: AppColors.inputText,
                fontSize: 14.5,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _GrowthTextSection(
            icon: Icons.auto_awesome_rounded,
            title: 'Development Highlights',
            child: _DotList(items: stage.developmentHighlights),
          ),
          const SizedBox(height: 12),
          _GrowthTextSection(
            icon: Icons.self_improvement_rounded,
            title: 'What Mom May Experience',
            child: _DotList(items: stage.motherChanges),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3F7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.health_and_safety_outlined,
                  color: AppColors.brandText,
                  size: 19,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'A gentle reminder',
                        style: TextStyle(
                          color: AppColors.headingSoft,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        stage.healthReminder,
                        style: const TextStyle(
                          color: AppColors.inputText,
                          fontSize: 14,
                          height: 1.5,
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
}

class _FetalGrowthVisual extends StatelessWidget {
  final PregnancyGrowthStage stage;
  final int numberOfBabies;

  const _FetalGrowthVisual({required this.stage, required this.numberOfBabies});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              stage.imageAsset,
              key: ValueKey<String>(stage.imageAsset),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _FetalVisualFallback(month: stage.month),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x660D0610)],
                  stops: [0.55, 1],
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 11,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Month ${stage.month} illustration',
                  style: const TextStyle(
                    color: AppColors.brandText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (numberOfBabies > 1)
              Positioned(
                right: 12,
                bottom: 11,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8055A6).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.child_friendly_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      Icon(
                        Icons.child_friendly_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'TWIN VIEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FetalVisualFallback extends StatelessWidget {
  final int month;

  const _FetalVisualFallback({required this.month});

  @override
  Widget build(BuildContext context) {
    final scale = 0.38 + (month * 0.055);
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFFFFD7E4), Color(0xFFF497B8)],
        ),
      ),
      alignment: Alignment.center,
      child: Transform.scale(
        scale: scale,
        child: const Icon(
          Icons.child_friendly_rounded,
          color: Color(0xFFFFF5F8),
          size: 120,
        ),
      ),
    );
  }
}

class _GrowthTextSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _GrowthTextSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF5E9EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.brandPrimary, size: 21),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.headingSoft,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DotList extends StatelessWidget {
  final List<String> items;

  const _DotList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 7),
                  decoration: const BoxDecoration(
                    color: AppColors.brandPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      // inputText, not textSecondary. At 14pt the old light
                      // grey sat near 3.5:1 against this near-white card,
                      // under the readable minimum — thin contrast is the
                      // first thing to fail on a cheap screen in daylight.
                      color: AppColors.inputText,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthNavigation extends StatelessWidget {
  final int currentIndex;
  final int currentPregnancyMonth;
  final int totalMonths;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onSelect;

  const _MonthNavigation({
    required this.currentIndex,
    required this.currentPregnancyMonth,
    required this.totalMonths,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF3E4EA)),
      ),
      // One line: back arrow, three months, forward arrow.
      //
      // All nine numbers used to sit in their own row beneath a "Month 3 of 9"
      // caption, which made three separate things to read before she could
      // move. Nine choices is also more than the control is for — she moves
      // one month at a time, and the two neighbours are the only ones she can
      // reach in a single tap anyway. Showing the neighbours instead of the
      // caption says "there is a month either side of this one" by making
      // them tappable, rather than by asking her to count.
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('pregnancy-previous'),
            tooltip: 'Previous pregnancy month',
            onPressed: onPrevious,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFFFEDF4),
              foregroundColor: AppColors.brandText,
              disabledForegroundColor: const Color(0xFFC7BFC2),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 19),
          ),
          Expanded(
            child: Semantics(
              // The visible "Month 3 of 9" is gone, so the position it carried
              // is handed to the screen reader here instead of being lost.
              label:
                  'Month ${currentIndex + 1} of $totalMonths, showing three months',
              container: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final month in _visibleMonths)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: _MonthCircle(
                        month: month,
                        selected: month == currentIndex + 1,
                        isCurrentPregnancyMonth:
                            month == currentPregnancyMonth,
                        onTap: () => onSelect(month - 1),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('pregnancy-next'),
            tooltip: 'Next pregnancy month',
            onPressed: onNext,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFFD5E5),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  /// The selected month and its two neighbours, as 1-based month numbers.
  ///
  /// Clamped at both ends so the row always holds three: month 1 shows 1-2-3
  /// and month 9 shows 7-8-9. Sliding the window instead of dropping a circle
  /// keeps the arrows in the same place as she pages through, so the control
  /// does not resize under her thumb.
  List<int> get _visibleMonths {
    if (totalMonths <= 3) {
      return <int>[for (var m = 1; m <= totalMonths; m++) m];
    }
    final start = (currentIndex - 1).clamp(0, totalMonths - 3);
    return <int>[start + 1, start + 2, start + 3];
  }
}

class _MonthCircle extends StatelessWidget {
  final int month;
  final bool selected;
  final bool isCurrentPregnancyMonth;
  final VoidCallback onTap;

  const _MonthCircle({
    required this.month,
    required this.selected,
    required this.isCurrentPregnancyMonth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // The month she is actually in keeps a ring of its own, so that after
    // browsing ahead she can still see which circle is her own month and
    // which one she is only reading about.
    final ringed = isCurrentPregnancyMonth && !selected;

    return Semantics(
      button: true,
      selected: selected,
      label: 'View pregnancy month $month',
      child: InkWell(
        key: ValueKey<String>('pregnancy-month-dot-$month'),
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: selected ? 44 : 38,
          height: selected ? 44 : 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brandPrimary : const Color(0xFFFBF4F7),
            shape: BoxShape.circle,
            border: ringed
                ? Border.all(color: AppColors.brandPrimary, width: 1.5)
                : null,
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: AppColors.brandPrimary.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            '$month',
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : ringed
                      ? AppColors.brandText
                      : AppColors.textSecondary,
              fontSize: selected ? 16 : 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
