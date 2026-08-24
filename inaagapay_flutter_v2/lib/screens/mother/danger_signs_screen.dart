import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/pregnancy_danger_signs.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';

/// The full danger-sign list, and the one action that follows from it.
///
/// Read in a hurry, possibly at night, possibly by someone who reads slowly.
/// So: one sign per row, a distinct icon on every row, no clinical vocabulary,
/// nothing to scroll past before the list starts, and a call button pinned to
/// the bottom so it is reachable without scrolling back.
class DangerSignsScreen extends StatelessWidget {
  const DangerSignsScreen({super.key});

  static const String _emergencyNumber = '911';

  String _t(String english, String filipino) =>
      LanguageService.translate(english, filipino);

  Future<void> _call(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: _emergencyNumber);
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Please dial $_emergencyNumber',
              'Pakitawagan ang $_emergencyNumber')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          // The shared header, so this page belongs to the app rather than
          // arriving as a separate warning screen.
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: SecondaryHeader(
              title: _t('Warning signs', 'Mga babalang senyales'),
              onBack: () => Navigator.pop(context),
            ),
          ),
          body: Column(
            children: [
              // A card with room around it rather than a full-bleed red band
              // clamped under the header. The sentence is unchanged — it is
              // the right sentence — but a warning that fills the top of the
              // screen edge to edge reads as an alarm going off, and she may
              // be here just to check something.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFAD1D1)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFDE7E7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.priority_high_rounded,
                            color: Color(0xFFD98080), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _t(
                            // "go now" is load-bearing and guarded by a test —
                            // the instruction has to be unhedged. The
                            // destination is named after it rather than in
                            // place of it, since the page heading no longer
                            // says where to go.
                            'If you feel any of these, go now to the health center. Do not wait.',
                            'Kung nararamdaman mo ang alinman dito, pumunta agad sa health center. Huwag maghintay.',
                          ),
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9E5A5A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  itemCount: pregnancyDangerSigns.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final sign = pregnancyDangerSigns[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderPrimary),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFDE7E7),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(sign.icon,
                                color: const Color(0xFFD98080), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              sign.label,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inputText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Pinned, so it is reachable without scrolling back up.
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: () => _call(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD9534F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.call_rounded, size: 22),
                      label: Text(
                        _t('Call $_emergencyNumber', 'Tumawag sa $_emergencyNumber'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
