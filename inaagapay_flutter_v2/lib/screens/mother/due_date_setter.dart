// lib/screens/mother/due_date_setter.dart

import 'package:flutter/material.dart';
// Change these:
import '../../theme/app_colors.dart';
import '../../widgets/main_button.dart';
import '../../widgets/page_title.dart';
import '../../services/language_service.dart';
import '../../widgets/app_input_field.dart';
import '../../models/due_date_mode.dart';

class DueDateSetter extends StatefulWidget {
  final DueDateMode mode;

  const DueDateSetter({super.key, required this.mode});

  @override
  State<DueDateSetter> createState() => _DueDateSetterState();
}

class _DueDateSetterState extends State<DueDateSetter> {
  DateTime? _selectedDate;
  final TextEditingController _dateController = TextEditingController();

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    // Fix: Use proper date range
    final DateTime now = DateTime.now();
    final DateTime minDate = now;
    final DateTime maxDate = now.add(const Duration(days: 365));
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? minDate.add(const Duration(days: 280)),
      firstDate: minDate,
      lastDate: maxDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.brandPrimary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandPrimary,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = _formatDate(picked);
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 20),
              PageTitle(
                title: widget.mode == DueDateMode.pregnant
                    ? 'When is your due date?'
                    : 'When is the due date?',
                leadingIcon: Icons.calendar_today,
              ),
              const SizedBox(height: 32),
              
              // Fix: Make the input field tappable and remove readOnly issue
              GestureDetector(
                onTap: () => _selectDate(context),
                child: AbsorbPointer(
                  child: AppInputField(
                    hintText: LanguageService.translate(
                        'Select Date', 'Pumili ng Petsa'),
                    controller: _dateController,
                    leadingIcon: Icons.calendar_today,
                    readOnly: true,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              Text(
                LanguageService.translate('You can always update this later',
                    'Puwede mo itong baguhin mamaya'),
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              MainButton(
                label: LanguageService.translate('Continue', 'Magpatuloy'),
                onPressed: _selectedDate != null
                    ? () {
                        Navigator.pushNamed(
                          context,
                          '/congrats',
                          arguments: widget.mode,
                        );
                      }
                    : null,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}