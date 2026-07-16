// lib/models/due_date_basis.dart

enum DueDateBasis {
  lmp,
  edd,
  aog,
}

extension DueDateBasisLabel on DueDateBasis {
  String get label {
    switch (this) {
      case DueDateBasis.lmp:
        return 'Last Menstrual Period';
      case DueDateBasis.edd:
        return 'Estimated Delivery Date';
      case DueDateBasis.aog:
        return 'Age of Gestation';
    }
  }
}
