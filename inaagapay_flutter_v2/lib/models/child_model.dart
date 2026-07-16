// lib/models/child_model.dart

class ChildModel {
  final int childId;
  final int motherId;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? extensionName;
  final String sex;
  final DateTime addedAt;
  final DateTime? birthdate;
  final double? birthWeight;
  final double? birthLength;
  final String? birthplaceCity;
  final String? birthplaceProvince;

  ChildModel({
    required this.childId,
    required this.motherId,
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.extensionName,
    required this.sex,
    required this.addedAt,
    this.birthdate,
    this.birthWeight,
    this.birthLength,
    this.birthplaceCity,
    this.birthplaceProvince,
  });

  String get fullName {
    final parts = [firstName, middleName, lastName];
    if (extensionName != null && extensionName!.isNotEmpty) {
      parts.add(extensionName!);
    }
    return parts.where((p) => p != null && p.isNotEmpty).join(' ');
  }

  String get ageText {
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

  int get ageInWeeks {
    if (birthdate == null) return 0;
    return DateTime.now().difference(birthdate!).inDays ~/ 7;
  }

  factory ChildModel.fromJson(Map<String, dynamic> json) {
    return ChildModel(
      childId: json['child_id'] as int,
      motherId: json['mother_id'] as int,
      firstName: json['first_name'] as String? ?? '',
      middleName: json['middle_name'] as String?,
      lastName: json['last_name'] as String? ?? '',
      extensionName: json['extension_name'] as String?,
      sex: json['sex'] as String? ?? 'male',
      addedAt: DateTime.parse(json['added_at']),
      birthdate: json['birthdate'] != null ? DateTime.parse(json['birthdate']) : null,
      birthWeight: (json['birth_weight'] as num?)?.toDouble(),
      birthLength: (json['birth_length'] as num?)?.toDouble(),
      birthplaceCity: json['birthplace_city_municipality'] as String?,
      birthplaceProvince: json['birthplace_province'] as String?,
    );
  }
}

class GrowthRecord {
  final int childDetailsId;
  final int childId;
  final double height;
  final double weight;
  final DateTime createdAt;

  GrowthRecord({
    required this.childDetailsId,
    required this.childId,
    required this.height,
    required this.weight,
    required this.createdAt,
  });

  factory GrowthRecord.fromJson(Map<String, dynamic> json) {
    return GrowthRecord(
      childDetailsId: json['child_details_id'] as int,
      childId: json['child_id'] as int,
      height: (json['child_height'] as num?)?.toDouble() ?? 0,
      weight: (json['child_weight'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class ImmunizationRecord {
  final int immunizationRecordId;
  final int childId;
  final int vaccineId;
  final String vaccineName;
  final int doseNumber;
  final double recommendedAgeMonths;
  final DateTime vaccinationDate;
  final String? remarks;

  ImmunizationRecord({
    required this.immunizationRecordId,
    required this.childId,
    required this.vaccineId,
    required this.vaccineName,
    required this.doseNumber,
    required this.recommendedAgeMonths,
    required this.vaccinationDate,
    this.remarks,
  });

  factory ImmunizationRecord.fromJson(Map<String, dynamic> json) {
    final vaccine = json['vaccine'] as Map<String, dynamic>?;
    return ImmunizationRecord(
      immunizationRecordId: json['immunization_record_id'] as int,
      childId: json['child_id'] as int,
      vaccineId: json['vaccine_id'] as int,
      vaccineName: vaccine?['vaccine_name'] as String? ?? 'Unknown',
      doseNumber: vaccine?['dose_number'] as int? ?? 0,
      recommendedAgeMonths: (vaccine?['recommended_age_months'] as num?)?.toDouble() ?? 0,
      vaccinationDate: DateTime.parse(json['vaccination_date']),
      remarks: json['remarks'] as String?,
    );
  }
}