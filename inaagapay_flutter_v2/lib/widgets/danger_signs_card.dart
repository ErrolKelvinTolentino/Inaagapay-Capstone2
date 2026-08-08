import 'package:flutter/material.dart';

import '../screens/mother/danger_signs_screen.dart';
import '../services/language_service.dart';

/// Always-present entry to the danger signs, sized as a link rather than an
/// alarm.
///
/// The tension is real: this content is the most time-critical in the app, so
/// it must always be reachable — but a mother seeing a big red warning block
/// every single day learns to look past it, and by the day it matters she no
/// longer sees it at all. So it stays one compact row: red enough to find,
/// small enough not to shout.
///
/// Red border *and* a warning icon *and* the word — never colour alone, for
/// colour-blind users and for cheap screens in daylight.
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
          color: const Color(0xFFFFF6F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFD32F2F).withValues(alpha: 0.35),
              width: 1.4),
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
                    t('When to get help fast', 'Kailan humingi ng agarang tulong'),
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
