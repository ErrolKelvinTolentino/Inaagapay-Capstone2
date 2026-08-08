import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/data/pregnancy_danger_signs.dart';
import 'package:inaagapay_flutter_v2/screens/mother/danger_signs_screen.dart';
import 'package:inaagapay_flutter_v2/widgets/danger_signs_card.dart';

/// Danger signs are the most time-critical content in the app. These cases
/// exist so a later refactor cannot quietly bury them again — which is the
/// state they were found in, reachable only behind a button labelled
/// "More Info".
void main() {
  group('the catalogue', () {
    test('every sign has both languages filled in', () {
      for (final sign in pregnancyDangerSigns) {
        expect(sign.english.trim(), isNotEmpty);
        expect(sign.filipino.trim(), isNotEmpty,
            reason: '"${sign.english}" has no Filipino — a mother reading '
                'Filipino would get an English-only emergency instruction');
        expect(sign.filipino, isNot(equals(sign.english)));
      }
    });

    test('no two signs share an icon', () {
      // The icon carries the meaning for someone who reads slowly. Two signs
      // wearing the same one makes the list harder to scan, not easier.
      final icons = pregnancyDangerSigns.map((s) => s.icon.codePoint).toList();
      expect(icons.toSet().length, icons.length);
    });

    test('the list stays short enough to scan in one breath', () {
      expect(pregnancyDangerSigns.length, lessThanOrEqualTo(10));
      expect(pregnancyDangerSigns.length, greaterThanOrEqualTo(6));
    });

    test('no clinical vocabulary a mother would have to decode', () {
      // The source wording included "vaginal", "preterm labor" and
      // "contractions before Week 37" in the same breath as its duplicate.
      const jargon = ['preterm', 'vaginal', 'hemorrhage', 'edema', 'gestational'];
      for (final sign in pregnancyDangerSigns) {
        final text = sign.english.toLowerCase();
        for (final word in jargon) {
          expect(text.contains(word), isFalse,
              reason: '"${sign.english}" contains "$word"');
        }
      }
    });
  });

  group('the screen', () {
    testWidgets('lists every sign and offers a call without scrolling',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DangerSignsScreen()));
      await tester.pumpAndSettle();

      for (final sign in pregnancyDangerSigns) {
        expect(find.text(sign.english, skipOffstage: false), findsOneWidget,
            reason: '"${sign.english}" is missing from the screen');
      }

      // Pinned outside the scroll view, so a mother who has scrolled to the
      // bottom of the list does not have to scroll back to act.
      expect(find.text('Call 911').hitTestable(), findsOneWidget);
    });

    testWidgets('says go now, without hedging', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DangerSignsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('go now', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('the card', () {
    testWidgets('opens the full list when tapped', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DangerSignsCard()),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(DangerSignsScreen), findsNothing);

      await tester.tap(find.byType(DangerSignsCard));
      await tester.pumpAndSettle();

      expect(find.byType(DangerSignsScreen), findsOneWidget);
    });

    testWidgets('carries an icon and a word, not colour alone', (tester) async {
      // Colour-blind users, and cheap screens in daylight, get nothing from a
      // red border by itself.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DangerSignsCard()),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
      expect(find.text('When to get help fast'), findsOneWidget);
    });
  });
}
