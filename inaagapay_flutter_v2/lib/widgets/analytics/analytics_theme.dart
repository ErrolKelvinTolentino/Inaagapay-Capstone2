// lib/widgets/analytics/analytics_theme.dart
//
// One palette and one measuring stick for every analytics card.
//
// The rule that matters clinically: severity colours are reserved for
// severity. Green, amber and red mean good, watch and alert — never "the third
// series in this chart". A midwife scanning a dashboard reads red as danger
// before she reads the label, so spending red on an ordinary age band spends
// the alarm on nothing. Ordered categories are drawn in a single-hue ramp of
// the brand pink instead, which also keeps every chart looking like it belongs
// to the same product.

import 'package:flutter/material.dart';

import '../../models/midwife_analytics.dart';
import '../../theme/app_colors.dart';

class AnalyticsTheme {
  const AnalyticsTheme._();

  // ===== SHAPE =====
  static const double cardRadius = 20;
  static const EdgeInsets cardPadding = EdgeInsets.all(18);
  static const double barRadius = 8;

  // ===== TYPE =====
  static const TextStyle titleStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle periodStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static const TextStyle headlineStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: AppColors.brandPrimary,
    height: 1.05,
  );

  static const TextStyle captionStyle = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
    height: 1.3,
  );

  static const TextStyle bandLabelStyle = TextStyle(
    fontSize: 12,
    color: AppColors.textPrimary,
  );

  static const TextStyle bandValueStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle axisStyle = TextStyle(
    fontSize: 10,
    color: AppColors.textSecondary,
    height: 1.2,
  );

  static const TextStyle insightStyle = TextStyle(
    fontSize: 12.5,
    height: 1.45,
    color: AppColors.textPrimary,
  );

  static const TextStyle footnoteStyle = TextStyle(
    fontSize: 11,
    height: 1.35,
    color: AppColors.textSecondary,
  );

  static const TextStyle actionStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.brandPrimary,
  );

  // ===== COLOUR =====

  /// Ordered categories, light to deep. One hue family, so a five-band age
  /// chart and a four-band month chart still look like the same dashboard.
  static const List<Color> brandRamp = [
    Color(0xFFFFC9DF),
    Color(0xFFFFA6C8),
    Color(0xFFFF85B4),
    Color(0xFFFF68A5),
    Color(0xFFE6398D),
    Color(0xFFC73578),
  ];

  /// Nothing was measured. A grey, never a green — see [AnalyticsSeverity].
  static const Color unknownColor = Color(0xFFCFCFCF);

  static Color severityColor(AnalyticsSeverity severity) {
    switch (severity) {
      case AnalyticsSeverity.good:
        return AppColors.success;
      case AnalyticsSeverity.watch:
        return AppColors.warning;
      case AnalyticsSeverity.alert:
        return AppColors.error;
      case AnalyticsSeverity.unknown:
        return unknownColor;
      case AnalyticsSeverity.neutral:
        return AppColors.brandPrimary;
    }
  }

  static Color toneColor(AnalyticsTone tone) {
    switch (tone) {
      case AnalyticsTone.good:
        return AppColors.success;
      case AnalyticsTone.watch:
        return AppColors.warning;
      case AnalyticsTone.alert:
        return AppColors.error;
      case AnalyticsTone.neutral:
        return AppColors.brandPrimary;
    }
  }

  /// The colour a band is drawn in.
  ///
  /// Neutral bands take their shade from position in the ramp, so an ordered
  /// series reads as a sequence rather than as a set of unrelated colours.
  /// Bands that carry clinical meaning keep their severity colour.
  static Color bandColor(AnalyticsBand band, int index, int total) {
    if (band.severity != AnalyticsSeverity.neutral) {
      return severityColor(band.severity);
    }
    if (total <= 1) return brandRamp[3];

    // Spread across the ramp without ever landing on the palest shade for a
    // single-band chart, which would read as disabled rather than as data.
    final position = (index / (total - 1)) * (brandRamp.length - 1);
    return brandRamp[position.round().clamp(0, brandRamp.length - 1)];
  }

  /// Very light wash used behind insight strips and chart tracks.
  static Color tint(Color color, [double alpha = 0.10]) =>
      color.withValues(alpha: alpha);
}

/// The card container every analytics card sits in.
///
/// Kept here rather than in each card so radius, border, shadow and padding
/// cannot drift apart card by card.
class AnalyticsSurface extends StatelessWidget {
  const AnalyticsSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? AnalyticsTheme.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(AnalyticsTheme.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
