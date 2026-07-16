// lib/services/ultrasound_interpretation_engine.dart
//
// Trimester-aware fetal measurement interpretation engine.
//
// Clinical References:
//   [1] INTERGROWTH-21st: Papageorghiou AT et al.
//       "International standards for fetal growth based on serial ultrasound
//       measurements: the Fetal Growth Longitudinal Study of the
//       INTERGROWTH-21st Project."
//       The Lancet. 2014. https://intergrowth21.tghn.org
//
//   [2] WHO Fetal Growth Charts: Kiserud T et al.
//       "The World Health Organization fetal growth charts."
//       PLOS Medicine. 2017.
//       https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.1002220

class UltrasoundInterpretationEngine {
  // ── Clinical Citation Strings ─────────────────────────────────────────────

  static const String citation1Title = 'INTERGROWTH-21st Project';
  static const String citation1Authors = 'Papageorghiou AT, et al.';
  static const String citation1Full =
      'International standards for fetal growth based on serial ultrasound '
      'measurements: the Fetal Growth Longitudinal Study of the '
      'INTERGROWTH-21st Project. The Lancet. 2014.';
  static const String citation1Url = 'https://intergrowth21.tghn.org';

  static const String citation2Title = 'WHO Fetal Growth Charts';
  static const String citation2Authors = 'Kiserud T, et al.';
  static const String citation2Full =
      'The World Health Organization fetal growth charts. PLOS Medicine. 2017.';
  static const String citation2Url =
      'https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.1002220';

  // ── Step 1: Trimester Determination ──────────────────────────────────────
  //
  // Based on standard obstetric trimester definitions used by both
  // INTERGROWTH-21st and WHO:
  //   1st Trimester : ≤13 weeks (includes week 0–13)
  //   2nd Trimester : 14–27 weeks
  //   3rd Trimester : ≥28 weeks

  static Trimester getTrimester(int aogWeeks) {
    if (aogWeeks <= 13) return Trimester.first;
    if (aogWeeks <= 27) return Trimester.second;
    return Trimester.third;
  }

  static String getTrimesterLabel(Trimester trimester, {String language = 'english'}) {
    final bool fil = language == 'filipino';
    switch (trimester) {
      case Trimester.first:
        return fil ? 'Unang Trimester' : '1st Trimester';
      case Trimester.second:
        return fil ? 'Ikalawang Trimester' : '2nd Trimester';
      case Trimester.third:
        return fil ? 'Ikatlong Trimester' : '3rd Trimester';
    }
  }

  // ── Step 2: Trimester-Relevant Measurement Categories ────────────────────
  //
  // Source: INTERGROWTH-21st (CRL for T1; BPD/HC/AC/FL for T2/T3)
  //         WHO Fetal Growth Charts (EFW, AFI, Presentation for T3)
  //
  // Only the categories listed below are clinically meaningful for the
  // corresponding trimester. Comparing measurements outside this set
  // increases the risk of irrelevant findings and AI misinterpretation.

  static List<RelevantMeasurementCategory> getRelevantCategories(
      Trimester trimester) {
    switch (trimester) {
      case Trimester.first:
        // CRL is the primary dating and growth measure in T1
        // (INTERGROWTH-21st CRL standards: 9–13+6 weeks)
        return [
          RelevantMeasurementCategory.crl,
        ];
      case Trimester.second:
        // BPD, HC, AC, FL are the standard biometric measures for T2
        // (INTERGROWTH-21st Fetal Growth standards: 14–40 weeks)
        return [
          RelevantMeasurementCategory.bpd,
          RelevantMeasurementCategory.hc,
          RelevantMeasurementCategory.ac,
          RelevantMeasurementCategory.fl,
        ];
      case Trimester.third:
        // T3 adds EFW, AFI, and fetal presentation as key clinical parameters
        // (WHO Fetal Growth Charts + INTERGROWTH-21st EFW standards)
        return [
          RelevantMeasurementCategory.efw,
          RelevantMeasurementCategory.afi,
          RelevantMeasurementCategory.presentation,
          RelevantMeasurementCategory.bpd, // still relevant for growth tracking
          RelevantMeasurementCategory.fl,  // still relevant for growth tracking
        ];
    }
  }

  // ── Step 3: Overall Monitoring Classification ─────────────────────────────
  //
  // Deterministically computes the overall classification from the list
  // of per-measurement status strings returned by the AI.
  //
  // Classification tiers (derived from INTERGROWTH-21st and WHO reference ranges):
  //   WITHIN_EXPECTED_RANGE     → Measurements mostly align with gestational-age
  //                               expectations (no concerning or borderline findings)
  //   REQUIRES_CLOSER_MONITORING → One or more mild deviations / borderline findings
  //   FOLLOW_UP_RECOMMENDED     → One or more notable / concerning findings

  static MonitoringClassification classifyMonitoring(
      List<String> measurementStatuses) {
    int borderlineCount = 0;
    int concerningCount = 0;

    for (final status in measurementStatuses) {
      final upper = status.toUpperCase().trim();
      if (upper.contains('ABNORMAL') ||
          upper.contains('CONCERNING') ||
          upper.contains('REVIEW')) {
        concerningCount++;
      } else if (upper.contains('BORDERLINE') ||
          upper.contains('MONITOR') ||
          upper.contains('OBSERVE') ||
          upper.contains('REQUIRES')) {
        borderlineCount++;
      }
    }

    // Notable findings → Follow-Up Recommended
    if (concerningCount >= 1) {
      return MonitoringClassification.followUpRecommended;
    }
    // Mild deviations → Requires Closer Monitoring
    if (borderlineCount >= 1) {
      return MonitoringClassification.requiresCloserMonitoring;
    }
    // No deviations → Within Expected Monitoring Range
    return MonitoringClassification.withinExpectedRange;
  }

  /// Also accepts a raw AI classification string (from JSON) and maps it.
  static MonitoringClassification classifyFromAiString(String? aiString) {
    if (aiString == null) return MonitoringClassification.withinExpectedRange;
    final upper = aiString.toUpperCase().trim();
    if (upper.contains('FOLLOW_UP') || upper.contains('FOLLOW-UP')) {
      return MonitoringClassification.followUpRecommended;
    }
    if (upper.contains('CLOSER') || upper.contains('REQUIRES')) {
      return MonitoringClassification.requiresCloserMonitoring;
    }
    return MonitoringClassification.withinExpectedRange;
  }

  /// Human-readable label for UI display.
  static String classificationLabel(
      MonitoringClassification classification, String language) {
    final bool fil = language == 'filipino';
    switch (classification) {
      case MonitoringClassification.withinExpectedRange:
        return fil
            ? 'Nasa Inaasahang Saklaw ng Pagsubaybay'
            : 'Within Expected Monitoring Range';
      case MonitoringClassification.requiresCloserMonitoring:
        return fil
            ? 'Nangangailangan ng Mas Masusing Pagsubaybay'
            : 'Requires Closer Monitoring';
      case MonitoringClassification.followUpRecommended:
        return fil
            ? 'Inirerekomenda ang Follow-Up na Konsultasyon'
            : 'Follow-Up Recommended';
    }
  }

  /// Database-safe string value for storage.
  static String classificationToString(MonitoringClassification c) {
    switch (c) {
      case MonitoringClassification.withinExpectedRange:
        return 'within_expected_range';
      case MonitoringClassification.requiresCloserMonitoring:
        return 'requires_closer_monitoring';
      case MonitoringClassification.followUpRecommended:
        return 'follow_up_recommended';
    }
  }

  // ── AI Clinical Context Builder ───────────────────────────────────────────
  //
  // Generates the enriched clinical context string passed to the AI prompt.
  // Including trimester + relevant categories allows the AI to focus its
  // measurement interpretation rather than guessing which biometrics apply.

  static String buildAiClinicalContext({
    required int aogWeeks,
    required Trimester trimester,
    required List<RelevantMeasurementCategory> relevantCategories,
    String? healthWorkerName,
    String? institution,
    String? profession,
    String? notes,
    int imageCount = 1,
  }) {
    final trimesterLabel = switch (trimester) {
      Trimester.first => '1st Trimester (AOG ≤13 weeks)',
      Trimester.second => '2nd Trimester (AOG 14–27 weeks)',
      Trimester.third => '3rd Trimester (AOG ≥28 weeks)',
    };

    final categoriesLabel =
        relevantCategories.map((c) => c.displayName).join(', ');

    return [
      'Ultrasound AI analysis request',
      'Gestational age at scan: $aogWeeks weeks',
      'Trimester: $trimesterLabel',
      'Clinically relevant measurement categories for this trimester: $categoriesLabel',
      'Reference standards applied: '
          'INTERGROWTH-21st (Papageorghiou AT et al., The Lancet, 2014); '
          'WHO Fetal Growth Charts (Kiserud T et al., PLOS Medicine, 2017)',
      'Health worker: ${(healthWorkerName?.trim().isNotEmpty == true) ? healthWorkerName : 'Not specified'}',
      'Institution: ${(institution?.trim().isNotEmpty == true) ? institution : 'Not specified'}',
      'Profession: ${(profession?.trim().isNotEmpty == true) ? profession : 'Not specified'}',
      'Clinical notes: ${(notes?.trim().isNotEmpty == true) ? notes : 'None provided'}',
      'Image count: $imageCount',
    ].join('\n');
  }
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum Trimester { first, second, third }

enum RelevantMeasurementCategory {
  crl('CRL — Crown-Rump Length'),
  bpd('BPD — Biparietal Diameter'),
  hc('HC — Head Circumference'),
  ac('AC — Abdominal Circumference'),
  fl('FL — Femur Length'),
  efw('EFW — Estimated Fetal Weight'),
  afi('AFI — Amniotic Fluid Index'),
  presentation('Fetal Presentation');

  final String displayName;
  const RelevantMeasurementCategory(this.displayName);
}

enum MonitoringClassification {
  withinExpectedRange,
  requiresCloserMonitoring,
  followUpRecommended,
}
