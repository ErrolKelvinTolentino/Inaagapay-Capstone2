// lib/services/weight_gain_engine.dart
// Maternal Weight Gain Monitoring Engine — adaptive evaluation.
//
// Implements two modes:
//   MODE A (FULL)  — when pre-pregnancy weight is available.
//   MODE B (TREND) — when only longitudinal checkup data exists.
//
// Based on IOM (Institute of Medicine) 2009 Guidelines for gestational
// weight gain by pre-pregnancy BMI category.


import '../models/weight_gain_models.dart';

class WeightGainEngine {
  // ═══════════════════════════════════════════════════════════════════════════
  // IOM 2009 GUIDELINES
  // ═══════════════════════════════════════════════════════════════════════════

  /// IOM 2009 recommended weight gain parameters by BMI category.
  /// All weight values are in kilograms.
  static const Map<String, Map<String, double>> iomGuidelines = {
    'Underweight': {
      'total_min': 12.5,
      'total_max': 18.0,
      'first_trimester': 2.0,
      'weekly_rate': 0.51,
      'weekly_min': 0.44,
      'weekly_max': 0.58,
    },
    'Normal': {
      'total_min': 11.5,
      'total_max': 16.0,
      'first_trimester': 1.6,
      'weekly_rate': 0.42,
      'weekly_min': 0.35,
      'weekly_max': 0.50,
    },
    'Overweight': {
      'total_min': 7.0,
      'total_max': 11.5,
      'first_trimester': 0.9,
      'weekly_rate': 0.28,
      'weekly_min': 0.23,
      'weekly_max': 0.33,
    },
    'Obese': {
      'total_min': 5.0,
      'total_max': 9.0,
      'first_trimester': 0.7,
      'weekly_rate': 0.22,
      'weekly_min': 0.17,
      'weekly_max': 0.27,
    },
  };

  /// IOM 2009 twin pregnancy guidelines by BMI category.
  /// Note: IOM does not provide ranges for underweight-twin;
  /// Normal-twin ranges are used as fallback.
  static const Map<String, Map<String, double>> iomTwinGuidelines = {
    'Underweight': {
      // No official IOM data for underweight twins; use Normal-twin as fallback
      'total_min': 16.8,
      'total_max': 24.5,
      'first_trimester': 2.0,
      'weekly_rate': 0.57,
      'weekly_min': 0.47,
      'weekly_max': 0.67,
    },
    'Normal': {
      'total_min': 16.8,
      'total_max': 24.5,
      'first_trimester': 2.0,
      'weekly_rate': 0.57,
      'weekly_min': 0.47,
      'weekly_max': 0.67,
    },
    'Overweight': {
      'total_min': 14.1,
      'total_max': 22.7,
      'first_trimester': 1.0,
      'weekly_rate': 0.54,
      'weekly_min': 0.41,
      'weekly_max': 0.60,
    },
    'Obese': {
      'total_min': 11.3,
      'total_max': 19.1,
      'first_trimester': 0.8,
      'weekly_rate': 0.46,
      'weekly_min': 0.33,
      'weekly_max': 0.53,
    },
  };

  /// Selects the appropriate guideline set based on fetal count.
  static Map<String, Map<String, double>> _guidelinesForFetalCount(int fetalCount) {
    return fetalCount >= 2 ? iomTwinGuidelines : iomGuidelines;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Main evaluation entry point.
  ///
  /// [currentWeight]       — weight at the current checkup (kg).
  /// [aogWeeks]            — age of gestation in weeks at the current checkup.
  /// [allCheckups]         — all prenatal checkups for this pregnancy, sorted
  ///                         by checkup_datetime ascending. Each map must
  ///                         contain 'checkup_weight', 'age_of_gestation',
  ///                         and 'checkup_datetime'.
  /// [prePregnancyWeight]  — optional pre-pregnancy weight (kg).
  /// [heightCm]            — maternal height in centimeters.
  /// [midwifeBmiCategory]  — optional manual BMI override from the midwife.
  /// [fetalCount]           — number of fetuses (default 1; ≥2 uses twin ranges).
  static WeightGainResult evaluate({
    required double currentWeight,
    required double aogWeeks,
    required List<Map<String, dynamic>> allCheckups,
    double? prePregnancyWeight,
    double? heightCm,
    String? midwifeBmiCategory,
    int fetalCount = 1,
  }) {
    // Determine BMI category using priority order
    final bmiCategory = _determineBmiCategory(
      prePregnancyWeight: prePregnancyWeight,
      currentWeight: currentWeight,
      heightCm: heightCm,
      midwifeBmiCategory: midwifeBmiCategory,
    );

    // IF PRE-PREGNANCY WEIGHT MISSING
    if (prePregnancyWeight == null) {
      final aogRound = aogWeeks.round();
      final msg = 'At approximately $aogRound weeks of pregnancy, weight changes may vary between mothers. Since pre-pregnancy weight was not available, personalized pregnancy weight gain analysis may be limited.';

      // Get baseline from earliest checkup if exists
      double? baselineWeight;
      double? baselineWeek;
      if (allCheckups.isNotEmpty) {
        final firstCheckup = allCheckups.first;
        baselineWeight = _toDouble(firstCheckup['checkup_weight']);
        baselineWeek = _toDouble(firstCheckup['age_of_gestation']);
      }

      // Calculate weekly gain if multiple checkups exist
      double? weeklyGain;
      if (allCheckups.length >= 2) {
        weeklyGain = _calculateLatestWeeklyGain(allCheckups);
      }

      return WeightGainResult(
        mode: WeightGainMode.trend,
        bmiCategory: bmiCategory,
        baselineWeight: baselineWeight,
        baselineWeek: baselineWeek,
        currentWeight: currentWeight,
        currentWeek: aogWeeks,
        status: WeightGainStatus.insufficient, // NO official weight gain interpretation
        confidence: WeightGainConfidence.low,
        message: msg,
        expectedGain: null,
        actualGain: baselineWeight != null ? currentWeight - baselineWeight : null,
        weeklyGain: weeklyGain,
        flags: const [],
      );
    }

    // MODE A: Full BMI-based evaluation
    return _evaluateFull(
      currentWeight: currentWeight,
      prePregnancyWeight: prePregnancyWeight,
      aogWeeks: aogWeeks,
      bmiCategory: bmiCategory,
      heightCm: heightCm,
      allCheckups: allCheckups,
      fetalCount: fetalCount,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE A — FULL BMI-BASED EVALUATION
  // ═══════════════════════════════════════════════════════════════════════════

  static WeightGainResult _evaluateFull({
    required double currentWeight,
    required double prePregnancyWeight,
    required double aogWeeks,
    required String bmiCategory,
    double? heightCm,
    required List<Map<String, dynamic>> allCheckups,
    required int fetalCount,
  }) {
    final activeGuidelines = _guidelinesForFetalCount(fetalCount);
    final guidelines = activeGuidelines[bmiCategory] ?? activeGuidelines['Normal']!;

    final firstTrimesterGain = guidelines['first_trimester']!;
    final weeklyRate = guidelines['weekly_rate']!;
    final totalMin = guidelines['total_min']!;
    final totalMax = guidelines['total_max']!;

    // Calculate expected gain at this gestational age
    double expectedGainMid;
    double expectedGainMin;
    double expectedGainMax;

    if (aogWeeks <= 13) {
      // First trimester (weeks 1-13): minimal or zero weight gain is normal
      final fraction = aogWeeks / 13.0;
      expectedGainMid = firstTrimesterGain * fraction;
      expectedGainMin = 0.0; // 0 kg gain in 1st trimester is normal
      expectedGainMax = (expectedGainMid * 1.4).clamp(1.0, firstTrimesterGain * 1.3);
    } else {
      // Second/third trimester
      final weeksAfterFirst = aogWeeks - 13;
      expectedGainMid = firstTrimesterGain + (weeksAfterFirst * weeklyRate);

      final firstTrimesterMin = firstTrimesterGain * 0.7;
      final firstTrimesterMax = firstTrimesterGain * 1.3;

      if (aogWeeks <= 40) {
        final progressFraction = (aogWeeks - 13) / 27.0;
        expectedGainMin = firstTrimesterMin + (totalMin - firstTrimesterMin) * progressFraction;
        expectedGainMax = firstTrimesterMax + (totalMax - firstTrimesterMax) * progressFraction;
      } else {
        // Post-term: extrapolate using weekly rate min/max
        final weeksAfterForty = aogWeeks - 40;
        final weeklyMin = guidelines['weekly_min'] ?? (weeklyRate * 0.8);
        final weeklyMax = guidelines['weekly_max'] ?? (weeklyRate * 1.2);
        expectedGainMin = totalMin + (weeksAfterForty * weeklyMin);
        expectedGainMax = totalMax + (weeksAfterForty * weeklyMax);
      }
    }

    final actualGain = currentWeight - prePregnancyWeight;

    // Classify status
    WeightGainStatus status;
    if (actualGain < expectedGainMin) {
      status = WeightGainStatus.low;
    } else if (actualGain > expectedGainMax) {
      status = WeightGainStatus.high;
    } else {
      status = WeightGainStatus.normal;
    }

    // Detect flags from checkup history
    final flags = _detectFlags(
      currentWeight: currentWeight,
      aogWeeks: aogWeeks,
      allCheckups: allCheckups,
      bmiCategory: bmiCategory,
      fetalCount: fetalCount,
    );

    // Escalate status if critical flags present
    // Weight loss between checkups is concerning — but it means the mother is
    // gaining LESS than expected, not MORE.  Escalate normal → low, never → high.
    if (flags.contains('weight_loss')) {
      if (status == WeightGainStatus.normal) {
        status = WeightGainStatus.low;
      }
      // If already low, keep it low — weight loss while underweight is still a
      // "below expected" concern, not "above expected".
    }

    // Confidence: HIGH if we have complete data
    final confidence = (heightCm != null && heightCm > 0)
        ? WeightGainConfidence.high
        : WeightGainConfidence.medium;

    // Build message
    final message = _buildFullMessage(
      status: status,
      actualGain: actualGain,
      expectedGainMin: expectedGainMin,
      expectedGainMax: expectedGainMax,
      bmiCategory: bmiCategory,
      aogWeeks: aogWeeks,
      flags: flags,
    );

    // Calculate weekly gain from most recent pair
    double? weeklyGain;
    if (allCheckups.length >= 2) {
      weeklyGain = _calculateLatestWeeklyGain(allCheckups);
    }

    return WeightGainResult(
      mode: WeightGainMode.full,
      bmiCategory: bmiCategory,
      baselineWeight: prePregnancyWeight,
      baselineWeek: 0,
      currentWeight: currentWeight,
      currentWeek: aogWeeks,
      expectedGain: expectedGainMid,
      expectedGainMin: expectedGainMin,
      expectedGainMax: expectedGainMax,
      actualGain: actualGain,
      weeklyGain: weeklyGain,
      status: status,
      confidence: confidence,
      message: message,
      flags: flags,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE B — TREND-BASED EVALUATION
  // ═══════════════════════════════════════════════════════════════════════════

  static WeightGainResult _evaluateTrend({
    required double currentWeight,
    required double aogWeeks,
    required List<Map<String, dynamic>> allCheckups,
    required String bmiCategory,
    double? heightCm,
    required int fetalCount,
  }) {
    // Need at least 2 checkups for trend analysis
    if (allCheckups.length < 2) {
      return WeightGainResult.insufficient(
        currentWeight: currentWeight,
        currentWeek: aogWeeks,
        bmiCategory: bmiCategory,
      );
    }

    // Use the two most recent checkups for weekly gain calculation
    final weeklyGain = _calculateLatestWeeklyGain(allCheckups);

    if (weeklyGain == null) {
      return WeightGainResult.insufficient(
        currentWeight: currentWeight,
        currentWeek: aogWeeks,
        bmiCategory: bmiCategory,
      );
    }

    final activeGuidelines = _guidelinesForFetalCount(fetalCount);
    final guidelines = activeGuidelines[bmiCategory] ?? activeGuidelines['Normal']!;
    final weeklyMin = guidelines['weekly_min']!;
    final weeklyMax = guidelines['weekly_max']!;

    // First trimester has different expectations
    final isFirstTrimester = aogWeeks <= 13;

    WeightGainStatus status;
    if (isFirstTrimester) {
      // In first trimester, weight gain is minimal and variable — wider tolerance
      if (weeklyGain < -0.1) {
        status = WeightGainStatus.low; // Losing weight in first trimester
      } else if (weeklyGain > weeklyMax * 1.5) {
        status = WeightGainStatus.high;
      } else {
        status = WeightGainStatus.normal;
      }
    } else {
      // Second/third trimester: use IOM weekly ranges
      if (weeklyGain < weeklyMin) {
        status = WeightGainStatus.low;
      } else if (weeklyGain > weeklyMax) {
        status = WeightGainStatus.high;
      } else {
        status = WeightGainStatus.normal;
      }
    }

    // Detect flags
    final flags = _detectFlags(
      currentWeight: currentWeight,
      aogWeeks: aogWeeks,
      allCheckups: allCheckups,
      bmiCategory: bmiCategory,
      fetalCount: fetalCount,
    );

    // Weight loss escalation: same logic as full mode — never flip low → high.
    if (flags.contains('weight_loss')) {
      if (status == WeightGainStatus.normal) {
        status = WeightGainStatus.low;
      }
    }

    // Determine confidence
    WeightGainConfidence confidence;
    if (heightCm != null && heightCm > 0 && allCheckups.length >= 3) {
      confidence = WeightGainConfidence.medium;
    } else {
      confidence = WeightGainConfidence.low;
    }

    // Late registration check: if AoG > 28 weeks and no pre-pregnancy weight
    final isLateRegistration = aogWeeks > 28;

    final message = _buildTrendMessage(
      status: status,
      weeklyGain: weeklyGain,
      weeklyMin: weeklyMin,
      weeklyMax: weeklyMax,
      bmiCategory: bmiCategory,
      aogWeeks: aogWeeks,
      isLateRegistration: isLateRegistration,
      flags: flags,
      isFirstTrimester: isFirstTrimester,
    );

    // Get baseline from earliest checkup
    final firstCheckup = allCheckups.first;
    final baselineWeight = _toDouble(firstCheckup['checkup_weight']);
    final baselineWeek = _toDouble(firstCheckup['age_of_gestation']);

    return WeightGainResult(
      mode: WeightGainMode.trend,
      bmiCategory: bmiCategory,
      baselineWeight: baselineWeight,
      baselineWeek: baselineWeek,
      currentWeight: currentWeight,
      currentWeek: aogWeeks,
      expectedGain: null, // Not available in trend mode
      actualGain: baselineWeight != null
          ? currentWeight - baselineWeight
          : null,
      weeklyGain: weeklyGain,
      status: status,
      confidence: confidence,
      message: message,
      flags: flags,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BMI CATEGORY DETERMINATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Determines BMI category using priority order:
  /// 1. Pre-pregnancy BMI (most accurate)
  /// 2. Current BMI estimate (less accurate during pregnancy)
  /// 3. Midwife manual input
  /// 4. Default safe range ("Normal")
  static String _determineBmiCategory({
    double? prePregnancyWeight,
    double? currentWeight,
    double? heightCm,
    String? midwifeBmiCategory,
  }) {
    // Priority 1: Pre-pregnancy BMI
    if (prePregnancyWeight != null && heightCm != null && heightCm > 0) {
      final heightM = heightCm / 100;
      final bmi = prePregnancyWeight / (heightM * heightM);
      return _bmiToCategory(bmi);
    }

    // Priority 2: Current BMI (estimated — less reliable during pregnancy)
    // During pregnancy, current weight includes gestational weight gain,
    // which can push the BMI category higher than the true pre-pregnancy category.
    if (currentWeight != null && heightCm != null && heightCm > 0) {
      final heightM = heightCm / 100;
      final bmi = currentWeight / (heightM * heightM);
      return _bmiToCategory(bmi);
    }

    // Priority 3: Midwife manual input
    if (midwifeBmiCategory != null && midwifeBmiCategory.isNotEmpty) {
      final normalized = midwifeBmiCategory.trim();
      if (iomGuidelines.containsKey(normalized)) return normalized;
    }

    // Priority 4: Default — use widest safe range
    return 'Normal';
  }

  /// Converts numeric BMI to category string.
  static String _bmiToCategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25.0) return 'Normal';
    if (bmi < 30.0) return 'Overweight';
    return 'Obese';
  }

  /// Public helper for UI — computes BMI from pre-pregnancy weight when
  /// available, falling back to current weight.
  static double? computePregnancyBMI({
    double? prePregnancyWeight,
    double? currentWeight,
    double? heightCm,
  }) {
    final weight = prePregnancyWeight ?? currentWeight;
    if (weight == null || heightCm == null || heightCm <= 0) return null;
    final heightM = heightCm / 100;
    return weight / (heightM * heightM);
  }

  /// Returns a label indicating the source of BMI calculation.
  static String bmiSourceLabel({
    double? prePregnancyWeight,
    double? currentWeight,
  }) {
    if (prePregnancyWeight != null) return 'Pre-Pregnancy BMI';
    if (currentWeight != null) return 'Estimated BMI (current weight)';
    return 'BMI Unavailable';
  }

  /// Estimates pre-pregnancy BMI using backtracking when the mother
  /// doesn't know her pre-pregnancy weight.
  ///
  /// Returns a map with: estimatedWeight, bmi, category, confidence,
  /// method, isEstimated, latePregnancyCaveat
  static Map<String, dynamic> estimatePrePregnancyBMI({
    required double currentWeightKg,
    required double heightCm,
    required int aogWeeks,
    double? knownPrePregnancyWeight,
    int fetalCount = 1,
  }) {
    final heightM = heightCm / 100.0;
    if (heightM <= 0) {
      return {
        'estimatedWeight': null,
        'bmi': null,
        'category': null,
        'confidence': 'low',
        'method': 'insufficient_data',
        'isEstimated': true,
        'latePregnancyCaveat': false,
      };
    }

    // CASE 1: Mother knows her pre-pregnancy weight
    if (knownPrePregnancyWeight != null && knownPrePregnancyWeight > 0) {
      final bmi = knownPrePregnancyWeight / (heightM * heightM);
      return {
        'estimatedWeight': knownPrePregnancyWeight,
        'bmi': double.parse(bmi.toStringAsFixed(1)),
        'category': _bmiToCategory(bmi),
        'confidence': 'high',
        'method': 'user_provided',
        'isEstimated': false,
        'latePregnancyCaveat': false,
      };
    }

    // CASE 2: AOG <= 13 weeks — current weight ≈ pre-pregnancy weight
    if (aogWeeks <= 13) {
      final bmi = currentWeightKg / (heightM * heightM);
      return {
        'estimatedWeight': currentWeightKg,
        'bmi': double.parse(bmi.toStringAsFixed(1)),
        'category': _bmiToCategory(bmi),
        'confidence': 'high',
        'method': 'early_pregnancy_proxy',
        'isEstimated': true,
        'latePregnancyCaveat': false,
      };
    }

    // CASE 3: AOG > 13 weeks — Backtracking algorithm
    final guidelines = fetalCount >= 2 ? iomTwinGuidelines : iomGuidelines;
    final weeksPast13 = aogWeeks - 13;
    final bool latePregnancy = aogWeeks > 28;

    // Try categories in order: Normal (most common), Overweight, Underweight, Obese
    final categoriesToTry = ['Normal', 'Overweight', 'Underweight', 'Obese'];

    for (final candidateCategory in categoriesToTry) {
      final g = guidelines[candidateCategory];
      if (g == null) continue;

      final firstTrimesterGain = (g['first_trimester'] as num).toDouble();
      final weeklyRate = (g['weekly_rate'] as num).toDouble();

      // Expected gain from conception to current AOG
      final expectedGain = firstTrimesterGain + (weeksPast13 * weeklyRate);

      // Candidate pre-pregnancy weight
      final candidatePreWeight = currentWeightKg - expectedGain;
      if (candidatePreWeight <= 0) continue; // nonsensical, skip

      // Candidate BMI
      final candidateBMI = candidatePreWeight / (heightM * heightM);
      final resultCategory = _bmiToCategory(candidateBMI);

      // Check self-consistency: does the BMI land in the category we guessed?
      if (resultCategory == candidateCategory) {
        return {
          'estimatedWeight': double.parse(candidatePreWeight.toStringAsFixed(1)),
          'bmi': double.parse(candidateBMI.toStringAsFixed(1)),
          'category': resultCategory,
          'confidence': latePregnancy ? 'low' : 'medium',
          'method': 'backtracked',
          'isEstimated': true,
          'latePregnancyCaveat': latePregnancy,
        };
      }
    }

    // Fallback: If no category is self-consistent (very rare),
    // use the Normal category's estimate as best guess
    final fallbackG = guidelines['Normal']!;
    final fallbackGain = (fallbackG['first_trimester'] as num).toDouble() +
        (weeksPast13 * (fallbackG['weekly_rate'] as num).toDouble());
    final fallbackWeight = currentWeightKg - fallbackGain;
    final fallbackBMI = fallbackWeight > 0
        ? fallbackWeight / (heightM * heightM)
        : currentWeightKg / (heightM * heightM);

    return {
      'estimatedWeight': double.parse((fallbackWeight > 0 ? fallbackWeight : currentWeightKg).toStringAsFixed(1)),
      'bmi': double.parse(fallbackBMI.toStringAsFixed(1)),
      'category': _bmiToCategory(fallbackBMI),
      'confidence': 'low',
      'method': 'backtracked_fallback',
      'isEstimated': true,
      'latePregnancyCaveat': latePregnancy,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLAG DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  static List<String> _detectFlags({
    required double currentWeight,
    required double aogWeeks,
    required List<Map<String, dynamic>> allCheckups,
    required String bmiCategory,
    required int fetalCount,
  }) {
    final flags = <String>[];

    if (allCheckups.length < 2) return flags;

    // Sort by date ascending
    final sorted = List<Map<String, dynamic>>.from(allCheckups);
    sorted.sort((a, b) {
      final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '');
      final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '');
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

    // Compare two most recent checkups
    final previous = sorted[sorted.length - 2];
    final prevWeight = _toDouble(previous['checkup_weight']);
    final prevWeek = _toDouble(previous['age_of_gestation']);

    if (prevWeight == null || prevWeek == null) return flags;

    final weightDiff = currentWeight - prevWeight;
    final weekDiff = aogWeeks - prevWeek;
    if (weekDiff <= 0) return flags;

    final weeklyGain = weightDiff / weekDiff;
    final activeGuidelines = _guidelinesForFetalCount(fetalCount);
    final guidelines = activeGuidelines[bmiCategory] ?? activeGuidelines['Normal']!;
    final weeklyMax = guidelines['weekly_max']!;

    // Scenario 7: Weight loss (clinically significant: > 0.5 kg)
    // Mild fluctuation (-0.1 to -0.5 kg) is within measurement variability
    if (weightDiff < -0.5) {
      flags.add('weight_loss');
    }

    // Scenario 6: Plateau (no meaningful weight change, post first trimester)
    // Require at least 3 weeks gap for reliability
    if (aogWeeks > 13 && weightDiff.abs() < 0.2 && weekDiff >= 3) {
      flags.add('plateau');
    }

    // Scenario 5: Sudden weight spike (≥ 2× upper bound of weekly rate)
    if (weeklyGain > weeklyMax * 2) {
      flags.add('abnormal_spike');
    }

    return flags;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WEEKLY GAIN CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════

  static double? _calculateLatestWeeklyGain(
      List<Map<String, dynamic>> allCheckups) {
    if (allCheckups.length < 2) return null;

    // Sort ascending by date
    final sorted = List<Map<String, dynamic>>.from(allCheckups);
    sorted.sort((a, b) {
      final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '');
      final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '');
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

    final current = sorted.last;
    final previous = sorted[sorted.length - 2];

    final curWeight = _toDouble(current['checkup_weight']);
    final prevWeight = _toDouble(previous['checkup_weight']);
    final curWeek = _toDouble(current['age_of_gestation']);
    final prevWeek = _toDouble(previous['age_of_gestation']);

    if (curWeight == null ||
        prevWeight == null ||
        curWeek == null ||
        prevWeek == null) {
      return null;
    }

    final weekDiff = curWeek - prevWeek;
    if (weekDiff <= 0) return null;

    return (curWeight - prevWeight) / weekDiff;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MESSAGE BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  static String _buildFullMessage({
    required WeightGainStatus status,
    required double actualGain,
    required double expectedGainMin,
    required double expectedGainMax,
    required String bmiCategory,
    required double aogWeeks,
    required List<String> flags,
  }) {
    final buf = StringBuffer();

    buf.write('Full BMI-Based Evaluation at Week ${aogWeeks.toStringAsFixed(1)}. ');
    buf.write('BMI category: $bmiCategory. ');
    buf.write('Total weight gain: ${actualGain.toStringAsFixed(1)} kg. ');
    buf.write(
        'Expected range: ${expectedGainMin.toStringAsFixed(1)}-${expectedGainMax.toStringAsFixed(1)} kg. ');

    switch (status) {
      case WeightGainStatus.normal:
        buf.write('Weight gain is within the recommended IOM 2009 range.');
        break;
      case WeightGainStatus.low:
        buf.write(
            'Weight gain is BELOW the recommended range. Monitor nutrition intake and discuss with the mother.');
        break;
      case WeightGainStatus.high:
        if (flags.contains('weight_loss')) {
          buf.write(
              'ATTENTION: Weight loss detected. Clinical evaluation recommended to rule out hyperemesis, inadequate nutrition, or other complications.');
        } else {
          buf.write(
              'Weight gain EXCEEDS the recommended range. Assess dietary intake and screen for gestational diabetes, fluid retention, or preeclampsia.');
        }
        break;
      case WeightGainStatus.insufficient:
        buf.write('Insufficient data for full evaluation.');
        break;
    }

    if (flags.contains('abnormal_spike')) {
      buf.write(
          ' ALERT: Sudden weight spike detected — rule out fluid retention or edema.');
    }
    if (flags.contains('plateau')) {
      buf.write(
          ' NOTE: Weight plateau detected — monitor for possible fetal growth restriction.');
    }

    return buf.toString();
  }

  static String _buildTrendMessage({
    required WeightGainStatus status,
    required double weeklyGain,
    required double weeklyMin,
    required double weeklyMax,
    required String bmiCategory,
    required double aogWeeks,
    required bool isLateRegistration,
    required List<String> flags,
    required bool isFirstTrimester,
  }) {
    final buf = StringBuffer();

    buf.write(
        'Trend-Based Evaluation at Week ${aogWeeks.toStringAsFixed(1)}. ');
    if (isLateRegistration) {
      buf.write('Late registration — total gain estimation not available. ');
    }
    buf.write('BMI category: $bmiCategory (estimated from current weight). ');
    buf.write(
        'Weekly gain rate: ${weeklyGain.toStringAsFixed(3)} kg/week. ');

    if (isFirstTrimester) {
      buf.write('First trimester — variable weight gain is expected. ');
    } else {
      buf.write(
          'Expected weekly range: ${weeklyMin.toStringAsFixed(2)}-${weeklyMax.toStringAsFixed(2)} kg/week. ');
    }

    switch (status) {
      case WeightGainStatus.normal:
        buf.write('Weight gain pace is within the expected range.');
        break;
      case WeightGainStatus.low:
        buf.write(
            'Weight gain pace is BELOW the expected range. Monitor nutrition and fetal growth.');
        break;
      case WeightGainStatus.high:
        if (flags.contains('weight_loss')) {
          buf.write(
              'HIGH RISK: Weight loss detected between checkups. Requires clinical attention.');
        } else {
          buf.write(
              'Weight gain pace EXCEEDS the expected range. Assess for excessive fluid retention or dietary factors.');
        }
        break;
      case WeightGainStatus.insufficient:
        buf.write('Insufficient data for trend evaluation.');
        break;
    }

    if (flags.contains('abnormal_spike')) {
      buf.write(
          ' ALERT: Rapid weight gain detected — possible fluid retention.');
    }
    if (flags.contains('plateau')) {
      buf.write(
          ' NOTE: No significant weight change detected — assess fetal well-being.');
    }

    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
