// lib/screens/midwife/midwife_add_mother_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/ocr_result.dart';
import '../../services/auth_storage.dart';
import '../../services/groq_service.dart';
import '../../services/supabase_service.dart';
import '../../services/ph_address_service.dart' as ph_addr;
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/dialog_box.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/main_button.dart';
import 'add_prenatal_checkup_screen.dart';

enum _GestationMethod { lmp, edd, aog }

enum _OcrDialogState { loading, results, error }

const List<String> _extensionOptions = [
  '',
  'Jr.',
  'Sr.',
  'II',
  'III',
  'IV',
  'V'
];
const List<String> _bloodTypeOptions = [
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
  'Unknown'
];
const List<String> _relationshipOptions = [
  'Spouse/Partner',
  'Parent',
  'Child',
  'Sibling',
  'Relative',
  'Friend',
  'Neighbor',
  'Coworker',
  'Other',
];
const List<String> _commonConditions = [
  'Anemia',
  'Diabetes',
  'Hypertension',
  'Asthma',
  'Thyroid Disorder',
  'Heart Disease',
  'Kidney Disease',
  'Epilepsy',
  'Hepatitis',
  'Other',
];
const List<String> _commonAllergens = [
  'Peanuts',
  'Penicillin',
  'Dust Mites',
  'Pollen',
  'Shellfish',
  'Pet Dander',
  'Fish',
  'Milk',
  'Eggs',
  'Soy',
  'Wheat',
  'Latex',
  'Insect Stings',
  'Mold',
  'Fragrances',
  'Nickel',
  'Other'
];

class _EmergencyContact {
  String firstName = '';
  String? middleName;
  String lastName = '';
  String? extensionName;
  String phoneNumber = '';
  String? relationship;

  bool get isValid =>
      firstName.isNotEmpty &&
      lastName.isNotEmpty &&
      phoneNumber.isNotEmpty &&
      relationship != null &&
      relationship!.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'extension_name': extensionName?.isEmpty == true ? null : extensionName,
        'phone_number': phoneNumber,
        'affiliation': relationship,
      };
}

class _MedicalCondition {
  final String conditionName;
  DateTime? diagnosisDate;
  String status = 'active';
  String? remarks;

  _MedicalCondition(this.conditionName);

  Map<String, dynamic> toMap() => {
        'condition_name': conditionName,
        'diagnosis_date': diagnosisDate?.toIso8601String().split('T')[0],
        'status': status,
        'remarks': remarks,
      };
}

class _Allergy {
  final String allergen;
  DateTime? diagnosisDate;
  String status = 'active';
  String? treatment;
  String? remarks;

  _Allergy(this.allergen);

  Map<String, dynamic> toMap() => {
        'allergen': allergen,
        'diagnosis_date': diagnosisDate?.toIso8601String().split('T')[0],
        'status': status,
        'treatment': treatment,
        'remarks': remarks,
      };
}

class _PastFetalOutcome {
  String outcome;
  DateTime outcomeDate;
  bool isEstimated = false;
  String? placeOfDelivery;
  String? deliveryMethod;
  double? gestationalAgeAtEnd;

  _PastFetalOutcome({required this.outcome, required this.outcomeDate});

  Map<String, dynamic> toMap() => {
        'outcome': outcome,
        'outcome_date': outcomeDate.toIso8601String().split('T')[0],
        'is_outcome_date_estimated': isEstimated,
        'place_of_delivery': placeOfDelivery,
        'delivery_method': deliveryMethod,
        'gestational_age_at_end': gestationalAgeAtEnd,
      };
}

class _PastPregnancy {
  int fetalCount = 1;
  double? gestationalAgeAtEnd;
  List<_PastFetalOutcome> outcomes = [];

  _PastPregnancy({String? outcome, DateTime? outcomeDate}) {
    if (outcome != null && outcomeDate != null) {
      outcomes = [
        _PastFetalOutcome(outcome: outcome, outcomeDate: outcomeDate)
      ];
    }
  }

  _PastFetalOutcome _ensurePrimaryOutcome() {
    if (outcomes.isEmpty) {
      outcomes.add(_PastFetalOutcome(
          outcome: 'live_birth', outcomeDate: DateTime.now()));
    }
    return outcomes.first;
  }

  _PastFetalOutcome _latestOutcomeRef() {
    final primary = _ensurePrimaryOutcome();
    if (outcomes.length == 1) return primary;
    return outcomes
        .reduce((a, b) => a.outcomeDate.isAfter(b.outcomeDate) ? a : b);
  }

  DateTime get earliestOutcomeDate => outcomes.isEmpty
      ? DateTime.now()
      : outcomes
          .map((o) => o.outcomeDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get latestOutcomeDate => outcomes.isEmpty
      ? DateTime.now()
      : outcomes
          .map((o) => o.outcomeDate)
          .reduce((a, b) => a.isAfter(b) ? a : b);
  String get primaryOutcome =>
      outcomes.isNotEmpty ? _latestOutcomeRef().outcome : 'live_birth';
  DateTime get primaryOutcomeDate => latestOutcomeDate;
  String get outcome => primaryOutcome;
  set outcome(String value) => _latestOutcomeRef().outcome = value;
  DateTime get outcomeDate => primaryOutcomeDate;
  set outcomeDate(DateTime value) => _latestOutcomeRef().outcomeDate = value;
  bool get isEstimated =>
      outcomes.isNotEmpty ? _latestOutcomeRef().isEstimated : false;
  set isEstimated(bool value) => _latestOutcomeRef().isEstimated = value;
  String? get placeOfDelivery =>
      outcomes.isNotEmpty ? _latestOutcomeRef().placeOfDelivery : null;
  set placeOfDelivery(String? value) =>
      _latestOutcomeRef().placeOfDelivery = value;
  String? get deliveryMethod =>
      outcomes.isNotEmpty ? _latestOutcomeRef().deliveryMethod : null;
  set deliveryMethod(String? value) =>
      _latestOutcomeRef().deliveryMethod = value;

  Map<String, dynamic> toMap() => {
        'fetal_count': fetalCount,
        'gestational_age_at_end': gestationalAgeAtEnd,
        'outcomes': outcomes.map((o) => o.toMap()).toList(),
      };
}

class MidwifeAddMotherScreen extends StatefulWidget {
  const MidwifeAddMotherScreen({super.key});

  @override
  State<MidwifeAddMotherScreen> createState() => _MidwifeAddMotherScreenState();
}

class _MidwifeAddMotherScreenState extends State<MidwifeAddMotherScreen> {
  // Context
  int? _midwifeId;
  int? _assignedBhcId;
  String _bhcName = '';
  bool _loadingContext = true;

  // Navigation
  int _step = 0;
  static const int _totalSteps = 9;
  bool _submitting = false;
  final PageController _pageController = PageController();
  final DateFormat _dateFmt = DateFormat('MMMM d, yyyy');

  // Step 0: Personal & Account
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _middleNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  String _selectedExtension = '';
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  DateTime? _birthdate;
  final TextEditingController _birthdateCtrl = TextEditingController();
  String? _birthdateError;
  String? _riskWarning;
  Color? _riskWarningColor;
  int? _calculatedAge;

  String? _phoneError;
  bool _phoneChecking = false;
  Timer? _phoneTimer;
  String? _emailError;
  bool _emailChecking = false;
  Timer? _emailTimer;
  String? _lastEmailChecked;
  bool _isEmailReadOnly = false;
  bool _isExistingSelfRegistered = false;
  String? _firstNameError;
  String? _lastNameError;

  // Auto-fill existing account
  int? _existingAccountId;
  int? _existingMotherId;
  bool _isUpdatingExisting = false;
  bool _checkingAccount = false;

  // Step 1: Address
  bool _addressSameAsBhc = true;
  final TextEditingController _houseCtrl = TextEditingController();
  final TextEditingController _streetCtrl = TextEditingController();
  final TextEditingController _barangayCtrl = TextEditingController();
  String? _selectedBarangay;
  final TextEditingController _cityCtrl = TextEditingController();
  final TextEditingController _provinceCtrl = TextEditingController();
  final ScrollController _streetSuggestionController = ScrollController();
  String? _houseError;
  String? _streetError;
  String? _barangayError;
  String? _cityError;
  String? _provinceError;

  // Cascading Address Selection State
  String? _activeAddressSearchField; // 'province', 'city', 'barangay', 'street'
  List<String> _apiProvinces = [];
  List<String> _apiCities = [];
  List<String> _apiBarangays = [];
  bool _loadingProvinces = false;
  bool _loadingCities = false;
  bool _loadingBarangays = false;

  static const List<String> _bhcBarangays = [
    'Sta Barbara',
    'Tarcan',
    'San Jose',
    'Tiaong',
    'Pinagbarilan'
  ];

  // Step 2: Emergency Contacts
  final List<_EmergencyContact> _emergencyContacts = [];

  // Step 3: Vitals
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _prePregnancyWeightCtrl = TextEditingController();
  bool _knowsPrePregnancyWeight = true;
  String? _bloodType;
  final TextEditingController _bloodTypeCtrl = TextEditingController();
  bool _showBloodTypeDropdown = false;
  bool _showExtensionDropdown = false;
  String? _heightError;
  String? _weightError;
  String? _heightWarning;
  String? _weightWarning;
  String? _prePregnancyWeightError;
  String? _prePregnancyWeightWarning;
  double? _calculatedBMI;
  String? _bmiClassification;
  String? _bmiWarning;

  // Step 4: Medical Conditions
  final List<_MedicalCondition> _medicalConditions = [];

  // Step 5: Allergies
  final List<_Allergy> _allergies = [];

  // Step 6: Pregnancy History
  bool _hasPastPregnancy = false;
  final List<_PastPregnancy> _pastPregnancies = [];

  // Step 7: Gestational Info
  _GestationMethod _gestationMethod = _GestationMethod.lmp;
  final TextEditingController _gestationMethodCtrl =
      TextEditingController(text: 'Last Menstrual Period (LMP)');
  bool _showGestationMethodDropdown = false;
  final TextEditingController _lmpCtrl = TextEditingController();
  final TextEditingController _eddCtrl = TextEditingController();
  final TextEditingController _aogWeeksCtrl = TextEditingController();
  final TextEditingController _aogDaysCtrl = TextEditingController();
  final TextEditingController _fetalCountCtrl =
      TextEditingController(text: '1');
  DateTime? _lmp;
  DateTime? _edd;
  String? _gestationError;
  String? _weeksError;
  String? _daysError;

  // OCR - Using GroqService
  final GroqService _groqService = GroqService();

  @override
  void initState() {
    super.initState();
    _loadContext();
    _loadProvinces();
    _phoneCtrl.addListener(_onPhoneChanged);
    _heightCtrl.addListener(_validateHeightWeight);
    _weightCtrl.addListener(_validateHeightWeight);
    _prePregnancyWeightCtrl.addListener(_validatePrePregnancyWeight);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailTimer?.cancel();
    _phoneTimer?.cancel();
    for (final c in [
      _firstNameCtrl,
      _middleNameCtrl,
      _lastNameCtrl,
      _phoneCtrl,
      _emailCtrl,
      _birthdateCtrl,
      _houseCtrl,
      _streetCtrl,
      _barangayCtrl,
      _cityCtrl,
      _provinceCtrl,
      _heightCtrl,
      _weightCtrl,
      _prePregnancyWeightCtrl,
      _lmpCtrl,
      _eddCtrl,
      _aogWeeksCtrl,
      _aogDaysCtrl,
      _fetalCountCtrl
    ]) {
      c.dispose();
    }
    _streetSuggestionController.dispose();
    super.dispose();
  }

  void _onPhoneChanged() {
    final normalized =
        _phoneCtrl.text.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    final valid = RegExp(r'^(\+?63|0)9\d{9}$').hasMatch(normalized);
    setState(() => _phoneError = _phoneCtrl.text.trim().isEmpty
        ? null
        : (valid ? null : 'Enter a valid PH number'));

    _phoneTimer?.cancel();
    if (valid && _existingAccountId == null) {
      _phoneTimer = Timer(const Duration(milliseconds: 600), () {
        _checkExistingAccountByPhone(normalized);
      });
    }
  }

  void _validateHeightWeight() {
    final height = double.tryParse(_heightCtrl.text.trim());
    final weight = double.tryParse(_weightCtrl.text.trim());

    if (height != null) {
      if (height < 50 || height > 250) {
        setState(() {
          _heightError = 'Must be 50-250 cm';
          _heightWarning = null;
        });
      } else {
        setState(() {
          _heightError = null;
          if (height < 120) {
            _heightWarning =
                'Entered maternal measurement is outside commonly expected maternal monitoring ranges. Please verify the information.';
          } else {
            _heightWarning = null;
          }
        });
      }
    } else {
      setState(() {
        _heightError =
            _heightCtrl.text.trim().isEmpty ? null : 'Enter a valid number';
        _heightWarning = null;
      });
    }

    if (weight != null) {
      if (weight < 10 || weight > 350) {
        setState(() {
          _weightError = 'Must be 10-350 kg';
          _weightWarning = null;
        });
      } else {
        setState(() {
          _weightError = null;
          if (weight < 35) {
            _weightWarning =
                'Entered maternal measurement is outside commonly expected maternal monitoring ranges. Please verify the information.';
          } else {
            _weightWarning = null;
          }
        });
      }
    } else {
      setState(() {
        _weightError =
            _weightCtrl.text.trim().isEmpty ? null : 'Enter a valid number';
        _weightWarning = null;
      });
    }

    _calculateBMI();
  }

  void _validatePrePregnancyWeight() {
    final ppw = double.tryParse(_prePregnancyWeightCtrl.text.trim());
    if (_prePregnancyWeightCtrl.text.trim().isEmpty) {
      setState(() {
        _prePregnancyWeightError = null;
        _prePregnancyWeightWarning = null;
      });
    } else if (ppw == null) {
      setState(() {
        _prePregnancyWeightError = 'Enter a valid number';
        _prePregnancyWeightWarning = null;
      });
    } else if (ppw < 10 || ppw > 350) {
      setState(() {
        _prePregnancyWeightError = 'Must be 10-350 kg';
        _prePregnancyWeightWarning = null;
      });
    } else if (ppw < 35) {
      setState(() {
        _prePregnancyWeightError = null;
        _prePregnancyWeightWarning =
            'Entered maternal measurement is outside commonly expected maternal monitoring ranges. Please verify the information.';
      });
    } else {
      setState(() {
        _prePregnancyWeightError = null;
        _prePregnancyWeightWarning = null;
      });
    }
    _calculateBMI();
  }

  void _calculateBMI() {
    if (!_knowsPrePregnancyWeight) {
      _calculatedBMI = null;
      _bmiClassification = null;
      _bmiWarning = null;
      _prePregnancyWeightWarning = null;
      setState(() {});
      return;
    }

    final height = double.tryParse(_heightCtrl.text.trim());
    final ppw = double.tryParse(_prePregnancyWeightCtrl.text.trim());

    if (height != null && ppw != null && height > 0) {
      final heightM = height / 100;
      final bmi = ppw / (heightM * heightM);
      _calculatedBMI = bmi;

      if (bmi < 18.5) {
        _bmiClassification = 'Underweight';
      } else if (bmi < 25) {
        _bmiClassification = 'Normal';
      } else if (bmi < 30) {
        _bmiClassification = 'Overweight';
      } else {
        _bmiClassification = 'Obese';
      }

      final weeks = int.tryParse(_aogWeeksCtrl.text.trim()) ?? 0;
      if (weeks <= 12) {
        _bmiWarning =
            'Recommended total weight gain for this week (Week $weeks) is 0.5 - 2.0 kg.';
      } else {
        final double minRate;
        final double maxRate;
        if (bmi < 18.5) {
          minRate = 0.44; // Underweight min
          maxRate = 0.58; // Underweight max
        } else if (bmi < 25) {
          minRate = 0.35; // Normal min
          maxRate = 0.50; // Normal max
        } else if (bmi < 30) {
          minRate = 0.23; // Overweight min
          maxRate = 0.33; // Overweight max
        } else {
          minRate = 0.17; // Obese min
          maxRate = 0.27; // Obese max
        }
        final minGain = 0.5 + (weeks - 12) * minRate;
        final maxGain = 2.0 + (weeks - 12) * maxRate;
        _bmiWarning =
            'Recommended total weight gain for this week (Week $weeks) is ${minGain.toStringAsFixed(1)} - ${maxGain.toStringAsFixed(1)} kg.';
      }
    } else {
      _calculatedBMI = null;
      _bmiClassification = null;
      _bmiWarning = null;
    }
    setState(() {});
  }

  void _validateBirthdate() {
    if (_birthdate == null) {
      setState(() => _birthdateError = null);
      return;
    }

    if (_birthdate!.isAfter(DateTime.now())) {
      setState(() => _birthdateError = 'Birthdate cannot be in the future');
      return;
    }

    final age =
        (DateTime.now().difference(_birthdate!).inDays / 365.25).floor();
    _calculatedAge = age;

    Color? warningColor;
    String? warningText;
    String? birthdateError;

    if (age < 5) {
      birthdateError =
          'Maternal age ($age years) is too young for registration.';
      warningText = null;
    } else if (age <= 14) {
      warningColor = AppColors.error;
      warningText =
          'Entered maternal age is outside typical reproductive ranges. Please verify the information.';
    } else if (age <= 19) {
      warningColor = AppColors.warning;
      warningText = 'High-Risk Adolescent Pregnancy.';
    } else if (age <= 34) {
      warningText = null;
    } else if (age <= 60) {
      warningColor = AppColors.warning;
      warningText = 'High-Risk Advanced Maternal Age Pregnancy.';
    } else {
      warningColor = AppColors.error;
      warningText =
          'Entered maternal age is outside supported maternal monitoring ranges. Please verify the information.';
    }

    if (age < 13) {
      _emailCtrl.clear();
      _emailError = null;
      _isEmailReadOnly = false;
      _emailChecking = false;
      _lastEmailChecked = null;
    }

    setState(() {
      _birthdateError = birthdateError;
      _riskWarning = warningText;
      _riskWarningColor = warningColor;
    });
  }

  String? _validatePregnancyInterval(DateTime newLmp) {
    const minGapDays = 42;
    for (final past in _pastPregnancies) {
      final gap = newLmp.difference(past.latestOutcomeDate).inDays;
      if (gap > 0 && gap < minGapDays) {
        return 'Pregnancy interval too short ($gap days). Minimum interval is $minGapDays days after previous pregnancy outcome.';
      }
    }
    return null;
  }

  // ── Official DOH/Annex P Risk Factors ──
  // Only factors in this list flip is_high_risk to true.
  List<String> _evaluatePregnancyRisk() {
    final factors = <String>[];

    // 1. Demographics — Adolescent pregnancy
    if (_calculatedAge != null && _calculatedAge! < 19) {
      factors.add('Maternal age below 19 years');
    }

    // 1. Demographics — Advanced maternal age (first pregnancy only per Annex P)
    if (_calculatedAge != null &&
        _calculatedAge! >= 35 &&
        _pastPregnancies.isEmpty) {
      factors.add('First pregnancy age ≥ 35 years');
    }

    // 2. Multiple gestation
    final fetalCount = int.tryParse(_fetalCountCtrl.text.trim()) ?? 1;
    if (fetalCount > 1) {
      factors.add('Multiple gestation');
    }

    // 3. Short interpregnancy interval
    if (_lmp != null && _pastPregnancies.isNotEmpty) {
      DateTime? mostRecentOutcome;
      for (final p in _pastPregnancies) {
        final latest = p.latestOutcomeDate;
        if (mostRecentOutcome == null || latest.isAfter(mostRecentOutcome)) {
          mostRecentOutcome = latest;
        }
      }
      if (mostRecentOutcome != null) {
        final gapDays = _lmp!.difference(mostRecentOutcome).inDays;
        if (gapDays > 0 && gapDays < 180) {
          factors.add('Short interpregnancy interval');
        }
      }
    }

    // 4. Obstetric History
    int miscarriages = 0;
    bool hasStillbirth = false;
    bool hasCs = false;

    for (final p in _pastPregnancies) {
      for (final outcome in p.outcomes) {
        final o = outcome.outcome.toLowerCase();
        if (o == 'miscarriage' || o == 'abortion') miscarriages++;
        if (o == 'stillbirth') hasStillbirth = true;

        final method = outcome.deliveryMethod?.toLowerCase() ?? '';
        if (method.contains('cesarean') || method == 'cs') hasCs = true;
      }
    }
    if (miscarriages >= 3) {
      factors.add('History of 3 or more miscarriages/abortions');
    }
    if (hasStillbirth) factors.add('History of stillbirth');
    if (hasCs) {
      factors.add('History of major obstetric surgery (Cesarean section)');
    }

    // 5. Medical Conditions — ACTIVE / ONGOING only
    final dohConditions = [
      'Hypertension',
      'Preeclampsia',
      'Eclampsia',
      'Heart disease',
      'Cardiovascular',
      'Diabetes',
      'Thyroid',
      'Asthma',
      'Epilepsy',
      'Renal',
      'Kidney',
      'Bleeding',
      'Clotting',
      'Hemophilia',
    ];
    for (final mc in _medicalConditions) {
      final st = mc.status.toLowerCase();
      if (st != 'active' && st != 'ongoing') continue;
      final name = mc.conditionName.toLowerCase();
      if (dohConditions.any((c) => name.contains(c.toLowerCase()))) {
        factors.add('Pre-Existing: ${mc.conditionName}');
      }
    }

    // 6. Morbid obesity (BMI >= 40, pre-pregnancy weight only)
    if (_heightCtrl.text.isNotEmpty &&
        _prePregnancyWeightCtrl.text.isNotEmpty) {
      final heightCm = double.tryParse(_heightCtrl.text) ?? 0;
      final weightKg = double.tryParse(_prePregnancyWeightCtrl.text) ?? 0;
      if (heightCm > 0 && weightKg > 0) {
        final heightM = heightCm / 100;
        final bmi = weightKg / (heightM * heightM);
        if (bmi >= 40) factors.add('Morbid obesity');
      }
    }

    return factors;
  }

  // ── Monitoring Insights (non-risk, informational only) ──
  // These do NOT flip is_high_risk and are not stored in risk_factors.
  List<String> _evaluateMonitoringInsights() {
    final insights = <String>[];

    // AMA with previous pregnancies — closer monitoring, not official risk
    if (_calculatedAge != null &&
        _calculatedAge! >= 35 &&
        _pastPregnancies.isNotEmpty) {
      insights
          .add('Maternal age ≥ 35 — closer prenatal monitoring recommended');
    }

    // Elevated BMI (30–39.9) or underweight — monitoring only
    if (_heightCtrl.text.isNotEmpty &&
        _prePregnancyWeightCtrl.text.isNotEmpty) {
      final heightCm = double.tryParse(_heightCtrl.text) ?? 0;
      final weightKg = double.tryParse(_prePregnancyWeightCtrl.text) ?? 0;
      if (heightCm > 0 && weightKg > 0) {
        final heightM = heightCm / 100;
        final bmi = weightKg / (heightM * heightM);
        if (bmi >= 30 && bmi < 40) {
          insights.add(
              'Elevated pre-pregnancy BMI — weight monitoring recommended');
        }
        if (bmi < 18.5) {
          insights.add(
              'Low pre-pregnancy BMI — nutritional monitoring recommended');
        }
      }
    }

    return insights;
  }

  String? _validateLmp(DateTime lmp) {
    final now = DateTime.now();
    final twoWeeksAgo = now.subtract(const Duration(days: 2 * 7));
    if (lmp.isAfter(twoWeeksAgo)) {
      return 'LMP must be at least 2 weeks ago.';
    }
    final daysSinceLmp = now.difference(lmp).inDays;
    if (daysSinceLmp > 42 * 7) {
      return 'LMP is more than 42 weeks ago. Please verify the date.';
    }
    return _validatePregnancyInterval(lmp);
  }

  String? _validateEdd(DateTime edd) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eddDate = DateTime(edd.year, edd.month, edd.day);
    if (eddDate.isBefore(today)) {
      return 'EDD cannot be in the past.';
    }
    final maxEdd = today.add(const Duration(days: 43 * 7));
    if (eddDate.isAfter(maxEdd)) {
      return 'EDD cannot be more than 43 weeks from today.';
    }
    return null;
  }

  void _showEarlyPregnancyWarning() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Early Pregnancy Notice',
        subtitle: 'The LMP is less than 4 weeks ago. At this early stage, '
            'pregnancy confirmation via serum hCG test is recommended '
            'before proceeding with registration.',
        confirmText: 'Understood',
        cancelText: 'Cancel',
        onConfirm: () => Navigator.pop(context),
        onCancel: () => Navigator.pop(context),
        accentColor: AppColors.brandPrimary,
      ),
    );
  }

  Future<DateTime?> _showBrandedDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    DateTime clampedInitial = initialDate;
    if (clampedInitial.isBefore(firstDate)) {
      clampedInitial = firstDate;
    } else if (clampedInitial.isAfter(lastDate)) {
      clampedInitial = lastDate;
    }

    return showDatePicker(
      context: context,
      initialDate: clampedInitial,
      firstDate: firstDate,
      lastDate: lastDate,
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
  }

  Future<void> _loadProvinces() async {
    setState(() => _loadingProvinces = true);
    try {
      final list = await ph_addr.PhAddressService.getProvinces();
      if (mounted) {
        setState(() {
          _apiProvinces = list.map((p) => p.name).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading provinces: $e');
    } finally {
      if (mounted) setState(() => _loadingProvinces = false);
    }
  }

  Future<void> _onProvinceSelected(String provinceName) async {
    setState(() {
      _provinceCtrl.text = provinceName;
      _cityCtrl.clear();
      _barangayCtrl.clear();
      _streetCtrl.clear();
      _selectedBarangay = null;
      _apiCities = [];
      _apiBarangays = [];
      _loadingCities = true;
    });

    try {
      final list = await ph_addr.PhAddressService.getCities(provinceName);
      if (mounted) {
        setState(() {
          _apiCities = list.map((c) => c.name).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading cities: $e');
    } finally {
      if (mounted) setState(() => _loadingCities = false);
    }
    _validateStepInline(1);
  }

  Future<void> _onCitySelected(String cityName) async {
    setState(() {
      _cityCtrl.text = cityName;
      _barangayCtrl.clear();
      _streetCtrl.clear();
      _selectedBarangay = null;
      _apiBarangays = [];
      _loadingBarangays = true;
    });

    try {
      final list = await ph_addr.PhAddressService.getBarangays(cityName);
      if (mounted) {
        setState(() {
          _apiBarangays = list.map((b) => b.name).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading barangays: $e');
    } finally {
      if (mounted) setState(() => _loadingBarangays = false);
    }
    _validateStepInline(1);
  }

  void _onBarangaySelected(String barangayName) {
    setState(() {
      _selectedBarangay = barangayName;
      _barangayCtrl.text = barangayName;
      _streetCtrl.clear();
    });
    _validateStepInline(1);
  }

  Future<void> _preloadCitiesAndBarangays() async {
    final province = _provinceCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    if (province.isNotEmpty) {
      setState(() => _loadingCities = true);
      try {
        final list = await ph_addr.PhAddressService.getCities(province);
        if (mounted) {
          setState(() {
            _apiCities = list.map((c) => c.name).toList();
          });
        }
      } catch (e) {
        debugPrint('Error preloading cities: $e');
      } finally {
        if (mounted) setState(() => _loadingCities = false);
      }
    }
    if (city.isNotEmpty) {
      setState(() => _loadingBarangays = true);
      try {
        final list = await ph_addr.PhAddressService.getBarangays(city);
        if (mounted) {
          setState(() {
            _apiBarangays = list.map((b) => b.name).toList();
          });
        }
      } catch (e) {
        debugPrint('Error preloading barangays: $e');
      } finally {
        if (mounted) setState(() => _loadingBarangays = false);
      }
    }
  }

  Future<void> _loadContext() async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) throw Exception('Not authenticated');
      final result = await SupabaseService.getMidwifeContext(accountId);
      if (result['success'] == true) {
        _midwifeId = result['midwife_id'] as int;
        _assignedBhcId = result['assigned_bhc_id'] as int;
        _bhcName = result['bhc_name'] as String;
        _applyBhcAddress();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load context: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingContext = false);
    }
  }

  String _buildLinkingDialogSubtitle(Map<String, dynamic> existingData, Map<String, dynamic>? pregnancyData) {
    final name = '${existingData['first_name'] ?? ''} ${existingData['last_name'] ?? ''}'.trim();
    final email = existingData['email_address'] ?? 'N/A';
    final phone = existingData['phone_number'] ?? 'N/A';

    final buffer = StringBuffer();
    buffer.writeln('Account: $name');
    buffer.writeln('Email: $email');
    buffer.writeln('Phone: $phone');

    if (pregnancyData != null) {
      buffer.writeln();
      buffer.writeln('Pregnancy: Week ${pregnancyData['week']} (${pregnancyData['trimester']})');
      buffer.writeln('LMP: ${pregnancyData['lmp']}');
      buffer.writeln('EDD: ${pregnancyData['edd']}');
    }

    buffer.writeln();
    buffer.write('Would you like to link this account?');
    return buffer.toString();
  }

  Future<void> _checkExistingAccountByPhone(String phone) async {
    if (phone.isEmpty) return;
    if (_existingAccountId != null) return;

    setState(() => _phoneChecking = true);

    try {
      final result = await SupabaseService.getExistingMotherAccount(phone: phone);

      if (result['exists']) {
        if (!result['has_bhc']) {
          _existingAccountId = result['account_id'];
          _existingMotherId = result['mother_id'];
          _isExistingSelfRegistered = true;
          final existingData = result['data'];
          final pregnancyData = result['pregnancy'];

          if (!mounted) return;
          final shouldLoad = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => ConfirmationDialogBox(
              title: 'Existing Account Found',
              subtitle: _buildLinkingDialogSubtitle(existingData, pregnancyData),
              confirmText: 'Yes, Link Account',
              cancelText: 'Cancel',
              onConfirm: () => Navigator.pop(ctx, true),
              onCancel: () => Navigator.pop(ctx, false),
            ),
          );

          if (shouldLoad == true) {
            _loadExistingData(existingData);
            _isUpdatingExisting = true;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Existing data loaded. Please complete missing information.'),
                backgroundColor: AppColors.success,
              ));
            }
          } else {
            _existingAccountId = null;
            _existingMotherId = null;
            _isExistingSelfRegistered = false;
          }
        } else {
          if (!mounted) return;
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => DialogBox(
              title: 'Phone Already Registered',
              content:
                  'This mother is already registered to a Barangay Health Center (BHC).',
              buttonText: 'OK',
              type: DialogType.warning,
              onPressed: () => Navigator.pop(context),
            ),
          );
          setState(() {
            _phoneError = 'This mother is already registered to a BHC';
          });
        }
      }
    } catch (e) {
      _existingAccountId = null;
      _existingMotherId = null;
      _isUpdatingExisting = false;
      _isExistingSelfRegistered = false;
    } finally {
      if (mounted) setState(() => _phoneChecking = false);
    }
  }

  Future<void> _checkExistingAccount() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    if (_existingAccountId != null) return;

    setState(() => _checkingAccount = true);

    try {
      final result = await SupabaseService.getExistingMotherAccount(email: email);

      if (result['exists']) {
        if (!result['has_bhc']) {
          _existingAccountId = result['account_id'];
          _existingMotherId = result['mother_id'];
          _isExistingSelfRegistered = true;
          final existingData = result['data'];
          final pregnancyData = result['pregnancy'];

          if (!mounted) return;
          final shouldLoad = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => ConfirmationDialogBox(
              title: 'Existing Account Found',
              subtitle: _buildLinkingDialogSubtitle(existingData, pregnancyData),
              confirmText: 'Yes, Link Account',
              cancelText: 'Cancel',
              onConfirm: () => Navigator.pop(ctx, true),
              onCancel: () => Navigator.pop(ctx, false),
            ),
          );

          if (shouldLoad == true) {
            _loadExistingData(existingData);
            _isUpdatingExisting = true;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Existing data loaded. Please complete missing information.'),
                backgroundColor: AppColors.success,
              ));
            }
          } else {
            _existingAccountId = null;
            _existingMotherId = null;
            _isExistingSelfRegistered = false;
          }
        } else {
          if (!mounted) return;
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => DialogBox(
              title: 'Email Already Registered',
              content:
                  'This mother is already registered to a Barangay Health Center (BHC).',
              buttonText: 'OK',
              type: DialogType.warning,
              onPressed: () => Navigator.pop(context),
            ),
          );
          setState(() {
            _emailError = 'This mother is already registered to a BHC';
          });
        }
      }
    } catch (e) {
      _existingAccountId = null;
      _existingMotherId = null;
      _isUpdatingExisting = false;
      _isExistingSelfRegistered = false;
    } finally {
      if (mounted) setState(() => _checkingAccount = false);
    }
  }

  void _loadExistingData(Map<String, dynamic> existingData) {
    _firstNameCtrl.text = existingData['first_name'] ?? '';
    _middleNameCtrl.text = existingData['middle_name'] ?? '';
    _lastNameCtrl.text = existingData['last_name'] ?? '';
    _selectedExtension = existingData['extension_name'] ?? '';
    _phoneCtrl.text = existingData['phone_number'] ?? '';
    _isEmailReadOnly = true;

    if (existingData['birthdate'] != null) {
      _birthdate = DateTime.tryParse(existingData['birthdate']);
      if (_birthdate != null) {
        _birthdateCtrl.text = _dateFmt.format(_birthdate!);
        _validateBirthdate();
      }
    }
    if (existingData['height'] != null) {
      _heightCtrl.text = existingData['height'].toString();
    }
    if (existingData['weight'] != null) {
      _weightCtrl.text = existingData['weight'].toString();
    }
    if (existingData['blood_type'] != null) {
      _bloodType = existingData['blood_type'];
      _bloodTypeCtrl.text = _bloodType ?? '';
    }

    if (existingData['house_number'] != null &&
        existingData['house_number'].toString().isNotEmpty) {
      _houseCtrl.text = existingData['house_number'].toString();
    }
    if (existingData['street'] != null &&
        existingData['street'].toString().isNotEmpty) {
      _streetCtrl.text = existingData['street'].toString();
    }
    if (existingData['barangay'] != null &&
        existingData['barangay'].toString().isNotEmpty) {
      _selectedBarangay = existingData['barangay'].toString();
      _barangayCtrl.text = existingData['barangay'].toString();
      _addressSameAsBhc = false;
    }
    if (existingData['city_municipality'] != null &&
        existingData['city_municipality'].toString().isNotEmpty) {
      _cityCtrl.text = existingData['city_municipality'].toString();
      _addressSameAsBhc = false;
    }
    if (existingData['province'] != null &&
        existingData['province'].toString().isNotEmpty) {
      _provinceCtrl.text = existingData['province'].toString();
      _addressSameAsBhc = false;
    }

    if (_existingMotherId != null) {
      SupabaseService.client
          .from('pregnancies')
          .select('last_menstrual_period, expected_date_of_delivery, status')
          .eq('mother_id', _existingMotherId!)
          .eq('status', 'ongoing')
          .maybeSingle()
          .then((pregnancyData) {
        if (pregnancyData != null && mounted) {
          final lmpStr = pregnancyData['last_menstrual_period'] as String?;
          final eddStr = pregnancyData['expected_date_of_delivery'] as String?;
          if (lmpStr != null && lmpStr.isNotEmpty) {
            final lmpDate = DateTime.tryParse(lmpStr);
            if (lmpDate != null) _updateFromLmp(lmpDate);
          } else if (eddStr != null && eddStr.isNotEmpty) {
            final eddDate = DateTime.tryParse(eddStr);
            if (eddDate != null) _updateFromEdd(eddDate);
          }
          setState(() {});
        }
      });
    }
    _preloadCitiesAndBarangays();
  }

  void _onEmailChanged(String v) {
    final value = v.trim();
    if (value.isEmpty) {
      _emailTimer?.cancel();
      setState(() {
        _emailChecking = false;
        _emailError = null;
      });
      _existingAccountId = null;
      _existingMotherId = null;
      _isUpdatingExisting = false;
      _isEmailReadOnly = false;
      _isExistingSelfRegistered = false;
      return;
    }
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
    setState(() => _emailError = valid ? null : 'Enter a valid email');
    if (!valid) {
      _emailTimer?.cancel();
      _emailChecking = false;
      return;
    }
    _emailTimer?.cancel();
    setState(() => _emailChecking = true);
    _emailTimer =
        Timer(const Duration(milliseconds: 600), () => _checkEmail(value));
    _checkExistingAccount();
  }

  Future<void> _checkEmail(String email) async {
    _lastEmailChecked = email;
    final available = await SupabaseService.isEmailAvailable(email);
    if (_lastEmailChecked != email || !mounted) return;
    setState(() {
      _emailChecking = false;
      if (!_isUpdatingExisting && !_isExistingSelfRegistered) {
        _emailError = available ? null : 'Email already in use';
      }
    });
  }

  void _applyBhcAddress() {
    _selectedBarangay = _bhcName;
    _barangayCtrl.text = _bhcName;
    _cityCtrl.text = 'Baliwag';
    _provinceCtrl.text = 'Bulacan';
  }

  void _updateFromLmp(DateTime lmp) {
    setState(() {
      _lmp = lmp;
      _edd = lmp.add(const Duration(days: 280));
      _lmpCtrl.text = _dateFmt.format(lmp);
      _eddCtrl.text = _dateFmt.format(_edd!);
      _gestationMethod = _GestationMethod.lmp;
      _gestationMethodCtrl.text = 'Last Menstrual Period (LMP)';
      _gestationError = _validateLmp(lmp);

      final days = DateTime.now().difference(lmp).inDays;
      if (days >= 0) {
        _aogWeeksCtrl.text = (days ~/ 7).toString();
        _aogDaysCtrl.text = (days % 7).toString();
      } else {
        _aogWeeksCtrl.text = '';
        _aogDaysCtrl.text = '';
      }
      _weeksError = null;
      _daysError = null;
    });

    _calculateBMI();

    // Warn if LMP is less than 4 weeks ago
    final daysSinceLmp = DateTime.now().difference(lmp).inDays;
    if (daysSinceLmp < 28 && _gestationError == null) {
      _showEarlyPregnancyWarning();
    }
  }

  void _updateFromEdd(DateTime edd) {
    setState(() {
      _edd = edd;
      _lmp = edd.subtract(const Duration(days: 280));
      _eddCtrl.text = _dateFmt.format(edd);
      _lmpCtrl.text = _dateFmt.format(_lmp!);
      _gestationMethod = _GestationMethod.edd;
      _gestationMethodCtrl.text = 'Estimated Delivery Date (EDD)';
      _gestationError = _validateEdd(edd) ?? _validateLmp(_lmp!);

      final days = DateTime.now().difference(_lmp!).inDays;
      if (days >= 0) {
        _aogWeeksCtrl.text = (days ~/ 7).toString();
        _aogDaysCtrl.text = (days % 7).toString();
      } else {
        _aogWeeksCtrl.text = '';
        _aogDaysCtrl.text = '';
      }
      _weeksError = null;
      _daysError = null;
    });

    _calculateBMI();
  }

  void _updateFromAog() {
    final wStr = _aogWeeksCtrl.text.trim();
    final dStr = _aogDaysCtrl.text.trim();

    if (wStr.isEmpty && dStr.isEmpty) {
      setState(() {
        _weeksError = null;
        _daysError = null;
        _gestationError = null;
        _lmp = null;
        _edd = null;
        _lmpCtrl.clear();
        _eddCtrl.clear();
      });
      _calculateBMI();
      return;
    }

    final w = int.tryParse(wStr);
    final d = int.tryParse(dStr);

    String? wErr;
    String? dErr;

    if (w == null && wStr.isNotEmpty) {
      wErr = 'Enter a valid number';
    } else if (w != null && (w < 2 || w > 42)) {
      wErr = 'Must be 2-42';
    }

    if (d == null && dStr.isNotEmpty) {
      dErr = 'Enter a valid number';
    } else if (d != null && (d < 0 || d > 6)) {
      dErr = 'Must be 0-6';
    }

    setState(() {
      _weeksError = wErr;
      _daysError = dErr;
      _gestationError =
          (wErr != null || dErr != null) ? 'Invalid AOG weeks or days' : null;
    });

    if (wErr == null && dErr == null && w != null && d != null) {
      final lmp = DateTime.now().subtract(Duration(days: w * 7 + d));
      setState(() {
        _lmp = lmp;
        _edd = lmp.add(const Duration(days: 280));
        _lmpCtrl.text = _dateFmt.format(lmp);
        _eddCtrl.text = _dateFmt.format(_edd!);
        _gestationMethod = _GestationMethod.aog;
        _gestationMethodCtrl.text = 'Age of Gestation (AOG)';
        _gestationError = _validateLmp(lmp);
      });
    }
    _calculateBMI();
  }

  String _formatAog() {
    if (_lmp == null) return '-';
    final days = DateTime.now().difference(_lmp!).inDays;
    if (days < 0) return '-';
    return '${days ~/ 7}w ${days % 7}d';
  }

  String _resolveEmail() {
    final provided = _emailCtrl.text.trim();
    if (provided.isNotEmpty) return provided;
    final first = _firstNameCtrl.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z]'), '');
    final last = _lastNameCtrl.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z]'), '');
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = (first.isEmpty ? 'mother' : first);
    final safeLast = (last.isEmpty ? 'unknown' : last);
    return '$safeName.$safeLast.$phone.$ts@inaagapay.internal';
  }

  bool _validateStepInline(int step) {
    switch (step) {
      case 0:
        final firstNameEmpty = _firstNameCtrl.text.trim().isEmpty;
        final lastNameEmpty = _lastNameCtrl.text.trim().isEmpty;
        final phoneEmpty = _phoneCtrl.text.trim().isEmpty;
        final birthdateEmpty = _birthdate == null;
        final emailVisible = _calculatedAge == null || _calculatedAge! >= 13;
        final emailHasValue = _emailCtrl.text.trim().isNotEmpty;
        final emailValid =
            !emailVisible || !emailHasValue || _emailError == null;

        setState(() {
          _firstNameError = firstNameEmpty ? 'First name is required' : null;
          _lastNameError = lastNameEmpty ? 'Last name is required' : null;
        });
        return !firstNameEmpty &&
            !lastNameEmpty &&
            !phoneEmpty &&
            !birthdateEmpty &&
            _birthdateError == null &&
            emailValid;

      case 1:
        final houseEmpty = _houseCtrl.text.trim().isEmpty;
        final streetEmpty = _streetCtrl.text.trim().isEmpty;
        setState(() {
          _houseError = houseEmpty ? 'House number is required' : null;
          _streetError = streetEmpty ? 'Street is required' : null;
          if (!_addressSameAsBhc) {
            _barangayError = _barangayCtrl.text.trim().isEmpty
                ? 'Barangay is required'
                : null;
            _cityError = _cityCtrl.text.trim().isEmpty
                ? 'City/Municipality is required'
                : null;
            _provinceError = _provinceCtrl.text.trim().isEmpty
                ? 'Province is required'
                : null;
          } else {
            _barangayError = null;
            _cityError = null;
            _provinceError = null;
          }
        });
        return !houseEmpty &&
            !streetEmpty &&
            (_addressSameAsBhc ||
                (_barangayCtrl.text.trim().isNotEmpty &&
                    _cityCtrl.text.trim().isNotEmpty &&
                    _provinceCtrl.text.trim().isNotEmpty));

      case 3:
        if (_gestationMethod == _GestationMethod.lmp && _lmp == null) {
          return false;
        }
        if (_gestationMethod == _GestationMethod.edd && _edd == null) {
          return false;
        }
        if (_gestationMethod == _GestationMethod.aog &&
            _aogWeeksCtrl.text.trim().isEmpty &&
            _aogDaysCtrl.text.trim().isEmpty) {
          return false;
        }
        if (_gestationError != null) return false;
        return true;

      case 4:
        final hVal = double.tryParse(_heightCtrl.text.trim());
        final wVal = double.tryParse(_weightCtrl.text.trim());

        setState(() {
          if (_heightCtrl.text.trim().isEmpty) {
            _heightError = 'Height is required';
          }
          if (_weightCtrl.text.trim().isEmpty) {
            _weightError = 'Weight is required';
          }
          if (_knowsPrePregnancyWeight &&
              _prePregnancyWeightCtrl.text.trim().isEmpty) {
            _prePregnancyWeightError = 'Pre-pregnancy weight is required';
          }
        });

        if (hVal == null || _heightError != null) return false;
        if (wVal == null || _weightError != null) return false;

        if (_knowsPrePregnancyWeight) {
          final ppwVal = double.tryParse(_prePregnancyWeightCtrl.text.trim());
          if (ppwVal == null || _prePregnancyWeightError != null) return false;
        }
        return true;

      default:
        return true;
    }
  }

  void _goNext() {
    if (_validateStepInline(_step)) {
      if (_step < _totalSteps - 1) {
        _pageController.animateToPage(_step + 1,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut);
        setState(() => _step++);
      }
    }
  }

  void _goBack() {
    if (_step > 0) {
      _pageController.animateToPage(_step - 1,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      setState(() => _step--);
    }
  }

  void _jumpToStep(int step) {
    if (step >= 0 && step < _totalSteps) {
      _pageController.animateToPage(step,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      setState(() => _step = step);
    }
  }

  Future<void> _submit() async {
    if (!_validateStepInline(8)) return;
    setState(() => _submitting = true);

    try {
      Map<String, dynamic> result;

      if (_isUpdatingExisting && _existingMotherId != null) {
        result = await SupabaseService.updateExistingMotherAccount(
          motherId: _existingMotherId!,
          assignedBhcId: _assignedBhcId!,
          houseNumber: _houseCtrl.text.trim(),
          street: _streetCtrl.text.trim(),
          barangay: _selectedBarangay,
          city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
          province: _provinceCtrl.text.trim().isEmpty
              ? null
              : _provinceCtrl.text.trim(),
          heightCm: double.tryParse(_heightCtrl.text.trim()),
          weightKg: double.tryParse(_weightCtrl.text.trim()),
          bloodType: _bloodType,
          lmp: _lmp,
          edd: _edd,
          emergencyContacts: _emergencyContacts.map((e) => e.toMap()).toList(),
          medicalConditions: _medicalConditions.map((m) => m.toMap()).toList(),
          allergies: _allergies.map((a) => a.toMap()).toList(),
          pastPregnancies: _pastPregnancies.map((p) => p.toMap()).toList(),
          fetalCount: int.tryParse(_fetalCountCtrl.text.trim()) ?? 1,
          prePregnancyWeight:
              double.tryParse(_prePregnancyWeightCtrl.text.trim()),
          riskFactors: _evaluatePregnancyRisk(),
        );
      } else {
        result = await SupabaseService.addMotherFullByMidwifeWithAutoPassword(
          midwifeId: _midwifeId!,
          assignedBhcId: _assignedBhcId!,
          email: _resolveEmail(),
          firstName: _firstNameCtrl.text.trim(),
          middleName: _middleNameCtrl.text.trim().isEmpty
              ? null
              : _middleNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          extensionName: _selectedExtension.isEmpty ? null : _selectedExtension,
          phone: _phoneCtrl.text.trim(),
          houseNumber: _houseCtrl.text.trim(),
          street: _streetCtrl.text.trim(),
          barangay: _selectedBarangay,
          city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
          province: _provinceCtrl.text.trim().isEmpty
              ? null
              : _provinceCtrl.text.trim(),
          birthdate: _birthdate,
          heightCm: double.tryParse(_heightCtrl.text.trim()),
          weightKg: double.tryParse(_weightCtrl.text.trim()),
          bloodType: _bloodType,
          lmp: _lmp,
          edd: _edd,
          emergencyContacts: _emergencyContacts.map((e) => e.toMap()).toList(),
          medicalConditions: _medicalConditions.map((m) => m.toMap()).toList(),
          allergies: _allergies.map((a) => a.toMap()).toList(),
          pastPregnancies: _pastPregnancies.map((p) => p.toMap()).toList(),
          fetalCount: int.tryParse(_fetalCountCtrl.text.trim()) ?? 1,
          prePregnancyWeight:
              double.tryParse(_prePregnancyWeightCtrl.text.trim()),
          riskFactors: _evaluatePregnancyRisk(),
        );
      }

      if (!mounted) return;

      if (result['success'] == true) {
        final motherId = result['mother_id'] as int?;
        final pregnancyId = result['pregnancy_id'] as int?;

        final hasRealEmail = _emailCtrl.text.trim().isNotEmpty;
        final emailSent = result['email_sent'] == true;
        final smsSent = result['sms_sent'] == true;
        
        String successMessage;
        if (_isUpdatingExisting) {
          successMessage = 'Mother profile successfully linked to your health center!\n\nNo temporary password was sent — the mother already has her own login credentials.';
        } else if (emailSent) {
          successMessage = 'Mother account created successfully!\n\nA temporary password has been sent to ${_emailCtrl.text.trim()}.';
        } else if (smsSent) {
          successMessage = 'Mother account created successfully!\n\nA temporary password has been sent via SMS to ${_phoneCtrl.text.trim()}.';
        } else {
          successMessage = 'Mother account created successfully!\n\nThe mother can register online later. Her account will sync automatically if she provides the same contact number.';
        }

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DialogBox(
            type: DialogType.success,
            title: _isUpdatingExisting
                ? 'Account Updated'
                : 'Mother Account Created',
            content: successMessage,
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );

        if (motherId != null && pregnancyId != null) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => AddPrenatalCheckupScreen(
                  motherId: motherId,
                  pregnancyId: pregnancyId,
                  lmp: _lmp,
                  motherWeight: double.tryParse(_weightCtrl.text.trim()),
                  isInitialRegistration: true,
                ),
              ),
            );
          }
          return;
        }

        if (mounted) Navigator.pop(context, true);
      } else {
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => DialogBox(
              type: DialogType.error,
              title: 'Failed to Save',
              content: result['message'] ?? 'Failed to save mother record.',
              buttonText: 'OK',
              onPressed: () => Navigator.pop(context),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DialogBox(
            type: DialogType.error,
            title: 'Error',
            content: 'An error occurred: $e',
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showAddEmergencyContact({int? editIndex}) async {
    _EmergencyContact? existing =
        editIndex != null ? _emergencyContacts[editIndex] : null;

    final firstNameCtrl =
        TextEditingController(text: existing?.firstName ?? '');
    final lastNameCtrl = TextEditingController(text: existing?.lastName ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phoneNumber ?? '');

    final isCustomRel = existing != null &&
        !['Spouse', 'Partner', 'Mother', 'Father', 'Sibling', 'Friend']
            .contains(existing.relationship);
    final relationshipCtrl = TextEditingController(
        text: isCustomRel ? 'Other' : (existing?.relationship ?? ''));
    final customRelationshipCtrl =
        TextEditingController(text: isCustomRel ? existing.relationship : '');

    bool showRelationshipDropdown = false;
    String? phoneError;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                // Real-time phone validation
                void validatePhone(String val) {
                  final normalized =
                      val.trim().replaceAll(RegExp(r'[^0-9+]'), '');
                  final isValid =
                      RegExp(r'^(\+?63|0)9\d{9}$').hasMatch(normalized);
                  setDialogState(() {
                    phoneError = val.isEmpty
                        ? null
                        : (isValid ? null : 'Enter a valid PH mobile number');
                  });
                }

                final isPhoneValid =
                    phoneCtrl.text.trim().isNotEmpty && phoneError == null;
                final isRelationshipValid =
                    relationshipCtrl.text.trim().isNotEmpty &&
                        (relationshipCtrl.text.trim() != 'Other' ||
                            customRelationshipCtrl.text.trim().isNotEmpty);
                final isFormValid = firstNameCtrl.text.trim().isNotEmpty &&
                    lastNameCtrl.text.trim().isNotEmpty &&
                    isPhoneValid &&
                    isRelationshipValid;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.brandText),
                          onPressed: () => Navigator.pop(dialogCtx, false),
                        ),
                        const Expanded(
                          child: Center(
                            child: Text(
                              'Add Emergency Contact',
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
                    // Scrollable body
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPremiumTextField(
                              controller: firstNameCtrl,
                              labelText: 'First Name',
                              hintText: 'Enter first name',
                              isRequired: true,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            _buildPremiumTextField(
                              controller: lastNameCtrl,
                              labelText: 'Last Name',
                              hintText: 'Enter last name',
                              isRequired: true,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            _buildPremiumTextField(
                              controller: phoneCtrl,
                              labelText: 'Contact Number',
                              hintText: 'e.g. 09171234567',
                              isRequired: true,
                              keyboardType: TextInputType.phone,
                              errorText: phoneError,
                              onChanged: (val) {
                                validatePhone(val);
                                setDialogState(() {});
                              },
                            ),
                            const SizedBox(height: 16),
                            // Relationship Dropdown Field
                            _buildPremiumTextField(
                              controller: relationshipCtrl,
                              labelText: 'Relationship',
                              hintText: 'Select relationship',
                              isRequired: true,
                              readOnly: true,
                              suffixIcon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: AppColors.brandPrimary),
                              onTap: () {
                                setDialogState(() {
                                  showRelationshipDropdown =
                                      !showRelationshipDropdown;
                                });
                              },
                            ),
                            if (showRelationshipDropdown) ...[
                              const SizedBox(height: 4),
                              Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                color: Colors.white,
                                child: Container(
                                  constraints:
                                      const BoxConstraints(maxHeight: 200),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: _relationshipOptions.length,
                                    itemBuilder: (context, idx) {
                                      final rel = _relationshipOptions[idx];
                                      return ListTile(
                                        title: Text(rel,
                                            style:
                                                const TextStyle(fontSize: 14)),
                                        dense: true,
                                        onTap: () {
                                          setDialogState(() {
                                            relationshipCtrl.text = rel;
                                            showRelationshipDropdown = false;
                                            if (rel != 'Other') {
                                              customRelationshipCtrl.clear();
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                            if (relationshipCtrl.text == 'Other') ...[
                              const SizedBox(height: 16),
                              _buildPremiumTextField(
                                controller: customRelationshipCtrl,
                                labelText: 'Specify Relationship',
                                hintText: 'Enter relationship',
                                isRequired: true,
                                onChanged: (val) => setDialogState(() {}),
                              ),
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Primary Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isFormValid
                            ? () => Navigator.pop(dialogCtx, true)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          editIndex != null ? 'Save Changes' : 'Add Contact',
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

    if (result == true) {
      setState(() {
        final rel = relationshipCtrl.text.trim() == 'Other'
            ? customRelationshipCtrl.text.trim()
            : relationshipCtrl.text.trim();
        final contact = _EmergencyContact()
          ..firstName = firstNameCtrl.text.trim()
          ..lastName = lastNameCtrl.text.trim()
          ..phoneNumber = phoneCtrl.text.trim()
          ..relationship = rel;

        if (editIndex != null) {
          _emergencyContacts[editIndex] = contact;
        } else {
          _emergencyContacts.add(contact);
        }
      });
    }
  }

  Future<void> _confirmDeleteEmergencyContact(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => ConfirmationDialogBox(
        title: 'Remove Contact',
        subtitle: 'Are you sure you want to remove this emergency contact?',
        confirmText: 'Remove',
        cancelText: 'Cancel',
        accentColor: AppColors.error,
        onConfirm: () => Navigator.pop(dlgCtx, true),
        onCancel: () => Navigator.pop(dlgCtx, false),
      ),
    );
    if (confirm == true) setState(() => _emergencyContacts.removeAt(index));
  }

  Future<void> _showAddMedicalCondition(
      {String? prefill, int? editIndex}) async {
    _MedicalCondition? existing =
        editIndex != null ? _medicalConditions[editIndex] : null;

    final nameCtrl =
        TextEditingController(text: existing?.conditionName ?? prefill ?? '');
    DateTime? diagDate = existing?.diagnosisDate;
    String status = existing?.status ?? 'active';
    final remarksCtrl = TextEditingController(text: existing?.remarks ?? '');
    final diagDateCtrl = TextEditingController(
        text: diagDate != null ? _dateFmt.format(diagDate) : '');

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            width: MediaQuery.of(ctx).size.width * 0.9,
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                final inputName = nameCtrl.text.trim();
                final isDuplicate = _medicalConditions.asMap().entries.any(
                    (e) =>
                        e.key != editIndex &&
                        e.value.conditionName.toLowerCase() ==
                            inputName.toLowerCase());
                final isFormValid = inputName.isNotEmpty && !isDuplicate;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.brandText),
                          onPressed: () => Navigator.pop(dialogCtx, false),
                        ),
                        const Expanded(
                          child: Center(
                            child: Text(
                              'Medical Condition',
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
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Common Conditions',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _commonConditions.map((cond) {
                                final isSelected = inputName.toLowerCase() ==
                                    cond.toLowerCase();
                                return ActionChip(
                                  label: Text(cond,
                                      style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.brandPrimary,
                                          fontSize: 12)),
                                  backgroundColor: isSelected
                                      ? AppColors.brandPrimary
                                      : Colors.white,
                                  side:
                                      BorderSide(color: AppColors.brandPrimary),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  onPressed: () {
                                    setDialogState(() {
                                      if (cond == 'Other') {
                                        nameCtrl.clear();
                                      } else {
                                        nameCtrl.text = cond;
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            AppInputField(
                              controller: nameCtrl,
                              hintText: 'Condition Name',
                              isRequired: true,
                              leadingIcon: Icons.medical_services_outlined,
                              errorText: isDuplicate
                                  ? 'Condition already added'
                                  : null,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: diagDateCtrl,
                              hintText: 'Diagnosis Date (Optional)',
                              readOnly: true,
                              leadingIcon: Icons.calendar_today_outlined,
                              onTap: () async {
                                final picked = await _showBrandedDatePicker(
                                  context: dialogCtx,
                                  initialDate: diagDate ?? DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    diagDate = picked;
                                    diagDateCtrl.text = _dateFmt.format(picked);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            const Text('Status',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setDialogState(() => status = 'active'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'active'
                                            ? AppColors.brandPrimary
                                                .withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: status == 'active'
                                                ? AppColors.brandPrimary
                                                : AppColors.borderPrimary),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Active',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: status == 'active'
                                                  ? AppColors.brandPrimary
                                                  : AppColors.textSecondary)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setDialogState(
                                        () => status = 'resolved'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'resolved'
                                            ? AppColors.brandPrimary
                                                .withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: status == 'resolved'
                                                ? AppColors.brandPrimary
                                                : AppColors.borderPrimary),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Resolved',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: status == 'resolved'
                                                  ? AppColors.brandPrimary
                                                  : AppColors.textSecondary)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: remarksCtrl,
                              hintText: 'Remarks (Optional)',
                              leadingIcon: Icons.notes_outlined,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isFormValid
                            ? () => Navigator.pop(dialogCtx, true)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          editIndex != null ? 'Save Changes' : 'Add Condition',
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

    if (result == true) {
      setState(() {
        final condition = _MedicalCondition(nameCtrl.text.trim())
          ..diagnosisDate = diagDate
          ..status = status
          ..remarks =
              remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim();

        if (editIndex != null) {
          _medicalConditions[editIndex] = condition;
        } else {
          _medicalConditions.add(condition);
        }
      });
    }
  }

  Future<void> _confirmDeleteMedicalCondition(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => ConfirmationDialogBox(
        title: 'Remove Condition',
        subtitle: 'Are you sure you want to remove this medical condition?',
        confirmText: 'Remove',
        cancelText: 'Cancel',
        accentColor: AppColors.error,
        onConfirm: () => Navigator.pop(dlgCtx, true),
        onCancel: () => Navigator.pop(dlgCtx, false),
      ),
    );
    if (confirm == true) setState(() => _medicalConditions.removeAt(index));
  }

  Future<void> _showAddAllergy({int? editIndex, String? prefill}) async {
    _Allergy? existing = editIndex != null ? _allergies[editIndex] : null;

    final allergenCtrl = TextEditingController(text: existing?.allergen ?? prefill ?? '');
    DateTime? diagDate = existing?.diagnosisDate;
    String status = existing?.status ?? 'active';
    final treatmentCtrl =
        TextEditingController(text: existing?.treatment ?? '');
    final diagDateCtrl = TextEditingController(
        text: diagDate != null ? _dateFmt.format(diagDate) : '');

    final List<String> commonAllergens = [
      'Peanuts',
      'Penicillin',
      'Dust Mites',
      'Pollen',
      'Shellfish',
      'Pet Dander',
      'Fish',
      'Milk',
      'Eggs',
      'Soy',
      'Wheat',
      'Latex',
      'Insect Stings',
      'Mold',
      'Fragrances',
      'Nickel',
      'Other'
    ];

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            width: MediaQuery.of(ctx).size.width * 0.9,
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                final inputName = allergenCtrl.text.trim();
                final isDuplicate = _allergies.asMap().entries.any((e) =>
                    e.key != editIndex &&
                    e.value.allergen.toLowerCase() == inputName.toLowerCase());
                final isFormValid = inputName.isNotEmpty && !isDuplicate;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.brandText),
                          onPressed: () => Navigator.pop(dialogCtx, false),
                        ),
                        const Expanded(
                          child: Center(
                            child: Text(
                              'Add Allergy',
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
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Common Allergens',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: commonAllergens.map((cond) {
                                final isSelected = inputName.toLowerCase() ==
                                    cond.toLowerCase();
                                return ActionChip(
                                  label: Text(cond,
                                      style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.brandPrimary,
                                          fontSize: 12)),
                                  backgroundColor: isSelected
                                      ? AppColors.brandPrimary
                                      : Colors.white,
                                  side:
                                      BorderSide(color: AppColors.brandPrimary),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  onPressed: () {
                                    setDialogState(() {
                                      allergenCtrl.text = cond;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            AppInputField(
                              controller: allergenCtrl,
                              hintText: 'Allergen Name',
                              isRequired: true,
                              leadingIcon: Icons.warning_amber_rounded,
                              errorText:
                                  isDuplicate ? 'Allergen already added' : null,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: diagDateCtrl,
                              hintText: 'Diagnosis Date (Optional)',
                              readOnly: true,
                              leadingIcon: Icons.calendar_today_outlined,
                              onTap: () async {
                                final picked = await _showBrandedDatePicker(
                                  context: dialogCtx,
                                  initialDate: diagDate ?? DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    diagDate = picked;
                                    diagDateCtrl.text = _dateFmt.format(picked);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            const Text('Status',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setDialogState(() => status = 'active'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'active'
                                            ? AppColors.brandPrimary
                                                .withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: status == 'active'
                                                ? AppColors.brandPrimary
                                                : AppColors.borderPrimary),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Active',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: status == 'active'
                                                  ? AppColors.brandPrimary
                                                  : AppColors.textSecondary)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setDialogState(
                                        () => status = 'resolved'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'resolved'
                                            ? AppColors.brandPrimary
                                                .withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: status == 'resolved'
                                                ? AppColors.brandPrimary
                                                : AppColors.borderPrimary),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Resolved',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: status == 'resolved'
                                                  ? AppColors.brandPrimary
                                                  : AppColors.textSecondary)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: treatmentCtrl,
                              hintText: 'Treatment (Optional)',
                              leadingIcon: Icons.medical_services_outlined,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isFormValid
                            ? () => Navigator.pop(dialogCtx, true)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          editIndex != null ? 'Save Changes' : 'Add Allergy',
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

    if (result == true) {
      setState(() {
        final allergy = _Allergy(allergenCtrl.text.trim())
          ..diagnosisDate = diagDate
          ..status = status
          ..treatment = treatmentCtrl.text.trim().isEmpty
              ? null
              : treatmentCtrl.text.trim();

        if (editIndex != null) {
          _allergies[editIndex] = allergy;
        } else {
          _allergies.add(allergy);
        }
      });
    }
  }

  Future<void> _confirmDeleteAllergy(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => ConfirmationDialogBox(
        title: 'Remove Allergy',
        subtitle: 'Are you sure you want to remove this allergy?',
        confirmText: 'Remove',
        cancelText: 'Cancel',
        accentColor: AppColors.error,
        onConfirm: () => Navigator.pop(dlgCtx, true),
        onCancel: () => Navigator.pop(dlgCtx, false),
      ),
    );
    if (confirm == true) setState(() => _allergies.removeAt(index));
  }

  Future<void> _showAddPastPregnancy({int? editIndex}) async {
    _PastPregnancy? existing =
        editIndex != null ? _pastPregnancies[editIndex] : null;

    int fetalCount = existing?.outcomes.length ?? 1;
    final gaCtrl = TextEditingController(
        text: existing?.outcomes.firstOrNull?.gestationalAgeAtEnd
                ?.toStringAsFixed(0) ??
            '');
    DateTime? pregnancyOutcomeDate = existing?.outcomes.isNotEmpty == true
        ? existing?.outcomes.first.outcomeDate
        : null;
    bool isPregnancyDateEstimated = existing?.outcomes.isNotEmpty == true
        ? existing!.outcomes.first.isEstimated
        : false;
    List<String> outcomes =
        existing?.outcomes.map((o) => o.outcome).toList() ?? ['live_birth'];
    List<TextEditingController> placeCtrls = existing?.outcomes
            .map((o) => TextEditingController(text: o.placeOfDelivery ?? ''))
            .toList() ??
        [TextEditingController()];
    List<String?> deliveryMethods =
        existing?.outcomes.map((o) => o.deliveryMethod).toList() ?? [null];
    List<bool> showOutcomeDropdowns = List.generate(10, (_) => false);
    List<bool> showDeliveryDropdowns = List.generate(10, (_) => false);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setS) {
                bool allValid = true;
                String? gaError;
                if (gaCtrl.text.trim().isNotEmpty) {
                  final gaVal = int.tryParse(gaCtrl.text.trim());
                  if (gaVal == null || gaVal > 42) gaError = '0-42 wks';
                }
                if (gaError != null) allValid = false;
                if (pregnancyOutcomeDate == null) allValid = false;

                for (int i = 0; i < fetalCount; i++) {
                  if (outcomes[i] == 'live_birth' ||
                      outcomes[i] == 'stillbirth') {
                    if (placeCtrls[i].text.trim().isEmpty) allValid = false;
                    if (deliveryMethods[i] == null) allValid = false;
                  }
                }

                final outcomeLabels = {
                  'live_birth': 'Live Birth',
                  'stillbirth': 'Stillbirth',
                  'miscarriage': 'Miscarriage',
                  'abortion': 'Abortion',
                  'ectopic': 'Ectopic',
                };

                final deliveryMethodsOptions = [
                  'Normal Spontaneous Vaginal Delivery',
                  'Cesarean Section',
                  'Assisted Vaginal Delivery',
                  'Other',
                ];

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.brandText),
                          onPressed: () => Navigator.pop(dialogCtx, false),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              editIndex != null
                                  ? 'Edit Past Pregnancy'
                                  : 'Add Past Pregnancy',
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildPremiumTextField(
                                    controller: gaCtrl,
                                    labelText: 'Gestational Age (weeks)',
                                    hintText: 'e.g., 39',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(2),
                                    ],
                                    errorText: gaError,
                                    onChanged: (val) => setS(() {}),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildPremiumTextField(
                              controller: TextEditingController(
                                text: pregnancyOutcomeDate == null
                                    ? ''
                                    : _dateFmt.format(pregnancyOutcomeDate!),
                              ),
                              labelText: 'Outcome Date',
                              hintText: 'Select date',
                              isRequired: true,
                              readOnly: true,
                              suffixIcon: const Icon(
                                  Icons.calendar_today_outlined,
                                  color: AppColors.brandPrimary),
                              onTap: () async {
                                final maxDate = _lmp != null
                                    ? _lmp!.subtract(const Duration(days: 14))
                                    : DateTime.now();
                                final picked = await _showBrandedDatePicker(
                                  context: dialogCtx,
                                  initialDate: pregnancyOutcomeDate ?? maxDate,
                                  firstDate: DateTime(1900),
                                  lastDate: maxDate,
                                );
                                if (picked != null) {
                                  setS(() {
                                    pregnancyOutcomeDate = picked;
                                  });
                                }
                              },
                            ),
                            if (pregnancyOutcomeDate != null &&
                                _lmp != null &&
                                _lmp!.difference(pregnancyOutcomeDate!).inDays <
                                    180) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: AppColors.warning
                                          .withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        color: AppColors.warning, size: 20),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'The interval between recorded pregnancies appears shorter than commonly expected maternal recovery intervals. Continued healthcare monitoring may be beneficial.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.warning,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => setS(() => isPregnancyDateEstimated =
                                  !isPregnancyDateEstimated),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: isPregnancyDateEstimated,
                                      onChanged: (v) => setS(() =>
                                          isPregnancyDateEstimated =
                                              v ?? false),
                                      activeColor: AppColors.brandPrimary,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Date is estimated',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.brandText),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Fetal Count',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.brandPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9F9F9),
                                    borderRadius: BorderRadius.circular(28),
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.people_outline,
                                          color: Colors.grey),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Number of Fetuses',
                                          style: TextStyle(
                                              fontSize: 15,
                                              color: AppColors.brandText),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: AppColors.brandPrimary),
                                        onPressed: () {
                                          if (fetalCount > 1) {
                                            setS(() {
                                              fetalCount--;
                                              outcomes.removeLast();
                                              placeCtrls.removeLast();
                                              deliveryMethods.removeLast();
                                            });
                                          }
                                        },
                                      ),
                                      Text(
                                        '$fetalCount',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.brandText,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.add_circle_outline,
                                            color: AppColors.brandPrimary),
                                        onPressed: () {
                                          if (fetalCount < 5) {
                                            setS(() {
                                              fetalCount++;
                                              outcomes.add('live_birth');
                                              placeCtrls
                                                  .add(TextEditingController());
                                              deliveryMethods.add(null);
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            for (int i = 0; i < fetalCount; i++) ...[
                              if (fetalCount > 1) ...[
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                        child: Divider(
                                            color: Colors.grey.shade300,
                                            thickness: 1)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: Text(
                                        'Fetus ${i + 1}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppColors.brandPrimary,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                        child: Divider(
                                            color: Colors.grey.shade300,
                                            thickness: 1)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ] else ...[
                                const SizedBox(height: 16),
                              ],
                              _buildPremiumTextField(
                                controller: TextEditingController(
                                    text: outcomeLabels[outcomes[i]] ??
                                        outcomes[i]),
                                labelText: 'Outcome',
                                hintText: 'Select outcome',
                                isRequired: true,
                                readOnly: true,
                                suffixIcon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: AppColors.brandPrimary),
                                onTap: () {
                                  setS(() {
                                    showOutcomeDropdowns[i] =
                                        !showOutcomeDropdowns[i];
                                  });
                                },
                              ),
                              if (showOutcomeDropdowns[i]) ...[
                                const SizedBox(height: 4),
                                Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  color: Colors.white,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children:
                                        outcomeLabels.entries.map((entry) {
                                      return ListTile(
                                        title: Text(entry.value,
                                            style:
                                                const TextStyle(fontSize: 14)),
                                        dense: true,
                                        onTap: () {
                                          setS(() {
                                            outcomes[i] = entry.key;
                                            showOutcomeDropdowns[i] = false;
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                              if (outcomes[i] == 'live_birth' ||
                                  outcomes[i] == 'stillbirth') ...[
                                const SizedBox(height: 16),
                                _buildPremiumTextField(
                                  controller: placeCtrls[i],
                                  labelText: 'Place of Delivery',
                                  hintText: 'Enter place of delivery',
                                  isRequired: true,
                                  onChanged: (val) => setS(() {}),
                                ),
                                const SizedBox(height: 16),
                                _buildPremiumTextField(
                                  controller: TextEditingController(
                                      text: deliveryMethods[i] ?? ''),
                                  labelText: 'Delivery Method',
                                  hintText: 'Select delivery method',
                                  isRequired: true,
                                  readOnly: true,
                                  suffixIcon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: AppColors.brandPrimary),
                                  onTap: () {
                                    setS(() {
                                      showDeliveryDropdowns[i] =
                                          !showDeliveryDropdowns[i];
                                    });
                                  },
                                ),
                                if (showDeliveryDropdowns[i]) ...[
                                  const SizedBox(height: 4),
                                  Card(
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    color: Colors.white,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children:
                                          deliveryMethodsOptions.map((method) {
                                        return ListTile(
                                          title: Text(method,
                                              style: const TextStyle(
                                                  fontSize: 14)),
                                          dense: true,
                                          onTap: () {
                                            setS(() {
                                              deliveryMethods[i] = method;
                                              showDeliveryDropdowns[i] = false;
                                            });
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: allValid
                            ? () => Navigator.pop(dialogCtx, true)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          editIndex != null
                              ? 'Save Changes'
                              : 'Add Past Pregnancy',
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

    if (result == true) {
      setState(() {
        final pastPreg = _PastPregnancy();
        pastPreg.fetalCount = fetalCount;
        for (int i = 0; i < fetalCount; i++) {
          pastPreg.outcomes.add(_PastFetalOutcome(
              outcome: outcomes[i], outcomeDate: pregnancyOutcomeDate!)
            ..isEstimated = isPregnancyDateEstimated
            ..placeOfDelivery = placeCtrls[i].text.trim().isEmpty
                ? null
                : placeCtrls[i].text.trim()
            ..deliveryMethod = deliveryMethods[i]
            ..gestationalAgeAtEnd = double.tryParse(gaCtrl.text.trim()));
        }
        if (editIndex != null) {
          _pastPregnancies[editIndex] = pastPreg;
        } else {
          _pastPregnancies.add(pastPreg);
        }
        _hasPastPregnancy = true;
      });
    }
  }

  Future<void> _confirmDeletePastPregnancy(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => ConfirmationDialogBox(
        title: 'Remove Pregnancy',
        subtitle: 'Are you sure you want to remove this past pregnancy?',
        confirmText: 'Remove',
        cancelText: 'Cancel',
        accentColor: AppColors.error,
        onConfirm: () => Navigator.pop(dlgCtx, true),
        onCancel: () => Navigator.pop(dlgCtx, false),
      ),
    );
    if (confirm == true) {
      setState(() {
        _pastPregnancies.removeAt(index);
        if (_pastPregnancies.isEmpty) _hasPastPregnancy = false;
      });
    }
  }

  // OCR Methods - Using GroqService
  Future<void> _startOcrFlow() async {
    final source = await _showOcrSourcePicker();
    if (source == null || !mounted) return;

    final file =
        await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (file == null || !mounted) return;

    await _showOcrProcessDialog(file);
  }

  Future<ImageSource?> _showOcrSourcePicker() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Scan Document',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Choose an image source to extract patient data',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Color(0x1AFF68A5),
                  child: Icon(Icons.camera_alt_outlined,
                      color: AppColors.brandPrimary)),
              title: const Text('Camera'),
              subtitle: const Text('Take a photo of the document'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Color(0x1AFF68A5),
                  child: Icon(Icons.photo_library_outlined,
                      color: AppColors.brandPrimary)),
              title: const Text('Gallery'),
              subtitle: const Text('Choose an existing photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showOcrProcessDialog(XFile imageFile) async {
    var dialogState = _OcrDialogState.loading;
    OcrResult? ocrResult;
    String? ocrError;
    StateSetter? setS;

    void startOcr() {
      _groqService.extractMotherRegistrationData(imageFile).then((r) {
        setS?.call(() {
          if (!r.hasAnyValue) {
            ocrError =
                'No recognisable patient data found in the image.\nTry a clearer or higher-quality photo.';
            dialogState = _OcrDialogState.error;
          } else {
            ocrResult = r;
            dialogState = _OcrDialogState.results;
          }
        });
      }).catchError((dynamic e) {
        setS?.call(() {
          ocrError = e.toString().replaceFirst('Exception: ', '');
          dialogState = _OcrDialogState.error;
        });
      });
    }

    startOcr();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateCallback) {
          setS = setStateCallback;
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [AppColors.brandPrimary, Color(0xFFE91E8C)]),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20))),
                  child: Row(
                    children: [
                      Icon(
                          switch (dialogState) {
                            _OcrDialogState.loading =>
                              Icons.cloud_upload_outlined,
                            _OcrDialogState.results =>
                              Icons.check_circle_outline_rounded,
                            _OcrDialogState.error => Icons.error_outline_rounded
                          },
                          color: Colors.white,
                          size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                switch (dialogState) {
                                  _OcrDialogState.loading =>
                                    'Scanning Document...',
                                  _OcrDialogState.results => 'Data Extracted',
                                  _OcrDialogState.error => 'Scan Failed'
                                },
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            Text(
                                switch (dialogState) {
                                  _OcrDialogState.loading =>
                                    'Uploading and analysing with Groq...',
                                  _OcrDialogState.results =>
                                    'Review the extracted fields below',
                                  _OcrDialogState.error =>
                                    'An error occurred during scanning'
                                },
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                      if (dialogState != _OcrDialogState.loading)
                        IconButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            icon: const Icon(Icons.close,
                                color: Colors.white70, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 36)),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: switch (dialogState) {
                      _OcrDialogState.loading => _ocrLoadingBody(imageFile),
                      _OcrDialogState.results => _buildOcrFieldList(ocrResult!),
                      _OcrDialogState.error => _ocrErrorBody(ocrError!),
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  decoration: const BoxDecoration(
                      border: Border(
                          top: BorderSide(color: AppColors.borderPrimary))),
                  child: switch (dialogState) {
                    _OcrDialogState.loading => const SizedBox.shrink(),
                    _OcrDialogState.results => Row(
                        children: [
                          Expanded(
                              child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'))),
                          const SizedBox(width: 12),
                          Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  icon:
                                      const Icon(Icons.check_rounded, size: 16),
                                  label: const Text('Apply to Form'))),
                        ],
                      ),
                    _OcrDialogState.error => Row(
                        children: [
                          Expanded(
                              child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Dismiss'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: ElevatedButton.icon(
                                  onPressed: () {
                                    setStateCallback(() {
                                      dialogState = _OcrDialogState.loading;
                                      ocrError = null;
                                    });
                                    startOcr();
                                  },
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 16),
                                  label: const Text('Retry'))),
                        ],
                      ),
                  },
                ),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed == true && mounted && ocrResult != null) {
      _applyOcrResult(ocrResult!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Form autofilled from scan. Please review & edit as needed.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF4CAF50)));
      }
    }
  }

  Widget _ocrLoadingBody(XFile imageFile) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FutureBuilder<Uint8List>(
              future: imageFile.readAsBytes(),
              builder: (ctx, snap) {
                if (snap.hasData) {
                  return Image.memory(snap.data!,
                      height: 180, width: double.infinity, fit: BoxFit.cover);
                }
                return Container(
                    height: 180,
                    color: AppColors.bgSecondary,
                    child: const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.brandPrimary)));
              },
            ),
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(
              color: AppColors.brandPrimary, strokeWidth: 3),
          const SizedBox(height: 16),
          const Text('Analysing with Groq AI...',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Extracting patient data from the image',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          _ocrStep(number: 1, label: 'Image uploaded', done: true),
          _ocrStep(number: 2, label: 'Groq reading document...', loading: true),
          _ocrStep(number: 3, label: 'Populating form fields'),
        ],
      );

  Widget _ocrStep(
          {required int number,
          required String label,
          bool done = false,
          bool loading = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: done
                  ? const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF4CAF50), size: 20)
                  : loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.brandPrimary))
                      : CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.borderPrimary,
                          child: Text('$number',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary))),
            ),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: (done || loading)
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: loading ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      );

  Widget _ocrErrorBody(String message) => Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 52),
          const SizedBox(height: 12),
          const Text('Scan Failed',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.error)),
          const SizedBox(height: 8),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.2))),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.error))),
          const SizedBox(height: 16),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Tips for better results:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          const SizedBox(height: 6),
          _ocrTip('Ensure the document is well lit'),
          _ocrTip('Keep the camera steady and in focus'),
          _ocrTip('Make sure all text is visible and unobstructed'),
        ],
      );

  Widget _ocrTip(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const Icon(Icons.lightbulb_outline,
                size: 14, color: AppColors.brandAccent),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary))),
          ],
        ),
      );

  Widget _buildOcrFieldList(OcrResult r) {
    final rows = <Widget>[];

    void section(String title) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(_ocrSectionHeader(title));
    }

    void field(String label, String? value) {
      if (value == null) return;
      rows.add(_ocrFieldRow(label, value));
    }

    section('Personal Information');
    field('First Name', r.firstName);
    field('Middle Name', r.middleName);
    field('Last Name', r.lastName);
    field('Extension', r.extensionName);
    field('Phone', r.phone);
    field('Email', r.email);

    section('Address');
    field('House No.', r.houseNumber);
    field('Street', r.street);
    field('Barangay', r.barangay);
    field('City', r.city);
    field('Province', r.province);

    section('Vital Statistics');
    field('Birthdate', r.birthdate);
    field('Height', r.heightCm != null ? '${r.heightCm} cm' : null);
    field('Weight', r.weightKg != null ? '${r.weightKg} kg' : null);
    field('Blood Type', r.bloodType);

    section('Gestational Info');
    field('LMP', r.lmpDate);
    field('EDD', r.eddDate);

    if (r.emergencyContacts.isNotEmpty) {
      section('Emergency Contacts (${r.emergencyContacts.length})');
      for (final c in r.emergencyContacts) {
        rows.add(_ocrFieldRow('${c.firstName} ${c.lastName}',
            '${c.phoneNumber}${c.affiliation != null ? ' · ${c.affiliation}' : ''}'));
      }
    }

    if (r.medicalConditions.isNotEmpty) {
      section('Medical Conditions (${r.medicalConditions.length})');
      for (final m in r.medicalConditions) {
        rows.add(_ocrFieldRow(m.conditionName,
            '${m.status}${m.diagnosisDate != null ? ' · ${m.diagnosisDate}' : ''}'));
      }
    }

    if (r.allergies.isNotEmpty) {
      section('Allergies (${r.allergies.length})');
      for (final a in r.allergies) {
        rows.add(_ocrFieldRow(a.allergen,
            '${a.status}${a.treatment != null ? ' · ${a.treatment}' : ''}'));
      }
    }

    if (r.pastPregnancies.isNotEmpty) {
      section('Past Pregnancies (${r.pastPregnancies.length})');
      for (final p in r.pastPregnancies) {
        final parsedDate = DateTime.tryParse(p.outcomeDate);
        rows.add(_ocrFieldRow(_outcomeLabel(p.outcome),
            parsedDate != null ? _dateFmt.format(parsedDate) : p.outcomeDate));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _ocrSectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(
          children: [
            Container(
                width: 3,
                height: 12,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                    color: AppColors.brandPrimary,
                    borderRadius: BorderRadius.circular(2))),
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2)),
          ],
        ),
      );

  Widget _ocrFieldRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 15, color: Color(0xFF4CAF50)),
            const SizedBox(width: 8),
            SizedBox(
                width: 110,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary))),
          ],
        ),
      );

  void _applyOcrResult(OcrResult r) {
    setState(() {
      if (r.firstName != null) _firstNameCtrl.text = r.firstName!;
      if (r.middleName != null) _middleNameCtrl.text = r.middleName!;
      if (r.lastName != null) _lastNameCtrl.text = r.lastName!;
      if (r.extensionName != null) _selectedExtension = r.extensionName!;
      if (r.phone != null) {
        _phoneCtrl.text = r.phone!;
        _onPhoneChanged();
      }
      if (r.email != null) {
        _emailCtrl.text = r.email!;
        _onEmailChanged(r.email!);
      }

      if (r.houseNumber != null) _houseCtrl.text = r.houseNumber!;
      if (r.street != null) _streetCtrl.text = r.street!;
      if (r.barangay != null) {
        final match = _bhcBarangays
            .where((b) =>
                b.toLowerCase().contains(r.barangay!.toLowerCase()) ||
                r.barangay!.toLowerCase().contains(b.toLowerCase()))
            .firstOrNull;
        if (match != null) {
          _selectedBarangay = match;
          _barangayCtrl.text = match;
          _addressSameAsBhc = false;
        } else {
          _addressSameAsBhc = false;
          _selectedBarangay = null;
          _barangayCtrl.text = r.barangay!;
        }
      }
      if (r.city != null) {
        _cityCtrl.text = r.city!;
        _addressSameAsBhc = false;
      }
      if (r.province != null) {
        _provinceCtrl.text = r.province!;
        _addressSameAsBhc = false;
      }

      if (r.birthdate != null) {
        final parsed = DateTime.tryParse(r.birthdate!);
        if (parsed != null) {
          _birthdate = parsed;
          _birthdateCtrl.text = _dateFmt.format(parsed);
          _validateBirthdate();
        }
      }
      if (r.heightCm != null) _heightCtrl.text = r.heightCm!.toStringAsFixed(1);
      if (r.weightKg != null) _weightCtrl.text = r.weightKg!.toStringAsFixed(1);
      if (r.bloodType != null) {
        _bloodType = r.bloodType;
        _bloodTypeCtrl.text = _bloodType ?? '';
      }

      for (final m in r.medicalConditions) {
        if (m.conditionName.isEmpty) continue;
        final mc = _MedicalCondition(m.conditionName)
          ..status = m.status
          ..remarks = m.remarks;
        if (m.diagnosisDate != null) {
          mc.diagnosisDate = DateTime.tryParse(m.diagnosisDate!);
        }
        _medicalConditions.add(mc);
      }

      for (final a in r.allergies) {
        if (a.allergen.isEmpty) continue;
        final al = _Allergy(a.allergen)
          ..status = a.status
          ..treatment = a.treatment
          ..remarks = a.remarks;
        if (a.diagnosisDate != null) {
          al.diagnosisDate = DateTime.tryParse(a.diagnosisDate!);
        }
        _allergies.add(al);
      }

      for (final ec in r.emergencyContacts) {
        if (ec.firstName.isEmpty ||
            ec.lastName.isEmpty ||
            ec.phoneNumber.isEmpty) {
          continue;
        }
        _emergencyContacts.add(
          _EmergencyContact()
            ..firstName = ec.firstName
            ..middleName = ec.middleName
            ..lastName = ec.lastName
            ..extensionName = ec.extensionName
            ..phoneNumber = ec.phoneNumber
            ..relationship = ec.affiliation,
        );
      }

      for (final p in r.pastPregnancies) {
        if (p.outcomeDate.trim().isEmpty) continue;
        final date = DateTime.tryParse(p.outcomeDate);
        if (date == null) continue;
        final imported = _PastPregnancy()
          ..fetalCount = 1
          ..gestationalAgeAtEnd = p.gestationalAgeAtEnd;
        imported.outcomes.add(
          _PastFetalOutcome(outcome: p.outcome, outcomeDate: date)
            ..isEstimated = p.isEstimated
            ..placeOfDelivery = p.placeOfDelivery
            ..deliveryMethod = p.deliveryMethod,
        );
        _pastPregnancies.add(imported);
        if (_pastPregnancies.isNotEmpty) _hasPastPregnancy = true;
      }

      if (r.lmpDate != null) {
        final lmp = DateTime.tryParse(r.lmpDate!);
        if (lmp != null) _updateFromLmp(lmp);
      } else if (r.eddDate != null) {
        final edd = DateTime.tryParse(r.eddDate!);
        if (edd != null) _updateFromEdd(edd);
      }
    });
    _preloadCitiesAndBarangays();
  }

  String _outcomeLabel(String outcome) {
    switch (outcome) {
      case 'live_birth':
        return 'Live Birth';
      case 'stillbirth':
        return 'Stillbirth';
      case 'miscarriage':
        return 'Miscarriage';
      case 'abortion':
        return 'Abortion';
      case 'ectopic':
        return 'Ectopic';
      default:
        return outcome;
    }
  }

  String _pastPregnancyTitle(_PastPregnancy p) {
    if (p.outcomes.isEmpty) return 'Past Pregnancy';
    final dateText = p.earliestOutcomeDate == p.latestOutcomeDate
        ? _dateFmt.format(p.latestOutcomeDate)
        : '${_dateFmt.format(p.earliestOutcomeDate)} to ${_dateFmt.format(p.latestOutcomeDate)}';
    return dateText;
  }

  String _pastPregnancySubtitle(_PastPregnancy p) {
    if (p.outcomes.isEmpty) return 'No outcomes recorded';
    final outcomeText = p.outcomes
        .asMap()
        .entries
        .map((e) => p.outcomes.length > 1
            ? 'F${e.key + 1}: ${_outcomeLabel(e.value.outcome)}'
            : _outcomeLabel(e.value.outcome))
        .join(' | ');
    final gaText = p.gestationalAgeAtEnd != null
        ? ' - ${p.gestationalAgeAtEnd!.toStringAsFixed(1)} weeks'
        : '';
    return '$outcomeText$gaText';
  }

  // UI Helpers
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

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    VoidCallback? onTap,
    bool readOnly = false,
    Widget? suffixIcon,
    void Function(String)? onChanged,
  }) {
    IconData? trailingIconData;
    if (suffixIcon is Icon) {
      trailingIconData = suffixIcon.icon;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              labelText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.brandPrimary,
              ),
            ),
            if (isRequired)
              const Text(
                ' *',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AppInputField(
          controller: controller,
          hintText: hintText,
          isRequired: false, // Avoid duplicate asterisk inside AppInputField
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          readOnly: readOnly,
          onTap: onTap,
          onChanged: onChanged,
          trailingIcon: trailingIconData,
          onTrailingTap: onTap,
          errorText: errorText,
        ),
      ],
    );
  }

  Widget _styledDropdown(
      {required String hint,
      required String? value,
      required List<String> items,
      List<String>? itemLabels,
      required IconData icon,
      required ValueChanged<String?> onChanged,
      String? errorText}) {
    final labels = itemLabels ?? items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6))
              ]),
          child: Row(
            children: [
              Icon(icon, color: AppColors.brandAccent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: value,
                    style: const TextStyle(
                      color: AppColors.inputText,
                      fontSize: 16,
                    ),
                    hint: Text(hint,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 14)),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down),
                    items: List.generate(
                        items.length,
                        (i) => DropdownMenuItem<String>(
                            value: items[i],
                            child: Text(
                              labels[i],
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.inputText,
                                fontSize: 16,
                              ),
                            ))),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (errorText != null)
          Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Text(errorText,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.error))),
      ],
    );
  }

  bool _isConditionAdded(String name) {
    return _medicalConditions.any((e) => e.conditionName.toLowerCase() == name.toLowerCase());
  }

  bool _isAllergyAdded(String name) {
    return _allergies.any((e) => e.allergen.toLowerCase() == name.toLowerCase());
  }

  int _getConditionIndex(String name) {
    return _medicalConditions.indexWhere((e) => e.conditionName.toLowerCase() == name.toLowerCase());
  }

  int _getAllergyIndex(String name) {
    return _allergies.indexWhere((e) => e.allergen.toLowerCase() == name.toLowerCase());
  }

  Widget _buildPillOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.brandPrimary : AppColors.borderPrimary,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.brandPrimary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.inputText,
          ),
        ),
      ),
    );
  }

  Widget _buildWeightToggleCard({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandPrimary.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.brandPrimary : Colors.black.withValues(alpha: 0.1),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.brandPrimary : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppColors.brandPrimary : AppColors.inputText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              Icon(icon,
                  size: 40,
                  color: AppColors.textSecondary.withValues(alpha: 0.4)),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _iconAvatar(IconData icon, {Color? color}) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: (color ?? AppColors.brandPrimary).withValues(alpha: 0.1),
            shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color ?? AppColors.brandPrimary),
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

  Widget _derivedRow(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Row(
          children: [
            Icon(icon, color: AppColors.brandAccent, size: 17),
            const SizedBox(width: 10),
            Text('$label:',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(value,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade800,
                        fontSize: 14))),
          ],
        ),
      );

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 100,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary))),
            const SizedBox(width: 8),
            Expanded(
                child: Text(value.isEmpty ? '-' : value,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary))),
          ],
        ),
      );

  Widget _bmiTag(double bmi) {
    final String label;
    final Color color;
    if (bmi < 18.5) {
      label = 'Underweight';
      color = AppColors.warning;
    } else if (bmi < 25) {
      label = 'Normal';
      color = const Color(0xFF4CAF50);
    } else if (bmi < 30) {
      label = 'Overweight';
      color = AppColors.warning;
    } else {
      label = 'Obese';
      color = AppColors.error;
    }
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)));
  }

  Widget _buildExtensionDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppInputField(
          controller: TextEditingController(
              text: _selectedExtension.isEmpty ? 'None' : _selectedExtension),
          hintText: 'Extension',
          readOnly: true,
          trailingIcon: Icons.keyboard_arrow_down_rounded,
          onTap: () {
            setState(() {
              _showExtensionDropdown = !_showExtensionDropdown;
            });
          },
        ),
        if (_showExtensionDropdown) ...[
          const SizedBox(height: 4),
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _extensionOptions.length,
                itemBuilder: (context, idx) {
                  final ext = _extensionOptions[idx];
                  return ListTile(
                    title: Text(ext.isEmpty ? 'None' : ext,
                        style: const TextStyle(fontSize: 14)),
                    dense: true,
                    onTap: () {
                      setState(() {
                        _selectedExtension = ext;
                        _showExtensionDropdown = false;
                      });
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepPersonal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Full Name'),
        Row(
          children: [
            Expanded(
                flex: 3,
                child: AppInputField(
                    hintText: 'First Name',
                    controller: _firstNameCtrl,
                    isRequired: true,
                    errorText: _firstNameError,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r"[a-zA-Z\s\-'’]")),
                      LengthLimitingTextInputFormatter(100)
                    ],
                    onChanged: (_) => _validateStepInline(0))),
            const SizedBox(width: 10),
            Expanded(
                flex: 2,
                child: AppInputField(
                    hintText: 'Middle',
                    controller: _middleNameCtrl,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r"[a-zA-Z\s\-'’]")),
                      LengthLimitingTextInputFormatter(100)
                    ])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                flex: 3,
                child: AppInputField(
                    hintText: 'Last Name',
                    controller: _lastNameCtrl,
                    isRequired: true,
                    errorText: _lastNameError,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r"[a-zA-Z\s\-'’]")),
                      LengthLimitingTextInputFormatter(100)
                    ],
                    onChanged: (_) => _validateStepInline(0))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: _buildExtensionDropdown()),
          ],
        ),
        const SizedBox(height: 24),
        _sectionLabel('Birthdate'),
        AppInputField(
          hintText: 'Birthdate',
          controller: _birthdateCtrl,
          isRequired: true,
          leadingIcon: Icons.cake_outlined,
          readOnly: true,
          errorText: _birthdateError,
          onTap: () async {
            final picked = await _showBrandedDatePicker(
                context: context,
                initialDate: _birthdate ?? DateTime(1990),
                firstDate: DateTime(1900),
                lastDate: DateTime.now());
            if (picked != null) {
              setState(() {
                _birthdate = picked;
                _birthdateCtrl.text = _dateFmt.format(picked);
              });
              _validateBirthdate();
            }
          },
        ),
        if (_calculatedAge != null) ...[
          const SizedBox(height: 4),
          Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text('Age: $_calculatedAge years old',
                  style: TextStyle(
                      fontSize: 12,
                      color: _riskWarningColor ?? AppColors.textSecondary))),
        ],
        if (_riskWarning != null) ...[
          const SizedBox(height: 4),
          Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: _riskWarningColor ?? AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(_riskWarning!,
                        style: TextStyle(
                            fontSize: 12,
                            color: _riskWarningColor ?? AppColors.warning)))
              ])),
        ],
        const SizedBox(height: 24),
        _sectionLabel('Contact'),
        AppInputField(
            hintText: 'Phone Number',
            controller: _phoneCtrl,
            isRequired: true,
            leadingIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            errorText: _phoneError,
            onChanged: (_) => _validateStepInline(0)),
        const SizedBox(height: 24),
        _sectionLabel('Account Credentials'),
        if (_calculatedAge == null || _calculatedAge! >= 13) ...[
          AppInputField(
              hintText: 'Email Address (optional)',
              controller: _emailCtrl,
              leadingIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              onChanged: _onEmailChanged,
              errorText: _emailError,
              readOnly: _isEmailReadOnly),
          if (_emailChecking) ...[
            const SizedBox(height: 6),
            Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(children: const [
                  SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.8, color: AppColors.brandAccent)),
                  SizedBox(width: 8),
                  Text('Checking availability...',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary))
                ])),
          ],
          if (_checkingAccount) ...[
            const SizedBox(height: 6),
            Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(children: const [
                  SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.8, color: AppColors.brandAccent)),
                  SizedBox(width: 8),
                  Text('Checking for existing account...',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary))
                ])),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.3))),
            child: Row(
              children: [
                Icon(Icons.email_outlined, color: AppColors.info, size: 20),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                      Text('Password will be auto-generated',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.info)),
                      SizedBox(height: 4),
                      Text(
                          'If email is provided, credentials will be sent. Otherwise, the password will be shown after registration.',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary))
                    ])),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.25))),
            child: Row(
              children: const [
                Icon(Icons.info_outline, color: AppColors.info, size: 20),
                SizedBox(width: 12),
                Expanded(
                    child: Text(
                        'Mothers under 13 are not asked for email. A password will be generated and shown after registration.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<TextSpan> _buildHighlightedTextSpans(String text, String query) {
    final List<TextSpan> spans = [];
    final textLower = text.toLowerCase();
    final queryLower = query.toLowerCase();

    int start = 0;
    int indexOfMatch = textLower.indexOf(queryLower, start);

    while (indexOfMatch != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(
          text: text.substring(start, indexOfMatch),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + query.length),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.brandPrimary,
        ),
      ));
      start = indexOfMatch + query.length;
      indexOfMatch = textLower.indexOf(queryLower, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
      ));
    }

    return spans;
  }

  Widget _buildSearchableAddressField({
    required String hintText,
    required TextEditingController controller,
    required String fieldType, // 'province', 'city', 'barangay', 'street'
    required bool isRequired,
    required IconData leadingIcon,
    required bool readOnly,
    required bool isLoading,
    required String? errorText,
    required Function(String) onSelected,
    required VoidCallback onChanged,
  }) {
    final bool isActive = _activeAddressSearchField == fieldType;

    // Filter items
    List<String> suggestions = [];
    if (fieldType == 'province') {
      suggestions = _apiProvinces;
    } else if (fieldType == 'city') {
      suggestions = _apiCities;
    } else if (fieldType == 'barangay') {
      suggestions = _apiBarangays;
    } else if (fieldType == 'street') {
      suggestions =
          ph_addr.PhAddressService.getStreetsForBarangay(_barangayCtrl.text);
    }

    final query = controller.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final primary = suggestions
          .where((item) => item.toLowerCase().startsWith(query))
          .toList();
      final secondary = suggestions
          .where((item) =>
              item.toLowerCase().contains(query) &&
              !item.toLowerCase().startsWith(query))
          .toList();
      suggestions = [...primary, ...secondary];
    }

    final visibleSuggestions = suggestions.take(15).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          onFocusChange: (focused) {
            if (focused && !readOnly) {
              setState(() {
                _activeAddressSearchField = fieldType;
              });
            } else {
              Future.delayed(const Duration(milliseconds: 250), () {
                if (mounted && _activeAddressSearchField == fieldType) {
                  setState(() {
                    _activeAddressSearchField = null;
                  });
                }
              });
            }
          },
          child: AppInputField(
            hintText: hintText,
            controller: controller,
            isRequired: isRequired,
            leadingIcon: leadingIcon,
            readOnly: readOnly,
            errorText: errorText,
            onChanged: (val) {
              onChanged();
              setState(() {});
            },
          ),
        ),
        if (!readOnly && isActive) ...[
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            constraints: const BoxConstraints(maxHeight: 220),
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.cardColorOf(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.brandPrimaryOf(context).withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.brandPrimaryOf(context),
                          ),
                        ),
                      ),
                    ),
                  )
                : visibleSuggestions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        child: Text(
                          query.isEmpty
                              ? 'Start typing to search...'
                              : 'No matches found. You can keep typing.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondaryOf(context),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : Scrollbar(
                        controller: _streetSuggestionController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _streetSuggestionController,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: visibleSuggestions.length,
                          itemBuilder: (context, index) {
                            final item = visibleSuggestions[index];
                            final bool startsWithQuery = query.isNotEmpty &&
                                item.toLowerCase().startsWith(query);

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  onSelected(item);
                                  FocusScope.of(context).unfocus();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        startsWithQuery
                                            ? Icons.arrow_right_alt
                                            : Icons.location_on_outlined,
                                        size: 16,
                                        color: startsWithQuery
                                            ? AppColors.brandPrimaryOf(context)
                                            : AppColors.textSecondaryOf(
                                                context,
                                              ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: AppColors.textPrimaryOf(
                                                context,
                                              ),
                                            ),
                                            children: query.isEmpty
                                                ? [TextSpan(text: item)]
                                                : _buildHighlightedTextSpans(
                                                    item,
                                                    query,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _stepAddress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgSecondaryOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.home_work_outlined,
                color: AppColors.brandAccent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Assigned BHC: ${_bhcName.isEmpty ? '-' : _bhcName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionLabel('Address Type'),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSecondaryOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _addressSameAsBhc
                  ? AppColors.brandPrimaryOf(context)
                  : AppColors.borderOf(context),
              width: 1.5,
            ),
          ),
          child: InkWell(
            onTap: () {
              setState(() {
                _addressSameAsBhc = !_addressSameAsBhc;
                if (_addressSameAsBhc) {
                  _applyBhcAddress();
                } else {
                  _selectedBarangay = null;
                  _barangayCtrl.clear();
                  _cityCtrl.clear();
                  _provinceCtrl.clear();
                }
                _validateStepInline(1);
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Checkbox(
                    value: _addressSameAsBhc,
                    onChanged: (val) {
                      setState(() {
                        _addressSameAsBhc = val ?? false;
                        if (_addressSameAsBhc) {
                          _applyBhcAddress();
                        } else {
                          _selectedBarangay = null;
                          _barangayCtrl.clear();
                          _cityCtrl.clear();
                          _provinceCtrl.clear();
                        }
                        _validateStepInline(1);
                      });
                    },
                    activeColor: AppColors.brandPrimaryOf(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Same as BHC address',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bulacan - Baliwag - ${_bhcName.isEmpty ? 'Assigned barangay' : _bhcName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel('Address Details'),
        AppInputField(
          hintText: 'House No.',
          controller: _houseCtrl,
          isRequired: true,
          leadingIcon: Icons.home_outlined,
          errorText: _houseError,
          onChanged: (_) => _validateStepInline(1),
        ),
        const SizedBox(height: 12),
        _buildSearchableAddressField(
          hintText: 'Street',
          controller: _streetCtrl,
          fieldType: 'street',
          isRequired: true,
          leadingIcon: Icons.streetview_outlined,
          readOnly: false,
          isLoading: false,
          errorText: _streetError,
          onSelected: (val) {
            setState(() {
              _streetCtrl.text = val;
            });
            _validateStepInline(1);
          },
          onChanged: () => _validateStepInline(1),
        ),
        const SizedBox(height: 12),
        _buildSearchableAddressField(
          hintText: 'Province',
          controller: _provinceCtrl,
          fieldType: 'province',
          isRequired: true,
          leadingIcon: Icons.map_outlined,
          readOnly: _addressSameAsBhc,
          isLoading: _loadingProvinces,
          errorText: _provinceError,
          onSelected: (val) {
            _onProvinceSelected(val);
          },
          onChanged: () {
            _cityCtrl.clear();
            _barangayCtrl.clear();
            _streetCtrl.clear();
            _selectedBarangay = null;
            _validateStepInline(1);
          },
        ),
        const SizedBox(height: 12),
        _buildSearchableAddressField(
          hintText: 'City / Municipality',
          controller: _cityCtrl,
          fieldType: 'city',
          isRequired: true,
          leadingIcon: Icons.location_city_outlined,
          readOnly: _addressSameAsBhc || _provinceCtrl.text.isEmpty,
          isLoading: _loadingCities,
          errorText: _cityError,
          onSelected: (val) {
            _onCitySelected(val);
          },
          onChanged: () {
            _barangayCtrl.clear();
            _streetCtrl.clear();
            _selectedBarangay = null;
            _validateStepInline(1);
          },
        ),
        const SizedBox(height: 12),
        _buildSearchableAddressField(
          hintText: 'Barangay',
          controller: _barangayCtrl,
          fieldType: 'barangay',
          isRequired: true,
          leadingIcon: Icons.location_on_outlined,
          readOnly: _addressSameAsBhc || _cityCtrl.text.isEmpty,
          isLoading: _loadingBarangays,
          errorText: _barangayError,
          onSelected: (val) {
            _onBarangaySelected(val);
          },
          onChanged: () {
            _selectedBarangay = _barangayCtrl.text.trim();
            _validateStepInline(1);
          },
        ),
      ],
    );
  }

  Widget _stepEmergencyContacts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Emergency Contacts'),
        const SizedBox(height: 16),
        if (_emergencyContacts.isEmpty)
          _emptyState(Icons.contacts_outlined,
              'No emergency contacts added.\nClick the add button to add one.')
        else
          ..._emergencyContacts.asMap().entries.map((e) => _itemCard(
              leading: _iconAvatar(Icons.person_outline),
              title: '${e.value.firstName} ${e.value.lastName}',
              subtitle:
                  '${e.value.phoneNumber} - ${e.value.relationship ?? "No relationship"}',
              onEdit: () => _showAddEmergencyContact(editIndex: e.key),
              onDelete: () => _confirmDeleteEmergencyContact(e.key))),
      ],
    );
  }

  Widget _stepVitals() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Body Measurements'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppInputField(
                hintText: 'Height (cm)',
                controller: _heightCtrl,
                isRequired: true,
                leadingIcon: Icons.straighten_outlined,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  LengthLimitingTextInputFormatter(5)
                ],
                errorText: _heightError,
                onChanged: (_) => _validateStepInline(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppInputField(
                hintText: 'Weight (kg)',
                controller: _weightCtrl,
                isRequired: true,
                leadingIcon: Icons.monitor_weight_outlined,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  LengthLimitingTextInputFormatter(5)
                ],
                errorText: _weightError,
                onChanged: (_) => _validateStepInline(4),
              ),
            ),
          ],
        ),
        if (_heightWarning != null || _weightWarning != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _heightWarning ?? _weightWarning!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        _sectionLabel('Pre-Pregnancy Weight'),
        IntrinsicHeight(
            child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _knowsPrePregnancyWeight = true;
                    _calculateBMI();
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: _knowsPrePregnancyWeight
                        ? AppColors.brandPrimary.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _knowsPrePregnancyWeight
                          ? AppColors.brandPrimary
                          : AppColors.borderPrimary,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _knowsPrePregnancyWeight
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: _knowsPrePregnancyWeight
                            ? AppColors.brandPrimary
                            : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Mother knows pre-pregnancy weight',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _knowsPrePregnancyWeight = false;
                    _prePregnancyWeightCtrl.clear();
                    _prePregnancyWeightError = null;
                    _calculateBMI();
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: !_knowsPrePregnancyWeight
                        ? AppColors.brandPrimary.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: !_knowsPrePregnancyWeight
                          ? AppColors.brandPrimary
                          : AppColors.borderPrimary,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        !_knowsPrePregnancyWeight
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: !_knowsPrePregnancyWeight
                            ? AppColors.brandPrimary
                            : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Mother does not know pre-pregnancy weight',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        )),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Knowing pre-pregnancy weight helps accurately calculate the mother\'s pre-pregnancy BMI to determine correct weekly weight gain guidelines and monitor healthy fetal development.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ),
        if (_knowsPrePregnancyWeight) ...[
          const SizedBox(height: 20),
          AppInputField(
            hintText: 'Weight before pregnancy (kg)',
            controller: _prePregnancyWeightCtrl,
            isRequired: true,
            leadingIcon: Icons.monitor_weight_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              LengthLimitingTextInputFormatter(5)
            ],
            errorText: _prePregnancyWeightError,
            onChanged: (_) => _validateStepInline(4),
          ),
          if (_prePregnancyWeightWarning != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _prePregnancyWeightWarning!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_calculatedBMI != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderPrimary),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Pre-Pregnancy BMI: ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _calculatedBMI!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brandText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _bmiTag(_calculatedBMI!),
                    ],
                  ),
                  if (_bmiWarning != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color:
                              (_calculatedBMI! >= 25 || _calculatedBMI! < 18.5)
                                  ? AppColors.warning
                                  : AppColors.brandPrimary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _bmiWarning!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: (_calculatedBMI! >= 25 ||
                                      _calculatedBMI! < 18.5)
                                  ? AppColors.warning
                                  : AppColors.brandPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 24),
        _sectionLabel('Blood Type'),
        AppInputField(
          hintText: 'Select Blood Type',
          controller: _bloodTypeCtrl,
          isRequired: false,
          leadingIcon: Icons.bloodtype_outlined,
          trailingIcon: Icons.keyboard_arrow_down_rounded,
          readOnly: true,
          onTap: () {
            setState(() {
              _showBloodTypeDropdown = !_showBloodTypeDropdown;
            });
          },
        ),
        if (_showBloodTypeDropdown) ...[
          const SizedBox(height: 4),
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _bloodTypeOptions.length,
                itemBuilder: (context, idx) {
                  final bt = _bloodTypeOptions[idx];
                  return ListTile(
                    title: Text(bt, style: const TextStyle(fontSize: 14)),
                    dense: true,
                    onTap: () {
                      setState(() {
                        _bloodType = bt;
                        _bloodTypeCtrl.text = bt;
                        _showBloodTypeDropdown = false;
                      });
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepMedicalConditions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (_medicalConditions.isEmpty)
          _emptyState(Icons.medical_services_outlined,
              'No medical conditions added.\nClick the add button to add one.')
        else
          ..._medicalConditions.asMap().entries.map((e) => _itemCard(
              leading: _iconAvatar(Icons.medical_services_outlined),
              title: e.value.conditionName,
              subtitle:
                  '${e.value.status[0].toUpperCase()}${e.value.status.substring(1)} - ${e.value.diagnosisDate != null ? DateFormat('MMM d, yyyy').format(e.value.diagnosisDate!) : 'Date not set'}',
              onEdit: () => _showAddMedicalCondition(editIndex: e.key),
              onDelete: () => _confirmDeleteMedicalCondition(e.key))),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _stepAllergies() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Quick Add - Common Allergens'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _commonAllergens.map((allergen) {
            final isAdded = _isAllergyAdded(allergen);
            return _buildPillOption(
              label: allergen,
              isSelected: isAdded,
              onTap: () {
                if (isAdded) {
                  final idx = _getAllergyIndex(allergen);
                  if (idx != -1) {
                    _confirmDeleteAllergy(idx);
                  }
                } else {
                  _showAddAllergy(prefill: allergen == 'Other' ? null : allergen);
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        _sectionLabel('Allergies List'),
        const SizedBox(height: 16),
        if (_allergies.isEmpty)
          _emptyState(Icons.no_food_outlined,
              'No allergies recorded.\nClick the add button to add one.')
        else
          ..._allergies.asMap().entries.map((e) => _itemCard(
              leading: _iconAvatar(Icons.warning_amber_rounded,
                  color: AppColors.warning),
              title: e.value.allergen,
              subtitle:
                  '${e.value.status[0].toUpperCase()}${e.value.status.substring(1)} - ${e.value.diagnosisDate != null ? DateFormat('MMM d, yyyy').format(e.value.diagnosisDate!) : 'Date not set'}',
              onEdit: () => _showAddAllergy(editIndex: e.key),
              onDelete: () => _confirmDeleteAllergy(e.key))),
      ],
    );
  }

  Widget _stepPregnancyHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pastPregnancies.isEmpty)
          Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]),
            child: SwitchListTile(
                title: const Text('Had previous pregnancies?',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Toggle on to log past pregnancy records'),
                value: _hasPastPregnancy,
                activeThumbColor: AppColors.brandPrimary,
                activeTrackColor: AppColors.brandPrimary.withValues(alpha: 0.5),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.shade200,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                onChanged: (v) => setState(() {
                      _hasPastPregnancy = v;
                      if (!v) _pastPregnancies.clear();
                    })),
          ),
        if (_hasPastPregnancy) ...[
          if (_pastPregnancies.isEmpty) const SizedBox(height: 16),
          if (_pastPregnancies.isEmpty)
            _emptyState(Icons.history_outlined,
                'No past pregnancies recorded.\nClick the add button to add one.')
          else
            ..._pastPregnancies.asMap().entries.map((e) {
              final p = e.value;
              return _itemCard(
                  leading: _iconAvatar(Icons.pregnant_woman_outlined),
                  title: _pastPregnancyTitle(p),
                  subtitle: _pastPregnancySubtitle(p),
                  onEdit: () => _showAddPastPregnancy(editIndex: e.key),
                  onDelete: () => _confirmDeletePastPregnancy(e.key));
            }),
        ],
      ],
    );
  }

  Widget _stepGestational() {
    const methodItems = ['lmp', 'edd', 'aog'];
    const methodLabels = [
      'Last Menstrual Period (LMP)',
      'Estimated Delivery Date (EDD)',
      'Age of Gestation (AOG)'
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Calculation Method'),
        AppInputField(
          hintText: 'Select method',
          controller: _gestationMethodCtrl,
          isRequired: false,
          leadingIcon: Icons.calculate_outlined,
          trailingIcon: Icons.keyboard_arrow_down_rounded,
          readOnly: true,
          onTap: () {
            setState(() {
              _showGestationMethodDropdown = !_showGestationMethodDropdown;
            });
          },
        ),
        if (_showGestationMethodDropdown) ...[
          const SizedBox(height: 4),
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: methodItems.length,
                itemBuilder: (context, idx) {
                  final v = methodItems[idx];
                  final label = methodLabels[idx];
                  return ListTile(
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    dense: true,
                    onTap: () {
                      setState(() {
                        _gestationMethod = _GestationMethod.values
                            .firstWhere((e) => e.name == v);
                        _gestationMethodCtrl.text = label;
                        _showGestationMethodDropdown = false;
                        _gestationError = null;
                        _weeksError = null;
                        _daysError = null;
                      });
                    },
                  );
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _sectionLabel('Date Entry'),
        if (_gestationMethod == _GestationMethod.lmp)
          GestureDetector(
              onTap: () async {
                final lastLmpDate =
                    DateTime.now().subtract(const Duration(days: 5 * 7));
                final initialLmpDate =
                    (_lmp != null && !_lmp!.isAfter(lastLmpDate))
                        ? _lmp!
                        : lastLmpDate;
                final picked = await _showBrandedDatePicker(
                    context: context,
                    initialDate: initialLmpDate,
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 42 * 7)),
                    lastDate: lastLmpDate);
                if (picked != null) {
                  setState(() => _updateFromLmp(picked));
                  _validateStepInline(3);
                }
              },
              child: AppInputField(
                  hintText: 'Last Menstrual Period',
                  controller: _lmpCtrl,
                  isRequired: true,
                  leadingIcon: Icons.calendar_today_outlined,
                  readOnly: true,
                  errorText: _gestationError))
        else if (_gestationMethod == _GestationMethod.edd)
          GestureDetector(
              onTap: () async {
                final picked = await _showBrandedDatePicker(
                    context: context,
                    initialDate: _edd ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 43 * 7)));
                if (picked != null) {
                  setState(() => _updateFromEdd(picked));
                  _validateStepInline(3);
                }
              },
              child: AppInputField(
                  hintText: 'Estimated Delivery Date',
                  controller: _eddCtrl,
                  isRequired: true,
                  leadingIcon: Icons.event_available_outlined,
                  readOnly: true,
                  errorText: _gestationError))
        else ...[
          Row(children: [
            Expanded(
                child: AppInputField(
                    hintText: 'Weeks',
                    controller: _aogWeeksCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    errorText: _weeksError,
                    onChanged: (_) {
                      _updateFromAog();
                      _validateStepInline(3);
                    })),
            const SizedBox(width: 12),
            Expanded(
                child: AppInputField(
                    hintText: 'Days',
                    controller: _aogDaysCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    errorText: _daysError,
                    onChanged: (_) {
                      _updateFromAog();
                      _validateStepInline(3);
                    }))
          ]),
          if (_gestationError != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                _gestationError!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          ]
        ],
        const SizedBox(height: 20),
        _sectionLabel('Computed Values'),
        _derivedRow(Icons.calendar_today_outlined, 'LMP',
            _lmpCtrl.text.isEmpty ? '-' : _lmpCtrl.text),
        const SizedBox(height: 8),
        _derivedRow(Icons.event_available_outlined, 'EDD',
            _eddCtrl.text.isEmpty ? '-' : _eddCtrl.text),
        const SizedBox(height: 8),
        _derivedRow(Icons.timer_outlined, 'AOG', _formatAog()),
      ],
    );
  }

  Widget _stepSummary() {
    final fullName = [
      _firstNameCtrl.text.trim(),
      if (_middleNameCtrl.text.trim().isNotEmpty)
        '${_middleNameCtrl.text.trim()[0]}.',
      _lastNameCtrl.text.trim(),
      if (_selectedExtension.isNotEmpty) _selectedExtension
    ].join(' ');
    final address = [
      if (_houseCtrl.text.trim().isNotEmpty) _houseCtrl.text.trim(),
      if (_streetCtrl.text.trim().isNotEmpty) _streetCtrl.text.trim(),
      if (_selectedBarangay != null) _selectedBarangay!,
      if (_cityCtrl.text.trim().isNotEmpty) _cityCtrl.text.trim(),
      if (_provinceCtrl.text.trim().isNotEmpty) _provinceCtrl.text.trim()
    ].join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderPrimary)),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.brandAccent),
              SizedBox(width: 8),
              Expanded(
                  child: Text('Tap on any field below to edit it directly.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)))
            ])),
        const SizedBox(height: 20),
        Builder(
          builder: (context) {
            final riskFactors = _evaluatePregnancyRisk();
            final insights = _evaluateMonitoringInsights();
            final isHighRisk = riskFactors.isNotEmpty;
            return Column(
              children: [
                // ── Tier 1: Official DOH Risk Assessment ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isHighRisk
                        ? AppColors.error.withValues(alpha: 0.05)
                        : AppColors.success.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color:
                            isHighRisk ? AppColors.error : AppColors.success),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isHighRisk
                                ? Icons.warning_rounded
                                : Icons.check_circle_rounded,
                            color: isHighRisk
                                ? AppColors.error
                                : AppColors.success,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Pregnancy Risk Assessment',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isHighRisk
                                  ? AppColors.error
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 28),
                        child: Text(
                          'Based on DOH/PhilHealth Annex P criteria',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'Status: ',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textSecondary),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: isHighRisk
                                  ? AppColors.error
                                  : AppColors.success,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isHighRisk ? 'HIGH RISK' : 'LOW RISK',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isHighRisk) ...[
                        const SizedBox(height: 14),
                        Divider(
                            color: AppColors.error.withValues(alpha: 0.15),
                            height: 1),
                        const SizedBox(height: 14),
                        const Text('Identified Risk Factors:',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 8),
                        ...riskFactors.map((f) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 5, right: 8),
                                    child: Icon(Icons.circle,
                                        size: 5, color: AppColors.error),
                                  ),
                                  Expanded(
                                      child: Text(f,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textPrimary))),
                                ],
                              ),
                            )),
                      ],
                      if (!isHighRisk) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 0),
                          child: Text(
                            'No official DOH risk factors were identified based on the information provided.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // ── Tier 2: Monitoring Insights (amber, non-risk) ──
                if (insights.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.visibility_outlined,
                                size: 18, color: AppColors.warning),
                            const SizedBox(width: 8),
                            Text(
                              'Monitoring Insights',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...insights.map((i) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 5, right: 8),
                                    child: Icon(Icons.circle,
                                        size: 4, color: AppColors.warning),
                                  ),
                                  Expanded(
                                      child: Text(i,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700))),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            );
          },
        ),
        _buildClickableSummarySection(
            'Personal Information',
            [
              _summaryRow('Full Name', fullName.isEmpty ? '-' : fullName),
              _summaryRow('Birthdate',
                  _birthdate != null ? _dateFmt.format(_birthdate!) : '-'),
              _summaryRow('Age',
                  _calculatedAge != null ? '$_calculatedAge years' : '-'),
              _summaryRow(
                  'Phone',
                  _phoneCtrl.text.trim().isEmpty
                      ? '-'
                      : _phoneCtrl.text.trim()),
              _summaryRow('Email',
                  _emailCtrl.text.trim().isEmpty ? '-' : _emailCtrl.text.trim())
            ],
            onTap: () => _jumpToStep(0)),
        const SizedBox(height: 12),
        _buildClickableSummarySection('Address',
            [_summaryRow('Full Address', address.isEmpty ? '-' : address)],
            onTap: () => _jumpToStep(1)),
        const SizedBox(height: 12),
        _buildClickableSummarySection(
            'Vital Statistics',
            [
              _summaryRow('Height / Weight',
                  '${_heightCtrl.text.trim().isEmpty ? '-' : _heightCtrl.text.trim()} cm / ${_weightCtrl.text.trim().isEmpty ? '-' : _weightCtrl.text.trim()} kg'),
              if (_knowsPrePregnancyWeight) ...[
                _summaryRow(
                    'Pre-Pregnancy Weight',
                    _prePregnancyWeightCtrl.text.trim().isEmpty
                        ? 'Not provided'
                        : '${_prePregnancyWeightCtrl.text.trim()} kg'),
                _summaryRow(
                    'BMI',
                    _calculatedBMI != null
                        ? '${_calculatedBMI!.toStringAsFixed(1)} ($_bmiClassification)'
                        : '-'),
              ],
              _summaryRow('Blood Type', _bloodType ?? '-')
            ],
            onTap: () => _jumpToStep(4)),
        const SizedBox(height: 12),
        _buildClickableSummarySection(
            'Gestational Information',
            [
              _summaryRow('LMP', _lmp != null ? _dateFmt.format(_lmp!) : '-'),
              _summaryRow('EDD', _edd != null ? _dateFmt.format(_edd!) : '-'),
              _summaryRow('AOG', _formatAog()),
            ],
            onTap: () => _jumpToStep(3)),
        const SizedBox(height: 12),
        _buildExpandableRecordsSection(
            'Emergency Contacts',
            _emergencyContacts
                .map((c) =>
                    '${c.firstName} ${c.lastName} - ${c.phoneNumber} (${c.relationship ?? "No relationship"})')
                .toList(),
            onTap: () => _jumpToStep(2)),
        const SizedBox(height: 12),
        _buildExpandableRecordsSection(
            'Medical Conditions',
            _medicalConditions
                .map((c) => '${c.conditionName} (${c.status})')
                .toList(),
            onTap: () => _jumpToStep(5)),
        const SizedBox(height: 12),
        _buildExpandableRecordsSection('Allergies',
            _allergies.map((a) => '${a.allergen} (${a.status})').toList(),
            onTap: () => _jumpToStep(6)),
        const SizedBox(height: 12),
        _buildExpandableRecordsSection('Past Pregnancies',
            _pastPregnancies.map((p) => _pastPregnancyTitle(p)).toList(),
            onTap: () => _jumpToStep(7)),
      ],
    );
  }

  Widget _buildClickableSummarySection(String title, List<Widget> rows,
      {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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

  Widget _buildExpandableRecordsSection(String title, List<String> items,
      {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
              child: items.isEmpty
                  ? const Text('No records added',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary))
                  : Column(
                      children: items
                          .map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(children: [
                                Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                        color: AppColors.brandPrimary,
                                        shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(item,
                                        style: const TextStyle(fontSize: 13)))
                              ])))
                          .toList()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _stepPersonal();
      case 1:
        return _stepAddress();
      case 2:
        return _stepEmergencyContacts();
      case 3:
        return _stepGestational();
      case 4:
        return _stepVitals();
      case 5:
        return _stepMedicalConditions();
      case 6:
        return _stepAllergies();
      case 7:
        return _stepPregnancyHistory();
      default:
        return _stepSummary();
    }
  }

  Widget? _buildFloatingActionButton() {
    if (_submitting) return null;

    if (_step == 2) {
      return FloatingActionButton(
        onPressed: _showAddEmergencyContact,
        backgroundColor: AppColors.brandPrimary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      );
    } else if (_step == 5) {
      return FloatingActionButton(
        onPressed: () => _showAddMedicalCondition(),
        backgroundColor: AppColors.brandPrimary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      );
    } else if (_step == 6) {
      return FloatingActionButton(
        onPressed: _showAddAllergy,
        backgroundColor: AppColors.brandPrimary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      );
    } else if (_step == 7 && _hasPastPregnancy) {
      return FloatingActionButton(
        onPressed: _showAddPastPregnancy,
        backgroundColor: AppColors.brandPrimary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingContext) {
      return const Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.brandPrimary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SecondaryHeader(
              title: 'Add Mother',
              onBack: () => Navigator.pop(context),
              trailing: TextButton.icon(
                onPressed: _startOcrFlow,
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text('Scan'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandPrimary,
                ),
              ),
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
                  Text(_stepTitles[_step],
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brandText)),
                  const SizedBox(height: 4),
                  Text(_stepSubtitles[_step],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _totalSteps,
                itemBuilder: (_, i) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: _buildStepContent(),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
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
                      onPressed: _submitting ? null : _goBack,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: _step < _totalSteps - 1
                      ? MainButton(
                          label: 'Next',
                          rightIcon: Icons.arrow_forward_ios_rounded,
                          onPressed: _submitting ? null : _goNext,
                        )
                      : MainButton(
                          label: _submitting ? 'Saving...' : 'Finalize & Save',
                          rightIcon: _submitting ? null : Icons.check_rounded,
                          onPressed: _submitting ? null : _submit,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const List<String> _stepTitles = [
    'Personal Information',
    'Address Information',
    'Emergency Contacts',
    'Gestational Information',
    'Vital Statistics',
    'Medical Conditions',
    'Allergies',
    'Pregnancy History',
    'Summary & Submit',
  ];

  static const List<String> _stepSubtitles = [
    'Name, birthdate, phone, email and login credentials',
    'Current place of residence',
    'Who to contact in an emergency',
    'Current pregnancy dating',
    'Height, weight and blood type',
    'Known diagnoses and health conditions',
    'Known allergens and reactions',
    'Previous pregnancy outcomes',
    'Review before saving',
  ];
}
