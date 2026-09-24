import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/account_status_guard.dart';

void main() {
  group('the sign-out notice', () {
    test('names a suspension', () {
      expect(
        AccountStatusGuard.signOutNotice(status: 'suspended'),
        startsWith('Your account has been suspended'),
      );
    });

    test('reads any other non-active status as a deactivation', () {
      expect(
        AccountStatusGuard.signOutNotice(status: 'inactive'),
        startsWith('Your account has been deactivated'),
      );
    });

    test('a deleted account is told it no longer exists', () {
      expect(
        AccountStatusGuard.signOutNotice(status: null),
        startsWith('This account no longer exists'),
      );
    });

    test('carries the administrator\'s reason when one was given', () {
      expect(
        AccountStatusGuard.signOutNotice(
            status: 'suspended', reason: '  Under review  '),
        endsWith('Reason given: Under review'),
      );
    });

    test('points to the health center when there is no reason', () {
      expect(
        AccountStatusGuard.signOutNotice(status: 'suspended', reason: ' '),
        endsWith('Please contact your health center.'),
      );
    });
  });
}
