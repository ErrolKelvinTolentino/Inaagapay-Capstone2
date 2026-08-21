// lib/widgets/profile_risk_card.dart
// Risk assessment card, extracted from _buildSimpleRiskCard.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../services/risk_engine.dart';
import '../services/auth_storage.dart';
import '../services/gestational_diabetes_screening.dart';

class ConsiderableFactor {
  final DateTime date;
  final String type;
  final String summary;

  ConsiderableFactor({
    required this.date,
    required this.type,
    required this.summary,
  });
}

/// Collapses risk-factor rows that describe one finding.
///
/// Public so the rules can be tested directly: they are string heuristics over
/// free text that three different screens write, which is exactly the kind of
/// logic that breaks quietly.
class RiskFactorRows {
  const RiskFactorRows._();

  /// Keeps one row per finding, choosing the wording that says the most.
  ///
  /// Three writers produce maternal-age rows and none of them agree: the
  /// add-mother form writes "Maternal age below 19 years", the prenatal
  /// check-up writes "Maternal age factor (17 years)", and a repeat assessment
  /// writes that second one again. All three arrived here verbatim, so one
  /// finding filled three of five bullets and counted as three in the banner —
  /// a 17-year-old read as more at risk than she is, on the strength of a
  /// duplicate.
  ///
  /// Collapsing happens at read time rather than in the writers because the
  /// specific wording is worth keeping on a mother's own record: "(17 years)"
  /// tells the midwife something "Young maternal age" does not. Only the
  /// repetition goes — and doing it here also fixes rows already saved.
  static void collapseInPlace(List<String> factors) {
    final byFinding = <String, String>{};
    for (final entry in factors) {
      final text = entry.trim();
      if (text.isEmpty) continue;
      final key = _factorKey(text);
      final existing = byFinding[key];
      if (existing == null || _saysMore(text, existing)) {
        byFinding[key] = text;
      }
    }
    final collapsed = byFinding.values.map(_displayFactor).toList();
    factors
      ..clear()
      ..addAll(collapsed);
  }

  static final RegExp _influenceSuffix = RegExp(
      r'\s*\((low|moderate|high|minimal|severe)\)\s*$',
      caseSensitive: false);

  static final RegExp _bracketedValue = RegExp(r'\s*\([^)]*\d[^)]*\)');

  static String _factorKey(String text) {
    final lower = text.toLowerCase().replaceAll(_influenceSuffix, '').trim();

    if (lower.contains('maternal age') ||
        lower.contains('adolescent') ||
        lower.contains('teen')) {
      final value = _firstNumber(lower);
      final saysAdvanced = lower.contains('advanced') ||
          lower.contains('elderly') ||
          lower.contains('≥') ||
          lower.contains('>=');
      if (saysAdvanced || (value != null && value >= 35)) {
        return 'maternal-age-advanced';
      }
      return 'maternal-age-young';
    }

    // Elsewhere a bracketed number is a threshold or a reading — "(>=140/90)",
    // "(BMI < 18.5)". The finding is the same finding without it.
    return lower.replaceAll(_bracketedValue, '').trim();
  }

  static double? _firstNumber(String text) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  /// Whether the number in a row is a cut-point rather than the mother's own
  /// measurement. "Below 19 years" carries a 19 that is not her age.
  static bool _statesThreshold(String text) {
    final lower = text.toLowerCase();
    return lower.contains('below') ||
        lower.contains('under') ||
        lower.contains('over') ||
        lower.contains('above') ||
        lower.contains('≥') ||
        lower.contains('>=');
  }

  /// A row carrying the mother's own value beats one carrying only the rule she
  /// fell outside of — "17 years" is what a midwife acts on.
  static int _informativeness(String text) {
    var score = 0;
    if (RegExp(r'\d').hasMatch(text)) score += 2;
    if (!_statesThreshold(text)) score += 1;
    return score;
  }

  static bool _saysMore(String candidate, String current) {
    final byScore = _informativeness(candidate) - _informativeness(current);
    if (byScore != 0) return byScore > 0;
    return candidate.length > current.length;
  }

  /// "Maternal age factor (17 years) (low)" is a database label read aloud. On
  /// screen it is one fact: her age, and which way it counts.
  static String _displayFactor(String text) {
    final influence = _influenceSuffix.firstMatch(text)?.group(0)?.trim() ?? '';
    final body = text.replaceAll(_influenceSuffix, '').trim();

    if (body.toLowerCase().contains('maternal age') && !_statesThreshold(body)) {
      final value = _firstNumber(body);
      if (value != null) {
        final age = value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toString();
        return 'Maternal age $age${influence.isEmpty ? '' : ' $influence'}';
      }
    }
    return text;
  }
}

class ProfileRiskCard extends StatefulWidget {
  final Map<String, dynamic> profile;
  final Map<String, dynamic> pregnancy;
  final bool? isMotherView;

  const ProfileRiskCard({
    super.key,
    required this.profile,
    required this.pregnancy,
    this.isMotherView,
  });

  @override
  State<ProfileRiskCard> createState() => _ProfileRiskCardState();
}

class _ProfileRiskCardState extends State<ProfileRiskCard> {
  bool _loading = true;
  bool _isMotherViewComputed = false;
  List<String> _registrationRiskFactors = [];
  Map<int, String> _labTestAiResponses = {};

  @override
  void initState() {
    super.initState();
    _determineViewRole();
    _loadDetails();
  }

  Future<void> _determineViewRole() async {
    if (widget.isMotherView != null) {
      if (mounted) {
        setState(() => _isMotherViewComputed = widget.isMotherView!);
      }
    } else {
      final role = await AuthStorage.getUserRole();
      if (mounted) {
        setState(() => _isMotherViewComputed = (role?.toLowerCase() == 'mother'));
      }
    }
  }

  @override
  void didUpdateWidget(covariant ProfileRiskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMotherView != widget.isMotherView) {
      _determineViewRole();
    }
    if (oldWidget.pregnancy['pregnancy_id'] != widget.pregnancy['pregnancy_id']) {
      setState(() => _loading = true);
      _loadDetails();
    }
  }

  Future<void> _loadDetails() async {
    try {
      final pregnancyId = widget.pregnancy['pregnancy_id'];
      if (pregnancyId == null) {
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }

      final client = Supabase.instance.client;

      // 1. Fetch registration risk factors (where ai_response_id is null)
      final assessments = await client
          .from('pregnancy_risk_assessments')
          .select('pregnancy_risk_id')
          .eq('pregnancy_id', pregnancyId)
          .filter('ai_response_id', 'is', null);

      List<String> regFactors = [];
      if (assessments.isNotEmpty) {
        final riskIds = assessments.map((a) => a['pregnancy_risk_id'] as int).toList();
        final factors = await client
            .from('pregnancy_risk_factors')
            .select('factor, risk_influence')
            .inFilter('pregnancy_risk_id', riskIds);

        if (factors.isNotEmpty) {
          regFactors = factors.map((f) {
            final factorText = f['factor']?.toString() ?? '';
            final influence = f['risk_influence']?.toString() ?? '';
            if (influence.isNotEmpty) {
              return '$factorText ($influence)';
            }
            return factorText;
          }).where((f) => f.isNotEmpty).toList();
        }
      }

      // 2. Fetch lab test AI responses
      final labTests = (widget.pregnancy['lab_tests'] as List?) ?? [];
      final labTestIds = labTests.map((l) => l['lab_test_id'] as int?).whereType<int>().toList();

      Map<int, String> labAi = {};
      if (labTestIds.isNotEmpty) {
        final aiResponses = await client
            .from('ai_responses')
            .select('reference_id, response')
            .eq('reference_table', 'lab_tests')
            .eq('response_type', 'lab_test_analysis')
            .eq('status', 'approved')
            .inFilter('reference_id', labTestIds);

        if (aiResponses.isNotEmpty) {
          for (final row in aiResponses.cast<Map<String, dynamic>>()) {
            final refId = row['reference_id'] as int?;
            final resp = row['response'] as String?;
            if (refId != null && resp != null) {
              labAi[refId] = resp;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _registrationRiskFactors = regFactors;
          _labTestAiResponses = labAi;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading risk card details: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkups =
        (widget.pregnancy['checkups'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final latestCheckup = checkups.isNotEmpty
        ? (List<Map<String, dynamic>>.from(checkups)
              ..sort((a, b) {
                final da =
                    DateTime.tryParse(a['checkup_datetime']?.toString() ?? '');
                final db =
                    DateTime.tryParse(b['checkup_datetime']?.toString() ?? '');
                if (da == null || db == null) return 0;
                return db.compareTo(da);
              }))
            .first
        : null;

    if (latestCheckup == null) return _buildNoDataCard();

    final ruleRisk = RiskEngine.evaluate(latestCheckup: latestCheckup);
    final dbRiskLevel = widget.pregnancy['pregnancy_risk_level']?.toString().toLowerCase();
    final checkupRiskLevel = latestCheckup['risk_assessment']?['risk_level']?.toString().toLowerCase();

    // Determine isHigh: database pregnancy risk level has highest priority,
    // then latest checkup database risk assessment, then rule-based fallback.
    final isHigh = dbRiskLevel == 'high' ||
                   (dbRiskLevel == null && checkupRiskLevel == 'high') ||
                   (dbRiskLevel == null && checkupRiskLevel == null && ruleRisk.level == 'high');

    // ── Compile Current Risk Factors ──────────────────────────────────────────
    final List<String> currentRiskFactors = [];
    currentRiskFactors.addAll(_registrationRiskFactors);

    final medicalConditions = (widget.profile['medical_conditions'] as List?) ?? [];
    for (final condition in medicalConditions) {
      final name = condition['condition_name']?.toString() ?? '';
      final status = condition['status']?.toString().toLowerCase() ?? '';
      if (name.isNotEmpty && (status == 'active' || status == 'ongoing')) {
        currentRiskFactors.add('Condition: $name');
      }
    }

    final allergies = (widget.profile['allergies'] as List?) ?? [];
    for (final allergy in allergies) {
      final allergen = allergy['allergen']?.toString() ?? '';
      final status = allergy['status']?.toString().toLowerCase() ?? '';
      if (allergen.isNotEmpty && (status == 'active' || status == 'ongoing')) {
        currentRiskFactors.add('Allergy to $allergen');
      }
    }

    RiskFactorRows.collapseInPlace(currentRiskFactors);

    // ── Compile Considerable Factors (Requires Closer Monitoring) ─────────────
    final List<ConsiderableFactor> considerableFactors = [];

    // 1. Prenatal Checkups
    for (final checkup in checkups) {
      final riskLvl = checkup['risk_assessment']?['risk_level']?.toString().toLowerCase();
      if (riskLvl == 'high') {
        final dateStr = checkup['checkup_datetime'] ?? checkup['created_at'] ?? '';
        final date = DateTime.tryParse(dateStr.toString()) ?? DateTime.now();

        // Compile checkup risk factors
        final factors = (checkup['risk_factors'] as List?) ?? [];
        final List<String> fList = [];
        for (final f in factors) {
          final factor = f['factor']?.toString() ?? '';
          final influence = f['risk_influence']?.toString() ?? '';
          if (factor.isNotEmpty) {
            fList.add(influence.isNotEmpty ? '$factor ($influence)' : factor);
          }
        }
        final summary = fList.isNotEmpty
            ? fList.join(', ')
            : 'Recorded as needing closer monitoring at this check-up.';

        considerableFactors.add(ConsiderableFactor(
          date: date,
          type: 'Prenatal Checkup',
          summary: summary,
        ));
      }
    }

    // 2. Ultrasound Records
    final ultrasounds = (widget.pregnancy['ultrasounds'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final us in ultrasounds) {
      final classification = us['monitoring_classification']?.toString().toLowerCase();
      if (classification == 'requires_closer_monitoring' || classification == 'requires closer monitoring') {
        final dateStr = us['ultrasound_date'] ?? us['created_at'] ?? '';
        final date = DateTime.tryParse(dateStr.toString()) ?? DateTime.now();

        final rawRemarks = us['remarks']?.toString() ?? '';
        final summary =
            _getShortSummary(rawRemarks, 'Recorded as needing closer monitoring.');

        considerableFactors.add(ConsiderableFactor(
          date: date,
          type: 'Ultrasound',
          summary: summary,
        ));
      }
    }

    // 3. Lab Test Results
    final labTests = (widget.pregnancy['lab_tests'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final lab in labTests) {
      final labId = lab['lab_test_id'] as int?;
      final aiResponse = labId != null ? _labTestAiResponses[labId] : null;

      if (_labTestRequiresMonitoring(lab, aiResponse)) {
        final dateStr = lab['lab_test_date'] ?? lab['created_at'] ?? '';
        final date = DateTime.tryParse(dateStr.toString()) ?? DateTime.now();
        final type = lab['lab_test_type'] ?? 'Lab Test';

        final summary = _getLabTestConcernSummary(lab, aiResponse);

        considerableFactors.add(ConsiderableFactor(
          date: date,
          type: type,
          summary: summary,
        ));
      }
    }

    // Sort Considerable Factors by date descending (newest first)
    considerableFactors.sort((a, b) => b.date.compareTo(a.date));

    // Compile banner title, note, and styling based on _isMotherViewComputed
    final bool isMother = _isMotherViewComputed;

    final String bannerTitle = isMother
        ? (isHigh ? 'SPECIAL CARE NEEDED' : 'ROUTINE CARE')
        : (isHigh ? 'HIGH RISK' : 'LOW RISK');

    String bannerNote;
    if (isMother) {
      if (currentRiskFactors.isNotEmpty) {
        bannerNote = isHigh
            ? '${currentRiskFactors.length} health indicator(s) under observation'
            : 'Monitored: ${currentRiskFactors.join(', ')}';
      } else {
        bannerNote = isHigh
            ? 'Closer midwife monitoring recommended'
            : 'All pregnancy metrics are on track';
      }
    } else {
      if (currentRiskFactors.isNotEmpty) {
        bannerNote = isHigh
            ? '${currentRiskFactors.length} risk factor(s) identified'
            : currentRiskFactors.join(', ');
      } else {
        bannerNote = isHigh
            ? 'High risk factors detected'
            : 'All readings within normal range';
      }
    }

    final Color bgColor = isHigh ? const Color(0xFFFFF1F2) : const Color(0xFFF0FDF4);
    final Color borderColor = isHigh ? const Color(0xFFFECDD3) : const Color(0xFFBBF7D0);
    final Color textColor = isHigh ? const Color(0xFF9F1239) : const Color(0xFF15803D);

    final IconData bannerIcon = isMother
        ? (isHigh ? Icons.medical_services_outlined : Icons.check_circle_outline_rounded)
        : (isHigh ? Icons.gpp_maybe_rounded : Icons.check_circle_outline_rounded);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showRiskDetailsModal(
          context,
          currentRiskFactors: currentRiskFactors,
          considerableFactors: considerableFactors,
          isHigh: isHigh,
          riskColor: textColor,
          bannerTitle: bannerTitle,
          bannerNote: bannerNote,
          isMotherView: isMother,
        ),
        child: Ink(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    bannerIcon,
                    color: textColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bannerTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bannerNote,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: textColor.withValues(alpha: 0.7),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static num? _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  /// Reads an OGTT straight from the recorded glucose values.
  ///
  /// The keyword scan below cannot see a sugar test at all. It looks for words
  /// like MONITOR or REVIEW in `remarks` and in the approved AI text, and the
  /// query that loads this pregnancy selects neither `remarks` nor
  /// `lab_test_id` — so the remarks are always empty, and the id used to fetch
  /// the AI response is always null, which leaves the id list empty and skips
  /// the AI query entirely. A completed OGTT with two samples at threshold
  /// matched nothing and never reached the sheet.
  ///
  /// The glucose columns *are* selected, so the test is read the way the rest
  /// of the app reads it: through the cited screening module, on the numbers
  /// themselves rather than on prose about them.
  GdmAssessment? _glucoseAssessment(Map<String, dynamic> lab) {
    final values = GlucoseValues(
      fasting: _num(lab['fasting_glucose_mg_dl']),
      oneHour: _num(lab['glucose_1hr_mg_dl']),
      twoHour: _num(lab['glucose_2hr_mg_dl']),
      threeHour: _num(lab['glucose_3hr_mg_dl']),
    );
    if (values.isEmpty) return null;
    return GestationalDiabetesScreening.assess(values: values);
  }

  bool _labTestRequiresMonitoring(Map<String, dynamic> lab, String? aiResponse) {
    final glucose = _glucoseAssessment(lab);
    if (glucose != null && glucose.result == GdmResult.meetsThreshold) {
      return true;
    }

    final remarks = lab['remarks']?.toString().toUpperCase() ?? '';
    if (remarks.contains('MONITOR') || remarks.contains('REQUIRES_CLOSER_MONITORING') || remarks.contains('MONITORING_RECOMMENDED') || remarks.contains('CLINICAL_FOLLOW_UP_RECOMMENDED') || remarks.contains('REVIEW')) {
      return true;
    }
    if (aiResponse != null) {
      final aiUpper = aiResponse.toUpperCase();
      if (aiUpper.contains('MONITOR') || aiUpper.contains('REQUIRES_CLOSER_MONITORING') || aiUpper.contains('MONITORING_RECOMMENDED') || aiUpper.contains('CLINICAL_FOLLOW_UP_RECOMMENDED') || aiUpper.contains('REVIEW')) {
        return true;
      }
    }
    return false;
  }

  String _getLabTestConcernSummary(Map<String, dynamic> lab, String? aiResponse) {
    // The screening module's own wording, so a sugar test reads the same here
    // as it does on the dashboard. It names which samples reached threshold and
    // stops there — the module is built never to name a condition.
    final glucose = _glucoseAssessment(lab);
    if (glucose != null && glucose.result == GdmResult.meetsThreshold) {
      final samples = glucose.samplesAtOrAboveThreshold;
      if (samples.isNotEmpty) {
        return 'Samples at or above the screening threshold: '
            '${samples.join(", ")}. ${GdmAction.referForAssessment.label}.';
      }
      return glucose.finding;
    }

    final text = aiResponse ?? lab['remarks']?.toString() ?? '';
    // "Abnormal" is a clinical judgement, and this widget is not entitled to
    // make one — it reports that a result was flagged and points at the record
    // holding the actual values.
    if (text.isEmpty) return 'Marked for review — open the record for the values.';

    final concerns = <String>[];
    final lines = text.split('\n');
    for (final line in lines) {
      final cleaned = line.replaceFirst(RegExp(r'^[•\-*]\s*'), '').trim();
      final bracketMatch = RegExp(r'\[(.*?)\]').firstMatch(cleaned);
      if (bracketMatch != null) {
        final status = bracketMatch.group(1)!.trim().toUpperCase();
        if (status == 'MONITOR' || status == 'ABNORMAL' || status == 'REVIEW' || status == 'CONCERNING') {
          final testName = cleaned.substring(0, bracketMatch.start).trim();
          final colonIdx = testName.indexOf(':');
          final nameOnly = colonIdx != -1 ? testName.substring(0, colonIdx).trim() : testName;
          concerns.add(nameOnly);
        }
      }
    }

    if (concerns.isNotEmpty) {
      return 'Marked for review: ${concerns.join(", ")}';
    }

    return _getShortSummary(
        lab['remarks'], 'Marked for review based on the recorded values.');
  }

  String _getShortSummary(String? text, String fallback) {
    if (text == null || text.trim().isEmpty) return fallback;
    var clean = text
        .replaceAll(RegExp(r'#+\s*'), '')
        .replaceAll(RegExp(r'[•\-*]\s*'), '')
        .trim();
    final index = clean.indexOf('.');
    if (index != -1) {
      clean = clean.substring(0, index).trim();
    }
    if (clean.length > 80) {
      return '${clean.substring(0, 80).trim()}...';
    }
    return clean;
  }


  void _showRiskDetailsModal(
    BuildContext context, {
    required List<String> currentRiskFactors,
    required List<ConsiderableFactor> considerableFactors,
    required bool isHigh,
    required Color riskColor,
    required String bannerTitle,
    required String bannerNote,
    required bool isMotherView,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomPadding = MediaQuery.of(sheetContext).viewInsets.bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.68,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.brandPrimary),
                    )
                  : ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding + 24),
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.borderPrimary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isMotherView ? 'Care & Health Assessment' : 'Risk Assessment',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildStatusBanner(
                          isHigh: isHigh,
                          titleText: bannerTitle,
                          note: bannerNote,
                          riskColor: riskColor,
                          isMotherView: isMotherView,
                        ),
                        const SizedBox(height: 16),
                        _buildRiskSection(
                          title: isMotherView ? 'Health Indicators Being Monitored' : 'Current Risk Factors',
                          icon: isHigh
                              ? (isMotherView ? Icons.medical_services_outlined : Icons.warning_amber_rounded)
                              : Icons.check_circle_outline_rounded,
                          iconColor: riskColor,
                          children: currentRiskFactors.isEmpty
                              ? [
                                  _buildDetailRow(
                                    isMotherView
                                        ? 'No concerns or special care factors identified'
                                        : 'No current risk factors identified',
                                    AppColors.success,
                                  ),
                                ]
                              : currentRiskFactors
                                  .map((finding) =>
                                      _buildDetailRow(finding, isHigh ? riskColor : AppColors.warning))
                                  .toList(),
                        ),
                        const SizedBox(height: 16),
                        // What the ultrasound and lab records actually say.
                        //
                        // This list was already being built from all three
                        // record types, sorted by date, and handed to this
                        // sheet — which then rendered only the registration
                        // factors and dropped it. Dart does not warn on an
                        // unused parameter, so the sheet had been quietly
                        // showing half its evidence.
                        _buildRecordFindingsSection(
                          considerableFactors: considerableFactors,
                          isMotherView: isMotherView,
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  // ── Findings carried from the records ─────────────────────────────────────

  /// The ultrasound, laboratory and check-up entries marked for closer
  /// monitoring.
  ///
  /// Written to report *what a record says and who recorded it*, never what it
  /// means. Each row names the record type, the date it was taken and the
  /// wording already stored against it — a pointer back to a document, not a
  /// finding of its own. That boundary is why there is no severity ranking here
  /// and no red: a ranked, alarm-coloured list of extracts reads as a diagnosis
  /// the app assembled, which is exactly what this must not look like.
  Widget _buildRecordFindingsSection({
    required List<ConsiderableFactor> considerableFactors,
    required bool isMotherView,
  }) {
    if (considerableFactors.isEmpty) {
      return _buildRiskSection(
        title: isMotherView ? 'From Your Records' : 'From the Records',
        icon: Icons.folder_open_rounded,
        iconColor: AppColors.textSecondary,
        children: [
          _buildDetailRow(
            isMotherView
                ? 'Nothing in your ultrasound or laboratory records has been marked for a closer look.'
                : 'No ultrasound, laboratory or check-up entry is marked for closer monitoring.',
            AppColors.success,
          ),
        ],
      );
    }

    return _buildRiskSection(
      title: isMotherView ? 'From Your Records' : 'From the Records',
      icon: Icons.folder_open_rounded,
      iconColor: AppColors.brandPrimary,
      children: [
        Text(
          isMotherView
              ? 'Entries your midwife marked for a closer look:'
              : 'Entries marked for closer monitoring, newest first:',
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),
        ...considerableFactors.map(_buildFindingCard),
        const SizedBox(height: 2),
        Text(
          isMotherView
              ? 'These are notes from records already saved by your midwife — not new results. Ask her to walk you through any of them.'
              : 'Taken from records already saved for this pregnancy. Open the record itself for the full result.',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.4,
            fontStyle: FontStyle.italic,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildFindingCard(ConsiderableFactor factor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The record type as a pill, so a row can be placed at a glance
              // without reading it: an ultrasound and a sugar test are
              // different kinds of evidence and should not look alike.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconForRecordType(factor.type),
                        size: 11, color: const Color(0xFF475569)),
                    const SizedBox(width: 5),
                    Text(
                      factor.type,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, yyyy').format(factor.date),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            factor.summary,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForRecordType(String type) {
    final t = type.toLowerCase();
    if (t.contains('ultrasound')) return Icons.monitor_heart_outlined;
    if (t.contains('checkup') || t.contains('check-up')) {
      return Icons.medical_information_outlined;
    }
    return Icons.science_outlined;
  }

  Widget _buildStatusBanner({
    required bool isHigh,
    required String titleText,
    required String note,
    required Color riskColor,
    required bool isMotherView,
  }) {
    final Color bgColor = isHigh ? const Color(0xFFFFF1F2) : const Color(0xFFF0FDF4);
    final Color borderColor = isHigh ? const Color(0xFFFECDD3) : const Color(0xFFBBF7D0);
    final Color textColor = isHigh ? const Color(0xFF9F1239) : const Color(0xFF15803D);

    final IconData bannerIcon = isMotherView
        ? (isHigh ? Icons.medical_services_outlined : Icons.check_circle_outline_rounded)
        : (isHigh ? Icons.gpp_maybe_rounded : Icons.check_circle_outline_rounded);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              bannerIcon,
              color: textColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgPrimary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.textSecondary),
          SizedBox(width: 12),
          Text('No checkup data available yet',
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
