import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:inaagapay_flutter_v2/services/immunization_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ongoing overdue mothers stay eligible; ended pregnancies do not', () async {
    const preferences = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferences,
            (call) async => call.method == 'getAll' ? <String, Object>{} : true);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferences, null));
    final recipients = <int>[];
    final now = DateTime.now();
    final pastEdd = now.subtract(const Duration(days: 28)).toIso8601String().split('T').first;
    final futureEdd = now.add(const Duration(days: 28)).toIso8601String().split('T').first;
    final client = MockClient((request) async {
      Object rows = [];
      if (request.url.path.endsWith('/vaccines')) {
        rows = [{'vaccine_id': 1, 'vaccine_name': 'TD', 'target_recipients': 'mother'}];
      } else if (request.url.path.endsWith('/mothers')) {
        rows = [for (final id in [1, 2, 3]) {'mother_id': id, 'account_id': id,
          'account': {'first_name': 'Mother', 'phone_number': null}}];
      } else if (request.url.path.endsWith('/pregnancies')) {
        final data = [
          {'pregnancy_id': 1, 'mother_id': 1, 'status': 'ongoing', 'expected_date_of_delivery': pastEdd},
          {'pregnancy_id': 2, 'mother_id': 2, 'status': 'ended', 'expected_date_of_delivery': pastEdd},
          {'pregnancy_id': 3, 'mother_id': 3, 'status': 'ongoing', 'expected_date_of_delivery': futureEdd},
        ];
        // Model the server's status and date filters rather than ignoring them.
        rows = data.where((row) {
          final status = request.url.queryParameters['status'];
          if (status != null && status != 'eq.${row['status']}') return false;
          final eddFilter = request.url.queryParameters['expected_date_of_delivery'];
          return eddFilter == null || !eddFilter.startsWith('gte.') ||
              (row['expected_date_of_delivery'] as String).compareTo(eddFilter.substring(4)) >= 0;
        }).toList();
      } else if (request.url.path.endsWith('/notifications') && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        recipients.add(body['account_id'] as int);
      }
      return http.Response(jsonEncode(rows), 200,
          headers: {'content-type': 'application/json'}, request: request);
    });
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-key',
      httpClient: client, authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(), detectSessionInUri: false, autoRefreshToken: false));
    final result = await ImmunizationReminderService.notifyEligibleBeneficiaries(
      bhcId: 1, vaccineIds: [1], scheduleDate: now.add(const Duration(days: 1)), bhcName: 'Clinic');
    expect(result.errors, isEmpty);
    expect(result.pushSent, 2);
    expect(result.smsSent, 0);
    expect(recipients, [1, 3]);
    await Supabase.instance.dispose();
  });
}
