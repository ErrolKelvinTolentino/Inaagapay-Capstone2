import 'dart:async';
import 'package:flutter/material.dart';
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

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _contactExists = false;
  bool _checkingContact = false;
  Timer? _contactTimer;

  @override
  void dispose() {
    _contactTimer?.cancel();
    _contactController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onContactChanged() {
    _contactTimer?.cancel();
    final contact = _contactController.text.trim();
    
    if (contact.isEmpty) {
      setState(() {
        _contactExists = false;
        _checkingContact = false;
        _hasError = false;
        _errorMessage = '';
      });
      return;
    }
    
    final isEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(contact);
    final isPhone = SupabaseService.isValidPhilippineNumber(contact);
    
    if (!isEmail && !isPhone) {
      setState(() {
        _contactExists = false;
        _checkingContact = false;
      });
      return;
    }
    
    setState(() => _checkingContact = true);
    _contactTimer = Timer(const Duration(milliseconds: 500), () async {
      final exists = isEmail
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

  String? _getContactType() {
    final contact = _contactController.text.trim();
    if (contact.isEmpty) return null;
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(contact)) return 'email';
    if (SupabaseService.isValidPhilippineNumber(contact)) return 'phone';
    return 'invalid';
  }

  PasswordStrength _calculateStrength(String password) {
    int met = 0;
    if (password.length >= 8) met++;
    if (RegExp(r'\d').hasMatch(password)) met++;
    if (RegExp(r'[A-Z]').hasMatch(password)) met++;
    if (RegExp(r'[a-z]').hasMatch(password)) met++;
    if (RegExp(r'[!@#\$%^&*]').hasMatch(password)) met++;

    if (met <= 2) return PasswordStrength.weak;
    if (met <= 4) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  bool get _isContactValid {
    final type = _getContactType();
    return type == 'email' || type == 'phone';
  }

  bool get _isContactAvailable => !_contactExists && _isContactValid && _contactController.text.isNotEmpty;

  bool get _passwordsMatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _passwordController.text == _confirmPasswordController.text;

  bool get _canSubmit =>
      _isContactAvailable &&
      _calculateStrength(_passwordController.text) == PasswordStrength.strong &&
      _passwordsMatch &&
      !_isLoading &&
      !_checkingContact;

  Future<void> _handleRegister() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final contactType = _getContactType();
    final channel = contactType == 'email' ? 'email' : 'sms';

    final response = await SupabaseService.registerWithOTP(
      contact: _contactController.text.trim(),
      password: _passwordController.text,
      channel: channel,
    );

    setState(() => _isLoading = false);
    if (!mounted) return;

    if (response['success']) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DialogBox(
          type: DialogType.success,
          title: 'Verification Code Sent',
          content: 'A verification code has been sent to your ${channel == 'email' ? 'email' : 'phone'}.',
          buttonText: 'Continue',
          onPressed: () => Navigator.pop(context),
        ),
      );
      
      Navigator.pushNamed(
        context,
        '/verify-otp',
        arguments: {
          'contact': _contactController.text.trim(),
          'channel': channel,
        },
      );
    } else {
      setState(() {
        _hasError = true;
        _errorMessage = response['message'] ?? 'Registration failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = _calculateStrength(_passwordController.text);
    final contactType = _getContactType();
    
    String? helperText;
    if (_contactController.text.isNotEmpty && contactType == 'invalid') {
      helperText = 'Please enter a valid email address or Philippine mobile number (e.g., 09123456789)';
    }

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
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
              
              // Contact Field (Email or Phone - single field)
              AppInputField(
                hintText: 'Email or Phone Number',
                controller: _contactController,
                keyboardType: TextInputType.text,
                leadingIcon: Icons.person_outline,
                isRequired: true,
                onChanged: (_) {
                  _onContactChanged();
                  setState(() {});
                },
              ),
              
              if (helperText != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    helperText,
                    style: const TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                ),
              ] else if (_contactController.text.isNotEmpty && !_checkingContact && !_contactExists && _isContactValid) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text(
                        contactType == 'email' ? 'Email is available' : 'Phone number is available',
                        style: const TextStyle(fontSize: 12, color: AppColors.success),
                      ),
                    ],
                  ),
                ),
              ] else if (_contactController.text.isNotEmpty && _contactExists) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.cancel, size: 16, color: AppColors.error),
                      const SizedBox(width: 6),
                      Text(
                        contactType == 'email' ? 'Email already exists' : 'Phone number already exists',
                        style: const TextStyle(fontSize: 12, color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ] else if (_contactController.text.isNotEmpty && _checkingContact) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: AppColors.brandAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Checking availability...',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Password
              AppInputField(
                hintText: 'Create Password',
                controller: _passwordController,
                obscureText: _obscurePassword,
                leadingIcon: Icons.lock_outline,
                isRequired: true,
                trailingIcon: _obscurePassword ? Icons.visibility_off : Icons.visibility,
                onTrailingTap: () => setState(() => _obscurePassword = !_obscurePassword),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: PasswordStrengthIndicator(strength: strength),
              ),
              const SizedBox(height: 12),
              PasswordConstraints(password: _passwordController.text),
              const SizedBox(height: 20),
              
              // Confirm Password
              AppInputField(
                hintText: 'Confirm Password',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                leadingIcon: Icons.lock_outline,
                isRequired: true,
                trailingIcon: _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                onTrailingTap: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                onChanged: (_) => setState(() {}),
              ),
              if (_confirmPasswordController.text.isNotEmpty && !_passwordsMatch) ...[
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Text(
                    'Passwords do not match',
                    style: TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                ),
              ],
              
              if (_hasError) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage, style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              MainButton(
                label: _isLoading ? 'Sending Code...' : 'Send Verification Code',
                onPressed: _canSubmit ? _handleRegister : null,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? '),
                  ClickableText(
                    text: 'Sign in Here',
                    onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}