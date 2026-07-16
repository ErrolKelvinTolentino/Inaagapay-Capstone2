import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/main_button.dart';
import '../../widgets/clickable_text.dart';
import '../../widgets/page_title.dart';
import '../../widgets/password_constraints.dart';
import '../../widgets/password_strength_indicator.dart';
import '../../widgets/dialog_box.dart';
import '../../services/supabase_service.dart';
import '../../models/password_strength.dart';

class MotherRegistrationScreen extends StatefulWidget {
  const MotherRegistrationScreen({super.key});

  @override
  State<MotherRegistrationScreen> createState() =>
      _MotherRegistrationScreenState();
}

class _MotherRegistrationScreenState extends State<MotherRegistrationScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _contactExists = false;
  bool _checkingContact = false;
  Timer? _contactTimer;
  String _registrationType = 'email'; // 'email' or 'phone'

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('=== REGISTRATION SCREEN INITIALIZED ===');
    }

    _passwordController.addListener(() => setState(() {}));
    _confirmPasswordController.addListener(() => setState(() {}));
    _contactController.addListener(_onContactChanged);

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _contactTimer?.cancel();
    _contactController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _onContactChanged() {
    _contactTimer?.cancel();
    final contact = _contactController.text.trim();
    
    if (contact.isEmpty) {
      setState(() {
        _contactExists = false;
        _checkingContact = false;
      });
      return;
    }
    
    final isValid = _registrationType == 'email'
        ? RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(contact)
        : SupabaseService.isValidPhilippineNumber(contact);
        
    if (!isValid) {
      setState(() {
        _contactExists = false;
        _checkingContact = false;
      });
      return;
    }
    
    setState(() => _checkingContact = true);
    _contactTimer = Timer(const Duration(milliseconds: 500), () async {
      final exists = _registrationType == 'email'
          ? !(await SupabaseService.isEmailAvailable(contact))
          : !(await SupabaseService.isPhoneNumberAvailable(contact));
          
      if (mounted) {
        setState(() {
          _contactExists = exists;
          _checkingContact = false;
        });
      }
    });
  }

  PasswordStrength _calculateStrength(String password) {
    int met = 0;
    if (password.length >= 8) met++;
    if (RegExp(r'\d').hasMatch(password)) met++;
    if (RegExp(r'[A-Z]').hasMatch(password)) met++;
    if (RegExp(r'[a-z]').hasMatch(password)) met++;

    if (met <= 1) return PasswordStrength.weak;
    if (met <= 3) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  bool get _isContactValid {
    final contact = _contactController.text.trim();
    if (contact.isEmpty) return false;
    return _registrationType == 'email'
        ? RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(contact)
        : SupabaseService.isValidPhilippineNumber(contact);
  }

  bool get _isContactAvailable => !_contactExists && _isContactValid;

  bool get _passwordsMatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _passwordController.text == _confirmPasswordController.text;

  bool get _passwordsDoNotMatch =>
      _confirmPasswordController.text.isNotEmpty && !_passwordsMatch;

  bool get _canSubmit =>
      _isContactAvailable &&
      _calculateStrength(_passwordController.text) == PasswordStrength.strong &&
      _passwordsMatch &&
      !_isLoading &&
      !_checkingContact;

  Future<void> _handleSubmit() async {
    if (!_canSubmit) {
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await SupabaseService.registerWithOTP(
        contact: _contactController.text.trim(),
        password: _passwordController.text,
        channel: _registrationType,
      );

      setState(() => _isLoading = false);
      
      if (!mounted) return;

      if (result['success'] == true) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DialogBox(
            title: 'Verification Code Sent',
            content: 'A 6-digit verification code has been sent to your ${_registrationType == 'email' ? 'email' : 'phone'}.',
            buttonText: 'Continue',
            type: DialogType.success,
            onPressed: () => Navigator.pop(context),
          ),
        );

        if (mounted) {
          Navigator.pushNamed(
            context,
            '/verify-registration',
            arguments: {
              'contact': _contactController.text.trim(),
              'channel': _registrationType,
            },
          );
        }
      } else {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DialogBox(
            type: DialogType.error,
            title: 'Registration Failed',
            content: result['message'] ?? 'Registration failed. Please try again.',
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      
      if (!mounted) return;
      
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DialogBox(
          type: DialogType.error,
          title: 'Error',
          content: 'Error: ${e.toString()}',
          buttonText: 'OK',
          onPressed: () => Navigator.pop(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final password = _passwordController.text;
    final strength = _calculateStrength(password);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),

                    // Logo
                    Image.asset('assets/images/logo.png', height: 100),
                    const SizedBox(height: 12),

                    // App Name
                    Image.asset(
                      'assets/images/inaagapay_name.png',
                      width: 210,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 24),

                    const PageTitle(
                      title: 'Create Account',
                      leadingIcon: Icons.account_circle,
                      trailingIcon: Icons.keyboard_arrow_down,
                      color: AppColors.brandText,
                    ),
                    const SizedBox(height: 24),

                    // Registration Type Toggle
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.bgSecondary,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _registrationType = 'email';
                                  _contactController.clear();
                                  _contactExists = false;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _registrationType == 'email'
                                      ? AppColors.brandPrimary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(26),
                                ),
                                child: Text(
                                  'Email',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _registrationType == 'email'
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontWeight: _registrationType == 'email'
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _registrationType = 'phone';
                                  _contactController.clear();
                                  _contactExists = false;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _registrationType == 'phone'
                                      ? AppColors.brandPrimary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(26),
                                ),
                                child: Text(
                                  'Phone Number',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _registrationType == 'phone'
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontWeight: _registrationType == 'phone'
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Contact Field (Email or Phone)
                    AppInputField(
                      hintText: _registrationType == 'email' 
                          ? 'Enter Email Address' 
                          : 'Enter Mobile Number',
                      controller: _contactController,
                      keyboardType: _registrationType == 'email' 
                          ? TextInputType.emailAddress 
                          : TextInputType.phone,
                      leadingIcon: _registrationType == 'email' 
                          ? Icons.email 
                          : Icons.phone,
                      isRequired: true,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),

                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Builder(
                        builder: (context) {
                          if (_contactController.text.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          if (_checkingContact) {
                            return _infoRow('Checking availability...', isInfo: true);
                          }
                          if (_contactExists) {
                            return _errorRow('${_registrationType == 'email' ? 'Email' : 'Phone number'} already exists');
                          }
                          if (!_isContactValid) {
                            return _errorRow(_registrationType == 'email' 
                                ? 'Enter a valid email address'
                                : 'Enter a valid PH number (e.g., 09123456789)');
                          }
                          return _successRow('${_registrationType == 'email' ? 'Email' : 'Phone number'} is available');
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              Container(
                width: double.infinity,
                color: AppColors.brandSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  children: [
                    // Password
                    AppInputField(
                      hintText: 'Create Password',
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      leadingIcon: Icons.lock,
                      isRequired: true,
                      trailingIcon: _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      onTrailingTap: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),

                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: PasswordStrengthIndicator(strength: strength),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: PasswordConstraints(password: password),
                    ),
                    const SizedBox(height: 20),

                    // Confirm password + shake animation on error
                    AnimatedBuilder(
                      animation: _shakeAnimation,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(_shakeAnimation.value, 0),
                        child: child,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppInputField(
                            hintText: 'Confirm Password',
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            leadingIcon: Icons.lock,
                            isRequired: true,
                            trailingIcon: _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            onTrailingTap: () => setState(
                                () => _obscureConfirmPassword = !_obscureConfirmPassword),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: Builder(
                              builder: (context) {
                                if (_passwordsDoNotMatch) {
                                  return _errorRow('Passwords do not match');
                                }
                                if (_passwordsMatch && _confirmPasswordController.text.isNotEmpty) {
                                  return _successRow('Passwords match');
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),

                    MainButton(
                      label: _isLoading ? 'Creating Account...' : 'Create Account',
                      showIcons: false,
                      onPressed: _canSubmit ? _handleSubmit : null,
                    ),
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Already have an account? ',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        ClickableText(
                          text: 'Sign in Here',
                          onTap: () => Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/login',
                            (route) => false,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'By proceeding, you are acknowledging the',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClickableText(
                          text: 'Terms of Use',
                          fontSize: 11,
                          color: AppColors.brandPrimary,
                          onTap: () {},
                        ),
                        const Text(
                          ' and ',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        ClickableText(
                          text: 'Privacy Policy',
                          fontSize: 11,
                          color: AppColors.brandPrimary,
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorRow(String text) {
    return Row(
      children: [
        const Icon(Icons.cancel, size: 16, color: AppColors.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text, 
            style: const TextStyle(fontSize: 13, color: AppColors.error),
          ),
        ),
      ],
    );
  }

  Widget _successRow(String text) {
    return Row(
      children: [
        const Icon(Icons.check_circle, size: 16, color: AppColors.success),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text, 
            style: const TextStyle(fontSize: 13, color: AppColors.success),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String text, {bool isInfo = true}) {
    return Row(
      children: [
        SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppColors.brandAccent,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text, 
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}