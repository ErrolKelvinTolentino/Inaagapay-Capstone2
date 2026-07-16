// lib/models/vaccine_schedule.dart

enum VaccineStatus {
  done,
  pending,
  locked,
}

class VaccineDefinition {
  final String key; // 👈 unique ID (important for DB mapping)
  final String name;

  const VaccineDefinition({
    required this.key,
    required this.name,
  });
}

class VaccineAgeGroup {
  final String label; // e.g. "At Birth"
  final int week;
  final List<VaccineDefinition> vaccines;

  const VaccineAgeGroup({
    required this.label,
    required this.week,
    required this.vaccines,
  });
}

/// Hardcoded vaccine schedule for reference.
/// NOTE: The immunization screens (add_immunization_page.dart,
/// child_immunization_list_page.dart) query the `vaccines` DB table
/// directly. This hardcoded list and the VaccineList widget are
/// currently unused but kept as a reference for the DOH EPI schedule.
const List<VaccineAgeGroup> vaccineSchedule = [
  VaccineAgeGroup(
    label: 'At Birth',
    week: 0,
    vaccines: [
      VaccineDefinition(key: 'bcg', name: 'BCG'),
      VaccineDefinition(key: 'opv0', name: 'OPV 0'),
    ],
  ),
  VaccineAgeGroup(
    label: '6 Weeks',
    week: 6,
    vaccines: [
      VaccineDefinition(key: 'opv1', name: 'OPV 1'),
      VaccineDefinition(key: 'penta1', name: 'Pentavalent 1'),
      VaccineDefinition(key: 'pcv1', name: 'PCV 1'),
      VaccineDefinition(key: 'rota1', name: 'Rotavirus 1'),
    ],
  ),
  VaccineAgeGroup(
    label: '10 Weeks',
    week: 10,
    vaccines: [
      VaccineDefinition(key: 'opv2', name: 'OPV 2'),
      VaccineDefinition(key: 'penta2', name: 'Pentavalent 2'),
      VaccineDefinition(key: 'pcv2', name: 'PCV 2'),
      VaccineDefinition(key: 'rota2', name: 'Rotavirus 2'),
    ],
  ),
  VaccineAgeGroup(
    label: '14 Weeks',
    week: 14,
    vaccines: [
      VaccineDefinition(key: 'opv3', name: 'OPV 3'),
      VaccineDefinition(key: 'penta3', name: 'Pentavalent 3'),
      VaccineDefinition(key: 'pcv3', name: 'PCV 3'),
      VaccineDefinition(key: 'ipv', name: 'IPV'),
    ],
  ),
  VaccineAgeGroup(
    label: '6 Months',
    week: 26,
    vaccines: [
      VaccineDefinition(key: 'vita6', name: 'Vitamin A (1st dose)'),
    ],
  ),
  VaccineAgeGroup(
    label: '9 Months',
    week: 39,
    vaccines: [
      VaccineDefinition(key: 'mcv1', name: 'MCV 1 (Measles)'),
    ],
  ),
  VaccineAgeGroup(
    label: '12 Months',
    week: 52,
    vaccines: [
      VaccineDefinition(key: 'mcv2', name: 'MCV 2 (Measles)'),
      VaccineDefinition(key: 'mmr', name: 'MMR'),
      VaccineDefinition(key: 'vita12', name: 'Vitamin A (2nd dose)'),
    ],
  ),
];
