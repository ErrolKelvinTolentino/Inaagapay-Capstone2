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
  State<AddChildSelectMotherPage> createState() => _AddChildSelectMotherPageState();
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
    if (query.isEmpty) {
      setState(() {
        _filteredMothers = List.from(_allMothers);
      });
    } else {
      setState(() {
        _filteredMothers = _allMothers.where((mother) {
          final name = mother['display_name'].toString().toLowerCase();
          final phone = mother['phone_number'].toString().toLowerCase();
          final email = mother['email_address'].toString().toLowerCase();
          return name.contains(query) || phone.contains(query) || email.contains(query);
        }).toList();
      });
    }
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
            birthdate,
            barangay,
            account:account_id (
              first_name,
              last_name,
              middle_name,
              extension_name,
              phone_number,
              email_address,
              status,
              is_verified
            ),
            pregnancies (
              pregnancy_id,
              status,
              pregnancy_risk_level,
              expected_date_of_delivery,
              last_menstrual_period
            )
          ''')
          .eq('assigned_bhc_id', _bhcId!);

      final List<Map<String, dynamic>> loadedMothers = [];
      for (var row in response) {
        final account = row['account'] as Map<String, dynamic>?;
        if (account != null &&
            account['status'] == 'active' &&
            account['is_verified'] == true) {
          final firstName = account['first_name']?.toString() ?? '';
          final lastName = account['last_name']?.toString() ?? '';
          final middleName = account['middle_name']?.toString() ?? '';
          final extensionName = account['extension_name']?.toString() ?? '';
          final displayName = '$firstName $lastName'.trim();

          // Extract ongoing pregnancy details
          final pregnanciesList = row['pregnancies'] as List<dynamic>? ?? [];
          Map<String, dynamic>? ongoingPregnancy;
          for (var p in pregnanciesList) {
            if (p is Map<String, dynamic> && p['status'] == 'ongoing') {
              ongoingPregnancy = p;
              break;
            }
          }

          String riskLevel = 'low';
          if (ongoingPregnancy != null) {
            riskLevel = ongoingPregnancy['pregnancy_risk_level'] as String? ?? 'low';
          }

          final motherId = row['mother_id'] as int;
          String? profilePictureUrl;
          try {
            profilePictureUrl = await SupabaseService.getProfilePictureUrl(motherId);
          } catch (e) {
            debugPrint('Error loading profile picture for mother $motherId: $e');
          }

          loadedMothers.add({
            'mother_id': motherId,
            'account_id': row['account_id'] as int,
            'first_name': firstName,
            'last_name': lastName,
            'middle_name': middleName,
            'extension_name': extensionName,
            'phone_number': account['phone_number']?.toString() ?? '',
            'email_address': account['email_address']?.toString() ?? '',
            'display_name': displayName.isEmpty ? 'Unknown Mother' : displayName,
            'risk_level': riskLevel,
            'profile_picture': profilePictureUrl,
          });
        }
      }

      loadedMothers.sort((a, b) => a['display_name'].compareTo(b['display_name']));

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
        ),
      ),
    );
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return AppColors.error;
      default:
        return AppColors.success;
    }
  }

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
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Select Mother',
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppInputField(
                hintText: 'Search Mother by name or email',
                controller: _searchController,
                leadingIcon: Icons.search,
                trailingIcon: _searchController.text.isNotEmpty ? Icons.clear : null,
                onTrailingTap: () {
                  _searchController.clear();
                },
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
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brandPrimary,
                      ),
                    )
                  : _error != null
                      ? Center(
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
                                ElevatedButton(
                                  onPressed: _loadBhcMothers,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brandPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: const Text('Retry', style: TextStyle(color: Colors.white)),
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
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                              itemCount: _filteredMothers.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final mother = _filteredMothers[index];
                                final isSelected = _selectedMother?['mother_id'] == mother['mother_id'];
                                final displayName = mother['display_name'] as String;
                                final phone = mother['phone_number'] as String;
                                final email = mother['email_address'] as String;
                                final riskLevel = mother['risk_level'] as String;
                                final profilePictureUrl = mother['profile_picture'] as String?;

                                final riskColor = _getRiskColor(riskLevel);
                                final initials = _getInitials(displayName);

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedMother = mother;
                                    });
                                  },
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
                                              child: profilePictureUrl != null && profilePictureUrl.isNotEmpty
                                                  ? Image.network(
                                                      profilePictureUrl,
                                                      width: 56,
                                                      height: 56,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context, error, stackTrace) {
                                                        return Center(
                                                          child: Text(
                                                            initials,
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
                                                        initials,
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
                                                Text(
                                                  displayName,
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                if (phone.isNotEmpty) ...[
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.phone_outlined, size: 12, color: AppColors.textSecondary),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        phone,
                                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                                if (email.isNotEmpty) ...[
                                                  const SizedBox(height: 1),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.email_outlined, size: 12, color: AppColors.textSecondary),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          email,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
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
                              },
                            ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                child: MainButton(
                  label: 'Continue',
                  onPressed: _selectedMother != null ? _onContinue : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
