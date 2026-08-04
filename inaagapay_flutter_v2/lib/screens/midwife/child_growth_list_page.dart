// lib/screens/midwife/child_growth_list_page.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/growth_calculator.dart';
import '../../services/growth_reference_data.dart';
import '../../services/groq_service.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/chart_card.dart';
import '../../widgets/secondary_header.dart';
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

  String _getAiTextForLanguage(String? fullText) {
    if (fullText == null || fullText.trim().isEmpty) return '';
    final normalized = fullText.replaceAll('\r\n', '\n');

    final englishMatch = RegExp(
      r'(?:===|##)\s*English\s*(?:===)?\s*([\s\S]*?)(?=(?:===|##)\s*Filipino\s*(?:===)?|$)',
      caseSensitive: false,
    ).firstMatch(normalized);
    
    final filipinoMatch = RegExp(
      r'(?:===|##)\s*Filipino\s*(?:===)?\s*([\s\S]*?)(?=(?:===|##)\s*English\s*(?:===)?|$)',
      caseSensitive: false,
    ).firstMatch(normalized);

    final englishText = englishMatch?.group(1)?.trim();
    final filipinoText = filipinoMatch?.group(1)?.trim();

    // If no language sections found, return full text
    if (englishText == null && filipinoText == null) return fullText;

    if (_showAiInFilipino) {
      return filipinoText ?? englishText ?? fullText;
    }
    return englishText ?? filipinoText ?? fullText;
  }

  String _getSectionForTab(String langText, int tabIndex) {
    final normalized = langText.replaceAll('\r\n', '\n');
    final sectionHeader = tabIndex == 0 ? 'BMI' : tabIndex == 1 ? 'Weight' : 'Height';

    final regex = RegExp(
      r'(?:^|\n)(?:#+\s*|\*+|\[)?' + RegExp.escape(sectionHeader) + r'(?:#+\s*|\*+|\])?:?\s*\n([\s\S]*?)(?=(?:^|\n)(?:#+\s*|\*+|\[)?(?:BMI|Weight|Height)(?:#+\s*|\*+|\])?:?|$)',
      caseSensitive: false,
    );

    final match = regex.firstMatch(normalized);
    if (match != null) {
      return match.group(1)?.trim() ?? '';
    }

    return langText.trim();
  }

  Widget _buildToggleBtn(String label, bool selected, Color activeColor) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showAiInFilipino = label == 'Filipino';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: selected ? activeColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
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

  String _bmiCategory(double bmi) {
    return GrowthCalculator.bandLabel(
      GrowthCalculator.calculateBMIZScore(bmi, latestAgeWeeks, childSex),
    );
  }

  Color _bmiCategoryColor(String category) {
    switch (category) {
      case 'Below standard range':
        return Colors.orange; // Yellow/Orange
      case 'Within standard range':
        return AppColors.success; // Green
      case 'Above standard range':
        return Colors.orange; // Yellow/Orange
      default:
        return AppColors.textSecondary;
    }
  }

  void _showReferenceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.info_outline, color: AppColors.brandPrimary),
            SizedBox(width: 8),
            Text('Growth Reference'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Our growth indicators are based on the World Health Organization (WHO) Child Growth Standards.',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 12),
              Text(
                'Z-scores compare a child\'s measurements (BMI-for-age, weight-for-age, height-for-age) to expected values for healthy growth:',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 8),
              Text('• Within standard range (Green): between -2 and +2 Z-score.', style: TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600)),
              Text('• Below standard range (Yellow): less than -2 Z-score.', style: TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w600)),
              Text('• Above standard range (Yellow): greater than +2 Z-score.', style: TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _describeZScore(double? zscore) {
    if (zscore == null || zscore.isNaN || zscore.isInfinite) {
      return 'Status unavailable';
    }
    return GrowthCalculator.bandLabel(zscore);
  }

  Color _zScoreColor(double? zScore) {
    if (zScore == null) return AppColors.textSecondary;
    if (!GrowthCalculator.bandForZScore(zScore).isWithin) return Colors.orange; // Yellow/Orange
    return AppColors.success; // Green
  }

  // FIXED: Properly filter and validate chart values
  List<double> _getChartValues(String metric) {
    final List<double> values = [];

    for (final record in records) {
      double value;
      switch (metric) {
        case 'height':
          value = (record['child_height'] as num?)?.toDouble() ?? 0;
          break;
        case 'weight':
          value = (record['child_weight'] as num?)?.toDouble() ?? 0;
          break;
        case 'bmi':
          final h = (record['child_height'] as num?)?.toDouble() ?? 0;
          final w = (record['child_weight'] as num?)?.toDouble() ?? 0;
          if (h <= 0 || w <= 0) {
            continue; // Skip invalid measurements
          }
          value = _calculateBMI(h, w);
          if (value <= 0 || value.isNaN || value.isInfinite) {
            continue; // Skip invalid BMI
          }
          break;
        default:
          continue;
      }

      if (value > 0) {
        values.add(value);
      }
    }

    return values;
  }

  // FIXED: Properly filter and validate chart labels to match values
  List<String> _getChartLabels(String metric) {
    final labels = <String>[];
    final weekCount = <String, int>{};

    for (final record in records) {
      double value;
      switch (metric) {
        case 'height':
          value = (record['child_height'] as num?)?.toDouble() ?? 0;
          break;
        case 'weight':
          value = (record['child_weight'] as num?)?.toDouble() ?? 0;
          break;
        case 'bmi':
          final h = (record['child_height'] as num?)?.toDouble() ?? 0;
          final w = (record['child_weight'] as num?)?.toDouble() ?? 0;
          if (h <= 0 || w <= 0) {
            continue; // Skip invalid measurements
          }
          value = _calculateBMI(h, w);
          if (value <= 0 || value.isNaN || value.isInfinite) {
            continue; // Skip invalid BMI
          }
          break;
        default:
          continue;
      }

      if (value <= 0) continue;

      final recordDate = DateTime.parse(record['created_at']);
      final weeks = _ageInWeeks(recordDate);
      final baseLabel = 'W$weeks';
      final count = (weekCount[baseLabel] ?? 0) + 1;
      weekCount[baseLabel] = count;

      if (count == 1) {
        labels.add(baseLabel);
      } else {
        labels.add(DateFormat('M/d').format(recordDate));
      }
    }

    return labels;
  }

  /// Builds WHO reference curves for the given [metric] ('weight' or 'height')
  /// aligned to the same index-based x-coordinates as the child data points.
  List<ReferenceCurve> _buildWhoCurves(
    String metric,
    String sex,
    List<Map<String, dynamic>> validRecords,
  ) {
    final isBoy = sex.toLowerCase() == 'male';

    // Select the correct weekly dataset
    List<Map<String, dynamic>> weeklyData;
    List<Map<String, dynamic>>? monthlyData;

    if (metric == 'weight') {
      weeklyData = isBoy
          ? GrowthReferenceData.weightBoysData
          : GrowthReferenceData.weightGirlsData;
      monthlyData = isBoy
          ? GrowthReferenceData.weightBoysMonthlyData
          : GrowthReferenceData.weightGirlsMonthlyData;
    } else {
      // height
      weeklyData = isBoy
          ? GrowthReferenceData.heightBoysData
          : GrowthReferenceData.heightGirlsData;
      monthlyData = null; // no monthly height data available
    }

    // For each SD line, collect spots at matching x-indices
    final medianSpots = <FlSpot>[];
    final sd2negSpots = <FlSpot>[];
    final sd2posSpots = <FlSpot>[];
    final sd3negSpots = <FlSpot>[];
    final sd3posSpots = <FlSpot>[];

    for (int i = 0; i < validRecords.length; i++) {
      final record = validRecords[i];
      final recordDate = DateTime.parse(record['created_at']);
      final ageWeeks = _ageInWeeks(recordDate);

      Map<String, dynamic>? refEntry;

      if (ageWeeks <= 13) {
        // Use weekly data
        refEntry = weeklyData.cast<Map<String, dynamic>?>().firstWhere(
              (e) => e!['week'] == ageWeeks,
              orElse: () => null,
            );
      } else if (monthlyData != null) {
        // Convert weeks to months and look up monthly data
        final ageMonths = (ageWeeks / 4.345).round();
        refEntry = monthlyData.cast<Map<String, dynamic>?>().firstWhere(
              (e) => e!['month'] == ageMonths,
              orElse: () => null,
            );
      }

      if (refEntry == null) continue;

      final x = i.toDouble();
      medianSpots.add(FlSpot(x, (refEntry['sd0'] as num).toDouble()));
      sd2negSpots.add(FlSpot(x, (refEntry['sd2neg'] as num).toDouble()));
      sd2posSpots.add(FlSpot(x, (refEntry['sd2'] as num).toDouble()));
      sd3negSpots.add(FlSpot(x, (refEntry['sd3neg'] as num).toDouble()));
      sd3posSpots.add(FlSpot(x, (refEntry['sd3'] as num).toDouble()));
    }

    // Only return curves that have at least 2 points (needed to draw a line)
    final curves = <ReferenceCurve>[];

    if (medianSpots.length >= 2) {
      curves.add(ReferenceCurve(
        label: 'Median',
        spots: medianSpots,
        color: Colors.green.withValues(alpha: 0.4),
        strokeWidth: 1.2,
      ));
    }
    if (sd2negSpots.length >= 2) {
      curves.add(ReferenceCurve(
        label: '-2 SD',
        spots: sd2negSpots,
        color: Colors.orange.withValues(alpha: 0.4),
        strokeWidth: 1.0,
        dashArray: [6, 4],
      ));
    }
    if (sd2posSpots.length >= 2) {
      curves.add(ReferenceCurve(
        label: '+2 SD',
        spots: sd2posSpots,
        color: Colors.orange.withValues(alpha: 0.4),
        strokeWidth: 1.0,
        dashArray: [6, 4],
      ));
    }
    if (sd3negSpots.length >= 2) {
      curves.add(ReferenceCurve(
        label: '-3 SD',
        spots: sd3negSpots,
        color: Colors.red.withValues(alpha: 0.3),
        strokeWidth: 1.0,
        dashArray: [4, 4],
      ));
    }
    if (sd3posSpots.length >= 2) {
      curves.add(ReferenceCurve(
        label: '+3 SD',
        spots: sd3posSpots,
        color: Colors.red.withValues(alpha: 0.3),
        strokeWidth: 1.0,
        dashArray: [4, 4],
      ));
    }

    return curves;
  }

  /// Returns the subset of records that have valid values for the given metric,
  /// in the same order as _getChartValues / _getChartLabels would produce.
  List<Map<String, dynamic>> _getValidRecords(String metric) {
    final valid = <Map<String, dynamic>>[];
    for (final record in records) {
      switch (metric) {
        case 'height':
          final v = (record['child_height'] as num?)?.toDouble() ?? 0;
          if (v > 0) valid.add(record);
          break;
        case 'weight':
          final v = (record['child_weight'] as num?)?.toDouble() ?? 0;
          if (v > 0) valid.add(record);
          break;
        default:
          break;
      }
    }
    return valid;
  }

  @override
  Widget build(BuildContext context) {
    final heightZ = GrowthCalculator.calculateHeightZScore(
        latestHeight, latestAgeWeeks, childSex);
    final weightZ = GrowthCalculator.calculateWeightZScore(
        latestWeight, latestAgeWeeks, childSex);
    final bmiZ = GrowthCalculator.calculateBMIZScore(
        latestBMI, latestAgeWeeks, childSex);

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
                      : _buildContent(
                          heightZ: heightZ,
                          weightZ: weightZ,
                          bmiZ: bmiZ,
                        ),
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

  Widget _buildContent({
    required double? heightZ,
    required double? weightZ,
    required double? bmiZ,
  }) {
    final heightValues = _getChartValues('height');
    final heightLabels = _getChartLabels('height');
    final weightValues = _getChartValues('weight');
    final weightLabels = _getChartLabels('weight');
    final bmiValues = _getChartValues('bmi');
    final bmiLabels = _getChartLabels('bmi');

    // Build WHO reference curves for weight and height
    final weightWhoCurves = weightValues.length >= 2
        ? _buildWhoCurves('weight', childSex, _getValidRecords('weight'))
        : <ReferenceCurve>[];
    final heightWhoCurves = heightValues.length >= 2
        ? _buildWhoCurves('height', childSex, _getValidRecords('height'))
        : <ReferenceCurve>[];

    // Debug output to verify data
    debugPrint('BMI Values: $bmiValues');
    debugPrint('BMI Labels: $bmiLabels');
    debugPrint('Height Values: $heightValues');
    debugPrint('Weight Values: $weightValues');

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
        _buildTabBar(),
        const SizedBox(height: 14),
        _buildMetricCard(
          label: 'BMI',
          value: latestBMI > 0 ? latestBMI.toStringAsFixed(1) : 'n/a',
          zScore: bmiZ,
          bmiValue: latestBMI > 0 ? latestBMI : null,
          icon: Icons.straighten,
          color: AppColors.brandText,
          show: activeTab == 0,
        ),
        _buildMetricCard(
          label: 'Weight',
          value: latestWeight > 0
              ? '${latestWeight.toStringAsFixed(1)} kg'
              : 'n/a',
          zScore: weightZ,
          icon: Icons.monitor_weight,
          color: AppColors.brandAccent,
          show: activeTab == 1,
        ),
        _buildMetricCard(
          label: 'Height',
          value: latestHeight > 0
              ? '${latestHeight.toStringAsFixed(1)} cm'
              : 'n/a',
          zScore: heightZ,
          icon: Icons.height,
          color: AppColors.brandPrimary,
          show: activeTab == 2,
        ),
        // BMI Chart
        if (activeTab == 0 &&
            bmiValues.length >= 2 &&
            bmiLabels.length >= 2 &&
            bmiValues.length == bmiLabels.length)
          ChartCard(
            title: 'BMI History',
            lineColor: AppColors.brandPrimary,
            values: bmiValues,
            labels: bmiLabels,
            unit: 'kg/m²',
            startingLabel: 'First',
            startingValue: bmiValues.first.toStringAsFixed(1),
            latestLabel: 'Latest',
            latestValue: latestBMI > 0 ? latestBMI.toStringAsFixed(1) : 'n/a',
            insightText: 'BMI trend indicates body composition changes.',
          ),
        if (activeTab == 0 && bmiValues.length < 2)
          _buildInsufficientDataMessage('BMI'),

        // Weight Chart
        if (activeTab == 1 &&
            weightValues.length >= 2 &&
            weightLabels.length >= 2 &&
            weightValues.length == weightLabels.length)
          ChartCard(
            title: 'Weight History',
            lineColor: AppColors.brandAccent,
            values: weightValues,
            labels: weightLabels,
            unit: 'kg',
            referenceCurves: weightWhoCurves,
            startingLabel: 'First',
            startingValue: '${weightValues.first.toStringAsFixed(1)} kg',
            latestLabel: 'Latest',
            latestValue: '${latestWeight.toStringAsFixed(1)} kg',
            insightText:
                'Weight tracking provides insight into nutritional status.',
          ),
        if (activeTab == 1 && weightValues.length < 2)
          _buildInsufficientDataMessage('Weight'),

        // Height Chart
        if (activeTab == 2 &&
            heightValues.length >= 2 &&
            heightLabels.length >= 2 &&
            heightValues.length == heightLabels.length)
          ChartCard(
            title: 'Height History',
            lineColor: AppColors.brandPrimary,
            values: heightValues,
            labels: heightLabels,
            unit: 'cm',
            referenceCurves: heightWhoCurves,
            startingLabel: 'First',
            startingValue: '${heightValues.first.toStringAsFixed(1)} cm',
            latestLabel: 'Latest',
            latestValue: '${latestHeight.toStringAsFixed(1)} cm',
            insightText:
                'Weekly height measurements showing growth pattern over time.',
          ),
        if (activeTab == 2 && heightValues.length < 2)
          _buildInsufficientDataMessage('Height'),
        const SizedBox(height: 20),
        _buildCustomInsightCard(
          heightZ: heightZ,
          weightZ: weightZ,
          bmiZ: bmiZ,
        ),
        _buildDisclaimerAndReferences(),
        const SizedBox(height: 24),
        _buildHistorySection(),
      ],
    );
  }

  Widget _buildTabBar() {
    final tabs = ['BMI', 'Weight', 'Height'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isActive = activeTab == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => activeTab = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.brandPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color:
                                AppColors.brandPrimary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    tabs[index],
                    style: TextStyle(
                      color: isActive ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required double? zScore,
    double? bmiValue,
    required IconData icon,
    required Color color,
    required bool show,
  }) {
    if (!show) return const SizedBox.shrink();

    final zScoreDesc = _describeZScore(zScore);
    final bmiCategory =
        label == 'BMI' && bmiValue != null ? _bmiCategory(bmiValue) : null;
    final bmiCategoryColor =
        bmiCategory != null ? _bmiCategoryColor(bmiCategory) : null;

    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
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
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  '$label Summary',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (label == 'BMI') ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _showReferenceDialog,
                    child: const Icon(
                      Icons.help_outline_rounded,
                      color: AppColors.textSecondary,
                      size: 16,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            if (bmiCategory != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bmiCategoryColor!.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    bmiCategory,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: bmiCategoryColor,
                    ),
                  ),
                ),
              ),
            ],
            if (label != 'BMI') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _zScoreColor(zScore).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        zScoreDesc,
                        style: TextStyle(
                          fontSize: 13,
                          color: _zScoreColor(zScore),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'This is a guide, not a diagnosis. Mild differences may be normal.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsufficientDataMessage(String metric) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              color: AppColors.textSecondary.withValues(alpha: 0.6), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Not enough data for $metric chart (need at least 2 measurements)',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerAndReferences() {
    final isFilipino = LanguageService.isFilipino;

    final disclaimerText = isFilipino
        ? 'Paalala: Ang AI-assisted growth insight na ito ay gabay lamang para sa pagsubaybay at hindi pamalit sa propesyonal na konsultasyong medikal.'
        : 'Note: This AI-assisted growth insight is intended only for monitoring support and does not replace professional medical consultation.';
    final referenceText = isFilipino
        ? 'Sanggunian: Batay sa World Health Organization (WHO) Child Growth Standards.'
        : 'Reference: Based on the World Health Organization (WHO) Child Growth Standards.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.borderPrimary,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.textSecondary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  disclaimerText,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  referenceText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomInsightCard({
    required double? heightZ,
    required double? weightZ,
    required double? bmiZ,
  }) {
    final isFilipino = LanguageService.isFilipino;
    
    // Choose styling color based on tab
    final activeColor = activeTab == 0
        ? AppColors.brandText
        : activeTab == 1
            ? AppColors.brandAccent
            : AppColors.brandPrimary;

    final headerText = activeTab == 0
        ? (isFilipino ? 'PAGSURI NG BMI' : 'BMI INSIGHT')
        : activeTab == 1
            ? (isFilipino ? 'PAGSURI NG TIMBANG' : 'WEIGHT INSIGHT')
            : (isFilipino ? 'PAGSURI NG TANGKAD' : 'HEIGHT INSIGHT');

    // Get the display text: if AI analysis is loaded and valid, use it; otherwise fall back to local rule-based text
    String displayText = '';
    bool hasAi = aiAnalysis != null && aiAnalysis!.trim().isNotEmpty;
    
    if (hasAi) {
      final langText = _getAiTextForLanguage(aiAnalysis);
      displayText = _getSectionForTab(langText, activeTab);
    } else {
      // Fallback local calculations
      if (activeTab == 0) {
        // BMI
        final z = bmiZ;
        if (z == null || z.isNaN || z.isInfinite) {
          displayText = isFilipino
              ? 'Hindi sapat ang datos para sa pagsusuri ng BMI.'
              : 'Insufficient data for BMI analysis.';
        } else if (GrowthCalculator.bandForZScore(z) == GrowthBand.below) {
          displayText = isFilipino
              ? 'Ang BMI ng iyong anak ay mas mababa sa standard range para sa kaniyang edad. Ibig sabihin, medyo mababa ang timbang niya kumpara sa kaniyang tangkad, na karaniwang nangyayari kapag napaka-aktibo ng bata o mabilis na tumatangkad.'
              : "Your child's BMI is below the standard range for their age. This means their weight is relatively low compared to their height, which is common during active phases or rapid growth spurts.";
        } else if (GrowthCalculator.bandForZScore(z).isWithin) {
          displayText = isFilipino
              ? 'Ang BMI ng iyong anak ay nasa loob ng standard range para sa kaniyang edad. Nagpapakita ito ng malusog at balanseng ugnayan sa pagitan ng kaniyang tangkad at timbang habang patuloy siyang lumalaki.'
              : "Your child's BMI is within the standard range for their age. This indicates a healthy, balanced relationship between their height and weight as they continue to grow.";
        } else {
          displayText = isFilipino
              ? 'Ang BMI ng iyong anak ay mas mataas sa standard range para sa kaniyang edad. Ibig sabihin, medyo mas mabigat siya kumpara sa kaniyang tangkad, na maaaring bahagi ng kaniyang normal na paglaki o hubog ng katawan.'
              : "Your child's BMI is above the standard range for their age. This means their weight is a bit higher relative to their height, which can be a temporary phase or natural body build variation.";
        }
      } else if (activeTab == 1) {
        // Weight
        final z = weightZ;
        if (z == null || z.isNaN || z.isInfinite) {
          displayText = isFilipino
              ? 'Hindi sapat ang datos para sa pagsusuri ng timbang.'
              : 'Insufficient data for weight analysis.';
        } else if (GrowthCalculator.bandForZScore(z) == GrowthBand.below) {
          displayText = isFilipino
              ? 'Ang timbang ng iyong anak ay mas mababa sa standard range para sa kaniyang edad. Ipinapakita nito na medyo mas magaan siya kaysa sa karaniwan, na maaaring dahil sa kaniyang pagiging aktibo o mabilis na paglaki.'
              : "Your child's weight is below the standard range for their age. This suggests they are a bit lighter than average, which can happen if they are highly active or during a growth spurt.";
        } else if (GrowthCalculator.bandForZScore(z).isWithin) {
          displayText = isFilipino
              ? 'Ang timbang ng iyong anak ay nasa loob ng standard range para sa kaniyang edad. Isang magandang senyales ito na sapat ang kaniyang nutrisyon at patuloy siyang lumalaki nang malusog.'
              : "Your child's weight is within the standard range for their age. This is a wonderful sign that they are receiving good nourishment and gaining weight steadily.";
        } else {
          displayText = isFilipino
              ? 'Ang timbang ng iyong anak ay mas mataas sa standard range para sa kaniyang edad. Ipinapakita nito na medyo mas mabigat siya kaysa sa karaniwan, na maaaring dahil sa kaniyang natural na pangangatawan.'
              : "Your child's weight is above the standard range for their age. This indicates they are a bit heavier than average for their age, which can be due to their natural body frame.";
        }
      } else {
        // Height
        final z = heightZ;
        if (z == null || z.isNaN || z.isInfinite) {
          displayText = isFilipino
              ? 'Hindi sapat ang datos para sa pagsusuri ng tangkad.'
              : 'Insufficient data for height analysis.';
        } else if (GrowthCalculator.bandForZScore(z) == GrowthBand.below) {
          displayText = isFilipino
              ? 'Ang tangkad ng iyong anak ay mas mababa sa standard range para sa kaniyang edad. Ibig sabihin, medyo mas mababa siya kaysa sa karaniwan, na madalas ay dulot ng henetika o sariling takbo ng kaniyang paglaki.'
              : "Your child's height is below the standard range for their age. This means they are a bit shorter than average, which is often influenced by genetics or individual growth timing.";
        } else if (GrowthCalculator.bandForZScore(z).isWithin) {
          displayText = isFilipino
              ? 'Ang tangkad ng iyong anak ay nasa loob ng standard range para sa kaniyang edad. Ipinapakita nito na maganda at tuloy-tuloy ang kaniyang pagtangkad sa malusog na pamamaraan.'
              : "Your child's height is within the standard range for their age. This shows they are stretching up and growing beautifully at a steady, healthy pace.";
        } else {
          displayText = isFilipino
              ? 'Ang tangkad ng iyong anak ay mas mataas sa standard range para sa kaniyang edad. Ibig sabihin, mas matangkad siya kaysa sa karaniwan, na nagpapakita ng magandang paglaki ng kaniyang mga buto at katawan.'
              : "Your child's height is above the standard range for their age. This indicates they are taller than average for their age, showing active bone development and growth.";
        }
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: activeColor.withValues(alpha: 0.15),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      activeTab == 0
                          ? Icons.straighten
                          : activeTab == 1
                              ? Icons.monitor_weight
                              : Icons.height,
                      color: activeColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    headerText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: activeColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (hasAi) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 10, color: activeColor),
                          const SizedBox(width: 3),
                          Text(
                            'AI',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: activeColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              // Render the language toggle buttons if AI analysis is present
              if (hasAi)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToggleBtn('English', !_showAiInFilipino, activeColor),
                    const SizedBox(width: 4),
                    _buildToggleBtn('Filipino', _showAiInFilipino, activeColor),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (aiLoading)
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: activeColor,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  isFilipino ? 'Ginagawa ang AI insight...' : 'Generating AI insight...',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            )
          else
            Text(
              displayText,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                height: 1.45,
              ),
            ),
        ],
      ),
    );
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
