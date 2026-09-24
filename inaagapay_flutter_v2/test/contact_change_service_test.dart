import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/contact_change_service.dart';

void main() {
  group('a new value is stored in one form', () {
    test('email is trimmed and lower-cased', () {
      expect(ContactChangeService.normalize(ContactKind.email, '  Maria.DC@Gmail.com '),
          'maria.dc@gmail.com');
    });

    test('an email without a domain is refused', () {
      expect(ContactChangeService.normalize(ContactKind.email, 'maria@gmail'), isNull);
      expect(ContactChangeService.normalize(ContactKind.email, 'maria'), isNull);
    });

    test('every way of typing a PH mobile number becomes +63', () {
      for (final typed in ['09171234567', '0917 123 4567', '+639171234567', '639171234567']) {
        expect(ContactChangeService.normalize(ContactKind.phone, typed), '+639171234567',
            reason: typed);
      }
    });

    test('a landline or short number is refused', () {
      expect(ContactChangeService.normalize(ContactKind.phone, '0441234567'), isNull);
      expect(ContactChangeService.normalize(ContactKind.phone, '0917123'), isNull);
    });
  });

  group('changing to the same address is caught', () {
    test('phone numbers compare by their last ten digits', () {
      expect(ContactChangeService.sameContact(ContactKind.phone, '+639171234567', '09171234567'),
          isTrue);
      expect(ContactChangeService.sameContact(ContactKind.phone, '+639171234567', '09181234567'),
          isFalse);
    });

    test('emails compare without case', () {
      expect(ContactChangeService.sameContact(ContactKind.email, 'A@b.com', 'a@B.com'), isTrue);
    });

    test('nothing on file is never the same', () {
      expect(ContactChangeService.sameContact(ContactKind.email, 'a@b.com', null), isFalse);
    });
  });

  group('the old address is told without revealing the new one', () {
    test('email', () {
      expect(ContactChangeService.mask(ContactKind.email, 'maria@gmail.com'), 'ma***@gmail.com');
    });
    test('phone', () {
      expect(ContactChangeService.mask(ContactKind.phone, '+639171234567'), '0917****567');
    });
  });
}
