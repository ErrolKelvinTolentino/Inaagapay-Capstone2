import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/mother/mother_dashboard.dart';
import 'package:inaagapay_flutter_v2/services/language_service.dart';
import 'package:inaagapay_flutter_v2/widgets/hero_card.dart';
import 'support/fake_backend.dart';

const motherStorage = {'user_id': '48', 'auth_token': 't', 'mother_id': '28', 'user_role': 'mother'};

void main() {
  setUpAll(() async {
    await FakeBackend.init(storage: motherStorage);
    await loadPhoneFonts();
  });
  tearDown(() => LanguageService.selectedLanguage.value = AppLanguage.english);

  testWidgets('shows due-day and overdue states with actual weeks and no weekly tip', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String iso(DateTime date) => date.toIso8601String().split('T').first;

    for (final pastDueDays in [-1, 0, 1, 7, 14, 28]) {
      FakeBackend.reset(storage: motherStorage);
      final edd = today.subtract(Duration(days: pastDueDays));
      FakeBackend.tables
        ..['mothers'] = [{'mother_id': 28, 'account_id': 48, 'assigned_bhc_id': 2, 'height': 158}]
        ..['accounts'] = [{'account_id': 48, 'first_name': 'Mother', 'last_name': 'Example'}]
        ..['pregnancies'] = [{
          'pregnancy_id': 900, 'mother_id': 28, 'status': 'ongoing',
          // Exercise the EDD-only fallback for the 42-week case too.
          'last_menstrual_period': pastDueDays == 14 ? null : iso(edd.subtract(const Duration(days: 280))),
          'expected_date_of_delivery': iso(edd), 'pre_pregnancy_weight': 52.0,
          'fetal_count': 1, 'pregnancy_risk_level': 'low',
        }];
      await tester.pumpWidget(const MaterialApp(home: MotherDashboard()));
      for (var i = 0; i < 15 && find.byType(HeroCard).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(HeroCard), findsOneWidget);
      expect(tester.widget<HeroCard>(find.byType(HeroCard)).week, (280 + pastDueDays) ~/ 7);
      if (pastDueDays < 0) {
        expect(find.text('1 day to go!'), findsOneWidget);
      } else if (pastDueDays == 0) {
        expect(find.text('Due today'), findsOneWidget);
      } else {
        expect(find.text('$pastDueDays ${pastDueDays == 1 ? 'day' : 'days'} past due date'), findsOneWidget);
        expect(find.textContaining('Contact your midwife'), findsOneWidget);
      }
      expect(find.text('TIP OF THE WEEK'), findsNothing);
      expect(find.text('Any day now!'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(FakeBackend.requests.where((r) => r.startsWith('PATCH /rest/v1/pregnancies')), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
