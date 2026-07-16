// lib/models/growth_record.dart

class GrowthRecord {
  final String id;
  final String childId;
  final DateTime dateRecorded;
  final int ageInWeeks;
  final double weight;
  final double height;
  final double bmi;
  final double weightZScore;
  final double heightZScore;
  final double bmiZScore;
  final String weightClassification;
  final String heightClassification;
  final String bmiClassification;

  GrowthRecord({
    required this.id,
    required this.childId,
    required this.dateRecorded,
    required this.ageInWeeks,
    required this.weight,
    required this.height,
    required this.bmi,
    required this.weightZScore,
    required this.heightZScore,
    required this.bmiZScore,
    required this.weightClassification,
    required this.heightClassification,
    required this.bmiClassification,
  });
}