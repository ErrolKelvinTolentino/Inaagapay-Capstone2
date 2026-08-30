// lib/services/auth_storage.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:inaagapay_flutter_v2/services/supabase_service.dart';

class AuthStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // Token
  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: 'auth_token');
  }

  // User Role
  static Future<void> saveUserRole(String role) async {
    await _storage.write(key: 'user_role', value: role);
  }

  static Future<String?> getUserRole() async {
    return await _storage.read(key: 'user_role');
  }

  // User ID
  static Future<void> saveUserId(int userId) async {
    await _storage.write(key: 'user_id', value: userId.toString());
  }

  static Future<int?> getUserId() async {
    final value = await _storage.read(key: 'user_id');
    return value != null ? int.tryParse(value) : null;
  }

  // Mother ID
  static Future<void> saveMotherId(int motherId) async {
    if (kDebugMode) {
      debugPrint('=== SAVING MOTHER ID ===');
      debugPrint('Mother ID: $motherId');
    }
    await _storage.write(key: 'mother_id', value: motherId.toString());
    
    final saved = await _storage.read(key: 'mother_id');
    if (kDebugMode) {
      debugPrint('Verified saved mother ID: $saved');
    }
  }

  static Future<int?> getMotherId() async {
    final value = await _storage.read(key: 'mother_id');
    int? motherId = value != null ? int.tryParse(value) : null;
    if (motherId == null) {
      final userId = await getUserId();
      if (userId != null) {
        try {
          final res = await SupabaseService.client
              .from('mothers')
              .select('mother_id')
              .eq('account_id', userId)
              .maybeSingle();
          if (res != null && res['mother_id'] != null) {
            motherId = res['mother_id'] as int;
            await saveMotherId(motherId);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error self-healing motherId: $e');
        }
      }
    }
    if (kDebugMode) {
      debugPrint('=== GETTING MOTHER ID ===');
      debugPrint('Retrieved value: $motherId');
    }
    return motherId;
  }

  static Future<void> clearMotherId() async {
    await _storage.delete(key: 'mother_id');
  }

  // Profile Complete
  static Future<void> saveProfileComplete(bool isComplete) async {
    await _storage.write(key: 'profile_complete', value: isComplete.toString());
  }

  static Future<bool> isProfileComplete() async {
    final value = await _storage.read(key: 'profile_complete');
    return value == 'true';
  }

  // Temporary Password Changed
  static const String _tempPasswordChangedKey = 'temp_password_changed';

  static Future<void> saveTemporaryPasswordChanged(bool changed) async {
    await _storage.write(key: _tempPasswordChangedKey, value: changed.toString());
  }

  static Future<bool> isTemporaryPasswordChanged() async {
    final value = await _storage.read(key: _tempPasswordChangedKey);
    return value == 'true';
  }

  static Future<void> clearTemporaryPasswordFlag() async {
    await _storage.delete(key: _tempPasswordChangedKey);
  }

  // Login Status
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // Dark Mode
  static Future<void> saveDarkMode(bool enabled) async {
    await _storage.write(key: 'dark_mode', value: enabled.toString());
  }

  static Future<bool> isDarkMode() async {
    final value = await _storage.read(key: 'dark_mode');
    return value == 'true';
  }

  // AI Privacy Settings
  static Future<void> saveHiddenAllergies(List<String> list) async {
    await _storage.write(key: 'hidden_allergies', value: list.join('|||'));
  }

  static Future<List<String>> getHiddenAllergies() async {
    final val = await _storage.read(key: 'hidden_allergies');
    if (val == null || val.isEmpty) return [];
    return val.split('|||');
  }

  /// Whether this mother was assigned to a health centre last time we looked.
  ///
  /// Cached so the shell can draw the right set of tabs on its first frame
  /// instead of showing five and removing two once the query returns. The
  /// database is still the authority — this only decides what is painted
  /// before the answer arrives, and an unregistered mother is the safe default
  /// because she is the one this gate exists for.
  static Future<void> saveBhcRegistered(bool registered) async {
    await _storage.write(key: 'bhc_registered', value: registered.toString());
  }

  static Future<bool> wasBhcRegistered() async {
    final value = await _storage.read(key: 'bhc_registered');
    return value == 'true';
  }

  /// Alert categories the user has switched off in Settings.
  ///
  /// Stored as the muted set rather than the enabled set, so a category added
  /// to the app later arrives switched on for everyone instead of hidden from
  /// everyone who saved a preference before it existed.
  static Future<void> saveMutedAlertCategories(List<String> categories) async {
    await _storage.write(
        key: 'muted_alert_categories', value: categories.join('|||'));
  }

  static Future<List<String>> getMutedAlertCategories() async {
    final val = await _storage.read(key: 'muted_alert_categories');
    if (val == null || val.isEmpty) return [];
    return val.split('|||');
  }

  /// Ids of notification-centre alerts the user has already read.
  ///
  /// Kept here, in the store that already keeps this device's other local
  /// lists, rather than in a separate preferences plugin. The alerts derived
  /// from inventory and pregnancy state have no database row to mark, so this
  /// is the only record that they were seen.
  static Future<void> saveReadAlertIds(int accountId, List<String> ids) async {
    await _storage.write(
        key: 'read_alert_ids_$accountId', value: ids.join('|||'));
  }

  static Future<List<String>> getReadAlertIds(int accountId) async {
    final val = await _storage.read(key: 'read_alert_ids_$accountId');
    if (val == null || val.isEmpty) return [];
    return val.split('|||');
  }

  /// Unread alert total for the bell, published by the notification centre.
  /// Cached so the badge is right on the first frame instead of flashing zero
  /// while the centre is still loading a stock snapshot.
  static Future<void> saveAlertUnreadCount(int accountId, int count) async {
    await _storage.write(
        key: 'alert_unread_count_$accountId', value: count.toString());
  }

  static Future<int> getAlertUnreadCount(int accountId) async {
    final val = await _storage.read(key: 'alert_unread_count_$accountId');
    return int.tryParse(val ?? '') ?? 0;
  }

  static Future<void> saveHiddenMedicalConditions(List<String> list) async {
    await _storage.write(key: 'hidden_medical_conditions', value: list.join('|||'));
  }

  static Future<List<String>> getHiddenMedicalConditions() async {
    final val = await _storage.read(key: 'hidden_medical_conditions');
    if (val == null || val.isEmpty) return [];
    return val.split('|||');
  }

  static Future<void> saveHiddenPregnancyInfo(bool hide) async {
    await _storage.write(key: 'hidden_pregnancy_info', value: hide.toString());
  }

  static Future<bool> getHiddenPregnancyInfo() async {
    final val = await _storage.read(key: 'hidden_pregnancy_info');
    return val == 'true';
  }

  // Clear All
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}