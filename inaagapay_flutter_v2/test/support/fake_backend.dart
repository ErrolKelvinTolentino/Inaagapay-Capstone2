// A stand-in Supabase for widget tests.
//
// The screens talk to Supabase.instance.client directly, so they cannot be
// driven in a test without a backend. This initialises the real client once,
// pointed at a fake project whose HTTP layer answers from [FakeBackend.tables]
// -- or fails every request the way a phone with no connection does, when
// [FakeBackend.offline] is set.
//
// Only reads are modelled faithfully: a GET returns the rows registered for
// that table (filtered by any `column=eq.value` in the query), and a request
// asking for one object gets the first match. Writes are answered with the
// row they sent, which is all the screens under test need.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Not a direct dependency: supabase_flutter keeps its session through it.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeBackend {
  FakeBackend._();

  static const String url = 'https://fake-project.supabase.co';

  /// Rows per table, as PostgREST would return them.
  static final Map<String, List<Map<String, dynamic>>> tables = {};

  /// Answers for RPCs by function name.
  static final Map<String, Object?> rpcs = {};

  /// Every request fails with a lost-connection error.
  static bool offline = false;

  /// Requests seen, newest last, as "METHOD /rest/v1/table?query".
  static final List<String> requests = [];

  static bool _initialised = false;

  /// Call from setUpAll. Safe to call more than once.
  static Future<void> init({Map<String, String> storage = const {}}) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues(Map<String, String>.from(storage));
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad(fileInput: 'SUPABASE_URL=$url\nSUPABASE_ANON_KEY=test-key');
    // Image and asset plugins some screens touch on first build.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/firebase_messaging'),
            (_) async => null);
    if (_initialised) return;
    await Supabase.initialize(
      url: url,
      anonKey: 'test-key',
      httpClient: MockClient(_handle),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    _initialised = true;
  }

  /// Clears tables, answers and the offline switch between tests.
  static void reset({Map<String, String> storage = const {}}) {
    tables.clear();
    rpcs.clear();
    requests.clear();
    offline = false;
    FlutterSecureStorage.setMockInitialValues(Map<String, String>.from(storage));
  }

  static Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    requests.add('${request.method} $path?${request.url.query}');
    if (offline) {
      throw http.ClientException(
        "SocketException: Failed host lookup: '${request.url.host}' "
        '(OS Error: No address associated with hostname, errno = 7)',
        request.url,
      );
    }

    const headers = {'content-type': 'application/json; charset=utf-8'};
    final wantsOne = (request.headers['accept'] ?? '').contains('vnd.pgrst.object');

    if (path.startsWith('/rest/v1/rpc/')) {
      final name = path.substring('/rest/v1/rpc/'.length);
      return http.Response(jsonEncode(rpcs[name]), 200, headers: headers, request: request);
    }

    if (!path.startsWith('/rest/v1/')) {
      return http.Response('{}', 200, headers: headers, request: request);
    }
    final table = path.substring('/rest/v1/'.length);

    if (request.method != 'GET') {
      // Echo the written row back: enough for .insert(...).select().
      Object? body;
      try {
        body = request.body.isEmpty ? null : jsonDecode(request.body);
      } catch (_) {}
      final row = body is List ? (body.isEmpty ? {} : body.first) : (body ?? {});
      return http.Response(jsonEncode(wantsOne ? row : [row]), 201, headers: headers, request: request);
    }

    var rows = List<Map<String, dynamic>>.from(tables[table] ?? const []);
    request.url.queryParameters.forEach((column, filter) {
      if (!filter.startsWith('eq.')) return;
      final value = filter.substring(3);
      rows = rows.where((r) => '${r[column]}' == value).toList();
    });

    if (wantsOne) {
      if (rows.isEmpty) {
        return http.Response(
          jsonEncode({
            'code': 'PGRST116',
            'details': 'The result contains 0 rows',
            'message': 'JSON object requested, multiple (or no) rows returned',
          }),
          406,
          headers: headers,
          request: request,
        );
      }
      return http.Response(jsonEncode(rows.first), 200, headers: headers, request: request);
    }
    return http.Response(jsonEncode(rows), 200, headers: headers, request: request);
  }
}

/// Loads Roboto, the font Android draws this app in, so text in a test takes
/// the width it takes on a phone.
///
/// The test default draws every character as a full square, roughly twice as
/// wide as real text, which reports overflows no phone would show. The theme
/// asks for 'DM Sans', which the app does not bundle, so Android falls back to
/// Roboto; it is registered under both names. The files come from the Flutter
/// SDK's own cache.
Future<void> loadPhoneFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  const weights = ['regular', 'medium', 'bold', 'light', 'black', 'thin', 'italic', 'bolditalic'];
  for (final family in ['Roboto', 'DM Sans']) {
    final loader = FontLoader(family);
    for (final w in weights) {
      final file = File('${dir.path}/roboto-$w.ttf');
      if (file.existsSync()) {
        loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
      }
    }
    await loader.load();
  }
  final icons = File('${dir.path}/materialicons-regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(icons.readAsBytes().then((b) => ByteData.view(b.buffer))))
        .load();
  }
}

/// A socket failure of the kind the offline switch simulates, for tests that
/// want to name it.
const offlineError = SocketException('Failed host lookup');
