import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final _client = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> getNotifications(int accountId, {int limit = 50}) async {
    final result = await _client
        .from('notifications')
        .select()
        .eq('account_id', accountId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(result);
  }

  static Future<int> getUnreadCount(int accountId) async {
    final result = await _client
        .from('notifications')
        .select('notification_id')
        .eq('account_id', accountId)
        .eq('is_read', false);
    return (result as List).length;
  }

  static Future<void> markAsRead(int notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('notification_id', notificationId);
  }

  static Future<void> markAllAsRead(int accountId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('account_id', accountId)
        .eq('is_read', false);
  }

  /// Insert a notification row into the `notifications` table.
  /// This automatically triggers the DB trigger `trg_send_push_notification`
  /// which invokes the Edge Function to deliver a push notification via FCM.
  ///
  /// [accountId] – the mother's account_id (the notification recipient).
  /// [title]     – notification title shown in the push.
  /// [message]   – notification body text.
  /// [type]      – one of 'checkup_reminder', 'vaccine_reminder', or 'general'.
  static Future<void> createNotification({
    required int accountId,
    required String title,
    required String message,
    String type = 'general',
  }) async {
    await _client.from('notifications').insert({
      'account_id': accountId,
      'title': title,
      'message': message,
      'type': type,
      'is_read': false,
    });
  }

  static RealtimeChannel subscribeToNotifications(int accountId, void Function(Map<String, dynamic>) onNew) {
    return _client
        .channel('notifications:$accountId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'account_id',
            value: accountId,
          ),
          callback: (payload) {
            onNew(payload.newRecord);
          },
        )
        .subscribe();
  }
}
