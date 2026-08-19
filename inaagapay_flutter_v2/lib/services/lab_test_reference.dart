// lib/services/lab_test_reference.dart
//
// Which fields a lab test has, in one place.
//
// A blood count reports haemoglobin and platelets; a glucose tolerance test
// reports timed samples; a urinalysis reports protein and glucose. The record
// screen had no way to know that, so every lab test rendered the same three
// sections — type, who performed it, notes — and the actual results lived only
// inside a paragraph of AI narrative, if they survived at all.
//
// WHAT THIS IS NOT
//
// It holds no reference ranges and makes no judgements. Pregnancy shifts
// haemoglobin, haematocrit and glucose cut-points away from the non-pregnant
// adult values, and this project's rule is that a threshold appears in code
// only with a source beside it and an object to override it — the way
// [BpThresholds] and [FhrThresholds] do. Until the RHU's ranges are confirmed,
// these fields carry values and units and say nothing about whether they are
// normal.
//
// Adding a test type later is one entry in [_catalogue], not a new screen.

/// One reportable value on a lab test.
class LabField {
  const LabField({
    required this.column,
    required this.label,
    this.unit,
  });

  /// The column on `lab_tests` that holds it.
  final String column;

  final String label;

  /// Omitted where laboratories genuinely disagree on the unit — white cell
  /// and platelet counts are reported per microlitre by some and as 10^9/L by
  /// others, and printing a unit the document did not use would be inventing
  /// precision.
  final String? unit;
}

/// The fields one kind of lab test reports, under a heading.
class LabPanel {
  const LabPanel({required this.title, required this.fields});

  final String title;
  final List<LabField> fields;
}

class LabTestReference {
  const LabTestReference._();

  static const _ogtt = LabPanel(
    title: 'Glucose Tolerance',
    fields: [
      LabField(
          column: 'fasting_glucose_mg_dl', label: 'Fasting', unit: 'mg/dL'),
      LabField(column: 'glucose_1hr_mg_dl', label: '1 hour', unit: 'mg/dL'),
      LabField(column: 'glucose_2hr_mg_dl', label: '2 hours', unit: 'mg/dL'),
      LabField(column: 'glucose_3hr_mg_dl', label: '3 hours', unit: 'mg/dL'),
    ],
  );

  static const _fbs = LabPanel(
    title: 'Blood Sugar',
    fields: [
      LabField(
          column: 'fasting_glucose_mg_dl',
          label: 'Fasting blood sugar',
          unit: 'mg/dL'),
    ],
  );

  static const _cbc = LabPanel(
    title: 'Blood Count',
    fields: [
      LabField(column: 'hemoglobin_g_dl', label: 'Haemoglobin', unit: 'g/dL'),
      LabField(column: 'hematocrit_pct', label: 'Haematocrit', unit: '%'),
      LabField(column: 'wbc_count', label: 'White blood cells'),
      LabField(column: 'platelet_count', label: 'Platelets'),
    ],
  );

  static const _urinalysis = LabPanel(
    title: 'Urinalysis',
    fields: [
      LabField(column: 'urinalysis_protein', label: 'Protein'),
      LabField(column: 'urinalysis_glucose', label: 'Glucose'),
    ],
  );

  static const _hepatitisB = LabPanel(
    title: 'Hepatitis B',
    fields: [
      LabField(column: 'hepatitis_b_status', label: 'HBsAg'),
    ],
  );

  static const _hiv = LabPanel(
    title: 'HIV',
    fields: [LabField(column: 'hiv_status', label: 'HIV screening')],
  );

  static const _syphilis = LabPanel(
    title: 'Syphilis',
    fields: [LabField(column: 'syphilis_status', label: 'VDRL / RPR')],
  );

  /// Matched on substrings rather than exact strings.
  ///
  /// `lab_test_type` is free-ish text: it comes from a dropdown, but OCR can
  /// also propose a value, and the same test is written "OGTT", "OGTT (Oral
  /// Glucose Tolerance Test)" and "Oral Glucose Tolerance Test" in the wild.
  /// Order matters — OGTT is checked before the plain sugar test, or an OGTT
  /// would match on "glucose" and report a single fasting value.
  static const _catalogue = <List<String>, LabPanel>{
    ['ogtt', 'oralglucose', 'glucosetolerance']: _ogtt,
    ['completebloodcount', 'cbc']: _cbc,
    ['urinalysis', 'urine']: _urinalysis,
    ['hbsag', 'hepatitis']: _hepatitisB,
    ['hiv']: _hiv,
    ['vdrl', 'syphilis', 'rpr']: _syphilis,
    ['fastingbloodsugar', 'fbs', 'bloodsugar']: _fbs,
  };

  /// The panel for a test type, or null when the type has no structured fields
  /// — a stool exam or an "Other" entry, where the attached document and the
  /// midwife's notes are the record.
  static LabPanel? panelFor(String? labTestType) {
    final key = (labTestType ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (key.isEmpty) return null;

    for (final entry in _catalogue.entries) {
      for (final alias in entry.key) {
        if (key.contains(alias)) return entry.value;
      }
    }
    return null;
  }

  /// Label/value pairs ready to display, skipping anything the record does not
  /// hold. A test that captured only a fasting sample shows one row, not four
  /// rows three of which say nothing.
  static List<MapEntry<String, String>> resultRows(
    String? labTestType,
    Map<String, dynamic> row,
  ) {
    final panel = panelFor(labTestType);
    if (panel == null) return const [];

    final rows = <MapEntry<String, String>>[];
    for (final field in panel.fields) {
      final raw = row[field.column];
      if (raw == null) continue;

      final value = raw.toString().trim();
      if (value.isEmpty || value.toLowerCase() == 'null') continue;

      rows.add(MapEntry(
        field.label,
        field.unit == null ? value : '$value ${field.unit}',
      ));
    }
    return rows;
  }
}
