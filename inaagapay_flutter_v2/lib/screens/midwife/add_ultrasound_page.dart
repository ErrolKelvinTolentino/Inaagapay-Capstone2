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
import '../../widgets/pregnancy_risk_override.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/headline.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/confirmation_dialog_box.dart';

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
    this.pregnancyId,
  });

  final int motherId;
  final int? pregnancyId;

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

  /// The pregnancy's risk level, as the midwife may revise it here.
  ///
  /// A scan is a reason to change it: an ultrasound that reads small for
  /// dates, or a finding she wants followed up, should not require reopening a
  /// prenatal checkup to record. Seeded from the pregnancy so the control
  /// shows the current level rather than defaulting to low.
  String _pregnancyRiskLevel = 'low';
  String _initialRiskLevel = 'low';
  String? _profession;
  int _fetalCount = 1;

  final List<UltrasoundAttachment> _attachments = [];

  bool _loading = true;
  bool _submitting = false;
  bool _processingDocument = false;
  bool _ocrExtracted = false;

  bool _eddRedated = false;
  DateTime? _originalEdd;

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
    _dateCtrl.dispose();
    _workerNameCtrl.dispose();
    _institutionCtrl.dispose();
    _locationCtrl.dispose();
    _egaWeeksCtrl.dispose();
    _egaDaysCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPregnancyAndUser() async {
    // ── Load current user profile (separate try-catch so it doesn't crash pregnancy lookup)
    try {
      final userId = await AuthStorage.getUserId();
      if (userId != null) {
        final profile = await Supabase.instance.client
            .from('accounts')
            .select('first_name, last_name, account_type')
            .eq('account_id', userId)
            .maybeSingle();

        if (profile != null) {
          // Deliberately NOT pre-filled from the signed-in account.
          //
          // These fields describe the person named ON THE DOCUMENT — the
          // sonologist who performed the scan, the laboratory that ran the
          // test. Seeding them with the logged-in midwife's name and
          // account_type meant a scan performed and signed by an OB-GYN was
          // filed with "Profession: midwife": the name field got corrected and
          // the profession quietly did not. The record then asserted, in
          // writing, that a midwife had performed an obstetric ultrasound.
          //
          // Blank is honest. OCR fills these from the document where it can,
          // and the midwife names the performer where it cannot. If she
          // performed it herself she enters herself — one field, on a
          // clinical record.
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AddUltrasound] User profile load error: $e');
    }

    // ── Load pregnancy data (separate try-catch)
    try {
      Map<String, dynamic>? response;

      // Tier 1: Query by explicit pregnancyId if passed
      if (widget.pregnancyId != null) {
        final res = await Supabase.instance.client
            .from('pregnancies')
            .select('pregnancy_id, last_menstrual_period, expected_date_of_delivery, fetal_count, status, pregnancy_risk_level')
            .eq('pregnancy_id', widget.pregnancyId!)
            .maybeSingle();
        if (res != null) {
          response = Map<String, dynamic>.from(res);
        }
      }

      // Tier 2: Query active pregnancy by mother_id
      if (response == null) {
        final List<dynamic> pregList = await Supabase.instance.client
            .from('pregnancies')
            .select('pregnancy_id, last_menstrual_period, expected_date_of_delivery, fetal_count, status, pregnancy_risk_level')
            .eq('mother_id', widget.motherId)
            .order('pregnancy_id', ascending: false);

        if (pregList.isNotEmpty) {
          response = (pregList.firstWhere(
            (p) {
              final st = p['status']?.toString().toLowerCase() ?? '';
              return st == 'active' || st == 'ongoing';
            },
            orElse: () => pregList.first,
          ) as Map).cast<String, dynamic>();
        }
      }

      // Tier 3: Resolve mother_id from account_id or auto-create active pregnancy fallback
      if (response == null) {
        final motherRecord = await Supabase.instance.client
            .from('mothers')
            .select('mother_id')
            .or('mother_id.eq.${widget.motherId},account_id.eq.${widget.motherId}')
            .maybeSingle();

        final int targetMotherId = motherRecord != null
            ? (int.tryParse(motherRecord['mother_id'].toString()) ?? widget.motherId)
            : widget.motherId;

        final List<dynamic> pregList2 = await Supabase.instance.client
            .from('pregnancies')
            .select('pregnancy_id, last_menstrual_period, expected_date_of_delivery, fetal_count, status, pregnancy_risk_level')
            .eq('mother_id', targetMotherId)
            .order('pregnancy_id', ascending: false);

        if (pregList2.isNotEmpty) {
          response = Map<String, dynamic>.from(pregList2.first);
        } else {
          final now = DateTime.now();
          final created = await Supabase.instance.client
              .from('pregnancies')
              .insert({
                'mother_id': targetMotherId,
                'status': 'active',
                'last_menstrual_period': DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 112))),
                'expected_date_of_delivery': DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 168))),
                'fetal_count': 1,
                'created_at': now.toIso8601String(),
              })
              .select('pregnancy_id, last_menstrual_period, expected_date_of_delivery, fetal_count, status, pregnancy_risk_level')
              .single();
          response = Map<String, dynamic>.from(created);
        }
      }

      _pregnancyId = int.tryParse(response['pregnancy_id']?.toString() ?? '');
      
      final lmpStr = response['last_menstrual_period']?.toString();
      final eddStr = response['expected_date_of_delivery']?.toString();

      _pregnancyLmp = lmpStr != null ? DateTime.tryParse(lmpStr) : null;
      _pregnancyEdd = eddStr != null ? DateTime.tryParse(eddStr) : null;

      // If EDD is missing but LMP exists, EDD = LMP + 280 days
      if (_pregnancyEdd == null && _pregnancyLmp != null) {
        _pregnancyEdd = _pregnancyLmp!.add(const Duration(days: 280));
      }

      _originalEdd = _pregnancyEdd;
      _fetalCount = int.tryParse(response['fetal_count']?.toString() ?? '') ?? 1;

      final level = response['pregnancy_risk_level']?.toString().toLowerCase();
      if (level == 'low' || level == 'high') {
        _pregnancyRiskLevel = level!;
        _initialRiskLevel = level;
      }

      if (kDebugMode) debugPrint('[AddUltrasound] Pregnancy loaded: id=$_pregnancyId');
    } catch (e) {
      if (kDebugMode) debugPrint('[AddUltrasound] Pregnancy load error: $e');
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

  // ── Full-Screen Image Preview Modal ──────────────────────────────────────

  void _showImagePreviewModal(UltrasoundAttachment item) {
    if (item.isPdf) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.95),
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.8,
              maxScale: 4.0,
              child: item.bytes != null
                  ? Image.memory(item.bytes!, fit: BoxFit.contain)
                  : (!kIsWeb && item.path != null && item.path!.isNotEmpty)
                      ? Image.file(File(item.path!), fit: BoxFit.contain)
                      : const Icon(Icons.broken_image, size: 64, color: Colors.white),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              bottom: 15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  item.name,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        withData: true,
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
        _triggerAutoOcr();
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
      _triggerAutoOcr();
    } catch (e) {
      _showMessage('Unable to capture photo: $e', type: AppSnackType.error);
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
        _egaWeeksCtrl.clear();
        _egaDaysCtrl.clear();
        _remarksCtrl.clear();
      }
    });
  }

  // ── Immediate Auto-OCR Extraction ─────────────────────────────────────

  Future<void> _triggerAutoOcr() async {
    if (_attachments.isEmpty) return;

    setState(() {
      _processingDocument = true;
      _ocrExtracted = false;
    });

    try {
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
              final rawDateStr = data['ultrasound_date'].toString().trim();
              DateTime? dt = DateTime.tryParse(rawDateStr);
              if (dt == null) {
                final monthMap = {
                  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
                  'apr': 4, 'april': 4, 'may': 5, 'june': 6, 'jun': 6, 'jul': 7, 'july': 7,
                  'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10, 'october': 10,
                  'nov': 11, 'november': 11, 'dec': 12, 'december': 12
                };
                final match = RegExp(r'([A-Za-z]+)\s+(\d{1,2})[\s,]+(\d{4})').firstMatch(rawDateStr);
                if (match != null) {
                  final mStr = match.group(1)!.toLowerCase();
                  final day = int.tryParse(match.group(2)!);
                  final year = int.tryParse(match.group(3)!);
                  if (monthMap.containsKey(mStr) && day != null && year != null) {
                    dt = DateTime(year, monthMap[mStr]!, day);
                  }
                }
              }
              if (dt != null) {
                _date = dt;
                _dateCtrl.text = DateFormat('MMM d, yyyy').format(dt);
              }
            }
            if (data['ega_weeks'] != null && data['ega_weeks'].toString().trim().isNotEmpty) {
              _egaWeeksCtrl.text = data['ega_weeks'].toString();
              _egaDaysCtrl.text = (data['ega_days'] ?? 0).toString();
            } else if (data['ega_days'] != null) {
              _egaDaysCtrl.text = data['ega_days'].toString();
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
            if (_isValidFieldValue(data['sonologist_name'])) {
              _workerNameCtrl.text = data['sonologist_name'].toString().trim();
            }
            if (_isValidFieldValue(data['sonologist_remarks'])) {
              _remarksCtrl.text = data['sonologist_remarks'].toString().trim();
            }
            if (data['fetal_count'] != null) {
              final fc = int.tryParse(data['fetal_count'].toString());
              if (fc != null && fc > 0) _fetalCount = fc;
            }
            _ocrExtracted = true;
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
        lower.startsWith('section') ||
        lower.startsWith('name:') ||
        lower.startsWith('location:') ||
        lower.startsWith('name and location:') ||
        lower.contains('top of the document') ||
        lower.contains('i see a logo') ||
        lower.contains('top header') ||
        lower.contains('header says') ||
        lower.contains('look for') ||
        lower.contains('the section under') ||
        str.endsWith(':') ||
        str.length < 3) {
      return false;
    }
    return true;
  }

  // ── Gestational Age & Discrepancy Logic ────────────────────────────────

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

  int get ultrasoundEgaTotalDays {
    final w = int.tryParse(_egaWeeksCtrl.text.trim()) ?? 0;
    final d = int.tryParse(_egaDaysCtrl.text.trim()) ?? 0;
    return w * 7 + d;
  }

  int get discrepancyDays {
    if (_date == null || ultrasoundEgaTotalDays <= 0 || _originalEdd == null) return 0;
    return (ultrasoundEgaTotalDays - registeredAogDaysOnScanDate).abs();
  }

  bool get hasSignificantDiscrepancy {
    if (_date == null || ultrasoundEgaTotalDays <= 0 || _originalEdd == null) return false;
    final isFirstTrimester = registeredAogWeeksOnScanDate <= 13.0;
    final threshold = isFirstTrimester ? 5 : 7;
    return discrepancyDays >= threshold;
  }

  bool get isEgaLowerThanAog {
    if (_date == null || ultrasoundEgaTotalDays <= 0 || _originalEdd == null) return false;
    return ultrasoundEgaTotalDays < registeredAogDaysOnScanDate;
  }

  void _redatePregnancyEdd() {
    if (_date == null || ultrasoundEgaTotalDays <= 0) return;

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
              surfaceTintColor: Colors.transparent,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandPrimary,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              headerBackgroundColor: Colors.white,
              headerForegroundColor: AppColors.brandText,
              headerHeadlineStyle: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.brandText,
              ),
              weekdayStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
              dayStyle: const TextStyle(fontWeight: FontWeight.w500),
              todayBorder: const BorderSide(color: AppColors.brandPrimary, width: 1.5),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return AppColors.brandText;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return AppColors.brandPrimary;
                return Colors.transparent;
              }),
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

  // ── Validation & Submission ─────────────────────────────────────────────

  bool _validateForm() {
    if (_attachments.isEmpty) {
      _showMessage('Please attach an ultrasound scan photo or PDF document first.');
      return false;
    }

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

  static String? _workingBucket;

  Future<List<String>> _uploadAttachments() async {
    final urls = <String>[];
    final candidateBuckets = ['files', 'ultrasounds', 'documents', 'public', 'attachments', 'media'];

    for (int i = 0; i < _attachments.length; i++) {
      final item = _attachments[i];
      final ext = item.isPdf ? 'pdf' : 'jpg';
      final fileName = 'ultrasound_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      final filePath = 'ultrasounds/${widget.motherId}/$fileName';

      Uint8List? bytes = item.bytes;
      if (bytes == null && !kIsWeb && item.path != null && item.path!.isNotEmpty) {
        try {
          bytes = await File(item.path!).readAsBytes();
        } catch (_) {}
      }
      if (bytes == null) continue;

      final mime = item.isPdf ? 'application/pdf' : 'image/jpeg';
      bool uploaded = false;

      // Fast-path: If storage buckets don't exist on Supabase, skip timeouts instantly
      if (_workingBucket != 'none') {
        final bucketsToTry = _workingBucket != null
            ? [_workingBucket!, ...candidateBuckets.where((b) => b != _workingBucket)]
            : candidateBuckets;

        for (final bucket in bucketsToTry) {
          try {
            await Supabase.instance.client.storage.from(bucket).uploadBinary(
              filePath,
              bytes,
              fileOptions: FileOptions(contentType: mime, upsert: true),
            ).timeout(const Duration(seconds: 60)); // was 500ms — see add_lab_test_page.dart
            final publicUrl = Supabase.instance.client.storage.from(bucket).getPublicUrl(filePath);
            urls.add(publicUrl);
            _workingBucket = bucket;
            uploaded = true;
            break;
          } catch (_) {}
        }
      }

      if (!uploaded) {
        _workingBucket = 'none';
        try {
          final base64Str = base64Encode(bytes);
          final dataUrl = 'data:$mime;base64,$base64Str';
          urls.add(dataUrl);
        } catch (_) {}
      }
    }
    return urls;
  }

  Future<String?> _showDiscrepancyWarningDialog() async {
    final isLower = isEgaLowerThanAog;
    final String subtitleText = isLower
        ? 'Ultrasound EGA (${(ultrasoundEgaTotalDays / 7).floor()}w ${ultrasoundEgaTotalDays % 7}d) is $discrepancyDays days LOWER than expected AOG (${(registeredAogDaysOnScanDate / 7).floor()}w ${registeredAogDaysOnScanDate % 7}d).\n\nWould you like to re-date the official pregnancy EDD to match the ultrasound, or keep the current EDD?'
        : 'Ultrasound EGA (${(ultrasoundEgaTotalDays / 7).floor()}w ${ultrasoundEgaTotalDays % 7}d) is $discrepancyDays days AHEAD of expected AOG (${(registeredAogDaysOnScanDate / 7).floor()}w ${registeredAogDaysOnScanDate % 7}d).\n\nWould you like to re-date the official pregnancy EDD to match the ultrasound, or keep the current EDD?';

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: isLower ? Colors.orange.shade800 : Colors.amber.shade800,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Gestational Age Discrepancy',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isLower ? Colors.orange.shade900 : Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          subtitleText,
          style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.brandText),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, 'ignore'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandText,
                    side: const BorderSide(color: AppColors.borderPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Ignore & Save', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, 'redate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLower ? Colors.orange.shade900 : Colors.amber.shade900,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text('Re-date EDD', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_validateForm()) return;
    if (_pregnancyId == null) {
      _showMessage('No ongoing pregnancy found for this mother.');
      return;
    }

    if (hasSignificantDiscrepancy && !_eddRedated) {
      final choice = await _showDiscrepancyWarningDialog();
      if (choice == null) return;
      if (choice == 'redate') {
        _redatePregnancyEdd();
      }
    }

    setState(() => _submitting = true);
    try {
      int? midwifeId;
      try {
        final accountId = await AuthStorage.getUserId();
        if (accountId != null) {
          final ctx = await SupabaseService.getMidwifeContext(accountId);
          midwifeId = int.tryParse(ctx['midwife_id']?.toString() ?? '');
        }
      } catch (_) {}

      final urls = await _uploadAttachments();

      // Create parent clinical encounter record first to get required encounter_id
      int? encounterId;
      try {
        final encRow = await Supabase.instance.client
            .from('clinical_encounters')
            .insert({
              'pregnancy_id': _pregnancyId,
              'mother_id': widget.motherId,
              if (midwifeId != null) 'recorded_by': midwifeId,
              'encounter_type': 'ultrasound',
              'encounter_datetime': _date?.toIso8601String() ?? DateTime.now().toIso8601String(),
              'midwife_notes': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
            })
            .select('encounter_id')
            .maybeSingle();
        if (encRow != null) {
          encounterId = int.tryParse(encRow['encounter_id']?.toString() ?? '');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[AddUltrasound] Clinical encounter insert note: $e');
      }

      // The midwife's risk call, written only when she actually changed it.
      //
      // Writing unconditionally would have this screen re-assert "low" on
      // every scan and quietly undo a level raised at a checkup an hour
      // earlier. A record screen may revise the pregnancy; it must not
      // overwrite it by default.
      if (_pregnancyRiskLevel != _initialRiskLevel && _pregnancyId != null) {
        try {
          await Supabase.instance.client
              .from('pregnancies')
              .update({'pregnancy_risk_level': _pregnancyRiskLevel})
              .eq('pregnancy_id', _pregnancyId!);
          _initialRiskLevel = _pregnancyRiskLevel;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[AddUltrasound] Risk level update note: $e');
          }
        }
      }

      final inserted = await Supabase.instance.client
          .from('ultrasounds')
          .insert({
            if (encounterId != null) 'encounter_id': encounterId,
            'pregnancy_id': _pregnancyId,
            'ultrasound_date': DateFormat('yyyy-MM-dd').format(_date!),
            'ultrasound_location': _locationCtrl.text.trim().isEmpty ? 'Clinic' : _locationCtrl.text.trim(),
            'ultrasound_image': urls.isEmpty ? null : urls.join(','),
            'findings_summary': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
            'health_worker_name': _workerNameCtrl.text.trim(),
            'health_worker_institution': _institutionCtrl.text.trim(),
            'health_worker_profession': _profession ?? 'Sonographer',
            'created_at': DateTime.now().toIso8601String(),
            // `recorded_by_midwife_id` was never a column on this table. The
            // parent clinical_encounters row above is the primary record of who
            // performed this; recorded_by here mirrors it for screens that read
            // the ultrasound directly.
            if (midwifeId != null) 'recorded_by': midwifeId,
          })
          .select()
          .single();

      final ultrasoundId = int.tryParse(inserted['encounter_id']?.toString() ?? inserted['ultrasound_id']?.toString() ?? '') ?? 0;

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

      final accountId = await AuthStorage.getUserId();
      if (accountId != null) {
        try {
          await Supabase.instance.client.from('audit_trail').insert({
            'action': 'ULTRASOUND_RECORDED',
            'table_name': 'ultrasounds',
            'account_id': accountId,
            'new_data': {
              'ultrasound_id': ultrasoundId,
              'pregnancy_id': _pregnancyId,
              'edd_redated': _eddRedated,
            },
            'description': 'Ultrasound recorded for pregnancy_id=$_pregnancyId by ${_workerNameCtrl.text.trim()}.',
          });
        } catch (_) {}
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

  // ── Discard Confirmation Logic ──────────────────────────────────────────

  bool get _hasUnsavedData {
    return _attachments.isNotEmpty ||
        _dateCtrl.text.isNotEmpty ||
        _locationCtrl.text.isNotEmpty ||
        _workerNameCtrl.text.isNotEmpty ||
        _institutionCtrl.text.isNotEmpty ||
        _egaWeeksCtrl.text.isNotEmpty ||
        _egaDaysCtrl.text.isNotEmpty ||
        _remarksCtrl.text.isNotEmpty;
  }

  Future<bool> _showDiscardConfirmationDialog() async {
    if (!_hasUnsavedData) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Discard ultrasound record?',
        subtitle: 'You have unsaved ultrasound document and record details. Are you sure you want to discard these changes?',
        cancelText: 'Cancel',
        confirmText: 'Discard',
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
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

  // ── UI BUILDERS ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final regAogStr = _date == null || _originalEdd == null
        ? '--'
        : '${registeredAogWeeksOnScanDate.floor()}w ${(registeredAogDaysOnScanDate % 7)}d';

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
                title: 'Record Ultrasound',
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

                    // ── Card 2: Ultrasound Information ────────────────────
                    _sectionCard(
                      title: 'Ultrasound Information',
                      child: Column(
                        children: [
                          AppInputField(
                            hintText: 'Ultrasound Date',
                            controller: _dateCtrl,
                            leadingIcon: Icons.calendar_today_outlined,
                            readOnly: true,
                            onTap: _pickDate,
                            isRequired: true,
                          ),
                          const SizedBox(height: 12),
                          AppInputField(
                            hintText: 'Location / Facility',
                            controller: _locationCtrl,
                            leadingIcon: Icons.location_on_outlined,
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
                          AppInputField(
                            hintText: 'Institution',
                            controller: _institutionCtrl,
                            leadingIcon: Icons.business_outlined,
                            isRequired: true,
                            errorText: _institutionError,
                          ),
                        ],
                      ),
                    ),

                    // ── Card 3: Gestational Age & Fetal Biometry ────────────
                    _sectionCard(
                      title: 'Gestational Age & Fetal Biometry',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AppInputField(
                                  hintText: 'EGA (Weeks)',
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
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                ),
                                Text(
                                  regAogStr,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.brandPrimary),
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

                    // ── Card 4: Interpretation & Sonologist Remarks ───────────
                    _sectionCard(
                      title: 'Sonologist Findings & Remarks',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _remarksCtrl,
                            maxLines: 5,
                            maxLength: 1000,
                            style: const TextStyle(fontSize: 13, height: 1.5),
                            decoration: InputDecoration(
                              hintText: 'Sonologist remarks or impression summary (editable)...',
                              hintStyle: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
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
                    // Same control, same wording as the prenatal checkup — a
                    // scan is as good a reason to revise the level as anything
                    // found at a visit, and she should not have to reopen a
                    // checkup to record it.
                    _sectionCard(
                      title: 'Pregnancy Risk Assessment',
                      child: PregnancyRiskOverride(
                        value: _pregnancyRiskLevel,
                        onChanged: (level) =>
                            setState(() => _pregnancyRiskLevel = level),
                        helperText:
                            'Applies to the whole pregnancy. Left unchanged, '
                            'the level set at the last checkup stands.',
                      ),
                    ),
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
                  : const Text('Save Ultrasound Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
          const Headline(
            text: 'Attach Ultrasound Document',
            fontSize: 17,
          ),
          const SizedBox(height: 4),
          Text(
            'Upload ultrasound scan photos (JPG, PNG) or diagnostic PDF reports. Maximum 10 MB per file.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
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
                    'Attach Ultrasound Picture or PDF',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Supports JPG, PNG, PDF (Up to 10 MB)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
                        Flexible(
                          child: Text('Scanning document for OCR fields...', style: TextStyle(fontSize: 12, color: AppColors.brandPrimary, fontWeight: FontWeight.bold)),
                        ),
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
                        Flexible(
                          child: Text('✓ Review contents below', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],

                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _attachments.length >= 5 ? null : _pickFiles,
                        icon: Icon(_attachments.isEmpty ? Icons.attach_file : Icons.add, size: 18),
                        label: Text(_attachments.isEmpty ? 'Choose File (JPG/PNG/PDF)' : 'Add File'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _attachments.length >= 5 ? null : _capturePhoto,
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('Take Photo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brandPrimary,
                          side: BorderSide(color: AppColors.brandPrimary.withValues(alpha: 0.4), width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
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
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
