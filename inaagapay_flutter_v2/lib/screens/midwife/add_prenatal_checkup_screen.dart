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
import '../../widgets/pregnancy_risk_override.dart';
import '../../services/sms_service.dart';
import '../../services/notification_service.dart';
import '../../services/prenatal_schedule_engine.dart';
import '../../services/blood_pressure_reference.dart';
import '../../services/fetal_heart_rate_reference.dart';
import '../../services/maternal_td_service.dart';
import '../../services/stock_deduction_outcome.dart';
import '../../widgets/stock_indicators.dart';
import 'maternal_td_screen.dart';

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
  })  : sourceTable = null,
        sourceId = null;

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
  int? _midwifeId;
  int? _midwifeBhcId;
  String? _midwifeName;
  int? _accountId;
  int _tdStockAvailable = 0;
  int _tdOpenVialDoses = 0;
  String? _tdOpenVialBatch;
  DateTime? _tdOpenVialOpenedAt;
  int _tdSealedVials = 0;
  String? _tdNextBatch;
  int _ferrousStockAvailable = 0;
  int _calciumStockAvailable = 0;
  bool _tdGivenOnSite = true;
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
  // Remarks are written once, in Tagalog. Mothers read this text in the record
  // view, so there is one version of it to write, edit and store — no second
  // language to keep in sync and no toggle to get wrong.
  String? _aiOriginalRemarks;      // original AI Tagalog text (for audit)
  String _aiRemarks = '';          // stored AI Tagalog text
  String? _aiRemarksModel;         // AI model used
  double? _initialSessionWeight;   // Locked baseline weight for session calculation

  static const List<String> _fetalTones = [
    'Regular',
    'Irregular',
    'Faint',
    'Absent',
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
    _nextSchedule ??= _calculateRecommendedNextSchedule();
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
          .select('*')
          .eq('pregnancy_id', widget.pregnancyId)
          .limit(1);

      final hasUltrasound = ultrasoundRes.isNotEmpty;

      final res = await Supabase.instance.client
          .from('pregnancies')
          .select('fetal_count')
          .eq('pregnancy_id', widget.pregnancyId)
          .maybeSingle(); // ← FIXED: Changed from .single()

      if (res != null && mounted) {
        final dbFetalCount = int.tryParse(res['fetal_count']?.toString() ?? '');
        setState(() {
          // Only reflect fetal count if there are ultrasound records; otherwise display Unknown
          _fetalCount = hasUltrasound ? dbFetalCount : null;
        });
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadLatestCheckupWeight() async {
    try {
      // 1. Fetch latest prenatal checkup weight
      final checkupRes = await Supabase.instance.client
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

      double? checkupWeight;
      DateTime? checkupDate;

      if (checkupRes != null) {
        checkupDate = DateTime.tryParse(checkupRes['encounter_datetime']?.toString() ?? '');
        dynamic checkupData = checkupRes['checkup'];
        Map<String, dynamic>? innerCheckup;
        if (checkupData is List && checkupData.isNotEmpty) {
          innerCheckup = checkupData.first as Map<String, dynamic>?;
        } else if (checkupData is Map) {
          innerCheckup = Map<String, dynamic>.from(checkupData);
        }
        if (innerCheckup != null && innerCheckup['checkup_weight'] != null) {
          checkupWeight = double.tryParse(innerCheckup['checkup_weight'].toString());
        }
      }

      // 2. Fetch latest maternal vital weight
      final vitalRes = await Supabase.instance.client
          .from('maternal_vitals')
          .select('recorded_at, weight_kg')
          .eq('pregnancy_id', widget.pregnancyId)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      double? vitalWeight;
      DateTime? vitalDate;

      if (vitalRes != null && vitalRes['weight_kg'] != null) {
        vitalDate = DateTime.tryParse(vitalRes['recorded_at']?.toString() ?? '');
        vitalWeight = double.tryParse(vitalRes['weight_kg'].toString());
      }

      // 3. Determine the absolute latest weight
      double? latestWeight;
      if (checkupWeight != null && vitalWeight != null && checkupDate != null && vitalDate != null) {
        if (checkupDate.isAfter(vitalDate)) {
          latestWeight = checkupWeight;
        } else {
          latestWeight = vitalWeight;
        }
      } else {
        latestWeight = checkupWeight ?? vitalWeight;
      }

      if (latestWeight != null && mounted) {
        setState(() {
          _weightCtrl.text = latestWeight!.toStringAsFixed(1);
        });
      }
    } catch (e) {
      debugPrint('Error loading latest weight: $e');
    }
  }

  Future<void> _loadMidwifeId() async {
    final accountId = await AuthStorage.getUserId();
    if (accountId == null) return;
    if (mounted) setState(() => _accountId = accountId);
    try {
      final result = await Supabase.instance.client
          .from('midwives')
          .select('midwife_id, assigned_bhc_id, account:accounts(first_name, last_name)')
          .eq('account_id', accountId)
          .maybeSingle();

      if (result != null && mounted) {
        final mwId = result['midwife_id'] as int;
        final bhcId = result['assigned_bhc_id'] as int?;
        String? mwName;
        final acc = result['account'] as Map<String, dynamic>?;
        if (acc != null) {
          mwName = '${acc['first_name'] ?? ''} ${acc['last_name'] ?? ''}'.trim();
        }
        setState(() {
          _midwifeId = mwId;
          _midwifeBhcId = bhcId;
          _midwifeName = mwName;
        });
        if (bhcId != null) {
          _loadFacilityInventory(bhcId);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadFacilityInventory(int facilityId) async {
    if (!mounted) return;
    try {
      final batches = await Supabase.instance.client
          .from('inventory_batches')
          .select('batch_number, quantity_remaining, expiration_date, status, doses_remaining_in_open_vial, vial_opened_at, item:inventory_items(name, generic_name, item_type, doses_per_unit)')
          .eq('facility_id', facilityId)
          .eq('status', 'active')
          .order('expiration_date', ascending: true);

      int tdDoses = 0;
      int tdOpenDoses = 0;
      String? tdOpenBatch;
      DateTime? tdOpenOpenedAt;
      int tdSealed = 0;
      String? tdNextBatch;
      int ferrousTabs = 0;
      int calciumTabs = 0;
      final now = DateTime.now();

      for (final b in (batches as List)) {
        final expStr = b['expiration_date']?.toString();
        if (expStr != null) {
          final exp = DateTime.tryParse(expStr);
          if (exp != null && exp.isBefore(now)) continue;
        }
        final item = b['item'] as Map<String, dynamic>?;
        if (item == null) continue;
        final name = (item['name']?.toString() ?? '').toLowerCase();
        final generic = (item['generic_name']?.toString() ?? '').toLowerCase();
        final type = (item['item_type']?.toString() ?? '').toLowerCase();
        final qty = (b['quantity_remaining'] as num?)?.toInt() ?? 0;
        final dosesPerUnit = (item['doses_per_unit'] as num?)?.toInt() ?? 1;
        final openDoses = (b['doses_remaining_in_open_vial'] as num?)?.toInt() ?? 0;
        final batchNum = b['batch_number']?.toString();
        final openedAtStr = b['vial_opened_at']?.toString();
        final openedAt = openedAtStr != null ? DateTime.tryParse(openedAtStr) : null;

        if (name.contains('td') || name.contains('tetanus') || generic.contains('tetanus') || (type == 'vaccine' && name.contains('td'))) {
          // Check if open vial is past 28-day DOH shelf limit (672 hours)
          bool isOpenVialValid = true;
          if (openDoses > 0 && openedAt != null) {
            if (now.difference(openedAt).inHours >= 672) {
              isOpenVialValid = false;
            }
          }

          if (isOpenVialValid && openDoses > 0) {
            tdDoses += openDoses;
            if (tdOpenBatch == null) {
              tdOpenDoses = openDoses;
              tdOpenBatch = batchNum;
              tdOpenOpenedAt = openedAt;
            }
          }

          tdDoses += (qty * dosesPerUnit);
          tdSealed += qty;
          if (tdNextBatch == null && qty > 0) {
            tdNextBatch = batchNum;
          }
        } else if (name.contains('ferrous') || generic.contains('ferrous') || name.contains('iron')) {
          ferrousTabs += qty;
        } else if (name.contains('calcium') || generic.contains('calcium')) {
          calciumTabs += qty;
        }
      }

      if (mounted) {
        setState(() {
          _tdStockAvailable = tdDoses;
          _tdOpenVialDoses = tdOpenDoses;
          _tdOpenVialBatch = tdOpenBatch;
          _tdOpenVialOpenedAt = tdOpenOpenedAt;
          _tdSealedVials = tdSealed;
          _tdNextBatch = tdNextBatch;
          _ferrousStockAvailable = ferrousTabs;
          _calciumStockAvailable = calciumTabs;
        });
      }
    } catch (e) {
      debugPrint('Error loading facility inventory: $e');
    }
  }

  Future<void> _loadSymptomTypes() async {
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

      // Ensure default symptoms are seeded in database if missing
      final defaultSymptoms = [
        {'symptom_name': 'Vaginal Bleeding', 'risk_category': 'danger'},
        {'symptom_name': 'Convulsions', 'risk_category': 'danger'},
        {'symptom_name': 'Severe Headache', 'risk_category': 'danger'},
        {'symptom_name': 'Blurred Vision', 'risk_category': 'danger'},
        {'symptom_name': 'Severe Abdominal Pain', 'risk_category': 'danger'},
        {'symptom_name': 'Leaking Vaginal Fluid', 'risk_category': 'danger'},
        {'symptom_name': 'No Fetal Movement', 'risk_category': 'danger'},
        {'symptom_name': 'Difficulty Breathing', 'risk_category': 'danger'},
        {'symptom_name': 'High Fever', 'risk_category': 'danger'},
        {'symptom_name': 'Severe Swelling of Face or Hands', 'risk_category': 'danger'},
        {'symptom_name': 'Reduced Fetal Movement', 'risk_category': 'danger'},
        {'symptom_name': 'Persistent Vomiting', 'risk_category': 'warning'},
        {'symptom_name': 'Painful Urination', 'risk_category': 'warning'},
        {'symptom_name': 'Pelvic Pain', 'risk_category': 'warning'},
        {'symptom_name': 'Severe Itching', 'risk_category': 'warning'},
        {'symptom_name': 'Dizziness', 'risk_category': 'warning'},
        {'symptom_name': 'Chest Pain', 'risk_category': 'warning'},
        {'symptom_name': 'Moderate Swelling', 'risk_category': 'warning'},
        {'symptom_name': 'Back Pain', 'risk_category': 'normal'},
        {'symptom_name': 'Nausea', 'risk_category': 'normal'},
        {'symptom_name': 'Vomiting', 'risk_category': 'normal'},
        {'symptom_name': 'Fatigue', 'risk_category': 'normal'},
        {'symptom_name': 'Frequent Urination', 'risk_category': 'normal'},
        {'symptom_name': 'Heartburn', 'risk_category': 'normal'},
        {'symptom_name': 'Constipation', 'risk_category': 'normal'},
        {'symptom_name': 'Skin Rash', 'risk_category': 'normal'},
        {'symptom_name': 'Other', 'risk_category': 'normal'},
      ];

      final existingNames = parsed.map((st) => st.name.trim().toLowerCase()).toSet();
      final toInsert = defaultSymptoms.where((ds) {
        final name = ds['symptom_name']!.trim().toLowerCase();
        return !existingNames.contains(name);
      }).toList();

      if (toInsert.isNotEmpty) {
        try {
          await Supabase.instance.client.from('symptom_types').insert(toInsert);
          final retryRows = await Supabase.instance.client
              .from('symptom_types')
              .select('symptom_type_id, symptom_name, risk_category, description')
              .order('risk_category')
              .order('symptom_name');
          final retryParsed = (retryRows as List)
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
          setState(() => _symptomTypes = retryParsed);
          return;
        } catch (e) {
          debugPrint('Failed to seed missing symptom types: $e');
        }
      }

      if (!mounted) return;
      setState(() => _symptomTypes = parsed);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Unable to load symptom types. Please try again.');
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
        final rawCheckup = enc['checkup'];
        Map<String, dynamic>? checkupData;
        if (rawCheckup is List) {
          if (rawCheckup.isNotEmpty) {
            checkupData = rawCheckup.first as Map<String, dynamic>?;
          }
        } else if (rawCheckup is Map) {
          checkupData = Map<String, dynamic>.from(rawCheckup);
        }
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
        if (pregLevel != null && pregLevel.isNotEmpty) {
          _pregnancyRiskLevel = pregLevel;
        }

        final motherHeight = mother?['height']?.toString();
        if (motherHeight != null && motherHeight.isNotEmpty && motherHeight != 'null') {
          _heightCtrl.text = '$motherHeight cm';
        } else {
          _heightCtrl.text = 'Not recorded in profile';
        }

        _nextSchedule = _calculateRecommendedNextSchedule();
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

    return _buildRuleBasedAssessmentTextFilipino(snapshot);
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
    if (bpText != null && _bpCategory == BpCategory.normal) {
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
    if (bpText != null && _bpCategory == BpCategory.normal) {
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

  /// Pulls the Tagalog summary out of an AI response.
  ///
  /// The prompt asks for Tagalog only, so normally the whole response *is* the
  /// summary. The old section markers are still honoured because a model can
  /// slip a heading in and because records saved before this change stored both
  /// languages in one column. If only English came back, this returns an empty
  /// string so the caller can fall back to the rule-based Tagalog text rather
  /// than showing a mother a summary she cannot read.
  String _extractTagalogText(String text) {
    const filTag = '=== FILIPINO ===';
    const enTag = '=== ENGLISH ===';
    final filipinoIndex = text.indexOf(filTag);
    final englishIndex = text.indexOf(enTag);

    if (filipinoIndex != -1) {
      final start = filipinoIndex + filTag.length;
      final end = englishIndex > filipinoIndex ? englishIndex : text.length;
      return text.substring(start, end).trim();
    }
    if (englishIndex != -1) return '';
    return text.trim();
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
      final bpCat = BloodPressureReference.categorise(systolic, diastolic);
      if (bpCat == BpCategory.raised || bpCat == BpCategory.severe) {
        isHigh = true;
        factors.add(_RiskFactorItem(
          factor: 'Raised blood pressure (>=140/90)',
          influence: 'high',
        ));
        actions
            .add('Monitor blood pressure closely and screen for preeclampsia.');
      }
    }

    // 2. Fetal Heart Rate Thresholds
    if (fetalBeat != null) {
      notable.add('Fetal heart rate: $fetalBeat bpm');
      final fhrAssessment = FetalHeartRateReference.assess(fetalBeat);
      if (fhrAssessment.isOutsideBaseline) {
        isHigh = true;
        factors.add(_RiskFactorItem(
          factor: 'Fetal heart rate outside baseline ($fetalBeat bpm)',
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

    final symptomLines = _symptoms
        .map((s) =>
            '- ${s.name} [${s.riskCategory}]${(s.notes ?? '').trim().isEmpty ? '' : ' | note: ${s.notes!.trim()}'}')
        .toList();

    // Calculate Weight Gain Evaluation using unified baseline resolution
    WeightGainResult? wgResult;
    try {
      final currentWeight = double.tryParse(_weightCtrl.text.trim());
      if (currentWeight != null && _aogWeeks != null && _aogWeeks! > 0) {
        final heightCm = mother?['height'] != null
            ? double.tryParse(mother!['height'].toString())
            : null;

        final effectivePrePreg = _resolveBaselineWeight();
        final checkupList = _buildCurrentCheckupList();

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

    if (sysVal != null && diaVal != null) {
      final bpCat = BloodPressureReference.categorise(sysVal, diaVal);
      switch (bpCat) {
        case BpCategory.severe:
        case BpCategory.raised:
          bpAssessmentStr = 'RAISED / HIGH ($sysVal/$diaVal mmHg. DO NOT SAY THIS IS WITHIN EXPECTED RANGE! PUT THIS IN FLAGGED ITEMS SENTENCE 2!)';
          break;
        case BpCategory.low:
          bpAssessmentStr = 'LOW / BELOW STANDARD RANGE ($sysVal/$diaVal mmHg)';
          break;
        case BpCategory.normal:
          bpAssessmentStr = 'WITHIN EXPECTED RANGE ($sysVal/$diaVal mmHg)';
          break;
        case BpCategory.unreadable:
          bpAssessmentStr = 'Not recorded';
          break;
      }
    } else {
      bpAssessmentStr = 'Not recorded';
    }

    final aogWeekStr = _aogWeeks != null ? '${_aogWeeks!.toInt()}' : '7';

    return '''[CRITICAL INSTRUCTIONS - ANATOMY & STRUCTURE MANDATE]

LANGUAGE MANDATE: Write the ENTIRE output in Tagalog. Do NOT produce an English version and do NOT add language headings. Keep clinical terms in English exactly as they appear here (blood pressure, fetal heart rate, edema, mmHg, bpm, kg, AOG, BMI) — rural mothers know these terms in English and translating them causes confusion. Everything around those terms is Tagalog. The example sentences below are written in English only to show you the required STRUCTURE; your output must be Tagalog.

You must structure the Tagalog assessment using this EXACT 3-part formula:

HEADER:
- "Buod ng Checkup — Linggo $aogWeekStr ng AOG"

SENTENCE 1: THE REASSURANCE ANCHOR
- Lead ONLY with vitals/findings that are WITHIN EXPECTED RANGE, including ACTUAL NUMBERS (e.g. "Fetal heart rate (${_fetalBeatCtrl.text.trim().isEmpty ? '140 bpm' : '${_fetalBeatCtrl.text.trim()} bpm'}) is within expected range this visit.").
- CRITICAL BLOOD PRESSURE RULE: ONLY include Blood Pressure in Sentence 1 if Blood Pressure Assessment is explicitly "WITHIN EXPECTED RANGE". If BP is RAISED or ELEVATED (e.g. raised systolic or diastolic), DO NOT put BP in Sentence 1! Place BP in Sentence 2 (Flagged Items)!
- NEVER use the word "normal" or "normal values". Use "within expected range" or "within commonly expected range".

SENTENCE 2: THE FLAGGED ITEMS (DATA, COMPARISON, REASSURANCE, SOFT ACTION)
- If weight gain, blood pressure (e.g. raised reading), edema, or symptoms are flagged or elevated:
  1. State finding plainly with ACTUAL NUMBERS & COMPARISON (e.g. "Blood pressure was recorded at $sysVal/$diaVal mmHg (raised reading), and weight gain is a bit ahead of pace for this BMI category (+2.0 kg vs. an expected 0–1.2 kg)").
  2. Immediately normalize it if common (e.g. "both are common at this stage and usually settle on their own").
  3. Suggest a soft non-urgent monitoring step (e.g. "but worth tracking closely at your next checkup").
- If NO items are flagged, write: "All recorded vitals and findings are progressing smoothly for this stage of pregnancy."

CRITICAL SAFETY & MIDWIFE POV RULES:
- REMOVE ALL DISCLAIMER LINES. DO NOT include any line like "General summary, not a diagnosis..."!
- MIDWIFE POV MANDATE: The midwife is the healthcare provider entering these remarks! NEVER say "with your midwife or healthcare provider" or "consult your midwife". Say "requires clinical evaluation / doctor consultation" if severe.
- NEVER write "No abnormal vital signs were noted" or claim findings are normal if Blood pressure is RAISED or Edema is Moderate/Severe!
- If Blood pressure is RAISED or Edema is Moderate/Severe:
  * Sentence 1 (Anchor): Lead ONLY with passed vitals (e.g. "Fetal heart rate is within expected range this visit.").
  * Sentence 2 (Flagged Items): Plainly state findings: "Blood pressure was recorded at $sysVal/$diaVal mmHg (raised reading), weight gain is +2.0 kg (above expected), and moderate swelling was observed — these findings require close monitoring and doctor consultation."
- KEEP THE SUMMARY CONCISE AND UNDER 280 CHARACTERS TOTAL.
- Never say "pre-pregnancy weight not provided" or "interpretation is limited".
- Do NOT use diagnostic or alarmist language.
- Do NOT use bullet points, disclaimer footers, or extra headers.

OUTPUT FORMAT REQUIREMENTS (Tagalog only, no language headings):
Buod ng Checkup — Linggo $aogWeekStr ng AOG

[Sentence 1: Reassurance Anchor with actual numbers of WITHIN RANGE vitals]
[Sentence 2: Flagged items with comparison, normalization, and soft action OR smooth progress confirmation]

GOOD EXAMPLE OUTPUT (BP 120/90 mmHg - Elevated Diastolic):
Buod ng Checkup — Linggo $aogWeekStr ng AOG

Ang fetal heart rate (120 bpm) ay nasa karaniwang inaasahang antas sa bisitang ito. Ang blood pressure ay naitala sa 120/90 mmHg (mataas ang diastolic), at ang pagdagdag ng timbang ay bahagyang nauna (+2.0 kg kumpara sa inaasahang 0–1.2 kg) — pareho itong magandang masubaybayan sa susunod na checkup.

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

IMPORTANT: Your response must be ONE Tagalog summary — the header line followed by the two sentences. No English version, no language labels, no other text.''';
  }

  Future<void> _refreshRiskPreview({bool force = false}) async {
    final signature = _currentRiskSignature();
    if (!force && _lastRiskSignature == signature && _riskSnapshot != null) {
      return;
    }

    final draft = _buildRuleBasedRiskSnapshot();
    setState(() {
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
        _syncEditableRiskState(_riskSnapshot!, mergedText);
        _lastRiskSignature = signature;
      });
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

  /// Canonical maternal Td state.
  ///
  /// Read through [MaternalTdService] so this screen and [MaternalTdScreen]
  /// share one definition of which doses a mother has had. This screen used to
  /// run its own query and compare raw strings against `'Td$i'`, which silently
  /// missed doses stored in the legacy `'TD 2'` spelling.
  MaternalTdStatus _tdStatus = MaternalTdStatus.empty;

  Future<void> _loadTakenTdDoses() async {
    final status = await MaternalTdService.fetchStatus(
      widget.motherId,
      extraDoseKeys: widget.takenTdDoses,
    );
    if (mounted) {
      setState(() => _tdStatus = status);
    }
  }

  /// One-line answer to "when is her next Td dose?", worded identically to the
  /// dedicated Td screen.
  String _prenatalTdTimingLabel() {
    final next = _tdStatus.nextDoseKey;
    if (next == null) return 'All 5 doses complete. No further Td needed.';

    switch (_tdStatus.nextAction) {
      case TdNextAction.eligibleNow:
        return '$next may be given today.';
      case TdNextAction.waiting:
        final on = _tdStatus.nextEligibleDate;
        final days = _tdStatus.daysUntilEligible;
        return on == null
            ? '$next is not due yet.'
            : 'No Td needed today. $next is due ${DateFormat('MMMM d, yyyy').format(on)} '
                '($days ${days == 1 ? 'day' : 'days'} to go).';
      case TdNextAction.missingPrevious:
        return '${_tdStatus.blockingDoseKey} is missing. Backfill it in the Td module before $next.';
      case TdNextAction.complete:
        return 'All 5 doses complete. No further Td needed.';
    }
  }

  /// The proposed next visit, from [PrenatalScheduleEngine].
  ///
  /// The interval rules used to live in this method. They were correct, but
  /// unreachable by a test and uncitable, and gestational diabetes screening
  /// needs the same arithmetic. They now live in the engine; this stays as the
  /// screen's way of asking, and the proposed date still lands in an editable
  /// field the midwife confirms or overrides.
  PrenatalScheduleProposal _scheduleProposal() {
    return PrenatalScheduleEngine.propose(
      lastVisit: _normalizedDate(_checkupDateTime),
      gestationalWeeks: _aogWeeks,
      isHighRisk: _pregnancyRiskLevel.toLowerCase() == 'high',
      expectedDateOfDelivery: _effectiveEdd(),
    );
  }

  DateTime _calculateRecommendedNextSchedule() => _scheduleProposal().date;

  String _scheduleRecommendationReason() => _scheduleProposal().reason;

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

  double? get _aogWeeks {
    final lmp = _effectiveLmp();
    if (lmp == null) return null;
    final days = _normalizedDate(_checkupDateTime)
        .difference(_normalizedDate(lmp))
        .inDays;
    if (days < 0) return null;
    return (days / 7).floorToDouble();
  }

  BpCategory get _bpCategory {
    final sys = int.tryParse(_sysCtrl.text.trim());
    final dia = int.tryParse(_diaCtrl.text.trim());
    return BloodPressureReference.categorise(sys, dia);
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

  Widget _sectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildClickableSummarySection(
    String title,
    List<Widget> rows, {
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.brandPrimary.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: AppColors.brandPrimary),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Color(0xFF5A5A5A),
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: AppColors.brandPrimary,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: AppColors.borderPrimary.withValues(alpha: 0.6),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    Color? valueColor,
    IconData? icon,
    Widget? badge,
    bool fullText = false,
  }) {
    final textColor = valueColor ?? const Color(0xFF5A5A5A);

    if (fullText) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  badge,
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                badge,
              ],
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bpStatusPill() {
    final cat = _bpCategory;
    if (cat == BpCategory.unreadable) return const SizedBox.shrink();

    final String pillLabel;
    final Color pillColor;

    if (cat == BpCategory.normal) {
      pillLabel = 'STANDARD';
      pillColor = AppColors.success;
    } else if (cat == BpCategory.low) {
      pillLabel = 'LOW';
      pillColor = const Color(0xFF3B82F6);
    } else if (cat == BpCategory.severe) {
      pillLabel = 'CRITICAL';
      pillColor = const Color(0xFFB71C1C);
    } else {
      pillLabel = 'RAISED';
      pillColor = AppColors.warning;
    }

    final isLow = cat == BpCategory.low;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLow ? const Color(0xFFEFF6FF) : pillColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLow ? const Color(0xFFBFDBFE) : pillColor.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        pillLabel,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: pillColor,
        ),
      ),
    );
  }

  // _riskSegmentOption removed — the control now lives in
  // widgets/pregnancy_risk_override.dart, shared with the ultrasound and lab
  // screens so the three cannot drift apart.


  /// Centralized baseline weight resolution for weight gain analysis.
  /// All weight gain evaluate() calls in this screen MUST use this method
  /// to ensure consistent baseline across status pill, insight card,
  /// AI prompt, risk factors, and persist.
  double? _resolveBaselineWeight() {
    final motherMap = _motherRiskContext?['mother'] as Map<String, dynamic>?;
    final pregnancyMap = _motherRiskContext?['pregnancy'] as Map<String, dynamic>?;
    final previousCheckups =
        (_motherRiskContext?['previous_checkups'] as List? ?? const [])
            .cast<dynamic>();

    final heightCm = motherMap?['height'] != null
        ? double.tryParse(motherMap!['height'].toString())
        : null;
    final prePregnancyWeight = pregnancyMap?['pre_pregnancy_weight'] != null
        ? double.tryParse(pregnancyMap!['pre_pregnancy_weight'].toString())
        : null;
    final motherWeight = motherMap?['weight'] != null
        ? double.tryParse(motherMap!['weight'].toString())
        : null;

    // Priority 1: DB pre_pregnancy_weight
    if (prePregnancyWeight != null) return prePregnancyWeight;

    // Priority 2: Backtrack using earliest checkup weight if height available
    if (heightCm != null && heightCm > 0) {
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
      final referenceWeight = motherWeight ?? widget.motherWeight ?? earliestCheckupWeight;
      if (referenceWeight != null) {
        final est = WeightGainEngine.estimatePrePregnancyBMI(
          currentWeightKg: referenceWeight,
          heightCm: heightCm,
          aogWeeks: (_aogWeeks ?? 0).toInt(),
          fetalCount: _fetalCount ?? 1,
        );
        final estimated = (est['estimatedWeight'] as num?)?.toDouble();
        if (estimated != null) return estimated;
      }
    }

    // Priority 3: mothers.weight (registration weight)
    if (motherWeight != null) return motherWeight;

    // Priority 4: widget.motherWeight
    if (widget.motherWeight != null) return widget.motherWeight;

    // Priority 5: Earliest checkup weight (no backtracking possible)
    if (previousCheckups.isNotEmpty) {
      final sortedPrev = List<Map<String, dynamic>>.from(
          previousCheckups.map((e) => Map<String, dynamic>.from(e as Map)));
      sortedPrev.sort((a, b) {
        final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '');
        final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '');
        if (da == null || db == null) return 0;
        return da.compareTo(db);
      });
      final earliest = double.tryParse(
          sortedPrev.first['checkup_weight']?.toString() ?? '');
      if (earliest != null) return earliest;
    }

    // Priority 6: Session fallback (current weight as last resort)
    final currentWeight = double.tryParse(_weightCtrl.text.trim());
    if (currentWeight != null) {
      _initialSessionWeight ??= currentWeight;
      return _initialSessionWeight;
    }

    return null;
  }

  /// Builds a sorted checkup list including the current checkup being entered.
  /// Used by evaluate() calls that need checkup history for flag detection.
  List<Map<String, dynamic>> _buildCurrentCheckupList() {
    final previousCheckups =
        (_motherRiskContext?['previous_checkups'] as List? ?? const [])
            .cast<dynamic>();
    final currentWeight = double.tryParse(_weightCtrl.text.trim());

    final checkupList = previousCheckups
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (currentWeight != null && _aogWeeks != null) {
      checkupList.add({
        'checkup_datetime': _checkupDateTime.toIso8601String(),
        'age_of_gestation': _aogWeeks,
        'checkup_weight': currentWeight,
      });
    }

    checkupList.sort((a, b) {
      final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '');
      final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '');
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

    return checkupList;
  }

  Widget _weightGainStatusPill() {
    final currentWeight = double.tryParse(_weightCtrl.text.trim());
    if (currentWeight == null || _aogWeeks == null || _aogWeeks! <= 0) {
      return const SizedBox.shrink();
    }

    final motherMap = _motherRiskContext?['mother'] as Map<String, dynamic>?;
    final heightCm = motherMap?['height'] != null
        ? double.tryParse(motherMap!['height'].toString())
        : null;

    final effectivePrePreg = _resolveBaselineWeight();
    final checkupList = _buildCurrentCheckupList();

    final result = WeightGainEngine.evaluate(
      currentWeight: currentWeight,
      aogWeeks: _aogWeeks!,
      allCheckups: checkupList,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pillColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        pillLabel,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
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

    if (sys == null || dia == null) {
      return const SizedBox.shrink();
    }

    final category = BloodPressureReference.categorise(sys, dia);
    if (category == BpCategory.unreadable) {
      return const SizedBox.shrink();
    }

    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (category) {
      case BpCategory.severe:
        statusText = 'Severely elevated (≥160/110 mmHg) — Immediate Referral Required';
        statusColor = const Color(0xFFB71C1C);
        statusIcon = Icons.error_rounded;
        break;
      case BpCategory.raised:
        statusText = 'Raised blood pressure (≥140/90 mmHg) — Repeat and monitor';
        statusColor = AppColors.error;
        statusIcon = Icons.warning_rounded;
        break;
      case BpCategory.low:
        statusText = 'Below standard range (<90/60 mmHg)';
        statusColor = Colors.blue.shade700;
        statusIcon = Icons.arrow_downward_rounded;
        break;
      case BpCategory.normal:
        statusText = 'Within standard range';
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle_rounded;
        break;
      case BpCategory.unreadable:
        return const SizedBox.shrink();
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
            date.weekday == DateTime.sunday) {
          return false;
        }
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

  /// True when this visit hands something over that stock must answer for:
  /// tablets, a Td dose given here, or both. When nothing is dispensed there is
  /// no deduction to attempt and no stock outcome worth reporting.
  bool _hasDispensableItems() {
    final ferrous = int.tryParse(_ferrousQtyCtrl.text.trim()) ?? 0;
    final calcium = int.tryParse(_calciumQtyCtrl.text.trim()) ?? 0;
    final tdHere = _tdGivenOnSite &&
        _tdDose != null &&
        _tdDose!.trim().isNotEmpty &&
        _tdDose!.trim() != '-';
    return ferrous > 0 || calcium > 0 || tdHere;
  }

  Future<void> _insertSupplementRecords(int encounterId) async {
    final client = Supabase.instance.client;
    final checkupDate = _normalizedDate(_checkupDateTime);

    final givenRows = <Map<String, dynamic>>[];

    final ferrousQty = int.tryParse(_ferrousQtyCtrl.text.trim());
    if (ferrousQty != null && ferrousQty > 0) {
      givenRows.add({
        'encounter_id': encounterId,
        'mother_id': widget.motherId,
        'facility_id': _midwifeBhcId,
        'given_medication_name': 'Ferrous + FA',
        'quantity': ferrousQty,
        'date_given': checkupDate.toIso8601String().split('T')[0],
      });
    }

    final calciumQty = int.tryParse(_calciumQtyCtrl.text.trim());
    if (calciumQty != null && calciumQty > 0) {
      givenRows.add({
        'encounter_id': encounterId,
        'mother_id': widget.motherId,
        'facility_id': _midwifeBhcId,
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

    // Original AI output, kept for the audit trail.
    final originalAiText = _aiOriginalRemarks ?? '';

    // What the midwife actually submitted.
    final finalAiText = hasAiRemarks ? _aiRemarks : remarksText;

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
        final rawCheckup = enc['checkup'];
        Map<String, dynamic>? checkupData;
        if (rawCheckup is List) {
          if (rawCheckup.isNotEmpty) {
            checkupData = rawCheckup.first as Map<String, dynamic>?;
          }
        } else if (rawCheckup is Map) {
          checkupData = Map<String, dynamic>.from(rawCheckup);
        }
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
            // Recorded beside the text it describes, so a record can say
            // whether the midwife wrote these words, approved an AI draft of
            // them, or corrected one. It was previously kept only inside an
            // audit_trail JSON blob, where nothing could read it back and the
            // record view had to label every summary identically.
            'remarks_source': _remarksCtrl.text.trim().isEmpty ? null : _remarksSource,
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

      await _insertSupplementRecords(encounterId);

      // Atomic inventory deduction for supplements and maternal Td vaccine.
      //
      // A throw here used to end in debugPrint, and a `mode: no_deduction` reply
      // was never read at all, so the midwife saw "Prenatal checkup saved" while
      // the tablets they had just handed over stayed on the books. Whatever the
      // database answers is now carried to the confirmation dialog verbatim.
      final dispensedSomething = _hasDispensableItems();
      StockDeductionOutcome? stockOutcome;

      if (!dispensedSomething) {
        stockOutcome = null; // Nothing was handed over; there is nothing to say.
      } else if (_midwifeBhcId == null) {
        stockOutcome = StockDeductionOutcome.fromPrenatalEncounter(
          null,
          facilityKnown: false,
        );
      } else {
        try {
          final shouldDeductTd = _tdGivenOnSite &&
              _tdDose != null &&
              _tdDose!.trim().isNotEmpty &&
              _tdDose!.trim() != '-';

          final invResult = await Supabase.instance.client.rpc(
            'deduct_prenatal_encounter_inventory',
            params: {
              'p_encounter_id': encounterId,
              'p_facility_id': _midwifeBhcId,
              'p_performed_by': _accountId ?? _midwifeId,
              'p_deduct_td': shouldDeductTd,
            },
          );

          stockOutcome = StockDeductionOutcome.fromPrenatalEncounter(invResult);
        } catch (invErr) {
          debugPrint('Prenatal inventory deduction failed: $invErr');
          stockOutcome = StockDeductionOutcome.fromPrenatalEncounter({
            'success': false,
            'error': invErr.toString().replaceAll('Exception: ', ''),
          });
        }
      }

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

      // Nothing dispensed: the old snackbar is still the right weight for it.
      // Anything else gets a dialog, because a stock shortfall the midwife has
      // to act on must not scroll away on its own.
      if (stockOutcome == null) {
        _showMessage('Prenatal checkup saved.', type: AppSnackType.success);
        Navigator.pop(context, true);
        return;
      }

      // Bound to a final local: the closure below cannot see the promotion on
      // a variable the branches above assign to.
      final outcome = stockOutcome;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StockOutcomeDialog(
          title: outcome.isProblem
              ? 'Checkup Saved — Check Stock'
              : 'Prenatal Checkup Saved',
          message: 'The checkup record was saved successfully.',
          outcome: outcome,
          onPressed: () => Navigator.pop(context),
        ),
      );

      if (!mounted) return;
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
              const Text(
                'VISIT DATE & TIME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.calendar_today_rounded,
                      color: AppColors.brandPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            DateFormat('MMMM d, yyyy').format(_checkupDateTime),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.brandText,
                            ),
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('h:mm a').format(_checkupDateTime),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_aogWeeks != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                            size: 15,
                            color: AppColors.brandPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Week ${_aogWeeks!.toInt()}',
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
          child: _motherRiskContext == null
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
    final rawMotherH = mother?['height'];
    final heightCm = heightCmVal ??
        (rawMotherH != null ? double.tryParse(rawMotherH.toString()) : null);

    try {
      final effectivePrePreg = _resolveBaselineWeight();
      final checkupList = _buildCurrentCheckupList();

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

      // Use centralized engine method for expected gain range
      final gainRange = WeightGainEngine.getExpectedGainAt(
        aogWeeks: _aogWeeks!,
        bmiCategory: result.bmiCategory,
        fetalCount: _fetalCount ?? 1,
      );
      final expectedGainMin = gainRange['min']!;
      final expectedGainMax = gainRange['max']!;

      final baselineW = result.baselineWeight ?? effectivePrePreg ?? currentWeight;
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
                    'Standard baseline: ${FhrThresholds.standard.minBpm}–${FhrThresholds.standard.maxBpm} bpm',
                    style: TextStyle(
                      fontSize: 12,
                      color: () {
                        final v = int.tryParse(_fetalBeatCtrl.text.trim());
                        if (v == null) return AppColors.textSecondary;
                        final assessment = FetalHeartRateReference.assess(v);
                        if (!assessment.isOutsideBaseline) return AppColors.success;
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: AppColors.brandPrimary, size: 18),
                    onPressed: onEdit,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                if (onEdit != null) const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.error, size: 18),
                  onPressed: onDelete,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
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
          trailing: _symptoms.isNotEmpty
              ? GestureDetector(
                  onTap: _confirmClearAllSymptoms,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.clear_all, size: 16, color: AppColors.error),
                      SizedBox(width: 4),
                      Text(
                        'Clear all',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

    // The pills are the catalogue, not a second list of their own.
    //
    // They used to be eleven hardcoded names, and six of them existed nowhere
    // in `symptom_types`: "Backache" against the catalogue's "Back Pain",
    // "Nausea / Morning Sickness" against "Nausea", "Decreased Fetal Movement"
    // against "Reduced Fetal Movement", and so on.
    //
    // Tapping one of those six did nothing useful. `selectedType` is only
    // assigned when `indexWhere` finds a match, so an unmatched tap left it
    // holding the *previous* selection — and the dialog reads its title from
    // `selectedType`, not from the pill. That is why tapping one chip showed
    // "Severe Itching": the name on screen was whatever had been chosen
    // before, not what was pressed.
    //
    // Saving it was worse. `_resolveSymptomTypeId` looks the name up in the
    // catalogue, fails, and falls through to the "Other" row — so a symptom
    // the midwife had deliberately named was filed as Other, with the real
    // name surviving only inside the free-text note.
    //
    // Building the chips from `_symptomTypes` makes both impossible: every
    // chip carries a real id, so every tap matches by construction and the
    // two lists cannot drift apart again. "Other" is left out — it is the
    // fallback, not something to offer as a one-tap choice — and stays
    // available in the dropdown below.
    final List<SymptomType> commonSymptoms = _symptomTypes
        .where((st) => !st.name.toLowerCase().contains('other'))
        .toList();

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              editIndex != null ? 'Edit Symptom' : 'Add Symptom',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.brandText,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ),
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
                                final name = sym.name;
                                final risk = sym.riskCategory;
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
                                    // The chip is a catalogue row, so this
                                    // assigns directly. No lookup, nothing to
                                    // fail, no path that leaves the previous
                                    // selection in place.
                                    setDialogState(() {
                                      selectedType = sym;
                                      customNameCtrl.text = sym.name;
                                      selectedRisk = sym.riskCategory;
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
                                  setDialogState(() {
                                    selectedType = st;
                                    customNameCtrl.text = st.name;
                                    selectedRisk = st.riskCategory;
                                  });
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
                                setDialogState(() => selectedRisk = val);
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
    final ferrousEntered = int.tryParse(_ferrousQtyCtrl.text.trim()) ?? 0;
    final calciumEntered = int.tryParse(_calciumQtyCtrl.text.trim()) ?? 0;
    final ferrousExceeds = _midwifeBhcId != null && _ferrousStockAvailable > 0 && ferrousEntered > _ferrousStockAvailable;
    final calciumExceeds = _midwifeBhcId != null && _calciumStockAvailable > 0 && calciumEntered > _calciumStockAvailable;

    final highestTd = _tdStatus.highestCompletedDose;
    final isProtectedAtBirth = _tdStatus.isProtectedAtBirth;
    final isFim = _tdStatus.isFim;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Supplements Section ──────────────────────────────────────────
        _sectionCard(
          title: 'Maternal Micronutrient Supplements',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // (A) Ferrous Sulfate + Folic Acid
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ferrousExceeds ? AppColors.error : AppColors.borderPrimary.withValues(alpha: 0.6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.medication_rounded, size: 16, color: Color(0xFFDC2626)),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Ferrous Sulfate + Folic Acid',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (_midwifeBhcId != null)
                          StockLevelChip.count(
                            available: _ferrousStockAvailable,
                            unit: 'tablets',
                            lowThreshold: 30,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AppInputField(
                      hintText: 'Enter tablets to dispense (e.g. 30)',
                      controller: _ferrousQtyCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      errorText: _ferrousError,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    // Quick Presets
                    Row(
                      children: [
                        _buildPresetChip('+30', () {
                          setState(() => _ferrousQtyCtrl.text = '30');
                        }),
                        const SizedBox(width: 6),
                        _buildPresetChip('+60', () {
                          setState(() => _ferrousQtyCtrl.text = '60');
                        }),
                        const SizedBox(width: 6),
                        _buildPresetChip('+90', () {
                          setState(() => _ferrousQtyCtrl.text = '90');
                        }),
                        const Spacer(),
                        if (_ferrousQtyCtrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _ferrousQtyCtrl.clear()),
                            child: Text(
                              'Clear',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                            ),
                          ),
                      ],
                    ),
                    if (ferrousExceeds)
                      StockStatusCard(
                        margin: const EdgeInsets.only(top: 8),
                        tone: StockTone.caution,
                        message: 'Only $_ferrousStockAvailable tablet(s) are in stock here. '
                            'The record will show what you hand over; the shortfall '
                            'needs reconciling with your RHU.',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // (B) Calcium Carbonate
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: calciumExceeds ? AppColors.error : AppColors.borderPrimary.withValues(alpha: 0.6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.healing_rounded, size: 16, color: Color(0xFF2563EB)),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Calcium Carbonate (500mg)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (_midwifeBhcId != null)
                          StockLevelChip.count(
                            available: _calciumStockAvailable,
                            unit: 'tablets',
                            lowThreshold: 30,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AppInputField(
                      hintText: 'Enter tablets to dispense (e.g. 30)',
                      controller: _calciumQtyCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      errorText: _calciumError,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    // Quick Presets
                    Row(
                      children: [
                        _buildPresetChip('+30', () {
                          setState(() => _calciumQtyCtrl.text = '30');
                        }),
                        const SizedBox(width: 6),
                        _buildPresetChip('+60', () {
                          setState(() => _calciumQtyCtrl.text = '60');
                        }),
                        const SizedBox(width: 6),
                        _buildPresetChip('+90', () {
                          setState(() => _calciumQtyCtrl.text = '90');
                        }),
                        const Spacer(),
                        if (_calciumQtyCtrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _calciumQtyCtrl.clear()),
                            child: Text(
                              'Clear',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                            ),
                          ),
                      ],
                    ),
                    if (calciumExceeds)
                      StockStatusCard(
                        margin: const EdgeInsets.only(top: 8),
                        tone: StockTone.caution,
                        message: 'Only $_calciumStockAvailable tablet(s) are in stock here. '
                            'The record will show what you hand over; the shortfall '
                            'needs reconciling with your RHU.',
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── 2. Maternal Td Immunization Status Card ──────────────────────────
        _sectionCard(
          title: 'Maternal Td Immunization Status',
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.borderPrimary.withValues(alpha: 0.8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.brandPrimary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.vaccines_rounded,
                        size: 18,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isFim
                            ? 'Fully Immunized Mother (FIM ⭐)'
                            : (highestTd > 0 ? 'Td$highestTd Recorded' : 'No Td Recorded'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brandText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isFim || isProtectedAtBirth
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isFim || isProtectedAtBirth
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Text(
                        isFim ? 'LIFETIME' : (isProtectedAtBirth ? 'PAB PROTECTED' : 'UNPROTECTED'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isFim || isProtectedAtBirth
                              ? const Color(0xFF166534)
                              : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isFim
                      ? 'Lifetime maternal and neonatal tetanus protection achieved.'
                      : (isProtectedAtBirth
                          ? 'Baby is Protected at Birth (PAB). Manage or backfill remaining doses in the dedicated Td module.'
                          : 'DOH recommends starting or updating Td doses as early as possible in pregnancy.'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),

                // Next-dose timing, mirroring the Td screen so the two views
                // never tell the midwife different things.
                if (!isFim) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.borderPrimary.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _tdStatus.canAdministerToday
                              ? Icons.event_available_rounded
                              : Icons.schedule_rounded,
                          size: 15,
                          color: _tdStatus.canAdministerToday
                              ? AppColors.brandPrimary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _prenatalTdTimingLabel(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _tdStatus.canAdministerToday
                                  ? AppColors.brandPrimary
                                  : AppColors.brandText,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                _buildTdStockCard(),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.vaccines_rounded, size: 16),
                    label: const Text(
                      'Manage Td Vaccine Records & Doses',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MaternalTdScreen(
                            motherId: widget.motherId,
                            assignedBhcId: _midwifeBhcId,
                          ),
                        ),
                      );
                      // Refresh maternal Td state
                      _loadTakenTdDoses();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Td stock at this health center, shown only when it bears on this visit.
  ///
  /// `_loadFacilityInventory` has always worked this out — open vial, its age,
  /// sealed vials, the next batch — and then nothing rendered any of it. A
  /// midwife could pick Td2 on a shelf that held none and find out only after
  /// saving. It stays hidden when no dose is due and none is selected, so the
  /// card does not add a line to every routine visit.
  Widget _buildTdStockCard() {
    final doseSelected = _tdDose != null &&
        _tdDose!.trim().isNotEmpty &&
        _tdDose!.trim() != '-';
    if (!doseSelected && !_tdStatus.canAdministerToday) {
      return const SizedBox.shrink();
    }

    const margin = EdgeInsets.only(top: 8);

    if (_midwifeBhcId == null) {
      return const StockStatusCard(
        margin: margin,
        tone: StockTone.blocked,
        message: 'Your account is not assigned to a health center, so a Td dose '
            'given here cannot be deducted from stock.',
      );
    }

    if (_tdStockAvailable <= 0) {
      return const StockStatusCard(
        margin: margin,
        tone: StockTone.blocked,
        message: 'No Td doses in stock at this health center.',
      );
    }

    final sealedLabel = _tdSealedVials > 0 ? '+$_tdSealedVials sealed' : null;

    // An open vial is drawn from first, so it is the fact that matters.
    if (_tdOpenVialDoses > 0) {
      final opened = _tdOpenVialOpenedAt;
      final hoursOpen = opened == null
          ? null
          : DateTime.now().difference(opened).inHours;
      final nearingLimit = hoursOpen != null && hoursOpen >= 600; // of 672h

      return StockStatusCard(
        margin: margin,
        tone: nearingLimit ? StockTone.caution : StockTone.ready,
        icon: Icons.colorize_rounded,
        trailing: sealedLabel,
        message: nearingLimit
            ? 'Open Td vial has $_tdOpenVialDoses dose(s) left and is near its '
                '28-day limit — use it first.'
            : 'Open Td vial: $_tdOpenVialDoses dose(s) left'
                '${_tdOpenVialBatch != null ? ' (Batch #$_tdOpenVialBatch)' : ''}.',
      );
    }

    return StockStatusCard(
      margin: margin,
      trailing: sealedLabel,
      message: '$_tdStockAvailable Td dose(s) available. A sealed vial'
          '${_tdNextBatch != null ? ' from Batch #$_tdNextBatch' : ''} will be '
          'opened for this dose.',
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
        ),
      ),
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

      // The prompt asks for Tagalog only. If the model answered in English
      // anyway, fall back to the rule-based Tagalog text, which carries the
      // same numbers.
      final extracted = _extractTagalogText(aiText);
      final tagalogText = extracted.isNotEmpty
          ? extracted
          : _buildRuleBasedAssessmentTextFilipino(draft);

      setState(() {
        _aiRemarks = tagalogText;
        _aiOriginalRemarks = tagalogText;
        _aiRemarksModel = extracted.isNotEmpty ? 'Groq' : 'Rule Engine';
        _remarksSource = 'ai_generated_approved';
        _remarksCtrl.text = tagalogText;
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
      final fil = _buildRuleBasedAssessmentTextFilipino(draft);
      setState(() {
        _aiRemarks = fil;
        _aiOriginalRemarks = fil;
        _aiRemarksModel = 'Rule Engine';
        _remarksSource = 'ai_generated_approved';
        _remarksCtrl.text = fil;
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
        _aiRemarks = '';
        _aiOriginalRemarks = null;
      });
      return;
    }

    if (_remarksSource != 'midwife_authored') {
      setState(() => _remarksSource = 'ai_generated_edited');
      // The midwife's edits are the summary from here on; the original AI text
      // stays in _aiOriginalRemarks for the audit trail.
      _aiRemarks = _remarksCtrl.text;
    }
  }

  Widget _buildStep4() {
    _nextSchedule ??= _calculateRecommendedNextSchedule();
    final bool hasAiRemarks = _remarksSource != 'midwife_authored';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          title: 'Next Visit',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: _pickNextSchedule,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.borderPrimary,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: AppColors.brandAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _nextSchedule == null
                            ? const Text(
                                'Recommended next visit (optional)',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Recommended next visit',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('MMMM d, yyyy (EEEE)').format(_nextSchedule!),
                                    style: const TextStyle(
                                      color: AppColors.inputText,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                      ),
                      if (_nextSchedule != null)
                        GestureDetector(
                          onTap: () => setState(() => _nextSchedule = null),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded, size: 20, color: AppColors.brandAccent),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
                    // One summary, in Tagalog. The mother reads this exact
                    // text in her record, so there is nothing to switch.
                    Text(
                      'Tagalog',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary.withValues(alpha: 0.9),
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


  List<String> _getDetectedRiskFactors() {
    final factors = <String>[];

    final sys = int.tryParse(_sysCtrl.text.trim());
    final dia = int.tryParse(_diaCtrl.text.trim());
    if (sys != null && dia != null) {
      final bpCat = BloodPressureReference.categorise(sys, dia);
      switch (bpCat) {
        case BpCategory.severe:
          factors.add('Severely elevated blood pressure (≥160/110 mmHg)');
          break;
        case BpCategory.raised:
          factors.add('Raised blood pressure (≥140/90 mmHg)');
          break;
        case BpCategory.low:
          factors.add('Below standard blood pressure (<90/60 mmHg)');
          break;
        case BpCategory.normal:
        case BpCategory.unreadable:
          break;
      }
    }

    final currentWeight = double.tryParse(_weightCtrl.text.trim());
    if (currentWeight != null && _aogWeeks != null) {
      try {
        final motherData = _motherRiskContext?['mother'] as Map<String, dynamic>?;
        final heightCm = motherData?['height'] != null
            ? double.tryParse(motherData!['height'].toString())
            : null;

        final effectivePrePreg = _resolveBaselineWeight();
        final checkupList = _buildCurrentCheckupList();

        final result = WeightGainEngine.evaluate(
          currentWeight: currentWeight,
          aogWeeks: _aogWeeks!,
          allCheckups: checkupList,
          prePregnancyWeight: effectivePrePreg,
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
            // Shared with the ultrasound and lab screens — see
            // widgets/pregnancy_risk_override.dart. Risk belongs to the
            // pregnancy, so the control that sets it is the same wherever a
            // midwife reaches for it.
            PregnancyRiskOverride(
              value: _pregnancyRiskLevel,
              onChanged: (level) => setState(() {
                _pregnancyRiskLevel = level;
                // Only this screen reschedules: the next visit interval
                // depends on risk, and the other two do not set a visit.
                _nextSchedule = _calculateRecommendedNextSchedule();
              }),
            ),
            const SizedBox(height: 10),
            if (detectedFactors.isEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'Detected Factors',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    'None',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5A5A5A),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Detected Factors',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: detectedFactors.map((factor) {
                      final isHigh = factor.toLowerCase().contains('severe') ||
                          factor.toLowerCase().contains('hypertension') ||
                          factor.toLowerCase().contains('urgent');
                      final chipColor = isHigh ? AppColors.error : AppColors.warning;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: chipColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
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
                            Flexible(
                              child: Text(
                                factor,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: chipColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
          ],
          icon: Icons.shield_outlined,
          onTap: () {},
        ),
        const SizedBox(height: 12),
        _buildClickableSummarySection(
          'VITALS',
          [
            _summaryRow('Midwife', _midwifeName ?? 'Loading...'),
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
          icon: Icons.monitor_heart_outlined,
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
          icon: Icons.child_care_rounded,
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
          icon: Icons.healing_outlined,
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
                  (_tdStatus.isFim
                      ? 'Complete (all doses given)'
                      : 'None given today'),
            ),
          ],
          icon: Icons.medication_outlined,
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
              fullText: true,
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
          icon: Icons.event_note_outlined,
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
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _submitting ? null : _back,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.brandPrimary,
                          side: const BorderSide(color: AppColors.brandPrimary, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
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
