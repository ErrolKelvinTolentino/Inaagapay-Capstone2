import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:inaagapay_flutter_v2/services/vaccination_drive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const preferences = MethodChannel('plugins.flutter.io/shared_preferences');
  final requests = <Map<String, dynamic>>[];
  var facilityOnly = false;
  var failSave = false;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferences,
            (call) async => call.method == 'getAll' ? <String, Object>{} : true);
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
      httpClient: MockClient((request) async {
        // Scheduling alone must not introduce audit RPCs or notifications.
        expect(request.url.path, '/rest/v1/immunization_schedule');
        expect(request.method, 'POST');
        final row = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(row);
        if (failSave || (facilityOnly && row.containsKey('bhc_id'))) {
          return http.Response(jsonEncode({'code': 'PGRST204', 'message': 'Column not available'}), 400,
              headers: {'content-type': 'application/json'}, request: request);
        }
        return http.Response(jsonEncode({'immunization_schedule_id': 17}), 201,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferences, null);
  });
  setUp(() {
    requests.clear();
    facilityOnly = false;
    failSave = false;
  });

  test('scheduling persists the actual account id with the drive', () async {
    final id = await VaccinationDriveService.createDrive(
      bhcId: 3, vaccineId: 1, date: DateTime(2026, 10, 9),
      notes: '  Morning drive  ', scheduledBy: 10,
    );
    expect(id, 17);
    expect(requests, hasLength(1));
    expect(requests.single['scheduled_by'], 10);
    expect(requests.single['schedule_date'], '2026-10-09');
    expect(requests.single['notes'], 'Morning drive');
  });

  test('the facility-column fallback preserves the audit actor', () async {
    facilityOnly = true;
    final id = await VaccinationDriveService.createDrive(
      bhcId: 3, vaccineId: 1, date: DateTime(2026, 10, 9), scheduledBy: 10,
    );
    expect(id, 17);
    expect(requests, hasLength(3));
    expect(requests.every((row) => row['scheduled_by'] == 10), isTrue);
    expect(requests.last['facility_id'], 3);
    expect(requests.last.containsKey('bhc_id'), isFalse);
  });

  test('callers without an actor stay compatible without inventing one', () async {
    expect(await VaccinationDriveService.createDrive(
      bhcId: 3, vaccineId: 1, date: DateTime(2026, 10, 9),
    ), 17);
    expect(requests.single.containsKey('scheduled_by'), isFalse);
  });

  test('a refused save does not report a successful drive', () async {
    failSave = true;
    expect(await VaccinationDriveService.createDrive(
      bhcId: 3, vaccineId: 1, date: DateTime(2026, 10, 9), scheduledBy: 10,
    ), isNull);
  });
}
