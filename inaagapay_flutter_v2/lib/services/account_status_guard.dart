// lib/services/account_status_guard.dart
//
// Keeps a suspended or deactivated account from staying signed in.
//
// Login already refuses any account whose status is not 'active', but a
// session opened before the suspension never went back to the server: the app
// restored it from secure storage on every launch and carried on. A midwife
// suspended for what she was doing kept reading patients and recording doses
// until she chose to sign out.
//
// This re-reads the account's status at launch, whenever the app returns to
// the foreground, and once a minute while it is open, and ends the session as
// soon as the answer is definite.
//
// A failed read is not proof of a suspension. A midwife on a weak signal in
// the field must not be signed out mid-visit because one request dropped, so
// only a row that says something other than 'active' — or no row at all, for
// an account that was deleted — ends the session. Same rule as
// verifyAdminSessionWithDB in the portal's common-security.js.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_storage.dart';
import 'push_notification_service.dart';
import 'supabase_service.dart';

class AccountStatusGuard {
  const AccountStatusGuard._();

  /// Given to the root MaterialApp so a session can be ended from outside any
  /// widget — a timer tick or an app-resume callback.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// One single-row read per minute at most, the same budget as the portal.
  static const Duration recheckInterval = Duration(minutes: 1);

  static DateTime? _lastCheck;
  static bool _checking = false;
  static String? _pendingNotice;

  /// Why the last session was ended. Read once by the login screen, so the
  /// person is told what happened instead of landing on a blank form.
  static String? takeSignOutNotice() {
    final notice = _pendingNotice;
    _pendingNotice = null;
    return notice;
  }

  /// Checks the signed-in account and ends the session if it is no longer
  /// active. Returns true when the session was ended.
  ///
  /// Throttled to [recheckInterval] unless [force] is set. Navigates to the
  /// login screen when the app's navigator exists; at launch it does not yet,
  /// and the caller routes to login itself.
  static Future<bool> enforce({bool force = false}) async {
    if (_checking) return false;
    final now = DateTime.now();
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < recheckInterval) {
      return false;
    }

    _checking = true;
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null || !await AuthStorage.isLoggedIn()) return false;

      _lastCheck = now;
      final account = await _readAccount(accountId);
      if (identical(account, _unreadable)) return false;

      final status = account?['status']?.toString();
      if (account != null && status == 'active') return false;

      await _endSession(
        accountId: accountId,
        status: status,
        reason: account?['status_reason']?.toString(),
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('AccountStatusGuard: $e');
      return false;
    } finally {
      _checking = false;
    }
  }

  /// Sentinel for "the read failed", kept apart from null ("no such account").
  static const Map<String, dynamic> _unreadable = {'_unreadable': true};

  static Future<Map<String, dynamic>?> _readAccount(int accountId) async {
    try {
      return await SupabaseService.client
          .from('accounts')
          .select('status, status_reason')
          .eq('account_id', accountId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      // Pre-20260925 database: no status_reason column. Retry without it.
      if (e.code == '42703' || e.message.contains('status_reason')) {
        try {
          return await SupabaseService.client
              .from('accounts')
              .select('status')
              .eq('account_id', accountId)
              .maybeSingle();
        } catch (_) {
          return _unreadable;
        }
      }
      return _unreadable;
    } catch (_) {
      return _unreadable;
    }
  }

  static Future<void> _endSession({
    required int accountId,
    required String? status,
    required String? reason,
  }) async {
    _pendingNotice = signOutNotice(status: status, reason: reason);

    await SupabaseService.recordAuthEvent(
      accountId,
      'session_expired',
      detail: status == null
          ? 'Signed out: the account no longer exists.'
          : 'Signed out: the account status is "$status".',
    );

    try {
      await PushNotificationService.removeToken();
    } catch (_) {}
    await AuthStorage.clearAll();
    SupabaseService.clearMidwifeContextCache();

    navigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  /// The sentence the login screen shows. Public for testing.
  static String signOutNotice({String? status, String? reason}) {
    final String wording;
    switch (status) {
      case 'suspended':
        wording = 'Your account has been suspended, so you were signed out.';
        break;
      case null:
        wording = 'This account no longer exists, so you were signed out.';
        break;
      default:
        wording = 'Your account has been deactivated, so you were signed out.';
    }
    final trimmed = reason?.trim() ?? '';
    return trimmed.isNotEmpty
        ? '$wording Reason given: $trimmed'
        : '$wording Please contact your health center.';
  }
}
