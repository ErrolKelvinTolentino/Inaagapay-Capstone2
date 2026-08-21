import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/stock_deduction_outcome.dart';
import 'package:inaagapay_flutter_v2/theme/app_colors.dart';
import 'package:inaagapay_flutter_v2/widgets/stock_indicators.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)),
  ));
}

Color _bgOf(WidgetTester tester, Type widgetType) {
  final container = tester.widget<Container>(
    find.descendant(of: find.byType(widgetType), matching: find.byType(Container)).first,
  );
  return ((container.decoration as BoxDecoration).color)!;
}

void main() {
  group('StockLevelChip', () {
    testWidgets('stock on the shelf is the brand colour, not a stray green',
        (tester) async {
      await _pump(tester,
          StockLevelChip.count(available: 120, unit: 'tablets', lowThreshold: 30));
      expect(find.text('120 tablets'), findsOneWidget);
      expect(_bgOf(tester, StockLevelChip), AppColors.brandSecondary);
    });

    testWidgets('low stock switches to the app warning token', (tester) async {
      await _pump(tester,
          StockLevelChip.count(available: 12, unit: 'tablets', lowThreshold: 30));
      expect(find.text('12 tablets'), findsOneWidget);
      expect(_bgOf(tester, StockLevelChip), isNot(AppColors.brandSecondary));
    });

    testWidgets('empty says so rather than showing a zero', (tester) async {
      await _pump(tester, StockLevelChip.count(available: 0, unit: 'tablets'));
      expect(find.text('Out of stock'), findsOneWidget);
      expect(find.text('0 tablets'), findsNothing);
    });
  });

  group('StockStatusCard', () {
    testWidgets('renders the message and the trailing fact', (tester) async {
      await _pump(
        tester,
        const StockStatusCard(
          message: 'This dose comes from the open vial (Batch #TD-7) — 6 will be left in it.',
          trailing: '+3 sealed',
        ),
      );
      expect(find.textContaining('Batch #TD-7'), findsOneWidget);
      expect(find.text('+3 sealed'), findsOneWidget);
    });

    testWidgets('the resting state is pink', (tester) async {
      await _pump(tester, const StockStatusCard(message: '40 doses here.'));
      expect(_bgOf(tester, StockStatusCard), AppColors.brandSecondary);
    });

    testWidgets('long copy wraps instead of overflowing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        const StockStatusCard(
          tone: StockTone.caution,
          message:
              'The open vial (Batch #BCG-2026A) was opened 5 hrs ago and expires '
              'after 6 h. This dose leaves 11 in it — use them soon.',
          trailing: '+2 sealed',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('StockOutcomePanel', () {
    testWidgets('a clean deduction reads as ordinary, in brand colour',
        (tester) async {
      final outcome = StockDeductionOutcome.fromImmunization({
        'success': true,
        'mode': 'open_vial_dose',
        'batch_number': 'TD-7',
        'doses_left_in_vial': 6,
      });
      await _pump(tester, StockOutcomePanel(outcome: outcome));
      expect(find.text('Drawn from the open vial'), findsOneWidget);
      expect(find.textContaining('Batch #TD-7'), findsOneWidget);
      expect(_bgOf(tester, StockOutcomePanel), AppColors.brandSecondary);
    });

    testWidgets('a shortfall is visibly not the resting state', (tester) async {
      final outcome = StockDeductionOutcome.fromPrenatalEncounter({
        'success': true,
        'deductions': [
          {
            'item_type': 'supplement',
            'medication': 'Calcium',
            'quantity': 20,
            'note': 'Only 20 of 30 were in stock',
          },
        ],
        'warnings': ['Calcium: 10 of 30 could not be deducted — stock ran out'],
      });
      await _pump(tester, StockOutcomePanel(outcome: outcome));
      expect(find.textContaining('partly deducted'), findsOneWidget);
      expect(find.textContaining('could not be deducted'), findsOneWidget);
      expect(_bgOf(tester, StockOutcomePanel), isNot(AppColors.brandSecondary));
    });
  });

  group('StockOutcomeDialog', () {
    testWidgets('shows the clinical line first, then the stock panel',
        (tester) async {
      final outcome = StockDeductionOutcome.fromMaternalTd(
        {'success': true, 'mode': 'no_deduction'},
        doseKey: 'Td2',
      );
      await _pump(
        tester,
        StockOutcomeDialog(
          title: 'Td2 Saved — Check Stock',
          message: 'Td2 recorded for Ana Cruz on 21 August 2026.',
          outcome: outcome,
          onPressed: () {},
        ),
      );
      expect(find.text('Td2 Saved — Check Stock'), findsOneWidget);
      expect(find.textContaining('Ana Cruz'), findsOneWidget);
      expect(find.text('Saved, but stock did not move'), findsOneWidget);
      expect(find.byType(StockOutcomePanel), findsOneWidget);
    });

    testWidgets('nothing dispensed means no empty stock panel', (tester) async {
      final outcome = StockDeductionOutcome.fromPrenatalEncounter(
          {'success': true, 'deductions': [], 'warnings': []});
      await _pump(
        tester,
        StockOutcomeDialog(
          title: 'Prenatal Checkup Saved',
          message: 'The checkup record was saved successfully.',
          outcome: outcome,
          onPressed: () {},
        ),
      );
      expect(find.byType(StockOutcomePanel), findsNothing);
    });
  });
}
