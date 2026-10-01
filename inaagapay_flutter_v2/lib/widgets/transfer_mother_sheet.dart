// lib/widgets/transfer_mother_sheet.dart
//
// Choosing where a mother is moving to. See MotherTransferService.

import 'package:flutter/material.dart';

import '../services/mother_transfer_service.dart';
import '../theme/app_colors.dart';

/// Returns true when the mother was transferred.
Future<bool> showTransferMotherSheet(
  BuildContext context, {
  required int motherId,
  required String motherName,
  int? currentBhcId,
}) async {
  final moved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // The sheet's own surface, so the checkbox row's ripple shows. A coloured
    // box inside a transparent sheet painted over it.
    backgroundColor: AppColors.bgPrimary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _TransferMotherSheet(
      motherId: motherId,
      motherName: motherName,
      currentBhcId: currentBhcId,
    ),
  );
  return moved == true;
}

class _TransferMotherSheet extends StatefulWidget {
  const _TransferMotherSheet({
    required this.motherId,
    required this.motherName,
    this.currentBhcId,
  });

  final int motherId;
  final String motherName;
  final int? currentBhcId;

  @override
  State<_TransferMotherSheet> createState() => _TransferMotherSheetState();
}

class _TransferMotherSheetState extends State<_TransferMotherSheet> {
  late final Future<List<TransferDestination>> _destinations =
      MotherTransferService.destinations(excludeBhcId: widget.currentBhcId);
  final _reason = TextEditingController();
  final _barangay = TextEditingController();
  int? _to;
  bool _moveChildren = true;
  bool _busy = false;
  String? _error;

  // Checked together and shown under their own fields. One message at a time
  // at the foot of the sheet meant a blank reason went unmentioned until a
  // destination had been picked, and the message itself sat under the
  // keyboard.
  String? _destinationError;
  String? _reasonError;

  @override
  void dispose() {
    _reason.dispose();
    _barangay.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final destinationError =
        _to == null ? 'Choose the health center she is moving to.' : null;
    final reasonError = _reason.text.trim().length < 5
        ? 'Say briefly why she is being transferred.'
        : null;
    if (destinationError != null || reasonError != null) {
      setState(() {
        _destinationError = destinationError;
        _reasonError = reasonError;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _destinationError = null;
      _reasonError = null;
    });
    final result = await MotherTransferService.transfer(
      motherId: widget.motherId,
      toBhcId: _to!,
      reason: _reason.text,
      moveChildren: _moveChildren,
      newBarangay: _barangay.text,
    );
    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  InputDecoration _field(String label, {String? hint, String? error}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        errorMaxLines: 2,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderPrimary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.swap_horiz_rounded, color: AppColors.brandText),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Transfer to another health center',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.motherName} and her records will appear at the new '
              'health center. Checkups and doses already given stay recorded '
              'where they happened.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<TransferDestination>>(
              future: _destinations,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Could not load health centers.',
                      style: TextStyle(color: AppColors.error));
                }
                final options = snapshot.data;
                if (options == null) {
                  return const LinearProgressIndicator(minHeight: 2);
                }
                return DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _to,
                  decoration: _field('Move to', error: _destinationError),
                  items: [
                    for (final d in options)
                      DropdownMenuItem(
                        value: d.id,
                        child: Text(d.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _to = value;
                            _destinationError = null;
                          }),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _barangay,
              enabled: !_busy,
              decoration: _field('New barangay (optional)',
                  hint: 'Leave blank to keep her address'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _moveChildren,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _moveChildren = value ?? true),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Move her children too',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text('They get new child numbers there.',
                  style: TextStyle(fontSize: 12)),
            ),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLines: 2,
              maxLength: 300,
              onChanged: (value) {
                if (_reasonError != null && value.trim().length >= 5) {
                  setState(() => _reasonError = null);
                }
              },
              decoration: _field('Reason',
                  hint: 'e.g. Moved to Sabang with her family',
                  error: _reasonError),
            ),
            if (_error != null) ...[
              Text(_error!,
                  style: const TextStyle(fontSize: 13, color: AppColors.error)),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.swap_horiz_rounded),
                label: const Text('Transfer',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
