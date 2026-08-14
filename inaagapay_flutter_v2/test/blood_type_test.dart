import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/blood_type.dart';

void main() {
  group('BloodType.parse accepts what lab reports actually print', () {
    const accepted = <String, String>{
      'O+': 'O+',
      'O-': 'O-',
      'AB+': 'AB+',
      'A-': 'A-',
      'O Positive': 'O+',
      'B Negative': 'B-',
      'o pos': 'O+',
      'A NEG': 'A-',
      'Blood Type: B Negative': 'B-',
      'BLOOD TYPING: AB POSITIVE': 'AB+',
      'ABO Group: A, Rh: Positive': 'A+',
      'AB Rh(D) Positive': 'AB+',
      'Type O, Rh Negative': 'O-',
      'Blood Group B Rhesus Positive': 'B+',
      '  a+  ': 'A+',
    };

    accepted.forEach((input, expected) {
      test('"$input" reads as $expected', () {
        expect(BloodType.parse(input), expected);
      });
    });

    test('reads a zero as the letter O, which is how OCR sees printed forms',
        () {
      expect(BloodType.parse('0+'), 'O+');
      expect(BloodType.parse('0 Positive'), 'O+');
    });
  });

  group('BloodType.parse refuses anything less than a whole answer', () {
    const rejected = <String>[
      // Nothing to read.
      '',
      '   ',
      'Unknown',
      'N/A',
      'None',
      'null',

      // A group with no Rh is not a blood type, and is not in the CHECK list.
      'A',
      'O',
      'AB',
      'Blood Type: A',
      'ABO: O, Rh: not determined',

      // Rh with no group.
      'Positive',
      '+',

      // The false positive this parser exists to prevent: prose that merely
      // begins with a letter that happens to name a blood group.
      'A positive result for HBsAg',
      'B negative for growth on culture',
      'O2 saturation 98 percent',

      // A reference table listing every option, not a result.
      'A+ A- B+ B- AB+ AB- O+ O-',

      // Not a blood type at all.
      'Hemoglobin 12.5 g/dL',
      'C+',
      'AA+',
    ];

    for (final input in rejected) {
      test('"$input" reads as nothing', () {
        expect(BloodType.parse(input), isNull);
      });
    }

    test('null in, null out', () {
      expect(BloodType.parse(null), isNull);
    });
  });

  group('BloodType guards the database constraint', () {
    test('every value it can return is one the column accepts', () {
      const columnAllows = {'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'};
      expect(BloodType.values.toSet(), columnAllows);
    });

    test('never emits "Unknown", which the CHECK constraint would reject', () {
      expect(BloodType.values.contains('Unknown'), isFalse);
      for (final spelling in ['Unknown', 'UNKNOWN', 'unknown']) {
        expect(BloodType.parse(spelling), isNull);
      }
    });

    test('isValid only passes storable values', () {
      expect(BloodType.isValid('O+'), isTrue);
      expect(BloodType.isValid('Unknown'), isFalse);
      expect(BloodType.isValid('o+'), isFalse);
      expect(BloodType.isValid(null), isFalse);
    });
  });
}
