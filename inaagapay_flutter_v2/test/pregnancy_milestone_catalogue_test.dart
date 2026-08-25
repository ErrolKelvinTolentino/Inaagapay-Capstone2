import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/data/baby_growth_milestone_data.dart';
import 'package:inaagapay_flutter_v2/models/baby_growth_milestone.dart';

/// The prenatal milestone catalogue exists twice: once in Dart, as the list
/// the preview and the widget tests draw, and once in SQL, as the rows a real
/// mother's app actually reads from `milestone_templates`.
///
/// Two copies of the same list drift. The first symptom of that drift is the
/// one that prompted this file: the Dart list was rewritten and the screen
/// kept showing the old nine, because the screen never read the Dart list —
/// it reads the database, and the seed had not been touched. Nothing failed;
/// the app just quietly served the previous catalogue.
///
/// These tests do not check that the migration has been *run* — no test can
/// see the user's database. They check that the two definitions say the same
/// thing, so that applying the migration is the only step left.
void main() {
  /// Every migration that touches the prenatal catalogue, oldest first.
  ///
  /// Read as a set rather than by name: the catalogue is amended over time —
  /// the lab bundle was split in a second migration — and a test pinned to
  /// one filename would pass while describing a catalogue that no longer
  /// exists.
  List<File> seeds() {
    final dir = Directory('../database/migrations');
    expect(dir.existsSync(), isTrue, reason: 'migrations directory missing');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .where((f) => f.readAsStringSync().contains("'prenatal', 'checkup'") ||
            f.readAsStringSync().contains("'prenatal', 'ultrasound'"))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: 'no prenatal catalogue migration found');
    return files;
  }

  /// Statement text only, with the `--` commentary stripped out, so prose in
  /// a migration header cannot be mistaken for a seeded value.
  String bodyOf(File file) => file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  String sqlBody() => seeds().map(bodyOf).join('\n');

  /// The keys left active after every migration has run, applied in order.
  Set<String> activeKeys() {
    final active = <String>{};
    for (final file in seeds()) {
      final body = bodyOf(file);

      for (final match
          in RegExp(r"\('([a-z0-9-]+)', 'prenatal'").allMatches(body)) {
        active.add(match.group(1)!);
      }

      // Everything named by a `SET is_active = false` block is retired. The
      // blocks list their keys inside an IN (...), one quoted key per line.
      for (final retire in RegExp(
        r'SET is_active = false(.*?);',
        dotAll: true,
      ).allMatches(body)) {
        for (final key
            in RegExp(r"'([a-z0-9-]+)'").allMatches(retire.group(1)!)) {
          active.remove(key.group(1));
        }
      }
    }
    return active;
  }

  test('every Dart milestone is seeded under the same template key', () {
    final body = sqlBody();
    for (final milestone in babyGrowthMilestoneSampleData) {
      expect(
        body,
        contains("'${milestone.id}'"),
        reason:
            '"${milestone.title}" has no row in the seed, so a real account '
            'would never see it',
      );
      expect(
        body,
        contains(milestone.title),
        reason: 'the seeded title for ${milestone.id} does not match the Dart '
            'title "${milestone.title}"',
      );
    }
  });

  test('what stays active after every migration is exactly the Dart list', () {
    final keys = activeKeys();
    final dartIds = babyGrowthMilestoneSampleData.map((m) => m.id).toSet();

    expect(
      keys,
      isNotEmpty,
      reason: 'the seed parsed to zero rows — has its INSERT changed shape?',
    );
    expect(
      keys.difference(dartIds),
      isEmpty,
      reason: 'seeded rows with no Dart counterpart would appear only for '
          'real accounts, never in the preview or these tests',
    );
    expect(
      dartIds.difference(keys),
      isEmpty,
      reason: 'Dart rows with no active seed are the failure that started '
          'this file: the preview shows them and a real account never does',
    );
  });

  test('retired templates are deactivated, never deleted', () {
    final body = sqlBody();

    // baby_book_milestones.template_id is ON DELETE SET NULL, so deleting a
    // template severs every milestone already recorded against it — a
    // recorded anatomy scan would survive as a row with no name.
    expect(
      body.toUpperCase(),
      isNot(contains('DELETE FROM')),
      reason: 'retire a template with is_active = false, do not delete it',
    );
    expect(body, contains('SET is_active = false'));

    for (final retired in const <String>[
      'pregnancy-confirmed',
      'first-ultrasound',
      'heart-activity',
      'second-trimester',
      'first-movement',
      'anatomy-scan',
      'third-trimester',
      'birth-preparation',
      // The bundled lab row, replaced by four separately markable tests.
      'early-pregnancy-labs',
    ]) {
      expect(
        activeKeys(),
        isNot(contains(retired)),
        reason: 'the old template $retired is neither retired nor re-seeded, '
            'so it would stay active alongside the new catalogue',
      );
    }
  });

  test('the catalogue is care a mother can attend', () {
    // Fetal development belongs to the growth journey, which is a different
    // section with a different job. Anything here should be something she can
    // turn up to, so the categories are limited accordingly.
    for (final milestone in babyGrowthMilestoneSampleData) {
      expect(
        milestone.category,
        anyOf(
          BabyGrowthMilestoneCategory.checkup,
          BabyGrowthMilestoneCategory.ultrasound,
        ),
        reason: '"${milestone.title}" is not care she can attend',
      );
    }
  });

  test('anything still outstanding leaves her someone to ask', () {
    // Completed entries are exempt: "This is recorded in InaAgapay" is the
    // whole answer, and sending her to her midwife about something already
    // done is the failure this section was rewritten to avoid.
    //
    // Everything else is checked against the not-recorded wording rather than
    // its current status, so the invariant holds for whatever status a
    // template later takes, not just the one it happens to have today.
    for (final milestone in babyGrowthMilestoneSampleData) {
      if (milestone.status == BabyGrowthMilestoneStatus.completed) continue;
      final text = '${milestone.description} '
              '${milestone.copyWith(status: BabyGrowthMilestoneStatus.notRecorded).recordGuidance}'
          .toLowerCase();
      expect(
        text,
        contains('midwife'),
        reason: '"${milestone.title}" leaves her with no one to ask',
      );
    }
  });
}
