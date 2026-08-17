// lib/screens/midwife/midwife_vaccination_drive_page.dart
//
// Scheduling a vaccination drive, and inviting the mothers who need it.
//
// One action, one confirmation. Scheduling a drive and telling mothers about
// it are the same intent, so the screen does not ask twice — but messaging
// thirty pregnant women spends SMS credits and cannot be recalled, so the
// confirmation names the count before anything goes out, and the drive is
// written first: nobody is told to come in for a drive that failed to save.
//
// The recipient list is on screen throughout, with each mother's name and how
// many TD doses she has had, so the count in the dialog is never a surprise.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';
import '../../services/vaccination_drive_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/branded_date_picker.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/main_button.dart';
import '../../widgets/secondary_header.dart';

class MidwifeVaccinationDrivePage extends StatefulWidget {
  const MidwifeVaccinationDrivePage({super.key});

  @override
  State<MidwifeVaccinationDrivePage> createState() =>
      _MidwifeVaccinationDrivePageState();
}

class _MidwifeVaccinationDrivePageState
    extends State<MidwifeVaccinationDrivePage> {
  final TextEditingController _notesCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _sending = false;

  int? _bhcId;
  String _facilityName = 'this health center';

  List<DriveVaccine> _vaccines = [];
  DriveVaccine? _selectedVaccine;
  DateTime? _date;

  List<DriveRecipient> _recipients = [];
  bool _loadingRecipients = false;

  DriveNotificationResult? _sendResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId != null) {
        final context = await SupabaseService.getMidwifeContext(accountId);
        _bhcId = context['assigned_bhc_id'] as int?;
        final name = context['bhc_name']?.toString();
        if (name != null && name.isNotEmpty) _facilityName = name;
      }

      final bhcId = _bhcId;
      if (bhcId != null) {
        _vaccines = await VaccinationDriveService.fetchDriveVaccines(
          bhcId: bhcId,
        );
      }

      // TD is the usual drive, so it starts selected — but never a vaccine
      // that cannot actually be given today.
      final selectable = _vaccines.where((v) => v.canBeScheduled).toList();
      if (selectable.isNotEmpty) {
        _selectedVaccine = selectable.firstWhere(
          (v) => v.name.toLowerCase().contains('td') && !v.forChildren,
          orElse: () => selectable.first,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _refreshRecipients();
    }
  }

  Future<void> _refreshRecipients() async {
    final bhcId = _bhcId;
    if (bhcId == null) return;

    final vaccine = _selectedVaccine;
    if (vaccine == null) return;

    setState(() => _loadingRecipients = true);
    // The drive date is passed because eligibility depends on it: a mother
    // whose last dose was recent may not be due on the 20th but is on the
    // 30th, and a child may only reach the scheduled age in between.
    final recipients = vaccine.forChildren
        ? await VaccinationDriveService.fetchChildrenDueForVaccine(
            bhcId: bhcId,
            vaccine: vaccine,
            driveDate: _date,
          )
        : await VaccinationDriveService.fetchMothersDueForDose(
            bhcId: bhcId,
            driveDate: _date,
          );
    if (!mounted) return;
    setState(() {
      _recipients = recipients;
      _loadingRecipients = false;
    });
  }

  String get _vaccineName => _selectedVaccine?.name ?? 'Vaccine';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // The app's own picker, as used by every other date field. The bare
    // Material showDatePicker looked like a different product.
    final picked = await showBrandedDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      // Who is due depends on the date chosen, so the list is rebuilt against
      // it rather than left showing yesterday's answer.
      _refreshRecipients();
    }
  }

  /// Saves the drive, then messages the mothers who need it.
  ///
  /// The drive is written first and the send only happens if that succeeded —
  /// nobody should be told to come in for a drive that was never recorded.
  Future<void> _scheduleAndNotify() async {
    final bhcId = _bhcId;
    final vaccineId = _selectedVaccine?.vaccineId;
    final date = _date;

    if (bhcId == null || vaccineId == null || date == null) {
      AppSnackbar.show(context, 'Choose a vaccine and a date first',
          type: AppSnackType.warning);
      return;
    }

    final reachable = _recipients.where((r) => !r.isUnreachable).length;

    // Text messages cannot be unsent, so the count is stated before anything
    // goes out rather than reported afterwards.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmationDialogBox(
        title: 'Schedule and notify $reachable '
            '${reachable == 1 ? 'mother' : 'mothers'}?',
        subtitle: 'The drive goes on the calendar for '
            '${DateFormat('MMMM d').format(date)}, and they get a text message '
            'and an email about it. Messages cannot be taken back once sent.',
        confirmText: 'Schedule & send',
        cancelText: 'Not yet',
        onConfirm: () => Navigator.pop(dialogContext, true),
        onCancel: () => Navigator.pop(dialogContext, false),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final driveId = await VaccinationDriveService.createDrive(
      bhcId: bhcId,
      vaccineId: vaccineId,
      date: date,
      notes: _notesCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
    });

    // Nobody is told to come in for a drive that was never recorded.
    if (driveId == null) {
      AppSnackbar.show(context,
          'Could not save the drive, so nothing was sent. Please try again.',
          type: AppSnackType.error);
      return;
    }

    if (reachable == 0) {
      AppSnackbar.show(
        context,
        'Drive scheduled for ${DateFormat('MMMM d, yyyy').format(date)}. '
        'No mother on this list has a phone or email, so tell them in person.',
        type: AppSnackType.warning,
      );
      return;
    }

    setState(() => _sending = true);
    final result = await VaccinationDriveService.notify(
      recipients: _recipients,
      vaccineName: _vaccineName,
      date: date,
      facilityName: _facilityName,
      notes: _notesCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sendResult = result;
    });

    AppSnackbar.show(
      context,
      result.summary,
      type: (result.failed > 0 || result.unreachable > 0)
          ? AppSnackType.warning
          : AppSnackType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            SecondaryHeader(
              title: 'Schedule Vaccination Drive',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.brandPrimary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _card(
                            title: 'Drive details',
                            child: Column(
                              children: [
                                // Stock is shown on every option and an empty
                                // shelf cannot be chosen — scheduling a drive
                                // for a vaccine the centre does not have is a
                                // wasted trip for every mother invited.
                                AppDropdownField<DriveVaccine>(
                                  hintText: 'Vaccine',
                                  leadingIcon: Icons.vaccines_outlined,
                                  value: _selectedVaccine,
                                  options: _vaccines,
                                  displayStringForOption: (v) => v.menuLabel,
                                  isOptionEnabled: (v) => v.canBeScheduled,
                                  onSelected: (v) {
                                    setState(() => _selectedVaccine = v);
                                    _refreshRecipients();
                                  },
                                ),
                                const SizedBox(height: 12),
                                GestureDetector(
                                  onTap: _pickDate,
                                  child: AbsorbPointer(
                                    child: AppInputField(
                                      controller: TextEditingController(
                                        text: _date == null
                                            ? ''
                                            : DateFormat('MMMM d, yyyy (EEEE)')
                                                .format(_date!),
                                      ),
                                      hintText: 'Date of the drive',
                                      leadingIcon: Icons.event_outlined,
                                      readOnly: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppInputField(
                                  controller: _notesCtrl,
                                  hintText: 'Notes (optional) — e.g. 8am-12nn',
                                  leadingIcon: Icons.notes_outlined,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _recipientsCard(),
                          const SizedBox(height: 20),
                          // One action, not two. Saving a drive and telling
                          // mothers about it are the same intent, so the
                          // screen no longer asks her to press twice — the
                          // confirmation dialog is where she reviews and
                          // agrees, and it still names how many people are
                          // about to be messaged. Text messages cannot be
                          // recalled, so that step stays.
                          MainButton(
                            label: _saving
                                ? 'Saving…'
                                : _sending
                                    ? 'Sending…'
                                    : (_sendResult != null
                                        ? 'Scheduled and sent'
                                        : 'Schedule drive & notify mothers'),
                            showIcons: false,
                            onPressed:
                                _saving || _sending || _sendResult != null
                                    ? null
                                    : _scheduleAndNotify,
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recipientsCard() {
    final unreachable = _recipients.where((r) => r.isUnreachable).length;

    return _card(
      title: 'Who will be invited',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedVaccine?.forChildren == true
                ? 'Children old enough for this dose who have not had it yet. '
                    'Their mother is the one messaged — she is the contact on '
                    'file — and the message names the child to bring.'
                : 'Pregnant mothers whose TD series is incomplete and who are '
                    'far enough past their last dose for the next one to '
                    'count. The series runs to TD5; TD2 is what protects the '
                    'baby at birth.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingRecipients)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.brandPrimary)),
                SizedBox(width: 12),
                Text('Checking records…',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ]),
            )
          else if (_recipients.isEmpty)
            const Text(
              'Nobody is due on this date — either their series is complete, '
              'or their last dose is too recent for the next one to count yet. '
              'Try a later date.',
              style: TextStyle(fontSize: 13, color: AppColors.success),
            )
          else ...[
            Row(
              children: [
                Text(
                  '${_recipients.length}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brandPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedVaccine?.forChildren == true
                        ? (_recipients.length == 1
                            ? 'child is due — their mother will be told'
                            : 'children are due — their mothers will be told')
                        : (_recipients.length == 1
                            ? 'mother will be invited'
                            : 'mothers will be invited'),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._recipients.take(12).map(_recipientRow),
            if (_recipients.length > 12)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('+${_recipients.length - 12} more',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ),
            if (unreachable > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$unreachable ${unreachable == 1 ? 'mother has' : 'mothers have'} '
                  'no phone number or email on file and cannot be messaged. '
                  'They will need telling in person.',
                  style: const TextStyle(
                      fontSize: 11, height: 1.35, color: AppColors.textPrimary),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _recipientRow(DriveRecipient recipient) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            recipient.isUnreachable
                ? Icons.phone_disabled_outlined
                : Icons.pregnant_woman,
            size: 16,
            color: recipient.isUnreachable
                ? AppColors.warning
                : AppColors.brandPrimary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(recipient.subjectName,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text(recipient.doseLabel,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
