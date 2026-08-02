import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_storage.dart';
import '../../services/groq_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/headline.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/confirmation_dialog_box.dart';

class LabTestAttachment {
  final String name;
  final String? path;
  final Uint8List? bytes;
  final int size;
  final bool isPdf;

  LabTestAttachment({
    required this.name,
    this.path,
    this.bytes,
    required this.size,
    required this.isPdf,
  });

  double get sizeMb => size / (1024 * 1024);
}

class AddLabTestPage extends StatefulWidget {
  const AddLabTestPage({
    super.key,
    required this.motherId,
    this.pregnancyId,
  });

  final int motherId;
  final int? pregnancyId;

  @override
  State<AddLabTestPage> createState() => _AddLabTestPageState();
}

class _AddLabTestPageState extends State<AddLabTestPage> {
  final ImagePicker _picker = ImagePicker();
  final GroqService _groqService = GroqService();

  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _workerNameCtrl = TextEditingController();
  final TextEditingController _institutionCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();
  final TextEditingController _customLabTypeCtrl = TextEditingController();

  DateTime? _date;
  int? _pregnancyId;
  String? _profession;
  String _selectedLabType = 'Complete Blood Count (CBC)';

  final List<LabTestAttachment> _attachments = [];

  bool _loading = true;
  bool _submitting = false;
  bool _processingDocument = false;
  bool _ocrExtracted = false;

  String? _workerNameError;
  String? _institutionError;

  static String? _workingBucket;

  static const List<String> _labTestTypes = [
    'Complete Blood Count (CBC)',
    'Urinalysis',
    'Fasting Blood Sugar (FBS)',
    'OGTT (Oral Glucose Tolerance Test)',
    'Blood Typing (ABO & Rh)',
    'HBsAg (Hepatitis B)',
    'VDRL / Syphilis Test',
    'HIV Test',
    'Stool Exam',
    'Other',
  ];

  static const List<String> _professions = [
    'Medical Technologist',
    'Pathologist',
    'Doctor',
    'Midwife',
    'Nurse',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _workerNameCtrl.addListener(_validateWorkerInline);
    _institutionCtrl.addListener(_validateWorkerInline);
    _loadPregnancyAndUser();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _workerNameCtrl.dispose();
    _institutionCtrl.dispose();
    _locationCtrl.dispose();
    _remarksCtrl.dispose();
    _customLabTypeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPregnancyAndUser() async {
    try {
      final userId = await AuthStorage.getUserId();
      if (userId != null) {
        final profile = await Supabase.instance.client
            .from('accounts')
            .select('first_name, last_name, account_type')
            .eq('account_id', userId)
            .maybeSingle();

        if (profile != null) {
          final fName = profile['first_name']?.toString() ?? '';
          final lName = profile['last_name']?.toString() ?? '';
          final fullName = '$fName $lName'.trim();
          if (fullName.isNotEmpty) {
            _workerNameCtrl.text = fullName;
          }
          if (profile['account_type'] != null && _profession == null) {
            _profession = profile['account_type'].toString();
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AddLabTest] User profile load error: $e');
    }

    try {
      if (widget.pregnancyId != null) {
        _pregnancyId = widget.pregnancyId;
      } else {
        final response = await Supabase.instance.client
            .from('pregnancies')
            .select('pregnancy_id, status')
            .eq('mother_id', widget.motherId)
            .eq('status', 'ongoing')
            .maybeSingle();

        if (response != null) {
          _pregnancyId = response['pregnancy_id'] as int?;
        }
      }

      if (_pregnancyId == null) {
        final newPregnancy = await Supabase.instance.client
            .from('pregnancies')
            .insert({
              'mother_id': widget.motherId,
              'status': 'ongoing',
              'fetal_count': 1,
            })
            .select('pregnancy_id')
            .single();

        _pregnancyId = newPregnancy['pregnancy_id'] as int?;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AddLabTest] Pregnancy load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _validateWorkerInline() {
    if (_workerNameCtrl.text.isNotEmpty && _workerNameError != null) {
      setState(() => _workerNameError = null);
    }
    if (_institutionCtrl.text.isNotEmpty && _institutionError != null) {
      setState(() => _institutionError = null);
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final List<LabTestAttachment> newAtts = [];
      for (final file in result.files) {
        final isPdf = file.extension?.toLowerCase() == 'pdf';
        final name = file.name;
        final bytes = file.bytes;
        final safePath = kIsWeb ? null : file.path;
        final size = file.size;

        final att = LabTestAttachment(
          name: name,
          path: safePath,
          bytes: bytes,
          size: size,
          isPdf: isPdf,
        );

        if (att.sizeMb > 10) {
          _showMessage('File "${att.name}" exceeds 10 MB limit.', type: AppSnackType.error);
          continue;
        }

        newAtts.add(att);
      }

      if (newAtts.isEmpty) return;

      setState(() {
        _attachments.addAll(newAtts);
      });

      _triggerAutoOcr();
    } catch (e) {
      _showMessage('Failed to pick files: $e', type: AppSnackType.error);
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
      if (image == null) return;

      final bytes = await image.readAsBytes();
      final name = 'lab_test_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final safePath = kIsWeb ? null : image.path;

      final att = LabTestAttachment(
        name: name,
        path: safePath,
        bytes: bytes,
        size: bytes.length,
        isPdf: false,
      );

      if (att.sizeMb > 10) {
        _showMessage('Captured photo exceeds 10 MB limit.', type: AppSnackType.error);
        return;
      }

      setState(() {
        _attachments.add(att);
      });

      _triggerAutoOcr();
    } catch (e) {
      _showMessage('Failed to capture photo: $e', type: AppSnackType.error);
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
      if (_attachments.isEmpty) {
        _ocrExtracted = false;
        _dateCtrl.clear();
        _date = null;
        _locationCtrl.clear();
        _institutionCtrl.clear();
        _remarksCtrl.clear();
        _customLabTypeCtrl.clear();
      }
    });
  }

  Future<void> _triggerAutoOcr() async {
    if (_attachments.isEmpty) return;

    setState(() {
      _processingDocument = true;
      _ocrExtracted = false;
    });

    try {
      final item = _attachments.firstWhere(
        (a) => !a.isPdf && (a.bytes != null || (a.path != null && a.path!.isNotEmpty)),
        orElse: () => _attachments.first,
      );

      if (!item.isPdf) {
        XFile xfile;
        if (item.bytes != null) {
          xfile = XFile.fromData(
            item.bytes!,
            name: item.name,
            mimeType: 'image/jpeg',
          );
        } else if (item.path != null && item.path!.isNotEmpty) {
          xfile = XFile(item.path!);
        } else {
          xfile = XFile.fromData(Uint8List(0), name: 'dummy');
        }

        if (xfile.name != 'dummy') {
          final data = await _groqService.extractLabTestSummaryOCR([xfile]);
          if (data.isNotEmpty && mounted) {
            setState(() {
              if (data['lab_test_date'] != null) {
                final rawDateStr = data['lab_test_date'].toString().trim();
                DateTime? dt = DateTime.tryParse(rawDateStr);
                if (dt != null) {
                  _date = dt;
                  _dateCtrl.text = DateFormat('MMM d, yyyy').format(dt);
                }
              }

              if (_isValidFieldValue(data['lab_test_type'])) {
                final detectedType = data['lab_test_type'].toString().trim();
                final matchedOption = _labTestTypes.firstWhere(
                  (opt) => opt.toLowerCase().contains(detectedType.toLowerCase()) || detectedType.toLowerCase().contains(opt.toLowerCase()),
                  orElse: () => 'Other',
                );
                if (matchedOption != 'Other') {
                  _selectedLabType = matchedOption;
                  _customLabTypeCtrl.clear();
                } else if (_isValidFieldValue(detectedType) && !detectedType.toLowerCase().contains('json')) {
                  _selectedLabType = 'Other';
                  _customLabTypeCtrl.text = detectedType;
                } else {
                  _selectedLabType = 'Complete Blood Count (CBC)';
                  _customLabTypeCtrl.clear();
                }
              }

              if (_isValidFieldValue(data['institution_name'])) {
                _institutionCtrl.text = data['institution_name'].toString().trim();
              }
              if (_isValidFieldValue(data['location_facility'])) {
                _locationCtrl.text = data['location_facility'].toString().trim();
              }

              if (_locationCtrl.text.isEmpty && _isValidFieldValue(_institutionCtrl.text)) {
                _locationCtrl.text = _institutionCtrl.text;
              }
              if (_institutionCtrl.text.isEmpty && _isValidFieldValue(_locationCtrl.text)) {
                _institutionCtrl.text = _locationCtrl.text;
              }

              if (_isValidFieldValue(data['health_worker_name'])) {
                _workerNameCtrl.text = data['health_worker_name'].toString().trim();
              }
              if (_isValidFieldValue(data['health_worker_profession'])) {
                final prof = data['health_worker_profession'].toString().trim();
                final matchedProf = _professions.firstWhere(
                  (p) => p.toLowerCase().contains(prof.toLowerCase()),
                  orElse: () => _profession ?? 'Medical Technologist',
                );
                _profession = matchedProf;
              }
              if (_isValidFieldValue(data['remarks'])) {
                _remarksCtrl.text = data['remarks'].toString().trim();
              }

              _ocrExtracted = true;
            });
          }
        }
      }
      _date ??= DateTime.now();
      if (_dateCtrl.text.isEmpty && _date != null) {
        _dateCtrl.text = DateFormat('MMM d, yyyy').format(_date!);
      }
    } catch (_) {
      _date ??= DateTime.now();
    } finally {
      if (mounted) setState(() => _processingDocument = false);
    }
  }

  bool _isValidFieldValue(dynamic input) {
    if (input == null) return false;
    final str = input.toString().trim();
    if (str.isEmpty) return false;
    final lower = str.toLowerCase();
    if (lower.startsWith('looking') ||
        lower.startsWith('see') ||
        lower.startsWith('top header') ||
        lower.startsWith('header says') ||
        lower.startsWith('look for') ||
        lower.startsWith('read the') ||
        lower.startsWith('the section') ||
        lower.startsWith('the impression') ||
        lower.contains('the user') ||
        lower.contains('user wants') ||
        lower.contains('report image') ||
        lower.contains('into a specific') ||
        lower.contains('json format') ||
        lower.contains('at the bottom') ||
        lower.contains('there are') ||
        lower.contains('signatures') ||
        lower.contains('need to') ||
        lower.contains('summarize') ||
        lower.contains('extract data') ||
        lower.contains('not specified') ||
        lower.contains('null')) {
      return false;
    }
    return true;
  }

  void _showMessage(String msg, {AppSnackType type = AppSnackType.info}) {
    if (mounted) AppSnackbar.show(context, msg, type: type);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor: Colors.white,
              elevation: 4,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    setState(() {
      _date = picked;
      _dateCtrl.text = DateFormat('MMM d, yyyy').format(picked);
    });
  }

  void _showImagePreviewModal(LabTestAttachment item) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(item.name, style: const TextStyle(fontSize: 14)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: item.isPdf
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.picture_as_pdf, color: Colors.red, size: 64),
                          SizedBox(height: 8),
                          Text('PDF Document Attached', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  : item.bytes != null
                      ? Image.memory(item.bytes!, fit: BoxFit.contain)
                      : (!kIsWeb && item.path != null)
                          ? Image.file(File(item.path!), fit: BoxFit.contain)
                          : const Icon(Icons.image, size: 64),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showDiscardConfirmationDialog() async {
    if (!_hasUnsavedData) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmationDialogBox(
        title: 'Discard lab test record?',
        subtitle: 'You have unsaved lab test document and record details. Are you sure you want to discard these changes?',
        cancelText: 'Cancel',
        confirmText: 'Discard',
        onCancel: () => Navigator.pop(ctx, false),
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    );
    return result ?? false;
  }

  void _handleBack() async {
    final shouldDiscard = await _showDiscardConfirmationDialog();
    if (shouldDiscard && mounted) {
      Navigator.pop(context);
    }
  }

  bool get _hasUnsavedData {
    return _attachments.isNotEmpty ||
        _workerNameCtrl.text.isNotEmpty ||
        _institutionCtrl.text.isNotEmpty ||
        _locationCtrl.text.isNotEmpty ||
        _remarksCtrl.text.isNotEmpty;
  }

  Future<List<String>> _uploadAttachments() async {
    if (_attachments.isEmpty) return [];

    final client = Supabase.instance.client;
    final List<String> urls = [];

    if (_workingBucket == 'none') {
      for (final att in _attachments) {
        if (att.bytes != null) {
          final b64 = base64Encode(att.bytes!);
          final mime = att.isPdf ? 'application/pdf' : 'image/jpeg';
          urls.add('data:$mime;base64,$b64');
        }
      }
      return urls;
    }

    final bucketsToTry = _workingBucket != null ? [_workingBucket!] : ['files', 'ultrasounds', 'documents'];

    for (final att in _attachments) {
      if (att.bytes == null && att.path == null) continue;

      final ext = att.name.contains('.') ? att.name.split('.').last : 'jpg';
      final fileName = 'lab_tests/mother_${widget.motherId}/${DateTime.now().millisecondsSinceEpoch}_${att.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';

      Uint8List fileBytes;
      if (att.bytes != null) {
        fileBytes = att.bytes!;
      } else {
        fileBytes = await File(att.path!).readAsBytes();
      }

      String? uploadedUrl;

      for (final bucket in bucketsToTry) {
        try {
          await client.storage.from(bucket).uploadBinary(
            fileName,
            fileBytes,
            fileOptions: FileOptions(
              contentType: att.isPdf ? 'application/pdf' : 'image/$ext',
              upsert: true,
            ),
          ).timeout(const Duration(milliseconds: 500));

          uploadedUrl = client.storage.from(bucket).getPublicUrl(fileName);
          _workingBucket = bucket;
          break;
        } catch (e) {
          if (kDebugMode) debugPrint('[AddLabTest] Bucket $bucket upload skipped/failed: $e');
        }
      }

      if (uploadedUrl != null) {
        urls.add(uploadedUrl);
      } else {
        final b64 = base64Encode(fileBytes);
        final mime = att.isPdf ? 'application/pdf' : 'image/jpeg';
        urls.add('data:$mime;base64,$b64');
      }
    }

    _workingBucket ??= 'none';

    return urls;
  }

  Future<void> _submit() async {
    final effectiveLabType = _selectedLabType == 'Other'
        ? (_customLabTypeCtrl.text.trim().isNotEmpty ? _customLabTypeCtrl.text.trim() : 'Other')
        : _selectedLabType;

    _date ??= DateTime.now();

    setState(() {
      _submitting = true;
      _workerNameError = null;
      _institutionError = null;
    });

    try {
      int? midwifeId;
      try {
        final accountId = await AuthStorage.getUserId();
        if (accountId != null) {
          final ctx = await SupabaseService.getMidwifeContext(accountId);
          midwifeId = int.tryParse(ctx['midwife_id']?.toString() ?? '');
        }
      } catch (_) {}

      final attachmentUrls = await _uploadAttachments();
      final imageValue = attachmentUrls.isNotEmpty ? attachmentUrls.join(',') : null;

      // 1. Create parent clinical encounter record first to get encounter_id and store encounter_datetime
      int? encounterId;
      try {
        final encRow = await Supabase.instance.client
            .from('clinical_encounters')
            .insert({
              'pregnancy_id': _pregnancyId,
              'mother_id': widget.motherId,
              if (midwifeId != null) 'recorded_by': midwifeId,
              'encounter_type': 'lab_test',
              'encounter_datetime': _date?.toIso8601String() ?? DateTime.now().toIso8601String(),
              'midwife_notes': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
            })
            .select('encounter_id')
            .maybeSingle();

        if (encRow != null) {
          encounterId = int.tryParse(encRow['encounter_id']?.toString() ?? '');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[AddLabTest] Clinical encounter insert note: $e');
      }

      // 2. Insert into lab_tests matching the database schema
      final labTestData = <String, dynamic>{
        if (encounterId != null) 'encounter_id': encounterId,
        'pregnancy_id': _pregnancyId!,
        'lab_test_type': effectiveLabType,
        'lab_test_location': _locationCtrl.text.trim().isNotEmpty ? _locationCtrl.text.trim() : 'Not specified',
        'health_worker_name': _workerNameCtrl.text.trim().isNotEmpty ? _workerNameCtrl.text.trim() : null,
        'health_worker_institution': _institutionCtrl.text.trim().isNotEmpty ? _institutionCtrl.text.trim() : null,
        'health_worker_profession': _profession ?? 'Medical Technologist',
        'lab_test_image': imageValue,
        'file_url': imageValue,
      };

      await Supabase.instance.client.from('lab_tests').insert(labTestData);

      if (mounted) {
        AppSnackbar.show(context, 'Lab test record saved successfully', type: AppSnackType.success);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, 'Failed to save lab test: $e', type: AppSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Headline(
            text: title,
            fontSize: 17,
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SecondaryHeader(
                title: 'Record Lab Test',
                onBack: _handleBack,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Card 1: Document Upload / Dropzone ─────────────────────
                      _buildUploadSectionCard(),
                      const SizedBox(height: 16),

                      // ── Card 2: Lab Test Information ────────────────────
                      _sectionCard(
                        title: 'Lab Test Information',
                        child: Column(
                          children: [
                            AppDropdownField<String>(
                              hintText: 'Lab Test Conducted',
                              leadingIcon: Icons.science_outlined,
                              value: _selectedLabType,
                              options: _labTestTypes,
                              displayStringForOption: (val) => val,
                              onSelected: (val) => setState(() => _selectedLabType = val),
                            ),
                            if (_selectedLabType == 'Other') ...[
                              const SizedBox(height: 12),
                              AppInputField(
                                hintText: 'Specify Lab Test Name',
                                controller: _customLabTypeCtrl,
                                leadingIcon: Icons.edit_outlined,
                              ),
                            ],
                            const SizedBox(height: 12),
                            AppInputField(
                              hintText: 'Lab Test Date',
                              controller: _dateCtrl,
                              leadingIcon: Icons.calendar_today_outlined,
                              readOnly: true,
                              onTap: _pickDate,
                              isRequired: true,
                            ),
                            const SizedBox(height: 12),
                            AppInputField(
                              hintText: 'Location / Facility (e.g. Hi-Precision Diagnostics)',
                              controller: _locationCtrl,
                              leadingIcon: Icons.location_on_outlined,
                            ),
                            const SizedBox(height: 12),
                            AppInputField(
                              hintText: 'Institution',
                              controller: _institutionCtrl,
                              leadingIcon: Icons.business_outlined,
                              isRequired: true,
                              errorText: _institutionError,
                            ),
                            const SizedBox(height: 12),
                            AppInputField(
                              hintText: 'Healthcare Worker Name',
                              controller: _workerNameCtrl,
                              leadingIcon: Icons.person_outline,
                              isRequired: true,
                              errorText: _workerNameError,
                            ),
                            const SizedBox(height: 12),
                            AppDropdownField<String>(
                              hintText: 'Profession',
                              leadingIcon: Icons.badge_outlined,
                              value: _professions.contains(_profession) ? _profession! : 'Medical Technologist',
                              options: _professions,
                              displayStringForOption: (val) => val,
                              onSelected: (val) => setState(() => _profession = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Card 3: Results & Findings Summary ────────────
                      _sectionCard(
                        title: 'Results & Findings Summary',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _remarksCtrl,
                              maxLines: 5,
                              maxLength: 1000,
                              style: const TextStyle(fontSize: 13, height: 1.5),
                              decoration: InputDecoration(
                                hintText: 'Lab report findings, impressions, or extracted lab values (editable)...',
                                hintStyle: TextStyle(
                                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                                ),
                                border: const OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.borderPrimary),
                                ),
                                enabledBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.borderPrimary),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.brandPrimary, width: 1.5),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Lab Test Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Unified Document Upload Section Card ──────────────────────────────

  Widget _buildUploadSectionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Headline(
                text: 'Attach Lab Test Document',
                fontSize: 17,
              ),
              if (_attachments.isNotEmpty)
                TextButton.icon(
                  onPressed: _processingDocument ? null : _triggerAutoOcr,
                  icon: _processingDocument
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPrimary))
                      : const Icon(Icons.auto_awesome, size: 16, color: AppColors.brandPrimary),
                  label: Text(
                    _processingDocument ? 'Scanning...' : 'Re-scan OCR',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandPrimary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Upload lab result photos (JPG, PNG) or diagnostic PDF reports. Maximum 10 MB per file.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // Dropzone / Thumbnail container
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.25), width: 1.5),
            ),
            child: Column(
              children: [
                if (_attachments.isEmpty) ...[
                  const Icon(Icons.cloud_upload_outlined, size: 44, color: AppColors.brandPrimary),
                  const SizedBox(height: 8),
                  const Text(
                    'Attach Lab Test Picture or PDF',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Supports JPG, PNG, PDF (Up to 10 MB)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(_attachments.length, (idx) {
                      final item = _attachments[idx];
                      return GestureDetector(
                        onTap: () => _showImagePreviewModal(item),
                        child: Stack(
                          children: [
                            Container(
                              width: 120,
                              height: 110,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.3)),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
                                ],
                              ),
                              child: item.isPdf
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.picture_as_pdf, color: Colors.red, size: 36),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          '${item.sizeMb.toStringAsFixed(1)} MB',
                                          style: const TextStyle(fontSize: 9, color: Colors.grey),
                                        ),
                                      ],
                                    )
                                  : item.bytes != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.memory(item.bytes!, fit: BoxFit.cover, width: 108, height: 98),
                                        )
                                      : (!kIsWeb && item.path != null && item.path!.isNotEmpty)
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.file(File(item.path!), fit: BoxFit.cover, width: 108, height: 98),
                                            )
                                          : const Icon(Icons.image, size: 36),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => _removeAttachment(idx),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                ],

                // OCR Status Badge
                if (_processingDocument) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPrimary)),
                        SizedBox(width: 8),
                        Text('Scanning document for OCR fields...', style: TextStyle(fontSize: 12, color: AppColors.brandPrimary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ] else if (_ocrExtracted) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text('✓ Fields Auto-Extracted! Review or edit below.', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _attachments.length >= 5 ? null : _pickFiles,
                      icon: Icon(_attachments.isEmpty ? Icons.attach_file : Icons.add, size: 18),
                      label: Text(_attachments.isEmpty ? 'Choose File (JPG/PNG/PDF)' : 'Add File'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _attachments.length >= 5 ? null : _capturePhoto,
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: const Text('Take Photo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brandPrimary,
                        side: BorderSide(color: AppColors.brandPrimary.withValues(alpha: 0.4), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
