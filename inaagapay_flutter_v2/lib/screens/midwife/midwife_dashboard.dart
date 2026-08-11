// lib/screens/midwife/midwife_dashboard.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../models/midwife_analytics.dart';
import '../../services/auth_storage.dart';
import '../../services/midwife_analytics_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/analytics/analytics_card.dart';
import '../../widgets/midwife_statistics_card.dart';
import '../../widgets/midwife_history_card.dart';
import '../../widgets/chart_card.dart';
import 'child_profile_page.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_snackbar.dart';
import '../shared/record_detail_screen.dart';
import '../../services/mother_profile_service.dart';
import 'midwife_shell.dart';

class MidwifeDashboard extends StatefulWidget {
  final ValueNotifier<int>? refreshNotifier;

  /// Switches the surrounding shell to another tab.
  ///
  /// Supplied by [MidwifeShell]. Without it the dashboard can only push routes,
  /// and pushing a tab's route stacks it on top of the shell — losing the
  /// header and the navigation bar that live there.
  final ValueChanged<int>? onNavigateToTab;

  const MidwifeDashboard({
    super.key,
    this.refreshNotifier,
    this.onNavigateToTab,
  });

  @override
  State<MidwifeDashboard> createState() => _MidwifeDashboardState();
}

class _MidwifeDashboardState extends State<MidwifeDashboard> {
  bool _isLoading = true;

  /// True between the header rendering and the visit data arriving.
  ///
  /// Without this, the recent-visits and chart sections cannot tell "still
  /// fetching" from "nothing found", so they flash their empty state on every
  /// load before the real data replaces it.
  bool _detailsLoading = false;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Dashboard data
  int _registeredMothers = 0;
  int _registeredChildren = 0;

  // Pregnancy statistics
  int _totalPregnancies = 0;
  int _firstTrimester = 0;
  int _secondTrimester = 0;
  int _thirdTrimester = 0;

  // Recent visits
  List<MidwifeVisitItem> _recentVisits = [];

  /// Analytics section. Loaded after the header and stats have already
  /// rendered — it is the slowest part of the screen and the least urgent, so
  /// it must never be what the midwife waits on to see her caseload.
  MidwifeAnalytics _analytics = const MidwifeAnalytics.empty();
  bool _analyticsLoading = true;

  /// Which of Mothers / Children / Supplies is showing.
  ///
  /// One group at a time. All twelve cards in a single column is the same
  /// information at four times the scroll, and a dashboard that has to be
  /// scrolled that far stops being looked at.
  int _analyticsTab = 0;

  /// Guards against a slow analytics load landing after a newer one.
  int _analyticsRequestId = 0;

  // Search data
  List<Map<String, dynamic>> _allMothers = [];
  List<Map<String, dynamic>> _allChildren = [];
  List<Map<String, dynamic>> _allCheckups = [];
  List<Map<String, dynamic>> _allUltrasounds = [];
  List<Map<String, dynamic>> _allLabTests = [];
  Map<int, Map<String, dynamic>> _pregnancyToMotherMap = {};

  // Search results
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;

  // BHC Visit data for chart
  List<double> _bhcVisitValues = List.filled(7, 0.0);
  List<String> _bhcVisitDays = [];

  // Computed RHU Visits this week
  int get _rhuVisitsThisWeek =>
      _bhcVisitValues.fold(0, (sum, val) => sum + val.toInt());

  // Midwife info
  String _midwifeName = 'Midwife';
  String _bhcName = 'Loading...';
  List<int> _motherIds = [];

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_loadDashboardData);
    _loadDashboardData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_loadDashboardData);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    _performLocalSearch(query);
  }

  void _performLocalSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
      });
      return;
    }

    final queryTerms =
        query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (queryTerms.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
      });
      return;
    }

    bool matchesAllTerms(String text) {
      final lowerText = text.toLowerCase();
      for (final term in queryTerms) {
        if (!lowerText.contains(term)) {
          return false;
        }
      }
      return true;
    }

    final results = <Map<String, dynamic>>[];

    // Search through cached mothers
    for (var mother in _allMothers) {
      final firstName = (mother['first_name'] ?? '').toLowerCase();
      final lastName = (mother['last_name'] ?? '').toLowerCase();
      final fullName = '$firstName $lastName'.toLowerCase();
      final phone = (mother['phone_number'] ?? '').toLowerCase();
      final email = (mother['email_address'] ?? '').toLowerCase();
      final matchText = '$fullName $phone $email';

      if (matchesAllTerms(matchText)) {
        results.add({
          'type': 'mother',
          'id': mother['mother_id'],
          'title': '${mother['first_name'] ?? ''} ${mother['last_name'] ?? ''}'
              .trim(),
          'subtitle': email.isNotEmpty
              ? email
              : (phone.isNotEmpty ? phone : 'No contact'),
          'icon': Icons.pregnant_woman,
          'matchText': fullName,
        });
      }
    }

    // Search through cached children
    for (var child in _allChildren) {
      final firstName = (child['first_name'] ?? '').toLowerCase();
      final lastName = (child['last_name'] ?? '').toLowerCase();
      final fullName = '$firstName $lastName'.toLowerCase();

      if (matchesAllTerms(fullName)) {
        results.add({
          'type': 'child',
          'id': child['child_id'],
          'title':
              '${child['first_name'] ?? ''} ${child['last_name'] ?? ''}'.trim(),
          'subtitle': 'Child record',
          'icon': Icons.child_care,
          'matchText': fullName,
        });
      }
    }

    // Search through cached checkups
    for (var checkup in _allCheckups) {
      final pregId = checkup['pregnancy_id'] as int?;
      final mother = pregId != null ? _pregnancyToMotherMap[pregId] : null;
      final motherName = mother != null
          ? '${mother['first_name'] ?? ''} ${mother['last_name'] ?? ''}'.trim()
          : 'Unknown Mother';
      final remarks = (checkup['remarks'] ?? '').toLowerCase();
      final aog = (checkup['age_of_gestation'] ?? '').toString();
      final date = _formatDateTime(checkup['checkup_datetime']);
      final matchText = '$motherName checkup prenatal $remarks $aog $date';

      if (matchesAllTerms(matchText)) {
        results.add({
          'type': 'checkup',
          'id': checkup['prenatal_checkup_id'],
          'motherId': mother != null ? mother['mother_id'] : null,
          'title': 'Prenatal Checkup - $motherName',
          'subtitle': 'AOG: $aog wks | Date: $date',
          'icon': Icons.medical_services,
          'matchText': matchText,
          'record': checkup,
        });
      }
    }

    // Search through cached ultrasounds
    for (var us in _allUltrasounds) {
      final pregId = us['pregnancy_id'] as int?;
      final mother = pregId != null ? _pregnancyToMotherMap[pregId] : null;
      final motherName = mother != null
          ? '${mother['first_name'] ?? ''} ${mother['last_name'] ?? ''}'.trim()
          : 'Unknown Mother';
      final remarks = (us['remarks'] ?? '').toLowerCase();
      final loc = (us['ultrasound_location'] ?? '').toLowerCase();
      final date = _formatDate(us['ultrasound_date']);
      final matchText = '$motherName ultrasound remarks $remarks $loc $date';

      if (matchesAllTerms(matchText)) {
        results.add({
          'type': 'ultrasound',
          'id': us['ultrasound_id'],
          'motherId': mother != null ? mother['mother_id'] : null,
          'title': 'Ultrasound - $motherName',
          'subtitle': 'Date: $date',
          'icon': Icons.monitor_heart,
          'matchText': matchText,
          'record': us,
        });
      }
    }

    // Search through cached lab tests
    for (var lt in _allLabTests) {
      final pregId = lt['pregnancy_id'] as int?;
      final mother = pregId != null ? _pregnancyToMotherMap[pregId] : null;
      final motherName = mother != null
          ? '${mother['first_name'] ?? ''} ${mother['last_name'] ?? ''}'.trim()
          : 'Unknown Mother';
      final remarks = (lt['remarks'] ?? '').toLowerCase();
      final type = (lt['lab_test_type'] ?? '').toLowerCase();
      final date = _formatDate(lt['lab_test_date']);
      final matchText = '$motherName lab test $type remarks $remarks $date';

      if (matchesAllTerms(matchText)) {
        results.add({
          'type': 'labtest',
          'id': lt['lab_test_id'],
          'motherId': mother != null ? mother['mother_id'] : null,
          'title': '${lt['lab_test_type'] ?? 'Lab Test'} - $motherName',
          'subtitle': 'Date: $date',
          'icon': Icons.science,
          'matchText': matchText,
          'record': lt,
        });
      }
    }

    // Sort results by relevance
    results.sort((a, b) {
      final aMatch = (a['matchText'] as String).toLowerCase();
      final bMatch = (b['matchText'] as String).toLowerCase();
      final aExact = aMatch == query;
      final bExact = bMatch == query;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;
      return aMatch.compareTo(bMatch);
    });

    setState(() {
      _searchResults = results;
      _showSearchResults = true;
    });
  }

  Future<void> _loadDashboardData() async {
    if (_allMothers.isEmpty && _recentVisits.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _errorMessage = null;
      });
    }

    try {
      // Get midwife context
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) throw Exception('Not authenticated');

      final contextResult = await SupabaseService.getMidwifeContext(accountId);
      if (!contextResult['success']) {
        throw Exception('Failed to load midwife context');
      }

      final assignedBhcId = contextResult['assigned_bhc_id'] as int?;
      _bhcName = contextResult['bhc_name']?.toString() ?? 'Unknown BHC';

      // Fetch midwife name and mothers list concurrently in 1 parallel roundtrip
      final stage1Results = await Future.wait<dynamic>([
        SupabaseService.client
            .from('accounts')
            .select('first_name, last_name')
            .eq('account_id', accountId)
            .maybeSingle()
            .timeout(const Duration(seconds: 5))
            .catchError((_) => null),
        SupabaseService.client.from('mothers').select('''
          mother_id,
          account_id,
          birthdate,
          assigned_bhc_id,
          accounts!inner (
            account_id,
            first_name,
            last_name,
            phone_number,
            email_address
          )
        ''').eq('assigned_bhc_id', assignedBhcId!).eq('status', 'active')
          .timeout(const Duration(seconds: 8))
          .catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final accountResponse = stage1Results[0] as Map<String, dynamic>?;
      final mothersData = stage1Results[1] as List<dynamic>;

      if (accountResponse != null) {
        _midwifeName =
            '${accountResponse['first_name'] ?? ''} ${accountResponse['last_name'] ?? ''}'
                .trim();
        if (_midwifeName.isEmpty) _midwifeName = 'Midwife';
      }

      _registeredMothers = mothersData.length;
      _motherIds = mothersData.map<int>((m) => m['mother_id'] as int).toList();

      final sortedMothersList = List<Map<String, dynamic>>.from(mothersData);
      sortedMothersList.sort((a, b) => (a['mother_id'] as int).compareTo(b['mother_id'] as int));

      // Load all mothers for search. bhc_patient_id is filled in just below,
      // from the database, once the header has rendered.
      _allMothers = [];
      for (int i = 0; i < sortedMothersList.length; i++) {
        final mother = sortedMothersList[i];
        final account = mother['accounts'];
        if (account != null) {
          final mId = mother['mother_id'] as int;
          _allMothers.add({
            'mother_id': mId,
            'account_id': mother['account_id'],
            'first_name': account['first_name'] ?? '',
            'last_name': account['last_name'] ?? '',
            'phone_number': account['phone_number'] ?? '',
            'email_address': account['email_address'] ?? '',
            'bhc_patient_id': null,
          });
        }
      }

      // Render core dashboard header & stats immediately. Recent visits and the
      // visits chart are still empty at this point, so _detailsLoading keeps
      // them showing a loading state rather than "no records" — those sections
      // only mean "nothing found" once this second stage has finished.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _detailsLoading = true;
        });
      }

      // Never awaited. The analytics section runs its own queries and paints
      // itself when they return, so the rest of the dashboard does not wait on
      // the heaviest thing on the screen.
      _loadAnalytics(assignedBhcId);

      // Started here but awaited below, so it runs alongside the stage-two
      // queries instead of delaying them. It must resolve before recent visits
      // are built, since those render the patient number.
      final patientNumbersFuture = SupabaseService.getPatientNumbersByAccountId(
        _allMothers
            .map((m) => m['account_id'] as int?)
            .whereType<int>()
            .toList(),
        facilityId: assignedBhcId,
      );

      // Get registered children count and load for search
      if (_motherIds.isNotEmpty) {
        // Parallelize initial children and pregnancies queries
        final responses = await Future.wait([
          SupabaseService.client
              .from('children')
              .select('child_id, first_name, last_name, mother_id')
              .inFilter('mother_id', _motherIds)
              .timeout(const Duration(seconds: 8))
              .catchError((e) {
                debugPrint('Dashboard children query note: $e');
                return <Map<String, dynamic>>[];
              }),
          SupabaseService.client
              .from('pregnancies')
              .select('pregnancy_id, mother_id, last_menstrual_period, status')
              .inFilter('mother_id', _motherIds)
              .timeout(const Duration(seconds: 8))
              .catchError((e) {
                debugPrint('Dashboard pregnancies query note: $e');
                return <Map<String, dynamic>>[];
              }),
        ]);

        // Ran concurrently with the batch above. Applied here, before recent
        // visits are assembled, because those rows display the patient number.
        final patientNumbersByAccountId = await patientNumbersFuture;
        if (patientNumbersByAccountId.isNotEmpty) {
          for (final mother in _allMothers) {
            mother['bhc_patient_id'] = SupabaseService.formatPatientNumber(
              patientNumbersByAccountId[mother['account_id'] as int?],
            );
          }
        }

        final childrenResponse = responses[0] as List<dynamic>;
        final allPregnanciesResponse = responses[1] as List<dynamic>;

        _registeredChildren = childrenResponse.length;
        _allChildren = List<Map<String, dynamic>>.from(childrenResponse);

        final pregnanciesResponse = allPregnanciesResponse
            .where((p) => p['status'] == 'ongoing')
            .toList();

        _totalPregnancies = pregnanciesResponse.length;
        final pregnancyIds = pregnanciesResponse
            .map<int>((p) => p['pregnancy_id'] as int)
            .toList();

        final allPregnancyIds = allPregnanciesResponse
            .map<int>((p) => p['pregnancy_id'] as int)
            .toList();

        // Populate _pregnancyToMotherMap
        _pregnancyToMotherMap = {};
        for (var p in allPregnanciesResponse) {
          final mId = p['mother_id'] as int?;
          if (mId != null) {
            final motherInfo = _allMothers.firstWhere(
              (m) => m['mother_id'] == mId,
              orElse: () => {},
            );
            if (motherInfo.isNotEmpty) {
              _pregnancyToMotherMap[p['pregnancy_id'] as int] = motherInfo;
            }
          }
        }

        // Calculate trimesters
        _firstTrimester = 0;
        _secondTrimester = 0;
        _thirdTrimester = 0;

        final now = DateTime.now();
        for (var pregnancy in pregnanciesResponse) {
          final lmp =
              DateTime.tryParse(pregnancy['last_menstrual_period'] ?? '');
          if (lmp != null) {
            final weeks = now.difference(lmp).inDays / 7;
            if (weeks <= 13) {
              _firstTrimester++;
            } else if (weeks <= 27) {
              _secondTrimester++;
            } else {
              _thirdTrimester++;
            }
          }
        }

        // Parallelize clinical fetches
        final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
        final sevenDaysAgoDate = sevenDaysAgo.toIso8601String().split('T')[0];

        final nowTime = DateTime.now();
        final todayStart = DateTime(nowTime.year, nowTime.month, nowTime.day, 0, 0, 0);
        final chartStart = todayStart.subtract(const Duration(days: 6));
        final chartEnd = DateTime(nowTime.year, nowTime.month, nowTime.day, 23, 59, 59);

        List<dynamic> recentCheckups = [];
        List<dynamic> recentUltrasounds = [];
        List<dynamic> recentLabTests = [];
        List<dynamic> chartCheckups = [];
        List<dynamic> checkupsData = [];
        List<dynamic> ultrasoundsData = [];
        List<dynamic> labTestsData = [];

        if (allPregnancyIds.isNotEmpty) {
          final clinicalResponses = await Future.wait([
            // Recent visits
            SupabaseService.client
                .from('clinical_encounters')
                .select('''
                  encounter_datetime,
                  midwife_notes,
                  age_of_gestation_weeks,
                  age_of_gestation_days,
                  is_midwife_approved,
                  recorded_by:midwives (
                    midwife_id,
                    account:accounts (first_name, last_name)
                  ),
                  checkup:prenatal_checkups (
                    prenatal_checkup_id,
                    td_vaccine_dose,
                    pregnancy_id,
                    blood_pressure_systolic,
                    blood_pressure_diastolic,
                    checkup_weight,
                    fetal_position,
                    fetal_heart_tone,
                    fetal_heart_beat,
                    next_schedule
                  )
                ''')
                .inFilter('pregnancy_id', allPregnancyIds)
                .eq('encounter_type', 'checkup')
                .gte('encounter_datetime', sevenDaysAgo.toIso8601String())
                .timeout(const Duration(seconds: 8))
                .catchError((e) {
                  debugPrint('Dashboard recent checkups query note: $e');
                  return <Map<String, dynamic>>[];
                }),
            SupabaseService.client
                .from('ultrasounds')
                .select('encounter_id, ultrasound_date, remarks:findings_summary, monitoring_classification, pregnancy_id, health_worker_name, ultrasound_location, ultrasound_image, health_worker_institution, health_worker_profession')
                .inFilter('pregnancy_id', allPregnancyIds)
                .gte('ultrasound_date', sevenDaysAgoDate)
                .timeout(const Duration(seconds: 8))
                .catchError((e) {
                  debugPrint('Dashboard recent ultrasounds query note: $e');
                  return <Map<String, dynamic>>[];
                }),
            SupabaseService.client
                .from('lab_tests')
                .select('encounter_id, lab_test_type, pregnancy_id, health_worker_name, lab_test_image, health_worker_institution, health_worker_profession, created_at')
                .inFilter('pregnancy_id', allPregnancyIds)
                .gte('created_at', sevenDaysAgo.toIso8601String())
                .timeout(const Duration(seconds: 8))
                .catchError((e) {
                  debugPrint('Dashboard recent lab tests query note: $e');
                  return <Map<String, dynamic>>[];
                }),

            // BHC Chart query (single call for 7 days)
            if (pregnancyIds.isNotEmpty)
              SupabaseService.client
                  .from('clinical_encounters')
                  .select('encounter_datetime')
                  .eq('encounter_type', 'checkup')
                  .gte('encounter_datetime', chartStart.toIso8601String())
                  .lte('encounter_datetime', chartEnd.toIso8601String())
                  .inFilter('pregnancy_id', pregnancyIds)
                  .timeout(const Duration(seconds: 8))
                  .catchError((e) {
                    debugPrint('Dashboard chart query note: $e');
                    return <Map<String, dynamic>>[];
                  })
            else
              Future.value([]),

            // Search records (bounded for fast dashboard load)
            SupabaseService.client
                .from('clinical_encounters')
                .select('''
                  encounter_datetime,
                  midwife_notes,
                  age_of_gestation_weeks,
                  age_of_gestation_days,
                  is_midwife_approved,
                  recorded_by:midwives (
                    midwife_id,
                    account:accounts (first_name, last_name)
                  ),
                  checkup:prenatal_checkups (
                    encounter_id,
                    td_vaccine_dose,
                    pregnancy_id,
                    blood_pressure_systolic,
                    blood_pressure_diastolic,
                    checkup_weight,
                    fetal_position,
                    fetal_heart_tone,
                    fetal_heart_beat,
                    next_schedule
                  )
                ''')
                .inFilter('pregnancy_id', allPregnancyIds)
                .eq('encounter_type', 'checkup')
                .order('encounter_datetime', ascending: false)
                .limit(50)
                .timeout(const Duration(seconds: 8))
                .catchError((e) {
                  debugPrint('Dashboard search checkups query note: $e');
                  return <Map<String, dynamic>>[];
                }),
            SupabaseService.client
                .from('ultrasounds')
                .select('encounter_id, ultrasound_date, remarks:findings_summary, monitoring_classification, pregnancy_id, health_worker_name, ultrasound_location, ultrasound_image, health_worker_institution, health_worker_profession')
                .inFilter('pregnancy_id', allPregnancyIds)
                .order('ultrasound_date', ascending: false)
                .limit(50)
                .timeout(const Duration(seconds: 8))
                .catchError((e) {
                  debugPrint('Dashboard search ultrasounds query note: $e');
                  return <Map<String, dynamic>>[];
                }),
            SupabaseService.client
                .from('lab_tests')
                .select('encounter_id, lab_test_type, pregnancy_id, health_worker_name, lab_test_image, health_worker_institution, health_worker_profession, created_at')
                .inFilter('pregnancy_id', allPregnancyIds)
                .limit(50)
                .timeout(const Duration(seconds: 8))
                .catchError((e) {
                  debugPrint('Dashboard search lab tests query note: $e');
                  return <Map<String, dynamic>>[];
                }),
          ]);

          final List recentCheckupsRaw = clinicalResponses[0];
          recentUltrasounds = (clinicalResponses[1]).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          recentLabTests = (clinicalResponses[2]).map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            map['lab_test_date'] = map['created_at'];
            map['remarks'] = map['lab_test_type'];
            return map;
          }).toList();
          final List chartCheckupsRaw = clinicalResponses[3];
          final List checkupsDataRaw = clinicalResponses[4];
          ultrasoundsData = (clinicalResponses[5]).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          labTestsData = (clinicalResponses[6]).map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            map['lab_test_date'] = map['created_at'];
            map['remarks'] = map['lab_test_type'];
            return map;
          }).toList();

          // Map recentCheckups
          recentCheckups = [];
          for (final enc in recentCheckupsRaw) {
            final innerCheckup = enc['checkup'] as Map<String, dynamic>?;
            if (innerCheckup != null) {
              final double aog = ((enc['age_of_gestation_weeks'] as num?)?.toDouble() ?? 0) +
                  ((enc['age_of_gestation_days'] as num?)?.toDouble() ?? 0) / 7.0;
              recentCheckups.add({
                'prenatal_checkup_id': innerCheckup['encounter_id'] ?? innerCheckup['prenatal_checkup_id'],
                'checkup_datetime': enc['encounter_datetime'],
                'remarks': enc['midwife_notes'],
                'age_of_gestation': aog,
                'td_vaccine_dose': innerCheckup['td_vaccine_dose'],
                'pregnancy_id': innerCheckup['pregnancy_id'],
                'blood_pressure_systolic': innerCheckup['blood_pressure_systolic'],
                'blood_pressure_diastolic': innerCheckup['blood_pressure_diastolic'],
                'checkup_weight': innerCheckup['checkup_weight'],
                'fetal_position': innerCheckup['fetal_position'],
                'fetal_heart_tone': innerCheckup['fetal_heart_tone'],
                'fetal_heart_beat': innerCheckup['fetal_heart_beat'],
                'next_schedule': innerCheckup['next_schedule'],
                'midwife': enc['recorded_by'],
                'is_midwife_approved': enc['is_midwife_approved'],
              });
            }
          }

          // Map chartCheckups
          chartCheckups = chartCheckupsRaw.map((enc) => {
            'checkup_datetime': enc['encounter_datetime'],
          }).toList();

          // Map checkupsData
          checkupsData = [];
          for (final enc in checkupsDataRaw) {
            final innerCheckup = enc['checkup'] as Map<String, dynamic>?;
            if (innerCheckup != null) {
              final double aog = ((enc['age_of_gestation_weeks'] as num?)?.toDouble() ?? 0) +
                  ((enc['age_of_gestation_days'] as num?)?.toDouble() ?? 0) / 7.0;
              checkupsData.add({
                'prenatal_checkup_id': innerCheckup['encounter_id'],
                'checkup_datetime': enc['encounter_datetime'],
                'remarks': enc['midwife_notes'],
                'age_of_gestation': aog,
                'td_vaccine_dose': innerCheckup['td_vaccine_dose'],
                'pregnancy_id': innerCheckup['pregnancy_id'],
                'blood_pressure_systolic': innerCheckup['blood_pressure_systolic'],
                'blood_pressure_diastolic': innerCheckup['blood_pressure_diastolic'],
                'checkup_weight': innerCheckup['checkup_weight'],
                'fetal_position': innerCheckup['fetal_position'],
                'fetal_heart_tone': innerCheckup['fetal_heart_tone'],
                'fetal_heart_beat': innerCheckup['fetal_heart_beat'],
                'next_schedule': innerCheckup['next_schedule'],
                'midwife': enc['recorded_by'],
                'is_midwife_approved': enc['is_midwife_approved'],
              });
            }
          }
        }

        // Process recent visits (based solely on checkups, with optional lab/ultrasound labels)
        _recentVisits = [];
        
        recentCheckups.sort((a, b) {
          final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        for (var checkup in recentCheckups.take(3)) {
          final pregId = checkup['pregnancy_id'] as int?;
          final mother = pregId != null ? _pregnancyToMotherMap[pregId] : null;
          final fullName = mother != null ? '${mother['first_name'] ?? ''} ${mother['last_name'] ?? ''}'.trim() : 'Unknown Mother';
          final motherId = mother != null ? mother['mother_id'] as int? : null;
          final bhcPatientId = mother != null ? mother['bhc_patient_id']?.toString() : null;
          // No mother_id fallback: a missing patient number must look missing,
          // not like a valid number that happens to be wrong.
          final displayId = bhcPatientId ?? '—';

          final dt = DateTime.tryParse(checkup['checkup_datetime']?.toString() ?? '');
          if (dt == null) continue;

          final dateString = checkup['checkup_datetime']?.toString().split('T')[0];

          // Check for matching ultrasound on the same day
          bool hasUltrasound = false;
          for (var us in recentUltrasounds) {
            if (us['pregnancy_id'] == pregId && us['ultrasound_date']?.toString() == dateString) {
              hasUltrasound = true;
              break;
            }
          }

          // Check for matching lab test on the same day
          bool hasLabTest = false;
          for (var lt in recentLabTests) {
            final ltDateStr = lt['lab_test_date']?.toString().split('T')[0];
            if (lt['pregnancy_id'] == pregId && ltDateStr == dateString) {
              hasLabTest = true;
              break;
            }
          }

          final List<String> visitTypeParts = ['Prenatal Check-up'];
          if (hasUltrasound) visitTypeParts.add('Ultrasound Record');
          if (hasLabTest) visitTypeParts.add('Lab Test Result');
          final visitTypeLabel = visitTypeParts.join(', ');

          final diffDays = nowTime.difference(DateTime(dt.year, dt.month, dt.day)).inDays;
          String timeLabel = diffDays == 0 ? 'Today' : (diffDays == 1 ? 'Yesterday' : '$diffDays days ago');

          _recentVisits.add(MidwifeVisitItem(
            name: fullName,
            displayId: displayId,
            visitType: visitTypeLabel,
            timeLabel: timeLabel,
            onTap: () => _navigateToSearchResult({
              'type': 'checkup',
              'id': checkup['prenatal_checkup_id'],
              'motherId': motherId,
              'record': checkup,
            }),
          ));
        }

        // Process BHC Chart checkup counts (last 7 rolling days)
        _bhcVisitValues = List.filled(7, 0.0);
        final List<String> dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        _bhcVisitDays = [];
        for (int i = 0; i < 7; i++) {
          final dayDate = chartStart.add(Duration(days: i));
          final formattedDate = DateFormat('MMM dd').format(dayDate);
          final labelIndex = dayDate.weekday % 7;
          _bhcVisitDays.add('${dayLabels[labelIndex]}\n$formattedDate');
        }

        for (final checkup in chartCheckups) {
          final dt = DateTime.tryParse(checkup['checkup_datetime']?.toString() ?? '');
          if (dt != null) {
            final localDt = dt.toLocal();
            final localDateOnly = DateTime(localDt.year, localDt.month, localDt.day);
            final chartStartOnly = DateTime(chartStart.year, chartStart.month, chartStart.day);
            final diffDays = localDateOnly.difference(chartStartOnly).inDays;
            if (diffDays >= 0 && diffDays < 7) {
              _bhcVisitValues[diffDays] += 1;
            }
          }
        }

        // Process search records
        _allCheckups = List<Map<String, dynamic>>.from(checkupsData);
        _allUltrasounds = List<Map<String, dynamic>>.from(ultrasoundsData);
        _allLabTests = List<Map<String, dynamic>>.from(labTestsData);
      } else {
        _registeredChildren = 0;
        _totalPregnancies = 0;
        _firstTrimester = 0;
        _secondTrimester = 0;
        _thirdTrimester = 0;
        _recentVisits = [];
        _bhcVisitValues = List.filled(7, 0.0);
        _bhcVisitDays = List.generate(7, (i) => '');
        _allCheckups = [];
        _allUltrasounds = [];
        _allLabTests = [];
        _pregnancyToMotherMap = {};
      }

      setState(() {
        _isLoading = false;
        _detailsLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _detailsLoading = false;
        _errorMessage = e.toString();
      });
      if (kDebugMode) {
        print('Error loading dashboard: $e');
      }
    }
  }

  /// Loads the analytics section, out of step with the rest of the dashboard.
  ///
  /// Deliberately not awaited by [_loadDashboardData]: it is the widest fetch
  /// on the screen, and the midwife's caseload header should never be held back
  /// by a stock forecast. A pull-to-refresh part way through an earlier load
  /// would otherwise let the slower response overwrite the newer one, so each
  /// run carries a token and only the newest is allowed to land.
  Future<void> _loadAnalytics(int bhcId) async {
    final int requestId = ++_analyticsRequestId;

    if (mounted) setState(() => _analyticsLoading = true);

    final analytics = await MidwifeAnalyticsService.load(bhcId: bhcId);

    if (!mounted || requestId != _analyticsRequestId) return;
    setState(() {
      _analytics = analytics;
      _analyticsLoading = false;
    });
  }

  /// Sends the midwife where a card's action says she should go.
  ///
  /// Mothers, children and schedules are tabs of [MidwifeShell], so they are
  /// reached by switching tabs, not by pushing their routes. Pushing put a bare
  /// screen over the shell: no header, no navigation bar, and no way back
  /// except the system gesture.
  ///
  /// Inventory is genuinely a separate destination — it is not a tab and brings
  /// its own header — so that one is still pushed.
  ///
  /// Screens, not deep links with filters: the destinations already carry their
  /// own search and sorting, and a prescription that lands somewhere she can
  /// work is worth more than one that promises a filter this screen cannot set.
  void _onAnalyticsAction(AnalyticsAction action) {
    switch (action) {
      case AnalyticsAction.viewMothers:
        _goToTab(MidwifeShell.mothersTab, '/midwife-mothers');
        break;
      case AnalyticsAction.viewChildren:
        _goToTab(MidwifeShell.childrenTab, '/midwife-children');
        break;
      case AnalyticsAction.viewSchedules:
        _goToTab(MidwifeShell.schedulesTab, '/midwife-schedules');
        break;
      case AnalyticsAction.viewInventory:
        Navigator.pushNamed(context, '/midwife-inventory');
        break;
      case AnalyticsAction.none:
        break;
    }
  }

  /// Switches the shell to [tabIndex], falling back to the route when the
  /// dashboard is shown outside the shell and has no tabs to switch.
  void _goToTab(int tabIndex, String fallbackRoute) {
    final navigateToTab = widget.onNavigateToTab;
    if (navigateToTab != null) {
      navigateToTab(tabIndex);
    } else {
      Navigator.pushNamed(context, fallbackRoute);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _showSearchResults = false;
      _searchResults = [];
    });
    FocusScope.of(context).unfocus();
  }

  void _navigateToSearchResult(Map<String, dynamic> result) async {
    _clearSearch();
    if (result['type'] == 'mother') {
      await Navigator.pushNamed(context, '/mother-profile', arguments: result['id']);
      if (mounted) _loadDashboardData();
    } else if (result['type'] == 'child') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChildProfilePage(childId: result['id']),
        ),
      );
      if (mounted) _loadDashboardData();
    } else if (result['type'] == 'checkup') {
      final record = result['record'] as Map<String, dynamic>;
      final checkupId = result['id'] as int;
      final motherId = result['motherId'] as int?;

      if (motherId == null) return;

      _showLoadingOverlay();

      try {
        final checkupDetails = await _fetchCheckupDetailsForSearch(
            checkupId, record['checkup_datetime'], motherId);
        String? aiAnalysis = checkupDetails?['aiResponse'] as String?;
        String? riskLevel = checkupDetails?['riskLevel'] as String?;
        String riskFactors = checkupDetails?['riskFactors'] ?? '';
        String medicationPlansSummary =
            checkupDetails?['medicationPlans'] ?? 'None';
        String givenMedicationsSummary =
            checkupDetails?['givenMedications'] ?? 'None';
        String ferrousSummary =
            checkupDetails?['ferrousQuantity'] ?? 'Not given';
        String calciumSummary =
            checkupDetails?['calciumQuantity'] ?? 'Not given';
        String symptomSummary =
            checkupDetails?['symptomSummary'] ?? 'None recorded';

        if (aiAnalysis == null || aiAnalysis.trim().isEmpty) {
          aiAnalysis =
              await MotherProfileService.getCheckupAIAnalysis(checkupId);
        }

        if (aiAnalysis == null || aiAnalysis.trim().isEmpty) {
          aiAnalysis = _generatePrenatalAIInsights(record);
        } else {
          aiAnalysis = aiAnalysis.trim();
        }

        final date = _formatDateTime(record['checkup_datetime']);
        final bpSys = _formatValue(record['blood_pressure_systolic']);
        final bpDia = _formatValue(record['blood_pressure_diastolic']);
        final aog = _formatValue(record['age_of_gestation']);
        final weight = _formatValue(record['checkup_weight']);

        double? height;
        try {
          final response = await SupabaseService.client
              .from('mothers')
              .select('height')
              .eq('mother_id', motherId)
              .maybeSingle();
          if (response != null) {
            height = double.tryParse(response['height']?.toString() ?? '');
          }
        } catch (_) {}

        final heightText =
            height == null ? 'Not recorded' : '${height.toStringAsFixed(1)} cm';
        String bmiText = '—';
        String bmiStatus = '—';
        try {
          final w = double.tryParse(record['checkup_weight']?.toString() ?? '');
          if (w != null && height != null && height > 0) {
            final hm = height / 100;
            final bmi = w / (hm * hm);
            bmiText = bmi.toStringAsFixed(1);
            if (bmi < 18.5) {
              bmiStatus = 'Underweight';
            } else if (bmi < 25) {
              bmiStatus = 'Normal';
            } else if (bmi < 30) {
              bmiStatus = 'Overweight';
            } else {
              bmiStatus = 'Obese';
            }
          }
        } catch (_) {}

        int fetalCount = 1;
        try {
          final response = await SupabaseService.client
              .from('pregnancies')
              .select('fetal_count')
              .eq('pregnancy_id', record['pregnancy_id'])
              .maybeSingle();
          if (response != null) {
            fetalCount =
                int.tryParse(response['fetal_count']?.toString() ?? '1') ?? 1;
          }
        } catch (_) {}

        _closeLoadingOverlay();

        if (!mounted) return;

        String midwifeName = '—';
        if (record['midwife'] != null) {
          final mw = record['midwife'] as Map<String, dynamic>;
          final acc = mw['account'] as Map<String, dynamic>?;
          if (acc != null) {
            midwifeName = '${acc['first_name'] ?? ''} ${acc['last_name'] ?? ''}'.trim();
          }
        }

        _showRecordDetails(
          title: 'Prenatal Checkup',
          subtitle: date,
          icon: Icons.medical_services,
          approvedByName: midwifeName == '—' ? null : midwifeName,
          isMidwifeApproved: record['is_midwife_approved'] == true,
          rows: [
            MapEntry('Conducted by', midwifeName),
            MapEntry('Fetal Count', fetalCount.toString()),
            MapEntry('Age of Gestation', aog),
            MapEntry('Weight (kg)', weight),
            MapEntry('Height', heightText),
            MapEntry('BMI', bmiText),
            MapEntry('BMI Status', bmiStatus),
            MapEntry('Blood Pressure', '$bpSys/$bpDia'),
            MapEntry('Fetal Position', _formatValue(record['fetal_position'])),
            MapEntry(
                'Fetal Heart Tone', _formatValue(record['fetal_heart_tone'])),
            MapEntry(
                'Fetal Heart Beat', _formatValue(record['fetal_heart_beat'])),
            MapEntry('Symptoms', symptomSummary),
            MapEntry('Medication Plans', medicationPlansSummary),
            MapEntry('Given Medications', givenMedicationsSummary),
            MapEntry('Ferrous + FA', ferrousSummary),
            MapEntry('Calcium', calciumSummary),
            MapEntry('TD Vaccine', _formatValue(record['td_vaccine_dose'])),
            MapEntry('Edema', _formatValue(record['edema'])),
            MapEntry('Remarks', _formatValue(record['remarks'])),
            MapEntry('Next Schedule', _formatDate(record['next_schedule'])),
          ],
          aiAnalysis: aiAnalysis,
          riskLevel: riskLevel,
          riskFactors: riskFactors,
        );
      } catch (e) {
        _closeLoadingOverlay();
        _showMessage('Failed to load checkup details',
            type: AppSnackType.error);
      }
    } else if (result['type'] == 'ultrasound') {
      final record = result['record'] as Map<String, dynamic>;
      final ultrasoundId = result['id'] as int;

      _showLoadingOverlay();

      try {
        List<String> imageUrls = [];
        if (record['ultrasound_image'] != null) {
          final imageField = record['ultrasound_image'].toString();
          if (imageField.contains(',')) {
            imageUrls = imageField.split(',').map((url) => url.trim()).toList();
          } else if (imageField.isNotEmpty) {
            imageUrls = [imageField];
          }
        }

        final split = _splitRemarksAndAi(record['remarks']?.toString());
        String? aiAnalysis =
            await MotherProfileService.getUltrasoundAIAnalysis(ultrasoundId);

        String finalRemarks = split.cleanRemarks;
        if (aiAnalysis != null && aiAnalysis.trim() == finalRemarks.trim()) {
          finalRemarks = '';
        }

        aiAnalysis = (aiAnalysis != null && aiAnalysis.trim().isNotEmpty)
            ? aiAnalysis.trim()
            : split.extractedAi ?? _generateUltrasoundAIInsights(record);

        final date = _formatDate(record['ultrasound_date']);

        _closeLoadingOverlay();

        if (!mounted) return;

        _showRecordDetails(
          title: 'Ultrasound',
          subtitle: date,
          icon: Icons.monitor_heart,
          imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
          rows: [
            MapEntry('Ultrasound Date', _formatDate(record['ultrasound_date'])),
            MapEntry('Location', _formatValue(record['ultrasound_location'])),
            MapEntry('Full Name', _formatValue(record['health_worker_name'])),
            MapEntry('Institution',
                _formatValue(record['health_worker_institution'])),
            MapEntry(
                'Profession', _formatValue(record['health_worker_profession'])),
            MapEntry('Remarks', _formatValue(finalRemarks)),
          ],
          aiAnalysis: aiAnalysis,
          useStructuredAiInsights: aiAnalysis.isNotEmpty,
          ultrasoundClassification:
              record['monitoring_classification']?.toString(),
        );
      } catch (e) {
        _closeLoadingOverlay();
        _showMessage('Failed to load ultrasound details',
            type: AppSnackType.error);
      }
    } else if (result['type'] == 'labtest') {
      final record = result['record'] as Map<String, dynamic>;
      final labTestId = result['id'] as int;

      _showLoadingOverlay();

      try {
        List<String> imageUrls = [];
        if (record['lab_test_image'] != null) {
          final imageField = record['lab_test_image'].toString();
          if (imageField.contains(',')) {
            imageUrls = imageField.split(',').map((url) => url.trim()).toList();
          } else if (imageField.isNotEmpty) {
            imageUrls = [imageField];
          }
        }

        final split = _splitRemarksAndAi(record['remarks']?.toString());
        String? aiAnalysis =
            await MotherProfileService.getLabTestAIAnalysis(labTestId);

        aiAnalysis = (aiAnalysis != null && aiAnalysis.trim().isNotEmpty)
            ? aiAnalysis.trim()
            : split.extractedAi;

        final date = _formatDate(record['lab_test_date']);
        final type = record['lab_test_type'] ?? 'Lab Test';

        _closeLoadingOverlay();

        if (!mounted) return;

        _showRecordDetails(
          title: type,
          subtitle: date,
          icon: Icons.science,
          imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
          rows: [
            MapEntry('Lab Test Type', type),
            MapEntry('Lab Test Date', _formatDate(record['lab_test_date'])),
            MapEntry('Full Name', _formatValue(record['health_worker_name'])),
            MapEntry('Institution',
                _formatValue(record['health_worker_institution'])),
            MapEntry(
                'Profession', _formatValue(record['health_worker_profession'])),
            MapEntry('Notes', _formatValue(split.cleanRemarks)),
          ],
          aiAnalysis: aiAnalysis,
          useStructuredAiInsights: aiAnalysis != null && aiAnalysis.isNotEmpty,
        );
      } catch (e) {
        _closeLoadingOverlay();
        _showMessage('Failed to load lab test details',
            type: AppSnackType.error);
      }
    }
  }

  void _showLoadingOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
          ),
        );
      },
    );
  }

  void _closeLoadingOverlay() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showMessage(String message,
      {AppSnackType type = AppSnackType.warning}) {
    AppSnackbar.show(context, message, type: type);
  }

  String _formatDate(dynamic dateString) {
    if (dateString == null) return '—';
    try {
      final date = DateTime.parse(dateString.toString());
      return DateFormat('MMMM d, yyyy').format(date);
    } catch (_) {
      return dateString.toString();
    }
  }

  String _formatDateTime(dynamic dateString) {
    if (dateString == null) return '—';
    try {
      final date = DateTime.parse(dateString.toString());
      return DateFormat('MMMM d, yyyy h:mm a').format(date);
    } catch (_) {
      return dateString.toString();
    }
  }

  String _formatValue(dynamic val) {
    if (val == null) return '—';
    final s = val.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  ({String cleanRemarks, String? extractedAi}) _splitRemarksAndAi(
      String? rawRemarks) {
    final source = rawRemarks?.trim() ?? '';
    if (source.isEmpty) {
      return (cleanRemarks: '', extractedAi: null);
    }

    final marker = RegExp(r'\bAI\s*Analysis\s*:', caseSensitive: false);
    final match = marker.firstMatch(source);
    if (match == null) {
      return (cleanRemarks: source, extractedAi: null);
    }

    final notesPart = source.substring(0, match.start).trim();
    final aiPart = source.substring(match.end).trim();
    return (
      cleanRemarks: notesPart,
      extractedAi: aiPart.isEmpty ? null : aiPart,
    );
  }

  String _generateUltrasoundAIInsights(Map<String, dynamic> ultrasound) {
    final remarks = ultrasound['remarks']?.toString().toLowerCase() ?? '';
    final buffer = StringBuffer();

    buffer.write('Ultrasound AI Insights:\n\n');

    if (remarks.contains('normal') || remarks.contains('healthy')) {
      buffer.write(
          'Normal Findings: Ultrasound appears normal with healthy fetal development.\n\n');
    } else if (remarks.contains('follow') || remarks.contains('monitor')) {
      buffer.write(
          'Follow-up Recommended: Some findings require additional observation.\n\n');
    } else if (remarks.contains('concern') || remarks.contains('abnormal')) {
      buffer.write(
          'Further Evaluation Needed: Discuss findings with healthcare provider.\n\n');
    } else {
      buffer.write(
          'Diagnostic Information: The ultrasound provides important diagnostic information.\n\n');
    }

    buffer.write('Key Recommendations:\n');
    buffer.write('• Discuss findings with your healthcare provider\n');
    buffer.write('• Continue all scheduled prenatal appointments\n');

    return buffer.toString();
  }

  String _generatePrenatalAIInsights(Map<String, dynamic> checkup) {
    final remarks = checkup['remarks']?.toString().toLowerCase() ?? '';
    final buffer = StringBuffer();

    buffer.write('Prenatal AI Insights:\n\n');

    if (remarks.contains('normal') || remarks.contains('healthy')) {
      buffer.write(
          'Prenatal Status: Check-up metrics appear normal and within expected clinical limits.\n\n');
    } else if (remarks.contains('high') ||
        remarks.contains('risk') ||
        remarks.contains('warning')) {
      buffer.write(
          'Risk Assessment: Borderline metrics or physical symptoms require careful clinical correlation.\n\n');
    } else {
      buffer.write(
          'Diagnostic Context: Check-up results provide important standard tracking data.\n\n');
    }

    buffer.write('Clinical Notes:\n');
    buffer.write('• Correlate findings with recent maternal vitals\n');
    buffer.write('• Advise adherence to standard prenatal guidelines\n');

    return buffer.toString();
  }

  void _showRecordDetails({
    required String title,
    required List<MapEntry<String, String>> rows,
    IconData icon = Icons.receipt_long,
    String? subtitle,
    List<String>? imageUrls,
    String? aiAnalysis,
    bool useStructuredAiInsights = false,
    String? riskLevel,
    String? riskFactors,
    List<String>? suggestedActions,
    Map<String, dynamic>? weightGainEval,
    String? ultrasoundClassification,
    String? approvedByName,
    bool? isMidwifeApproved,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordDetailScreen(
          approvedByName: approvedByName,
          isMidwifeApproved: isMidwifeApproved,
          title: title,
          rows: rows,
          icon: icon,
          subtitle: subtitle,
          imageUrls: imageUrls,
          aiAnalysis: aiAnalysis,
          useStructuredAiInsights: useStructuredAiInsights,
          riskLevel: (riskLevel != null && riskLevel.trim().isNotEmpty)
              ? riskLevel
              : null,
          riskFactors: (riskFactors != null && riskFactors.trim().isNotEmpty)
              ? riskFactors.split(';').map((s) => s.trim()).toList()
              : null,
          suggestedActions: suggestedActions,
          weightGainEval: weightGainEval,
          ultrasoundClassification: ultrasoundClassification,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchCheckupDetailsForSearch(
      int prenatalCheckupId, dynamic checkupDateTime, int motherId) async {
    try {
      final aiRow = await SupabaseService.client
          .from('ai_responses')
          .select('ai_response_id, response')
          .eq('reference_table', 'prenatal_checkups')
          .eq('reference_id', prenatalCheckupId)
          .eq('response_type', 'risk_assessment')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      String? aiResponse = aiRow?['response'] as String?;
      String? riskLevel;
      String riskFactors = '';
      String medicationPlans = 'None';
      String givenMedications = 'None';
      String ferrousQuantity = 'Not given';
      String calciumQuantity = 'Not given';

      if (aiRow != null) {
        final aiResponseId = aiRow['ai_response_id'] != null
            ? int.tryParse(aiRow['ai_response_id'].toString())
            : null;
        if (aiResponseId != null) {
          final riskRow = await SupabaseService.client
              .from('pregnancy_risk_assessments')
              .select('pregnancy_risk_id, risk_level')
              .eq('ai_response_id', aiResponseId)
              .maybeSingle();

          if (riskRow != null) {
            riskLevel = riskRow['risk_level']?.toString();
            final factorRows = await SupabaseService.client
                .from('pregnancy_risk_factors')
                .select('factor, risk_influence')
                .eq('pregnancy_risk_id', riskRow['pregnancy_risk_id'])
                .order('risk_factor_id', ascending: true);

            final factorList = <String>[];
            for (final factor
                in (factorRows as List).cast<Map<String, dynamic>>()) {
              final factorText = factor['factor']?.toString() ?? '';
              final influence = factor['risk_influence']?.toString() ?? '';
              if (factorText.isNotEmpty) {
                factorList.add(
                    '$factorText${influence.isNotEmpty ? ' ($influence)' : ''}');
              }
            }
            riskFactors = factorList.join('; ');
          }
        }
      }

      if (checkupDateTime != null) {
        final date = DateTime.tryParse(checkupDateTime.toString());
        final checkupDateString =
            date != null ? date.toIso8601String().split('T')[0] : null;
        if (checkupDateString != null) {
          final givenRows = await SupabaseService.client
              .from('given_medications')
              .select('given_medication_name, quantity')
              .eq('mother_id', motherId)
              .eq('date_given', checkupDateString);

          final medicationRows = await SupabaseService.client
              .from('mother_medications')
              .select(
                  'mother_medication_name, quantity, frequency, start_date, end_date')
              .eq('mother_id', motherId)
              .eq('start_date', checkupDateString);

          final givenItems = <String>[];
          for (final row in (givenRows as List).cast<Map<String, dynamic>>()) {
            final name = row['given_medication_name']?.toString() ?? 'Unknown';
            final quantity = row['quantity']?.toString() ?? '1';
            givenItems.add('$name x$quantity');
            if (name.toLowerCase().contains('ferrous')) {
              ferrousQuantity = quantity;
            }
            if (name.toLowerCase().contains('calcium')) {
              calciumQuantity = quantity;
            }
          }
          if (givenItems.isNotEmpty) givenMedications = givenItems.join('; ');

          final planItems = <String>[];
          for (final row
              in (medicationRows as List).cast<Map<String, dynamic>>()) {
            final name = row['mother_medication_name']?.toString() ?? 'Unknown';
            final qty = row['quantity']?.toString() ?? '1';
            final freq = row['frequency']?.toString();
            final start = row['start_date']?.toString();
            final end = row['end_date']?.toString();
            final details = [
              qty != 'null' ? 'Qty $qty' : null,
              freq,
              start != null ? 'Start $start' : null,
              end != null ? 'End $end' : null,
            ].whereType<String>().join(' · ');
            planItems.add('$name${details.isNotEmpty ? ' ($details)' : ''}');
          }
          if (planItems.isNotEmpty) medicationPlans = planItems.join('; ');
        }
      }

      String symptomSummaryStr = 'None recorded';
      try {
        final symRows = await SupabaseService.client
            .from('pregnancy_symptoms')
            .select(
                'symptom_type_id, notes, symptom_type:symptom_types(symptom_name, risk_category)')
            .eq('encounter_id', prenatalCheckupId);

        if ((symRows as List).isNotEmpty) {
          final items = <String>[];
          for (final row in symRows.cast<Map<String, dynamic>>()) {
            final symptomType = row['symptom_type'] as Map<String, dynamic>?;
            final symName =
                symptomType?['symptom_name']?.toString() ?? 'Unknown symptom';
            final risk = symptomType?['risk_category']?.toString() ?? 'unknown';
            final note = (row['notes'] as String?)?.trim();
            items.add(note != null && note.isNotEmpty
                ? '$symName ($risk): $note'
                : '$symName ($risk)');
          }
          symptomSummaryStr = items.join('; ');
        }
      } catch (_) {}

      return {
        'aiResponse': aiResponse,
        'riskLevel': riskLevel,
        'riskFactors': riskFactors,
        'medicationPlans': medicationPlans,
        'givenMedications': givenMedications,
        'ferrousQuantity': ferrousQuantity,
        'calciumQuantity': calciumQuantity,
        'symptomSummary': symptomSummaryStr,
      };
    } catch (_) {
      return null;
    }
  }

  String _getWelcomeMessage() {
    return 'Welcome, ${_midwifeName.split(' ').first}! 🌸';
  }

  /// Placeholder for a dashboard section whose data is still loading.
  ///
  /// Matches the empty-state card's shape so the layout does not jump when the
  /// real content arrives.
  Widget _buildSectionLoadingCard(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  String _getChartInsight() {
    int maxIndex = 0;
    int maxValue = 0;
    for (int i = 0; i < _bhcVisitValues.length; i++) {
      if (_bhcVisitValues[i] > maxValue) {
        maxValue = _bhcVisitValues[i].toInt();
        maxIndex = i;
      }
    }

    final List<String> fullDays = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ];
    final bestDay = fullDays[maxIndex];

    if (maxValue == 0) {
      return 'No visits recorded this week.';
    } else {
      return '$bestDay had the most visits';
    }
  }

  Widget _buildStatCard({
    required int value,
    required String label,
    required IconData iconData,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: AppColors.borderOf(context),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconData,
              color: AppColors.brandPrimary,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// The analytics block: one group of cards at a time.
  ///
  /// The switcher is the whole reason this fits on a phone. Mothers, children
  /// and supplies are three different questions, and a midwife asking one of
  /// them should not have to scroll past the other two to finish reading.
  List<Widget> _buildAnalyticsSection() {
    final sections = _analytics.sections;
    final tabIndex = _analyticsTab.clamp(0, sections.length - 1);
    final metrics = sections[tabIndex].metrics;

    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.insights, color: AppColors.brandPrimary, size: 22),
          SizedBox(width: 8),
          Text(
            'Analytics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      AnalyticsSegmentedControl(
        labels: [for (final section in sections) section.title],
        selectedIndex: tabIndex,
        onChanged: (index) => setState(() => _analyticsTab = index),
      ),
      const SizedBox(height: 16),
      if (_analyticsLoading && _analytics.isEmpty)
        _buildSectionLoadingCard('Reading this month\'s records...')
      else if (metrics.isEmpty)
        AnalyticsCard(
          metric: AnalyticsMetric.empty(
            title: sections[tabIndex].title,
            message: 'Nothing to analyse here yet. Cards appear as records '
                'are added at this health centre.',
          ),
        )
      else
        for (int i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          AnalyticsCard(
            metric: metrics[i],
            onAction: _onAnalyticsAction,
          ),
        ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimaryOf(context),
      body: SafeArea(
        top: false,
        bottom: false,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Failed to load dashboard',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadDashboardData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadDashboardData,
                    color: AppColors.brandPrimary,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),

                          // Cozy & Professional Welcome Header Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.cardColorOf(context),
                                  AppColors.bgSecondaryOf(context),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.brandPrimary.withValues(alpha: 0.05),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _getWelcomeMessage(),
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF5A5A5A),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppColors.brandPrimary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.location_on_rounded,
                                                  size: 14,
                                                  color: AppColors.brandPrimary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _bhcName,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.brandPrimary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      height: 64,
                                      width: 64,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.brandPrimary.withValues(alpha: 0.2),
                                          width: 3,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.brandPrimary.withValues(alpha: 0.15),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: ClipOval(
                                        child: Image.asset(
                                          'assets/images/midwife.png',
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Icon(
                                            Icons.person,
                                            size: 36,
                                            color: AppColors.brandPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Global Search Bar
                                AppInputField(
                                  controller: _searchController,
                                  hintText: 'Search mothers, children, check-ups...',
                                  leadingIcon: Icons.search,
                                  trailingIcon: _searchController.text.isNotEmpty
                                      ? Icons.clear
                                      : null,
                                  onTrailingTap: _clearSearch,
                                ),
                              ],
                            ),
                          ),

                          // Search Results
                          if (_showSearchResults &&
                              _searchResults.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.cardColorOf(context),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text(
                                      'Search Results',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Divider(
                                      height: 1,
                                      color: AppColors.borderPrimary),
                                  ..._searchResults.map((result) => ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: AppColors
                                              .brandPrimary
                                              .withValues(alpha: 0.1),
                                          child: Icon(result['icon'],
                                              color: AppColors.brandPrimary),
                                        ),
                                        title: Text(
                                          result['title'],
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w500),
                                        ),
                                        subtitle: Text(
                                          result['subtitle'],
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: const Icon(
                                            Icons.chevron_right,
                                            size: 20),
                                        onTap: () =>
                                            _navigateToSearchResult(result),
                                      )),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ] else if (_showSearchResults &&
                              _searchResults.isEmpty &&
                              _searchController.text.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.cardColorOf(context),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.search_off,
                                        size: 48,
                                        color:
                                            AppColors.textSecondaryOf(context)),
                                    SizedBox(height: 12),
                                    Text(
                                      'No results found',
                                      style: TextStyle(
                                          color: AppColors.textSecondary),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Try a different search term',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          const SizedBox(height: 20),

                          // What needs doing, before what has happened. The
                          // numbers further down describe the caseload; this
                          // is the part of the screen she can act on today.
                          AnalyticsPriorityBoard(
                            priorities: _analytics.priorities,
                            isLoading: _analyticsLoading,
                            onAction: _onAnalyticsAction,
                          ),

                          const SizedBox(height: 24),

                          // Health Center Overview Title
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.local_hospital,
                                  color: AppColors.brandPrimary, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Health Center Overview',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Quick Overview
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  value: _registeredChildren,
                                  label: 'Registered\nChildren',
                                  iconData: Icons.child_care,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  value: _registeredMothers,
                                  label: 'Registered\nMothers',
                                  iconData: Icons.pregnant_woman,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  value: _rhuVisitsThisWeek,
                                  label: 'RHU Visits\nThis week',
                                  iconData: Icons.medical_services,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Active Pregnancies Card
                          MidwifeStatisticsCard(
                            totalPregnancies: _totalPregnancies,
                            firstTrimester: _firstTrimester,
                            secondTrimester: _secondTrimester,
                            thirdTrimester: _thirdTrimester,
                          ),

                          const SizedBox(height: 20),

                          // Recent Visits
                          if (_recentVisits.isNotEmpty)
                            MidwifeHistoryCard(
                              visits: _recentVisits,
                            )
                          else if (_detailsLoading)
                            _buildSectionLoadingCard('Loading recent visits...')
                          else
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.cardColorOf(context),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.borderOf(context)),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 48,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'No recent visits',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimaryOf(context),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Checkups in the last 7 days will appear here',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 20),

                          // BHC Visits Chart
                          if (_bhcVisitValues.any((v) => v > 0))
                            ChartCard(
                              title: 'BHC Visits Chart',
                              titleColor: AppColors.brandPrimary,
                              headerIcon: null,
                              values: _bhcVisitValues,
                              labels: _bhcVisitDays,
                              unit: 'visits',
                              lineColor: AppColors.brandPrimary,
                              startingLabel: null,
                              startingValue: null,
                              latestLabel: null,
                              latestValue: null,
                              insightText: _getChartInsight(),
                            )
                          else if (_detailsLoading)
                            _buildSectionLoadingCard('Loading visit data...')
                          else
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.cardColorOf(context),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.borderOf(context)),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.show_chart,
                                    size: 48,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'No visit data available',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimaryOf(context),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Visits in the last 7 days will appear here',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 28),

                          // Analytics sits last on purpose. Above it is what
                          // happened — caseload, recent visits, this week's
                          // chart. This is the part she scrolls to when she
                          // wants to know why, and it replaced three tiles
                          // counting every Ferrous, Calcium and TD dose ever
                          // recorded: totals that only ever rose, and so could
                          // never show a gap.
                          ..._buildAnalyticsSection(),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
