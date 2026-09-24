// lib/services/pregnancy_stage.dart
//
// Where a pregnancy is, from its dates. One definition for every screen that
// counts trimesters, so the dashboard's caseload card and its analytics card
// cannot give two different answers for the same mother.
//
// Trimesters follow completed weeks, the convention on the Mother and Baby
// Book and in WHO antenatal guidance:
//
//   first    0w0d – 13w6d
//   second  14w0d – 27w6d
//   third   28w0d onwards
//
// The dashboard used to compare fractional weeks against 13 and 27, which put
// 13w1d–13w6d in the second trimester, and it skipped every pregnancy dated by
// its due date alone.

enum Trimester { first, second, third }

class PregnancyStage {
  const PregnancyStage._();

  /// A term pregnancy is dated 280 days from the last menstrual period.
  static const int termDays = 280;

  /// Days since the last menstrual period, or null when neither date is on
  /// file. Falls back to the due date — an ultrasound-dated pregnancy may have
  /// no LMP recorded at all.
  static int? gestationalDays({
    DateTime? lmp,
    DateTime? edd,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    if (lmp != null) {
      return today.difference(DateTime(lmp.year, lmp.month, lmp.day)).inDays;
    }
    if (edd != null) {
      final due = DateTime(edd.year, edd.month, edd.day);
      return termDays - due.difference(today).inDays;
    }
    return null;
  }

  static int completedWeeks(int gestationalDays) => gestationalDays ~/ 7;

  static Trimester trimesterOf(int gestationalDays) {
    final weeks = completedWeeks(gestationalDays);
    if (weeks < 14) return Trimester.first;
    if (weeks < 28) return Trimester.second;
    return Trimester.third;
  }

  /// Parses the loose values Supabase returns for a date column.
  static DateTime? parse(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}
