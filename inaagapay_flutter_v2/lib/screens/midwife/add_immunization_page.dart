import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/branded_date_picker.dart';
import '../../widgets/main_button.dart';
import '../../widgets/dialog_box.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../services/groq_service.dart';
import '../../services/immunization_schedule.dart';
import '../../services/sms_service.dart';
import '../../services/notification_service.dart';
import 'add_immunization_choice.dart';
import 'immunization_ocr_review_page.dart';
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';

class AddImmunizationPage extends StatefulWidget {
  final int childId;

  /// Whether this dose was given here or transcribed from elsewhere. Chosen on
  /// [AddImmunizationChoicePage] before this form opens, because it decides who
  /// is recorded as administering the dose and — once wired — whether stock
  /// moves. Defaults to `thisBhc` so the OCR entry point keeps working while it
  /// is migrated.
  final ImmunizationSource source;

  const AddImmunizationPage({
    super.key,
    required this.childId,
    this.source = ImmunizationSource.thisBhc,
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
  late String _administrationPlace; // 'local_facility' or 'external_facility'
  bool _isLoading = false;
  List<Map<String, dynamic>> _vaccines = [];
  bool _vaccinesLoading = true;
  Set<int> _takenVaccineIds = {};
  String? _errorMessage;
  DateTime? _childBirthdate;
  final GroqService _groqService = GroqService();
  bool _anyRecordAdded = false;

  int? _bhcStockCount;
  bool _bhcStockLoading = false;
  int? _midwifeBhcId;

  // ── Outside-record fields ──────────────────────────────────────────────────
  // Only collected when source == outside.
  final TextEditingController _facilityController = TextEditingController();

  /// How the outside dose was verified. A stamped card and a parent's
  /// recollection are not equal evidence, and coverage figures built on the
  /// latter should not look identical to the former.
  String _evidence = 'immunization_card';

  static const Map<String, String> _evidenceLabels = {
    'immunization_card': 'Immunization card shown',
    'facility_record': 'Record from the facility',
    'parent_recall': 'Parent recalls it',
  };

  bool get _isOutside => widget.source == ImmunizationSource.outside;

  /// Whether the vaccine picker is expanded. Mirrors the Add Mother form's
  /// select fields, which open in place rather than over the form.
  bool _vaccineDropdownOpen = false;

  /// Whether the rare groups — scheduled later, no longer given, already given
  /// — are expanded. Collapsed by default so the actionable doses stay visible.
  bool _showAllVaccines = false;

  @override
  void initState() {
    super.initState();
    _administrationPlace = widget.source == ImmunizationSource.outside
        ? 'external_facility'
        : 'local_facility';
    _loadData();
  }

  @override
  void dispose() {
    _vaccineController.dispose();
    _dateController.dispose();
    _remarksController.dispose();
    _facilityController.dispose();
    super.dispose();
  }

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
      final bool? recorded = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ImmunizationOcrReviewPage(
            childId: widget.childId,
            extractedVaccines: extractedData,
            allVaccines: _vaccines,
            takenVaccineIds: _takenVaccineIds,
            childBirthdate: _childBirthdate,
            // A scanned card is a history, not a record of what we just gave.
            // Carrying the chosen path through keeps a card scanned under
            // "Given elsewhere" from being attributed to this centre.
            source: widget.source,
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

  Future<void> _loadData() async {
    setState(() {
      _vaccinesLoading = true;
      _errorMessage = null;
    });

    await Future.wait([
      _loadVaccines(),
      _loadTakenVaccines(),
      _loadChildBirthdate(),
      _loadMidwifeBhcId(),
    ]);

    setState(() => _vaccinesLoading = false);

    if (_selectedVaccineId == null && _vaccines.isNotEmpty) {
      final available = _getAvailableVaccines();
      final untaken = available.where((v) => !_takenVaccineIds.contains(v['vaccine_id'] as int)).toList();
      final target = untaken.isNotEmpty ? untaken.first : available.first;

      final vId = target['vaccine_id'] as int;
      final label = _vaccineLabel(target);

      setState(() {
        _selectedVaccineId = vId;
        _vaccineController.text = label;
      });
      _checkBhcStock(vId);
    } else if (_selectedVaccineId != null) {
      _checkBhcStock(_selectedVaccineId!);
    }

    debugPrint('Vaccines loaded: ${_vaccines.length}');
    debugPrint('Taken vaccines: ${_takenVaccineIds.length}');
    debugPrint('Available vaccines: ${_getAvailableVaccines().length}');
    debugPrint('Child birthdate: $_childBirthdate');
  }

  Future<void> _loadMidwifeBhcId() async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId != null) {
        final ctx = await SupabaseService.getMidwifeContext(accountId);
        _midwifeBhcId = ctx['assigned_bhc_id'] as int?;
      }
    } catch (e) {
      debugPrint('Error loading midwife BHC ID: $e');
    }
  }

  Future<void> _checkBhcStock(int vaccineId) async {
    if (mounted) {
      setState(() {
        _bhcStockLoading = true;
      });
    }

    try {
      if (_midwifeBhcId == null) {
        await _loadMidwifeBhcId();
      }

      if (_midwifeBhcId == null) {
        if (mounted) {
          setState(() {
            _bhcStockCount = 0;
            _bhcStockLoading = false;
          });
        }
        return;
      }

      final vRes = await Supabase.instance.client
          .from('vaccines')
          .select('vaccine_name, inventory_item_id')
          .eq('vaccine_id', vaccineId)
          .maybeSingle();

      if (vRes == null) {
        if (mounted) {
          setState(() {
            _bhcStockCount = 0;
            _bhcStockLoading = false;
          });
        }
        return;
      }

      int? itemId = vRes['inventory_item_id'] as int?;
      final vName = (vRes['vaccine_name'] as String? ?? '').toLowerCase();

      if (itemId == null) {
        final iRes = await Supabase.instance.client
            .from('inventory_items')
            .select('item_id, name');
        for (final row in (iRes as List<dynamic>)) {
          final iName = (row['name'] as String? ?? '').toLowerCase();
          if ((vName.contains('bcg') && iName.contains('bcg')) ||
              (vName.contains('penta') && iName.contains('penta')) ||
              (vName.contains('pcv') && iName.contains('pcv')) ||
              (vName.contains('opv') && iName.contains('opv')) ||
              (vName.contains('ipv') && iName.contains('ipv')) ||
              (vName.contains('measles') && (iName.contains('mr') || iName.contains('measles'))) ||
              (vName.contains('mmr') && (iName.contains('mr') || iName.contains('mmr'))) ||
              (vName.contains('hep') && iName.contains('hep')) ||
              (vName.contains('td') && iName.contains('td')) ||
              (vName.contains('tetanus') && iName.contains('tetanus'))) {
            itemId = row['item_id'] as int?;
            break;
          }
        }
      }

      if (itemId == null) {
        if (mounted) {
          setState(() {
            _bhcStockCount = 0;
            _bhcStockLoading = false;
          });
        }
        return;
      }

      final today = DateTime.now().toIso8601String().split('T')[0];
      final batchesRes = await Supabase.instance.client
          .from('inventory_batches')
          .select('quantity_remaining, doses_remaining_in_open_vial, facility_id, item:inventory_items(doses_per_unit)')
          .eq('item_id', itemId)
          .eq('facility_id', _midwifeBhcId!)
          .eq('status', 'active')
          .gte('expiration_date', today);

      int totalDoses = 0;
      for (final b in (batchesRes as List<dynamic>)) {
        final sealedQty = (b['quantity_remaining'] as num? ?? 0).toInt();
        final openDoses = (b['doses_remaining_in_open_vial'] as num? ?? 0).toInt();
        final itemMap = b['item'] as Map<String, dynamic>?;
        final dosesPerUnit = (itemMap?['doses_per_unit'] as num? ?? 1).toInt();
        totalDoses += (sealedQty * dosesPerUnit) + openDoses;
      }

      if (mounted) {
        setState(() {
          _bhcStockCount = totalDoses;
          _bhcStockLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking BHC stock: $e');
      if (mounted) {
        setState(() {
          _bhcStockCount = 0;
          _bhcStockLoading = false;
        });
      }
    }
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

  double _getChildAgeMonths() {
    if (_childBirthdate == null) return 0;
    final now = DateTime.now();
    final diff = now.difference(_childBirthdate!);
    return diff.inDays / 30.44;
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
      // Indexes are rebuilt here rather than rescanned per row: the schedule
      // only changes on load, but the dropdown rebuilds on every keystroke.
      _rebuildLookups();

      if (_vaccines.isEmpty) {
        setState(() {
          // Not a failure — the schedule simply has not been loaded into this
          // deployment yet. Say what is missing and who can fix it, rather than
          // implying the record or the connection is broken.
          _errorMessage =
              'The immunization schedule has not been set up for this health '
              'centre yet. Ask your administrator to load the DOH schedule '
              'before recording vaccines.';
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
      // Dates come along too: the minimum interval before a later dose is
      // measured from when the previous one was actually given.
      final response = await Supabase.instance.client
          .from('immunization_records')
          .select('vaccine_id, vaccination_date')
          .eq('child_id', widget.childId);

      final taken = List<Map<String, dynamic>>.from(response);

      final ids = <int>{};
      final dates = <int, DateTime>{};
      for (final row in taken) {
        final id = row['vaccine_id'] as int?;
        if (id == null) continue;
        ids.add(id);

        final raw = row['vaccination_date']?.toString();
        final parsed = raw == null ? null : DateTime.tryParse(raw);
        // Keep the latest, in case a vaccine somehow has more than one record.
        if (parsed != null &&
            (dates[id] == null || parsed.isAfter(dates[id]!))) {
          dates[id] = parsed;
        }
      }

      if (!mounted) return;
      setState(() {
        _takenVaccineIds = ids;
        _givenDateByVaccineId
          ..clear()
          ..addAll(dates);
      });
    } catch (e) {
      debugPrint('Error loading taken vaccines: $e');
    }
  }

  /// Doses of each vaccine, ordered by dose number.
  final Map<String, List<Map<String, dynamic>>> _dosesByVaccineName = {};

  /// When each recorded dose was administered.
  final Map<int, DateTime> _givenDateByVaccineId = {};

  /// Vaccines that have more than one dose, so the tile knows when to show it.
  final Set<String> _multiDoseVaccineNames = {};

  void _rebuildLookups() {
    _dosesByVaccineName.clear();
    _multiDoseVaccineNames.clear();

    for (final vaccine in _vaccines) {
      final name = vaccine['vaccine_name']?.toString() ?? '';
      _dosesByVaccineName.putIfAbsent(name, () => []).add(vaccine);
    }

    for (final entry in _dosesByVaccineName.entries) {
      entry.value.sort((a, b) =>
          ((a['dose_number'] as num?)?.toInt() ?? 1)
              .compareTo((b['dose_number'] as num?)?.toInt() ?? 1));
      if (entry.value.length > 1) _multiDoseVaccineNames.add(entry.key);
    }
  }

  /// Whether every earlier dose of this vaccine is already recorded.
  bool _isPrerequisiteMet(Map<String, dynamic> vaccine) {
    final doseNumber = (vaccine['dose_number'] as num?)?.toInt() ?? 1;
    if (doseNumber <= 1) return true;

    final siblings = _dosesByVaccineName[vaccine['vaccine_name']?.toString()];
    if (siblings == null) return true;

    for (final dose in siblings) {
      final n = (dose['dose_number'] as num?)?.toInt() ?? 1;
      if (n >= doseNumber) break;
      if (!_takenVaccineIds.contains(dose['vaccine_id'] as int)) return false;
    }
    return true;
  }

  /// When the dose immediately before this one was given, if it was.
  DateTime? _previousDoseGivenOn(Map<String, dynamic> vaccine) {
    final doseNumber = (vaccine['dose_number'] as num?)?.toInt() ?? 1;
    if (doseNumber <= 1) return null;

    final siblings = _dosesByVaccineName[vaccine['vaccine_name']?.toString()];
    if (siblings == null) return null;

    for (final dose in siblings) {
      if (((dose['dose_number'] as num?)?.toInt() ?? 1) == doseNumber - 1) {
        return _givenDateByVaccineId[dose['vaccine_id'] as int];
      }
    }
    return null;
  }

  /// The earliest date this dose may be given, honouring both the scheduled
  /// age and the minimum interval since the previous dose.
  DateTime? _earliestAllowedFor(Map<String, dynamic> vaccine) {
    return ImmunizationSchedule.earliestAllowedDate(
      birthdate: _childBirthdate,
      scheduledAtMonths:
          (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0,
      previousDoseGivenOn: _previousDoseGivenOn(vaccine),
      minimumIntervalWeeks:
          (vaccine['minimum_interval_weeks'] as num?)?.toInt(),
    );
  }

  /// Every vaccine in the schedule, unfiltered.
  List<Map<String, dynamic>> _getAvailableVaccines() {
    return _vaccines;
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
        _dateController.text = DateFormat('MMMM d, yyyy').format(picked);
      });
    }
  }

  /// Age as printed on the DOH card.
  String _formatRecommendedAge(double? months) =>
      ImmunizationSchedule.formatScheduledAge(months);

  /// How late a dose must be before it counts as overdue rather than simply due.
  static const double _overdueAfterMonths = 4 / 4.345;

  /// Where each vaccine sits for this child, right now.
  _VaccineGroups _groupVaccines() {
    final childAgeMonths = _getChildAgeMonths();
    final today = DateTime.now();

    final given = <Map<String, dynamic>>[];
    final pastDue = <Map<String, dynamic>>[];
    final due = <Map<String, dynamic>>[];
    final dueSoon = <Map<String, dynamic>>[];
    final needsEarlierDose = <Map<String, dynamic>>[];
    final scheduledLater = <Map<String, dynamic>>[];
    final noLongerGiven = <Map<String, dynamic>>[];

    for (final vaccine in _vaccines) {
      if (_takenVaccineIds.contains(vaccine['vaccine_id'] as int)) {
        given.add(vaccine);
        continue;
      }

      final scheduledAt =
          (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0;

      if (_isPastAgeCeiling(vaccine, childAgeMonths)) {
        noLongerGiven.add(vaccine);
        continue;
      }

      if (childAgeMonths < scheduledAt) {
        scheduledLater.add(vaccine);
        continue;
      }

      if (!_isPrerequisiteMet(vaccine)) {
        needsEarlierDose.add(vaccine);
        continue;
      }

      final earliest = _earliestAllowedFor(vaccine);
      if (earliest != null && earliest.isAfter(today)) {
        dueSoon.add(vaccine);
        continue;
      }

      if (childAgeMonths - scheduledAt > _overdueAfterMonths) {
        pastDue.add(vaccine);
      } else {
        due.add(vaccine);
      }
    }

    int byScheduledAge(Map<String, dynamic> a, Map<String, dynamic> b) {
      final ageA = (a['recommended_age_months'] as num?)?.toDouble() ?? 0;
      final ageB = (b['recommended_age_months'] as num?)?.toDouble() ?? 0;
      return ageA.compareTo(ageB);
    }

    pastDue.sort(byScheduledAge);
    needsEarlierDose.sort(byScheduledAge);
    dueSoon.sort(byScheduledAge);

    return (
      pastDue: pastDue,
      dueSoon: dueSoon,
      due: due,
      needsEarlierDose: needsEarlierDose,
      scheduledLater: scheduledLater,
      noLongerGiven: noLongerGiven,
      given: given,
    );
  }

  /// Whether the child has passed the age after which this dose should no longer be given.
  bool _isPastAgeCeiling(Map<String, dynamic> vaccine, double childAgeMonths) {
    final ceiling = (vaccine['maximum_age_months'] as num?)?.toDouble();
    if (ceiling == null) return false;
    if (_childBirthdate == null) return false;
    return childAgeMonths > ceiling;
  }

  /// How far past its scheduled age a dose is, in plain words.
  String _overdueBy(Map<String, dynamic> vaccine) {
    final scheduledAt =
        (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0;
    final lateMonths = _getChildAgeMonths() - scheduledAt;
    if (lateMonths <= 0) return '';

    final lateWeeks = (lateMonths * 4.345).round();
    if (lateWeeks < 8) return '$lateWeeks weeks late';

    final months = lateMonths.floor();
    return months == 1 ? '1 month late' : '$months months late';
  }

  Widget _buildVaccineDropdown() {
    final groups = _groupVaccines();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppInputField(
          hintText: 'Select Vaccine',
          controller: _vaccineController,
          leadingIcon: Icons.vaccines_outlined,
          readOnly: true,
          isRequired: true,
          trailingIcon: _vaccineDropdownOpen
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          onTap: _toggleVaccineDropdown,
          onTrailingTap: _toggleVaccineDropdown,
        ),
        if (_vaccineDropdownOpen) ...[
          const SizedBox(height: 4),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  if (groups.pastDue.isNotEmpty) ...[
                    _buildDropdownSectionHeader(
                        'Past due', AppColors.warning),
                    ...groups.pastDue
                        .map((v) => _buildVaccineTile(v)),
                  ],
                  if (groups.due.isNotEmpty) ...[
                    _buildDropdownSectionHeader('Due now', AppColors.success),
                    ...groups.due.map((v) => _buildVaccineTile(v)),
                  ],
                  if (groups.dueSoon.isNotEmpty) ...[
                    _buildDropdownSectionHeader(
                        'Due soon', AppColors.brandAccent),
                    ...groups.dueSoon.map((v) => _buildVaccineTile(v)),
                  ],
                  if (_hasCollapsedGroups(groups)) _buildShowAllToggle(groups),

                  if (_showAllVaccines) ...[
                    if (groups.needsEarlierDose.isNotEmpty) ...[
                      _buildDropdownSectionHeader(
                          'Waiting on an earlier dose',
                          const Color(0xFFB78103)),
                      ...groups.needsEarlierDose
                          .map((v) => _buildVaccineTile(v)),
                    ],
                    if (groups.scheduledLater.isNotEmpty) ...[
                      _buildDropdownSectionHeader(
                          'Scheduled later', AppColors.textSecondary),
                      ...groups.scheduledLater
                          .map((v) => _buildVaccineTile(v)),
                    ],
                    if (groups.noLongerGiven.isNotEmpty) ...[
                      _buildDropdownSectionHeader(
                          'No longer given at this age', AppColors.error),
                      ...groups.noLongerGiven
                          .map((v) => _buildVaccineTile(v, isPastCeiling: true)),
                    ],
                    if (groups.given.isNotEmpty) ...[
                      _buildDropdownSectionHeader(
                          'Already given', AppColors.textSecondary),
                      ...groups.given.map(
                          (v) => _buildVaccineTile(v, isAlreadyTaken: true)),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _toggleVaccineDropdown() {
    if (_vaccinesLoading || _vaccines.isEmpty) return;
    setState(() => _vaccineDropdownOpen = !_vaccineDropdownOpen);
  }

  bool _hasCollapsedGroups(_VaccineGroups groups) =>
      groups.needsEarlierDose.isNotEmpty ||
      groups.scheduledLater.isNotEmpty ||
      groups.noLongerGiven.isNotEmpty ||
      groups.given.isNotEmpty;

  Widget _buildShowAllToggle(_VaccineGroups groups) {
    final hidden = groups.needsEarlierDose.length +
        groups.scheduledLater.length +
        groups.noLongerGiven.length +
        groups.given.length;

    return InkWell(
      onTap: () => setState(() => _showAllVaccines = !_showAllVaccines),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _showAllVaccines ? 'Show fewer' : 'Show all ($hidden more)',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.brandPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _showAllVaccines ? Icons.expand_less : Icons.expand_more,
              size: 17,
              color: AppColors.brandPrimary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvidenceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            'How do we know?',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        ..._evidenceLabels.entries.map((entry) {
          final selected = _evidence == entry.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _evidence = entry.key),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.brandPrimary.withValues(alpha: 0.07)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? AppColors.brandPrimary.withValues(alpha: 0.4)
                        : AppColors.borderPrimary,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected
                          ? AppColors.brandPrimary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected
                              ? AppColors.brandPrimary
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
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

  Widget _buildVaccineTile(
    Map<String, dynamic> vaccine, {
    bool isAlreadyTaken = false,
    bool isPastCeiling = false,
  }) {
    final vaccineName = vaccine['vaccine_name']?.toString() ?? '';
    final doseNumber = vaccine['dose_number']?.toString() ?? '';
    final recommendedAge =
        (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0;
    final ageText = _formatRecommendedAge(recommendedAge);

    final multiDose = _multiDoseVaccineNames.contains(vaccineName);
    final label =
        multiDose ? '$vaccineName · Dose $doseNumber' : vaccineName;

    final earliest = isAlreadyTaken || isPastCeiling
        ? null
        : _earliestAllowedFor(vaccine);
    final waiting = earliest != null && earliest.isAfter(DateTime.now());

    final lateness = _overdueBy(vaccine);
    final isLate =
        !isAlreadyTaken && !isPastCeiling && !waiting && lateness.isNotEmpty;

    final String subtitle;
    if (isAlreadyTaken) {
      subtitle = '$ageText · already given';
    } else if (isPastCeiling) {
      subtitle = 'Should not be started after this age';
    } else if (waiting) {
      subtitle = 'Due ${DateFormat('MMMM d, yyyy').format(earliest)}';
    } else if (isLate) {
      subtitle = '$ageText · $lateness';
    } else {
      subtitle = ageText;
    }

    final Color subtitleColor;
    if (isPastCeiling) {
      subtitleColor = AppColors.error;
    } else if (isLate) {
      subtitleColor = AppColors.warning;
    } else if (waiting) {
      subtitleColor = AppColors.brandAccent;
    } else {
      subtitleColor = Colors.grey.shade500;
    }

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color:
              isAlreadyTaken ? AppColors.textSecondary : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11.5,
          color: subtitleColor,
          fontWeight:
              isLate || isPastCeiling ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isAlreadyTaken
          ? const Icon(Icons.check_circle_rounded,
              size: 18, color: AppColors.success)
          : (isLate
              ? const Icon(Icons.schedule_rounded,
                  size: 17, color: AppColors.warning)
              : null),
      onTap: () {
        final vId = vaccine['vaccine_id'] as int;
        setState(() {
          _selectedVaccineId = vId;
          _vaccineController.text = label;
          _vaccineDropdownOpen = false;
        });
        _checkBhcStock(vId);
      },
    );
  }

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

  Future<bool?> _confirmPastAgeCeiling(String label) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Past the age limit',
        subtitle: _isOutside
            ? '$label is not given after this age. Record it only if it was '
                'actually given earlier, at the date shown.'
            : '$label should not be given at this child\'s age. If it has '
                'already been given elsewhere you may still record it — '
                'otherwise cancel and do not administer it.',
        cancelText: 'Cancel',
        confirmText: 'Record anyway',
        accentColor: AppColors.error,
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
  }

  Future<bool?> _confirmTooSoon(String label, DateTime earliestAllowed) {
    final due = DateFormat('MMMM d, yyyy').format(earliestAllowed);
    return showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Too soon after the last dose',
        subtitle:
            '$label is not due until $due — the minimum interval since the '
            'previous dose has not passed. A dose given too early may not '
            'count and may need repeating. Record it only if it was genuinely '
            'given on the date entered.',
        cancelText: 'Cancel',
        confirmText: 'Record anyway',
        accentColor: AppColors.warning,
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
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

    if (_isPastAgeCeiling(selected, _getChildAgeMonths())) {
      final proceed = await _confirmPastAgeCeiling(vaccineLabel);
      if (proceed != true) return false;
    }

    final earliestAllowed = _earliestAllowedFor(selected);
    if (earliestAllowed != null && _selectedDate!.isBefore(earliestAllowed)) {
      final proceed =
          await _confirmTooSoon(vaccineLabel, earliestAllowed);
      if (proceed != true) return false;
    }

    if (!_isPrerequisiteMet(selected)) {
      final doseNumber = (selected['dose_number'] as num?)?.toInt() ?? 1;
      final proceed = await _confirmMissingPrerequisite(
        vaccineLabel,
        doseNumber,
      );
      if (proceed != true) return false;
    }

    if (!_isOutside && (_bhcStockCount ?? 0) <= 0) {
      if (mounted) {
        await _showBlockedDialog(
          'Out of Stock',
          'There are no remaining vials for this vaccine at your BHC. '
          'You cannot deduct stock when count is 0. '
          'Please request stock replenishment or go back to record a dose given elsewhere.',
        );
      }
      return false;
    }

    try {
      int? midwifeId;
      int? bhcId;
      try {
        final accountId = await AuthStorage.getUserId();
        if (accountId != null) {
          final ctx = await SupabaseService.getMidwifeContext(accountId);
          midwifeId = ctx['midwife_id'] as int?;
          bhcId = ctx['assigned_bhc_id'] as int?;
        }
      } catch (e) {
        debugPrint('Error getting midwife ID: $e');
      }

      final vaccine = _vaccines.firstWhere(
        (v) => v['vaccine_id'] == _selectedVaccineId,
        orElse: () => <String, dynamic>{},
      );

      final insertedRes = await Supabase.instance.client
          .from('immunization_records')
          .insert({
            'child_id': widget.childId,
            'vaccine_id': _selectedVaccineId!,
            'vaccination_date': _selectedDate!.toIso8601String().split('T')[0],
            'dose_number': (vaccine['dose_number'] as num?)?.toInt() ?? 1,
            'remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
            'created_at': DateTime.now().toIso8601String(),
            'source': widget.source.dbValue,
            'administration_place': _administrationPlace,
            if (bhcId != null) 'facility_id': bhcId,
            if (midwifeId != null) 'recorded_by': midwifeId,
            if (midwifeId != null && !_isOutside) 'administered_by': midwifeId,
            if (_isOutside) ...{
              'facility_name': _facilityController.text.trim().isEmpty
                  ? null
                  : _facilityController.text.trim(),
              'evidence': _evidence,
            },
          })
          .select('immunization_record_id')
          .single();

      final recId = insertedRes['immunization_record_id'] as int?;
      if (recId != null && !_isOutside) {
        try {
          final rpcRes = await Supabase.instance.client.rpc('deduct_immunization_stock', params: {
            'p_immunization_record_id': recId,
          });
          debugPrint('Deduct stock RPC result: $rpcRes');
        } catch (rpcErr) {
          debugPrint('RPC stock deduction warning (non-fatal): $rpcErr');
        }
      }

      setState(() {
        _anyRecordAdded = true;
        _takenVaccineIds.add(_selectedVaccineId!);
        _givenDateByVaccineId[_selectedVaccineId!] = _selectedDate!;
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

  Widget _buildBhcStockCard() {
    if (_isOutside || _selectedVaccineId == null) return const SizedBox.shrink();

    if (_bhcStockLoading) {
      return Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPrimary),
            ),
            SizedBox(width: 8),
            Text('Checking BHC stock availability...', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (_bhcStockCount == null) return const SizedBox.shrink();

    if (_bhcStockCount! > 10) {
      return Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF059669), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'BHC Stock Available: $_bhcStockCount dose${_bhcStockCount == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
              ),
            ),
          ],
        ),
      );
    }

    if (_bhcStockCount! > 0) {
      return Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Low Stock Warning: Only $_bhcStockCount dose${_bhcStockCount == 1 ? '' : 's'} remaining at this BHC.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: const Row(
        children: [
          Icon(Icons.block_rounded, color: Color(0xFFDC2626), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Out of Stock: 0 vials available at this BHC. Request stock replenishment or go back to record a dose given elsewhere.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
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
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(
                        _isOutside ? 'Given Elsewhere' : 'Given Here',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brandText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isOutside
                            ? 'Recording a dose given at another facility'
                            : 'Recording a dose given at this health center',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

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
                        const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.error, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_vaccinesLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  )
                else ...[
                  // Select Vaccine
                  _buildVaccineDropdown(),

                  if (!hasAvailableVaccines && _vaccines.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0, left: 8.0),
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

                  _buildBhcStockCard(),

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

                  // Outside-record fields
                  if (_isOutside) ...[
                    AppInputField(
                      hintText: 'Where was it given?',
                      controller: _facilityController,
                      leadingIcon: Icons.location_city_outlined,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(
                        'Hospital, clinic or health center name, if known.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                    _buildEvidenceSelector(),
                    const SizedBox(height: 16),
                  ],

                  // Remarks
                  Row(
                    children: const [
                      Icon(Icons.notes_rounded,
                          size: 18, color: AppColors.textSecondary),
                      SizedBox(width: 8),
                      Text(
                        'Remarks',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _remarksController,
                    maxLines: 5,
                    maxLength: 1000,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                    cursorColor: AppColors.brandPrimary,
                    decoration: InputDecoration(
                      hintText: _isOutside
                          ? 'Anything worth noting about this record (optional)'
                          : 'Observations, reactions, batch notes (optional)',
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      border: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.borderPrimary),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppColors.borderPrimary),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppColors.brandPrimary),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),

                  const SizedBox(height: 12),

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vaccines sorted into what the midwife can act on, in one pass.
typedef _VaccineGroups = ({
  List<Map<String, dynamic>> pastDue,
  List<Map<String, dynamic>> due,
  List<Map<String, dynamic>> dueSoon,
  List<Map<String, dynamic>> needsEarlierDose,
  List<Map<String, dynamic>> scheduledLater,
  List<Map<String, dynamic>> noLongerGiven,
  List<Map<String, dynamic>> given,
});
