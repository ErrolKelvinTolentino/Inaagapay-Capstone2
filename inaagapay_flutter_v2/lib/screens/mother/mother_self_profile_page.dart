import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_colors.dart';
import '../../services/language_service.dart';
import '../../services/mother_profile_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/profile_widgets.dart';
import 'mother_vitals_page.dart';

class MotherSelfProfilePage extends StatefulWidget {
  final int motherId;

  const MotherSelfProfilePage({super.key, required this.motherId});

  @override
  State<MotherSelfProfilePage> createState() => _MotherSelfProfilePageState();
}

class _MotherSelfProfilePageState extends State<MotherSelfProfilePage> {
  late Future<Map<String, dynamic>> _profileFuture;
  String? _profilePictureUrl;
  String? _patientNumber;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfile();
    _loadProfilePicture();
    _loadPatientNumber();
  }

  Future<Map<String, dynamic>> _fetchProfile() async {
    return await MotherProfileService.fetchMotherProfile(widget.motherId);
  }

  Future<void> _loadProfilePicture() async {
    final url = await SupabaseService.getProfilePictureUrl(widget.motherId);
    if (!mounted) return;
    setState(() => _profilePictureUrl = url);
  }

  Future<void> _loadPatientNumber() async {
    final number =
        await SupabaseService.getPatientNumberForMother(widget.motherId);
    if (!mounted) return;
    setState(() => _patientNumber = number);
  }

  Future<void> _refresh() async {
    setState(() {
      _profileFuture = _fetchProfile();
    });
    await Future.wait([
      _loadProfilePicture(),
      _loadPatientNumber(),
    ]);
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFFFF7FA),
        surfaceTintColor: const Color(0xFFFFF7FA),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('Add a photo', 'Magdagdag ng larawan'),
                style: const TextStyle(
                  color: AppColors.headingSoft,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 18),
              _photoSourceRow(
                ctx,
                icon: Icons.photo_library_rounded,
                label: _t('Choose from gallery', 'Pumili mula sa gallery'),
                source: ImageSource.gallery,
              ),
              const SizedBox(height: 10),
              _photoSourceRow(
                ctx,
                icon: Icons.camera_alt_rounded,
                label: _t('Take a photo now', 'Kumuha ng larawan ngayon'),
                source: ImageSource.camera,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoSourceRow(
    BuildContext dialogContext, {
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.pop(dialogContext);
          _pickImage(source);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDF4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.brandPrimary, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.headingSoft,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 85,
      );

      if (image == null) return;
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final bytes = await image.readAsBytes();
      final url =
          await SupabaseService.uploadProfilePicture(widget.motherId, bytes);

      if (!mounted) return;
      Navigator.pop(context);

      if (url != null) {
        setState(() {
          _profilePictureUrl = url;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimaryOf(context),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: _t('My Profile', 'Aking Profile'),
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                _t('Unable to load profile.', 'Hindi ma-load ang profile.'),
              ),
            );
          }

          final data = snapshot.data ?? {};
          final profile = data['profile'] as Map<String, dynamic>? ?? data;
          final medicalConditions = (data['medical_conditions'] as List?) ?? [];
          final allergies = (data['allergies'] as List?) ?? [];
          final emergencyContacts = (data['emergency_contacts'] as List?) ?? [];
          final children = (data['children'] as List?) ?? [];
          final pregnancies = (data['pregnancies'] as List?) ?? [];
          final currentPregnancy =
              data['current_pregnancy'] as Map<String, dynamic>?;

          final fullName = profile['full_name']?.toString() ?? '';
          final email = profile['email_address']?.toString() ??
              profile['account']?['email_address']?.toString();
          final phone = profile['phone_number']?.toString() ??
              profile['account']?['phone_number']?.toString();

          final age = profile['birthdate'] != null
              ? DateTime.now()
                      .difference(DateTime.parse(profile['birthdate']))
                      .inDays ~/
                  365
              : 0;

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.brandPrimary,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ProfileHeaderCard(
                  fullName: fullName,
                  email: email,
                  phone: phone,
                  profilePictureUrl: _profilePictureUrl,
                  patientNumber: _patientNumber,
                  onAvatarTap: _showImageSourceDialog,
                  showEditAvatarBadge: true,
                ),
                const SizedBox(height: 16),
                ProfileQuickStats(
                  age: age,
                  childrenCount: children.isNotEmpty
                      ? children.length
                      : (profile['children_count'] ?? 0),
                  pregnanciesCount: pregnancies.isNotEmpty
                      ? pregnancies.length
                      : (profile['pregnancies_count'] ?? 0),
                ),
                const SizedBox(height: 16),
                if (currentPregnancy != null) ...[
                  ProfileRiskCard(
                    profile: profile,
                    pregnancy: currentPregnancy,
                  ),
                  const SizedBox(height: 16),
                ],
                _buildMedicalInfoSection(profile),
                const SizedBox(height: 14),
                _buildAddressSection(profile),
                const SizedBox(height: 14),
                _buildMedicalConditionsSection(medicalConditions),
                const SizedBox(height: 14),
                _buildAllergiesSection(allergies),
                const SizedBox(height: 14),
                _buildEmergencyContactsSection(emergencyContacts),
                const SizedBox(height: 14),
                _buildChildrenSection(children),
                const SizedBox(height: 16),
                if (currentPregnancy != null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final pregnancyId =
                            currentPregnancy['pregnancy_id'] as int;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MotherVitalsPage(
                              motherId: widget.motherId,
                              pregnancyId: pregnancyId,
                              lastMenstrualPeriod:
                                  currentPregnancy['last_menstrual_period']
                                      ?.toString(),
                            ),
                          ),
                        ).then((_) => _refresh());
                      },
                      icon: const Icon(Icons.favorite),
                      label: Text(_t('My Vitals & Weight Gain',
                          'Aking Vitals & Timbang')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMedicalInfoSection(Map<String, dynamic> profile) {
    final double? heightCm = toDouble(profile['height']);
    final double? prePregWeight = toDouble(profile['pre_pregnancy_weight']);
    final double? currWeight = toDouble(profile['weight']);
    final double? bmi = computePregnancyBMI(
      prePregnancyWeight: prePregWeight,
      currentWeight: currWeight,
      heightCm: heightCm,
    );
    final String? bmiStatus = bmi != null ? getBMIStatus(bmi) : null;
    final Color bmiColor = bmiStatus != null
        ? getBMIStatusColor(bmiStatus)
        : AppColors.textSecondary;

    return ProfileCardSection(
      title: _t('Medical Information', 'Impormasyong Medikal'),
      icon: Icons.medical_information,
      children: [
        ProfileInfoRow(
          icon: Icons.cake_outlined,
          label: _t('Birthdate', 'Araw ng Kapanganakan'),
          value: formatProfileDate(profile['birthdate']),
        ),
        ProfileInfoRow(
          icon: Icons.straighten,
          label: _t('Height', 'Taas'),
          value: heightCm != null
              ? '${heightCm.toStringAsFixed(0)} cm'
              : _t('Not set', 'Hindi nakatakda'),
        ),
        ProfileInfoRow(
          icon: Icons.scale_outlined,
          label: _t('Weight', 'Timbang'),
          value: currWeight != null
              ? '${currWeight.toStringAsFixed(1)} kg'
              : _t('Not set', 'Hindi nakatakda'),
        ),
        ProfileInfoRow(
          icon: Icons.monitor_weight_outlined,
          label: _t('Pre-Pregnancy Weight', 'Timbang Bago Magbuntis'),
          value: prePregWeight != null
              ? '${prePregWeight.toStringAsFixed(1)} kg'
              : _t('Unknown', 'Hindi alam'),
        ),
        ProfileInfoRow(
          icon: Icons.speed_rounded,
          labelFlex: 4,
          valueFlex: 2,
          labelWidget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('BMI', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              if (bmiStatus != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: bmiColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(bmiStatus, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: bmiColor)),
                ),
              ],
            ],
          ),
          value: bmi != null ? bmi.toStringAsFixed(1) : _t('Not calculated', 'Hindi nakalkula'),
        ),
        ProfileInfoRow(
            icon: Icons.bloodtype_outlined,
            label: _t('Blood Type', 'Uri ng Dugo'),
            value: formatValue(profile['blood_type'])),
        ProfileInfoRow(
          icon: Icons.medical_services_outlined,
          label: _t('Obstetric Score', 'Iskor sa Panganganak'),
          value: 'G${profile['gravida'] ?? 0} P${profile['para'] ?? 0} A${profile['abortus'] ?? 0} L${profile['living_children'] ?? 0}',
        ),
      ],
    );
  }

  Widget _buildAddressSection(Map<String, dynamic> profile) {
    return ProfileCardSection(
      title: _t('Address', 'Tirahan'),
      icon: Icons.home_outlined,
      children: [
        ProfileInfoRow(icon: Icons.numbers_outlined, label: _t('House No.', 'Numero ng Bahay'), value: formatValue(profile['house_number'])),
        ProfileInfoRow(icon: Icons.add_road_outlined, label: _t('Street', 'Kalsada'), value: formatValue(profile['street'])),
        ProfileInfoRow(icon: Icons.location_city_outlined, label: _t('Barangay', 'Barangay'), value: formatValue(profile['barangay'])),
        ProfileInfoRow(icon: Icons.location_on_outlined, label: _t('City', 'Lungsod / Bayan'), value: formatValue(profile['city_municipality'])),
        ProfileInfoRow(icon: Icons.map_outlined, label: _t('Province', 'Lalawigan'), value: formatValue(profile['province'])),
      ],
    );
  }

  Widget _buildMedicalConditionsSection(List medicalConditions) {
    return ProfileCardSection(
      title: _t('Medical Conditions', 'Kondisyong Medikal'),
      icon: Icons.medical_services_outlined,
      children: [
        if (medicalConditions.isEmpty)
          _buildEmptyText(_t('No medical conditions recorded', 'Walang naitalang kondisyong medikal'))
        else
          ...medicalConditions.map((c) => _buildStatusListTile(
              c['condition_name'] ?? '-', '${c['status'] ?? 'active'} • ${formatProfileDate(c['diagnosis_date'])}', c['status'] == 'active')),
      ],
    );
  }

  Widget _buildAllergiesSection(List allergies) {
    return ProfileCardSection(
      title: _t('Allergies', 'Mga Allergy'),
      icon: Icons.warning_amber_outlined,
      children: [
        if (allergies.isEmpty)
          _buildEmptyText(_t('No allergies recorded', 'Walang naitalang allergy'))
        else
          ...allergies.map((a) => _buildStatusListTile(
              a['allergen'] ?? '-', '${a['status'] ?? 'active'} • ${formatProfileDate(a['diagnosis_date'])}', a['status'] == 'active')),
      ],
    );
  }

  Widget _buildEmergencyContactsSection(List emergencyContacts) {
    return ProfileCardSection(
      title: _t('Emergency Contacts', 'Mga Pang-emergency na Kontak'),
      icon: Icons.contacts_outlined,
      children: [
        if (emergencyContacts.isEmpty)
          _buildEmptyText(_t('No emergency contacts', 'Walang pang-emergency na kontak'))
        else
          ...emergencyContacts.map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.phone_outlined, size: 16, color: AppColors.brandPrimary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c['first_name'] ?? ''} ${c['last_name'] ?? ''}'.trim(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.inputText)),
                          Text('${c['phone_number'] ?? '-'} • ${c['relationship'] ?? '-'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildChildrenSection(List children) {
    return ProfileCardSection(
      title: _t('Children', 'Mga Anak'),
      icon: Icons.child_care_outlined,
      children: [
        if (children.isEmpty)
          _buildEmptyText(_t('No children registered', 'Walang naitalang anak'))
        else
          ...children.map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(radius: 14, backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.12), child: Text(c['first_name']?.toString().isNotEmpty == true ? c['first_name'][0].toUpperCase() : 'C', style: const TextStyle(color: AppColors.brandPrimary, fontSize: 12, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c['first_name'] ?? ''} ${c['last_name'] ?? ''}'.trim(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.inputText)),
                          Text('Born: ${formatProfileDate(c['birth_date'] ?? c['birthdate'])}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildEmptyText(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Center(child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))));

  Widget _buildStatusListTile(String title, String subtitle, bool isActive) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: isActive ? AppColors.warning : AppColors.success, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.inputText)), Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))])),
          ],
        ),
      );
}
