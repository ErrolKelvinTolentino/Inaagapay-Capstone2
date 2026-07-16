import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/page_title.dart';
import '../../widgets/main_button.dart';
import '../../widgets/small_description.dart';
import '../../widgets/dialog_box.dart';
import '../../widgets/app_input_field.dart';
import 'add_child_step3_child.dart';
import 'child_profile_page.dart';
import 'add_growth_step1.dart';
import '../../services/ph_address_service.dart' as ph_addr;

class AddChildStep4Birth extends StatefulWidget {
  final ChildParentMode mode;

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

  @override
  void initState() {
    super.initState();
    _loadProvinces();
    if (provinceCtrl.text.isNotEmpty) {
      _preloadCities();
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

  bool get isFormValid {
    final birthdateValid = birthdateCtrl.text.isNotEmpty;
    final provinceValid = provinceCtrl.text.trim().isNotEmpty;
    final cityValid = cityCtrl.text.trim().isNotEmpty;
    final birthplaceValid = birthplaceCtrl.text.trim().isNotEmpty;

    // Optional birth weight and length (if provided, they must be valid numbers)
    final weightText = birthWeightCtrl.text.trim();
    final lengthText = birthLengthCtrl.text.trim();
    final birthWeightValid = weightText.isEmpty || double.tryParse(weightText) != null;
    final birthLengthValid = lengthText.isEmpty || double.tryParse(lengthText) != null;

    return birthdateValid &&
        birthWeightValid &&
        birthLengthValid &&
        provinceValid &&
        cityValid &&
        birthplaceValid;
  }

  Future<void> _pickBirthdate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        selectedBirthdate = picked;
        birthdateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
      });
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

      final weightText = birthWeightCtrl.text.trim();
      final lengthText = birthLengthCtrl.text.trim();
      final birthWeight = weightText.isNotEmpty ? double.tryParse(weightText) : null;
      final birthLength = lengthText.isNotEmpty ? double.tryParse(lengthText) : null;

      await Supabase.instance.client.from('birth_details').insert({
        'child_id': childId,
        'birthdate': birthdateCtrl.text,
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

  Future<void> _confirmDiscardAndPop() async {
    if (!_hasEnteredData) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
            'You have unsaved birth details. Are you sure you want to go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.pop(context);
    }
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Add Child',
          onBack: _confirmDiscardAndPop,
        ),
      ),
      body: SafeArea(
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
                      Center(
                        child: PageTitle(
                          title: 'Birth Information',
                          leadingIcon: Icons.cake_outlined,
                          trailingIcon: Icons.check_circle,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SmallDescription(
                        text: widget.mode == ChildParentMode.registeredMother
                            ? 'Enter the child\'s birth details (Mother: $parentDisplayName)'
                            : 'Enter the child\'s birth details (Guardian: $parentDisplayName)',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
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
                                  hintText: 'Birth Date *',
                                  controller: birthdateCtrl,
                                  isRequired: true,
                                  readOnly: true,
                                  trailingIcon: Icons.calendar_today,
                                  onTrailingTap: _pickBirthdate,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              hintText: 'Birth Weight (kg) *',
                              controller: birthWeightCtrl,
                              isRequired: true,
                              keyboardType: TextInputType.number,
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
                              hintText: 'Birth Length (cm) *',
                              controller: birthLengthCtrl,
                              isRequired: true,
                              keyboardType: TextInputType.number,
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
                              hintText: 'Birth Province *',
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
                              hintText: 'Birth City/Municipality *',
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
                              hintText: 'Birthplace (Hospital/Clinic/Home) *',
                              controller: birthplaceCtrl,
                              isRequired: true,
                              leadingIcon: Icons.location_on_outlined,
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _confirmDiscardAndPop,
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                side: BorderSide(color: AppColors.brandPrimary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: Text(
                                'Back',
                                style: TextStyle(
                                  color: AppColors.brandPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MainButton(
                              label: 'Add Child',
                              onPressed: isFormValid ? _saveChild : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
