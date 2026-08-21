// Guards the narrative on the growth card against saying less than the card
// shows.
//
// The card renders a verdict chip for each of the three indicators and then a
// paragraph explaining them. The paragraph used to cover only two: a child
// could be flagged "Above standard range" for body proportion and find nothing
// in the text about it. The same paragraph opened with "Height is also
// shorter…" whenever weight was within range, because "also" was baked into the
// height sentence rather than depending on a weight sentence preceding it.
//
// Both are invisible to the analyzer and to the calculator tests, so they need
// a rendering test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/growth_calculator.dart';
import 'package:inaagapay_flutter_v2/widgets/growth_summary_card.dart';

/// Renders the card and returns every string it painted.
Future<List<String>> _renderedText(
  WidgetTester tester, {
  required double heightCm,
  required double weightKg,
  int ageWeeks = 27,
  String sex = 'female',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GrowthSummaryCard(
            childFirstName: 'Madeline',
            sex: sex,
            measurements: [
              GrowthMeasurement(
                takenAt: DateTime(2026, 1, 1),
                heightCm: heightCm,
                weightKg: weightKg,
                ageWeeks: ageWeeks,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
}

/// A measurement set where weight sits inside the band and height below it —
/// the combination in which the old paragraph opened on a dangling "also".
const _shortForAge = (heightCm: 49.0, weightKg: 7.0);

void main() {
  group('growth narrative', () {
    testWidgets('names every indicator that falls outside the range',
        (tester) async {
      final texts = await _renderedText(
        tester,
        heightCm: _shortForAge.heightCm,
        weightKg: _shortForAge.weightKg,
      );
      final paragraph = texts.firstWhere(
        (t) => t.contains('regular check-ups'),
        orElse: () => '',
      );

      expect(paragraph, isNotEmpty,
          reason: 'the card should render a summary paragraph');

      // Whichever indicators the calculator puts outside the band must each be
      // spoken for, rather than the paragraph covering only weight and height.
      final outside = <GrowthMetric>[];
      for (final metric in GrowthMetric.values) {
        final z = GrowthCalculator.zScoreFor(
          metric,
          metric == GrowthMetric.weightForAge
              ? _shortForAge.weightKg
              : metric == GrowthMetric.heightForAge
                  ? _shortForAge.heightCm
                  : _shortForAge.weightKg /
                      ((_shortForAge.heightCm / 100) *
                          (_shortForAge.heightCm / 100)),
          27,
          'female',
        );
        if (!GrowthCalculator.bandForZScore(z).isWithin) outside.add(metric);
      }

      expect(outside, isNotEmpty,
          reason: 'the fixture should put at least one indicator outside');

      for (final metric in outside) {
        final keyword = switch (metric) {
          GrowthMetric.weightForAge => 'weighs',
          GrowthMetric.heightForAge => 'shorter',
          GrowthMetric.bmiForAge => 'Body proportion',
        };
        expect(paragraph, contains(keyword),
            reason: '${metric.label} is outside the range but the paragraph '
                'never mentions it');
      }
    });

    testWidgets('never opens on a dangling "also"', (tester) async {
      final texts = await _renderedText(
        tester,
        heightCm: _shortForAge.heightCm,
        weightKg: _shortForAge.weightKg,
      );
      final paragraph = texts.firstWhere(
        (t) => t.contains('regular check-ups'),
        orElse: () => '',
      );

      expect(paragraph.trimLeft(), isNot(startsWith('Height is also')));
      expect(paragraph, isNot(contains('is also shorter')));
    });

    testWidgets('says so plainly when all three are within range',
        (tester) async {
      // A median-ish six-month-old girl: every indicator should land inside.
      final texts = await _renderedText(tester, heightCm: 65.7, weightKg: 7.3);
      final paragraph = texts.firstWhere(
        (t) => t.contains('growing well'),
        orElse: () => '',
      );

      expect(paragraph, contains('Weight, height and body proportion'));
      expect(paragraph, isNot(contains('check-ups')),
          reason: 'nothing is outside the range, so there is nothing to '
              'follow up on');
    });

    testWidgets('carries the standard it judged by', (tester) async {
      final texts = await _renderedText(tester, heightCm: 65.7, weightKg: 7.3);

      expect(texts.any((t) => t.contains('Clinical Disclaimer & References')),
          isTrue,
          reason: 'a reading should show whose rule it was measured against');
    });
  });
}
