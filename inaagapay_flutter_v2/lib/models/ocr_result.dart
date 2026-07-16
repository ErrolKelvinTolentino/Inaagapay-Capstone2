// lib/models/ocr_result.dart

// Model returned by OCR for autofilling the Add Mother form.
// All fields are nullable — only fields visible in the document are populated.

class OcrEmergencyContact {
  String firstName;
  String? middleName;
  String lastName;
  String? extensionName;
  String phoneNumber;
  String? affiliation;

  OcrEmergencyContact({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    this.middleName,
    this.extensionName,
    this.affiliation,
  });

  factory OcrEmergencyContact.fromJson(Map<String, dynamic> j) =>
      OcrEmergencyContact(
        firstName: (j['first_name'] as String? ?? '').trim(),
        middleName: _nonEmpty(j['middle_name']),
        lastName: (j['last_name'] as String? ?? '').trim(),
        extensionName: _nonEmpty(j['extension_name']),
        phoneNumber: (j['phone_number'] as String? ?? '').trim(),
        affiliation: _nonEmpty(j['affiliation']),
      );
}

class OcrMedicalCondition {
  String conditionName;
  String? diagnosisDate; // ISO date string yyyy-MM-dd
  String status; // 'active' | 'resolved'
  String? remarks;

  OcrMedicalCondition({
    required this.conditionName,
    this.diagnosisDate,
    this.status = 'active',
    this.remarks,
  });

  factory OcrMedicalCondition.fromJson(Map<String, dynamic> j) =>
      OcrMedicalCondition(
        conditionName: (j['condition_name'] as String? ?? '').trim(),
        diagnosisDate: _nonEmpty(j['diagnosis_date']),
        status: (j['status'] as String? ?? 'active').trim(),
        remarks: _nonEmpty(j['remarks']),
      );
}

class OcrAllergy {
  String allergen;
  String? diagnosisDate;
  String status;
  String? treatment;
  String? remarks;

  OcrAllergy({
    required this.allergen,
    this.diagnosisDate,
    this.status = 'active',
    this.treatment,
    this.remarks,
  });

  factory OcrAllergy.fromJson(Map<String, dynamic> j) => OcrAllergy(
        allergen: (j['allergen'] as String? ?? '').trim(),
        diagnosisDate: _nonEmpty(j['diagnosis_date']),
        status: (j['status'] as String? ?? 'active').trim(),
        treatment: _nonEmpty(j['treatment']),
        remarks: _nonEmpty(j['remarks']),
      );
}

class OcrPastPregnancy {
  String outcome; // live_birth | stillbirth | miscarriage | abortion | ectopic
  String outcomeDate; // ISO date yyyy-MM-dd
  bool isEstimated;
  double? gestationalAgeAtEnd;
  String? placeOfDelivery;
  String? deliveryMethod;

  OcrPastPregnancy({
    required this.outcome,
    required this.outcomeDate,
    this.isEstimated = false,
    this.gestationalAgeAtEnd,
    this.placeOfDelivery,
    this.deliveryMethod,
  });

  factory OcrPastPregnancy.fromJson(Map<String, dynamic> j) => OcrPastPregnancy(
        outcome: (j['outcome'] as String? ?? 'live_birth').trim(),
        outcomeDate: (j['outcome_date'] as String? ?? '').trim(),
        isEstimated: j['is_estimated'] == true,
        gestationalAgeAtEnd: (j['gestational_age_at_end'] as num?)?.toDouble(),
        placeOfDelivery: _nonEmpty(j['place_of_delivery']),
        deliveryMethod: _nonEmpty(j['delivery_method']),
      );
}

class OcrResult {
  // Step 0 — Personal & Credentials
  String? firstName;
  String? middleName;
  String? lastName;
  String? extensionName;
  String? phone;
  String? email;

  // Step 1 — Address
  String? houseNumber;
  String? street;
  String? barangay;
  String? city;
  String? province;

  // Step 2 — Emergency Contacts
  List<OcrEmergencyContact> emergencyContacts;

  // Step 3 — Vitals
  String? birthdate; // ISO yyyy-MM-dd
  double? heightCm;
  double? weightKg;
  String? bloodType;

  // Step 4 — Medical Conditions
  List<OcrMedicalCondition> medicalConditions;

  // Step 5 — Allergies
  List<OcrAllergy> allergies;

  // Step 6 — Pregnancy History
  List<OcrPastPregnancy> pastPregnancies;

  // Step 7 — Gestational Info
  String? lmpDate; // ISO yyyy-MM-dd
  String? eddDate; // ISO yyyy-MM-dd

  OcrResult({
    this.firstName,
    this.middleName,
    this.lastName,
    this.extensionName,
    this.phone,
    this.email,
    this.houseNumber,
    this.street,
    this.barangay,
    this.city,
    this.province,
    this.emergencyContacts = const [],
    this.birthdate,
    this.heightCm,
    this.weightKg,
    this.bloodType,
    this.medicalConditions = const [],
    this.allergies = const [],
    this.pastPregnancies = const [],
    this.lmpDate,
    this.eddDate,
  });

  factory OcrResult.fromJson(Map<String, dynamic> j) {
    List<T> parseList<T>(
      dynamic raw,
      T Function(Map<String, dynamic>) fromJson,
    ) {
      if (raw is! List) return [];
      return raw.whereType<Map<String, dynamic>>().map(fromJson).toList();
    }

    return OcrResult(
      firstName: _nonEmpty(j['first_name']),
      middleName: _nonEmpty(j['middle_name']),
      lastName: _nonEmpty(j['last_name']),
      extensionName: _nonEmpty(j['extension_name']),
      phone: _nonEmpty(j['phone']),
      email: _nonEmpty(j['email']),
      houseNumber: _nonEmpty(j['house_number']),
      street: _nonEmpty(j['street']),
      barangay: _nonEmpty(j['barangay']),
      city: _nonEmpty(j['city']),
      province: _nonEmpty(j['province']),
      emergencyContacts:
          parseList(j['emergency_contacts'], OcrEmergencyContact.fromJson),
      birthdate: _nonEmpty(j['birthdate']),
      heightCm: (j['height_cm'] as num?)?.toDouble(),
      weightKg: (j['weight_kg'] as num?)?.toDouble(),
      bloodType: _nonEmpty(j['blood_type']),
      medicalConditions:
          parseList(j['medical_conditions'], OcrMedicalCondition.fromJson),
      allergies: parseList(j['allergies'], OcrAllergy.fromJson),
      pastPregnancies:
          parseList(j['past_pregnancies'], OcrPastPregnancy.fromJson),
      lmpDate: _nonEmpty(j['lmp_date']),
      eddDate: _nonEmpty(j['edd_date']),
    );
  }

  /// Returns true if at least one field has a value.
  bool get hasAnyValue =>
      firstName != null ||
      lastName != null ||
      phone != null ||
      email != null ||
      birthdate != null ||
      barangay != null ||
      heightCm != null ||
      weightKg != null ||
      bloodType != null ||
      lmpDate != null ||
      eddDate != null ||
      emergencyContacts.isNotEmpty ||
      medicalConditions.isNotEmpty ||
      allergies.isNotEmpty ||
      pastPregnancies.isNotEmpty;
}

String? _nonEmpty(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}
