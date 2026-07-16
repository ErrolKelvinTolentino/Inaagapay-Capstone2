import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../services/language_service.dart';
import '../../services/mother_profile_service.dart';
import '../../services/supabase_service.dart';
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
  bool _isUploadingPhoto = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfile();
    _loadProfilePicture();
  }

  Future<Map<String, dynamic>> _fetchProfile() async {
    return await MotherProfileService.fetchMotherProfile(widget.motherId);
  }

  Future<void> _loadProfilePicture() async {
    final url = await SupabaseService.getProfilePictureUrl(widget.motherId);
    if (!mounted) return;
    setState(() => _profilePictureUrl = url);
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(LanguageService.translate(
            'Choose Source', 'Piliin ang Pinagmulan')),
        content: Text(LanguageService.translate(
            'Select where to get your photo from:',
            'Piliin kung saan kukuha ng larawan:')),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
            icon: const Icon(Icons.photo_library, size: 18),
            label: Text(LanguageService.translate('Gallery', 'Gallery')),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandPrimary,
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.camera);
            },
            icon: const Icon(Icons.camera_alt, size: 18),
            label: Text(LanguageService.translate('Camera', 'Camera')),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandPrimary,
            ),
          ),
        ],
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
      setState(() => _isUploadingPhoto = true);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final bytes = await image.readAsBytes();
      final url =
          await SupabaseService.uploadProfilePicture(widget.motherId, bytes);

      if (!mounted) return;
      Navigator.pop(context);
      setState(() => _isUploadingPhoto = false);

      if (url != null) {
        setState(() {
          _profilePictureUrl = url;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LanguageService.translate(
              'Profile picture updated!',
              'Na-update ang larawan ng profile!',
            )),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  String _formatDate(dynamic value) {
    if (value == null) return _t('Not set', 'Hindi nakatakda');
    try {
      final parsed = DateTime.tryParse(value.toString());
      if (parsed == null) return value.toString();
      return DateFormat('MMM d, yyyy').format(parsed);
    } catch (_) {
      return value.toString();
    }
  }

  String _formatValue(dynamic value) {
    if (value == null) return _t('Not set', 'Hindi nakatakda');
    final text = value.toString().trim();
    return text.isEmpty ? _t('Not set', 'Hindi nakatakda') : text;
  }

  String _buildFullName(Map<String, dynamic> account) {
    final firstName = account['first_name']?.toString().trim() ?? '';
    final middleName = account['middle_name']?.toString().trim() ?? '';
    final lastName = account['last_name']?.toString().trim() ?? '';
    final ext = account['extension_name']?.toString().trim() ?? '';

    final nameParts = <String>[];
    if (firstName.isNotEmpty) nameParts.add(firstName);
    if (middleName.isNotEmpty) nameParts.add(middleName);
    if (lastName.isNotEmpty) nameParts.add(lastName);
    if (ext.isNotEmpty) nameParts.add(ext);

    return nameParts.isEmpty
        ? _t('Unknown', 'Hindi alam')
        : nameParts.join(' ');
  }

  Widget _buildSection(String title, List<MapEntry<String, String>> rows) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.brandText,
            ),
          ),
          const SizedBox(height: 14),
          ...rows.map((row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        row.key,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.value,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.cardColorOf(context),
        elevation: 0,
        title: Text(_t('My Profile', 'Aking Profile')),
      ),
      backgroundColor: AppColors.bgPrimaryOf(context),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _t('Unable to load profile. Please try again.',
                      'Hindi ma-load ang profile. Subukan muli.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }

          final profile = snapshot.data ?? {};
          final fullName = _formatValue(profile['full_name']);
          final email = _formatValue(profile['email_address']);
          final phone = _formatValue(profile['phone_number']);
          final status = _formatValue(profile['account_status']);
          final memberSince = _formatDate(profile['created_at']);

          final birthdate = _formatDate(profile['birthdate']);
          final address = [
            profile['barangay']?.toString().trim(),
            profile['city_municipality']?.toString().trim(),
            profile['province']?.toString().trim(),
          ].where((part) => part != null && part.isNotEmpty).join(', ');
          final height = _formatValue(profile['height']);
          final weight = _formatValue(profile['weight']);
          final bloodType = _formatValue(profile['blood_type']);
          final lmp = _formatDate(profile['last_menstrual_period']);
          final edd = _formatDate(profile['expected_date_of_delivery']);
          final prePregnancy = _formatValue(profile['pre_pregnancy_weight']);

          final pregnancy =
              profile['current_pregnancy'] as Map<String, dynamic>?;
          final pregnancyStatus = pregnancy != null
              ? _t('Ongoing Pregnancy', 'Nagpapatuloy na Pagbubuntis')
              : _t('No active pregnancy', 'Walang aktibong pagbubuntis');

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _showImageSourceDialog,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: AppColors.brandPrimary
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                    image: _profilePictureUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(
                                                _profilePictureUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: _profilePictureUrl == null
                                      ? Center(
                                          child: Text(
                                            fullName.isNotEmpty
                                                ? fullName[0].toUpperCase()
                                                : 'M',
                                            style: const TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.brandPrimary,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  bottom: -2,
                                  right: -2,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppColors.borderPrimary,
                                        width: 1,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      size: 16,
                                      color: AppColors.brandPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_t('Member since', 'Kasapi mula')} $memberSince',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _buildStatusChip(status),
                          const SizedBox(width: 10),
                          _buildStatusChip(pregnancyStatus,
                              active: pregnancy != null),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildSection(
                  _t('Account Details', 'Detalye ng Account'),
                  [
                    MapEntry(_t('Email', 'Email'), email),
                    MapEntry(_t('Mobile Number', 'Numero ng Cellphone'), phone),
                    MapEntry(
                        _t('Account Status', 'Katayuan ng Account'), status),
                  ],
                ),
                _buildSection(
                  _t('Personal Details', 'Personal na Detalye'),
                  [
                    MapEntry(
                        _t('Birthdate', 'Araw ng Kapanganakan'), birthdate),
                    MapEntry(_t('Blood Type', 'Uri ng Dugo'), bloodType),
                    MapEntry(_t('Height', 'Taas'), height),
                    MapEntry(_t('Weight', 'Timbang'), weight),
                  ],
                ),
                _buildSection(
                  _t('Location', 'Lokasyon'),
                  [
                    MapEntry(
                        _t('Address', 'Tirahan'),
                        address.isNotEmpty
                            ? address
                            : _t('Not set', 'Hindi nakatakda')),
                  ],
                ),
                _buildSection(
                  _t('Pregnancy Info', 'Impormasyon sa Pagbubuntis'),
                  [
                    MapEntry(
                        _t('Last Menstrual Period', 'Huling Panregla'), lmp),
                    MapEntry(
                        _t('Expected Delivery Date',
                            'Inaasahang Petsa ng Panganganak'),
                        edd),
                    MapEntry(
                        _t('Pre-pregnancy Weight', 'Timbang Bago Magbuntis'),
                        prePregnancy),
                  ],
                ),
                if (pregnancy != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final pregnancyId = pregnancy['pregnancy_id'] as int;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MotherVitalsPage(
                              motherId: widget.motherId,
                              pregnancyId: pregnancyId,
                              lastMenstrualPeriod: pregnancy['last_menstrual_period']?.toString(),
                            ),
                          ),
                        ).then((_) {
                          setState(() {
                            _profileFuture = _fetchProfile();
                          });
                        });
                      },
                      icon: const Icon(Icons.favorite),
                      label: Text(_t('My Vitals & Weight Gain', 'Aking Vitals & Timbang')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
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

  Widget _buildStatusChip(String label, {bool active = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? AppColors.success.withValues(alpha: 0.12)
            : AppColors.textSecondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? AppColors.success : AppColors.textSecondary,
        ),
      ),
    );
  }
}
