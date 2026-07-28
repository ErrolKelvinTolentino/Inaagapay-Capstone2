// lib/screens/midwife/add_prenatal_checkup_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_storage.dart';
import '../../services/groq_service.dart';
import '../../services/weight_gain_engine.dart';
import '../../models/weight_gain_models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/main_button.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../services/sms_service.dart';
import '../../services/notification_service.dart';

class AddPrenatalCheckupScreen extends StatefulWidget {
  const AddPrenatalCheckupScreen({
    super.key,
    required this.motherId,
    required this.pregnancyId,
    this.lmp,
    this.motherWeight,
    this.motherEmail,
    this.generatedPassword,
    this.takenTdDoses = const [],
    this.isInitialRegistration = false,
  });

  final int motherId;
  final int pregnancyId;
  final DateTime? lmp;
  final double? motherWeight;
  final String? motherEmail;
  final String? generatedPassword;
  final List<String> takenTdDoses;
  final bool isInitialRegistration;

  @override
  State<AddPrenatalCheckupScreen> createState() =>
      _AddPrenatalCheckupScreenState();
}

class SymptomType {
  SymptomType({
    required this.id,
    required this.name,
    required this.riskCategory,
    this.description,
  });

  final int id;
  final String name;
  final String riskCategory;
  final String? description;
}

class _SymptomEntry {
  _SymptomEntry({
    required this.symptomTypeId,
    required this.name,
    required this.riskCategory,
    this.notes,
  });

  final int symptomTypeId;
  final String name;
  final String riskCategory;
  final String? notes;
}

class _RiskFactorItem {
  _RiskFactorItem({
    required this.factor,
    required this.influence,
    this.sourceTable,
    this.sourceId,
  });

  final String factor;
  final String influence; // low | high
  final String? sourceTable;
  final int? sourceId;
}

class _RiskSnapshot {
  _RiskSnapshot({
    required this.level,
    required this.factors,
    required this.notableRecords,
    required this.suggestedActions,
    required this.aiAssessment,
    required this.aiGenerated,
    this.aiModel,
  });

  final String level;
  final List<_RiskFactorItem> factors;
  final List<String> notableRecords;
  final List<String> suggestedActions;
  final String aiAssessment;
  final bool aiGenerated;
  final String? aiModel;

  _RiskSnapshot copyWith({
    String? level,
    List<_RiskFactorItem>? factors,
    List<String>? notableRecords,
    List<String>? suggestedActions,
    String? aiAssessment,
    bool? aiGenerated,
    String? aiModel,
  }) {
    return _RiskSnapshot(
      level: level ?? this.level,
      factors: factors ?? this.factors,
      notableRecords: notableRecords ?? this.notableRecords,
      suggestedActions: suggestedActions ?? this.suggestedActions,
      aiAssessment: aiAssessment ?? this.aiAssessment,
      aiGenerated: aiGenerated ?? this.aiGenerated,
      aiModel: aiModel ?? this.aiModel,
    );
  }
}

// ── BP classification ────────────────────────────────────────────────────────

enum _BpStatus {
  unknown,
  low,
  normal,
  elevated,
  stage1,
  stage2,
  severe;

  String get label {
    switch (this) {
      case _BpStatus.low:
        return 'Low BP';
      case _BpStatus.normal:
        return 'Normal';
      case _BpStatus.elevated:
        return 'Elevated';
      case _BpStatus.stage1:
        return 'HTN Stage 1';
      case _BpStatus.stage2:
        return 'HTN Stage 2';
      case _BpStatus.severe:
        return 'Hypertensive Crisis';
      default:
        return '';
    }
  }

  Color get color {
    switch (this) {
      case _BpStatus.low:
        return AppColors.info;
      case _BpStatus.normal:
        return AppColors.success;
      case _BpStatus.elevated:
        return AppColors.warning;
      case _BpStatus.stage1:
        return const Color(0xFFE65100);
      case _BpStatus.stage2:
        return AppColors.error;
      case _BpStatus.severe:
        return const Color(0xFFB71C1C);
      default:
        return AppColors.textSecondary;
    }
  }

  IconData get icon {
    switch (this) {
      case _BpStatus.low:
        return Icons.arrow_downward_rounded;
      case _BpStatus.normal:
        return Icons.check_circle_rounded;
      case _BpStatus.unknown:
        return Icons.help_outline;
      default:
        return Icons.warning_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AddPrenatalCheckupScreenState extends State<AddPrenatalCheckupScreen> {
  final _groqService = GroqService();
  final _symptomSearchCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _sysCtrl = TextEditingController();
  final _diaCtrl = TextEditingController();
  final _fetalBeatCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  final _ferrousQtyCtrl = TextEditingController();
  final _calciumQtyCtrl = TextEditingController();

  int? _fetalCount;
  int? _originalFetalCount;
  bool _loadingFetalCount = true;

  String _edema = 'none';

  final List<_SymptomEntry> _symptoms = [];
  List<SymptomType> _symptomTypes = [];

  DateTime _checkupDateTime = DateTime.now();
  DateTime? _nextSchedule;

  String? _fetalTone;
  String? _tdDose;

  // inline error texts
  String? _weightError;
  String? _sysError;
  String? _diaError;
  String? _fetalBeatError;
  String? _ferrousError;
  String? _calciumError;

  int _step = 0;
  static const int _totalSteps = 6;
  bool _submitting = false;
  bool _loadingSymptomTypes = false;
  String _symptomRiskFilter = 'all';
  int? _midwifeId;
  int? _accountId;
  bool _loadingRiskPreview = false;
  String? _riskPreviewError;
  _RiskSnapshot? _riskSnapshot;
  String? _lastRiskSignature;
  String? _lastRiskAiPrompt;
  Map<String, dynamic>? _motherRiskContext;
  String _editableRiskLevel = 'low';
  String _pregnancyRiskLevel = 'low';
  List<_RiskFactorItem> _editableRiskFactors = [];

  // ── AI Remarks (Option C) ─────────────────────────────────────────────────
  bool _generatingAiRemarks = false;
  String _remarksSource = 'midwife_authored'; // midwife_authored | ai_generated_approved | ai_generated_edited
  String? _aiOriginalRemarksEn;   // original AI English text (for audit)
  String? _aiOriginalRemarksFil;  // original AI Filipino text (for audit)
  String _remarksLanguage = 'english'; // toggle for bilingual AI remarks
  String _aiRemarksEnglish = '';   // stored AI English text
  String _aiRemarksFilipino = '';  // stored AI Filipino text
  String? _aiRemarksModel;         // AI model used
  double? _initialSessionWeight;   // Locked baseline weight for session calculation

  static const List<String> _fetalTones = [
    'Regular',
    'Irregular',
    'Faint',
    'Absent',
  ];

  static const List<String> _tdOptions = [
    'TD 1',
    'TD 2',
    'TD 3',
    'TD 4',
    'TD 5',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.motherWeight != null) {
      _weightCtrl.text = widget.motherWeight!.toStringAsFixed(1);
    }
    _loadMidwifeId();
    _loadSymptomTypes();
    _loadMotherRiskContext();
    _loadFetalCount();
    _loadLatestCheckupWeight();
    _loadTakenTdDoses();
    _weightCtrl.addListener(_validateWeightInline);
    _sysCtrl.addListener(_validateBpInline);
    _diaCtrl.addListener(_validateBpInline);
    _fetalBeatCtrl.addListener(_validateFetalBeatInline);
    _ferrousQtyCtrl.addListener(_validateFerrousInline);
    _calciumQtyCtrl.addListener(_validateCalciumInline);
    if (_nextSchedule == null) {
      _nextSchedule = _calculateRecommendedNextSchedule();
    }
  }

  void _validateWeightInline() {
    final t = _weightCtrl.text.trim();
    if (t.isEmpty) {
      setState(() => _weightError = null);
      return;
    }
    final v = double.tryParse(t);
    setState(() => _weightError = (v == null)
        ? 'Enter a valid number'
        : (v < 30 || v > 200)
            ? 'Must be 30 – 200 kg'
            : null);
  }

  void _validateBpInline() {
    final sys = int.tryParse(_sysCtrl.text.trim());
    final dia = int.tryParse(_diaCtrl.text.trim());
    setState(() {
      _sysError = _sysCtrl.text.trim().isEmpty
          ? null
          : (sys == null || sys < 70 || sys > 250)
              ? '70 – 250 mmHg'
              : null;
      _diaError = _diaCtrl.text.trim().isEmpty
          ? null
          : (dia == null || dia < 40 || dia > 150)
              ? '40 – 150 mmHg'
              : (sys != null && sys <= dia)
                  ? 'Must be < systolic'
                  : null;
    });
  }

  void _validateFetalBeatInline() {
    final t = _fetalBeatCtrl.text.trim();
    if (t.isEmpty) {
      if (_fetalTone != null) {
        _fetalTone = null;
      }
      setState(() => _fetalBeatError = null);
      return;
    }
    final v = int.tryParse(t);
    setState(() => _fetalBeatError =
        (v == null || v <= 0 || v > 250) ? 'Enter valid bpm (1 – 250)' : null);
  }

  void _validateFerrousInline() {
    final t = _ferrousQtyCtrl.text.trim();
    if (t.isEmpty) {
      setState(() => _ferrousError = null);
      return;
    }
    final v = int.tryParse(t);
    setState(() => _ferrousError =
        (v == null || v < 1 || v > 365) ? '1 – 365 tablets' : null);
  }

  void _validateCalciumInline() {
    final t = _calciumQtyCtrl.text.trim();
    if (t.isEmpty) {
      setState(() => _calciumError = null);
      return;
    }
    final v = int.tryParse(t);
    setState(() => _calciumError =
        (v == null || v < 1 || v > 365) ? '1 – 365 tablets' : null);
  }

  Future<void> _loadFetalCount() async {
    try {
      // Check if there are any saved ultrasound records for this pregnancy
      final ultrasoundRes = await Supabase.instance.client
          .from('ultrasounds')
          .select('ultrasound_id')
          .eq('pregnancy_id', widget.pregnancyId)
          .limit(1);

      final hasUltrasound = ultrasoundRes != null && ultrasoundRes.isNotEmpty;

      final res = await Supabase.instance.client
          .from('pregnancies')
          .select('fetal_count')
          .eq('pregnancy_id', widget.pregnancyId)
          .maybeSingle(); // ← FIXED: Changed from .single()

      if (res != null && mounted) {
        final dbFetalCount = int.tryParse(res['fetal_count']?.toString() ?? '');
        setState(() {
          _originalFetalCount = dbFetalCount;
          // Only reflect fetal count if there are ultrasound records; otherwise display Unknown
          _fetalCount = hasUltrasound ? dbFetalCount : null;
          _loadingFetalCount = false;
        });
      } else {
        if (mounted) setState(() => _loadingFetalCount = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFetalCount = false);
    }
  }

  Future<void> _loadLatestCheckupWeight() async {
    try {
      final res = await Supabase.instance.client
          .from('clinical_encounters')
          .select('''
            encounter_datetime,
            checkup:prenatal_checkups (
              checkup_weight
            )
          ''')
          .eq('pregnancy_id', widget.pregnancyId)
          .eq('encounter_type', 'checkup')
          .order('encounter_datetime', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        final checkupList = res['checkup'] as List?;
        final innerCheckup = checkupList != null && checkupList.isNotEmpty
            ? checkupList.first as Map<String, dynamic>
            : null;
        if (innerCheckup != null && innerCheckup['checkup_weight'] != null && mounted) {
          final latestWeight = double.tryParse(innerCheckup['checkup_weight'].toString());
          if (latestWeight != null) {
            setState(() {
              _weightCtrl.text = latestWeight.toStringAsFixed(1);
            });
          }
        }
      }
    } catch (_) {
      // Non-critical: fall back to widget.motherWeight which is already set
    }
  }

  Future<void> _loadMidwifeId() async {
    final accountId = await AuthStorage.getUserId();
    if (accountId == null) return;
    if (mounted) setState(() => _accountId = accountId);
    try {
      final result = await Supabase.instance.client
          .from('midwives')
          .select('midwife_id')
          .eq('account_id', accountId)
          .maybeSingle(); // ← FIXED: Changed from .single()

      if (result != null && mounted) {
        setState(() => _midwifeId = result['midwife_id'] as int);
      }
    } catch (_) {}
  }

  Future<void> _loadSymptomTypes() async {
    setState(() => _loadingSymptomTypes = true);
    try {
      final rows = await Supabase.instance.client
          .from('symptom_types')
          .select('symptom_type_id, symptom_name, risk_category, description')
          .order('risk_category')
          .order('symptom_name');

      final parsed = (rows as List)
          .map(
            (row) => SymptomType(
              id: row['symptom_type_id'] as int,
              name: row['symptom_name'] as String,
              riskCategory: row['risk_category'] as String,
              description: row['description'] as String?,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() => _symptomTypes = parsed);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Unable to load symptom types. Please try again.');
    } finally {
      if (mounted) setState(() => _loadingSymptomTypes = false);
    }
  }

  Future<void> _loadMotherRiskContext() async {
    try {
      final client = Supabase.instance.client;

      final mother = await client.from('mothers').select('''
            birthdate,
            height,
            weight,
            blood_type
          ''').eq('mother_id', widget.motherId).maybeSingle();

      if (mounted && mother != null) {
        final motherHeight = mother['height']?.toString();
        setState(() {
          if (motherHeight != null && motherHeight.isNotEmpty && motherHeight != 'null') {
            _heightCtrl.text = '$motherHeight cm';
          } else {
            _heightCtrl.text = 'Not recorded in profile';
          }
        });
      }

      final pregnancy = await client.from('pregnancies').select('''
            pregnancy_id,
            status,
            pregnancy_risk_level,
            last_menstrual_period,
            expected_date_of_delivery,
            pre_pregnancy_weight,
            created_at
          ''').eq('pregnancy_id', widget.pregnancyId).maybeSingle();

      final medicalConditions = await client
          .from('medical_conditions')
          .select('condition_name, status, diagnosis_date')
          .eq('mother_id', widget.motherId)
          .order('created_at', ascending: false);

      final allergies = await client
          .from('allergies')
          .select('allergen, status, diagnosis_date')
          .eq('mother_id', widget.motherId)
          .order('created_at', ascending: false);

      final pastPregnancies = await client
          .from('pregnancies')
          .select('pregnancy_id, fetal_count, status, created_at')
          .eq('mother_id', widget.motherId)
          .neq('pregnancy_id', widget.pregnancyId)
          .order('created_at', ascending: false);

      final pastPregnancyIds = (pastPregnancies as List)
          .map((p) => p['pregnancy_id'])
          .whereType<int>()
          .toList();

      List<dynamic> pastPregnancyOutcomes = const [];
      if (pastPregnancyIds.isNotEmpty) {
        try {
          pastPregnancyOutcomes = await client
              .from('pregnancy_outcomes')
              .select('''
                pregnancy_id,
                outcome,
                outcome_date,
                is_outcome_date_estimated
              ''')
              .inFilter('pregnancy_id', pastPregnancyIds)
              .order('outcome_date', ascending: false);
        } catch (_) {
          // Optional table in some deployments; keep fallback logic.
        }
      }

      final rawCheckups = await client
          .from('clinical_encounters')
          .select('''
            encounter_datetime,
            midwife_notes,
            age_of_gestation_weeks,
            age_of_gestation_days,
            checkup:prenatal_checkups (
              encounter_id,
              checkup_weight,
              blood_pressure_systolic,
              blood_pressure_diastolic,
              fetal_heart_beat
            )
          ''')
          .eq('pregnancy_id', widget.pregnancyId)
          .eq('encounter_type', 'checkup')
          .order('encounter_datetime', ascending: false)
          .limit(6);

      final previousCheckups = (rawCheckups as List).map((enc) {
        final innerCheckup = enc['checkup'] as List?;
        final checkupData = innerCheckup != null && innerCheckup.isNotEmpty
            ? innerCheckup.first as Map<String, dynamic>
            : null;
        final weeks = (enc['age_of_gestation_weeks'] as num?)?.toDouble() ?? 0;
        final days = (enc['age_of_gestation_days'] as num?)?.toDouble() ?? 0;
        return {
          'prenatal_checkup_id': checkupData?['encounter_id'],
          'checkup_datetime': enc['encounter_datetime'],
          'age_of_gestation': weeks + days / 7.0,
          'checkup_weight': checkupData?['checkup_weight'],
          'blood_pressure_systolic': checkupData?['blood_pressure_systolic'],
          'blood_pressure_diastolic': checkupData?['blood_pressure_diastolic'],
          'fetal_heart_beat': checkupData?['fetal_heart_beat'],
          'remarks': enc['midwife_notes'],
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _motherRiskContext = {
          'mother': mother,
          'pregnancy': pregnancy,
          'medical_conditions': medicalConditions,
          'allergies': allergies,
          'past_pregnancies': pastPregnancies,
          'past_pregnancy_outcomes': pastPregnancyOutcomes,
          'previous_checkups': previousCheckups,
        };
        final pregLevel =
            pregnancy?['pregnancy_risk_level']?.toString().toLowerCase();
        if (pregLevel != null) {
          _pregnancyRiskLevel = pregLevel;
        }

        final motherHeight = mother?['height']?.toString();
        if (motherHeight != null && motherHeight.isNotEmpty && motherHeight != 'null') {
          _heightCtrl.text = '$motherHeight cm';
        } else {
          _heightCtrl.text = 'Not recorded in profile';
        }

        if (_nextSchedule == null) {
          _nextSchedule = _calculateRecommendedNextSchedule();
        }
      });
    } catch (e, st) {
      debugPrint('Error loading mother risk context: $e\n$st');
      // Risk preview should still work with form-only data.
    }
  }

  DateTime? _tryDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  int? _ageFromBirthdate(DateTime? birthdate) {
    if (birthdate == null) return null;
    return (DateTime.now().difference(birthdate).inDays / 365.25).floor();
  }

  Color _riskLevelColor(String level) {
    switch (level) {
      case 'high':
        return AppColors.error;
      default:
        return AppColors.success;
    }
  }

  String _riskLevelLabel(String level) {
    switch (level) {
      case 'high':
        return 'High Risk';
      default:
        return 'Low Risk';
    }
  }

  String _currentRiskSignature() {
    return [
      _checkupDateTime.toIso8601String(),
      (_fetalCount?.toString() ?? 'null'),
      _edema,
      _weightCtrl.text.trim(),
      _sysCtrl.text.trim(),
      _diaCtrl.text.trim(),
      _fetalBeatCtrl.text.trim(),
      _fetalTone ?? '-',
      _tdDose ?? '-',
      _ferrousQtyCtrl.text.trim(),
      _calciumQtyCtrl.text.trim(),
      _symptoms
          .map((s) => '${s.symptomTypeId}:${s.riskCategory}:${s.notes ?? ''}')
          .join('|'),
      _remarksCtrl.text.trim(),
      _nextSchedule?.toIso8601String() ?? '-',
      (_motherRiskContext?['previous_checkups'] as List? ?? const [])
          .length
          .toString(),
      (_motherRiskContext?['medical_conditions'] as List? ?? const [])
          .length
          .toString(),
      (_motherRiskContext?['allergies'] as List? ?? const []).length.toString(),
      (_motherRiskContext?['past_pregnancies'] as List? ?? const [])
          .length
          .toString(),
      (_motherRiskContext?['past_pregnancy_outcomes'] as List? ?? const [])
          .length
          .toString(),
    ].join('||');
  }

  String _buildMergedAssessmentText(_RiskSnapshot snapshot, String? aiText) {
    final cleanedAiText = _sanitizeAiText(aiText);
    if (cleanedAiText.isNotEmpty) {
      // Strip "AI INSIGHTS:" prefix and any section headers that the AI might have added
      return _stripAiSectionHeaders(cleanedAiText);
    }

    final en = _buildRuleBasedAssessmentText(snapshot);
    final fil = _buildRuleBasedAssessmentTextFilipino(snapshot);
    return '=== FILIPINO ===\n$fil\n\n=== ENGLISH ===\n$en';
  }

  String _stripAiSectionHeaders(String text) {
    var result = text;

    // Remove "AI INSIGHTS:" prefix (case insensitive)
    if (result.toUpperCase().startsWith('AI INSIGHTS:')) {
      result = result.substring('AI INSIGHTS:'.length).trim();
    }

    // Remove common section headers that AI might generate
    final sectionHeaders = [
      'OVERALL ASSESSMENT:',
      'OVERALL HEALTH STATUS:',
      'KEY OBSERVATIONS:',
      'RECOMMENDATIONS:',
      'RECOMMENDED NEXT ACTIONS:',
      'CLINICAL IMPRESSION:',
      'FOLLOW-UP SUGGESTIONS:',
      'DETAILED MEASUREMENTS ASSESSMENT:',
      'ANATOMICAL ASSESSMENT:',
      'GESTATIONAL AGE ASSESSMENT:',
      'LABORATORY RESULTS:',
      'ABNORMAL FINDINGS:',
      'NORMAL RANGES:',
      'SUMMARY:',
    ];

    for (final header in sectionHeaders) {
      if (result.toUpperCase().startsWith(header)) {
        result = result.substring(header.length).trim();
        break;
      }
    }

    return result.trim();
  }

  // Replace the _sanitizeAiText method with this:

  String _sanitizeAiText(String? aiText) {
    final trimmed = aiText?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }

    final lower = trimmed.toLowerCase();

    // Check for fallback indicators
    if (lower.contains('ai insight fallback') ||
        lower.contains('ai insight unavailable') ||
        lower.contains('showing rule-based assessment') ||
        lower.contains('unable to generate') ||
        lower.contains('error generating')) {
      return '';
    }

    return trimmed;
  }

  String _buildRuleBasedAssessmentText(_RiskSnapshot snapshot) {
    final weekStr = _aogWeeks != null ? '${_aogWeeks!.toInt()}' : '7';
    final sysText = _sysCtrl.text.trim();
    final diaText = _diaCtrl.text.trim();
    final bpText = (sysText.isNotEmpty && diaText.isNotEmpty) ? '$sysText/$diaText mmHg' : null;
    final fhrText = _fetalBeatCtrl.text.trim().isNotEmpty ? '${_fetalBeatCtrl.text.trim()} bpm' : null;

    final reasPoints = <String>[];
    if (bpText != null && _bpStatus == _BpStatus.normal) {
      reasPoints.add('Blood pressure ($bpText)');
    }
    if (fhrText != null) {
      reasPoints.add('fetal heart rate ($fhrText)');
    }

    final buf = StringBuffer();
    buf.writeln('Checkup Summary — Week $weekStr AOG');
    buf.writeln();

    if (reasPoints.isNotEmpty) {
      final joined = reasPoints.join(' and ');
      buf.write('$joined ${reasPoints.length > 1 ? "are both" : "is"} within expected range this visit. ');
    } else {
      buf.write('Vitals recorded during this prenatal checkup are documented. ');
    }

    final highFactors = snapshot.factors
        .where((f) => f.influence == 'high')
        .map((f) => f.factor)
        .toList();
    if (highFactors.isEmpty) {
      buf.write('All recorded vitals and findings are progressing smoothly for this stage of pregnancy.');
    } else {
      final itemsText = highFactors.join(', ');
      buf.write('Note that $itemsText — these are worth tracking closely at your next checkup.');
    }

    return buf.toString();
  }

  String _buildRuleBasedAssessmentTextFilipino(_RiskSnapshot snapshot) {
    final weekStr = _aogWeeks != null ? '${_aogWeeks!.toInt()}' : '7';
    final sysText = _sysCtrl.text.trim();
    final diaText = _diaCtrl.text.trim();
    final bpText = (sysText.isNotEmpty && diaText.isNotEmpty) ? '$sysText/$diaText mmHg' : null;
    final fhrText = _fetalBeatCtrl.text.trim().isNotEmpty ? '${_fetalBeatCtrl.text.trim()} bpm' : null;

    final reasPoints = <String>[];
    if (bpText != null && _bpStatus == _BpStatus.normal) {
      reasPoints.add('Ang blood pressure ($bpText)');
    }
    if (fhrText != null) {
      reasPoints.add('fetal heart rate ($fhrText)');
    }

    final buf = StringBuffer();
    buf.writeln('Buod ng Checkup — Linggo $weekStr ng AOG');
    buf.writeln();

    if (reasPoints.isNotEmpty) {
      final joined = reasPoints.join(' at ');
      buf.write('$joined ay parehong nasa karaniwang inaasahang antas sa bisitang ito. ');
    } else {
      buf.write('Naitala nang maayos ang mga resulta para sa prenatal checkup na ito. ');
    }

    final highFactors = snapshot.factors
        .where((f) => f.influence == 'high')
        .map((f) => f.factor)
        .toList();
    if (highFactors.isEmpty) {
      buf.write('Maayos ang lagay ng lahat ng naitalang resulta para sa yugtong ito ng pagbubuntis.');
    } else {
      final itemsText = highFactors.join(', ');
      buf.write('Napansin ang $itemsText — karaniwan itong nababantayan at magandang masubaybayan sa susunod na checkup.');
    }

    return buf.toString();
  }

  Map<String, String> _parseBilingualText(String text) {
    String filipino = '';
    String english = '';

    final filipinoIndex = text.indexOf('=== FILIPINO ===');
    final englishIndex = text.indexOf('=== ENGLISH ===');

    if (filipinoIndex != -1 && englishIndex != -1) {
      if (filipinoIndex < englishIndex) {
        filipino = text
            .substring(filipinoIndex + '=== FILIPINO ==='.length, englishIndex)
            .trim();
        english =
            text.substring(englishIndex + '=== ENGLISH ==='.length).trim();
      } else {
        english = text
            .substring(englishIndex + '=== ENGLISH ==='.length, filipinoIndex)
            .trim();
        filipino =
            text.substring(filipinoIndex + '=== FILIPINO ==='.length).trim();
      }
    } else if (filipinoIndex != -1) {
      filipino =
          text.substring(filipinoIndex + '=== FILIPINO ==='.length).trim();
      english = filipino;
    } else if (englishIndex != -1) {
      english = text.substring(englishIndex + '=== ENGLISH ==='.length).trim();
      filipino = english;
    } else {
      english = text.trim();
      filipino = _translateRuleTextToFilipino(text);
    }

    return {'filipino': filipino, 'english': english};
  }

  String _translateRuleTextToFilipino(String text) {
    final isLow =
        text.contains('everything is looking good') || text.contains('maayos') || text.contains('commonly expected');
    final currentBpMatch = RegExp(r'(\d+/\d+)').firstMatch(text);
    final currentBp = currentBpMatch != null ? currentBpMatch.group(1) : null;

    final buf = StringBuffer();
    if (isLow) {
      buf.write(
          'Sa prenatal checkup ng ina ngayon, maayos at nasa karaniwang antas ang lahat ng vital signs. ');
      if (currentBp != null) {
        buf.write(
            'Ang blood pressure na $currentBp mmHg ay nasa magandang antas para sa kalusugan ng ina. ');
      }
      buf.write(
          'Ang sapat na pahinga at masustansyang pagkain ay nakakatulong sa kalusugan ng ina at ng sanggol. ');
    } else {
      buf.write(
          'May ilang detalye sa prenatal checkup ng ina na kailangang masubaybayan nang mabuti ng healthcare personnel. ');
      if (currentBp != null) {
        buf.write(
            'Ang blood pressure ng ina ay naitala sa $currentBp mmHg sa bisitang ito. ');
      }
      buf.write(
          'Inirerekomenda ang masusing pagsubaybay at pagsunod sa mga payo sa pangangalaga. ');
    }
    buf.write(
        'Ang patuloy na prenatal checkup ay inirerekomenda upang suportahan ang kalusugan ng ina sa buong pagbubuntis.');
    return buf.toString();
  }

  void _syncEditableRiskState(_RiskSnapshot snapshot, String mergedText) {
    _editableRiskLevel = snapshot.level;
    _editableRiskFactors = List<_RiskFactorItem>.from(snapshot.factors);
  }

  bool _sameFactorLists(List<_RiskFactorItem> a, List<_RiskFactorItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].factor != b[i].factor || a[i].influence != b[i].influence) {
        return false;
      }
    }
    return true;
  }

  _RiskSnapshot _buildRuleBasedRiskSnapshot() {
    final factors = <_RiskFactorItem>[];
    final notable = <String>[];
    final actions = <String>[];

    final mother = _motherRiskContext?['mother'] as Map<String, dynamic>?;
    final pregnancy = _motherRiskContext?['pregnancy'] as Map<String, dynamic>?;
    final conditions =
        (_motherRiskContext?['medical_conditions'] as List? ?? const [])
            .cast<dynamic>();
    final pastPregnancies =
        (_motherRiskContext?['past_pregnancies'] as List? ?? const [])
            .cast<dynamic>();
    final pastPregnancyOutcomes =
        (_motherRiskContext?['past_pregnancy_outcomes'] as List? ?? const [])
            .cast<dynamic>();

    final currentLmp =
        _tryDate(pregnancy?['last_menstrual_period']) ?? widget.lmp;
    final today = DateTime.now();

    final systolic = int.tryParse(_sysCtrl.text.trim());
    final diastolic = int.tryParse(_diaCtrl.text.trim());
    final fetalBeat = int.tryParse(_fetalBeatCtrl.text.trim());
    final gaCurrent =
        currentLmp != null ? today.difference(currentLmp).inDays ~/ 7 : null;

    if (gaCurrent != null) {
      notable.add('Current gestational age estimate: $gaCurrent weeks');
    }

    // High Risk Triggers (Binary)
    bool isHigh = false;

    // 1. Blood Pressure Thresholds
    if (systolic != null && diastolic != null) {
      notable.add('Current BP: $systolic/$diastolic mmHg');
      if (systolic >= 140 || diastolic >= 90) {
        isHigh = true;
        factors.add(_RiskFactorItem(
          factor: 'High blood pressure (>=140/90)',
          influence: 'high',
        ));
        actions
            .add('Monitor blood pressure closely and screen for preeclampsia.');
      }
    }

    // 2. Fetal Heart Rate Thresholds
    if (fetalBeat != null) {
      notable.add('Fetal heart rate: $fetalBeat bpm');
      if (fetalBeat < 110 || fetalBeat > 160) {
        isHigh = true;
        factors.add(_RiskFactorItem(
          factor: 'Abnormal fetal heart rate ($fetalBeat bpm)',
          influence: 'high',
        ));
        actions.add(
            'Repeat fetal heart monitoring; correlate with fetal movement.');
      }
    }

    // 3. Danger Symptoms
    final dangerSymptomsFiltered =
        _symptoms.where((s) => s.riskCategory == 'danger').toList();
    if (dangerSymptomsFiltered.isNotEmpty) {
      isHigh = true;
      for (final s in dangerSymptomsFiltered) {
        factors.add(_RiskFactorItem(
          factor: 'Severe symptom: ${s.name}',
          influence: 'high',
        ));
      }
      actions.add('Prioritize immediate care protocol and referral if needed.');
    }

    // 5. Medical History & Pregnancy Context (Watch Items)
    final age = _ageFromBirthdate(_tryDate(mother?['birthdate']));
    if (age != null) {
      if (age < 18 || age >= 35) {
        factors.add(_RiskFactorItem(
          factor: 'Maternal age factor ($age years)',
          influence: 'low',
        ));
      }
    }

    if (_fetalCount != null && _fetalCount! > 1) {
      factors.add(_RiskFactorItem(
        factor: 'Multifetal gestation ($_fetalCount)',
        influence: 'low',
      ));
      actions.add(
          'Monitor closely for preterm labor and growth in multifetal pregnancy.');
    }

    for (final row in conditions) {
      final map = row as Map<String, dynamic>;
      if ((map['status'] ?? '').toString().toLowerCase() == 'active') {
        factors.add(_RiskFactorItem(
          factor: 'Condition: ${map['condition_name']}',
          influence: 'low',
        ));
      }
    }

    // 6. IOM Weight Gain — handled by WeightGainEngine (see AI prompt builder)

    final level = isHigh ? 'high' : 'low';

    final dedupedActions = actions.toSet().toList();
    if (dedupedActions.isEmpty) {
      dedupedActions.add('Continue routine prenatal follow-up and monitoring.');
    }

    final fallbackSnapshot = _RiskSnapshot(
      level: level,
      factors: factors,
      notableRecords: notable,
      suggestedActions: dedupedActions,
      aiAssessment: '',
      aiGenerated: false,
      aiModel: null,
    );

    final fallbackAiText = _buildRuleBasedAssessmentText(fallbackSnapshot);

    return _RiskSnapshot(
      level: level,
      factors: factors,
      notableRecords: notable,
      suggestedActions: dedupedActions,
      aiAssessment: fallbackAiText,
      aiGenerated: false,
      aiModel: null,
    );
  }

  String _buildAiPrompt(_RiskSnapshot draft) {
    final mother = _motherRiskContext?['mother'] as Map<String, dynamic>?;
    final pregnancy = _motherRiskContext?['pregnancy'] as Map<String, dynamic>?;
    final conditions =
        (_motherRiskContext?['medical_conditions'] as List? ?? const [])
            .cast<dynamic>();
    final allergies =
        (_motherRiskContext?['allergies'] as List? ?? const []).cast<dynamic>();
    final pastPregnancies =
        (_motherRiskContext?['past_pregnancies'] as List? ?? const [])
            .cast<dynamic>();
    final pastPregnancyOutcomes =
        (_motherRiskContext?['past_pregnancy_outcomes'] as List? ?? const [])
            .cast<dynamic>();
    final previousCheckups =
        (_motherRiskContext?['previous_checkups'] as List? ?? const [])
            .cast<dynamic>();

    final Map<int, List<Map<String, dynamic>>> outcomesByPregnancy = {};
    for (final row in pastPregnancyOutcomes) {
      if (row is! Map<String, dynamic>) continue;
      final pid = row['pregnancy_id'] as int?;
      if (pid == null) continue;
      outcomesByPregnancy
          .putIfAbsent(pid, () => <Map<String, dynamic>>[])
          .add(row);
    }

    final activeConditionLines = conditions
        .where((c) => (c['status'] ?? '').toString().toLowerCase() == 'active')
        .map((c) {
      final name = (c['condition_name'] ?? 'Unknown condition').toString();
      final diagnosis = (c['diagnosis_date'] ?? '').toString();
      return diagnosis.isEmpty ? '- $name' : '- $name (diagnosed: $diagnosis)';
    }).toList();

    final activeAllergyLines = allergies
        .where((a) => (a['status'] ?? '').toString().toLowerCase() == 'active')
        .map((a) {
      final name = (a['allergen'] ?? 'Unknown allergen').toString();
      final diagnosis = (a['diagnosis_date'] ?? '').toString();
      return diagnosis.isEmpty ? '- $name' : '- $name (noted: $diagnosis)';
    }).toList();

    final pastPregnancyLines = pastPregnancies.map((p) {
      final pid = p['pregnancy_id'] as int?;
      final fetalCount = p['fetal_count']?.toString() ?? '1';
      final linkedOutcomes = pid == null
          ? <Map<String, dynamic>>[]
          : (outcomesByPregnancy[pid] ?? <Map<String, dynamic>>[]);

      if (linkedOutcomes.isNotEmpty) {
        final details = linkedOutcomes.asMap().entries.map((e) {
          final o = e.value;
          final outcome = (o['outcome'] ?? 'unknown').toString();
          final date = (o['outcome_date'] ?? 'unknown').toString();
          final method = (o['delivery_method'] ?? '').toString();
          return 'F${e.key + 1}: $outcome on $date${method.isEmpty ? '' : ', method: $method'}';
        }).join(' | ');
        return '- pregnancy ${pid ?? 'unknown'} (fetal_count: $fetalCount): $details';
      }

      final outcome = (p['outcome'] ?? 'unknown').toString();
      final date = (p['outcome_date'] ?? 'unknown').toString();
      return '- pregnancy ${pid ?? 'unknown'} (fetal_count: $fetalCount): $outcome on $date';
    }).toList();

    final previousCheckupLines = previousCheckups.map((c) {
      final date = (c['checkup_datetime'] ?? 'unknown').toString();
      final weight = (c['checkup_weight'] ?? 'n/a').toString();
      final sys = (c['blood_pressure_systolic'] ?? 'n/a').toString();
      final dia = (c['blood_pressure_diastolic'] ?? 'n/a').toString();
      final fhr = (c['fetal_heart_beat'] ?? 'n/a').toString();
      return '- $date | wt: $weight kg | BP: $sys/$dia | FHR: $fhr';
    }).toList();

    final symptomLines = _symptoms
        .map((s) =>
            '- ${s.name} [${s.riskCategory}]${(s.notes ?? '').trim().isEmpty ? '' : ' | note: ${s.notes!.trim()}'}')
        .toList();

    // Calculate Maternal Age
    final maternalAge = _ageFromBirthdate(_tryDate(mother?['birthdate']));

    // Calculate Weight Gain Evaluation inline using session baseline
    WeightGainResult? wgResult;
    try {
      final currentWeight = double.tryParse(_weightCtrl.text.trim());
      if (currentWeight != null && _aogWeeks != null && _aogWeeks! > 0) {
        final heightCm = mother?['height'] != null
            ? double.tryParse(mother!['height'].toString())
            : null;
        final prePregnancyWeight = pregnancy?['pre_pregnancy_weight'] != null
            ? double.tryParse(pregnancy!['pre_pregnancy_weight'].toString())
            : null;
        final motherWeight = mother?['weight'] != null
            ? double.tryParse(mother!['weight'].toString())
            : null;

        // Get earliest checkup weight if available from history
        double? earliestCheckupWeight;
        if (previousCheckups.isNotEmpty) {
          final sortedPrev = List<Map<String, dynamic>>.from(
              previousCheckups.map((e) => Map<String, dynamic>.from(e as Map)));
          sortedPrev.sort((a, b) {
            final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '');
            final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '');
            if (da == null || db == null) return 0;
            return da.compareTo(db);
          });
          earliestCheckupWeight = double.tryParse(
              sortedPrev.first['checkup_weight']?.toString() ?? '');
        }

        double? baselinePreWeight = prePregnancyWeight ?? motherWeight ?? widget.motherWeight ?? earliestCheckupWeight;
        if (baselinePreWeight == null) {
          _initialSessionWeight ??= currentWeight;
          baselinePreWeight = _initialSessionWeight;
        }

        double? effectivePrePreg = baselinePreWeight;
        if (effectivePrePreg == null && heightCm != null && heightCm > 0) {
          final est = WeightGainEngine.estimatePrePregnancyBMI(
            currentWeightKg: currentWeight,
            heightCm: heightCm,
            aogWeeks: _aogWeeks!.toInt(),
            knownPrePregnancyWeight: baselinePreWeight,
            fetalCount: _fetalCount ?? 1,
          );
          effectivePrePreg = est['estimatedWeight'] as double?;
        }

        final checkupList = previousCheckups
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        checkupList.add({
          'checkup_datetime': _checkupDateTime.toIso8601String(),
          'age_of_gestation': _aogWeeks,
          'checkup_weight': currentWeight,
        });
        checkupList.sort((a, b) => DateTime.parse(a['checkup_datetime'])
            .compareTo(DateTime.parse(b['checkup_datetime'])));

        wgResult = WeightGainEngine.evaluate(
          currentWeight: currentWeight,
          aogWeeks: _aogWeeks!,
          allCheckups: checkupList,
          prePregnancyWeight: effectivePrePreg,
          heightCm: heightCm,
          fetalCount: _fetalCount ?? 1,
        );
      }
    } catch (_) {
      // ignore
    }

    final String wgAssessmentStr;
    if (wgResult != null) {
      final statusName = wgResult.status == WeightGainStatus.low
          ? 'BELOW_EXPECTED_WEIGHT_GAIN'
          : wgResult.status == WeightGainStatus.high
              ? 'ABOVE_EXPECTED_WEIGHT_GAIN'
              : 'WITHIN_EXPECTED_WEIGHT_GAIN';
      final actualStr = wgResult.actualGain != null
          ? "${wgResult.actualGain! >= 0 ? '+' : ''}${wgResult.actualGain!.toStringAsFixed(1)} kg"
          : "+0.0 kg";
      wgAssessmentStr =
          '$statusName (BMI Category: ${wgResult.bmiCategory}, Current Weight Gain: $actualStr)';
    } else {
      wgAssessmentStr = 'Not evaluated';
    }

    final sysVal = int.tryParse(_sysCtrl.text.trim());
    final diaVal = int.tryParse(_diaCtrl.text.trim());
    final String bpAssessmentStr;
    final bool isBpNormal = sysVal != null && diaVal != null && (sysVal >= 90 && sysVal < 120) && (diaVal >= 60 && diaVal < 80);

    if (sysVal != null && diaVal != null) {
      if (sysVal >= 140 || diaVal >= 90) {
        bpAssessmentStr = 'HIGH / STAGE 1-2 HYPERTENSION IN PREGNANCY ($sysVal/$diaVal mmHg - Diastolic $diaVal mmHg >= 90 mmHg. DO NOT SAY THIS IS WITHIN EXPECTED RANGE! PUT THIS IN FLAGGED ITEMS SENTENCE 2!)';
      } else if (sysVal >= 120 || diaVal >= 80) {
        bpAssessmentStr = 'ELEVATED / PRE-HYPERTENSION ($sysVal/$diaVal mmHg - Systolic $sysVal or Diastolic $diaVal is elevated. DO NOT SAY THIS IS WITHIN EXPECTED RANGE! PUT THIS IN FLAGGED ITEMS SENTENCE 2!)';
      } else if (sysVal < 90 || diaVal < 60) {
        bpAssessmentStr = 'LOW / HYPOTENSION ($sysVal/$diaVal mmHg)';
      } else {
        bpAssessmentStr = 'WITHIN EXPECTED RANGE ($sysVal/$diaVal mmHg)';
      }
    } else {
      bpAssessmentStr = 'Not recorded';
    }

    // Compute trimester from gestational age
    final String trimester;
    if (_aogWeeks != null) {
      if (_aogWeeks! <= 12) {
        trimester = '1st trimester';
      } else if (_aogWeeks! <= 27) {
        trimester = '2nd trimester';
      } else {
        trimester = '3rd trimester';
      }
    } else {
      trimester = 'unknown';
    }

    // Compute weight gain trend from previous checkups
    final weightTrendLines = <String>[];
    if (previousCheckups.length >= 2) {
      for (int i = 1; i < previousCheckups.length; i++) {
        final prev = previousCheckups[i - 1];
        final curr = previousCheckups[i];
        final prevW =
            double.tryParse((prev['checkup_weight'] ?? '').toString());
        final currW =
            double.tryParse((curr['checkup_weight'] ?? '').toString());
        if (prevW != null && currW != null) {
          final diff = currW - prevW;
          final prevDate = (prev['checkup_datetime'] ?? '').toString();
          final currDate = (curr['checkup_datetime'] ?? '').toString();
          weightTrendLines.add(
              '- $prevDate to $currDate: ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} kg');
        }
      }
    }

    final aogWeekStr = _aogWeeks != null ? '${_aogWeeks!.toInt()}' : '7';
    final sysText = _sysCtrl.text.trim();
    final diaText = _diaCtrl.text.trim();

    return '''[CRITICAL INSTRUCTIONS - ANATOMY & STRUCTURE MANDATE]

You must structure BOTH the Tagalog and English assessments using this EXACT 3-part formula:

HEADER:
- English header: "Checkup Summary — Week $aogWeekStr AOG"
- Tagalog header: "Buod ng Checkup — Linggo $aogWeekStr ng AOG"

SENTENCE 1: THE REASSURANCE ANCHOR
- Lead ONLY with vitals/findings that are WITHIN EXPECTED RANGE, including ACTUAL NUMBERS (e.g. "Fetal heart rate (${_fetalBeatCtrl.text.trim().isEmpty ? '120 bpm' : _fetalBeatCtrl.text.trim() + ' bpm'}) is within expected range this visit.").
- CRITICAL BLOOD PRESSURE RULE: ONLY include Blood Pressure in Sentence 1 if Blood Pressure Assessment is explicitly "WITHIN EXPECTED RANGE". If BP is HIGH or ELEVATED (e.g. 120/90 mmHg where diastolic >= 80/90 mmHg), DO NOT put BP in Sentence 1! Place BP in Sentence 2 (Flagged Items)!
- NEVER use the word "normal" or "normal values". Use "within expected range" or "within commonly expected range".

SENTENCE 2: THE FLAGGED ITEMS (DATA, COMPARISON, REASSURANCE, SOFT ACTION)
- If weight gain, blood pressure (e.g. 120/90 mmHg), edema, or symptoms are flagged or elevated:
  1. State finding plainly with ACTUAL NUMBERS & COMPARISON (e.g. "Blood pressure was recorded at 120/90 mmHg (elevated diastolic), and weight gain is a bit ahead of pace for this BMI category (+2.0 kg vs. an expected 0–1.2 kg)").
  2. Immediately normalize it if common (e.g. "both are common at this stage and usually settle on their own").
  3. Suggest a soft non-urgent monitoring step (e.g. "but worth tracking closely at your next checkup").
- If NO items are flagged, write: "All recorded vitals and findings are progressing smoothly for this stage of pregnancy."

CRITICAL SAFETY & MIDWIFE POV RULES:
- REMOVE ALL DISCLAIMER LINES. DO NOT include any line like "General summary, not a diagnosis..."!
- MIDWIFE POV MANDATE: The midwife is the healthcare provider entering these remarks! NEVER say "with your midwife or healthcare provider" or "consult your midwife". Say "requires clinical evaluation / doctor consultation" if severe.
- NEVER write "No abnormal vital signs were noted" or claim findings are normal if Blood pressure is HIGH (e.g. 120/100 mmHg) or Edema is Moderate/Severe!
- If Blood pressure is HIGH (diastolic >= 90 mmHg or systolic >= 140 mmHg) or Edema is Moderate/Severe:
  * Sentence 1 (Anchor): Lead ONLY with passed vitals (e.g. "Fetal heart rate (120 bpm) is within expected range this visit.").
  * Sentence 2 (Flagged Items): Plainly state findings: "Blood pressure was recorded at 120/100 mmHg (high diastolic), weight gain is +2.0 kg (above expected), and moderate swelling was observed — these findings require close monitoring and doctor consultation."
- KEEP EACH TRANSLATED SECTION CONCISE AND UNDER 280 CHARACTERS TOTAL.
- Never say "pre-pregnancy weight not provided" or "interpretation is limited".
- Do NOT use diagnostic or alarmist language.
- Do NOT use bullet points, disclaimer footers, or extra headers.

OUTPUT FORMAT REQUIREMENTS:
=== FILIPINO ===
Buod ng Checkup — Linggo $aogWeekStr ng AOG

[Sentence 1: Reassurance Anchor with actual numbers of WITHIN RANGE vitals]
[Sentence 2: Flagged items with comparison, normalization, and soft action OR smooth progress confirmation]

=== ENGLISH ===
Checkup Summary — Week $aogWeekStr AOG

[Sentence 1: Reassurance Anchor with actual numbers of WITHIN RANGE vitals]
[Sentence 2: Flagged items with comparison, normalization, and soft action OR smooth progress confirmation]

GOOD EXAMPLE OUTPUT (BP 120/90 mmHg - Elevated Diastolic):
=== FILIPINO ===
Buod ng Checkup — Linggo $aogWeekStr ng AOG

Ang fetal heart rate (120 bpm) ay nasa karaniwang inaasahang antas sa bisitang ito. Ang blood pressure ay naitala sa 120/90 mmHg (mataas ang diastolic), at ang pagdagdag ng timbang ay bahagyang nauna (+2.0 kg kumpara sa inaasahang 0–1.2 kg) — pareho itong magandang masubaybayan sa susunod na checkup.

=== ENGLISH ===
Checkup Summary — Week $aogWeekStr AOG

Fetal heart rate (120 bpm) is within expected range this visit. Blood pressure was recorded at 120/90 mmHg (elevated diastolic), and weight gain is a bit ahead of pace (+2.0 kg vs. an expected 0–1.2 kg) — both are worth monitoring closely at your next checkup.

TODAY'S CHECKUP
- Weight: ${_weightCtrl.text.trim()} kg
- Weight Gain Assessment: $wgAssessmentStr
- Blood pressure Assessment: $bpAssessmentStr
- Fetal heart beat: ${_fetalBeatCtrl.text.trim().isEmpty ? 'not recorded' : '${_fetalBeatCtrl.text.trim()} bpm'}
- Fetal heart tone: ${_fetalTone ?? 'not recorded'}
- Edema level: ${_edema == 'none' ? 'No swelling' : _edema == 'mild' ? 'Mild swelling in feet or ankles' : _edema == 'moderate' ? 'Moderate swelling in lower legs, feet, or hands' : 'Severe significant swelling in face, hands, and legs'}
- Symptoms reported:
${symptomLines.isEmpty ? '- none' : symptomLines.join('\n')}
- Remarks: ${_remarksCtrl.text.trim().isEmpty ? 'none' : _remarksCtrl.text.trim()}

IMPORTANT: Your response must consist ONLY of the two sections labeled with "=== FILIPINO ===" and "=== ENGLISH ===". No other text or labels.''';
  }

  Future<void> _refreshRiskPreview({bool force = false}) async {
    final signature = _currentRiskSignature();
    if (!force && _lastRiskSignature == signature && _riskSnapshot != null) {
      return;
    }

    final draft = _buildRuleBasedRiskSnapshot();
    setState(() {
      _loadingRiskPreview = true;
      _riskPreviewError = null;
      _riskSnapshot = draft;
    });

    try {
      final prompt = _buildAiPrompt(draft);
      _lastRiskAiPrompt = prompt;
      final aiText = await _groqService.generateTextInsight(
        prompt: prompt,
        temperature: 0.1,
        maxOutputTokens: 2600,
      );

      if (!mounted) return;
      setState(() {
        final mergedText = _buildMergedAssessmentText(draft, aiText);
        _riskSnapshot = _RiskSnapshot(
          level: draft.level,
          factors: draft.factors,
          notableRecords: draft.notableRecords,
          suggestedActions: draft.suggestedActions,
          aiAssessment: mergedText,
          aiGenerated: true,
          aiModel: 'Groq',
        );
        _syncEditableRiskState(_riskSnapshot!, mergedText);
        _lastRiskSignature = signature;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final mergedText = _buildMergedAssessmentText(draft, null);
        _riskSnapshot = _RiskSnapshot(
          level: draft.level,
          factors: draft.factors,
          notableRecords: draft.notableRecords,
          suggestedActions: draft.suggestedActions,
          aiAssessment: mergedText,
          aiGenerated: false,
          aiModel: null,
        );
        _riskPreviewError =
            'AI insight unavailable right now. Showing rule-based assessment.';
        _syncEditableRiskState(_riskSnapshot!, mergedText);
        _lastRiskSignature = signature;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingRiskPreview = false);
      }
    }
  }

  @override
  void dispose() {
    _symptomSearchCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _sysCtrl.dispose();
    _diaCtrl.dispose();
    _fetalBeatCtrl.dispose();
    _remarksCtrl.dispose();
    _ferrousQtyCtrl.dispose();
    _calciumQtyCtrl.dispose();
    super.dispose();
  }

  List<String> _dbTakenTdDoses = [];

  Future<void> _loadTakenTdDoses() async {
    try {
      final res = await Supabase.instance.client
          .from('clinical_encounters')
          .select('prenatal_checkups!inner(td_vaccine_dose)')
          .eq('mother_id', widget.motherId);
      if (res != null && mounted) {
        final doses = <String>[];
        for (final row in (res as List)) {
          final pc = row['prenatal_checkups'];
          if (pc != null) {
            final dose = pc['td_vaccine_dose']?.toString();
            if (dose != null && dose.isNotEmpty && dose != '-') {
              doses.add(dose);
            }
          }
        }
        if (mounted) {
          setState(() {
            _dbTakenTdDoses = doses;
          });
        }
      }
    } catch (_) {}
  }

  Set<String> get _allTakenTdDoses {
    final set = <String>{};
    for (final d in widget.takenTdDoses) {
      if (d.isNotEmpty && d != '-') set.add(d.trim());
    }
    for (final d in _dbTakenTdDoses) {
      if (d.isNotEmpty && d != '-') set.add(d.trim());
    }
    return set;
  }

  int? _parseTdNumber(String doseStr) {
    final match = RegExp(r'\d+').firstMatch(doseStr);
    if (match != null) {
      return int.tryParse(match.group(0)!);
    }
    return null;
  }

  List<String> get _availableTdDoses {
    final takenSet = _allTakenTdDoses;
    int maxTakenDoseNum = 0;
    for (final dose in takenSet) {
      final num = _parseTdNumber(dose);
      if (num != null && num > maxTakenDoseNum) {
        maxTakenDoseNum = num;
      }
    }

    if (maxTakenDoseNum > 0) {
      return _tdOptions.where((opt) {
        final optNum = _parseTdNumber(opt) ?? 0;
        return optNum > maxTakenDoseNum;
      }).toList();
    } else {
      return List.from(_tdOptions);
    }
  }

  DateTime _calculateRecommendedNextSchedule() {
    final baseDate = _normalizedDate(_checkupDateTime);
    final weeks = _aogWeeks ?? 0;
    final isHighRisk = _pregnancyRiskLevel.toLowerCase() == 'high';

    int addDays;
    if (weeks > 40) {
      // Post-term mode: every 3 days with fetal surveillance
      addDays = 3;
    } else if (isHighRisk) {
      // High-risk mode: every 1-2 weeks regardless of trimester
      addDays = weeks >= 28 ? 7 : 14;
    } else {
      // Standard mode:
      // Month 1-6 (weeks < 28): every 4 weeks (28 days)
      // Month 7-8 (weeks 28 - 35.6): every 2 weeks (14 days)
      // Month 9 (weeks 36 - 40): every 1 week (7 days)
      if (weeks < 28) {
        addDays = 28;
      } else if (weeks < 36) {
        addDays = 14;
      } else {
        addDays = 7;
      }
    }

    return baseDate.add(Duration(days: addDays));
  }

  String _scheduleRecommendationReason() {
    final weeks = _aogWeeks ?? 0;
    final isHighRisk = _pregnancyRiskLevel.toLowerCase() == 'high';

    if (weeks > 40) {
      return 'Post-term monitoring (+3 days)';
    } else if (isHighRisk) {
      return weeks >= 28 ? 'High-risk weekly monitoring (+1 week)' : 'High-risk bi-weekly monitoring (+2 weeks)';
    } else {
      if (weeks < 28) {
        return 'Standard Month 1–6 schedule (+4 weeks / 28 days)';
      } else if (weeks < 36) {
        return 'Standard Month 7–8 schedule (+2 weeks / 14 days)';
      } else {
        return 'Standard Month 9 schedule (+1 week / 7 days)';
      }
    }
  }

  DateTime? _effectiveLmp([Map<String, dynamic>? pregnancy]) {
    final lmpFromPregnancy = _tryDate(pregnancy?['last_menstrual_period']);
    return lmpFromPregnancy ??
        widget.lmp ??
        _tryDate((_motherRiskContext?['pregnancy']
            as Map<String, dynamic>?)?['last_menstrual_period']);
  }

  DateTime? _effectiveEdd([Map<String, dynamic>? pregnancy]) {
    final eddFromPregnancy = _tryDate(pregnancy?['expected_date_of_delivery']);
    if (eddFromPregnancy != null) return eddFromPregnancy;
    final lmp = _effectiveLmp(pregnancy);
    return lmp?.add(const Duration(days: 280));
  }

  String _formatDate(DateTime? date) {
    return date == null ? 'unknown' : DateFormat('yyyy-MM-dd').format(date);
  }

  double? get _aogWeeks {
    final lmp = _effectiveLmp();
    if (lmp == null) return null;
    final days = _normalizedDate(_checkupDateTime)
        .difference(_normalizedDate(lmp))
        .inDays;
    if (days < 0) return null;
    return (days / 7).floorToDouble();
  }

  _BpStatus get _bpStatus {
    final sys = int.tryParse(_sysCtrl.text.trim());
    final dia = int.tryParse(_diaCtrl.text.trim());

    if (sys == null || dia == null) return _BpStatus.unknown;
    if (sys <= 0 || dia <= 0) return _BpStatus.unknown;

    // Physiological validation
    if (sys <= dia) {
      print('Warning: Systolic ≤ Diastolic - possible measurement error');
      return _BpStatus.unknown;
    }

    // Hypertensive Crisis
    if (sys > 180 || dia > 120) {
      return _BpStatus.stage2;
    }

    // Stage 2 Hypertension
    if (sys > 140 || dia > 90) {
      return _BpStatus.stage2;
    }

    // Stage 1 Hypertension
    if (sys > 130 || dia > 80) {
      return _BpStatus.stage1;
    }

    // Elevated BP
    if (sys > 120 && dia < 80) {
      return _BpStatus.elevated;
    }

    // Hypotension
    if (sys < 90 || dia < 60) {
      return _BpStatus.low;
    }

    // Normal BP
    return _BpStatus.normal;
  }

  DateTime _normalizedDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String _prettyDate(DateTime value) {
    return DateFormat('MMM d, yyyy').format(value);
  }

  void _showMessage(String message,
      {AppSnackType type = AppSnackType.warning}) {
    AppSnackbar.show(context, message, type: type);
  }

  // ── UI helpers ─────────────────────────────────────────────────────────

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildClickableSummarySection(String title, List<Widget> rows,
      {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandPrimary)),
                  const Spacer(),
                  const Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.brandPrimary)
                ])),
            Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.borderPrimary),
            Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: rows)),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {Color? valueColor, IconData? icon, Widget? badge}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6)
          ],
          SizedBox(
            width: 125,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? AppColors.brandText,
              ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            badge,
          ],
        ],
      ),
    );
  }

  Widget _bpStatusPill() {
    final s = _bpStatus;
    if (s == _BpStatus.unknown) return const SizedBox.shrink();

    final String pillLabel;
    final Color pillColor;

    if (s == _BpStatus.normal) {
      pillLabel = 'NORMAL';
      pillColor = AppColors.success;
    } else if (s == _BpStatus.low) {
      pillLabel = 'LOW';
      pillColor = const Color(0xFF3B82F6);
    } else {
      pillLabel = 'ELEVATED';
      pillColor = AppColors.warning;
    }

    final isLow = s == _BpStatus.low;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: isLow ? const Color(0xFFEFF6FF) : pillColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLow ? const Color(0xFFBFDBFE) : pillColor.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        pillLabel,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
          color: pillColor,
        ),
      ),
    );
  }

  Widget _riskSegmentOption(String levelKey, String label, Color color) {
    final isSelected = _pregnancyRiskLevel == levelKey;
    return GestureDetector(
      onTap: () => setState(() => _pregnancyRiskLevel = levelKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 13,
              color: isSelected ? color : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weightGainStatusPill() {
    final currentWeight = double.tryParse(_weightCtrl.text.trim());
    if (currentWeight == null || _aogWeeks == null || _aogWeeks! <= 0) {
      return const SizedBox.shrink();
    }

    final motherMap = _motherRiskContext?['mother'] as Map<String, dynamic>?;
    final pregnancyMap = _motherRiskContext?['pregnancy'] as Map<String, dynamic>?;
    final heightCm = motherMap?['height'] != null
        ? double.tryParse(motherMap!['height'].toString())
        : null;
    final prePregnancyWeight = pregnancyMap?['pre_pregnancy_weight'] != null
        ? double.tryParse(pregnancyMap!['pre_pregnancy_weight'].toString())
        : null;
    final motherWeight = motherMap?['weight'] != null
        ? double.tryParse(motherMap!['weight'].toString())
        : null;

    double? baselinePreWeight = prePregnancyWeight ?? motherWeight ?? widget.motherWeight;
    if (baselinePreWeight == null) {
      _initialSessionWeight ??= currentWeight;
      baselinePreWeight = _initialSessionWeight;
    }

    double? effectivePrePreg = baselinePreWeight;
    if (effectivePrePreg == null && heightCm != null && heightCm > 0) {
      final est = WeightGainEngine.estimatePrePregnancyBMI(
        currentWeightKg: currentWeight,
        heightCm: heightCm,
        aogWeeks: _aogWeeks!.toInt(),
        knownPrePregnancyWeight: baselinePreWeight,
        fetalCount: _fetalCount ?? 1,
      );
      effectivePrePreg = est['estimatedWeight'] as double?;
    }

    final result = WeightGainEngine.evaluate(
      currentWeight: currentWeight,
      aogWeeks: _aogWeeks!,
      allCheckups: [],
      prePregnancyWeight: effectivePrePreg,
      heightCm: heightCm,
      fetalCount: _fetalCount ?? 1,
    );

    final String pillLabel;
    final Color pillColor;

    if (result.status == WeightGainStatus.low) {
      pillLabel = 'BELOW EXPECTED';
      pillColor = AppColors.warning;
    } else if (result.status == WeightGainStatus.high) {
      pillLabel = 'ABOVE EXPECTED';
      pillColor = AppColors.warning;
    } else {
      pillLabel = 'WITHIN EXPECTED';
      pillColor = AppColors.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pillColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        pillLabel,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
          color: pillColor,
        ),
      ),
    );
  }

  Widget _bpClinicalGuidanceCard() {
    if (_sysError != null || _diaError != null) {
      return const SizedBox.shrink();
    }
    final sys = int.tryParse(_sysCtrl.text.trim());
    final dia = int.tryParse(_diaCtrl.text.trim());

    if (sys == null || dia == null || sys < 70 || sys > 250 || dia < 40 || dia > 150 || sys <= dia) {
      return const SizedBox.shrink();
    }

    final isLow = sys < 90 || dia < 60;
    final isSevere = sys >= 160 || dia >= 110;
    final isHypertensive = (sys >= 140 || dia >= 90) && !isSevere;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isSevere) {
      statusText = 'Severe Hypertension (≥160/110 mmHg) — Immediate Referral Required';
      statusColor = const Color(0xFFB71C1C);
      statusIcon = Icons.error_rounded;
    } else if (isHypertensive) {
      statusText = 'Hypertension in Pregnancy (≥140/90 mmHg)';
      statusColor = AppColors.error;
      statusIcon = Icons.warning_rounded;
    } else if (isLow) {
      statusText = 'Low Blood Pressure (<90/60 mmHg)';
      statusColor = Colors.blue.shade700;
      statusIcon = Icons.arrow_downward_rounded;
    } else {
      statusText = 'Normal Blood Pressure (Within acceptable range)';
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle_rounded;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _riskColor(String riskCategory) {
    switch (riskCategory) {
      case 'danger':
        return AppColors.error;
      case 'warning':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  String _riskLabel(String riskCategory) {
    switch (riskCategory) {
      case 'danger':
        return 'Needs Urgent Attention';
      case 'warning':
        return 'Needs Closer Monitoring';
      default:
        return 'Standard / Expected';
    }
  }

  List<SymptomType> _symptomsByRisk(String riskCategory) {
    final query = _symptomSearchCtrl.text.trim().toLowerCase();
    final grouped = _symptomTypes.where((s) => s.riskCategory == riskCategory);
    if (query.isEmpty) return grouped.toList();

    return grouped
        .where((s) =>
            s.name.toLowerCase().contains(query) ||
            (s.description ?? '').toLowerCase().contains(query))
        .toList();
  }

  bool _isSymptomSelected(int symptomTypeId) {
    return _symptoms.any((s) => s.symptomTypeId == symptomTypeId);
  }

  int get _severeSymptomCount =>
      _symptoms.where((s) => s.riskCategory == 'danger').length;

  List<String> get _severeSymptomNames => _symptoms
      .where((s) => s.riskCategory == 'danger')
      .map((s) => s.name)
      .toList();

  bool _passesRiskFilter(String riskCategory) {
    return _symptomRiskFilter == 'all' || _symptomRiskFilter == riskCategory;
  }

  bool _validateCurrentStep() {
    if (_step == 0) {
      // Date is auto-locked to now, no date validation needed.

      final weight = double.tryParse(_weightCtrl.text.trim());
      if (weight == null) {
        setState(() => _weightError = 'Weight is required');
        _showMessage('Weight is required.');
        return false;
      }
      if (weight < 30 || weight > 200) {
        setState(() => _weightError = 'Must be 30 – 200 kg');
        _showMessage('Weight must be between 30 and 200 kg.');
        return false;
      }

      final systolic = int.tryParse(_sysCtrl.text.trim());
      final diastolic = int.tryParse(_diaCtrl.text.trim());
      if (systolic == null || diastolic == null) {
        _showMessage('Enter valid blood pressure values.');
        return false;
      }
      if (systolic < 70 ||
          systolic > 250 ||
          diastolic < 40 ||
          diastolic > 150) {
        _showMessage('Blood pressure values are outside valid clinical range.');
        return false;
      }
      if (systolic <= diastolic) {
        setState(() => _diaError = 'Must be < systolic');
        _showMessage('Systolic pressure must be higher than diastolic.');
        return false;
      }
      // Hypertension warning (non-blocking)
      if (systolic >= 140 || diastolic >= 90) {
        _showMessage(
          'Warning: BP $systolic/$diastolic suggests hypertension. Proceed with caution.',
          type: AppSnackType.warning,
        );
      }
    }

    if (_step == 1) {
      final fetalBeatText = _fetalBeatCtrl.text.trim();
      final hasRate = fetalBeatText.isNotEmpty;

      if (hasRate) {
        final fetalBeat = int.tryParse(fetalBeatText);
        if (fetalBeat == null || fetalBeat <= 0 || fetalBeat > 250) {
          _showMessage('Please enter a valid fetal heart rate in bpm.');
          return false;
        }
        if (_fetalTone == null || _fetalTone!.isEmpty) {
          _showMessage('Fetal Heart Tone is required when Fetal Heart Rate is entered.');
          return false;
        }
      }
    }

    if (_step == 3) {
      if (_ferrousError != null || _calciumError != null) {
        _showMessage('Please fix the highlighted field errors.');
        return false;
      }
      final ferrous = _ferrousQtyCtrl.text.trim();
      if (ferrous.isNotEmpty) {
        final qty = int.tryParse(ferrous);
        if (qty == null || qty < 1 || qty > 365) {
          _showMessage('Ferrous + FA quantity must be between 1 and 365.');
          return false;
        }
      }
      final calcium = _calciumQtyCtrl.text.trim();
      if (calcium.isNotEmpty) {
        final qty = int.tryParse(calcium);
        if (qty == null || qty < 1 || qty > 365) {
          _showMessage('Calcium quantity must be between 1 and 365.');
          return false;
        }
      }
    }

    if (_step == 4) {
      if (_nextSchedule != null &&
          !_normalizedDate(_nextSchedule!)
              .isAfter(_normalizedDate(_checkupDateTime))) {
        _showMessage('Next schedule must be after the checkup date.');
        return false;
      }
      if (_remarksCtrl.text.trim().length > 1000) {
        _showMessage('Remarks must be 1000 characters or less.');
        return false;
      }
    }

    return true;
  }

  Future<void> _openSymptomNotesDialog(SymptomType symptomType) async {
    if (_isSymptomSelected(symptomType.id)) {
      _showMessage('${symptomType.name} is already recorded.');
      return;
    }

    final notesCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.brandText),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Add Symptom',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.brandText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  symptomType.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _riskColor(symptomType.riskCategory)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _riskColor(symptomType.riskCategory)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    _riskLabel(symptomType.riskCategory),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _riskColor(symptomType.riskCategory),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppColors.borderPrimary, width: 1.5),
                  ),
                  child: TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Notes (optional)',
                      hintStyle: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Add Symptom',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (saved == true) {
      final nameLower = symptomType.name.trim().toLowerCase();
      final exists = _symptoms.any((s) =>
          (s.symptomTypeId != null && s.symptomTypeId == symptomType.id) ||
          s.name.trim().toLowerCase() == nameLower);
      if (!exists) {
        setState(() {
          _symptoms.add(
            _SymptomEntry(
              symptomTypeId: symptomType.id,
              name: symptomType.name,
              riskCategory: symptomType.riskCategory,
              notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
            ),
          );
        });
      } else {
        _showMessage('${symptomType.name} is already recorded.');
      }
    }

    notesCtrl.dispose();
  }



  Future<void> _confirmClearAllSymptoms() async {
    if (_symptoms.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear Recorded Symptoms?'),
          content: const Text(
              'This will remove all currently selected symptoms for this checkup form.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() => _symptoms.clear());
    }
  }

  Widget _buildSymptomGroup({
    required String title,
    required String riskCategory,
  }) {
    if (!_passesRiskFilter(riskCategory)) return const SizedBox.shrink();
    final color = _riskColor(riskCategory);
    final group = _symptomsByRisk(riskCategory);
    if (group.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.map((symptomType) {
              final selected = _isSymptomSelected(symptomType.id);
              return ActionChip(
                label: Text(
                  symptomType.name,
                  style: TextStyle(
                    color: selected ? Colors.white : color,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                backgroundColor: selected ? color : Colors.white,
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                onPressed: () {
                  if (!selected) {
                    _openSymptomNotesDialog(symptomType);
                  } else {
                    setState(() => _symptoms.removeWhere(
                        (item) => item.symptomTypeId == symptomType.id));
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _pickNextSchedule() async {
    final baseDate =
        _normalizedDate(_checkupDateTime).add(const Duration(days: 1));
    final now = DateTime.now();

    // Ensure initialDate is not on a blocked weekend day
    var initialDate =
        (_nextSchedule != null && _nextSchedule!.isAfter(baseDate))
            ? _nextSchedule!
            : baseDate;
    bool isHoliday(DateTime date) {
      final holidays = <String>[
        '01-01', // New Year's Day
        '02-25', // EDSA Revolution Anniversary
        '04-09', // Araw ng Kagitingan
        '05-01', // Labor Day
        '06-12', // Independence Day
        '08-21', // Ninoy Aquino Day
        '11-01', // All Saints' Day
        '11-02', // All Souls' Day
        '11-30', // Bonifacio Day
        '12-08', // Feast of the Immaculate Conception
        '12-24', // Christmas Eve
        '12-25', // Christmas Day
        '12-30', // Rizal Day
        '12-31', // Last Day of the Year
      ];
      final monthStr = date.month.toString().padLeft(2, '0');
      final dayStr = date.day.toString().padLeft(2, '0');
      return holidays.contains('$monthStr-$dayStr');
    }

    // Advance past weekends and holidays so the picker opens on a valid day
    while (initialDate.weekday == DateTime.saturday ||
        initialDate.weekday == DateTime.sunday ||
        isHoliday(initialDate)) {
      initialDate = initialDate.add(const Duration(days: 1));
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: baseDate,
      lastDate: DateTime(now.year + 2, now.month, now.day),
      helpText: 'Must be after ${_prettyDate(_checkupDateTime)}',
      selectableDayPredicate: (date) {
        // Block weekends — BHCs are typically closed on Sat/Sun
        if (date.weekday == DateTime.saturday ||
            date.weekday == DateTime.sunday) return false;
        // Block Philippine regular holidays
        if (isHoliday(date)) return false;

        return true;
      },
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
    if (picked == null) return;
    setState(() => _nextSchedule = picked);
  }

  Future<void> _insertSupplementRecords() async {
    final client = Supabase.instance.client;
    final checkupDate = _normalizedDate(_checkupDateTime);

    final givenRows = <Map<String, dynamic>>[];

    final ferrousQty = int.tryParse(_ferrousQtyCtrl.text.trim());
    if (ferrousQty != null && ferrousQty > 0) {
      givenRows.add({
        'mother_id': widget.motherId,
        'given_medication_name': 'Ferrous + FA',
        'quantity': ferrousQty,
        'date_given': checkupDate.toIso8601String().split('T')[0],
      });
    }

    final calciumQty = int.tryParse(_calciumQtyCtrl.text.trim());
    if (calciumQty != null && calciumQty > 0) {
      givenRows.add({
        'mother_id': widget.motherId,
        'given_medication_name': 'Calcium',
        'quantity': calciumQty,
        'date_given': checkupDate.toIso8601String().split('T')[0],
      });
    }

    if (givenRows.isNotEmpty) {
      await client.from('given_medications').insert(givenRows);
    }
  }

  int? _resolveSymptomTypeId(_SymptomEntry entry) {
    if (entry.symptomTypeId > 0) return entry.symptomTypeId;

    final nameLower = entry.name.trim().toLowerCase();
    for (final st in _symptomTypes) {
      if (st.name.trim().toLowerCase() == nameLower) {
        return st.id;
      }
    }

    for (final st in _symptomTypes) {
      if (st.name.toLowerCase().contains('other')) {
        return st.id;
      }
    }

    if (_symptomTypes.isNotEmpty) {
      return _symptomTypes.first.id;
    }

    return null;
  }

  Future<void> _insertSymptomRecords(int encounterId) async {
    if (_symptoms.isEmpty) return;

    final payload = <Map<String, dynamic>>[];
    for (final entry in _symptoms) {
      final typeId = _resolveSymptomTypeId(entry);
      if (typeId != null && typeId > 0) {
        final noteText = entry.notes != null
            ? '${entry.name}: ${entry.notes}'
            : entry.name;
        payload.add({
          'pregnancy_id': widget.pregnancyId,
          'encounter_id': encounterId,
          'symptom_type_id': typeId,
          'notes': noteText,
        });
      }
    }

    if (payload.isNotEmpty) {
      await Supabase.instance.client.from('pregnancy_symptoms').insert(payload);
    }
  }

  Future<void> _persistRiskAssessment(int encounterId) async {
    final snapshot = _riskSnapshot ?? _buildRuleBasedRiskSnapshot();
    final client = Supabase.instance.client;

    // ── AI Remarks audit trail ──────────────────────────────────────────────
    final bool hasAiRemarks = _remarksSource != 'midwife_authored';
    final remarksText = _remarksCtrl.text.trim();
    final aiStatus = _remarksSource == 'ai_generated_approved'
        ? 'approved'
        : _remarksSource == 'ai_generated_edited'
            ? 'edited'
            : 'skipped';

    // Build bilingual AI text for storage (original AI output)
    final originalAiText = (_aiOriginalRemarksEn != null || _aiOriginalRemarksFil != null)
        ? '=== FILIPINO ===\n${_aiOriginalRemarksFil ?? ''}\n\n=== ENGLISH ===\n${_aiOriginalRemarksEn ?? ''}'
        : '';

    // Build final text (what the midwife actually submitted)
    final finalAiText = hasAiRemarks
        ? '=== FILIPINO ===\n${_aiRemarksFilipino}\n\n=== ENGLISH ===\n${_aiRemarksEnglish}'
        : remarksText;

    final wasEdited = _remarksSource == 'ai_generated_edited';

    final finalRiskLevel = _editableRiskLevel;
    final finalRiskFactors = List<_RiskFactorItem>.from(_editableRiskFactors);
    final riskManuallyEdited = finalRiskLevel != snapshot.level ||
        !_sameFactorLists(finalRiskFactors, snapshot.factors);

    // ── ai_responses row (only if AI was used) ──────────────────────────────
    int? aiResponseId;
    if (hasAiRemarks) {
      Map<String, dynamic>? aiRow = await client
          .from('ai_responses')
          .select('ai_response_id')
          .eq('reference_table', 'prenatal_checkups')
          .eq('reference_id', encounterId)
          .eq('response_type', 'checkup_remarks')
          .maybeSingle();

      final bool aiResponseUpdated = aiRow != null;
      if (aiRow != null) {
        aiResponseId = aiRow['ai_response_id'] as int;
        await client.from('ai_responses').update({
          'ai_model': _aiRemarksModel ?? 'Rule Engine',
          'response': finalAiText,
          'response_category': 'remarks',
          'status': aiStatus,
          'generated_by_ai': true,
          'approved_by': _accountId,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('ai_response_id', aiResponseId);
      } else {
        final insertedAi = await client
            .from('ai_responses')
            .insert({
              'response_type': 'checkup_remarks',
              'reference_table': 'prenatal_checkups',
              'reference_id': encounterId,
              'ai_model': _aiRemarksModel ?? 'Rule Engine',
              'confidence_score': null,
              'response': finalAiText,
              'response_category': 'remarks',
              'status': aiStatus,
              'generated_by_ai': true,
              'approved_by': _accountId,
            })
            .select('ai_response_id')
            .maybeSingle();

        if (insertedAi != null) {
          aiResponseId = insertedAi['ai_response_id'] as int;
        }
      }

      // Prompt log
      if (aiResponseId != null && (_lastRiskAiPrompt ?? '').trim().isNotEmpty) {
        await client.from('ai_prompt_logs').insert({
          'ai_response_id': aiResponseId,
          'prompt': _lastRiskAiPrompt,
          'model_used': _aiRemarksModel ?? 'Rule Engine',
        });
      }

      // Audit trail for AI remarks
      await client.from('audit_trail').insert({
        'action': aiResponseUpdated ? 'UPDATE' : 'INSERT',
        'table_name': 'ai_responses',
        'account_id': _accountId,
        'new_data': {
          'ai_response_id': aiResponseId,
          'status': aiStatus,
          'remarks_source': _remarksSource,
        },
        'description':
            'AI checkup insight ${wasEdited ? "edited by midwife and " : ""}saved for prenatal checkup $encounterId.',
      });

      // If midwife edited the AI text, record the diff
      if (wasEdited && aiResponseId != null) {
        await client.from('ai_edit_history').insert({
          'ai_response_id': aiResponseId,
          'old_content': originalAiText,
          'new_content': finalAiText,
          'edited_by': _accountId,
          'edit_reason':
              'Midwife edited AI-generated checkup remarks before saving.',
        });

        await client.from('audit_trail').insert({
          'action': 'UPDATE',
          'table_name': 'ai_edit_history',
          'account_id': _accountId,
          'old_data': {'content': originalAiText},
          'new_data': {'content': finalAiText, 'ai_response_id': aiResponseId},
          'description':
              'Midwife edited AI checkup remarks content before submission.',
        });
      }
    }

    // ── pregnancy_risk_assessments row ───────────────────────────────────────
    final riskInsert = await client
        .from('pregnancy_risk_assessments')
        .insert({
          'pregnancy_id': widget.pregnancyId,
          'ai_response_id': aiResponseId,
          'risk_level': finalRiskLevel,
          'assessed_by_ai': hasAiRemarks && !wasEdited && !riskManuallyEdited,
        })
        .select('pregnancy_risk_id')
        .maybeSingle();

    if (riskInsert != null) {
      final pregnancyRiskId = riskInsert['pregnancy_risk_id'] as int;

      if (finalRiskFactors.isNotEmpty) {
        final factorRows = finalRiskFactors
            .map(
              (f) => {
                'pregnancy_risk_id': pregnancyRiskId,
                'factor': f.factor,
                'risk_influence': f.influence,
                'source_table': f.sourceTable ?? 'prenatal_checkups',
                'source_id': f.sourceId ?? encounterId,
              },
            )
            .toList();
        await client.from('pregnancy_risk_factors').insert(factorRows);
      }
    }

    await client
        .from('pregnancies')
        .update({'pregnancy_risk_level': _pregnancyRiskLevel}).eq(
            'pregnancy_id', widget.pregnancyId);
  }

  /// Evaluates and persists maternal weight gain analysis for this checkup.
  Future<void> _persistWeightGainEvaluation(
      int encounterId, double currentWeight) async {
    try {
      // Guard: skip if gestational age is unknown
      final aog = _aogWeeks;
      if (aog == null || aog <= 0) {
        debugPrint(
            'Weight gain evaluation skipped: gestational age unavailable.');
        return;
      }

      final client = Supabase.instance.client;

      // Fetch mother's height from mothers table
      final motherData = await client
          .from('mothers')
          .select('height')
          .eq('mother_id', widget.motherId)
          .maybeSingle();

      // Fetch pre-pregnancy weight and fetal count from pregnancies table
      final pregnancyData = await client
          .from('pregnancies')
          .select('pre_pregnancy_weight, fetal_count')
          .eq('pregnancy_id', widget.pregnancyId)
          .maybeSingle();

      final heightCm = _wgeToDouble(motherData?['height']);
      final prePregnancyWeight =
          _wgeToDouble(pregnancyData?['pre_pregnancy_weight']);
      final fetalCount =
          int.tryParse(pregnancyData?['fetal_count']?.toString() ?? '') ?? 1;

      // Fetch all checkups for this pregnancy (ascending order)
      final rawEncounters = await client
          .from('clinical_encounters')
          .select('''
            encounter_datetime,
            age_of_gestation_weeks,
            age_of_gestation_days,
            checkup:prenatal_checkups (
              checkup_weight
            )
          ''')
          .eq('pregnancy_id', widget.pregnancyId)
          .eq('encounter_type', 'checkup')
          .order('encounter_datetime', ascending: true);

      final checkupList = (rawEncounters as List).map((enc) {
        final innerCheckup = enc['checkup'] as List?;
        final checkupData = innerCheckup != null && innerCheckup.isNotEmpty
            ? innerCheckup.first as Map<String, dynamic>
            : null;
        final weeks = (enc['age_of_gestation_weeks'] as num?)?.toDouble() ?? 0;
        final days = (enc['age_of_gestation_days'] as num?)?.toDouble() ?? 0;
        return {
          'checkup_weight': checkupData?['checkup_weight'],
          'age_of_gestation': weeks + days / 7.0,
          'checkup_datetime': enc['encounter_datetime'],
        };
      }).toList();

      // Run the weight gain engine
      final result = WeightGainEngine.evaluate(
        currentWeight: currentWeight,
        aogWeeks: aog,
        allCheckups: checkupList,
        prePregnancyWeight: prePregnancyWeight,
        heightCm: heightCm,
        fetalCount: fetalCount,
      );

      // Persist evaluation result
      await client.from('weight_gain_evaluations').insert({
        'pregnancy_id': widget.pregnancyId,
        'encounter_id': encounterId,
        'mode': result.mode == WeightGainMode.full ? 'FULL' : 'TREND',
        'bmi_category': result.bmiCategory,
        'baseline_weight': result.baselineWeight,
        'baseline_week': result.baselineWeek,
        'current_weight': result.currentWeight,
        'current_week': result.currentWeek,
        'expected_gain': result.expectedGain,
        'actual_gain': result.actualGain,
        'weekly_gain': result.weeklyGain,
        'status': result.statusLabel,
        'confidence': result.confidenceLabel,
        'message': result.message,
        'flags': result.flags,
      });

      // Store in ai_responses for AI explanation layer
      await client.from('ai_responses').insert({
        'response_type': 'weight_gain_analysis',
        'reference_table': 'prenatal_checkups',
        'reference_id': encounterId,
        'ai_model': 'Weight Gain Engine (IOM 2009)',
        'confidence_score': null,
        'response': result.message,
        'response_category': 'analysis',
        'status': 'generated',
        'generated_by_ai': false,
        'approved_by': null,
      });
    } catch (e) {
      // Non-critical: log but don't block checkup save
      debugPrint('Weight gain evaluation error (non-critical): $e');
    }
  }

  static double? _wgeToDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String? _normalizeFetalTone(String? tone) {
    if (tone == null || tone.isEmpty) return null;
    final lower = tone.trim().toLowerCase();
    if (lower == 'regular' || lower == 'normal') return 'regular';
    if (lower == 'irregular') return 'irregular';
    if (lower == 'faint' || lower == 'muffled') return 'faint';
    if (lower == 'absent') return 'absent';
    return 'regular';
  }

  Future<void> _submitCheckup() async {
    if (!_validateCurrentStep()) return;

    final weight = double.tryParse(_weightCtrl.text.trim());
    final systolic = int.tryParse(_sysCtrl.text.trim());
    final diastolic = int.tryParse(_diaCtrl.text.trim());
    final fetalBeat = int.tryParse(_fetalBeatCtrl.text.trim());

    if (weight == null || systolic == null || diastolic == null) {
      _showMessage('Please complete all required fields.');
      return;
    }

    if (_midwifeId == null) {
      _showMessage(
          'Could not identify midwife. Please log out and log in again.');
      return;
    }

    // Lock checkup datetime to now at submission
    setState(() {
      _submitting = true;
      _checkupDateTime = DateTime.now();
    });
    try {
      await _refreshRiskPreview();

      final lmp = _effectiveLmp();
      int? aogWeeks;
      int? aogDays;
      if (lmp != null) {
        final totalDays = _normalizedDate(_checkupDateTime).difference(_normalizedDate(lmp)).inDays;
        if (totalDays >= 0) {
          aogWeeks = totalDays ~/ 7;
          aogDays = totalDays % 7;
        }
      }

      final encounter = await Supabase.instance.client
          .from('clinical_encounters')
          .insert({
            'pregnancy_id': widget.pregnancyId,
            'mother_id': widget.motherId,
            'recorded_by': _midwifeId,
            'encounter_type': 'checkup',
            'encounter_datetime': _checkupDateTime.toIso8601String(),
            'age_of_gestation_weeks': aogWeeks,
            'age_of_gestation_days': aogDays,
            'midwife_notes': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
          })
          .select('encounter_id')
          .maybeSingle();

      if (encounter == null) {
        throw Exception('Failed to create clinical encounter record');
      }

      final encounterId = encounter['encounter_id'] as int;

      await Supabase.instance.client
          .from('prenatal_checkups')
          .insert({
            'encounter_id': encounterId,
            'pregnancy_id': widget.pregnancyId,
            'checkup_weight': weight,
            'blood_pressure_systolic': systolic,
            'blood_pressure_diastolic': diastolic,
            'fetal_heart_beat': fetalBeat,
            'fetal_heart_tone': _normalizeFetalTone(_fetalTone),
            'td_vaccine_dose': _tdDose,
            'edema': _edema == 'none' ? null : _edema,
            'next_schedule': _nextSchedule?.toIso8601String().split('T')[0],
          });

      await _insertSymptomRecords(encounterId);

      await _insertSupplementRecords();

      await _persistRiskAssessment(encounterId);

      // Weight Gain Monitoring — evaluate and persist
      await _persistWeightGainEvaluation(encounterId, weight);

      // If a next schedule is specified, send an automated SMS reminder to the mother
      if (_nextSchedule != null) {
        try {
          final motherDetails = await Supabase.instance.client
              .from('mothers')
              .select(
                  'mother_id, account:account_id (first_name, last_name, phone_number), assigned_bhc_id, bhc:assigned_bhc_id (bhc_name)')
              .eq('mother_id', widget.motherId)
              .maybeSingle();

          if (motherDetails != null) {
            final account = motherDetails['account'] as Map<String, dynamic>?;
            final phone = account?['phone_number']?.toString();
            final firstName = account?['first_name']?.toString() ?? 'Mother';
            final bhc = motherDetails['bhc'] as Map<String, dynamic>?;
            final bhcName = bhc?['bhc_name']?.toString() ?? 'Health Center';
            final nextDateStr =
                DateFormat('MMMM d, yyyy').format(_nextSchedule!);

            if (phone != null && phone.isNotEmpty) {
              final smsMessage =
                  'InaAgapay: Hello $firstName! Ang inyong susunod na prenatal check-up ay nakatakda sa $nextDateStr sa $bhcName. Mangyaring i-save ang petsang ito at mag-ingat po kayo. Salamat!';
              await SmsService.sendSmsMessage(phone, smsMessage);
            }
          }
        } catch (smsError) {
          debugPrint('Error sending automated checkup SMS: $smsError');
        }
      }

      // ── Push notification for the mother ──────────────────────────────
      try {
        final motherAcct = await Supabase.instance.client
            .from('mothers')
            .select('account_id')
            .eq('mother_id', widget.motherId)
            .maybeSingle();
        final motherAccountId = motherAcct?['account_id'] as int?;
        if (motherAccountId != null) {
          final nextDateStr = _nextSchedule != null
              ? DateFormat('MMMM d, yyyy').format(_nextSchedule!)
              : null;
          final pushTitle = 'Prenatal Checkup Recorded';
          final pushMessage = nextDateStr != null
              ? 'Your prenatal checkup has been recorded. Your next schedule is on $nextDateStr.'
              : 'Your prenatal checkup has been recorded. Keep up the great care, mommy!';
          await NotificationService.createNotification(
            accountId: motherAccountId,
            title: pushTitle,
            message: pushMessage,
            type: 'checkup_reminder',
          );
        }
      } catch (pushError) {
        debugPrint('Error sending checkup push notification: $pushError');
      }

      if (!mounted) return;
      _showMessage('Prenatal checkup saved.', type: AppSnackType.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to save prenatal checkup: $e',
          type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _next() async {
    if (!_validateCurrentStep()) return;
    if (_step < _totalSteps - 1) {
      final nextStep = _step + 1;
      setState(() => _step = nextStep);
      if (nextStep == _totalSteps - 1) {
        await _refreshRiskPreview(force: false);
      }
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step -= 1);
    }
  }

  void _jumpToStep(int step) {
    if (step >= 0 && step < _totalSteps) {
      setState(() => _step = step);
      if (step == _totalSteps - 1) {
        _refreshRiskPreview(force: false);
      }
    }
  }

  Widget _stepTitle() {
    const labels = [
      'Vitals',
      'Fetal Assessment',
      'Pregnancy Symptoms',
      'Supplements & TD',
      'Schedule & Remarks',
      'Summary & Risk Level',
    ];
    const subtitles = [
      'Date, weight, and blood pressure',
      'Fetal heart rate and tone',
      'Record symptoms and identify serious warning signs',
      'Supplements and TD vaccine',
      'Next visit and remarks',
      'Review details and set pregnancy risk level before saving',
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
    switch (_step) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      case 4:
        return _buildStep4();
      case 5:
      default:
        return _buildStep5();
    }
  }

  Widget _buildStep0() {
    final motherData = _motherRiskContext?['mother'] as Map<String, dynamic>?;
    final motherHeight = motherData?['height']?.toString();
    final pregnancy = _motherRiskContext?['pregnancy'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'VISIT DATE & TIME',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Row(
                    children: const [
                      Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.textSecondary),
                      SizedBox(width: 3),
                      Text(
                        'Auto-locked',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.calendar_today_rounded,
                      color: AppColors.brandPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMMM d, yyyy').format(_checkupDateTime),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.brandText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('h:mm a').format(_checkupDateTime),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_aogWeeks != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.brandPrimary.withValues(alpha: 0.12),
                            AppColors.brandPrimary.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.brandPrimary.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.child_care_rounded,
                            size: 16,
                            color: AppColors.brandPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_aogWeeks!.toInt()} wks AOG',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brandPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Height',
          child: _motherRiskContext == null && _heightCtrl.text.isEmpty
              ? Container(
                  height: 48,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderPrimary),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Loading height...',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : AppInputField(
                  hintText: 'Height (cm)',
                  controller: _heightCtrl,
                  readOnly: true,
                ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Weight',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInputField(
                hintText: 'Weight (kg)',
                controller: _weightCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,3}(\.\d{0,2})?$')),
                ],
                isRequired: true,
                errorText: _weightError,
              ),
              if (_weightError == null)
                _buildWeightGainInsight(
                      motherHeight != null
                          ? double.tryParse(motherHeight)
                          : null,
                      pregnancy,
                    ) ??
                    const SizedBox.shrink(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Blood Pressure',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: AppInputField(
                      hintText: 'Systolic (mmHg)',
                      controller: _sysCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      isRequired: true,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '/',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: AppInputField(
                      hintText: 'Diastolic (mmHg)',
                      controller: _diaCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      isRequired: true,
                    ),
                  ),
                ],
              ),
              if (_sysError != null || _diaError != null)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 14, color: AppColors.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _sysError ?? _diaError!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _bpClinicalGuidanceCard(),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 13, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Source: World Health Organization (WHO) & DOH Clinical Practice Guidelines for Maternal Care.',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _buildWeightGainInsight(
      double? heightCmVal, Map<String, dynamic>? pregnancyData) {
    if (_aogWeeks == null) return null;

    final t = _weightCtrl.text.trim();
    if (t.isEmpty) return null;
    final currentWeight = double.tryParse(t);
    if (currentWeight == null || currentWeight < 30 || currentWeight > 200) {
      return null;
    }

    final mother = _motherRiskContext?['mother'] as Map<String, dynamic>?;
    final previousCheckups =
        (_motherRiskContext?['previous_checkups'] as List? ?? const [])
            .cast<dynamic>();

    final rawPrePreg = pregnancyData?['pre_pregnancy_weight'];
    final prePregnancyWeight =
        rawPrePreg != null ? double.tryParse(rawPrePreg.toString()) : null;

    final rawMotherW = mother?['weight'];
    final motherWeight =
        rawMotherW != null ? double.tryParse(rawMotherW.toString()) : null;

    final rawMotherH = mother?['height'];
    final heightCm = heightCmVal ??
        (rawMotherH != null ? double.tryParse(rawMotherH.toString()) : null);

    final checkupList = previousCheckups
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    checkupList.add({
      'checkup_datetime': _checkupDateTime.toIso8601String(),
      'age_of_gestation': _aogWeeks,
      'checkup_weight': currentWeight,
    });
    checkupList.sort((a, b) => DateTime.parse(a['checkup_datetime'])
        .compareTo(DateTime.parse(b['checkup_datetime'])));

    try {
      // Get earliest checkup weight if available from history
      double? earliestCheckupWeight;
      if (previousCheckups.isNotEmpty) {
        final sortedPrev = List<Map<String, dynamic>>.from(
            previousCheckups.map((e) => Map<String, dynamic>.from(e as Map)));
        sortedPrev.sort((a, b) {
          final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '');
          final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '');
          if (da == null || db == null) return 0;
          return da.compareTo(db);
        });
        earliestCheckupWeight = double.tryParse(
            sortedPrev.first['checkup_weight']?.toString() ?? '');
      }

      // Lock session initial weight so typing current weight never shifts the baseline
      double? baselinePreWeight = prePregnancyWeight ?? motherWeight ?? widget.motherWeight ?? earliestCheckupWeight;
      if (baselinePreWeight == null) {
        _initialSessionWeight ??= currentWeight;
        baselinePreWeight = _initialSessionWeight;
      }

      double? effectivePrePreg = baselinePreWeight;
      if (effectivePrePreg == null && heightCm != null && heightCm > 0) {
        final est = WeightGainEngine.estimatePrePregnancyBMI(
          currentWeightKg: currentWeight,
          heightCm: heightCm,
          aogWeeks: _aogWeeks!.toInt(),
          knownPrePregnancyWeight: baselinePreWeight,
          fetalCount: _fetalCount ?? 1,
        );
        effectivePrePreg = est['estimatedWeight'] as double?;
      }

      final result = WeightGainEngine.evaluate(
        currentWeight: currentWeight,
        aogWeeks: _aogWeeks!,
        allCheckups: checkupList,
        prePregnancyWeight: effectivePrePreg,
        heightCm: heightCm,
        fetalCount: _fetalCount ?? 1,
      );

      final isLow = result.status == WeightGainStatus.low;
      final isHigh = result.status == WeightGainStatus.high;

      Color bgColor;
      Color textColor;
      IconData icon;
      String statusText;

      if (isLow) {
        bgColor = AppColors.warning.withValues(alpha: 0.08);
        textColor = AppColors.warning;
        icon = Icons.trending_down_rounded;
        statusText = "Below expected weight gain";
      } else if (isHigh) {
        bgColor = AppColors.error.withValues(alpha: 0.08);
        textColor = AppColors.error;
        icon = Icons.trending_up_rounded;
        statusText = "Above expected weight gain";
      } else {
        bgColor = AppColors.success.withValues(alpha: 0.08);
        textColor = AppColors.success;
        icon = Icons.trending_flat_rounded;
        statusText = "Within expected weight gain";
      }

      final activeGuidelines = (_fetalCount ?? 1) >= 2
          ? WeightGainEngine.iomTwinGuidelines
          : WeightGainEngine.iomGuidelines;
      final guidelines =
          activeGuidelines[result.bmiCategory] ?? activeGuidelines['Normal']!;

      final firstTrimesterGain = guidelines['first_trimester']!;
      final weeklyRate = guidelines['weekly_rate']!;
      final totalMin = guidelines['total_min']!;
      final totalMax = guidelines['total_max']!;

      double expectedGainMin;
      double expectedGainMax;

      if (_aogWeeks! <= 13) {
        final fraction = _aogWeeks! / 13.0;
        final expectedGainMid = firstTrimesterGain * fraction;
        // In first trimester (weeks 1-13), zero weight gain (0 kg) is normal
        expectedGainMin = 0.0;
        expectedGainMax = (expectedGainMid * 1.4).clamp(1.0, firstTrimesterGain * 1.3);
      } else {
        final firstTrimesterMin = firstTrimesterGain * 0.7;
        final firstTrimesterMax = firstTrimesterGain * 1.3;

        if (_aogWeeks! <= 40) {
          final progressFraction = (_aogWeeks! - 13) / 27.0;
          expectedGainMin = firstTrimesterMin +
              (totalMin - firstTrimesterMin) * progressFraction;
          expectedGainMax = firstTrimesterMax +
              (totalMax - firstTrimesterMax) * progressFraction;
        } else {
          final weeksAfterForty = _aogWeeks! - 40;
          final weeklyMin = guidelines['weekly_min'] ?? (weeklyRate * 0.8);
          final weeklyMax = guidelines['weekly_max'] ?? (weeklyRate * 1.2);
          expectedGainMin = totalMin + (weeksAfterForty * weeklyMin);
          expectedGainMax = totalMax + (weeksAfterForty * weeklyMax);
        }
      }

      final baselineW = result.baselineWeight ?? effectivePrePreg ?? baselinePreWeight ?? currentWeight;
      final expectedWeightMin = baselineW + expectedGainMin;
      final expectedWeightMax = baselineW + expectedGainMax;

      final actualGain = result.actualGain ?? (currentWeight - baselineW);
      final actualStr =
          "${actualGain >= 0 ? '+' : ''}${actualGain.toStringAsFixed(1)} kg";
      final gainRangeStr =
          "${expectedGainMin.toStringAsFixed(1)} – ${expectedGainMax.toStringAsFixed(1)} kg";
      final weightRangeStr =
          "${expectedWeightMin.toStringAsFixed(1)} – ${expectedWeightMax.toStringAsFixed(1)} kg";

      final detailsText =
          "Based on pre-pregnancy BMI (${result.bmiCategory}): "
          "recommended target weight for Week ${_aogWeeks!.toInt()} is $weightRangeStr "
          "(ideal gain: $gainRangeStr; current gain: $actualStr).";

      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: textColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: textColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detailsText,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: textColor.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildStep1() {
    final hasRate = _fetalBeatCtrl.text.trim().isNotEmpty;
    final hasTone = _fetalTone != null && _fetalTone!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          title: 'Fetal Count (from ultrasound records)',
          child: AppInputField(
            hintText: 'Fetal Count',
            controller: TextEditingController(
                text: _fetalCount == null
                    ? 'Unknown'
                    : '$_fetalCount Fetus${_fetalCount! > 1 ? 'es' : ''}'),
            readOnly: true,
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Fetal Heart Rate',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInputField(
                hintText: 'Beats per minute (bpm)',
                controller: _fetalBeatCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: _fetalBeatError,
                isRequired: hasTone,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Normal range: 110 \u2013 160 bpm',
                    style: TextStyle(
                      fontSize: 12,
                      color: () {
                        final v = int.tryParse(_fetalBeatCtrl.text.trim());
                        if (v == null) return AppColors.textSecondary;
                        if (v >= 110 && v <= 160) return AppColors.success;
                        return AppColors.error;
                      }(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (hasRate) ...[
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Fetal Heart Tone',
            child: AppDropdownField<String>(
              hintText: 'Select tone *',
              value: _fetalTone,
              options: _fetalTones,
              displayStringForOption: (t) => t,
              onSelected: (value) => setState(() => _fetalTone = value),
            ),
          ),
        ],
      ],
    );
  }

  Widget _iconAvatar(IconData icon, {Color? color}) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: (color ?? AppColors.brandPrimary).withValues(alpha: 0.1),
            shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color ?? AppColors.brandPrimary),
      );

  Widget _emptyState(IconData icon, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 38,
                  color: AppColors.textSecondary.withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _itemCard(
          {required Widget leading,
          required String title,
          required String subtitle,
          required VoidCallback onDelete,
          VoidCallback? onEdit}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: leading,
          title: Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(subtitle,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEdit != null)
                IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: AppColors.brandPrimary, size: 20),
                    onPressed: onEdit),
              IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.error, size: 20),
                  onPressed: onDelete),
            ],
          ),
        ),
      );

  Widget _buildStep2() => _stepSymptoms();

  Widget _stepSymptoms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          title: 'Edema Level',
          child: AppDropdownField<String>(
            hintText: 'Select edema level',
            value: _edema,
            options: const ['none', 'mild', 'moderate', 'severe'],
            displayStringForOption: (val) {
              switch (val) {
                case 'none':
                  return 'None (No swelling)';
                case 'mild':
                  return 'Mild (Slight swelling in feet or ankles)';
                case 'moderate':
                  return 'Moderate (Swelling in lower legs, feet, or hands)';
                case 'severe':
                  return 'Severe (Significant swelling in face, hands, and legs)';
                default:
                  return 'None (No swelling)';
              }
            },
            onSelected: (value) => setState(() => _edema = value),
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Recorded Symptoms',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_symptoms.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _confirmClearAllSymptoms,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear all'),
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.error),
                  ),
                ),
              if (_symptoms.isEmpty)
                _emptyState(
                  Icons.healing_outlined,
                  'No symptoms recorded yet.\nClick the + button to add one.',
                )
              else ...[
                ..._symptoms.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final riskColor = _riskColor(item.riskCategory);
                  return _itemCard(
                    leading:
                        _iconAvatar(Icons.healing_outlined, color: riskColor),
                    title: item.name,
                    subtitle:
                        '${_riskLabel(item.riskCategory)}${(item.notes?.isNotEmpty == true) ? ' - ${item.notes}' : ''}',
                    onEdit: () => _showAddSymptomDialog(editIndex: index),
                    onDelete: () => setState(() => _symptoms.removeAt(index)),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddSymptomDialog({int? editIndex}) async {
    _SymptomEntry? existing = editIndex != null && editIndex < _symptoms.length ? _symptoms[editIndex] : null;

    SymptomType? selectedType;
    if (existing != null) {
      final matchIndex = _symptomTypes.indexWhere(
        (st) => st.id == existing.symptomTypeId || st.name.toLowerCase() == existing.name.toLowerCase(),
      );
      if (matchIndex != -1) {
        selectedType = _symptomTypes[matchIndex];
      } else {
        selectedType = SymptomType(
          id: existing.symptomTypeId,
          name: existing.name,
          riskCategory: existing.riskCategory,
        );
      }
    } else if (_symptomTypes.isNotEmpty) {
      selectedType = _symptomTypes.first;
    }

    final customNameCtrl = TextEditingController(text: existing?.name ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String selectedRisk = selectedType?.riskCategory ?? existing?.riskCategory ?? 'normal';

    final List<Map<String, String>> commonSymptoms = [
      {'name': 'Nausea / Morning Sickness', 'risk': 'normal'},
      {'name': 'Fatigue / Tiredness', 'risk': 'normal'},
      {'name': 'Mild Headache', 'risk': 'normal'},
      {'name': 'Backache', 'risk': 'normal'},
      {'name': 'Dizziness', 'risk': 'warning'},
      {'name': 'Swelling / Edema', 'risk': 'warning'},
      {'name': 'Heartburn', 'risk': 'normal'},
      {'name': 'Vaginal Bleeding', 'risk': 'danger'},
      {'name': 'Severe Abdominal Pain', 'risk': 'danger'},
      {'name': 'High Fever', 'risk': 'danger'},
      {'name': 'Decreased Fetal Movement', 'risk': 'danger'},
    ];

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            width: MediaQuery.of(ctx).size.width * 0.9,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                final isCustom = _symptomTypes.isEmpty;
                final symptomName = isCustom ? customNameCtrl.text.trim() : (selectedType?.name ?? customNameCtrl.text.trim());
                final isValid = symptomName.isNotEmpty;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.brandText),
                          onPressed: () => Navigator.pop(dialogCtx, false),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              editIndex != null ? 'Edit Symptom' : 'Add Symptom',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.brandText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Common Pregnancy Symptoms',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: commonSymptoms.map((sym) {
                                final name = sym['name']!;
                                final risk = sym['risk']!;
                                final isSelected = symptomName.toLowerCase() == name.toLowerCase();

                                Color chipColor;
                                if (risk == 'danger') {
                                  chipColor = AppColors.error;
                                } else if (risk == 'warning') {
                                  chipColor = AppColors.warning;
                                } else {
                                  chipColor = AppColors.brandPrimary;
                                }

                                return ActionChip(
                                  label: Text(
                                    name,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : chipColor,
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  backgroundColor: isSelected ? chipColor : Colors.white,
                                  side: BorderSide(color: chipColor),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      if (_symptomTypes.isNotEmpty) {
                                        final matchIndex = _symptomTypes.indexWhere(
                                          (st) => st.name.toLowerCase() == name.toLowerCase(),
                                        );
                                        if (matchIndex != -1) {
                                          selectedType = _symptomTypes[matchIndex];
                                        }
                                      }
                                      customNameCtrl.text = name;
                                      selectedRisk = risk;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            if (!isCustom) ...[
                              const Text(
                                'Select Symptom',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              AppDropdownField<SymptomType>(
                                hintText: 'Select pregnancy symptom',
                                value: selectedType,
                                options: _symptomTypes,
                                displayStringForOption: (st) => st.name,
                                onSelected: (st) {
                                  if (st != null) {
                                    setDialogState(() {
                                      selectedType = st;
                                      customNameCtrl.text = st.name;
                                      selectedRisk = st.riskCategory;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 14),
                            ] else ...[
                              AppInputField(
                                hintText: 'Symptom Name',
                                controller: customNameCtrl,
                                isRequired: true,
                                onChanged: (_) => setDialogState(() {}),
                              ),
                              const SizedBox(height: 14),
                            ],
                            const Text(
                              'Risk Level',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            AppDropdownField<String>(
                              hintText: 'Select risk level',
                              value: selectedRisk,
                              options: const ['normal', 'warning', 'danger'],
                              displayStringForOption: (val) {
                                switch (val) {
                                  case 'danger':
                                    return 'Needs Urgent Attention';
                                  case 'warning':
                                    return 'Needs Closer Monitoring';
                                  default:
                                    return 'Standard / Expected';
                                }
                              },
                              onSelected: (val) {
                                if (val != null) {
                                  setDialogState(() => selectedRisk = val);
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            AppInputField(
                              hintText: 'Notes / details (optional)',
                              controller: notesCtrl,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isValid ? AppColors.brandPrimary : Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isValid
                            ? () {
                                final typeId = selectedType?.id ??
                                    (_symptomTypes.isNotEmpty ? _symptomTypes.first.id : 1);
                                final entry = _SymptomEntry(
                                  symptomTypeId: typeId,
                                  name: symptomName,
                                  riskCategory: selectedRisk,
                                  notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                                );
                                setState(() {
                                  if (editIndex != null && editIndex < _symptoms.length) {
                                    _symptoms[editIndex] = entry;
                                  } else {
                                    _symptoms.add(entry);
                                  }
                                });
                                Navigator.pop(dialogCtx, true);
                              }
                            : null,
                        child: Text(
                          editIndex != null ? 'Save Changes' : 'Add Symptom',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          title: 'Supplements',
          child: Column(
            children: [
              AppInputField(
                hintText: 'Ferrous + FA quantity',
                controller: _ferrousQtyCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: _ferrousError,
              ),
              const SizedBox(height: 10),
              AppInputField(
                hintText: 'Calcium quantity',
                controller: _calciumQtyCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: _calciumError,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'TD Vaccine',
          child: _availableTdDoses.isEmpty
              ? Row(
                  children: const [
                    Icon(Icons.check_circle_outline,
                        color: AppColors.success, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Complete TD vaccination received.',
                      style: TextStyle(color: AppColors.success),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppDropdownField<String>(
                      hintText: 'Select dose given today',
                      value: _tdDose,
                      options: _availableTdDoses,
                      displayStringForOption: (t) => t,
                      onSelected: (value) => setState(() => _tdDose = value),
                    ),
                    if (_allTakenTdDoses.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: _allTakenTdDoses
                            .map((d) => Chip(
                                  label: Text(d,
                                      style: const TextStyle(fontSize: 12)),
                                  backgroundColor: AppColors.bgSecondary,
                                  side: const BorderSide(
                                      color: AppColors.borderPrimary),
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Already given doses shown above.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ── AI Remarks Generation (Option C) ──────────────────────────────────────
  Future<void> _generateAiRemarks() async {
    setState(() => _generatingAiRemarks = true);
    try {
      final draft = _buildRuleBasedRiskSnapshot();
      final prompt = _buildAiPrompt(draft);
      _lastRiskAiPrompt = prompt;

      final aiText = await _groqService.generateTextInsight(
        prompt: prompt,
        temperature: 0.1,
        maxOutputTokens: 2600,
      );

      if (!mounted) return;

      // Parse bilingual response
      final parsed = _parseBilingualText(aiText);
      final englishText = parsed['english'] ?? aiText;
      final filipinoText = parsed['filipino'] ?? '';

      setState(() {
        _aiRemarksEnglish = englishText;
        _aiRemarksFilipino = filipinoText;
        _aiOriginalRemarksEn = englishText;
        _aiOriginalRemarksFil = filipinoText;
        _aiRemarksModel = 'Groq';
        _remarksSource = 'ai_generated_approved';
        _remarksCtrl.text = _remarksLanguage == 'english' ? englishText : filipinoText;
        // Sync risk snapshot for persistence
        _riskSnapshot = draft.copyWith(
          aiAssessment: aiText,
          aiGenerated: true,
          aiModel: 'Groq',
        );
      });
    } catch (_) {
      if (!mounted) return;
      // Fallback to rule-based text
      final draft = _buildRuleBasedRiskSnapshot();
      final en = _buildRuleBasedAssessmentText(draft);
      final fil = _buildRuleBasedAssessmentTextFilipino(draft);
      setState(() {
        _aiRemarksEnglish = en;
        _aiRemarksFilipino = fil;
        _aiOriginalRemarksEn = en;
        _aiOriginalRemarksFil = fil;
        _aiRemarksModel = 'Rule Engine';
        _remarksSource = 'ai_generated_approved';
        _remarksCtrl.text = _remarksLanguage == 'english' ? en : fil;
        _riskSnapshot = draft;
      });
      _showMessage(
        'AI unavailable. Showing rule-based insight instead.',
        type: AppSnackType.info,
      );
    } finally {
      if (mounted) setState(() => _generatingAiRemarks = false);
    }
  }

  void _onRemarksChanged() {
    final text = _remarksCtrl.text.trim();
    if (text.isEmpty) {
      // Reset AI state when midwife deletes everything
      setState(() {
        _remarksSource = 'midwife_authored';
        _aiRemarksEnglish = '';
        _aiRemarksFilipino = '';
        _aiOriginalRemarksEn = null;
        _aiOriginalRemarksFil = null;
      });
      return;
    }

    if (_remarksSource != 'midwife_authored') {
      setState(() => _remarksSource = 'ai_generated_edited');
      // Save edits strictly to the active language version so English & Tagalog remain distinct
      if (_remarksLanguage == 'english') {
        _aiRemarksEnglish = _remarksCtrl.text;
      } else {
        _aiRemarksFilipino = _remarksCtrl.text;
      }
    }
  }

  void _switchRemarksLanguage(String lang) {
    if (lang == _remarksLanguage) return;
    if (_remarksSource != 'midwife_authored') {
      if (_remarksLanguage == 'english') {
        _aiRemarksEnglish = _remarksCtrl.text;
      } else {
        _aiRemarksFilipino = _remarksCtrl.text;
      }
    }
    setState(() {
      _remarksLanguage = lang;
      if (_remarksSource != 'midwife_authored') {
        _remarksCtrl.text = lang == 'english' ? _aiRemarksEnglish : _aiRemarksFilipino;
      }
    });
  }

  Widget _buildStep4() {
    if (_nextSchedule == null) {
      _nextSchedule = _calculateRecommendedNextSchedule();
    }
    final bool hasAiRemarks = _remarksSource != 'midwife_authored';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          title: 'Next Visit',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInputField(
                hintText: 'Tap to set recommended next visit (optional)',
                controller: TextEditingController(
                  text: _nextSchedule == null
                      ? ''
                      : DateFormat('MMMM d, yyyy (EEEE)').format(_nextSchedule!),
                ),
                readOnly: true,
                onTap: _pickNextSchedule,
                leadingIcon: Icons.calendar_month,
                trailingIcon: _nextSchedule != null ? Icons.clear : null,
                onTrailingTap: _nextSchedule != null
                    ? () => setState(() => _nextSchedule = null)
                    : null,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 13, color: AppColors.brandPrimary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _nextSchedule != null
                          ? 'Auto-suggested based on ${_scheduleRecommendationReason()}. Tap field to edit.'
                          : 'No next visit scheduled. Tap above to pick a custom date.',
                      style: const TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Remarks',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── AI badge + bilingual toggle row ──────────────────────────
              if (hasAiRemarks) ...[
                Row(
                  children: [
                    // AI-Assisted badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.brandPrimary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.smart_toy_outlined, size: 13, color: AppColors.brandPrimary),
                          const SizedBox(width: 4),
                          Text(
                            _remarksSource == 'ai_generated_edited'
                                ? 'AI-Assisted (Edited)'
                                : 'AI-Assisted',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brandPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Bilingual toggle
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.bgSecondary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _langToggleChip('English', 'english'),
                          _langToggleChip('Tagalog', 'filipino'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // ── Remarks text field ──────────────────────────────────────
              TextField(
                controller: _remarksCtrl,
                onChanged: (_) => _onRemarksChanged(),
                maxLines: 5,
                maxLength: 1000,
                style: const TextStyle(fontSize: 13, height: 1.5),
                decoration: InputDecoration(
                  hintText: hasAiRemarks
                      ? 'AI-generated insight (editable)...'
                      : 'Clinical notes, observations (optional)',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  border: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.borderPrimary),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: hasAiRemarks
                          ? AppColors.brandPrimary.withValues(alpha: 0.3)
                          : AppColors.borderPrimary,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppColors.brandPrimary),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),

              // ── Helper text for AI ──────────────────────────────────────
              if (hasAiRemarks) ...[
                const SizedBox(height: 4),
                Row(
                  children: const [
                    Icon(Icons.info_outline, size: 12, color: AppColors.textSecondary),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'You can edit freely. The original AI text is saved for audit.',
                        style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // ── Generate AI Insight button ──────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _generatingAiRemarks ? null : _generateAiRemarks,
                  icon: _generatingAiRemarks
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.brandPrimary,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(
                    _generatingAiRemarks
                        ? 'Generating...'
                        : hasAiRemarks
                            ? 'Regenerate AI Insight'
                            : 'Generate AI Checkup Insight',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandPrimary,
                    side: BorderSide(
                      color: AppColors.brandPrimary.withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _langToggleChip(String label, String lang) {
    final isActive = _remarksLanguage == lang;
    return GestureDetector(
      onTap: () => _switchRemarksLanguage(lang),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? AppColors.brandPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  List<String> _getDetectedRiskFactors() {
    final factors = <String>[];

    final sys = int.tryParse(_sysCtrl.text.trim());
    final dia = int.tryParse(_diaCtrl.text.trim());
    if (sys != null && dia != null) {
      if (sys >= 160 || dia >= 110) {
        factors.add('Severe Hypertension (≥160/110 mmHg)');
      } else if (sys >= 140 || dia >= 90) {
        factors.add('Hypertension in Pregnancy (≥140/90 mmHg)');
      } else if (sys < 90 || dia < 60) {
        factors.add('Low Blood Pressure (<90/60 mmHg)');
      }
    }

    final currentWeight = double.tryParse(_weightCtrl.text.trim());
    if (currentWeight != null && _aogWeeks != null) {
      try {
        final motherData = _motherRiskContext?['mother'] as Map<String, dynamic>?;
        final pregnancy = _motherRiskContext?['pregnancy'] as Map<String, dynamic>?;
        final prePregnancyWeight = pregnancy?['pre_pregnancy_weight'] != null
            ? double.tryParse(pregnancy!['pre_pregnancy_weight'].toString())
            : null;
        final heightCm = motherData?['height'] != null
            ? double.tryParse(motherData!['height'].toString())
            : null;
        final result = WeightGainEngine.evaluate(
          currentWeight: currentWeight,
          aogWeeks: _aogWeeks!,
          allCheckups: const [],
          prePregnancyWeight: prePregnancyWeight,
          heightCm: heightCm,
          fetalCount: _fetalCount ?? 1,
        );
        if (result.status == WeightGainStatus.low) {
          factors.add('Weight Gain: Inadequate Gain');
        } else if (result.status == WeightGainStatus.high) {
          factors.add('Weight Gain: Excessive Gain');
        }
      } catch (_) {}
    }

    if (_edema == 'moderate' || _edema == 'severe') {
      factors.add('${_edema[0].toUpperCase()}${_edema.substring(1)} Edema');
    }
    for (final s in _symptoms) {
      if (s.riskCategory == 'danger') {
        factors.add('Urgent Symptom: ${s.name}');
      } else if (s.riskCategory == 'warning') {
        factors.add('Monitored Symptom: ${s.name}');
      }
    }

    final medicalConditions = _motherRiskContext?['medical_conditions'] as List<dynamic>?;
    if (medicalConditions != null) {
      for (final mc in medicalConditions) {
        final name = mc['condition_name'] ?? mc['name'];
        if (name != null && name.toString().isNotEmpty) {
          factors.add('Medical History: $name');
        }
      }
    }

    return factors;
  }

  Widget _buildStep5() {
    final bpText =
        '${_sysCtrl.text.trim().isEmpty ? '-' : _sysCtrl.text.trim()}/'
        '${_diaCtrl.text.trim().isEmpty ? '-' : _diaCtrl.text.trim()} mmHg';
    final detectedFactors = _getDetectedRiskFactors();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildClickableSummarySection(
          'PREGNANCY RISK ASSESSMENT',
          [
            Row(
              children: [
                const SizedBox(
                  width: 125,
                  child: Text(
                    'Risk Override',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      _riskSegmentOption('low', 'Low Risk', AppColors.success),
                      const SizedBox(width: 8),
                      _riskSegmentOption('high', 'High Risk', AppColors.error),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 125,
                  child: Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Detected Factors',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                Expanded(
                  child: detectedFactors.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'No critical risk factors',
                            style: TextStyle(fontSize: 13, color: AppColors.brandText),
                          ),
                        )
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: detectedFactors.map((factor) {
                            final isHigh = factor.toLowerCase().contains('severe') ||
                                factor.toLowerCase().contains('hypertension') ||
                                factor.toLowerCase().contains('urgent');
                            final chipColor = isHigh ? AppColors.error : AppColors.warning;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: chipColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: chipColor.withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isHigh ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                                    size: 13,
                                    color: chipColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    factor,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: chipColor,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ],
          onTap: () {},
        ),
        const SizedBox(height: 12),
        _buildClickableSummarySection(
          'VITALS',
          [
            _summaryRow('Checkup Date',
                DateFormat('MMM d, yyyy h:mm a').format(_checkupDateTime)),
            if (_aogWeeks != null)
              _summaryRow('AOG', '${_aogWeeks!.toInt()} weeks'),
            _summaryRow(
              'Weight',
              _weightCtrl.text.trim().isEmpty
                  ? 'Not recorded'
                  : '${_weightCtrl.text.trim()} kg',
              badge: _weightGainStatusPill(),
            ),
            _summaryRow(
              'Blood Pressure',
              bpText,
              badge: _bpStatusPill(),
            ),
          ],
          onTap: () => _jumpToStep(0),
        ),
        _buildClickableSummarySection(
          'FETAL ASSESSMENT',
          [
            _summaryRow(
              'Fetal Heart Rate',
              _fetalBeatCtrl.text.trim().isEmpty
                  ? 'Not recorded'
                  : '${_fetalBeatCtrl.text.trim()} bpm',
            ),
            _summaryRow('Heart Tone', _fetalTone ?? 'Not recorded'),
          ],
          onTap: () => _jumpToStep(1),
        ),
        _buildClickableSummarySection(
          'SYMPTOMS & EDEMA',
          [
            _summaryRow(
              'Edema Level',
              _edema == 'none'
                  ? 'None'
                  : '${_edema[0].toUpperCase()}${_edema.substring(1)}',
            ),
            _summaryRow(
              'Symptoms',
              _symptoms.isEmpty
                  ? 'None recorded'
                  : _symptoms.map((s) => s.name).join(', '),
            ),
          ],
          onTap: () => _jumpToStep(2),
        ),
        _buildClickableSummarySection(
          'SUPPLEMENTS & TD VACCINE',
          [
            _summaryRow(
              'Ferrous + FA',
              _ferrousQtyCtrl.text.trim().isEmpty
                  ? 'Not given'
                  : '${_ferrousQtyCtrl.text.trim()} tablet${(int.tryParse(_ferrousQtyCtrl.text.trim()) ?? 0) != 1 ? 's' : ''}',
            ),
            _summaryRow(
              'Calcium',
              _calciumQtyCtrl.text.trim().isEmpty
                  ? 'Not given'
                  : '${_calciumQtyCtrl.text.trim()} tablet${(int.tryParse(_calciumQtyCtrl.text.trim()) ?? 0) != 1 ? 's' : ''}',
            ),
            _summaryRow(
              'TD Vaccine Dose',
              _tdDose ??
                  (_availableTdDoses.isEmpty
                      ? 'Complete (all doses given)'
                      : 'None given today'),
            ),
          ],
          onTap: () => _jumpToStep(3),
        ),
        _buildClickableSummarySection(
          'SCHEDULE & REMARKS',
          [
            _summaryRow(
              'Next Visit',
              _nextSchedule == null
                  ? 'Not set'
                  : DateFormat('MMMM d, yyyy').format(_nextSchedule!),
            ),
            _summaryRow(
              'Remarks',
              _remarksCtrl.text.trim().isEmpty
                  ? 'None'
                  : _remarksCtrl.text.trim(),
            ),
            if (_remarksSource != 'midwife_authored') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.smart_toy_outlined, size: 11, color: AppColors.brandPrimary),
                        const SizedBox(width: 3),
                        Text(
                          _remarksSource == 'ai_generated_edited'
                              ? 'AI-Assisted (Edited by Midwife)'
                              : 'AI-Assisted',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
          onTap: () => _jumpToStep(4),
        ),
      ],
    );
  }

  bool get _hasEnteredData =>
      _weightCtrl.text.trim().isNotEmpty ||
      _sysCtrl.text.trim().isNotEmpty ||
      _diaCtrl.text.trim().isNotEmpty ||
      _fetalBeatCtrl.text.trim().isNotEmpty ||
      _symptoms.isNotEmpty ||
      _remarksCtrl.text.trim().isNotEmpty ||
      _ferrousQtyCtrl.text.trim().isNotEmpty ||
      _calciumQtyCtrl.text.trim().isNotEmpty;

  Future<bool> _showSkipCheckupDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Skip Initial Checkup?',
        subtitle: 'The initial prenatal checkup is required to complete the '
            'mother\'s registration. Skipping will leave her record '
            'incomplete.\n\nAre you sure you want to skip?',
        cancelText: 'Continue Checkup',
        confirmText: 'Skip',
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
    return result ?? false;
  }

  Future<bool> _showDiscardCheckupDialog() async {
    if (!_hasEnteredData) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Discard changes?',
        subtitle:
            'You have unsaved prenatal checkup data. Are you sure you want to go back?',
        cancelText: 'Cancel',
        confirmText: 'Discard',
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
    return result ?? false;
  }

  void _backOrPop() async {
    if (widget.isInitialRegistration) {
      final shouldSkip = await _showSkipCheckupDialog();
      if (shouldSkip && mounted) Navigator.pop(context);
    } else {
      final shouldDiscard = await _showDiscardCheckupDialog();
      if (shouldDiscard && mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _backOrPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        floatingActionButton: _step == 2
            ? FloatingActionButton(
                onPressed: _showAddSymptomDialog,
                backgroundColor: AppColors.brandPrimary,
                shape: const CircleBorder(),
                child: const Icon(Icons.add, color: Colors.white),
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              SecondaryHeader(
                title: 'Add Prenatal Checkup',
                onBack: _backOrPop,
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
                child: _stepTitle(),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: _buildStepContent(),
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
              child: Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      child: MainButton(
                        label: 'Back',
                        leftIcon: Icons.arrow_back_ios_new_rounded,
                        isWhiteVariant: true,
                        onPressed: _submitting ? null : _back,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: (_step > 0) ? 2 : 1,
                    child: _step == _totalSteps - 1
                        ? MainButton(
                            label: 'Save Checkup',
                            rightIcon: Icons.check_rounded,
                            onPressed: _submitting ? null : _submitCheckup,
                          )
                        : MainButton(
                            label: 'Next',
                            rightIcon: Icons.arrow_forward_ios_rounded,
                            onPressed: _submitting ? null : _next,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
