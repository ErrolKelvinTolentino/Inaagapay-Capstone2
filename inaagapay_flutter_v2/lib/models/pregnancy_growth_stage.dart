class PregnancyGrowthStage {
  final int month;
  final int startWeek;
  final int endWeek;
  final String trimester;
  final String sizeComparison;
  final String approximateLength;
  final String approximateWeight;
  final String developmentSummary;
  final String twinDevelopmentSummary;
  final List<String> developmentHighlights;
  final List<String> motherChanges;
  final String healthReminder;
  final String imageAsset;

  const PregnancyGrowthStage({
    required this.month,
    required this.startWeek,
    required this.endWeek,
    required this.trimester,
    required this.sizeComparison,
    required this.approximateLength,
    required this.approximateWeight,
    required this.developmentSummary,
    required this.twinDevelopmentSummary,
    required this.developmentHighlights,
    required this.motherChanges,
    required this.healthReminder,
    required this.imageAsset,
  });

  String developmentFor(int numberOfBabies) =>
      numberOfBabies > 1 ? twinDevelopmentSummary : developmentSummary;

  String get weekRange => 'Weeks $startWeek–$endWeek';
}

class CurrentPregnancyState {
  final int currentWeek;
  final int currentMonth;
  final DateTime estimatedDueDate;
  final int numberOfBabies;
  final double pregnancyProgress;
  final String trimester;

  const CurrentPregnancyState({
    required this.currentWeek,
    required this.currentMonth,
    required this.estimatedDueDate,
    required this.numberOfBabies,
    required this.pregnancyProgress,
    required this.trimester,
  });

  bool get isTwinPregnancy => numberOfBabies == 2;
  bool get isMultiplePregnancy => numberOfBabies > 1;

  CurrentPregnancyState copyWith({
    int? currentWeek,
    int? currentMonth,
    DateTime? estimatedDueDate,
    int? numberOfBabies,
    double? pregnancyProgress,
    String? trimester,
  }) {
    return CurrentPregnancyState(
      currentWeek: currentWeek ?? this.currentWeek,
      currentMonth: currentMonth ?? this.currentMonth,
      estimatedDueDate: estimatedDueDate ?? this.estimatedDueDate,
      numberOfBabies: numberOfBabies ?? this.numberOfBabies,
      pregnancyProgress: pregnancyProgress ?? this.pregnancyProgress,
      trimester: trimester ?? this.trimester,
    );
  }
}
