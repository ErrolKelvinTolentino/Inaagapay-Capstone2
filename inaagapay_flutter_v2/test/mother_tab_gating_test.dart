// Guards the mother's bottom navigation against index drift.
//
// Children and Records need a health centre behind them — everything on those
// pages is entered by a midwife — so they are hidden until she is assigned to
// one. Hiding a tab from a fixed list is where this goes wrong: the tabs, the
// page stack and the header title were three parallel five-element lists all
// indexed by the same integer, so removing Children silently turned index 3
// from Records into Hotlines and index 4 into a range error.
//
// The source is scanned rather than the widget rendered because the shell
// needs a signed-in mother and a live database to build at all.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _shell = 'lib/screens/mother/mother_dashboard_shell.dart';

String _codeOf(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue,
      reason: '$path not found — run tests from the package root');
  return file.readAsLinesSync().map((line) {
    final comment = line.indexOf('//');
    return comment == -1 ? line : line.substring(0, comment);
  }).join('\n');
}

void main() {
  group('the tab set is built, not hardcoded', () {
    test('tabs, pages and titles all come from one list', () {
      final source = _codeOf(_shell);

      expect(source, contains('_visibleTabs'),
          reason: 'the visible tabs must be derived from registration state');

      // Three consumers, one list. If any of them goes back to a literal
      // five-element array the header, the page and the highlighted tab can
      // disagree with each other.
      expect(source, contains('tabs.map(_screenFor)'),
          reason: 'the page stack must follow the visible tabs');
      expect(source, contains('tabs.indexed'),
          reason: 'the nav bar must follow the visible tabs');
      expect(source, contains('titles[safeIndex]'),
          reason: 'the header title must follow the visible tabs');
    });

    test('the selected index is clamped, never used raw', () {
      final source = _codeOf(_shell);

      expect(source, contains('safeIndex'),
          reason: 'a selection made while five tabs were showing must not '
              'index into a list of three');
      expect(source.contains('titles[_currentIndex]'), isFalse);
      expect(source.contains('index: _currentIndex'), isFalse);
    });
  });

  group('what a mother without a health centre can still reach', () {
    test('Children and Records are the only gated tabs', () {
      final source = _codeOf(_shell);

      // requiresBhc appears once in the enum's constructor declaration, once
      // in its field, and once per gated tab.
      final gated = 'requiresBhc: true'.allMatches(source).length;
      expect(gated, 2,
          reason: 'exactly two tabs should require a health centre; if this '
              'changed, check it was deliberate');
    });

    test('emergency hotlines are never taken away', () {
      final source = _codeOf(_shell);

      // A mother with no health centre is the one with no midwife to call.
      // Whatever else gets gated, this must not.
      final hotlinesBlock = source.substring(
        source.indexOf('hotlines('),
        source.indexOf('hotlines(') + 220,
      );
      expect(hotlinesBlock.contains('requiresBhc'), isFalse,
          reason: 'hotlines is emergency contact information and must stay '
              'reachable without a health centre');
    });

    test('home and journal stay reachable too', () {
      final source = _codeOf(_shell);

      for (final tab in ['home(', 'journal(']) {
        final start = source.indexOf(tab);
        expect(start, greaterThan(-1), reason: '$tab is missing from the tabs');
        final block = source.substring(start, start + 220);
        expect(block.contains('requiresBhc'), isFalse,
            reason: '$tab must not require a health centre');
      }
    });
  });
}
