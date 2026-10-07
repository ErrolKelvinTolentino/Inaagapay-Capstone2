import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/pregnancy_stage.dart';

void main() {
  final due = DateTime(2026, 10, 8);

  test('counts calendar days at morning, noon and midnight boundaries', () {
    for (final hour in [0, 12, 23]) {
      expect(PregnancyStage.daysUntilDue(edd: due, now: DateTime(2026, 10, 7, hour)), 1);
      expect(PregnancyStage.daysUntilDue(edd: due, now: DateTime(2026, 10, 8, hour)), 0);
      expect(PregnancyStage.daysUntilDue(edd: due, now: DateTime(2026, 10, 9, hour)), -1);
    }
  });

  test('retains the actual week past 40 and supports EDD-only records', () {
    for (final daysPastDue in [0, 1, 7, 14, 28, 70]) {
      final days = PregnancyStage.gestationalDays(
          edd: due, now: due.add(Duration(days: daysPastDue)));
      expect(days, 280 + daysPastDue);
      expect(PregnancyStage.completedWeeks(days!), 40 + daysPastDue ~/ 7);
    }
  });

  test('prefers the saved EDD and derives it only when missing', () {
    final lmp = due.subtract(const Duration(days: 280));
    expect(PregnancyStage.dueDate(lmp: lmp), due);
    expect(PregnancyStage.dueDate(lmp: lmp, edd: DateTime(2026, 10, 10, 12)), DateTime(2026, 10, 10));
    expect(PregnancyStage.dueDate(), isNull);
  });
}
