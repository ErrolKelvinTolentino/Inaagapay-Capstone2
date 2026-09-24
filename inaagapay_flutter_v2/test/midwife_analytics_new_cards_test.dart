import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/midwife_analytics.dart';
import 'package:inaagapay_flutter_v2/services/midwife_analytics_service.dart';
import 'package:inaagapay_flutter_v2/services/pregnancy_stage.dart';

final _now = DateTime(2026, 9, 24);

String _iso(DateTime d) => d.toIso8601String().split('T').first;

Map<String, dynamic> _pregnancy({int? weeks, int? eddInDays}) => {
      'pregnancy_id': 1,
      'mother_id': 1,
      'status': 'ongoing',
      'last_menstrual_period':
          weeks == null ? null : _iso(_now.subtract(Duration(days: weeks * 7))),
      'expected_date_of_delivery':
          eddInDays == null ? null : _iso(_now.add(Duration(days: eddInDays))),
    };

int _band(AnalyticsMetric m, String label) =>
    m.bands.firstWhere((b) => b.label == label).count;

void main() {
  group('pregnancy stage', () {
    test('trimesters follow completed weeks', () {
      expect(PregnancyStage.trimesterOf(13 * 7 + 6), Trimester.first);
      expect(PregnancyStage.trimesterOf(14 * 7), Trimester.second);
      expect(PregnancyStage.trimesterOf(27 * 7 + 6), Trimester.second);
      expect(PregnancyStage.trimesterOf(28 * 7), Trimester.third);
    });

    test('a pregnancy dated only by its due date is still placed', () {
      final days = PregnancyStage.gestationalDays(
        edd: _now.add(const Duration(days: 140)),
        now: _now,
      );
      expect(days, 140);
      expect(PregnancyStage.trimesterOf(days!), Trimester.second);
    });

    test('the card sorts, flags past-due and counts the undated', () {
      final card = MidwifeAnalyticsService.pregnancyStageCard([
        _pregnancy(weeks: 8),
        _pregnancy(weeks: 20),
        _pregnancy(weeks: 37),
        _pregnancy(weeks: 43),
        _pregnancy(),
      ], _now);

      expect(_band(card, 'First trimester'), 1);
      expect(_band(card, 'Second trimester'), 1);
      expect(_band(card, 'Third trimester'), 1);
      expect(_band(card, 'Past 40 weeks'), 1);
      expect(_band(card, 'No dates recorded'), 1);
      // Past the due date outranks everything else.
      expect(card.insight!.tone, AnalyticsTone.alert);
      expect(card.headline, '1');
    });

    test('due within four weeks is the next thing said', () {
      final card = MidwifeAnalyticsService.pregnancyStageCard(
          [_pregnancy(weeks: 37), _pregnancy(weeks: 20)], _now);
      expect(card.headlineCaption, contains('due within 4 weeks'));
      expect(card.insight!.tone, AnalyticsTone.watch);
    });
  });

  group('vaccination status', () {
    // BCG at birth, then a 1.5-month dose.
    final vaccines = [
      {
        'vaccine_id': 1,
        'vaccine_name': 'BCG',
        'dose_number': 1,
        'recommended_age_months': 0,
      },
      {
        'vaccine_id': 2,
        'vaccine_name': 'Pentavalent',
        'dose_number': 1,
        'recommended_age_months': 1.5,
      },
    ];

    Map<String, dynamic> child(int id, DateTime born) => {
          'child_id': id,
          'first_name': 'Child',
          'last_name': '$id',
          'birth_details': {'birthdate': _iso(born)},
        };

    test('splits zero-dose, partial and fully vaccinated for age', () {
      final sixMonthsOld = _now.subtract(const Duration(days: 183));
      final card = MidwifeAnalyticsService.vaccinationStatusCard(
        children: [
          child(1, sixMonthsOld), // nothing given
          child(2, sixMonthsOld), // BCG only
          child(3, sixMonthsOld), // both
        ],
        vaccines: vaccines,
        records: [
          {'child_id': 2, 'vaccine_id': 1, 'vaccination_date': _iso(sixMonthsOld)},
          {'child_id': 3, 'vaccine_id': 1, 'vaccination_date': _iso(sixMonthsOld)},
          {
            'child_id': 3,
            'vaccine_id': 2,
            'vaccination_date': _iso(sixMonthsOld.add(const Duration(days: 46))),
          },
        ],
        now: _now,
      );

      expect(_band(card, 'Unvaccinated (zero-dose)'), 1);
      expect(_band(card, 'Partially vaccinated'), 1);
      expect(_band(card, 'Fully vaccinated for age'), 1);
      expect(card.insight!.tone, AnalyticsTone.alert);
    });
  });

  group('vaccination drives', () {
    test('a database without the view says so instead of "no drives"', () {
      final card = MidwifeAnalyticsService.vaccinationDrivesCard(null, _now);
      expect(card.hasData, isFalse);
      expect(card.emptyMessage, contains('20260912'));
    });

    test('turnout is counted against invitations', () {
      final card = MidwifeAnalyticsService.vaccinationDrivesCard([
        {
          'schedule_date': _iso(_now.add(const Duration(days: 5))),
          'vaccine_name': 'MR',
          'drive_status': 'upcoming',
          'invited_count': 12,
        },
        {
          'schedule_date': _iso(_now.subtract(const Duration(days: 10))),
          'vaccine_name': 'Td',
          'drive_status': 'completed',
          'invited_count': 10,
          'invited_attended': 4,
          'attended_count': 6,
          'walk_in_count': 2,
          'no_show_count': 6,
          'doses_administered': 6,
        },
      ], _now);

      expect(card.headline, '4');
      expect(card.headlineCaption, contains('of 10 invited'));
      expect(card.bands.single.fraction, closeTo(0.4, 0.001));
      expect(card.bands.single.severity, AnalyticsSeverity.alert);
      expect(card.insight!.text, contains('6 invited people did not come'));
      expect(card.insight!.evidence, contains('Next: MR'));
    });
  });
}
