import 'dart:typed_data';

enum BabyGrowthMilestoneCategory {
  development,
  movement,
  checkup,
  ultrasound,
  trimester,
  personalMemory,
}

extension BabyGrowthMilestoneCategoryLabel on BabyGrowthMilestoneCategory {
  String get label => switch (this) {
        BabyGrowthMilestoneCategory.development => 'Development',
        BabyGrowthMilestoneCategory.movement => 'Movement',
        BabyGrowthMilestoneCategory.checkup => 'Checkup',
        BabyGrowthMilestoneCategory.ultrasound => 'Ultrasound',
        BabyGrowthMilestoneCategory.trimester => 'Trimester',
        BabyGrowthMilestoneCategory.personalMemory => 'Personal Memory',
      };
}

enum BabyGrowthMilestoneStatus {
  upcoming,
  current,
  completed,
  notRecorded,
}

extension BabyGrowthMilestoneStatusLabel on BabyGrowthMilestoneStatus {
  String get label => switch (this) {
        BabyGrowthMilestoneStatus.upcoming => 'Upcoming',
        BabyGrowthMilestoneStatus.current => 'Current',
        BabyGrowthMilestoneStatus.completed => 'Completed',
        BabyGrowthMilestoneStatus.notRecorded => 'Not yet recorded',
      };
}

class BabyGrowthMilestone {
  static const Object _unset = Object();

  final String id;
  final String title;
  final String description;
  final int? expectedStartWeek;
  final int? expectedEndWeek;
  final int? recordedPregnancyWeek;
  final int? pregnancyMonth;
  final DateTime? completedDate;
  final BabyGrowthMilestoneCategory category;
  final BabyGrowthMilestoneStatus status;
  final String? note;
  final String? photoPath;
  final Uint8List? photoBytes;
  final String? recordedBy;
  final bool isCustom;

  const BabyGrowthMilestone({
    required this.id,
    required this.title,
    required this.description,
    this.expectedStartWeek,
    this.expectedEndWeek,
    this.recordedPregnancyWeek,
    this.pregnancyMonth,
    this.completedDate,
    required this.category,
    required this.status,
    this.note,
    this.photoPath,
    this.photoBytes,
    this.recordedBy,
    this.isCustom = false,
  });

  BabyGrowthMilestone copyWith({
    String? id,
    String? title,
    String? description,
    Object? expectedStartWeek = _unset,
    Object? expectedEndWeek = _unset,
    Object? recordedPregnancyWeek = _unset,
    Object? pregnancyMonth = _unset,
    Object? completedDate = _unset,
    BabyGrowthMilestoneCategory? category,
    BabyGrowthMilestoneStatus? status,
    Object? note = _unset,
    Object? photoPath = _unset,
    Object? photoBytes = _unset,
    Object? recordedBy = _unset,
    bool? isCustom,
  }) {
    return BabyGrowthMilestone(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      expectedStartWeek: identical(expectedStartWeek, _unset)
          ? this.expectedStartWeek
          : expectedStartWeek as int?,
      expectedEndWeek: identical(expectedEndWeek, _unset)
          ? this.expectedEndWeek
          : expectedEndWeek as int?,
      recordedPregnancyWeek: identical(recordedPregnancyWeek, _unset)
          ? this.recordedPregnancyWeek
          : recordedPregnancyWeek as int?,
      pregnancyMonth: identical(pregnancyMonth, _unset)
          ? this.pregnancyMonth
          : pregnancyMonth as int?,
      completedDate: identical(completedDate, _unset)
          ? this.completedDate
          : completedDate as DateTime?,
      category: category ?? this.category,
      status: status ?? this.status,
      note: identical(note, _unset) ? this.note : note as String?,
      photoPath:
          identical(photoPath, _unset) ? this.photoPath : photoPath as String?,
      photoBytes: identical(photoBytes, _unset)
          ? this.photoBytes
          : photoBytes as Uint8List?,
      recordedBy: identical(recordedBy, _unset)
          ? this.recordedBy
          : recordedBy as String?,
      isCustom: isCustom ?? this.isCustom,
    );
  }
}
