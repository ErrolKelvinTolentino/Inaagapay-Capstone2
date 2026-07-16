// lib/widgets/calculation_dropdown.dart

import 'package:flutter/material.dart';
import '../models/due_date_basis.dart';
import 'app_dropdown_field.dart';

class CalculationDropdown extends StatelessWidget {
  final DueDateBasis value;
  final ValueChanged<DueDateBasis> onChanged;

  const CalculationDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppDropdownField<DueDateBasis>(
      leadingIcon: Icons.calculate,
      hintText: 'Choose calculation method',
      options: DueDateBasis.values,
      value: value,
      displayStringForOption: (basis) => basis.label,
      onSelected: onChanged,
    );
  }
}