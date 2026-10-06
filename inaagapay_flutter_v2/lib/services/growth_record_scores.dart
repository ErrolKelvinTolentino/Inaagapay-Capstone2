import 'growth_calculator.dart';

/// Uses the child's recorded sex and age on the measurement date.
class GrowthRecordScores {
  GrowthRecordScores(
      {required Map<String, dynamic> record,
      required DateTime? birthdate,
      required String? sex}) {
    final measured = DateTime.tryParse(record['created_at']?.toString() ?? '');
    final normalized = sex?.toLowerCase();
    if (birthdate == null ||
        measured == null ||
        !['male', 'female'].contains(normalized)) return;
    final days = DateTime(measured.year, measured.month, measured.day)
        .difference(DateTime(birthdate.year, birthdate.month, birthdate.day))
        .inDays;
    if (days < 0) return;
    final weight = (record['child_weight'] as num?)?.toDouble();
    final height = (record['child_height'] as num?)?.toDouble();
    if (weight != null && weight > 0)
      weightZ = GrowthCalculator.calculateWeightZScore(
          weight, days ~/ 7, normalized!);
    if (height != null && height > 0)
      heightZ = GrowthCalculator.calculateHeightZScore(
          height, days ~/ 7, normalized!);
  }
  double? weightZ;
  double? heightZ;
  static String value(double? z) =>
      z == null || !z.isFinite ? 'Not available' : z.toStringAsFixed(2);
  static String interpretation(double? z) => z == null || !z.isFinite
      ? 'Insufficient reference data'
      : GrowthCalculator.bandLabel(z);
}
