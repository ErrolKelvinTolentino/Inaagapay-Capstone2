// Guards the schedule badge against calling a past date "upcoming".
//
// Every prenatal row on the schedules screen carried the literal string
// 'upcoming', and every booked row mapped straight across from 'scheduled'.
// Nothing on the screen compared the date to today, so a visit three days gone
// still read UPCOMING — the one thing it is not.
//
// The rule is a pure date comparison, so it is checked here directly rather
// than through the screen.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screen = 'lib/screens/midwife/midwife_schedules_screen.dart';

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
  group('schedule badges consult the date', () {
    test('no row hard-codes its own standing', () {
      final source = _codeOf(_screen);

      expect(source.contains("'status': 'upcoming'"), isFalse,
          reason: 'a row that always claims to be upcoming will still claim it '
              'a week after the visit');
      expect(source.contains("status == 'scheduled' ? 'upcoming' : status"),
          isFalse,
          reason: 'mapping scheduled straight to upcoming ignores the date');
    });

    test('standing is derived from the date being viewed', () {
      final source = _codeOf(_screen);

      expect(source, contains('_scheduleStanding'),
          reason: 'the badge must be computed from the date');
      expect(source, contains("'status': _scheduleStanding(date)"),
          reason: 'prenatal rows must take their standing from the date shown');
    });

    test('past and today are rendered, not left to the default colour', () {
      final source = _codeOf(_screen);

      // Both land in _getStatusColor. Without their own cases they fall to the
      // default grey, which would make "TODAY" — the one that needs acting on —
      // the quietest badge on the screen.
      expect(source, contains("case 'today':"));
      expect(source, contains("case 'past':"));
    });
  });

  group('immunization drives read like every other row', () {
    test('a drive is badged by its date, not by its own category', () {
      final source = _codeOf(_screen);

      expect(source.contains("'status': 'immunization'"), isFalse,
          reason: 'IMMUNIZATION repeats the type line directly beneath it and '
              'never says whether the drive has happened');
      expect(source, contains("'status': _scheduleStanding(date)"));
    });

    test('a vaccine already named "… Vaccine" is not doubled', () {
      final source = _codeOf(_screen);

      expect(source, contains('_withoutTrailingVaccine'),
          reason: '"BCG Vaccine" + " Vaccine Drive" reads as '
              '"BCG Vaccine Vaccine Drive" on the card');
      expect(source.contains("'\$vaccineName Vaccine Drive'"), isFalse);
    });
  });

  group('the tarpaulin poster is hidden, not deleted', () {
    test('the shortcut is behind a flag and the route still exists', () {
      final source = _codeOf(_screen);

      expect(source, contains('_showTarpaulinPosterCard'),
          reason: 'hiding the card should be one flag, not a deletion');
      expect(source, contains('/immunization-poster'),
          reason: 'the poster route must survive hiding its entry point');
    });
  });
}
