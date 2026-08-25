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
        constraints: const BoxConstraints(minHeight: 128),
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          // Text and artwork are side by side, not stacked. The first version
          // laid words over the illustration behind a scrim, and pink type on
          // a pink drawing stayed muddy however the scrim was tuned. Giving
          // each its own column removes the problem rather than managing it.
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF7FB3), Color(0xFFE6398D)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandAccent.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('MY PREGNANCY', 'ANG AKING PAGBUBUNTIS'),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // One line where it fits, wrapping where it does not.
                  //
                  // The hard newline forced two lines on every screen, however
                  // wide. Removing it lets the title sit on one across
                  // ordinary phone widths and wrap only when it truly cannot.
                  //
                  // Deliberately *not* a FittedBox: that would hold one line
                  // by scaling the type down, which cancels a mother's system
                  // text-size setting — the audience most likely to have it
                  // turned up. Wrapping and letting the banner grow is what
                  // the tests in my_pregnancy_banner_test pin, and it is the
                  // right behaviour.
                  //
                  // Note for anyone measuring this under test: flutter_test
                  // substitutes a fixed-width placeholder font where every
                  // glyph is one em, so a widget test reports this wrapping
                  // when the real font does not. Line count here has to be
                  // checked on a device, not in the suite.
                  Text(
                    // Named for what it opens. "Everything about your journey"
                    // described a feeling rather than a destination, and the
                    // page behind it is the mother-and-baby book — the thing a
                    // mother already knows by name from her health centre.
                    t('Mother and Baby Book', 'Aklat ng Ina at Sanggol'),
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // White pill on pink: high contrast, and clearly a way in
                  // rather than a button that submits something.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                            color: AppColors.brandAccent,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 13, color: AppColors.brandAccent),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // A soft disc behind the cut-out figure lifts her off the pink
            // without a hard edge, and matches the circular treatment the
            // hero and baby-size cards already use.
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(4),
              child: const Image(
                // 1080px source rendered at 96 logical px; decoding at 300
                // is ample and saves the rest.
                image: ResizeImage(
                  AssetImage('assets/images/pregnant1.png'),
                  width: 300,
                ),
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
