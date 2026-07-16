// lib/screens/midwife/midwife_children_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../services/auth_storage.dart';
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

  static List<Map<String, dynamic>>? _childrenCache;

  @override
  void initState() {
    super.initState();
    _loadMidwifeContext();
    _searchController.addListener(_filterChildren);
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
      
      final result = await Supabase.instance.client
          .from('midwives')
          .select('midwife_id, assigned_bhc_id')
          .eq('account_id', accountId)
          .single();

      _assignedBhcId = result['assigned_bhc_id'] as int;
      
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
        _filteredChildren = List<Map<String, dynamic>>.from(_childrenCache!);
        _loading = false;
        _errorMessage = null;
      });
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
        _filteredChildren = childrenList;
        _loading = false;
      });
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
          _filterChildren();
        });
      }
    } catch (e) {
      debugPrint('Error revalidating children: $e');
    }
  }

  void _filterChildren() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredChildren = List.from(_children);
      });
    } else {
      setState(() {
        _filteredChildren = _children.where((child) {
          final firstName = (child['first_name'] ?? '').toString().toLowerCase();
          final lastName = (child['last_name'] ?? '').toString().toLowerCase();
          final fullName = '$firstName $lastName';
          return fullName.contains(query) || firstName.contains(query) || lastName.contains(query);
        }).toList();
      });
    }
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
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 16),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 110,
              decoration: BoxDecoration(
                image: const DecorationImage(
                  image: AssetImage('assets/images/pinkbg.png'),
                  fit: BoxFit.cover,
                ),
                borderRadius: BorderRadius.circular(20),
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
                        const Text('Showing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                        Text('${_filteredChildren.length}/${_children.length} Children', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.brandPrimary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppInputField(
                hintText: 'Search child by name',
                controller: _searchController,
                leadingIcon: Icons.search,
              ),
            ),

            const SizedBox(height: 16),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Text(
                'Tap a child to view health records',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),

            const SizedBox(height: 8),

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
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                itemCount: _filteredChildren.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final child = _filteredChildren[index];
                                  final firstName = child['first_name']?.toString() ?? '';
                                  final lastName = child['last_name']?.toString() ?? '';
                                  final birthDetails = child['birth_details'] as Map<String, dynamic>?;
                                  final birthdate = birthDetails != null && birthDetails['birthdate'] != null ? DateTime.parse(birthDetails['birthdate']) : null;
                                  final age = _formatAge(birthdate);
                                  final parentName = _getParentName(child);
                                  final isGuardianChild = child['guardian_id'] != null && child['mother_id'] == null;
                                  
                                  return _ChildCard(
                                    firstName: firstName,
                                    lastName: lastName,
                                    age: age,
                                    parentName: parentName,
                                    isGuardianChild: isGuardianChild,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => ChildProfilePage(childId: child['child_id'] as int)),
                                      ).then((_) => _fetchChildren());
                                    },
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
  final VoidCallback onTap;

  const _ChildCard({
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.parentName,
    required this.isGuardianChild,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isGuardianChild ? AppColors.success.withValues(alpha: 0.3) : AppColors.brandPrimary.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _initials,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isGuardianChild ? AppColors.success : AppColors.brandPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary),
                              ),
                            ),
                            if (isGuardianChild) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
                                child: const Text('Guardian', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.success)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(age, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(isGuardianChild ? Icons.person_outline : Icons.pregnant_woman, size: 12, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(child: Text(parentName, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 24, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}