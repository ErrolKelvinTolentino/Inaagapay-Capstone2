import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/due_date_basis.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_input_field.dart';

class StartPregnancyScreen extends StatefulWidget {
  const StartPregnancyScreen({
    super.key,
    required this.motherId,
    this.motherName,
  });

  final int motherId;
  final String? motherName;

  @override
  State<StartPregnancyScreen> createState() => _StartPregnancyScreenState();
}

class _StartPregnancyScreenState extends State<StartPregnancyScreen> {
  final DateFormat _dateFmt = DateFormat('MMM d, yyyy');
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _weeksController = TextEditingController();
  final TextEditingController _daysController = TextEditingController();

  DueDateBasis _basis = DueDateBasis.lmp;
  DateTime? _lmp;
  DateTime? _edd;
  String? _aogInputError;
  bool _submitting = false;

  static const int _maxGestationDays = 294; // 42 weeks
  static const Map<String, int> _impossibleIntervalThresholds = {
    'live_birth': 1,
    'stillbirth': 30,
    'miscarriage': 30,
    'abortion': 20,
    'ectopic': 20,
  };

  static const Map<String, int> _recommendedIntervalThresholds = {
    'live_birth': 180,
    'stillbirth': 180,
    'miscarriage': 90,
    'abortion': 90,
    'ectopic': 90,
  };

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _normalize(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  void _resetInputs() {
    _lmp = null;
    _edd = null;
    _aogInputError = null;
    _dateController.clear();
    _weeksController.clear();
    _daysController.clear();
  }

  void _setBasis(DueDateBasis basis) {
    setState(() {
      _basis = basis;
      _resetInputs();
    });
  }

  void _updateFromLmp(DateTime lmp) {
    final normalized = _normalize(lmp);
    setState(() {
      _lmp = normalized;
      _edd = normalized.add(const Duration(days: 280));
      _dateController.text = _dateFmt.format(normalized);
    });
  }

  void _updateFromEdd(DateTime edd) {
    final normalized = _normalize(edd);
    setState(() {
      _edd = normalized;
      _lmp = normalized.subtract(const Duration(days: 280));
      _dateController.text = _dateFmt.format(normalized);
    });
  }

  void _updateFromAog() {
    final weeksText = _weeksController.text.trim();
    final daysText = _daysController.text.trim();

    if (weeksText.isEmpty && daysText.isEmpty) {
      setState(() {
        _lmp = null;
        _edd = null;
        _aogInputError = null;
      });
      return;
    }

    final weeks = int.tryParse(weeksText);
    final days = int.tryParse(daysText.isEmpty ? '0' : daysText);
    if (weeks == null || days == null) {
      setState(() {
        _lmp = null;
        _edd = null;
        _aogInputError = 'Use whole numbers for weeks and days.';
      });
      return;
    }

    if (weeks < 0 || weeks > 42) {
      setState(() {
        _lmp = null;
        _edd = null;
        _aogInputError = 'Weeks must be between 0 and 42.';
      });
      return;
    }

    if (days < 0 || days > 6) {
      setState(() {
        _lmp = null;
        _edd = null;
        _aogInputError = 'Days must be between 0 and 6.';
      });
      return;
    }

    final totalDays = (weeks * 7) + days;
    if (totalDays <= 0 || totalDays > _maxGestationDays) {
      setState(() {
        _lmp = null;
        _edd = null;
        _aogInputError = 'AOG must be between 1 day and 42 weeks.';
      });
      return;
    }

    final lmp = _today.subtract(Duration(days: totalDays));
    setState(() {
      _lmp = lmp;
      _edd = lmp.add(const Duration(days: 280));
      _aogInputError = null;
    });
  }

  String _formatAogFromLmp() {
    if (_lmp == null) return '—';
    final days = _today.difference(_lmp!).inDays;
    if (days < 0) return '—';
    final weeks = days ~/ 7;
    final remDays = days % 7;
    return '${weeks}w ${remDays}d';
  }

  String? _validate() {
    if (_lmp == null || _edd == null) {
      return 'Provide gestational information to compute LMP and EDD.';
    }

    if (_basis == DueDateBasis.aog && _aogInputError != null) {
      return _aogInputError;
    }

    if (_lmp!.isAfter(_today)) {
      return 'LMP cannot be in the future.';
    }

    final gestationDays = _today.difference(_lmp!).inDays;
    if (gestationDays < 0) {
      return 'Gestational age cannot be negative.';
    }
    if (gestationDays > _maxGestationDays) {
      return 'Current gestational age exceeds 42 weeks. Verify the date.';
    }

    final spanDays = _edd!.difference(_lmp!).inDays;
    if (spanDays != 280) {
      return 'EDD must be exactly 280 days from LMP.';
    }

    return null;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return null;
    return _normalize(parsed);
  }

  String _outcomeLabel(String outcome) {
    switch (outcome) {
      case 'live_birth':
        return 'live birth';
      case 'stillbirth':
        return 'stillbirth';
      case 'miscarriage':
        return 'miscarriage';
      case 'abortion':
        return 'abortion';
      case 'ectopic':
        return 'ectopic pregnancy';
      default:
        return 'pregnancy outcome';
    }
  }

  String? _validatePregnancyInterval(List<dynamic> endedPregnancies) {
    if (_lmp == null || endedPregnancies.isEmpty) return null;

    final normalizedRecords = endedPregnancies
        .map((row) {
          final map = row as Map<String, dynamic>;
          final outcomeDate = _parseDate(map['outcome_date']);
          final endedAt = _parseDate(map['ended_at']);
          final endDate = outcomeDate ?? endedAt;
          return {
            'outcome': (map['outcome'] ?? '').toString(),
            'endDate': endDate,
          };
        })
        .where((row) => row['endDate'] != null)
        .toList();

    if (normalizedRecords.isEmpty) return null;

    normalizedRecords.sort((a, b) {
      final aDate = a['endDate'] as DateTime;
      final bDate = b['endDate'] as DateTime;
      return bDate.compareTo(aDate);
    });

    final latest = normalizedRecords.first;
    final lastOutcome = latest['outcome'] as String;
    final lastEndDate = latest['endDate'] as DateTime;
    final intervalDays = _lmp!.difference(lastEndDate).inDays;

    if (intervalDays < 0) {
      return 'LMP is before the last ended pregnancy date (${_dateFmt.format(lastEndDate)}).';
    }

    final impossibleMin = _impossibleIntervalThresholds[lastOutcome] ?? 30;
    if (intervalDays < impossibleMin) {
      return 'Pregnancy interval of $intervalDays days after ${_outcomeLabel(lastOutcome)} is biologically impossible (minimum: $impossibleMin days).';
    }

    final recommendedMin = _recommendedIntervalThresholds[lastOutcome] ?? 90;
    if (intervalDays < recommendedMin) {
      return 'Pregnancy interval is too short ($intervalDays days). Minimum enforced interval after ${_outcomeLabel(lastOutcome)} is $recommendedMin days.';
    }

    return null;
  }

  Future<void> _pickDate() async {
    final now = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _basis == DueDateBasis.edd
          ? (_edd ?? now.add(const Duration(days: 1)))
          : (_lmp ?? now),
      firstDate: _basis == DueDateBasis.edd
          ? now.subtract(const Duration(days: 14))
          : now.subtract(const Duration(days: _maxGestationDays)),
      lastDate:
          _basis == DueDateBasis.edd ? now.add(const Duration(days: 280)) : now,
    );

    if (picked != null) {
      if (_basis == DueDateBasis.lmp) {
        _updateFromLmp(picked);
      } else {
        _updateFromEdd(picked);
      }
    }
  }

  Future<void> _submit() async {
    final message = _validate();
    if (message != null) {
      AppSnackbar.warning(context, message);
      return;
    }

    setState(() => _submitting = true);
    try {
      final client = Supabase.instance.client;

      final existing = await client
          .from('pregnancies')
          .select('pregnancy_id')
          .eq('mother_id', widget.motherId)
          .eq('status', 'ongoing')
          .maybeSingle();

      if (existing != null) {
        throw Exception('This mother already has an ongoing pregnancy.');
      }

      final endedPregnancies = await client
          .from('pregnancies')
          .select('outcome, outcome_date, ended_at')
          .eq('mother_id', widget.motherId)
          .eq('status', 'ended');

      final intervalError = _validatePregnancyInterval(endedPregnancies);
      if (intervalError != null) {
        throw Exception(intervalError);
      }

      await client.from('pregnancies').insert({
        'mother_id': widget.motherId,
        'last_menstrual_period': _lmp!.toIso8601String().split('T')[0],
        'expected_date_of_delivery': _edd!.toIso8601String().split('T')[0],
        'status': 'ongoing',
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.brandPrimary,
        ),
      ),
    );
  }

  Widget _basisChip(
    DueDateBasis basis,
    IconData icon,
    String subtitle,
  ) {
    final selected = _basis == basis;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _setBasis(basis),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brandPrimary.withValues(alpha: 0.13)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  selected ? AppColors.brandPrimary : AppColors.borderPrimary,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color:
                    selected ? AppColors.brandPrimary : AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(height: 6),
              Text(
                basis == DueDateBasis.lmp
                    ? 'LMP'
                    : basis == DueDateBasis.edd
                        ? 'EDD'
                        : 'AOG',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color:
                      selected ? AppColors.brandPrimary : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brandAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
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
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Start Pregnancy'),
        backgroundColor: AppColors.bgPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.brandPrimary.withValues(alpha: 0.15),
                              AppColors.brandAccent.withValues(alpha: 0.07),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                AppColors.brandPrimary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.motherName?.trim().isNotEmpty == true
                                  ? widget.motherName!.trim()
                                  : 'New pregnancy record',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Provide LMP, EDD, or AOG. The app computes and validates gestation and pregnancy interval before saving.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _sectionTitle('1) Calculation basis'),
                      Row(
                        children: [
                          _basisChip(
                            DueDateBasis.lmp,
                            Icons.calendar_today_rounded,
                            'Last period date',
                          ),
                          const SizedBox(width: 8),
                          _basisChip(
                            DueDateBasis.edd,
                            Icons.event_rounded,
                            'Due date',
                          ),
                          const SizedBox(width: 8),
                          _basisChip(
                            DueDateBasis.aog,
                            Icons.timeline_rounded,
                            'Weeks and days',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _sectionTitle('2) Provide value'),
                      if (_basis == DueDateBasis.lmp ||
                          _basis == DueDateBasis.edd)
                        AppInputField(
                          hintText: _basis == DueDateBasis.lmp
                              ? 'Tap to choose LMP date'
                              : 'Tap to choose EDD date',
                          controller: _dateController,
                          readOnly: true,
                          onTap: _pickDate,
                          trailingIcon: Icons.calendar_month,
                          onTrailingTap: _pickDate,
                          isRequired: true,
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: AppInputField(
                                    hintText: 'Weeks (0-42)',
                                    controller: _weeksController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    onChanged: (_) => _updateFromAog(),
                                    isRequired: true,
                                    errorText: _aogInputError,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: AppInputField(
                                    hintText: 'Days (0-6)',
                                    controller: _daysController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    onChanged: (_) => _updateFromAog(),
                                  ),
                                ),
                              ],
                            ),
                            if (_aogInputError == null)
                              const Padding(
                                padding: EdgeInsets.only(top: 6, left: 12),
                                child: Text(
                                  'Accepted range: 1 day to 42 weeks.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      _sectionTitle('3) Computed values'),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderPrimary),
                        ),
                        child: Column(
                          children: [
                            _infoRow(
                              'LMP',
                              _lmp == null ? '—' : _dateFmt.format(_lmp!),
                              Icons.calendar_today,
                            ),
                            _infoRow(
                              'Current AOG',
                              _formatAogFromLmp(),
                              Icons.timeline,
                            ),
                            _infoRow(
                              'EDD',
                              _edd == null ? '—' : _dateFmt.format(_edd!),
                              Icons.event,
                            ),
                            const SizedBox(height: 4),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.shield_outlined,
                                  size: 17,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Pregnancy interval constraints will be checked before saving.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary.withValues(
                                        alpha: 0.95,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Start Pregnancy'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
