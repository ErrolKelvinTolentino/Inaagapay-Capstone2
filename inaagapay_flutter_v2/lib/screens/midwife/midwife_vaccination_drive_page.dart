// lib/screens/midwife/midwife_vaccination_drive_page.dart
//
// Scheduling a vaccination drive, and inviting the mothers who need it.
//
// The screen is deliberately two steps rather than one. Saving the drive and
// messaging thirty pregnant women are different acts with different
// consequences: the first is a calendar entry that can be changed, the second
// spends SMS credits and cannot be recalled. So the drive saves on its own,
// the recipient list is shown with names and how many doses each mother has
// had, and sending is a separate button behind a confirmation that states the
// count out loud.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';
import '../../services/vaccination_drive_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/app_input_field.dart';
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

  List<Map<String, dynamic>> _vaccines = [];
  Map<String, dynamic>? _selectedVaccine;
  DateTime? _date;

  List<DriveRecipient> _recipients = [];
  bool _loadingRecipients = false;

  /// Set once the drive row exists, which is what unlocks sending.
  int? _savedDriveId;
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

      _vaccines = await VaccinationDriveService.fetchMaternalVaccines();

      // Most maternal drives are TD, so it starts selected rather than making
      // her find it in a list of one or two.
      if (_vaccines.isNotEmpty) {
        _selectedVaccine = _vaccines.firstWhere(
          (v) => (v['vaccine_name']?.toString() ?? '')
              .toLowerCase()
              .contains('td'),
          orElse: () => _vaccines.first,
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

    setState(() => _loadingRecipients = true);
    final recipients =
        await VaccinationDriveService.fetchUnprotectedMothers(bhcId: bhcId);
    if (!mounted) return;
    setState(() {
      _recipients = recipients;
      _loadingRecipients = false;
    });
  }

  String get _vaccineName =>
      _selectedVaccine?['vaccine_name']?.toString() ?? 'Vaccine';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _saveDrive() async {
    final bhcId = _bhcId;
    final vaccineId = _selectedVaccine?['vaccine_id'];
    final date = _date;

    if (bhcId == null || vaccineId == null || date == null) {
      AppSnackbar.show(context, 'Choose a vaccine and a date first',
          type: AppSnackType.warning);
      return;
    }

    setState(() => _saving = true);
    final driveId = await VaccinationDriveService.createDrive(
      bhcId: bhcId,
      vaccineId: vaccineId as int,
      date: date,
      notes: _notesCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedDriveId = driveId;
    });

    AppSnackbar.show(
      context,
      driveId == null
          ? 'Could not save the drive. Nothing was sent.'
          : 'Drive scheduled for ${DateFormat('MMMM d, yyyy').format(date)}. '
              'It now shows on the Schedules calendar.',
      type: driveId == null ? AppSnackType.error : AppSnackType.success,
    );
  }

  Future<void> _sendNotifications() async {
    final date = _date;
    if (_savedDriveId == null || date == null) return;

    final reachable = _recipients.where((r) => !r.isUnreachable).length;
    if (reachable == 0) {
      AppSnackbar.show(context, 'No mother on this list has a phone or email',
          type: AppSnackType.warning);
      return;
    }

    // Text messages cannot be unsent, so the count is stated before anything
    // goes out rather than reported afterwards.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmationDialogBox(
        title: 'Send to $reachable ${reachable == 1 ? 'mother' : 'mothers'}?',
        subtitle: 'They will get a text message and an email about the '
            '$_vaccineName drive on ${DateFormat('MMMM d').format(date)}. '
            'Messages cannot be taken back once sent.',
        confirmText: 'Send now',
        cancelText: 'Not yet',
        onConfirm: () => Navigator.pop(dialogContext, true),
        onCancel: () => Navigator.pop(dialogContext, false),
      ),
    );
    if (confirmed != true || !mounted) return;

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
      'Reached ${result.reached} of ${_recipients.length}: '
      '${result.smsSent} by text, ${result.emailsQueued} by email.',
      type: result.smsFailed > 0 ? AppSnackType.warning : AppSnackType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            const SecondaryHeader(title: 'Schedule Vaccination Drive'),
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
                                AppDropdownField<String>(
                                  hintText: 'Vaccine',
                                  leadingIcon: Icons.vaccines_outlined,
                                  value: _selectedVaccine?['vaccine_name']
                                      ?.toString(),
                                  options: _vaccines
                                      .map((v) =>
                                          v['vaccine_name']?.toString() ?? '')
                                      .where((n) => n.isNotEmpty)
                                      .toSet()
                                      .toList(),
                                  displayStringForOption: (v) => v,
                                  onSelected: (name) => setState(() {
                                    _selectedVaccine = _vaccines.firstWhere(
                                      (v) =>
                                          v['vaccine_name']?.toString() == name,
                                      orElse: () => _vaccines.first,
                                    );
                                    _savedDriveId = null;
                                  }),
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
                          MainButton(
                            label: _saving
                                ? 'Saving…'
                                : (_savedDriveId == null
                                    ? 'Save drive to calendar'
                                    : 'Saved to calendar'),
                            showIcons: false,
                            onPressed: _saving || _savedDriveId != null
                                ? null
                                : _saveDrive,
                          ),
                          if (_savedDriveId != null) ...[
                            const SizedBox(height: 12),
                            MainButton(
                              label: _sending
                                  ? 'Sending…'
                                  : (_sendResult == null
                                      ? 'Notify mothers'
                                      : 'Notifications sent'),
                              showIcons: false,
                              onPressed: _sending || _sendResult != null
                                  ? null
                                  : _sendNotifications,
                            ),
                          ],
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
            'Pregnant mothers who have not yet had TD2 — the second dose is '
            'what protects the baby against tetanus at birth.',
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
              'Every pregnant mother here already has TD2 or more. Nobody '
              'needs inviting.',
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
                    _recipients.length == 1
                        ? 'mother will be invited'
                        : 'mothers will be invited',
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
            child: Text(recipient.name,
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
