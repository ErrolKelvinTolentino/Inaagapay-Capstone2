import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_storage.dart';

/// Handles FCM push notification setup, token management, and foreground handling.
/// On web, all methods are no-ops since FCM push requires native platform.
class PushNotificationService {
  static final _client = Supabase.instance.client;

  /// Initialize push notifications.
  static Future<void> initialize() async {
    if (kIsWeb) {
      if (kDebugMode) debugPrint('[Push] Skipping on web platform');
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) debugPrint('[Push] Permission denied');
        return;
      }

      final token = await messaging.getToken();
      if (token != null) {
        await _saveToken(token);
        if (kDebugMode) debugPrint('[Push] Token: ${token.substring(0, 20)}...');
      }

      messaging.onTokenRefresh.listen(_saveToken);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint('[Push] Foreground: ${message.notification?.title}');
        }
      });

      if (kDebugMode) debugPrint('[Push] Initialized successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] Init error (non-fatal): $e');
    }
  }

  static Future<void> _saveToken(String token) async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) return;

      await _client.from('device_tokens').upsert(
        {
          'account_id': accountId,
          'fcm_token': token,
          'platform': 'android',
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'account_id,fcm_token',
      );

      if (kDebugMode) debugPrint('[Push] Token saved for account $accountId');
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] Error saving token: $e');
    }
  }

  /// Remove token on logout.
  static Future<void> removeToken() async {
    if (kIsWeb) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await _client
          .from('device_tokens')
          .update({'is_active': false})
          .eq('fcm_token', token);

      if (kDebugMode) debugPrint('[Push] Token deactivated');
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] Error removing token: $e');
    }
  }
}
