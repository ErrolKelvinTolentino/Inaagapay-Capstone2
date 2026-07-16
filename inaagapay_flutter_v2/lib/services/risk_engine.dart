// lib/services/risk_engine.dart
// Simplified legacy risk engine – used only to provide a low/high risk flag
// based on the latest check‑up data.

class RiskAssessment {
  final String level; // 'low' or 'high'
  final List<String> findings; // list of abnormal observations
  final String note; // one‑line summary

  const RiskAssessment({
    required this.level,
    required this.findings,
    required this.note,
  });
}

class RiskEngine {
  /// Evaluate the latest check‑up and return a simple assessment.
  /// Returns 'high' if any abnormal finding is detected, otherwise 'low'.
  static RiskAssessment evaluate({
    required Map<String, dynamic> latestCheckup,
  }) {
    final findings = <String>[];

    // Blood pressure thresholds
    final bpSys = _num(latestCheckup['blood_pressure_systolic']);
    final bpDia = _num(latestCheckup['blood_pressure_diastolic']);
    if (bpSys != null && bpDia != null) {
      if (bpSys >= 140 || bpDia >= 90) {
        findings.add('BP ${bpSys.toInt()}/${bpDia.toInt()} (above 140/90)');
      } else if (bpSys < 90 || bpDia < 60) {
        findings.add('BP ${bpSys.toInt()}/${bpDia.toInt()} (below 90/60)');
      }
    }

    // Fetal heart rate thresholds (120‑160 bpm is normal)
    final fhr = _intVal(latestCheckup['fetal_heart_beat']);
    if (fhr != null && (fhr < 120 || fhr > 160)) {
      findings.add('FHR $fhr bpm (outside 120‑160 range)');
    }

    // Edema – flag moderate or severe
    final edema = latestCheckup['edema']?.toString().toLowerCase() ?? '';
    if (edema.contains('moderate') || edema.contains('severe')) {
      findings.add('Edema: ${latestCheckup['edema']}');
    }

    // Bleeding flag – either explicit boolean or mentioned in remarks
    final bleeding = latestCheckup['bleeding'] == true ||
        (latestCheckup['remarks']?.toString().toLowerCase().contains('bleeding') ?? false);
    if (bleeding) {
      findings.add('Bleeding reported');
    }

    // Additional simple thresholds can be added here (e.g., Hb, proteinuria, fever)

    // Weight loss detection — flag if current weight is below previous
    // (requires previous checkup data to be passed in latestCheckup as
    // 'previous_weight'; callers may optionally include this field)
    final prevWeight = _num(latestCheckup['previous_weight']);
    final curWeight = _num(latestCheckup['checkup_weight']);
    if (prevWeight != null && curWeight != null && curWeight < prevWeight - 0.1) {
      findings.add('Weight loss: ${(prevWeight - curWeight).toStringAsFixed(1)} kg since previous checkup');
    }

    final isHigh = findings.isNotEmpty;
    return RiskAssessment(
      level: isHigh ? 'high' : 'low',
      findings: findings,
      note: isHigh ? '${findings.length} finding(s) outside normal range' : 'All readings within normal range',
    );
  }

  // Helpers – same as previous implementation
  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _intVal(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
