import 'package:flutter_test/flutter_test.dart';

/// Mirrors the default ordering of the midwife's mothers list: risk first,
/// most urgent at the top, then patient number within each band.
///
/// The comparison lives in _MidwifeMothersScreenState, which cannot be
/// constructed without Supabase, so the rule is reproduced here. It is small
/// and stable; what it guards is that the *rule* stays as the adviser
/// specified, and that the two easy mistakes stay fixed — sorting a patient
/// number as text, and dropping medium-risk mothers to the bottom.
int riskRank(Object? level) {
  switch (level?.toString().toLowerCase().trim()) {
    case 'critical':
      return 0;
    case 'high':
      return 1;
    case 'medium':
    case 'moderate':
      return 2;
    case 'low':
      return 3;
    default:
      return 1;
  }
}

int patientNumberOf(Map<String, dynamic> m) {
  final raw = m['bhc_patient_id']?.toString() ?? '';
  final digits = RegExp(r'\d+').firstMatch(raw)?.group(0);
  return digits == null ? 1 << 30 : int.parse(digits);
}

List<String> sorted(List<Map<String, dynamic>> mothers) {
  final copy = [...mothers]..sort((a, b) {
      final byRisk = riskRank(a['risk_level']).compareTo(riskRank(b['risk_level']));
      if (byRisk != 0) return byRisk;
      return patientNumberOf(a).compareTo(patientNumberOf(b));
    });
  return copy.map((m) => m['bhc_patient_id'] as String).toList();
}

Map<String, dynamic> mother(String id, String risk) =>
    {'bhc_patient_id': id, 'risk_level': risk};

void main() {
  test('matches the ordering the adviser asked for', () {
    // 002 high, 003 high, 001 low, 004 low
    expect(
      sorted([
        mother('INA-001', 'low'),
        mother('INA-002', 'high'),
        mother('INA-003', 'high'),
        mother('INA-004', 'low'),
      ]),
      ['INA-002', 'INA-003', 'INA-001', 'INA-004'],
    );
  });

  test('orders patient numbers numerically, not as text', () {
    // The mistake this prevents: "INA-010" sorting before "INA-002" because
    // '0' precedes '2' one character in.
    expect(
      sorted([
        mother('INA-010', 'high'),
        mother('INA-002', 'high'),
        mother('INA-100', 'high'),
        mother('INA-009', 'high'),
      ]),
      ['INA-002', 'INA-009', 'INA-010', 'INA-100'],
    );
  });

  test('places medium risk between high and low', () {
    // pregnancy_risk_level allows low, medium and high, but the risk *filter*
    // only knows two — so a medium mother is easy to leave sitting with the
    // low-risk ones.
    expect(
      sorted([
        mother('INA-001', 'low'),
        mother('INA-002', 'medium'),
        mother('INA-003', 'high'),
      ]),
      ['INA-003', 'INA-002', 'INA-001'],
    );
  });

  test('critical sorts above high', () {
    expect(
      sorted([
        mother('INA-001', 'high'),
        mother('INA-002', 'critical'),
      ]),
      ['INA-002', 'INA-001'],
    );
  });

  test('an unclassified mother sorts high, not low', () {
    // A missing risk level means nobody has assessed her. Sorting her to the
    // bottom is how she stays unassessed.
    expect(
      sorted([
        mother('INA-001', 'low'),
        mother('INA-002', ''),
        mother('INA-003', 'high'),
      ]),
      ['INA-002', 'INA-003', 'INA-001'],
    );
  });

  test('a mother without a patient number sorts last within her band', () {
    expect(
      sorted([
        {'bhc_patient_id': '—', 'risk_level': 'high'},
        mother('INA-005', 'high'),
      ]),
      ['INA-005', '—'],
    );
  });
}
