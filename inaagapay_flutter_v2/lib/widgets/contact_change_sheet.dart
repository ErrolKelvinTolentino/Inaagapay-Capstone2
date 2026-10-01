// lib/widgets/contact_change_sheet.dart
//
// The two steps of adding or changing an email address or mobile number:
// type the new one, then type the code that was sent to it. See
// ContactChangeService for why the second step is not optional.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/contact_change_service.dart';
import '../services/language_service.dart';
import '../theme/app_colors.dart';
import 'otp_input_field.dart';

/// Returns the saved value, or null when the person backed out.
Future<String?> showContactChangeSheet(
  BuildContext context, {
  required int accountId,
  required ContactKind kind,
  String? currentValue,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ContactChangeSheet(
      accountId: accountId,
      kind: kind,
      currentValue: currentValue,
    ),
  ).whenComplete(ContactChangeService.cancel);
}

class _ContactChangeSheet extends StatefulWidget {
  const _ContactChangeSheet({
    required this.accountId,
    required this.kind,
    this.currentValue,
  });

  final int accountId;
  final ContactKind kind;
  final String? currentValue;

  @override
  State<_ContactChangeSheet> createState() => _ContactChangeSheetState();
}

class _ContactChangeSheetState extends State<_ContactChangeSheet> {
  final _valueController = TextEditingController();
  String _code = '';
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _info;
  Timer? _ticker;
  int _resendIn = 0;

  bool get _isEmail => widget.kind == ContactKind.email;
  bool get _adding => (widget.currentValue ?? '').trim().isEmpty;

  String _t(String en, String fil) => LanguageService.translate(en, fil);

  @override
  void dispose() {
    _valueController.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _resendIn = ContactChangeService.resendWaitSeconds();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn = ContactChangeService.resendWaitSeconds());
      if (_resendIn == 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ContactChangeService.requestCode(
      accountId: widget.accountId,
      kind: widget.kind,
      newValue: _valueController.text,
      currentValue: widget.currentValue,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success) {
        _codeSent = true;
        _info = result.message;
        _code = '';
        _startTicker();
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ContactChangeService.resend();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success) {
        _info = result.message;
        _startTicker();
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ContactChangeService.confirm(
      accountId: widget.accountId,
      code: _code,
    );
    if (!mounted) return;
    if (result.success) {
      Navigator.pop(context, result.savedValue);
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
      // A change that can no longer be confirmed sends her back to step one.
      if (result.message.startsWith('Start again') ||
          result.message.contains('expired') ||
          result.message.startsWith('Too many') ||
          result.message.contains('just registered')) {
        _codeSent = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final what = _isEmail
        ? _t('email address', 'email address')
        : _t('mobile number', 'mobile number');
    final title = _adding
        ? _t('Add your $what', 'Magdagdag ng $what')
        : _t('Change your $what', 'Palitan ang $what');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgPrimary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
            Row(
              children: [
                Icon(
                  _isEmail ? Icons.alternate_email_rounded : Icons.phone_iphone_rounded,
                  color: AppColors.brandText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? (_info ?? '')
                  : _t(
                      'We will send a 6-digit code to the new $what. It is '
                          'saved only after you enter that code.',
                      'Magpapadala kami ng 6-digit na code sa bagong $what. '
                          'Mase-save lang ito kapag nailagay mo ang code.',
                    ),
              style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            ),
            if (!_adding && !_codeSent) ...[
              const SizedBox(height: 12),
              Text(
                '${_t('Current', 'Kasalukuyan')}: ${widget.currentValue}',
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ],
            const SizedBox(height: 16),
            if (!_codeSent)
              TextField(
                controller: _valueController,
                autofocus: true,
                enabled: !_busy,
                keyboardType:
                    _isEmail ? TextInputType.emailAddress : TextInputType.phone,
                inputFormatters: _isEmail
                    ? null
                    : [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                        LengthLimitingTextInputFormatter(13),
                      ],
                decoration: InputDecoration(
                  hintText: _isEmail ? 'name@example.com' : '09171234567',
                  labelText: _t('New $what', 'Bagong $what'),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: (_) => _busy ? null : _sendCode(),
              )
            else ...[
              OtpInputField(
                length: 6,
                showError: _error != null,
                onChanged: (value) => setState(() => _code = value),
              ),
              const SizedBox(height: 8),
              // A Wrap, not a Row: "Use a different email address" and
              // "Resend in 60s" do not fit side by side on a 360dp phone, and
              // the Row pushed the second one off the edge.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _error = null;
                              ContactChangeService.cancel();
                            }),
                    child: Text(_t('Use a different $what', 'Ibang $what')),
                  ),
                  TextButton(
                    onPressed: _busy || _resendIn > 0 ? null : _resend,
                    child: Text(_resendIn > 0
                        ? _t('Resend in ${_resendIn}s', 'Ipadala muli sa ${_resendIn}s')
                        : _t('Resend code', 'Ipadala muli')),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(fontSize: 13, color: AppColors.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy || (_codeSent && _code.length < 6)
                    ? null
                    : (_codeSent ? _confirm : _sendCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _codeSent
                            ? _t('Confirm', 'Kumpirmahin')
                            : _t('Send code', 'Ipadala ang code'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
