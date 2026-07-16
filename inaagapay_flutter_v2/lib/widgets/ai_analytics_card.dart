// lib/widgets/ai_analytics_card.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/language_service.dart';
import 'profile_helpers.dart';

class AiAnalyticsCard extends StatefulWidget {
  final String text;
  final bool isLoading;

  const AiAnalyticsCard({
    super.key,
    required this.text,
    this.isLoading = false,
  });

  @override
  State<AiAnalyticsCard> createState() => _AiAnalyticsCardState();
}

class _AiAnalyticsCardState extends State<AiAnalyticsCard> {
  bool _isExpanded = false;
  late bool _showFilipino;

  @override
  void initState() {
    super.initState();
    // Default to the app's current language setting
    _showFilipino = LanguageService.isFilipino;
    LanguageService.selectedLanguage.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    LanguageService.selectedLanguage.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) {
      setState(() {
        _showFilipino = LanguageService.isFilipino;
      });
    }
  }

  @override
  void didUpdateWidget(covariant AiAnalyticsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      _isExpanded = false;
    }
  }

  String _extractLanguageSection(String fullText, bool filipino) {
    final normalized = fullText.replaceAll('\r\n', '\n');

    final englishRegex = RegExp(
      r'(?:^|\n)(?:#+\s*|\*+|\[)?English(?:#+\s*|\*+|\])?:?\s*?\n([\s\S]*?)(?=(?:^|\n)(?:#+\s*|\*+|\[)?(?:Filipino|Tagalog)(?:#+\s*|\*+|\[)?:?|$)',
      caseSensitive: false,
    );
    final filipinoRegex = RegExp(
      r'(?:^|\n)(?:#+\s*|\*+|\[)?(?:Filipino|Tagalog)(?:#+\s*|\*+|\[)?:?\s*?\n([\s\S]*?)(?=(?:^|\n)(?:#+\s*|\*+|\[)?English(?:#+\s*|\*+|\[)?:?|$)',
      caseSensitive: false,
    );

    final englishMatch = englishRegex.firstMatch(normalized);
    final filipinoMatch = filipinoRegex.firstMatch(normalized);

    final englishText = englishMatch?.group(1)?.trim();
    final filipinoText = filipinoMatch?.group(1)?.trim();

    if (filipino) {
      return filipinoText ?? englishText ?? normalized.trim();
    }
    return englishText ?? filipinoText ?? normalized.trim();
  }

  String _selectedText(String fullText) {
    final text = _extractLanguageSection(fullText, _showFilipino);
    return text.isEmpty ? fullText.replaceAll('\r\n', '\n').trim() : text;
  }

  String _getSummary(String fullText) {
    final trimmed = fullText.trim();
    if (trimmed.length <= 200) return trimmed;

    final lines =
        trimmed.split('\n').where((line) => line.trim().isNotEmpty).toList();
    final buffer = StringBuffer();

    for (final line in lines) {
      final textLine = line.trim();
      if (buffer.length + textLine.length > 210) {
        if (buffer.isEmpty) {
          return '${textLine.substring(0, 210)}...';
        }
        break;
      }
      buffer.writeln(textLine);
      if (buffer.length > 170) break;
    }

    final summary = buffer.toString().trim();
    return summary.length < trimmed.length ? '$summary...' : summary;
  }

  Widget _buildLanguageToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildLanguageButton('English', !_showFilipino),
        const SizedBox(width: 8),
        _buildLanguageButton('Filipino', _showFilipino),
      ],
    );
  }

  Widget _buildLanguageButton(String label, bool selected) {
    return TextButton(
      onPressed: () {
        setState(() {
          _showFilipino = label == 'Filipino';
        });
      },
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? AppColors.brandPrimary.withValues(alpha: 0.12)
            : AppColors.bgSecondary,
        foregroundColor:
            selected ? AppColors.brandPrimary : AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.brandPrimary : AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedText = _selectedText(widget.text);
    final displayText = _isExpanded ? selectedText : _getSummary(selectedText);
    final shouldShowToggle = selectedText.length > 200;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.brandPrimary.withValues(alpha: 0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: AppColors.brandPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'AI GROWTH ANALYSIS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(
                  color: AppColors.brandPrimary,
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLanguageToggle(),
                const SizedBox(height: 12),
                buildFormattedAiText(displayText),
                if (shouldShowToggle) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                      },
                      icon: Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _isExpanded ? 'Show less' : 'Show full',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brandPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
