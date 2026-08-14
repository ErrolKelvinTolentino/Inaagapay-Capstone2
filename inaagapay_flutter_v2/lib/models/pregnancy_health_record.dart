enum PregnancyRecordType {
  vaccination,
  supplement,
}

extension PregnancyRecordTypeLabel on PregnancyRecordType {
  String get label => switch (this) {
        PregnancyRecordType.vaccination => 'Vaccination',
        PregnancyRecordType.supplement => 'Supplement',
      };
}

enum PregnancyRecordStatus {
  upcoming,
  active,
  completed,
  missed,
  discontinued,
}

extension PregnancyRecordStatusLabel on PregnancyRecordStatus {
  String get label => switch (this) {
        PregnancyRecordStatus.upcoming => 'Upcoming',
        PregnancyRecordStatus.active => 'Active',
        PregnancyRecordStatus.completed => 'Completed',
        PregnancyRecordStatus.missed => 'Missed',
        PregnancyRecordStatus.discontinued => 'Discontinued',
      };
}

class PregnancyHealthRecord {
  static const Object _unset = Object();

  final String id;
  final PregnancyRecordType type;
  final String name;
  final DateTime recordDate;
  final String? dosage;
  final String? frequency;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? providerName;
  final String? healthFacility;
  final String? instructions;
  final String? notes;
  final PregnancyRecordStatus status;
  final DateTime? nextScheduledDate;
  final bool isSample;

  const PregnancyHealthRecord({
    required this.id,
    required this.type,
    required this.name,
    required this.recordDate,
    this.dosage,
    this.frequency,
    this.startDate,
    this.endDate,
    this.providerName,
    this.healthFacility,
    this.instructions,
    this.notes,
    required this.status,
    this.nextScheduledDate,
    this.isSample = false,
  });

  PregnancyHealthRecord copyWith({
    String? id,
    PregnancyRecordType? type,
    String? name,
    DateTime? recordDate,
    Object? dosage = _unset,
    Object? frequency = _unset,
    Object? startDate = _unset,
    Object? endDate = _unset,
    Object? providerName = _unset,
    Object? healthFacility = _unset,
    Object? instructions = _unset,
    Object? notes = _unset,
    PregnancyRecordStatus? status,
    Object? nextScheduledDate = _unset,
    bool? isSample,
  }) {
    return PregnancyHealthRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      recordDate: recordDate ?? this.recordDate,
      dosage: identical(dosage, _unset) ? this.dosage : dosage as String?,
      frequency:
          identical(frequency, _unset) ? this.frequency : frequency as String?,
      startDate: identical(startDate, _unset)
          ? this.startDate
          : startDate as DateTime?,
      endDate: identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
      providerName: identical(providerName, _unset)
          ? this.providerName
          : providerName as String?,
      healthFacility: identical(healthFacility, _unset)
          ? this.healthFacility
          : healthFacility as String?,
      instructions: identical(instructions, _unset)
          ? this.instructions
          : instructions as String?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      status: status ?? this.status,
      nextScheduledDate: identical(nextScheduledDate, _unset)
          ? this.nextScheduledDate
          : nextScheduledDate as DateTime?,
      isSample: isSample ?? this.isSample,
    );
  }
}
