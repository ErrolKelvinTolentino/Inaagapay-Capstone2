import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/page_title.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/branded_date_picker.dart';
import '../../widgets/main_button.dart';
import '../../widgets/dialog_box.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/validation_message.dart';
import '../../services/groq_service.dart';
import '../../services/sms_service.dart';
import '../../services/notification_service.dart';
import 'immunization_ocr_review_page.dart';
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';

class AddImmunizationPage extends StatefulWidget {
  final int childId;

  const AddImmunizationPage({
    super.key,
    required this.childId,
  });

  @override
  State<AddImmunizationPage> createState() => _AddImmunizationPageState();
}

class _AddImmunizationPageState extends State<AddImmunizationPage> {
  final TextEditingController _vaccineController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  int? _selectedVaccineId;
  DateTime? _selectedDate;
  bool _isLoading = false;
  List<Map<String, dynamic>> _vaccines = [];
  bool _vaccinesLoading = true;
  Set<int> _takenVaccineIds = {};
  String? _errorMessage;
  DateTime? _childBirthdate;
  final GroqService _groqService = GroqService();
  bool _anyRecordAdded = false;

  Future<ImageSource?> _showOcrSourcePicker() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Scan Card',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Choose an image source to extract immunization records',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Color(0x1AFF68A5),
                  child: Icon(Icons.camera_alt_outlined,
                      color: AppColors.brandPrimary)),
              title: const Text('Camera'),
              subtitle: const Text('Take a photo of the card'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Color(0x1AFF68A5),
                  child: Icon(Icons.photo_library_outlined,
                      color: AppColors.brandPrimary)),
              title: const Text('Gallery'),
              subtitle: const Text('Choose an existing photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _startOcrFlow() async {
    final source = await _showOcrSourcePicker();
    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        imageQuality: 88,
      );

      if (image != null) {
        _showScanProcessDialog(image);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _showScanProcessDialog(XFile imageFile) async {
    String dialogState = 'loading';
    String? scanError;
    StateSetter? setS;

    void startScan() {
      _groqService.extractImmunizationCardData(imageFile).then((extractionResult) {
        final relevanceCheck = extractionResult['relevance_check']?.toString().toUpperCase() ?? 'RELATED';
        if (relevanceCheck == 'UNRELATED') {
          final reason = extractionResult['relevance_reason']?.toString() ?? 'The uploaded image does not appear to be an immunization record.';
          setS?.call(() {
            scanError = reason;
            dialogState = 'error';
          });
          return;
        }

        final administeredList = extractionResult['administered_vaccines'] as List<dynamic>? ?? [];
        if (administeredList.isEmpty) {
          setS?.call(() {
            scanError = 'We could not detect any administered vaccine records with valid dates in the uploaded photo. Please verify the photo is clear and contains handwritten dates.';
            dialogState = 'error';
          });
          return;
        }

        final extractedData = List<Map<String, dynamic>>.from(
          administeredList.map((item) => Map<String, dynamic>.from(item)),
        );

        if (mounted) {
          // Success! Pop the dialog and return the extracted data
          Navigator.pop(context, extractedData);
        }
      }).catchError((dynamic e) {
        setS?.call(() {
          scanError = e.toString().replaceFirst('Exception: ', '');
          dialogState = 'error';
        });
      });
    }

    startScan();

    final extractedData = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateCallback) {
          setS = setStateCallback;
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dialog Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.brandPrimary, Color(0xFFE91E8C)],
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        dialogState == 'loading'
                            ? Icons.cloud_upload_outlined
                            : Icons.error_outline_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dialogState == 'loading' ? 'Scanning Document...' : 'Scan Failed',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              dialogState == 'loading'
                                  ? 'Uploading and analysing with Groq...'
                                  : 'An error occurred during scanning',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (dialogState != 'loading')
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, null),
                          icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: dialogState == 'loading'
                        ? _scanLoadingBody(imageFile)
                        : _scanErrorBody(scanError ?? 'Unknown error'),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.borderPrimary),
                    ),
                  ),
                  child: dialogState == 'loading'
                      ? const SizedBox.shrink()
                      : Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx, null),
                                child: const Text('Dismiss'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setStateCallback(() {
                                    dialogState = 'loading';
                                    scanError = null;
                                  });
                                  startScan();
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Retry'),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (extractedData != null && mounted) {
      // Navigate to the review page
      final bool? recorded = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ImmunizationOcrReviewPage(
            childId: widget.childId,
            extractedVaccines: extractedData,
            allVaccines: _vaccines,
            takenVaccineIds: _takenVaccineIds,
            childBirthdate: _childBirthdate,
          ),
        ),
      );

      if (recorded == true) {
        setState(() {
          _anyRecordAdded = true;
        });
        _loadData();
      }
    }
  }

  Widget _scanLoadingBody(XFile imageFile) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FutureBuilder<Uint8List>(
              future: imageFile.readAsBytes(),
              builder: (ctx, snap) {
                if (snap.hasData) {
                  return Image.memory(
                    snap.data!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  );
                }
                return Container(
                  height: 180,
                  color: AppColors.bgSecondary,
                  child: const Center(
                    child: CircularProgressIndicator(color: AppColors.brandPrimary),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: AppColors.brandPrimary, strokeWidth: 3),
          const SizedBox(height: 16),
          const Text(
            'Analysing with Groq AI...',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Extracting immunization records from the card image',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          _scanStep(number: 1, label: 'Image uploaded', done: true),
          _scanStep(number: 2, label: 'Groq reading document...', loading: true),
          _scanStep(number: 3, label: 'Mapping vaccine matches'),
        ],
      );

  Widget _scanStep({
    required int number,
    required String label,
    bool done = false,
    bool loading = false,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: done
                  ? const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 20)
                  : loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.brandPrimary,
                          ),
                        )
                      : CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.borderPrimary,
                          child: Text(
                            '$number',
                            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                          ),
                        ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: (done || loading) ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: loading ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      );

  Widget _scanErrorBody(String message) => Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Scan Failed',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tips for a better scan:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _scanTip('Ensure the immunization card is well lit'),
                _scanTip('Keep the camera steady and in focus'),
                _scanTip('Ensure the handwritten dates are clearly readable'),
              ],
            ),
          ),
        ],
      );

  Widget _scanTip(String tip) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Text(
                tip,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _vaccinesLoading = true;
      _errorMessage = null;
    });

    await Future.wait([
      _loadVaccines(),
      _loadTakenVaccines(),
      _loadChildBirthdate(),
    ]);

    setState(() => _vaccinesLoading = false);

    debugPrint('Vaccines loaded: ${_vaccines.length}');
    debugPrint('Taken vaccines: ${_takenVaccineIds.length}');
    debugPrint('Available vaccines: ${_getAvailableVaccines().length}');
    debugPrint('Child birthdate: $_childBirthdate');
  }

  Future<void> _loadChildBirthdate() async {
    try {
      final response = await Supabase.instance.client
          .from('birth_details')
          .select('birthdate')
          .eq('child_id', widget.childId)
          .maybeSingle();

      if (response != null && response['birthdate'] != null) {
        _childBirthdate = DateTime.parse(response['birthdate']);
      }
    } catch (e) {
      debugPrint('Error loading child birthdate: $e');
    }
  }

  /// Returns the child's age in months (fractional).
  double _getChildAgeMonths() {
    if (_childBirthdate == null) return 0;
    final now = DateTime.now();
    final diff = now.difference(_childBirthdate!);
    return diff.inDays / 30.44; // average days per month
  }

  Future<void> _loadVaccines() async {
    try {
      final response = await Supabase.instance.client
          .from('vaccines')
          .select('*')
          .eq('target_recipients', 'child')
          .order('recommended_age_months')
          .order('vaccine_name');

      _vaccines = List<Map<String, dynamic>>.from(response);

      if (_vaccines.isEmpty) {
        setState(() {
          _errorMessage = 'No vaccines found in the database. Please add vaccines first.';
        });
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading vaccines: $e');
      setState(() {
        _errorMessage = 'Failed to load vaccines: $e';
      });
    }
  }

  Future<void> _loadTakenVaccines() async {
    try {
      final response = await Supabase.instance.client
          .from('immunization_records')
          .select('vaccine_id')
          .eq('child_id', widget.childId);

      final taken = List<Map<String, dynamic>>.from(response);
      setState(() {
        _takenVaccineIds = taken.map((t) => t['vaccine_id'] as int).toSet();
      });
    } catch (e) {
      debugPrint('Error loading taken vaccines: $e');
    }
  }

  /// Checks whether the prerequisite dose for a given vaccine has been taken.
  /// For multi-dose vaccines (e.g. Pentavalent 1->2->3), dose N requires dose N-1.
  bool _isPrerequisiteMet(Map<String, dynamic> vaccine) {
    final doseNumber = (vaccine['dose_number'] as num?)?.toInt() ?? 1;
    if (doseNumber <= 1) return true; // first dose has no prerequisite

    final vaccineName = vaccine['vaccine_name']?.toString() ?? '';

    // Find the previous dose for the same vaccine_name
    final previousDose = _vaccines.where((v) {
      final vName = v['vaccine_name']?.toString() ?? '';
      final vDose = (v['dose_number'] as num?)?.toInt() ?? 1;
      return vName == vaccineName && vDose == doseNumber - 1;
    }).toList();

    if (previousDose.isEmpty) return true; // no previous dose found in DB, allow

    // Check if the previous dose vaccine_id is in takenVaccineIds
    final prevId = previousDose.first['vaccine_id'] as int;
    return _takenVaccineIds.contains(prevId);
  }

  /// Returns vaccines available for selection:
  /// - Not already taken
  /// - Age-appropriate (child age >= recommended_age_months)
  /// - Prerequisite doses met
  List<Map<String, dynamic>> _getAvailableVaccines() {
    return _vaccines;
  }

  /// Determines the status of a vaccine for the roadmap display.
  /// Returns 'given', 'recommended', or 'not_due'.
  String _getVaccineStatus(Map<String, dynamic> vaccine) {
    final vaccineId = vaccine['vaccine_id'] as int;
    if (_takenVaccineIds.contains(vaccineId)) return 'given';

    final recommendedAge = (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0;
    final childAgeMonths = _getChildAgeMonths();
    if (childAgeMonths >= recommendedAge) return 'recommended';

    return 'not_due';
  }

  bool get _isFormValid =>
      _selectedVaccineId != null && _selectedDate != null;

  Future<void> _selectDate() async {
    final picked = await showBrandedDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'SELECT VACCINATION DATE',
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        // Display only — the row written to the database is built from
        // _selectedDate, so the readable format here is safe.
        _dateController.text = DateFormat('MMMM d, yyyy').format(picked);
      });
    }
  }

  String _formatRecommendedAge(double? months) {
    if (months == null) return '';
    if (months == 0) return 'At birth';
    if (months < 1) {
      final weeks = (months * 4).round();
      return '$weeks weeks';
    }
    return '${months.toStringAsFixed(0)} months';
  }

  /// Returns a milestone label for grouping vaccines by recommended age.
  String _getMilestoneLabel(double months) {
    if (months == 0) return 'At Birth';
    if (months < 1) {
      final weeks = (months * 4).round();
      return '$weeks Weeks';
    }
    if (months < 12) {
      return '${months.toStringAsFixed(0)} Months';
    }
    final years = months / 12;
    if (years == years.roundToDouble()) {
      return '${years.toStringAsFixed(0)} Year${years > 1 ? 's' : ''}';
    }
    return '${months.toStringAsFixed(0)} Months';
  }

  void _openVaccineDropdown() {
    if (_vaccinesLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading vaccines, please wait...')),
      );
      return;
    }

    if (_vaccines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No vaccines available in the system.')),
      );
      return;
    }

    final availableVaccines = _getAvailableVaccines();

    final childAgeMonths = _getChildAgeMonths();

    // 1. Already Taken
    final alreadyTakenVaccines = availableVaccines.where((v) {
      final vaccineId = v['vaccine_id'] as int;
      return _takenVaccineIds.contains(vaccineId);
    }).toList();

    // 2. Recommended (Not taken, age-appropriate, prerequisite met)
    final recommendedVaccines = availableVaccines.where((v) {
      final vaccineId = v['vaccine_id'] as int;
      if (_takenVaccineIds.contains(vaccineId)) return false;

      final recommendedAge = (v['recommended_age_months'] as num?)?.toDouble() ?? 0;
      return childAgeMonths >= recommendedAge && _isPrerequisiteMet(v);
    }).toList();

    // 3. Outside Recommended Range (Not taken, but too early or prerequisite pending)
    final outsideRangeVaccines = availableVaccines.where((v) {
      final vaccineId = v['vaccine_id'] as int;
      if (_takenVaccineIds.contains(vaccineId)) return false;
      return !recommendedVaccines.contains(v);
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select Vaccine',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Showing all ${availableVaccines.length} vaccines',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    if (recommendedVaccines.isNotEmpty) ...[
                      _buildDropdownSectionHeader(
                        'Recommended (Age-Appropriate & Ready)',
                        AppColors.success,
                      ),
                      ...recommendedVaccines.map((v) => _buildVaccineTile(v)),
                    ],
                    if (outsideRangeVaccines.isNotEmpty) ...[
                      _buildDropdownSectionHeader(
                        'Outside Recommended Range (Too Early / Pending)',
                        const Color(0xFFB78103),
                      ),
                      ...outsideRangeVaccines.map((v) => _buildVaccineTile(v)),
                    ],
                    if (alreadyTakenVaccines.isNotEmpty) ...[
                      _buildDropdownSectionHeader(
                        'Already Administered (Taken)',
                        AppColors.textSecondary,
                      ),
                      ...alreadyTakenVaccines.map((v) => _buildVaccineTile(v, isAlreadyTaken: true)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownSectionHeader(String title, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.08),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildVaccineTile(Map<String, dynamic> vaccine, {bool isAlreadyTaken = false}) {
    final vaccineName = vaccine['vaccine_name']?.toString() ?? '';
    final doseNumber = vaccine['dose_number']?.toString() ?? '';
    final notes = vaccine['notes']?.toString() ?? '';
    final recommendedAge = (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0;
    final ageText = _formatRecommendedAge(recommendedAge);
    
    final parts = <String>['$vaccineName (Dose $doseNumber)'];
    if (ageText.isNotEmpty) {
      parts.add(ageText);
    }
    if (notes.isNotEmpty && notes.toLowerCase() != ageText.toLowerCase()) {
      parts.add(notes);
    }
    if (isAlreadyTaken) {
      parts.add('(Already Recorded)');
    }
    final displayName = parts.join(' - ');

    return ListTile(
      leading: Icon(
        isAlreadyTaken ? Icons.check_circle_rounded : Icons.vaccines,
        color: isAlreadyTaken ? AppColors.success : AppColors.brandPrimary,
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontSize: 14,
          color: isAlreadyTaken ? AppColors.textSecondary : AppColors.textPrimary,
        ),
      ),
      onTap: () {
        setState(() {
          _selectedVaccineId = vaccine['vaccine_id'] as int;
          _vaccineController.text = displayName;
        });
        Navigator.pop(context);
      },
    );
  }

  /// "Pentavalent 3" — name plus dose, when the vaccine has more than one.
  String _vaccineLabel(Map<String, dynamic> vaccine) {
    final name = vaccine['vaccine_name']?.toString() ?? 'This vaccine';
    final dose = (vaccine['dose_number'] as num?)?.toInt() ?? 1;
    final hasMultipleDoses = _vaccines.any((v) =>
        v['vaccine_name'] == vaccine['vaccine_name'] &&
        ((v['dose_number'] as num?)?.toInt() ?? 1) > 1);
    return hasMultipleDoses ? '$name $dose' : name;
  }

  Future<void> _showBlockedDialog(String title, String message) {
    return showDialog(
      context: context,
      builder: (_) => DialogBox(
        type: DialogType.error,
        title: title,
        content: message,
        buttonText: 'OK',
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Future<bool?> _confirmMissingPrerequisite(String label, int doseNumber) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Earlier dose not recorded',
        subtitle:
            'Dose ${doseNumber - 1} of this vaccine is not on file for this child. '
            'Record $label anyway? Do this only if the earlier dose was given '
            'elsewhere — note where, in the remarks.',
        cancelText: 'Cancel',
        confirmText: 'Record anyway',
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
  }

  Future<bool> _submitImmunization() async {
    if (_selectedVaccineId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a vaccine.')),
        );
      }
      return false;
    }

    if (_selectedDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a vaccination date.')),
        );
      }
      return false;
    }

    final selected = _vaccines.firstWhere(
      (v) => v['vaccine_id'] == _selectedVaccineId,
      orElse: () => <String, dynamic>{},
    );
    final vaccineLabel = _vaccineLabel(selected);

    // Already recorded. The database now enforces this too, but catching it
    // here gives a readable message instead of a constraint error.
    if (_takenVaccineIds.contains(_selectedVaccineId)) {
      if (mounted) {
        await _showBlockedDialog(
          'Already recorded',
          '$vaccineLabel is already on this child\'s immunization record. '
          'Use the immunization list to review or correct the existing entry.',
        );
      }
      return false;
    }

    // Earlier dose missing. This is a warning rather than a hard block:
    // catch-up schedules are real, and a child may have been vaccinated
    // elsewhere. The midwife decides, and the decision is recorded.
    if (!_isPrerequisiteMet(selected)) {
      final doseNumber = (selected['dose_number'] as num?)?.toInt() ?? 1;
      final proceed = await _confirmMissingPrerequisite(
        vaccineLabel,
        doseNumber,
      );
      if (proceed != true) return false;
    }

    try {
      int? midwifeId;
      try {
        final accountId = await AuthStorage.getUserId();
        if (accountId != null) {
          final ctx = await SupabaseService.getMidwifeContext(accountId);
          midwifeId = ctx['midwife_id'] as int?;
        }
      } catch (e) {
        debugPrint('Error getting midwife ID: $e');
      }

      final vaccine = _vaccines.firstWhere(
        (v) => v['vaccine_id'] == _selectedVaccineId,
        orElse: () => <String, dynamic>{},
      );

      await Supabase.instance.client
          .from('immunization_records')
          .insert({
            'child_id': widget.childId,
            'vaccine_id': _selectedVaccineId!,
            'vaccination_date': _selectedDate!.toIso8601String().split('T')[0],
            // The column defaults to 1, so omitting it stored every dose as a
            // first dose — a Pentavalent 3 looked like a Pentavalent 1.
            'dose_number': (vaccine['dose_number'] as num?)?.toInt() ?? 1,
            'remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
            'created_at': DateTime.now().toIso8601String(),
            // The column is `administered_by`. This previously wrote
            // `recorded_by_midwife_id`, which the table does not declare.
            if (midwifeId != null) 'administered_by': midwifeId,
          });

      setState(() {
        _anyRecordAdded = true;
        // Keep the taken set current: this screen lets the midwife record
        // several vaccines without reloading, so a stale set would let the
        // same one through twice.
        _takenVaccineIds.add(_selectedVaccineId!);
      });

      return true;
    } catch (e) {
      debugPrint('Error saving immunization: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => DialogBox(
            type: DialogType.error,
            title: 'Cannot Save',
            content: e.toString().replaceAll('Exception: ', ''),
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );
      }
      return false;
    }
  }

  void _submit() {
    final selectedVaccine = _vaccines.firstWhere(
      (v) => v['vaccine_id'] == _selectedVaccineId,
      orElse: () => <String, dynamic>{},
    );
    final recommendedAge = (selectedVaccine['recommended_age_months'] as num?)?.toDouble() ?? 0;
    final childAgeMonths = _getChildAgeMonths();
    final isTooEarly = childAgeMonths < recommendedAge;
    final isPrereqPending = !_isPrerequisiteMet(selectedVaccine);
    final isAlreadyTaken = _takenVaccineIds.contains(_selectedVaccineId);
    final hasWarning = isTooEarly || isPrereqPending || isAlreadyTaken;

    String subtitle = 'Please review the details carefully. Immunization records cannot be edited once added.';
    List<String> warnings = [];
    if (isTooEarly) {
      warnings.add('this vaccine is scheduled before the recommended age');
    }
    if (isPrereqPending) {
      warnings.add('a previous dose for this vaccine is pending');
    }
    if (isAlreadyTaken) {
      warnings.add('this vaccine has already been administered to this child');
    }

    if (warnings.isNotEmpty) {
      final warningStr = warnings.map((w) => w[0].toUpperCase() + w.substring(1)).join(', ');
      subtitle = 'Warning: $warningStr. Are you sure you want to save?';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmationDialogBox(
        title: 'Confirm Immunization',
        subtitle: subtitle,
        confirmText: 'Confirm',
        cancelText: 'Cancel',
        accentColor: hasWarning ? AppColors.warning : AppColors.brandPrimary,
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);

          setState(() => _isLoading = true);

          final success = await _submitImmunization();

          setState(() => _isLoading = false);

          if (success) {
            try {
              final selectedVaccine = _vaccines.firstWhere(
                (v) => v['vaccine_id'] == _selectedVaccineId,
                orElse: () => <String, dynamic>{},
              );
              if (selectedVaccine.isNotEmpty) {
                final vName = selectedVaccine['vaccine_name']?.toString() ?? '';
                final vDose = selectedVaccine['dose_number']?.toString() ?? '';
                final vFull = '$vName (Dose $vDose)';
                SmsService.sendAutomatedVaccineSms(
                  childId: widget.childId,
                  recordedVaccines: [vFull],
                );

                // ── Push notification for the mother ──────────────────
                try {
                  final childRow = await Supabase.instance.client
                      .from('children')
                      .select('mother_id')
                      .eq('child_id', widget.childId)
                      .maybeSingle();
                  final motherId = childRow?['mother_id'] as int?;
                  if (motherId != null) {
                    final motherRow = await Supabase.instance.client
                        .from('mothers')
                        .select('account_id')
                        .eq('mother_id', motherId)
                        .maybeSingle();
                    final motherAccountId = motherRow?['account_id'] as int?;
                    if (motherAccountId != null) {
                      await NotificationService.createNotification(
                        accountId: motherAccountId,
                        title: 'Vaccine Recorded',
                        message: '$vFull has been recorded for your child.',
                        type: 'vaccine_reminder',
                      );
                    }
                  }
                } catch (pushError) {
                  debugPrint('Error sending vaccine push notification: $pushError');
                }
              }
            } catch (smsError) {
              debugPrint('Error triggering automated vaccine SMS: $smsError');
            }
          }

          if (success && mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => DialogBox(
                type: DialogType.success,
                title: 'Immunization Added',
                content: 'The immunization record has been successfully saved.',
                buttonText: 'OK',
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, true);
                },
              ),
            );
          }
        },
      ),
    );
  }

  /// Groups vaccines by recommended_age_months for the roadmap display.
  /// Returns a list of (milestoneLabel, vaccines) pairs sorted by age.
  List<MapEntry<String, List<Map<String, dynamic>>>> _getGroupedVaccines() {
    final Map<double, List<Map<String, dynamic>>> grouped = {};

    for (final v in _vaccines) {
      final age = (v['recommended_age_months'] as num?)?.toDouble() ?? 0;
      grouped.putIfAbsent(age, () => []);
      grouped[age]!.add(v);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    return sortedKeys.map((age) {
      return MapEntry(_getMilestoneLabel(age), grouped[age]!);
    }).toList();
  }

  /// Builds the immunization roadmap widget.
  Widget _buildRoadmap() {
    final groups = _getGroupedVaccines();
    if (groups.isEmpty) return const SizedBox.shrink();

    final givenCount = _vaccines.where((v) =>
        _takenVaccineIds.contains(v['vaccine_id'] as int)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.map_outlined, color: AppColors.brandPrimary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Immunization Roadmap',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '$givenCount / ${_vaccines.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _vaccines.isEmpty ? 0 : givenCount / _vaccines.length,
            backgroundColor: AppColors.borderPrimary,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _legendDot(AppColors.success, 'Given'),
            _legendDot(AppColors.warning, 'Recommended'),
            _legendDot(AppColors.textSecondary, 'Not due yet'),
          ],
        ),
        const SizedBox(height: 12),
        // Milestone groups
        ...groups.map((entry) => _buildMilestoneGroup(entry.key, entry.value)),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildMilestoneGroup(String label, List<Map<String, dynamic>> vaccines) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.brandAccent,
              ),
            ),
            const SizedBox(height: 6),
            ...vaccines.map((v) => _buildVaccineStatusRow(v)),
          ],
        ),
      ),
    );
  }

  Widget _buildVaccineStatusRow(Map<String, dynamic> vaccine) {
    final status = _getVaccineStatus(vaccine);
    final vaccineName = vaccine['vaccine_name']?.toString() ?? '';
    final doseNumber = vaccine['dose_number']?.toString() ?? '';
    final notes = vaccine['notes']?.toString() ?? '';

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (status) {
      case 'given':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        statusLabel = 'Already given';
        break;
      case 'recommended':
        statusColor = AppColors.warning;
        statusIcon = Icons.schedule;
        statusLabel = 'Recommended';
        break;
      default: // not_due
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.lock_outline;
        statusLabel = 'Not due yet';
    }

    final displayText = notes.isNotEmpty
        ? '$vaccineName (Dose $doseNumber) - $notes'
        : '$vaccineName (Dose $doseNumber)';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 12,
                color: status == 'not_due'
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                decoration: status == 'given'
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasEnteredData =>
      _selectedVaccineId != null ||
      _selectedDate != null ||
      _remarksController.text.trim().isNotEmpty;

  Future<void> _confirmDiscardAndPop() async {
    if (!_hasEnteredData) {
      Navigator.pop(context, _anyRecordAdded);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
            'You have unsaved immunization data. Are you sure you want to go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.pop(context, _anyRecordAdded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableVaccines = _getAvailableVaccines();
    final hasAvailableVaccines = availableVaccines.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _confirmDiscardAndPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Add Immunization',
          onBack: _confirmDiscardAndPop,
          trailing: TextButton.icon(
            onPressed: _startOcrFlow,
            icon: const Icon(Icons.document_scanner_outlined, size: 18),
            label: const Text('Scan'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandPrimary,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: PageTitle(
                  title: 'Vaccine Details',
                  leadingIcon: Icons.vaccines_rounded,
                  trailingIcon: Icons.check_circle,
                ),
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 16),
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Loading indicator
              if (_vaccinesLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(
                      color: AppColors.brandPrimary,
                    ),
                  ),
                ),

              // Roadmap has been moved to child_immunization_list_page.dart

              // Select Vaccine
              GestureDetector(
                onTap: _vaccinesLoading ? null : _openVaccineDropdown,
                child: AbsorbPointer(
                  child: AppInputField(
                    hintText: 'Select Vaccine',
                    controller: _vaccineController,
                    leadingIcon: Icons.vaccines_outlined,
                    trailingIcon: Icons.keyboard_arrow_down_rounded,
                    isRequired: true,
                  ),
                ),
              ),

              if (!_vaccinesLoading && !hasAvailableVaccines && _vaccines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, left: 8.0),
                  child: Text(
                    'All age-appropriate vaccines have been administered, '
                    'or the child has not reached the recommended age for remaining vaccines.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Select Date
              GestureDetector(
                onTap: _selectDate,
                child: AbsorbPointer(
                  child: AppInputField(
                    hintText: 'Vaccination Date',
                    controller: _dateController,
                    leadingIcon: Icons.calendar_month_rounded,
                    isRequired: true,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Remarks
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.bgSecondary,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.borderPrimary),
                ),
                child: TextField(
                  controller: _remarksController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: 'Remarks (optional)',
                    border: InputBorder.none,
                    icon: Icon(Icons.notes_rounded, color: AppColors.brandPrimary),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              if (!_isFormValid)
                const ValidationMessage(
                  message: 'Please complete all required fields before submitting.',
                  type: ValidationType.info,
                ),

              const SizedBox(height: 28),

              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brandPrimary,
                      ),
                    )
                  : MainButton(
                      label: 'Add Immunization Record',
                      onPressed: (_isFormValid && hasAvailableVaccines && !_vaccinesLoading) ? _submit : null,
                    ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ) );
  }
}
