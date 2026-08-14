
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/growth_summary_card.dart';
import '../../widgets/hero_card.dart';
import '../../widgets/records_display_card.dart';
import '../../widgets/status_indicator.dart';
import '../../services/groq_service.dart';
import '../../services/growth_calculator.dart';
import '../../services/immunization_schedule.dart';
import '../../services/supabase_service.dart';
import 'add_growth_step1.dart';
import 'add_immunization_choice.dart';
import 'child_growth_list_page.dart';
import 'child_immunization_list_page.dart';

class ChildProfilePage extends StatefulWidget {
  final int childId;

  const ChildProfilePage({
    super.key,
    required this.childId,
  });

  @override
  State<ChildProfilePage> createState() => _ChildProfilePageState();
}

class _ChildProfilePageState extends State<ChildProfilePage> {
  bool loading = true;
  Map<String, dynamic>? childData;
  Map<String, dynamic>? birthData;
  Map<String, dynamic>? latestGrowth;
  List<Map<String, dynamic>> growthRecords = [];
  String? aiAnalysis;
  bool aiLoading = false;
  String? aiError;
  List<Map<String, dynamic>> immunizations = [];
  Map<String, dynamic>? guardianData;
  bool hasGuardian = false;

  @override
  void initState() {
    super.initState();
    fetchProfile();
  }

  Future<void> fetchProfile() async {
    setState(() => loading = true);

    try {
      final results = await Future.wait([
        Supabase.instance.client.from('children').select('''
          *,
          mother:mother_id (
            mother_id,
            barangay,
            city_municipality,
            province,
            account:account_id (
              first_name,
              last_name,
              middle_name,
              phone_number
            )
          ),
          guardian:guardian_id (
            guardian_id,
            first_name,
            last_name,
            middle_name,
            extension_name,
            phone_number,
            address,
            relationship
          ),
          registered_by:midwives!registered_by_midwife_id (
            midwife_id,
            account:account_id (first_name, last_name)
          )
        ''').eq('child_id', widget.childId).single().timeout(const Duration(seconds: 8)),
        Supabase.instance.client
            .from('birth_details')
            .select('*')
            .eq('child_id', widget.childId)
            .maybeSingle()
            .timeout(const Duration(seconds: 8))
            .catchError((e) {
              debugPrint('Child birth details note: $e');
              return null;
            }),
        Supabase.instance.client
            .from('child_growth_records')
            .select('*')
            .eq('child_id', widget.childId)
            .order('created_at', ascending: true)
            .timeout(const Duration(seconds: 8))
            .catchError((e) {
              debugPrint('Child growth records note: $e');
              return <Map<String, dynamic>>[];
            }),
        Supabase.instance.client
            .from('immunization_records')
            .select('''
              *,
              vaccine:vaccine_id (*)
            ''')
            .eq('child_id', widget.childId)
            .order('vaccination_date', ascending: false)
            .limit(5)
            .timeout(const Duration(seconds: 8))
            .catchError((e) {
              debugPrint('Child immunizations note: $e');
              return <Map<String, dynamic>>[];
            }),
      ]);

      final childResponse = results[0] as Map<String, dynamic>;
      final birthResponse = results[1] as Map<String, dynamic>?;
      final growthResponse = (results[2] as List<dynamic>?) ?? [];
      final immunizationResponse = (results[3] as List<dynamic>?) ?? [];

      childData = childResponse;

      final guardian = childResponse['guardian'] as Map<String, dynamic>?;
      hasGuardian = guardian != null && childResponse['mother_id'] == null;

      if (hasGuardian && guardian != null) {
        guardianData = guardian;
      }

      birthData = birthResponse;

      growthRecords = List<Map<String, dynamic>>.from(growthResponse);
      latestGrowth = growthRecords.isNotEmpty ? growthRecords.last : null;

      if (latestGrowth != null && latestGrowth!['child_details_id'] != null) {
        await _loadProfileAiInsight(latestGrowth!['child_details_id'] as int)
            .catchError((e) => debugPrint('AI insight note: $e'));
      }

      immunizations = List<Map<String, dynamic>>.from(immunizationResponse);

      if (mounted) {
        setState(() => loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String calculateAge() {
    if (birthData == null) return 'Unknown age';
    final birthdate = birthData!['birthdate']?.toString();
    if (birthdate == null || birthdate.isEmpty) return 'Unknown age';

    try {
      final birth = DateTime.parse(birthdate);
      final now = DateTime.now();

      int years = now.year - birth.year;
      int months = now.month - birth.month;
      int days = now.day - birth.day;

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
    } catch (e) {
      return 'Unknown age';
    }
  }

  /// The child's date of birth, or null when no birth record exists.
  DateTime? get _birthdate {
    final raw = birthData?['birthdate']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  int _ageInWeeks(DateTime recordDate) {
    if (birthData == null) return 0;
    final birthdate = birthData!['birthdate']?.toString();
    if (birthdate == null || birthdate.isEmpty) return 0;

    try {
      final birth = DateTime.parse(birthdate);
      final difference = recordDate.difference(birth);
      return (difference.inDays / 7).round();
    } catch (_) {
      return 0;
    }
  }

  double _calculateBMI(double heightCm, double weightKg) {
    if (heightCm <= 0 || weightKg <= 0) return 0;
    final heightM = heightCm / 100.0;
    return weightKg / (heightM * heightM);
  }

  String formatDate(String? date) {
    if (date == null || date.isEmpty) return 'Not recorded';
    try {
      final parsed = DateTime.parse(date);
      return DateFormat('MMMM d, yyyy').format(parsed);
    } catch (e) {
      return date;
    }
  }

  String getParentName() {
    if (hasGuardian && guardianData != null) {
      final firstName = guardianData!['first_name']?.toString() ?? '';
      final lastName = guardianData!['last_name']?.toString() ?? '';
      return '$firstName $lastName';
    }

    final mother = childData?['mother'] as Map<String, dynamic>?;
    if (mother != null) {
      final account = mother['account'] as Map<String, dynamic>?;
      if (account != null) {
        final firstName = account['first_name']?.toString() ?? '';
        final lastName = account['last_name']?.toString() ?? '';
        return '$firstName $lastName';
      }
    }

    final firstName = childData?['first_name']?.toString() ?? '';
    final lastName = childData?['last_name']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();
    return fullName.isNotEmpty ? fullName : 'Child';
  }

  String getChildName() {
    final firstName = childData?['first_name']?.toString() ?? '';
    final lastName = childData?['last_name']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();
    return fullName.isNotEmpty ? fullName : 'Child';
  }

  String getParentRelationship() {
    if (hasGuardian && guardianData != null) {
      return guardianData!['relationship']?.toString() ?? 'Guardian';
    }
    return 'Mother';
  }

  /// Name of the midwife who registered this child.
  ///
  /// Children registered before registered_by_midwife_id existed have no
  /// registrar on file, and are reported as such rather than attributed to
  /// whoever happens to be viewing the record.
  String get _registeringMidwifeName {
    final registeredBy = childData?['registered_by'];
    if (registeredBy is! Map) return 'Not recorded';
    final account = registeredBy['account'];
    if (account is! Map) return 'Not recorded';
    final name =
        '${account['first_name'] ?? ''} ${account['last_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Not recorded' : name;
  }

  String getParentPhone() {
    if (hasGuardian && guardianData != null) {
      return guardianData!['phone_number']?.toString() ?? 'Not recorded';
    }
    final mother = childData?['mother'] as Map<String, dynamic>?;
    if (mother != null) {
      final account = mother['account'] as Map<String, dynamic>?;
      if (account != null) {
        return account['phone_number']?.toString() ?? 'Not recorded';
      }
    }
    return 'Not recorded';
  }

  String getParentAddress() {
    if (hasGuardian && guardianData != null) {
      return guardianData!['address']?.toString() ?? 'Not recorded';
    }
    final mother = childData?['mother'] as Map<String, dynamic>?;
    if (mother != null) {
      final barangay = mother['barangay']?.toString() ?? '';
      final city = mother['city_municipality']?.toString() ?? '';
      final province = mother['province']?.toString() ?? '';
      final parts = [barangay, city, province].where((p) => p.trim().isNotEmpty).toList();
      return parts.isNotEmpty ? parts.join(', ') : 'Not recorded';
    }
    return 'Not recorded';
  }

  String getBirthPlace() {
    final city = birthData?['birthplace_city_municipality']?.toString() ?? '';
    final province = birthData?['birthplace_province']?.toString() ?? '';
    final facility = birthData?['birthplace_facility']?.toString() ?? '';

    final parts = [facility, city, province].where((p) => p.isNotEmpty);
    return parts.isNotEmpty ? parts.join(', ') : 'Not recorded';
  }

  void _showAddOptionsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            const Text(
              'Add Record',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the type of record to add',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),

            // Options
            Row(
              children: [
                Expanded(
                  child: _buildAddOptionCard(
                    icon: Icons.trending_up,
                    title: 'Growth',
                    subtitle: 'Height & Weight',
                    color: AppColors.brandPrimary,
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToAddGrowth();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAddOptionCard(
                    icon: Icons.vaccines,
                    title: 'Immunization',
                    subtitle: 'Vaccine Record',
                    color: AppColors.success,
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToAddImmunization();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToAddGrowth() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddGrowthStep1(childId: widget.childId),
      ),
    );
    if (result == true && mounted) {
      fetchProfile();
    }
  }

  Future<void> _navigateToAddImmunization() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddImmunizationChoicePage(childId: widget.childId),
      ),
    );
    if (result == true && mounted) {
      fetchProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.brandPrimary,
          ),
        ),
      );
    }

    if (childData == null) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: SecondaryHeader(
            title: 'Child Information',
            onBack: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Failed to load child profile',
                style: TextStyle(color: AppColors.error, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: fetchProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                ),
                child:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final fullName =
        '${childData!['first_name']} ${childData!['last_name']}'.trim();
    final age = calculateAge();
    final sex = (childData!['sex'] ?? '').toString();
    final birthPlace = getBirthPlace();
    final parentName = getParentName();
    final parentRelationship = getParentRelationship();

    final displayHeight = latestGrowth != null
        ? '${(latestGrowth!['child_height'] as num?)?.toStringAsFixed(1) ?? '0'} cm'
        : 'Not recorded';

    final displayWeight = latestGrowth != null
        ? '${(latestGrowth!['child_weight'] as num?)?.toStringAsFixed(1) ?? '0'} kg'
        : 'Not recorded';

    final latestBMI = _getLatestBMI();
    final bmiStatus = latestBMI != null ? _bmiStatus(latestBMI) : null;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Child Information',
          onBack: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_child_profile',
        onPressed: _showAddOptionsModal,
        backgroundColor: AppColors.brandPrimary,
        // Circular, matching every other FAB in the app. Material 3 defaults to
        // a rounded rectangle without this.
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // ── Hero Card ──────────────────────────────────────
              HeroCard(
                image: null,
                title: fullName.isNotEmpty ? fullName : 'Unnamed Child',
                subtitle: age,
                sex: sex,
                showWeekBadge: false,
                showHeartRow: false,
              ),

              // ── Child Number ───────────────────────────────────
              // Hidden when absent rather than showing a placeholder id, so a
              // child registered before the child_number migration simply has
              // no badge instead of a misleading one.
              if (SupabaseService.formatChildNumber(
                    childData?['child_number'] as int?,
                  ) !=
                  null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.brandPrimary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    SupabaseService.formatChildNumber(
                      childData?['child_number'] as int?,
                    )!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandPrimary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Quick Stats ────────────────────────────────────
              _buildQuickStatsRow(displayHeight, displayWeight),

              const SizedBox(height: 24),

              // ── Parent / Guardian ──────────────────────────────
              _buildGuardianCard(parentName, parentRelationship),

              const SizedBox(height: 16),

              // ── Birth Details ──────────────────────────────────
              RecordsDisplayCard(
                title: 'Birth Details',
                headerIcon: Icons.cake_outlined,
                items: [
                  RecordItem(
                    leadingIcon: Icons.calendar_month_rounded,
                    label: 'Birth Date',
                    value: formatDate(birthData?['birthdate']),
                  ),
                  RecordItem(
                    leadingIcon: Icons.place_outlined,
                    label: 'Birthplace',
                    value: birthPlace,
                  ),
                  RecordItem(
                    leadingIcon: Icons.straighten_outlined,
                    label: 'Birth Length',
                    value: birthData?['birth_length'] != null
                        ? '${birthData!['birth_length']} cm'
                        : 'Not recorded',
                  ),
                  RecordItem(
                    leadingIcon: Icons.monitor_weight_outlined,
                    label: 'Birth Weight',
                    value: birthData?['birth_weight'] != null
                        ? '${birthData!['birth_weight']} kg'
                        : 'Not recorded',
                  ),
                  RecordItem(
                    leadingIcon: Icons.badge_outlined,
                    label: 'Registered by',
                    value: _registeringMidwifeName,
                  ),
                ],
              ),

              _buildSectionDivider(),

              // ── Growth & Development ──────────────────────────
              // No section header here: the card states its own title and
              // carries the "View history" link, so a header above it would
              // repeat both.
              _buildProfileAiCard(),

              _buildSectionDivider(),

              // ── Immunization ───────────────────────────────────
              _buildSectionHeader(
                title: 'Immunization',
                icon: Icons.vaccines_outlined,
                onViewAll: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ChildImmunizationListPage(childId: widget.childId),
                    ),
                  ).then((_) => fetchProfile());
                },
              ),
              const SizedBox(height: 12),

              RecordsDisplayCard(
                title: 'Recent Immunizations',
                headerIcon: Icons.vaccines_outlined,
                items: immunizations.isEmpty
                    ? [
                        RecordItem(
                          leadingIcon: Icons.info_outline,
                          label: 'Status',
                          value: 'No immunization records yet',
                        ),
                      ]
                    : immunizations.map((imm) {
                        final vaccine = imm['vaccine'] as Map<String, dynamic>?;
                        final doseNum = vaccine?['dose_number'];
                        // Judged, not assumed. This was previously the literal
                        // StatusIndicatorType.onTime, so a dose given ten
                        // months late still read "On Time".
                        final timeliness =
                            ImmunizationSchedule.timelinessOfRecord(
                          imm,
                          birthdate: _birthdate,
                        );
                        return RecordItem(
                          leadingIcon: Icons.vaccines,
                          label: vaccine?['vaccine_name'] ?? 'Unknown Vaccine',
                          subLabel: doseNum != null ? 'Dose $doseNum' : null,
                          value: formatDate(imm['vaccination_date']),
                          trailingWidget: timeliness == null
                              ? null
                              : StatusIndicator(status: timeliness),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChildImmunizationListPage(
                                    childId: widget.childId),
                              ),
                            ).then((_) => fetchProfile());
                          },
                        );
                      }).toList(),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStatsRow(String height, String weight) {
    return Row(
      children: [
        Expanded(
          child: _buildQuickStatCard(
            icon: Icons.height,
            label: 'Height',
            value: height,
            color: AppColors.brandPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            icon: Icons.monitor_weight,
            label: 'Weight',
            value: weight,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            icon: Icons.vaccines,
            label: 'Vaccines',
            value: '${immunizations.length}',
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  double? _getLatestBMI() {
    if (latestGrowth == null) return null;
    final heightCm = (latestGrowth!['child_height'] as num?)?.toDouble() ?? 0;
    final weightKg = (latestGrowth!['child_weight'] as num?)?.toDouble() ?? 0;
    if (heightCm <= 0 || weightKg <= 0) return null;
    final heightM = heightCm / 100;
    if (heightM <= 0) return null;
    return weightKg / (heightM * heightM);
  }
  static const double _whoStandardSd = GrowthCalculator.whoStandardSd;

  static String _bandForZScore(double? zScore) =>
      GrowthCalculator.bandLabel(zScore);

  String _bmiStatus(double bmi) {
    if (latestGrowth == null || childData == null) {
      return 'Within standard range';
    }
    final sex = (childData!['sex'] as String?) ?? 'female';
    final ageWeeks = _ageInWeeks(DateTime.parse(latestGrowth!['created_at']));
    return _bandForZScore(
      GrowthCalculator.calculateBMIZScore(bmi, ageWeeks, sex),
    );
  }

  Color _bmiStatusColor(String status) {
    switch (status) {
      case 'Below standard range':
      case 'Above standard range':
        return Colors.orange;
      case 'Within standard range':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }

  void _showReferenceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.info_outline, color: AppColors.brandPrimary),
            SizedBox(width: 8),
            Text('Growth Reference'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Our growth indicators are based on the World Health Organization (WHO) Child Growth Standards.',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 12),
              Text(
                'Z-scores compare a child\'s measurements (BMI-for-age, weight-for-age, height-for-age) to expected values for healthy growth:',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 8),
              Text('• Within standard range (Green): between -2 and +2 Z-score.', style: TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600)),
              Text('• Below standard range (Yellow): less than -2 Z-score.', style: TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w600)),
              Text('• Above standard range (Yellow): greater than +2 Z-score.', style: TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBMICard(double? bmi, String? status) {
    final isAvailable = bmi != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.monitor_weight,
                  color: AppColors.brandPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Body Mass Index',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _showReferenceDialog,
                      child: const Icon(
                        Icons.help_outline_rounded,
                        color: AppColors.textSecondary,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAvailable ? bmi.toStringAsFixed(1) : 'No data',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAvailable ? 'kg/m²' : 'Height or weight missing',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    // Classification label removed to avoid redundancy. Only badge chip remains.
                  ],
                ),
              ),
              if (isAvailable && status != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _bmiStatusColor(status).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _bmiStatusColor(status),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'This BMI value is calculated using the latest recorded height and weight.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAiCard() {
    if (latestGrowth == null || childData == null) {
      return const SizedBox.shrink();
    }

    return GrowthSummaryCard(
      childFirstName: (childData!['first_name'] as String?) ?? '',
      sex: ((childData!['sex'] as String?) ?? 'female').toLowerCase(),
      measurements: _growthMeasurements(),
      // AI narrative is written for a parent, so it stays on the mother app.
      // The midwife sees the rule-based summary instead.
      approvedBy: _registeringMidwifeName == 'Not recorded'
          ? null
          : _registeringMidwifeName,
      onViewHistory: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChildGrowthListPage(childId: widget.childId),
          ),
        ).then((_) => fetchProfile());
      },
    );
  }

  /// Growth records mapped into the shared card's input, oldest first.
  ///
  /// Birth measurements are prepended as the week-0 point, matching the Growth
  /// Records page. Without it the chart starts at the first clinic visit and
  /// the reference band looks flat, because every plotted point shares one age.
  List<GrowthMeasurement> _growthMeasurements() {
    final out = <GrowthMeasurement>[];

    final birthdateRaw = birthData?['birthdate']?.toString();
    final birthWeight = (birthData?['birth_weight'] as num?)?.toDouble();
    final birthLength = (birthData?['birth_length'] as num?)?.toDouble();
    if (birthdateRaw != null &&
        birthWeight != null &&
        birthLength != null &&
        birthWeight > 0 &&
        birthLength > 0) {
      final birthDate = DateTime.tryParse(birthdateRaw);
      if (birthDate != null) {
        out.add(GrowthMeasurement(
          takenAt: birthDate,
          heightCm: birthLength,
          weightKg: birthWeight,
          ageWeeks: 0,
        ));
      }
    }

    final sorted = List<Map<String, dynamic>>.from(growthRecords)
      ..sort((a, b) {
        final da = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final db = DateTime.tryParse(b['created_at']?.toString() ?? '');
        if (da == null || db == null) return 0;
        return da.compareTo(db);
      });

    for (final record in sorted) {
      final height = (record['child_height'] as num?)?.toDouble();
      final weight = (record['child_weight'] as num?)?.toDouble();
      final createdAt = record['created_at']?.toString();
      if (height == null || weight == null || createdAt == null) continue;
      if (height <= 0 || weight <= 0) continue;

      final takenAt = DateTime.parse(createdAt);
      out.add(GrowthMeasurement(
        takenAt: takenAt,
        heightCm: height,
        weightKg: weight,
        ageWeeks: _ageInWeeks(takenAt),
      ));
    }
    return out;
  }

  Future<void> _loadProfileAiInsight(int latestRecordId) async {
    if (!mounted) return;
    setState(() {
      aiLoading = true;
      aiError = null;
    });

    try {
      final saved = await Supabase.instance.client
          .from('ai_responses')
          .select('response, generated_by_ai')
          .eq('reference_table', 'child_growth_records')
          .eq('reference_id', latestRecordId)
          .eq('response_type', 'growth_analysis')
          .maybeSingle();

      if (saved != null) {
        final isGeneratedByAi = saved['generated_by_ai'] == true;
        if (saved['response'] != null &&
            saved['response'].toString().trim().isNotEmpty) {
          final savedText = saved['response'].toString().trim();
          final lower = savedText.toLowerCase();
          final isOldOrSingleLang = !lower.contains('english') ||
              !(lower.contains('filipino') || lower.contains('tagalog'));
          final isBulletFormat = savedText.contains('## Baby Growth Summary') ||
              savedText.contains('Buod ng Paglaki ng Bata');

          if (!isGeneratedByAi || isOldOrSingleLang || isBulletFormat) {
            await _generateAndSaveProfileAiInsight(latestRecordId);
          } else {
            aiAnalysis = savedText;
          }
        } else {
          await _generateAndSaveProfileAiInsight(latestRecordId);
        }
      } else {
        await _generateAndSaveProfileAiInsight(latestRecordId);
      }
    } catch (e) {
      aiError = 'Unable to load AI insight.';
      aiAnalysis = null;
    } finally {
      if (mounted) {
        setState(() => aiLoading = false);
      }
    }
  }

  Future<void> _generateAndSaveProfileAiInsight(int latestRecordId) async {
    if (growthRecords.isEmpty || childData == null || latestGrowth == null) {
      aiAnalysis = 'Not enough data for AI insight.';
      return;
    }

    try {
      final latestHeight =
          (latestGrowth!['child_height'] as num?)?.toDouble() ?? 0;
      final latestWeight =
          (latestGrowth!['child_weight'] as num?)?.toDouble() ?? 0;
      final latestBMI = _calculateBMI(latestHeight, latestWeight);
      final latestAgeWeeks =
          _ageInWeeks(DateTime.parse(latestGrowth!['created_at']));
      final sex = (childData!['sex'] as String?) ?? 'female';

      final prompt = _buildGrowthAiPrompt(
        childName: getChildName(),
        sex: sex,
        ageWeeks: latestAgeWeeks,
        height: latestHeight,
        weight: latestWeight,
        bmi: latestBMI,
        heightZ: GrowthCalculator.calculateHeightZScore(
            latestHeight, latestAgeWeeks, sex),
        weightZ: GrowthCalculator.calculateWeightZScore(
            latestWeight, latestAgeWeeks, sex),
        bmiZ:
            GrowthCalculator.calculateBMIZScore(latestBMI, latestAgeWeeks, sex),
      );

      final generated = await GroqService().generateTextInsight(
        prompt: prompt,
        systemPrompt: GroqService.childGrowthSystemPrompt,
        temperature: 0.2,
        maxOutputTokens: 2048,
      );

      aiAnalysis = generated.trim();
      await _saveProfileAiResponse(aiAnalysis!, latestRecordId);
    } catch (e) {
      aiError = 'AI insight could not be generated right now.';
      aiAnalysis = null;
    }
  }

  Future<void> _saveProfileAiResponse(
      String responseText, int latestRecordId) async {
    try {
      final existing = await Supabase.instance.client
          .from('ai_responses')
          .select('ai_response_id')
          .eq('reference_table', 'child_growth_records')
          .eq('reference_id', latestRecordId)
          .eq('response_type', 'growth_analysis')
          .maybeSingle();

      final values = {
        'reference_table': 'child_growth_records',
        'reference_id': latestRecordId,
        'response_type': 'growth_analysis',
        'response_category': 'growth',
        'generated_by_ai': true,
        'ai_model': 'groq',
        'status': 'generated',
        'response': responseText,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existing != null && existing['ai_response_id'] != null) {
        await Supabase.instance.client
            .from('ai_responses')
            .update(values)
            .eq('ai_response_id', existing['ai_response_id']);
      } else {
        values['created_at'] = DateTime.now().toIso8601String();
        await Supabase.instance.client.from('ai_responses').insert(values);
      }
    } catch (e) {
      debugPrint('Error saving profile AI response: $e');
    }
  }

  String _buildGrowthAiPrompt({
    required String childName,
    required String sex,
    required int ageWeeks,
    required double height,
    required double weight,
    required double bmi,
    required double? heightZ,
    required double? weightZ,
    required double? bmiZ,
  }) {
    final recordsSummary = growthRecords.map((record) {
      final heightVal = (record['child_height'] as num?)?.toDouble() ?? 0;
      final weightVal = (record['child_weight'] as num?)?.toDouble() ?? 0;
      final bmiVal = _calculateBMI(heightVal, weightVal);
      final weeks = _ageInWeeks(DateTime.parse(record['created_at']));
      return '- Week $weeks: ${heightVal.toStringAsFixed(1)} cm, ${weightVal.toStringAsFixed(1)} kg, BMI ${bmiVal.toStringAsFixed(1)}';
    }).join('\n');

    String getStatus(double? z) {
      if (z == null || z.isNaN || z.isInfinite) return 'Within standard range';
      return _bandForZScore(z);
    }

    final heightStatus = getStatus(heightZ);
    final weightStatus = getStatus(weightZ);
    final bmiStatus = getStatus(bmiZ);

    return '''
You are a warm, caring midwife assistant (like a loving ate or trusted midwife in a local health center) writing a short, gentle growth update for a parent.
Your tone must be gentle, comforting, and encouraging. Use simple, non-clinical language.
Do NOT use diagnostic terms or medical jargon (avoid terms like underweight, overweight, obesity, diagnosis, or clinical standard deviation).
Write EXACTLY 1 extremely short sentence of friendly, warm, non-diagnostic AI growth reassurance. Focus purely on comforting the parent and normalizing the child's growth.
Do NOT give any medical, dietary, lifestyle, or play suggestions (avoid suggestions like active play, sleep, feeding, or exercises).
Refer to the child by their first name or as "your little one" ("iyong munting anak" in Filipino) to make it personal and comforting.

Provide the response in both English and Filipino.
Use the exact output format below. Do not add extra sections, titles, bullet points, or tables.

Please carefully note the status indicators: "Within standard range", "Above standard range", or "Below standard range". 
- If any measurement is slightly above standard range, reassure the parent warmly and concisely (e.g. "Baby [Name] is growing well! Even though it seems like [his/her] [weight/height/BMI] is a bit higher than most babies [his/her] age, [he/she]'s gaining steadily and will catch up!").
- If any measurement is slightly below standard range, reassure them warmly and concisely (e.g. "Baby [Name] is growing well! Even though [his/her] [weight/height/BMI] is a bit lower than most babies [his/her] age, [he/she]'s growing steadily and will catch up at [his/her] own pace!").
- If everything is within expected range, celebrate their steady growth concisely (e.g. "Baby [Name] is doing great! [His/Her] growth is right on track, and [he/she] is growing steadily and beautifully!").

Output format:

## English
[Write exactly 1 sentence of friendly, warm, non-diagnostic AI growth reassurance here]

## Filipino
[Write exactly 1 sentence of friendly, warm, non-diagnostic AI growth reassurance in Tagalog here]

Child: $childName
Sex: ${sex.toLowerCase()}
Current age: $ageWeeks weeks
Latest measurements: Length: ${height.toStringAsFixed(1)} cm ($heightStatus), Weight: ${weight.toStringAsFixed(1)} kg ($weightStatus), BMI: ${bmi.toStringAsFixed(1)} kg/m² ($bmiStatus)
Recent growth:
$recordsSummary
''';
  }

  Widget _buildGuardianCard(String parentName, String parentRelationship) {
    final phone = getParentPhone();
    final address = getParentAddress();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasGuardian
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.brandPrimary.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasGuardian
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasGuardian ? Icons.person_outline : Icons.pregnant_woman,
                  color:
                      hasGuardian ? AppColors.success : AppColors.brandPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasGuardian ? 'Guardian Details' : 'Mother\'s Details',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hasGuardian
                          ? AppColors.success
                          : AppColors.brandPrimary,
                    ),
                  ),
                  Text(
                    hasGuardian ? parentRelationship : 'Primary Caregiver',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.person,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  parentName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          if (phone != 'Not recorded' && phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.phone_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (address != 'Not recorded' && address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required VoidCallback onViewAll,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.brandPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: onViewAll,
          child: const Text(
            'View All',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.brandPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.borderPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthCards(String height, String weight) {
    return Row(
      children: [
        Expanded(
          child: _buildGrowthDetailCard(
            icon: Icons.height,
            title: 'Height',
            value: height,
            color: AppColors.brandPrimary,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChildGrowthListPage(childId: widget.childId),
                ),
              ).then((_) => fetchProfile());
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildGrowthDetailCard(
            icon: Icons.monitor_weight,
            title: 'Weight',
            value: weight,
            color: AppColors.success,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChildGrowthListPage(childId: widget.childId),
                ),
              ).then((_) => fetchProfile());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGrowthDetailCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

