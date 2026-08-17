// lib/services/risk_engine.dart
// Simplified legacy risk engine – used only to provide a low/high risk flag
// based on the latest check‑up data.
//
// Blood pressure and fetal heart rate are not judged here. They come from
// `blood_pressure_reference.dart` and `fetal_heart_rate_reference.dart`, the
// same objects the checkup screen and the mother's profile read, so this
// engine cannot drift away from what the midwife was shown when she recorded
// the visit. It used to hold its own copy of both, and the heart rate copy had
// already drifted: it called 110–119 bpm a finding where the recording screen
// called it normal.
//
// It still judges a single visit — that is its purpose, and the card it feeds
// only falls back to it when no risk level has been stored. Whether a raised
// reading *repeated* is a property of the series and belongs to
// [BloodPressureReference.assess], which the trend card uses.

import 'blood_pressure_reference.dart';
import 'fetal_heart_rate_reference.dart';

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

    // Blood pressure — cited thresholds, one object
    const bp = BpThresholds.standard;
    final bpSys = _num(latestCheckup['blood_pressure_systolic']);
    final bpDia = _num(latestCheckup['blood_pressure_diastolic']);
    if (bpSys != null && bpDia != null) {
      final reading = 'BP ${bpSys.toInt()}/${bpDia.toInt()}';
      switch (BloodPressureReference.categorise(
          bpSys.round(), bpDia.round())) {
        case BpCategory.severe:
          findings.add('$reading (at or above '
              '${bp.severeSystolic}/${bp.severeDiastolic})');
        case BpCategory.raised:
          findings.add('$reading (at or above '
              '${bp.raisedSystolic}/${bp.raisedDiastolic})');
        case BpCategory.low:
          findings.add(
              '$reading (below ${bp.lowSystolic}/${bp.lowDiastolic})');
        case BpCategory.unreadable:
          // Systolic at or below diastolic. Previously this fell into the
          // raised branch — 80/120 was reported as being above 140/90 — so a
          // transposed entry produced a confident finding about a reading
          // that was never valid.
          findings.add('$reading (not readable)');
        case BpCategory.normal:
          break;
      }
    }

    // Fetal heart rate — cited baseline, one object
    final fhr = _intVal(latestCheckup['fetal_heart_beat']);
    final fhrAssessment = FetalHeartRateReference.assess(fhr);
    if (fhrAssessment.isOutsideBaseline) {
      findings.add('FHR $fhr bpm (outside '
          '${FhrThresholds.standard.baselineMin}–'
          '${FhrThresholds.standard.baselineMax})');
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
