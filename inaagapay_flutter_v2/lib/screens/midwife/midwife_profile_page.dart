// lib/screens/midwife/midwife_profile_page.dart
//
// The signed-in user's own account: who the system thinks they are, when the
// record was made, and the two things they are allowed to change about it —
// their photo and their password.
//
// Keyed on `account_id` rather than on a role table, so it opens for a midwife
// or an admin without either needing a row anywhere else.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/main_button.dart';
import '../../widgets/profile_header_card.dart';
import '../../widgets/profile_section.dart';
import '../../widgets/secondary_header.dart';

class MidwifeProfilePage extends StatefulWidget {
  const MidwifeProfilePage({super.key});

  @override
  State<MidwifeProfilePage> createState() => _MidwifeProfilePageState();
}

class _MidwifeProfilePageState extends State<MidwifeProfilePage> {
  static final DateFormat _stamp = DateFormat('MMM d, yyyy · h:mm a');
  static final DateFormat _day = DateFormat('MMM d, yyyy');

  bool _loading = true;
  bool _uploadingPhoto = false;
  String? _error;

  int? _accountId;
  Map<String, dynamic>? _account;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'You are not signed in on this device.';
          });
        }
        return;
      }
      _accountId = accountId;

      final account = await SupabaseService.getAccountOverview(accountId);

      // The photo is fetched on its own and allowed to fail on its own. Folding
      // it into the account query would mean one missing row or one storage
      // hiccup emptying the whole page.
      final photo =
          await SupabaseService.getAccountProfilePictureUrl(accountId);

      if (!mounted) return;
      setState(() {
        _account = account;
        _photoUrl = photo;
        _loading = false;
        _error = account == null ? 'Could not load your account.' : null;
      });
    } catch (e) {
      debugPrint('Profile load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load your account. Pull down to try again.';
        });
      }
    }
  }

  // ── Photo ─────────────────────────────────────────────────────────────────

  Future<void> _changePhoto() async {
    final accountId = _accountId;
    if (accountId == null || _uploadingPhoto) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Resized on the way in. A modern phone camera produces a file large
        // enough to be slow over a barangay connection, for an image that is
        // never shown larger than a hundred pixels.
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _uploadingPhoto = true);
      final Uint8List bytes = await picked.readAsBytes();
      final url = await SupabaseService.uploadAccountProfilePicture(
          accountId, bytes);

      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        if (url != null) _photoUrl = url;
      });

      _say(url != null
          ? 'Profile photo updated.'
          : 'Could not upload the photo. Please try again.');
    } catch (e) {
      debugPrint('Photo change error: $e');
      if (mounted) setState(() => _uploadingPhoto = false);
      _say('Could not upload the photo. Please try again.');
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.brandPrimary),
    );
  }

  // ── Password ──────────────────────────────────────────────────────────────

  Future<void> _openChangePassword() {
    final accountId = _accountId;
    if (accountId == null) return Future.value();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangePasswordSheet(
        accountId: accountId,
        onChanged: () {
          _say('Password changed.');
          _load();
        },
      ),
    );
  }

  // ── Display helpers ───────────────────────────────────────────────────────

  String get _fullName {
    final a = _account;
    if (a == null) return '';
    final parts = [
      a['first_name'],
      a['middle_name'],
      a['last_name'],
      a['extension_name'],
    ].map((p) => p?.toString().trim() ?? '').where((p) => p.isNotEmpty);
    return parts.join(' ');
  }

  String _formatStamp(dynamic value, {bool dayOnly = false}) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '—';
    return dayOnly ? _day.format(parsed) : _stamp.format(parsed.toLocal());
  }

  /// How long ago, in the words a person would use.
  ///
  /// A timestamp alone answers "when" but not "recently?", which is the actual
  /// question behind "when was this last updated".
  String _relative(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    final months = diff.inDays ~/ 30;
    if (months < 12) return '$months month${months == 1 ? '' : 's'} ago';
    final years = diff.inDays ~/ 365;
    return '$years year${years == 1 ? '' : 's'} ago';
  }

  String _roleLabel(String? type) => switch (type?.toLowerCase()) {
        'midwife' => 'Midwife',
        'admin' => 'Administrator',
        'mother' => 'Mother',
        _ => 'Account',
      };

  /// Who made this account, in plain words rather than a raw column value.
  String _createdByLabel(dynamic createdBy) {
    final raw = createdBy?.toString() ?? '';
    if (raw.isEmpty) return '—';
    // `created_by` holds one of four shapes; the shared helper is what knows
    // which of them mean "someone else made this account".
    final byStaff = SupabaseService.isMidwifeCreated(
      createdBy: raw,
      accountId: _accountId,
    );
    return byStaff ? 'Created by staff' : 'Self-registered';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'My Profile',
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brandPrimary))
          : RefreshIndicator(
              color: AppColors.brandPrimary,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 12),
                  ],
                  if (_account != null) ...[
                    _buildHeader(),
                    const SizedBox(height: 14),
                    _buildAccountSection(),
                    const SizedBox(height: 14),
                    _buildRecordSection(),
                    const SizedBox(height: 14),
                    _buildSecuritySection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final a = _account!;
    final status = a['status']?.toString() ?? 'active';
    final verified = a['is_verified'] == true;

    return Column(
      children: [
        ProfileHeaderCard(
          fullName: _fullName.isEmpty ? 'Unnamed account' : _fullName,
          email: a['email_address']?.toString(),
          phone: a['phone_number']?.toString(),
          profilePictureUrl: _photoUrl,
          patientNumber: _roleLabel(a['account_type']?.toString()),
          chips: [
            ProfileHeaderChip(
              icon: verified
                  ? Icons.verified_rounded
                  : Icons.error_outline_rounded,
              text: verified ? 'Verified' : 'Not verified',
            ),
            ProfileHeaderChip(
              icon: Icons.circle,
              text: status[0].toUpperCase() + status.substring(1),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // The one control the header needs, kept out of the card so the card
        // stays the same component every other profile in the app uses.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _uploadingPhoto ? null : _changePhoto,
            icon: _uploadingPhoto
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.brandPrimary),
                  )
                : const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(_uploadingPhoto
                ? 'Uploading…'
                : (_photoUrl == null ? 'Add a photo' : 'Change photo')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandPrimary,
              side: const BorderSide(color: AppColors.brandPrimary),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection() {
    final a = _account!;
    return ProfileCardSection(
      title: 'Account',
      icon: Icons.badge_outlined,
      children: [
        ProfileInfoRow(
          label: 'Role',
          value: _roleLabel(a['account_type']?.toString()),
        ),
        ProfileInfoRow(
          label: 'Email',
          value: a['email_address']?.toString().trim().isNotEmpty == true
              ? a['email_address'].toString()
              : 'Not set',
        ),
        ProfileInfoRow(
          label: 'Mobile number',
          value: a['phone_number']?.toString().trim().isNotEmpty == true
              ? a['phone_number'].toString()
              : 'Not set',
        ),
        ProfileInfoRow(
          label: 'Account ID',
          value: '#${a['account_id']}',
        ),
      ],
    );
  }

  Widget _buildRecordSection() {
    final a = _account!;
    return ProfileCardSection(
      title: 'Record',
      icon: Icons.schedule_rounded,
      children: [
        _stampRow('Account created', a['created_at'], dayOnly: true),
        _stampRow('Last updated', a['updated_at']),
        _stampRow('Last signed in', a['last_login_at']),
        ProfileInfoRow(
          label: 'Registered',
          value: _createdByLabel(a['created_by']),
        ),
      ],
    );
  }

  /// A timestamp with how long ago it was, since "when" and "recently?" are
  /// different questions and the raw date only answers the first.
  Widget _stampRow(String label, dynamic value, {bool dayOnly = false}) {
    final relative = _relative(value);
    return ProfileInfoRow(
      label: label,
      valueWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatStamp(value, dayOnly: dayOnly),
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.inputText,
            ),
          ),
          if (relative.isNotEmpty)
            Text(
              relative,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection() {
    final isTemporary = _account?['is_temporary_password'] == true;

    return ProfileCardSection(
      title: 'Security',
      icon: Icons.lock_outline_rounded,
      children: [
        if (isTemporary) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(Icons.key_rounded, size: 16, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You are still using the temporary password issued with '
                    'this account. Set your own below.',
                    style: TextStyle(
                        fontSize: 11.5, height: 1.35, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'Your password protects the records of every mother assigned to you. '
          'Change it if you think anyone else has seen it.',
          style: TextStyle(
              fontSize: 12, height: 1.45, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        MainButton(
          label: 'Change password',
          showIcons: true,
          leftIcon: Icons.lock_reset_rounded,
          onPressed: _openChangePassword,
        ),
      ],
    );
  }
}

// ── Change password sheet ───────────────────────────────────────────────────

class _ChangePasswordSheet extends StatefulWidget {
  final int accountId;
  final VoidCallback onChanged;

  const _ChangePasswordSheet({
    required this.accountId,
    required this.onChanged,
  });

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _showCurrent = false;
  bool _showNext = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// The rules, checked here so the reason for a refusal is on screen before
  /// anything is sent.
  String? _localProblem() {
    if (_current.text.isEmpty) return 'Enter your current password.';
    if (_next.text.length < 8) {
      return 'The new password must be at least 8 characters.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(_next.text) ||
        !RegExp(r'\d').hasMatch(_next.text)) {
      return 'The new password must contain both letters and numbers.';
    }
    if (_next.text != _confirm.text) return 'The two new passwords do not match.';
    if (_next.text == _current.text) {
      return 'The new password is the same as the current one.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _localProblem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await SupabaseService.changePassword(
      accountId: widget.accountId,
      currentPassword: _current.text,
      newPassword: _next.text,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      Navigator.pop(context);
      widget.onChanged();
    } else {
      setState(() {
        _saving = false;
        _error = result['message']?.toString() ?? 'Could not change password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Change password',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'At least 8 characters, with letters and numbers.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              AppInputField(
                hintText: 'Current password',
                controller: _current,
                obscureText: !_showCurrent,
                leadingIcon: Icons.lock_outline_rounded,
                trailingIcon:
                    _showCurrent ? Icons.visibility_off : Icons.visibility,
                onTrailingTap: () =>
                    setState(() => _showCurrent = !_showCurrent),
              ),
              const SizedBox(height: 12),
              AppInputField(
                hintText: 'New password',
                controller: _next,
                obscureText: !_showNext,
                leadingIcon: Icons.lock_reset_rounded,
                trailingIcon:
                    _showNext ? Icons.visibility_off : Icons.visibility,
                onTrailingTap: () => setState(() => _showNext = !_showNext),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              AppInputField(
                hintText: 'Confirm new password',
                controller: _confirm,
                obscureText: !_showNext,
                leadingIcon: Icons.check_circle_outline_rounded,
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 18),
              MainButton(
                label: _saving ? 'Saving…' : 'Save new password',
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12, height: 1.35, color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }
}
