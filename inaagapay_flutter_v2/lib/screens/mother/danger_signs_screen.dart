import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/pregnancy_danger_signs.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';

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
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            foregroundColor: AppColors.textPrimary,
            title: Text(
              _t('Go to the health center', 'Pumunta sa health center'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          body: Column(
            children: [
              // One sentence, then straight into the list. Nothing to read past.
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF1F1),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    const Icon(Icons.warning_rounded,
                        color: Color(0xFFD32F2F), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _t(
                          'If you feel any of these, go now. Do not wait.',
                          'Kung nararamdaman mo ang alinman dito, pumunta agad. Huwag maghintay.',
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB71C1C),
                        ),
                      ),
                    ),
                  ],
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
                        border: Border.all(
                            color: const Color(0xFFD32F2F)
                                .withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFEBEE),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(sign.icon,
                                color: const Color(0xFFD32F2F), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              sign.label,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
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
                        backgroundColor: const Color(0xFFD32F2F),
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
