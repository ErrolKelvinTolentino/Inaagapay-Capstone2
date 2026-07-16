// lib/models/weight_gain_models.dart
// Data models for the Maternal Weight Gain Monitoring Module.

/// Evaluation mode — FULL when pre-pregnancy weight is available,
/// TREND when only longitudinal checkup data exists.
enum WeightGainMode { full, trend }

/// Weight gain status classification.
enum WeightGainStatus { normal, low, high, insufficient }

/// Confidence in the evaluation result.
enum WeightGainConfidence { high, medium, low }

/// BMI category per IOM 2009 guidelines.
enum BmiCategory { underweight, normal, overweight, obese }

/// Result object returned by the weight gain engine.
class WeightGainResult {
  final WeightGainMode mode;
  final String bmiCategory; // human-readable: 'Underweight', 'Normal', etc.
  final double? baselineWeight;
  final double? baselineWeek;
  final double currentWeight;
  final double currentWeek;
  final double? expectedGain;
  final double? expectedGainMin;
  final double? expectedGainMax;
  final double? actualGain;
  final double? weeklyGain;
  final WeightGainStatus status;
  final WeightGainConfidence confidence;
  final String message;
  final List<String> flags; // e.g. 'weight_loss', 'plateau', 'abnormal_spike'

  const WeightGainResult({
    required this.mode,
    required this.bmiCategory,
    this.baselineWeight,
    this.baselineWeek,
    required this.currentWeight,
    required this.currentWeek,
    this.expectedGain,
    this.expectedGainMin,
    this.expectedGainMax,
    this.actualGain,
    this.weeklyGain,
    required this.status,
    required this.confidence,
    required this.message,
    this.flags = const [],
  });

  String get modeLabel {
    switch (mode) {
      case WeightGainMode.full:
        return 'Full Analysis';
      case WeightGainMode.trend:
        return 'Trend-Based Analysis';
    }
  }

  String get statusLabel {
    switch (status) {
      case WeightGainStatus.normal:
        return 'NORMAL';
      case WeightGainStatus.low:
        return 'LOW';
      case WeightGainStatus.high:
        return 'HIGH';
      case WeightGainStatus.insufficient:
        return 'INSUFFICIENT DATA';
    }
  }

  String get statusDisplayLabel {
    switch (status) {
      case WeightGainStatus.normal:
        return 'Within expected monitoring range';
      case WeightGainStatus.low:
        return 'Slightly lower than expected monitoring range';
      case WeightGainStatus.high:
        return 'Slightly above expected monitoring range';
      case WeightGainStatus.insufficient:
        return 'Insufficient data';
    }
  }

  String get confidenceLabel {
    switch (confidence) {
      case WeightGainConfidence.high:
        return 'HIGH';
      case WeightGainConfidence.medium:
        return 'MEDIUM';
      case WeightGainConfidence.low:
        return 'LOW';
    }
  }

  bool get hasFlags => flags.isNotEmpty;
  bool get isWeightLoss => flags.contains('weight_loss');
  bool get isPlateau => flags.contains('plateau');
  bool get isAbnormalSpike => flags.contains('abnormal_spike');

  Map<String, dynamic> toJson() => {
        'mode': mode == WeightGainMode.full ? 'FULL' : 'TREND',
        'bmi_category': bmiCategory,
        'baseline_weight': baselineWeight,
        'baseline_week': baselineWeek,
        'current_weight': currentWeight,
        'current_week': currentWeek,
        'expected_gain': expectedGain,
        'expected_gain_min': expectedGainMin,
        'expected_gain_max': expectedGainMax,
        'actual_gain': actualGain,
        'weekly_gain': weeklyGain,
        'status': statusLabel,
        'confidence': confidenceLabel,
        'message': message,
        'flags': flags,
      };

  factory WeightGainResult.fromJson(Map<String, dynamic> json) {
    return WeightGainResult(
      mode: json['mode'] == 'FULL' ? WeightGainMode.full : WeightGainMode.trend,
      bmiCategory: json['bmi_category'] ?? 'Normal',
      baselineWeight: _toDouble(json['baseline_weight']),
      baselineWeek: _toDouble(json['baseline_week']),
      currentWeight: _toDouble(json['current_weight']) ?? 0,
      currentWeek: _toDouble(json['current_week']) ?? 0,
      expectedGain: _toDouble(json['expected_gain']),
      expectedGainMin: _toDouble(json['expected_gain_min']),
      expectedGainMax: _toDouble(json['expected_gain_max']),
      actualGain: _toDouble(json['actual_gain']),
      weeklyGain: _toDouble(json['weekly_gain']),
      status: _parseStatus(json['status']),
      confidence: _parseConfidence(json['confidence']),
      message: json['message'] ?? '',
      flags: List<String>.from(json['flags'] ?? []),
    );
  }

  factory WeightGainResult.insufficient({
    required double currentWeight,
    required double currentWeek,
    String bmiCategory = 'Unknown',
  }) {
    return WeightGainResult(
      mode: WeightGainMode.trend,
      bmiCategory: bmiCategory,
      currentWeight: currentWeight,
      currentWeek: currentWeek,
      status: WeightGainStatus.insufficient,
      confidence: WeightGainConfidence.low,
      message:
          'Insufficient data for weight gain evaluation. At least two checkup '
          'records are needed for trend-based analysis, or pre-pregnancy weight '
          'is required for full evaluation.',
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static WeightGainStatus _parseStatus(dynamic v) {
    switch (v?.toString().toUpperCase()) {
      case 'NORMAL':
        return WeightGainStatus.normal;
      case 'LOW':
        return WeightGainStatus.low;
      case 'HIGH':
        return WeightGainStatus.high;
      default:
        return WeightGainStatus.insufficient;
    }
  }

  static WeightGainConfidence _parseConfidence(dynamic v) {
    switch (v?.toString().toUpperCase()) {
      case 'HIGH':
        return WeightGainConfidence.high;
      case 'MEDIUM':
        return WeightGainConfidence.medium;
      default:
        return WeightGainConfidence.low;
    }
  }
}
