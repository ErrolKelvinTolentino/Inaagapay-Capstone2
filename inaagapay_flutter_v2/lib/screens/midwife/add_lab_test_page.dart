import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/blood_type.dart';
import '../../services/auth_storage.dart';
import '../../services/gestational_diabetes_screening.dart';
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

  /// The pregnancy's risk level, revisable from here.
  ///
  /// An anaemic blood count or a glucose result the midwife wants followed up
  /// is as much a reason to raise the level as anything found at a visit.
  String _pregnancyRiskLevel = 'low';
  String _initialRiskLevel = 'low';
  String? _profession;
  String _selectedLabType = 'Complete Blood Count (CBC)';

  final List<LabTestAttachment> _attachments = [];

  bool _loading = true;
  bool _submitting = false;
  bool _processingDocument = false;
  bool _ocrExtracted = false;

  String? _workerNameError;
  String? _institutionError;

  /// What the mother's record already says, read once when the page opens.
  String? _bloodTypeOnFile;

  /// What the attached report says, once OCR has read it.
  String? _bloodTypeFromReport;

  /// What will be saved. Starts as whatever is on file, so an OCR reading never
  /// replaces a recorded blood type on its own — the midwife has to choose it.
  String? _selectedBloodType;

  /// Glucose samples, when the attached report is a sugar test.
  ///
  /// Held as controllers rather than numbers so an OCR reading and a typed
  /// correction go through the same field — the midwife confirms every value
  /// by submitting the form, exactly as with the blood type above.
  final TextEditingController _fastingGlucoseCtrl = TextEditingController();
  final TextEditingController _glucose1hrCtrl = TextEditingController();
  final TextEditingController _glucose2hrCtrl = TextEditingController();
  final TextEditingController _glucose3hrCtrl = TextEditingController();

  // CBC, urinalysis and hepatitis B. Columns for all of these have existed on
  // lab_tests since the schema was drawn; nothing ever wrote them, so the
  // values were read off the document, rendered into a sentence of prose and
  // then discarded.
  final TextEditingController _hemoglobinCtrl = TextEditingController();
  final TextEditingController _hematocritCtrl = TextEditingController();
  final TextEditingController _wbcCtrl = TextEditingController();
  final TextEditingController _plateletCtrl = TextEditingController();
  final TextEditingController _urineGlucoseCtrl = TextEditingController();
  String? _urineProtein;
  String? _hepatitisBStatus;

  /// True once OCR has read at least one glucose value off the report.
  bool _glucoseFromReport = false;

  /// Whether the blood type field is worth showing.
  ///
  /// Mirrors [_isGlucoseTest]: the field appears when the report actually
  /// carries a blood type, or when the selected test is one that produces
  /// them. An OGTT has no business displaying a blood type field.
  ///
  /// It deliberately does not appear on extraction alone. A midwife holding a
  /// blood typing result the OCR could not read still needs somewhere to put
  /// it, and a field that only ever materialises on a successful scan teaches
  /// her the app cannot be told directly.
  bool get _isBloodTypeTest {
    final type = (_selectedLabType == 'Other'
            ? _customLabTypeCtrl.text
            : _selectedLabType)
        .toLowerCase();
    return _bloodTypeFromReport != null ||
        type.contains('blood typ') ||
        type.contains('abo') ||
        type.contains('blood group');
  }

  /// Whether the glucose section is worth showing.
  ///
  /// A CBC has no business displaying four empty sugar fields, but a midwife
  /// holding a printed OGTT the OCR could not read still needs somewhere to
  /// type it — so the section follows the selected test type as well as the
  /// extraction.
  bool get _isGlucoseTest {
    final type = (_selectedLabType == 'Other'
            ? _customLabTypeCtrl.text
            : _selectedLabType)
        .toLowerCase();
    return _glucoseFromReport ||
        type.contains('glucose') ||
        type.contains('ogtt') ||
        type.contains('sugar') ||
        type.contains('fbs');
  }

  String get _typeForGating => (_selectedLabType == 'Other'
          ? _customLabTypeCtrl.text
          : _selectedLabType)
      .toLowerCase();

  /// Same rule as [_isGlucoseTest]: the section follows the selected type as
  /// well as the extraction, so a midwife holding a printed report the OCR
  /// could not read still has somewhere to type it.
  bool get _isCbcTest =>
      _cbcFromReport ||
      _typeForGating.contains('blood count') ||
      _typeForGating.contains('cbc');

  bool get _isUrinalysisTest =>
      _urinalysisFromReport ||
      _typeForGating.contains('urinalysis') ||
      _typeForGating.contains('urine');

  bool get _isHepatitisTest =>
      _hepatitisFromReport ||
      _typeForGating.contains('hepatitis') ||
      _typeForGating.contains('hbsag');

  bool _cbcFromReport = false;
  bool _urinalysisFromReport = false;
  bool _hepatitisFromReport = false;

  /// The urinalysis protein scale the database will accept.
  ///
  /// `urinalysis_protein` carries a CHECK constraint listing exactly these
  /// values. Anything else — "Negative" capitalised, "nil", "absent", a bare
  /// number — is rejected by Postgres, and because this write shares a
  /// statement with the lab test itself, one stray token would lose the whole
  /// record. So the value is validated here rather than hoped for.
  static const List<String> urineProteinScale = [
    'negative',
    'trace',
    '1+',
    '2+',
    '3+',
    '4+',
  ];

  static String? normaliseUrineProtein(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return urineProteinScale.contains(value) ? value : null;
  }

  /// Writes an extracted value into a field only when the document produced
  /// one, so a null never overwrites something the midwife has already typed.
  void _fillIfPresent(TextEditingController ctrl, Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') return;
    ctrl.text = text;
  }

  GlucoseValues get _enteredGlucose => GlucoseValues(
        fasting: double.tryParse(_fastingGlucoseCtrl.text.trim()),
        oneHour: double.tryParse(_glucose1hrCtrl.text.trim()),
        twoHour: double.tryParse(_glucose2hrCtrl.text.trim()),
        threeHour: double.tryParse(_glucose3hrCtrl.text.trim()),
      );

  /// True when the report and the record disagree and neither is blank.
  ///
  /// Usually an OCR misread or someone else's document attached to the wrong
  /// mother. Either way it is a question for a person: silently rewriting a
  /// blood type is how the wrong blood gets ordered later.
  bool get _bloodTypeConflicts =>
      _bloodTypeOnFile != null &&
      _bloodTypeFromReport != null &&
      _bloodTypeOnFile != _bloodTypeFromReport;

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
    _fastingGlucoseCtrl.dispose();
    _glucose1hrCtrl.dispose();
    _glucose2hrCtrl.dispose();
    _glucose3hrCtrl.dispose();
    _hemoglobinCtrl.dispose();
    _hematocritCtrl.dispose();
    _wbcCtrl.dispose();
    _plateletCtrl.dispose();
    _urineGlucoseCtrl.dispose();
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
          // Deliberately NOT pre-filled from the signed-in account.
          //
          // These fields describe whoever is named ON THE DOCUMENT — the
          // laboratory or technologist that ran the test. Seeding them from
          // the logged-in midwife meant a test run at Redcliffe Labs was
          // filed with the midwife's name and "Profession: midwife", because
          // OCR corrected the name field and left the profession alone.
          //
          // Blank is honest. OCR fills these from the document where it can,
          // and the midwife names the performer where it cannot.
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AddLabTest] User profile load error: $e');
    }

    // Read before OCR runs, so a reading from the report can be compared
    // against what is already recorded rather than just landing on top of it.
    try {
      final mother = await Supabase.instance.client
          .from('mothers')
          .select('blood_type')
          .eq('mother_id', widget.motherId)
          .maybeSingle();

      _bloodTypeOnFile = BloodType.parse(mother?['blood_type']?.toString());
      _selectedBloodType = _bloodTypeOnFile;
    } catch (e) {
      if (kDebugMode) debugPrint('[AddLabTest] Blood type load note: $e');
    }

    try {
      if (widget.pregnancyId != null) {
        _pregnancyId = widget.pregnancyId;
      } else {
        final response = await Supabase.instance.client
            .from('pregnancies')
            .select('pregnancy_id, status, pregnancy_risk_level')
            .eq('mother_id', widget.motherId)
            .eq('status', 'ongoing')
            .maybeSingle();

        if (response != null) {
          _pregnancyId = response['pregnancy_id'] as int?;
          final level =
              response['pregnancy_risk_level']?.toString().toLowerCase();
          if (level == 'low' || level == 'high') {
            _pregnancyRiskLevel = level!;
            _initialRiskLevel = level;
          }
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
            if (data['is_lab_test'] == false) {
              _showMessage(
                'Attached document appears to be an ultrasound or non-lab report. Please attach a laboratory report or enter details manually.',
                type: AppSnackType.warning,
              );
              setState(() {
                _ocrExtracted = false;
                _dateCtrl.clear();
                _date = null;
                _locationCtrl.clear();
                _institutionCtrl.clear();
                _remarksCtrl.clear();
                _customLabTypeCtrl.clear();
                _selectedLabType = 'Complete Blood Count (CBC)';
                // Anything read off a document that turned out not to be a lab
                // report is void. Fall back to the recorded value.
                _bloodTypeFromReport = null;
                _selectedBloodType = _bloodTypeOnFile;
              });
            } else {
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

                // Blood type is offered, never applied. It fills the field
                // only when the record has none; where the record already has
                // one, the stored value stands and the disagreement is shown
                // instead. Submitting the form is the midwife's confirmation.
                final readFromReport =
                    BloodType.parse(data['blood_type']?.toString());
                _bloodTypeFromReport = readFromReport;
                if (readFromReport != null && _bloodTypeOnFile == null) {
                  _selectedBloodType = readFromReport;
                }

                // Glucose samples. Filled in for review, never saved silently —
                // the midwife submits the form to confirm them.
                _glucoseFromReport = _fillGlucoseField(
                      _fastingGlucoseCtrl,
                      data['glucose_fasting_mg_dl'],
                    ) |
                    _fillGlucoseField(
                      _glucose1hrCtrl,
                      data['glucose_1hr_mg_dl'],
                    ) |
                    _fillGlucoseField(
                      _glucose2hrCtrl,
                      data['glucose_2hr_mg_dl'],
                    ) |
                    _fillGlucoseField(
                      _glucose3hrCtrl,
                      data['glucose_3hr_mg_dl'],
                    );

                // CBC / urinalysis / hepatitis, filled the same way the
                // glucose samples are: the extraction proposes, the midwife
                // reviews on screen, and only what is in the fields at save
                // time is written. Nothing here goes to the database unseen.
                _fillIfPresent(_hemoglobinCtrl, data['hemoglobin_g_dl']);
                _fillIfPresent(_hematocritCtrl, data['hematocrit_pct']);
                _fillIfPresent(_wbcCtrl, data['wbc_count']);
                _fillIfPresent(_plateletCtrl, data['platelet_count']);
                _fillIfPresent(_urineGlucoseCtrl, data['urinalysis_glucose']);

                final protein = normaliseUrineProtein(data['urinalysis_protein']);
                if (protein != null) _urineProtein = protein;

                final hbsag = data['hepatitis_b_status']?.toString().trim();
                if (hbsag != null && hbsag.isNotEmpty && hbsag.toLowerCase() != 'null') {
                  _hepatitisBStatus = hbsag;
                }

                _cbcFromReport = _hemoglobinCtrl.text.isNotEmpty ||
                    _hematocritCtrl.text.isNotEmpty ||
                    _wbcCtrl.text.isNotEmpty ||
                    _plateletCtrl.text.isNotEmpty;
                _urinalysisFromReport =
                    _urineProtein != null || _urineGlucoseCtrl.text.isNotEmpty;
                _hepatitisFromReport = _hepatitisBStatus != null;

                _ocrExtracted = true;
              });
            }
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
        lower.startsWith('`:') ||
        lower.startsWith('`') ||
        lower.startsWith(':') ||
        lower.contains('this is an ultrasound') ||
        lower.contains('ultrasound report') ||
        lower.contains('radiology') ||
        lower.contains('test reports') ||
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
          // Long enough for the upload to actually happen.
          //
          // This was 500ms. A lab slip photographed on a phone is two to three
          // megabytes, which cannot leave a barangay connection in half a
          // second, so the upload threw on essentially every save and the code
          // fell through to base64Encode — embedding the whole image in the
          // row. That is where the 36MB-per-mother payload came from, and why
          // the images could not be displayed: they were data URIs being
          // handed to Image.network.
          //
          // Storage is the right place for a 3MB scan. Sixty seconds is
          // generous rather than optimistic, and the fallback still exists for
          // the case it is meant for — storage genuinely being unreachable.
          ).timeout(const Duration(seconds: 60));

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

      // Glucose samples, only the ones actually entered. Absent keys leave the
      // columns NULL rather than writing a zero, which would read as a real
      // measurement of nothing.
      final glucose = _enteredGlucose;
      if (glucose.fasting != null) {
        labTestData['fasting_glucose_mg_dl'] = glucose.fasting;
      }
      if (glucose.oneHour != null) {
        labTestData['glucose_1hr_mg_dl'] = glucose.oneHour;
      }
      if (glucose.twoHour != null) {
        labTestData['glucose_2hr_mg_dl'] = glucose.twoHour;
      }
      if (glucose.threeHour != null) {
        labTestData['glucose_3hr_mg_dl'] = glucose.threeHour;
      }

      // CBC, urinalysis and hepatitis B, from the reviewed fields.
      //
      // Absent keys leave the columns NULL rather than writing zeros or empty
      // strings, on the same principle as the glucose samples: a measurement
      // of nothing is not a measurement.
      void putNum(String column, TextEditingController ctrl) {
        final value = num.tryParse(ctrl.text.trim());
        if (value != null) labTestData[column] = value;
      }

      putNum('hemoglobin_g_dl', _hemoglobinCtrl);
      putNum('hematocrit_pct', _hematocritCtrl);
      putNum('wbc_count', _wbcCtrl);
      putNum('platelet_count', _plateletCtrl);

      // Validated against the CHECK constraint before it is sent. A value
      // outside the scale is dropped rather than allowed to fail the insert
      // and take the whole lab record with it.
      final protein = normaliseUrineProtein(_urineProtein);
      if (protein != null) labTestData['urinalysis_protein'] = protein;

      if (_urineGlucoseCtrl.text.trim().isNotEmpty) {
        labTestData['urinalysis_glucose'] = _urineGlucoseCtrl.text.trim();
      }
      if ((_hepatitisBStatus ?? '').trim().isNotEmpty) {
        labTestData['hepatitis_b_status'] = _hepatitisBStatus!.trim();
      }

      // Written only when she actually changed it, so a lab entry never
      // re-asserts "low" over a level raised elsewhere.
      if (_pregnancyRiskLevel != _initialRiskLevel && _pregnancyId != null) {
        try {
          await Supabase.instance.client
              .from('pregnancies')
              .update({'pregnancy_risk_level': _pregnancyRiskLevel})
              .eq('pregnancy_id', _pregnancyId!);
          _initialRiskLevel = _pregnancyRiskLevel;
        } catch (e) {
          if (kDebugMode) debugPrint('[AddLabTest] Risk level update note: $e');
        }
      }

      await Supabase.instance.client.from('lab_tests').insert(labTestData);

      // 3. Blood type, only when the midwife's selection differs from what is
      // stored. Written after the lab test itself so the record that justifies
      // the value is already saved and can be produced if anyone asks where the
      // blood type came from. A failure here must not lose the lab result, so
      // it reports rather than throwing.
      final bool bloodTypeChanged = BloodType.isValid(_selectedBloodType) &&
          _selectedBloodType != _bloodTypeOnFile;
      bool bloodTypeSaved = false;

      if (bloodTypeChanged) {
        try {
          await Supabase.instance.client
              .from('mothers')
              .update({'blood_type': _selectedBloodType})
              .eq('mother_id', widget.motherId);
          bloodTypeSaved = true;
        } catch (e) {
          if (kDebugMode) debugPrint('[AddLabTest] Blood type update failed: $e');
        }
      }

      if (mounted) {
        AppSnackbar.show(
          context,
          bloodTypeChanged && bloodTypeSaved
              ? 'Lab test saved. Blood type recorded as $_selectedBloodType.'
              : (bloodTypeChanged
                  ? 'Lab test saved, but the blood type could not be updated. '
                      'Please set it on the mother\'s profile.'
                  : 'Lab test record saved successfully'),
          type: bloodTypeChanged && !bloodTypeSaved
              ? AppSnackType.warning
              : AppSnackType.success,
        );
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

  /// Writes an OCR-read glucose value into its field, rejecting anything
  /// outside the range a plasma glucose can plausibly take.
  ///
  /// The bound matters more than it looks: a report in mmol/L reads about 5.1
  /// where mg/dL reads 92, and a stray "5.1" entered as mg/dL would sail under
  /// every threshold and report a reassuring result. The prompt already
  /// instructs the model to return null for mmol/L reports; this is the guard
  /// for when it does not.
  bool _fillGlucoseField(TextEditingController controller, Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (value == null || value < 20 || value > 600) return false;

    controller.text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return true;
  }

  /// Blood type, shown whether or not the report mentioned one.
  ///
  /// Always visible on purpose: a midwife holding a paper result the OCR could
  /// not read still needs somewhere to put it, and a field that appears only on
  /// a successful extraction teaches her the app cannot be told directly.
  ///
  /// There is no way to clear a stored blood type from here. Correcting one is
  /// picking the right value; emptying it is not something a lab report can
  /// justify.
  Widget _buildBloodTypeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bloodtype_outlined,
                size: 16, color: AppColors.brandPrimary),
            const SizedBox(width: 6),
            const Text(
              'Blood type',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _bloodTypeOnFile == null ? '(not yet on record)' : '(on record)',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppDropdownField<String>(
          hintText: 'Select if shown on the report',
          leadingIcon: Icons.bloodtype_outlined,
          value: _selectedBloodType,
          options: BloodType.values,
          displayStringForOption: (val) => val,
          onSelected: (val) => setState(() => _selectedBloodType = val),
        ),
        if (_bloodTypeConflicts) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This report reads $_bloodTypeFromReport, but the record '
                        'says $_bloodTypeOnFile.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Keeping $_bloodTypeOnFile unless you change it above. '
                        'Check that this report belongs to this mother before '
                        'overwriting.',
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else if (_bloodTypeFromReport != null &&
            _bloodTypeFromReport == _selectedBloodType) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 13, color: AppColors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _bloodTypeOnFile == null
                      ? 'Read from the report. Saving this form records it on '
                          'the mother\'s profile.'
                      : 'The report agrees with what is already on record.',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The glucose samples, with the screening reading beneath them.
  ///
  /// The reading names which samples reached threshold and what to do next. It
  /// does not name a condition: gestational diabetes is diagnosed by a
  /// physician, and a midwife's job here is to screen and refer.
  Widget _buildGlucoseFields() {
    final values = _enteredGlucose;
    final assessment = values.isEmpty
        ? null
        : GestationalDiabetesScreening.assess(values: values);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.water_drop_outlined,
                size: 16, color: AppColors.brandPrimary),
            const SizedBox(width: 6),
            const Text(
              'Blood sugar values (mg/dL)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Leave a box empty if that sample is not on the report.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _glucoseInput(_fastingGlucoseCtrl, 'Fasting')),
            const SizedBox(width: 10),
            Expanded(child: _glucoseInput(_glucose1hrCtrl, '1 hour')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _glucoseInput(_glucose2hrCtrl, '2 hours')),
            const SizedBox(width: 10),
            Expanded(child: _glucoseInput(_glucose3hrCtrl, '3 hours')),
          ],
        ),
        if (assessment != null &&
            assessment.result != GdmResult.noResult) ...[
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final meets = assessment.result == GdmResult.meetsThreshold;
            final incomplete = assessment.result == GdmResult.incomplete;
            final tone = meets
                ? AppColors.error
                : (incomplete ? AppColors.warning : AppColors.success);

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tone.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        meets
                            ? Icons.warning_amber_rounded
                            : Icons.insights_outlined,
                        size: 16,
                        color: tone,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          assessment.finding,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (assessment.action != GdmAction.none) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        assessment.action.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: tone,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          const Text(
            kGdmSourceShort,
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _labResultHeading(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.brandText,
          ),
        ),
      );

  static const String _blankFieldHint =
      'Leave a box empty if that value is not on the report.';

  Widget _buildCbcFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labResultHeading('Blood Count'),
        const Text(_blankFieldHint,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _glucoseInput(_hemoglobinCtrl, 'Haemoglobin g/dL')),
            const SizedBox(width: 10),
            Expanded(child: _glucoseInput(_hematocritCtrl, 'Haematocrit %')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _countInput(_wbcCtrl, 'White blood cells')),
            const SizedBox(width: 10),
            Expanded(child: _countInput(_plateletCtrl, 'Platelets')),
          ],
        ),
      ],
    );
  }

  Widget _buildUrinalysisFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labResultHeading('Urinalysis'),
        const Text(_blankFieldHint,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        // A dropdown, not free text: the column accepts exactly this scale and
        // rejects anything else, so the form offers only what can be saved.
        AppDropdownField<String>(
          hintText: 'Protein',
          value: _urineProtein,
          options: urineProteinScale,
          displayStringForOption: (v) => v,
          onSelected: (v) => setState(() => _urineProtein = v),
        ),
        const SizedBox(height: 10),
        AppInputField(
          controller: _urineGlucoseCtrl,
          hintText: 'Glucose (as printed)',
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildHepatitisFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labResultHeading('Hepatitis B'),
        const SizedBox(height: 6),
        AppDropdownField<String>(
          hintText: 'HBsAg',
          value: _hepatitisBStatus,
          options: const ['Reactive', 'Non-reactive'],
          displayStringForOption: (v) => v,
          onSelected: (v) => setState(() => _hepatitisBStatus = v),
        ),
      ],
    );
  }

  Widget _countInput(TextEditingController controller, String label) {
    return AppInputField(
      controller: controller,
      hintText: label,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?$')),
      ],
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _glucoseInput(TextEditingController controller, String label) {
    return AppInputField(
      controller: controller,
      hintText: label,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,1})?$')),
      ],
      onChanged: (_) => setState(() {}),
    );
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
                              hintText: 'Location / Facility',
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
                            if (_isBloodTypeTest) ...[
                              const SizedBox(height: 16),
                              _buildBloodTypeField(),
                            ],
                            if (_isGlucoseTest) ...[
                              const SizedBox(height: 20),
                              _buildGlucoseFields(),
                            ],
                            if (_isCbcTest) ...[
                              const SizedBox(height: 20),
                              _buildCbcFields(),
                            ],
                            if (_isUrinalysisTest) ...[
                              const SizedBox(height: 20),
                              _buildUrinalysisFields(),
                            ],
                            if (_isHepatitisTest) ...[
                              const SizedBox(height: 20),
                              _buildHepatitisFields(),
                            ],
                            const SizedBox(height: 20),
                            // Same control as the prenatal checkup and the
                            // ultrasound screen — see
                            // widgets/pregnancy_risk_override.dart.
                            _labResultHeading('Pregnancy Risk Assessment'),
                            const SizedBox(height: 8),
                            PregnancyRiskOverride(
                              value: _pregnancyRiskLevel,
                              onChanged: (level) =>
                                  setState(() => _pregnancyRiskLevel = level),
                              helperText:
                                  'Applies to the whole pregnancy. Left '
                                  'unchanged, the level set at the last '
                                  'checkup stands.',
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
          const Headline(
            text: 'Attach Lab Test Document',
            fontSize: 17,
          ),
          const SizedBox(height: 4),
          Text(
            'Upload lab result photos (JPG, PNG) or diagnostic PDF reports. Maximum 10 MB per file.',
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
                    'Attach Lab Test Picture or PDF',
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
}
