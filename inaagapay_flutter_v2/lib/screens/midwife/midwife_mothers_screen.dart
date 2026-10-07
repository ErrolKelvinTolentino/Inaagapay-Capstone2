// lib/screens/midwife/midwife_mothers_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/main_button.dart';
import '../../services/mother_directory_order.dart';
import '../../services/pregnancy_stage.dart';
import '../../services/supabase_service.dart';
import '../mother/mother_profile_page.dart';
import 'midwife_add_mother_screen.dart';
import '../../services/auth_storage.dart';

class MidwifeMothersScreen extends StatefulWidget {
  const MidwifeMothersScreen({super.key, this.refreshSignal});

  /// Bumped by the shell each time this tab is opened again.
  ///
  /// The tab is kept alive in an IndexedStack, so without this it showed the
  /// list as it was the first time it was opened: a mother transferred to
  /// another health center in the meantime was still listed, and still came
  /// up in search, until someone thought to pull down to refresh.
  final ValueListenable<int>? refreshSignal;

  @override
  State<MidwifeMothersScreen> createState() => _MidwifeMothersScreenState();
}

class _MidwifeMothersScreenState extends State<MidwifeMothersScreen> {
  // Data lists
  List<Map<String, dynamic>> _allMothers = [];
  List<Map<String, dynamic>> _filteredMothers = [];
  bool _isLoading = true;
  final bool _isLoadingMore = false;
  final bool _hasMoreData = false; // Always false to disable pagination loaders
  String? _error;

  /// Kept across visits so the list paints at once, then revalidated.
  ///
  /// Owned by one midwife account. It is static, so it outlives a sign-out:
  /// without an owner, the next midwife to sign in on the same phone was
  /// shown the previous midwife's mothers -- another health center's
  /// patients -- until the background refresh replaced them.
  static List<Map<String, dynamic>>? _mothersCache;
  static int? _mothersCacheOwner;
  int? _accountId;
  int? _assignedBhcId;

  // Search and Filter
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedRiskFilter = 'All';
  Timer? _searchDebounceTimer;

  String _selectedSort = 'Risk';
  bool _sortAscending = false;

  int _currentPage = 1;
  static const int _pageSize = 5;

  // Filter options
  final List<String> _riskFilters = [
    'All',
    'Low Risk',
    'Medium Risk',
    'High Risk',
    'Critical Risk'
  ];

  // Scroll controller
  final ScrollController _scrollController = ScrollController();

  // Profile picture cache
  final Map<int, String?> _profilePictureCache = {};

  @override
  void initState() {
    super.initState();
    _loadMothers();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    widget.refreshSignal?.addListener(_revalidateMothers);
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_revalidateMothers);
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<String?> _loadProfilePicture(int motherId) async {
    if (_profilePictureCache.containsKey(motherId)) {
      return _profilePictureCache[motherId];
    }

    try {
      final url = await SupabaseService.getProfilePictureUrl(motherId);
      _profilePictureCache[motherId] = url;
      return url;
    } catch (e) {
      debugPrint('Error loading profile picture for mother $motherId: $e');
      return null;
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Map<String, dynamic>> results = List.from(_allMothers);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      results = results.where((mother) {
        final fullName = mother['full_name']?.toString().toLowerCase() ?? '';
        final email = mother['email_address']?.toString().toLowerCase() ?? '';
        final patientId =
            mother['bhc_patient_id']?.toString().toLowerCase() ?? '';
        return fullName.contains(_searchQuery) ||
            email.contains(_searchQuery) ||
            patientId.contains(_searchQuery);
      }).toList();
    }

    // Risk ordering for the default sort. Lower rank sorts first, so the
    // most urgent are at the top. `medium` is included because
    // pregnancies.pregnancy_risk_level allows low, medium and high — the risk
    // filter above only handles two of them, so a medium mother would
    // otherwise fall through to the bottom with the low-risk ones.

    // Apply risk filter
    if (_selectedRiskFilter != 'All') {
      final filterLower = _selectedRiskFilter.toLowerCase();
      results = results.where((mother) {
        final riskLevel =
            mother['risk_level']?.toString().toLowerCase() ?? 'low';
        if (filterLower == 'high risk') return riskLevel == 'high';
        if (filterLower == 'low risk') return riskLevel == 'low';
        if (filterLower == 'medium risk') {
          return riskLevel == 'medium' || riskLevel == 'moderate';
        }
        if (filterLower == 'critical risk') return riskLevel == 'critical';
        return true;
      }).toList();
    }

    results.sort((a, b) =>
        MotherDirectoryOrder.compare(a, b, _selectedSort, _sortAscending));

    setState(() {
      _filteredMothers = results;
      _currentPage = 1;
    });
  }

  void _onScroll() {}

  Future<void> _loadMothers({bool reset = false}) async {
    _accountId ??= await AuthStorage.getUserId();
    if (!mounted) return;

    if (reset || _mothersCacheOwner != _accountId) {
      _mothersCache = null;
    }

    if (_mothersCache != null) {
      setState(() {
        _allMothers = List<Map<String, dynamic>>.from(_mothersCache!);
        _applyFilters();
        _isLoading = false;
        _error = null;
      });
      _revalidateMothers();
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _fetchAndCacheMothers();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading mothers: $e');
      }
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchAndCacheMothers() async {
    if (_assignedBhcId == null) {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) throw Exception('Not authenticated');

      final ctx = await SupabaseService.getMidwifeContext(accountId);
      _assignedBhcId = ctx['assigned_bhc_id'] as int?;
    }

    if (_assignedBhcId == null) {
      throw Exception('No Barangay Health Center assigned to this midwife.');
    }

    final response = await SupabaseService.client.from('mothers').select('''
          mother_id,
          account_id,
          birthdate,
          barangay,
          city_municipality,
          province,
          height,
          weight,
          blood_type,
          accounts!inner (
            first_name,
            last_name,
            phone_number,
            email_address
          ),
          pregnancies (
            pregnancy_id,
            last_menstrual_period,
            pregnancy_risk_level,
            expected_date_of_delivery,
            status
          )
        ''').eq('assigned_bhc_id', _assignedBhcId!);

    final List<dynamic> rawMothers = List<dynamic>.from(response);
    rawMothers.sort(
        (a, b) => (a['mother_id'] as int).compareTo(b['mother_id'] as int));

    final accountIds = rawMothers
        .map((r) => r['account_id'] as int?)
        .whereType<int>()
        .toList();

    final Map<int, String?> profileUrlsByAccountId = {};
    if (accountIds.isNotEmpty) {
      try {
        final filesResponse = await SupabaseService.client
            .from('files')
            .select('uploaded_by, file_path, bucket_name')
            .eq('reference_type', 'profile_photo')
            .inFilter('uploaded_by', accountIds)
            .timeout(const Duration(seconds: 5))
            .catchError((e) {
          debugPrint('Batch profile picture fetch note: $e');
          return <Map<String, dynamic>>[];
        });

        for (var file in filesResponse) {
          final accId = file['uploaded_by'] as int?;
          final path = file['file_path'] as String?;
          final bucket = file['bucket_name'] as String? ?? 'files';
          if (accId != null && path != null && path.isNotEmpty) {
            final url =
                SupabaseService.client.storage.from(bucket).getPublicUrl(path);
            profileUrlsByAccountId[accId] = url;
          }
        }
      } catch (e) {
        debugPrint('Error batch fetching profile pictures: $e');
      }
    }

    final patientNumbersByAccountId =
        await SupabaseService.getPatientNumbersByAccountId(
      accountIds,
      facilityId: _assignedBhcId,
    );

    final List<Map<String, dynamic>> parsedMothers = [];

    for (int i = 0; i < rawMothers.length; i++) {
      final raw = rawMothers[i];
      final int motherId = raw['mother_id'] as int;
      final int accountId = raw['account_id'] as int;
      final String? bhcPatientId = SupabaseService.formatPatientNumber(
        patientNumbersByAccountId[accountId],
      );
      final account = raw['accounts'] as Map<String, dynamic>?;
      if (account == null) continue;

      final String firstName = account['first_name']?.toString() ?? '';
      final String lastName = account['last_name']?.toString() ?? '';
      final String fullName = '$firstName $lastName'.trim();

      int age = 0;
      final String? birthdateStr = raw['birthdate']?.toString();
      if (birthdateStr != null && birthdateStr.isNotEmpty) {
        final DateTime? birthdate = DateTime.tryParse(birthdateStr);
        if (birthdate != null) {
          age = DateTime.now().difference(birthdate).inDays ~/ 365;
        }
      }

      final pregnancies = raw['pregnancies'] as List?;
      final ongoingPregnancy = pregnancies?.firstWhere(
        (p) => p['status'] == 'ongoing',
        orElse: () => null,
      ) as Map<String, dynamic>?;

      int gestWeeks = 0;
      String riskLevel = 'low';
      String? expectedDueDate;
      if (ongoingPregnancy != null) {
        riskLevel =
            ongoingPregnancy['pregnancy_risk_level'] as String? ?? 'low';
        expectedDueDate =
            ongoingPregnancy['expected_date_of_delivery'] as String?;
        final String? lmpString =
            ongoingPregnancy['last_menstrual_period'] as String?;
        if (lmpString != null && lmpString.isNotEmpty) {
          final DateTime? lmpDate = DateTime.tryParse(lmpString);
          if (lmpDate != null) {
            gestWeeks = DateTime.now().difference(lmpDate).inDays ~/ 7;
          }
        }
      }

      String? profilePictureUrl = profileUrlsByAccountId[accountId];

      parsedMothers.add({
        'account_id': accountId,
        'first_name': firstName,
        'last_name': lastName,
        'full_name': fullName.isEmpty ? 'Unknown Mother' : fullName,
        'phone_number': account['phone_number']?.toString() ?? '',
        'email_address': account['email_address']?.toString() ?? '',
        'mother_id': motherId,
        'bhc_patient_id': bhcPatientId,
        'age': age,
        'gest_weeks': gestWeeks,
        'risk_level': riskLevel,
        'expected_due_date': expectedDueDate,
        'has_pregnancy': ongoingPregnancy != null,
        'barangay': raw['barangay']?.toString() ?? '',
        'profile_picture': profilePictureUrl,
        'pregnancy_id': ongoingPregnancy?['pregnancy_id'] as int?,
        'last_menstrual_period':
            ongoingPregnancy?['last_menstrual_period'] as String?,
      });
    }

    _mothersCache = parsedMothers;
    _mothersCacheOwner = _accountId;

    if (mounted) {
      setState(() {
        _allMothers = List<Map<String, dynamic>>.from(parsedMothers);
        _applyFilters();
        _isLoading = false;
      });
    }
  }

  Future<void> _revalidateMothers() async {
    try {
      if (_assignedBhcId == null) {
        final accountId = await AuthStorage.getUserId();
        if (accountId == null) return;

        final ctx = await SupabaseService.getMidwifeContext(accountId);
        _assignedBhcId = ctx['assigned_bhc_id'] as int?;
      }

      if (_assignedBhcId == null) return;

      final response = await SupabaseService.client.from('mothers').select('''
            mother_id,
            account_id,
            birthdate,
            barangay,
            city_municipality,
            province,
            height,
            weight,
            blood_type,
            accounts!inner (
              first_name,
              last_name,
              phone_number,
              email_address
            ),
            pregnancies (
              pregnancy_id,
              last_menstrual_period,
              pregnancy_risk_level,
              expected_date_of_delivery,
              status
            )
          ''').eq('assigned_bhc_id', _assignedBhcId!);

      final List<dynamic> rawMothers = List<dynamic>.from(response);
      rawMothers.sort(
          (a, b) => (a['mother_id'] as int).compareTo(b['mother_id'] as int));

      final patientNumbersByAccountId =
          await SupabaseService.getPatientNumbersByAccountId(
        rawMothers
            .map((r) => r['account_id'] as int?)
            .whereType<int>()
            .toList(),
        facilityId: _assignedBhcId,
      );

      final List<Map<String, dynamic>> parsedMothers = [];

      for (int i = 0; i < rawMothers.length; i++) {
        final raw = rawMothers[i];
        final int motherId = raw['mother_id'] as int;
        final int accountId = raw['account_id'] as int;
        final String? bhcPatientId = SupabaseService.formatPatientNumber(
          patientNumbersByAccountId[accountId],
        );
        final account = raw['accounts'] as Map<String, dynamic>?;
        if (account == null) continue;

        final String firstName = account['first_name']?.toString() ?? '';
        final String lastName = account['last_name']?.toString() ?? '';
        final String fullName = '$firstName $lastName'.trim();

        int age = 0;
        final String? birthdateStr = raw['birthdate']?.toString();
        if (birthdateStr != null && birthdateStr.isNotEmpty) {
          final DateTime? birthdate = DateTime.tryParse(birthdateStr);
          if (birthdate != null) {
            age = DateTime.now().difference(birthdate).inDays ~/ 365;
          }
        }

        final pregnancies = raw['pregnancies'] as List?;
        final ongoingPregnancy = pregnancies?.firstWhere(
          (p) => p['status'] == 'ongoing',
          orElse: () => null,
        ) as Map<String, dynamic>?;

        int gestWeeks = 0;
        String riskLevel = 'low';
        String? expectedDueDate;
        if (ongoingPregnancy != null) {
          riskLevel =
              ongoingPregnancy['pregnancy_risk_level'] as String? ?? 'low';
          expectedDueDate =
              ongoingPregnancy['expected_date_of_delivery'] as String?;
          final String? lmpString =
              ongoingPregnancy['last_menstrual_period'] as String?;
          if (lmpString != null && lmpString.isNotEmpty) {
            final DateTime? lmpDate = DateTime.tryParse(lmpString);
            if (lmpDate != null) {
              gestWeeks = DateTime.now().difference(lmpDate).inDays ~/ 7;
            }
          }
        }

        String? profilePictureUrl = _profilePictureCache[motherId];

        parsedMothers.add({
          'account_id': accountId,
          'first_name': firstName,
          'last_name': lastName,
          'full_name': fullName.isEmpty ? 'Unknown Mother' : fullName,
          'phone_number': account['phone_number']?.toString() ?? '',
          'email_address': account['email_address']?.toString() ?? '',
          'mother_id': motherId,
          'age': age,
          'gest_weeks': gestWeeks,
          'risk_level': riskLevel,
          'expected_due_date': expectedDueDate,
          'has_pregnancy': ongoingPregnancy != null,
          'barangay': raw['barangay']?.toString() ?? '',
          'profile_picture': profilePictureUrl,
          'pregnancy_id': ongoingPregnancy?['pregnancy_id'] as int?,
          'last_menstrual_period':
              ongoingPregnancy?['last_menstrual_period'] as String?,
          'bhc_patient_id': bhcPatientId,
        });
      }

      bool hasChanges = false;
      if (_mothersCache == null ||
          _mothersCache!.length != parsedMothers.length) {
        hasChanges = true;
      } else {
        for (int i = 0; i < parsedMothers.length; i++) {
          final m1 = parsedMothers[i];
          final m2 = _mothersCache!.firstWhere(
            (m) => m['mother_id'] == m1['mother_id'],
            orElse: () => {},
          );
          if (m2.isEmpty ||
              m1['full_name'] != m2['full_name'] ||
              m1['risk_level'] != m2['risk_level'] ||
              m1['gest_weeks'] != m2['gest_weeks']) {
            hasChanges = true;
            break;
          }
        }
      }

      // The cache is corrected even when this screen has gone, so the next
      // visit does not open on a list already known to be out of date.
      if (hasChanges) {
        _mothersCache = parsedMothers;
        _mothersCacheOwner = _accountId;
        if (mounted) {
          setState(() {
            _allMothers = List<Map<String, dynamic>>.from(parsedMothers);
            _applyFilters();
          });
        }
      }
    } catch (e) {
      debugPrint('Error revalidating mothers: $e');
    }
  }

  Future<void> _refreshMothers() async {
    _mothersCache = null;
    _profilePictureCache.clear();
    await _loadMothers(reset: true);
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return AppColors.error;
      default:
        return AppColors.success;
    }
  }

  String _getRiskLabel(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return 'HIGH RISK';
      default:
        return 'LOW RISK';
    }
  }

  String _getEmptyStateMessage() {
    if (_allMothers.isEmpty && !_isLoading) {
      return 'No mothers registered yet';
    }
    if (_searchQuery.isNotEmpty && _filteredMothers.isEmpty) {
      return 'No matching mothers found';
    }
    if (_selectedRiskFilter != 'All' && _filteredMothers.isEmpty) {
      return 'No mothers matching the risk filter';
    }
    return 'No mothers found';
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedSort = 'Risk';
      _sortAscending = false;
      _selectedRiskFilter = 'All';
      _applyFilters();
    });
  }

  void _showFilterSortDialog() {
    var tempSort = _selectedSort;
    var tempAscending = _sortAscending;
    var tempRisk = _selectedRiskFilter;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, update) => Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                backgroundColor: AppColors.bgSecondaryOf(context),
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Expanded(
                              child: Text('Sort & Filter',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.brandText))),
                          IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close)),
                        ]),
                        const SizedBox(height: 16),
                        const Text('Sort by',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        AppDropdownField<String>(
                            hintText: 'Criteria',
                            value: tempSort,
                            options: const [
                              'Risk',
                              'ID Number',
                              'Name',
                              'Age',
                              'Due Date'
                            ],
                            displayStringForOption: (v) => v,
                            onSelected: (v) => update(() {
                                  tempSort = v;
                                  tempAscending = v != 'Risk';
                                })),
                        const SizedBox(height: 16),
                        AppDropdownField<bool>(
                            hintText: 'Order',
                            value: tempAscending,
                            options: const [true, false],
                            displayStringForOption: (v) =>
                                v ? 'Ascending' : 'Descending',
                            onSelected: (v) => update(() => tempAscending = v)),
                        const SizedBox(height: 16),
                        const Text('Filter by risk',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        AppDropdownField<String>(
                            hintText: 'Risk level',
                            value: tempRisk,
                            options: _riskFilters,
                            displayStringForOption: (v) =>
                                v == 'All' ? 'All risk levels' : v,
                            onSelected: (v) => update(() => tempRisk = v)),
                        const SizedBox(height: 24),
                        MainButton(
                            label: 'Apply',
                            onPressed: () {
                              _selectedSort = tempSort;
                              _sortAscending = tempAscending;
                              _selectedRiskFilter = tempRisk;
                              _applyFilters();
                              Navigator.pop(context);
                            }),
                        TextButton(
                            onPressed: () => update(() {
                                  tempSort = 'Risk';
                                  tempAscending = false;
                                  tempRisk = 'All';
                                }),
                            child: const Text('Reset filters')),
                      ]),
                ),
              )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int totalMothersCount = _filteredMothers.length;
    final int startIndex = (_currentPage - 1) * _pageSize;
    final int endIndex = startIndex + _pageSize < totalMothersCount
        ? startIndex + _pageSize
        : totalMothersCount;
    final List<Map<String, dynamic>> displayedMothers = _filteredMothers.isEmpty
        ? <Map<String, dynamic>>[]
        : _filteredMothers.sublist(startIndex, endIndex);

    return Scaffold(
      backgroundColor: AppColors.bgPrimaryOf(context),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            // Modern Banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.brandPrimary.withValues(alpha: 0.08),
                    AppColors.brandPrimary.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.brandPrimary.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    bottom: 0,
                    top: 0,
                    child: Padding(
                      padding: const EdgeInsets.only(
                          right: 16.0, top: 4.0, bottom: 4.0),
                      child: Image.asset('assets/images/pregnant1.png',
                          fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 0,
                    bottom: 0,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mothers Directory',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brandText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage prenatal visits and health records',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.brandText.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Search & Filter Row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppInputField(
                      hintText: 'Search mothers',
                      controller: _searchController,
                      leadingIcon: Icons.search,
                      trailingIcon: _searchController.text.isNotEmpty
                          ? Icons.clear
                          : null,
                      onTrailingTap: _searchController.text.isNotEmpty
                          ? () {
                              _searchController.clear();
                              _searchQuery = '';
                              _applyFilters();
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Sort & Filter Icon Button
                  Container(
                    decoration: BoxDecoration(
                      color: ((_selectedSort != 'Risk' || _sortAscending) ||
                              _selectedRiskFilter != 'All' ||
                              _searchQuery.isNotEmpty)
                          ? AppColors.brandPrimary
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: ((_selectedSort != 'Risk' || _sortAscending) ||
                                _selectedRiskFilter != 'All' ||
                                _searchQuery.isNotEmpty)
                            ? AppColors.brandPrimary
                            : AppColors.borderPrimary,
                        width: 1.5,
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.filter_list,
                        color: ((_selectedSort != 'Risk' || _sortAscending) ||
                                _selectedRiskFilter != 'All' ||
                                _searchQuery.isNotEmpty)
                            ? Colors.white
                            : AppColors.brandPrimary,
                      ),
                      onPressed: _showFilterSortDialog,
                      tooltip: 'Sort & Filter',
                    ),
                  ),
                  if ((_selectedSort != 'Risk' || _sortAscending) ||
                      _selectedRiskFilter != 'All' ||
                      _searchQuery.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.borderPrimary,
                          width: 1.5,
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: AppColors.brandPrimary,
                        ),
                        onPressed: _resetFilters,
                        tooltip: 'Clear Filters',
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Results Count & Pagination Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    (_searchQuery.isNotEmpty || _selectedRiskFilter != 'All')
                        ? 'Showing ${_filteredMothers.length} of ${_allMothers.length} mothers'
                        : 'Total of ${_allMothers.length} registered mothers',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_filteredMothers.length > _pageSize) ...[
                    _buildPaginationWidget(_filteredMothers.length),
                  ],
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: _isLoading && _allMothers.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.brandPrimary),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 48, color: AppColors.error),
                                const SizedBox(height: 12),
                                const Text(
                                  'Failed to load mothers',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _refreshMothers(),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brandPrimary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filteredMothers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _searchQuery.isNotEmpty
                                        ? Icons.search_off_rounded
                                        : (_selectedRiskFilter == 'Due Soon'
                                            ? Icons.calendar_today
                                            : Icons.pregnant_woman_rounded),
                                    size: 64,
                                    color: AppColors.brandPrimary
                                        .withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _getEmptyStateMessage(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: _resetFilters,
                                    icon: const Icon(Icons.clear),
                                    label: const Text('Clear Filters'),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _refreshMothers,
                              color: AppColors.brandPrimary,
                              child: ListView.builder(
                                controller: _scrollController,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                itemCount: displayedMothers.length,
                                itemBuilder: (context, index) {
                                  final mother = displayedMothers[index];
                                  final int? motherId =
                                      mother['mother_id'] as int?;
                                  final riskLevel =
                                      mother['risk_level']?.toString() ?? 'low';
                                  final riskColor = _getRiskColor(riskLevel);
                                  final riskLabel = _getRiskLabel(riskLevel);
                                  final expectedDueDate =
                                      mother['expected_due_date'] as String?;
                                  final profilePictureUrl =
                                      mother['profile_picture'] as String?;
                                  final barangay =
                                      mother['barangay']?.toString() ?? '';

                                  String? dueDateText;
                                  if (expectedDueDate != null &&
                                      expectedDueDate.isNotEmpty) {
                                    final edd =
                                        DateTime.tryParse(expectedDueDate);
                                    if (edd != null) {
                                      final daysUntil = PregnancyStage.daysUntilDue(
                                          edd: edd, now: DateTime.now());
                                      if (daysUntil >= 0) {
                                        final int months = daysUntil ~/ 30;
                                        final int remainingDays =
                                            daysUntil % 30;
                                        final int weeks = remainingDays ~/ 7;

                                        if (months > 0 && weeks > 0) {
                                          dueDateText =
                                              'Due in $months month${months == 1 ? '' : 's'} and $weeks week${weeks == 1 ? '' : 's'}';
                                        } else if (months > 0) {
                                          dueDateText =
                                              'Due in $months month${months == 1 ? '' : 's'}';
                                        } else if (weeks > 0) {
                                          dueDateText =
                                              'Due in $weeks week${weeks == 1 ? '' : 's'}';
                                        } else if (daysUntil > 0) {
                                          dueDateText =
                                              'Due in $daysUntil day${daysUntil == 1 ? '' : 's'}';
                                        } else {
                                          dueDateText = 'Due today';
                                        }
                                      } else {
                                        dueDateText = 'Past due date';
                                      }
                                    }
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _MotherCard(
                                      mother: mother,
                                      riskColor: riskColor,
                                      riskLabel: riskLabel,
                                      dueDateText: dueDateText,
                                      profilePictureUrl: profilePictureUrl,
                                      barangay: barangay,
                                      onTap: motherId != null
                                          ? () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      MotherProfilePage(
                                                    motherId: motherId,
                                                  ),
                                                ),
                                              ).then((_) {
                                                if (mounted) {
                                                  _refreshMothers();
                                                }
                                              });
                                            }
                                          : null,
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_mothers',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const MidwifeAddMotherScreen(),
            ),
          );
          if (mounted) {
            _refreshMothers();
          }
        },
        backgroundColor: AppColors.brandPrimary,
        foregroundColor: Colors.white,
        tooltip: 'Add Mother',
        shape: const CircleBorder(),
        child: const Icon(Icons.person_add_rounded),
      ),
    );
  }

  Widget _buildPaginationWidget(int totalMothers) {
    final totalPages = (totalMothers / _pageSize).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 24),
                color: AppColors.brandPrimary,
                disabledColor: Colors.grey.shade300,
                onPressed: _currentPage > 1
                    ? () => setState(() => _currentPage--)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(totalPages, (index) {
                  final pageNum = index + 1;
                  final isCurrent = _currentPage == pageNum;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppColors.brandPrimary
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.brandPrimary,
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 24),
                color: AppColors.brandPrimary,
                disabledColor: Colors.grey.shade300,
                onPressed: _currentPage < totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$_currentPage of $totalPages',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.brandText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _getRiskFilterIcon(String filter) {
    switch (filter) {
      case 'High Risk':
        return Icon(Icons.error_outline, size: 16, color: AppColors.error);
      case 'Low Risk':
        return const Icon(Icons.check_circle_outline,
            size: 16, color: AppColors.success);
      case 'Due Soon':
        return Icon(Icons.event_available, size: 16, color: Colors.pink[300]);
      default:
        return Icon(Icons.circle,
            size: 10, color: AppColors.textSecondary.withValues(alpha: 0.5));
    }
  }
}

class _MotherCard extends StatelessWidget {
  final Map<String, dynamic> mother;
  final VoidCallback? onTap;
  final Color riskColor;
  final String riskLabel;
  final String? dueDateText;
  final String? profilePictureUrl;
  final String barangay;

  const _MotherCard({
    required this.mother,
    required this.riskColor,
    required this.riskLabel,
    this.dueDateText,
    this.profilePictureUrl,
    required this.barangay,
    this.onTap,
  });

  String _getInitials(String fullName) {
    if (fullName.isEmpty || fullName == 'Unknown Mother') return '?';

    final String trimmed = fullName.trim();
    if (trimmed.isEmpty) return '?';

    final List<String> parts = trimmed.split(' ');
    if (parts.isEmpty) return '?';

    final String firstPart = parts[0];
    if (firstPart.isEmpty) return '?';
    final String firstInitial = firstPart[0].toUpperCase();

    if (parts.length > 1) {
      final String secondPart = parts[1];
      if (secondPart.isNotEmpty) {
        return '$firstInitial${secondPart[0].toUpperCase()}';
      }
    }

    return firstInitial;
  }

  @override
  Widget build(BuildContext context) {
    final String fullName = mother['full_name']?.toString() ?? '';
    final int age = mother['age'] as int? ?? 0;
    final int gestWeeks = mother['gest_weeks'] as int? ?? 0;
    final bool hasPregnancy = mother['has_pregnancy'] as bool? ?? false;

    final String displayName = fullName.isEmpty ? 'Unknown Mother' : fullName;

    final StringBuffer subtitleBuffer = StringBuffer();
    if (age > 0) {
      subtitleBuffer.write('$age years old');
    } else {
      subtitleBuffer.write('Age unknown');
    }

    if (dueDateText != null && dueDateText!.isNotEmpty) {
      String dueStr = dueDateText!;
      if (dueStr.toLowerCase().startsWith('due ')) {
        dueStr = 'due ${dueStr.substring(4)}';
      }
      subtitleBuffer.write(' • $dueStr');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.brandPrimary.withValues(alpha: 0.15),
                        AppColors.brandPrimary.withValues(alpha: 0.05),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: profilePictureUrl != null &&
                            profilePictureUrl!.isNotEmpty
                        ? Image.network(
                            profilePictureUrl!,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Text(
                                  _getInitials(displayName),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.brandPrimary,
                                  ),
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.brandPrimary,
                                  ),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Text(
                              _getInitials(displayName),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.brandPrimary,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.brandPrimary
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.brandPrimary
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              mother['bhc_patient_id']?.toString() ?? '—',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandPrimary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: riskColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: riskColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              riskLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: riskColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppColors.inputText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitleBuffer.toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.brandPrimary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
