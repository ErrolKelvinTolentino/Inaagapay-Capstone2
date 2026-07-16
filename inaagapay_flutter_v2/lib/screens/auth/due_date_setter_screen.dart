// lib/screens/auth/due_date_setter_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/headline.dart';
import '../../../widgets/main_button.dart';
import '../../../widgets/calculation_dropdown.dart';
import '../../../widgets/aog_input.dart';
import '../../../models/due_date_basis.dart';
import '../../../services/supabase_service.dart';
import '../../../services/auth_storage.dart';

enum DueDateMode { pregnant, supporting }

class DueDateSetterScreen extends StatefulWidget {
  final DueDateMode mode;
  final int? motherId;
  final int? pregnancyId;

  const DueDateSetterScreen({
    super.key,
    required this.mode,
    this.motherId,
    this.pregnancyId,
  });

  @override
  State<DueDateSetterScreen> createState() => _DueDateSetterScreenState();
}

class _DueDateSetterScreenState extends State<DueDateSetterScreen> {
  DueDateBasis _basis = DueDateBasis.lmp;
  bool _isLoading = false;

  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _weeksController = TextEditingController();
  final TextEditingController _daysController = TextEditingController();

  DateTime? _selectedDate;
  int? _motherId;

  @override
  void initState() {
    super.initState();
    _loadMotherId();
  }

  Future<void> _loadMotherId() async {
    if (widget.motherId != null) {
      _motherId = widget.motherId;
      return;
    }

    final motherId = await AuthStorage.getMotherId();
    if (motherId != null && mounted) {
      setState(() {
        _motherId = motherId;
      });
    }
  }

  Future<void> _pickDateForBasis() async {
    final now = DateTime.now();

    DateTime initialDate;
    DateTime firstDate;
    DateTime lastDate;

    if (_basis == DueDateBasis.edd) {
      initialDate = _selectedDate ?? now.add(const Duration(days: 280));
      firstDate = now;
      lastDate = now.add(const Duration(days: 365));
    } else {
      initialDate = _selectedDate ?? now.subtract(const Duration(days: 30));
      firstDate = now.subtract(const Duration(days: 365));
      lastDate = now;
    }

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: _basis == DueDateBasis.lmp
          ? 'Select first day of last menstrual period'
          : 'Select estimated delivery date',
    );

    if (pickedDate != null && mounted) {
      setState(() {
        _selectedDate = pickedDate;
        _dateController.text = DateFormat('MM/dd/yyyy').format(pickedDate);
      });
    }
  }

  void _clearDate() {
    setState(() {
      _selectedDate = null;
      _dateController.clear();
    });
  }

  Future<void> _savePregnancy() async {
    if (_basis == DueDateBasis.lmp && _selectedDate == null) {
      _showError('Please select your last menstrual period date');
      return;
    }

    if (_basis == DueDateBasis.edd && _selectedDate == null) {
      _showError('Please select the estimated delivery date');
      return;
    }

    if (_basis == DueDateBasis.aog) {
      final weeks = int.tryParse(_weeksController.text.trim());
      final days = int.tryParse(_daysController.text.trim());

      if (weeks == null || (weeks == 0 && (days == null || days == 0))) {
        _showError('Please enter the age of gestation');
        return;
      }
    }

    if (_motherId == null) {
      _showError('Unable to identify mother account');
      return;
    }

    setState(() => _isLoading = true);

    try {
      DateTime? lmp;
      DateTime? edd;

      if (_basis == DueDateBasis.lmp && _selectedDate != null) {
        lmp = _selectedDate;
        edd = _selectedDate!.add(const Duration(days: 280));
      } else if (_basis == DueDateBasis.edd && _selectedDate != null) {
        edd = _selectedDate;
        lmp = _selectedDate!.subtract(const Duration(days: 280));
      } else if (_basis == DueDateBasis.aog) {
        final weeks = int.tryParse(_weeksController.text.trim()) ?? 0;
        final days = int.tryParse(_daysController.text.trim()) ?? 0;
        final totalDays = (weeks * 7) + days;
        lmp = DateTime.now().subtract(Duration(days: totalDays));
        edd = lmp.add(const Duration(days: 280));
      }

      if (lmp == null || edd == null) {
        throw Exception('Could not calculate dates');
      }

      await SupabaseService.client.from('pregnancies').insert({
        'mother_id': _motherId,
        'last_menstrual_period': DateFormat('yyyy-MM-dd').format(lmp),
        'expected_date_of_delivery': DateFormat('yyyy-MM-dd').format(edd),
        'status': 'ongoing',
        'fetal_count': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/congrats',
          arguments: widget.mode,
        );
      }
    } catch (e) {
      _showError('Failed to save pregnancy: ${e.toString()}');
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _dateController.dispose();
    _weeksController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPregnant = widget.mode == DueDateMode.pregnant;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Image.asset('assets/images/logo.png', height: 90),
              const SizedBox(height: 24),
              Headline(
                text: isPregnant ? 'Set Your Due Date' : 'Set Their Due Date',
              ),
              const SizedBox(height: 12),
              Text(
                isPregnant
                    ? 'This helps us give you weekly updates tailored to your pregnancy journey'
                    : 'This helps us give you weekly updates tailored to their pregnancy journey',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Calculate Based on:',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CalculationDropdown(
                value: _basis,
                onChanged: (value) {
                  setState(() {
                    _basis = value;
                    _clearDate();
                  });
                },
              ),
              const SizedBox(height: 24),
              if (_basis == DueDateBasis.lmp || _basis == DueDateBasis.edd)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _pickDateForBasis,
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: _selectedDate != null
                                ? AppColors.brandPrimary
                                : AppColors.borderPrimary,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(15),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: _selectedDate != null
                                  ? AppColors.brandPrimary
                                  : AppColors.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _dateController.text.isEmpty
                                    ? (_basis == DueDateBasis.lmp
                                        ? 'First day of last menstrual period'
                                        : 'Estimated delivery date')
                                    : _dateController.text,
                                style: TextStyle(
                                  color: _dateController.text.isEmpty
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (_selectedDate != null)
                              GestureDetector(
                                onTap: _clearDate,
                                child: Icon(
                                  Icons.clear,
                                  color: AppColors.textSecondary,
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.brandPrimary.withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 24,
                            color: AppColors.brandPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isPregnant
                                  ? 'Not sure of the exact date?\nYour closest estimate works too!'
                                  : 'Not sure of the exact date?\nTheir closest estimate works too!',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              if (_basis == DueDateBasis.aog)
                AogInput(
                  weeksController: _weeksController,
                  daysController: _daysController,
                ),
              const Spacer(),
              MainButton(
                label: _isLoading
                    ? 'Saving...'
                    : (isPregnant
                        ? 'Calculate My Due Date'
                        : 'Calculate Their Due Date'),
                onPressed: _isLoading ? null : _savePregnancy,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
