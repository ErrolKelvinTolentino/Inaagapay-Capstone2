// lib/screens/midwife/midwife_children_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';
import 'child_profile_page.dart';
import 'add_child_choice.dart';

class MidwifeChildrenScreen extends StatefulWidget {
  const MidwifeChildrenScreen({super.key});

  @override
  State<MidwifeChildrenScreen> createState() => _MidwifeChildrenScreenState();
}

class _MidwifeChildrenScreenState extends State<MidwifeChildrenScreen> {
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _filteredChildren = [];
  bool _loading = true;
  String? _errorMessage;
  int? _assignedBhcId;

  // Search, Filter, Sort and Pagination
  String _searchQuery = '';
  String _selectedGenderFilter = 'All';
  String _selectedSort = 'ID Number';
  int _currentPage = 1;
  static const int _pageSize = 5;

  static List<Map<String, dynamic>>? _childrenCache;

  @override
  void initState() {
    super.initState();
    _loadMidwifeContext();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMidwifeContext() async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) throw Exception('Not authenticated');
      
      final ctx = await SupabaseService.getMidwifeContext(accountId);
      if (ctx['success'] != true) {
        throw Exception('Failed to load midwife context');
      }

      _assignedBhcId = ctx['assigned_bhc_id'] as int?;
      
      await _fetchChildren();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchChildren({bool forceRefresh = false}) async {
    if (_assignedBhcId == null) return;

    if (forceRefresh) {
      _childrenCache = null;
    }

    if (_childrenCache != null) {
      setState(() {
        _children = List<Map<String, dynamic>>.from(_childrenCache!);
        _loading = false;
        _errorMessage = null;
      });
      _applyFilters();
      _revalidateChildren();
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await _fetchAndCacheChildren();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchAndCacheChildren() async {
    final mothersResponse = await Supabase.instance.client
        .from('mothers')
        .select('mother_id')
        .eq('assigned_bhc_id', _assignedBhcId!)
        .timeout(const Duration(seconds: 8))
        .catchError((e) {
          debugPrint('Children mothers fetch note: $e');
          return <Map<String, dynamic>>[];
        });
    
    final List<int> motherIds = [];
    for (var mother in mothersResponse) {
      motherIds.add(mother['mother_id'] as int);
    }
    
    List<Map<String, dynamic>> childrenList = [];
    
    if (motherIds.isNotEmpty) {
      final childrenWithMother = await Supabase.instance.client
          .from('children')
          .select('''
            *,
            mother:mother_id (
              mother_id,
              account:account_id (
                first_name,
                last_name
              )
            ),
            guardian:guardian_id (
              guardian_id,
              first_name,
              last_name,
              relationship
            ),
            birth_details (
              birthdate,
              birth_weight,
              birth_length
            )
          ''')
          .inFilter('mother_id', motherIds)
          .timeout(const Duration(seconds: 8))
          .catchError((e) {
            debugPrint('Children query note: $e');
            return <Map<String, dynamic>>[];
          });
      
      childrenList.addAll(List<Map<String, dynamic>>.from(childrenWithMother));
    }
    
    final childrenWithGuardianOnly = await Supabase.instance.client
        .from('children')
        .select('''
          *,
          mother:mother_id (
            mother_id,
            account:account_id (
              first_name,
              last_name
            )
          ),
          guardian:guardian_id (
            guardian_id,
            first_name,
            last_name,
            relationship
          ),
          birth_details (
            birthdate,
            birth_weight,
            birth_length
          )
        ''')
        .filter('mother_id', 'is', null)
        .not('guardian_id', 'is', null)
        .timeout(const Duration(seconds: 8))
        .catchError((e) {
          debugPrint('Children with guardian query note: $e');
          return <Map<String, dynamic>>[];
        });
    
    childrenList.addAll(List<Map<String, dynamic>>.from(childrenWithGuardianOnly));
    
    final seenIds = <int>{};
    childrenList = childrenList.where((child) {
      final id = child['child_id'] as int;
      if (seenIds.contains(id)) return false;
      seenIds.add(id);
      return true;
    }).toList();

    // Read the persisted NAK number rather than deriving one from list order —
    // an index-based id changes whenever the list is filtered or re-sorted.
    for (var child in childrenList) {
      child['bhc_child_id'] =
          SupabaseService.formatChildNumber(child['child_number'] as int?);
    }

    childrenList.sort((a, b) {
      final dateA = DateTime.tryParse(a['added_at'] ?? '');
      final dateB = DateTime.tryParse(b['added_at'] ?? '');
      if (dateA == null || dateB == null) return 0;
      return dateB.compareTo(dateA);
    });

    _childrenCache = childrenList;
    
    if (mounted) {
      setState(() {
        _children = childrenList;
        _loading = false;
      });
      _applyFilters();
    }
  }

  Future<void> _revalidateChildren() async {
    try {
      final mothersResponse = await Supabase.instance.client
          .from('mothers')
          .select('mother_id')
          .eq('assigned_bhc_id', _assignedBhcId!);
      
      final List<int> motherIds = [];
      for (var mother in mothersResponse) {
        motherIds.add(mother['mother_id'] as int);
      }
      
      List<Map<String, dynamic>> childrenList = [];
      
      if (motherIds.isNotEmpty) {
        final childrenWithMother = await Supabase.instance.client
            .from('children')
            .select('''
              *,
              mother:mother_id (
                mother_id,
                account:account_id (
                  first_name,
                  last_name
                )
              ),
              guardian:guardian_id (
                guardian_id,
                first_name,
                last_name,
                relationship
              ),
              birth_details (
                birthdate,
                birth_weight,
                birth_length
              )
            ''')
            .inFilter('mother_id', motherIds);
        
        childrenList.addAll(List<Map<String, dynamic>>.from(childrenWithMother));
      }
      
      final childrenWithGuardianOnly = await Supabase.instance.client
          .from('children')
          .select('''
            *,
            mother:mother_id (
              mother_id,
              account:account_id (
                first_name,
                last_name
              )
            ),
            guardian:guardian_id (
              guardian_id,
              first_name,
              last_name,
              relationship
            ),
            birth_details (
              birthdate,
              birth_weight,
              birth_length
            )
          ''')
          .filter('mother_id', 'is', null)
          .not('guardian_id', 'is', null);
      
      childrenList.addAll(List<Map<String, dynamic>>.from(childrenWithGuardianOnly));
      
      final seenIds = <int>{};
      childrenList = childrenList.where((child) {
        final id = child['child_id'] as int;
        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      }).toList();

      for (var child in childrenList) {
        child['bhc_child_id'] =
            SupabaseService.formatChildNumber(child['child_number'] as int?);
      }

      childrenList.sort((a, b) {
        final dateA = DateTime.tryParse(a['added_at'] ?? '');
        final dateB = DateTime.tryParse(b['added_at'] ?? '');
        if (dateA == null || dateB == null) return 0;
        return dateB.compareTo(dateA);
      });

      bool hasChanges = false;
      if (_childrenCache == null || _childrenCache!.length != childrenList.length) {
        hasChanges = true;
      } else {
        for (int i = 0; i < childrenList.length; i++) {
          final c1 = childrenList[i];
          final c2 = _childrenCache!.firstWhere(
            (c) => c['child_id'] == c1['child_id'],
            orElse: () => {},
          );
          if (c2.isEmpty ||
              c1['first_name'] != c2['first_name'] ||
              c1['last_name'] != c2['last_name'] ||
              c1['guardian_id'] != c2['guardian_id']) {
            hasChanges = true;
            break;
          }
        }
      }

      if (hasChanges && mounted) {
        _childrenCache = childrenList;
        setState(() {
          _children = childrenList;
        });
        _applyFilters();
      }
    } catch (e) {
      debugPrint('Error revalidating children: $e');
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Map<String, dynamic>> results = List.from(_children);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      results = results.where((child) {
        final firstName = (child['first_name'] ?? '').toString().toLowerCase();
        final lastName = (child['last_name'] ?? '').toString().toLowerCase();
        final fullName = '$firstName $lastName';
        return fullName.contains(_searchQuery) || firstName.contains(_searchQuery) || lastName.contains(_searchQuery);
      }).toList();
    }

    // Apply gender filter
    if (_selectedGenderFilter != 'All') {
      results = results.where((child) {
        final sex = child['sex']?.toString().toLowerCase() ?? '';
        return sex == _selectedGenderFilter.toLowerCase();
      }).toList();
    }

    // Apply sorting
    if (_selectedSort == 'ID Number') {
      results.sort((a, b) => (a['child_id'] as int? ?? 0).compareTo(b['child_id'] as int? ?? 0));
    } else if (_selectedSort == 'Name (A-Z)') {
      results.sort((a, b) {
        final nameA = '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim().toLowerCase();
        final nameB = '${b['first_name'] ?? ''} ${b['last_name'] ?? ''}'.trim().toLowerCase();
        return nameA.compareTo(nameB);
      });
    } else if (_selectedSort == 'Age (Ascending)') {
      results.sort((a, b) {
        final detailsA = a['birth_details'] as Map<String, dynamic>?;
        final detailsB = b['birth_details'] as Map<String, dynamic>?;
        final dateA = DateTime.tryParse(detailsA?['birthdate']?.toString() ?? '') ?? DateTime(1970);
        final dateB = DateTime.tryParse(detailsB?['birthdate']?.toString() ?? '') ?? DateTime(1970);
        return dateB.compareTo(dateA);
      });
    } else if (_selectedSort == 'Age (Descending)') {
      results.sort((a, b) {
        final detailsA = a['birth_details'] as Map<String, dynamic>?;
        final detailsB = b['birth_details'] as Map<String, dynamic>?;
        final dateA = DateTime.tryParse(detailsA?['birthdate']?.toString() ?? '') ?? DateTime(1970);
        final dateB = DateTime.tryParse(detailsB?['birthdate']?.toString() ?? '') ?? DateTime(1970);
        return dateA.compareTo(dateB);
      });
    }

    setState(() {
      _filteredChildren = results;
    });
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedSort = 'ID Number';
      _selectedGenderFilter = 'All';
      _applyFilters();
    });
  }

  void _showFilterSortDialog() {
    String tempSort = _selectedSort;
    String tempGender = _selectedGenderFilter;

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
                        'ID Number',
                        'Name (A-Z)',
                        'Age (Ascending)',
                        'Age (Descending)'
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
                          selectedColor: AppColors.brandPrimary,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppColors.brandPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          side: const BorderSide(
                            color: AppColors.brandPrimary,
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    const Text('Filter by Gender',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          ['All', 'Male', 'Female'].map((genderOption) {
                        final isSelected = tempGender == genderOption;
                        return ChoiceChip(
                          label: Text(genderOption),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() => tempGender = genderOption);
                            }
                          },
                          selectedColor: AppColors.brandPrimary,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppColors.brandPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          side: const BorderSide(
                            color: AppColors.brandPrimary,
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedSort = tempSort;
                            _selectedGenderFilter = tempGender;
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

  Widget _buildPaginationWidget(int totalChildren) {
    final totalPages = (totalChildren / _pageSize).ceil();
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
                      color: isCurrent ? AppColors.brandPrimary : Colors.transparent,
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

  String _formatAge(DateTime? birthdate) {
    if (birthdate == null) return 'Age unknown';
    final now = DateTime.now();
    int years = now.year - birthdate.year;
    int months = now.month - birthdate.month;
    int days = now.day - birthdate.day;

    if (days < 0) {
      months -= 1;
      final prevMonthDate = DateTime(now.year, now.month, 0);
      days += prevMonthDate.day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }

    if (years > 0) {
      final monthPart = months > 0 ? ', $months month${months != 1 ? 's' : ''}' : '';
      return '$years year${years != 1 ? 's' : ''}$monthPart old';
    } else if (months > 0) {
      final weeks = days ~/ 7;
      final weekPart = weeks > 0 ? ', $weeks week${weeks != 1 ? 's' : ''}' : '';
      return '$months month${months != 1 ? 's' : ''}$weekPart old';
    } else {
      if (days >= 7) {
        final weeks = days ~/ 7;
        final remainingDays = days % 7;
        final dayPart = remainingDays > 0 ? ', $remainingDays day${remainingDays != 1 ? 's' : ''}' : '';
        return '$weeks week${weeks != 1 ? 's' : ''}$dayPart old';
      } else if (days > 0) {
        return '$days day${days != 1 ? 's' : ''} old';
      } else {
        return 'Newborn';
      }
    }
  }

  String _getParentName(Map<String, dynamic> child) {
    final mother = child['mother'] as Map<String, dynamic>?;
    if (mother != null) {
      final account = mother['account'] as Map<String, dynamic>?;
      if (account != null) {
        final firstName = account['first_name']?.toString() ?? '';
        final lastName = account['last_name']?.toString() ?? '';
        return 'Mother: $firstName $lastName';
      }
    }
    
    final guardian = child['guardian'] as Map<String, dynamic>?;
    if (guardian != null) {
      final firstName = guardian['first_name']?.toString() ?? '';
      final lastName = guardian['last_name']?.toString() ?? '';
      final relationship = guardian['relationship']?.toString() ?? 'Guardian';
      return '$relationship: $firstName $lastName';
    }
    
    return 'No parent record';
  }

  Future<void> _addChild() async {
    if (_assignedBhcId == null) return;

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddChildChoicePage(assignedBhcId: _assignedBhcId!),
      ),
    );
    if (mounted) {
      _fetchChildren(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pagination slicing
    final startIndex = (_currentPage - 1) * _pageSize;
    final endIndex = startIndex + _pageSize;
    final displayedChildren = _filteredChildren.sublist(
      startIndex,
      endIndex > _filteredChildren.length ? _filteredChildren.length : endIndex,
    );

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
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
                      padding: const EdgeInsets.only(right: 16.0, top: 4.0, bottom: 4.0),
                      child: Image.asset('assets/images/baby.png', fit: BoxFit.contain),
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
                          'Children Directory',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brandText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Track health growth and immunizations',
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

            // Search and Sort/Filter Row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppInputField(
                      hintText: 'Search child by name',
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
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: (_selectedSort != 'ID Number' ||
                              _selectedGenderFilter != 'All' ||
                              _searchQuery.isNotEmpty)
                          ? AppColors.brandPrimary
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (_selectedSort != 'ID Number' ||
                                _selectedGenderFilter != 'All' ||
                                _searchQuery.isNotEmpty)
                            ? AppColors.brandPrimary
                            : AppColors.borderPrimary,
                        width: 1.5,
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.filter_list,
                        color: (_selectedSort != 'ID Number' ||
                                _selectedGenderFilter != 'All' ||
                                _searchQuery.isNotEmpty)
                            ? Colors.white
                            : AppColors.brandPrimary,
                      ),
                      onPressed: _showFilterSortDialog,
                      tooltip: 'Sort & Filter',
                    ),
                  ),
                  if (_selectedSort != 'ID Number' ||
                      _selectedGenderFilter != 'All' ||
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
                    (_searchQuery.isNotEmpty || _selectedGenderFilter != 'All')
                        ? 'Showing ${_filteredChildren.length} of ${_children.length} children'
                        : 'Total of ${_children.length} registered children',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_filteredChildren.length > _pageSize) ...[
                    _buildPaginationWidget(_filteredChildren.length),
                  ],
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _fetchChildren(forceRefresh: true),
                color: AppColors.brandPrimary,
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary))
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                                const SizedBox(height: 16),
                                Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                                const SizedBox(height: 16),
                                ElevatedButton(onPressed: () => _fetchChildren(forceRefresh: true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPrimary), child: const Text('Retry')),
                              ],
                            ),
                          )
                        : _filteredChildren.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.child_care_outlined, size: 64, color: AppColors.textSecondary),
                                    const SizedBox(height: 16),
                                    const Text('No children found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                    const SizedBox(height: 8),
                                    const Text('Tap the + button to add a child', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                itemCount: displayedChildren.length,
                                itemBuilder: (context, index) {
                                  final child = displayedChildren[index];
                                  final firstName = child['first_name']?.toString() ?? '';
                                  final lastName = child['last_name']?.toString() ?? '';
                                  final birthDetails = child['birth_details'] as Map<String, dynamic>?;
                                  final birthdate = birthDetails != null && birthDetails['birthdate'] != null ? DateTime.parse(birthDetails['birthdate']) : null;
                                  final age = _formatAge(birthdate);
                                  final parentName = _getParentName(child);
                                  final isGuardianChild = child['guardian_id'] != null && child['mother_id'] == null;
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _ChildCard(
                                      firstName: firstName,
                                      lastName: lastName,
                                      age: age,
                                      parentName: parentName,
                                      isGuardianChild: isGuardianChild,
                                      bhcChildId: child['bhc_child_id']?.toString(),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => ChildProfilePage(childId: child['child_id'] as int)),
                                        ).then((_) => _fetchChildren());
                                      },
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
        heroTag: 'fab_children',
        onPressed: _addChild,
        backgroundColor: AppColors.brandPrimary,
        foregroundColor: Colors.white,
        tooltip: 'Add Child',
        shape: const CircleBorder(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final String firstName;
  final String lastName;
  final String age;
  final String parentName;
  final bool isGuardianChild;
  final String? bhcChildId;
  final VoidCallback onTap;

  const _ChildCard({
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.parentName,
    required this.isGuardianChild,
    this.bhcChildId,
    required this.onTap,
  });

  String get fullName => '$firstName $lastName'.trim();

  String get _initials {
    final firstInitial = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final lastInitial = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    if (firstInitial.isNotEmpty && lastInitial.isNotEmpty) return '$firstInitial$lastInitial';
    return firstInitial.isNotEmpty ? firstInitial : 'C';
  }

  @override
  Widget build(BuildContext context) {
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
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFFEEF3),
                        Color(0xFFFFD5E2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _initials,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((bhcChildId != null && bhcChildId!.isNotEmpty) || isGuardianChild) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (bhcChildId != null && bhcChildId!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.brandPrimary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.brandPrimary.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  bhcChildId!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brandPrimary,
                                  ),
                                ),
                              ),
                            if (isGuardianChild)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.success.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: const Text(
                                  'Guardian',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        fullName.isEmpty ? 'Unnamed Child' : fullName,
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
                        age,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (parentName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          parentName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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