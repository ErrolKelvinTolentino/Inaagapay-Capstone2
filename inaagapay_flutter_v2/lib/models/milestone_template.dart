import 'baby_growth_milestone.dart';

/// A row from `milestone_templates` — one entry in the catalogue of
/// milestones worth recording.
///
/// Prenatal templates are placed on the timeline by gestational week;
/// postnatal ones by the child's age in months. A template carries no state
/// about any particular pregnancy or child: that lives in
/// `baby_book_milestones`, and the two are combined on read.
class MilestoneTemplate {
  /// Stable slug (`pregnancy-confirmed`, `anatomy-scan`, …). Survives
  /// re-seeding, unlike `templateId`.
  final String key;
  final int templateId;
  final MilestonePhase phase;
  final String category;
  final String titleEn;
  final String? titleFil;
  final String? descriptionEn;
  final String? descriptionFil;

  /// Prenatal placement, in completed weeks of gestation.
  final int? expectedStartWeek;
  final int? expectedEndWeek;

  /// Postnatal placement, in completed months since birth.
  final int? ageMonthsTarget;

  final int sortOrder;

  const MilestoneTemplate({
    required this.key,
    required this.templateId,
    required this.phase,
    required this.category,
    required this.titleEn,
    this.titleFil,
    this.descriptionEn,
    this.descriptionFil,
    this.expectedStartWeek,
    this.expectedEndWeek,
    this.ageMonthsTarget,
    this.sortOrder = 0,
  });

  factory MilestoneTemplate.fromRow(Map<String, dynamic> row) {
    return MilestoneTemplate(
      key: row['template_key']?.toString() ?? '',
      templateId: (row['template_id'] as num).toInt(),
      phase: MilestonePhase.fromDb(row['phase']?.toString()),
      category: row['category']?.toString() ?? '',
      titleEn: row['title_en']?.toString() ?? '',
      titleFil: row['title_fil']?.toString(),
      descriptionEn: row['description_en']?.toString(),
      descriptionFil: row['description_fil']?.toString(),
      expectedStartWeek: (row['expected_start_week'] as num?)?.toInt(),
      expectedEndWeek: (row['expected_end_week'] as num?)?.toInt(),
      ageMonthsTarget: (row['age_months_target'] as num?)?.toInt(),
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  /// The catalogue stores prenatal categories using the same names as
  /// [BabyGrowthMilestoneCategory], in snake_case.
  BabyGrowthMilestoneCategory get prenatalCategory => switch (category) {
        'development' => BabyGrowthMilestoneCategory.development,
        'movement' => BabyGrowthMilestoneCategory.movement,
        'checkup' => BabyGrowthMilestoneCategory.checkup,
        'ultrasound' => BabyGrowthMilestoneCategory.ultrasound,
        'trimester' => BabyGrowthMilestoneCategory.trimester,
        'personal_memory' => BabyGrowthMilestoneCategory.personalMemory,
        // A category outside the prenatal set means a postnatal template was
        // read as prenatal. Falling back keeps the list rendering rather than
        // throwing at the mother.
        _ => BabyGrowthMilestoneCategory.development,
      };
}

/// Which half of the Baby Book a template belongs to.
///
/// The distinction is not cosmetic: prenatal entries attach to a pregnancy
/// and are shared by twins, postnatal entries attach to one child. The
/// database enforces it with `baby_book_milestones_scope_check`.
enum MilestonePhase {
  prenatal,
  postnatal;

  static MilestonePhase fromDb(String? value) =>
      value == 'postnatal' ? MilestonePhase.postnatal : MilestonePhase.prenatal;

  String get dbValue => name;
}
