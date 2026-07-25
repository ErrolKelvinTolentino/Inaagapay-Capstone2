// lib/screens/midwife/midwife_dashboard.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';
import '../../widgets/midwife_statistics_card.dart';
import '../../widgets/midwife_history_card.dart';
import '../../widgets/chart_card.dart';
import 'child_profile_page.dart';
import '../mother/mother_profile_page.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_snackbar.dart';
import '../shared/record_detail_screen.dart';
import '../../services/mother_profile_service.dart';

class MidwifeDashboard extends StatefulWidget {
  const MidwifeDashboard({super.key});

  @override
  State<MidwifeDashboard> createState() => _MidwifeDashboardState();
}

class _MidwifeDashboardState extends State<MidwifeDashboard> {
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Dashboard data
  int _registeredMothers = 0;
  int _registeredChildren = 0;
  int _ferrousGiven = 0;
  int _calciumGiven = 0;
  int _tdDosesGiven = 0;

  // Pregnancy statistics
  int _totalPregnancies = 0;
  int _firstTrimester = 0;
  int _secondTrimester = 0;
  int _thirdTrimester = 0;

  // Recent visits
  List<MidwifeVisitItem> _recentVisits = [];

  // Priority Tasks
  List<PriorityTask> _priorityTasks = [];

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
  List<double> _bhcVisitValues = [0, 0, 0, 0, 0, 0, 0];
  final List<String> _bhcVisitDays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun'
  ];

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
    _loadDashboardData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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

      // Get midwife name from accounts
      final accountResponse = await SupabaseService.client
          .from('accounts')
          .select('first_name, last_name')
          .eq('account_id', accountId)
          .maybeSingle();

      if (accountResponse != null) {
        _midwifeName =
            '${accountResponse['first_name'] ?? ''} ${accountResponse['last_name'] ?? ''}'
                .trim();
        if (_midwifeName.isEmpty) _midwifeName = 'Midwife';
      }

      if (assignedBhcId == null) {
        throw Exception('No BHC assigned to this midwife');
      }

      // Get registered mothers for this BHC
      final mothersData =
          await SupabaseService.client.from('mothers').select('''
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
          ''').eq('assigned_bhc_id', assignedBhcId).eq('status', 'active');

      _registeredMothers = mothersData.length;
      _motherIds = mothersData.map<int>((m) => m['mother_id'] as int).toList();

      // Load all mothers for search
      _allMothers = [];
      for (var mother in mothersData) {
        final account = mother['accounts'];
        if (account != null) {
          _allMothers.add({
            'mother_id': mother['mother_id'],
            'first_name': account['first_name'] ?? '',
            'last_name': account['last_name'] ?? '',
            'phone_number': account['phone_number'] ?? '',
            'email_address': account['email_address'] ?? '',
          });
        }
      }

      // Get registered children count and load for search
      if (_motherIds.isNotEmpty) {
        // Parallelize initial children and pregnancies queries
        final responses = await Future.wait([
          SupabaseService.client.from('children').select('child_id, first_name, last_name, mother_id').inFilter('mother_id', _motherIds),
          SupabaseService.client.from('pregnancies').select('pregnancy_id, mother_id, last_menstrual_period, status').inFilter('mother_id', _motherIds),
        ]);

        final childrenResponse = responses[0] as List<dynamic>;
        final allPregnanciesResponse = responses[1] as List<dynamic>;

        _registeredChildren = childrenResponse.length;
        _allChildren = List<Map<String, dynamic>>.from(childrenResponse);

        // Get medication statistics defensively
        try {
          final ferrousResponse = await SupabaseService.client
              .from('given_medications')
              .select('given_medication_id')
              .eq('given_medication_name', 'Ferrous FA')
              .inFilter('mother_id', _motherIds);
          _ferrousGiven = ferrousResponse.length;
        } catch (e) {
          if (kDebugMode) debugPrint('Error fetching Ferrous: $e');
          _ferrousGiven = 0;
        }

        try {
          final calciumResponse = await SupabaseService.client
              .from('given_medications')
              .select('given_medication_id')
              .eq('given_medication_name', 'Calcium')
              .inFilter('mother_id', _motherIds);
          _calciumGiven = calciumResponse.length;
        } catch (e) {
          if (kDebugMode) debugPrint('Error fetching Calcium: $e');
          _calciumGiven = 0;
        }

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

        List<dynamic> recentCheckups = [];
        List<dynamic> recentUltrasounds = [];
        List<dynamic> recentLabTests = [];
        List<dynamic> tdResponse = [];
        List<dynamic> chartCheckups = [];
        List<dynamic> checkupsData = [];
        List<dynamic> ultrasoundsData = [];
        List<dynamic> labTestsData = [];

        if (allPregnancyIds.isNotEmpty) {
          final clinicalResponses = await Future.wait([
            // TD Vaccine doses
            if (pregnancyIds.isNotEmpty)
              SupabaseService.client
                  .from('clinical_encounters')
                  .select('prenatal_checkups!inner(prenatal_checkup_id)')
                  .inFilter('pregnancy_id', pregnancyIds)
                  .eq('encounter_type', 'checkup')
                  .not('prenatal_checkups.td_vaccine_dose', 'is', null)
            else
              Future.value([]),

            // Recent visits
            SupabaseService.client
                .from('clinical_encounters')
                .select('''
                  encounter_datetime,
                  midwife_notes,
                  age_of_gestation_weeks,
                  age_of_gestation_days,
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
                .gte('encounter_datetime', sevenDaysAgo.toIso8601String()),
            SupabaseService.client
                .from('ultrasounds')
                .select('encounter_id, ultrasound_date, remarks:findings_summary, monitoring_classification, pregnancy_id, health_worker_name, ultrasound_location, ultrasound_image, health_worker_institution, health_worker_profession')
                .inFilter('pregnancy_id', allPregnancyIds)
                .gte('ultrasound_date', sevenDaysAgoDate),
            SupabaseService.client
                .from('lab_tests')
                .select('encounter_id, lab_test_type, pregnancy_id, health_worker_name, lab_test_image, health_worker_institution, health_worker_profession, encounter:clinical_encounters!inner(encounter_datetime, midwife_notes)')
                .inFilter('pregnancy_id', allPregnancyIds)
                .gte('encounter.encounter_datetime', sevenDaysAgo.toIso8601String()),

            // BHC Chart query (single call for 7 days)
            if (pregnancyIds.isNotEmpty)
              SupabaseService.client
                  .from('clinical_encounters')
                  .select('encounter_datetime')
                  .eq('encounter_type', 'checkup')
                  .gte('encounter_datetime', sevenDaysAgo.toIso8601String())
                  .inFilter('pregnancy_id', pregnancyIds)
            else
              Future.value([]),

            // Search records
            SupabaseService.client
                .from('clinical_encounters')
                .select('''
                  encounter_datetime,
                  midwife_notes,
                  age_of_gestation_weeks,
                  age_of_gestation_days,
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
                .eq('encounter_type', 'checkup'),
            SupabaseService.client
                .from('ultrasounds')
                .select('encounter_id, ultrasound_date, remarks:findings_summary, monitoring_classification, pregnancy_id, health_worker_name, ultrasound_location, ultrasound_image, health_worker_institution, health_worker_profession')
                .inFilter('pregnancy_id', allPregnancyIds),
            SupabaseService.client
                .from('lab_tests')
                .select('encounter_id, lab_test_type, pregnancy_id, health_worker_name, lab_test_image, health_worker_institution, health_worker_profession, encounter:clinical_encounters(encounter_datetime, midwife_notes)')
                .inFilter('pregnancy_id', allPregnancyIds),
          ]);

          tdResponse = clinicalResponses[0];
          final List recentCheckupsRaw = clinicalResponses[1];
          recentUltrasounds = (clinicalResponses[2] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          recentLabTests = (clinicalResponses[3] as List).map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            final enc = map['encounter'] as Map<String, dynamic>?;
            map['lab_test_date'] = enc?['encounter_datetime'];
            map['remarks'] = enc?['midwife_notes'];
            return map;
          }).toList();
          final List chartCheckupsRaw = clinicalResponses[4];
          final List checkupsDataRaw = clinicalResponses[5];
          ultrasoundsData = (clinicalResponses[6] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          labTestsData = (clinicalResponses[7] as List).map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            final enc = map['encounter'] as Map<String, dynamic>?;
            map['lab_test_date'] = enc?['encounter_datetime'];
            map['remarks'] = enc?['midwife_notes'];
            return map;
          }).toList();

          // Map recentCheckups
          recentCheckups = [];
          for (final enc in recentCheckupsRaw) {
            final checkupList = enc['checkup'] as List?;
            final innerCheckup = checkupList != null && checkupList.isNotEmpty
                ? checkupList.first as Map<String, dynamic>
                : null;
            if (innerCheckup != null) {
              final double aog = ((enc['age_of_gestation_weeks'] as num?)?.toDouble() ?? 0) +
                  ((enc['age_of_gestation_days'] as num?)?.toDouble() ?? 0) / 7.0;
              recentCheckups.add({
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
            final checkupList = enc['checkup'] as List?;
            final innerCheckup = checkupList != null && checkupList.isNotEmpty
                ? checkupList.first as Map<String, dynamic>
                : null;
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
              });
            }
          }
        }

        _tdDosesGiven = tdResponse.length;

        // Process recent visits
        final List<Map<String, dynamic>> combinedVisits = [];
        for (var checkup in recentCheckups) {
          final dt = DateTime.tryParse(checkup['checkup_datetime']?.toString() ?? '');
          if (dt != null) {
            combinedVisits.add({'type': 'checkup', 'date': dt, 'record': checkup, 'id': checkup['prenatal_checkup_id'], 'pregId': checkup['pregnancy_id']});
          }
        }
        for (var us in recentUltrasounds) {
          final dt = DateTime.tryParse(us['ultrasound_date']?.toString() ?? '');
          if (dt != null) {
            combinedVisits.add({'type': 'ultrasound', 'date': dt, 'record': us, 'id': us['encounter_id'], 'pregId': us['pregnancy_id']});
          }
        }
        for (var lt in recentLabTests) {
          final dt = DateTime.tryParse(lt['lab_test_date']?.toString() ?? '');
          if (dt != null) {
            combinedVisits.add({'type': 'labtest', 'date': dt, 'record': lt, 'id': lt['encounter_id'], 'pregId': lt['pregnancy_id']});
          }
        }

        combinedVisits.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
        _recentVisits = [];

        for (var item in combinedVisits.take(3)) {
          final pregId = item['pregId'] as int?;
          final mother = pregId != null ? _pregnancyToMotherMap[pregId] : null;
          final fullName = mother != null ? '${mother['first_name'] ?? ''} ${mother['last_name'] ?? ''}'.trim() : 'Unknown Mother';
          final motherId = mother != null ? mother['mother_id'] as int? : null;

          final dt = item['date'] as DateTime;
          final nowTime = DateTime.now();
          final diffDays = nowTime.difference(DateTime(dt.year, dt.month, dt.day)).inDays;

          String timeLabel = diffDays == 0 ? 'Today' : (diffDays == 1 ? 'Yesterday' : '$diffDays days ago');
          String visitTypeLabel = 'Prenatal Check-up';
          if (item['type'] == 'ultrasound') {
            visitTypeLabel = 'Ultrasound Assessment';
          } else if (item['type'] == 'labtest') {
            final testType = item['record']['lab_test_type'] ?? 'Lab Test';
            visitTypeLabel = 'Lab Test ($testType)';
          }

          _recentVisits.add(MidwifeVisitItem(
            fullName: fullName,
            visitType: visitTypeLabel,
            timeLabel: timeLabel,
            onTap: () => _navigateToSearchResult({
              'type': item['type'],
              'id': item['id'],
              'motherId': motherId,
              'record': item['record'],
            }),
          ));
        }

        // Process BHC Chart checkup counts (past 7 days including today)
        _bhcVisitValues = List.filled(7, 0);
        for (final checkup in chartCheckups) {
          final dt = DateTime.tryParse(checkup['checkup_datetime']?.toString() ?? '');
          if (dt != null) {
            final localDt = dt.toLocal();
            int chartIndex = localDt.weekday == 7 ? 6 : localDt.weekday - 1;
            _bhcVisitValues[chartIndex] += 1;
          }
        }

        // Process search records
        _allCheckups = List<Map<String, dynamic>>.from(checkupsData);
        _allUltrasounds = List<Map<String, dynamic>>.from(ultrasoundsData);
        _allLabTests = List<Map<String, dynamic>>.from(labTestsData);

        // Load priority tasks
        await _loadPriorityTasks(pregnancyIds);
      } else {
        _registeredChildren = 0;
        _ferrousGiven = 0;
        _calciumGiven = 0;
        _tdDosesGiven = 0;
        _totalPregnancies = 0;
        _firstTrimester = 0;
        _secondTrimester = 0;
        _thirdTrimester = 0;
        _recentVisits = [];
        _priorityTasks = [];
        _bhcVisitValues = [0, 0, 0, 0, 0, 0, 0];
        _allCheckups = [];
        _allUltrasounds = [];
        _allLabTests = [];
        _pregnancyToMotherMap = {};
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      if (kDebugMode) {
        print('Error loading dashboard: $e');
      }
    }
  }

  Future<void> _loadPriorityTasks(List<int> pregnancyIds) async {
    _priorityTasks = [];

    if (pregnancyIds.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      // Task 1: Check for upcoming scheduled checkups (next 7 days)
      final upcomingCheckups = await SupabaseService.client
          .from('prenatal_checkups')
          .select('''
            prenatal_checkup_id,
            next_schedule,
            pregnancy_id
          ''')
          .inFilter('pregnancy_id', pregnancyIds)
          .not('next_schedule', 'is', null)
          .gte('next_schedule', today.toIso8601String().split('T')[0]);

      for (var checkup in upcomingCheckups) {
        final nextDate = DateTime.parse(checkup['next_schedule']);
        final daysUntil = nextDate.difference(today).inDays;

        if (daysUntil <= 7) {
          String urgency = daysUntil == 0
              ? 'urgent'
              : (daysUntil <= 2 ? 'warning' : 'normal');

          final pregnancyData = await SupabaseService.client
              .from('pregnancies')
              .select('mother_id')
              .eq('pregnancy_id', checkup['pregnancy_id'])
              .maybeSingle();

          if (pregnancyData != null) {
            final motherInfo = _allMothers.firstWhere(
              (m) => m['mother_id'] == pregnancyData['mother_id'],
              orElse: () => {},
            );

            final name = motherInfo.isNotEmpty
                ? '${motherInfo['first_name']} ${motherInfo['last_name']}'
                    .trim()
                : 'Unknown Mother';

            _priorityTasks.add(PriorityTask(
              id: checkup['prenatal_checkup_id'],
              motherId: pregnancyData['mother_id'] as int,
              title: 'Prenatal Checkup Scheduled',
              description:
                  '$name has a checkup scheduled for ${DateFormat('MMM d, yyyy').format(nextDate)}',
              urgency: urgency,
              type: 'checkup',
              action: 'View Schedule',
            ));
          }
        }
      }

      // Task 2: Check for high-risk pregnancies
      final highRiskPregnancies = await SupabaseService.client
          .from('pregnancies')
          .select('''
            pregnancy_id,
            pregnancy_risk_level,
            mother_id
          ''')
          .inFilter('pregnancy_id', pregnancyIds)
          .eq('pregnancy_risk_level', 'high');

      for (var pregnancy in highRiskPregnancies) {
        final motherInfo = _allMothers.firstWhere(
          (m) => m['mother_id'] == pregnancy['mother_id'],
          orElse: () => {},
        );

        final name = motherInfo.isNotEmpty
            ? '${motherInfo['first_name']} ${motherInfo['last_name']}'.trim()
            : 'Unknown Mother';

        _priorityTasks.add(PriorityTask(
          id: pregnancy['pregnancy_id'],
          motherId: pregnancy['mother_id'] as int,
          title: 'High-Risk Pregnancy',
          description: '$name requires close monitoring and follow-up',
          urgency: 'urgent',
          type: 'high_risk',
          action: 'View Details',
        ));
      }

      // Sort tasks by urgency
      _priorityTasks.sort((a, b) {
        final urgencyOrder = {'urgent': 0, 'warning': 1, 'normal': 2};
        return urgencyOrder[a.urgency]!.compareTo(urgencyOrder[b.urgency]!);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading priority tasks: $e');
      }
    }

    setState(() {});
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
      Navigator.pushNamed(context, '/mother-profile', arguments: result['id']);
    } else if (result['type'] == 'child') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChildProfilePage(childId: result['id']),
        ),
      );
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

        _showRecordDetails(
          title: 'Prenatal Checkup',
          subtitle: date,
          icon: Icons.medical_services,
          rows: [
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
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordDetailScreen(
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

  String _getChartInsight() {
    int maxIndex = 0;
    int maxValue = 0;
    for (int i = 0; i < _bhcVisitValues.length; i++) {
      if (_bhcVisitValues[i] > maxValue) {
        maxValue = _bhcVisitValues[i].toInt();
        maxIndex = i;
      }
    }

    final bestDay = _bhcVisitDays[maxIndex];

    if (maxValue == 0) {
      return 'No visits recorded in the last 7 days.';
    } else if (maxValue == 1) {
      return '$bestDay had 1 prenatal visit this week.';
    } else {
      return '$bestDay had the most prenatal visits ($maxValue visits) this week!';
    }
  }

  Widget _buildStatCard(
      {required int value, required String label, required IconData iconData}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            iconData,
            color: AppColors.brandPrimary,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 26,
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
            ),
          ),
        ],
      ),
    );
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

                          // Hero Card with Search
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 24, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.cardColorOf(context),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  height: 110,
                                  width: 110,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFFFF0F5),
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/images/midwife.png',
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error,
                                              stackTrace) =>
                                          const Icon(Icons.person,
                                              size: 60,
                                              color: AppColors.brandPrimary),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _getWelcomeMessage(),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.brandPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _bhcName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Global Search Bar
                                AppInputField(
                                  controller: _searchController,
                                  hintText:
                                      'Search mothers, children, check-ups, records...',
                                  leadingIcon: Icons.search,
                                  trailingIcon:
                                      _searchController.text.isNotEmpty
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
                                    iconData: Icons.child_care),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                    value: _registeredMothers,
                                    label: 'Registered\nMothers',
                                    iconData: Icons.pregnant_woman),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                    value: _rhuVisitsThisWeek,
                                    label: 'RHU Visits\nThis week',
                                    iconData: Icons.medical_services),
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

                          // Medication Statistics
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                    value: _ferrousGiven,
                                    label: 'Ferrous FA\ngiven',
                                    iconData: Icons.medication),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                    value: _calciumGiven,
                                    label: 'Calcium\ngiven',
                                    iconData: Icons.local_pharmacy),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                    value: _tdDosesGiven,
                                    label: 'TD Vaccine\ndoses given',
                                    iconData: Icons.vaccines),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Recent Visits
                          if (_recentVisits.isNotEmpty)
                            MidwifeHistoryCard(
                              visits: _recentVisits,
                            )
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

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

// Priority Task Model
class PriorityTask {
  final int id;
  final int motherId;
  final String title;
  final String description;
  final String urgency;
  final String type;
  final String action;

  PriorityTask({
    required this.id,
    required this.motherId,
    required this.title,
    required this.description,
    required this.urgency,
    required this.type,
    required this.action,
  });
}

// Priority Task Tile Widget
class _PriorityTaskTile extends StatelessWidget {
  final PriorityTask task;
  final VoidCallback? onTap;

  const _PriorityTaskTile({required this.task, this.onTap});

  Color _getUrgencyColor() {
    switch (task.urgency) {
      case 'urgent':
        return AppColors.error;
      case 'warning':
        return AppColors.warning;
      default:
        return AppColors.info;
    }
  }

  IconData _getTaskIcon() {
    switch (task.type) {
      case 'checkup':
        return Icons.medical_services;
      case 'high_risk':
        return Icons.warning_amber;
      case 'vaccine':
        return Icons.vaccines;
      default:
        return Icons.task_alt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final urgencyColor = _getUrgencyColor();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: AppColors.borderPrimary.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: urgencyColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getTaskIcon(), color: urgencyColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: urgencyColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  task.urgency.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: urgencyColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
