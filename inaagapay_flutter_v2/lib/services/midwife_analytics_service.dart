// lib/services/midwife_analytics_service.dart
//
// Everything the dashboard's analytics section knows, computed in one place.
//
// Three rules this file is written to keep:
//
//   1. Counts over percentages. One health centre carries a few dozen mothers,
//      where a single person moves a percentage by several points. Percentages
//      appear only once a denominator reaches ten (see
//      `AnalyticsMetric.coveragePercent`); below that the card says "3 of 8".
//
//   2. Services are measured against who was eligible, not against how many
//      were handed out. "142 iron tablets dispensed" is a stockroom figure that
//      only ever grows. "31 of 38 pregnant mothers had iron this month" is the
//      one a midwife can act on, and it is also the shape DOH reporting wants.
//
//   3. Every "why" sentence is a rule over recorded rows, never a guess. The
//      diagnostic layer here compares a service count against the caseload that
//      could have received it, reads risk factors the assessment already
//      stored, and says which it is. Where the data cannot support a reason,
//      the card says what it sees and stops.
//
// A missing table degrades to an empty card, never to a broken dashboard —
// `_rows` swallows the error and the metric renders its empty state, so a
// centre that has not started recording growth still gets the rest.

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/midwife_analytics.dart';
import 'immunization_schedule.dart';
import 'supabase_service.dart';

class MidwifeAnalyticsService {
  const MidwifeAnalyticsService._();

  static const double _daysPerMonth = 30.44;

  /// How long a growth measurement stays current. Matches the quarterly rhythm
  /// of barangay growth monitoring.
  static const int _growthStaleDays = 90;

  /// The supplementation window. A mother given iron five weeks ago has run
  /// out; she is not "covered".
  static const int _supplementWindowDays = 30;

  static Future<MidwifeAnalytics> load({required int bhcId}) async {
    final now = DateTime.now();

    final mothers = await _rows(
      SupabaseService.client
          .from('mothers')
          .select(
            'mother_id, birthdate, gravida, para, '
            'accounts!inner (first_name, last_name)',
          )
          .eq('assigned_bhc_id', bhcId)
          .eq('status', 'active'),
      'mothers',
    );

    if (mothers.isEmpty) return const MidwifeAnalytics.empty();

    final motherIds = mothers
        .map((row) => _int(row['mother_id']))
        .whereType<int>()
        .toList();

    final stage1 = await Future.wait([
      _rows(
        SupabaseService.client
            .from('pregnancies')
            .select(
              'pregnancy_id, mother_id, status, last_menstrual_period, '
              'expected_date_of_delivery, pregnancy_risk_level, ended_at, '
              'created_at',
            )
            .inFilter('mother_id', motherIds),
        'pregnancies',
      ),
      _rows(
        SupabaseService.client
            .from('children')
            .select(
              'child_id, mother_id, first_name, last_name, sex, '
              'birth_details (birthdate, birth_weight)',
            )
            .inFilter('mother_id', motherIds),
        'children',
      ),
      _rows(
        SupabaseService.client
            .from('given_medications')
            .select('mother_id, given_medication_name, quantity, date_given')
            .inFilter('mother_id', motherIds)
            .gte(
              'date_given',
              _isoDate(now.subtract(const Duration(days: 120))),
            ),
        'given medications',
      ),
      _rows(
        SupabaseService.client
            .from('vaccines')
            .select('*')
            .eq('target_recipients', 'child')
            .order('recommended_age_months'),
        'vaccine catalogue',
      ),
    ]);

    final pregnancies = stage1[0];
    final children = stage1[1];
    final givenMedications = stage1[2];
    final vaccines = stage1[3];

    final pregnancyIds = pregnancies
        .map((row) => _int(row['pregnancy_id']))
        .whereType<int>()
        .toList();
    final childIds =
        children.map((row) => _int(row['child_id'])).whereType<int>().toList();

    final stage2 = await Future.wait([
      pregnancyIds.isEmpty
          ? _none()
          : _rows(
              SupabaseService.client
                  .from('clinical_encounters')
                  .select(
                    'encounter_datetime, pregnancy_id, '
                    'checkup:prenatal_checkups (td_vaccine_dose)',
                  )
                  .inFilter('pregnancy_id', pregnancyIds)
                  .eq('encounter_type', 'checkup'),
              'checkups',
            ),
      pregnancyIds.isEmpty
          ? _none()
          : _rows(
              SupabaseService.client
                  .from('pregnancy_risk_assessments')
                  .select(
                    'pregnancy_id, risk_level, created_at, '
                    'pregnancy_risk_factors (factor, risk_influence)',
                  )
                  .inFilter('pregnancy_id', pregnancyIds),
              'risk assessments',
            ),
      pregnancyIds.isEmpty
          ? _none()
          : _rows(
              SupabaseService.client
                  .from('weight_gain_evaluations')
                  .select('pregnancy_id, status, created_at')
                  .inFilter('pregnancy_id', pregnancyIds),
              'weight gain evaluations',
            ),
      childIds.isEmpty
          ? _none()
          : _rows(
              SupabaseService.client
                  .from('child_growth_records')
                  .select(
                    'child_id, measurement_date, weight_for_age_zscore, '
                    'height_for_age_zscore, bmi_for_age_zscore',
                  )
                  .inFilter('child_id', childIds),
              'growth records',
            ),
      childIds.isEmpty
          ? _none()
          : _rows(
              SupabaseService.client
                  .from('immunization_records')
                  .select('child_id, vaccine_id, vaccination_date, dose_number')
                  .inFilter('child_id', childIds),
              'immunization records',
            ),
      pregnancyIds.isEmpty
          ? _none()
          : _rows(
              SupabaseService.client
                  .from('prenatal_checkups')
                  .select('pregnancy_id, next_schedule')
                  .inFilter('pregnancy_id', pregnancyIds)
                  .not('next_schedule', 'is', null)
                  .gte('next_schedule', _isoDate(_dayStart(now))),
              'upcoming checkups',
            ),
      _rows(
        SupabaseService.client
            .from('inventory_items')
            .select('item_id, name, item_type, unit_of_measure, '
                'minimum_stock_threshold'),
        'inventory items',
      ),
      _rows(
        SupabaseService.client
            .from('inventory_batches')
            .select('batch_id, item_id, quantity_remaining, expiration_date, '
                'batch_number, status')
            .eq('facility_id', bhcId)
            .eq('status', 'active'),
        'inventory batches',
      ),
    ]);

    final checkups = stage2[0];
    final riskAssessments = stage2[1];
    final weightGain = stage2[2];
    final growthRecords = stage2[3];
    final immunizations = stage2[4];
    final upcomingCheckups = stage2[5];
    final inventoryItems = stage2[6];
    final inventoryBatches = stage2[7];

    // ===== SHARED DERIVATIONS =====
    final mothersById = {
      for (final row in mothers) _int(row['mother_id']) ?? -1: row,
    };
    final ongoing = pregnancies
        .where((row) => row['status']?.toString() == 'ongoing')
        .toList();

    final stock = _resolveStock(inventoryItems, inventoryBatches);
    final childDoses = _childDoseStatuses(children, vaccines, immunizations, now);

    final mothersSection = AnalyticsSection(
      title: 'Mothers',
      metrics: [
        _ageDistribution(mothers, ongoing, now),
        _riskLevels(ongoing),
        _riskDrivers(ongoing, riskAssessments),
        _tdProtection(ongoing, pregnancies, checkups, now),
        _supplementation(ongoing, givenMedications, now),
        _weightGain(ongoing, weightGain),
      ],
    );

    final childrenSection = AnalyticsSection(
      title: 'Children',
      metrics: [
        _childAgeBands(children, now),
        _growthFindings(children, growthRecords, now),
        _immunizationCoverage(childDoses, immunizations, now),
      ],
    );

    final suppliesSection = AnalyticsSection(
      title: 'Supplies',
      metrics: [
        _stockOnHand(stock),
        _expiringSoon(stock),
        _upcomingDemand(childDoses, stock),
      ],
    );

    return MidwifeAnalytics(
      mothers: mothersSection,
      children: childrenSection,
      supplies: suppliesSection,
      suppliesAreSample: stock.isSample,
      priorities: _priorities(
        ongoing: ongoing,
        mothersById: mothersById,
        upcomingCheckups: upcomingCheckups,
        riskAssessments: riskAssessments,
        childDoses: childDoses,
        stock: stock,
        now: now,
      ),
    );
  }

  // ==========================================================================
  // MOTHERS
  // ==========================================================================

  /// Age is not a demographic footnote here — under 20 and 35-and-over are both
  /// recognised obstetric risk factors, so the two tails of this chart are the
  /// point of drawing it. They are the only bands given a warning colour.
  static AnalyticsMetric _ageDistribution(
    List<Map<String, dynamic>> mothers,
    List<Map<String, dynamic>> ongoing,
    DateTime now,
  ) {
    const title = 'Age of registered mothers';

    final ages = <int, int>{}; // mother_id -> age
    int missing = 0;
    for (final row in mothers) {
      final birthdate = _date(row['birthdate']);
      final id = _int(row['mother_id']);
      if (birthdate == null || id == null) {
        missing++;
        continue;
      }
      ages[id] = _yearsBetween(birthdate, now);
    }

    if (ages.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        message: 'No birthdates recorded yet, so ages cannot be shown.',
      );
    }

    int under20 = 0, age20 = 0, age25 = 0, age30 = 0, over35 = 0;
    for (final age in ages.values) {
      if (age < 20) {
        under20++;
      } else if (age < 25) {
        age20++;
      } else if (age < 30) {
        age25++;
      } else if (age < 35) {
        age30++;
      } else {
        over35++;
      }
    }

    final bands = [
      AnalyticsBand(
        label: 'Under 20',
        shortLabel: '<20',
        count: under20,
        severity: AnalyticsSeverity.watch,
      ),
      AnalyticsBand(label: '20–24', count: age20),
      AnalyticsBand(label: '25–29', count: age25),
      AnalyticsBand(label: '30–34', count: age30),
      AnalyticsBand(
        label: '35 and over',
        shortLabel: '35+',
        count: over35,
        severity: AnalyticsSeverity.watch,
      ),
    ];

    // The diagnostic link: how much of the flagged caseload sits in the two
    // risk-age bands. This is a count of recorded facts, not an attribution of
    // cause — the wording says "belong to", not "because of".
    final highRisk = ongoing
        .where((row) => row['pregnancy_risk_level']?.toString() == 'high')
        .toList();
    final highRiskInTails = highRisk.where((row) {
      final age = ages[_int(row['mother_id']) ?? -1];
      return age != null && (age < 20 || age >= 35);
    }).length;

    final tails = under20 + over35;

    AnalyticsInsight insight;
    if (highRisk.isNotEmpty && highRiskInTails > 0) {
      insight = AnalyticsInsight(
        '$highRiskInTails of the ${highRisk.length} high-risk '
        '${_plural(highRisk.length, 'pregnancy', 'pregnancies')} '
        '${highRiskInTails == 1 ? 'belongs' : 'belong'} to a mother under 20 or '
        '35 and over.',
        tone: AnalyticsTone.watch,
        evidence: 'Both age bands carry added obstetric risk on their own.',
      );
    } else if (tails > 0) {
      insight = AnalyticsInsight(
        '$tails ${_plural(tails, 'mother', 'mothers')} '
        '${tails == 1 ? 'sits' : 'sit'} in a higher-risk age band — '
        '$under20 under 20, $over35 aged 35 and over.',
        tone: AnalyticsTone.watch,
      );
    } else {
      insight = const AnalyticsInsight(
        'Every registered mother is between 20 and 34, the band with the '
        'lowest obstetric risk.',
        tone: AnalyticsTone.good,
      );
    }

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.bars,
      headline: '${ages.length}',
      headlineCaption: 'mothers with a recorded age',
      bands: bands,
      insight: insight,
      footnote: missing > 0
          ? '$missing ${_plural(missing, 'mother has', 'mothers have')} no '
              'birthdate on file and ${missing == 1 ? 'is' : 'are'} not counted here.'
          : null,
      prescription: tails > 0
          ? const AnalyticsPrescription(
              label: 'Open mother list',
              action: AnalyticsAction.viewMothers,
            )
          : null,
    );
  }

  static AnalyticsMetric _riskLevels(List<Map<String, dynamic>> ongoing) {
    const title = 'Pregnancy risk levels';

    if (ongoing.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.donut,
        message: 'No ongoing pregnancies are recorded at this centre yet.',
      );
    }

    int low = 0, medium = 0, high = 0, unassessed = 0;
    for (final row in ongoing) {
      switch (row['pregnancy_risk_level']?.toString()) {
        case 'low':
          low++;
          break;
        case 'medium':
          medium++;
          break;
        case 'high':
          high++;
          break;
        default:
          unassessed++;
      }
    }

    final assessed = low + medium + high;
    final pregnancyWord =
        _plural(ongoing.length, 'pregnancy', 'pregnancies');

    // Headline and insight follow one order of urgency: a high-risk pregnancy
    // first, then an unassessed one — unknown outranks medium, because an
    // unassessed pregnancy could be either — then medium, then the all-clear.
    String headline;
    String caption;
    AnalyticsInsight insight;

    if (high > 0) {
      headline = '$high';
      caption = 'high risk of ${ongoing.length} ongoing $pregnancyWord';
      insight = AnalyticsInsight(
        '$high of ${ongoing.length} ongoing '
        '${_plural(ongoing.length, 'pregnancy is', 'pregnancies are')} high '
        'risk. See what is driving them in the next card.',
        tone: AnalyticsTone.alert,
      );
    } else if (unassessed > 0) {
      headline = '$unassessed';
      caption = 'of ${ongoing.length} ongoing $pregnancyWord not yet assessed';
      insight = AnalyticsInsight(
        '$unassessed of ${ongoing.length} ongoing '
        '${_plural(ongoing.length, 'pregnancy has', 'pregnancies have')} no '
        'risk assessment yet, so this mix describes only the $assessed that do.',
        tone: AnalyticsTone.watch,
        evidence: 'An unassessed pregnancy is not a low-risk one.',
      );
    } else if (medium > 0) {
      headline = '$medium';
      caption = 'at medium risk of ${ongoing.length} ongoing $pregnancyWord';
      insight = AnalyticsInsight(
        'None is high risk. $medium '
        '${_plural(medium, 'is', 'are')} medium risk and worth watching at the '
        'next visit.',
        tone: AnalyticsTone.watch,
      );
    } else {
      headline = '${ongoing.length}';
      caption = 'ongoing $pregnancyWord, all assessed low risk';
      insight = const AnalyticsInsight(
        'Every ongoing pregnancy has been assessed, and none is above low risk.',
        tone: AnalyticsTone.good,
      );
    }

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.donut,
      headline: headline,
      headlineCaption: caption,
      bands: [
        AnalyticsBand(
          label: 'Low',
          count: low,
          severity: AnalyticsSeverity.good,
        ),
        AnalyticsBand(
          label: 'Medium',
          count: medium,
          severity: AnalyticsSeverity.watch,
        ),
        AnalyticsBand(
          label: 'High',
          count: high,
          severity: AnalyticsSeverity.alert,
        ),
        AnalyticsBand(
          label: 'Not assessed',
          count: unassessed,
          severity: AnalyticsSeverity.unknown,
        ),
      ],
      insight: insight,
      prescription: const AnalyticsPrescription(
        label: 'Open mother list',
        action: AnalyticsAction.viewMothers,
      ),
    );
  }

  /// The diagnostic card the database was already carrying: every risk
  /// assessment stores the factors it was based on, and nothing had ever shown
  /// them side by side. This is why the risk mix looks the way it does.
  static AnalyticsMetric _riskDrivers(
    List<Map<String, dynamic>> ongoing,
    List<Map<String, dynamic>> assessments,
  ) {
    const title = 'What is driving the risk';

    final ongoingIds = ongoing
        .map((row) => _int(row['pregnancy_id']))
        .whereType<int>()
        .toSet();

    // One assessment per pregnancy — the newest. Older assessments describe a
    // pregnancy that has since been reassessed, and counting both would double
    // a factor that was only ever recorded once.
    final latestByPregnancy = <int, Map<String, dynamic>>{};
    for (final row in assessments) {
      final id = _int(row['pregnancy_id']);
      if (id == null || !ongoingIds.contains(id)) continue;
      final existing = latestByPregnancy[id];
      if (existing == null ||
          (_date(row['created_at']) ?? DateTime(1900))
              .isAfter(_date(existing['created_at']) ?? DateTime(1900))) {
        latestByPregnancy[id] = row;
      }
    }

    final counts = <String, int>{};

    // The denominator has to be the same population the numerators come from.
    // Counting factors across every assessment while comparing them against
    // only the medium/high subset produced "appears in 5 of the 4 flagged
    // pregnancies" — a numerator larger than its denominator.
    int withFactors = 0;

    for (final assessment in latestByPregnancy.values) {
      final factors = assessment['pregnancy_risk_factors'];
      if (factors is! List) continue;

      // Grouped first, then de-duplicated: three spellings of a young maternal
      // age are one finding about one mother, and must count once.
      final seen = <String>{};
      for (final entry in factors) {
        if (entry is! Map) continue;
        final label = _canonicalFactor(entry['factor']?.toString() ?? '');
        if (label.isEmpty || !seen.add(label)) continue;
        counts[label] = (counts[label] ?? 0) + 1;
      }
      if (seen.isNotEmpty) withFactors++;
    }

    if (counts.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.rankedBars,
        message:
            'No risk factors recorded yet. They appear here as soon as a '
            'checkup produces a risk assessment.',
      );
    }

    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(5).toList();

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.rankedBars,
      headline: '${top.first.value}',
      headlineCaption: 'of $withFactors assessed '
          '${_plural(withFactors, 'pregnancy shows', 'pregnancies show')} '
          '${_lowerFirst(top.first.key)}, the most common factor',
      bands: [
        for (final entry in top)
          AnalyticsBand(label: entry.key, count: entry.value),
      ],
      insight: AnalyticsInsight(
        '${top.first.key} appears in ${top.first.value} of the $withFactors '
        '${_plural(withFactors, 'pregnancy', 'pregnancies')} with recorded '
        'factors.',
        tone: AnalyticsTone.watch,
        evidence: 'Read from the factors saved with each risk assessment.',
      ),
      footnote: 'Counted once per pregnancy, from its most recent assessment. '
          'Wordings that describe the same finding are grouped — every way of '
          'recording a young maternal age counts as one factor.',
      prescription: const AnalyticsPrescription(
        label: 'Review flagged mothers',
        action: AnalyticsAction.viewMothers,
      ),
    );
  }

  /// Tetanus-diphtheria protection, and the card that answers "why were fewer
  /// given this month".
  ///
  /// Two numbers are needed for that question and the dashboard previously had
  /// neither: doses in each month, and how many mothers were pregnant in each
  /// month. A fall in the first that matches a fall in the second is caseload.
  /// A fall in the first while the second holds is missed service. The card
  /// states which, and shows both numbers so the midwife can check.
  static AnalyticsMetric _tdProtection(
    List<Map<String, dynamic>> ongoing,
    List<Map<String, dynamic>> allPregnancies,
    List<Map<String, dynamic>> checkups,
    DateTime now,
  ) {
    const title = 'Tetanus (TD) protection';

    if (ongoing.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.coverage,
        message: 'No ongoing pregnancies, so TD coverage has nothing to cover.',
      );
    }

    final highestDose = <int, int>{};
    int dosesThisMonth = 0;
    int dosesLastMonth = 0;

    final thisMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);

    for (final row in checkups) {
      final checkup = _firstMap(row['checkup']);
      final dose = _doseNumber(checkup?['td_vaccine_dose']?.toString());
      if (dose == null) continue;

      final pregnancyId = _int(row['pregnancy_id']);
      if (pregnancyId != null) {
        final current = highestDose[pregnancyId] ?? 0;
        if (dose > current) highestDose[pregnancyId] = dose;
      }

      final when = _date(row['encounter_datetime']);
      if (when == null) continue;
      if (!when.isBefore(thisMonthStart)) {
        dosesThisMonth++;
      } else if (!when.isBefore(lastMonthStart)) {
        dosesLastMonth++;
      }
    }

    final protected = ongoing
        .where((row) => (highestDose[_int(row['pregnancy_id']) ?? -1] ?? 0) >= 2)
        .length;
    final outstanding = ongoing.length - protected;

    final caseloadThisMonth = allPregnancies
        .where((row) => _wasPregnantDuring(row, thisMonthStart, now))
        .length;
    final caseloadLastMonth = allPregnancies
        .where((row) => _wasPregnantDuring(
              row,
              lastMonthStart,
              thisMonthStart.subtract(const Duration(days: 1)),
            ))
        .length;

    AnalyticsInsight insight;
    if (dosesThisMonth < dosesLastMonth) {
      final caseloadFell = caseloadThisMonth < caseloadLastMonth;
      insight = AnalyticsInsight(
        caseloadFell
            ? 'Doses fell from $dosesLastMonth to $dosesThisMonth, and so did '
                'the number of mothers who were pregnant this month '
                '($caseloadLastMonth to $caseloadThisMonth). This tracks '
                'caseload, not missed service.'
            : 'Doses fell from $dosesLastMonth to $dosesThisMonth while the '
                'pregnant caseload held near $caseloadThisMonth. That points to '
                'missed opportunities rather than fewer mothers.',
        tone: caseloadFell ? AnalyticsTone.neutral : AnalyticsTone.watch,
        evidence: 'Counted from TD doses written on prenatal checkups.',
      );
    } else if (dosesThisMonth > dosesLastMonth) {
      insight = AnalyticsInsight(
        '$dosesThisMonth doses so far this month, up from $dosesLastMonth, '
        'with $caseloadThisMonth mothers pregnant during the month.',
        tone: AnalyticsTone.good,
      );
    } else {
      insight = AnalyticsInsight(
        'Dosing is steady at $dosesThisMonth this month, with '
        '$caseloadThisMonth mothers pregnant during the month.',
        tone: AnalyticsTone.neutral,
      );
    }

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.coverage,
      periodLabel: 'TD2 or more',
      headline: '$protected',
      headlineCaption:
          'of ${ongoing.length} pregnant ${_plural(ongoing.length, 'mother', 'mothers')} '
          'have had TD2 or more',
      covered: protected,
      eligible: ongoing.length,
      comparison: AnalyticsComparison(
        previousLabel: DateFormat('MMMM').format(lastMonthStart),
        previousValue: dosesLastMonth,
        currentLabel: DateFormat('MMMM').format(thisMonthStart),
        currentValue: dosesThisMonth,
        unit: 'doses',
        previousEligible: caseloadLastMonth,
        currentEligible: caseloadThisMonth,
      ),
      insight: insight,
      prescription: outstanding > 0
          ? AnalyticsPrescription(
              label:
                  'Follow up $outstanding ${_plural(outstanding, 'mother', 'mothers')} '
                  'without TD2',
              action: AnalyticsAction.viewMothers,
            )
          : null,
    );
  }

  static AnalyticsMetric _supplementation(
    List<Map<String, dynamic>> ongoing,
    List<Map<String, dynamic>> given,
    DateTime now,
  ) {
    const title = 'Iron and calcium supplements';

    if (ongoing.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.coverage,
        message: 'No ongoing pregnancies to supplement.',
      );
    }

    final pregnantMotherIds = ongoing
        .map((row) => _int(row['mother_id']))
        .whereType<int>()
        .toSet();

    final windowStart = now.subtract(const Duration(days: _supplementWindowDays));
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);

    final ironRecently = <int>{};
    final calciumRecently = <int>{};
    int ironThisMonth = 0;
    int ironLastMonth = 0;

    for (final row in given) {
      final motherId = _int(row['mother_id']);
      final when = _date(row['date_given']);
      final name = row['given_medication_name']?.toString().toLowerCase() ?? '';
      if (motherId == null || when == null) continue;

      final isIron = name.contains('ferrous') || name.contains('iron');
      final isCalcium = name.contains('calcium');

      if (isIron) {
        if (!when.isBefore(thisMonthStart)) {
          ironThisMonth++;
        } else if (!when.isBefore(lastMonthStart)) {
          ironLastMonth++;
        }
      }

      if (!when.isBefore(windowStart) && pregnantMotherIds.contains(motherId)) {
        if (isIron) ironRecently.add(motherId);
        if (isCalcium) calciumRecently.add(motherId);
      }
    }

    final covered = ironRecently.length;
    final lapsed = pregnantMotherIds.length - covered;

    final insight = lapsed > 0
        ? AnalyticsInsight(
            '$lapsed pregnant ${_plural(lapsed, 'mother has', 'mothers have')} '
            'no iron recorded in the last $_supplementWindowDays days — long '
            'enough to have run out between visits.',
            tone: lapsed > covered ? AnalyticsTone.alert : AnalyticsTone.watch,
            evidence: 'Anaemia in pregnancy builds quietly once supply stops.',
          )
        : const AnalyticsInsight(
            'Every pregnant mother has iron dispensed within the last month.',
            tone: AnalyticsTone.good,
          );

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.coverage,
      periodLabel: 'Last 30 days',
      headline: '$covered',
      headlineCaption:
          'of ${pregnantMotherIds.length} pregnant '
          '${_plural(pregnantMotherIds.length, 'mother', 'mothers')} received iron',
      covered: covered,
      eligible: pregnantMotherIds.length,
      comparison: AnalyticsComparison(
        previousLabel: DateFormat('MMMM').format(lastMonthStart),
        previousValue: ironLastMonth,
        currentLabel: DateFormat('MMMM').format(thisMonthStart),
        currentValue: ironThisMonth,
        unit: 'hand-outs',
      ),
      insight: insight,
      footnote:
          '${calciumRecently.length} of these mothers also received calcium in '
          'the same window.',
      prescription: lapsed > 0
          ? AnalyticsPrescription(
              label: 'Dispense at the next visit',
              action: AnalyticsAction.viewMothers,
            )
          : null,
    );
  }

  static AnalyticsMetric _weightGain(
    List<Map<String, dynamic>> ongoing,
    List<Map<String, dynamic>> evaluations,
  ) {
    const title = 'Weight gain against expected';

    final ongoingIds = ongoing
        .map((row) => _int(row['pregnancy_id']))
        .whereType<int>()
        .toSet();

    final latest = <int, Map<String, dynamic>>{};
    for (final row in evaluations) {
      final id = _int(row['pregnancy_id']);
      if (id == null || !ongoingIds.contains(id)) continue;
      final existing = latest[id];
      if (existing == null ||
          (_date(row['created_at']) ?? DateTime(1900))
              .isAfter(_date(existing['created_at']) ?? DateTime(1900))) {
        latest[id] = row;
      }
    }

    if (latest.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.donut,
        message:
            'No weight-gain evaluations yet. They are produced once a mother '
            'has a pre-pregnancy weight and two checkup weights.',
      );
    }

    int low = 0, normal = 0, high = 0, insufficient = 0;
    for (final row in latest.values) {
      switch (row['status']?.toString().toUpperCase()) {
        case 'LOW':
          low++;
          break;
        case 'NORMAL':
          normal++;
          break;
        case 'HIGH':
          high++;
          break;
        default:
          insufficient++;
      }
    }

    final assessed = low + normal + high;

    // The headline is whichever number the midwife would act on, not a fixed
    // one. A card whose biggest element is a pink "0" spends the loudest thing
    // on the screen saying nothing happened — when nothing has, the headline
    // states the reassuring number instead.
    String headline;
    String caption;
    if (low > 0) {
      headline = '$low';
      caption = 'gaining below the expected range';
    } else if (high > 0) {
      headline = '$high';
      caption = 'gaining above the expected range';
    } else if (normal > 0) {
      headline = '$normal';
      caption = 'all gaining within the expected range';
    } else {
      headline = '$insufficient';
      caption = 'waiting on more weights before gain can be judged';
    }

    AnalyticsInsight insight;
    if (low > 0) {
      insight = AnalyticsInsight(
        '$low of $assessed assessed '
        '${_plural(assessed, 'pregnancy is', 'pregnancies are')} gaining below '
        'the range expected for their pre-pregnancy BMI.',
        tone: AnalyticsTone.watch,
        evidence: 'Low gain is linked to low birth weight and preterm birth.',
      );
    } else if (high > 0) {
      // Says exactly which pregnancies are which. The earlier wording — "the
      // rest are within it" — quietly swept the not-enough-data group in with
      // the healthy ones.
      insight = AnalyticsInsight(
        '$high of $assessed assessed '
        '${_plural(assessed, 'pregnancy is', 'pregnancies are')} gaining above '
        'the expected range, and $normal '
        '${_plural(normal, 'is', 'are')} within it.',
        tone: AnalyticsTone.watch,
      );
    } else if (assessed > 0) {
      insight = AnalyticsInsight(
        'All $assessed assessed '
        '${_plural(assessed, 'pregnancy is', 'pregnancies are')} gaining within '
        'the expected range.',
        tone: AnalyticsTone.good,
      );
    } else {
      insight = const AnalyticsInsight(
        'No pregnancy has enough recorded weights yet to judge gain against '
        'its expected range.',
        tone: AnalyticsTone.neutral,
      );
    }

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.donut,
      headline: headline,
      headlineCaption: caption,
      bands: [
        AnalyticsBand(
          label: 'Below expected',
          count: low,
          severity: AnalyticsSeverity.watch,
        ),
        AnalyticsBand(
          label: 'Within expected',
          count: normal,
          severity: AnalyticsSeverity.good,
        ),
        AnalyticsBand(
          label: 'Above expected',
          count: high,
          severity: AnalyticsSeverity.watch,
        ),
        AnalyticsBand(
          label: 'Not enough data',
          count: insufficient,
          severity: AnalyticsSeverity.unknown,
        ),
      ],
      insight: insight,
      footnote: insufficient > 0
          ? '$insufficient ${_plural(insufficient, 'pregnancy does', 'pregnancies do')} '
              'not yet have enough recorded weights to judge, and '
              '${_plural(insufficient, 'is', 'are')} counted separately above.'
          : null,
      prescription: (low + high) > 0
          ? const AnalyticsPrescription(
              label: 'Review nutrition counselling',
              action: AnalyticsAction.viewMothers,
            )
          : null,
    );
  }

  // ==========================================================================
  // CHILDREN
  // ==========================================================================

  static AnalyticsMetric _childAgeBands(
    List<Map<String, dynamic>> children,
    DateTime now,
  ) {
    const title = 'Children by age';

    if (children.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        message: 'No children registered at this centre yet.',
      );
    }

    int infantEarly = 0, infantLate = 0, oneYear = 0, preschool = 0, older = 0;
    int missing = 0;

    for (final child in children) {
      final months = _ageMonths(child, now);
      if (months == null) {
        missing++;
        continue;
      }
      if (months < 6) {
        infantEarly++;
      } else if (months < 12) {
        infantLate++;
      } else if (months < 24) {
        oneYear++;
      } else if (months < 60) {
        preschool++;
      } else {
        older++;
      }
    }

    final known =
        infantEarly + infantLate + oneYear + preschool + older;
    final underOne = infantEarly + infantLate;

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.bars,
      headline: '${children.length}',
      headlineCaption: 'children registered at this centre',
      bands: [
        AnalyticsBand(label: '0–5 months', shortLabel: '0–5m', count: infantEarly),
        AnalyticsBand(label: '6–11 months', shortLabel: '6–11m', count: infantLate),
        AnalyticsBand(label: '1 year', shortLabel: '1y', count: oneYear),
        AnalyticsBand(label: '2–4 years', shortLabel: '2–4y', count: preschool),
        AnalyticsBand(label: '5 and over', shortLabel: '5y+', count: older),
      ],
      insight: underOne > 0
          ? AnalyticsInsight(
              '$underOne ${_plural(underOne, 'child is', 'children are')} under '
              'one year old — the stretch where almost every scheduled dose '
              'falls, and where growth is checked most often.',
              tone: AnalyticsTone.neutral,
            )
          : AnalyticsInsight(
              'No child is under one year old. Immunisation work here is '
              'catch-up and boosters rather than the primary series.',
              tone: AnalyticsTone.neutral,
            ),
      footnote: missing > 0
          ? '$missing ${_plural(missing, 'child has', 'children have')} no '
              'birthdate recorded, so ${missing == 1 ? 'it is' : 'they are'} '
              'left out of the bands above.'
          : null,
      prescription: known > 0
          ? const AnalyticsPrescription(
              label: 'Open children list',
              action: AnalyticsAction.viewChildren,
            )
          : null,
    );
  }

  /// Growth findings, with measurement coverage stated in the same breath.
  ///
  /// The two belong together: "four children underweight" means something
  /// different when it comes from thirty measurements than from six, and a
  /// card that reports the first without the second invites the wrong reading.
  static AnalyticsMetric _growthFindings(
    List<Map<String, dynamic>> children,
    List<Map<String, dynamic>> records,
    DateTime now,
  ) {
    const title = 'Growth findings';

    if (children.isEmpty || records.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.rankedBars,
        message:
            'No growth measurements recorded yet. Weight and height entries '
            'appear here as soon as they are taken.',
      );
    }

    final latest = <int, Map<String, dynamic>>{};
    for (final row in records) {
      final id = _int(row['child_id']);
      if (id == null) continue;
      final existing = latest[id];
      if (existing == null ||
          (_date(row['measurement_date']) ?? DateTime(1900))
              .isAfter(_date(existing['measurement_date']) ?? DateTime(1900))) {
        latest[id] = row;
      }
    }

    int underweight = 0, underweightSevere = 0;
    int stunted = 0, stuntedSevere = 0;
    int thin = 0;
    int overweight = 0;
    int flagged = 0;
    int recent = 0;

    for (final row in latest.values) {
      final weightZ = _double(row['weight_for_age_zscore']);
      final heightZ = _double(row['height_for_age_zscore']);
      final bmiZ = _double(row['bmi_for_age_zscore']);

      bool anyFlag = false;
      if (weightZ != null && weightZ < -2) {
        underweight++;
        anyFlag = true;
        if (weightZ < -3) underweightSevere++;
      }
      if (heightZ != null && heightZ < -2) {
        stunted++;
        anyFlag = true;
        if (heightZ < -3) stuntedSevere++;
      }
      if (bmiZ != null && bmiZ < -2) {
        thin++;
        anyFlag = true;
      }
      if (bmiZ != null && bmiZ > 2) {
        overweight++;
        anyFlag = true;
      }
      if (anyFlag) flagged++;

      final when = _date(row['measurement_date']);
      if (when != null &&
          now.difference(when).inDays <= _growthStaleDays) {
        recent++;
      }
    }

    final stale = children.length - recent;
    final bands = <AnalyticsBand>[
      AnalyticsBand(
        label: 'Underweight for age',
        count: underweight,
        severity: AnalyticsSeverity.alert,
        detail: underweightSevere > 0 ? '$underweightSevere severe' : null,
      ),
      AnalyticsBand(
        label: 'Stunted (short for age)',
        count: stunted,
        severity: AnalyticsSeverity.alert,
        detail: stuntedSevere > 0 ? '$stuntedSevere severe' : null,
      ),
      AnalyticsBand(
        label: 'Thin for height',
        count: thin,
        severity: AnalyticsSeverity.watch,
      ),
      AnalyticsBand(
        label: 'Above healthy weight',
        count: overweight,
        severity: AnalyticsSeverity.watch,
      ),
      AnalyticsBand(
        label: 'Within healthy range',
        count: latest.length - flagged,
        severity: AnalyticsSeverity.good,
      ),
    ]..removeWhere((band) => band.count == 0);

    final coverageIsThin = recent < (children.length * 0.7);

    AnalyticsInsight insight;
    if (coverageIsThin) {
      insight = AnalyticsInsight(
        'Only $recent of ${children.length} children have been measured in the '
        'last $_growthStaleDays days, so these findings describe part of the '
        'caseload, not all of it.',
        tone: AnalyticsTone.watch,
        evidence: 'Weigh the rest before reading too much into the split.',
      );
    } else if (flagged > 0) {
      insight = AnalyticsInsight(
        '$flagged of ${latest.length} measured '
        '${_plural(latest.length, 'child falls', 'children fall')} outside the '
        'WHO range on their latest measurement.',
        tone: AnalyticsTone.alert,
      );
    } else {
      insight = AnalyticsInsight(
        'Every one of the ${latest.length} measured children is within the WHO '
        'range on their latest measurement.',
        tone: AnalyticsTone.good,
      );
    }

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.rankedBars,
      periodLabel: 'Latest measurement',
      headline: flagged > 0 ? '$flagged' : '${latest.length}',
      headlineCaption: flagged > 0
          ? 'of ${latest.length} measured ${_plural(latest.length, 'child', 'children')} '
              'need follow-up'
          : 'measured ${_plural(latest.length, 'child', 'children')}, all within '
              'the healthy range',
      bands: bands,
      insight: insight,
      footnote: 'Judged against WHO Child Growth Standards z-scores.',
      prescription: stale > 0
          ? AnalyticsPrescription(
              label:
                  'Weigh $stale ${_plural(stale, 'child', 'children')} not seen recently',
              action: AnalyticsAction.viewChildren,
            )
          : const AnalyticsPrescription(
              label: 'Open children list',
              action: AnalyticsAction.viewChildren,
            ),
    );
  }

  static AnalyticsMetric _immunizationCoverage(
    Map<int, _ChildDoses> childDoses,
    List<Map<String, dynamic>> immunizations,
    DateTime now,
  ) {
    const title = 'Childhood immunisation';

    if (childDoses.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.coverage,
        message:
            'Immunisation coverage needs children with recorded birthdates and '
            'a vaccine schedule to compare against.',
      );
    }

    final upToDate =
        childDoses.values.where((doses) => doses.pastDue.isEmpty).length;
    final behind = childDoses.length - upToDate;

    final thisMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    int dosesThisMonth = 0, dosesLastMonth = 0;
    for (final row in immunizations) {
      final when = _date(row['vaccination_date']);
      if (when == null) continue;
      if (!when.isBefore(thisMonthStart)) {
        dosesThisMonth++;
      } else if (!when.isBefore(lastMonthStart)) {
        dosesLastMonth++;
      }
    }

    // Pentavalent dropout — the standard EPI read. Low coverage with low
    // dropout is an access problem; low coverage with high dropout is a
    // follow-up problem, and they call for different work.
    int penta1 = 0, penta3 = 0;
    for (final doses in childDoses.values) {
      if (doses.givenPentaDoses.contains(1)) penta1++;
      if (doses.givenPentaDoses.contains(3)) penta3++;
    }
    final dropout = penta1 > 0 ? ((penta1 - penta3) / penta1 * 100).round() : null;

    // Fully immunised child, in the sense the DOH card uses: every dose
    // scheduled on or before the first birthday, in children old enough to
    // have finished.
    final eligibleForFic =
        childDoses.values.where((doses) => doses.ageMonths >= 12).toList();
    final fic = eligibleForFic.where((doses) => doses.completedByOneYear).length;

    AnalyticsInsight insight;
    if (dropout != null && dropout > 10 && penta1 > 2) {
      insight = AnalyticsInsight(
        'Pentavalent dropout is $dropout% — $penta1 children started the series '
        'and ${penta1 - penta3} have not finished it. That is a follow-up gap, '
        'not an access one.',
        tone: AnalyticsTone.watch,
        evidence: 'Children who reached the centre once can be brought back.',
      );
    } else if (behind > 0) {
      insight = AnalyticsInsight(
        '$behind ${_plural(behind, 'child has', 'children have')} at least one '
        'dose past due for their age.',
        tone: AnalyticsTone.alert,
      );
    } else {
      insight = const AnalyticsInsight(
        'Every child with a recorded birthdate is on schedule for their age.',
        tone: AnalyticsTone.good,
      );
    }

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.coverage,
      periodLabel: 'On schedule',
      headline: '$upToDate',
      headlineCaption:
          'of ${childDoses.length} ${_plural(childDoses.length, 'child is', 'children are')} '
          'up to date for their age',
      covered: upToDate,
      eligible: childDoses.length,
      comparison: AnalyticsComparison(
        previousLabel: DateFormat('MMMM').format(lastMonthStart),
        previousValue: dosesLastMonth,
        currentLabel: DateFormat('MMMM').format(thisMonthStart),
        currentValue: dosesThisMonth,
        unit: 'doses',
      ),
      insight: insight,
      footnote: eligibleForFic.isEmpty
          ? 'Judged against the DOH childhood schedule.'
          : 'Fully immunised by one year: $fic of ${eligibleForFic.length} '
              '${_plural(eligibleForFic.length, 'child', 'children')} old enough to have finished.',
      prescription: behind > 0
          ? AnalyticsPrescription(
              label:
                  'Chase $behind ${_plural(behind, 'child', 'children')} behind schedule',
              action: AnalyticsAction.viewChildren,
            )
          : null,
    );
  }

  // ==========================================================================
  // SUPPLIES
  // ==========================================================================

  static AnalyticsMetric _stockOnHand(_Stock stock) {
    const title = 'Stock on hand';

    if (stock.items.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.rankedBars,
        message: 'No inventory recorded for this health centre yet.',
      );
    }

    final items = [...stock.items]
      ..sort((a, b) => a.headroom.compareTo(b.headroom));
    final short = items.where((item) => item.isBelowThreshold).toList();

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.rankedBars,
      periodLabel: stock.isSample ? 'Sample data' : 'Live',
      headline: '${short.length}',
      headlineCaption:
          'of ${items.length} items are below their reorder level',
      bands: [
        for (final item in items.take(6))
          AnalyticsBand(
            label: item.name,
            count: item.quantity,
            severity: item.severity,
            // Drawn against the reorder level, not against the largest number
            // on the shelf: 640 tablets and 18 vials share this chart, and
            // "how close to running out" is the only thing they can both be
            // measured in.
            fraction: (item.headroom / 2).clamp(0.02, 1.0),
            detail: 'reorder at ${item.threshold} ${item.unit}',
          ),
      ],
      insight: short.isEmpty
          ? const AnalyticsInsight(
              'Every tracked item is above its reorder level.',
              tone: AnalyticsTone.good,
            )
          : AnalyticsInsight(
              '${short.length} ${_plural(short.length, 'item is', 'items are')} '
              'below reorder level, starting with ${short.first.name} at '
              '${short.first.quantity} ${short.first.unit}.',
              tone: AnalyticsTone.alert,
            ),
      footnote: stock.isSample
          ? 'Sample figures shown until this centre records its own batches.'
          : null,
      prescription: const AnalyticsPrescription(
        label: 'Open inventory',
        action: AnalyticsAction.viewInventory,
      ),
    );
  }

  static AnalyticsMetric _expiringSoon(_Stock stock) {
    const title = 'Expiring stock';

    final soon = stock.batches
        .where((batch) =>
            batch.expiresIn != null &&
            batch.expiresIn! <= 90 &&
            batch.quantity > 0)
        .toList()
      ..sort((a, b) => a.expiresIn!.compareTo(b.expiresIn!));

    if (soon.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.rankedBars,
        message: 'Nothing on the shelf expires within the next three months.',
      );
    }

    final within30 = soon.where((batch) => batch.expiresIn! <= 30).toList();
    final atRisk = soon.fold<int>(0, (sum, batch) => sum + batch.quantity);

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.rankedBars,
      periodLabel: 'Next 90 days',
      headline: '$atRisk',
      headlineCaption: 'units expire within 90 days',
      bands: [
        for (final batch in soon.take(5))
          AnalyticsBand(
            label: batch.itemName,
            count: batch.quantity,
            severity: batch.expiresIn! <= 30
                ? AnalyticsSeverity.alert
                : (batch.expiresIn! <= 60
                    ? AnalyticsSeverity.watch
                    : AnalyticsSeverity.neutral),
            // Length is urgency, not quantity — the soonest to expire is the
            // longest bar, whatever unit it is counted in.
            fraction: (1 - (batch.expiresIn! / 90)).clamp(0.05, 1.0),
            detail: 'batch ${batch.batchNumber} · '
                '${batch.expiresIn} days left',
          ),
      ],
      insight: within30.isEmpty
          ? AnalyticsInsight(
              'Nothing expires within the month. Give the ${soon.first.itemName} '
              'batch first so it is used before its date.',
              tone: AnalyticsTone.neutral,
            )
          : AnalyticsInsight(
              '${within30.fold<int>(0, (sum, b) => sum + b.quantity)} units '
              'expire within 30 days. Give these before any newer batch.',
              tone: AnalyticsTone.alert,
              evidence: 'Stock that expires on the shelf is stock nobody got.',
            ),
      footnote: stock.isSample
          ? 'Sample figures shown until this centre records its own batches.'
          : null,
      prescription: const AnalyticsPrescription(
        label: 'Open inventory',
        action: AnalyticsAction.viewInventory,
      ),
    );
  }

  /// Where the two halves of the system meet: children's due doses on one side,
  /// what is on the shelf on the other.
  static AnalyticsMetric _upcomingDemand(
    Map<int, _ChildDoses> childDoses,
    _Stock stock,
  ) {
    const title = 'Doses needed next month';

    final demand = <String, int>{};
    for (final doses in childDoses.values) {
      for (final name in doses.dueWithin30Days) {
        demand[name] = (demand[name] ?? 0) + 1;
      }
    }

    if (demand.isEmpty) {
      return const AnalyticsMetric.empty(
        title: title,
        kind: AnalyticsChartKind.rankedBars,
        message:
            'No doses fall due in the next 30 days for the children on file.',
      );
    }

    final ranked = demand.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final bands = <AnalyticsBand>[];
    final shortfalls = <String>[];
    for (final entry in ranked.take(5)) {
      final onHand = stock.quantityMatching(entry.key);
      final short = onHand != null && onHand < entry.value;
      if (short) {
        shortfalls.add('${entry.key} (${entry.value - onHand} short)');
      }
      bands.add(
        AnalyticsBand(
          label: entry.key,
          count: entry.value,
          severity: short ? AnalyticsSeverity.alert : AnalyticsSeverity.neutral,
          detail: onHand == null
              ? 'no matching stock item'
              : '$onHand on hand',
        ),
      );
    }

    final total = demand.values.fold<int>(0, (sum, value) => sum + value);

    return AnalyticsMetric(
      title: title,
      kind: AnalyticsChartKind.rankedBars,
      periodLabel: 'Next 30 days',
      headline: '$total',
      headlineCaption: 'doses fall due for children on file',
      bands: bands,
      insight: shortfalls.isEmpty
          ? const AnalyticsInsight(
              'Stock on hand covers every dose falling due in the next month.',
              tone: AnalyticsTone.good,
            )
          : AnalyticsInsight(
              'Stock will not cover ${shortfalls.join(', ')}. Request resupply '
              'before those children come in.',
              tone: AnalyticsTone.alert,
            ),
      footnote: stock.isSample
          ? 'Doses due are from real records; the stock they are matched '
              'against is sample data.'
          : 'Stock is matched to vaccines by name — confirm on the inventory '
              'page before ordering.',
      prescription: const AnalyticsPrescription(
        label: 'Open inventory',
        action: AnalyticsAction.viewInventory,
      ),
    );
  }

  // ==========================================================================
  // TODAY
  // ==========================================================================

  static List<AnalyticsPriority> _priorities({
    required List<Map<String, dynamic>> ongoing,
    required Map<int, Map<String, dynamic>> mothersById,
    required List<Map<String, dynamic>> upcomingCheckups,
    required List<Map<String, dynamic>> riskAssessments,
    required Map<int, _ChildDoses> childDoses,
    required _Stock stock,
    required DateTime now,
  }) {
    final priorities = <AnalyticsPriority>[];
    final today = _dayStart(now);

    final motherByPregnancy = <int, Map<String, dynamic>>{};
    for (final row in ongoing) {
      final pregnancyId = _int(row['pregnancy_id']);
      final mother = mothersById[_int(row['mother_id']) ?? -1];
      if (pregnancyId != null && mother != null) {
        motherByPregnancy[pregnancyId] = mother;
      }
    }

    // Checkups due this week.
    for (final row in upcomingCheckups) {
      final due = _date(row['next_schedule']);
      final mother = motherByPregnancy[_int(row['pregnancy_id']) ?? -1];
      if (due == null || mother == null) continue;

      final days = _dayStart(due).difference(today).inDays;
      if (days < 0 || days > 7) continue;

      priorities.add(
        AnalyticsPriority(
          title: 'Checkup due — ${_motherName(mother)}',
          detail: days == 0
              ? 'Scheduled for today'
              : '${DateFormat('EEEE, MMM d').format(due)} · in $days '
                  '${_plural(days, 'day', 'days')}',
          severity: days == 0
              ? AnalyticsSeverity.alert
              : (days <= 2 ? AnalyticsSeverity.watch : AnalyticsSeverity.neutral),
          action: AnalyticsAction.viewSchedules,
          sortKey: days,
        ),
      );
    }

    // High-risk pregnancies, named with the factor that flagged them where one
    // was recorded — "high risk" alone gives the midwife nothing to prepare.
    final factorByPregnancy = <int, String>{};
    for (final assessment in riskAssessments) {
      final id = _int(assessment['pregnancy_id']);
      final factors = assessment['pregnancy_risk_factors'];
      if (id == null || factors is! List || factors.isEmpty) continue;
      final first = factors.first;
      if (first is Map) {
        final label = _canonicalFactor(first['factor']?.toString() ?? '');
        if (label.isNotEmpty) factorByPregnancy[id] = _lowerFirst(label);
      }
    }

    for (final row in ongoing) {
      if (row['pregnancy_risk_level']?.toString() != 'high') continue;
      final pregnancyId = _int(row['pregnancy_id']);
      final mother = mothersById[_int(row['mother_id']) ?? -1];
      if (mother == null) continue;

      final factor = factorByPregnancy[pregnancyId ?? -1];
      priorities.add(
        AnalyticsPriority(
          title: 'High-risk pregnancy — ${_motherName(mother)}',
          detail: factor == null
              ? 'Marked high risk — review at the next visit'
              : 'Flagged for $factor',
          severity: AnalyticsSeverity.alert,
          action: AnalyticsAction.viewMothers,
          sortKey: -20,
        ),
      );
    }

    // Children with a dose past due, worst first.
    for (final doses in childDoses.values) {
      if (doses.pastDue.isEmpty) continue;
      priorities.add(
        AnalyticsPriority(
          title: '${doses.childName} is behind on ${doses.pastDue.first}',
          detail: doses.pastDue.length == 1
              ? doses.worstOverdueLabel
              : '${doses.pastDue.length} doses past due · ${doses.worstOverdueLabel}',
          severity: AnalyticsSeverity.alert,
          action: AnalyticsAction.viewChildren,
          sortKey: -10,
        ),
      );
    }

    // Stock, but only when the figures are this centre's own. A sample number
    // has no business in a list headed "needs attention".
    if (!stock.isSample) {
      for (final item in stock.items.where((item) => item.isBelowThreshold)) {
        priorities.add(
          AnalyticsPriority(
            title: '${item.name} below reorder level',
            detail: '${item.quantity} ${item.unit} left · reorder at '
                '${item.threshold}',
            severity: AnalyticsSeverity.watch,
            action: AnalyticsAction.viewInventory,
            sortKey: 10,
          ),
        );
      }
    }

    priorities.sort((a, b) {
      final byKey = a.sortKey.compareTo(b.sortKey);
      return byKey != 0 ? byKey : a.title.compareTo(b.title);
    });
    return priorities;
  }

  // ==========================================================================
  // DERIVATIONS
  // ==========================================================================

  /// Every child's outstanding doses, judged by the same rules the child
  /// profile uses.
  ///
  /// Reusing [ImmunizationSchedule] rather than re-deriving "late" here is the
  /// point: a child must not be able to read "past due" on this dashboard and
  /// "on time" on their own page.
  static Map<int, _ChildDoses> _childDoseStatuses(
    List<Map<String, dynamic>> children,
    List<Map<String, dynamic>> vaccines,
    List<Map<String, dynamic>> records,
    DateTime now,
  ) {
    if (vaccines.isEmpty) return {};

    final recordsByChild = <int, List<Map<String, dynamic>>>{};
    for (final row in records) {
      final childId = _int(row['child_id']);
      if (childId == null) continue;
      recordsByChild.putIfAbsent(childId, () => []).add(row);
    }

    // Doses of the same vaccine in order, so a later dose can be judged against
    // when the previous one was actually given.
    final byName = <String, List<Map<String, dynamic>>>{};
    for (final vaccine in vaccines) {
      final name = vaccine['vaccine_name']?.toString() ?? '';
      if (name.isEmpty) continue;
      byName.putIfAbsent(name, () => []).add(vaccine);
    }
    for (final series in byName.values) {
      series.sort((a, b) =>
          (_int(a['dose_number']) ?? 0).compareTo(_int(b['dose_number']) ?? 0));
    }

    final result = <int, _ChildDoses>{};

    for (final child in children) {
      final childId = _int(child['child_id']);
      final birthdate = _birthdate(child);
      if (childId == null || birthdate == null) continue;

      final ageMonths = now.difference(birthdate).inDays / _daysPerMonth;
      final given = recordsByChild[childId] ?? const [];
      final givenDates = <int, DateTime>{};
      for (final row in given) {
        final vaccineId = _int(row['vaccine_id']);
        final when = _date(row['vaccination_date']);
        if (vaccineId != null && when != null) givenDates[vaccineId] = when;
      }

      final pastDue = <String>[];
      final dueSoon = <String>[];
      final pentaGiven = <int>{};
      double worstLateMonths = 0;
      bool completedByOneYear = true;

      for (final series in byName.values) {
        DateTime? previousGivenOn;
        for (final vaccine in series) {
          final vaccineId = _int(vaccine['vaccine_id']);
          final name = vaccine['vaccine_name']?.toString() ?? 'Vaccine';
          final doseNumber = _int(vaccine['dose_number']) ?? 1;
          final scheduledAt =
              _double(vaccine['recommended_age_months']) ?? 0;
          final alreadyGiven =
              vaccineId != null && givenDates.containsKey(vaccineId);

          if (alreadyGiven) {
            previousGivenOn = givenDates[vaccineId];
            if (name.toLowerCase().contains('penta')) {
              pentaGiven.add(doseNumber);
            }
          } else if (scheduledAt <= 12 && ageMonths >= 12) {
            completedByOneYear = false;
          }

          final status = ImmunizationSchedule.statusOfVaccine(
            vaccine,
            alreadyGiven: alreadyGiven,
            childAgeMonths: ageMonths,
            ageIsKnown: true,
            birthdate: birthdate,
            previousDoseGivenOn: previousGivenOn,
          );

          final label =
              doseNumber > 1 ? '$name dose $doseNumber' : name;

          if (status == DoseStatus.pastDue) {
            pastDue.add(label);
            final late = ageMonths - scheduledAt;
            if (late > worstLateMonths) worstLateMonths = late;
          } else if (status == DoseStatus.due) {
            dueSoon.add(name);
          } else if (status == DoseStatus.notYetDue) {
            // Falls due inside the next month if the child reaches the
            // scheduled age within 30 days.
            final daysUntil =
                ((scheduledAt - ageMonths) * _daysPerMonth).round();
            if (daysUntil > 0 && daysUntil <= 30) dueSoon.add(name);
          }
        }
      }

      result[childId] = _ChildDoses(
        childName: _childName(child),
        ageMonths: ageMonths,
        pastDue: pastDue,
        dueWithin30Days: dueSoon,
        givenPentaDoses: pentaGiven,
        completedByOneYear: completedByOneYear,
        worstOverdueLabel: worstLateMonths <= 0
            ? 'past due'
            : ImmunizationSchedule.describeOverdue(
                childAgeMonths: ageMonths,
                scheduledAtMonths: ageMonths - worstLateMonths,
              ),
      );
    }

    return result;
  }

  static _Stock _resolveStock(
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> batches,
  ) {
    if (items.isEmpty || batches.isEmpty) return _Stock.sample();

    final byItem = <int, List<Map<String, dynamic>>>{};
    for (final batch in batches) {
      final itemId = _int(batch['item_id']);
      if (itemId == null) continue;
      byItem.putIfAbsent(itemId, () => []).add(batch);
    }

    final stockItems = <_StockItem>[];
    final stockBatches = <_StockBatch>[];
    final now = DateTime.now();

    for (final item in items) {
      final itemId = _int(item['item_id']);
      if (itemId == null) continue;
      final itemBatches = byItem[itemId] ?? const [];
      if (itemBatches.isEmpty) continue;

      final name = item['name']?.toString() ?? 'Item';
      final unit = item['unit_of_measure']?.toString() ?? 'units';
      final threshold = _int(item['minimum_stock_threshold']) ?? 50;
      final quantity = itemBatches.fold<int>(
        0,
        (sum, batch) => sum + (_int(batch['quantity_remaining']) ?? 0),
      );

      stockItems.add(
        _StockItem(
          name: name,
          quantity: quantity,
          threshold: threshold,
          unit: unit,
        ),
      );

      for (final batch in itemBatches) {
        final expiry = _date(batch['expiration_date']);
        stockBatches.add(
          _StockBatch(
            itemName: name,
            batchNumber: batch['batch_number']?.toString() ?? '—',
            quantity: _int(batch['quantity_remaining']) ?? 0,
            expiresIn:
                expiry == null ? null : _dayStart(expiry).difference(_dayStart(now)).inDays,
          ),
        );
      }
    }

    if (stockItems.isEmpty) return _Stock.sample();
    return _Stock(items: stockItems, batches: stockBatches, isSample: false);
  }

  // ==========================================================================
  // PLUMBING
  // ==========================================================================

  static Future<List<Map<String, dynamic>>> _none() async => const [];

  /// Runs a query and returns rows, or an empty list and a debug line.
  ///
  /// Deliberately forgiving: a centre whose database has not had every
  /// migration applied still gets every card the data supports, and the ones it
  /// does not support say so instead of taking the dashboard down.
  static Future<List<Map<String, dynamic>>> _rows(
    dynamic query,
    String label,
  ) async {
    try {
      final result = await (query as Future).timeout(
        const Duration(seconds: 8),
      );
      if (result is List) {
        return result
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }
      return const [];
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Analytics: $label unavailable — $error');
      }
      return const [];
    }
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _double(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static Map<String, dynamic>? _firstMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) return _firstMap(value.first);
    return null;
  }

  static DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _isoDate(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value);

  static int _yearsBetween(DateTime birthdate, DateTime now) {
    var years = now.year - birthdate.year;
    final hadBirthday = now.month > birthdate.month ||
        (now.month == birthdate.month && now.day >= birthdate.day);
    if (!hadBirthday) years--;
    return years;
  }

  static DateTime? _birthdate(Map<String, dynamic> child) =>
      _date(_firstMap(child['birth_details'])?['birthdate']);

  static double? _ageMonths(Map<String, dynamic> child, DateTime now) {
    final birthdate = _birthdate(child);
    if (birthdate == null) return null;
    return now.difference(birthdate).inDays / _daysPerMonth;
  }

  /// Whether a pregnancy was running at any point inside the window.
  ///
  /// This is the denominator behind every "fewer doses this month" reading, so
  /// it counts pregnancies that ended mid-window too — a mother who delivered
  /// on the 10th was still someone who could have been given TD on the 3rd.
  static bool _wasPregnantDuring(
    Map<String, dynamic> pregnancy,
    DateTime start,
    DateTime end,
  ) {
    final began = _date(pregnancy['last_menstrual_period']) ??
        _date(pregnancy['created_at']);
    if (began == null || began.isAfter(end)) return false;

    final ended = _date(pregnancy['ended_at']);
    if (ended != null) return !ended.isBefore(start);
    return true;
  }

  /// The dose number written on a checkup, however it was written.
  ///
  /// Free text in practice: "TD2", "2", "second dose". A dose that cannot be
  /// read is not counted rather than guessed at.
  static int? _doseNumber(String? raw) {
    if (raw == null) return null;
    final text = raw.toLowerCase().trim();
    if (text.isEmpty) return null;

    final digits = RegExp(r'(\d+)').firstMatch(text);
    if (digits != null) return int.tryParse(digits.group(1)!);

    const words = {
      'first': 1,
      'second': 2,
      'third': 3,
      'fourth': 4,
      'fifth': 5,
    };
    for (final entry in words.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static String _motherName(Map<String, dynamic> mother) {
    final account = _firstMap(mother['accounts']);
    final name =
        '${account?['first_name'] ?? ''} ${account?['last_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Unnamed mother' : name;
  }

  static String _childName(Map<String, dynamic> child) {
    final name =
        '${child['first_name'] ?? ''} ${child['last_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Unnamed child' : name;
  }

  /// Groups risk-factor text by the clinical finding it describes.
  ///
  /// Three screens write these strings and none of them agree. A young mother
  /// arrives as "Maternal age below 19 years" from the add-mother form, as
  /// "Early Maternal Age (16 years)" from the ultrasound analyser, and as
  /// "Maternal age factor (16 years)" from the prenatal checkup — and that last
  /// one embeds her own age, so every age becomes its own category. Counted
  /// verbatim, one finding in five pregnancies showed up as three short bars
  /// that each looked minor.
  ///
  /// Grouping happens here, at read time, rather than in the writers: the
  /// specific wording is worth keeping on a mother's own record, where "(16
  /// years)" tells the midwife something. It is only the aggregate that needs
  /// them to be one thing. Doing it here also fixes rows already saved.
  static String _canonicalFactor(String raw) {
    final trimmed = raw
        .trim()
        .replaceFirst(
          RegExp(r'^(condition|medical condition|history)\s*:\s*',
              caseSensitive: false),
          '',
        )
        .trim();
    if (trimmed.isEmpty) return '';

    final lower = trimmed.toLowerCase();

    // A number in the text is nearly always the mother's own value, not part
    // of the finding's name. Read it before it is stripped, because for an age
    // factor it is the only thing saying which direction the risk runs.
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(lower);
    final value = match == null ? null : double.tryParse(match.group(1)!);

    if (lower.contains('maternal age') ||
        lower.contains('primigravida') ||
        lower.contains('adolescent')) {
      final saysYoung = lower.contains('below') ||
          lower.contains('under') ||
          lower.contains('early') ||
          lower.contains('young') ||
          lower.contains('adolescent') ||
          lower.contains('teen');
      final saysAdvanced = lower.contains('advanced') ||
          lower.contains('elderly') ||
          lower.contains('≥') ||
          lower.contains('>=') ||
          lower.contains('over');

      if (saysYoung) return 'Young maternal age';
      if (saysAdvanced) return 'Advanced maternal age';
      if (value != null) {
        if (value < 20) return 'Young maternal age';
        if (value >= 35) return 'Advanced maternal age';
      }
      return 'Maternal age';
    }

    // Elsewhere a bracketed number is a threshold or a reading — "(BMI < 18.5
    // kg/m²)", "(140/90)". The finding is the same finding without it.
    final withoutValues =
        trimmed.replaceAll(RegExp(r'\s*\([^)]*\d[^)]*\)'), '').trim();
    return _titleCase(withoutValues.isEmpty ? trimmed : withoutValues);
  }

  static String _plural(int count, String one, String many) =>
      count == 1 ? one : many;

  static String _titleCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  static String _lowerFirst(String value) {
    if (value.isEmpty) return value;
    return value[0].toLowerCase() + value.substring(1);
  }
}

/// One child's outstanding schedule, reduced to what the cards need.
class _ChildDoses {
  const _ChildDoses({
    required this.childName,
    required this.ageMonths,
    required this.pastDue,
    required this.dueWithin30Days,
    required this.givenPentaDoses,
    required this.completedByOneYear,
    required this.worstOverdueLabel,
  });

  final String childName;
  final double ageMonths;
  final List<String> pastDue;
  final List<String> dueWithin30Days;
  final Set<int> givenPentaDoses;
  final bool completedByOneYear;
  final String worstOverdueLabel;
}

class _StockItem {
  const _StockItem({
    required this.name,
    required this.quantity,
    required this.threshold,
    required this.unit,
  });

  final String name;
  final int quantity;
  final int threshold;
  final String unit;

  bool get isBelowThreshold => quantity < threshold;

  /// How far above the reorder level this item is, as a share of the level.
  /// Sorting on this puts the most exposed item first regardless of whether it
  /// is counted in vials or tablets.
  double get headroom =>
      threshold == 0 ? quantity.toDouble() : quantity / threshold;

  AnalyticsSeverity get severity {
    if (isBelowThreshold) return AnalyticsSeverity.alert;
    if (headroom < 1.5) return AnalyticsSeverity.watch;
    return AnalyticsSeverity.good;
  }
}

class _StockBatch {
  const _StockBatch({
    required this.itemName,
    required this.batchNumber,
    required this.quantity,
    required this.expiresIn,
  });

  final String itemName;
  final String batchNumber;
  final int quantity;

  /// Days from today until the expiration date.
  final int? expiresIn;
}

class _Stock {
  const _Stock({
    required this.items,
    required this.batches,
    required this.isSample,
  });

  /// A stand-in shelf, used until a centre records its own batches.
  ///
  /// Every card built on it says "Sample data" on its face and it is kept out
  /// of the priority list entirely, so nobody reorders against an invented
  /// number.
  factory _Stock.sample() {
    final now = DateTime.now();
    int daysFromNow(int days) =>
        MidwifeAnalyticsService._dayStart(now.add(Duration(days: days)))
            .difference(MidwifeAnalyticsService._dayStart(now))
            .inDays;

    return _Stock(
      isSample: true,
      items: const [
        _StockItem(name: 'Pentavalent (DPT-HepB-Hib)', quantity: 18, threshold: 40, unit: 'vials'),
        _StockItem(name: 'Tetanus-diphtheria (TD)', quantity: 26, threshold: 30, unit: 'vials'),
        _StockItem(name: 'Ferrous sulfate + folic acid', quantity: 640, threshold: 500, unit: 'tablets'),
        _StockItem(name: 'BCG', quantity: 42, threshold: 30, unit: 'vials'),
        _StockItem(name: 'Oral polio (OPV)', quantity: 55, threshold: 40, unit: 'vials'),
        _StockItem(name: 'Measles-containing (MCV)', quantity: 31, threshold: 25, unit: 'vials'),
      ],
      batches: [
        _StockBatch(
          itemName: 'Measles-containing (MCV)',
          batchNumber: 'MCV-2411',
          quantity: 12,
          expiresIn: daysFromNow(24),
        ),
        _StockBatch(
          itemName: 'Oral polio (OPV)',
          batchNumber: 'OPV-2503',
          quantity: 20,
          expiresIn: daysFromNow(52),
        ),
        _StockBatch(
          itemName: 'Ferrous sulfate + folic acid',
          batchNumber: 'FE-2502',
          quantity: 180,
          expiresIn: daysFromNow(81),
        ),
      ],
    );
  }

  final List<_StockItem> items;
  final List<_StockBatch> batches;
  final bool isSample;

  /// Stock for a vaccine named on the schedule.
  ///
  /// Matched on words rather than on an identifier because the catalogue and
  /// the shelf are maintained separately — "Pentavalent (DPT-HepB-Hib)" on one
  /// side, "Pentavalent" on the other. Returns null when nothing matches, and
  /// the card says so rather than reporting a zero that would read as "none
  /// left".
  int? quantityMatching(String vaccineName) {
    final needle = vaccineName.toLowerCase().split(RegExp(r'[^a-z]+')).first;
    if (needle.isEmpty) return null;

    for (final item in items) {
      if (item.name.toLowerCase().contains(needle)) return item.quantity;
    }
    return null;
  }
}
