// lib/services/lab_cbc_interpretation_engine.dart
//
// Trimester-aware CBC interpretation engine for pregnancy monitoring.
//
// Clinical References:
//   [1] WHO. Haemoglobin concentrations for the diagnosis of anaemia
//       and assessment of severity. Geneva: World Health Organization; 2011.
//       https://www.who.int/publications/i/item/WHO-NMH-NHD-MNM-11.1
//
//   [2] Abbassi-Ghanavati M, Greer LG, Cunningham FG.
//       Pregnancy and Laboratory Studies: A Reference Table for Clinicians.
//       Obstetrics & Gynecology. 2009;114(6):1326–1331.
//       https://doi.org/10.1097/AOG.0b013e3181c2bde8
//
// IMPORTANT: This engine provides contextual monitoring interpretations ONLY.
// It does NOT diagnose conditions. All phrasing is deliberately interpretive.

import 'ultrasound_interpretation_engine.dart'
    show MonitoringClassification, Trimester;

/// Classification tier for a single CBC component value.
enum CbcComponentStatus {
  expected,  // Within the commonly expected range
  monitor,   // Slightly outside range, continued monitoring suggested
  review,    // Significantly outside range, clinical review recommended
}

/// A single reference range for a CBC component in a given trimester.
class CbcReferenceRange {
  final String componentName;
  final String unit;
  final double low;
  final double high;
  final Trimester trimester;

  const CbcReferenceRange({
    required this.componentName,
    required this.unit,
    required this.low,
    required this.high,
    required this.trimester,
  });
}

/// Result of interpreting a single CBC component value.
class CbcComponentResult {
  final String componentName;
  final String unit;
  final double value;
  final double referenceLow;
  final double referenceHigh;
  final Trimester trimester;
  final CbcComponentStatus status;
  final String contextPhrase;

  const CbcComponentResult({
    required this.componentName,
    required this.unit,
    required this.value,
    required this.referenceLow,
    required this.referenceHigh,
    required this.trimester,
    required this.status,
    required this.contextPhrase,
  });
}

class LabCbcInterpretationEngine {
  // ── Clinical Citation Strings ─────────────────────────────────────────────

  static const String citation1Title = 'WHO Haemoglobin Standards';
  static const String citation1Authors = 'World Health Organization.';
  static const String citation1Full =
      'Haemoglobin concentrations for the diagnosis of anaemia and assessment '
      'of severity. Geneva: WHO; 2011.';
  static const String citation1Url =
      'https://www.who.int/publications/i/item/WHO-NMH-NHD-MNM-11.1';

  static const String citation2Title =
      'Pregnancy Laboratory Reference Table';
  static const String citation2Authors = 'Abbassi-Ghanavati M, et al.';
  static const String citation2Full =
      'Pregnancy and Laboratory Studies: A Reference Table for Clinicians. '
      'Obstet Gynecol. 2009;114(6):1326–1331.';
  static const String citation2Url =
      'https://doi.org/10.1097/AOG.0b013e3181c2bde8';

  // ── Trimester Determination ───────────────────────────────────────────────

  static Trimester getTrimester(int aogWeeks) {
    if (aogWeeks <= 13) return Trimester.first;
    if (aogWeeks <= 27) return Trimester.second;
    return Trimester.third;
  }

  static int calculateAogWeeks(DateTime lmp, DateTime referenceDate) {
    final diff = referenceDate.difference(lmp).inDays;
    return (diff / 7).floor();
  }

  static String getTrimesterLabel(Trimester trimester) {
    switch (trimester) {
      case Trimester.first:
        return '1st Trimester';
      case Trimester.second:
        return '2nd Trimester';
      case Trimester.third:
        return '3rd Trimester';
    }
  }

  // ── Reference Ranges ──────────────────────────────────────────────────────
  //
  // Sources:
  //   Hemoglobin anemia thresholds: WHO 2011
  //   Trimester-adjusted CBC ranges: Abbassi-Ghanavati et al., 2009
  //
  // Note: These ranges represent the 2.5th–97.5th percentile ranges
  // from the Abbassi-Ghanavati reference table.

  static const Map<String, Map<Trimester, List<double>>> _referenceRanges = {
    'Hemoglobin': {
      Trimester.first: [11.6, 13.9],
      Trimester.second: [9.7, 14.8],
      Trimester.third: [9.5, 15.0],
    },
    'Hematocrit': {
      Trimester.first: [31.0, 41.0],
      Trimester.second: [30.0, 39.0],
      Trimester.third: [28.0, 40.0],
    },
    'WBC': {
      Trimester.first: [5.7, 13.6],
      Trimester.second: [5.6, 14.8],
      Trimester.third: [5.9, 16.9],
    },
    'Platelets': {
      Trimester.first: [174.0, 391.0],
      Trimester.second: [155.0, 409.0],
      Trimester.third: [146.0, 429.0],
    },
    'RBC': {
      Trimester.first: [3.42, 4.55],
      Trimester.second: [2.81, 4.49],
      Trimester.third: [2.71, 4.43],
    },
    'MCV': {
      Trimester.first: [81.0, 96.0],
      Trimester.second: [82.0, 97.0],
      Trimester.third: [81.0, 99.0],
    },
    'MCH': {
      Trimester.first: [26.0, 32.0],
      Trimester.second: [26.0, 32.0],
      Trimester.third: [26.0, 32.0],
    },
    'MCHC': {
      Trimester.first: [31.0, 36.0],
      Trimester.second: [30.0, 36.0],
      Trimester.third: [30.0, 36.0],
    },
  };

  static const Map<String, String> _componentUnits = {
    'Hemoglobin': 'g/dL',
    'Hematocrit': '%',
    'WBC': '×10³/μL',
    'Platelets': '×10³/μL',
    'RBC': '×10⁶/μL',
    'MCV': 'fL',
    'MCH': 'pg',
    'MCHC': 'g/dL',
  };

  /// Returns the list of CBC components that we have reference ranges for.
  static List<String> get supportedComponents => _referenceRanges.keys.toList();

  /// Get the reference range for a specific component and trimester.
  static CbcReferenceRange? getReferenceRange(
      String componentName, Trimester trimester) {
    final normalized = _normalizeComponentName(componentName);
    final ranges = _referenceRanges[normalized];
    if (ranges == null) return null;
    final trimesterRange = ranges[trimester];
    if (trimesterRange == null) return null;
    return CbcReferenceRange(
      componentName: normalized,
      unit: _componentUnits[normalized] ?? '',
      low: trimesterRange[0],
      high: trimesterRange[1],
      trimester: trimester,
    );
  }

  // ── WHO Anemia Severity (Pregnancy) ───────────────────────────────────────
  //
  // WHO 2011 thresholds for pregnant women:
  //   No anemia:  Hb ≥ 11.0 g/dL
  //   Mild:       Hb 10.0–10.9 g/dL
  //   Moderate:   Hb 7.0–9.9 g/dL
  //   Severe:     Hb < 7.0 g/dL

  static String? getWhoAnemiaSeverity(double hemoglobinGdL) {
    if (hemoglobinGdL >= 11.0) return null; // No anemia
    if (hemoglobinGdL >= 10.0) return 'mild';
    if (hemoglobinGdL >= 7.0) return 'moderate';
    return 'severe';
  }

  static String getWhoAnemiaPhrase(double hemoglobinGdL) {
    final severity = getWhoAnemiaSeverity(hemoglobinGdL);
    if (severity == null) {
      return 'The recorded hemoglobin level meets the WHO threshold for '
          'non-anemic status during pregnancy (≥ 11.0 g/dL).';
    }
    switch (severity) {
      case 'mild':
        return 'The recorded hemoglobin level falls slightly below the WHO '
            'threshold (11.0 g/dL) for pregnancy and may be associated with '
            'mild anemia. Continued monitoring and nutritional support may '
            'be beneficial.';
      case 'moderate':
        return 'The recorded hemoglobin level falls below the WHO threshold '
            'and may be associated with moderate anemia during pregnancy. '
            'Healthcare consultation for further evaluation is recommended.';
      case 'severe':
        return 'The recorded hemoglobin level is significantly below the WHO '
            'threshold and may be associated with severe anemia during '
            'pregnancy. Prompt clinical evaluation is strongly recommended.';
      default:
        return '';
    }
  }

  // ── Single Component Interpretation ───────────────────────────────────────

  /// Normalizes raw lab value based on magnitude and OCR string content.
  static double normalizeValue(String componentName, double rawValue, String valueStr) {
    final normalized = _normalizeComponentName(componentName);
    final rawUnit = valueStr.toLowerCase();
    double value = rawValue;

    switch (normalized) {
      case 'Hemoglobin':
        if (rawUnit.contains('g/l') || value > 40.0) {
          value = value / 10.0;
        }
        break;
      case 'Hematocrit':
        if (value > 0.0 && value < 1.0) {
          value = value * 100.0;
        }
        break;
      case 'WBC':
        if (rawUnit.contains('cumm') || rawUnit.contains('ul') || rawUnit.contains('µl') || value > 100.0) {
          value = value / 1000.0;
        }
        break;
      case 'Platelets':
        if (rawUnit.contains('cumm') || rawUnit.contains('ul') || rawUnit.contains('µl') || value > 1000.0) {
          value = value / 1000.0;
        }
        break;
      case 'RBC':
        if (value > 1000000.0) {
          value = value / 1000000.0;
        } else if (value > 100000.0) {
          value = value / 100000.0;
        }
        break;
      case 'MCHC':
        if (rawUnit.contains('g/l') || value > 100.0) {
          value = value / 10.0;
        }
        break;
    }
    return value;
  }

  static CbcComponentResult? interpretComponent({
    required String componentName,
    required double value,
    required Trimester trimester,
    String? valueStr,
  }) {
    final normalized = _normalizeComponentName(componentName);
    final ref = getReferenceRange(normalized, trimester);
    if (ref == null) {
      // Component not in our supported CBC reference list — skip it entirely
      return null;
    }

    final double normalizedValue = normalizeValue(normalized, value, valueStr ?? '');
    final status = _classifyValue(normalizedValue, ref.low, ref.high);
    final phrase = _buildContextPhrase(
      componentName: normalized,
      value: normalizedValue,
      unit: ref.unit,
      low: ref.low,
      high: ref.high,
      trimester: trimester,
      status: status,
    );

    return CbcComponentResult(
      componentName: normalized,
      unit: ref.unit,
      value: normalizedValue,
      referenceLow: ref.low,
      referenceHigh: ref.high,
      trimester: trimester,
      status: status,
      contextPhrase: phrase,
    );
  }

  // ── Batch Interpretation ──────────────────────────────────────────────────

  /// Interprets a map of { componentName: value } for a given trimester.
  /// Only includes components that have reference ranges in our table.
  static List<CbcComponentResult> interpretAll({
    required Map<String, double> values,
    Map<String, String>? valueStrs,
    required Trimester trimester,
  }) {
    final results = <CbcComponentResult>[];
    for (final entry in values.entries) {
      final valueStr = valueStrs?[entry.key];
      final result = interpretComponent(
        componentName: entry.key,
        value: entry.value,
        valueStr: valueStr,
        trimester: trimester,
      );
      if (result != null) {
        results.add(result);
      }
    }
    return results;
  }

  // ── Overall Monitoring Classification ─────────────────────────────────────

  /// Classifies the overall monitoring status from a list of component results.
  static MonitoringClassification classifyOverall(
      List<CbcComponentResult> results) {
    int highPriorityMonitorCount = 0;
    int lowPriorityMonitorCount = 0;
    int highPriorityReviewCount = 0;
    int lowPriorityReviewCount = 0;

    final highPriorityNames = {'Hemoglobin', 'Hematocrit', 'WBC', 'Platelets'};

    for (final result in results) {
      final isHighPriority = highPriorityNames.contains(result.componentName);
      
      switch (result.status) {
        case CbcComponentStatus.review:
          if (isHighPriority) {
            highPriorityReviewCount++;
          } else {
            lowPriorityReviewCount++;
          }
          break;
        case CbcComponentStatus.monitor:
          if (isHighPriority) {
            highPriorityMonitorCount++;
          } else {
            lowPriorityMonitorCount++;
          }
          break;
        case CbcComponentStatus.expected:
          break;
      }
    }

    // 1. Clinically notable deviations -> Clinical Follow-Up Recommended
    // Co-existing multiple reviews OR single high-priority review (severe anemia or platelet drop, etc.)
    if (highPriorityReviewCount >= 1 || (lowPriorityReviewCount + highPriorityReviewCount) >= 2) {
      return MonitoringClassification.followUpRecommended;
    }

    // 2. 2+ mild findings (monitor status) -> Monitoring Recommended
    final totalMonitorCount = highPriorityMonitorCount + lowPriorityMonitorCount;
    if (totalMonitorCount >= 2 || lowPriorityReviewCount == 1) {
      return MonitoringClassification.requiresCloserMonitoring;
    }

    // 3. Isolated high-priority mild deviation -> Monitoring Recommended
    if (totalMonitorCount == 1 && highPriorityMonitorCount == 1) {
      return MonitoringClassification.requiresCloserMonitoring;
    }

    // Default: reassuring or isolated low-priority mild deviation (e.g. isolated mild MCV/MCHC)
    return MonitoringClassification.withinExpectedRange;
  }

  /// Custom decoupled labels specifically for CBC laboratory interpretation.
  static String classificationLabel(
      MonitoringClassification classification, {String language = 'english'}) {
    final bool fil = language == 'filipino';
    switch (classification) {
      case MonitoringClassification.withinExpectedRange:
        return fil
            ? 'Nasa Inaasahang Saklaw ng Pagsubaybay'
            : 'Within Expected Monitoring Range';
      case MonitoringClassification.requiresCloserMonitoring:
        return fil
            ? 'Inirerekomenda ang Pagsubaybay'
            : 'Monitoring Recommended';
      case MonitoringClassification.followUpRecommended:
        return fil
            ? 'Inirerekomenda ang Clinical Follow-Up'
            : 'Clinical Follow-Up Recommended';
    }
  }

  /// Returns a safety or data-quality warning if the results are insufficient.
  static String? getSufficiencyWarning({
    required List<CbcComponentResult> results,
    required Trimester? trimester,
    required double? confidenceScore,
  }) {
    if (confidenceScore != null && confidenceScore < 0.6) {
      return 'Some laboratory values may require manual verification due to incomplete or unclear record formatting.';
    }

    final presentComponents = results.map((r) => r.componentName).toSet();
    if (presentComponents.isNotEmpty && !presentComponents.contains('Hemoglobin')) {
      return 'Critical pregnancy monitoring values (like Hemoglobin) were not detected. Please verify the report manually.';
    }

    return null;
  }

  /// UI label for a component status badge.
  static String statusLabel(CbcComponentStatus status) {
    switch (status) {
      case CbcComponentStatus.expected:
        return 'EXPECTED';
      case CbcComponentStatus.monitor:
        return 'MONITOR';
      case CbcComponentStatus.review:
        return 'REVIEW';
    }
  }

  // ── Internal Helpers ──────────────────────────────────────────────────────

  /// Normalizes common aliases for CBC component names.
  static String _normalizeComponentName(String name) {
    final upper = name.toUpperCase().trim();
    // Hemoglobin aliases
    if (upper == 'HB' ||
        upper == 'HGB' ||
        upper == 'HEMOGLOBIN' ||
        upper == 'HAEMOGLOBIN') {
      return 'Hemoglobin';
    }
    // Hematocrit aliases
    if (upper == 'HCT' || upper == 'HEMATOCRIT' || upper == 'HAEMATOCRIT') {
      return 'Hematocrit';
    }
    // WBC aliases
    if (upper == 'WBC' ||
        upper == 'WHITE BLOOD CELL COUNT' ||
        upper == 'WHITE BLOOD CELLS' ||
        upper == 'TOTAL LEUCOCYTE COUNT' ||
        upper == 'TOTAL LEUKOCYTE COUNT' ||
        upper == 'LEUCOCYTE COUNT' ||
        upper == 'LEUKOCYTE COUNT') {
      return 'WBC';
    }
    // Platelet aliases
    if (upper == 'PLT' ||
        upper == 'PLATELETS' ||
        upper == 'PLATELET COUNT') {
      return 'Platelets';
    }
    // RBC aliases
    if (upper == 'RBC' ||
        upper == 'RED BLOOD CELL COUNT' ||
        upper == 'RED BLOOD CELLS' ||
        upper == 'ERYTHROCYTE COUNT') {
      return 'RBC';
    }
    // MCV aliases
    if (upper == 'MCV' || upper == 'MEAN CORPUSCULAR VOLUME') {
      return 'MCV';
    }
    // MCH aliases
    if (upper == 'MCH' || upper == 'MEAN CORPUSCULAR HEMOGLOBIN') {
      return 'MCH';
    }
    // MCHC aliases
    if (upper == 'MCHC' ||
        upper == 'MEAN CORPUSCULAR HEMOGLOBIN CONCENTRATION') {
      return 'MCHC';
    }
    // Return original casing if unrecognized
    return name.trim();
  }

  /// Classifies a numeric value against reference range boundaries.
  /// A 10% margin outside the range boundary classifies as MONITOR;
  /// beyond that is REVIEW.
  static CbcComponentStatus _classifyValue(
      double value, double low, double high) {
    if (value >= low && value <= high) {
      return CbcComponentStatus.expected;
    }

    final rangeSpan = high - low;
    final margin = rangeSpan * 0.10; // 10% margin for MONITOR zone

    if (value < low) {
      if (value >= low - margin) return CbcComponentStatus.monitor;
      return CbcComponentStatus.review;
    } else {
      if (value <= high + margin) return CbcComponentStatus.monitor;
      return CbcComponentStatus.review;
    }
  }

  /// Builds an interpretive (non-diagnostic) context phrase.
  static String _buildContextPhrase({
    required String componentName,
    required double value,
    required String unit,
    required double low,
    required double high,
    required Trimester trimester,
    required CbcComponentStatus status,
  }) {
    final trimesterLabel = getTrimesterLabel(trimester).toLowerCase();

    switch (status) {
      case CbcComponentStatus.expected:
        return 'The recorded $componentName level of $value $unit falls within '
            'the commonly expected range of $low–$high $unit during the '
            '$trimesterLabel of pregnancy.';
      case CbcComponentStatus.monitor:
        final direction = value < low ? 'slightly below' : 'slightly above';
        return 'The recorded $componentName level of $value $unit appears '
            '$direction the commonly expected range of $low–$high $unit '
            'during the $trimesterLabel and may benefit from continued '
            'healthcare monitoring.';
      case CbcComponentStatus.review:
        final direction = value < low ? 'below' : 'above';
        return 'The recorded $componentName level of $value $unit appears '
            '$direction the commonly expected range of $low–$high $unit '
            'during the $trimesterLabel. Clinical review and consultation '
            'is recommended.';
    }
  }
}
