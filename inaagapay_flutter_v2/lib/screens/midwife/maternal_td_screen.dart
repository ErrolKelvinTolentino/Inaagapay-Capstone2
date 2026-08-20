import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/maternal_td_service.dart';
import '../../services/sms_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/dialog_box.dart';
import '../../widgets/secondary_header.dart';

/// Dedicated maternal Td (tetanus-diphtheria) immunization module.
///
/// Features:
/// - Signature Pink Color Theme
/// - Administer Tab strictly dedicated to local administration ("Given Here")
///   with multi-dose open vial & sealed vial inventory deduction logic.
/// - Lifetime History Tab containing the full series history & Backfill Past Doses tool.
class MaternalTdScreen extends StatefulWidget {
  final int motherId;
  final String? motherName;
  final int? assignedBhcId;

  const MaternalTdScreen({
    super.key,
    required this.motherId,
    this.motherName,
    this.assignedBhcId,
  });

  @override
  State<MaternalTdScreen> createState() => _MaternalTdScreenState();
}

class _MaternalTdScreenState extends State<MaternalTdScreen> {
  int _activeTabIndex = 0; // 0: Administer, 1: Lifetime History

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  String _motherFullName = '';
  int? _bhcId;
  String _bhcName = 'Barangay Health Center';
  int? _midwifeId;

  /// Canonical, merged dose state.
  MaternalTdStatus _status = MaternalTdStatus.empty;

  DateTime _administrationDate = DateTime.now();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();

  // BHC Td inventory cache & vial logic
  int _tdStockAvailable = 0;
  int _tdSealedVials = 0;
  int _tdOpenVialDoses = 0;
  String? _tdOpenVialBatch;
  DateTime? _tdOpenVialOpenedAt;
  String? _tdNextBatch;
  String? _tdNextBatchExpiration;
  int _dosesPerUnit = 10;
  int _openVialShelfHours = 672; // 28 days for Td
  bool _isOpenVialExpired = false;
  bool _tdStockLoading = false;

  static final DateFormat _longDate = DateFormat('MMMM d, yyyy');

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = _longDate.format(_administrationDate);
    _motherFullName = widget.motherName ?? 'Mother';
    _bhcId = widget.assignedBhcId;
    _loadInitialData();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────── data loading

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = Supabase.instance.client;

      // 1. Resolve current midwife & BHC context
      final accountId = await AuthStorage.getUserId();
      if (accountId != null) {
        try {
          final ctx = await SupabaseService.getMidwifeContext(accountId);
          _midwifeId = (ctx['midwife_id'] as num?)?.toInt();
          _bhcId ??= (ctx['assigned_bhc_id'] as num?)?.toInt();
          if (ctx['bhc_name'] != null && ctx['bhc_name'].toString().isNotEmpty) {
            _bhcName = ctx['bhc_name'].toString();
          }
        } catch (e) {
          debugPrint('Error getting midwife context: $e');
        }
      }

      // 2. Mother profile details
      try {
        // `mothers` has no full_name and there is no `users` table — the name
        // lives on the linked account. The previous select named both and threw
        // every time, which silently cost us the mother's own BHC as a fallback
        // for _bhcId.
        final motherRes = await client
            .from('mothers')
            .select('assigned_bhc_id, account:account_id(first_name, middle_name, last_name)')
            .eq('mother_id', widget.motherId)
            .maybeSingle();

        if (motherRes != null) {
          _bhcId ??= (motherRes['assigned_bhc_id'] as num?)?.toInt();

          final acc = motherRes['account'] as Map<String, dynamic>?;
          final fn = [
            acc?['first_name'],
            acc?['middle_name'],
            acc?['last_name'],
          ].whereType<String>().where((p) => p.trim().isNotEmpty).join(' ');

          if (fn.isNotEmpty && widget.motherName == null) {
            _motherFullName = fn;
          }
        }
      } catch (e) {
        debugPrint('Maternal Td: mother profile read failed: $e');
      }

      // 3. Canonical dose state
      _status = await MaternalTdService.fetchStatus(widget.motherId);

      // 4. Default the administration date to the first legal day
      _resetAdministrationDate();

      // 5. BHC Td inventory & vial tracking
      await _loadBhcTdStock();
    } catch (e) {
      debugPrint('Error loading maternal Td data: $e');
      _errorMessage = 'Unable to load maternal immunization data: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Clamps the administration date into the window the RPC will accept:
  /// on or after the DOH-eligible date, and never in the future.
  void _resetAdministrationDate() {
    final today = DateTime.now();
    final floor = _status.nextEligibleDate;

    var d = today;
    if (floor != null && floor.isAfter(d)) d = floor;
    if (d.isAfter(today)) d = today;

    _administrationDate = d;
    _dateCtrl.text = _longDate.format(d);
  }

  Future<void> _loadBhcTdStock() async {
    setState(() => _tdStockLoading = true);

    try {
      final client = Supabase.instance.client;

      var query = client
          .from('inventory_batches')
          .select('batch_id, batch_number, quantity_remaining, doses_remaining_in_open_vial, vial_opened_at, expiration_date, status, facility_id, item:inventory_items(name, generic_name, item_type, doses_per_unit, open_vial_shelf_hours)')
          .eq('status', 'active');

      if (_bhcId != null) {
        query = query.eq('facility_id', _bhcId!);
      }

      final batches = await query.order('expiration_date', ascending: true);

      int sealedCount = 0;
      int openDosesCount = 0;
      String? openBatch;
      DateTime? openVialOpened;
      String? nextBatch;
      String? nextBatchExp;
      int totalDoses = 0;
      int dosesPerUnit = 10;
      int shelfHours = 672; // 28 days
      bool openVialExpired = false;

      final now = DateTime.now();

      for (final b in (batches as List<dynamic>)) {
        final expStr = b['expiration_date']?.toString();
        if (expStr != null) {
          final exp = DateTime.tryParse(expStr);
          if (exp != null && exp.isBefore(DateTime(now.year, now.month, now.day))) {
            continue; // Skip expired batches
          }
        }

        final item = b['item'] as Map<String, dynamic>?;
        if (item == null) continue;

        final name = (item['name']?.toString() ?? '').toLowerCase();
        final generic = (item['generic_name']?.toString() ?? '').toLowerCase();
        final isTd = name.contains('td') ||
            name.contains('tetanus') ||
            generic.contains('tetanus') ||
            generic.contains('diphtheria');
        if (!isTd) continue;

        dosesPerUnit = (item['doses_per_unit'] as num?)?.toInt() ?? 10;
        shelfHours = (item['open_vial_shelf_hours'] as num?)?.toInt() ?? 672;

        final qty = (b['quantity_remaining'] as num?)?.toInt() ?? 0;
        final openDoses = (b['doses_remaining_in_open_vial'] as num?)?.toInt() ?? 0;
        final openedAtStr = b['vial_opened_at']?.toString();

        if (openDoses > 0 && openBatch == null) {
          if (openedAtStr != null && shelfHours > 0) {
            final openedAt = DateTime.tryParse(openedAtStr);
            if (openedAt != null) {
              final hours = now.difference(openedAt).inHours;
              if (hours >= shelfHours) {
                openVialExpired = true;
              } else {
                openDosesCount += openDoses;
                openBatch = b['batch_number']?.toString();
                openVialOpened = openedAt;
              }
            }
          } else {
            openDosesCount += openDoses;
            openBatch = b['batch_number']?.toString();
          }
        }

        if (qty > 0) {
          sealedCount += qty;
          if (nextBatch == null) {
            nextBatch = b['batch_number']?.toString();
            nextBatchExp = expStr;
          }
          totalDoses += qty * dosesPerUnit;
        }
      }

      if (mounted) {
        setState(() {
          _dosesPerUnit = dosesPerUnit;
          _openVialShelfHours = shelfHours;
          _tdSealedVials = sealedCount;
          _tdOpenVialDoses = openDosesCount;
          _tdOpenVialBatch = openBatch;
          _tdOpenVialOpenedAt = openVialOpened;
          _isOpenVialExpired = openVialExpired;
          _tdNextBatch = nextBatch;
          _tdNextBatchExpiration = nextBatchExp;
          _tdStockAvailable = totalDoses + openDosesCount;
          _tdStockLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading BHC Td stock: $e');
      if (mounted) setState(() => _tdStockLoading = false);
    }
  }

  // ────────────────────────────────────────────────────────────────── actions

  Future<void> _selectDate() async {
    final today = DateTime.now();
    var first = _status.nextEligibleDate ?? DateTime(2000);
    if (first.isAfter(today)) first = today;

    final picked = await showDatePicker(
      context: context,
      initialDate: _administrationDate.isBefore(first) ? first : _administrationDate,
      firstDate: first,
      lastDate: today,
      helpText: 'Date ${_status.nextDoseKey ?? 'dose'} was given',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.brandPrimary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _administrationDate = picked;
        _dateCtrl.text = _longDate.format(picked);
      });
    }
  }

  Future<void> _submitAdministerDose() async {
    final doseKey = _status.nextDoseKey;

    if (doseKey == null || !_status.canAdministerToday) return;

    final formattedDate = _longDate.format(_administrationDate);
    final dateStr = DateFormat('yyyy-MM-dd').format(_administrationDate);

    String subtitle =
        'Are you sure you want to administer and record $doseKey for $_motherFullName on $formattedDate?\n\n'
        '• Administration Source: Given Here (At $_bhcName)';

    if (_tdOpenVialDoses > 0) {
      subtitle += '\n• Inventory Deduction: 1 dose will be deducted from active open vial (Batch #${_tdOpenVialBatch ?? "Active"}, $_tdOpenVialDoses doses remaining).';
    } else if (_tdSealedVials > 0) {
      final remInNewVial = _dosesPerUnit - 1;
      subtitle += '\n• Inventory Deduction: 1 new sealed vial will be opened from Batch #${_tdNextBatch ?? "Next"}. 1 dose will be used and $remInNewVial doses will remain open for 28 days.';
    } else {
      subtitle += '\n• Inventory Deduction: Stock deduction will be attempted from BHC inventory.';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmationDialogBox(
        title: 'Confirm $doseKey Administration',
        subtitle: subtitle,
        confirmText: 'Administer Dose',
        cancelText: 'Cancel',
        accentColor: AppColors.brandPrimary,
        onConfirm: () => Navigator.pop(context, true),
        onCancel: () => Navigator.pop(context, false),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final client = Supabase.instance.client;
      final res = await client.rpc('administer_maternal_td_dose', params: {
        'p_mother_id': widget.motherId,
        'p_dose_number': doseKey,
        'p_vaccination_date': dateStr,
        'p_facility_id': _bhcId,
        'p_administered_by': _midwifeId,
        'p_source': 'bhc', // Automatically Given Here
        'p_facility_name': null,
        'p_remarks': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
      });

      debugPrint('Administer Maternal Td RPC result: $res');

      final resMap = (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (resMap['success'] != true) {
        throw Exception(resMap['error'] ?? 'Could not save maternal Td record');
      }

      // Proactive SMS reminder
      try {
        final motherRes = await client
            .from('mothers')
            .select('account:account_id(phone_number)')
            .eq('mother_id', widget.motherId)
            .maybeSingle();

        final acc = motherRes?['account'] as Map<String, dynamic>?;
        final phone = acc?['phone_number']?.toString();

        if (phone != null && phone.isNotEmpty) {
          final nextDueStr = resMap['next_due_date'] != null
              ? ' Next dose is scheduled on ${_longDate.format(DateTime.parse(resMap['next_due_date'].toString()))}.'
              : '';
          await SmsService.sendSmsMessage(
            phone,
            'Inaagapay Update: Maternal $doseKey immunization recorded on $formattedDate.$nextDueStr',
          );
        }
      } catch (smsErr) {
        debugPrint('SMS notification non-fatal error: $smsErr');
      }

      if (mounted) {
        final mode = resMap['mode']?.toString();
        final remDoses = resMap['doses_left_in_vial'] ?? 0;
        var dialogContent = '$doseKey recorded successfully for $_motherFullName on $formattedDate as Given Here.';

        if (mode == 'open_vial_dose') {
          dialogContent += '\n\n1 dose deducted from the active open vial ($remDoses doses remaining in vial).';
        } else if (mode == 'new_vial_opened') {
          dialogContent += '\n\nOpened 1 new sealed vial ($remDoses doses remaining open).';
        }

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DialogBox(
            type: DialogType.success,
            title: '$doseKey Administered Successfully',
            content: dialogContent,
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );

        _remarksCtrl.clear();
        await _loadInitialData();
      }
    } catch (e) {
      debugPrint('Error administering maternal Td dose: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => DialogBox(
            type: DialogType.error,
            title: 'Error Saving Dose',
            content: e.toString().replaceAll('Exception: ', ''),
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // ────────────────────────────────────────────────────────────────── backfill

  void _showBackfillHistoryModal() {
    final backfillDates = <String, DateTime?>{
      for (final def in MaternalTdService.doseDefs)
        def.key: _status.recordFor(def.key)?.date,
    };

    final facilityCtrls = <String, TextEditingController>{
      for (final def in MaternalTdService.doseDefs)
        def.key: TextEditingController(
          text: _status.recordFor(def.key)?.facilityName ?? '',
        ),
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            String? getValidationMessage(String dKey) {
              final def = MaternalTdService.defFor(dKey);
              final cur = backfillDates[dKey];
              if (cur == null || def.number == 1) return null;

              final prevKey = 'Td${def.number - 1}';
              final prev = backfillDates[prevKey];
              if (prev == null) {
                return 'Please set the $prevKey date first before $dKey';
              }

              final days = cur.difference(prev).inDays;
              if (days < def.minIntervalDays) {
                return '$dKey must be at least ${def.minIntervalDays} days after $prevKey ($days days elapsed)';
              }
              return null;
            }

            final hasErrors = MaternalTdService.doseDefs
                .any((d) => getValidationMessage(d.key) != null);
            final filledCount =
                backfillDates.values.where((d) => d != null).length;

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Backfill Past Td Doses',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCE7F3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: AppColors.brandPrimary, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Record doses given anywhere else — a previous pregnancy card, another health center, a private clinic, or school records. DOH interval rules are enforced automatically.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.brandText,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...MaternalTdService.doseDefs.map((def) {
                          final dKey = def.key;
                          final pickedDate = backfillDates[dKey];
                          final errorMsg = getValidationMessage(dKey);

                          DateTime minDate = DateTime(1990);
                          if (def.number > 1) {
                            final prev = backfillDates['Td${def.number - 1}'];
                            if (prev != null) {
                              minDate = prev.add(Duration(days: def.minIntervalDays));
                            }
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: errorMsg != null
                                  ? const Color(0xFFFEF2F2)
                                  : (pickedDate != null ? const Color(0xFFFDF2F8) : Colors.grey.shade50),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: errorMsg != null
                                    ? const Color(0xFFFECACA)
                                    : (pickedDate != null ? const Color(0xFFFBCFE8) : Colors.grey.shade200),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        def.title,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (pickedDate != null && errorMsg == null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFCE7F3),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFFBCFE8)),
                                        ),
                                        child: const Text(
                                          'Valid Date',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.brandText,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          DateTime initDate = pickedDate ?? DateTime.now();
                                          if (initDate.isBefore(minDate)) initDate = minDate;
                                          if (initDate.isAfter(DateTime.now())) initDate = DateTime.now();

                                          final picked = await showDatePicker(
                                            context: modalCtx,
                                            initialDate: initDate,
                                            firstDate: minDate.isBefore(DateTime.now()) ? minDate : DateTime(1990),
                                            lastDate: DateTime.now(),
                                            builder: (context, child) {
                                              return Theme(
                                                data: Theme.of(context).copyWith(
                                                  colorScheme: const ColorScheme.light(
                                                    primary: AppColors.brandPrimary,
                                                    onPrimary: Colors.white,
                                                    onSurface: AppColors.textPrimary,
                                                  ),
                                                ),
                                                child: child!,
                                              );
                                            },
                                          );
                                          if (picked != null) {
                                            setModalState(() => backfillDates[dKey] = picked);
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: errorMsg != null
                                                  ? const Color(0xFFEF4444)
                                                  : Colors.grey.shade300,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.brandPrimary),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  pickedDate != null
                                                      ? _longDate.format(pickedDate)
                                                      : 'Select Past Date',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: pickedDate != null ? AppColors.textPrimary : Colors.grey.shade500,
                                                    fontWeight: pickedDate != null ? FontWeight.w600 : FontWeight.normal,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (pickedDate != null) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                                        onPressed: () =>
                                            setModalState(() => backfillDates[dKey] = null),
                                      ),
                                    ],
                                  ],
                                ),
                                if (errorMsg != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    errorMsg,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                                  ),
                                ],
                                if (pickedDate != null) ...[
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: facilityCtrls[dKey],
                                    decoration: InputDecoration(
                                      hintText: 'Administering clinic/hospital (optional)',
                                      hintStyle: TextStyle(fontSize: 11.5, color: Colors.grey.shade400),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: AppColors.brandPrimary),
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          offset: const Offset(0, -2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasErrors ? Colors.grey.shade400 : AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: hasErrors
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _saveBackfilledRecords(backfillDates, facilityCtrls);
                              },
                        child: Text(
                          filledCount == 0
                              ? 'Save Backfilled Doses'
                              : 'Save $filledCount Backfilled Dose${filledCount == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
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

  Future<void> _saveBackfilledRecords(
    Map<String, DateTime?> backfillDates,
    Map<String, TextEditingController> facilityCtrls,
  ) async {
    setState(() => _isSaving = true);

    try {
      final recordsToSave = <Map<String, dynamic>>[];
      backfillDates.forEach((doseKey, date) {
        if (date != null) {
          final fac = facilityCtrls[doseKey]?.text.trim();
          recordsToSave.add({
            'dose_number': doseKey,
            'vaccination_date': DateFormat('yyyy-MM-dd').format(date),
            'facility_name': (fac == null || fac.isEmpty) ? null : fac,
            'remarks': 'Historical backfill from patient card',
          });
        }
      });

      if (recordsToSave.isEmpty) {
        setState(() => _isSaving = false);
        return;
      }

      final client = Supabase.instance.client;
      final res = await client.rpc('backfill_maternal_td_history', params: {
        'p_mother_id': widget.motherId,
        'p_records': recordsToSave,
      });

      debugPrint('Backfill Td RPC result: $res');

      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => DialogBox(
            type: DialogType.success,
            title: 'History Updated',
            content: 'Successfully saved ${recordsToSave.length} historical maternal Td record${recordsToSave.length == 1 ? '' : 's'}.',
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );
        await _loadInitialData();
      }
    } catch (e) {
      debugPrint('Error backfilling Td records: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => DialogBox(
            type: DialogType.error,
            title: 'Error Saving History',
            content: e.toString().replaceAll('Exception: ', ''),
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Maternal Td Immunization',
          onBack: () => Navigator.pop(context, true),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary))
          : SafeArea(
              child: Column(
                children: [
                  if (_errorMessage != null) _buildErrorBanner(),
                  _buildHeroProtectionCard(),
                  _buildTabSwitcher(),
                  Expanded(
                    child: _activeTabIndex == 0
                        ? _buildAdministerTab()
                        : _buildLifetimeHistoryTab(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    Widget tab(int index, IconData icon, String label) {
      final active = _activeTabIndex == index;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _activeTabIndex = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: active ? AppColors.brandPrimary : const Color(0xFF64748B)),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.bold : FontWeight.w500,
                        color: active ? AppColors.brandPrimary : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          tab(0, Icons.vaccines_rounded, 'Administer'),
          tab(1, Icons.history_rounded, 'Lifetime History'),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────── hero card

  Widget _buildHeroProtectionCard() {
    final highestDose = _status.highestCompletedDose;
    final isPab = _status.isProtectedAtBirth;
    final isFim = _status.isFim;

    // One hue, three depths. The previous version switched to crimson (0xFFE11D48)
    // the moment the mother reached PAB and to burgundy at FIM, so the screen
    // turned red exactly when the news was good — off-brand and alarming.
    // Progress now reads as the brand pink deepening.
    late final Color startColor;
    late final Color endColor;
    if (isFim) {
      startColor = const Color(0xFF9E2A5F); // deepest — series complete
      endColor = AppColors.brandText;
    } else if (isPab) {
      startColor = AppColors.brandText;
      endColor = AppColors.brandAccent;
    } else {
      startColor = AppColors.brandAccent;
      endColor = AppColors.brandPrimary;
    }

    String statusTitle;
    String statusSubtitle;
    if (isFim) {
      statusTitle = 'Fully Immunized Mother (FIM)';
      statusSubtitle = 'Lifetime maternal and infant protection achieved';
    } else if (highestDose == 0) {
      statusTitle = 'No Td Recorded';
      statusSubtitle = 'Needs Td1 as early as possible in pregnancy';
    } else if (isPab) {
      statusTitle = 'Td$highestDose Completed';
      statusSubtitle = 'Infant Protected at Birth (PAB)';
    } else {
      statusTitle = 'Td$highestDose Completed (Priming)';
      statusSubtitle = 'Not yet protected — Td2 gives infant protection';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [startColor, endColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: startColor.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _motherFullName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isFim ? 'FIM STATUS' : (isPab ? 'PAB ACTIVE' : 'UNPROTECTED'),
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            statusTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            statusSubtitle,
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 10),
          _buildHeroNextChip(),
        ],
      ),
    );
  }

  Widget _buildHeroNextChip() {
    final next = _status.nextDoseKey;
    final action = _status.nextAction;

    IconData icon;
    String label;

    switch (action) {
      case TdNextAction.complete:
        icon = Icons.verified_rounded;
        label = 'All 5 doses complete — no further Td needed';
        break;
      case TdNextAction.eligibleNow:
        icon = Icons.event_available_rounded;
        label = '$next is due now';
        break;
      case TdNextAction.waiting:
        final on = _status.nextEligibleDate;
        final days = _status.daysUntilEligible;
        icon = Icons.schedule_rounded;
        label = on == null
            ? '$next not due yet'
            : 'Next: $next on ${_longDate.format(on)} · in $days ${days == 1 ? 'day' : 'days'}';
        break;
      case TdNextAction.missingPrevious:
        icon = Icons.report_problem_rounded;
        label = '${_status.blockingDoseKey} record missing — see Lifetime History';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────── administer

  Widget _buildAdministerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DOH 5-Dose Progress',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          _buildDoseProgressRow(),
          const SizedBox(height: 14),

          // Clean "Given Here" Local Health Center attribution banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCE7F3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 16, color: AppColors.brandPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Administering at $_bhcName (Given Here)',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // The administration workflow
          switch (_status.nextAction) {
            TdNextAction.complete => _buildCompleteCard(),
            TdNextAction.missingPrevious => _buildMissingPreviousCard(),
            TdNextAction.waiting => _buildNotDueCard(),
            TdNextAction.eligibleNow => _buildAdministerForm(),
          },
        ],
      ),
    );
  }

  /// Read-only progress strip in signature pink theme.
  Widget _buildDoseProgressRow() {
    final nextKey = _status.nextDoseKey;
    final dueNow = _status.canAdministerToday;

    return Row(
      children: MaternalTdService.doseDefs.map((def) {
        final dKey = def.key;
        final rec = _status.recordFor(dKey);
        final isCompleted = rec != null;
        final isNext = dKey == nextKey;

        Color cardBg = const Color(0xFFF8FAFC);
        Color borderColor = const Color(0xFFE2E8F0);
        Color textColor = const Color(0xFF94A3B8);
        String statusLabel = 'Locked';
        IconData statusIcon = Icons.lock_outline_rounded;

        if (isCompleted) {
          cardBg = const Color(0xFFFDF2F8);
          borderColor = const Color(0xFFFBCFE8);
          textColor = AppColors.brandText;
          statusLabel = rec.date != null
              ? DateFormat('MMM d, yy').format(rec.date!)
              : 'Done';
          statusIcon = Icons.check_circle_rounded;
        } else if (isNext) {
          if (dueNow) {
            cardBg = AppColors.brandPrimary;
            borderColor = AppColors.brandAccent;
            textColor = Colors.white;
            statusLabel = 'Due now';
            statusIcon = Icons.star_rounded;
          } else if (_status.nextAction == TdNextAction.missingPrevious) {
            cardBg = const Color(0xFFFFFBEB);
            borderColor = const Color(0xFFFDE68A);
            textColor = const Color(0xFF92400E);
            statusLabel = 'Blocked';
            statusIcon = Icons.report_problem_rounded;
          } else {
            final on = _status.nextEligibleDate;
            cardBg = const Color(0xFFFFF1F5);
            borderColor = const Color(0xFFFBCFE8);
            textColor = AppColors.brandText;
            statusLabel = on == null ? 'Pending' : DateFormat('MMM d, yy').format(on);
            statusIcon = Icons.schedule_rounded;
          }
        }

        return Expanded(
          flex: isNext ? 11 : 9,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(vertical: isNext ? 12 : 9, horizontal: 2),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: isNext ? 2.0 : 1.0),
                boxShadow: (isNext && dueNow)
                    ? [
                        BoxShadow(
                          color: AppColors.brandPrimary.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dKey,
                          style: TextStyle(
                            fontSize: isNext ? 13.5 : 12.5,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(statusIcon, size: isNext ? 12 : 10, color: textColor),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: isNext ? FontWeight.bold : FontWeight.w500,
                        color: textColor.withValues(alpha: isNext ? 1.0 : 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// All five doses on file.
  Widget _buildCompleteCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF2F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFBCFE8)),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_rounded, size: 52, color: AppColors.brandAccent),
          const SizedBox(height: 10),
          const Text(
            'Fully Immunized Mother',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.brandText),
          ),
          const SizedBox(height: 6),
          const Text(
            'All 5 Td doses are recorded. She has lifetime protection against maternal and neonatal tetanus — no further Td vaccination is needed.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.brandText, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// The series cannot advance because an earlier dose has no record.
  Widget _buildMissingPreviousCard() {
    final blocking = _status.blockingDoseKey ?? 'the previous dose';
    final next = _status.nextDoseKey ?? 'the next dose';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.report_problem_rounded, size: 20, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$blocking has no record',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$next cannot be given until $blocking is on file, because the DOH interval is measured from it. '
            'If she already received $blocking somewhere else, record it in the Lifetime History tab.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.history_edu_rounded, size: 18),
              label: const Text(
                'Go to Lifetime History',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                setState(() => _activeTabIndex = 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// On schedule, but the DOH interval has not elapsed yet.
  Widget _buildNotDueCard() {
    final next = _status.nextDoseKey ?? '';
    final on = _status.nextEligibleDate;
    final days = _status.daysUntilEligible;
    final def = MaternalTdService.defFor(next);
    final protectedUntil = _status.protectionUntil;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCE7F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_busy_rounded, size: 20, color: AppColors.brandAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'No Td dose needed today',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.brandText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'She is on schedule. $next is not due yet — DOH requires ${def.minIntervalLabel.toLowerCase()}.',
            style: const TextStyle(fontSize: 12, color: AppColors.brandText, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: '$next DUE ON',
                  value: on == null ? '—' : DateFormat('MMM d, yyyy').format(on),
                  icon: Icons.event_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'TIME REMAINING',
                  value: '$days ${days == 1 ? 'day' : 'days'}',
                  icon: Icons.hourglass_bottom_rounded,
                ),
              ),
            ],
          ),
          if (protectedUntil != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.shield_rounded, size: 14, color: AppColors.brandAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Current protection runs until ${_longDate.format(protectedUntil)}.',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.brandText),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFBCFE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.brandAccent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandAccent,
                    letterSpacing: 0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.brandText),
            ),
          ),
        ],
      ),
    );
  }

  /// The administration form — automatically "Given Here" with real-time stock deduction preview.
  Widget _buildAdministerForm() {
    final doseKey = _status.nextDoseKey!;
    final def = MaternalTdService.defFor(doseKey);
    final outOfStock = _bhcId != null && !_tdStockLoading && _tdStockAvailable <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dose Due Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_available_rounded, size: 20, color: AppColors.brandPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$doseKey is due now',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.brandText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                def.protection,
                style: const TextStyle(fontSize: 11.5, color: AppColors.brandText, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Multi-Dose & Open Vial Inventory Status Card
        if (_bhcId != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: outOfStock ? const Color(0xFFFEF2F2) : const Color(0xFFFDF2F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: outOfStock ? const Color(0xFFFECACA) : const Color(0xFFFBCFE8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      outOfStock ? Icons.warning_amber_rounded : Icons.inventory_2_rounded,
                      size: 18,
                      color: outOfStock ? const Color(0xFFDC2626) : AppColors.brandAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        outOfStock
                            ? 'No Td stock at this health center'
                            : 'BHC Stock: $_tdStockAvailable doses available',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: outOfStock ? const Color(0xFF991B1B) : AppColors.brandText,
                        ),
                      ),
                    ),
                    if (!outOfStock)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _tdOpenVialDoses > 0 ? 'Open Vial Active' : 'Sealed Vials',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brandText,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (outOfStock)
                  const Text(
                    'Please restock Td vaccines in inventory before administering.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF991B1B)),
                  )
                else ...[
                  if (_tdOpenVialDoses > 0) ...[
                    Text(
                      '• Active Open Vial: Batch #${_tdOpenVialBatch ?? "Active"} has $_tdOpenVialDoses doses remaining.',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF4A0E2E), height: 1.3),
                    ),
                    Text(
                      '• Deduction: 1 dose will be drawn from the open vial ($_tdOpenVialDoses - 1 = ${_tdOpenVialDoses - 1} left).',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF701A75), height: 1.3, fontWeight: FontWeight.w600),
                    ),
                  ] else if (_tdSealedVials > 0) ...[
                    Text(
                      '• Sealed Stock: Batch #${_tdNextBatch ?? "Next"} ($_tdSealedVials sealed vials available).',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF4A0E2E), height: 1.3),
                    ),
                    Text(
                      '• Deduction: 1 new sealed vial will be opened. 1 dose given, ${_dosesPerUnit - 1} doses will remain open for 28 days.',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF701A75), height: 1.3, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (_isOpenVialExpired)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Note: Previous open vial expired (> 28 days) and will be auto-discarded.',
                        style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        const Text(
          'Vaccination Date',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _selectDate,
          child: AbsorbPointer(
            child: AppInputField(
              hintText: 'Vaccination Date',
              controller: _dateCtrl,
              leadingIcon: Icons.calendar_month_rounded,
              isRequired: true,
            ),
          ),
        ),
        const SizedBox(height: 14),

        const Text(
          'Remarks / Notes (Optional)',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        AppInputField(
          hintText: 'e.g. Given right deltoid, no adverse reaction',
          controller: _remarksCtrl,
          leadingIcon: Icons.notes_rounded,
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.vaccines_rounded, size: 18),
            label: Text(
              _isSaving ? 'Saving Record...' : 'Record $doseKey Dose (Given Here)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: _isSaving ? null : _submitAdministerDose,
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────── history

  Widget _buildLifetimeHistoryTab() {
    final nextKey = _status.nextDoseKey;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'DOH 5-Dose Td Timeline',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          '${_status.completedCount} of 5 doses recorded',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),

        // Backfill Past Doses prompt card placed at the top of Lifetime History
        _buildBackfillPrompt(),
        const SizedBox(height: 16),

        ...MaternalTdService.doseDefs.map((def) {
          final dKey = def.key;
          final rec = _status.recordFor(dKey);
          final isDone = rec != null;
          final isNext = dKey == nextKey;

          final formattedDate =
              rec?.date != null ? _longDate.format(rec!.date!) : null;
          final facName = rec?.facilityName ?? (rec?.source == 'bhc' ? _bhcName : 'External Health Center');

          String statusLabel;
          Color chipBg;
          Color chipFg;
          if (isDone) {
            statusLabel = 'Completed';
            chipBg = const Color(0xFFFCE7F3);
            chipFg = AppColors.brandText;
          } else if (isNext && _status.canAdministerToday) {
            statusLabel = 'Due now';
            chipBg = const Color(0xFFFFF1F5);
            chipFg = AppColors.brandText;
          } else if (isNext && _status.nextAction == TdNextAction.missingPrevious) {
            statusLabel = 'Blocked';
            chipBg = const Color(0xFFFEF3C7);
            chipFg = const Color(0xFF92400E);
          } else if (isNext) {
            statusLabel = 'Scheduled';
            chipBg = const Color(0xFFFFF1F5);
            chipFg = AppColors.brandText;
          } else {
            statusLabel = 'Pending';
            chipBg = const Color(0xFFF1F5F9);
            chipFg = const Color(0xFF64748B);
          }

          String subtitle;
          if (isDone) {
            subtitle = formattedDate != null
                ? 'Given on $formattedDate · $facName'
                : 'Recorded · $facName';
          } else if (isNext && _status.canAdministerToday) {
            subtitle = 'Eligible today';
          } else if (isNext && _status.nextEligibleDate != null) {
            subtitle =
                'Due ${_longDate.format(_status.nextEligibleDate!)} · in ${_status.daysUntilEligible} days';
          } else {
            subtitle = 'Interval: ${def.minIntervalLabel}';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDone ? const Color(0xFFFDF2F8) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDone
                    ? const Color(0xFFFBCFE8)
                    : (isNext ? AppColors.brandPrimary.withValues(alpha: 0.4) : Colors.grey.shade200),
                width: isNext && !isDone ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.brandText
                        : (isNext ? AppColors.brandPrimary.withValues(alpha: 0.12) : Colors.grey.shade100),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      dKey,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: isDone
                            ? Colors.white
                            : (isNext ? AppColors.brandPrimary : Colors.grey.shade700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              def.title,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: chipBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: chipFg),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isDone ? FontWeight.w600 : FontWeight.w500,
                          color: isDone ? AppColors.brandText : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        def.protection,
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBackfillPrompt() {
    final missing = MaternalTdService.doseDefs
        .where((d) => !_status.has(d.key))
        .map((d) => d.key)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFBCFE8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.history_edu_rounded, size: 18, color: AppColors.brandPrimary),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Doses given somewhere else?',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            missing.isEmpty
                ? 'Every dose is on file. You can still open the history editor to correct a recorded date or facility.'
                : 'Add doses from a previous pregnancy card, another health center, or a private clinic. '
                    'Still missing: ${missing.join(', ')}.',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandPrimary,
                backgroundColor: AppColors.brandSecondary,
                side: const BorderSide(color: AppColors.brandPrimary, width: 1.4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
              label: const Text(
                'Backfill Past Doses',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              onPressed: _showBackfillHistoryModal,
            ),
          ),
        ],
      ),
    );
  }
}
