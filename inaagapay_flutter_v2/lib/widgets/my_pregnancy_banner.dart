import 'package:flutter/material.dart';

import '../services/language_service.dart';
import '../theme/app_colors.dart';

/// The way into the Mother Book, and the most prominent thing on Home.
///
/// Styled as an illustrated feature card rather than a filled button. The
/// distinction matters: a solid CTA promises that tapping *submits* something,
/// and this only opens a page to read. Artwork and an "Open →" pill invite the
/// tap without making that promise.
///
/// Lives in its own file so its layout can be tested. It previously sat inside
/// MotherDashboard as a private method, where the only way to render it was to
/// build the whole dashboard — which needs Supabase and so renders a spinner
/// under test. A layout bug there was invisible to the suite, and one shipped:
/// a hard 132px height clipped the pill by 8 pixels.
class MyPregnancyBanner extends StatelessWidget {
  const MyPregnancyBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LanguageService.translate;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        // Content drives the height. A fixed height clipped the pill, and
        // would clip far more for a mother using large system text — a
        // setting this audience is more likely than most to have on.
        constraints: const BoxConstraints(minHeight: 132),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          image: const DecorationImage(
            // Decoded at 800px, not its native 1823px. A 2.1 MB illustration
            // rendered into a card about 320px wide costs roughly 6 MB of
            // memory at full decode, for no visible gain — the kind of waste
            // that shows up as jank on the cheap phones this app is for.
            image: ResizeImage(
              AssetImage('assets/images/current_pregnancy_card.png'),
              width: 800,
            ),
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandPrimary.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Scrim over the left side only, so the words stay legible while
            // the illustration keeps its detail on the right.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.92),
                      Colors.white.withValues(alpha: 0.72),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.42, 0.78],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('MY PREGNANCY', 'ANG AKING PAGBUBUNTIS'),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  // Capped rather than fixed, so the text wraps inside the
                  // clear part of the illustration on a narrow phone instead
                  // of running under the artwork.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 195),
                    child: Text(
                      t('Everything about your journey',
                          'Lahat tungkol sa iyong paglalakbay'),
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppColors.brandText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t('Open', 'Buksan'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 13, color: Colors.white),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
