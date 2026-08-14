// lib/screens/midwife/child_growth_list_page.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/growth_calculator.dart';
import '../../services/groq_service.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/growth_summary_card.dart';
import '../../widgets/hero_card.dart';

/// Data class representing a reference curve for growth charts
class ReferenceCurve {
  final String label;
  final List<FlSpot> spots;
  final Color color;
  final double strokeWidth;
  final List<int>? dashArray;

  ReferenceCurve({
    required this.label,
    required this.spots,
    required this.color,
    required this.strokeWidth,
    this.dashArray,
  });
}

class ChildGrowthListPage extends StatefulWidget {
  final int childId;

  const ChildGrowthListPage({
    super.key,
    required this.childId,
  });

  @override
  State<ChildGrowthListPage> createState() => _ChildGrowthListPageState();
}

class _ChildGrowthListPageState extends State<ChildGrowthListPage> {
  bool loading = true;
  bool aiLoading = false;
  String? aiAnalysis;
  String? aiError;
  int activeTab = 0;
  List<Map<String, dynamic>> records = [];
  Map<String, dynamic>? childData;
  DateTime? birthdate;
  double? birthWeight;
  double? birthHeight;

  bool _showAiInFilipino = false;

  final GroqService _groqService = GroqService();

  // Computed properties for latest measurements
  Map<String, dynamic>? get latestRecord =>
      records.isNotEmpty ? records.last : null;

  double get latestHeight =>
      (latestRecord?['child_height'] as num?)?.toDouble() ?? 0;

  double get latestWeight =>
      (latestRecord?['child_weight'] as num?)?.toDouble() ?? 0;

  double get latestBMI => _calculateBMI(latestHeight, latestWeight);

  int get latestAgeWeeks => latestRecord != null
      ? _ageInWeeks(DateTime.parse(latestRecord!['created_at']))
      : 0;

  String get childSex => (childData?['sex'] as String?) ?? 'female';

  @override
  void initState() {
    super.initState();
    _showAiInFilipino = LanguageService.isFilipino;
    fetchGrowthRecords();
  }

  Future<void> fetchGrowthRecords() async {
    setState(() {
      loading = true;
      aiError = null;
    });

    try {
      await _fetchChildData();
      await _fetchBirthDetails();
      await _fetchGrowthRecords();

      final realRecords = records.where((r) => r['child_details_id'] != -1).toList();
      if (realRecords.isNotEmpty && birthdate != null) {
        final latestReal = realRecords.last;
        final latestId = (latestReal['child_details_id'] as int?) ?? 0;

        if (latestId > 0) {
          final saved = await _fetchSavedGrowthAnalysis(latestId);
          if (saved != null &&
              saved['response'] != null &&
              saved['response'].toString().isNotEmpty) {
            final savedText = saved['response'].toString().trim();
            final isGeneratedByAi = saved['generated_by_ai'] == true;
            final lower = savedText.toLowerCase();
            final isOldOrSingleLang = !lower.contains('english') ||
                !(lower.contains('filipino') || lower.contains('tagalog'));
            final isBulletFormat = savedText.contains('## Baby Growth Summary') ||
                savedText.contains('Buod ng Paglaki ng Bata');

            if (!isGeneratedByAi || isOldOrSingleLang || isBulletFormat) {
              await _generateAndSaveAIAnalysis(latestId);
            } else {
              aiAnalysis = savedText;
            }
          } else {
            await _generateAndSaveAIAnalysis(latestId);
          }
        } else {
          aiAnalysis =
              'Cannot generate AI growth summary because the latest record ID is unavailable.';
        }
      } else {
        aiAnalysis = 'Not enough growth data yet to generate an AI summary.';
      }
    } catch (e) {
      debugPrint('Error loading growth records: $e');
      if (mounted) {
        setState(() {
          aiError = e.toString();
          aiAnalysis = 'Unable to load growth data. Please try again.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading growth records: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _fetchChildData() async {
    final response = await Supabase.instance.client
        .from('children')
        .select('child_id, first_name, last_name, sex')
        .eq('child_id', widget.childId)
        .single();
    childData = response;
  }

  Future<void> _fetchBirthDetails() async {
    final response = await Supabase.instance.client
        .from('birth_details')
        .select('birthdate, birth_weight, birth_length')
        .eq('child_id', widget.childId)
        .maybeSingle();

    if (response != null) {
      if (response['birthdate'] != null) {
        birthdate = DateTime.parse(response['birthdate']);
      }
      birthWeight = (response['birth_weight'] as num?)?.toDouble();
      birthHeight = (response['birth_length'] as num?)?.toDouble();
    }
  }

  Future<void> _fetchGrowthRecords() async {
    final response = await Supabase.instance.client
        .from('child_growth_records')
        .select('*')
        .eq('child_id', widget.childId)
        .order('created_at', ascending: true);

    records = List<Map<String, dynamic>>.from(response);

    if (birthdate != null && birthWeight != null && birthWeight! > 0 && birthHeight != null && birthHeight! > 0) {
      final birthRecord = {
        'child_details_id': -1, // Synthetic ID for chart purposes
        'child_id': widget.childId,
        'child_height': birthHeight,
        'child_weight': birthWeight,
        'created_at': birthdate!.toIso8601String(),
      };
      records.insert(0, birthRecord);
    }
  }

  Future<Map<String, dynamic>?> _fetchSavedGrowthAnalysis(
      int childDetailsId) async {
    return await Supabase.instance.client
        .from('ai_responses')
        .select('*')
        .eq('reference_table', 'child_growth_records')
        .eq('reference_id', childDetailsId)
        .eq('response_type', 'growth_analysis')
        .maybeSingle();
  }

  Future<void> _generateAndSaveAIAnalysis(int latestRecordId) async {
    if (records.isEmpty || birthdate == null || childData == null) return;
    if (latestRecordId <= 0) return;

    setState(() => aiLoading = true);

    try {
      final heightZ = GrowthCalculator.calculateHeightZScore(
          latestHeight, latestAgeWeeks, childSex);
      final weightZ = GrowthCalculator.calculateWeightZScore(
          latestWeight, latestAgeWeeks, childSex);
      final bmiZ = GrowthCalculator.calculateBMIZScore(
          latestBMI, latestAgeWeeks, childSex);

      final prompt = _buildGrowthAiPrompt(
        childName: getChildName(),
        sex: childSex,
        ageWeeks: latestAgeWeeks,
        height: latestHeight,
        weight: latestWeight,
        bmi: latestBMI,
        heightZ: heightZ,
        weightZ: weightZ,
        bmiZ: bmiZ,
      );

      final generated = await _groqService.generateTextInsight(
        prompt: prompt,
        systemPrompt: GroqService.childGrowthSystemPrompt,
        temperature: 0.2,
        maxOutputTokens: 2048,
      );

      final analysis = generated.trim();
      if (mounted) {
        setState(() => aiAnalysis = analysis);
      }
      await _saveAIResponse(analysis, latestRecordId);
    } catch (e) {
      debugPrint('Error generating AI analysis: $e');
      if (mounted) {
        setState(() {
          aiError = 'AI analysis unavailable';
          aiAnalysis = 'AI analysis could not be generated right now.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => aiLoading = false);
      }
    }
  }

  String _buildGrowthAiPrompt({
    required String childName,
    required String sex,
    required int ageWeeks,
    required double height,
    required double weight,
    required double bmi,
    required double? heightZ,
    required double? weightZ,
    required double? bmiZ,
  }) {
    final recordsSummary = records.map((record) {
      final weightVal = (record['child_weight'] as num?)?.toDouble() ?? 0;
      final heightVal = (record['child_height'] as num?)?.toDouble() ?? 0;
      final bmiVal = _calculateBMI(heightVal, weightVal);
      final weeks = _ageInWeeks(DateTime.parse(record['created_at']));
      return '- Week $weeks: ${heightVal.toStringAsFixed(1)} cm, ${weightVal.toStringAsFixed(1)} kg, BMI ${bmiVal.toStringAsFixed(1)}';
    }).join('\n');

    return '''
You are a warm, caring midwife assistant (like a loving ate or trusted midwife in a local health center) writing a short, gentle growth update for a parent.
Your tone must be gentle, comforting, and encouraging. Use simple, non-clinical language.
Do NOT use diagnostic terms or medical jargon (avoid terms like underweight, overweight, obesity, diagnosis, or clinical standard deviation).
Write EXACTLY 1 extremely short sentence of friendly, warm, non-diagnostic AI growth reassurance. Focus purely on comforting the parent and normalizing the child's growth.
Do NOT give any medical, dietary, lifestyle, or play suggestions (avoid suggestions like active play, sleep, feeding, or exercises).
Refer to the child by their first name or as "your little one" ("iyong munting anak" in Filipino) to make it personal and comforting.

Provide the response in both English and Filipino.
Use the exact output format below. Do not add extra sections, titles, bullet points, or tables.

Please carefully note the status indicators: "Within standard range", "Above standard range", or "Below standard range".
- If any measurement is slightly above standard range, reassure the parent warmly and concisely (e.g. "Baby [Name] is growing well! Even though it seems like [his/her] [weight/height/BMI] is a bit higher than most babies [his/her] age, [he/she]'s gaining steadily and will catch up!").
- If any measurement is slightly below standard range, reassure them warmly and concisely (e.g. "Baby [Name] is growing well! Even though [his/her] [weight/height/BMI] is a bit lower than most babies [his/her] age, [he/she]'s growing steadily and will catch up at [his/her] own pace!").
- If everything is within expected range, celebrate their steady growth concisely (e.g. "Baby [Name] is doing great! [His/Her] growth is right on track, and [he/she] is growing steadily and beautifully!").

Output format:

## English
[Write exactly 1 sentence of friendly, warm, non-diagnostic AI growth reassurance here]

## Filipino
[Write exactly 1 sentence of friendly, warm, non-diagnostic AI growth reassurance in Tagalog here]

Child: $childName
Sex: ${sex.toLowerCase()}
Current age: $ageWeeks weeks
Latest measurements: Length: ${height.toStringAsFixed(1)} cm (${_getZStatus(heightZ)}), Weight: ${weight.toStringAsFixed(1)} kg (${_getZStatus(weightZ)}), BMI: ${bmi.toStringAsFixed(1)} kg/m² (${_getZStatus(bmiZ)})
Recent growth:
$recordsSummary
''';
  }

  String _getZStatus(double? z) {
    return GrowthCalculator.bandLabel(z);
  }

  Future<void> _saveAIResponse(String responseText, int childDetailsId) async {
    try {
      final existing = await Supabase.instance.client
          .from('ai_responses')
          .select('ai_response_id')
          .eq('reference_table', 'child_growth_records')
          .eq('reference_id', childDetailsId)
          .eq('response_type', 'growth_analysis')
          .maybeSingle();

      final values = {
        'reference_table': 'child_growth_records',
        'reference_id': childDetailsId,
        'response_type': 'growth_analysis',
        'response_category': 'growth',
        'generated_by_ai': true,
        'ai_model': 'groq',
        'status': 'generated',
        'response': responseText,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existing != null && existing['ai_response_id'] != null) {
        await Supabase.instance.client
            .from('ai_responses')
            .update(values)
            .eq('ai_response_id', existing['ai_response_id']);
      } else {
        values['created_at'] = DateTime.now().toIso8601String();
        await Supabase.instance.client.from('ai_responses').insert(values);
      }
    } catch (e) {
      debugPrint('Error saving AI response: $e');
    }
  }

  String getChildName() {
    if (childData == null) return 'Child';
    final firstName = childData!['first_name'] ?? '';
    final lastName = childData!['last_name'] ?? '';
    return '$firstName $lastName'.trim();
  }

  String calculateAge() {
    if (birthdate == null) return 'Age unknown';

    final now = DateTime.now();
    int years = now.year - birthdate!.year;
    int months = now.month - birthdate!.month;
    int days = now.day - birthdate!.day;

    if (days < 0) {
      months -= 1;
      final prevMonthDate = DateTime(now.year, now.month, 0);
      days += prevMonthDate.day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }

    if (years > 0) {
      final monthPart = months > 0 ? ', $months month${months != 1 ? 's' : ''}' : '';
      return '$years year${years != 1 ? 's' : ''}$monthPart old';
    } else if (months > 0) {
      final weeks = days ~/ 7;
      final weekPart = weeks > 0 ? ', $weeks week${weeks != 1 ? 's' : ''}' : '';
      return '$months month${months != 1 ? 's' : ''}$weekPart old';
    } else {
      if (days >= 7) {
        final weeks = days ~/ 7;
        final remainingDays = days % 7;
        final dayPart = remainingDays > 0 ? ', $remainingDays day${remainingDays != 1 ? 's' : ''}' : '';
        return '$weeks week${weeks != 1 ? 's' : ''}$dayPart old';
      } else if (days > 0) {
        return '$days day${days != 1 ? 's' : ''} old';
      } else {
        return 'Newborn';
      }
    }
  }

  String formatDate(String? date) {
    if (date == null || date.isEmpty) return 'No date';
    try {
      final parsed = DateTime.parse(date);
      return DateFormat('MMM d, yyyy').format(parsed);
    } catch (_) {
      return date;
    }
  }

  int _ageInWeeks(DateTime recordDate) {
    if (birthdate == null) return 0;
    final difference = recordDate.difference(birthdate!);
    return (difference.inDays / 7).round();
  }

  double _calculateBMI(double heightCm, double weightKg) {
    if (heightCm <= 0 || weightKg <= 0) return 0;
    final heightM = heightCm / 100.0;
    return weightKg / (heightM * heightM);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Growth Records',
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: fetchGrowthRecords,
          color: AppColors.brandPrimary,
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.brandPrimary,
                  ),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: records.isEmpty
                      ? _buildEmptyState()
                      : _buildContent(),
                ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.child_care,
                size: 64,
                color: AppColors.brandPrimary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Growth Records Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Growth measurements for ${getChildName()} will appear here once recorded.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// GrowthSummaryCard derives its own values, labels and reference bands from
  /// the measurement list, so this body only supplies records and chrome.
  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        HeroCard(
          image: null,
          title: getChildName(),
          subtitle: calculateAge(),
          sex: childSex,
          showWeekBadge: false,
          showHeartRow: false,
        ),
        const SizedBox(height: 14),
        // One card for all three indicators. The previous three tabs presented
        // three findings derived from two measurements, which made the midwife
        // assemble the picture herself and let the wording drift apart.
        GrowthSummaryCard(
          childFirstName: (childData?['first_name'] as String?) ?? '',
          sex: childSex,
          measurements: _growthMeasurements(),
          isFilipino: _showAiInFilipino,
          // AI narrative is written for a parent, so it stays on the mother app.
          // The midwife sees the rule-based summary instead.
        ),
        const SizedBox(height: 24),
        _buildHistorySection(),
      ],
    );
  }
  /// Growth records mapped into the shared card's input, oldest first.
  List<GrowthMeasurement> _growthMeasurements() {
    final out = <GrowthMeasurement>[];
    for (final record in records) {
      final height = (record['child_height'] as num?)?.toDouble();
      final weight = (record['child_weight'] as num?)?.toDouble();
      final createdAt = record['created_at']?.toString();
      if (height == null || weight == null || createdAt == null) continue;
      if (height <= 0 || weight <= 0) continue;

      final takenAt = DateTime.parse(createdAt);
      out.add(GrowthMeasurement(
        takenAt: takenAt,
        heightCm: height,
        weightKg: weight,
        ageWeeks: _ageInWeeks(takenAt),
      ));
    }
    return out;
  }

  Widget _buildHistorySection() {
    final historyRecords = records.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.history,
                color: AppColors.brandPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Growth History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${records.length} record${records.length != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (historyRecords.isEmpty)
          const Center(
            child: Text(
              'No growth measurements available yet.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          )
        else
          ...historyRecords.map((record) {
            final height = (record['child_height'] as num?)?.toDouble() ?? 0;
            final weight = (record['child_weight'] as num?)?.toDouble() ?? 0;
            final date = record['created_at']?.toString() ?? '';
            final weeks = _ageInWeeks(DateTime.parse(date));
            final isLatest = record == records.last;
            final bmi = _calculateBMI(height, weight);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildHistoryRecordCard(
                height: height,
                weight: weight,
                bmi: bmi,
                date: formatDate(date),
                weekNumber: weeks,
                isLatest: isLatest,
              ),
            );
          }),
      ],
    );
  }

  Widget _buildHistoryRecordCard({
    required double height,
    required double weight,
    required double bmi,
    required String date,
    required int weekNumber,
    required bool isLatest,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isLatest
            ? Border.all(
                color: AppColors.brandPrimary.withValues(alpha: 0.3),
                width: 1.5,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Week $weekNumber',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLatest)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Latest',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (activeTab == 0) ...[
            Row(
              children: [
                Expanded(
                  child: _buildMeasurementItem(
                    'Height',
                    '${height.toStringAsFixed(1)} cm',
                    Icons.height,
                    AppColors.brandPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMeasurementItem(
                    'Weight',
                    '${weight.toStringAsFixed(1)} kg',
                    Icons.monitor_weight,
                    AppColors.brandAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.brandText.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.brandText.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.straighten, size: 18, color: AppColors.brandText),
                  const SizedBox(width: 8),
                  Text(
                    'Calculated BMI',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandText,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    bmi > 0 ? bmi.toStringAsFixed(1) : 'n/a',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (activeTab == 1) ...[
            _buildMeasurementItem(
              'Weight',
              '${weight.toStringAsFixed(1)} kg',
              Icons.monitor_weight,
              AppColors.brandAccent,
            ),
          ] else if (activeTab == 2) ...[
            _buildMeasurementItem(
              'Height',
              '${height.toStringAsFixed(1)} cm',
              Icons.height,
              AppColors.brandPrimary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMeasurementItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
