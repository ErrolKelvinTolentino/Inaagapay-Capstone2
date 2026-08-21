// Guards PostgREST selects against joining two tables that are not related.
//
// `prenatal_checkups` and `weight_gain_evaluations` are both children of
// `clinical_encounters`. Neither points at the other, so asking PostgREST for
// one nested inside the other fails with PGRST200 — and because the whole
// Records page is loaded by that one query, a mother saw "Failed to Load
// Records" with her checkups, ultrasounds and lab tests all missing.
//
// Nothing catches this before it runs: the select is a string, so the analyzer
// sees valid Dart and the failure only appears against a live database with
// data. Hence a source scan.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tables that are siblings under `clinical_encounters` — each has its own
/// `encounter_id`, and none has a foreign key to another. PostgREST can nest
/// any of them under an encounter, never under each other.
const _encounterChildren = <String>[
  'prenatal_checkups',
  'weight_gain_evaluations',
  'ultrasounds',
  'lab_tests',
];

List<File> _dartSources() {
  final dir = Directory('lib');
  expect(dir.existsSync(), isTrue,
      reason: 'run tests from the package root');
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

/// The text inside `name (` … matching `)`, for every occurrence of [name].
List<String> _nestedBlocks(String source, String name) {
  final blocks = <String>[];
  final pattern = RegExp('$name\\s*\\(');

  for (final match in pattern.allMatches(source)) {
    var depth = 1;
    var i = match.end;
    final buffer = StringBuffer();
    while (i < source.length && depth > 0) {
      final ch = source[i];
      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0) break;
      }
      buffer.write(ch);
      i++;
    }
    blocks.add(buffer.toString());
  }
  return blocks;
}

void main() {
  group('PostgREST selects only nest tables that are actually related', () {
    test('no encounter child is nested inside another encounter child', () {
      final problems = <String>[];

      for (final file in _dartSources()) {
        final source = file.readAsStringSync();

        for (final parent in _encounterChildren) {
          if (!source.contains(parent)) continue;

          for (final block in _nestedBlocks(source, parent)) {
            for (final child in _encounterChildren) {
              if (child == parent) continue;
              if (block.contains(child)) {
                problems.add('${file.path}: "$child" is nested inside '
                    '"$parent". Both hang off clinical_encounters and neither '
                    'references the other, so this select fails at runtime '
                    'with PGRST200. Nest it under the encounter instead and '
                    'carry the value across in Dart.');
              }
            }
          }
        }
      }

      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  });

  group('the schema still says what these tests assume', () {
    // If someone later adds the missing foreign key, the guard above becomes
    // wrong rather than merely unnecessary — so the assumption is checked
    // against the schema rather than left in a comment.
    test('weight_gain_evaluations hangs off encounters, not checkups', () {
      final schema = File('../database/active-draftschema.sql');
      if (!schema.existsSync()) {
        // The Flutter package can be checked out on its own; skip rather than
        // fail on a layout this test cannot see.
        return;
      }

      final sql = schema.readAsStringSync();
      final start = sql.indexOf('CREATE TABLE public.weight_gain_evaluations');
      expect(start, greaterThan(-1),
          reason: 'weight_gain_evaluations is missing from the schema');

      final body = sql.substring(start, sql.indexOf(');', start));
      expect(body, contains('REFERENCES public.clinical_encounters'));
      expect(body.contains('REFERENCES public.prenatal_checkups'), isFalse,
          reason: 'if this relationship now exists, the nesting guard above '
              'needs revisiting');
    });
  });
}
