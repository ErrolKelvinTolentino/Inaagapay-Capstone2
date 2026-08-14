// lib/models/blood_type.dart
//
// Reading an ABO/Rh blood type off a document, strictly.
//
// Blood type is the one field in this app where a confident wrong answer is
// more dangerous than no answer: it is what a hospital reaches for during a
// postpartum haemorrhage. So this parser is deliberately unhelpful. It accepts
// a value only when the text says the whole thing plainly — group *and* Rh —
// and returns null for everything else, including everything it half
// understands. "A" is not a blood type. "O, Rh unknown" is not a blood type.
//
// It never returns "Unknown" either. `mothers.blood_type` carries a CHECK
// constraint listing exactly eight strings, so "Unknown" would not be a weak
// answer — it would be a database error at insert time.

class BloodType {
  const BloodType._();

  /// The only values `mothers.blood_type` will accept.
  ///
  /// Mirrors the CHECK constraint in `database/active-draftschema.sql`. Kept in
  /// this order because it is the order the DOH prenatal card prints them.
  static const List<String> values = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  /// Words that label a blood type on a lab report without being part of one.
  ///
  /// Stripped before matching so "Blood Type: B Negative" and "ABO Group: B,
  /// Rh: Negative" both reduce to the same two tokens.
  static final RegExp _labels = RegExp(
    r'\b(BLOOD|TYPING|TYPE|ABO|GROUPING|GROUP|RH|RHESUS|FACTOR|RESULT)\b',
  );

  /// The shape a blood type has once the labels are gone.
  ///
  /// Anchored end to end on purpose. An unanchored match would read "A" out of
  /// "A positive result for HBsAg" and file it as A+ — the exact class of
  /// mistake this parser exists to prevent.
  static final RegExp _pattern = RegExp(
    r'^(AB|A|B|O)\s*(\+|-|POS(?:ITIVE)?|NEG(?:ATIVE)?)$',
  );

  /// The canonical blood type in [raw], or null if it does not plainly state one.
  ///
  /// Handles the spellings that actually turn up on Philippine lab reports —
  /// "O Positive", "O+", "AB Rh(D) Positive", "Blood Type: B Neg" — plus the
  /// zero-for-O confusion that OCR reliably produces on printed forms.
  static String? parse(String? raw) {
    if (raw == null) return null;

    var text = raw.toUpperCase().trim();
    if (text.isEmpty) return null;

    // Values the model may return in place of an answer. Checked before
    // anything else so they can never be massaged into a type.
    if (text == 'UNKNOWN' || text == 'NULL' || text == 'N/A' || text == 'NONE') {
      return null;
    }

    // OCR reads the letter O as a zero on most printed forms.
    text = text.replaceAll('0', 'O');

    text = text
        .replaceAll(_labels, ' ')
        .replaceAll(RegExp(r'\(\s*D\s*\)'), ' ')
        .replaceAll(RegExp(r'[.,:;()\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final match = _pattern.firstMatch(text);
    if (match == null) return null;

    final group = match.group(1)!;
    final rhesus = match.group(2)!;
    final sign = rhesus.startsWith('N') || rhesus == '-' ? '-' : '+';

    final result = '$group$sign';

    // Belt and braces: nothing leaves here that the column would reject.
    return values.contains(result) ? result : null;
  }

  /// Whether [value] is storable as-is.
  static bool isValid(String? value) =>
      value != null && values.contains(value);
}
