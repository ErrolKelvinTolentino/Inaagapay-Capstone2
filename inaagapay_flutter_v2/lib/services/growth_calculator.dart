// lib/services/growth_calculator.dart

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'growth_reference_data.dart';

/// Where a measurement sits against the WHO Child Growth Standards.
enum GrowthBand {
  below,
  within,
  above;

  /// Label shown to midwives and mothers. Kept here so every screen renders the
  /// same words for the same z-score.
  String get label => switch (this) {
        GrowthBand.below => 'Below standard range',
        GrowthBand.within => 'Within standard range',
        GrowthBand.above => 'Above standard range',
      };

  String get labelFilipino => switch (this) {
        GrowthBand.below => 'Mababa sa pamantayan',
        GrowthBand.within => 'Nasa loob ng pamantayan',
        GrowthBand.above => 'Mataas sa pamantayan',
      };

  bool get isWithin => this == GrowthBand.within;
}

class GrowthCalculator {
  /// WHO reference cut-off, in standard deviations.
  ///
  /// ±2 SD is the WHO threshold: -2 SD marks wasting/thinness and +2 SD marks
  /// overweight in under-fives. A tighter ±1 SD would flag roughly a third of
  /// perfectly healthy children, since that is simply how a normal
  /// distribution is shaped.
  static const double whoStandardSd = 2.0;

  /// The single source of truth for classifying a growth z-score.
  ///
  /// Every screen that shows a growth status pill must go through this, so the
  /// same child cannot read "within range" on one page and "above range" on
  /// another.
  static GrowthBand bandForZScore(double? zScore) {
    if (zScore == null || zScore.isNaN || zScore.isInfinite) {
      return GrowthBand.within;
    }
    if (zScore < -whoStandardSd) return GrowthBand.below;
    if (zScore > whoStandardSd) return GrowthBand.above;
    return GrowthBand.within;
  }

  /// Convenience wrapper returning the display label directly.
  static String bandLabel(double? zScore) => bandForZScore(zScore).label;

  // Weight data for girls (WHO standards) - Weeks 0-13
  static final List<Map<String, dynamic>> _weightGirlsData = [
    {
      'week': 0,
      'l': 0.3809,
      'm': 3.2322,
      's': 0.14171,
      'sd3neg': 2.0,
      'sd2neg': 2.4,
      'sd1neg': 2.8,
      'sd0': 3.2,
      'sd1': 3.7,
      'sd2': 4.2,
      'sd3': 4.8
    },
    {
      'week': 1,
      'l': 0.2671,
      'm': 3.3388,
      's': 0.1460,
      'sd3neg': 2.1,
      'sd2neg': 2.5,
      'sd1neg': 2.9,
      'sd0': 3.3,
      'sd1': 3.9,
      'sd2': 4.4,
      'sd3': 5.1
    },
    {
      'week': 2,
      'l': 0.2304,
      'm': 3.5693,
      's': 0.14339,
      'sd3neg': 2.3,
      'sd2neg': 2.7,
      'sd1neg': 3.1,
      'sd0': 3.6,
      'sd1': 4.1,
      'sd2': 4.7,
      'sd3': 5.4
    },
    {
      'week': 3,
      'l': 0.2024,
      'm': 3.8352,
      's': 0.1406,
      'sd3neg': 2.5,
      'sd2neg': 2.9,
      'sd1neg': 3.3,
      'sd0': 3.8,
      'sd1': 4.4,
      'sd2': 5.0,
      'sd3': 5.7
    },
    {
      'week': 4,
      'l': 0.1789,
      'm': 4.0987,
      's': 0.13805,
      'sd3neg': 2.7,
      'sd2neg': 3.1,
      'sd1neg': 3.6,
      'sd0': 4.1,
      'sd1': 4.7,
      'sd2': 5.4,
      'sd3': 6.1
    },
    {
      'week': 5,
      'l': 0.1582,
      'm': 4.3476,
      's': 0.13583,
      'sd3neg': 2.9,
      'sd2neg': 3.3,
      'sd1neg': 3.8,
      'sd0': 4.3,
      'sd1': 5.0,
      'sd2': 5.7,
      'sd3': 6.5
    },
    {
      'week': 6,
      'l': 0.1395,
      'm': 4.5793,
      's': 0.13392,
      'sd3neg': 3.0,
      'sd2neg': 3.5,
      'sd1neg': 4.0,
      'sd0': 4.6,
      'sd1': 5.2,
      'sd2': 6.0,
      'sd3': 6.8
    },
    {
      'week': 7,
      'l': 0.1224,
      'm': 4.7950,
      's': 0.13228,
      'sd3neg': 3.2,
      'sd2neg': 3.7,
      'sd1neg': 4.2,
      'sd0': 4.8,
      'sd1': 5.5,
      'sd2': 6.2,
      'sd3': 7.1
    },
    {
      'week': 8,
      'l': 0.1065,
      'm': 4.9959,
      's': 0.13087,
      'sd3neg': 3.3,
      'sd2neg': 3.8,
      'sd1neg': 4.4,
      'sd0': 5.0,
      'sd1': 5.7,
      'sd2': 6.5,
      'sd3': 7.3
    },
    {
      'week': 9,
      'l': 0.0918,
      'm': 5.1842,
      's': 0.12966,
      'sd3neg': 3.5,
      'sd2neg': 4.0,
      'sd1neg': 4.6,
      'sd0': 5.2,
      'sd1': 5.9,
      'sd2': 6.7,
      'sd3': 7.6
    },
    {
      'week': 10,
      'l': 0.0779,
      'm': 5.3618,
      's': 0.12861,
      'sd3neg': 3.6,
      'sd2neg': 4.1,
      'sd1neg': 4.7,
      'sd0': 5.4,
      'sd1': 6.1,
      'sd2': 6.9,
      'sd3': 7.8
    },
    {
      'week': 11,
      'l': 0.0648,
      'm': 5.5295,
      's': 0.1277,
      'sd3neg': 3.8,
      'sd2neg': 4.3,
      'sd1neg': 4.9,
      'sd0': 5.5,
      'sd1': 6.3,
      'sd2': 7.1,
      'sd3': 8.1
    },
    {
      'week': 12,
      'l': 0.0525,
      'm': 5.6883,
      's': 0.12691,
      'sd3neg': 3.9,
      'sd2neg': 4.4,
      'sd1neg': 5.0,
      'sd0': 5.7,
      'sd1': 6.5,
      'sd2': 7.3,
      'sd3': 8.3
    },
    {
      'week': 13,
      'l': 0.0407,
      'm': 5.8393,
      's': 0.12622,
      'sd3neg': 4.0,
      'sd2neg': 4.5,
      'sd1neg': 5.1,
      'sd0': 5.8,
      'sd1': 6.6,
      'sd2': 7.5,
      'sd3': 8.5
    },
  ];

  // Weight data for boys (WHO standards) - Weeks 0-13
  static final List<Map<String, dynamic>> _weightBoysData = [
    {
      'week': 0,
      'l': 0.3487,
      'm': 3.3464,
      's': 0.14602,
      'sd3neg': 2.1,
      'sd2neg': 2.5,
      'sd1neg': 2.9,
      'sd0': 3.3,
      'sd1': 3.9,
      'sd2': 4.4,
      'sd3': 5.0
    },
    {
      'week': 1,
      'l': 0.2776,
      'm': 3.4879,
      's': 0.14483,
      'sd3neg': 2.2,
      'sd2neg': 2.6,
      'sd1neg': 3.0,
      'sd0': 3.5,
      'sd1': 4.0,
      'sd2': 4.6,
      'sd3': 5.3
    },
    {
      'week': 2,
      'l': 0.2581,
      'm': 3.7529,
      's': 0.14142,
      'sd3neg': 2.4,
      'sd2neg': 2.8,
      'sd1neg': 3.2,
      'sd0': 3.8,
      'sd1': 4.3,
      'sd2': 4.9,
      'sd3': 5.6
    },
    {
      'week': 3,
      'l': 0.2442,
      'm': 4.0603,
      's': 0.13807,
      'sd3neg': 2.6,
      'sd2neg': 3.1,
      'sd1neg': 3.5,
      'sd0': 4.1,
      'sd1': 4.7,
      'sd2': 5.3,
      'sd3': 6.0
    },
    {
      'week': 4,
      'l': 0.2331,
      'm': 4.3671,
      's': 0.13497,
      'sd3neg': 2.9,
      'sd2neg': 3.3,
      'sd1neg': 3.8,
      'sd0': 4.4,
      'sd1': 5.0,
      'sd2': 5.7,
      'sd3': 6.4
    },
    {
      'week': 5,
      'l': 0.2237,
      'm': 4.6590,
      's': 0.13215,
      'sd3neg': 3.1,
      'sd2neg': 3.5,
      'sd1neg': 4.1,
      'sd0': 4.7,
      'sd1': 5.3,
      'sd2': 6.0,
      'sd3': 6.8
    },
    {
      'week': 6,
      'l': 0.2155,
      'm': 4.9303,
      's': 0.1296,
      'sd3neg': 3.3,
      'sd2neg': 3.8,
      'sd1neg': 4.3,
      'sd0': 4.9,
      'sd1': 5.6,
      'sd2': 6.3,
      'sd3': 7.2
    },
    {
      'week': 7,
      'l': 0.2081,
      'm': 5.1817,
      's': 0.12729,
      'sd3neg': 3.5,
      'sd2neg': 4.0,
      'sd1neg': 4.6,
      'sd0': 5.2,
      'sd1': 5.9,
      'sd2': 6.6,
      'sd3': 7.5
    },
    {
      'week': 8,
      'l': 0.2014,
      'm': 5.4149,
      's': 0.1252,
      'sd3neg': 3.7,
      'sd2neg': 4.2,
      'sd1neg': 4.8,
      'sd0': 5.4,
      'sd1': 6.1,
      'sd2': 6.9,
      'sd3': 7.8
    },
    {
      'week': 9,
      'l': 0.1952,
      'm': 5.6319,
      's': 0.1233,
      'sd3neg': 3.8,
      'sd2neg': 4.4,
      'sd1neg': 5.0,
      'sd0': 5.6,
      'sd1': 6.4,
      'sd2': 7.2,
      'sd3': 8.0
    },
    {
      'week': 10,
      'l': 0.1894,
      'm': 5.8346,
      's': 0.12157,
      'sd3neg': 4.0,
      'sd2neg': 4.5,
      'sd1neg': 5.2,
      'sd0': 5.8,
      'sd1': 6.6,
      'sd2': 7.4,
      'sd3': 8.3
    },
    {
      'week': 11,
      'l': 0.1840,
      'm': 6.0242,
      's': 0.12001,
      'sd3neg': 4.2,
      'sd2neg': 4.7,
      'sd1neg': 5.3,
      'sd0': 6.0,
      'sd1': 6.8,
      'sd2': 7.6,
      'sd3': 8.5
    },
    {
      'week': 12,
      'l': 0.1789,
      'm': 6.2019,
      's': 0.1186,
      'sd3neg': 4.3,
      'sd2neg': 4.9,
      'sd1neg': 5.5,
      'sd0': 6.2,
      'sd1': 7.0,
      'sd2': 7.8,
      'sd3': 8.8
    },
    {
      'week': 13,
      'l': 0.1740,
      'm': 6.3690,
      's': 0.11732,
      'sd3neg': 4.4,
      'sd2neg': 5.0,
      'sd1neg': 5.7,
      'sd0': 6.4,
      'sd1': 7.2,
      'sd2': 8.0,
      'sd3': 8.8
    },
  ];

  // Height data for girls (WHO standards) - Weeks 0-13
  static final List<Map<String, dynamic>> _heightGirlsData = [
    {
      'week': 0,
      'l': 1.0,
      'm': 49.1477,
      's': 0.0379,
      'sd3neg': 43.6,
      'sd2neg': 45.4,
      'sd1neg': 47.3,
      'sd0': 49.1,
      'sd1': 51.0,
      'sd2': 52.9,
      'sd3': 54.7
    },
    {
      'week': 1,
      'l': 1.0,
      'm': 50.3298,
      's': 0.03742,
      'sd3neg': 44.7,
      'sd2neg': 46.6,
      'sd1neg': 48.4,
      'sd0': 50.3,
      'sd1': 52.2,
      'sd2': 54.1,
      'sd3': 56.0
    },
    {
      'week': 2,
      'l': 1.0,
      'm': 51.5120,
      's': 0.03694,
      'sd3neg': 45.8,
      'sd2neg': 47.7,
      'sd1neg': 49.6,
      'sd0': 51.5,
      'sd1': 53.4,
      'sd2': 55.3,
      'sd3': 57.2
    },
    {
      'week': 3,
      'l': 1.0,
      'm': 52.4695,
      's': 0.03669,
      'sd3neg': 46.7,
      'sd2neg': 48.6,
      'sd1neg': 50.5,
      'sd0': 52.5,
      'sd1': 54.4,
      'sd2': 56.3,
      'sd3': 58.2
    },
    {
      'week': 4,
      'l': 1.0,
      'm': 53.3809,
      's': 0.03647,
      'sd3neg': 47.5,
      'sd2neg': 49.5,
      'sd1neg': 51.4,
      'sd0': 53.4,
      'sd1': 55.3,
      'sd2': 57.3,
      'sd3': 59.2
    },
    {
      'week': 5,
      'l': 1.0,
      'm': 54.2454,
      's': 0.03627,
      'sd3neg': 48.3,
      'sd2neg': 50.3,
      'sd1neg': 52.3,
      'sd0': 54.2,
      'sd1': 56.2,
      'sd2': 58.2,
      'sd3': 60.1
    },
    {
      'week': 6,
      'l': 1.0,
      'm': 55.0642,
      's': 0.03609,
      'sd3neg': 49.1,
      'sd2neg': 51.1,
      'sd1neg': 53.1,
      'sd0': 55.1,
      'sd1': 57.1,
      'sd2': 59.0,
      'sd3': 61.0
    },
    {
      'week': 7,
      'l': 1.0,
      'm': 55.8406,
      's': 0.03593,
      'sd3neg': 49.8,
      'sd2neg': 51.8,
      'sd1neg': 53.8,
      'sd0': 55.8,
      'sd1': 57.8,
      'sd2': 59.9,
      'sd3': 61.9
    },
    {
      'week': 8,
      'l': 1.0,
      'm': 56.5767,
      's': 0.03578,
      'sd3neg': 50.5,
      'sd2neg': 52.5,
      'sd1neg': 54.6,
      'sd0': 56.6,
      'sd1': 58.6,
      'sd2': 60.6,
      'sd3': 62.6
    },
    {
      'week': 9,
      'l': 1.0,
      'm': 57.2761,
      's': 0.03564,
      'sd3neg': 51.2,
      'sd2neg': 53.2,
      'sd1neg': 55.2,
      'sd0': 57.3,
      'sd1': 59.3,
      'sd2': 61.4,
      'sd3': 63.4
    },
    {
      'week': 10,
      'l': 1.0,
      'm': 57.9436,
      's': 0.03552,
      'sd3neg': 51.8,
      'sd2neg': 53.8,
      'sd1neg': 55.9,
      'sd0': 57.9,
      'sd1': 60.0,
      'sd2': 62.1,
      'sd3': 64.1
    },
    {
      'week': 11,
      'l': 1.0,
      'm': 58.5816,
      's': 0.0354,
      'sd3neg': 52.4,
      'sd2neg': 54.4,
      'sd1neg': 56.5,
      'sd0': 58.6,
      'sd1': 60.7,
      'sd2': 62.7,
      'sd3': 64.8
    },
    {
      'week': 12,
      'l': 1.0,
      'm': 59.1922,
      's': 0.0353,
      'sd3neg': 52.9,
      'sd2neg': 55.0,
      'sd1neg': 57.1,
      'sd0': 59.2,
      'sd1': 61.3,
      'sd2': 63.4,
      'sd3': 65.5
    },
    {
      'week': 13,
      'l': 1.0,
      'm': 59.7773,
      's': 0.0352,
      'sd3neg': 53.5,
      'sd2neg': 55.6,
      'sd1neg': 57.7,
      'sd0': 59.8,
      'sd1': 61.9,
      'sd2': 64.0,
      'sd3': 66.1
    },
  ];

  // Height data for boys (WHO standards) - Weeks 0-13
  static final List<Map<String, dynamic>> _heightBoysData = [
    {
      'week': 0,
      'l': 1.0,
      'm': 49.8842,
      's': 0.03795,
      'sd3neg': 44.2,
      'sd2neg': 46.1,
      'sd1neg': 48.0,
      'sd0': 49.9,
      'sd1': 51.8,
      'sd2': 53.7,
      'sd3': 55.6
    },
    {
      'week': 1,
      'l': 1.0,
      'm': 51.1152,
      's': 0.03723,
      'sd3neg': 45.4,
      'sd2neg': 47.3,
      'sd1neg': 49.2,
      'sd0': 51.1,
      'sd1': 53.0,
      'sd2': 54.9,
      'sd3': 56.8
    },
    {
      'week': 2,
      'l': 1.0,
      'm': 52.3461,
      's': 0.03652,
      'sd3neg': 46.6,
      'sd2neg': 48.5,
      'sd1neg': 50.4,
      'sd0': 52.3,
      'sd1': 54.3,
      'sd2': 56.2,
      'sd3': 58.1
    },
    {
      'week': 3,
      'l': 1.0,
      'm': 53.3905,
      's': 0.03609,
      'sd3neg': 47.6,
      'sd2neg': 49.5,
      'sd1neg': 51.5,
      'sd0': 53.4,
      'sd1': 55.3,
      'sd2': 57.2,
      'sd3': 59.2
    },
    {
      'week': 4,
      'l': 1.0,
      'm': 54.3881,
      's': 0.0357,
      'sd3neg': 48.6,
      'sd2neg': 50.5,
      'sd1neg': 52.4,
      'sd0': 54.4,
      'sd1': 56.3,
      'sd2': 58.3,
      'sd3': 60.2
    },
    {
      'week': 5,
      'l': 1.0,
      'm': 55.3374,
      's': 0.03534,
      'sd3neg': 49.5,
      'sd2neg': 51.4,
      'sd1neg': 53.4,
      'sd0': 55.3,
      'sd1': 57.3,
      'sd2': 59.2,
      'sd3': 61.2
    },
    {
      'week': 6,
      'l': 1.0,
      'm': 56.2357,
      's': 0.03501,
      'sd3neg': 50.3,
      'sd2neg': 52.3,
      'sd1neg': 54.3,
      'sd0': 56.2,
      'sd1': 58.2,
      'sd2': 60.2,
      'sd3': 62.1
    },
    {
      'week': 7,
      'l': 1.0,
      'm': 57.0851,
      's': 0.0347,
      'sd3neg': 51.1,
      'sd2neg': 53.1,
      'sd1neg': 55.1,
      'sd0': 57.1,
      'sd1': 59.1,
      'sd2': 61.0,
      'sd3': 63.0
    },
    {
      'week': 8,
      'l': 1.0,
      'm': 57.8889,
      's': 0.03442,
      'sd3neg': 51.9,
      'sd2neg': 53.9,
      'sd1neg': 55.9,
      'sd0': 57.9,
      'sd1': 59.9,
      'sd2': 61.9,
      'sd3': 63.9
    },
    {
      'week': 9,
      'l': 1.0,
      'm': 58.6536,
      's': 0.03416,
      'sd3neg': 52.6,
      'sd2neg': 54.6,
      'sd1neg': 56.6,
      'sd0': 58.7,
      'sd1': 60.7,
      'sd2': 62.7,
      'sd3': 64.7
    },
    {
      'week': 10,
      'l': 1.0,
      'm': 59.3872,
      's': 0.03392,
      'sd3neg': 53.3,
      'sd2neg': 55.4,
      'sd1neg': 57.4,
      'sd0': 59.4,
      'sd1': 61.4,
      'sd2': 63.4,
      'sd3': 65.4
    },
    {
      'week': 11,
      'l': 1.0,
      'm': 60.0894,
      's': 0.03369,
      'sd3neg': 54.0,
      'sd2neg': 56.0,
      'sd1neg': 58.1,
      'sd0': 60.1,
      'sd1': 62.1,
      'sd2': 64.1,
      'sd3': 66.2
    },
    {
      'week': 12,
      'l': 1.0,
      'm': 60.7605,
      's': 0.03348,
      'sd3neg': 54.7,
      'sd2neg': 56.7,
      'sd1neg': 58.7,
      'sd0': 60.8,
      'sd1': 62.8,
      'sd2': 64.8,
      'sd3': 66.9
    },
    {
      'week': 13,
      'l': 1.0,
      'm': 61.4013,
      's': 0.03329,
      'sd3neg': 55.3,
      'sd2neg': 57.3,
      'sd1neg': 59.4,
      'sd0': 61.4,
      'sd1': 63.4,
      'sd2': 65.5,
      'sd3': 67.5
    },
  ];

  // BMI data for girls (WHO standards) - Weeks 0-13
  static final List<Map<String, dynamic>> _bmiGirlsData = [
    {
      'week': 0,
      'l': -0.0631,
      'm': 13.3363,
      's': 0.09272,
      'sd3neg': 10.1,
      'sd2neg': 11.1,
      'sd1neg': 12.2,
      'sd0': 13.3,
      'sd1': 14.6,
      'sd2': 16.1,
      'sd3': 17.7
    },
    {
      'week': 1,
      'l': 0.6319,
      'm': 13.2113,
      's': 0.09887,
      'sd3neg': 9.5,
      'sd2neg': 10.7,
      'sd1neg': 11.9,
      'sd0': 13.2,
      'sd1': 14.5,
      'sd2': 15.9,
      'sd3': 17.3
    },
    {
      'week': 2,
      'l': 0.5082,
      'm': 13.4501,
      's': 0.09741,
      'sd3neg': 9.8,
      'sd2neg': 11.0,
      'sd1neg': 12.2,
      'sd0': 13.5,
      'sd1': 14.8,
      'sd2': 16.2,
      'sd3': 17.7
    },
    {
      'week': 3,
      'l': 0.4263,
      'm': 13.9505,
      's': 0.09647,
      'sd3neg': 10.2,
      'sd2neg': 11.4,
      'sd1neg': 12.6,
      'sd0': 14.0,
      'sd1': 15.3,
      'sd2': 16.8,
      'sd3': 18.3
    },
    {
      'week': 4,
      'l': 0.3637,
      'm': 14.4208,
      's': 0.09577,
      'sd3neg': 10.6,
      'sd2neg': 11.8,
      'sd1neg': 13.1,
      'sd0': 14.4,
      'sd1': 15.8,
      'sd2': 17.4,
      'sd3': 19.0
    },
    {
      'week': 5,
      'l': 0.3124,
      'm': 14.8157,
      's': 0.0952,
      'sd3neg': 11.0,
      'sd2neg': 12.2,
      'sd1neg': 13.5,
      'sd0': 14.8,
      'sd1': 16.3,
      'sd2': 17.8,
      'sd3': 19.5
    },
    {
      'week': 6,
      'l': 0.2688,
      'm': 15.1380,
      's': 0.09472,
      'sd3neg': 11.3,
      'sd2neg': 12.5,
      'sd1neg': 13.8,
      'sd0': 15.1,
      'sd1': 16.6,
      'sd2': 18.2,
      'sd3': 19.9
    },
    {
      'week': 7,
      'l': 0.2306,
      'm': 15.4063,
      's': 0.09431,
      'sd3neg': 11.5,
      'sd2neg': 12.7,
      'sd1neg': 14.0,
      'sd0': 15.4,
      'sd1': 16.9,
      'sd2': 18.5,
      'sd3': 20.3
    },
    {
      'week': 8,
      'l': 0.1966,
      'm': 15.6311,
      's': 0.09394,
      'sd3neg': 11.7,
      'sd2neg': 12.9,
      'sd1neg': 14.2,
      'sd0': 15.6,
      'sd1': 17.2,
      'sd2': 18.8,
      'sd3': 20.6
    },
    {
      'week': 9,
      'l': 0.1658,
      'm': 15.8232,
      's': 0.09361,
      'sd3neg': 11.9,
      'sd2neg': 13.1,
      'sd1neg': 14.4,
      'sd0': 15.8,
      'sd1': 17.4,
      'sd2': 19.0,
      'sd3': 20.8
    },
    {
      'week': 10,
      'l': 0.1377,
      'm': 15.9874,
      's': 0.09332,
      'sd3neg': 12.0,
      'sd2neg': 13.2,
      'sd1neg': 14.6,
      'sd0': 16.0,
      'sd1': 17.5,
      'sd2': 19.2,
      'sd3': 21.0
    },
    {
      'week': 11,
      'l': 0.1118,
      'm': 16.1277,
      's': 0.09304,
      'sd3neg': 12.1,
      'sd2neg': 13.4,
      'sd1neg': 14.7,
      'sd0': 16.1,
      'sd1': 17.7,
      'sd2': 19.4,
      'sd3': 21.2
    },
    {
      'week': 12,
      'l': 0.0877,
      'm': 16.2485,
      's': 0.09279,
      'sd3neg': 12.3,
      'sd2neg': 13.5,
      'sd1neg': 14.8,
      'sd0': 16.2,
      'sd1': 17.8,
      'sd2': 19.5,
      'sd3': 21.4
    },
    {
      'week': 13,
      'l': 0.0652,
      'm': 16.3531,
      's': 0.09255,
      'sd3neg': 12.4,
      'sd2neg': 13.6,
      'sd1neg': 14.9,
      'sd0': 16.4,
      'sd1': 17.9,
      'sd2': 19.7,
      'sd3': 21.5
    },
  ];

  // BMI data for boys (WHO standards) - Weeks 0-13
  static final List<Map<String, dynamic>> _bmiBoysData = [
    {
      'week': 0,
      'l': -0.0631,
      'm': 13.3363,
      's': 0.09272,
      'sd3neg': 10.1,
      'sd2neg': 11.1,
      'sd1neg': 12.2,
      'sd0': 13.3,
      'sd1': 14.6,
      'sd2': 16.1,
      'sd3': 17.7
    },
    {
      'week': 1,
      'l': 0.6319,
      'm': 13.2113,
      's': 0.09887,
      'sd3neg': 9.5,
      'sd2neg': 10.7,
      'sd1neg': 11.9,
      'sd0': 13.2,
      'sd1': 14.5,
      'sd2': 15.9,
      'sd3': 17.3
    },
    {
      'week': 2,
      'l': 0.5082,
      'm': 13.4501,
      's': 0.09741,
      'sd3neg': 9.8,
      'sd2neg': 11.0,
      'sd1neg': 12.2,
      'sd0': 13.5,
      'sd1': 14.8,
      'sd2': 16.2,
      'sd3': 17.7
    },
    {
      'week': 3,
      'l': 0.4263,
      'm': 13.9505,
      's': 0.09647,
      'sd3neg': 10.2,
      'sd2neg': 11.4,
      'sd1neg': 12.6,
      'sd0': 14.0,
      'sd1': 15.3,
      'sd2': 16.8,
      'sd3': 18.3
    },
    {
      'week': 4,
      'l': 0.3637,
      'm': 14.4208,
      's': 0.09577,
      'sd3neg': 10.6,
      'sd2neg': 11.8,
      'sd1neg': 13.1,
      'sd0': 14.4,
      'sd1': 15.8,
      'sd2': 17.4,
      'sd3': 19.0
    },
    {
      'week': 5,
      'l': 0.3124,
      'm': 14.8157,
      's': 0.0952,
      'sd3neg': 11.0,
      'sd2neg': 12.2,
      'sd1neg': 13.5,
      'sd0': 14.8,
      'sd1': 16.3,
      'sd2': 17.8,
      'sd3': 19.5
    },
    {
      'week': 6,
      'l': 0.2688,
      'm': 15.1380,
      's': 0.09472,
      'sd3neg': 11.3,
      'sd2neg': 12.5,
      'sd1neg': 13.8,
      'sd0': 15.1,
      'sd1': 16.6,
      'sd2': 18.2,
      'sd3': 19.9
    },
    {
      'week': 7,
      'l': 0.2306,
      'm': 15.4063,
      's': 0.09431,
      'sd3neg': 11.5,
      'sd2neg': 12.7,
      'sd1neg': 14.0,
      'sd0': 15.4,
      'sd1': 16.9,
      'sd2': 18.5,
      'sd3': 20.3
    },
    {
      'week': 8,
      'l': 0.1966,
      'm': 15.6311,
      's': 0.09394,
      'sd3neg': 11.7,
      'sd2neg': 12.9,
      'sd1neg': 14.2,
      'sd0': 15.6,
      'sd1': 17.2,
      'sd2': 18.8,
      'sd3': 20.6
    },
    {
      'week': 9,
      'l': 0.1658,
      'm': 15.8232,
      's': 0.09361,
      'sd3neg': 11.9,
      'sd2neg': 13.1,
      'sd1neg': 14.4,
      'sd0': 15.8,
      'sd1': 17.4,
      'sd2': 19.0,
      'sd3': 20.8
    },
    {
      'week': 10,
      'l': 0.1377,
      'm': 15.9874,
      's': 0.09332,
      'sd3neg': 12.0,
      'sd2neg': 13.2,
      'sd1neg': 14.6,
      'sd0': 16.0,
      'sd1': 17.5,
      'sd2': 19.2,
      'sd3': 21.0
    },
    {
      'week': 11,
      'l': 0.1118,
      'm': 16.1277,
      's': 0.09304,
      'sd3neg': 12.1,
      'sd2neg': 13.4,
      'sd1neg': 14.7,
      'sd0': 16.1,
      'sd1': 17.7,
      'sd2': 19.4,
      'sd3': 21.2
    },
    {
      'week': 12,
      'l': 0.0877,
      'm': 16.2485,
      's': 0.09279,
      'sd3neg': 12.3,
      'sd2neg': 13.5,
      'sd1neg': 14.8,
      'sd0': 16.2,
      'sd1': 17.8,
      'sd2': 19.5,
      'sd3': 21.4
    },
    {
      'week': 13,
      'l': 0.0652,
      'm': 16.3531,
      's': 0.09255,
      'sd3neg': 12.4,
      'sd2neg': 13.6,
      'sd1neg': 14.9,
      'sd0': 16.4,
      'sd1': 17.9,
      'sd2': 19.7,
      'sd3': 21.5
    },
  ];

  // Get weight data for specific week (handles weeks beyond data range)
  static Map<String, dynamic>? getWeightData(int week, String gender) {
    final dataList =
        gender.toLowerCase() == 'female' ? _weightGirlsData : _weightBoysData;

    if (week < 0 || week > 13) {
      if (kDebugMode) {
        debugPrint(
            'Week $week is outside the supported reference range 0-13 weeks for weight. No reference data returned.');
      }
      return null;
    }

    try {
      return dataList.firstWhere((item) => item['week'] == week);
    } catch (e) {
      debugPrint('No weight data found for week $week, gender $gender');
      return null;
    }
  }

  // Get height data for specific week (handles weeks beyond data range)
  static Map<String, dynamic>? getHeightData(int week, String gender) {
    final dataList =
        gender.toLowerCase() == 'female' ? _heightGirlsData : _heightBoysData;

    if (week < 0 || week > 13) {
      if (kDebugMode) {
        debugPrint(
            'Week $week is outside the supported reference range 0-13 weeks for height. No reference data returned.');
      }
      return null;
    }

    try {
      return dataList.firstWhere((item) => item['week'] == week);
    } catch (e) {
      debugPrint('No height data found for week $week, gender $gender');
      return null;
    }
  }

  // Get BMI data for specific week (handles weeks beyond data range)
  static Map<String, dynamic>? getBMIData(int week, String gender) {
    final dataList =
        gender.toLowerCase() == 'female' ? _bmiGirlsData : _bmiBoysData;

    if (week < 0 || week > 13) {
      if (kDebugMode) {
        debugPrint(
            'Week $week is outside the supported reference range 0-13 weeks for BMI. No reference data returned.');
      }
      return null;
    }

    try {
      return dataList.firstWhere((item) => item['week'] == week);
    } catch (e) {
      debugPrint('No BMI data found for week $week, gender $gender');
      return null;
    }
  }

  static const Map<int, List<double>> _boysHeightKeyPoints = {
    0: [44.2, 46.1, 48.0, 49.9, 51.8, 53.7, 55.6],
    3: [55.3, 57.3, 59.4, 61.4, 63.4, 65.5, 67.5],
    6: [61.2, 63.3, 65.5, 67.6, 69.8, 71.9, 74.0],
    9: [65.2, 67.5, 69.7, 72.0, 74.2, 76.5, 78.7],
    12: [68.6, 71.0, 73.4, 75.7, 78.1, 80.5, 82.9],
    18: [75.0, 77.4, 79.9, 82.3, 84.8, 87.3, 89.8],
    24: [81.0, 83.2, 85.5, 87.8, 90.1, 92.4, 94.7],
    36: [88.7, 91.2, 93.6, 96.1, 98.6, 101.1, 103.5],
    48: [95.4, 98.0, 100.7, 103.3, 106.0, 108.6, 111.3],
    60: [101.6, 104.4, 107.2, 110.0, 112.8, 115.6, 118.4],
  };

  static const Map<int, List<double>> _girlsHeightKeyPoints = {
    0: [43.6, 45.4, 47.3, 49.1, 51.0, 52.9, 54.7],
    3: [53.5, 55.6, 57.7, 59.8, 61.9, 64.0, 66.1],
    6: [59.3, 61.4, 63.5, 65.7, 67.8, 69.9, 72.0],
    9: [63.2, 65.5, 67.8, 70.1, 72.4, 74.7, 77.0],
    12: [66.5, 68.9, 71.4, 74.0, 76.5, 79.0, 81.5],
    18: [72.8, 75.4, 78.0, 80.7, 83.3, 86.0, 88.6],
    24: [79.3, 81.7, 84.1, 86.4, 88.7, 91.1, 93.5],
    36: [87.4, 89.9, 92.5, 95.1, 97.7, 100.3, 102.9],
    48: [94.1, 97.0, 99.8, 102.7, 105.5, 108.4, 111.2],
    60: [100.7, 103.6, 106.5, 109.4, 112.3, 115.2, 118.1],
  };

  static const Map<int, List<double>> _boysBmiKeyPoints = {
    0: [10.1, 11.1, 12.2, 13.3, 14.6, 16.1, 17.7],
    3: [12.2, 13.3, 14.6, 16.0, 17.5, 19.2, 21.0],
    6: [13.1, 14.3, 15.5, 16.9, 18.4, 20.0, 21.8],
    9: [13.1, 14.2, 15.4, 16.8, 18.3, 19.9, 21.7],
    12: [12.9, 14.0, 15.2, 16.5, 18.0, 19.6, 21.4],
    18: [12.5, 13.5, 14.7, 16.0, 17.4, 19.0, 20.8],
    24: [12.1, 13.1, 14.2, 15.4, 16.8, 18.3, 20.0],
    36: [11.8, 12.7, 13.7, 14.9, 16.2, 17.7, 19.4],
    48: [11.5, 12.4, 13.3, 14.4, 15.7, 17.2, 18.9],
    60: [11.2, 12.1, 13.0, 14.1, 15.3, 16.8, 18.5],
  };

  static const Map<int, List<double>> _girlsBmiKeyPoints = {
    0: [10.1, 11.1, 12.2, 13.3, 14.6, 16.1, 17.7],
    3: [12.0, 13.2, 14.4, 15.8, 17.3, 18.9, 20.7],
    6: [12.7, 13.9, 15.1, 16.5, 18.0, 19.6, 21.4],
    9: [12.7, 13.8, 15.0, 16.4, 17.9, 19.5, 21.3],
    12: [12.4, 13.5, 14.7, 16.0, 17.5, 19.1, 20.9],
    18: [12.0, 13.0, 14.1, 15.4, 16.8, 18.4, 20.2],
    24: [11.6, 12.6, 13.7, 14.9, 16.3, 17.8, 19.6],
    36: [11.3, 12.2, 13.2, 14.4, 15.7, 17.2, 19.0],
    48: [11.0, 11.8, 12.8, 13.9, 15.2, 16.7, 18.4],
    60: [10.7, 11.5, 12.5, 13.6, 14.8, 16.3, 18.0],
  };

  static Map<String, dynamic> _getInterpolatedSDBoundaries(int month, String metric, String gender) {
    final isBoy = gender.toLowerCase() != 'female';
    
    // Select the key points
    final Map<int, List<double>> keyPoints;
    if (metric == 'height') {
      keyPoints = isBoy ? _boysHeightKeyPoints : _girlsHeightKeyPoints;
    } else {
      keyPoints = isBoy ? _boysBmiKeyPoints : _girlsBmiKeyPoints;
    }

    if (month <= 0) {
      return _listToMap(month, keyPoints[0]!);
    }
    if (month >= 60) {
      return _listToMap(month, keyPoints[60]!);
    }

    // Find the lower and upper key months
    final sortedKeys = keyPoints.keys.toList()..sort();
    int lowerKey = 0;
    int upperKey = 60;
    for (int i = 0; i < sortedKeys.length - 1; i++) {
      if (month >= sortedKeys[i] && month <= sortedKeys[i + 1]) {
        lowerKey = sortedKeys[i];
        upperKey = sortedKeys[i + 1];
        break;
      }
    }

    final lowerVals = keyPoints[lowerKey]!;
    final upperVals = keyPoints[upperKey]!;
    final t = (month - lowerKey) / (upperKey - lowerKey);

    final interpolated = List<double>.generate(7, (idx) {
      return lowerVals[idx] + t * (upperVals[idx] - lowerVals[idx]);
    });

    return _listToMap(month, interpolated);
  }

  static Map<String, dynamic> _listToMap(int month, List<double> vals) {
    return {
      'month': month,
      'sd3neg': vals[0],
      'sd2neg': vals[1],
      'sd1neg': vals[2],
      'sd0': vals[3],
      'sd1': vals[4],
      'sd2': vals[5],
      'sd3': vals[6],
    };
  }

  static double _calculateZScoreFromSDBoundaries(double value, Map<String, dynamic> entry) {
    final sd3neg = (entry['sd3neg'] as num).toDouble();
    final sd2neg = (entry['sd2neg'] as num).toDouble();
    final sd1neg = (entry['sd1neg'] as num).toDouble();
    final sd0 = (entry['sd0'] as num).toDouble();
    final sd1 = (entry['sd1'] as num).toDouble();
    final sd2 = (entry['sd2'] as num).toDouble();
    final sd3 = (entry['sd3'] as num).toDouble();

    if (value < sd0) {
      if (value >= sd1neg) {
        return -1.0 + (value - sd1neg) / (sd0 - sd1neg);
      } else if (value >= sd2neg) {
        return -2.0 + (value - sd2neg) / (sd1neg - sd2neg);
      } else if (value >= sd3neg) {
        return -3.0 + (value - sd3neg) / (sd2neg - sd3neg);
      } else {
        return -3.0 - (sd3neg - value) / (sd2neg - sd3neg);
      }
    } else {
      if (value <= sd1) {
        return (value - sd0) / (sd1 - sd0);
      } else if (value <= sd2) {
        return 1.0 + (value - sd1) / (sd2 - sd1);
      } else if (value <= sd3) {
        return 2.0 + (value - sd2) / (sd3 - sd2);
      } else {
        return 3.0 + (value - sd3) / (sd3 - sd2);
      }
    }
  }

  /// BMI-for-age boundaries at a given week, as the inverse of the z-score
  /// calculation: what BMI values sit at -2 SD and +2 SD for this age and sex.
  ///
  /// Used to plot the WHO reference band behind a child's BMI trend, the same
  /// way the maternal chart plots its IOM bounds.
  ///
  /// Returns null when there is no reference data for the requested week.
  static Map<String, double>? bmiStandardRangeAt(
    int week,
    String gender, {
    double sd = 2.0,
  }) {
    if (week <= 13) {
      final data = getBMIData(week, gender);
      if (data == null) return null;

      final l = data['l'] as double;
      final m = data['m'] as double;
      final s = data['s'] as double;

      // Inverse Box-Cox (LMS): value = M * (1 + L*S*z)^(1/L), or M*exp(S*z)
      // when L is zero.
      double valueAt(double z) {
        if (l == 0) return m * math.exp(s * z);
        final base = 1 + l * s * z;
        if (base <= 0) return double.nan;
        return m * math.pow(base, 1 / l).toDouble();
      }

      final min = valueAt(-sd);
      final max = valueAt(sd);
      if (min.isNaN || max.isNaN) return null;
      return {'min': min, 'max': max};
    }

    // Monthly reference data uses tabulated SD boundaries rather than LMS.
    final month = (week / 4.345).round();
    try {
      final entry = _getInterpolatedSDBoundaries(month, 'bmi', gender);
      return {
        'min': (entry['sd2neg'] as num).toDouble(),
        'max': (entry['sd2'] as num).toDouble(),
      };
    } catch (e) {
      debugPrint('bmiStandardRangeAt note: $e');
      return null;
    }
  }

  // Calculate Z-score for weight using LMS method (weekly) or SD interpolation (monthly)
  static double? calculateWeightZScore(double weight, int week, String gender) {
    if (week <= 13) {
      final data = getWeightData(week, gender);
      if (data == null) {
        if (kDebugMode) {
          debugPrint(
              '⚠️ Cannot calculate weight Z-score for week $week, gender $gender without reference data.');
        }
        return null;
      }

      final l = data['l'] as double;
      final m = data['m'] as double;
      final s = data['s'] as double;

      if (l == 0) {
        return (math.log(weight / m)) / s;
      } else {
        return (math.pow(weight / m, l) - 1) / (l * s);
      }
    } else {
      // Monthly reference data (weeks > 13)
      final month = (week / 4.345).round();
      final monthlyList = gender.toLowerCase() == 'female'
          ? GrowthReferenceData.weightGirlsMonthlyData
          : GrowthReferenceData.weightBoysMonthlyData;
      
      try {
        final entry = monthlyList.firstWhere(
          (e) => e['month'] == month,
          orElse: () => monthlyList.last, // Fallback to last month if > 60 months
        );
        return _calculateZScoreFromSDBoundaries(weight, entry);
      } catch (e) {
        debugPrint('❌ Error calculating weight monthly Z-score: $e');
        return null;
      }
    }
  }

  // Calculate Z-score for height using LMS method (weekly) or SD interpolation (monthly)
  static double? calculateHeightZScore(double height, int week, String gender) {
    if (week <= 13) {
      final data = getHeightData(week, gender);
      if (data == null) {
        if (kDebugMode) {
          debugPrint(
              '⚠️ Cannot calculate height Z-score for week $week, gender $gender without reference data.');
        }
        return null;
      }

      final l = data['l'] as double;
      final m = data['m'] as double;
      final s = data['s'] as double;

      if (l == 0) {
        return (math.log(height / m)) / s;
      } else {
        return (math.pow(height / m, l) - 1) / (l * s);
      }
    } else {
      // Monthly reference data (weeks > 13)
      final month = (week / 4.345).round();
      try {
        final entry = _getInterpolatedSDBoundaries(month, 'height', gender);
        return _calculateZScoreFromSDBoundaries(height, entry);
      } catch (e) {
        debugPrint('❌ Error calculating height monthly Z-score: $e');
        return null;
      }
    }
  }

  // Calculate Z-score for BMI using LMS method (weekly) or SD interpolation (monthly)
  static double? calculateBMIZScore(double bmi, int week, String gender) {
    if (week <= 13) {
      final data = getBMIData(week, gender);
      if (data == null) {
        debugPrint('⚠️ No BMI data for week $week, gender $gender');
        return null;
      }

      final l = data['l'] as double;
      final m = data['m'] as double;
      final s = data['s'] as double;

      debugPrint(
          '📊 BMI Reference Data: L=$l, M=$m, S=$s, Week=$week, Gender=$gender');
      debugPrint('📊 Input BMI: $bmi');

      double zScore;
      try {
        if (l == 0) {
          zScore = (math.log(bmi / m)) / s;
        } else {
          final powValue = math.pow(bmi / m, l);
          zScore = (powValue - 1) / (l * s);
        }
        debugPrint('📊 Calculated Z-Score: $zScore');
        return zScore;
      } catch (e) {
        debugPrint('❌ Error calculating BMI Z-score: $e');
        return null;
      }
    } else {
      // Monthly reference data (weeks > 13)
      final month = (week / 4.345).round();
      try {
        final entry = _getInterpolatedSDBoundaries(month, 'bmi', gender);
        final zScore = _calculateZScoreFromSDBoundaries(bmi, entry);
        debugPrint('📊 Calculated Monthly BMI Z-Score: $zScore');
        return zScore;
      } catch (e) {
        debugPrint('❌ Error calculating monthly BMI Z-score: $e');
        return null;
      }
    }
  }
}
