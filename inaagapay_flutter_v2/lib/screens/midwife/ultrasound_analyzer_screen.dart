// lib/screens/midwife/ultrasound_analyzer_screen.dart

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/groq_service.dart';
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';
import '../../services/ultrasound_interpretation_engine.dart';
import '../../models/groq_response.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/main_button.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/confirmation_dialog_box.dart';

class UltrasoundAnalyzerScreen extends StatefulWidget {
  final int motherId;
  final int pregnancyId;

  const UltrasoundAnalyzerScreen({
    super.key,
    required this.motherId,
    required this.pregnancyId,
  });

  @override
  State<UltrasoundAnalyzerScreen> createState() =>
      _UltrasoundAnalyzerScreenState();
}

class _UltrasoundAnalyzerScreenState extends State<UltrasoundAnalyzerScreen> {
  final ImagePicker _picker = ImagePicker();
  final GroqService _groqService = GroqService();
  final DateFormat _dateFormat = DateFormat('MMMM d, yyyy');

  final List<XFile> _selectedImages = [];
  GroqResponse? _combinedResponse;
  bool _isSaving = false;
  String? _errorMessage;

  int _step = 0;
  static const int _totalSteps = 3;
  static const List<String> _stepTitles = [
    'Ultrasound Details',
    'Attach Images and Notes',
    'Assessment & Clinical Review',
  ];
  static const List<String> _stepSubtitles = [
    'Set the date and enter optional health worker details.',
    'Attach ultrasound images and add optional clinical notes.',
    'Review AI-assisted analysis and override risk factors if necessary.',
  ];
  bool _analysisApproved = false;
  bool _aiAnalysisSkipped = false;
  bool _showAdvancedAiDetails = false;
  bool _loadingOverlayVisible = false;
  String _loadingTitle = 'Preparing your explanation';
  String _loadingDetail = 'Validating images and input context';
  int _analysisRunId = 0;
  final Set<int> _cancelledRunIds = <int>{};
  final Set<String> _expandedAspects = <String>{};
  String? _lastAiPrompt;

  // Trimester-aware monitoring classification (computed by UltrasoundInterpretationEngine)
  // Reference: INTERGROWTH-21st (Papageorghiou et al., Lancet 2014);
  //            WHO Fetal Growth Charts (Kiserud et al., PLOS Medicine 2017)
  MonitoringClassification _monitoringClassification =
      MonitoringClassification.withinExpectedRange;

  final TextEditingController _notesController = TextEditingController();

  late TextEditingController _healthSummaryController;
  bool _isEditing = false;
  bool _isManualEditing = false;
  String _healthSummaryBeforeEdit = '';

  bool _editMonitoringRange = true;
  DateTime? _motherBirthdate;
  late TextEditingController _editPregnancySummaryController;
  late TextEditingController _editBabyGrowthIntroController;
  String _editBabyGrowthIntro = '';
  List<({String testName, String value, String status, String remark})>
      _editBabyGrowthMeasurements = [];
  List<TextEditingController> _editBabyGrowthValueControllers = [];
  List<TextEditingController> _editBabyGrowthRemarkControllers = [];
  late TextEditingController _editKeyObservationsController;
  late TextEditingController _editNextStepsController;
  bool _showDetailedUltrasoundValues = false;

  DateTime? _ultrasoundDate;
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _healthWorkerNameController =
      TextEditingController();
  final TextEditingController _healthWorkerInstitutionController =
      TextEditingController();
  final TextEditingController _healthWorkerProfessionController =
      TextEditingController();
  String? _selectedHealthWorkerProfession;

  late int _motherId;
  late int _pregnancyId;
  String _motherName = '';
  DateTime? _pregnancyLmp;
  DateTime? _pregnancyEdd;
  bool _datesUpdated = false;
  String _pregnancyRiskLevel = 'low';
  String _activeRiskTab = 'pregnancy';
  String _selectedLanguage = 'filipino';
  List<String> _maternalActiveConditions = [];
  List<String> _maternalAllergies = [];
  double? _maternalHeight;
  double? _maternalPrePregWeight;
  int? _pregnancyFetalCount;

  final List<String> _uploadedImageUrls = [];

  static const List<String> _ultrasoundProfessions = [
    'Radiologist',
    'Sonographer',
    'OB-GYN',
    'Midwife',
    'Other (specify)',
  ];
  static const String _otherProfessionOption = 'Other (specify)';

  @override
  void initState() {
    super.initState();
    _healthSummaryController = TextEditingController();
    _editPregnancySummaryController = TextEditingController();
    _editBabyGrowthIntroController = TextEditingController();
    _editKeyObservationsController = TextEditingController();
    _editNextStepsController = TextEditingController();

    _ultrasoundDate = DateTime.now();
    _dateController.text = _dateFormat.format(_ultrasoundDate!);

    _motherId = widget.motherId;
    _pregnancyId = widget.pregnancyId;
    _motherName = 'Mother #$_motherId';

    _loadUserContext();
    _loadMotherName();
    _loadPregnancyDetails();
  }

  @override
  void dispose() {
    _healthSummaryController.dispose();
    _editPregnancySummaryController.dispose();
    _editBabyGrowthIntroController.dispose();
    for (final ctrl in _editBabyGrowthValueControllers) {
      ctrl.dispose();
    }
    for (final ctrl in _editBabyGrowthRemarkControllers) {
      ctrl.dispose();
    }
    _editKeyObservationsController.dispose();
    _editNextStepsController.dispose();
    _notesController.dispose();
    _dateController.dispose();
    _healthWorkerNameController.dispose();
    _healthWorkerInstitutionController.dispose();
    _healthWorkerProfessionController.dispose();
    super.dispose();
  }

  void _showMessage(String message,
      {AppSnackType type = AppSnackType.warning}) {
    AppSnackbar.show(context, message, type: type);
  }

  Future<void> _loadUserContext() async {
    try {
      await AuthStorage.getUserRole();
    } catch (e) {
      if (kDebugMode) print('Error loading user context: $e');
    }
  }

  Future<void> _loadMotherName() async {
    try {
      final response = await Supabase.instance.client
          .from('mothers')
          .select('account:account_id (first_name, last_name)')
          .eq('mother_id', _motherId)
          .maybeSingle();

      if (response != null && response['account'] != null) {
        final account = response['account'] as Map<String, dynamic>;
        final first = account['first_name']?.toString() ?? '';
        final last = account['last_name']?.toString() ?? '';
        final full = '$first $last'.trim();
        if (mounted && full.isNotEmpty) {
          setState(() {
            _motherName = full;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error loading mother name: $e');
    }
  }

  Future<void> _loadPregnancyDetails() async {
    try {
      final response = await Supabase.instance.client
          .from('pregnancies')
          .select(
              'last_menstrual_period, expected_date_of_delivery, pregnancy_risk_level, fetal_count, pre_pregnancy_weight')
          .eq('pregnancy_id', _pregnancyId)
          .maybeSingle();

      if (response != null) {
        if (mounted) {
          setState(() {
            if (response['last_menstrual_period'] != null) {
              _pregnancyLmp =
                  DateTime.parse(response['last_menstrual_period'].toString());
            }
            if (response['expected_date_of_delivery'] != null) {
              _pregnancyEdd = DateTime.parse(
                  response['expected_date_of_delivery'].toString());
            }

            // Fallback back-calculations if one is missing but the other exists
            if (_pregnancyLmp == null && _pregnancyEdd != null) {
              _pregnancyLmp =
                  _pregnancyEdd!.subtract(const Duration(days: 280));
            }
            if (_pregnancyEdd == null && _pregnancyLmp != null) {
              _pregnancyEdd = _pregnancyLmp!.add(const Duration(days: 280));
            }

            if (response['pregnancy_risk_level'] != null) {
              _pregnancyRiskLevel =
                  response['pregnancy_risk_level'].toString().toLowerCase();
            }
            if (response['fetal_count'] != null) {
              _pregnancyFetalCount =
                  int.tryParse(response['fetal_count'].toString());
            }
            if (response['pre_pregnancy_weight'] != null) {
              _maternalPrePregWeight =
                  double.tryParse(response['pre_pregnancy_weight'].toString());
            }
          });
        }
      }

      // Load mother profile details (height, birthdate)
      final motherRes = await Supabase.instance.client
          .from('mothers')
          .select('height, birthdate')
          .eq('mother_id', _motherId)
          .maybeSingle();
      if (motherRes != null) {
        if (mounted) {
          setState(() {
            if (motherRes['height'] != null) {
              _maternalHeight = double.tryParse(motherRes['height'].toString());
            }
            if (motherRes['birthdate'] != null) {
              _motherBirthdate =
                  DateTime.parse(motherRes['birthdate'].toString());
            }
          });
        }
      }

      // Load active medical conditions
      final List conditionsRes = await Supabase.instance.client
          .from('medical_conditions')
          .select('condition_name')
          .eq('mother_id', _motherId)
          .eq('status', 'active');
      if (mounted) {
        setState(() {
          _maternalActiveConditions =
              conditionsRes.map((c) => c['condition_name'].toString()).toList();
        });
      }

      // Load allergies
      final List allergiesRes = await Supabase.instance.client
          .from('allergies')
          .select('allergen')
          .eq('mother_id', _motherId)
          .eq('status', 'active');
      if (mounted) {
        setState(() {
          _maternalAllergies =
              allergiesRes.map((a) => a['allergen'].toString()).toList();
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error loading pregnancy details: $e');
    }
  }

  int? _calculateExpectedWeeksAtUltrasound() {
    if (_pregnancyLmp != null && _ultrasoundDate != null) {
      final diffInDays = _ultrasoundDate!.difference(_pregnancyLmp!).inDays;
      if (diffInDays < 0) return 0;
      return (diffInDays / 7).floor();
    }
    if (_pregnancyEdd != null && _ultrasoundDate != null) {
      // EDD is 40 weeks (280 days) after LMP.
      // So expected gestational age = 40 weeks - (EDD - ultrasoundDate) in weeks.
      final diffToEdd = _pregnancyEdd!.difference(_ultrasoundDate!).inDays;
      final gestationalDays = 280 - diffToEdd;
      if (gestationalDays < 0) return 0;
      return (gestationalDays / 7).floor();
    }
    return null;
  }

  int? _calculateMaternalAge() {
    if (_motherBirthdate == null) return null;
    final today = DateTime.now();
    var age = today.year - _motherBirthdate!.year;
    if (today.month < _motherBirthdate!.month ||
        (today.month == _motherBirthdate!.month &&
            today.day < _motherBirthdate!.day)) {
      age--;
    }
    return age;
  }

  String _buildRuleBasedUltrasoundSummary({String? lang}) {
    final language = lang ?? _selectedLanguage;
    final aogWeeks = _calculateExpectedWeeksAtUltrasound() ?? 0;
    final trimesterLabel = aogWeeks <= 13
        ? 'First Trimester'
        : (aogWeeks <= 27 ? 'Second Trimester' : 'Third Trimester');
    final trimesterFil = aogWeeks <= 13
        ? 'Unang Trimester'
        : (aogWeeks <= 27 ? 'Ikalawang Trimester' : 'Ikatlong Trimester');
    final fetalCountLabel = _pregnancyFetalCount == null
        ? 'Singleton'
        : (_pregnancyFetalCount == 1
            ? 'Singleton'
            : '$_pregnancyFetalCount babies');
    final fetalCountFil = _pregnancyFetalCount == null
        ? 'Isa (Singleton)'
        : (_pregnancyFetalCount == 1
            ? 'Isa (Singleton)'
            : '$_pregnancyFetalCount sanggol');

    final riskLabelEn = _pregnancyRiskLevel == 'low' ? 'Low Risk' : 'High Risk';
    final riskLabelFil = _pregnancyRiskLevel == 'low'
        ? 'Mababa (Low Risk)'
        : 'Mataas (High Risk)';

    if (language == 'filipino') {
      return '''Kamusta, mommy! Sa iyong ultrasound record ngayon, naitala ang iyong edad ng pagbubuntis (AOG) sa $aogWeeks linggo ($trimesterFil) kasama ang $fetalCountFil. Ang iyong pangkalahatang pregnancy risk level ay $riskLabelFil. Iminumungkahi namin ang regular na pagsubaybay sa anatomical measurements at anatomical findings mula sa iyong ultrasound report upang masiguro ang malusog na paglaki ni baby. Ang patuloy na pagbisita sa iyong doktor o midwife ay makakatulong sa inyong kalusugan.''';
    } else {
      return '''Hello, Mommy! In your ultrasound record today, your gestational age is recorded at $aogWeeks weeks ($trimesterLabel) with a $fetalCountLabel fetus. Your overall pregnancy risk level is evaluated as $riskLabelEn. We recommend tracking baby's growth measurements and anatomical developments from your ultrasound report to ensure healthy progression. Continued prenatal checkups and consultations are highly recommended.''';
    }
  }

  int? _extractWeeksFromAiText(String? ageText) {
    if (ageText == null || ageText.isEmpty) return null;

    // 1. Explicitly check for week pattern first (e.g. "34 weeks", "34 wks", "34w")
    final regExp = RegExp(r'(\d+)\s*(?:weeks?|wks?|w\b)', caseSensitive: false);
    final match = regExp.firstMatch(ageText);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    // 2. Look for any number in the sensible gestational range (4 to 42)
    // to avoid matching small numbers like 1, 2, 3 (from "3rd trimester" etc.)
    final numRegExp = RegExp(r'\b\d+\b');
    final matches = numRegExp.allMatches(ageText);
    for (final m in matches) {
      final val = int.tryParse(m.group(0)!);
      if (val != null && val >= 4 && val <= 42) {
        return val;
      }
    }

    // 3. Fall back to first number found
    final fallbackMatch = numRegExp.firstMatch(ageText);
    if (fallbackMatch != null) {
      return int.tryParse(fallbackMatch.group(0)!);
    }
    return null;
  }

  int _extractDaysFromAiText(String? ageText) {
    if (ageText == null || ageText.isEmpty) return 0;
    final regExp = RegExp(r'(\d+)\s*(?:days?|d\b)', caseSensitive: false);
    final match = regExp.firstMatch(ageText);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  bool _hasGestationalAgeDiscrepancy({GroqResponse? response}) {
    final res = response ?? _combinedResponse;
    final expected = _calculateExpectedWeeksAtUltrasound();
    final aiWeeks = _extractWeeksFromAiText(res?.gestationalAge);
    if (expected == null || aiWeeks == null) return false;
    return (expected - aiWeeks).abs() >= 2;
  }

  /// Deterministically computes the overall monitoring classification from
  /// the AI response. First checks the AI's explicit `monitoring_classification`
  /// field; falls back to deriving it from per-measurement statuses.
  ///
  /// Reference standards:
  ///   INTERGROWTH-21st (Papageorghiou et al., The Lancet, 2014)
  ///   WHO Fetal Growth Charts (Kiserud et al., PLOS Medicine, 2017)
  MonitoringClassification _computeMonitoringClassification(
      GroqResponse result) {
    // Programmatic override: If there is a gestational age discrepancy of >= 2 weeks,
    // require closer monitoring regardless of the raw AI status.
    if (_hasGestationalAgeDiscrepancy(response: result)) {
      return MonitoringClassification.requiresCloserMonitoring;
    }

    // Prefer the AI-provided field if present
    if (result.monitoringClassification != null &&
        result.monitoringClassification!.isNotEmpty) {
      return UltrasoundInterpretationEngine.classifyFromAiString(
          result.monitoringClassification);
    }

    // Fallback: derive from per-measurement statuses
    final statuses = <String>[];
    if (result.measurements != null) {
      for (final m in result.measurements!) {
        final bracketMatch = RegExp(r'\[([A-Z_]+)\]').firstMatch(m);
        if (bracketMatch != null) {
          statuses.add(bracketMatch.group(1)!);
        }
      }
    }
    return UltrasoundInterpretationEngine.classifyMonitoring(statuses);
  }

  bool _isNameMismatch() {
    final extracted = _combinedResponse?.extractedPatientName;
    if (extracted == null || extracted.trim().isEmpty) return false;

    final cleanExtracted =
        extracted.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final cleanMother =
        _motherName.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');

    final tokensExt = cleanExtracted
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2)
        .toList();
    final tokensMoth =
        cleanMother.split(RegExp(r'\s+')).where((t) => t.length > 2).toList();

    if (tokensExt.isEmpty || tokensMoth.isEmpty) return false;

    for (final t in tokensExt) {
      if (tokensMoth.contains(t)) return false;
    }
    return true;
  }

  Future<void> _reDatePregnancy() async {
    final aiWeeks = _extractWeeksFromAiText(_combinedResponse?.gestationalAge);
    final aiDays = _extractDaysFromAiText(_combinedResponse?.gestationalAge);

    if (aiWeeks == null || _ultrasoundDate == null) {
      _showMessage(
          'Unable to re-date pregnancy without valid AI gestational age.',
          type: AppSnackType.warning);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final totalDays = (aiWeeks * 7) + aiDays;
      final newLmp = _ultrasoundDate!.subtract(Duration(days: totalDays));
      final newEdd = newLmp.add(const Duration(days: 280));

      await Supabase.instance.client.from('pregnancies').update({
        'last_menstrual_period': newLmp.toIso8601String().split('T')[0],
        'expected_date_of_delivery': newEdd.toIso8601String().split('T')[0],
      }).eq('pregnancy_id', _pregnancyId);

      setState(() {
        _pregnancyLmp = newLmp;
        _pregnancyEdd = newEdd;
        _datesUpdated = true;
      });

      _showMessage(
        'Pregnancy re-dated successfully! LMP set to ${DateFormat('MMM d, yyyy').format(newLmp)}, EDD set to ${DateFormat('MMM d, yyyy').format(newEdd)}.',
        type: AppSnackType.success,
      );
    } catch (e) {
      if (kDebugMode) print('Error re-dating pregnancy: $e');
      _showMessage('Error re-dating pregnancy: $e', type: AppSnackType.error);
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  double? _calculatePrePregnancyBmi() {
    if (_maternalPrePregWeight == null ||
        _maternalHeight == null ||
        _maternalHeight! <= 0) {
      return null;
    }
    final heightInMeters = _maternalHeight! / 100.0;
    return _maternalPrePregWeight! / (heightInMeters * heightInMeters);
  }

  List<Widget> _buildRiskFactorsPills() {
    final List<Widget> pills = [];

    // BMI Warning Pill
    final bmi = _calculatePrePregnancyBmi();
    if (bmi != null) {
      if (bmi < 18.5) {
        pills.add(_buildRiskPill('Underweight BMI (${bmi.toStringAsFixed(1)})',
            isSevere: false));
      } else if (bmi >= 25.0 && bmi < 30.0) {
        pills.add(_buildRiskPill('Overweight BMI (${bmi.toStringAsFixed(1)})',
            isSevere: false));
      } else if (bmi >= 30.0) {
        pills.add(_buildRiskPill('Obese BMI (${bmi.toStringAsFixed(1)})',
            isSevere: true));
      }
    }

    // Maternal Age Warning Pill
    final age = _calculateMaternalAge();
    if (age != null) {
      if (age < 18) {
        pills.add(
            _buildRiskPill('Early Maternal Age ($age years)', isSevere: true));
      } else if (age >= 35) {
        pills.add(_buildRiskPill('Advanced Maternal Age ($age years)',
            isSevere: true));
      }
    }

    // Multiple pregnancy pill
    if (_pregnancyFetalCount != null && _pregnancyFetalCount! > 1) {
      pills.add(_buildRiskPill(
          'Multiple Pregnancy ($_pregnancyFetalCount babies)',
          isSevere: true));
    }

    // Medical conditions
    for (final cond in _maternalActiveConditions) {
      pills.add(_buildRiskPill('Medical: $cond', isSevere: true));
    }

    // Allergies
    for (final allerg in _maternalAllergies) {
      pills.add(_buildRiskPill('Allergy: $allerg', isSevere: false));
    }

    // Gestational age discrepancy
    if (_hasGestationalAgeDiscrepancy()) {
      pills.add(_buildRiskPill('AOG Discrepancy (LMP vs AI)', isSevere: false));
    }

    // Patient name mismatch
    if (_isNameMismatch()) {
      pills.add(_buildRiskPill('Patient Name Mismatch', isSevere: true));
    }

    if (pills.isEmpty) {
      pills.add(_buildRiskPill('No high-risk complications detected',
          isSevere: false, isSuccess: true));
    }

    return pills;
  }

  Widget _buildRiskPill(String label,
      {required bool isSevere, bool isSuccess = false}) {
    final Color bgColor = isSuccess
        ? AppColors.success.withValues(alpha: 0.08)
        : (isSevere
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.warning.withValues(alpha: 0.08));
    final Color borderColor = isSuccess
        ? AppColors.success.withValues(alpha: 0.3)
        : (isSevere
            ? AppColors.error.withValues(alpha: 0.3)
            : AppColors.warning.withValues(alpha: 0.3));
    final Color textColor = isSuccess
        ? AppColors.success
        : (isSevere ? AppColors.error : AppColors.warning);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.error_outline,
            size: 12,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  int? _detectFetalCountFromAiText(String? description) {
    if (description == null || description.isEmpty) return null;
    final text = description.toLowerCase();
    if (text.contains('twin') ||
        text.contains('multiple') ||
        text.contains('dalawa') ||
        text.contains('kambal')) {
      return 2;
    }
    if (text.contains('triplet') || text.contains('tatlo')) {
      return 3;
    }
    if (text.contains('singleton') ||
        text.contains('single fetus') ||
        text.contains('isa') ||
        text.contains('solo')) {
      return 1;
    }
    return null;
  }

  String _getFetalCount() {
    if (_pregnancyFetalCount != null) {
      return _pregnancyFetalCount == 1
          ? 'Singleton'
          : '$_pregnancyFetalCount babies';
    }
    final detected =
        _detectFetalCountFromAiText(_combinedResponse?.description);
    if (detected != null) {
      return detected == 1 ? 'Singleton' : '$detected babies';
    }
    return 'Singleton';
  }

  int _determineFetalCountInt() {
    if (_pregnancyFetalCount != null) {
      return _pregnancyFetalCount!;
    }
    return _detectFetalCountFromAiText(_combinedResponse?.description) ?? 1;
  }

  String _safeStatusLabel(String status, String language) {
    final s = status.toUpperCase();
    if (s == 'NORMAL' || s == 'SUCCESS') {
      return language == 'filipino'
          ? 'Nasa Inaasahang Saklaw'
          : 'Within Expected Range';
    } else if (s == 'ABNORMAL' || s == 'CONCERNING' || s == 'REVIEW') {
      return language == 'filipino'
          ? 'Kailangan ng Masusing Pagsubaybay'
          : 'Requires Closer Monitoring';
    } else if (s == 'BORDERLINE' || s == 'MONITOR' || s == 'OBSERVE') {
      return language == 'filipino'
          ? 'Inirerekomenda ang Pagsubaybay'
          : 'Monitoring Recommended';
    }
    return status;
  }

  String _getTrimester(int weeks, String language) {
    if (weeks <= 13) {
      return language == 'filipino' ? 'Unang Trimester' : 'First Trimester';
    } else if (weeks <= 27) {
      return language == 'filipino'
          ? 'Ikalawang Trimester'
          : 'Second Trimester';
    } else {
      return language == 'filipino' ? 'Ikatlong Trimester' : 'Third Trimester';
    }
  }

  Widget _buildGroupedAnatomicalAssessment(List<String> lines) {
    final List<({String structure, String status, String note})>
        flaggedStructures = [];

    for (final line in lines) {
      final parsed = _parseUltrasoundMetricLine(line);
      if (parsed.testName.isEmpty) continue;

      if (parsed.status != 'NORMAL' &&
          parsed.status != 'SUCCESS' &&
          parsed.status != 'UNKNOWN') {
        flaggedStructures.add((
          structure: parsed.testName,
          status: parsed.status,
          note: parsed.remark.isNotEmpty ? parsed.remark : parsed.value,
        ));
      }
    }

    if (flaggedStructures.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectedLanguage == 'filipino'
              ? '🔍 Mga Pambihirang Obserbasyon (Notable Findings)'
              : '🔍 Notable Findings',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.warning,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: flaggedStructures.map((item) {
            final isConcerning = item.status == 'ABNORMAL' ||
                item.status == 'CONCERNING' ||
                item.status == 'REVIEW';
            final color = isConcerning ? AppColors.error : _cautionBlue;
            final safeLabelText =
                _safeStatusLabel(item.status, _selectedLanguage);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: icon + title + pill
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        isConcerning
                            ? Icons.warning_rounded
                            : Icons.info_outline,
                        size: 16,
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.structure,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: color.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          safeLabelText,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.note,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      _selectedLanguage == 'filipino'
                          ? 'Ang obserbasyon na ito ay maaaring mangailangan ng karagdagang pagsusuri. Iminumungkahi ang pagkonsulta sa iyong doktor o komadrona.'
                          : 'This finding may require further evaluation. Consultation with your healthcare provider is recommended.',
                      style: TextStyle(
                        fontSize: 11,
                        color: color.withValues(alpha: 0.75),
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMaternalUltrasoundResults() {
    final text = _healthSummaryController.text;
    final isFilipino = _selectedLanguage == 'filipino';

    // Helper to search keywords
    bool hasKeywords(List<String> keywords) {
      final lower = text.toLowerCase();
      return keywords.any((kw) => lower.contains(kw));
    }

    // Resolve statuses
    final growthWarning = (_monitoringClassification !=
                MonitoringClassification.withinExpectedRange &&
            hasKeywords([
              'growth',
              'size',
              'bpd',
              'hc',
              'ac',
              'fl',
              'weight',
              'efw',
              'restricted',
              'iugr',
              'lga',
              'sga',
              'sukat',
              'laki',
              'timbang'
            ])) ||
        hasKeywords([
          'growth restriction',
          'iugr',
          'small for gestational',
          'large for gestational',
          'abnormal growth'
        ]);

    final heartWarning = (_monitoringClassification !=
                MonitoringClassification.withinExpectedRange &&
            hasKeywords(
                ['heart', 'fhr', 'cardiac', 'beat', 'tibok', 'puso', 'bpm'])) ||
        hasKeywords([
          'bradycardia',
          'tachycardia',
          'irregular heart rate',
          'fetal distress',
          'abnormal heartbeat'
        ]);

    final envWarning = (_monitoringClassification !=
                MonitoringClassification.withinExpectedRange &&
            hasKeywords([
              'fluid',
              'amniotic',
              'afi',
              'oligo',
              'poly',
              'placenta',
              'previa',
              'praevia',
              'tubig',
              'inunan'
            ])) ||
        hasKeywords([
          'oligohydramnios',
          'polyhydramnios',
          'placenta previa',
          'low-lying placenta',
          'placental abruption'
        ]);

    // Colors & Text based on classification
    final Color overallColor = _monitoringChipColor(_monitoringClassification);
    final String overallTitle = isFilipino
        ? (_monitoringClassification ==
                MonitoringClassification.withinExpectedRange
            ? 'Nasa Inaasahang Kondisyon'
            : (_monitoringClassification ==
                    MonitoringClassification.requiresCloserMonitoring
                ? 'Kailangan ng Masusing Pagsubaybay'
                : 'Inirerekomenda ang Konsultasyon'))
        : (_monitoringClassification ==
                MonitoringClassification.withinExpectedRange
            ? 'Within Expected Monitoring Range'
            : (_monitoringClassification ==
                    MonitoringClassification.requiresCloserMonitoring
                ? 'Requires Closer Monitoring'
                : 'Clinical Follow-Up Recommended'));

    final String overallDesc = isFilipino
        ? (_monitoringClassification ==
                MonitoringClassification.withinExpectedRange
            ? 'Ang iyong ultrasound ay umaayon sa inaasahang kondisyon sa yugtong ito ng pagbubuntis. Ipagpatuloy ang iyong nakasanayang pangangalaga!'
            : (_monitoringClassification ==
                    MonitoringClassification.requiresCloserMonitoring
                ? 'May mga obserbasyon sa iyong ultrasound na nangangailangan ng karagdagang atensyon sa susunod na checkup. Huwag mag-alala, ito ay para sa tamang gabay.'
                : 'May mga natuklasang obserbasyon na nangangailangan ng konsultasyon sa doktor o espesyalista upang masigurong ligtas kayo ni baby.'))
        : (_monitoringClassification ==
                MonitoringClassification.withinExpectedRange
            ? 'Your recorded ultrasound results generally appear consistent with the expected range for this stage of pregnancy. Continue your regular prenatal care!'
            : (_monitoringClassification ==
                    MonitoringClassification.requiresCloserMonitoring
                ? 'Some observations in your ultrasound suggest closer attention in upcoming checkups. There is no cause for alarm; this is for standard prenatal guidance.'
                : 'Certain findings suggest that a clinical follow-up or consultation is recommended to ensure both you and your baby remain healthy and safe.'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Overall Summary Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: overallColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: overallColor.withValues(alpha: 0.25), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _monitoringChipIcon(_monitoringClassification),
                    color: overallColor,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isFilipino
                              ? 'Pangkalahatang Katayuan'
                              : 'Overall Pregnancy Status',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          overallTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: overallColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                overallDesc,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // 2. Simple Monitoring Notes Header
        Row(
          children: [
            const Icon(Icons.favorite_rounded,
                color: Colors.pinkAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              isFilipino ? 'Mga Gabay Para sa Ina' : 'Simple Monitoring Notes',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Card 1: Baby's Growth
        _buildMotherFriendlyCard(
          title: isFilipino
              ? 'Suporta sa Paglaki at Sukat ng Baby'
              : "Baby's Growth & Size Support",
          subtitle: isFilipino
              ? 'BPD, HC, AC, FL, gestational age, at fetal weight'
              : 'Body metrics, weight, and general size',
          icon: Icons.child_care_rounded,
          iconColor: Colors.teal.shade500,
          isWarning: growthWarning,
          desc: isFilipino
              ? (growthWarning
                  ? 'May kaunting pagkakaiba sa sukat ni baby para sa kanyang linggo sa sinapupunan. Huwag mag-alala, Mommy! Ipinapayo namin ang patuloy na pag-monitor kasama ang iyong komadrona upang masubaybayan nang maayos ang kanyang paglaki.'
                  : 'Ang sukat ng ulo, tiyan, at hita ni baby ay maganda at sakto sa kanyang linggo sa sinapupunan. Ito ay nagpapakita ng malusog na paglaki ni baby!')
              : (growthWarning
                  ? "Some of your baby's measurements show slight variations. Don't worry, Mommy! We recommend keeping track of her growth during your regular midwife visits to make sure she grows healthy."
                  : "Your baby's head, tummy, and leg measurements are perfect for her stage of pregnancy. She is growing healthy and beautifully!"),
        ),
        const SizedBox(height: 12),

        // Card 2: Baby's Heart Activity
        _buildMotherFriendlyCard(
          title: isFilipino ? 'Tibok ng Puso ni Baby' : "Baby's Heart Activity",
          subtitle: isFilipino
              ? 'Tibok ng puso o Fetal Heart Rate (FHR)'
              : 'Fetal Heart Rate (FHR) & cardiac rhythm',
          icon: Icons.favorite_border_rounded,
          iconColor: Colors.redAccent.shade200,
          isWarning: heartWarning,
          desc: isFilipino
              ? (heartWarning
                  ? 'May nakitang kaunting pagbabago sa tibok ng puso ni baby. Inirerekomenda namin ang patuloy na pag-monitor sa iyong susunod na checkup upang masiguro ang kanyang kaligtasan.'
                  : 'Napakaganda ng tibok ng puso ni baby! Ito ay malakas, malusog, at nasa ligtas na bilis. Napakagandang senyales nito ng isang masiglang sanggol!')
              : (heartWarning
                  ? "We noticed a slight variation in your baby's heartbeat. We recommend keeping a close watch during your next prenatal visits to ensure baby stays safe and active."
                  : "Your baby's heartbeat is perfectly strong, healthy, and beating at a safe speed. This is a wonderful sign of a happy and thriving baby!"),
        ),
        const SizedBox(height: 12),

        // Card 3: Baby's Environment & Placenta
        _buildMotherFriendlyCard(
          title: isFilipino
              ? 'Placenta at Tubig sa Sinapupunan'
              : "Baby's Environment & Placenta Support",
          subtitle: isFilipino
              ? 'Amniotic fluid at posisyon ng inunan'
              : 'Amniotic fluid level and placental position',
          icon: Icons.water_drop_outlined,
          iconColor: Colors.blue.shade400,
          isWarning: envWarning,
          desc: isFilipino
              ? (envWarning
                  ? 'May kaunting pagbabago sa dami ng tubig (amniotic fluid) o sa pwesto ng inunan (placenta). Pinapayuhan ka naming magpahinga nang mabuti, umiwas sa mabibigat na gawain, at sumunod sa payo ng iyong midwife.'
                  : 'Sapat na sapat ang dami ng tubig sa iyong sinapupunan para malayang makalaro at makagalaw si baby, at ang inunan ay nasa ligtas na pwesto.')
              : (envWarning
                  ? "There is a slight change in your water level (amniotic fluid) or the position of your placenta. We advise you to get plenty of rest, avoid heavy lifting, and follow your midwife's guidance."
                  : "Your baby has plenty of water to swim and play safely, and your placenta is in a perfect position to give her all the strength she needs."),
        ),
      ],
    );
  }

  Widget _buildMotherFriendlyCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isWarning,
    required String desc,
  }) {
    final statusColor = isWarning ? AppColors.warning : AppColors.success;
    final statusText = _selectedLanguage == 'filipino'
        ? (isWarning
            ? 'Para sa Dagdag na Pagsubaybay'
            : 'Nasa Inaasahang Kondisyon')
        : (isWarning
            ? 'Closer Monitoring Recommended'
            : 'Within Expected Range');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.2), width: 1),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.borderPrimary, height: 1),
          const SizedBox(height: 10),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPregnancyProgressionCard() {
    final fetalCount = _getFetalCount();
    final aogWeeks =
        _extractWeeksFromAiText(_combinedResponse?.gestationalAge) ??
            _calculateExpectedWeeksAtUltrasound() ??
            0;
    final trimester = _getTrimester(aogWeeks, _selectedLanguage);

    final String fetalCountLabel =
        _selectedLanguage == 'filipino' ? 'Bilang ng Fetus' : 'Fetal Count';
    final String aogLabel = _selectedLanguage == 'filipino'
        ? 'Edad ng Pagbubuntis'
        : 'Gestational Age';
    final String trimesterLabel =
        _selectedLanguage == 'filipino' ? 'Trimester' : 'Trimester';

    final String translatedFetalCount = _selectedLanguage == 'filipino'
        ? (fetalCount.toLowerCase().contains('singleton')
            ? 'Isa (Singleton)'
            : 'Kambal (Twins)')
        : fetalCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.teal.shade50.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.shade200.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Fetal Count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.child_care_rounded,
                        size: 18, color: Colors.teal.shade600),
                    const SizedBox(height: 4),
                    Text(
                      fetalCountLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      translatedFetalCount,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.teal.shade200.withValues(alpha: 0.6),
              ),
              // AOG
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month_rounded,
                        size: 18, color: Colors.teal.shade600),
                    const SizedBox(height: 4),
                    Text(
                      aogLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$aogWeeks ${_selectedLanguage == 'filipino' ? 'Linggo' : 'Weeks'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.teal.shade200.withValues(alpha: 0.6),
              ),
              // Trimester
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.pregnant_woman_rounded,
                        size: 18, color: Colors.teal.shade600),
                    const SizedBox(height: 4),
                    Text(
                      trimesterLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trimester,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ], // end Row children
          ), // end Row
        ], // end Column children
      ), // end Column (card body)
    ); // end Container
  }

  // ── Shared helpers for monitoring classification color/icon ────────────────
  // Used by BOTH the header badge AND the pregnancy card chip so they are
  // always in sync with the same single source of truth.
  Color _monitoringChipColor(MonitoringClassification classification) {
    switch (classification) {
      case MonitoringClassification.withinExpectedRange:
        return AppColors.success;
      case MonitoringClassification.requiresCloserMonitoring:
        return AppColors.warning;
      case MonitoringClassification.followUpRecommended:
        return AppColors.error;
    }
  }

  IconData _monitoringChipIcon(MonitoringClassification classification) {
    switch (classification) {
      case MonitoringClassification.withinExpectedRange:
        return Icons.check_circle_outline_rounded;
      case MonitoringClassification.requiresCloserMonitoring:
        return Icons.info_outline_rounded;
      case MonitoringClassification.followUpRecommended:
        return Icons.warning_amber_rounded;
    }
  }

  /// Subtle expandable panel showing clinical references for the
  /// monitoring classification (INTERGROWTH-21st; WHO Fetal Growth Charts).
  Widget _buildClinicalReferenceTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.borderPrimary.withValues(alpha: 0.4),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Icon(
            Icons.menu_book_outlined,
            size: 15,
            color: AppColors.textSecondary.withValues(alpha: 0.6),
          ),
          title: Text(
            _selectedLanguage == 'filipino'
                ? 'Batayan ng Klinikal na Paliwanag'
                : 'Clinical Reference Basis',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
          iconColor: AppColors.textSecondary.withValues(alpha: 0.5),
          collapsedIconColor: AppColors.textSecondary.withValues(alpha: 0.4),
          children: [
            _buildCitationRow(
              authors: UltrasoundInterpretationEngine.citation1Authors,
              full: UltrasoundInterpretationEngine.citation1Full,
              url: UltrasoundInterpretationEngine.citation1Url,
            ),
            const SizedBox(height: 8),
            _buildCitationRow(
              authors: UltrasoundInterpretationEngine.citation2Authors,
              full: UltrasoundInterpretationEngine.citation2Full,
              url: UltrasoundInterpretationEngine.citation2Url,
            ),
            const SizedBox(height: 8),
            Text(
              _selectedLanguage == 'filipino'
                  ? 'Para lamang sa pagsubaybay ng kalusugan at hindi kapalit ng medikal na konsultasyon.'
                  : 'For health monitoring support only. Does not replace professional medical consultation.',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary.withValues(alpha: 0.55),
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCitationRow({
    required String authors,
    required String full,
    required String url,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$authors $full',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary.withValues(alpha: 0.65),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          url,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.brandPrimary.withValues(alpha: 0.6),
            decoration: TextDecoration.underline,
          ),
        ),
      ],
    );
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
          _combinedResponse = null;
          _errorMessage = null;
          _isEditing = false;
          _analysisApproved = false;
          _showAdvancedAiDetails = false;
          _healthSummaryController.clear();
          _uploadedImageUrls.clear();
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking images: $e';
      });
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImages.add(image);
          _combinedResponse = null;
          _errorMessage = null;
          _isEditing = false;
          _analysisApproved = false;
          _showAdvancedAiDetails = false;
          _healthSummaryController.clear();
          _uploadedImageUrls.clear();
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error taking photo: $e';
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      if (_selectedImages.isEmpty) {
        _combinedResponse = null;
        _healthSummaryController.clear();
        _uploadedImageUrls.clear();
      }
      _isEditing = false;
    });
  }

  void _clearAll() {
    setState(() {
      _selectedImages.clear();
      _combinedResponse = null;
      _errorMessage = null;
      _isEditing = false;
      _healthSummaryController.clear();
      _uploadedImageUrls.clear();
      _dateController.text = _dateFormat.format(DateTime.now());
      _ultrasoundDate = DateTime.now();
      _healthWorkerNameController.clear();
      _healthWorkerInstitutionController.clear();
      _healthWorkerProfessionController.clear();
      _selectedHealthWorkerProfession = null;
      _analysisApproved = false;
      _aiAnalysisSkipped = false;
      _showAdvancedAiDetails = false;
    });
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _ultrasoundDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.brandPrimary,
              onPrimary: Colors.white,
              onSurface: AppColors.brandText,
              secondary: AppColors.brandPrimary,
              surface: Colors.white,
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor: Colors.white,
              elevation: 4,
              surfaceTintColor: Colors.transparent,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandPrimary,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              headerBackgroundColor: Colors.white,
              headerForegroundColor: AppColors.brandText,
              headerHeadlineStyle: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.brandText,
              ),
              headerHelpStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.brandPrimary,
              ),
              surfaceTintColor: Colors.transparent,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _ultrasoundDate = picked;
        _dateController.text = _dateFormat.format(picked);
      });
    }
  }

  bool _validateStep1() {
    if (_ultrasoundDate == null) {
      _showMessage('Please select ultrasound date.',
          type: AppSnackType.warning);
      return false;
    }
    return true;
  }

  bool _validateStep2() {
    if (_selectedImages.isEmpty) {
      _showMessage('Please attach at least one ultrasound image.',
          type: AppSnackType.warning);
      return false;
    }
    return true;
  }

  String? _effectiveSelectedProfession() {
    final selected = _selectedHealthWorkerProfession?.trim();
    final text = _healthWorkerProfessionController.text.trim();

    if (selected != null && selected.isNotEmpty) {
      if (selected == _otherProfessionOption) return selected;
      if (_ultrasoundProfessions.contains(selected)) return selected;
    }

    if (text.isEmpty) return null;
    if (_ultrasoundProfessions.contains(text)) return text;
    return _otherProfessionOption;
  }

  bool _isAiResultUnrelated(String text) {
    return RegExp(r'RELEVANCE\s*CHECK\s*:\s*UNRELATED', caseSensitive: false)
            .hasMatch(text) ||
        RegExp(r'not\s+ultrasound|unrelated\s+image|unreadable',
                caseSensitive: false)
            .hasMatch(text);
  }

  String _extractRelevanceReason(String text) {
    final match =
        RegExp(r'RELEVANCE\s*REASON\s*:\s*([^\n]+)', caseSensitive: false)
            .firstMatch(text);
    if (match == null) {
      return 'Uploaded content appears unrelated to ultrasound.';
    }
    return match.group(1)?.trim() ??
        'Uploaded content appears unrelated to ultrasound.';
  }

  void _setLoadingState(String title, String detail) {
    if (!mounted) return;
    setState(() {
      _loadingTitle = title;
      _loadingDetail = detail;
    });
  }

  Future<String?> _runImageQualityChecks() async {
    if (_selectedImages.isEmpty) return 'Please attach at least one image.';

    if (_selectedImages.length > 10) {
      return 'Too many images attached. Please keep it to 10 or fewer per record.';
    }

    for (int i = 0; i < _selectedImages.length; i++) {
      final image = _selectedImages[i];
      final size = await image.length();

      if (size < 25 * 1024) {
        return 'Image ${i + 1} looks too small/low quality. Please upload a clearer photo.';
      }

      if (size > 8 * 1024 * 1024) {
        return 'Image ${i + 1} is too large. Please keep each image below 8MB.';
      }

      try {
        final bytes = await image.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final decoded = frame.image;
        final shortestSide =
            decoded.width < decoded.height ? decoded.width : decoded.height;
        if (shortestSide < 400) {
          return 'Image ${i + 1} resolution is too low (minimum 400px on the shortest side). Retake in better lighting and closer framing.';
        }
      } catch (_) {
        return 'Image ${i + 1} could not be decoded. Please upload JPG, PNG, WEBP, or another convertible image.';
      }
    }

    return null;
  }

  Future<
      ({
        Uint8List bytes,
        String contentType,
        String extension,
        bool converted,
      })> _prepareImageForUpload(XFile image) async {
    final rawBytes = await image.readAsBytes();
    final ext = image.path.split('.').last.toLowerCase();

    if (ext == 'jpg' || ext == 'jpeg') {
      return (
        bytes: Uint8List.fromList(rawBytes),
        contentType: 'image/jpeg',
        extension: 'jpg',
        converted: false,
      );
    }

    if (ext == 'png') {
      return (
        bytes: Uint8List.fromList(rawBytes),
        contentType: 'image/png',
        extension: 'png',
        converted: false,
      );
    }

    if (ext == 'webp') {
      return (
        bytes: Uint8List.fromList(rawBytes),
        contentType: 'image/webp',
        extension: 'webp',
        converted: false,
      );
    }

    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw Exception(
          'Unsupported image format detected. Please upload convertible image files.');
    }

    final convertedBytes =
        Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
    return (
      bytes: convertedBytes,
      contentType: 'image/jpeg',
      extension: 'jpg',
      converted: true,
    );
  }

  bool get _hasEnteredData =>
      _selectedImages.isNotEmpty ||
      _notesController.text.trim().isNotEmpty ||
      _healthWorkerNameController.text.trim().isNotEmpty;

  Future<void> _confirmDiscardAndPop() async {
    if (!_hasEnteredData) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Discard changes?',
        subtitle:
            'You have unsaved ultrasound data. Are you sure you want to go back?',
        cancelText: 'Cancel',
        confirmText: 'Discard',
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
    if (discard == true && mounted) {
      Navigator.pop(context);
    }
  }

  void _nextStep() {
    if (_step == 0 && !_validateStep1()) return;
    if (_step == 1 && !_validateStep2()) return;
    if (_step < _totalSteps - 1) {
      setState(() => _step += 1);
    }
  }

  void _prevStep() {
    if (_step > 0) {
      setState(() => _step -= 1);
    }
  }

  Future<void> _analyzeImages() async {
    if (!_validateStep1() || !_validateStep2()) return;

    _setLoadingState(
      'Checking image quality',
      'Validating image format, size, and readability',
    );
    final imageQualityIssue = await _runImageQualityChecks();
    if (imageQualityIssue != null) {
      _showMessage(imageQualityIssue, type: AppSnackType.warning);
      return;
    }

    final runId = ++_analysisRunId;
    _setLoadingState(
      'Preparing your explanation',
      'Checking images and clinical context',
    );
    _showLoadingOverlay(runId);

    setState(() {
      _errorMessage = null;
      _combinedResponse = null;
      _isEditing = false;
      _analysisApproved = false;
      _aiAnalysisSkipped = false;
      _healthSummaryController.clear();
    });

    try {
      // ── Build enriched clinical context using UltrasoundInterpretationEngine ──
      // Determines trimester from AOG and filters to relevant measurement categories.
      // Reference: INTERGROWTH-21st (Papageorghiou et al., Lancet 2014)
      //            WHO Fetal Growth Charts (Kiserud et al., PLOS Medicine 2017)
      final aogWeeks = _calculateExpectedWeeksAtUltrasound() ?? 0;
      final trimester = UltrasoundInterpretationEngine.getTrimester(aogWeeks);
      final relevantCategories =
          UltrasoundInterpretationEngine.getRelevantCategories(trimester);
      final trimesterLabel = UltrasoundInterpretationEngine.getTrimesterLabel(
          trimester,
          language: _selectedLanguage);
      final categoriesLabel =
          relevantCategories.map((c) => c.displayName).join(', ');

      _lastAiPrompt = UltrasoundInterpretationEngine.buildAiClinicalContext(
        aogWeeks: aogWeeks,
        trimester: trimester,
        relevantCategories: relevantCategories,
        healthWorkerName: _healthWorkerNameController.text.trim(),
        institution: _healthWorkerInstitutionController.text.trim(),
        profession: _effectiveSelectedProfession(),
        notes: _notesController.text.trim(),
        imageCount: _selectedImages.length,
      );

      _setLoadingState(
        'Reading ultrasound images',
        'Extracting ultrasound observations and measurements',
      );

      final result = await _groqService.analyzeUltrasoundImages(
        _selectedImages,
        clinicalContext: _lastAiPrompt,
        aogWeeks: aogWeeks,
        trimesterLabel: trimesterLabel,
        relevantCategories: categoriesLabel,
      );
      if (!mounted || _cancelledRunIds.contains(runId)) return;

      _setLoadingState(
        'Finalizing insights',
        'Checking relevance and preparing summary',
      );

      if (_isAiResultUnrelated(result.description)) {
        _closeLoadingOverlayIfNeeded();
        _showMessage(
          'AI flagged unrelated upload: ${_extractRelevanceReason(result.description)}',
          type: AppSnackType.warning,
        );
        return;
      }

      _closeLoadingOverlayIfNeeded();

      // ── Compute monitoring classification deterministically from AI result ──
      // Uses UltrasoundInterpretationEngine which applies:
      //   INTERGROWTH-21st (Papageorghiou et al., Lancet 2014)
      //   WHO Fetal Growth Charts (Kiserud et al., PLOS Medicine 2017)
      final computed = _computeMonitoringClassification(result);

      setState(() {
        _combinedResponse = result;
        _monitoringClassification = computed;

        // Auto-detect and update fetal count from scan text if detected
        final detectedFetalCount =
            _detectFetalCountFromAiText(result.description);
        if (detectedFetalCount != null) {
          _pregnancyFetalCount = detectedFetalCount;
        }

        if (result.description.isNotEmpty) {
          _healthSummaryController.text = result.description;
        } else {
          _healthSummaryController.text = "No analysis available";
        }

        // Populate extracted admin fields if available
        if (result.extractedProfessional != null &&
            result.extractedProfessional!.isNotEmpty &&
            _healthWorkerNameController.text.trim().isEmpty) {
          _healthWorkerNameController.text = result.extractedProfessional!;
        }
        if (result.extractedClinicLocation != null &&
            result.extractedClinicLocation!.isNotEmpty &&
            _healthWorkerInstitutionController.text.trim().isEmpty) {
          _healthWorkerInstitutionController.text =
              result.extractedClinicLocation!;
        }
      });

      _showMessage('AI analysis completed successfully!',
          type: AppSnackType.success);
      setState(() {
        _step = 2; // Move to Step 3: Assessment & Clinical Review
      });
    } catch (e) {
      if (!mounted || _cancelledRunIds.contains(runId)) return;
      _closeLoadingOverlayIfNeeded();
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
      _showMessage(_errorMessage!, type: AppSnackType.error);
    } finally {
      _cancelledRunIds.remove(runId);
      _closeLoadingOverlayIfNeeded();
    }
  }

  Future<void> _saveToDatabase() async {
    print('DEBUG: _saveToDatabase() triggered');
    try {
      print('DEBUG: running validations');
      final val1 = _validateStep1();
      final val2 = _validateStep2();
      print('DEBUG: _validateStep1 = $val1, _validateStep2 = $val2');

      if (!val1 || !val2) {
        print('DEBUG: validations failed early');
        return;
      }

      final aiGenerated = _combinedResponse != null;
      print(
          'DEBUG: aiGenerated = $aiGenerated, _analysisApproved = $_analysisApproved, _aiAnalysisSkipped = $_aiAnalysisSkipped');

      if (!aiGenerated && !_aiAnalysisSkipped) {
        _showMessage('Please run AI analysis or skip it before saving.',
            type: AppSnackType.warning);
        return;
      }
      if (aiGenerated && !_analysisApproved) {
        _showMessage('Please approve the AI analysis before saving.',
            type: AppSnackType.warning);
        return;
      }

      print('DEBUG: validations passed, setting _isSaving = true');
      setState(() {
        _isSaving = true;
      });

      print('DEBUG: entering Supabase operations block, getting userId');
      final userId = await AuthStorage.getUserId();
      print('DEBUG: userId = $userId');

      if (userId == null) {
        throw Exception('User not logged in');
      }

      _uploadedImageUrls.clear();

      final List<String> uploadedFilePaths = [];
      final List<int> fileIds = [];
      int convertedCount = 0;
      int storageFailureCount = 0;

      print('DEBUG: uploading ${_selectedImages.length} images');
      for (int i = 0; i < _selectedImages.length; i++) {
        try {
          final image = _selectedImages[i];
          final preparedUpload = await _prepareImageForUpload(image);
          final bytes = preparedUpload.bytes;
          if (preparedUpload.converted) {
            convertedCount += 1;
          }
          final fileName =
              'ultrasound_${DateTime.now().millisecondsSinceEpoch}_$i.${preparedUpload.extension}';
          final filePath = 'ultrasounds/$_motherId/$fileName';

          print('DEBUG: uploading image $i to $filePath');
          await Supabase.instance.client.storage.from('files').uploadBinary(
                filePath,
                bytes,
                fileOptions:
                    FileOptions(contentType: preparedUpload.contentType),
              );

          final publicUrl = Supabase.instance.client.storage
              .from('files')
              .getPublicUrl(filePath);

          uploadedFilePaths.add(filePath);
          _uploadedImageUrls.add(publicUrl);

          print('DEBUG: inserting image metadata to files table');
          final fileResponse = await Supabase.instance.client
              .from('files')
              .insert({
                'bucket_name': 'files',
                'file_path': filePath,
                'file_name': fileName,
                'file_category': 'ultrasound_image',
                'mime_type': preparedUpload.contentType,
                'file_size': bytes.length,
                'uploaded_by': userId,
                'reference_type': 'ultrasound',
                'processing_type': 'ultrasound_analysis',
                'ai_processed': aiGenerated,
                'created_at': DateTime.now().toIso8601String(),
              })
              .select('file_id')
              .single();

          fileIds.add(fileResponse['file_id'] as int);
        } catch (uploadError) {
          storageFailureCount += 1;
          print('Storage upload skipped/failed for image $i: $uploadError');
        }
      }

      final profession = _effectiveSelectedProfession();
      final finalProfession = profession == _otherProfessionOption
          ? _healthWorkerProfessionController.text.trim()
          : profession ?? '';

      final determinedFetalCount = _determineFetalCountInt();
      print('DEBUG: determinedFetalCount = $determinedFetalCount');

      print('DEBUG: updating pregnancies table');
      // Update pregnancy risk level and fetal count if overridden by midwife
      await Supabase.instance.client.from('pregnancies').update({
        'pregnancy_risk_level': _pregnancyRiskLevel,
        'fetal_count': determinedFetalCount,
      }).eq('pregnancy_id', _pregnancyId);

      print('DEBUG: inserting ultrasound record');
      int? midwifeId;
      try {
        final accountId = await AuthStorage.getUserId();
        if (accountId != null) {
          final ctx = await SupabaseService.getMidwifeContext(accountId);
          midwifeId = ctx['midwife_id'] as int?;
        }
      } catch (e) {
        print('Error getting midwife ID: $e');
      }

      final ultrasoundResponse = await Supabase.instance.client
          .from('ultrasounds')
          .insert({
            'pregnancy_id': _pregnancyId,
            'ultrasound_date': _ultrasoundDate!.toIso8601String().split('T')[0],
            'ultrasound_location': 'Mobile Upload',
            'ultrasound_image': _uploadedImageUrls.isNotEmpty
                ? _uploadedImageUrls.join(',')
                : null,
            'remarks': _healthSummaryController.text.trim().isEmpty
                ? null
                : _healthSummaryController.text.trim(),
            'health_worker_name': _healthWorkerNameController.text.trim(),
            'health_worker_institution':
                _healthWorkerInstitutionController.text.trim().isEmpty
                    ? ''
                    : _healthWorkerInstitutionController.text.trim(),
            'health_worker_profession': finalProfession,
            // Monitoring classification — trimester-aware 3-tier result
            // Reference: INTERGROWTH-21st (Papageorghiou et al., Lancet 2014)
            //            WHO Fetal Growth Charts (Kiserud et al., PLOS Medicine 2017)
            'monitoring_classification': aiGenerated
                ? UltrasoundInterpretationEngine.classificationToString(
                    _monitoringClassification)
                : null,
            'created_at': DateTime.now().toIso8601String(),
            // `recorded_by_midwife_id` was never a column on this table.
            if (midwifeId != null) 'recorded_by': midwifeId,
          })
          .select('ultrasound_id')
          .single();

      final ultrasoundId = ultrasoundResponse['ultrasound_id'] as int;
      print('DEBUG: inserted ultrasoundId = $ultrasoundId');

      if (aiGenerated) {
        final finalAiText = _healthSummaryController.text.trim();
        final originalAiText = (_combinedResponse?.description ?? '').trim();
        final aiWasEdited =
            originalAiText.isNotEmpty && finalAiText != originalAiText;

        print('DEBUG: inserting ai_response record');
        final insertedAi = await Supabase.instance.client
            .from('ai_responses')
            .insert({
              'response_type': 'ultrasound_analysis',
              'reference_table': 'ultrasounds',
              'reference_id': ultrasoundId,
              'ai_model': 'Gemini 1.5 Flash',
              'confidence_score': null,
              'response': finalAiText,
              'response_category': 'analysis',
              'status': 'approved',
              'generated_by_ai': true,
              'approved_by': userId,
              'created_at': DateTime.now().toIso8601String(),
            })
            .select('ai_response_id')
            .single();

        final aiResponseId = insertedAi['ai_response_id'] as int;

        if ((_lastAiPrompt ?? '').trim().isNotEmpty) {
          print('DEBUG: inserting ai_prompt_logs');
          await Supabase.instance.client.from('ai_prompt_logs').insert({
            'ai_response_id': aiResponseId,
            'prompt': _lastAiPrompt,
            'model_used': 'Gemini 1.5 Flash',
          });
        }

        if (aiWasEdited) {
          print('DEBUG: inserting ai_edit_history');
          await Supabase.instance.client.from('ai_edit_history').insert({
            'ai_response_id': aiResponseId,
            'old_content': originalAiText,
            'new_content': finalAiText,
            'edited_by': userId,
            'edit_reason':
                'Midwife edited AI ultrasound analysis before final save.',
          });
        }

        print('DEBUG: inserting audit_trail');
        await Supabase.instance.client.from('audit_trail').insert({
          'action': 'AI_APPROVAL',
          'table_name': 'ai_responses',
          'account_id': userId,
          'old_data': {
            'status': aiWasEdited ? 'edited' : 'generated',
            'approved_by': null,
          },
          'new_data': {
            'ai_response_id': aiResponseId,
            'status': 'approved',
            'approved_by': userId,
            'reference_table': 'ultrasounds',
            'reference_id': ultrasoundId,
          },
          'description':
              'Midwife approved AI ultrasound analysis for ultrasound_id=$ultrasoundId.',
        });
      }

      print('DEBUG: linking files metadata');
      for (int fileId in fileIds) {
        await Supabase.instance.client.from('files').update({
          'reference_id': ultrasoundId,
        }).eq('file_id', fileId);
      }

      if (!mounted) return;
      if (convertedCount > 0) {
        _showMessage(
          '$convertedCount image(s) were automatically converted to an acceptable format.',
          type: AppSnackType.info,
        );
      }
      if (storageFailureCount > 0) {
        _showMessage(
          'Record saved, but $storageFailureCount image upload(s) were blocked by storage permissions.',
          type: AppSnackType.warning,
        );
      }
      print('DEBUG: save completed successfully! showing success message');
      _showMessage('Ultrasound analysis saved successfully!',
          type: AppSnackType.success);
      Navigator.pop(context, true);
    } catch (e, stackTrace) {
      print('CRITICAL EXCEPTION in _saveToDatabase: $e\n$stackTrace');

      if (!mounted) return;

      // Attempt showing simple error dialog so user definitely sees it
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error Saving Record'),
          content: SingleChildScrollView(
            child: Text('Unable to save record due to an error:\n\n$e'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      _showMessage('Error saving: ${e.toString()}', type: AppSnackType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // UI BUILDERS
  // ============================================================

  Widget _buildFormattedText(String text) {
    if (text.isEmpty) return const SizedBox.shrink();

    final lines = text.split('\n');
    final List<Widget> sections = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Section headers (ALL CAPS)
      if (line.length > 2 &&
          line == line.toUpperCase() &&
          !line.contains(RegExp(r'[0-9]'))) {
        sections.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.brandPrimary.withValues(alpha: 0.1),
                    AppColors.brandSecondary.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.brandPrimary.withValues(alpha: 0.2)),
              ),
              child: Text(
                line,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brandPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        );
      }
      // Bullet points
      else if (line.startsWith('•') ||
          line.startsWith('-') ||
          line.startsWith('*')) {
        sections.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 8),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.brandPrimary,
                        AppColors.brandSecondary
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    line.substring(1).trim(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Status messages
      else if (line.contains('✅') || line.contains('NORMAL')) {
        sections.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.success,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Medical Condition messages
      else if (line.contains('🩺') || line.contains('medical_condition')) {
        sections.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.medical_services_outlined,
                    color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Warning messages
      else if (line.contains('⚠️') ||
          line.contains('MONITORING') ||
          line.contains('CONCERN') ||
          line.contains('Mag-ingat') ||
          line.contains('Caution')) {
        sections.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Regular text
      else {
        sections.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              line,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }

  Map<String, List<String>> _extractInsightSections(String rawText) {
    final lines = rawText.split('\n').map((l) => l.trim()).toList();

    final Map<String, List<String>> sections = {};
    String currentSection = 'Summary';
    sections[currentSection] = [];

    final headingPattern = RegExp(
      r'^(?:\d+\.\s*)?(RELEVANCE CHECK|RELEVANCE REASON|OVERALL HEALTH STATUS|OVERALL ASSESSMENT|GESTATIONAL AGE ASSESSMENT|DETAILED MEASUREMENTS ASSESSMENT|ANATOMICAL ASSESSMENT|ABNORMAL FINDINGS|RECOMMENDED NEXT ACTIONS|RECOMMENDATIONS|KEY OBSERVATIONS)\s*:?\s*(.*)$',
      caseSensitive: false,
    );

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (RegExp(r'^[-_=]{2,}$').hasMatch(line.replaceAll(' ', ''))) continue;

      final heading = headingPattern.firstMatch(line);
      if (heading != null) {
        currentSection = heading.group(1)!.toUpperCase();
        sections.putIfAbsent(currentSection, () => []);
        final inlineContent = heading.group(2)?.trim() ?? '';
        if (inlineContent.isNotEmpty && inlineContent != ':') {
          sections[currentSection]!.add(inlineContent);
        }
        continue;
      }

      sections.putIfAbsent(currentSection, () => []);
      sections[currentSection]!.add(line);
    }

    sections.removeWhere((_, value) => value.isEmpty);
    return sections;
  }

  String _safeText(Object? value) => value?.toString() ?? '';

  bool _isConcerningStatus(String status) {
    final s = status.toUpperCase();
    return s.contains('REVIEW') ||
        s.contains('ABNORMAL') ||
        s.contains('CONCERNING');
  }

  bool _isCautionStatus(String status) {
    final s = status.toUpperCase();
    return s == 'OBSERVE' || s == 'BORDERLINE' || s == 'MONITOR';
  }

  // Caution statuses use blue instead of yellow for readability
  static const Color _cautionBlue = Color(0xFF3B82F6);

  Color _statusChipBackground(String status) {
    if (_isConcerningStatus(status)) {
      return AppColors.error.withValues(alpha: 0.08);
    }
    if (_isCautionStatus(status)) return Colors.white;
    return AppColors.success.withValues(alpha: 0.08);
  }

  Color _statusChipBorder(String status) {
    if (_isConcerningStatus(status)) {
      return AppColors.error.withValues(alpha: 0.25);
    }
    if (_isCautionStatus(status)) {
      return AppColors.warning.withValues(alpha: 0.35);
    }
    return AppColors.success.withValues(alpha: 0.25);
  }

  Color _statusChipTextColor(String status) {
    if (_isConcerningStatus(status)) return AppColors.error;
    if (_isCautionStatus(status)) return AppColors.textSecondary;
    return AppColors.success;
  }

  ({String testName, String value, String status, String remark})
      _parseUltrasoundMetricLine(String line) {
    final cleaned =
        _safeText(line).replaceFirst(RegExp(r'^[-\*•]\s*'), '').trim();

    String testName = '';
    String value = '';
    String status = 'UNKNOWN';
    String remark = '';

    final bracketMatch = RegExp(r'\[(.*?)\]').firstMatch(cleaned);

    if (bracketMatch != null) {
      status = bracketMatch.group(1)!.trim().toUpperCase();
      testName = cleaned.substring(0, bracketMatch.start).trim();

      final colonIdx = testName.indexOf(':');
      if (colonIdx != -1) {
        value = testName.substring(colonIdx + 1).trim();
        testName = testName.substring(0, colonIdx).trim();
      }

      remark = cleaned.substring(bracketMatch.end).trim();
      remark = remark.replaceFirst(RegExp(r'^[-:]\s*'), '').trim();
    } else {
      final colonIndex = cleaned.indexOf(':');
      if (colonIndex != -1) {
        testName = cleaned.substring(0, colonIndex).trim();
        String rest = cleaned.substring(colonIndex + 1).trim();

        final parenMatch = RegExp(r'\(([^)]+)\)$').firstMatch(rest);
        if (parenMatch != null) {
          remark = parenMatch.group(1)!.trim();
          rest = rest.substring(0, parenMatch.start).trim();
        }

        if (rest.startsWith('✓') ||
            rest.toLowerCase() == 'normal' ||
            rest.toLowerCase() == 'present') {
          value = 'Present / Normal';
          status = 'NORMAL';
        } else if (rest.startsWith('X') ||
            rest.startsWith('✗') ||
            rest.toLowerCase() == 'abnormal' ||
            rest.toLowerCase() == 'absent') {
          value = 'Absent / Abnormal';
          status = 'ABNORMAL';
        } else {
          final dashIndex = rest.lastIndexOf('-');
          if (dashIndex != -1) {
            final possibleStatus =
                rest.substring(dashIndex + 1).trim().toUpperCase();
            if (possibleStatus == 'NORMAL' ||
                possibleStatus == 'ABNORMAL' ||
                possibleStatus == 'REVIEW' ||
                possibleStatus == 'MONITOR' ||
                possibleStatus == 'BORDERLINE' ||
                possibleStatus == 'CONCERNING') {
              status = possibleStatus;
              value = rest.substring(0, dashIndex).trim();
            } else {
              value = rest;
            }
          } else {
            value = rest;
          }
        }
      } else {
        return (testName: cleaned, value: '', status: 'UNKNOWN', remark: '');
      }
    }

    if (status == 'CONCERNING') status = 'ABNORMAL';

    return (testName: testName, value: value, status: status, remark: remark);
  }

  Widget _buildMetricsList(List<String> lines) {
    final rows = lines
        .map(_parseUltrasoundMetricLine)
        .where((r) => r.testName.isNotEmpty)
        .toList();

    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 8),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    line.replaceFirst(RegExp(r'^[-\-*]\s*'), '').trim(),
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.map((row) {
        final bool isNonExpected =
            _isConcerningStatus(row.status) || _isCautionStatus(row.status);
        final bool isCaution = _isCautionStatus(row.status);
        final statusColor = _statusChipTextColor(row.status);

        final borderColor = isNonExpected
            ? (isCaution
                ? AppColors.warning.withValues(alpha: 0.25)
                : statusColor.withValues(alpha: 0.25))
            : AppColors.borderPrimary;
        final cardBgColor = isNonExpected
            ? (isCaution
                ? AppColors.warning.withValues(alpha: 0.04)
                : statusColor.withValues(alpha: 0.04))
            : Colors.white;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
            color: cardBgColor,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row with status pill on the right
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      row.testName,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (row.status != 'UNKNOWN' && row.status != 'INFO')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusChipBackground(row.status),
                        borderRadius: BorderRadius.circular(999),
                        border:
                            Border.all(color: _statusChipBorder(row.status)),
                      ),
                      child: Text(
                        _safeStatusLabel(row.status, _selectedLanguage),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                ],
              ),
              if (row.value.isNotEmpty &&
                  row.value != 'Present / Normal' &&
                  row.value != 'Absent / Abnormal') ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    row.value,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (row.remark.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      row.status == 'ABNORMAL'
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 14,
                      color: row.status == 'ABNORMAL'
                          ? AppColors.error
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        row.remark,
                        style: TextStyle(
                          fontSize: 11,
                          color: row.status == 'ABNORMAL'
                              ? AppColors.error.withValues(alpha: 0.85)
                              : AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Auto-generate brief explanation for non-expected measurements
              if (isNonExpected && row.remark.isEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      row.status == 'ABNORMAL'
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 14,
                      color: row.status == 'ABNORMAL'
                          ? AppColors.error
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _selectedLanguage == 'filipino'
                            ? 'Ang sukat na ito ay bahagyang lumihis sa karaniwang inaasahang saklaw. Iminumungkahi ang pagkonsulta sa iyong doktor o komadrona para sa karagdagang pagsusuri.'
                            : 'This measurement is slightly outside the commonly expected range. Consultation with your healthcare provider is recommended for further evaluation.',
                        style: TextStyle(
                          fontSize: 11,
                          color: row.status == 'ABNORMAL'
                              ? AppColors.error.withValues(alpha: 0.85)
                              : AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  String _translateLine(String line, String lang) {
    var result = line;

    // Apply clinical softening for polyhydramnios first for both languages
    if (lang == 'filipino') {
      final polyReg = RegExp(r'\bmild\s+polyhydramnios\b|\bpolyhydramnios\b',
          caseSensitive: false);
      result = result.replaceAll(polyReg,
          'Ang naitalang sukat ng amniotic fluid ay mukhang mas mataas nang bahagya sa karaniwang inaasahang saklaw at maaaring makinabang sa patuloy na pagsubaybay.');
    } else {
      final polyReg = RegExp(r'\bmild\s+polyhydramnios\b|\bpolyhydramnios\b',
          caseSensitive: false);
      result = result.replaceAll(polyReg,
          'The recorded amniotic fluid measurement appears slightly higher than the commonly expected range and may benefit from continued prenatal monitoring.');
    }

    if (lang == 'english') return result;

    final translations = {
      'recorded fetal measurements appear generally consistent for this stage':
          'ang mga naitalang sukat ng baby ay pangkalahatang tugma para sa yugtong ito',
      'recorded fetal measurements appear generally consistent':
          'ang mga naitalang sukat ng baby ay pangkalahatang tugma',
      'recorded measurements appear generally consistent for this stage':
          'ang mga naitalang sukat ay pangkalahatang tugma para sa yugtong ito',
      'recorded measurements appear generally consistent':
          'ang mga naitalang sukat ay pangkalahatang tugma',
      'pregnancy monitoring measurements':
          'mga sukat sa pagsubaybay ng pagbubuntis',
      'growth measurements appear generally consistent for this stage':
          'ang mga sukat ng paglaki ng baby ay pangkalahatang tugma para sa yugtong ito',
      'continued healthcare monitoring may help support pregnancy health':
          'ang patuloy na pagsubaybay sa kalusugan ay makakatulong sa iyong pagbubuntis',
      'This AI-assisted explanation restates the findings recorded by the sonologist in simpler words, adds nothing of its own, and is intended only for healthcare monitoring support and does not replace professional medical consultation.':
          'Ang AI-assisted na paliwanag na ito ay muling isinasalaysay lamang sa simpleng salita ang natuklasan ng sonologist at suporta lamang sa pagsubaybay at hindi pumapalit sa propesyonal na payong medikal.',
      'Continued prenatal checkups and healthcare consultation may help support pregnancy health':
          'Ang patuloy na prenatal checkup at konsultasyon sa doktor ay makakatulong upang maging ligtas ang iyong pagbubuntis.',
      'skull': 'ulo / bungo',
      'brain': 'utak',
      'face': 'mukha',
      'heart': 'puso',
      'spine': 'gulugod / spine',
      'limbs': 'mga braso at binti',
      'hands': 'mga kamay',
      'feet': 'mga paa',
      'stomach': 'tiyan',
      'bladder': 'pantog',
      'kidneys': 'bato / kidneys',
      'cervix': 'sipit-sipitan / cervix',
      'placenta': 'plasenta / inunan',
      'Underweight BMI': 'Mababa ang BMI (Underweight)',
      'Overweight BMI': 'Mataas ang BMI (Overweight)',
      'Obese BMI': 'Sobrang Taas ng BMI (Obese)',
      'Multiple Pregnancy': 'Kambal o Higit Pa (Multiple Pregnancy)',
      'AOG Discrepancy (LMP vs AI)':
          'May Pagkakaiba sa Edad ng Baby (AOG Discrepancy)',
      'Patient Name Mismatch': 'Hindi Tugma ang Pangalan sa Ultrasound',
      'No high-risk complications detected':
          'Walang nakitang kumplikasyon o mataas na panganib',
    };

    translations.forEach((eng, fil) {
      final reg = RegExp(RegExp.escape(eng), caseSensitive: false);
      result = result.replaceAll(reg, fil);
    });

    return result;
  }

  String _cleanBilingualText(String text, String language) {
    final filipinoIndex = text.indexOf('=== FILIPINO ===');
    final englishIndex = text.indexOf('=== ENGLISH ===');

    if (filipinoIndex != -1 && englishIndex != -1) {
      if (filipinoIndex < englishIndex) {
        final filipino = text
            .substring(filipinoIndex + '=== FILIPINO ==='.length, englishIndex)
            .trim();
        final english =
            text.substring(englishIndex + '=== ENGLISH ==='.length).trim();
        return language == 'filipino' ? filipino : english;
      } else {
        final english = text
            .substring(englishIndex + '=== ENGLISH ==='.length, filipinoIndex)
            .trim();
        final filipino =
            text.substring(filipinoIndex + '=== FILIPINO ==='.length).trim();
        return language == 'filipino' ? filipino : english;
      }
    } else if (filipinoIndex != -1) {
      return text.substring(filipinoIndex + '=== FILIPINO ==='.length).trim();
    } else if (englishIndex != -1) {
      return text.substring(englishIndex + '=== ENGLISH ==='.length).trim();
    }
    return text.trim();
  }

  Widget _buildStructuredInsights(String text) {
    final cleanedText = _cleanBilingualText(text, _selectedLanguage);
    final sections = _extractInsightSections(cleanedText);
    if (sections.isEmpty) return _buildFormattedText(cleanedText);

    final sectionOrder = [
      'OVERALL HEALTH STATUS',
      'OVERALL ASSESSMENT',
      'GESTATIONAL AGE ASSESSMENT',
      'DETAILED MEASUREMENTS ASSESSMENT',
      'ANATOMICAL ASSESSMENT',
      'ABNORMAL FINDINGS',
      'RECOMMENDED NEXT ACTIONS',
      'RECOMMENDATIONS',
      'KEY OBSERVATIONS',
      'SUMMARY',
    ];

    final orderedEntries = <MapEntry<String, List<String>>>[];
    for (final key in sectionOrder) {
      if (sections.containsKey(key)) {
        orderedEntries.add(MapEntry(key, sections[key]!));
      }
    }
    for (final entry in sections.entries) {
      if (!sectionOrder.contains(entry.key)) {
        orderedEntries.add(entry);
      }
    }

    final widgets = <Widget>[];
    for (final entry in orderedEntries) {
      if (entry.key == 'RELEVANCE CHECK' ||
          entry.key == 'RELEVANCE REASON' ||
          entry.key == 'OVERALL HEALTH STATUS' ||
          entry.key == 'GESTATIONAL AGE ASSESSMENT') {
        continue;
      }

      final isMeasurements = entry.key == 'DETAILED MEASUREMENTS ASSESSMENT';
      final isAnatomical = entry.key == 'ANATOMICAL ASSESSMENT';
      final isAbnormal = entry.key == 'ABNORMAL FINDINGS';
      final isRecommendation = entry.key.contains('RECOMMENDED') ||
          entry.key.contains('RECOMMENDATION');

      Color accentColor;
      IconData icon;
      if (entry.key.contains('HEALTH STATUS')) {
        final hasHealthy =
            entry.value.any((v) => v.toLowerCase().contains('healthy'));
        accentColor = hasHealthy ? AppColors.success : AppColors.warning;
        icon = Icons.monitor_heart_outlined;
      } else if (isMeasurements) {
        accentColor = Colors.teal;
        icon = Icons.straighten;
      } else if (isAnatomical) {
        accentColor = AppColors.success;
        icon = Icons.child_care_outlined;
      } else if (isAbnormal) {
        accentColor = AppColors.error;
        icon = Icons.warning_amber_rounded;
      } else if (isRecommendation) {
        accentColor = Colors.blue;
        icon = Icons.lightbulb_outline;
      } else {
        accentColor = AppColors.brandPrimary;
        icon = Icons.article_outlined;
      }

      var lines = List<String>.from(entry.value)
          .map((line) => _translateLine(line, _selectedLanguage))
          .toList();

      if (isRecommendation) {
        lines = _selectedLanguage == 'filipino'
            ? [
                '• Ipagpatuloy ang regular na prenatal checkup at konsultasyon sa iyong doktor o komadrona.',
                '• Ipaalam at talakayin ang mga naitalang obserbasyon sa iyong ultrasound sa iyong doktor o komadrona.',
                '• Maaaring imungkahi ang susunod na ultrasound upang masubaybayan ang paglaki ng baby sa paglipas ng panahon.',
              ]
            : [
                '• Continue regular prenatal visits and healthcare consultation.',
                '• Discuss the recorded ultrasound findings with your healthcare provider or midwife.',
                '• Follow-up ultrasound monitoring may help observe how the findings progress over time.',
              ];

        if (_maternalAllergies.isNotEmpty) {
          if (_selectedLanguage == 'filipino') {
            lines.add(
                '⚠️ Mag-ingat dahil may naitalang allergy si Mommy: ${_maternalAllergies.join(", ")}. Ipaalam ito sa doktor bago uminom ng anumang gamot o supplement.');
          } else {
            lines.add(
                '⚠️ Caution: The mother has recorded allergies to: ${_maternalAllergies.join(", ")}. Inform the doctor before taking any medication or supplements.');
          }
        }
        if (_maternalActiveConditions.isNotEmpty) {
          if (_selectedLanguage == 'filipino') {
            lines.add(
                '🩺 Dahil sa naitalang kondisyong medikal (${_maternalActiveConditions.join(", ")}), iminumungkahi ang patuloy at masusing pagsubaybay kasama ang iyong doktor o komadrona.');
          } else {
            lines.add(
                '🩺 Due to active medical conditions (${_maternalActiveConditions.join(", ")}), continued and close monitoring with your doctor or midwife is recommended.');
          }
        }
      }

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
                accentColor.withValues(alpha: isRecommendation ? 0.10 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  accentColor.withValues(alpha: isRecommendation ? 0.45 : 0.3),
              width: isRecommendation ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _friendlySectionTitle(entry.key),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (isMeasurements) ...[
                Text(
                  _selectedLanguage == 'filipino'
                      ? 'Ang naitalang sukat sa paglaki ng baby ay pangkalahatang tugma sa expected monitoring range para sa humigit-kumulang ${_extractWeeksFromAiText(_combinedResponse?.gestationalAge) ?? 20} linggo ng pagbubuntis.'
                      : 'The recorded fetal growth measurements generally appear consistent with the expected monitoring range for approximately ${_extractWeeksFromAiText(_combinedResponse?.gestationalAge) ?? 20} weeks of pregnancy.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      _selectedLanguage == 'filipino'
                          ? 'Tingnan ang Detalyadong Sukat (Para sa Midwife)'
                          : 'View Detailed Measurements (Healthcare Personnel)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    iconColor: accentColor,
                    collapsedIconColor: accentColor,
                    childrenPadding: const EdgeInsets.only(top: 8),
                    children: [
                      _buildMetricsList(lines),
                    ],
                  ),
                ),
              ] else if (isAnatomical) ...[
                Text(
                  _selectedLanguage == 'filipino'
                      ? 'Ang mga naitalang obserbasyon sa ultrasound ay pangkalahatang tugma sa inaasahang pagsubaybay para sa yugtong ito ng pagbubuntis.'
                      : 'The recorded ultrasound findings generally appear consistent with the expected monitoring range for this stage of pregnancy.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                ...() {
                  final flagged = lines.where((line) {
                    final parsed = _parseUltrasoundMetricLine(line);
                    return parsed.status != 'NORMAL' &&
                        parsed.status != 'SUCCESS';
                  }).toList();

                  if (flagged.isNotEmpty) {
                    return [
                      const SizedBox(height: 12),
                      _buildGroupedAnatomicalAssessment(lines),
                    ];
                  }
                  return <Widget>[];
                }(),
              ] else if (isAbnormal)
                _buildMetricsList(lines)
              else
                ...lines.map((line) {
                  final cleaned =
                      line.replaceFirst(RegExp(r'^[•\-*]\s*'), '').trim();

                  final isAlert = cleaned.contains('⚠️') ||
                      cleaned.contains('🩺') ||
                      cleaned.contains('✅');
                  if (isAlert) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildFormattedText(cleaned),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6, right: 8),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(child: _buildFormattedText(cleaned)),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    }

    final disclaimerWidget = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedLanguage == 'filipino'
                  ? 'Paunawa: Ang AI-assisted na paliwanag na ito ay muling isinasalaysay lamang sa simpleng salita ang natuklasan ng sonologist at suporta lamang sa pagsubaybay at hindi pumapalit sa propesyonal na payong medikal ng doktor o komadrona.'
                  : 'Disclaimer: This AI-assisted explanation restates the findings recorded by the sonologist in simpler words, adds nothing of its own, and is intended only for healthcare monitoring support and does not replace professional medical consultation.',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    widgets.add(disclaimerWidget);

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  String _friendlySectionTitle(String title) {
    final friendly = _friendlySectionTitleRaw(title);
    if (_selectedLanguage == 'filipino') {
      switch (friendly) {
        case 'Health Status':
          return 'Kalagayan ng Kalusugan';
        case 'Overall Assessment':
          return 'Pangkalahatang Pagsusuri';
        case 'Gestational Age':
          return 'Gulang ng Pagbubuntis (AOG)';
        case 'Baby Growth Monitoring':
          return 'Pagsubaybay sa Paglaki ng Baby';
        case 'Pregnancy Monitoring Summary':
          return 'Buod ng Pagsubaybay sa Pagbubuntis';
        case 'Abnormal Findings / Concerns':
          return 'Mga Flagged na Obserbasyon';
        case 'Recommended Next Steps':
          return 'Mga Mungkahing Hakbang';
        default:
          return friendly;
      }
    }
    return friendly;
  }

  String _friendlySectionTitleRaw(String title) {
    switch (title) {
      case 'OVERALL HEALTH STATUS':
        return 'Health Status';
      case 'OVERALL ASSESSMENT':
        return 'Overall Assessment';
      case 'GESTATIONAL AGE ASSESSMENT':
        return 'Gestational Age';
      case 'DETAILED MEASUREMENTS ASSESSMENT':
        return 'Baby Growth Monitoring';
      case 'ANATOMICAL ASSESSMENT':
        return 'Pregnancy Monitoring Summary';
      case 'ABNORMAL FINDINGS':
        return 'Abnormal Findings / Concerns';
      case 'RECOMMENDED NEXT ACTIONS':
      case 'RECOMMENDATIONS':
        return 'Recommended Next Steps';
      default:
        return title
            .split(' ')
            .map((w) =>
                w.isNotEmpty ? '${w[0]}${w.substring(1).toLowerCase()}' : w)
            .join(' ');
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Add Ultrasound Images',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade800,
                ),
              ),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.photo_library, color: Colors.teal.shade700),
              ),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Select multiple images'),
              onTap: () {
                Navigator.pop(context);
                _pickImages();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.camera_alt, color: Colors.blue.shade700),
              ),
              title: const Text('Take a Photo'),
              subtitle: const Text('Capture new image'),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLoadingOverlay(int runId) {
    _loadingOverlayVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.35),
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.faintWhite,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Circular container with loading spinner
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandPrimary, width: 3),
                  ),
                  child: const CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  _loadingTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                // Detail subtitle
                Text(
                  _loadingDetail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                // Cancel button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      _cancelledRunIds.add(runId);
                      Navigator.of(context).pop();
                      _loadingOverlayVisible = false;
                      _showMessage('AI analysis canceled.',
                          type: AppSnackType.info);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      side: const BorderSide(
                        color: AppColors.borderPrimary,
                        width: 1.5,
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      _loadingOverlayVisible = false;
    });
  }

  void _closeLoadingOverlayIfNeeded() {
    if (!_loadingOverlayVisible || !mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _loadingOverlayVisible = false;
  }

  void _enterEditMode() {
    final rawText = _healthSummaryController.text;
    final sections = _extractInsightSections(rawText);

    // Determine monitoring range
    final statusText =
        (sections['OVERALL HEALTH STATUS'] ?? []).join(' ').toLowerCase();
    final isHealthy = statusText.contains('healthy') ||
        statusText.isEmpty ||
        _getHealthStatus() == 'HEALTHY PREGNANCY' ||
        _getHealthStatus() == 'ASSESSMENT COMPLETE';
    _editMonitoringRange = isHealthy;

    // Load pregnancy summary (OVERALL ASSESSMENT / SUMMARY)
    final summaryLines = [
      ...(sections['OVERALL ASSESSMENT'] ?? []),
      ...(sections['SUMMARY'] ?? []),
    ];
    _editPregnancySummaryController.text = summaryLines.join('\n');

    // Parse Baby Growth (GESTATIONAL AGE ASSESSMENT / DETAILED MEASUREMENTS ASSESSMENT / ANATOMICAL ASSESSMENT)
    final growthLines = [
      ...(sections['GESTATIONAL AGE ASSESSMENT'] ?? []),
      ...(sections['DETAILED MEASUREMENTS ASSESSMENT'] ?? []),
      ...(sections['ANATOMICAL ASSESSMENT'] ?? []),
    ];

    final List<String> introLines = [];
    final List<({String testName, String value, String status, String remark})>
        parsedMeasures = [];

    for (final line in growthLines) {
      final parsed = _parseUltrasoundMetricLine(line);
      if (parsed.status == 'UNKNOWN' || parsed.testName.isEmpty) {
        introLines.add(line);
      } else {
        parsedMeasures.add(parsed);
      }
    }

    _editBabyGrowthIntro = introLines.join('\n');
    _editBabyGrowthIntroController.text = _editBabyGrowthIntro;

    // Dispose old measurement controllers to prevent leaks
    for (final ctrl in _editBabyGrowthValueControllers) {
      ctrl.dispose();
    }
    for (final ctrl in _editBabyGrowthRemarkControllers) {
      ctrl.dispose();
    }

    _editBabyGrowthMeasurements = parsedMeasures;
    _editBabyGrowthValueControllers = parsedMeasures
        .map((m) => TextEditingController(text: m.value))
        .toList();
    _editBabyGrowthRemarkControllers = parsedMeasures
        .map((m) => TextEditingController(text: m.remark))
        .toList();

    // Load key observations (KEY OBSERVATIONS / ABNORMAL FINDINGS)
    final obsLines = [
      ...(sections['KEY OBSERVATIONS'] ?? []),
      ...(sections['ABNORMAL FINDINGS'] ?? []),
    ];
    _editKeyObservationsController.text = obsLines.join('\n');

    // Load next steps (RECOMMENDED NEXT ACTIONS / RECOMMENDATIONS)
    final stepsLines = [
      ...(sections['RECOMMENDED NEXT ACTIONS'] ?? []),
      ...(sections['RECOMMENDATIONS'] ?? []),
    ];
    _editNextStepsController.text = stepsLines.join('\n');

    setState(() {
      _healthSummaryBeforeEdit = rawText;
      _isEditing = true;
    });
  }

  void _saveEditDraft() {
    final rangeText = _editMonitoringRange
        ? 'Healthy pregnancy (Within expected monitoring range)'
        : 'Requires closer monitoring';

    final compiled = StringBuffer();
    compiled.writeln('OVERALL HEALTH STATUS: $rangeText');

    final summaryVal = _editPregnancySummaryController.text.trim();
    if (summaryVal.isNotEmpty) {
      compiled.writeln('OVERALL ASSESSMENT:');
      compiled.writeln(summaryVal);
    }

    // Compile Baby Growth Intro under GESTATIONAL AGE ASSESSMENT
    final introVal = _editBabyGrowthIntroController.text.trim();
    if (introVal.isNotEmpty) {
      compiled.writeln('GESTATIONAL AGE ASSESSMENT:');
      compiled.writeln(introVal);
    }

    // Compile Measurements under DETAILED MEASUREMENTS ASSESSMENT
    if (_editBabyGrowthMeasurements.isNotEmpty) {
      compiled.writeln('DETAILED MEASUREMENTS ASSESSMENT:');
      for (int i = 0; i < _editBabyGrowthMeasurements.length; i++) {
        final m = _editBabyGrowthMeasurements[i];
        final val = _editBabyGrowthValueControllers[i].text.trim();
        final remark = _editBabyGrowthRemarkControllers[i].text.trim();
        final statusPart = '[${m.status}]';
        final remarkPart = remark.isNotEmpty ? ' ($remark)' : '';
        compiled.writeln('• ${m.testName}: $val $statusPart$remarkPart');
      }
    }

    final obsVal = _editKeyObservationsController.text.trim();
    if (obsVal.isNotEmpty) {
      compiled.writeln('KEY OBSERVATIONS:');
      compiled.writeln(obsVal);
    }

    final stepsVal = _editNextStepsController.text.trim();
    if (stepsVal.isNotEmpty) {
      compiled.writeln('RECOMMENDED NEXT ACTIONS:');
      compiled.writeln(stepsVal);
    }

    setState(() {
      _healthSummaryController.text = compiled.toString();
      _isEditing = false;
      _analysisApproved = false; // Reset approval so midwife reviews
    });

    _showMessage('Assessment changes draft updated.',
        type: AppSnackType.success);
  }

  String _getHealthStatus() {
    if (_combinedResponse == null) return 'Assessment Complete';

    final sections = _extractInsightSections(_healthSummaryController.text);
    final healthStatus = sections['OVERALL HEALTH STATUS'] ?? const <String>[];

    if (healthStatus.isNotEmpty) {
      final statusText = healthStatus.join(' ').toLowerCase();
      if (statusText.contains('healthy')) return 'HEALTHY PREGNANCY';
      if (statusText.contains('monitoring') ||
          statusText.contains('follow-up')) {
        return 'REQUIRES MONITORING';
      }
    }

    final abnormal = sections['ABNORMAL FINDINGS'] ?? const <String>[];
    if (abnormal.isNotEmpty) return 'REVIEW FLAGGED FINDINGS';

    return 'ASSESSMENT COMPLETE';
  }

  List<String> _getCloserMonitoringReasons() {
    final List<String> reasons = [];
    final lang = _selectedLanguage;

    if (_pregnancyFetalCount != null && _pregnancyFetalCount! > 1) {
      reasons.add(lang == 'filipino'
          ? 'Kambal o maramihang pagbubuntis (Multiple pregnancy)'
          : 'Multiple pregnancy (twins/triplets)');
    }

    final bmi = _calculatePrePregnancyBmi();
    if (bmi != null && bmi >= 30.0) {
      reasons.add(lang == 'filipino'
          ? 'Mataas na pre-pregnancy BMI (Obese)'
          : 'High pre-pregnancy BMI (Obese)');
    }

    final age = _calculateMaternalAge();
    if (age != null) {
      if (age < 18) {
        reasons.add(lang == 'filipino'
            ? 'Maagang Edad ng Ina ($age taong gulang)'
            : 'Early Maternal Age ($age years)');
      } else if (age >= 35) {
        reasons.add(lang == 'filipino'
            ? 'Mataas na Edad ng Ina ($age taong gulang)'
            : 'Advanced Maternal Age ($age years)');
      }
    }

    for (final cond in _maternalActiveConditions) {
      reasons.add(lang == 'filipino'
          ? 'Aktibong kondisyong medikal: $cond'
          : 'Active medical condition: $cond');
    }

    if (_hasGestationalAgeDiscrepancy()) {
      reasons.add(lang == 'filipino'
          ? 'Pagkakaiba sa Edad ng Pagbubuntis (AOG Discrepancy)'
          : 'Gestational age discrepancy (2+ weeks difference)');
    }

    if (_isNameMismatch()) {
      reasons.add(lang == 'filipino'
          ? 'Hindi tugmang pangalan sa ultrasound record'
          : 'Patient name mismatch on the uploaded scan');
    }

    if (_combinedResponse != null) {
      final rawText = _healthSummaryController.text;
      final sections = _extractInsightSections(rawText);

      final measurements = sections['DETAILED MEASUREMENTS ASSESSMENT'] ?? [];
      for (final line in measurements) {
        final parsed = _parseUltrasoundMetricLine(line);
        if (parsed.testName.isNotEmpty &&
            (parsed.status == 'ABNORMAL' ||
                parsed.status == 'CONCERNING' ||
                parsed.status == 'REVIEW' ||
                parsed.status == 'BORDERLINE' ||
                parsed.status == 'MONITOR')) {
          reasons.add(lang == 'filipino'
              ? 'Sukat ng ${parsed.testName}: ${parsed.remark.isNotEmpty ? parsed.remark : parsed.value}'
              : 'Measurement of ${parsed.testName}: ${parsed.remark.isNotEmpty ? parsed.remark : parsed.value}');
        }
      }

      final anatomy = sections['ANATOMICAL ASSESSMENT'] ?? [];
      for (final line in anatomy) {
        final parsed = _parseUltrasoundMetricLine(line);
        if (parsed.testName.isNotEmpty &&
            (parsed.status == 'ABNORMAL' ||
                parsed.status == 'CONCERNING' ||
                parsed.status == 'REVIEW' ||
                parsed.status == 'BORDERLINE' ||
                parsed.status == 'MONITOR')) {
          reasons.add(lang == 'filipino'
              ? 'Obserbasyon sa ${parsed.testName}: ${parsed.remark.isNotEmpty ? parsed.remark : parsed.value}'
              : 'Anatomical finding on ${parsed.testName}: ${parsed.remark.isNotEmpty ? parsed.remark : parsed.value}');
        }
      }
    }

    return reasons;
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Ultrasound Date'),
        AppInputField(
          hintText: 'Select Ultrasound Date',
          controller: _dateController,
          isRequired: true,
          leadingIcon: Icons.calendar_today_outlined,
          readOnly: true,
          onTap: _selectDate,
        ),
        const SizedBox(height: 24),

        // Optional Health Worker details card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderPrimary),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.brandPrimary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'AI will automatically extract clinical and health worker details from your uploaded scans. You can also optionally specify them below.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(color: AppColors.borderPrimary, height: 1),
              const SizedBox(height: 18),
              _sectionLabel('Health Worker Name (Optional)'),
              AppInputField(
                hintText: 'e.g. Dr. Jane Doe',
                controller: _healthWorkerNameController,
                isRequired: false,
                leadingIcon: Icons.person_outline,
              ),
              const SizedBox(height: 16),
              _sectionLabel('Institution / Clinic (Optional)'),
              AppInputField(
                hintText: 'e.g. Health Center or Clinic Name',
                controller: _healthWorkerInstitutionController,
                isRequired: false,
                leadingIcon: Icons.local_hospital_outlined,
              ),
              const SizedBox(height: 16),
              _sectionLabel('Profession (Optional)'),
              AppDropdownField<String>(
                value: _selectedHealthWorkerProfession,
                options: _ultrasoundProfessions,
                displayStringForOption: (val) => val,
                onSelected: (val) {
                  setState(() {
                    _selectedHealthWorkerProfession = val;
                  });
                },
                hintText: 'Select Profession',
                leadingIcon: Icons.work_outline,
              ),
              if (_selectedHealthWorkerProfession ==
                  _otherProfessionOption) ...[
                const SizedBox(height: 16),
                _sectionLabel('Specify Profession'),
                AppInputField(
                  hintText: 'e.g. Radiologist, OB-GYN',
                  controller: _healthWorkerProfessionController,
                  isRequired: true,
                  leadingIcon: Icons.work_outline,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary),
        color: AppColors.bgSecondary.withValues(alpha: 0.35),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (int i = 0; i < _selectedImages.length; i++)
            Stack(
              children: [
                Container(
                  width: 98,
                  height: 98,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderPrimary),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: kIsWeb
                        ? Image.network(_selectedImages[i].path,
                            fit: BoxFit.cover)
                        : Image.file(File(_selectedImages[i].path),
                            fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: IconButton(
                    onPressed: () => _removeImage(i),
                    iconSize: 18,
                    splashRadius: 18,
                    color: AppColors.error,
                    icon: const Icon(Icons.cancel),
                  ),
                ),
              ],
            ),
          InkWell(
            onTap: _showImageSourceDialog,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 98,
              height: 98,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.brandPrimary.withValues(alpha: 0.55)),
                color: AppColors.bgSecondary,
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      color: AppColors.brandPrimary),
                  SizedBox(height: 6),
                  Text(
                    'Add Image +',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.brandText,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameMismatchWarning() {
    if (!_isNameMismatch()) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person_search_rounded, color: AppColors.error, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Patient Name Mismatch Detected',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The uploaded ultrasound image contains the patient name "${_combinedResponse?.extractedPatientName}" which does not align with the registered mother "$_motherName".',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Please double check if you uploaded the correct ultrasound scan for this mother.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscrepancyWarning() {
    if (!_hasGestationalAgeDiscrepancy()) return const SizedBox.shrink();

    final expected = _calculateExpectedWeeksAtUltrasound();
    final aiWeeks = _extractWeeksFromAiText(_combinedResponse?.gestationalAge);
    final lmpFormatted =
        _pregnancyLmp != null ? _dateFormat.format(_pregnancyLmp!) : 'N/A';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.info, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestational Age Discrepancy',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Expected Gestational Age on ultrasound date is $expected weeks (calculated from registered LMP: $lmpFormatted). However, the scan analysis indicates a gestational age of $aiWeeks weeks.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (!_datesUpdated) ...[
                  const Text(
                    'Would you like to re-date the mother\'s pregnancy using the ultrasound\'s gestational age measurements?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _reDatePregnancy,
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: const Text('Re-date Pregnancy (LMP & EDD)'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: const [
                      Icon(Icons.check_circle,
                          color: AppColors.success, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Pregnancy successfully re-dated!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUltrasoundAssessmentCard() {
    if (_combinedResponse == null) {
      if (_aiAnalysisSkipped) {
        return Container(
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
                    const Icon(Icons.info_outline,
                        color: AppColors.brandPrimary, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Pregnancy Risk Assessment (AI Skipped)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.25)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.orange, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'AI analysis was skipped. This record will be saved with a plain rule-based monitoring summary.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        const Text(
                          'Pregnancy Risk Override',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppDropdownField<String>(
                            value: _pregnancyRiskLevel,
                            options: const ['low', 'high'],
                            displayStringForOption: (val) =>
                                val == 'low' ? 'Low Risk' : 'High Risk',
                            onSelected: (val) {
                              setState(() {
                                _pregnancyRiskLevel = val;
                                _healthSummaryController.text =
                                    _buildRuleBasedUltrasoundSummary(); // Re-populate based on selected risk
                              });
                            },
                            hintText: 'Select Pregnancy Risk',
                            leadingIcon: Icons.flag_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.borderPrimary, height: 1),
                    const SizedBox(height: 16),
                    const Text(
                      'Overall Pregnancy Risk Factors',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _buildRiskFactorsPills(),
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.borderPrimary, height: 1),
                    const SizedBox(height: 16),

                    // Clinical Findings (Rule-Based Summary)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Clinical Findings',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: AppColors.borderPrimary
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedLanguage = 'filipino';
                                        _healthSummaryController.text =
                                            _buildRuleBasedUltrasoundSummary();
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _selectedLanguage == 'filipino'
                                            ? AppColors.brandPrimary
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Tagalog',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight:
                                              _selectedLanguage == 'filipino'
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                          color: _selectedLanguage == 'filipino'
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedLanguage = 'english';
                                        _healthSummaryController.text =
                                            _buildRuleBasedUltrasoundSummary();
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _selectedLanguage == 'english'
                                            ? AppColors.brandPrimary
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'English',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight:
                                              _selectedLanguage == 'english'
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
                            const SizedBox(width: 8),
                            if (!_isManualEditing)
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _healthSummaryBeforeEdit =
                                        _healthSummaryController.text;
                                    _isManualEditing = true;
                                  });
                                },
                                icon: const Icon(Icons.edit_outlined,
                                    size: 14, color: AppColors.brandPrimary),
                                label: const Text(
                                  'Edit',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.brandPrimary,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!_isManualEditing) ...[
                      _buildStructuredInsights(_healthSummaryController.text),
                      const SizedBox(height: 16),
                    ] else ...[
                      TextField(
                        controller: _healthSummaryController,
                        maxLines: 6,
                        decoration: InputDecoration(
                          hintText: 'Edit clinical findings...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: AppColors.borderPrimary),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _healthSummaryController.text =
                                      _healthSummaryBeforeEdit;
                                  _isManualEditing = false;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                side: const BorderSide(
                                    color: AppColors.borderPrimary),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _isManualEditing = false;
                                });
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.brandPrimary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('Save Draft'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Container(
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
          // Header styled like Prenatal checkup
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.08),
              border: const Border(
                  bottom: BorderSide(color: AppColors.borderPrimary)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: AppColors.brandPrimary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Ultrasound AI-Assisted Assessment',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _monitoringChipColor(_monitoringClassification)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _monitoringChipIcon(_monitoringClassification),
                        size: 14,
                        color: _monitoringChipColor(_monitoringClassification),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        UltrasoundInterpretationEngine.classificationLabel(
                            _monitoringClassification, _selectedLanguage),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              _monitoringChipColor(_monitoringClassification),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_activeRiskTab == 'pregnancy') ...[
                  // Pregnancy Risk Override
                  Row(
                    children: [
                      const Text(
                        'Pregnancy Risk Override',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppDropdownField<String>(
                          value: _pregnancyRiskLevel,
                          options: const ['low', 'high'],
                          displayStringForOption: (val) =>
                              val == 'low' ? 'Low Risk' : 'High Risk',
                          onSelected: (val) {
                            setState(() {
                              _pregnancyRiskLevel = val;
                            });
                          },
                          hintText: 'Select Pregnancy Risk',
                          leadingIcon: Icons.flag_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.borderPrimary, height: 1),
                  const SizedBox(height: 16),

                  // Based on / Risk Factors (always read-only)
                  const Text(
                    'Based on',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _buildRiskFactorsPills(),
                  ),
                ] else ...[
                  if (!_isEditing) ...[
                    // A. Mother-Centered Warm UI Results
                    _buildMaternalUltrasoundResults(),
                    const SizedBox(height: 24),
                    const Divider(color: AppColors.borderPrimary, height: 1),
                    const SizedBox(height: 16),

                    // B. Healthcare Personnel Expandable Panel
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: _showDetailedUltrasoundValues,
                        onExpansionChanged: (expanded) {
                          setState(() {
                            _showDetailedUltrasoundValues = expanded;
                          });
                        },
                        title: Row(
                          children: [
                            const Icon(Icons.settings_outlined,
                                color: AppColors.brandPrimary, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedLanguage == 'filipino'
                                    ? 'Detalyadong Resulta ng Ultrasound (Para sa Midwife)'
                                    : 'Detailed Ultrasound Findings (Healthcare Personnel View)',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.brandPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        tilePadding: EdgeInsets.zero,
                        children: [
                          const SizedBox(height: 12),

                          // Progression card
                          _buildPregnancyProgressionCard(),

                          // Reference basis
                          if (_combinedResponse != null)
                            _buildClinicalReferenceTile(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header + Edit option + structured insights (placed outside the ExpansionTile)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Clinical Findings',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: AppColors.borderPrimary
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedLanguage = 'filipino';
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _selectedLanguage == 'filipino'
                                            ? AppColors.brandPrimary
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Tagalog',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight:
                                              _selectedLanguage == 'filipino'
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                          color: _selectedLanguage == 'filipino'
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedLanguage = 'english';
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _selectedLanguage == 'english'
                                            ? AppColors.brandPrimary
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'English',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight:
                                              _selectedLanguage == 'english'
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
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: _enterEditMode,
                              icon: const Icon(Icons.edit_outlined,
                                  size: 14, color: AppColors.brandPrimary),
                              label: const Text(
                                'Edit',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.brandPrimary,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildStructuredInsights(_healthSummaryController.text),
                    const SizedBox(height: 16),
                  ] else ...[
                    // Premium Modular Sectioned Editor
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section 1: Interactive Pill Switch for Assessment Status
                        const Text(
                          'Pregnancy Assessment Status',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Pill 1: Within Expected Monitoring Range
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _editMonitoringRange = true;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: _editMonitoringRange
                                        ? AppColors.success
                                            .withValues(alpha: 0.9)
                                        : AppColors.success
                                            .withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _editMonitoringRange
                                          ? AppColors.success
                                          : AppColors.success
                                              .withValues(alpha: 0.3),
                                      width: 1.5,
                                    ),
                                    boxShadow: _editMonitoringRange
                                        ? [
                                            BoxShadow(
                                              color: AppColors.success
                                                  .withValues(alpha: 0.2),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: _editMonitoringRange
                                            ? Colors.white
                                            : AppColors.success,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Within Expected Range',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: _editMonitoringRange
                                                ? Colors.white
                                                : AppColors.success,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Pill 2: Requires Closer Monitoring
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _editMonitoringRange = false;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: !_editMonitoringRange
                                        ? AppColors.warning
                                            .withValues(alpha: 0.9)
                                        : AppColors.warning
                                            .withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: !_editMonitoringRange
                                          ? AppColors.warning
                                          : AppColors.warning
                                              .withValues(alpha: 0.3),
                                      width: 1.5,
                                    ),
                                    boxShadow: !_editMonitoringRange
                                        ? [
                                            BoxShadow(
                                              color: AppColors.warning
                                                  .withValues(alpha: 0.2),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.warning_rounded,
                                        size: 16,
                                        color: !_editMonitoringRange
                                            ? Colors.white
                                            : AppColors.warning,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Requires Monitoring',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: !_editMonitoringRange
                                                ? Colors.white
                                                : AppColors.warning,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Section 2: Pregnancy Monitoring Summary
                        _buildModularEditField(
                          label: 'Pregnancy Monitoring Summary',
                          controller: _editPregnancySummaryController,
                          hintText:
                              'Enter general pregnancy state & health review...',
                          icon: Icons.assignment_outlined,
                        ),
                        const SizedBox(height: 16),

                        // Section 3: Baby Growth Monitoring (Structured)
                        _buildEditSectionCard(
                          title: 'Baby Growth Monitoring',
                          icon: Icons.child_care_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fetal Assessment Introduction',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.bgSecondary
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: AppColors.borderPrimary),
                                ),
                                child: TextField(
                                  controller: _editBabyGrowthIntroController,
                                  minLines: 2,
                                  maxLines: 4,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                    height: 1.4,
                                  ),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Enter general gestational age assessment or baby status...',
                                    hintStyle: TextStyle(
                                      color: AppColors.textSecondary
                                          .withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.all(12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Fetal Measurements & Metrics',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_editBabyGrowthMeasurements.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text(
                                    'No individual measurements detected. Edit details in introduction or summary.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                )
                              else
                                ...List.generate(
                                    _editBabyGrowthMeasurements.length,
                                    (index) {
                                  return _buildMeasurementEditRow(index);
                                }),
                            ],
                          ),
                        ),

                        // Section 4: Key Observations
                        _buildModularEditField(
                          label: 'Key Observations & Flagged Findings',
                          controller: _editKeyObservationsController,
                          hintText:
                              'Enter details about placenta, fluid level or concerning signs...',
                          icon: Icons.visibility_outlined,
                        ),
                        const SizedBox(height: 16),

                        // Section 5: Recommended Next Steps
                        _buildModularEditField(
                          label: 'Recommended Next Steps & Plan',
                          controller: _editNextStepsController,
                          hintText:
                              'Enter follow-up schedule, dietary advice or medical referral plan...',
                          icon: Icons.next_plan_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _isEditing = false;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(
                                  color: AppColors.borderPrimary),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saveEditDraft,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.brandPrimary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Save Draft'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],

                // F. Global Approval Checkbox at the very bottom (outside tabs)
                const SizedBox(height: 16),
                const Divider(color: AppColors.borderPrimary, height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _analysisApproved,
                      activeColor: AppColors.brandPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) {
                        setState(() {
                          _analysisApproved = val ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _analysisApproved = !_analysisApproved;
                          });
                        },
                        child: const Text(
                          'I have reviewed and approved this clinical assessment',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Attached Images'),
        const SizedBox(height: 8),
        _buildImageBox(),
        const SizedBox(height: 24),
        _sectionLabel('Notes'),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText:
                'Optional context. AI uses this during analysis if provided.',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildAssessmentTabSwitcher() {
    if (_combinedResponse == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(4),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderPrimary, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _activeRiskTab = 'pregnancy';
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _activeRiskTab == 'pregnancy'
                      ? AppColors.brandPrimary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.gavel_rounded,
                      size: 14,
                      color: _activeRiskTab == 'pregnancy'
                          ? Colors.white
                          : AppColors.brandPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Pregnancy Risk',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _activeRiskTab == 'pregnancy'
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: _activeRiskTab == 'pregnancy'
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                setState(() {
                  _activeRiskTab = 'insight';
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _activeRiskTab == 'insight'
                      ? AppColors.brandPrimary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      size: 14,
                      color: _activeRiskTab == 'insight'
                          ? Colors.white
                          : AppColors.brandPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Ultrasound Insight',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _activeRiskTab == 'insight'
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: _activeRiskTab == 'insight'
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNameMismatchWarning(),
        _buildDiscrepancyWarning(),
        _buildAssessmentTabSwitcher(),
        _buildUltrasoundAssessmentCard(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SecondaryHeader(
              title: 'Ultrasound Assessment',
              onBack: _confirmDiscardAndPop,
              trailing: _selectedImages.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.delete_sweep, color: AppColors.error),
                      onPressed: _clearAll,
                      tooltip: 'Clear all images',
                    )
                  : null,
            ),
            LinearProgressIndicator(
              value: (_step + 1) / _totalSteps,
              backgroundColor: AppColors.borderPrimary,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
              minHeight: 3,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  Text(
                    _stepTitles[_step],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stepSubtitles[_step],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.person,
                                size: 20, color: Colors.teal.shade700),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _motherName,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderPrimary),
                      ),
                      child: Text(
                        _step == 0
                            ? 'Complete ultrasound details first, then continue.'
                            : (_step == 1
                                ? 'Attach images and notes, then run AI analysis.'
                                : 'Review the AI-assisted assessment findings and risk level.'),
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _step == 0
                        ? _buildStep1()
                        : (_step == 1 ? _buildStep2() : _buildStep3()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
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
            child: Builder(
              builder: (context) {
                if (_step == 1) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: MainButton(
                          label: '<',
                          isWhiteVariant: true,
                          fontSize: 13,
                          onPressed: _isSaving ? null : _prevStep,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: MainButton(
                          label: 'Skip Analysis',
                          isWhiteVariant: true,
                          fontSize: 13,
                          onPressed: _isSaving
                              ? null
                              : () {
                                  if (!_validateStep2()) return;
                                  setState(() {
                                    _aiAnalysisSkipped = true;
                                    _combinedResponse = null;
                                    _healthSummaryController.text =
                                        _buildRuleBasedUltrasoundSummary();
                                    _isManualEditing = false;
                                    _analysisApproved = false;
                                    _step =
                                        2; // Move to Step 3: Assessment & Clinical Review
                                  });
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: MainButton(
                          label: 'Analyze',
                          fontSize: 13,
                          onPressed: _isSaving ? null : _analyzeImages,
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    if (_step > 0) ...[
                      Expanded(
                        child: MainButton(
                          label: '<',
                          isWhiteVariant: true,
                          onPressed: _isSaving ? null : _prevStep,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: _buildRightButton(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightButton() {
    if (_step == 0) {
      return MainButton(
        label: 'Next',
        rightIcon: Icons.arrow_forward_ios_rounded,
        onPressed: _isSaving ? null : _nextStep,
      );
    } else if (_step == 1) {
      return Row(
        children: [
          Expanded(
            child: MainButton(
              label: 'Skip Analysis',
              isWhiteVariant: true,
              onPressed: _isSaving
                  ? null
                  : () {
                      if (!_validateStep2()) return;
                      setState(() {
                        _aiAnalysisSkipped = true;
                        _combinedResponse = null;
                        _healthSummaryController.text =
                            _buildRuleBasedUltrasoundSummary();
                        _isManualEditing = false;
                        _analysisApproved = false;
                        _step =
                            2; // Move to Step 3: Assessment & Clinical Review
                      });
                    },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MainButton(
              label: 'Analyze',
              onPressed: _isSaving ? null : _analyzeImages,
            ),
          ),
        ],
      );
    } else {
      return MainButton(
        label: _isSaving ? 'Saving...' : 'Save to Records',
        rightIcon: _isSaving ? null : Icons.check_rounded,
        onPressed: _isSaving ? null : _saveToDatabase,
      );
    }
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
                width: 3,
                height: 12,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                    color: AppColors.brandPrimary,
                    borderRadius: BorderRadius.circular(2))),
            Text(text.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.3)),
          ],
        ),
      );

  Widget _buildEditSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: AppColors.brandPrimary),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildModularEditField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
  }) {
    return _buildEditSectionCard(
      title: label,
      icon: icon,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.6),
              fontSize: 12,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ),
    );
  }

  Widget _buildMeasurementEditRow(int index) {
    final m = _editBabyGrowthMeasurements[index];
    final valueCtrl = _editBabyGrowthValueControllers[index];
    final remarkCtrl = _editBabyGrowthRemarkControllers[index];

    final bool isNormal =
        m.status == 'NORMAL' || m.status == 'UNKNOWN' || m.status.isEmpty;
    final pillText = isNormal ? 'Within Expected Range' : 'Requires Monitoring';
    final pillBg = isNormal
        ? AppColors.success.withValues(alpha: 0.1)
        : AppColors.warning.withValues(alpha: 0.1);
    final pillBorder = isNormal
        ? AppColors.success.withValues(alpha: 0.3)
        : AppColors.warning.withValues(alpha: 0.3);
    final pillTextColor = isNormal ? AppColors.success : AppColors.warning;
    final pillIcon =
        isNormal ? Icons.check_circle_outline : Icons.warning_amber_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  m.testName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                offset: const Offset(0, 36),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                color: Colors.white,
                onSelected: (String statusVal) {
                  setState(() {
                    _editBabyGrowthMeasurements[index] = (
                      testName: m.testName,
                      value: m.value,
                      status: statusVal,
                      remark: m.remark,
                    );
                  });
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'NORMAL',
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: AppColors.success, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Within expected monitoring range',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'ABNORMAL',
                    child: Row(
                      children: [
                        Icon(Icons.warning_rounded,
                            color: AppColors.warning, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Requires Closer Monitoring',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: pillBg,
                    border: Border.all(color: pillBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(pillIcon, size: 12, color: pillTextColor),
                      const SizedBox(width: 4),
                      Text(
                        pillText,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: pillTextColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down,
                          size: 14, color: pillTextColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Value / Measurement',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderPrimary),
                      ),
                      child: TextField(
                        controller: valueCtrl,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          hintText: 'e.g. 72 mm',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Clinical Note / Remark',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderPrimary),
                      ),
                      child: TextField(
                        controller: remarkCtrl,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          hintText: 'e.g. 29 weeks equivalent',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiInsightsEditorPage extends StatefulWidget {
  const _AiInsightsEditorPage({required this.initialText});

  final String initialText;

  @override
  State<_AiInsightsEditorPage> createState() => _AiInsightsEditorPageState();
}

class _AiInsightsEditorPageState extends State<_AiInsightsEditorPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit AI Insights'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 20,
          maxLines: null,
          decoration: const InputDecoration(
            hintText: 'Type or edit AI insights here...',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  final text = _controller.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(context, text);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
