import 'package:flutter/material.dart';

import '../screens/mother/danger_signs_screen.dart';
import '../services/language_service.dart';

/// Entry to the danger signs, styled as **reference, not an alert**.
///
/// The first version of this was red-on-pink and sat near the top of Home. It
/// read as "something is wrong right now", which is false on almost every day
/// she opens the app — and a warning shown daily stops being seen, so by the
/// day it matters she looks past it. An alert should fire when something *is*
/// wrong; a mother's standing reference for what to watch for should be calm
/// and findable.
///
/// So: a white card in the ordinary run of cards, one red accent on the icon
/// to make it locatable at a glance, and no red fill or red border. The full
/// screen behind it is red-accented, which is right — by then she has chosen
/// to look.
///
/// Icon *and* words, never colour alone, for colour-blind users and cheap
/// screens in daylight.
class DangerSignsCard extends StatelessWidget {
  const DangerSignsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LanguageService.translate;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DangerSignsScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFD32F2F).withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_rounded,
                  color: Color(0xFFD32F2F), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Phrased as something to know, not something happening.
                    t('Know the warning signs', 'Alamin ang mga babala'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t('Signs that mean go now',
                        'Mga senyales na dapat pumunta agad'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 15, color: Color(0xFFD32F2F)),
          ],
        ),
      ),
    );
  }
}
