// lib/models/add_mother_form_data.dart

class MidwifeContext {
  int? midwifeId;
  int? assignedBhcId;
  String? assignedBhcName;

  MidwifeContext();
}

class EmergencyContact {
  String? firstName;
  String? middleName;
  String? lastName;
  String? extensionName;
  String? phoneNumber;
  String? affiliation;

  bool get isValid =>
      (firstName?.isNotEmpty ?? false) &&
      (lastName?.isNotEmpty ?? false) &&
      (phoneNumber?.isNotEmpty ?? false);

  Map<String, dynamic> toMap() => {
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'extension_name': extensionName,
        'phone_number': phoneNumber,
        'affiliation': affiliation,
      };
}

class MedicalConditionEntry {
  String conditionName;
  DateTime? diagnosisDate;
  String status; // 'active' or 'resolved'
  String? remarks;

  MedicalConditionEntry({required this.conditionName, this.status = 'active'});

  Map<String, dynamic> toMap() => {
        'condition_name': conditionName,
        'diagnosis_date': diagnosisDate?.toIso8601String().split('T')[0],
        'status': status,
        'remarks': remarks,
      };
}

class AllergyEntry {
  String allergen;
  DateTime? diagnosisDate;
  String status; // 'active' or 'resolved'
  String? treatment;
  String? remarks;

  AllergyEntry({required this.allergen, this.status = 'active'});

  Map<String, dynamic> toMap() => {
        'allergen': allergen,
        'diagnosis_date': diagnosisDate?.toIso8601String().split('T')[0],
        'status': status,
        'treatment': treatment,
        'remarks': remarks,
      };
}

class PregnancyHistoryEntry {
  String outcome; // live_birth, stillbirth, miscarriage, abortion, ectopic
  DateTime outcomeDate;
  bool isOutcomeDateEstimated;
  double? gestationalAgeAtEnd;
  String? placeOfDelivery;
  String? deliveryMethod;

  PregnancyHistoryEntry({
    required this.outcome,
    required this.outcomeDate,
    this.isOutcomeDateEstimated = false,
  });

  Map<String, dynamic> toMap() => {
        'outcome': outcome,
        'outcome_date': outcomeDate.toIso8601String().split('T')[0],
        'is_outcome_date_estimated': isOutcomeDateEstimated,
        'gestational_age_at_end': gestationalAgeAtEnd,
        'place_of_delivery': placeOfDelivery,
        'delivery_method': deliveryMethod,
      };
}

class AddMotherFormData {
  // Context
  final MidwifeContext context = MidwifeContext();

  // Personal Info
  String? firstName;
  String? middleName;
  String? lastName;
  String? extensionName;
  String? phone;
  String? email;

  // Address
  bool addressSameAsBhc = true;
  String? houseNumber;
  String? street;
  String? barangay;
  String? city;
  String? province;

  // Vitals
  DateTime? birthdate;
  double? heightCm;
  double? weightKg;
  String? bloodType;

  // Lists
  final List<EmergencyContact> emergencyContacts = [];
  final List<MedicalConditionEntry> medicalConditions = [];
  final List<AllergyEntry> allergies = [];
  bool hasPastPregnancy = false;
  final List<PregnancyHistoryEntry> pregnancyHistory = [];

  // Gestation
  DateTime? lmp;
  DateTime? edd;

  int? get ageYears {
    if (birthdate == null) return null;
    return DateTime.now().difference(birthdate!).inDays ~/ 365;
  }

  double? get bmi {
    if (heightCm == null || weightKg == null || heightCm! <= 0) return null;
    final heightM = heightCm! / 100;
    return weightKg! / (heightM * heightM);
  }

  Map<String, dynamic> toPayload({
    required String pregnancyRiskLevel,
    bool includeFirstPrenatal = false,
  }) {
    final Map<String, dynamic> payload = {
      'midwife_id': context.midwifeId,
      'assigned_bhc_id': context.assignedBhcId,
      'personal': {
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'extension_name': extensionName,
        'phone_number': phone,
        'email_address': email,
      },
      'address': {
        'house_number': houseNumber,
        'street': street,
        'barangay': addressSameAsBhc ? context.assignedBhcName : barangay,
        'city_municipality': addressSameAsBhc ? 'Baliwag' : city,
        'province': addressSameAsBhc ? 'Bulacan' : province,
      },
      'vitals': {
        'birthdate': birthdate?.toIso8601String().split('T')[0],
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'blood_type': bloodType,
      },
      'emergency_contacts': emergencyContacts.map((e) => e.toMap()).toList(),
      'medical_conditions': medicalConditions.map((m) => m.toMap()).toList(),
      'allergies': allergies.map((a) => a.toMap()).toList(),
      'pregnancy_history': pregnancyHistory.map((p) => p.toMap()).toList(),
      'current_pregnancy': {
        'lmp': lmp?.toIso8601String().split('T')[0],
        'edd': edd?.toIso8601String().split('T')[0],
        'risk_level': pregnancyRiskLevel,
      },
    };
    
    if (includeFirstPrenatal) {
      payload['first_prenatal'] = {
        // Will be populated by the prenatal screen
      };
    }
    
    return payload;
  }
}