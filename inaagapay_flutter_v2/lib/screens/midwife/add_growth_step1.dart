// lib/screens/midwife/add_growth_step1.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/main_button.dart';
import '../../widgets/dialog_box.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/validation_message.dart';
import '../../services/growth_calculator.dart';
import '../../services/groq_service.dart';
import '../../widgets/profile_helpers.dart';
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';

class AddGrowthStep1 extends StatefulWidget {
  final int childId;

  const AddGrowthStep1({
    super.key,
    required this.childId,
  });

  @override
  State<AddGrowthStep1> createState() => _AddGrowthStep1State();
}

class _AddGrowthStep1State extends State<AddGrowthStep1> {
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _bmiController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  final TextEditingController _aiEnglishCtrl = TextEditingController();
  final TextEditingController _aiFilipinoCtrl = TextEditingController();

  Map<String, dynamic>? _childData;
  Map<String, dynamic>? _previousGrowth;
  List<Map<String, dynamic>> _growthRecords = [];
  DateTime? _birthdate;
  final GroqService _groqService = GroqService();
  String _savingStatus = 'Saving growth record...';

  int _step = 0;
  static const int _totalSteps = 1;

  String _aiOriginalEnglish = '';
  String _aiOriginalFilipino = '';

  String _backupEnglish = '';
  String _backupFilipino = '';

  bool _isEditingAi = false;
  bool _aiResponseApproved = false;
  String _selectedLanguage = 'filipino';

  bool _loading = true;
  int _ageInWeeks = 0;
  bool _hasBirthdate = false;
  String _gender = '';

  double? _weightZScore;
  double? _heightZScore;
  double? _bmiZScore;

  String _bmiCategoryText = 'Normal';
  Color _bmiCategoryColor = AppColors.textPrimary;

  bool _isFormValid = false;
  String? _validationMessage;
  ValidationType _validationMessageType = ValidationType.error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadChildData();
    _heightController.addListener(_onMeasurementChanged);
    _weightController.addListener(_onMeasurementChanged);
  }

  Future<void> _loadChildData() async {
    try {
      // First fetch child details
      final childResponse =
          await Supabase.instance.client.from('children').select('''
            child_id,
            first_name,
            last_name,
            sex
          ''').eq('child_id', widget.childId).single();

      // Then fetch birth details separately
      final birthDetailsResponse = await Supabase.instance.client
          .from('birth_details')
          .select('birthdate')
          .eq('child_id', widget.childId)
          .maybeSingle();

      final birthdate = birthDetailsResponse?['birthdate']?.toString();

      if (birthdate != null) {
        final birth = DateTime.parse(birthdate);
        _birthdate = birth;
        final now = DateTime.now();
        _ageInWeeks = (now.difference(birth).inDays / 7).floor();
        _hasBirthdate = true;
      }

      _gender = childResponse['sex']?.toString().toLowerCase() ?? '';

      final growthResponse = await Supabase.instance.client
          .from('child_growth_records')
          .select('*')
          .eq('child_id', widget.childId)
          .order('created_at', ascending: true);

      _growthRecords = List<Map<String, dynamic>>.from(growthResponse);
      _previousGrowth = _growthRecords.isNotEmpty ? _growthRecords.last : null;

      if (mounted) {
        setState(() {
          _childData = childResponse;
          _loading = false;
        });
      }

      // After loading, trigger an initial calculation if there are values
      _onMeasurementChanged();
    } catch (e) {
      debugPrint('Error loading child data: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading child data: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onMeasurementChanged() {
    _updateBMIAndStatus();
    _validateForm();
  }

  void _updateBMIAndStatus() {
    final double? heightCm = double.tryParse(_heightController.text);
    final double? weightKg = double.tryParse(_weightController.text);

    debugPrint('=== REAL-TIME BMI CALCULATION ===');
    debugPrint('Height: ${_heightController.text} cm');
    debugPrint('Weight: ${_weightController.text} kg');
    debugPrint('Age in weeks: $_ageInWeeks');
    debugPrint('Gender: $_gender');

    // Always recalculate height/weight z-scores so they never get stuck
    if (_hasBirthdate && _gender.isNotEmpty) {
      _heightZScore = heightCm != null && heightCm > 0
          ? GrowthCalculator.calculateHeightZScore(heightCm, _ageInWeeks, _gender)
          : null;
      _weightZScore = weightKg != null && weightKg > 0
          ? GrowthCalculator.calculateWeightZScore(weightKg, _ageInWeeks, _gender)
          : null;
    } else {
      _heightZScore = null;
      _weightZScore = null;
    }

    if (heightCm == null ||
        weightKg == null ||
        heightCm == 0 ||
        weightKg == 0) {
      debugPrint('Invalid height or weight, resetting BMI');
      setState(() {
        _bmiController.text = '';
        _bmiZScore = null;
        _bmiCategoryText = 'Normal';
        _bmiCategoryColor = AppColors.success;
      });
      return;
    }

    final double heightM = heightCm / 100;
    final double bmi = weightKg / (heightM * heightM);

    debugPrint('Calculated BMI: $bmi');

    setState(() {
      _bmiController.text = bmi.toStringAsFixed(1);
    });

    if (_hasBirthdate && _gender.isNotEmpty) {
      // Calculate BMI Z-score
      _bmiZScore =
          GrowthCalculator.calculateBMIZScore(bmi, _ageInWeeks, _gender);

      debugPrint('BMI Z-Score: $_bmiZScore');

      // Update status based on Z-score
      _updateBMICategory(_bmiZScore);
    } else {
      debugPrint(
          'Cannot calculate Z-score: Age in weeks=$_ageInWeeks, Gender=$_gender');
      setState(() {
        _bmiZScore = null;
        _bmiCategoryText = 'n/a';
        _bmiCategoryColor = AppColors.textSecondary;
      });
    }
  }

  void _updateBMICategory(double? zScore) {
    debugPrint('Updating BMI category for Z-Score: $zScore');

    setState(() {
      if (zScore == null) {
        _bmiCategoryText = 'n/a';
        _bmiCategoryColor = AppColors.textSecondary;
        debugPrint('Category: n/a (zScore is null)');
        return;
      }
      if (zScore < -1) {
        _bmiCategoryText = 'Slightly below standard range';
        _bmiCategoryColor = AppColors.warning;
        debugPrint('Category: Slightly below standard range (zScore < -1)');
      } else if (zScore <= 1) {
        _bmiCategoryText = 'Within expected standard range';
        _bmiCategoryColor = AppColors.success;
        debugPrint('Category: Within expected standard range (-1 <= zScore <= 1)');
      } else {
        _bmiCategoryText = 'Slightly above standard range';
        _bmiCategoryColor = AppColors.warning;
        debugPrint('Category: Slightly above standard range (zScore > 1)');
      }
    });
  }

  void _calculateZScores() {
    // Height and weight z-scores are now always calculated in _updateBMIAndStatus().
    // This method only handles the BMI z-score update from the form validation path.
    final double? bmi = double.tryParse(_bmiController.text);

    if (bmi != null && _hasBirthdate && _gender.isNotEmpty) {
      _bmiZScore =
          GrowthCalculator.calculateBMIZScore(bmi, _ageInWeeks, _gender);
      _updateBMICategory(_bmiZScore);
    }
  }

  void _validateForm() {
    if (_heightController.text.isEmpty || _weightController.text.isEmpty) {
      setState(() {
        _isFormValid = false;
        _validationMessage = null;
      });
      return;
    }

    final height = double.tryParse(_heightController.text);
    final weight = double.tryParse(_weightController.text);

    if (height == null || weight == null) {
      setState(() {
        _isFormValid = false;
        _validationMessageType = ValidationType.error;
        _validationMessage = 'Please enter valid numbers for height and weight.';
      });
      return;
    }

    if (height <= 0 || weight <= 0) {
      setState(() {
        _isFormValid = false;
        _validationMessageType = ValidationType.error;
        _validationMessage = 'Height and weight must be greater than zero.';
      });
      return;
    }

    if (height < 20 || height > 200) {
      setState(() {
        _isFormValid = false;
        _validationMessageType = ValidationType.error;
        _validationMessage = 'Height must be between 20 cm and 200 cm.';
      });
      return;
    }

    if (weight < 0.5 || weight > 120) {
      setState(() {
        _isFormValid = false;
        _validationMessageType = ValidationType.error;
        _validationMessage = 'Weight must be between 0.5 kg and 120 kg.';
      });
      return;
    }

    setState(() {
      _isFormValid = true;
      _validationMessage = null;
      _calculateZScores();
    });
  }

  double _calculateBMI(double heightCm, double weightKg) {
    if (heightCm <= 0 || weightKg <= 0) return 0;
    final heightM = heightCm / 100.0;
    return weightKg / (heightM * heightM);
  }

  int _ageInWeeksForDate(DateTime date) {
    if (!_hasBirthdate || _birthdate == null) return 0;
    final difference = date.difference(_birthdate!);
    return (difference.inDays / 7).round();
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
    required List<Map<String, dynamic>> allGrowthRecords,
  }) {
    final recordsSummary = allGrowthRecords.map((record) {
      final heightVal = (record['child_height'] as num?)?.toDouble() ?? 0;
      final weightVal = (record['child_weight'] as num?)?.toDouble() ?? 0;
      final bmiVal = _calculateBMI(heightVal, weightVal);
      final recordCreatedAt = record['created_at'] != null
          ? DateTime.parse(record['created_at'].toString())
          : DateTime.now();
      final weeks = _ageInWeeksForDate(recordCreatedAt);
      return '- Week $weeks: ${heightVal.toStringAsFixed(1)} cm, ${weightVal.toStringAsFixed(1)} kg, BMI ${bmiVal.toStringAsFixed(1)}';
    }).join('\n');

    String getStatus(double? z) {
      if (z == null || z.isNaN || z.isInfinite) return 'Within expected standard range';
      if (z < -1) return 'Slightly below standard range';
      if (z <= 1) return 'Within expected standard range';
      return 'Slightly above standard range';
    }

    final heightStatus = getStatus(heightZ);
    final weightStatus = getStatus(weightZ);
    final bmiStatus = getStatus(bmiZ);

    return '''
You are a warm, caring midwife assistant (like a loving ate or trusted midwife in a local health center) writing a short, gentle growth update for a parent.
Your tone must be gentle, comforting, and encouraging. Use simple, non-clinical language.
Do NOT use diagnostic terms or medical jargon (avoid terms like underweight, overweight, obesity, diagnosis, or clinical standard deviation).
Write EXACTLY 1 extremely short sentence of friendly, warm, non-diagnostic AI growth reassurance. Focus purely on comforting the parent and normalizing the child's growth.
Do NOT give any medical, dietary, lifestyle, or play suggestions (avoid suggestions like active play, sleep, feeding, or exercises).
Refer to the child by their first name or as "your little one" ("iyong munting anak" in Filipino) to make it personal and comforting.

Provide the response in both English and Filipino.
Use the exact output format below. Do not add extra sections, titles, bullet points, or tables.

Please carefully note the status indicators: "Within expected standard range", "Slightly above standard range", or "Slightly below standard range". 
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
Latest measurements: Length: ${height.toStringAsFixed(1)} cm ($heightStatus), Weight: ${weight.toStringAsFixed(1)} kg ($weightStatus), BMI: ${bmi.toStringAsFixed(1)} kg/m² ($bmiStatus)
Recent growth:
$recordsSummary
''';
  }

  void _splitPromptResponse(String text) {
    String english = '';
    String filipino = '';
    final normalized = text.replaceAll('\r\n', '\n');

    final englishRegex = RegExp(
      r'(?:^|\n)(?:#+\s*|\*+|\[)?English(?:#+\s*|\*+|\[)?:?\s*?\n([\s\S]*?)(?=(?:^|\n)(?:#+\s*|\*+|\[)?(?:Filipino|Tagalog)(?:#+\s*|\*+|\[)?:?|$)',
      caseSensitive: false,
    );
    final filipinoRegex = RegExp(
      r'(?:^|\n)(?:#+\s*|\*+|\[)?(?:Filipino|Tagalog)(?:#+\s*|\*+|\[)?:?\s*?\n([\s\S]*?)(?=(?:^|\n)(?:#+\s*|\*+|\[)?English(?:#+\s*|\*+|\[)?:?|$)',
      caseSensitive: false,
    );

    final englishMatch = englishRegex.firstMatch(normalized);
    final filipinoMatch = filipinoRegex.firstMatch(normalized);

    if (englishMatch != null) {
      english = englishMatch.group(1)?.trim() ?? '';
    }
    if (filipinoMatch != null) {
      filipino = filipinoMatch.group(1)?.trim() ?? '';
    }

    if (english.isEmpty && filipino.isEmpty) {
      english = normalized.trim();
      filipino = normalized.trim();
    } else if (english.isEmpty) {
      english = filipino;
    } else if (filipino.isEmpty) {
      filipino = english;
    }

    _aiEnglishCtrl.text = english;
    _aiFilipinoCtrl.text = filipino;
    _aiOriginalEnglish = english;
    _aiOriginalFilipino = filipino;
  }

  Future<void> _generateAIInsight() async {
    setState(() {
      _isSaving = true;
      _savingStatus = 'Generating AI growth analysis...';
    });

    try {
      final height = double.parse(_heightController.text);
      final weight = double.parse(_weightController.text);
      final bmi = double.parse(_bmiController.text);
      final childName =
          '${_childData?['first_name'] ?? ''} ${_childData?['last_name'] ?? ''}'
              .trim();
      final sex = _gender;

      final heightZ =
          GrowthCalculator.calculateHeightZScore(height, _ageInWeeks, sex);
      final weightZ =
          GrowthCalculator.calculateWeightZScore(weight, _ageInWeeks, sex);
      final bmiZ = GrowthCalculator.calculateBMIZScore(bmi, _ageInWeeks, sex);

      final tempNewRecord = {
        'child_height': height,
        'child_weight': weight,
        'created_at': DateTime.now().toIso8601String(),
      };
      final allRecords = [..._growthRecords, tempNewRecord];

      final prompt = _buildGrowthAiPrompt(
        childName: childName,
        sex: sex,
        ageWeeks: _ageInWeeks,
        height: height,
        weight: weight,
        bmi: bmi,
        heightZ: heightZ,
        weightZ: weightZ,
        bmiZ: bmiZ,
        allGrowthRecords: allRecords,
      );

      final generated = await _groqService.generateTextInsight(
        prompt: prompt,
        systemPrompt: GroqService.childGrowthSystemPrompt,
        temperature: 0.2,
        maxOutputTokens: 2048,
      );

      final responseText = generated.trim();
      _splitPromptResponse(responseText);

      setState(() {
        _isSaving = false;
        _aiResponseApproved = false;
        _step = 1;
      });
    } catch (e) {
      debugPrint('Error generating AI analysis: $e');

      final height = double.parse(_heightController.text);
      final weight = double.parse(_weightController.text);
      final childName =
          '${_childData?['first_name'] ?? ''} ${_childData?['last_name'] ?? ''}'
              .trim();
      final fallbackResponse = '''
## English
## Baby Growth Summary
- We are currently unable to generate a detailed AI summary for $childName, but we are actively tracking their growth details.

### Current Measurements
- Length: ${height.toStringAsFixed(1)} cm
- Weight: ${weight.toStringAsFixed(1)} kg

### What This Means
- Please consult your local health worker or midwife to review the length and weight measurements of your child.

### Helpful Note
- Every baby grows at their own pace. Continue providing loving care and nutrition.

## Filipino
## Buod ng Paglaki ng Bata
- Sa kasalukuyan ay hindi natin makagawa ng detalyadong AI summary para kay $childName, ngunit patuloy nating sinusubaybayan ang kanilang paglaki.

### Kasalukuyang Sukat
- Haba: ${height.toStringAsFixed(1)} cm
- Timbang: ${weight.toStringAsFixed(1)} kg

### Ano ang Kahulugan Nito
- Mangyaring kumonsulta sa inyong midwife o tagapangalaga ng kalusugan upang suriin ang haba at timbang ng inyong anak.

### Paalala
- Ang bawat sanggol ay lumalaki sa sarili nilang bilis. Ipagpatuloy ang mapagkalingang pag-aalaga at natrisyon.
''';

      _splitPromptResponse(fallbackResponse);

      setState(() {
        _isSaving = false;
        _aiResponseApproved = false;
        _step = 1;
      });
    }
  }

  Future<int?> _saveGrowthRecord() async {
    try {
      final height = double.parse(_heightController.text);
      final weight = double.parse(_weightController.text);

      int? midwifeId;
      try {
        final accountId = await AuthStorage.getUserId();
        if (accountId != null) {
          final ctx = await SupabaseService.getMidwifeContext(accountId);
          midwifeId = ctx['midwife_id'] as int?;
        }
      } catch (e) {
        debugPrint('Error getting midwife ID: $e');
      }

      final insertResult = await Supabase.instance.client.from('child_growth_records').insert({
        'child_id': widget.childId,
        'child_height': height,
        'child_weight': weight,
        'created_at': DateTime.now().toIso8601String(),
        if (midwifeId != null) 'recorded_by_midwife_id': midwifeId,
      }).select('child_details_id').single();

      return insertResult['child_details_id'] as int;
    } catch (e) {
      debugPrint('Error saving growth record: $e');
      return null;
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return DialogBox(
          type: DialogType.error,
          title: 'Save Failed',
          content: message,
          buttonText: 'OK',
          onPressed: () => Navigator.pop(context),
        );
      },
    );
  }

  void _submit() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return ConfirmationDialogBox(
          title: 'Confirm Growth Record',
          subtitle:
              'Please make sure the details are correct. Growth records cannot be edited once added.',
          confirmText: 'Confirm',
          cancelText: 'Cancel',
          onCancel: () => Navigator.pop(context, false),
          onConfirm: () => Navigator.pop(context, true),
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isSaving = true;
      _savingStatus = 'Saving growth record...';
    });

    try {
      final childDetailsId = await _saveGrowthRecord();

      if (childDetailsId != null) {
        final height = double.parse(_heightController.text);
        final weight = double.parse(_weightController.text);
        final bmi = double.parse(_bmiController.text);
        final sex = _gender;

        final heightZ =
            GrowthCalculator.calculateHeightZScore(height, _ageInWeeks, sex);
        final weightZ =
            GrowthCalculator.calculateWeightZScore(weight, _ageInWeeks, sex);
        final bmiZ = GrowthCalculator.calculateBMIZScore(bmi, _ageInWeeks, sex);

        final bmiDesc = _describeZScore(bmiZ);
        final weightDesc = _describeZScore(weightZ);
        final heightDesc = _describeZScore(heightZ);

        final bmiDescFil = _describeZScoreFilipino(bmiZ);
        final weightDescFil = _describeZScoreFilipino(weightZ);
        final heightDescFil = _describeZScoreFilipino(heightZ);

        final englishText = 'Full WHO-Based Evaluation at Week $_ageInWeeks. The child\'s Weight is $weightDesc and BMI-for-Age is $bmiDesc. Height-for-Age is $heightDesc.';
        final filipinoText = 'Buong Pagsusuri base sa WHO sa Ika-$_ageInWeeks na Linggo. Ang Timbang ng bata ay $weightDescFil at ang BMI ay $bmiDescFil. Ang Haba ay $heightDescFil.';
        final combinedText = '## English\n$englishText\n\n## Filipino\n$filipinoText';

        final values = {
          'reference_table': 'child_growth_records',
          'reference_id': childDetailsId,
          'response_type': 'growth_analysis',
          'response_category': 'growth',
          'generated_by_ai': false,
          'ai_model': 'none',
          'status': 'generated',
          'response': combinedText,
          'updated_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        };

        await Supabase.instance.client.from('ai_responses').insert(values);

        // Fire-and-forget background AI analysis
        _runBackgroundAiAnalysis(childDetailsId);

        setState(() => _isSaving = false);

        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        setState(() => _isSaving = false);
        _showErrorDialog('Failed to save growth record. Please try again.');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      _showErrorDialog('Unexpected error: $e');
    }
  }

  String _describeZScore(double? zScore) {
    if (zScore == null) return 'Within expected standard range';
    if (zScore < -1) return 'Slightly below standard range';
    if (zScore <= 1) return 'Within expected standard range';
    return 'Slightly above standard range';
  }

  String _describeZScoreFilipino(double? zScore) {
    if (zScore == null) return 'naaayon sa inaasahang pamantayan';
    if (zScore < -1) return 'medyo mababa sa pamantayan';
    if (zScore <= 1) return 'naaayon sa inaasahang pamantayan';
    return 'medyo mataas sa pamantayan';
  }

  void _runBackgroundAiAnalysis(int childDetailsId) async {
    try {
      final height = double.parse(_heightController.text);
      final weight = double.parse(_weightController.text);
      final bmi = double.parse(_bmiController.text);
      final childName =
          '${_childData?['first_name'] ?? ''} ${_childData?['last_name'] ?? ''}'
              .trim();
      final sex = _gender;

      final heightZ =
          GrowthCalculator.calculateHeightZScore(height, _ageInWeeks, sex);
      final weightZ =
          GrowthCalculator.calculateWeightZScore(weight, _ageInWeeks, sex);
      final bmiZ = GrowthCalculator.calculateBMIZScore(bmi, _ageInWeeks, sex);

      final tempNewRecord = {
        'child_height': height,
        'child_weight': weight,
        'created_at': DateTime.now().toIso8601String(),
      };
      final allRecords = [..._growthRecords, tempNewRecord];

      final prompt = _buildGrowthAiPrompt(
        childName: childName,
        sex: sex,
        ageWeeks: _ageInWeeks,
        height: height,
        weight: weight,
        bmi: bmi,
        heightZ: heightZ,
        weightZ: weightZ,
        bmiZ: bmiZ,
        allGrowthRecords: allRecords,
      );

      final generated = await _groqService.generateTextInsight(
        prompt: prompt,
        systemPrompt: GroqService.childGrowthSystemPrompt,
        temperature: 0.2,
        maxOutputTokens: 2048,
      );

      final responseText = generated.trim();
      if (responseText.isNotEmpty) {
        await Supabase.instance.client
            .from('ai_responses')
            .update({
              'response': responseText,
              'generated_by_ai': true,
              'ai_model': 'groq',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('reference_table', 'child_growth_records')
            .eq('reference_id', childDetailsId)
            .eq('response_type', 'growth_analysis');
      }
    } catch (e) {
      debugPrint('Error in background growth AI analysis: $e');
    }
  }

  String _growthStatusDescription(String metric, double? zScore) {
    if (zScore == null) {
      return '$metric status unavailable';
    }
    if (zScore < -5 || zScore > 5) {
      return '$metric is outside the possible range';
    }
    if (zScore < -2) {
      return '$metric is below the expected range';
    }
    if (zScore < -1) {
      return '$metric is slightly below the expected range';
    }
    if (zScore <= 1) {
      return '$metric is within the expected range';
    }
    if (zScore <= 2) {
      return '$metric is slightly above the expected range';
    }
    return '$metric is above the expected range';
  }

  Color _zScoreColor(double? zScore) {
    if (zScore == null) return AppColors.textSecondary;
    if (zScore < -2 || zScore > 2) return AppColors.error;
    if (zScore < -1 || zScore > 1) return AppColors.warning;
    return AppColors.success;
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
              Text('• Within expected standard range (Green): between -1 and +1 Z-score.', style: TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600)),
              Text('• Slightly below standard range (Yellow): less than -1 Z-score.', style: TextStyle(fontSize: 13, color: AppColors.warning, fontWeight: FontWeight.w600)),
              Text('• Slightly above standard range (Yellow): greater than +1 Z-score.', style: TextStyle(fontSize: 13, color: AppColors.warning, fontWeight: FontWeight.w600)),
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

  String? _calculatePreviousBMI() {
    if (_previousGrowth == null) return null;
    final prevHeight =
        (_previousGrowth!['child_height'] as num?)?.toDouble() ?? 0;
    final prevWeight =
        (_previousGrowth!['child_weight'] as num?)?.toDouble() ?? 0;
    if (prevHeight <= 0 || prevWeight <= 0) return null;
    final prevHeightM = prevHeight / 100.0;
    final prevBmi = prevWeight / (prevHeightM * prevHeightM);
    return prevBmi.toStringAsFixed(1);
  }

  String _formatDate(String date) {
    try {
      final parsed = DateTime.parse(date);
      return DateFormat('MMM d, yyyy').format(parsed);
    } catch (_) {
      return date;
    }
  }

  String? _getBmiExplanation() {
    if (_bmiZScore == null || _bmiController.text.isEmpty) return null;

    final double? heightCm = double.tryParse(_heightController.text);
    final double? weightKg = double.tryParse(_weightController.text);
    if (heightCm == null || weightKg == null || heightCm <= 0 || weightKg <= 0) return null;

    final String status = _bmiCategoryText;

    if (status == 'Slightly below standard range') {
      if (_weightZScore != null && _weightZScore! < -1 && _heightZScore != null && _heightZScore! > 1) {
        return 'Both the child\'s weight is slightly below expected range and height is slightly above expected range, contributing to the lower BMI.';
      }
      if (_weightZScore != null && _weightZScore! < -1) {
        return 'The child\'s weight is slightly below the standard range for their age, contributing to the lower BMI.';
      }
      if (_heightZScore != null && _heightZScore! > 1) {
        return 'The child\'s height is slightly above the standard range for their age, which contributes to a lower BMI relative to their frame.';
      }
      if (_weightZScore != null && _weightZScore! >= -1 && _heightZScore != null && _heightZScore! <= 1) {
        return 'Although the child\'s height and weight are both individually within expected ranges, the weight is on the lower side relative to their height, resulting in a slightly lower BMI.';
      }
      return 'The child\'s weight is lower than typical for their height at this age, resulting in a lower BMI.';
    } else if (status == 'Slightly above standard range') {
      if (_weightZScore != null && _weightZScore! > 1 && _heightZScore != null && _heightZScore! < -1) {
        return 'Both the child\'s weight is slightly above expected range and height is slightly below expected range, contributing to the higher BMI.';
      }
      if (_weightZScore != null && _weightZScore! > 1) {
        return 'The child\'s weight is slightly above the standard range for their age, contributing to the higher BMI.';
      }
      if (_heightZScore != null && _heightZScore! < -1) {
        return 'The child\'s height is slightly below the standard range for their age, which contributes to a higher BMI relative to their frame.';
      }
      if (_weightZScore != null && _weightZScore! <= 1 && _heightZScore != null && _heightZScore! >= -1) {
        return 'Although the child\'s height and weight are both individually within expected ranges, the weight is on the higher side relative to their height, resulting in a slightly higher BMI.';
      }
      return 'The child\'s weight is higher than typical for their height at this age, resulting in a higher BMI.';
    } else if (status == 'Within expected standard range') {
      return 'The child\'s height and weight are both within the expected standard range for this age, resulting in a healthy BMI.';
    }
    return null;
  }

  @override
  void dispose() {
    _heightController.removeListener(_onMeasurementChanged);
    _weightController.removeListener(_onMeasurementChanged);
    _heightController.dispose();
    _weightController.dispose();
    _bmiController.dispose();
    _remarksController.dispose();
    _aiEnglishCtrl.dispose();
    _aiFilipinoCtrl.dispose();
    super.dispose();
  }

  Widget _stepTitle() {
    const labels = [
      'Growth Record',
      'AI Growth Review',
    ];
    const subtitles = [
      'Enter the child\'s height and weight measurements',
      'Review and approve the AI growth summary before saving',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            labels[_step],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.brandText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitles[_step],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    if (_step == 0) {
      return _buildStep0();
    }
    return _buildStep1();
  }

  Widget _buildStep0() {
    final childName =
        '${_childData?['first_name'] ?? ''} ${_childData?['last_name'] ?? ''}'
            .trim();
    final ageText = '$_ageInWeeks weeks old';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // Child Info Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _gender == 'female'
                    ? Colors.pink.shade100
                    : Colors.blue.shade100,
                child: Text(
                  childName.isNotEmpty ? childName[0].toUpperCase() : 'C',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _gender == 'female' ? Colors.pink : Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      childName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      ageText,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Height Input
        AppInputField(
          hintText: 'Height (cm)',
          controller: _heightController,
          leadingIcon: Icons.height,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
          ],
          onChanged: (_) => _onMeasurementChanged(),
          isRequired: true,
        ),

        if (_previousGrowth != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              'Previous height: ${(_previousGrowth!['child_height'] as num?)?.toStringAsFixed(1) ?? 'n/a'} cm • ${_formatDate(_previousGrowth!['created_at']?.toString() ?? '')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],



        const SizedBox(height: 16),

        // Weight Input
        AppInputField(
          hintText: 'Weight (kg)',
          controller: _weightController,
          leadingIcon: Icons.monitor_weight,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
          ],
          onChanged: (_) => _onMeasurementChanged(),
          isRequired: true,
        ),

        if (_previousGrowth != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              'Previous weight: ${(_previousGrowth!['child_weight'] as num?)?.toStringAsFixed(1) ?? 'n/a'} kg • ${_formatDate(_previousGrowth!['created_at']?.toString() ?? '')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],



        const SizedBox(height: 16),

        // BMI Display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.brandPrimary.withValues(alpha: 0.3),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.calculate,
                    color: AppColors.brandPrimary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          _bmiController.text.isEmpty
                              ? 'BMI: ---'
                              : 'BMI: ${_bmiController.text}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _bmiController.text.isEmpty
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
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
                    ),
                  ),
                  if (_bmiController.text.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _bmiCategoryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _bmiCategoryText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _bmiCategoryColor,
                        ),
                      ),
                    ),
                ],
              ),
              if (_bmiZScore != null && _bmiController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _growthStatusDescription('BMI', _bmiZScore),
                    style: TextStyle(
                      fontSize: 11,
                      color: _bmiCategoryColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                if (_getBmiExplanation() != null) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: _bmiCategoryColor.withValues(alpha: 0.2)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _getBmiExplanation()!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _bmiCategoryColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        if (_previousGrowth != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              'Previous BMI: ${_calculatePreviousBMI() ?? 'n/a'} • ${_formatDate(_previousGrowth!['created_at']?.toString() ?? '')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.borderPrimary.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(
                Icons.help_outline,
                size: 18,
                color: AppColors.textSecondary,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Measurement guide: enter height in cm and weight in kg. Use the child\'s age range to choose realistic values and double-check the measuring tool if numbers seem unusual.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.textSecondary.withValues(alpha: 0.22),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(
                    Icons.notes_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Remarks (optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remarksController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Add optional notes to describe the measurement context',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 0),
                ),
                style: TextStyle(
                  color: AppColors.textPrimary.withValues(alpha: 0.85),
                  fontSize: 15,
                ),
                cursorColor: AppColors.brandPrimary,
              ),
            ],
          ),
        ),

        if (_validationMessage != null) ...[
          const SizedBox(height: 12),
          ValidationMessage(
            message: _validationMessage!,
            type: _validationMessageType,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStep1() {
    final activeInsight = _selectedLanguage == 'filipino'
        ? _aiFilipinoCtrl.text.trim()
        : _aiEnglishCtrl.text.trim();

    final content = activeInsight.isEmpty
        ? (_selectedLanguage == 'filipino'
            ? 'Kamusta mommy? Ang pag-analisa sa paglaki ng bata ay magsisimula sa sandaling makuha ang AI assessment...'
            : 'The care insight will appear here once generated...')
        : activeInsight;

    final lineCount = '\n'.allMatches(content).length + 1;
    final editorLines = (lineCount + 2).clamp(5, 18);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // A. Mother-Facing Info Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.brandPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.15)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(
                Icons.info_outline,
                color: AppColors.brandPrimary,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This Care Insight is what the parent will see on their mobile app. It is written in a warm, reassuring tone to guide and support them.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.inputText,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Main Card
        Container(
          width: double.infinity,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderPrimary),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.08),
                  border: const Border(
                      bottom: BorderSide(color: AppColors.borderPrimary)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: AppColors.brandPrimary, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Growth Insight for Parent',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _generateAIInsight,
                      child: const Icon(Icons.refresh_rounded,
                          size: 18, color: AppColors.brandPrimary),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Language Toggle
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.bgSecondary,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: AppColors.borderPrimary, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedLanguage = 'filipino';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _selectedLanguage == 'filipino'
                                      ? AppColors.brandPrimary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Filipino (Conversational)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _selectedLanguage == 'filipino'
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: _selectedLanguage == 'filipino'
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedLanguage = 'english';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _selectedLanguage == 'english'
                                      ? AppColors.brandPrimary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'English',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _selectedLanguage == 'english'
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: _selectedLanguage == 'english'
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // AI Insight Text
                    if (!_isEditingAi)
                      buildFormattedAiText(content)
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.faintWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderPrimary),
                        ),
                        child: TextField(
                          key: ValueKey(_selectedLanguage),
                          controller: _selectedLanguage == 'filipino'
                              ? _aiFilipinoCtrl
                              : _aiEnglishCtrl,
                          minLines: editorLines,
                          maxLines: editorLines,
                          decoration: InputDecoration(
                            hintText: _selectedLanguage == 'filipino'
                                ? 'Isulat ang growth message para sa magulang (Filipino)...'
                                : 'Write the growth message for the parent (English)...',
                            hintStyle: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(14),
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.inputText,
                            height: 1.65,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Action Buttons
        if (_isEditingAi) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _aiFilipinoCtrl.text = _backupFilipino;
                      _aiEnglishCtrl.text = _backupEnglish;
                      _isEditingAi = false;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.borderPrimary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () {
                    final nextFilText = _aiFilipinoCtrl.text.trim();
                    final nextEngText = _aiEnglishCtrl.text.trim();
                    if (nextFilText.isEmpty || nextEngText.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Both Filipino and English insights are required.')),
                      );
                      return;
                    }
                    setState(() {
                      _aiResponseApproved = false;
                      _isEditingAi = false;
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ] else if (_aiResponseApproved) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Growth insight approved! This insight is ready and will be saved when you submit.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.success,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _aiResponseApproved = false;
                    });
                  },
                  child: const Text(
                    'Re-edit',
                    style: TextStyle(
                      color: AppColors.brandPrimary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (content.isEmpty || activeInsight.isEmpty)
                      ? null
                      : () {
                          setState(() {
                            _aiResponseApproved = true;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Insight approved! You can now save the growth record.')),
                          );
                        },
                  icon:
                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Approve Care Insight'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _backupFilipino = _aiFilipinoCtrl.text;
                          _backupEnglish = _aiEnglishCtrl.text;
                          _isEditingAi = true;
                          _aiResponseApproved = false;
                        });
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit Insight'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.borderPrimary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.brandPrimary,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Add Growth Record',
          onBack: () {
            if (_step > 0 && !_isSaving) {
              setState(() {
                _isEditingAi = false;
                _step = 0;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: _isSaving
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppColors.brandPrimary),
                    const SizedBox(height: 20),
                    Text(
                      _savingStatus,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  LinearProgressIndicator(
                    value: (_step + 1) / _totalSteps,
                    backgroundColor: AppColors.borderPrimary,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
                    minHeight: 3,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _stepTitle(),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildStepContent(),
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: _isSaving
          ? null
          : Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 14,
                    offset: const Offset(0, -4))
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: MainButton(
                          label: 'Save Growth Record',
                          rightIcon: Icons.check_rounded,
                          onPressed: _isFormValid ? _submit : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
