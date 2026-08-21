// Keeps the version shown in Settings honest.
//
// The About section states an app version. Reading it through a platform
// plugin means one more dependency that can fail on one platform and not
// another — and this app has already been bitten by a newly added plugin
// silently dropping its writes. So the version is a constant, and this test is
// what stops a constant from drifting away from the real one.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/settings_screen.dart';

void main() {
  test('the version shown in Settings matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue,
        reason: 'run tests from the package root');

    final line = pubspec
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
    expect(line, isNotEmpty, reason: 'pubspec.yaml has no version line');

    final declared = line.substring('version:'.length).trim();

    expect(kAppVersion, declared,
        reason: 'Settings shows "$kAppVersion" but pubspec.yaml says '
            '"$declared". Update kAppVersion in '
            'lib/screens/settings_screen.dart when bumping the version.');
  });
}
