// lib/screens/midwife/immunization_ocr_review_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import 'add_immunization_choice.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/main_button.dart';
import '../../widgets/dialog_box.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/branded_date_picker.dart';
import '../../services/sms_service.dart';
import '../../services/notification_service.dart';
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';

class ReviewItem {
  final String vaccineNameRaw;
  final int doseNumberRaw;
  final String dateRaw;
  final String? remarksRaw;
  
  int? matchedVaccineId;
  DateTime? vaccinationDate;
  String remarks;
  bool isSelected;
  bool alreadyTaken;

  ReviewItem({
    required this.vaccineNameRaw,
    required this.doseNumberRaw,
    required this.dateRaw,
    this.remarksRaw,
    this.matchedVaccineId,
    this.vaccinationDate,
    required this.remarks,
    this.isSelected = true,
    this.alreadyTaken = false,
  });
}

class ImmunizationOcrReviewPage extends StatefulWidget {
  final int childId;
  final List<Map<String, dynamic>> extractedVaccines;
  final List<Map<String, dynamic>> allVaccines;
  final Set<int> takenVaccineIds;
  final DateTime? childBirthdate;

  /// Carried through from the entry choice. A scanned card is a history that
  /// may span several facilities, so these records must not silently claim
  /// this centre administered them.
  final ImmunizationSource source;

  const ImmunizationOcrReviewPage({
    super.key,
    required this.childId,
    required this.extractedVaccines,
    required this.allVaccines,
    required this.takenVaccineIds,
    this.childBirthdate,
    this.source = ImmunizationSource.outside,
  });

  @override
  State<ImmunizationOcrReviewPage> createState() => _ImmunizationOcrReviewPageState();
}

class _ImmunizationOcrReviewPageState extends State<ImmunizationOcrReviewPage> {
  final List<ReviewItem> _reviewItems = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeReviewItems();
  }

  void _initializeReviewItems() {
    for (final extracted in widget.extractedVaccines) {
      final nameRaw = extracted['vaccine_name_raw']?.toString() ?? '';
      final doseRaw = (extracted['dose_number'] as num?)?.toInt() ?? 1;
      final dateRaw = extracted['date_raw']?.toString() ?? '';
      final parsedDateStr = extracted['parsed_date']?.toString();
      final remarksRaw = extracted['remarks']?.toString();

      // Attempt parsing date
      DateTime? initialDate;
      if (parsedDateStr != null && parsedDateStr.isNotEmpty) {
        try {
          initialDate = DateTime.parse(parsedDateStr);
        } catch (_) {}
      }

      // Try to find the best matching vaccine in database
      final matchedId = _findBestMatch(nameRaw, doseRaw);
      final alreadyTaken = matchedId != null && widget.takenVaccineIds.contains(matchedId);

      _reviewItems.add(
        ReviewItem(
          vaccineNameRaw: nameRaw,
          doseNumberRaw: doseRaw,
          dateRaw: dateRaw,
          remarksRaw: remarksRaw,
          matchedVaccineId: matchedId,
          vaccinationDate: initialDate,
          remarks: remarksRaw ?? '',
          isSelected: !alreadyTaken && matchedId != null, // Auto-uncheck if already taken
          alreadyTaken: alreadyTaken,
        ),
      );
    }
  }

  int? _findBestMatch(String rawName, int dose) {
    final lower = rawName.toLowerCase();
    
    // Determine the type of vaccine
    String? searchKeyword;
    if (lower.contains('bcg')) {
      searchKeyword = 'bcg';
    } else if (lower.contains('hepa') || lower.contains('hepatitis')) {
      searchKeyword = 'hepatitis';
    } else if (lower.contains('penta') || lower.contains('dpt')) {
      searchKeyword = 'pentavalent';
    } else if (lower.contains('opv') || (lower.contains('polio') && lower.contains('oral'))) {
      searchKeyword = 'oral polio';
    } else if (lower.contains('ipv') || (lower.contains('polio') && lower.contains('inactivated'))) {
      searchKeyword = 'inactivated polio';
    } else if (lower.contains('pcv') || lower.contains('pneumo')) {
      searchKeyword = 'pneumococcal';
    } else if (lower.contains('mmr') || lower.contains('measles')) {
      searchKeyword = 'measles';
    } else if (lower.contains('rota')) {
      searchKeyword = 'rotavirus';
    }

    if (searchKeyword == null) return null;

    // Search in the master database vaccines list
    for (final v in widget.allVaccines) {
      final dbName = (v['vaccine_name']?.toString() ?? '').toLowerCase();
      final dbDose = (v['dose_number'] as num?)?.toInt() ?? 1;

      if (dbName.contains(searchKeyword) && dbDose == dose) {
        return v['vaccine_id'] as int;
      }
    }
    
    return null;
  }

  Future<void> _selectDate(ReviewItem item) async {
    final picked = await showBrandedDatePicker(
      context: context,
      initialDate: item.vaccinationDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        item.vaccinationDate = picked;
      });
    }
  }

  void _showVaccinePickerSheet(ReviewItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = widget.allVaccines.where((v) {
              final name = (v['vaccine_name']?.toString() ?? '').toLowerCase();
              final dose = (v['dose_number']?.toString() ?? '');
              final q = searchQuery.toLowerCase().trim();
              if (q.isEmpty) return true;
              return name.contains(q) || dose.contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderPrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select Vaccine',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose the corresponding vaccine record in the system',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    onChanged: (q) => setSheetState(() => searchQuery = q),
                    decoration: InputDecoration(
                      hintText: 'Search vaccine...',
                      hintStyle: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.brandAccent, size: 20),
                      filled: true,
                      fillColor: AppColors.bgSecondary,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: AppColors.borderPrimary),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: AppColors.borderPrimary),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                            color: AppColors.brandPrimary, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, color: AppColors.borderPrimary),
                      itemBuilder: (ctx, idx) {
                        final v = filtered[idx];
                        final id = v['vaccine_id'] as int;
                        final name = v['vaccine_name']?.toString() ?? '';
                        final dose = v['dose_number']?.toString() ?? '';
                        final isSelected = item.matchedVaccineId == id;
                        final isAlreadyTaken =
                            widget.takenVaccineIds.contains(id);

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.brandPrimary
                                      .withValues(alpha: 0.15)
                                  : AppColors.brandPrimary
                                      .withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.vaccines_outlined,
                              color: AppColors.brandPrimary,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            '$name (Dose $dose)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          subtitle: isAlreadyTaken
                              ? const Text(
                                  'Already recorded for this child',
                                  style: TextStyle(
                                      fontSize: 11.5, color: AppColors.success),
                                )
                              : null,
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded,
                                  color: AppColors.brandPrimary, size: 22)
                              : const Icon(Icons.chevron_right_rounded,
                                  color: AppColors.textSecondary),
                          onTap: () {
                            setState(() {
                              item.matchedVaccineId = id;
                              item.alreadyTaken = isAlreadyTaken;
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getRecommendedAgeText(ReviewItem item) {
    if (item.matchedVaccineId == null) return '';
    final vaccine = widget.allVaccines.firstWhere(
      (v) => v['vaccine_id'] == item.matchedVaccineId,
      orElse: () => <String, dynamic>{},
    );
    if (vaccine.isEmpty) return '';
    final rec = (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0.0;
    if (rec == 0.0) return 'At birth';
    if (rec == 1.5) return '6 weeks';
    if (rec == 2.5) return '10 weeks';
    if (rec == 3.5) return '14 weeks';
    
    if (rec % 1 == 0) {
      final monthsInt = rec.toInt();
      return '$monthsInt month${monthsInt != 1 ? 's' : ''}';
    } else {
      return '$rec months';
    }
  }

  String? _getAgeValidationWarning(ReviewItem item) {
    if (item.vaccinationDate == null || item.matchedVaccineId == null) {
      return null;
    }
    
    if (widget.childBirthdate == null) {
      return null;
    }
    
    if (item.vaccinationDate!.isBefore(widget.childBirthdate!)) {
      return "Vaccination date cannot be before the child's birthdate.";
    }
    
    final vaccine = widget.allVaccines.firstWhere(
      (v) => v['vaccine_id'] == item.matchedVaccineId,
      orElse: () => <String, dynamic>{},
    );
    if (vaccine.isEmpty) return null;
    
    final recommendedAge = (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0.0;
    
    final ageDays = item.vaccinationDate!.difference(widget.childBirthdate!).inDays;
    final ageMonths = ageDays / 30.44;
    
    if (ageMonths < (recommendedAge - 0.25)) {
      final recText = _getRecommendedAgeText(item);
      return "Vaccination date is before the recommended age ($recText).";
    }
    
    return null;
  }

  String? get _validationError {
    final selectedItems = _reviewItems.where((item) => item.isSelected).toList();
    if (selectedItems.isEmpty) return null;

    final Set<int> seenVaccineIds = {};
    for (final item in selectedItems) {
      if (item.matchedVaccineId == null || item.vaccinationDate == null) {
        return 'Make sure all selected vaccines have a valid match and date.';
      }
      if (widget.childBirthdate != null && item.vaccinationDate!.isBefore(widget.childBirthdate!)) {
        return "Vaccination date cannot be before the child's birthdate.";
      }
      if (seenVaccineIds.contains(item.matchedVaccineId!)) {
        return 'Duplicate vaccine matches selected. You can only record a vaccine once.';
      }
      seenVaccineIds.add(item.matchedVaccineId!);
    }
    return null;
  }

  bool get _isFormValid => _validationError == null;

  Future<void> _saveRecords() async {
    final selectedItems = _reviewItems.where((item) => item.isSelected).toList();
    if (selectedItems.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final client = Supabase.instance.client;
      final List<Map<String, dynamic>> recordsToInsert = [];

      int? midwifeId;
      try {
        final accountId = await AuthStorage.getUserId();
        if (accountId != null) {
          final ctx = await SupabaseService.getMidwifeContext(accountId);
          midwifeId = ctx['midwife_id'] as int?;
        }
      } catch (e) {
        debugPrint('Error getting midwife ID: $e');
      }

      for (final item in selectedItems) {
        final vaccine = widget.allVaccines.firstWhere(
          (v) => v['vaccine_id'] == item.matchedVaccineId,
          orElse: () => <String, dynamic>{},
        );

        recordsToInsert.add({
          'child_id': widget.childId,
          'vaccine_id': item.matchedVaccineId!,
          'vaccination_date': DateFormat('yyyy-MM-dd').format(item.vaccinationDate!),
          // Without this the column falls back to its default of 1, so every
          // scanned dose was stored as a first dose.
          'dose_number': (vaccine['dose_number'] as num?)?.toInt() ?? 1,
          'remarks': item.remarks.trim().isEmpty ? null : item.remarks.trim(),
          'created_at': DateTime.now().toIso8601String(),
          'source': widget.source.dbValue,
          // Who transcribed the card — always this midwife.
          if (midwifeId != null) 'recorded_by': midwifeId,
          // Who gave the dose. Only claimed when the card is being recorded
          // as doses this centre administered.
          if (midwifeId != null && widget.source == ImmunizationSource.thisBhc)
            'administered_by': midwifeId,
          // A scanned card is documentary evidence by definition.
          if (widget.source == ImmunizationSource.outside)
            'evidence': 'immunization_card',
        });
      }

      // Perform bulk upsert to handle overlapping records that were already taken but confirmed to overwrite
      await client.from('immunization_records').upsert(
            recordsToInsert,
            onConflict: 'child_id,vaccine_id',
          );

      // Trigger automated vaccine SMS in the background
      try {
        final List<String> recordedVaccines = [];
        for (final item in selectedItems) {
          final vaccine = widget.allVaccines.firstWhere(
            (v) => v['vaccine_id'] == item.matchedVaccineId,
            orElse: () => <String, dynamic>{},
          );
          if (vaccine.isNotEmpty) {
            final vName = vaccine['vaccine_name']?.toString() ?? '';
            final vDose = vaccine['dose_number']?.toString() ?? '';
            recordedVaccines.add('$vName (Dose $vDose)');
          }
        }
        if (recordedVaccines.isNotEmpty) {
          SmsService.sendAutomatedVaccineSms(
            childId: widget.childId,
            recordedVaccines: recordedVaccines,
          );

          // ── Push notification for the mother ──────────────────────
          try {
            final childRow = await client
                .from('children')
                .select('mother_id')
                .eq('child_id', widget.childId)
                .maybeSingle();
            final motherId = childRow?['mother_id'] as int?;
            if (motherId != null) {
              final motherRow = await client
                  .from('mothers')
                  .select('account_id')
                  .eq('mother_id', motherId)
                  .maybeSingle();
              final motherAccountId = motherRow?['account_id'] as int?;
              if (motherAccountId != null) {
                final vaccineList = recordedVaccines.length <= 3
                    ? recordedVaccines.join(', ')
                    : '${recordedVaccines.take(3).join(', ')} and ${recordedVaccines.length - 3} more';
                await NotificationService.createNotification(
                  accountId: motherAccountId,
                  title: 'Vaccines Recorded',
                  message: '$vaccineList ${recordedVaccines.length == 1 ? 'has' : 'have'} been recorded for your child.',
                  type: 'vaccine_reminder',
                );
              }
            }
          } catch (pushError) {
            debugPrint('Error sending vaccine push notification: $pushError');
          }
        }
      } catch (smsError) {
        debugPrint('Error triggering automated vaccine SMS: $smsError');
      }

      if (mounted) {
        setState(() => _isSaving = false);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DialogBox(
            type: DialogType.success,
            title: 'Records Saved',
            content: '${recordsToInsert.length} immunization records have been successfully saved.',
            buttonText: 'OK',
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pop(context, true); // Return success to previous screen
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving bulk immunizations: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        showDialog(
          context: context,
          builder: (_) => DialogBox(
            type: DialogType.error,
            title: 'Save Failed',
            content: e.toString().replaceAll('Exception: ', ''),
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );
      }
    }
  }

  void _confirmSave() {
    final hasAgeWarning = _reviewItems.any((item) =>
        item.isSelected &&
        _getAgeValidationWarning(item) != null &&
        !_getAgeValidationWarning(item)!.contains('birthdate'));

    final hasAlreadyTakenWarning = _reviewItems.any((item) =>
        item.isSelected && item.alreadyTaken);

    final hasWarning = hasAgeWarning || hasAlreadyTakenWarning;

    String subtitle = 'Please review all vaccine matches and dates. Growth and immunization records cannot be modified once added.';
    if (hasWarning) {
      if (hasAlreadyTakenWarning) {
        subtitle = 'Warning: One or more selected vaccines have already been recorded for this child. Are you sure you want to save them?';
      } else {
        subtitle = 'Warning: One or more selected vaccines are scheduled before their recommended age. Are you sure you want to save them?';
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmationDialogBox(
        title: 'Confirm Bulk Save',
        subtitle: subtitle,
        confirmText: 'Save Records',
        cancelText: 'Cancel',
        accentColor: hasWarning ? AppColors.warning : AppColors.brandPrimary,
        onCancel: () => Navigator.pop(context),
        onConfirm: () {
          Navigator.pop(context);
          _saveRecords();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _reviewItems.where((item) => item.isSelected).toList().length;

    // Partition review items for separation and grouping
    final beforeBirth = _reviewItems.where((item) {
      return widget.childBirthdate != null && 
             item.vaccinationDate != null && 
             item.vaccinationDate!.isBefore(widget.childBirthdate!);
    }).toList();

    final earlyDoses = _reviewItems.where((item) {
      if (widget.childBirthdate == null || item.vaccinationDate == null || item.matchedVaccineId == null) {
        return false;
      }
      if (item.vaccinationDate!.isBefore(widget.childBirthdate!)) {
        return false;
      }
      final vaccine = widget.allVaccines.firstWhere(
        (v) => v['vaccine_id'] == item.matchedVaccineId,
        orElse: () => <String, dynamic>{},
      );
      if (vaccine.isEmpty) return false;
      final recommendedAge = (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0.0;
      final ageDays = item.vaccinationDate!.difference(widget.childBirthdate!).inDays;
      final ageMonths = ageDays / 30.44;
      return ageMonths < (recommendedAge - 0.25);
    }).toList();

    final validMatches = _reviewItems.where((item) {
      return !beforeBirth.contains(item) && !earlyDoses.contains(item);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Review Extracted Vaccines',
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isSaving
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.brandPrimary),
                    SizedBox(height: 16),
                    Text(
                      'Recording immunizations...',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // Instruction Card
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.brandPrimary.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.info_outline_rounded,
                            color: AppColors.brandPrimary, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Below are the vaccines detected from the card photo. Please review the vaccine matches, dates, and select which ones to record.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      children: [
                        if (validMatches.isNotEmpty) ...[
                          _buildSectionHeader(
                            'Standard Schedule Matches',
                            'These matches align with the standard recommended age schedule.',
                            AppColors.success,
                            icon: Icons.check_circle_outline_rounded,
                          ),
                          ...validMatches.map((item) => _buildReviewCard(item)),
                        ],
                        if (earlyDoses.isNotEmpty) ...[
                          _buildSectionHeader(
                            'Outside Recommended Age Doses',
                            'These vaccines were administered earlier than the standard recommended age. Please verify before saving.',
                            AppColors.warning,
                            icon: Icons.warning_amber_rounded,
                          ),
                          ...earlyDoses.map((item) => _buildReviewCard(item)),
                        ],
                        if (beforeBirth.isNotEmpty) ...[
                          _buildSectionHeader(
                            'Invalid Doses (Before Birth)',
                            'These vaccination dates are before the child\'s birthdate and cannot be saved.',
                            AppColors.error,
                            icon: Icons.error_outline_rounded,
                          ),
                          ...beforeBirth.map((item) => _buildReviewCard(item)),
                        ],
                      ],
                    ),
                  ),

                  // Bottom Action Bar
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: const Border(
                        top: BorderSide(color: AppColors.borderPrimary, width: 1.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_isFormValid && selectedCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Center(
                              child: Text(
                                _validationError ?? 'Make sure all selected vaccines have a valid match and date.',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        MainButton(
                          label: selectedCount == 0
                              ? 'Select records to save'
                              : 'Record $selectedCount Immunization${selectedCount != 1 ? 's' : ''}',
                          onPressed: _isFormValid ? _confirmSave : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String disclaimer, Color color, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            if (disclaimer.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                disclaimer,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.85),
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTag(ReviewItem item) {
    if (item.alreadyTaken) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 11),
            SizedBox(width: 4),
            Text(
              'Already recorded',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.childBirthdate != null &&
        item.vaccinationDate != null &&
        item.vaccinationDate!.isBefore(widget.childBirthdate!)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Invalid Date',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.error,
          ),
        ),
      );
    }

    if (item.matchedVaccineId != null && item.vaccinationDate != null) {
      final warningMsg = _getAgeValidationWarning(item);
      if (warningMsg != null) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Outside Rec. Age',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9A5B18),
            ),
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Schedule Match',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        );
      }
    }

    if (item.matchedVaccineId == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Unmatched',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildReviewCard(ReviewItem item) {
    final warningMsg = _getAgeValidationWarning(item);

    final selectedVaccine = widget.allVaccines.firstWhere(
      (v) => v['vaccine_id'] == item.matchedVaccineId,
      orElse: () => <String, dynamic>{},
    );
    final selectedVaccineText = selectedVaccine.isNotEmpty
        ? '${selectedVaccine['vaccine_name']} (Dose ${selectedVaccine['dose_number']})'
        : 'Select vaccine match *';

    final dateText = item.vaccinationDate != null
        ? DateFormat('yyyy-MM-dd').format(item.vaccinationDate!)
        : 'Select Date *';

    return Opacity(
      opacity: item.isSelected ? 1.0 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: item.isSelected
                ? AppColors.brandPrimary.withValues(alpha: 0.3)
                : AppColors.borderPrimary,
            width: item.isSelected ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Toggle Selection and Raw Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  activeColor: AppColors.brandPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  value: item.isSelected,
                  onChanged: (val) {
                    setState(() {
                      item.isSelected = val ?? false;
                    });
                  },
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.vaccineNameRaw} (Dose ${item.doseNumberRaw})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (item.dateRaw.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Date on card: ${item.dateRaw}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusTag(item),
                    ],
                  ),
                ),
              ],
            ),

            if (item.isSelected) ...[
              const SizedBox(height: 14),

              // Match Dropdown Input Field
              GestureDetector(
                onTap: () => _showVaccinePickerSheet(item),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: item.matchedVaccineId != null
                          ? AppColors.borderPrimary
                          : AppColors.error.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.vaccines_outlined,
                          color: AppColors.brandAccent, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          selectedVaccineText,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: item.matchedVaccineId != null
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Date Picker and Remarks in Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Picker
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _selectDate(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.borderPrimary, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded,
                                color: AppColors.brandAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dateText,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: item.vaccinationDate != null
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Remarks
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.borderPrimary, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notes_rounded,
                              color: AppColors.brandAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              onChanged: (val) {
                                item.remarks = val;
                              },
                              controller: TextEditingController.fromValue(
                                TextEditingValue(
                                  text: item.remarks,
                                  selection: TextSelection.collapsed(
                                      offset: item.remarks.length),
                                ),
                              ),
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'Remarks',
                                hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (warningMsg != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: warningMsg.contains('birthdate')
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: warningMsg.contains('birthdate')
                          ? AppColors.error.withValues(alpha: 0.3)
                          : AppColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        warningMsg.contains('birthdate')
                            ? Icons.error_outline_rounded
                            : Icons.warning_amber_rounded,
                        color: warningMsg.contains('birthdate')
                            ? AppColors.error
                            : AppColors.warning,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warningMsg,
                          style: TextStyle(
                            fontSize: 11,
                            color: warningMsg.contains('birthdate')
                                ? AppColors.error
                                : const Color(0xFFB78103),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

