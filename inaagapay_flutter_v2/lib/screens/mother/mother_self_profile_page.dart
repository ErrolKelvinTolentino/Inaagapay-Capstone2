import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_colors.dart';
import '../../services/language_service.dart';
import '../../services/mother_profile_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/profile_widgets.dart';
import 'mother_vitals_page.dart';

import 'package:intl/intl.dart';
import '../../widgets/password_strength_indicator.dart';
import '../../widgets/password_constraints.dart';
import '../../models/password_strength.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/main_button.dart';

const List<String> _commonConditions = [
  'Anemia',
  'Diabetes',
  'Hypertension',
  'Asthma',
  'Thyroid Disorder',
  'Heart Disease',
  'Kidney Disease',
  'Epilepsy',
  'Hepatitis',
  'Other'
];

const List<String> _commonAllergens = [
  'Peanuts',
  'Penicillin',
  'Dust Mites',
  'Pollen',
  'Shellfish',
  'Pet Dander',
  'Fish',
  'Milk',
  'Eggs',
  'Soy',
  'Wheat',
  'Latex',
  'Insect Stings',
  'Mold',
  'Fragrances',
  'Nickel',
  'Other'
];

const List<String> _relationshipOptions = [
  'Spouse/Partner',
  'Parent',
  'Child',
  'Sibling',
  'Relative',
  'Friend',
  'Neighbor',
  'Coworker',
  'Other',
];

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

  /// Extracts the birth date from a child record.
  /// The Supabase join nests it inside `birth_details` which can be a Map or
  /// a single-element List depending on the relation type.
  String _childBirthDate(Map<String, dynamic> child) {
    final bd = child['birth_details'];
    if (bd is Map) return formatProfileDate(bd['birthdate']);
    if (bd is List && bd.isNotEmpty) {
      return formatProfileDate(bd[0]['birthdate']);
    }
    // Fallback to top-level keys if birth_details is absent
    return formatProfileDate(child['birthdate'] ?? child['birth_date']);
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
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _showChangePasswordSheet(
                    profile['account_id'] as int,
                  ),
                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                  label: Text(_t('Change Password', 'Palitan ang Password')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandPrimary,
                    side: const BorderSide(color: AppColors.brandPrimary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
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
      actionButton: IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.brandPrimary),
        onPressed: () => _showEditAddressModal(profile),
      ),
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
      actionButton: IconButton(
        icon: const Icon(Icons.edit_note_outlined, size: 20, color: AppColors.brandPrimary),
        onPressed: () => _showManageMedicalConditionsModal(medicalConditions),
      ),
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
      actionButton: IconButton(
        icon: const Icon(Icons.edit_note_outlined, size: 20, color: AppColors.brandPrimary),
        onPressed: () => _showManageAllergiesModal(allergies),
      ),
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
      actionButton: IconButton(
        icon: const Icon(Icons.edit_note_outlined, size: 20, color: AppColors.brandPrimary),
        onPressed: () => _showManageEmergencyContactsModal(emergencyContacts),
      ),
      children: [
        if (emergencyContacts.isEmpty)
          _buildEmptyText(_t('No emergency contacts', 'Walang pang-emergency na kontak'))
        else
          ...emergencyContacts.map((c) {
            final name = [c['first_name'], c['middle_name'], c['last_name'], c['extension_name']]
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .join(' ');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16, color: AppColors.brandPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isNotEmpty ? name : '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.inputText)),
                        Text('${c['phone_number'] ?? '-'} • ${c['affiliation'] ?? c['relationship'] ?? '-'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
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
                          Text('${_t('Born', 'Ipinanganak')}: ${_childBirthDate(c)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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

  void _showChangePasswordSheet(int accountId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChangePasswordSheet(
        accountId: accountId,
        onChanged: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t('Password changed successfully.', 'Matagumpay na napalitan ang password.')),
              backgroundColor: AppColors.success,
            ),
          );
        },
      ),
    );
  }

  void _showEditAddressModal(Map<String, dynamic> profile) {
    final houseNoCtrl = TextEditingController(text: profile['house_number']?.toString() ?? '');
    final streetCtrl = TextEditingController(text: profile['street']?.toString() ?? '');
    final barangayCtrl = TextEditingController(text: profile['barangay']?.toString() ?? '');
    final cityCtrl = TextEditingController(text: profile['city_municipality']?.toString() ?? '');
    final provinceCtrl = TextEditingController(text: profile['province']?.toString() ?? '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.borderPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.brandPrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.home_outlined, color: AppColors.brandPrimary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _t('Edit Address', 'I-edit ang Tirahan'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brandText,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    AppInputField(
                      controller: houseNoCtrl,
                      hintText: _t('House Number', 'Numero ng Bahay'),
                    ),
                    const SizedBox(height: 12),
                    AppInputField(
                      controller: streetCtrl,
                      hintText: _t('Street', 'Kalsada'),
                    ),
                    const SizedBox(height: 12),
                    AppInputField(
                      controller: barangayCtrl,
                      hintText: _t('Barangay', 'Barangay'),
                    ),
                    const SizedBox(height: 12),
                    AppInputField(
                      controller: cityCtrl,
                      hintText: _t('City/Municipality', 'Lungsod / Bayan'),
                    ),
                    const SizedBox(height: 12),
                    AppInputField(
                      controller: provinceCtrl,
                      hintText: _t('Province', 'Lalawigan'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: MainButton(
                            label: _t('Cancel', 'Kanselahin'),
                            isWhiteVariant: true,
                            onPressed: () => Navigator.pop(modalContext),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MainButton(
                            label: saving ? _t('Saving…', 'Nagse-save…') : _t('Save Changes', 'I-save ang Pagbabago'),
                            onPressed: saving
                                ? null
                                : () async {
                                    setModalState(() => saving = true);
                                    try {
                                      await SupabaseService.client.from('mothers').update({
                                        'house_number': houseNoCtrl.text.trim(),
                                        'street': streetCtrl.text.trim(),
                                        'barangay': barangayCtrl.text.trim(),
                                        'city_municipality': cityCtrl.text.trim(),
                                        'province': provinceCtrl.text.trim(),
                                      }).eq('mother_id', widget.motherId);
                                      if (!mounted) return;
                                      Navigator.pop(modalContext);
                                      _refresh();
                                    } catch (e) {
                                      setModalState(() => saving = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                                        );
                                      }
                                    }
                                  },
                          ),
                        ),
                      ],
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

  void _showManageMedicalConditionsModal(List medicalConditions) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.medical_services_outlined, color: AppColors.brandPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('Medical Conditions', 'Kondisyong Medikal'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandText,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(sheetCtx, {'action': 'add'}),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(_t('Add', 'Magdagdag')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (medicalConditions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      _t('No medical conditions recorded', 'Walang naitalang kondisyong medikal'),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: medicalConditions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final c = medicalConditions[index] as Map<String, dynamic>;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: c['status'] == 'active' ? AppColors.warning : AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c['condition_name'] ?? '-',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.inputText),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${c['status'] ?? 'active'} • ${formatProfileDate(c['diagnosis_date'])}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppColors.brandPrimary, size: 20),
                              onPressed: () => Navigator.pop(sheetCtx, {'action': 'edit', 'item': c}),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                              onPressed: () => Navigator.pop(sheetCtx, {'action': 'delete', 'item': c}),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || result == null) return;
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final action = result['action'];
    if (action == 'add') {
      _showMedicalConditionDialog(medicalConditions: medicalConditions);
    } else if (action == 'edit') {
      _showMedicalConditionDialog(prefill: result['item'], medicalConditions: medicalConditions);
    } else if (action == 'delete') {
      _removeMedicalCondition(result['item']);
    }
  }

  Future<void> _showMedicalConditionDialog({
    Map<String, dynamic>? prefill,
    required List medicalConditions,
  }) async {
    final nameCtrl = TextEditingController(text: prefill?['condition_name'] ?? '');
    DateTime? diagDate = prefill?['diagnosis_date'] != null
        ? DateTime.tryParse(prefill!['diagnosis_date'].toString())
        : null;
    String status = prefill?['status'] ?? 'active';
    final remarksCtrl = TextEditingController(text: prefill?['remarks'] ?? '');
    final diagDateCtrl = TextEditingController(
        text: diagDate != null ? DateFormat('MMMM d, yyyy').format(diagDate) : '');

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                final inputName = nameCtrl.text.trim();
                final alreadyAdded = medicalConditions
                    .where((c) =>
                        prefill == null ||
                        c['medical_condition_id'] != prefill['medical_condition_id'])
                    .map((c) => c['condition_name']?.toString().toLowerCase())
                    .toSet();

                final isDuplicate = alreadyAdded.contains(inputName.toLowerCase());
                final isFormValid = inputName.isNotEmpty && !isDuplicate;

                final displayedConditions = _commonConditions.where((cond) {
                  if (cond == 'Other') return true;
                  return !alreadyAdded.contains(cond.toLowerCase());
                }).toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.brandText),
                          onPressed: () {
                            FocusScope.of(dialogCtx).unfocus();
                            Navigator.of(dialogCtx, rootNavigator: true).pop(false);
                          },
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              prefill != null
                                  ? _t('Edit Medical Condition', 'I-edit ang Kondisyong Medikal')
                                  : _t('Medical Condition', 'Kondisyong Medikal'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.brandText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (displayedConditions.isNotEmpty) ...[
                              Text(
                                _t('Common Conditions', 'Karaniwang Kondisyon'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: displayedConditions.map((cond) {
                                  final isSelected = inputName.toLowerCase() == cond.toLowerCase();
                                  return ActionChip(
                                    label: Text(cond,
                                        style: TextStyle(
                                            color: isSelected ? Colors.white : AppColors.brandPrimary,
                                            fontSize: 12)),
                                    backgroundColor: isSelected ? AppColors.brandPrimary : Colors.white,
                                    side: const BorderSide(color: AppColors.brandPrimary),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    onPressed: () {
                                      setDialogState(() {
                                        if (cond == 'Other') {
                                          nameCtrl.clear();
                                        } else {
                                          nameCtrl.text = cond;
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                            ],
                            AppInputField(
                              controller: nameCtrl,
                              hintText: _t('Condition Name', 'Pangalan ng Kondisyon'),
                              isRequired: true,
                              leadingIcon: Icons.medical_services_outlined,
                              errorText: isDuplicate ? _t('Condition already added', 'Naidagdag na ang kondisyon') : null,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: diagDateCtrl,
                              hintText: _t('Diagnosis Date (Optional)', 'Petsa ng Diagnosis (Opsyonal)'),
                              readOnly: true,
                              leadingIcon: Icons.calendar_today_outlined,
                              onTap: () async {
                                final picked = await _showBrandedDatePicker(
                                  context: dialogCtx,
                                  initialDate: diagDate ?? DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    diagDate = picked;
                                    diagDateCtrl.text = DateFormat('MMMM d, yyyy').format(picked);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _t('Status', 'Katayuan'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setDialogState(() => status = 'active'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'active'
                                            ? AppColors.brandPrimary.withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: status == 'active'
                                              ? AppColors.brandPrimary
                                              : AppColors.borderPrimary,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _t('Active', 'Aktibo'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: status == 'active'
                                              ? AppColors.brandPrimary
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setDialogState(() => status = 'resolved'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'resolved'
                                            ? AppColors.brandPrimary.withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: status == 'resolved'
                                              ? AppColors.brandPrimary
                                              : AppColors.borderPrimary,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _t('Resolved', 'Nalutas'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: status == 'resolved'
                                              ? AppColors.brandPrimary
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: remarksCtrl,
                              hintText: _t('Remarks (Optional)', 'Mga Tala (Opsyonal)'),
                              leadingIcon: Icons.notes_outlined,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isFormValid ? () => Navigator.of(dialogCtx, rootNavigator: true).pop(true) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          elevation: 0,
                        ),
                        child: Text(
                          prefill != null ? _t('Save Changes', 'I-save ang Pagbabago') : _t('Add Condition', 'Magdagdag ng Kondisyon'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    final savedName = nameCtrl.text.trim();
    final savedRemarks = remarksCtrl.text.trim();
    nameCtrl.dispose();
    remarksCtrl.dispose();
    diagDateCtrl.dispose();

    if (result == true) {
      try {
        final Map<String, dynamic> data = {
          'condition_name': savedName,
          'status': status,
          'diagnosis_date': diagDate?.toIso8601String().split('T')[0],
          'remarks': savedRemarks.isEmpty ? null : savedRemarks,
        };

        if (prefill != null) {
          final condId = prefill['medical_condition_id'];
          await SupabaseService.client
              .from('medical_conditions')
              .update(data)
              .eq('medical_condition_id', condId);
        } else {
          data['mother_id'] = widget.motherId;
          await SupabaseService.client
              .from('medical_conditions')
              .insert(data);
        }
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _removeMedicalCondition(Map<String, dynamic> condition) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Remove Condition', 'Tanggalin ang Kondisyon')),
        content: Text(
          _t('Remove "${condition['condition_name']}"? This will mark it as resolved.',
             'Tanggalin ang "${condition['condition_name']}"? Mamamarkahan ito bilang nalutas na.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Cancel', 'Kanselahin')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: Text(_t('Remove', 'Tanggalin')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final conditionId = condition['medical_condition_id'];
        if (conditionId != null) {
          await SupabaseService.client
              .from('medical_conditions')
              .update({'status': 'resolved'})
              .eq('medical_condition_id', conditionId);
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _showManageAllergiesModal(List allergies) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warning_amber_outlined, color: AppColors.brandPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('Allergies', 'Mga Allergy'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandText,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(sheetCtx, {'action': 'add'}),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(_t('Add', 'Magdagdag')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (allergies.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      _t('No allergies recorded', 'Walang naitalang allergy'),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: allergies.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final a = allergies[index] as Map<String, dynamic>;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: a['status'] == 'active' ? AppColors.warning : AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a['allergen'] ?? '-',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.inputText),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${a['status'] ?? 'active'} • ${formatProfileDate(a['diagnosis_date'])}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppColors.brandPrimary, size: 20),
                              onPressed: () => Navigator.pop(sheetCtx, {'action': 'edit', 'item': a}),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                              onPressed: () => Navigator.pop(sheetCtx, {'action': 'delete', 'item': a}),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || result == null) return;
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final action = result['action'];
    if (action == 'add') {
      _showAllergyDialog(allergies: allergies);
    } else if (action == 'edit') {
      _showAllergyDialog(prefill: result['item'], allergies: allergies);
    } else if (action == 'delete') {
      _removeAllergy(result['item']);
    }
  }

  Future<void> _showAllergyDialog({
    Map<String, dynamic>? prefill,
    required List allergies,
  }) async {
    final allergenCtrl = TextEditingController(text: prefill?['allergen'] ?? '');
    DateTime? diagDate = prefill?['diagnosis_date'] != null
        ? DateTime.tryParse(prefill!['diagnosis_date'].toString())
        : null;
    String status = prefill?['status'] ?? 'active';
    final treatmentCtrl = TextEditingController(text: prefill?['treatment'] ?? '');
    final remarksCtrl = TextEditingController(text: prefill?['remarks'] ?? '');
    final diagDateCtrl = TextEditingController(
        text: diagDate != null ? DateFormat('MMMM d, yyyy').format(diagDate) : '');

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                final inputName = allergenCtrl.text.trim();
                final alreadyAdded = allergies
                    .where((a) =>
                        prefill == null ||
                        a['allergy_id'] != prefill['allergy_id'])
                    .map((a) => a['allergen']?.toString().toLowerCase())
                    .toSet();

                final isDuplicate = alreadyAdded.contains(inputName.toLowerCase());
                final isFormValid = inputName.isNotEmpty && !isDuplicate;

                final displayedAllergens = _commonAllergens.where((cond) {
                  if (cond == 'Other') return true;
                  return !alreadyAdded.contains(cond.toLowerCase());
                }).toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.brandText),
                          onPressed: () {
                            FocusScope.of(dialogCtx).unfocus();
                            Navigator.of(dialogCtx, rootNavigator: true).pop(false);
                          },
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              prefill != null
                                  ? _t('Edit Allergy', 'I-edit ang Allergy')
                                  : _t('Add Allergy', 'Magdagdag ng Allergy'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.brandText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (displayedAllergens.isNotEmpty) ...[
                              Text(
                                _t('Common Allergens', 'Karaniwang Allergy'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: displayedAllergens.map((cond) {
                                  final isSelected = inputName.toLowerCase() == cond.toLowerCase();
                                  return ActionChip(
                                    label: Text(cond,
                                        style: TextStyle(
                                            color: isSelected ? Colors.white : AppColors.brandPrimary,
                                            fontSize: 12)),
                                    backgroundColor: isSelected ? AppColors.brandPrimary : Colors.white,
                                    side: const BorderSide(color: AppColors.brandPrimary),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    onPressed: () {
                                      setDialogState(() {
                                        allergenCtrl.text = cond;
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                            ],
                            AppInputField(
                              controller: allergenCtrl,
                              hintText: _t('Allergen Name', 'Pangalan ng Allergen'),
                              isRequired: true,
                              leadingIcon: Icons.warning_amber_rounded,
                              errorText: isDuplicate ? _t('Allergen already added', 'Naidagdag na ang allergen') : null,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: diagDateCtrl,
                              hintText: _t('Diagnosis Date (Optional)', 'Petsa ng Diagnosis (Opsyonal)'),
                              readOnly: true,
                              leadingIcon: Icons.calendar_today_outlined,
                              onTap: () async {
                                final picked = await _showBrandedDatePicker(
                                  context: dialogCtx,
                                  initialDate: diagDate ?? DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    diagDate = picked;
                                    diagDateCtrl.text = DateFormat('MMMM d, yyyy').format(picked);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _t('Status', 'Katayuan'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setDialogState(() => status = 'active'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'active'
                                            ? AppColors.brandPrimary.withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: status == 'active'
                                              ? AppColors.brandPrimary
                                              : AppColors.borderPrimary,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _t('Active', 'Aktibo'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: status == 'active'
                                              ? AppColors.brandPrimary
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setDialogState(() => status = 'resolved'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'resolved'
                                            ? AppColors.brandPrimary.withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: status == 'resolved'
                                              ? AppColors.brandPrimary
                                              : AppColors.borderPrimary,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _t('Resolved', 'Nalutas'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: status == 'resolved'
                                              ? AppColors.brandPrimary
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: treatmentCtrl,
                              hintText: _t('Treatment (Optional)', 'Paggamot (Opsyonal)'),
                              leadingIcon: Icons.medical_services_outlined,
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: remarksCtrl,
                              hintText: _t('Remarks (Optional)', 'Mga Tala (Opsyonal)'),
                              leadingIcon: Icons.notes_outlined,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isFormValid ? () => Navigator.of(dialogCtx, rootNavigator: true).pop(true) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          elevation: 0,
                        ),
                        child: Text(
                          prefill != null ? _t('Save Changes', 'I-save ang Pagbabago') : _t('Add Allergy', 'Magdagdag ng Allergy'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    final savedAllergen = allergenCtrl.text.trim();
    final savedTreatment = treatmentCtrl.text.trim();
    final savedRemarks = remarksCtrl.text.trim();
    allergenCtrl.dispose();
    treatmentCtrl.dispose();
    remarksCtrl.dispose();
    diagDateCtrl.dispose();

    if (result == true) {
      try {
        final Map<String, dynamic> data = {
          'allergen': savedAllergen,
          'status': status,
          'diagnosis_date': diagDate?.toIso8601String().split('T')[0],
          'treatment': savedTreatment.isEmpty ? null : savedTreatment,
          'remarks': savedRemarks.isEmpty ? null : savedRemarks,
        };

        if (prefill != null) {
          final allergyId = prefill['allergy_id'];
          await SupabaseService.client
              .from('allergies')
              .update(data)
              .eq('allergy_id', allergyId);
        } else {
          data['mother_id'] = widget.motherId;
          await SupabaseService.client
              .from('allergies')
              .insert(data);
        }
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _removeAllergy(Map<String, dynamic> allergy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Remove Allergy', 'Tanggalin ang Allergy')),
        content: Text(
          _t('Remove "${allergy['allergen']}"? This will mark it as resolved.',
             'Tanggalin ang "${allergy['allergen']}"? Mamamarkahan ito bilang nalutas na.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Cancel', 'Kanselahin')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: Text(_t('Remove', 'Tanggalin')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final allergyId = allergy['allergy_id'];
        if (allergyId != null) {
          await SupabaseService.client
              .from('allergies')
              .update({'status': 'resolved'})
              .eq('allergy_id', allergyId);
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _showManageEmergencyContactsModal(List emergencyContacts) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.contacts_outlined, color: AppColors.brandPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('Emergency Contacts', 'Mga Pang-emergency na Kontak'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandText,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(sheetCtx, {'action': 'add'}),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(_t('Add', 'Magdagdag')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (emergencyContacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      _t('No emergency contacts', 'Walang pang-emergency na kontak'),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: emergencyContacts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final c = emergencyContacts[index] as Map<String, dynamic>;
                      final name = [c['first_name'], c['middle_name'], c['last_name'], c['extension_name']]
                          .whereType<String>()
                          .where((s) => s.trim().isNotEmpty)
                          .join(' ');
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.brandPrimary.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.phone_outlined, size: 18, color: AppColors.brandPrimary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.isNotEmpty ? name : '-',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.inputText),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${c['phone_number'] ?? '-'} • ${c['affiliation'] ?? c['relationship'] ?? '-'}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppColors.brandPrimary, size: 20),
                              onPressed: () => Navigator.pop(sheetCtx, {'action': 'edit', 'item': c}),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                              onPressed: () => Navigator.pop(sheetCtx, {'action': 'delete', 'item': c}),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || result == null) return;
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final action = result['action'];
    if (action == 'add') {
      _showEmergencyContactDialog();
    } else if (action == 'edit') {
      _showEmergencyContactDialog(prefill: result['item']);
    } else if (action == 'delete') {
      _removeEmergencyContact(result['item']);
    }
  }

  Future<void> _showEmergencyContactDialog({Map<String, dynamic>? prefill}) async {
    final relationshipOptionsNoOther = [
      'Spouse/Partner',
      'Parent',
      'Child',
      'Sibling',
      'Relative',
      'Friend',
      'Neighbor',
      'Coworker'
    ];
    final isCustomRel = prefill != null &&
        !relationshipOptionsNoOther.contains(prefill['affiliation']);

    final firstNameCtrl = TextEditingController(text: prefill?['first_name'] ?? '');
    final lastNameCtrl = TextEditingController(text: prefill?['last_name'] ?? '');
    final phoneCtrl = TextEditingController(text: prefill?['phone_number'] ?? '');
    final relationshipCtrl = TextEditingController(
        text: isCustomRel
            ? 'Other'
            : (prefill != null ? (prefill['affiliation']?.toString() ?? '') : ''));
    final customRelationshipCtrl = TextEditingController(
        text: isCustomRel ? (prefill['affiliation']?.toString() ?? '') : '');

    bool showRelationshipDropdown = false;
    String? phoneError;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                void validatePhone(String val) {
                  final normalized = val.trim().replaceAll(RegExp(r'[^0-9+]'), '');
                  final isValid = RegExp(r'^(\+?63|0)9\d{9}$').hasMatch(normalized);
                  setDialogState(() {
                    phoneError = val.isEmpty
                        ? null
                        : (isValid ? null : _t('Enter a valid PH mobile number', 'Maglagay ng wastong numero sa PH'));
                  });
                }

                final isPhoneValid = phoneCtrl.text.trim().isNotEmpty && phoneError == null;
                final isRelationshipValid = relationshipCtrl.text.trim().isNotEmpty &&
                    (relationshipCtrl.text.trim() != 'Other' ||
                        customRelationshipCtrl.text.trim().isNotEmpty);
                final isFormValid = firstNameCtrl.text.trim().isNotEmpty &&
                    lastNameCtrl.text.trim().isNotEmpty &&
                    isPhoneValid &&
                    isRelationshipValid;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.brandText),
                          onPressed: () {
                            FocusScope.of(dialogCtx).unfocus();
                            Navigator.of(dialogCtx, rootNavigator: true).pop(false);
                          },
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              prefill != null
                                  ? _t('Edit Emergency Contact', 'I-edit ang Kontak')
                                  : _t('Add Emergency Contact', 'Magdagdag ng Kontak'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.brandText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppInputField(
                              controller: firstNameCtrl,
                              hintText: _t('First Name', 'Pangalan'),
                              isRequired: true,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: lastNameCtrl,
                              hintText: _t('Last Name', 'Apelyido'),
                              isRequired: true,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: phoneCtrl,
                              hintText: _t('Contact Number', 'Numero ng Telepono'),
                              isRequired: true,
                              keyboardType: TextInputType.phone,
                              errorText: phoneError,
                              onChanged: (val) {
                                validatePhone(val);
                                setDialogState(() {});
                              },
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: relationshipCtrl,
                              hintText: _t('Relationship', 'Relasyon'),
                              isRequired: true,
                              readOnly: true,
                              trailingIcon: Icons.keyboard_arrow_down_rounded,
                              onTrailingTap: () {
                                setDialogState(() {
                                  showRelationshipDropdown = !showRelationshipDropdown;
                                });
                              },
                              onTap: () {
                                setDialogState(() {
                                  showRelationshipDropdown = !showRelationshipDropdown;
                                });
                              },
                            ),
                            if (showRelationshipDropdown) ...[
                              const SizedBox(height: 4),
                              Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                color: Colors.white,
                                child: Container(
                                  constraints: const BoxConstraints(maxHeight: 200),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: _relationshipOptions.length,
                                    itemBuilder: (context, idx) {
                                      final rel = _relationshipOptions[idx];
                                      return ListTile(
                                        title: Text(rel, style: const TextStyle(fontSize: 14)),
                                        dense: true,
                                        onTap: () {
                                          setDialogState(() {
                                            relationshipCtrl.text = rel;
                                            showRelationshipDropdown = false;
                                            if (rel != 'Other') {
                                              customRelationshipCtrl.clear();
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                            if (relationshipCtrl.text == 'Other') ...[
                              const SizedBox(height: 16),
                              AppInputField(
                                controller: customRelationshipCtrl,
                                hintText: _t('Specify Relationship', 'Tukuyin ang Relasyon'),
                                isRequired: true,
                                onChanged: (val) => setDialogState(() {}),
                              ),
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isFormValid ? () => Navigator.of(dialogCtx, rootNavigator: true).pop(true) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          elevation: 0,
                        ),
                        child: Text(
                          prefill != null ? _t('Save Changes', 'I-save ang Pagbabago') : _t('Add Contact', 'Magdagdag ng Kontak'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    final savedFirstName = firstNameCtrl.text.trim();
    final savedLastName = lastNameCtrl.text.trim();
    final savedPhone = phoneCtrl.text.trim();
    final savedRel = relationshipCtrl.text == 'Other'
        ? customRelationshipCtrl.text.trim()
        : relationshipCtrl.text.trim();

    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    phoneCtrl.dispose();
    relationshipCtrl.dispose();
    customRelationshipCtrl.dispose();

    if (result == true) {
      try {
        final Map<String, dynamic> data = {
          'first_name': savedFirstName,
          'last_name': savedLastName,
          'phone_number': savedPhone,
          'affiliation': savedRel,
        };

        if (prefill != null) {
          final contactId = prefill['emergency_contact_id'];
          await SupabaseService.client
              .from('emergency_contacts')
              .update(data)
              .eq('emergency_contact_id', contactId);
        } else {
          data['mother_id'] = widget.motherId;
          data['status'] = 'active';
          await SupabaseService.client
              .from('emergency_contacts')
              .insert(data);
        }
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _removeEmergencyContact(Map<String, dynamic> contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Remove Emergency Contact', 'Tanggalin ang Kontak')),
        content: Text(
          _t('Remove "${contact['first_name']} ${contact['last_name']}"?',
             'Tanggalin si "${contact['first_name']} ${contact['last_name']}"?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Cancel', 'Kanselahin')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: Text(_t('Remove', 'Tanggalin')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final contactId = contact['emergency_contact_id'];
        if (contactId != null) {
          await SupabaseService.client
              .from('emergency_contacts')
              .delete()
              .eq('emergency_contact_id', contactId);
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<DateTime?> _showBrandedDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    DateTime clampedInitial = initialDate;
    if (clampedInitial.isBefore(firstDate)) {
      clampedInitial = firstDate;
    } else if (clampedInitial.isAfter(lastDate)) {
      clampedInitial = lastDate;
    }

    return showDatePicker(
      context: context,
      initialDate: clampedInitial,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.brandPrimary,
              onPrimary: Colors.white,
              onSurface: AppColors.brandText,
              secondary: AppColors.brandPrimary,
              surface: Colors.white,
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              backgroundColor: Colors.white,
              elevation: 4,
              surfaceTintColor: Colors.transparent,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandPrimary,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  final int accountId;
  final VoidCallback onChanged;

  const _ChangePasswordSheet({
    required this.accountId,
    required this.onChanged,
  });

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _showCurrent = false;
  bool _showNext = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  PasswordStrength _calculateStrength(String password) {
    int met = 0;
    if (password.length >= 8) met++;
    if (RegExp(r'\d').hasMatch(password)) met++;
    if (RegExp(r'[A-Z]').hasMatch(password)) met++;
    if (RegExp(r'[a-z]').hasMatch(password)) met++;
    if (RegExp(r'[!@#\$%^&*]').hasMatch(password)) met++;

    if (met <= 2) return PasswordStrength.weak;
    if (met <= 4) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  String? _localProblem() {
    if (_current.text.isEmpty) return 'Enter your current password.';
    if (_next.text.length < 8) return 'The new password must be at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(_next.text) || !RegExp(r'\d').hasMatch(_next.text)) {
      return 'The new password must contain both letters and numbers.';
    }
    if (_next.text != _confirm.text) return 'The two new passwords do not match.';
    if (_next.text == _current.text) return 'The new password is the same as the current one.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _localProblem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await SupabaseService.changePassword(
      accountId: widget.accountId,
      currentPassword: _current.text,
      newPassword: _next.text,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      Navigator.pop(context);
      widget.onChanged();
    } else {
      setState(() {
        _saving = false;
        _error = result['message']?.toString() ?? 'Could not change password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.borderPrimary, borderRadius: BorderRadius.circular(999)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      LanguageService.translate('Change password', 'Palitan ang password'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                LanguageService.translate('At least 8 characters, with letters and numbers.', 'Kahit 8 na karakter, may letra at numero.'),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              AppInputField(
                hintText: LanguageService.translate('Current password', 'Kasalukuyang password'),
                controller: _current,
                obscureText: !_showCurrent,
                leadingIcon: Icons.lock_outline_rounded,
                trailingIcon: _showCurrent ? Icons.visibility_off : Icons.visibility,
                onTrailingTap: () => setState(() => _showCurrent = !_showCurrent),
              ),
              const SizedBox(height: 12),
              AppInputField(
                hintText: LanguageService.translate('New password', 'Bagong password'),
                controller: _next,
                obscureText: !_showNext,
                leadingIcon: Icons.lock_reset_rounded,
                trailingIcon: _showNext ? Icons.visibility_off : Icons.visibility,
                onTrailingTap: () => setState(() => _showNext = !_showNext),
                onChanged: (_) => setState(() {}),
              ),
              if (_next.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PasswordStrengthIndicator(strength: _calculateStrength(_next.text)),
                  ],
                ),
                const SizedBox(height: 8),
                PasswordConstraints(password: _next.text),
              ],
              const SizedBox(height: 12),
              AppInputField(
                hintText: LanguageService.translate('Confirm new password', 'Kumpirmahin ang bagong password'),
                controller: _confirm,
                obscureText: !_showNext,
                leadingIcon: Icons.check_circle_outline_rounded,
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFECACA))),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF991B1B)))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              MainButton(
                label: _saving ? LanguageService.translate('Saving…', 'Nagse-save…') : LanguageService.translate('Save new password', 'I-save ang bagong password'),
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
