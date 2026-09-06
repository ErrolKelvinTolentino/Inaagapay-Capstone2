import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/midwife_analytics.dart';
import 'package:inaagapay_flutter_v2/widgets/analytics/analytics_card.dart';

void main() {
  group('AnalyticsCard Empty State and Action Button Tests', () {
    testWidgets(
        'empty state renders prominent action button when prescription is present and triggers onAction',
        (tester) async {
      AnalyticsAction? receivedAction;

      const metric = AnalyticsMetric.empty(
        title: 'Supplies',
        icon: AnalyticsIcon.stock,
        message:
            'Nothing to analyse here yet. Cards appear as records are added at this health centre.',
        prescription: AnalyticsPrescription(
          label: 'Open Inventory',
          action: AnalyticsAction.viewInventory,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalyticsCard(
              metric: metric,
              onAction: (action) {
                receivedAction = action;
              },
            ),
          ),
        ),
      );

      // Verify title (rendered in uppercase in header) and empty message
      expect(find.text('SUPPLIES'), findsOneWidget);
      expect(
        find.text(
            'Nothing to analyse here yet. Cards appear as records are added at this health centre.'),
        findsOneWidget,
      );

      // Verify action button is rendered as an ElevatedButton with label and inventory icon
      final buttonFinder = find.widgetWithText(ElevatedButton, 'Open Inventory');
      expect(buttonFinder, findsOneWidget);
      expect(
        find.descendant(
          of: buttonFinder,
          matching: find.byIcon(Icons.inventory_2_outlined),
        ),
        findsOneWidget,
      );

      // Tap button and verify onAction is invoked
      await tester.tap(buttonFinder);
      await tester.pump();

      expect(receivedAction, equals(AnalyticsAction.viewInventory));
    });

    testWidgets(
        'empty state does not render action button when prescription is null',
        (tester) async {
      const metric = AnalyticsMetric.empty(
        title: 'Supplies',
        icon: AnalyticsIcon.stock,
        message: 'No records available.',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnalyticsCard(
              metric: metric,
            ),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets(
        'card with data renders prominent action button and invokes onAction',
        (tester) async {
      AnalyticsAction? receivedAction;

      const metric = AnalyticsMetric(
        title: 'Stock on hand',
        kind: AnalyticsChartKind.rankedBars,
        icon: AnalyticsIcon.stock,
        headline: '2',
        headlineCaption: 'items are below their reorder level',
        bands: [
          AnalyticsBand(
            label: 'Paracetamol',
            count: 10,
            severity: AnalyticsSeverity.alert,
          ),
        ],
        prescription: AnalyticsPrescription(
          label: 'Open inventory',
          action: AnalyticsAction.viewInventory,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalyticsCard(
                metric: metric,
                onAction: (action) {
                  receivedAction = action;
                },
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.widgetWithText(ElevatedButton, 'Open inventory');
      expect(buttonFinder, findsOneWidget);
      expect(
        find.descendant(
          of: buttonFinder,
          matching: find.byIcon(Icons.inventory_2_outlined),
        ),
        findsOneWidget,
      );

      await tester.tap(buttonFinder);
      await tester.pump();

      expect(receivedAction, equals(AnalyticsAction.viewInventory));
    });

    testWidgets(
        'action button icons match the action destination (mothers, children, schedules)',
        (tester) async {
      const mothersMetric = AnalyticsMetric.empty(
        title: 'Mothers',
        icon: AnalyticsIcon.mothers,
        message: 'No records.',
        prescription: AnalyticsPrescription(
          label: 'View Mothers',
          action: AnalyticsAction.viewMothers,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnalyticsCard(metric: mothersMetric),
          ),
        ),
      );

      final buttonFinder = find.widgetWithText(ElevatedButton, 'View Mothers');
      expect(buttonFinder, findsOneWidget);
      expect(
        find.descendant(
          of: buttonFinder,
          matching: find.byIcon(Icons.pregnant_woman_rounded),
        ),
        findsOneWidget,
      );
    });
  });
}
