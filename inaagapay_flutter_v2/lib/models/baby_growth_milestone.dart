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

  /// The `baby_book_milestones.entry_id` backing this, when one exists.
  ///
  /// Null for a template that has never been recorded. Un-marking needs it:
  /// without the row's own id there is nothing to delete, and the only other
  /// way to find the row again is to re-derive it from the template, which
  /// would delete the wrong entry as soon as two rows share a template.
  final int? entryId;

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
    this.entryId,
  });

  /// What the record says about this milestone, and what she can do about it.
  ///
  /// This sentence is derived from [status] rather than written into
  /// [description] because it is a claim about the record, and a claim about
  /// the record goes stale the moment the record changes. "No checkup is
  /// currently recorded in InaAgapay" stored as fixed text would keep saying
  /// so after her midwife entered one — telling a mother to chase something
  /// she has already done, in the app that holds the proof she did it.
  ///
  /// It stops at what the app can see. Whether the milestone was done
  /// elsewhere, is due, or should be scheduled is not something a record of
  /// absence can answer, so the wording asks her midwife rather than deciding.
  String get recordGuidance => switch (status) {
        BabyGrowthMilestoneStatus.completed =>
          'This is recorded in InaAgapay.',
        BabyGrowthMilestoneStatus.current =>
          'This is not yet recorded in InaAgapay. You may ask your midwife '
              'whether it has been done, needs to be scheduled, or needs to be '
              'added to your record.',
        BabyGrowthMilestoneStatus.notRecorded =>
          'This is not yet recorded in InaAgapay. You may ask your midwife '
              'whether it has been done, needs to be scheduled, or needs to be '
              'added to your record.',
        BabyGrowthMilestoneStatus.upcoming =>
          'This is not due yet. Your midwife will tell you when it is time.',
      };

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
    Object? entryId = _unset,
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
      entryId: identical(entryId, _unset) ? this.entryId : entryId as int?,
    );
  }
}
