// medical_conditions is keyed on `med_condition_id`. Both profile pages read
// and filtered on `medical_condition_id`, which does not exist: the row's id
// read back null, so "Remove" silently did nothing and "Save Changes" threw
// "type 'Null' is not a subtype of type 'Object'" from .eq().
//
// The column name is a string, so the analyzer cannot see the mistake. Hence a
// source scan, in the manner of postgrest_relationship_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no source refers to medical_condition_id', () {
    final dir = Directory('lib');
    expect(dir.existsSync(), isTrue, reason: 'run tests from the package root');

    final offenders = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('medical_condition_id'))
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty,
        reason: 'medical_conditions has no medical_condition_id column; its '
            'key is med_condition_id. Found in: ${offenders.join(', ')}');
  });

  test('the schema still names the key med_condition_id', () {
    final schema = File('../database/active-draftschema.sql');
    // The package can be checked out on its own; skip rather than fail.
    if (!schema.existsSync()) return;

    final sql = schema.readAsStringSync();
    final start = sql.indexOf('CREATE TABLE public.medical_conditions');
    expect(start, greaterThan(-1));
    expect(sql.substring(start, sql.indexOf(');', start)),
        contains('med_condition_id BIGSERIAL PRIMARY KEY'));
  });
}
