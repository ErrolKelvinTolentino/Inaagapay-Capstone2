// Executes Add Mother test cases from InaAgapay Test Case.xlsx on the real
// wizard, against the fake backend.
//
//   TC-MW-ADDM-013  LMP more than 42 weeks ago
//   TC-MW-ADDM-020  scanning a form with no connection

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/midwife_add_mother_screen.dart';
import 'package:inaagapay_flutter_v2/widgets/app_input_field.dart';
import 'package:intl/intl.dart';

import '../support/fake_backend.dart';

const _midwife = {'user_id': '41', 'auth_token': 't', 'user_role': 'midwife'};

/// A 1 x 1 PNG, standing in for the photo of a paper form.
final _photo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// The text box inside the app's labelled input with this hint.
Finder field(String hint) => find.descendant(
      of: find.byWidgetPredicate((w) => w is AppInputField && w.hintText == hint),
      matching: find.byType(TextField),
    );

/// Every connection attempt fails, as on a phone with no signal.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) =>
        Future.error(const SocketException('Failed host lookup: api.groq.com'));
    return client;
  }
}

void main() {
  late String photoPath;

  setUpAll(() async {
    await FakeBackend.init(storage: _midwife);
    await loadPhoneFonts();
    final dir = await Directory.systemTemp.createTemp('inaagapay_scan');
    photoPath = '${dir.path}${Platform.pathSeparator}form.png';
    await File(photoPath).writeAsBytes(_photo);
  });

  void seed() {
    FakeBackend.tables
      ..['midwives'] = [
        {'midwife_id': 5, 'account_id': 41, 'assigned_bhc_id': 2},
      ]
      ..['health_facilities'] = [
        {'facility_id': 2, 'name': 'Tarcan BHC', 'barangay': 'Tarcan',
         'city_municipality': 'Baliuag', 'province': 'Bulacan'},
      ]
      ..['accounts'] = [];
  }

  Future<void> openWizard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: MidwifeAddMotherScreen()));
    await tester.pumpAndSettle();
  }

  /// Opens the date field's calendar and types the date instead of paging
  /// back month by month -- the calendar's own pencil button.
  Future<void> pickDate(WidgetTester tester, String hint, DateTime date) async {
    await tester.ensureVisible(field(hint));
    await tester.tap(field(hint));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
        DateFormat('MM/dd/yyyy').format(date));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  testWidgets('TC-MW-ADDM-013 an LMP 301 days ago asks to verify the date',
      (tester) async {
    FakeBackend.reset(storage: _midwife);
    seed();
    await openWizard(tester);

    // Personal details.
    await tester.enterText(field('First Name'), 'Juana');
    await tester.enterText(field('Last Name'), 'Dela Cruz');
    await tester.enterText(field('Contact Number'), '09171234599');
    await pickDate(tester, 'Birthdate', DateTime(1998, 4, 12));
    await tester.pump(const Duration(seconds: 2)); // the number's availability check
    await tester.pumpAndSettle();
    await next(tester);

    // Address, same as the health center.
    await tester.enterText(field('House No.'), '12');
    await tester.enterText(field('Street'), 'Mabini');
    await next(tester);

    // Emergency contacts are optional.
    await next(tester);

    // Pregnancy dating: LMP 43 weeks back.
    final lmp = DateTime.now().subtract(const Duration(days: 301));
    await pickDate(tester, 'Last Menstrual Period', lmp);

    expect(find.text('LMP is more than 42 weeks ago. Please verify the date.'),
        findsOneWidget);
  });

  testWidgets('TC-MW-ADDM-020 scanning offline gives a readable error, and typing still works',
      (tester) async {
    FakeBackend.reset(storage: _midwife);
    seed();
    dotenv.testLoad(
        fileInput: 'SUPABASE_URL=${FakeBackend.url}\nSUPABASE_ANON_KEY=test-key\n'
            'GROQ_API_KEY=test-groq-key');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async => photoPath,
    );
    final previous = HttpOverrides.current;
    HttpOverrides.global = _NoNetwork();
    addTearDown(() => HttpOverrides.global = previous);

    await openWizard(tester);
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gallery'));

    // Real time for the file read and the refused connections.
    for (var i = 0; i < 40 && find.text('Scan Failed').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('Scan Failed'), findsWidgets);
    expect(find.textContaining('Network error. Please check your internet connection.'),
        findsOneWidget);
    expect(find.textContaining('You can still fill in the form by hand.'), findsOneWidget);
    for (final raw in ['SocketException', 'ClientException', 'Groq', 'api.groq.com']) {
      expect(find.textContaining(raw), findsNothing, reason: 'no technical text: $raw');
    }

    // Close the error and type the form by hand.
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(field('First Name'), 'Juana');
    expect(find.text('Juana'), findsOneWidget);
  });
}
