import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/main_button.dart';
import '../../widgets/dialog_box.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/branded_date_picker.dart';
import '../../widgets/app_input_field.dart';
import 'add_child_step3_child.dart';
import 'child_profile_page.dart';
import 'add_growth_step1.dart';
import '../../services/ph_address_service.dart' as ph_addr;
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';

class AddChildStep4Birth extends StatefulWidget {
  final ChildParentMode mode;

  /// BHC the registering midwife belongs to. Stamped onto the child row so the
  /// database trigger can assign a NAK number that is unique within that BHC.
  final int? assignedBhcId;

  // Child info
  final String firstName;
  final String lastName;
  final String middleName;
  final String extensionName;
  final String sex;

  // Registered Mother mode
  final int? motherId;
  final String? motherName;

  // New Guardian mode
  final String? guardianFirstName;
  final String? guardianLastName;
  final String? guardianMiddleName;
  final String? guardianExtensionName;
  final String? guardianPhone;
  final String? guardianAddress;
  final String? guardianRelationship;

  const AddChildStep4Birth({
    super.key,
    required this.mode,
    this.assignedBhcId,
    required this.firstName,
    required this.lastName,
    required this.middleName,
    required this.extensionName,
    required this.sex,
    this.motherId,
    this.motherName,
    this.guardianFirstName,
    this.guardianLastName,
    this.guardianMiddleName,
    this.guardianExtensionName,
    this.guardianPhone,
    this.guardianAddress,
    this.guardianRelationship,
  });

  @override
  State<AddChildStep4Birth> createState() => _AddChildStep4BirthState();
}

class _AddChildStep4BirthState extends State<AddChildStep4Birth> {
  final _formKey = GlobalKey<FormState>();
  bool isSaving = false;

  /// Errors stay hidden until the midwife first tries to submit, so a form
  /// opens clean instead of pre-flagging fields nobody has touched yet.
  bool _showErrors = false;

  /// Human-readable date format used across the app's forms (see Add Mother).
  /// Dates are shown as "March 20, 2020" and stored as ISO-8601.
  static final DateFormat _displayDateFmt = DateFormat('MMMM d, yyyy');

  /// Digits and a single decimal point only — birth weight and length are
  /// measurements, so letters can never be valid input.
  static final List<TextInputFormatter> _decimalInputFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
    LengthLimitingTextInputFormatter(6),
    TextInputFormatter.withFunction((oldValue, newValue) {
      // Reject a second decimal point rather than letting "3..2" reach the
      // parser and surface as a validation error the midwife has to decode.
      if ('.'.allMatches(newValue.text).length > 1) return oldValue;
      return newValue;
    }),
  ];

  final birthdateCtrl = TextEditingController();
  final birthWeightCtrl = TextEditingController();
  final birthLengthCtrl = TextEditingController();
  final provinceCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final birthplaceCtrl = TextEditingController();

  DateTime? selectedBirthdate;

  List<String> _apiProvinces = [];
  List<String> _apiCities = [];
  bool _loadingProvinces = false;
  bool _loadingCities = false;
  String? _activeAddressSearchField;
  final ScrollController _suggestionScrollController = ScrollController();

  /// Birth dates from the mother's recorded pregnancy history, offered as
  /// one-tap suggestions. Empty for guardian-only registrations and for mothers
  /// with no live births on file.
  List<DateTime> _suggestedBirthdates = [];

  @override
  void initState() {
    super.initState();
    _loadProvinces();
    if (provinceCtrl.text.isNotEmpty) {
      _preloadCities();
    }
    _loadSuggestedBirthdates();
  }

  Future<void> _loadSuggestedBirthdates() async {
    final motherId = widget.motherId;
    if (motherId == null) return;

    final dates = await SupabaseService.getLiveBirthDatesForMother(motherId);
    if (mounted && dates.isNotEmpty) {
      setState(() => _suggestedBirthdates = dates);
    }
  }

  Future<void> _loadProvinces() async {
    setState(() => _loadingProvinces = true);
    try {
      final list = await ph_addr.PhAddressService.getProvinces();
      if (mounted) {
        setState(() {
          _apiProvinces = list.map((p) => p.name).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading provinces: $e');
    } finally {
      if (mounted) setState(() => _loadingProvinces = false);
    }
  }

  Future<void> _preloadCities() async {
    setState(() => _loadingCities = true);
    try {
      final list = await ph_addr.PhAddressService.getCities(provinceCtrl.text);
      if (mounted) {
        setState(() {
          _apiCities = list.map((c) => c.name).toList();
        });
      }
    } catch (e) {
      debugPrint('Error preloading cities: $e');
    } finally {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  Future<void> _onProvinceSelected(String provinceName) async {
    setState(() {
      provinceCtrl.text = provinceName;
      cityCtrl.clear();
      _apiCities = [];
      _loadingCities = true;
    });

    try {
      final list = await ph_addr.PhAddressService.getCities(provinceName);
      if (mounted) {
        setState(() {
          _apiCities = list.map((c) => c.name).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading cities: $e');
    } finally {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  void _onCitySelected(String cityName) {
    setState(() {
      cityCtrl.text = cityName;
    });
  }

  List<TextSpan> _buildHighlightedTextSpans(String text, String query) {
    final List<TextSpan> spans = [];
    final textLower = text.toLowerCase();
    final queryLower = query.toLowerCase();

    int start = 0;
    int indexOfMatch = textLower.indexOf(queryLower, start);

    while (indexOfMatch != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(
          text: text.substring(start, indexOfMatch),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + query.length),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.brandPrimary,
        ),
      ));
      start = indexOfMatch + query.length;
      indexOfMatch = textLower.indexOf(queryLower, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
      ));
    }

    return spans;
  }

  Widget _buildSearchableAddressField({
    required String hintText,
    required TextEditingController controller,
    required String fieldType, // 'province', 'city'
    required bool isRequired,
    required IconData leadingIcon,
    required bool readOnly,
    required bool isLoading,
    required Function(String) onSelected,
    required VoidCallback onChanged,
  }) {
    final bool isActive = _activeAddressSearchField == fieldType;

    // Filter items
    List<String> suggestions = [];
    if (fieldType == 'province') {
      suggestions = _apiProvinces;
    } else if (fieldType == 'city') {
      suggestions = _apiCities;
    }

    final query = controller.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final primary = suggestions
          .where((item) => item.toLowerCase().startsWith(query))
          .toList();
      final secondary = suggestions
          .where((item) =>
              item.toLowerCase().contains(query) &&
              !item.toLowerCase().startsWith(query))
          .toList();
      suggestions = [...primary, ...secondary];
    }

    final visibleSuggestions = suggestions.take(15).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          onFocusChange: (focused) {
            if (focused && !readOnly) {
              setState(() {
                _activeAddressSearchField = fieldType;
              });
            } else {
              Future.delayed(const Duration(milliseconds: 250), () {
                if (mounted && _activeAddressSearchField == fieldType) {
                  setState(() {
                    _activeAddressSearchField = null;
                  });
                }
              });
            }
          },
          child: AppInputField(
            hintText: hintText,
            controller: controller,
            isRequired: isRequired,
            leadingIcon: leadingIcon,
            readOnly: readOnly,
            onChanged: (val) {
              onChanged();
              setState(() {});
            },
          ),
        ),
        if (!readOnly && isActive) ...[
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            constraints: const BoxConstraints(maxHeight: 220),
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.cardColorOf(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.brandPrimaryOf(context).withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.brandPrimaryOf(context),
                          ),
                        ),
                      ),
                    ),
                  )
                : visibleSuggestions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        child: Text(
                          query.isEmpty
                              ? 'Start typing to search...'
                              : 'No matches found. You can keep typing.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondaryOf(context),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : Scrollbar(
                        controller: _suggestionScrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _suggestionScrollController,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: visibleSuggestions.length,
                          itemBuilder: (context, index) {
                            final item = visibleSuggestions[index];
                            final bool startsWithQuery = query.isNotEmpty &&
                                item.toLowerCase().startsWith(query);

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  onSelected(item);
                                  FocusScope.of(context).unfocus();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        startsWithQuery
                                            ? Icons.arrow_right_alt
                                            : Icons.location_on_outlined,
                                        size: 16,
                                        color: startsWithQuery
                                            ? AppColors.brandPrimaryOf(context)
                                            : AppColors.textSecondaryOf(
                                                context,
                                              ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: AppColors.textPrimaryOf(
                                                context,
                                              ),
                                            ),
                                            children: query.isEmpty
                                                ? [TextSpan(text: item)]
                                                : _buildHighlightedTextSpans(
                                                    item,
                                                    query,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String? get _birthWeightWarning {
    final weight = double.tryParse(birthWeightCtrl.text);
    if (weight == null) return null;
    if (weight < 0.5 || weight > 6.0) {
      return 'Typical birth weight is 0.5 - 6.0 kg. Please verify.';
    }
    return null;
  }

  String? get _birthLengthWarning {
    final length = double.tryParse(birthLengthCtrl.text);
    if (length == null) return null;
    if (length < 30 || length > 60) {
      return 'Typical birth length is 30 - 60 cm. Please verify.';
    }
    return null;
  }

  /// Blocking errors, as opposed to the soft range warnings above.
  ///
  /// Birth weight and length were previously labelled required but accepted as
  /// empty. They are enforced here because the growth module uses them as the
  /// week-0 baseline for WHO z-scores — a child registered without them starts
  /// with an incomplete growth chart.
  String? get _birthWeightError {
    final text = birthWeightCtrl.text.trim();
    if (text.isEmpty) return 'Birth weight is required';
    final weight = double.tryParse(text);
    if (weight == null) return 'Enter a number, e.g. 3.2';
    if (weight <= 0) return 'Birth weight must be greater than 0';
    return null;
  }

  String? get _birthLengthError {
    final text = birthLengthCtrl.text.trim();
    if (text.isEmpty) return 'Birth length is required';
    final length = double.tryParse(text);
    if (length == null) return 'Enter a number, e.g. 49.5';
    if (length <= 0) return 'Birth length must be greater than 0';
    return null;
  }

  String? get _birthdateError {
    // selectedBirthdate is the source of truth; the controller only mirrors it
    // for display. Requiring it here guarantees _saveChild has a real DateTime.
    if (selectedBirthdate == null) return 'Birth date is required';
    if (selectedBirthdate!.isAfter(DateTime.now())) {
      return 'Birth date cannot be in the future';
    }
    return null;
  }

  bool get isFormValid {
    return _birthdateError == null &&
        _birthWeightError == null &&
        _birthLengthError == null &&
        provinceCtrl.text.trim().isNotEmpty &&
        cityCtrl.text.trim().isNotEmpty &&
        birthplaceCtrl.text.trim().isNotEmpty;
  }

  /// Earliest selectable birth date.
  ///
  /// Normally 6 years back, since the child health module covers 0-5 years. If
  /// the mother's history contains an older live birth, the window stretches to
  /// include it — a suggestion the picker cannot reach would be useless.
  DateTime get _earliestBirthdate {
    final now = DateTime.now();
    var earliest = DateTime(now.year - 6, now.month, now.day);
    for (final date in _suggestedBirthdates) {
      if (date.isBefore(earliest)) earliest = date;
    }
    return earliest;
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();

    final picked = await showBrandedDatePicker(
      context: context,
      initialDate: selectedBirthdate ?? now,
      firstDate: _earliestBirthdate,
      lastDate: now,
      helpText: 'SELECT BIRTH DATE',
    );

    if (picked != null) {
      _applyBirthdate(picked);
    }
  }

  void _applyBirthdate(DateTime date) {
    setState(() {
      selectedBirthdate = date;
      // Display format only. The value written to the database comes from
      // selectedBirthdate, never from this controller's text.
      birthdateCtrl.text = _displayDateFmt.format(date);
    });
  }

  /// One-tap birth dates taken from the mother's recorded pregnancy history.
  ///
  /// These are a shortcut, not a constraint: the field stays fully editable and
  /// the calendar remains available, because the history may be incomplete or
  /// the child in front of the midwife may not be one of these births.
  Widget _buildBirthdateSuggestions() {
    if (_suggestedBirthdates.isEmpty) return const SizedBox.shrink();

    final formatter = DateFormat('MMMM d, yyyy');

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 14,
                color: AppColors.brandAccent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _suggestedBirthdates.length == 1
                      ? 'Previous live birth on record'
                      : 'Previous live births on record',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestedBirthdates.map((date) {
              final isSelected = selectedBirthdate != null &&
                  DateUtils.isSameDay(selectedBirthdate, date);

              return InkWell(
                onTap: () => _applyBirthdate(date),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.brandPrimary.withValues(alpha: 0.12)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.brandPrimary
                          : AppColors.borderPrimary,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.calendar_today_outlined,
                        size: 14,
                        color: isSelected
                            ? AppColors.brandPrimary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatter.format(date),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? AppColors.brandPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Fallback for entry points that did not carry the midwife's BHC through
  /// the wizard (for example the guardian branch launched from the choice
  /// screen without an assignedBhcId).
  Future<int?> _resolveMidwifeBhcId() async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) return null;
      final ctx = await SupabaseService.getMidwifeContext(accountId);
      return ctx['assigned_bhc_id'] as int?;
    } catch (e) {
      debugPrint('Could not resolve midwife BHC for child number: $e');
      return null;
    }
  }

  /// The signed-in midwife's midwife_id, for registrar attribution.
  Future<int?> _resolveMidwifeId() async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) return null;
      final ctx = await SupabaseService.getMidwifeContext(accountId);
      return ctx['midwife_id'] as int?;
    } catch (e) {
      debugPrint('Could not resolve registering midwife: $e');
      return null;
    }
  }

  Future<void> _saveChild() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSaving = true);

    try {
      int? guardianId;

      if (widget.mode == ChildParentMode.newGuardian) {
        final guardianResponse = await Supabase.instance.client
            .from('guardians')
            .insert({
              'first_name': widget.guardianFirstName,
              'last_name': widget.guardianLastName,
              'middle_name': widget.guardianMiddleName?.isEmpty == true
                  ? null
                  : widget.guardianMiddleName,
              'extension_name': widget.guardianExtensionName?.isEmpty == true
                  ? null
                  : widget.guardianExtensionName,
              'phone_number': widget.guardianPhone?.isEmpty == true
                  ? null
                  : widget.guardianPhone,
              'address': widget.guardianAddress?.isEmpty == true
                  ? null
                  : widget.guardianAddress,
              'relationship': widget.guardianRelationship ?? 'Guardian',
              'created_at': DateTime.now().toIso8601String(),
            })
            .select('guardian_id')
            .single();

        guardianId = guardianResponse['guardian_id'] as int;
      }

      final Map<String, dynamic> childData = {
        'first_name': widget.firstName,
        'last_name': widget.lastName,
        'middle_name': widget.middleName.isEmpty ? null : widget.middleName,
        'extension_name':
            widget.extensionName.isEmpty ? null : widget.extensionName,
        'sex': widget.sex,
        'added_at': DateTime.now().toIso8601String(),
      };

      // The BHC drives the NAK child number, which the database trigger assigns
      // per BHC. Guardian-only children are registered at the same BHC as the
      // midwife entering them, so both modes carry one.
      final bhcId = widget.assignedBhcId ?? await _resolveMidwifeBhcId();
      if (bhcId != null) {
        childData['assigned_bhc_id'] = bhcId;
      }

      // Records which midwife registered this child, mirroring
      // mothers.registered_by_midwife_id.
      final midwifeId = await _resolveMidwifeId();
      if (midwifeId != null) {
        childData['registered_by_midwife_id'] = midwifeId;
      }

      if (widget.mode == ChildParentMode.registeredMother &&
          widget.motherId != null) {
        childData['mother_id'] = widget.motherId;
        childData['guardian_id'] = null;
        childData['has_guardian_only'] = false;
      } else if (guardianId != null) {
        childData['mother_id'] = null;
        childData['guardian_id'] = guardianId;
        childData['has_guardian_only'] = true;
      } else {
        childData['mother_id'] = null;
        childData['guardian_id'] = null;
        childData['has_guardian_only'] = false;
      }

      debugPrint('Inserting child with data: $childData');

      final childResponse = await Supabase.instance.client
          .from('children')
          .insert(childData)
          .select('child_id')
          .single();

      final childId = childResponse['child_id'] as int;

      // Read the trigger-assigned number in a separate, failure-tolerant call.
      // If the child_number migration has not been applied yet this returns
      // null and registration still succeeds — the number is an identifier,
      // not a precondition for having a record.
      final childNumber = await SupabaseService.getChildNumber(childId);

      final weightText = birthWeightCtrl.text.trim();
      final lengthText = birthLengthCtrl.text.trim();
      final birthWeight = weightText.isNotEmpty ? double.tryParse(weightText) : null;
      final birthLength = lengthText.isNotEmpty ? double.tryParse(lengthText) : null;

      await Supabase.instance.client.from('birth_details').insert({
        'child_id': childId,
        // ISO-8601 from the picked DateTime, not the field's display text —
        // the field now reads "March 20, 2020", which Postgres cannot parse.
        'birthdate':
            DateFormat('yyyy-MM-dd').format(selectedBirthdate!),
        'birth_weight': birthWeight,
        'birth_length': birthLength,
        'birthplace_city_municipality': cityCtrl.text,
        'birthplace_province': provinceCtrl.text,
        'birthplace_facility': birthplaceCtrl.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });

      // REMOVED duplicate child_details insertion to avoid double-logging birth measurements in different weeks.
      // The synthetic W0 record prepending logic in list pages will handle displaying birth details at Week 0.

      if (!mounted) return;

      String successMessage;
      if (widget.mode == ChildParentMode.registeredMother) {
        successMessage =
            'Child has been successfully registered to ${widget.motherName ?? 'the mother'}.';
      } else {
        successMessage =
            'Child has been successfully registered with guardian ${widget.guardianFirstName} ${widget.guardianLastName} (${widget.guardianRelationship ?? 'Guardian'}).';
      }

      if (childNumber != null) {
        successMessage = '$successMessage\n\nChild Number: $childNumber';
      }

      if (!mounted) return;

      // Show success dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return DialogBox(
            type: DialogType.success,
            title: 'Child Added',
            content: successMessage,
            buttonText: 'OK',
            onPressed: () {
              Navigator.pop(context);
            },
          );
        },
      );

      // After dialog closes, navigate to AddGrowthStep1 first on top of ChildProfilePage
      if (mounted) {
        // Pop all add-child wizard screens and place ChildProfilePage as the new base screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ChildProfilePage(childId: childId),
          ),
          (route) => route.isFirst,
        );

        // Immediately push the AddGrowthStep1 screen on top so the midwife can log the first growth record right away
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddGrowthStep1(childId: childId),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving child: $e');
      setState(() => isSaving = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add child: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  void dispose() {
    birthdateCtrl.dispose();
    birthWeightCtrl.dispose();
    birthLengthCtrl.dispose();
    provinceCtrl.dispose();
    cityCtrl.dispose();
    birthplaceCtrl.dispose();
    _suggestionScrollController.dispose();
    super.dispose();
  }

  bool get _hasEnteredData =>
      birthdateCtrl.text.trim().isNotEmpty ||
      birthWeightCtrl.text.trim().isNotEmpty ||
      birthLengthCtrl.text.trim().isNotEmpty ||
      birthplaceCtrl.text.trim().isNotEmpty ||
      provinceCtrl.text.trim().isNotEmpty ||
      cityCtrl.text.trim().isNotEmpty;

  /// Header back = leave the Add Child flow entirely.
  ///
  /// Popping a single route would land on the previous wizard step, forcing the
  /// midwife to confirm a discard once per screen on the way out. Abandoning
  /// registration is one decision, so it takes one confirmation and returns to
  /// the children list.
  Future<void> _confirmDiscardAndExit() async {
    if (!_hasEnteredData) {
      _exitWizard();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Discard child registration?',
        subtitle:
            'You have unsaved child registration details. Are you sure you want to discard these changes?',
        cancelText: 'Cancel',
        confirmText: 'Discard',
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
    if (discard == true && mounted) {
      _exitWizard();
    }
  }

  /// Unwinds every screen of the Add Child flow back to the children list.
  ///
  /// The list lives in the midwife shell, which login installs as the first
  /// route — the same anchor _saveChild uses on success.
  void _exitWizard() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    String parentDisplayName;
    if (widget.mode == ChildParentMode.registeredMother &&
        widget.motherName != null) {
      parentDisplayName = widget.motherName!;
    } else if (widget.guardianFirstName != null &&
        widget.guardianLastName != null) {
      parentDisplayName =
          '${widget.guardianFirstName} ${widget.guardianLastName}';
    } else {
      parentDisplayName = 'Guardian';
    }

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SecondaryHeader(
              title: 'Add Child',
              onBack: _confirmDiscardAndExit,
            ),
            // Step 2 of 2 — mirrors the Add Mother wizard's progress bar and
            // title/subtitle block so both registration flows read the same.
            const LinearProgressIndicator(
              value: 1.0,
              backgroundColor: AppColors.borderPrimary,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
              minHeight: 3,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  const Text(
                    'Birth Information',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.mode == ChildParentMode.registeredMother
                        ? 'Birth details for the child of $parentDisplayName'
                        : 'Birth details for the child of $parentDisplayName',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isSaving
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.brandPrimary),
                    SizedBox(height: 20),
                    Text(
                      'Adding child...',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please wait a moment',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: _pickBirthdate,
                              child: AbsorbPointer(
                                child: AppInputField(
                                  hintText: 'Birth Date',
                                  controller: birthdateCtrl,
                                  isRequired: true,
                                  readOnly: true,
                                  errorText: _showErrors ? _birthdateError : null,
                                  trailingIcon: Icons.calendar_today,
                                  onTrailingTap: _pickBirthdate,
                                ),
                              ),
                            ),
                            _buildBirthdateSuggestions(),
                            const SizedBox(height: 16),
                            AppInputField(
                              hintText: 'Birth Weight (kg)',
                              controller: birthWeightCtrl,
                              isRequired: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: _decimalInputFormatters,
                              errorText: _showErrors ? _birthWeightError : null,
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_birthWeightWarning != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: 6, left: 12, bottom: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        size: 16, color: AppColors.warning),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _birthWeightWarning!,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.warning),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            AppInputField(
                              hintText: 'Birth Length (cm)',
                              controller: birthLengthCtrl,
                              isRequired: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: _decimalInputFormatters,
                              errorText: _showErrors ? _birthLengthError : null,
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_birthLengthWarning != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: 6, left: 12, bottom: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        size: 16, color: AppColors.warning),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _birthLengthWarning!,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.warning),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            _buildSearchableAddressField(
                              hintText: 'Birth Province',
                              controller: provinceCtrl,
                              fieldType: 'province',
                              isRequired: true,
                              leadingIcon: Icons.map_outlined,
                              readOnly: false,
                              isLoading: _loadingProvinces,
                              onSelected: (val) {
                                _onProvinceSelected(val);
                              },
                              onChanged: () {
                                setState(() {
                                  cityCtrl.clear();
                                  _apiCities = [];
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildSearchableAddressField(
                              hintText: 'Birth City/Municipality',
                              controller: cityCtrl,
                              fieldType: 'city',
                              isRequired: true,
                              leadingIcon: Icons.location_city_outlined,
                              readOnly: provinceCtrl.text.isEmpty,
                              isLoading: _loadingCities,
                              onSelected: (val) {
                                _onCitySelected(val);
                              },
                              onChanged: () {},
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              hintText: 'Birthplace (Hospital/Clinic/Home)',
                              controller: birthplaceCtrl,
                              isRequired: true,
                              leadingIcon: Icons.location_on_outlined,
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: MainButton(
                    label: 'Back',
                    leftIcon: Icons.arrow_back_ios_new_rounded,
                    isWhiteVariant: true,
                    // Steps back to Child Information with its data intact —
                    // that screen is still on the stack. Only the header back
                    // abandons the whole registration.
                    onPressed: isSaving ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MainButton(
                    label: isSaving ? 'Saving...' : 'Add Child',
                    rightIcon: isSaving ? null : Icons.check_rounded,
                    onPressed: isSaving ? null : _onSubmitPressed,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Reveals validation errors rather than leaving a disabled button with no
  /// explanation — the midwife should be told which field is blocking her.
  void _onSubmitPressed() {
    if (!isFormValid) {
      setState(() => _showErrors = true);
      return;
    }
    _saveChild();
  }
}
