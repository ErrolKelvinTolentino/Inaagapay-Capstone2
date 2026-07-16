// lib/widgets/profile_risk_card.dart
// Risk assessment card, extracted from _buildSimpleRiskCard.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../services/risk_engine.dart';

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

class ProfileRiskCard extends StatefulWidget {
  final Map<String, dynamic> profile;
  final Map<String, dynamic> pregnancy;

  const ProfileRiskCard({
    super.key,
    required this.profile,
    required this.pregnancy,
  });

  @override
  State<ProfileRiskCard> createState() => _ProfileRiskCardState();
}

class _ProfileRiskCardState extends State<ProfileRiskCard> {
  bool _loading = true;
  List<String> _registrationRiskFactors = [];
  Map<int, String> _labTestAiResponses = {};

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void didUpdateWidget(covariant ProfileRiskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
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

    final riskColor = isHigh ? AppColors.error : AppColors.success;

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
        final summary = fList.isNotEmpty ? fList.join(', ') : 'Elevated risk parameters detected';

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
        final summary = _getShortSummary(rawRemarks, 'Ultrasound metrics require closer monitoring');

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

    // Compile banner note
    String bannerNote = isHigh ? 'High risk factors detected' : 'All readings within normal range';
    if (currentRiskFactors.isNotEmpty) {
      if (isHigh) {
        bannerNote = '${currentRiskFactors.length} risk factor(s) identified';
      } else {
        bannerNote = currentRiskFactors.join(', ');
      }
    }

    final Color bgColor = isHigh ? const Color(0xFFFFF3F0) : const Color(0xFFEBF7F5);
    final Color borderColor = isHigh ? const Color(0xFFFFAB91) : const Color(0xFFB2DFDB);
    final Color textColor = isHigh ? const Color(0xFFD84315) : const Color(0xFF00796B);

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
          riskColor: riskColor,
          bannerNote: bannerNote,
        ),
        child: Ink(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
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
                    isHigh ? Icons.gpp_maybe_rounded : Icons.check_circle_outline_rounded,
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
                        isHigh ? 'HIGH RISK' : 'LOW RISK',
                        style: TextStyle(
                          fontSize: 16,
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
                  color: textColor,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _labTestRequiresMonitoring(Map<String, dynamic> lab, String? aiResponse) {
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
    final text = aiResponse ?? lab['remarks']?.toString() ?? '';
    if (text.isEmpty) return 'Abnormal levels detected.';

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
      return 'Abnormal levels for: ${concerns.join(", ")}';
    }

    return _getShortSummary(lab['remarks'], 'Requires monitoring based on results.');
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
    required String bannerNote,
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
                            const Expanded(
                              child: Text(
                                'Risk Assessment',
                                style: TextStyle(
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
                          note: bannerNote,
                          riskColor: riskColor,
                        ),
                        const SizedBox(height: 16),
                        _buildRiskSection(
                          title: 'Current Risk Factors',
                          icon: isHigh
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline_rounded,
                          iconColor: riskColor,
                          children: currentRiskFactors.isEmpty
                              ? [
                                  _buildDetailRow(
                                    'No current risk factors identified',
                                    AppColors.success,
                                  ),
                                ]
                              : currentRiskFactors
                                  .map((finding) =>
                                      _buildDetailRow(finding, isHigh ? AppColors.error : AppColors.warning))
                                  .toList(),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBanner({
    required bool isHigh,
    required String note,
    required Color riskColor,
  }) {
    final Color bgColor = isHigh ? const Color(0xFFFFF3F0) : const Color(0xFFEBF7F5);
    final Color borderColor = isHigh ? const Color(0xFFFFAB91) : const Color(0xFFB2DFDB);
    final Color textColor = isHigh ? const Color(0xFFD84315) : const Color(0xFF00796B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
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
              isHigh ? Icons.gpp_maybe_rounded : Icons.check_circle_outline_rounded,
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
                  isHigh ? 'HIGH RISK' : 'LOW RISK',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: 0.4,
                  ),
                ),
                if (isHigh) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ],
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
