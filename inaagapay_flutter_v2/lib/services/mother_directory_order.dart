class MotherDirectoryOrder {
  const MotherDirectoryOrder._();

  static int riskRank(Object? level) =>
      switch (level?.toString().toLowerCase().trim()) {
        'critical' => 0,
        'high' => 1,
        'medium' || 'moderate' => 2,
        'low' => 3,
        _ => 1,
      };

  static int? patientNumber(Map<String, dynamic> row) => int.tryParse(
        RegExp(r'\d+')
                .firstMatch(row['bhc_patient_id']?.toString() ?? '')
                ?.group(0) ??
            '',
      );

  static int compare(Map<String, dynamic> a, Map<String, dynamic> b,
      String criterion, bool ascending) {
    int nullable<T extends Comparable<dynamic>>(T? x, T? y) {
      if (x == null) return y == null ? 0 : 1;
      if (y == null) return -1;
      return ascending ? x.compareTo(y) : y.compareTo(x);
    }

    final result = switch (criterion) {
      'ID Number' => nullable(patientNumber(a), patientNumber(b)),
      'Name' => nullable(a['full_name']?.toString().toLowerCase(),
          b['full_name']?.toString().toLowerCase()),
      'Age' =>
        nullable((a['age'] as num?)?.toInt(), (b['age'] as num?)?.toInt()),
      'Due Date' => nullable(
          DateTime.tryParse(a['expected_due_date']?.toString() ?? ''),
          DateTime.tryParse(b['expected_due_date']?.toString() ?? '')),
      // Rank 0 is critical, so the default descending risk order is rank ASC.
      _ => ascending
          ? riskRank(b['risk_level']).compareTo(riskRank(a['risk_level']))
          : riskRank(a['risk_level']).compareTo(riskRank(b['risk_level'])),
    };
    if (result != 0) return result;
    final x = patientNumber(a), y = patientNumber(b);
    if (x == null && y != null) return 1;
    if (y == null && x != null) return -1;
    final byNumber = (x ?? 0).compareTo(y ?? 0);
    return byNumber != 0
        ? byNumber
        : ((a['mother_id'] as num?) ?? 0)
            .compareTo((b['mother_id'] as num?) ?? 0);
  }
}
