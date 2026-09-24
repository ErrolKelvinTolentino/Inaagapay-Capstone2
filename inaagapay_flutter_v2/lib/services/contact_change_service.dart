// lib/services/contact_change_service.dart
//
// Adding or changing the e-mail address or mobile number on an account.
//
// Either one is a sign-in identifier and the channel every reset code and
// reminder goes to, so a typo is not cosmetic: a mistyped number locks the
// person out of password recovery and sends her checkup reminders to a
// stranger. So a new value is never saved as typed. A six-digit code goes to
// the NEW address, and only the person who can read it there can make the
// change. The OLD address is then told, so a change made on a borrowed phone
// does not go unnoticed.
//
// The pending change lives in memory for ten minutes and five attempts. It is
// not written anywhere until it is confirmed, so an abandoned change leaves no
// trace on the account.

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'email_service.dart';
import 'sms_service.dart';
import 'supabase_service.dart';

enum ContactKind { email, phone }

class ContactChangeResult {
  const ContactChangeResult(this.success, this.message, {this.savedValue});

  final bool success;
  final String message;

  /// The value as stored, once a change is confirmed.
  final String? savedValue;
}

class _PendingChange {
  _PendingChange({
    required this.accountId,
    required this.kind,
    required this.value,
    required this.previous,
    required this.code,
    required this.expiresAt,
  });

  final int accountId;
  final ContactKind kind;
  final String value;
  final String? previous;
  String code;
  DateTime expiresAt;
  int attempts = 0;
  DateTime sentAt = DateTime.now();
}

class ContactChangeService {
  const ContactChangeService._();

  static const codeLifetime = Duration(minutes: 10);
  static const maxAttempts = 5;
  static const resendAfter = Duration(seconds: 60);

  static _PendingChange? _pending;

  /// Seconds until another code may be sent, or 0.
  static int resendWaitSeconds() {
    final p = _pending;
    if (p == null) return 0;
    final wait = resendAfter - DateTime.now().difference(p.sentAt);
    return wait.isNegative ? 0 : wait.inSeconds + 1;
  }

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  /// The value in the form it is stored, or null when it is not valid.
  @visibleForTesting
  static String? normalize(ContactKind kind, String raw) {
    final value = raw.trim();
    switch (kind) {
      case ContactKind.email:
        final email = value.toLowerCase();
        return _emailPattern.hasMatch(email) ? email : null;
      case ContactKind.phone:
        final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
        final valid = RegExp(r'^(09\d{9}|639\d{9}|9\d{9})$').hasMatch(digits);
        return valid ? SmsService.formatPhilippineNumber(digits) : null;
    }
  }

  /// Whether two stored-or-typed values name the same address.
  @visibleForTesting
  static bool sameContact(ContactKind kind, String? a, String? b) {
    if (a == null || b == null) return false;
    if (kind == ContactKind.email) {
      return a.trim().toLowerCase() == b.trim().toLowerCase();
    }
    String tail(String v) {
      final d = v.replaceAll(RegExp(r'[^0-9]'), '');
      return d.length >= 10 ? d.substring(d.length - 10) : d;
    }
    return tail(a) == tail(b);
  }

  static String label(ContactKind kind) =>
      kind == ContactKind.email ? 'email address' : 'mobile number';

  /// Sends a code to [newValue]. Nothing on the account changes yet.
  static Future<ContactChangeResult> requestCode({
    required int accountId,
    required ContactKind kind,
    required String newValue,
    String? currentValue,
  }) async {
    final value = normalize(kind, newValue);
    if (value == null) {
      return ContactChangeResult(
        false,
        kind == ContactKind.email
            ? 'Enter a valid email address, like name@example.com.'
            : 'Enter a valid Philippine mobile number, like 09171234567.',
      );
    }
    if (sameContact(kind, value, currentValue)) {
      return ContactChangeResult(false, 'That is already your ${label(kind)}.');
    }

    final available = kind == ContactKind.email
        ? await SupabaseService.isEmailAvailable(value)
        : await SupabaseService.isPhoneNumberAvailable(value);
    if (!available) {
      return ContactChangeResult(
        false,
        'That ${label(kind)} is already used by another account.',
      );
    }

    final code = _newCode();
    final sent = await _sendCode(kind, value, code);
    if (!sent) {
      return ContactChangeResult(
        false,
        'The code could not be sent. Check the ${label(kind)} and try again.',
      );
    }

    _pending = _PendingChange(
      accountId: accountId,
      kind: kind,
      value: value,
      previous: currentValue,
      code: code,
      expiresAt: DateTime.now().add(codeLifetime),
    );
    return ContactChangeResult(
      true,
      kind == ContactKind.email
          ? 'We sent a 6-digit code to $value.'
          : 'We sent a 6-digit code to ${SmsService.formatDisplayNumber(value)}.',
    );
  }

  /// A fresh code for the pending change, after [resendAfter].
  static Future<ContactChangeResult> resend() async {
    final p = _pending;
    if (p == null) {
      return const ContactChangeResult(false, 'Start again: no change is pending.');
    }
    final wait = resendWaitSeconds();
    if (wait > 0) {
      return ContactChangeResult(false, 'You can ask for a new code in $wait seconds.');
    }
    final code = _newCode();
    if (!await _sendCode(p.kind, p.value, code)) {
      return const ContactChangeResult(false, 'The code could not be sent. Try again.');
    }
    p
      ..code = code
      ..expiresAt = DateTime.now().add(codeLifetime)
      ..attempts = 0
      ..sentAt = DateTime.now();
    return const ContactChangeResult(true, 'A new code is on its way.');
  }

  /// Checks [code] and, when it matches, saves the new value.
  static Future<ContactChangeResult> confirm({
    required int accountId,
    required String code,
  }) async {
    final p = _pending;
    if (p == null || p.accountId != accountId) {
      return const ContactChangeResult(false, 'Start again: no change is pending.');
    }
    if (DateTime.now().isAfter(p.expiresAt)) {
      _pending = null;
      return const ContactChangeResult(
          false, 'That code has expired. Start again to get a new one.');
    }
    if (p.attempts >= maxAttempts) {
      _pending = null;
      return const ContactChangeResult(
          false, 'Too many wrong codes. Start again to get a new one.');
    }

    p.attempts++;
    if (!_sameCode(code.trim(), p.code)) {
      final left = maxAttempts - p.attempts;
      if (left <= 0) _pending = null;
      return ContactChangeResult(
        false,
        left <= 0
            ? 'Too many wrong codes. Start again to get a new one.'
            : 'That code is not right. $left ${left == 1 ? 'try' : 'tries'} left.',
      );
    }

    // Someone else may have taken the address while the code was in transit.
    final stillFree = p.kind == ContactKind.email
        ? await SupabaseService.isEmailAvailable(p.value)
        : await SupabaseService.isPhoneNumberAvailable(p.value);
    if (!stillFree) {
      _pending = null;
      return ContactChangeResult(
          false, 'That ${label(p.kind)} was just registered to another account.');
    }

    try {
      await SupabaseService.client.from('accounts').update({
        p.kind == ContactKind.email ? 'email_address' : 'phone_number': p.value,
      }).eq('account_id', accountId);
    } catch (e) {
      if (kDebugMode) debugPrint('Contact change failed: $e');
      return const ContactChangeResult(
          false, 'The change could not be saved. Check the connection and try again.');
    }

    final change = p;
    _pending = null;
    await _tellPreviousAddress(change);
    return ContactChangeResult(
      true,
      'Your ${label(change.kind)} has been updated.',
      savedValue: change.value,
    );
  }

  static void cancel() => _pending = null;

  static String _newCode() =>
      (100000 + Random.secure().nextInt(900000)).toString();

  static bool _sameCode(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Future<bool> _sendCode(ContactKind kind, String value, String code) {
    return kind == ContactKind.email
        ? EmailService.sendVerificationEmail(value, code)
        : SmsService.sendOtp(value, code);
  }

  /// Best effort: a notice that fails to send must not undo a confirmed change.
  static Future<void> _tellPreviousAddress(_PendingChange change) async {
    final previous = change.previous?.trim() ?? '';
    if (previous.isEmpty) return;
    try {
      if (change.kind == ContactKind.email) {
        await EmailService.sendContactChangedNotice(
          email: previous,
          what: 'email address',
          newValueHint: _mask(change.kind, change.value),
        );
      } else {
        await SmsService.sendSmsMessage(
          previous,
          'INAAGAPAY: The mobile number on your account was changed to '
          '${_mask(change.kind, change.value)}. If you did not do this, contact '
          'your health center right away.',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Contact change notice failed: $e');
    }
  }

  /// "ma***@gmail.com", "0917****567"
  @visibleForTesting
  static String mask(ContactKind kind, String value) => _mask(kind, value);

  static String _mask(ContactKind kind, String value) {
    if (kind == ContactKind.email) {
      final at = value.indexOf('@');
      if (at <= 0) return value;
      final name = value.substring(0, at);
      final keep = name.length <= 2 ? 1 : 2;
      return '${name.substring(0, keep)}***${value.substring(at)}';
    }
    final display = SmsService.formatDisplayNumber(value);
    if (display.length < 8) return display;
    return '${display.substring(0, 4)}****${display.substring(display.length - 3)}';
  }
}
