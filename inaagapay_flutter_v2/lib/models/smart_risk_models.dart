// lib/models/smart_risk_models.dart
// Simplified risk models for the "is something off now?" assessment.

/// Simple risk state – either all normal or something abnormal right now.
enum RiskState { low, high }

/// Represents a single abnormal finding in the latest check‑up.
class CurrentFinding {
  final String measurement; // e.g. "Blood Pressure"
  final String value;       // e.g. "142/90 mmHg"
  final String threshold;   // e.g. "Normal < 140/90"
  const CurrentFinding({
    required this.measurement,
    required this.value,
    required this.threshold,
  });
}

/// Historical observable events (previous check‑ups, past pregnancies).
class PregnancyEvent {
  final double? week;
  final dynamic date;
  final String what; // description of the fact
  final String type; // 'elevated', 'normal', 'history'
  const PregnancyEvent({
    this.week,
    this.date,
    required this.what,
    required this.type,
  });
}

/// Aggregated assessment shown on the mother profile screen.
class SmartRiskAssessment {
  final RiskState currentState;
  final List<CurrentFinding> currentFindings;
  final List<PregnancyEvent> history;
  final List<String> watchItems;
  final String summary;

  const SmartRiskAssessment({
    required this.currentState,
    this.currentFindings = const [],
    this.history = const [],
    this.watchItems = const [],
    this.summary = '',
  });

  // Helper strings for UI
  String get statusText => currentState == RiskState.high ? 'HIGH RISK' : 'LOW RISK';

  String get summaryText {
    if (currentState == RiskState.low) {
      return 'All readings within normal range. Continue routine care.';
    }
    final findings = currentFindings.map((f) => '${f.measurement} ${f.value}').join(', ');
    return '$findings outside normal range.';
  }
}
