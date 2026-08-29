import 'package:flutter/foundation.dart';

import 'auth_storage.dart';

/// The number on the bell, and the number the notification centre shows.
///
/// These used to be two unrelated counts. The bell asked
/// `NotificationService.getUnreadCount`, which counts unread rows in the
/// `notifications` table; the centre it opens counts unread items in its own
/// list, which is those rows PLUS the alerts it derives from live stock —
/// out-of-stock, low stock, expiring batches, pending transfers, clinical
/// flags. The derived ones exist in no table, so the bell could never see them
/// and the two numbers disagreed by however many were outstanding: 2 on the
/// bell against 6 unread in the centre.
///
/// A badge is a promise about what is behind it, so the centre is the authority
/// and publishes here. The bell reads this and nothing else.
///
/// The count is persisted per account, so the badge survives a restart and is
/// right on the first frame rather than flashing zero.
class MidwifeAlertBadge {
  const MidwifeAlertBadge._();

  /// Live count. The shell listens so the bell updates the moment an alert is
  /// marked read, rather than waiting for the next tab change.
  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  /// Called by the notification centre whenever its unread total changes.
  static Future<void> publish(int accountId, int unread) async {
    count.value = unread;
    try {
      await AuthStorage.saveAlertUnreadCount(accountId, unread);
    } catch (e) {
      // A badge that cannot be cached is still correct for this session; it
      // just starts from the last good value next launch. Not worth surfacing.
      debugPrint('MidwifeAlertBadge: could not cache the count: $e');
    }
  }

  /// The last published count for this account.
  ///
  /// Read at startup, before the centre has been opened. It is the previous
  /// session's answer, so it can lag a stock change made elsewhere until the
  /// centre is next opened — which is also true of the count it replaces, since
  /// the shell only ever refreshed on a tab change.
  static Future<int> restore(int accountId) async {
    try {
      final stored = await AuthStorage.getAlertUnreadCount(accountId);
      count.value = stored;
      return stored;
    } catch (e) {
      debugPrint('MidwifeAlertBadge: could not read the cached count: $e');
      return count.value;
    }
  }
}
