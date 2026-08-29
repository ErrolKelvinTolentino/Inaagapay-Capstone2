import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/hero_card.dart';
import '../../widgets/records_display_card.dart';
import '../../services/immunization_schedule.dart';
import '../../widgets/status_indicator.dart';
import '../../services/groq_service.dart';
import '../../widgets/growth_summary_card.dart';
import '../../services/growth_calculator.dart';
import '../../services/language_service.dart';

class MotherViewChildPage extends StatefulWidget {
  final VoidCallback onBackToChildren;
  final VoidCallback onViewGrowth;
  final VoidCallback onViewVaccines;
  final int childId;
  final String childName;
  final String childAge;
  final String childGender;

  const MotherViewChildPage({
    super.key,
    required this.onBackToChildren,
    required this.onViewGrowth,
    required this.onViewVaccines,
    required this.childId,
    required this.childName,
    required this.childAge,
    required this.childGender,
  });

  @override
  State<MotherViewChildPage> createState() => _MotherViewChildPageState();
}

class _MotherViewChildPageState extends State<MotherViewChildPage> {
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

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  @override
  void initState() {
    super.initState();
    fetchProfile();
  }

  Future<void> fetchProfile() async {
    setState(() => loading = true);

    try {
      final childResponse =
          await Supabase.instance.client.from('children').select('''
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
            )
          ''').eq('child_id', widget.childId).single();

      childData = childResponse;

      final guardian = childResponse['guardian'] as Map<String, dynamic>?;
      hasGuardian = guardian != null && childResponse['mother_id'] == null;

      if (hasGuardian && guardian != null) {
        guardianData = guardian;
      }

      final birthResponse = await Supabase.instance.client
          .from('birth_details')
          .select('*')
          .eq('child_id', widget.childId)
          .maybeSingle();

      birthData = birthResponse;

      final growthResponse = await Supabase.instance.client
          .from('child_growth_records')
          .select('*')
          .eq('child_id', widget.childId)
          .order('created_at', ascending: true);

      growthRecords = List<Map<String, dynamic>>.from(growthResponse);
      latestGrowth = growthRecords.isNotEmpty ? growthRecords.last : null;

      if (latestGrowth != null && latestGrowth!['child_details_id'] != null) {
        await _loadProfileAiInsight(latestGrowth!['child_details_id'] as int);
      }

      final immunizationResponse = await Supabase.instance.client
          .from('immunization_records')
          .select('''
            *,
            vaccine:vaccine_id (*)
          ''')
          .eq('child_id', widget.childId)
          .order('vaccination_date', ascending: false)
          .limit(5);

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
    if (date == null || date.isEmpty) {
      return _t('Not recorded', 'Hindi naitala');
    }
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
      return guardianData!['relationship']?.toString() ??
          _t('Guardian', 'Tagapag-alaga');
    }
    return _t('Mother', 'Ina');
  }

  String getParentPhone() {
    if (hasGuardian && guardianData != null) {
      return guardianData!['phone_number']?.toString() ??
          _t('Not recorded', 'Hindi naitala');
    }
    final mother = childData?['mother'] as Map<String, dynamic>?;
    if (mother != null) {
      final account = mother['account'] as Map<String, dynamic>?;
      if (account != null) {
        return account['phone_number']?.toString() ??
            _t('Not recorded', 'Hindi naitala');
      }
    }
    return _t('Not recorded', 'Hindi naitala');
  }

  String getParentAddress() {
    if (hasGuardian && guardianData != null) {
      return guardianData!['address']?.toString() ??
          _t('Not recorded', 'Hindi naitala');
    }
    final mother = childData?['mother'] as Map<String, dynamic>?;
    if (mother != null) {
      final barangay = mother['barangay']?.toString() ?? '';
      final city = mother['city_municipality']?.toString() ?? '';
      final province = mother['province']?.toString() ?? '';
      final parts = [barangay, city, province].where((p) => p.trim().isNotEmpty).toList();
      return parts.isNotEmpty ? parts.join(', ') : _t('Not recorded', 'Hindi naitala');
    }
    return _t('Not recorded', 'Hindi naitala');
  }

  String getBirthPlace() {
    final city = birthData?['birthplace_city_municipality']?.toString() ?? '';
    final province = birthData?['birthplace_province']?.toString() ?? '';
    final facility = birthData?['birthplace_facility']?.toString() ?? '';

    final parts = [facility, city, province].where((p) => p.isNotEmpty);
    return parts.isNotEmpty
        ? parts.join(', ')
        : _t('Not recorded', 'Hindi naitala');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return _buildContent(context);
      },
    );
  }

  Widget _buildContent(BuildContext context) {
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
            title: _t('Child Information', 'Impormasyon ng Anak'),
            onBack: widget.onBackToChildren,
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
        : _t('Not recorded', 'Hindi naitala');

    final displayWeight = latestGrowth != null
        ? '${(latestGrowth!['child_weight'] as num?)?.toStringAsFixed(1) ?? '0'} kg'
        : _t('Not recorded', 'Hindi naitala');

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: _t('Child Information', 'Impormasyon ng Anak'),
          onBack: widget.onBackToChildren,
        ),
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

              const SizedBox(height: 20),

              // ── Quick Stats ────────────────────────────────────
              _buildQuickStatsRow(displayHeight, displayWeight),

              const SizedBox(height: 24),

              // ── Parent / Guardian ──────────────────────────────
              _buildGuardianCard(parentName, parentRelationship),

              const SizedBox(height: 16),

              // ── Birth Details ──────────────────────────────────
              RecordsDisplayCard(
                title: _t('Birth Details', 'Detalye ng Kapanganakan'),
                headerIcon: Icons.cake_outlined,
                items: [
                  RecordItem(
                    leadingIcon: Icons.calendar_month_rounded,
                    label: _t('Birth Date', 'Petsa ng Kapanganakan'),
                    value: formatDate(birthData?['birthdate']),
                  ),
                  RecordItem(
                    leadingIcon: Icons.place_outlined,
                    label: _t('Birthplace', 'Lugar ng Kapanganakan'),
                    value: birthPlace,
                  ),
                  RecordItem(
                    leadingIcon: Icons.straighten_outlined,
                    label: _t('Birth Length', 'Haba sa Kapanganakan'),
                    value: birthData?['birth_length'] != null
                        ? '${birthData!['birth_length']} cm'
                        : _t('Not recorded', 'Hindi naitala'),
                  ),
                  RecordItem(
                    leadingIcon: Icons.monitor_weight_outlined,
                    label: _t('Birth Weight', 'Timbang sa Kapanganakan'),
                    value: birthData?['birth_weight'] != null
                        ? '${birthData!['birth_weight']} kg'
                        : _t('Not recorded', 'Hindi naitala'),
                  ),
                ],
              ),

              _buildSectionDivider(),

              // ── Growth & Development ──────────────────────────
              _buildSectionHeader(
                title: _t('Your child\'s growth', 'Paglaki ng iyong anak'),
                icon: Icons.trending_up,
              ),
              const SizedBox(height: 12),

              _buildGrowthAnalysisCard(),

              // Kept beside the shared card rather than inside it.
              //
              // Logging a measurement at home is the mother's own action and
              // has no equivalent on the midwife's profile, so it does not
              // belong in the card they both draw. It used to sit inside this
              // page's own growth card, and swapping that card out would have
              // quietly removed the only way she can add a height and weight
              // anywhere in the app — the growth page only reads.
              if (childData != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    button: true,
                    label: _t('Add a growth measurement',
                        'Magdagdag ng sukat ng paglaki'),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: FloatingActionButton(
                        key: const ValueKey<String>('add-growth-measurement'),
                        heroTag: 'add-growth-measurement',
                        onPressed: _showAddGrowthBottomSheet,
                        tooltip:
                            _t('Add a measurement', 'Magdagdag ng sukat'),
                        backgroundColor: AppColors.brandPrimary,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        shape: const CircleBorder(),
                        child: const Icon(Icons.add_rounded, size: 26),
                      ),
                    ),
                  ),
                ),
              ],

              _buildSectionDivider(),

              // ── Immunization ───────────────────────────────────
              _buildSectionHeader(
                title: _t('Immunization History', 'Kasaysayan ng Bakuna'),
                icon: Icons.vaccines_outlined,
                onViewAll: () {
                  widget.onViewVaccines();
                },
              ),
              const SizedBox(height: 12),

              RecordsDisplayCard(
                title: _t('Recent Immunizations', 'Mga Kamakailang Bakuna'),
                headerIcon: Icons.vaccines_outlined,
                items: immunizations.isEmpty
                    ? [
                        RecordItem(
                          leadingIcon: Icons.info_outline,
                          label: _t('Status', 'Status'),
                          value: _t('No immunization records yet',
                              'Wala pang naitalang bakuna'),
                        ),
                      ]
                    : immunizations.map((imm) {
                        final vaccine = imm['vaccine'] as Map<String, dynamic>?;
                        final doseNum = vaccine?['dose_number'];
                        // Judged rather than assumed — this was a hardcoded
                        // onTime, so every dose read on time however late.
                        final timeliness =
                            ImmunizationSchedule.timelinessOfRecord(
                          imm,
                          birthdate: _birthdate,
                        );
                        return RecordItem(
                          leadingIcon: Icons.vaccines,
                          label: vaccine?['vaccine_name'] ??
                              _t('Unknown Vaccine', 'Hindi Kilalang Bakuna'),
                          subLabel: doseNum != null ? '${_t('Dose', 'Dose')} $doseNum' : null,
                          value: formatDate(imm['vaccination_date']),
                          trailingWidget: timeliness == null
                              ? null
                              : StatusIndicator(status: timeliness),
                          onTap: () {
                            widget.onViewVaccines();
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
            label: _t('Height', 'Taas'),
            value: height,
            color: AppColors.brandPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            icon: Icons.monitor_weight,
            label: _t('Weight', 'Timbang'),
            value: weight,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            icon: Icons.vaccines,
            label: _t('Vaccines', 'Bakuna'),
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




  /// One colour, one plain sentence about what it means for her child.






  String? aiAnalysisCategory;

  /// Input styling that matches [AppInputField], which the rest of the app's
  /// forms use.
  ///
  /// Not `AppInputField` itself: that widget is fixed-height and single-line
  /// with its own error slot, and these two fields sit inside a `Form` and
  /// validate through it. Copying the look keeps the sheet in the same visual
  /// language without a second validation path to keep in step.
  InputDecoration _growthFieldDecoration({
    required String hint,
    required IconData icon,
  }) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: color, width: 1.5),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
      ),
      prefixIcon: Icon(icon, color: AppColors.brandAccent),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      enabledBorder: border(Colors.transparent),
      border: border(Colors.transparent),
      focusedBorder: border(AppColors.brandPrimary),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error),
    );
  }

  void _showAddGrowthBottomSheet() {
    final formKey = GlobalKey<FormState>();
    final heightCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    bool isSavingLocal = false;
    final childSex = (childData?['sex'] as String?) ?? 'female';
    final latestAgeWeeks = birthData != null && birthData!['birthdate'] != null
        ? _ageInWeeks(DateTime.now())
        : 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSheet) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              // The tinted ground the app's other sheets and dialogs use. On
              // white, the white input boxes below have nothing to sit on and
              // read as bare underlines.
              decoration: const BoxDecoration(
                color: Color(0xFFFFF7FA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _t('Log Growth Measurements', 'Itala ang Sukat ng Paglaki'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.headingSoft,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _t(
                        'Measurements you take at home appear in the chart straight away.',
                        'Ang mga sukat na kinuha mo sa bahay ay agad na lalabas sa tsart.',
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.inputText,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _t('Height (cm)', 'Taas (cm)'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.headingSoft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: heightCtrl,
                      decoration: _growthFieldDecoration(
                        hint: _t('e.g. 58.5', 'hal. 58.5'),
                        icon: Icons.height_rounded,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) {
                        if (val == null || val.isEmpty) return _t('Please enter height', 'Pakilagay ang taas');
                        final numVal = double.tryParse(val);
                        if (numVal == null || numVal <= 0) return _t('Please enter a valid height', 'Pakilagay ang tamang taas');
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _t('Weight (kg)', 'Timbang (kg)'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.headingSoft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: weightCtrl,
                      decoration: _growthFieldDecoration(
                        hint: _t('e.g. 5.4', 'hal. 5.4'),
                        icon: Icons.monitor_weight_outlined,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) {
                        if (val == null || val.isEmpty) return _t('Please enter weight', 'Pakilagay ang timbang');
                        final numVal = double.tryParse(val);
                        if (numVal == null || numVal <= 0) return _t('Please enter a valid weight', 'Pakilagay ang tamang timbang');
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isSavingLocal
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setStateSheet(() => isSavingLocal = true);

                                try {
                                  final height = double.parse(heightCtrl.text);
                                  final weight = double.parse(weightCtrl.text);
                                  final bmi = weight / ((height / 100) * (height / 100));

                                  // Insert into child_growth_records
                                  final insertResult = await Supabase.instance.client
                                      .from('child_growth_records')
                                      .insert({
                                    'child_id': widget.childId,
                                    'child_height': height,
                                    'child_weight': weight,
                                    'created_at': DateTime.now().toIso8601String(),
                                  }).select('child_details_id').single();

                                  final childDetailsId = insertResult['child_details_id'] as int;

                                  // Calculate local WHO classifications
                                  final heightZ = GrowthCalculator.calculateHeightZScore(height, latestAgeWeeks, childSex);
                                  final weightZ = GrowthCalculator.calculateWeightZScore(weight, latestAgeWeeks, childSex);
                                  final bmiZ = GrowthCalculator.calculateBMIZScore(bmi, latestAgeWeeks, childSex);

                                  final bmiDesc = _describeZScoreLocal(bmiZ);
                                  final weightDesc = _describeZScoreLocal(weightZ);
                                  final heightDesc = _describeZScoreLocal(heightZ);

                                  final bmiDescFil = _describeZScoreFilipinoLocal(bmiZ);
                                  final weightDescFil = _describeZScoreFilipinoLocal(weightZ);
                                  final heightDescFil = _describeZScoreFilipinoLocal(heightZ);

                                  final englishText = 'Full WHO-Based Evaluation at Week $latestAgeWeeks. The child\'s Weight is $weightDesc and BMI-for-Age is $bmiDesc. Height-for-Age is $heightDesc.';
                                  final filipinoText = 'Buong Pagsusuri base sa WHO sa Ika-$latestAgeWeeks na Linggo. Ang Timbang ng bata ay $weightDescFil at ang BMI ay $bmiDescFil. Ang Haba ay $heightDescFil.';
                                  final combinedText = '## English\n$englishText\n\n## Filipino\n$filipinoText';

                                  // Insert into ai_responses
                                  await Supabase.instance.client.from('ai_responses').insert({
                                    'reference_table': 'child_growth_records',
                                    'reference_id': childDetailsId,
                                    'response_type': 'growth_analysis',
                                    'response_category': 'growth_mother',
                                    'generated_by_ai': false,
                                    'ai_model': 'none',
                                    'status': 'generated',
                                    'response': combinedText,
                                    'updated_at': DateTime.now().toIso8601String(),
                                    'created_at': DateTime.now().toIso8601String(),
                                  });

                                  // Asynchronous background AI summary generation
                                  _runBackgroundAiAnalysis(childDetailsId, height, weight, bmi);

                                  Navigator.pop(ctx);
                                  // Refresh profile data
                                  fetchProfile();
                                } catch (e) {
                                  setStateSheet(() => isSavingLocal = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          elevation: 4,
                          shadowColor:
                              AppColors.brandPrimary.withValues(alpha: 0.4),
                        ),
                        child: isSavingLocal
                            // Sized down: an unbounded indicator inside a 56pt
                            // button expands to fill it and paints over its own
                            // edges.
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Text(
                                _t('Save Measurements',
                                    'I-save ang mga Sukat'),
                                style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The same growth card the midwife's child profile draws.
  ///
  /// This page had its own card, and the two had drifted into saying different
  /// things about the same child. It reported a single BMI figure — "Body size
  /// now 14.3 kg/m²" — which is not one of the indicators child growth is
  /// assessed on, and its insight only ever described height.
  ///
  /// The shared card carries weight-for-age, length/height-for-age and
  /// weight-for-length, an insight covering all three, and the WHO MGRS 2006
  /// attribution the numbers come from. A mother and her midwife looking at
  /// the same child now read the same assessment.
  ///
  /// One difference is deliberate and built into the card: she sees the
  /// approved AI narrative, written for a parent, where the midwife sees the
  /// rule-based summary.
  Widget _buildGrowthAnalysisCard() {
    if (latestGrowth == null || childData == null) {
      return const SizedBox.shrink();
    }

    return GrowthSummaryCard(
      childFirstName: (childData!['first_name'] as String?) ?? '',
      sex: ((childData!['sex'] as String?) ?? 'female').toLowerCase(),
      measurements: _growthMeasurements(),
      isFilipino:
          LanguageService.selectedLanguage.value == AppLanguage.filipino,
      aiInsight: aiAnalysis,
      onViewHistory: widget.onViewGrowth,
    );
  }

  /// Growth records mapped into the shared card's input, oldest first.
  ///
  /// Birth measurements are prepended as the week-0 point, the same as on the
  /// midwife's profile. Without it the chart starts at the first clinic visit
  /// and the reference band looks flat, because every plotted point shares
  /// roughly one age.
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

      final takenAt = DateTime.tryParse(createdAt);
      if (takenAt == null) continue;
      out.add(GrowthMeasurement(
        takenAt: takenAt,
        heightCm: height,
        weightKg: weight,
        ageWeeks: _ageInWeeks(takenAt),
      ));
    }
    return out;
  }

  String _describeZScoreLocal(double? zScore) {
    return GrowthCalculator.bandLabel(zScore);
  }

  String _describeZScoreFilipinoLocal(double? zScore) {
    return GrowthCalculator.bandForZScore(zScore).labelFilipino;
  }

  void _runBackgroundAiAnalysis(int childDetailsId, double height, double weight, double bmi) async {
    try {
      final childName = widget.childName;
      final sex = (childData?['sex'] as String?) ?? 'female';
      final latestAgeWeeks = birthData != null && birthData!['birthdate'] != null
          ? _ageInWeeks(DateTime.now())
          : 0;

      final heightZ = GrowthCalculator.calculateHeightZScore(height, latestAgeWeeks, sex);
      final weightZ = GrowthCalculator.calculateWeightZScore(weight, latestAgeWeeks, sex);
      final bmiZ = GrowthCalculator.calculateBMIZScore(bmi, latestAgeWeeks, sex);

      final prompt = _buildGrowthAiPrompt(
        childName: childName,
        sex: sex,
        ageWeeks: latestAgeWeeks,
        height: height,
        weight: weight,
        bmi: bmi,
        heightZ: heightZ,
        weightZ: weightZ,
        bmiZ: bmiZ,
      );

      final generated = await GroqService().generateTextInsight(
        prompt: prompt,
        systemPrompt: GroqService.childGrowthSystemPrompt,
        temperature: 0.2,
        maxOutputTokens: 2048,
      );

      final responseText = generated.trim();
      if (responseText.isNotEmpty) {
        await Supabase.instance.client
            .from('ai_responses')
            .update({
              'response': responseText,
              'generated_by_ai': true,
              'ai_model': 'groq',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('reference_table', 'child_growth_records')
            .eq('reference_id', childDetailsId)
            .eq('response_type', 'growth_analysis');
      }
    } catch (e) {
      debugPrint('Error in background growth AI analysis: $e');
    }
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
          .select('response, response_category, generated_by_ai')
          .eq('reference_table', 'child_growth_records')
          .eq('reference_id', latestRecordId)
          .eq('response_type', 'growth_analysis')
          .maybeSingle();

      if (saved != null) {
        aiAnalysisCategory = saved['response_category'];
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
        'response_category': aiAnalysisCategory ?? 'growth',
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

    String getStatus(double? z) => GrowthCalculator.bandLabel(z);

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
    final notRecordedText = _t('Not recorded', 'Hindi naitala');
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
                    hasGuardian
                        ? _t('Guardian Details', 'Mga Detalye ng Tagapag-alaga')
                        : _t('Mother\'s Details', 'Mga Detalye ng Ina'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hasGuardian
                          ? AppColors.success
                          : AppColors.brandPrimary,
                    ),
                  ),
                  Text(
                    hasGuardian ? parentRelationship : _t('Primary Caregiver', 'Pangunahing Tagapag-alaga'),
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

          if (phone != notRecordedText && phone.isNotEmpty) ...[
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
          if (address != notRecordedText && address.isNotEmpty) ...[
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

  /// [onViewAll] is optional now.
  ///
  /// The growth section drops it: the shared card already ends in "View
  /// History & Charts", so a "View All" in the header was a second link to the
  /// same page, sitting where a mother has not yet seen what she would be
  /// leaving.
  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    VoidCallback? onViewAll,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.headingSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            child: Text(
              _t('View All', 'Tingnan Lahat'),
              style: const TextStyle(
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


}
