import 'dart:convert';

class GroqResponse {
  final String description;
  final List<String>? measurements;
  final List<String>? labels;
  final double? confidence;

  // Fields for ultrasound assessment
  final String? healthStatus;
  final List<String>? normalFindings;
  final List<String>? concerns;
  final String? gestationalAge;
  final String? fetalWeight;
  final String? heartRate;

  // Trimester-aware monitoring classification
  // Values: 'WITHIN_EXPECTED_RANGE' | 'REQUIRES_CLOSER_MONITORING' | 'FOLLOW_UP_RECOMMENDED'
  // Reference: INTERGROWTH-21st (Papageorghiou et al., Lancet 2014);
  //            WHO Fetal Growth Charts (Kiserud et al., PLOS Medicine 2017)
  final String? monitoringClassification;

  // Fields for lab test assessment
  final List<LabResult>? labResults;
  final String? overallAssessment;
  final List<String>? abnormalFindings;
  final List<String>? normalRanges;
  final List<String>? recommendations;

  // Fields for extracted admin/patient info
  final String? extractedPatientName;
  final String? extractedClinicLocation;
  final String? extractedProfessional;
  final String? extractedLabTestType;

  GroqResponse({
    required this.description,
    this.measurements,
    this.labels,
    this.confidence,
    this.healthStatus,
    this.normalFindings,
    this.concerns,
    this.gestationalAge,
    this.fetalWeight,
    this.heartRate,
    this.monitoringClassification,
    this.labResults,
    this.overallAssessment,
    this.abnormalFindings,
    this.normalRanges,
    this.recommendations,
    this.extractedPatientName,
    this.extractedClinicLocation,
    this.extractedProfessional,
    this.extractedLabTestType,
  });

  factory GroqResponse.fromJson(Map<String, dynamic> json) {
    final text = _extractText(json);

    if (text.isEmpty) {
      return GroqResponse(
        description: 'AI output unavailable. Manual review required.',
      );
    }

    final structured = _decodeStructuredJson(text);
    if (structured != null) {
      return _fromStructuredJson(structured);
    }

    return _fromFreeText(text);
  }

  static String _extractText(Map<String, dynamic> json) {
    try {
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        return '';
      }

      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        return '';
      }

      return (parts.first as Map<String, dynamic>)['text']?.toString().trim() ??
          '';
    } catch (_) {
      return '';
    }
  }

  static Map<String, dynamic>? _decodeStructuredJson(String raw) {
    var text = raw.trim();

    if (text.startsWith('```')) {
      text = text
          .replaceAll(RegExp(r'^```[a-zA-Z0-9_-]*\n?'), '')
          .replaceAll(RegExp(r'\n?```$'), '')
          .trim();
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Try to recover JSON object from mixed text.
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final candidate = text.substring(start, end + 1);
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {}
    }

    return null;
  }

  static GroqResponse _fromStructuredJson(Map<String, dynamic> json) {
    final relevance = _safeText(json['relevance_check']).toUpperCase();
    final relevanceReason = _safeText(json['relevance_reason']);
    final confidence = _toBoundedDouble(json['confidence_score']);

    final measurements = <String>[];
    final normalFindings = <String>[];
    final concerns = <String>[];
    final labResults = <LabResult>[];
    final abnormalFindings = _toStringList(json['abnormal_findings']);
    final normalRanges = _toStringList(json['normal_ranges']);
    final recommendations = _toStringList(json['recommendations']);
    final keyObservations = _toStringList(json['key_observations']);
    final aiSummary = _safeText(json['summary']);

    String? fetalWeight;
    String? heartRate;

    final rawMeasurements = json['measurements'];
    if (rawMeasurements is List) {
      for (final item in rawMeasurements) {
        if (item is! Map) continue;
        final name = _safeText(item['name']);
        final value = _safeText(item['value']);
        final status = _safeText(item['status']).toUpperCase();
        final evidence = _safeText(item['evidence']);
        if (name.isEmpty && value.isEmpty) continue;

        final base =
            '${name.isEmpty ? 'Measurement' : name}: ${value.isEmpty ? 'n/a' : value} [$status]';
        final summary = evidence.isNotEmpty ? '$base ($evidence)' : base;
        measurements.add(summary);

        if (name.toLowerCase().contains('weight') && value.isNotEmpty) {
          fetalWeight = value;
        }
        if (name.toLowerCase().contains('heart') && value.isNotEmpty) {
          heartRate = value;
        }
      }
    }

    final rawAnatomical = json['anatomical_findings'];
    if (rawAnatomical is List) {
      for (final item in rawAnatomical) {
        if (item is! Map) continue;
        final structure = _safeText(item['structure']);
        final status = _safeText(item['status']).toUpperCase();
        final note = _safeText(item['note']);
        if (structure.isEmpty) continue;

        final summary = note.isEmpty
            ? '$structure [$status]'
            : '$structure [$status] - $note';

        if (status == 'NORMAL') {
          normalFindings.add(summary);
        } else if (status == 'CONCERNING') {
          concerns.add(summary);
        }
      }
    }

    final rawLabResults = json['lab_results'];
    if (rawLabResults is List) {
      for (final item in rawLabResults) {
        if (item is! Map) continue;
        final testName = _safeText(item['test_name']);
        final value = _safeText(item['value']);
        final unit = _safeText(item['unit']);
        final status = _safeText(item['status']).toUpperCase();
        final cleanValue = value.toLowerCase().trim();
        final cleanUnit = unit.toLowerCase().trim();
        final displayValue = (cleanValue.endsWith(cleanUnit) ||
                              cleanValue.contains(' $cleanUnit') ||
                              unit.isEmpty)
            ? value
            : '$value $unit'.trim();

        if (testName.isEmpty && displayValue.isEmpty) continue;

        labResults.add(
          LabResult(
            testName: testName.isEmpty ? 'Unknown test' : testName,
            value: displayValue,
            isNormal: status == 'NORMAL',
            isAbnormal: status == 'ABNORMAL' || status == 'CONCERNING',
          ),
        );
      }
    }

    final healthStatus = _safeText(json['overall_health_status']).toUpperCase();
    final gestationalAge = _safeText(json['gestational_age_assessment']);
    final overallAssessment = _safeText(json['overall_assessment']);

    // Parse trimester-aware monitoring classification
    // Reference: INTERGROWTH-21st; WHO Fetal Growth Charts
    final monitoringClassification = _safeText(json['monitoring_classification']).toUpperCase();

    final patientInfo = json['patient_info_visible'] as Map<String, dynamic>?;
    final extractedPatientName = _safeText(patientInfo?['patient_name'] ?? patientInfo?['name']);
    final extractedClinicLocation = _safeText(patientInfo?['clinic_location'] ?? patientInfo?['lab_name']);
    final extractedProfessional = _safeText(patientInfo?['attending_professional']);
    final extractedLabTestType = _safeText(json['identified_lab_test_type'] ?? json['lab_test_type']);

    final description = _buildStructuredDescription(
      relevance: relevance,
      relevanceReason: relevanceReason,
      aiSummary: aiSummary,
      healthStatus: healthStatus,
      measurements: measurements,
      gestationalAge: gestationalAge,
      normalFindings: normalFindings,
      concerns: concerns,
      keyObservations: keyObservations,
      labResults: labResults,
      abnormalFindings: abnormalFindings,
      normalRanges: normalRanges,
      overallAssessment: overallAssessment,
      recommendations: recommendations,
    );

    return GroqResponse(
      description: description,
      measurements: measurements.isEmpty ? null : measurements,
      labels: const [],
      confidence: confidence,
      healthStatus: healthStatus.isEmpty ? null : healthStatus,
      normalFindings: normalFindings.isEmpty ? null : normalFindings,
      concerns: concerns.isEmpty ? null : concerns,
      gestationalAge: gestationalAge.isEmpty ? null : gestationalAge,
      fetalWeight: fetalWeight,
      heartRate: heartRate,
      monitoringClassification: monitoringClassification.isEmpty ? null : monitoringClassification,
      labResults: labResults.isEmpty ? null : labResults,
      overallAssessment: overallAssessment.isEmpty ? null : overallAssessment,
      abnormalFindings:
          abnormalFindings.isEmpty ? null : abnormalFindings.toList(),
      normalRanges: normalRanges.isEmpty ? null : normalRanges.toList(),
      recommendations:
          recommendations.isEmpty ? null : recommendations.toList(),
      extractedPatientName: extractedPatientName.isEmpty ? null : extractedPatientName,
      extractedClinicLocation: extractedClinicLocation.isEmpty ? null : extractedClinicLocation,
      extractedProfessional: extractedProfessional.isEmpty ? null : extractedProfessional,
      extractedLabTestType: extractedLabTestType.isEmpty ? null : extractedLabTestType,
    );
  }

  static GroqResponse _fromFreeText(String text) {
    String? healthStatus;
    if (RegExp(r'HEALTHY[_\s-]?NORMAL', caseSensitive: false).hasMatch(text)) {
      healthStatus = 'HEALTHY_NORMAL';
    } else if (RegExp(r'REQUIRES[_\s-]?MONITORING', caseSensitive: false)
        .hasMatch(text)) {
      healthStatus = 'REQUIRES_MONITORING';
    } else if (RegExp(r'CONSULT[_\s-]?SPECIALIST', caseSensitive: false)
        .hasMatch(text)) {
      healthStatus = 'CONSULT_SPECIALIST';
    }

    final measurements = <String>[];
    final measurementPatterns = [
      RegExp(r'BPD[:\s]*(\d+(?:\.\d+)?\s*mm)', caseSensitive: false),
      RegExp(r'HC[:\s]*(\d+(?:\.\d+)?\s*mm)', caseSensitive: false),
      RegExp(r'AC[:\s]*(\d+(?:\.\d+)?\s*mm)', caseSensitive: false),
      RegExp(r'FL[:\s]*(\d+(?:\.\d+)?\s*mm)', caseSensitive: false),
      RegExp(r'Fetal Heart Rate[:\s]*(\d+(?:\.\d+)?\s*bpm)',
          caseSensitive: false),
      RegExp(r'Estimated Fetal Weight[:\s]*(\d+(?:\.\d+)?\s*(?:g|kg))',
          caseSensitive: false),
    ];

    for (final pattern in measurementPatterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(0);
        if (value != null && value.trim().isNotEmpty) {
          measurements.add(value.trim());
        }
      }
    }

    final normalFindings = RegExp(r'✓([^\n]+)')
        .allMatches(text)
        .map((m) => (m.group(1) ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toList();

    final concerns =
        RegExp(r'(?:⚠|concerning|borderline)([^\n]*)', caseSensitive: false)
            .allMatches(text)
            .map((m) => (m.group(0) ?? '').trim())
            .where((value) => value.isNotEmpty)
            .toList();

    final gestationalAge = RegExp(
      r'Gestational Age[:\s]*(\d+\s*(?:weeks?|wks?)[^\n]*)',
      caseSensitive: false,
    ).firstMatch(text)?.group(1);

    final labResults = <LabResult>[];
    final labMatches = RegExp(r'•\s*([^:\n]+):\s*([^\n]+)')
        .allMatches(text)
        .toList(growable: false);
    for (final match in labMatches) {
      final testName = (match.group(1) ?? '').trim();
      final value = (match.group(2) ?? '').trim();
      if (testName.isEmpty || value.isEmpty) continue;
      final upper = value.toUpperCase();
      labResults.add(
        LabResult(
          testName: testName,
          value: value,
          isNormal: upper.contains('NORMAL') && !upper.contains('ABNORMAL'),
          isAbnormal:
              upper.contains('ABNORMAL') || upper.contains('CONCERNING'),
        ),
      );
    }

    final abnormalFindings =
        _extractSectionLines(text, 'ABNORMAL FINDINGS:', 'NORMAL RANGES:');
    final normalRanges =
        _extractSectionLines(text, 'NORMAL RANGES:', 'RECOMMENDATIONS:');
    final recommendations = _extractSectionLines(
      text,
      'RECOMMENDATIONS:',
      'OVERALL ASSESSMENT:',
    );
    final overallAssessment =
        _extractSectionText(text, 'OVERALL ASSESSMENT:', 'RECOMMENDATIONS:');

    return GroqResponse(
      description: text,
      measurements: measurements.isEmpty ? null : measurements.toSet().toList(),
      labels: const [],
      confidence: null,
      healthStatus: healthStatus,
      normalFindings: normalFindings.isEmpty ? null : normalFindings,
      concerns: concerns.isEmpty ? null : concerns,
      gestationalAge: gestationalAge,
      fetalWeight: measurements
              .firstWhere(
                (m) => RegExp(r'weight', caseSensitive: false).hasMatch(m),
                orElse: () => '',
              )
              .isEmpty
          ? null
          : measurements.firstWhere(
              (m) => RegExp(r'weight', caseSensitive: false).hasMatch(m),
            ),
      heartRate: measurements
              .firstWhere(
                (m) => RegExp(r'heart', caseSensitive: false).hasMatch(m),
                orElse: () => '',
              )
              .isEmpty
          ? null
          : measurements.firstWhere(
              (m) => RegExp(r'heart', caseSensitive: false).hasMatch(m),
            ),
      monitoringClassification: null, // Free-text fallback; engine will compute from screen
      labResults: labResults.isEmpty ? null : labResults,
      overallAssessment: overallAssessment.isEmpty ? null : overallAssessment,
      abnormalFindings: abnormalFindings.isEmpty ? null : abnormalFindings,
      normalRanges: normalRanges.isEmpty ? null : normalRanges,
      recommendations: recommendations.isEmpty ? null : recommendations,
    );
  }

  static String _buildStructuredDescription({
    required String relevance,
    required String relevanceReason,
    String aiSummary = '',
    required String healthStatus,
    required List<String> measurements,
    required String gestationalAge,
    required List<String> normalFindings,
    required List<String> concerns,
    required List<String> keyObservations,
    required List<LabResult> labResults,
    required List<String> abnormalFindings,
    required List<String> normalRanges,
    required String overallAssessment,
    required List<String> recommendations,
  }) {
    final dedupedMeasurements = _dedupeStable(measurements);
    final dedupedNormalFindings = _dedupeStable(normalFindings);
    final dedupedConcerns = _dedupeStable(concerns);
    final dedupedObservations = _dedupeStable(keyObservations);
    final dedupedAbnormalFindings = _dedupeStable(abnormalFindings);
    final dedupedNormalRanges = _dedupeStable(normalRanges);
    final dedupedRecommendations = _dedupeStable(recommendations);

    final lines = <String>[];

    if (relevance.isNotEmpty) {
      lines.add('RELEVANCE CHECK: $relevance');
    }
    if (relevanceReason.isNotEmpty) {
      lines.add('RELEVANCE REASON: $relevanceReason');
    }

    if (relevance == 'UNRELATED') {
      lines.add(
          'RECOMMENDATION: Upload clear and related medical record images only.');
      return lines.join('\n');
    }

    if (aiSummary.isNotEmpty) {
      lines.add('SUMMARY: $aiSummary');
    }

    if (healthStatus.isNotEmpty) {
      lines.add('OVERALL HEALTH STATUS: $healthStatus');
    }

    // Ultrasound-only sections: only show when there are no lab results
    // (i.e. this is an ultrasound, not a lab test).
    final isUltrasound = labResults.isEmpty;

    if (isUltrasound && dedupedMeasurements.isNotEmpty) {
      lines.add('DETAILED MEASUREMENTS ASSESSMENT:');
      for (final item in dedupedMeasurements) {
        lines.add('• $item');
      }
    }

    if (isUltrasound && gestationalAge.isNotEmpty) {
      lines.add('GESTATIONAL AGE ASSESSMENT: $gestationalAge');
    }

    if (isUltrasound && dedupedNormalFindings.isNotEmpty) {
      lines.add('ANATOMICAL ASSESSMENT:');
      for (final item in dedupedNormalFindings) {
        lines.add('• $item');
      }
    }

    if (isUltrasound && dedupedObservations.isNotEmpty) {
      lines.add('KEY OBSERVATIONS:');
      for (final item in dedupedObservations) {
        lines.add('• $item');
      }
    }

    if (labResults.isNotEmpty) {
      lines.add('LABORATORY RESULTS:');
      for (final result in labResults) {
        final status = result.isAbnormal
            ? 'ABNORMAL'
            : (result.isNormal ? 'NORMAL' : 'UNKNOWN');
        lines.add('• ${result.testName}: ${result.value} [$status]');
      }
    }

    final mergedAbnormal = _dedupeStable(
      <String>[...dedupedConcerns, ...dedupedAbnormalFindings],
    );
    if (mergedAbnormal.isNotEmpty) {
      lines.add('ABNORMAL FINDINGS:');
      for (final item in mergedAbnormal) {
        lines.add('• $item');
      }
    }

    if (dedupedNormalRanges.isNotEmpty) {
      lines.add('NORMAL RANGES:');
      for (final item in dedupedNormalRanges) {
        lines.add('• $item');
      }
    }

    if (overallAssessment.isNotEmpty) {
      lines.add('OVERALL ASSESSMENT: $overallAssessment');
    }

    if (dedupedRecommendations.isNotEmpty) {
      lines.add('RECOMMENDATIONS:');
      for (final item in dedupedRecommendations) {
        lines.add('• $item');
      }
    }

    return lines.join('\n').trim();
  }

  static String _safeText(Object? value) {
    return value?.toString().trim() ?? '';
  }

  static List<String> _toStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _dedupeStable(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty || seen.contains(normalized)) {
        continue;
      }
      seen.add(normalized);
      result.add(value.trim());
    }
    return result;
  }

  static double? _toBoundedDouble(Object? value) {
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed < 0) return 0;
      if (parsed > 1) return 1;
      return parsed;
    }

    final parsed = double.tryParse(_safeText(value));
    if (parsed == null) return null;
    if (parsed < 0) return 0;
    if (parsed > 1) return 1;
    return parsed;
  }

  static List<String> _extractSectionLines(
    String source,
    String start,
    String end,
  ) {
    final body = _extractSectionText(source, start, end);
    if (body.isEmpty) return const [];

    return body
        .split('\n')
        .map((line) =>
            line.replaceFirst(RegExp(r'^\s*(?:•|-|\*)\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  static String _extractSectionText(String source, String start, String end) {
    final startIndex = source.toUpperCase().indexOf(start.toUpperCase());
    if (startIndex < 0) return '';

    final contentStart = startIndex + start.length;
    final endIndex =
        source.toUpperCase().indexOf(end.toUpperCase(), contentStart);

    final text = endIndex > contentStart
        ? source.substring(contentStart, endIndex)
        : source.substring(contentStart);

    return text.trim();
  }
}

class LabResult {
  final String testName;
  final String value;
  final bool isNormal;
  final bool isAbnormal;

  LabResult({
    required this.testName,
    required this.value,
    required this.isNormal,
    required this.isAbnormal,
  });
}

