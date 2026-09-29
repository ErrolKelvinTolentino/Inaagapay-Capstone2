import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/danger_signs_card.dart';
import '../../widgets/secondary_header.dart';

/// Numbers to call, and the signs that say when to call them.
///
/// This was a tab of its own on her bottom bar. It is now a page opened from
/// Home, which every mother has — registered or not — so it stays reachable
/// for the mother with no midwife to call, who needs it most.
class HotlinesScreen extends StatelessWidget {
  const HotlinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: SecondaryHeader(
              title: LanguageService.translate('Hotlines', 'Hotlines'),
              onBack: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LanguageService.translate(
                    'Numbers to call',
                    'Mga numerong matatawagan',
                  ),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    // Brand pink, like every other page heading on her side.
                    // "EMERGENCY HOTLINES" in near-black w800 greeted her with
                    // the word emergency before she had asked anything.
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  LanguageService.translate(
                    'Tap a number to call it. Hold it down to copy.',
                    'I-tap ang numero para tumawag. Pindutin nang matagal para kopyahin.',
                  ),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                // Placed above the numbers on purpose. Someone who opens this
                // page is already worried but may not know whether what she is
                // feeling warrants a call. Answering that comes before giving
                // her a number to dial.
                const DangerSignsCard(),
                const SizedBox(height: 16),

                _HotlineButton(
                  label: LanguageService.translate(
                      'National Emergency Hotline',
                      'Pambansang Emergency Hotline'),
                  number: '911',
                  icon: Icons.local_hospital,
                  color: AppColors.error,
                ),
                const SizedBox(height: 12),
                _HotlineButton(
                  label: LanguageService.translate(
                      'DOH Health Hotline', 'DOH Health Hotline'),
                  number: '1555',
                  icon: Icons.phone,
                  color: AppColors.brandPrimary,
                ),
                const SizedBox(height: 12),
                _HotlineButton(
                  label: LanguageService.translate(
                      'Philippine Red Cross', 'Philippine Red Cross'),
                  number: '143',
                  icon: Icons.health_and_safety,
                  color: const Color(0xFFD32F2F),
                ),
                const SizedBox(height: 12),
                _HotlineButton(
                  label: LanguageService.translate(
                      'PNP Emergency', 'PNP Emergency'),
                  number: '117',
                  icon: Icons.shield,
                  color: const Color(0xFF1565C0),
                ),
                const SizedBox(height: 12),
                _HotlineButton(
                  label: LanguageService.translate(
                      'Bureau of Fire Protection', 'Bureau of Fire Protection'),
                  number: '160',
                  icon: Icons.local_fire_department,
                  color: const Color(0xFFE65100),
                ),
                const SizedBox(height: 12),
                _HotlineButton(
                  label: LanguageService.translate(
                      'Mental Health Crisis Line', 'Mental Health Crisis Line'),
                  number: '1553',
                  icon: Icons.psychology,
                  color: const Color(0xFF7B1FA2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HotlineButton extends StatelessWidget {
  final String label;
  final String number;
  final IconData icon;
  final Color color;

  const _HotlineButton({
    required this.label,
    required this.number,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // A white row with a tinted icon, not a tinted pill.
    //
    // Six differently-coloured pills stacked down the page — red, pink, red,
    // blue, orange, purple — read as a colour chart, and none of those colours
    // was the app's. The service colour now lives only in the small icon disc,
    // which is enough to tell them apart, and the rest matches every other
    // list a mother sees.
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final uri = Uri.parse('tel:$number');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(LanguageService.translate(
                      'Could not launch $number',
                      'Hindi mabuksan ang $number')),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          }
        },
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: number));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                LanguageService.translate(
                  '$number copied to clipboard',
                  '$number kinopya sa clipboard',
                ),
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: color,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inputText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // The number itself, shown rather than hidden behind a
                    // tap. She could not see what she was about to dial, and
                    // a number she can read is one she can also write down or
                    // give to someone else.
                    Text(
                      number,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: AppColors.brandText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_rounded,
                    size: 18, color: AppColors.brandPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
