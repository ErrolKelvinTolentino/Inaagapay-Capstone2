// lib/screens/midwife/add_child_step3_child.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/main_button.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirmation_dialog_box.dart';
import 'add_child_step4_birth.dart';

enum ChildParentMode {
  registeredMother,
  newGuardian,
}

const List<String> _extensionOptions = ['', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'];

class AddChildStep3Child extends StatefulWidget {
  final ChildParentMode mode;
  final int? motherId;  // Optional: only used when mode is registeredMother
  final String? motherFirstName;  // Optional: pre-fill mother info

  /// BHC the registering midwife belongs to. Carried through the wizard so the
  /// child row can be stamped with a facility and receive a NAK number.
  final int? assignedBhcId;

  const AddChildStep3Child({
    super.key,
    required this.mode,
    this.motherId,
    this.motherFirstName,
    this.assignedBhcId,
  });

  @override
  State<AddChildStep3Child> createState() => _AddChildStep3ChildState();
}

class _AddChildStep3ChildState extends State<AddChildStep3Child> {
  final _formKey = GlobalKey<FormState>();

  // Child fields
  final firstNameCtrl = TextEditingController();
  final lastNameCtrl = TextEditingController();
  final middleNameCtrl = TextEditingController();
  String _selectedExtension = '';
  String sex = 'male';

  /// Which select field is currently expanded, if any. A single key keeps only
  /// one open at a time so two option cards can never overlap.
  String? _openDropdownKey;

  // Display text for the read-only select fields. The real values live in
  // _selectedExtension / _guardianSelectedExtension / _guardianRelationship.
  final _extensionDisplayCtrl = TextEditingController(text: 'None');
  final _guardianExtensionDisplayCtrl = TextEditingController(text: 'None');
  final _relationshipDisplayCtrl = TextEditingController(text: 'Guardian');

  // Child validation error state
  String? _firstNameError;
  String? _lastNameError;

  // For REGISTERED MOTHER mode - list of ALL mothers in database
  List<Map<String, dynamic>> _allMothers = [];
  Map<String, dynamic>? _selectedMother;
  bool _loadingMothers = false;
  String _searchQuery = '';
  List<Map<String, dynamic>> _filteredMothers = [];

  // For NEW GUARDIAN mode - guardian details
  final guardianFirstNameCtrl = TextEditingController();
  final guardianLastNameCtrl = TextEditingController();
  final guardianMiddleNameCtrl = TextEditingController();
  String _guardianSelectedExtension = '';
  final guardianPhoneCtrl = TextEditingController();
  final guardianAddressCtrl = TextEditingController();
  String _guardianRelationship = 'Guardian';

  // Guardian validation error state
  String? _guardianFirstNameError;
  String? _guardianLastNameError;
  String? _guardianPhoneError;

  final List<String> _relationshipOptions = [
    'Mother',
    'Father',
    'Guardian',
    'Grandparent',
    'Sibling',
    'Aunt',
    'Uncle',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.mode == ChildParentMode.registeredMother) {
      if (widget.motherId != null) {
        // If motherId is provided, we don't need to load all mothers
        _loadSelectedMother();
      } else {
        _loadAllMothers();
      }
    }
  }

  @override
  void dispose() {
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    middleNameCtrl.dispose();
    guardianFirstNameCtrl.dispose();
    guardianLastNameCtrl.dispose();
    guardianMiddleNameCtrl.dispose();
    guardianPhoneCtrl.dispose();
    guardianAddressCtrl.dispose();
    _extensionDisplayCtrl.dispose();
    _guardianExtensionDisplayCtrl.dispose();
    _relationshipDisplayCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSelectedMother() async {
    if (widget.motherId == null) return;
    
    setState(() => _loadingMothers = true);
    
    try {
      final response = await Supabase.instance.client
          .from('mothers')
          .select('''
            mother_id,
            account_id,
            account:account_id (
              first_name,
              last_name,
              phone_number,
              email_address
            )
          ''')
          .eq('mother_id', widget.motherId!)
          .maybeSingle();
      
      if (response != null) {
        final account = response['account'] as Map<String, dynamic>?;
        final firstName = account?['first_name']?.toString() ?? '';
        final lastName = account?['last_name']?.toString() ?? '';
        
        if (mounted) {
          setState(() {
            _selectedMother = {
              'mother_id': response['mother_id'],
              'account_id': response['account_id'],
              'first_name': firstName,
              'last_name': lastName,
              'display_name': '$firstName $lastName'.trim(),
              'phone_number': account?['phone_number']?.toString() ?? '',
              'email_address': account?['email_address']?.toString() ?? '',
            };
            _loadingMothers = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingMothers = false);
      }
    } catch (e) {
      debugPrint('Error loading selected mother: $e');
      if (mounted) setState(() => _loadingMothers = false);
    }
  }

  Future<void> _loadAllMothers() async {
    setState(() => _loadingMothers = true);

    try {
      final accountsResponse = await Supabase.instance.client
          .from('accounts')
          .select('''
            account_id,
            email_address,
            first_name,
            last_name,
            middle_name,
            extension_name,
            phone_number,
            status,
            is_verified
          ''')
          .eq('account_type', 'mother')
          .eq('is_verified', true)
          .eq('status', 'active');

      if (accountsResponse.isEmpty) {
        if (mounted) {
          setState(() {
            _allMothers = [];
            _filteredMothers = [];
            _loadingMothers = false;
          });
        }
        return;
      }

      final accountIds = accountsResponse.map<int>((a) => a['account_id'] as int).toList();
      
      final mothersResponse = await Supabase.instance.client
          .from('mothers')
          .select('mother_id, account_id')
          .inFilter('account_id', accountIds);

      final motherIdByAccountId = <int, int>{};
      for (var mother in mothersResponse) {
        motherIdByAccountId[mother['account_id'] as int] = mother['mother_id'] as int;
      }

      final List<Map<String, dynamic>> mothers = [];
      for (var account in accountsResponse) {
        final accountId = account['account_id'] as int;
        final motherId = motherIdByAccountId[accountId];
        
        if (motherId != null) {
          final firstName = account['first_name']?.toString() ?? '';
          final lastName = account['last_name']?.toString() ?? '';
          final displayName = '$firstName $lastName'.trim();
          
          mothers.add({
            'mother_id': motherId,
            'account_id': accountId,
            'first_name': firstName,
            'last_name': lastName,
            'middle_name': account['middle_name']?.toString() ?? '',
            'extension_name': account['extension_name']?.toString() ?? '',
            'phone_number': account['phone_number']?.toString() ?? '',
            'email_address': account['email_address']?.toString() ?? '',
            'display_name': displayName.isEmpty ? 'Unknown Mother' : displayName,
          });
        }
      }

      if (mounted) {
        setState(() {
          _allMothers = mothers;
          _filteredMothers = mothers;
          _loadingMothers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading mothers: $e');
      if (mounted) setState(() => _loadingMothers = false);
    }
  }

  void _filterMothers(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredMothers = _allMothers;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredMothers = _allMothers.where((mother) {
          final name = mother['display_name'].toLowerCase();
          final phone = mother['phone_number'].toLowerCase();
          final email = mother['email_address'].toLowerCase();
          return name.contains(lowerQuery) || 
                 phone.contains(lowerQuery) || 
                 email.contains(lowerQuery);
        }).toList();
      }
    });
  }

  void _showMotherSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderPrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Select Registered Mother',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandText,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      '${_filteredMothers.length} mother${_filteredMothers.length != 1 ? 's' : ''} available',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      onChanged: (value) {
                        setModalState(() {
                          _filterMothers(value);
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by name, phone, or email...',
                        prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                                onPressed: () {
                                  setModalState(() {
                                    _searchQuery = '';
                                    _filteredMothers = _allMothers;
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: AppColors.borderPrimary),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: AppColors.borderPrimary),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: AppColors.brandPrimary),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _loadingMothers
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.brandPrimary,
                            ),
                          )
                        : _filteredMothers.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _searchQuery.isEmpty 
                                          ? Icons.person_off 
                                          : Icons.search_off,
                                      size: 48,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _searchQuery.isEmpty
                                          ? 'No registered mothers found'
                                          : 'No matching mothers found',
                                      style: const TextStyle(color: AppColors.textSecondary),
                                    ),
                                    if (_searchQuery.isNotEmpty)
                                      TextButton(
                                        onPressed: () {
                                          setModalState(() {
                                            _searchQuery = '';
                                            _filteredMothers = _allMothers;
                                          });
                                        },
                                        child: const Text('Clear search'),
                                      ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _filteredMothers.length,
                                itemBuilder: (context, index) {
                                  final mother = _filteredMothers[index];
                                  final isSelected = _selectedMother?['mother_id'] == mother['mother_id'];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.1),
                                      child: Text(
                                        mother['first_name'].isNotEmpty 
                                            ? mother['first_name'][0].toUpperCase()
                                            : 'M',
                                        style: TextStyle(
                                          color: AppColors.brandPrimary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      mother['display_name'],
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (mother['phone_number'].isNotEmpty)
                                          Text(
                                            mother['phone_number'],
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        if (mother['email_address'].isNotEmpty)
                                          Text(
                                            mother['email_address'],
                                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                          ),
                                      ],
                                    ),
                                    trailing: isSelected
                                        ? const Icon(Icons.check_circle, color: AppColors.success)
                                        : null,
                                    tileColor: isSelected 
                                        ? AppColors.success.withValues(alpha: 0.05)
                                        : null,
                                    onTap: () {
                                      setState(() {
                                        _selectedMother = mother;
                                      });
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _validateChildFields() {
    setState(() {
      _firstNameError = firstNameCtrl.text.trim().isEmpty
          ? 'First name is required'
          : null;
      _lastNameError = lastNameCtrl.text.trim().isEmpty
          ? 'Last name is required'
          : null;
    });
  }

  void _validateGuardianFields() {
    final phone = guardianPhoneCtrl.text.trim();
    final normalized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final isPhoneValid = RegExp(r'^(\+?63|0)9\d{9}$').hasMatch(normalized);

    setState(() {
      _guardianFirstNameError = guardianFirstNameCtrl.text.trim().isEmpty
          ? 'First name is required'
          : null;
      _guardianLastNameError = guardianLastNameCtrl.text.trim().isEmpty
          ? 'Last name is required'
          : null;
      _guardianPhoneError = phone.isEmpty
          ? 'Phone number is required'
          : (isPhoneValid ? null : 'Enter a valid PH number');
    });
  }

  bool get isFormValid {
    final childValid = firstNameCtrl.text.trim().isNotEmpty &&
        _firstNameError == null &&
        lastNameCtrl.text.trim().isNotEmpty &&
        _lastNameError == null;
    if (!childValid) return false;

    if (widget.mode == ChildParentMode.registeredMother) {
      return _selectedMother != null;
    } else {
      final guardianValid = guardianFirstNameCtrl.text.trim().isNotEmpty &&
          _guardianFirstNameError == null &&
          guardianLastNameCtrl.text.trim().isNotEmpty &&
          _guardianLastNameError == null &&
          guardianPhoneCtrl.text.trim().isNotEmpty &&
          _guardianPhoneError == null;
      return guardianValid;
    }
  }

  String get _selectedMotherName {
    if (_selectedMother == null) return '';
    return _selectedMother!['display_name'] ?? '';
  }

  bool get _hasEnteredData =>
      firstNameCtrl.text.trim().isNotEmpty ||
      lastNameCtrl.text.trim().isNotEmpty ||
      middleNameCtrl.text.trim().isNotEmpty ||
      _selectedMother != null ||
      guardianFirstNameCtrl.text.trim().isNotEmpty ||
      guardianLastNameCtrl.text.trim().isNotEmpty ||
      guardianPhoneCtrl.text.trim().isNotEmpty;

  /// Header back = leave the Add Child flow entirely, in one confirmation,
  /// rather than unwinding a screen at a time back through mother selection.
  Future<void> _confirmDiscardAndExit() async {
    if (!_hasEnteredData) {
      _exitWizard();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialogBox(
        title: 'Discard child details?',
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

  /// Unwinds the Add Child flow back to the children list, which lives in the
  /// midwife shell — the first route on the stack after login.
  void _exitWizard() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final isRegisteredMode = widget.mode == ChildParentMode.registeredMother;

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
            // Step 1 of 2 — matches the Add Mother wizard's progress bar and
            // title/subtitle block.
            const LinearProgressIndicator(
              value: 0.5,
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
                    'Child Information',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isRegisteredMode
                        ? 'Child details and the registered mother to link'
                        : 'Child details and guardian information',
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                if (isRegisteredMode) ...[
                  _buildRegisteredMotherSection(),
                  const SizedBox(height: 24),
                ],

                // Child Information Card
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
                      AppInputField(
                        hintText: 'First Name',
                        controller: firstNameCtrl,
                        isRequired: true,
                        errorText: _firstNameError,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-'’]")),
                          LengthLimitingTextInputFormatter(100),
                        ],
                        onChanged: (_) => _validateChildFields(),
                      ),
                      const SizedBox(height: 16),

                      AppInputField(
                        hintText: 'Last Name',
                        controller: lastNameCtrl,
                        isRequired: true,
                        errorText: _lastNameError,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-'’]")),
                          LengthLimitingTextInputFormatter(100),
                        ],
                        onChanged: (_) => _validateChildFields(),
                      ),
                      const SizedBox(height: 16),

                      AppInputField(
                        hintText: 'Middle Name (Optional)',
                        controller: middleNameCtrl,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-'’]")),
                          LengthLimitingTextInputFormatter(100),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _buildExtensionDropdown(),
                      const SizedBox(height: 16),

                      // Sex Selection
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderPrimary),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sex *',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => setState(() => sex = 'male'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: sex == 'male' 
                                            ? AppColors.brandPrimary.withValues(alpha: 0.1) 
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: sex == 'male' 
                                              ? AppColors.brandPrimary 
                                              : AppColors.borderPrimary,
                                          width: sex == 'male' ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.male,
                                            color: sex == 'male' 
                                                ? AppColors.brandPrimary 
                                                : AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Male',
                                            style: TextStyle(
                                              fontWeight: sex == 'male' ? FontWeight.bold : FontWeight.normal,
                                              color: sex == 'male' 
                                                  ? AppColors.brandPrimary 
                                                  : AppColors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => setState(() => sex = 'female'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: sex == 'female' 
                                            ? AppColors.brandPrimary.withValues(alpha: 0.1) 
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: sex == 'female' 
                                              ? AppColors.brandPrimary 
                                              : AppColors.borderPrimary,
                                          width: sex == 'female' ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.female,
                                            color: sex == 'female' 
                                                ? AppColors.brandPrimary 
                                                : AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Female',
                                            style: TextStyle(
                                              fontWeight: sex == 'female' ? FontWeight.bold : FontWeight.normal,
                                              color: sex == 'female' 
                                                  ? AppColors.brandPrimary 
                                                  : AppColors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
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
                ),

                if (!isRegisteredMode) ...[
                  const SizedBox(height: 24),
                  _buildNewGuardianSection(),
                ],

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
                    // Steps back to mother/guardian selection. Only the header
                    // back abandons the whole registration.
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MainButton(
                    label: 'Next',
                    rightIcon: Icons.arrow_forward_ios_rounded,
                    onPressed: _onNextPressed,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Runs validation and surfaces the errors instead of silently refusing.
  /// Mirrors the Add Mother wizard, where Next is always tappable and tells the
  /// midwife what is missing.
  void _onNextPressed() {
    _validateChildFields();
    if (widget.mode == ChildParentMode.newGuardian) {
      _validateGuardianFields();
    }

    if (!isFormValid) {
      if (widget.mode == ChildParentMode.registeredMother &&
          _selectedMother == null) {
        AppSnackbar.warning(
          context,
          'Select the registered mother before continuing.',
        );
      }
      return;
    }

    _goToBirthDetails();
  }

  void _goToBirthDetails() {
    final isRegisteredMode = widget.mode == ChildParentMode.registeredMother;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddChildStep4Birth(
          mode: widget.mode,
          assignedBhcId: widget.assignedBhcId,
          motherId: isRegisteredMode && _selectedMother != null
              ? _selectedMother!['mother_id'] as int
              : null,
          motherName: isRegisteredMode && _selectedMother != null
              ? _selectedMotherName
              : null,
          firstName: firstNameCtrl.text.trim(),
          lastName: lastNameCtrl.text.trim(),
          middleName: middleNameCtrl.text.trim(),
          extensionName: _selectedExtension,
          sex: sex,
          guardianFirstName:
              !isRegisteredMode ? guardianFirstNameCtrl.text.trim() : null,
          guardianLastName:
              !isRegisteredMode ? guardianLastNameCtrl.text.trim() : null,
          guardianMiddleName:
              !isRegisteredMode ? guardianMiddleNameCtrl.text.trim() : null,
          guardianExtensionName:
              !isRegisteredMode ? _guardianSelectedExtension : null,
          guardianPhone:
              !isRegisteredMode ? guardianPhoneCtrl.text.trim() : null,
          guardianAddress:
              !isRegisteredMode ? guardianAddressCtrl.text.trim() : null,
          guardianRelationship:
              !isRegisteredMode ? _guardianRelationship : null,
        ),
      ),
    );
  }

  /// Select field styled like the rest of the app's forms: a read-only
  /// [AppInputField] that expands into a card of options, matching the Add
  /// Mother wizard instead of Material's default DropdownButton menu.
  ///
  /// [dropdownKey] identifies which field is open, so opening one closes any
  /// other.
  Widget _buildSelectField({
    required String hintText,
    required TextEditingController controller,
    required String dropdownKey,
    required List<String> options,
    required String Function(String) labelFor,
    required ValueChanged<String> onSelected,
  }) {
    final isOpen = _openDropdownKey == dropdownKey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppInputField(
          controller: controller,
          hintText: hintText,
          readOnly: true,
          trailingIcon: isOpen
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          onTap: () => setState(
            () => _openDropdownKey = isOpen ? null : dropdownKey,
          ),
          onTrailingTap: () => setState(
            () => _openDropdownKey = isOpen ? null : dropdownKey,
          ),
        ),
        if (isOpen) ...[
          const SizedBox(height: 4),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, idx) {
                  final option = options[idx];
                  return ListTile(
                    dense: true,
                    title: Text(
                      labelFor(option),
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () => setState(() {
                      controller.text = labelFor(option);
                      _openDropdownKey = null;
                      onSelected(option);
                    }),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExtensionDropdown() {
    return _buildSelectField(
      hintText: 'Extension Name',
      controller: _extensionDisplayCtrl,
      dropdownKey: 'child_extension',
      options: _extensionOptions,
      labelFor: (ext) => ext.isEmpty ? 'None' : ext,
      onSelected: (ext) => _selectedExtension = ext,
    );
  }

  Widget _buildRegisteredMotherSection() {
    // If motherId was provided and we already have selected mother, show info
    if (widget.motherId != null && _selectedMother != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      children: [
                        const TextSpan(text: 'Linked Mother: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: '${_selectedMother!['display_name']}'),
                      ],
                    ),
                  ),
                  if (_selectedMother!['phone_number'] != null && _selectedMother!['phone_number'].isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Phone: ${_selectedMother!['phone_number']}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pregnant_woman, color: AppColors.brandPrimary, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Select Registered Mother',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          GestureDetector(
            onTap: _loadingMothers ? null : _showMotherSelectionSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.borderPrimary),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (_loadingMothers)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandPrimary,
                      ),
                    )
                  else
                    const Icon(Icons.person_outline, color: AppColors.brandPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _loadingMothers
                          ? 'Loading mothers...'
                          : (_selectedMother == null 
                              ? 'Tap to select a mother' 
                              : _selectedMotherName),
                      style: TextStyle(
                        color: _selectedMother == null && !_loadingMothers
                            ? AppColors.textSecondary 
                            : AppColors.textPrimary,
                        fontWeight: _selectedMother == null 
                            ? FontWeight.normal 
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!_loadingMothers)
                    const Icon(Icons.arrow_drop_down, color: AppColors.brandPrimary),
                ],
              ),
            ),
          ),

          if (_selectedMother != null && widget.motherId == null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected: $_selectedMotherName',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (_selectedMother!['phone_number'] != null && _selectedMother!['phone_number'].isNotEmpty)
                          Text(
                            _selectedMother!['phone_number'],
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNewGuardianSection() {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_add, color: AppColors.success, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Guardian Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppInputField(
                  hintText: 'First Name',
                  controller: guardianFirstNameCtrl,
                  isRequired: true,
                  errorText: _guardianFirstNameError,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-'’]")),
                    LengthLimitingTextInputFormatter(100),
                  ],
                  onChanged: (_) => _validateGuardianFields(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppInputField(
                  hintText: 'Last Name',
                  controller: guardianLastNameCtrl,
                  isRequired: true,
                  errorText: _guardianLastNameError,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-'’]")),
                    LengthLimitingTextInputFormatter(100),
                  ],
                  onChanged: (_) => _validateGuardianFields(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          AppInputField(
            hintText: 'Middle Name (Optional)',
            controller: guardianMiddleNameCtrl,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-'’]")),
              LengthLimitingTextInputFormatter(100),
            ],
          ),
          const SizedBox(height: 12),
          
          _buildGuardianExtensionDropdown(),
          const SizedBox(height: 12),
          
          AppInputField(
            hintText: 'Phone Number',
            controller: guardianPhoneCtrl,
            isRequired: true,
            keyboardType: TextInputType.phone,
            errorText: _guardianPhoneError,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
              LengthLimitingTextInputFormatter(12),
            ],
            onChanged: (_) => _validateGuardianFields(),
          ),
          const SizedBox(height: 12),
          
          AppInputField(
            hintText: 'Address',
            controller: guardianAddressCtrl,
          ),
          const SizedBox(height: 12),
          
          _buildRelationshipDropdown(),
          
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.info, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'The guardian\'s information will be kept on file and can be used for future child registrations.',
                    style: TextStyle(fontSize: 12, color: AppColors.info),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuardianExtensionDropdown() {
    return _buildSelectField(
      hintText: 'Extension Name (Optional)',
      controller: _guardianExtensionDisplayCtrl,
      dropdownKey: 'guardian_extension',
      options: _extensionOptions,
      labelFor: (ext) => ext.isEmpty ? 'None' : ext,
      onSelected: (ext) => _guardianSelectedExtension = ext,
    );
  }

  Widget _buildRelationshipDropdown() {
    return _buildSelectField(
      hintText: 'Relationship to Child',
      controller: _relationshipDisplayCtrl,
      dropdownKey: 'guardian_relationship',
      options: _relationshipOptions,
      labelFor: (rel) => rel,
      onSelected: (rel) => _guardianRelationship = rel,
    );
  }
}