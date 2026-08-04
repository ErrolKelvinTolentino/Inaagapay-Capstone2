// lib/screens/midwife/add_child_select_mother.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/main_button.dart';
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';
import 'add_child_step3_child.dart';

class AddChildSelectMotherPage extends StatefulWidget {
  final int? assignedBhcId;

  const AddChildSelectMotherPage({
    super.key,
    this.assignedBhcId,
  });

  @override
  State<AddChildSelectMotherPage> createState() =>
      _AddChildSelectMotherPageState();
}

class _AddChildSelectMotherPageState extends State<AddChildSelectMotherPage> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allMothers = [];
  List<Map<String, dynamic>> _filteredMothers = [];
  Map<String, dynamic>? _selectedMother;
  bool _isLoading = true;
  String? _error;
  int? _bhcId;

  @override
  void initState() {
    super.initState();
    _bhcId = widget.assignedBhcId;
    _searchController.addListener(_onSearchChanged);
    _loadBhcMothers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredMothers = List.from(_allMothers);
      } else {
        _filteredMothers = _allMothers.where((mother) {
          final name = mother['display_name'].toString().toLowerCase();
          final patientId =
              mother['patient_id']?.toString().toLowerCase() ?? '';
          return name.contains(query) || patientId.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadBhcMothers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_bhcId == null) {
        final accountId = await AuthStorage.getUserId();
        if (accountId == null) throw Exception('Not authenticated');
        final result = await Supabase.instance.client
            .from('midwives')
            .select('assigned_bhc_id')
            .eq('account_id', accountId)
            .single();
        _bhcId = result['assigned_bhc_id'] as int?;
      }

      if (_bhcId == null) {
        throw Exception('No assigned BHC health center found.');
      }

      final response = await Supabase.instance.client
          .from('mothers')
          .select('''
            mother_id,
            account_id,
            assigned_bhc_id,
            account:account_id (
              first_name,
              last_name,
              status,
              is_verified
            )
          ''')
          .eq('assigned_bhc_id', _bhcId!);

      final List<Map<String, dynamic>> loadedMothers = [];
      for (var row in response) {
        final account = row['account'] as Map<String, dynamic>?;
        if (account == null ||
            account['status'] != 'active' ||
            account['is_verified'] != true) {
          continue;
        }

        final firstName = account['first_name']?.toString() ?? '';
        final lastName = account['last_name']?.toString() ?? '';
        final displayName = '$firstName $lastName'.trim();

        loadedMothers.add({
          'mother_id': row['mother_id'] as int,
          'account_id': row['account_id'] as int,
          'first_name': firstName,
          'last_name': lastName,
          'display_name': displayName.isEmpty ? 'Unknown Mother' : displayName,
        });
      }

      // Both lookups are batched: the picker used to fetch a profile picture
      // per mother, which meant one round trip per row.
      final patientNumbers = await SupabaseService.getPatientNumbersByAccountId(
        loadedMothers.map((m) => m['account_id'] as int).toList(),
        facilityId: _bhcId,
      );
      final childCounts = await SupabaseService.getChildCountsByMotherId(
        loadedMothers.map((m) => m['mother_id'] as int).toList(),
      );

      for (final mother in loadedMothers) {
        mother['patient_id'] = SupabaseService.formatPatientNumber(
          patientNumbers[mother['account_id'] as int],
        );
        mother['children_count'] = childCounts[mother['mother_id'] as int] ?? 0;
      }

      // Ordered by patient number so the list matches the numbering on the
      // physical charts. Mothers without a number yet sort last rather than
      // jumping to the top.
      loadedMothers.sort((a, b) {
        final numA = patientNumbers[a['account_id'] as int];
        final numB = patientNumbers[b['account_id'] as int];
        if (numA == null && numB == null) {
          return (a['display_name'] as String)
              .compareTo(b['display_name'] as String);
        }
        if (numA == null) return 1;
        if (numB == null) return -1;
        return numA.compareTo(numB);
      });

      if (mounted) {
        setState(() {
          _allMothers = loadedMothers;
          _filteredMothers = loadedMothers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onContinue() {
    if (_selectedMother == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddChildStep3Child(
          mode: ChildParentMode.registeredMother,
          motherId: _selectedMother!['mother_id'] as int,
          motherFirstName: _selectedMother!['first_name'] as String?,
          assignedBhcId: _bhcId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SecondaryHeader(
              title: 'Select Mother',
              onBack: () => Navigator.pop(context),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppInputField(
                hintText: 'Search by name or patient number',
                controller: _searchController,
                leadingIcon: Icons.search,
                trailingIcon:
                    _searchController.text.isNotEmpty ? Icons.clear : null,
                onTrailingTap: _searchController.clear,
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Only showing active mothers linked to your Barangay Health Center (BHC).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: MainButton(
                    label: 'Back',
                    leftIcon: Icons.arrow_back_ios_new_rounded,
                    isWhiteVariant: true,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MainButton(
                    label: 'Next',
                    rightIcon: Icons.arrow_forward_ios_rounded,
                    onPressed: _selectedMother != null ? _onContinue : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandPrimary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 160,
                child: MainButton(
                  label: 'Retry',
                  onPressed: _loadBhcMothers,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredMothers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No matching mothers found'
                  : 'No mothers linked to this BHC yet',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _filteredMothers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final mother = _filteredMothers[index];
        final isSelected =
            _selectedMother?['mother_id'] == mother['mother_id'];

        return _MotherPickerCard(
          patientId: mother['patient_id'] as String?,
          displayName: mother['display_name'] as String,
          childrenCount: mother['children_count'] as int? ?? 0,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedMother = mother),
        );
      },
    );
  }
}

/// Row in the mother picker.
///
/// Deliberately minimal: patient number, name, and how many children are
/// already registered. That is everything a midwife needs to pick the right
/// mother, and it keeps the row free of clinical data that has no bearing on
/// this decision.
class _MotherPickerCard extends StatelessWidget {
  final String? patientId;
  final String displayName;
  final int childrenCount;
  final bool isSelected;
  final VoidCallback onTap;

  const _MotherPickerCard({
    required this.patientId,
    required this.displayName,
    required this.childrenCount,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final childLabel =
        childrenCount == 1 ? '1 registered child' : '$childrenCount registered children';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.brandPrimary : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.brandPrimary.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              AppColors.brandPrimary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        patientId ?? '—',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandPrimary,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.child_care_outlined,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          childLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle : Icons.chevron_right,
                color: AppColors.brandPrimary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
