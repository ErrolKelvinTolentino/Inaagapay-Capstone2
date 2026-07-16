// lib/screens/midwife/midwife_mothers_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../services/supabase_service.dart';
import '../mother/mother_profile_page.dart';
import 'midwife_add_mother_screen.dart';
import '../../services/auth_storage.dart';

class MidwifeMothersScreen extends StatefulWidget {
  const MidwifeMothersScreen({super.key});

  @override
  State<MidwifeMothersScreen> createState() => _MidwifeMothersScreenState();
}

class _MidwifeMothersScreenState extends State<MidwifeMothersScreen> {
  // Data lists
  List<Map<String, dynamic>> _allMothers = [];
  List<Map<String, dynamic>> _filteredMothers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = false; // Always false to disable pagination loaders
  String? _error;

  static List<Map<String, dynamic>>? _mothersCache;
  int? _assignedBhcId;

  // Search and Filter
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedRiskFilter = 'All';
  String _selectedBarangayFilter = 'All';
  Timer? _searchDebounceTimer;

  String _selectedSort = 'Name (A-Z)';

  // Filter options
  final List<String> _riskFilters = ['All', 'Low Risk', 'High Risk'];
  final List<String> _barangayFilters = [
    'All',
    'Sta Barbara',
    'Tarcan',
    'San Jose',
    'Tiaong',
    'Pinagbarilan',
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
  }

  @override
  void dispose() {
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
    if (_searchDebounceTimer?.isActive ?? false) {
      _searchDebounceTimer?.cancel();
    }
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
        _applyFilters();
      });
    });
  }

  void _applyFilters() {
    List<Map<String, dynamic>> results = List.from(_allMothers);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      results = results.where((mother) {
        final fullName = mother['full_name']?.toString().toLowerCase() ?? '';
        final email = mother['email_address']?.toString().toLowerCase() ?? '';
        return fullName.contains(_searchQuery) || email.contains(_searchQuery);
      }).toList();
    }

    // Apply risk filter
    if (_selectedRiskFilter != 'All') {
      final filterLower = _selectedRiskFilter.toLowerCase();
      results = results.where((mother) {
        final riskLevel =
            mother['risk_level']?.toString().toLowerCase() ?? 'low';
        if (filterLower == 'high risk') return riskLevel == 'high';
        if (filterLower == 'low risk') return riskLevel == 'low';
        return true;
      }).toList();
    }

    // Apply barangay filter
    if (_selectedBarangayFilter != 'All') {
      results = results.where((mother) {
        final barangay = mother['barangay']?.toString() ?? '';
        return barangay == _selectedBarangayFilter;
      }).toList();
    }

    // Apply sorting
    if (_selectedSort == 'Age (Ascending)') {
      results.sort(
          (a, b) => (a['age'] as int? ?? 0).compareTo(b['age'] as int? ?? 0));
    } else if (_selectedSort == 'Age (Descending)') {
      results.sort(
          (a, b) => (b['age'] as int? ?? 0).compareTo(a['age'] as int? ?? 0));
    } else if (_selectedSort == 'Due Date (Ascending)') {
      results.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['expected_due_date']?.toString() ?? '');
        final dateB =
            DateTime.tryParse(b['expected_due_date']?.toString() ?? '');
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });
    } else if (_selectedSort == 'Due Date (Descending)') {
      results.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['expected_due_date']?.toString() ?? '');
        final dateB =
            DateTime.tryParse(b['expected_due_date']?.toString() ?? '');
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA);
      });
    } else {
      results.sort((a, b) => (a['full_name']?.toString() ?? '')
          .compareTo(b['full_name']?.toString() ?? ''));
    }

    setState(() {
      _filteredMothers = results;
    });
  }

  void _onScroll() {}

  Future<void> _loadMothers({bool reset = false}) async {
    if (!mounted) return;

    if (reset) {
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
      
      final result = await SupabaseService.client
          .from('midwives')
          .select('assigned_bhc_id')
          .eq('account_id', accountId)
          .single();
      
      _assignedBhcId = result['assigned_bhc_id'] as int?;
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

    final List<dynamic> rawMothers = response;
    final List<Map<String, dynamic>> parsedMothers = [];

    for (var raw in rawMothers) {
      final int motherId = raw['mother_id'] as int;
      final int accountId = raw['account_id'] as int;
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
        riskLevel = ongoingPregnancy['pregnancy_risk_level'] as String? ?? 'low';
        expectedDueDate = ongoingPregnancy['expected_date_of_delivery'] as String?;
        final String? lmpString = ongoingPregnancy['last_menstrual_period'] as String?;
        if (lmpString != null && lmpString.isNotEmpty) {
          final DateTime? lmpDate = DateTime.tryParse(lmpString);
          if (lmpDate != null) {
            gestWeeks = DateTime.now().difference(lmpDate).inDays ~/ 7;
          }
        }
      }

      String? profilePictureUrl = await _loadProfilePicture(motherId);

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
        'last_menstrual_period': ongoingPregnancy?['last_menstrual_period'] as String?,
      });
    }

    _mothersCache = parsedMothers;

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
        
        final result = await SupabaseService.client
            .from('midwives')
            .select('assigned_bhc_id')
            .eq('account_id', accountId)
            .single();
        
        _assignedBhcId = result['assigned_bhc_id'] as int?;
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

      final List<dynamic> rawMothers = response;
      final List<Map<String, dynamic>> parsedMothers = [];

      for (var raw in rawMothers) {
        final int motherId = raw['mother_id'] as int;
        final int accountId = raw['account_id'] as int;
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
          riskLevel = ongoingPregnancy['pregnancy_risk_level'] as String? ?? 'low';
          expectedDueDate = ongoingPregnancy['expected_date_of_delivery'] as String?;
          final String? lmpString = ongoingPregnancy['last_menstrual_period'] as String?;
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
          'last_menstrual_period': ongoingPregnancy?['last_menstrual_period'] as String?,
        });
      }

      bool hasChanges = false;
      if (_mothersCache == null || _mothersCache!.length != parsedMothers.length) {
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

      if (hasChanges && mounted) {
        _mothersCache = parsedMothers;
        setState(() {
          _allMothers = List<Map<String, dynamic>>.from(parsedMothers);
          _applyFilters();
        });
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
    if (_selectedBarangayFilter != 'All' && _filteredMothers.isEmpty) {
      return 'No mothers in this barangay';
    }
    return 'No mothers found';
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedSort = 'Name (A-Z)';
      _selectedRiskFilter = 'All';
      _selectedBarangayFilter = 'All';
      _applyFilters();
    });
  }

  void _showFilterSortDialog() {
    String tempSort = _selectedSort;
    String tempRisk = _selectedRiskFilter;
    String tempBarangay = _selectedBarangayFilter;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              backgroundColor: AppColors.cardColorOf(context),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Sort & Filter',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.brandPrimary)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Sort By',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        'Name (A-Z)',
                        'Age (Ascending)',
                        'Age (Descending)',
                        'Due Date (Ascending)',
                        'Due Date (Descending)'
                      ].map((sortOption) {
                        final isSelected = tempSort == sortOption;
                        return ChoiceChip(
                          label: Text(sortOption),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() => tempSort = sortOption);
                            }
                          },
                          selectedColor:
                              AppColors.brandPrimary.withValues(alpha: 0.2),
                          backgroundColor: AppColors.bgSecondary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? AppColors.brandPrimary
                                : AppColors.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.brandPrimary
                                  : Colors.transparent,
                            ),
                          ),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    const Text('Filter by Risk',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          ['All', 'Low Risk', 'High Risk'].map((riskOption) {
                        final isSelected = tempRisk == riskOption;
                        return ChoiceChip(
                          label: Text(
                              riskOption == 'All' ? 'All Risks' : riskOption),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() => tempRisk = riskOption);
                            }
                          },
                          selectedColor:
                              AppColors.brandPrimary.withValues(alpha: 0.2),
                          backgroundColor: AppColors.bgSecondary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? AppColors.brandPrimary
                                : AppColors.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.brandPrimary
                                  : Colors.transparent,
                            ),
                          ),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    const Text('Filter by Barangay',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    DropdownMenu<String>(
                      initialSelection: tempBarangay,
                      width: MediaQuery.of(context).size.width - 48,
                      textStyle: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      menuStyle: MenuStyle(
                        backgroundColor: WidgetStateProperty.all(Colors.white),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        elevation: WidgetStateProperty.all(4),
                      ),
                      inputDecorationTheme: InputDecorationTheme(
                        fillColor: AppColors.bgSecondary,
                        filled: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSelected: (val) {
                        if (val != null) {
                          setModalState(() => tempBarangay = val);
                        }
                      },
                      dropdownMenuEntries: _barangayFilters
                          .map((b) => DropdownMenuEntry<String>(
                                value: b,
                                label: b == 'All' ? 'All Barangays' : b,
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedSort = tempSort;
                            _selectedRiskFilter = tempRisk;
                            _selectedBarangayFilter = tempBarangay;
                            _applyFilters();
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Apply',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimaryOf(context),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // Header Banner
            Container(
              width: double.infinity,
              height: 110,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                image: const DecorationImage(
                  image: AssetImage('assets/images/pinkbg.png'),
                  fit: BoxFit.cover,
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
                      child: Image.asset(
                        'assets/images/pregnant1.png',
                        fit: BoxFit.contain,
                      ),
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
                          'Showing',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '${_filteredMothers.length}/${_allMothers.length} Mothers',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: AppInputField(
                hintText: 'Search Mother by name or email',
                controller: _searchController,
                leadingIcon: Icons.search,
                trailingIcon:
                    _searchController.text.isNotEmpty ? Icons.clear : null,
                onTrailingTap: _searchController.text.isNotEmpty
                    ? () {
                        _searchController.clear();
                        _searchQuery = '';
                        _applyFilters();
                      }
                    : null,
              ),
            ),

            // Filter & Sort Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.brandPrimary.withValues(alpha: 0.1),
                        foregroundColor: AppColors.brandPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _showFilterSortDialog,
                      icon: const Icon(Icons.filter_list),
                      label: const Text('Sort & Filter',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (_selectedSort != 'Name (A-Z)' ||
                      _selectedRiskFilter != 'All' ||
                      _selectedBarangayFilter != 'All' ||
                      _searchQuery.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.brandPrimary.withValues(alpha: 0.1),
                        foregroundColor: AppColors.brandPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _resetFilters,
                      child: const Text('Clear',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),

            // Results Count
            if (_searchQuery.isNotEmpty ||
                _selectedRiskFilter != 'All' ||
                _selectedBarangayFilter != 'All')
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${_filteredMothers.length} of ${_allMothers.length} mothers',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

            // Helper Text
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Text(
                'Tap a mother to view health records',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
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
                                itemCount: _filteredMothers.length +
                                    (_hasMoreData &&
                                            _searchQuery.isEmpty &&
                                            _selectedRiskFilter == 'All' &&
                                            _selectedBarangayFilter == 'All'
                                        ? 1
                                        : 0),
                                itemBuilder: (context, index) {
                                  if (index == _filteredMothers.length &&
                                      _hasMoreData &&
                                      _searchQuery.isEmpty &&
                                      _selectedRiskFilter == 'All' &&
                                      _selectedBarangayFilter == 'All') {
                                    return const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 20),
                                      child: Center(
                                        child: SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.brandPrimary,
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final mother = _filteredMothers[index];
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
                                      final daysUntil =
                                          edd.difference(DateTime.now()).inDays;
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
        child: const Icon(Icons.person_add_rounded),
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

    if (hasPregnancy && gestWeeks > 0) {
      subtitleBuffer.write(' • $gestWeeks weeks pregnant');
    }

    if (barangay.isNotEmpty) {
      subtitleBuffer.write(' • $barangay');
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
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        riskColor.withValues(alpha: 0.3),
                        riskColor.withValues(alpha: 0.2),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: profilePictureUrl != null &&
                            profilePictureUrl!.isNotEmpty
                        ? Image.network(
                            profilePictureUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Text(
                                  _getInitials(displayName),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: riskColor,
                                  ),
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: riskColor,
                                  ),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Text(
                              _getInitials(displayName),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: riskColor,
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
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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
                        subtitleBuffer.toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dueDateText != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.event_available,
                              size: 12,
                              color: Colors.pink[300],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dueDateText!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.pink[300],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
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
