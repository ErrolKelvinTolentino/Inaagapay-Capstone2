import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_storage.dart';
import '../../services/groq_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/headline.dart';
import '../../widgets/secondary_header.dart';

class UltrasoundAttachment {
  final String name;
  final String? path;
  final Uint8List? bytes;
  final int size;
  final bool isPdf;

  UltrasoundAttachment({
    required this.name,
    this.path,
    this.bytes,
    required this.size,
    required this.isPdf,
  });

  double get sizeMb => size / (1024 * 1024);
}

class AddUltrasoundPage extends StatefulWidget {
  const AddUltrasoundPage({
    super.key,
    required this.motherId,
  });

  final int motherId;

  @override
  State<AddUltrasoundPage> createState() => _AddUltrasoundPageState();
}

class _AddUltrasoundPageState extends State<AddUltrasoundPage> {
  final ImagePicker _picker = ImagePicker();
  final GroqService _groqService = GroqService();

  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _workerNameCtrl = TextEditingController();
  final TextEditingController _institutionCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();
  final TextEditingController _egaWeeksCtrl = TextEditingController();
  final TextEditingController _egaDaysCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();

  DateTime? _date;
  DateTime? _pregnancyLmp;
  DateTime? _pregnancyEdd;
  int? _pregnancyId;
  String? _profession;
  int _fetalCount = 1;

  final List<UltrasoundAttachment> _attachments = [];

  bool _loading = true;
  bool _submitting = false;
  bool _processingDocument = false;

  int _step = 0; // 0: Upload File, 1: Review Extracted Data & Save

  bool _eddRedated = false;
  DateTime? _originalEdd;

  final String _aiInsightStatus = 'not_assisted';

  String? _workerNameError;
  String? _institutionError;

  @override
  void initState() {
    super.initState();
    _workerNameCtrl.addListener(_validateWorkerInline);
    _institutionCtrl.addListener(_validateWorkerInline);
    _loadPregnancyAndUser();
  }

  @override
  void dispose() {
    _workerNameCtrl.dispose();
    _institutionCtrl.dispose();
    _locationCtrl.dispose();
    _egaWeeksCtrl.dispose();
    _egaDaysCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPregnancyAndUser() async {
    try {
      final userId = await AuthStorage.getUserId();
      if (userId != null) {
        final profile = await Supabase.instance.client
            .from('users')
            .select('first_name, last_name, role')
            .eq('account_id', userId)
            .maybeSingle();

        if (profile != null) {
          final fName = profile['first_name']?.toString() ?? '';
          final lName = profile['last_name']?.toString() ?? '';
          final fullName = '$fName $lName'.trim();
          if (fullName.isNotEmpty) {
            _workerNameCtrl.text = fullName;
          }
          if (profile['role'] != null && _profession == null) {
            _profession = profile['role'].toString();
          }
        }
      }

      final response = await Supabase.instance.client
          .from('pregnancies')
          .select('pregnancy_id, last_menstrual_period, expected_date_of_delivery, fetal_count')
          .eq('mother_id', widget.motherId)
          .eq('status', 'ongoing')
          .maybeSingle();

      _pregnancyId = response?['pregnancy_id'] as int?;
      _pregnancyLmp = response?['last_menstrual_period'] != null
          ? DateTime.tryParse(response!['last_menstrual_period'].toString())
          : null;
      _pregnancyEdd = response?['expected_date_of_delivery'] != null
          ? DateTime.tryParse(response!['expected_date_of_delivery'].toString())
          : null;
      _originalEdd = _pregnancyEdd;
      _fetalCount = (response?['fetal_count'] as int?) ?? 1;
    } catch (_) {
      _pregnancyId = null;
      _pregnancyLmp = null;
      _pregnancyEdd = null;
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _showMessage(String message, {AppSnackType type = AppSnackType.warning}) {
    AppSnackbar.show(context, message, type: type);
  }

  void _validateWorkerInline() {
    final worker = _workerNameCtrl.text.trim();
    final institution = _institutionCtrl.text.trim();
    setState(() {
      _workerNameError = (worker.isNotEmpty && (worker.length < 3 || worker.length > 80))
          ? 'Must be 3 to 80 characters'
          : null;
      _institutionError = (institution.isNotEmpty && (institution.length < 3 || institution.length > 120))
          ? 'Must be 3 to 120 characters'
          : null;
    });
  }

  // ── Attachment Pickers (JPG, PNG, PDF up to 10MB) ─────────────────────

  Future<void> _pickFiles() async {
    if (_attachments.length >= 5) {
      _showMessage('Maximum 5 attachments allowed per ultrasound record.');
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: true,
        withData: true, // Always request bytes so it works on Web and Mobile
      );

      if (result == null || result.files.isEmpty) return;

      final newAttachments = <UltrasoundAttachment>[];
      for (final file in result.files) {
        if (file.size > 10 * 1024 * 1024) {
          _showMessage('File "${file.name}" exceeds the 10 MB limit.', type: AppSnackType.error);
          continue;
        }

        final ext = (file.extension ?? '').toLowerCase();
        final isPdf = ext == 'pdf';
        final safePath = kIsWeb ? null : file.path;

        newAttachments.add(
          UltrasoundAttachment(
            name: file.name,
            path: safePath,
            bytes: file.bytes,
            size: file.size,
            isPdf: isPdf,
          ),
        );
      }

      if (newAttachments.isNotEmpty && mounted) {
        setState(() {
          _attachments.addAll(newAttachments.take(5 - _attachments.length));
        });
      }
    } catch (e) {
      _showMessage('Unable to pick files: $e', type: AppSnackType.error);
    }
  }

  Future<void> _capturePhoto() async {
    if (_attachments.length >= 5) {
      _showMessage('Maximum 5 attachments allowed per ultrasound record.');
      return;
    }

    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;

      final bytes = await image.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        _showMessage('Captured photo exceeds the 10 MB limit.', type: AppSnackType.error);
        return;
      }

      final safePath = kIsWeb ? null : image.path;
      setState(() {
        _attachments.add(
          UltrasoundAttachment(
            name: image.name,
            path: safePath,
            bytes: bytes,
            size: bytes.length,
            isPdf: false,
          ),
        );
      });
    } catch (e) {
      _showMessage('Unable to capture photo: $e', type: AppSnackType.error);
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  // ── Step Transition & Document Extraction ─────────────────────────────

  Future<void> _proceedToReview() async {
    if (_attachments.isEmpty) {
      _showMessage('Please attach an ultrasound photo or PDF document first.');
      return;
    }

    setState(() => _processingDocument = true);

    try {
      // Find first image attachment for vision OCR
      final imageAttachment = _attachments.firstWhere(
        (a) => !a.isPdf && (a.bytes != null || (a.path != null && a.path!.isNotEmpty)),
        orElse: () => _attachments.first,
      );

      if (!imageAttachment.isPdf) {
        XFile xfile;
        if (imageAttachment.bytes != null) {
          xfile = XFile.fromData(
            imageAttachment.bytes!,
            name: imageAttachment.name,
            mimeType: 'image/jpeg',
          );
        } else if (imageAttachment.path != null && imageAttachment.path!.isNotEmpty) {
          xfile = XFile(imageAttachment.path!);
        } else {
          xfile = XFile.fromData(Uint8List(0), name: 'dummy');
        }

        if (xfile.name != 'dummy') {
          final data = await _groqService.extractUltrasoundSummaryOCR([xfile]);

          if (data.isNotEmpty) {
            if (data['ultrasound_date'] != null) {
              final dt = DateTime.tryParse(data['ultrasound_date'].toString());
              if (dt != null) {
                _date = dt;
                _dateCtrl.text = DateFormat('MMM d, yyyy').format(dt);
              }
            }
            if (data['ega_weeks'] != null) {
              _egaWeeksCtrl.text = data['ega_weeks'].toString();
            }
            if (data['ega_days'] != null) {
              _egaDaysCtrl.text = data['ega_days'].toString();
            }
            if (data['location_facility'] != null && data['location_facility'].toString().trim().isNotEmpty) {
              _locationCtrl.text = data['location_facility'].toString();
            } else if (data['institution_name'] != null && data['institution_name'].toString().trim().isNotEmpty) {
              _locationCtrl.text = data['institution_name'].toString();
            }
            if (data['sonologist_name'] != null && data['sonologist_name'].toString().trim().isNotEmpty) {
              _workerNameCtrl.text = data['sonologist_name'].toString();
            }
            if (data['institution_name'] != null && data['institution_name'].toString().trim().isNotEmpty) {
              _institutionCtrl.text = data['institution_name'].toString();
            }
            if (data['sonologist_remarks'] != null && data['sonologist_remarks'].toString().trim().isNotEmpty) {
              _remarksCtrl.text = data['sonologist_remarks'].toString();
            }
            if (data['fetal_count'] != null) {
              final fc = int.tryParse(data['fetal_count'].toString());
              if (fc != null && fc > 0) _fetalCount = fc;
            }
          }
        }
      }

      // Default date to today if OCR didn't find date
      _date ??= DateTime.now();

      if (mounted) {
        setState(() {
          _step = 1;
        });
      }
    } catch (e) {
      _date ??= DateTime.now();
      if (mounted) {
        setState(() {
          _step = 1;
        });
      }
    } finally {
      if (mounted) setState(() => _processingDocument = false);
    }
  }

  // ── Gestational Age & Discrepancy Logic ────────────────────────────────

  /// Registered AOG as of the date the ultrasound was actually taken
  double get registeredAogWeeksOnScanDate {
    if (_originalEdd == null || _date == null) return 0.0;
    final daysUntilEdd = _originalEdd!.difference(_date!).inDays;
    final aogDays = 280 - daysUntilEdd;
    return (aogDays / 7.0).clamp(0.0, 42.0);
  }

  int get registeredAogDaysOnScanDate {
    final weeks = registeredAogWeeksOnScanDate;
    return (weeks * 7).round();
  }

  /// Total Ultrasound EGA in days
  int get ultrasoundEgaTotalDays {
    final w = int.tryParse(_egaWeeksCtrl.text.trim()) ?? 0;
    final d = int.tryParse(_egaDaysCtrl.text.trim()) ?? 0;
    return w * 7 + d;
  }

  /// Discrepancy between Ultrasound EGA and Registered AOG on scan date (in days)
  int get discrepancyDays {
    if (_date == null || ultrasoundEgaTotalDays <= 0) return 0;
    return (ultrasoundEgaTotalDays - registeredAogDaysOnScanDate).abs();
  }

  /// Significant discrepancy check (>= 7 days for 2nd/3rd trimester, >= 5 days for 1st trimester)
  bool get hasSignificantDiscrepancy {
    if (_date == null || ultrasoundEgaTotalDays <= 0) return false;
    final isFirstTrimester = registeredAogWeeksOnScanDate <= 13.0;
    final threshold = isFirstTrimester ? 5 : 7;
    return discrepancyDays >= threshold;
  }

  void _redatePregnancyEdd() {
    if (_date == null || ultrasoundEgaTotalDays <= 0) return;

    // Corrected EDD = Ultrasound Date + (280 - Ultrasound EGA in days)
    final daysRemaining = 280 - ultrasoundEgaTotalDays;
    final newEdd = _date!.add(Duration(days: daysRemaining));
    final newLmp = newEdd.subtract(const Duration(days: 280));

    setState(() {
      _pregnancyEdd = newEdd;
      _pregnancyLmp = newLmp;
      _eddRedated = true;
    });

    _showMessage(
      'Official EDD updated to ${DateFormat('MMM d, yyyy').format(newEdd)} based on ultrasound.',
      type: AppSnackType.success,
    );
  }

  // ── Date Picker ────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = _pregnancyLmp != null
        ? DateTime(_pregnancyLmp!.year, _pregnancyLmp!.month, _pregnancyLmp!.day)
        : DateTime(2000);

    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: first,
      lastDate: now,
      helpText: _pregnancyLmp == null
          ? 'Select Ultrasound Date'
          : 'Select date after LMP (${DateFormat('MMM d, yyyy').format(_pregnancyLmp!)})',
    );

    if (picked == null) return;
    setState(() {
      _date = picked;
      _dateCtrl.text = DateFormat('MMM d, yyyy').format(picked);
    });
  }

  // ── Validation & Submission ─────────────────────────────────────────────

  bool _validateForm() {
    final worker = _workerNameCtrl.text.trim();
    final institution = _institutionCtrl.text.trim();

    if (_date == null) {
      _showMessage('Please select ultrasound date.');
      return false;
    }
    if (_date!.isAfter(DateTime.now())) {
      _showMessage('Future ultrasound dates are not allowed.');
      return false;
    }
    if (worker.isEmpty || worker.length < 3 || worker.length > 80) {
      _showMessage('Health worker / Sonologist name must be 3 to 80 characters.');
      return false;
    }
    if (institution.isEmpty || institution.length < 3 || institution.length > 120) {
      _showMessage('Institution must be 3 to 120 characters.');
      return false;
    }

    final egaW = int.tryParse(_egaWeeksCtrl.text.trim());
    if (egaW == null || egaW < 3 || egaW > 44) {
      _showMessage('Please enter valid Ultrasound EGA (weeks 3–44).');
      return false;
    }

    return true;
  }

  Future<List<String>> _uploadAttachments() async {
    final urls = <String>[];
    for (int i = 0; i < _attachments.length; i++) {
      final item = _attachments[i];
      final ext = item.isPdf ? 'pdf' : 'jpg';
      final fileName = 'ultrasound_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      final filePath = 'ultrasounds/${widget.motherId}/$fileName';

      Uint8List? bytes = item.bytes;
      if (bytes == null && !kIsWeb && item.path != null && item.path!.isNotEmpty) {
        bytes = await File(item.path!).readAsBytes();
      }
      if (bytes == null) continue;

      final mime = item.isPdf ? 'application/pdf' : 'image/jpeg';

      await Supabase.instance.client.storage.from('files').uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(contentType: mime, upsert: true),
      );

      final publicUrl = Supabase.instance.client.storage.from('files').getPublicUrl(filePath);
      urls.add(publicUrl);
    }
    return urls;
  }

  Future<void> _submit() async {
    if (!_validateForm()) return;
    if (_pregnancyId == null) {
      _showMessage('No ongoing pregnancy found for this mother.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final userId = await AuthStorage.getUserId();
      final urls = await _uploadAttachments();

      final inserted = await Supabase.instance.client
          .from('ultrasounds')
          .insert({
            'pregnancy_id': _pregnancyId,
            'ultrasound_date': DateFormat('yyyy-MM-dd').format(_date!),
            'ultrasound_location': _locationCtrl.text.trim().isEmpty ? 'Clinic' : _locationCtrl.text.trim(),
            'ultrasound_image': urls.isEmpty ? null : urls.join(','),
            'remarks': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
            'health_worker_name': _workerNameCtrl.text.trim(),
            'health_worker_institution': _institutionCtrl.text.trim(),
            'health_worker_profession': _profession ?? 'Sonographer',
            'estimated_gestational_age_weeks': int.tryParse(_egaWeeksCtrl.text.trim()),
            'estimated_gestational_age_days': int.tryParse(_egaDaysCtrl.text.trim()) ?? 0,
            'fetal_count': _fetalCount,
            'ai_insight': null,
            'ai_insight_status': _aiInsightStatus,
            'recorded_by': _workerNameCtrl.text.trim(),
            'recorded_at': DateTime.now().toIso8601String(),
          })
          .select('ultrasound_id')
          .single();

      final ultrasoundId = inserted['ultrasound_id'] as int;

      // Update Pregnancy Record if EDD re-dated or Fetus count updated
      final pregnancyUpdates = <String, dynamic>{
        'fetal_count': _fetalCount,
      };
      if (_eddRedated && _pregnancyEdd != null) {
        pregnancyUpdates['expected_date_of_delivery'] = DateFormat('yyyy-MM-dd').format(_pregnancyEdd!);
        if (_pregnancyLmp != null) {
          pregnancyUpdates['last_menstrual_period'] = DateFormat('yyyy-MM-dd').format(_pregnancyLmp!);
        }
      }

      await Supabase.instance.client
          .from('pregnancies')
          .update(pregnancyUpdates)
          .eq('pregnancy_id', _pregnancyId!);

      // Audit Trail
      if (userId != null) {
        await Supabase.instance.client.from('audit_trail').insert({
          'action': 'ULTRASOUND_RECORDED',
          'table_name': 'ultrasounds',
          'account_id': userId,
          'new_data': {
            'ultrasound_id': ultrasoundId,
            'pregnancy_id': _pregnancyId,
            'edd_redated': _eddRedated,
            'ai_insight_status': _aiInsightStatus,
          },
          'description': 'Ultrasound recorded for pregnancy_id=$_pregnancyId by ${_workerNameCtrl.text.trim()}.',
        });
      }

      if (!mounted) return;
      _showMessage('Ultrasound record saved successfully.', type: AppSnackType.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Error saving ultrasound record: $e', type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI BUILDERS ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final headerTitle = _step == 0 ? 'Upload Ultrasound' : 'Review & Save Record';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SecondaryHeader(
              title: headerTitle,
              onBack: () {
                if (_step == 1) {
                  setState(() => _step = 0);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            Expanded(
              child: _processingDocument
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppColors.brandPrimary),
                          SizedBox(height: 16),
                          Text('Reading ultrasound document...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          SizedBox(height: 4),
                          Text('Extracting dates, EGA, and clinical findings...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _step == 0 ? _buildStep1Upload() : _buildStep2Review(),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _processingDocument
          ? null
          : Container(
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
                child: _step == 0
                    ? SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _proceedToReview,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: SizedBox(
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => _step = 0),
                                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                                label: const Text('Back'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.brandPrimary,
                                  side: BorderSide(color: AppColors.brandPrimary.withValues(alpha: 0.4), width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
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
                                    : const Text('Save Ultrasound Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
    );
  }

  // ── Step 1: Upload Ultrasound Photo / PDF ──────────────────────────────

  Widget _buildStep1Upload() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Headline(
          text: 'Attach Ultrasound Document',
          fontSize: 20,
        ),
        const SizedBox(height: 6),
        Text(
          'Upload ultrasound scan photos (JPG, PNG) or diagnostic PDF reports. Maximum 10 MB per file.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),

        // Attachment Dropzone
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
                const Icon(Icons.cloud_upload_outlined, size: 48, color: AppColors.brandPrimary),
                const SizedBox(height: 10),
                const Text(
                  'Attach Ultrasound Picture or PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Supports JPG, PNG, PDF (Up to 10 MB)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(_attachments.length, (idx) {
                    final item = _attachments[idx];
                    return Stack(
                      children: [
                        Container(
                          width: 110,
                          height: 100,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
                            ],
                          ),
                          child: item.isPdf
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.picture_as_pdf, color: Colors.red, size: 32),
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
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.memory(item.bytes!, fit: BoxFit.cover, width: 98, height: 88),
                                    )
                                  : (!kIsWeb && item.path != null && item.path!.isNotEmpty)
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.file(File(item.path!), fit: BoxFit.cover, width: 98, height: 88),
                                        )
                                      : const Icon(Icons.image, size: 30),
                        ),
                        Positioned(
                          top: 3,
                          right: 3,
                          child: GestureDetector(
                            onTap: () => _removeAttachment(idx),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _attachments.length >= 5 ? null : _pickFiles,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Choose File (JPG/PNG/PDF)'),
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
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Step 2: Review Extracted Data & Save ──────────────────────────────

  Widget _buildStep2Review() {
    final regAogStr = _date == null || _originalEdd == null
        ? '--'
        : '${registeredAogWeeksOnScanDate.floor()}w ${(registeredAogDaysOnScanDate % 7)}d';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Discrepancy Banner & Redating Button (Top Priority) ──────
        if (hasSignificantDiscrepancy) ...[
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.shade400, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Gestational Age Discrepancy: $discrepancyDays Days',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Ultrasound EGA ($ultrasoundEgaTotalDays days) differs from registered LMP AOG on scan date ($registeredAogDaysOnScanDate days) by $discrepancyDays days. Updating official EDD ensures accurate growth & weight gain tracking.',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900, height: 1.35),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _redatePregnancyEdd,
                    icon: const Icon(Icons.sync, size: 16),
                    label: Text(_eddRedated ? '✓ Official EDD Re-dated' : 'Update Official Pregnancy EDD to Ultrasound'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _eddRedated ? Colors.green : Colors.amber.shade800,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Card 1: Basic Ultrasound Info ────────────────────────────
        _sectionCard(
          title: 'Ultrasound Information',
          child: Column(
            children: [
              AppInputField(
                hintText: 'Ultrasound Date *',
                controller: _dateCtrl,
                leadingIcon: Icons.calendar_today_outlined,
                readOnly: true,
                onTap: _pickDate,
                isRequired: true,
              ),
              const SizedBox(height: 12),
              AppInputField(
                hintText: 'Location / Facility (e.g. Austria Diagnostic Center)',
                controller: _locationCtrl,
                leadingIcon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 12),
              AppInputField(
                hintText: 'Healthcare Worker Name *',
                controller: _workerNameCtrl,
                leadingIcon: Icons.person_outline,
                isRequired: true,
                errorText: _workerNameError,
              ),
              const SizedBox(height: 12),
              AppInputField(
                hintText: 'Institution *',
                controller: _institutionCtrl,
                leadingIcon: Icons.business_outlined,
                isRequired: true,
                errorText: _institutionError,
              ),
            ],
          ),
        ),

        // ── Card 2: Gestational Age & Biometry ────────────────────────
        _sectionCard(
          title: 'Gestational Age & Fetal Biometry',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppInputField(
                      hintText: 'EGA (Weeks) *',
                      controller: _egaWeeksCtrl,
                      leadingIcon: Icons.access_time_outlined,
                      keyboardType: TextInputType.number,
                      isRequired: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppInputField(
                      hintText: 'EGA (Days)',
                      controller: _egaDaysCtrl,
                      leadingIcon: Icons.timer_outlined,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Registered AOG on Scan Date (${_date == null ? 'Select Date' : DateFormat('MMM d').format(_date!)}): ',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    Text(
                      regAogStr,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppDropdownField<int>(
                hintText: 'Fetus Count',
                leadingIcon: Icons.child_care_outlined,
                value: _fetalCount,
                options: const [1, 2, 3],
                displayStringForOption: (val) => val == 1 ? '1 (Singleton)' : val == 2 ? '2 (Twins)' : '3 (Triplets)',
                onSelected: (val) => setState(() => _fetalCount = val),
              ),
            ],
          ),
        ),

        // ── Card 3: Interpretation & Sonologist Remarks ───────────────
        _sectionCard(
          title: 'Interpretation & Sonologist Remarks',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _remarksCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'Sonologist findings or report summary (e.g. Single live intrauterine pregnancy 16 weeks AOG...)',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: AppColors.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
