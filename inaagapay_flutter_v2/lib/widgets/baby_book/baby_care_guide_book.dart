// lib/widgets/baby_book/baby_care_guide_book.dart
//
// The eight-page DOH/UNICEF care guide, as a self-contained paged reader.
//
// It used to live inside the *pregnancy* baby book, which is where a mother
// eleven weeks pregnant was shown "Baby's first days", "Feeding through the
// first year" and "Make every space safer". Every page but the first is about
// a baby who has been born, so the guide now sits in the baby book of a
// registered child, where it is about someone who exists.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The heading the guide draws for itself, so it no longer depends on a
/// private widget belonging to the pregnancy page.
class _GuideHeading extends StatelessWidget {
  const _GuideHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BABY CARE GUIDE',
          style: TextStyle(
            color: AppColors.brandPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Read the book, page by page',
          style: TextStyle(
            color: AppColors.inputText,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class BabyCareGuideBook extends StatefulWidget {
  const BabyCareGuideBook({super.key});

  static const List<_GuidePageData> _pages = [
    _GuidePageData(
      number: 1,
      icon: Icons.auto_stories_rounded,
      imagePath: 'assets/images/baby_guide_page_1.png',
      title: 'How to use this baby book',
      takeaway: 'Bring this book to every visit.',
      paragraphs: [
        'Keep this Baby Book where every caregiver can find it. Read it together, write down your baby’s growth, vaccines, checkups and special moments, and bring it to every visit so you can discuss each entry with a doctor, nurse, midwife or barangay health worker.',
        'The record belongs with your family, but it works alongside the clinic’s records—not as a replacement for them. Use the questions and notes pages to prepare for appointments, and ask a health worker whenever an instruction is unclear.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF p. 4 • WHO guideline: pp. 9, 21–22',
      accent: Color(0xFFFF68A5),
    ),
    _GuidePageData(
      number: 2,
      icon: Icons.child_friendly_rounded,
      imagePath: 'assets/images/baby_guide_page_2.png',
      title: 'Baby’s first days',
      takeaway: 'Hold baby skin-to-skin and feed early.',
      paragraphs: [
        'After birth, keep baby warm with immediate skin-to-skin contact when possible and begin breastfeeding early. Colostrum is baby’s important first milk. The DOH guide also recommends delaying the first bath for about 24 hours while keeping baby clean, warm and close.',
        'Before going home, ask about the newborn examination, newborn screening, vitamin K, eye care, BCG and hepatitis B vaccination. Register the birth certificate within 30 days, then keep the official details and health results together in this book.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 5, 34–37',
      accent: Color(0xFF8E7CC3),
    ),
    _GuidePageData(
      number: 3,
      icon: Icons.restaurant_rounded,
      imagePath: 'assets/images/baby_guide_page_3.png',
      title: 'Feeding through the first year',
      takeaway: 'Only breast milk until six months.',
      paragraphs: [
        'From birth through six months, give only breast milk—no other food or water—unless a qualified health professional gives different advice for your baby. Feed responsively by noticing early hunger and fullness cues. If feeding is painful or difficult, ask the health center for support.',
        'At about six months, begin safe and nutritious complementary food while continuing breastfeeding. Start with soft mashed food in small amounts, then gradually offer thicker textures, finger foods and varied family foods as baby develops. Use fresh ingredients, sit with baby during meals and never force-feed.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 21–23, 51, 57–60, 68',
      accent: Color(0xFFF29B61),
    ),
    _GuidePageData(
      number: 4,
      icon: Icons.health_and_safety_rounded,
      imagePath: 'assets/images/baby_guide_page_4.png',
      title: 'Make every space safer',
      takeaway: 'Keep baby within reach, always.',
      paragraphs: [
        'A baby needs an attentive adult nearby. For sleep, place baby on a safe, firm sleep surface and keep pillows, loose blankets and soft objects away. Prevent falls, and keep hot liquids, medicines, cleaning products, matches, plastic bags, cords and small choking hazards locked away or out of reach.',
        'Choose age-appropriate toys and supervise all play. Use an appropriate child restraint when travelling, never leave a child alone in a vehicle, and stay within reach around a bath, pool, river or any open water—even for a moment. Keep baby away from tobacco smoke.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 13–17',
      accent: Color(0xFF4B8FD8),
    ),
    _GuidePageData(
      number: 5,
      icon: Icons.soap_rounded,
      imagePath: 'assets/images/baby_guide_page_5.png',
      title: 'Clean hands, food and surroundings',
      takeaway: 'Wash hands before every feed.',
      paragraphs: [
        'Wash hands with soap and safe water for at least 20 seconds before preparing food or feeding baby, and after using the toilet or changing a diaper. Let hands air-dry or use a clean towel. Dispose of stool safely, clean reusable diaper materials carefully and wash the child’s hands too.',
        'Prepare food with clean tools and safe water, keep raw and cooked food separate, cook food thoroughly and protect it from pests. A clean feeding area and safely grown or selected food help make everyday nutrition safer.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 24–29',
      accent: Color(0xFF54B6A5),
    ),
    _GuidePageData(
      number: 6,
      icon: Icons.show_chart_rounded,
      imagePath: 'assets/images/baby_guide_page_6.png',
      title: 'Follow growth and development',
      takeaway: 'Every child grows at their own pace.',
      paragraphs: [
        'Record weight and length during checkups and review the growth chart with a health worker. Development includes movement, hand skills, self-help, language, thinking, and social-emotional skills. The examples in this book are guides, not strict deadlines, because every child develops at an individual pace.',
        'Help development every day through warm, responsive care. Talk, sing, smile, read and play using clean, safe objects. Notice what interests your child, praise new attempts and write down new skills or concerns so they can be discussed early.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 32–33, 38, 41, 58, 74, 88',
      accent: Color(0xFFEE7E9D),
    ),
    _GuidePageData(
      number: 7,
      icon: Icons.medical_services_rounded,
      imagePath: 'assets/images/baby_guide_page_7.png',
      title: 'Checkups, vaccines and warning signs',
      takeaway: 'Do not wait if baby seems unwell.',
      paragraphs: [
        'The DOH booklet lists routine visits for the newborn period, 3–5 days, and months 1, 2, 4, 6, 9 and 12; then months 15, 18, 24 and 30, followed by annual visits from ages 3 to 10. Bring this book each time and ask the health worker to update growth, findings, vaccines and the return date.',
        'Do not wait for a scheduled visit if baby has trouble breathing, blue or gray skin, fever, seizures, signs of dehydration, poor feeding, unusual sleepiness or another sudden worrying change. Seek prompt care from a health facility. Follow the current national vaccine schedule given by your health center because schedules may be updated.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 6, 30–31, 126',
      accent: Color(0xFFE06B65),
    ),
    _GuidePageData(
      number: 8,
      icon: Icons.diversity_1_rounded,
      imagePath: 'assets/images/baby_guide_page_8.png',
      title: 'Care is a team effort',
      takeaway: 'You do not have to do this alone.',
      paragraphs: [
        'Caring for a child takes a village. List the relatives, friends, neighbors and community workers who can offer practical or emotional support. Share the baby’s routines and important instructions with trusted caregivers, and encourage them to record useful observations in the same place.',
        'WHO recommends home-based records to improve communication, care-seeking and support at home. Keep personal health information private, allow only trusted people to view it, and remember that written education works best when it is paired with continuing care and conversation with trained health workers.',
      ],
      source:
          'DOH/UNICEF Baby Book: PDF pp. 4, 10 • WHO guideline: pp. 9, 21–22',
      accent: Color(0xFF9A76B9),
    ),
  ];

  @override
  State<BabyCareGuideBook> createState() => BabyCareGuideBookState();
}

class BabyCareGuideBookState extends State<BabyCareGuideBook> {
  int _currentPageIndex = 0;

  void _showPreviousPage() {
    if (_currentPageIndex == 0) return;
    setState(() => _currentPageIndex--);
  }

  void _showNextPage() {
    if (_currentPageIndex == BabyCareGuideBook._pages.length - 1) return;
    setState(() => _currentPageIndex++);
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = BabyCareGuideBook._pages[_currentPageIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _GuideHeading(),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFEFF5), Color(0xFFFFF9F1)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFFDCE9)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GuideBookIcon(),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ONE CONTINUOUS BOOK',
                      style: TextStyle(
                        color: AppColors.brandText,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Use the Back and Next arrows to read all eight pages. Each page turns official DOH and WHO guidance into a short, readable family instruction.',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
                child: child,
              ),
            );
          },
          child: _GuidePaperPage(
            key: ValueKey<int>(currentPage.number),
            data: currentPage,
          ),
        ),
        const SizedBox(height: 16),
        _GuidePageNavigation(
          currentPage: _currentPageIndex + 1,
          totalPages: BabyCareGuideBook._pages.length,
          onPrevious: _currentPageIndex == 0 ? null : _showPreviousPage,
          onNext: _currentPageIndex == BabyCareGuideBook._pages.length - 1
              ? null
              : _showNextPage,
        ),
      ],
    );
  }
}

class _GuidePageNavigation extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _GuidePageNavigation({
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF3E4EA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69243F).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: onPrevious,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandText,
              disabledForegroundColor: AppColors.textSecondary,
              side: BorderSide(
                color: onPrevious == null
                    ? const Color(0xFFEAEAEA)
                    : const Color(0xFFFFC5DC),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text(
              'Back',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Page $currentPage of $totalPages',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(totalPages, (index) {
                    final isCurrent = index == currentPage - 1;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: isCurrent ? 13 : 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppColors.brandPrimary
                            : const Color(0xFFFFD8E7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFFD5E5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Next',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                SizedBox(width: 5),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidePageData {
  final int number;
  final IconData icon;
  final String imagePath;
  final String title;

  /// The one line to take away, for a mother who reads no further.
  ///
  /// Every page is two paragraphs of 45–55 words — around 1,100 words across
  /// the book — written in the register of a public-health booklet. That is a
  /// lot to ask of someone reading on a phone, in a second language, possibly
  /// with a baby in the other arm. Each takeaway is drawn from the paragraphs
  /// beneath it and adds nothing to them; it is a way in, not a replacement.
  final String takeaway;

  final List<String> paragraphs;
  final String source;
  final Color accent;

  const _GuidePageData({
    required this.number,
    required this.icon,
    required this.imagePath,
    required this.title,
    required this.takeaway,
    required this.paragraphs,
    required this.source,
    required this.accent,
  });
}

class _GuideBookIcon extends StatelessWidget {
  const _GuideBookIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.brandPrimary,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(7),
          right: Radius.circular(13),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 27),
    );
  }
}

class _GuidePaperPage extends StatelessWidget {
  final _GuidePageData data;

  const _GuidePaperPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEDE4D7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B4632).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      // The spine is painted behind the content rather than measured beside
      // it.
      //
      // It used to be a 6px Container in a Row inside an IntrinsicHeight, so
      // the whole page was laid out twice — and an intrinsic pass around an
      // ExpansionTile that animates its height overflowed by a couple of
      // pixels every time the source note opened. A Positioned fill stretches
      // the spine without any second measurement.
      //
      // Not a left BorderSide either: a Border with a radius has to be one
      // colour, so an accent edge and a cream edge cannot share one box.
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 6,
            child: ColoredBox(color: data.accent),
          ),
          Padding(
                padding: const EdgeInsets.fromLTRB(26, 20, 20, 17),
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
                            color: data.accent.withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            'PAGE ${data.number}',
                            style: TextStyle(
                              color: data.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(data.icon, color: data.accent, size: 23),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      data.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Georgia',
                        fontSize: 21,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 13),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: AspectRatio(
                        aspectRatio: 2,
                        child: Image.asset(
                          data.imagePath,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: data.accent.withValues(alpha: 0.08),
                              alignment: Alignment.center,
                              child: Icon(
                                data.icon,
                                color: data.accent,
                                size: 40,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    // The takeaway, before the prose.
                    //
                    // A mother who reads only this has still got the page.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: data.accent.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.push_pin_rounded,
                              size: 15, color: data.accent),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              data.takeaway,
                              style: TextStyle(
                                color: data.accent,
                                fontSize: 14.5,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    for (var index = 0;
                        index < data.paragraphs.length;
                        index++) ...[
                      Text(
                        data.paragraphs[index],
                        // Ragged right, not justified.
                        //
                        // Justifying a narrow column stretches the spaces to
                        // force each line flush, which opens rivers of white
                        // down the paragraph and gives the eye nothing to track
                        // — it is measurably harder to read, and hardest for
                        // people who already read slowly. On a phone-width
                        // column of 50-word paragraphs it was the worst
                        // possible setting.
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                          color: Color(0xFF544C45),
                          fontFamily: 'Georgia',
                          // 13pt serif on a low-density screen is small. The
                          // book feel is worth keeping; the strain is not.
                          fontSize: 14.5,
                          height: 1.7,
                        ),
                      ),
                      if (index != data.paragraphs.length - 1)
                        const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 17),
                    Container(height: 1, color: const Color(0xFFEDE4D7)),
                    const SizedBox(height: 4),
                    // The citation, folded away.
                    //
                    // "SOURCE NOTES • DOH/UNICEF Baby Book: PDF pp. 32–33, 38,
                    // 41, 58, 74, 88" sat open at the foot of all eight pages.
                    // A source should be available — a mother is entitled to
                    // know where advice about her baby comes from — but page
                    // numbers into a PDF she has never seen are apparatus, not
                    // information, and they closed every page on a line she
                    // could not use.
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          'Where this comes from',
                          style: TextStyle(
                            color: data.accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding:
                            const EdgeInsets.only(bottom: 6),
                        dense: true,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              data.source,
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
                ),
              ),
        ],
      ),
    );
  }
}
