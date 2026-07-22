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
        Text(
          'PREGNANCY GROWTH',
          style: const TextStyle(
            color: AppColors.brandText,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          plural ? 'Your Babies’ Growth Journey' : 'Your Baby’s Growth Journey',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.45,
          ),
        ),
        const SizedBox(height: 12),
        _CurrentPregnancySummary(pregnancy: pregnancy),
        const SizedBox(height: 16),
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
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8EA),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFFFE1A3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFD78C28),
                size: 18,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Every pregnancy develops differently. The information shown is a general guide and does not replace advice from your doctor or midwife.',
                  style: TextStyle(
                    color: Color(0xFF8A632D),
                    fontSize: 10,
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

class _CurrentPregnancySummary extends StatelessWidget {
  final CurrentPregnancyState pregnancy;

  const _CurrentPregnancySummary({required this.pregnancy});

  @override
  Widget build(BuildContext context) {
    final percentage = (pregnancy.pregnancyProgress * 100).round();

    return BabyBookPictureCardShell(
      key: const ValueKey<String>('current-pregnancy-picture-card'),
      assetPath: 'assets/images/current_pregnancy_card.png',
      semanticLabel: 'Pregnant mother holding her growing belly',
      height: 196,
      imageKey: const ValueKey('current-pregnancy-card-artwork'),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'CURRENT PREGNANCY',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.05,
                  ),
                ),
                const Spacer(),
                if (pregnancy.isTwinPregnancy)
                  const BabyBookTwinPregnancyBadge(light: true),
              ],
            ),
            const SizedBox(height: 9),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 250),
              child: Text(
                'Currently ${pregnancy.currentWeek} Weeks Pregnant',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Month ${pregnancy.currentMonth} • ${pregnancy.trimester}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Pregnancy progress',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '$percentage%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                minHeight: 6,
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
                  size: 15,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Estimated due date: ${babyBookFormatDate(pregnancy.estimatedDueDate)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.94),
                      fontSize: 9,
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
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isCurrentStage
                      ? AppColors.brandPrimary
                      : const Color(0xFFFFEDF4),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  isCurrentStage
                      ? 'YOUR CURRENT STAGE'
                      : 'PREGNANCY GUIDE PREVIEW',
                  style: TextStyle(
                    color: isCurrentStage ? Colors.white : AppColors.brandText,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.65,
                  ),
                ),
              ),
              const Spacer(),
              if (pregnancy.isTwinPregnancy)
                const BabyBookTwinPregnancyBadge(light: false),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Month ${stage.month} — ${stage.weekRange}',
            key: ValueKey<String>('pregnancy-month-${stage.month}'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 21,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stage.trimester,
            style: const TextStyle(
              color: AppColors.brandText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _FetalGrowthVisual(
            stage: stage,
            numberOfBabies: pregnancy.numberOfBabies,
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _GrowthMetric(
                  icon: Icons.straighten_rounded,
                  value: stage.approximateLength,
                  label: 'Approx. length',
                  color: const Color(0xFF5AAE9F),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GrowthMetric(
                  icon: Icons.monitor_weight_outlined,
                  value: stage.approximateWeight,
                  label: 'Approx. weight',
                  color: const Color(0xFFF09B57),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GrowthMetric(
                  icon: Icons.eco_outlined,
                  value: stage.sizeComparison,
                  label: 'About the size of',
                  color: AppColors.brandPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          _GrowthTextSection(
            icon: plural ? Icons.groups_2_outlined : Icons.favorite_outline,
            title: plural ? 'Your Babies This Month' : 'Your Baby This Month',
            child: Text(
              stage.developmentFor(pregnancy.numberOfBabies),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
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
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stage.healthReminder,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
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
                  'Educational month ${stage.month} illustration',
                  style: const TextStyle(
                    color: AppColors.brandText,
                    fontSize: 8,
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

class _GrowthMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _GrowthMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 8,
              height: 1.2,
            ),
          ),
        ],
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
              Icon(icon, color: AppColors.brandPrimary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
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
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    color: AppColors.brandPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      height: 1.45,
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
      child: Column(
        children: [
          Row(
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
                child: Text(
                  'Month ${currentIndex + 1} of $totalMonths',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalMonths, (index) {
              final selected = index == currentIndex;
              final actual = index + 1 == currentPregnancyMonth;
              return Semantics(
                button: true,
                selected: selected,
                label: 'View pregnancy month ${index + 1}',
                child: InkWell(
                  key: ValueKey<String>('pregnancy-month-dot-${index + 1}'),
                  onTap: () => onSelect(index),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: selected ? 26 : 22,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.brandPrimary
                          : actual
                              ? const Color(0xFFFFD6E6)
                              : const Color(0xFFF7F1F4),
                      shape: BoxShape.circle,
                      border: actual && !selected
                          ? Border.all(color: AppColors.brandPrimary)
                          : null,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : actual
                                ? AppColors.brandText
                                : AppColors.textSecondary,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
