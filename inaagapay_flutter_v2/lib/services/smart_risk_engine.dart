// lib/services/smart_risk_engine.dart
import '../models/smart_risk_models.dart';

class SmartRiskEngine {
  /// Builds a history of observable facts from checkups and past pregnancies.
  static List<PregnancyEvent> buildHistory({
    required List<Map<String, dynamic>> allCheckups,
    required List<Map<String, dynamic>> pastPregnancies,
  }) {
    final events = <PregnancyEvent>[];

    // Add events from current pregnancy checkups
    for (final checkup in allCheckups) {
      final week = _num(checkup['age_of_gestation']);
      final date = checkup['checkup_datetime'];

      // Check BP elevation
      final sys = _num(checkup['blood_pressure_systolic']);
      final dia = _num(checkup['blood_pressure_diastolic']);
      if (sys != null && dia != null && (sys >= 140 || dia >= 90)) {
        events.add(PregnancyEvent(
          week: week,
          date: date,
          what: 'BP ${sys.toInt()}/${dia.toInt()} — above 140/90',
          type: 'elevated',
        ));
      }

      // Check for bleeding/spotting in remarks
      final remarks = checkup['remarks']?.toString().toLowerCase() ?? '';
      if (remarks.contains('bleeding') || remarks.contains('spotting')) {
        events.add(PregnancyEvent(
          week: week,
          date: date,
          what: 'Bleeding/spotting reported',
          type: 'elevated',
        ));
      }

      // Check for abnormal FHR in history
      final fhr = _intVal(checkup['fetal_heart_beat']);
      if (fhr != null && (fhr < 120 || fhr > 160)) {
        events.add(PregnancyEvent(
          week: week,
          date: date,
          what: 'FHR $fhr bpm — outside 120-160 range',
          type: 'elevated',
        ));
      }
    }

    // Add past pregnancy outcomes as historical facts
    for (final pg in pastPregnancies) {
      final outcome = pg['outcome']?.toString() ?? 'Unknown';
      final date = pg['outcome_date']?.toString();
      final ga = pg['gestational_age_at_end'];

      events.add(PregnancyEvent(
        date: date,
        what: 'Previous pregnancy: $outcome${ga != null ? ' at $ga weeks' : ''}',
        type: 'history',
      ));
    }

    // Sort by date, most recent first
    events.sort((a, b) {
      final da = a.date != null ? DateTime.tryParse(a.date.toString()) : null;
      final db = b.date != null ? DateTime.tryParse(b.date.toString()) : null;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    return events;
  }

  /// Spots patterns or concerns without giving clinical advice.
  static List<String> buildWatchList({
    required List<Map<String, dynamic>> allCheckups,
    required List<Map<String, dynamic>> pastPregnancies,
    required Map<String, dynamic> latestCheckup,
  }) {
    final items = <String>[];

    // Check BP trend across last 3 visits
    final bpReadings = <double>[];
    final sortedCheckups = List<Map<String, dynamic>>.from(allCheckups)
      ..sort((a, b) {
        final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '');
        final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '');
        if (da == null || db == null) return 0;
        return da.compareTo(db);
      });

    for (final c in sortedCheckups.reversed.take(3)) {
      final sys = _num(c['blood_pressure_systolic']);
      if (sys != null) bpReadings.add(sys);
    }

    if (bpReadings.length >= 3) {
      // Index 0 is latest, 1 is previous, 2 is before that
      if (bpReadings[0] > bpReadings[1] && bpReadings[1] > bpReadings[2]) {
        items.add('BP has been rising: ${bpReadings.reversed.map((e) => e.toInt()).join(" → ")}');
      }
    }

    // Check if current week matches previous complication timing
    final currentWeek = _num(latestCheckup['age_of_gestation']);
    for (final pg in pastPregnancies) {
      final prevWeek = _num(pg['gestational_age_at_end']);
      final complication = pg['outcome']?.toString().toLowerCase() ?? '';
      if (currentWeek != null && prevWeek != null && complication.contains('eclampsia')) {
        if ((currentWeek - prevWeek).abs() <= 4) {
          items.add('Previous pre-eclampsia happened around Week ${prevWeek.toInt()} — similar timing now');
        }
      }
    }

    // Check if edema appeared with borderline BP
    final edema = latestCheckup['edema']?.toString().toLowerCase() ?? '';
    final sys = _num(latestCheckup['blood_pressure_systolic']);
    if (edema.isNotEmpty && edema != 'none' && sys != null && sys >= 135) {
      items.add('Edema present with borderline BP — check for other signs next visit');
    }

    // Weight gain trend analysis
    if (sortedCheckups.length >= 2) {
      final latest = sortedCheckups.last;
      final previous = sortedCheckups[sortedCheckups.length - 2];
      final curWeight = _num(latest['checkup_weight']);
      final prevWeight = _num(previous['checkup_weight']);
      final curWeek = _num(latest['age_of_gestation']);
      final prevWeek = _num(previous['age_of_gestation']);

      if (curWeight != null && prevWeight != null &&
          curWeek != null && prevWeek != null && curWeek > prevWeek) {
        final weekDiff = curWeek - prevWeek;
        final weightDiff = curWeight - prevWeight;
        final weeklyGain = weightDiff / weekDiff;

        if (weightDiff < -0.1) {
          items.add('⚠️ Weight loss detected (${weightDiff.toStringAsFixed(1)} kg) — requires clinical attention');
        } else if (weeklyGain > 1.0 && curWeek > 13) {
          items.add('Rapid weight gain (${weeklyGain.toStringAsFixed(2)} kg/week) — rule out fluid retention');
        } else if (weeklyGain < 0.15 && curWeek > 13 && weekDiff >= 2) {
          items.add('Low weight gain rate (${weeklyGain.toStringAsFixed(2)} kg/week) — monitor nutrition');
        }
      }
    }

    if (items.isEmpty) {
      items.add('No specific concerns based on current data');
    }

    return items.take(5).toList();
  }

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
