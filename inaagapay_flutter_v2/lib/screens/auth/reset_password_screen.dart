// lib/screens/auth/reset_password_screen.dart
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/main_button.dart';
import '../../widgets/page_title.dart';
import '../../widgets/password_constraints.dart';
import '../../widgets/password_strength_indicator.dart';
import '../../widgets/dialog_box.dart';
import '../../services/supabase_service.dart';
import '../../models/password_strength.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  
  late String _email;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args is String) {
      _email = args;
    } else {
      _email = '';
    }
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
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

  bool get _passwordsMatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _newPasswordController.text == _confirmPasswordController.text;

  bool get _canSubmit =>
      _calculateStrength(_newPasswordController.text) == PasswordStrength.strong &&
      _passwordsMatch &&
      !_isLoading;

  Future<void> _handleReset() async {
    if (!_canSubmit) return;
    
    setState(() => _isLoading = true);

    final response = await SupabaseService.resetPasswordWithNew(
      _email,
      _newPasswordController.text,
    );

    if (!mounted) return;
    
    setState(() => _isLoading = false);

    if (response['success'] == true) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DialogBox(
          title: 'Password Reset Successful',
          content: 'Your password has been reset. You can now log in with your new password.',
          buttonText: 'Go to Login',
          type: DialogType.success,
          onPressed: () {
            Navigator.pop(context);
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/login',
              (route) => false,
            );
          },
        ),
      );
    } else {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DialogBox(
          title: 'Reset Failed',
          content: response['message'] ?? 'Failed to reset password. Please try again.',
          buttonText: 'OK',
          type: DialogType.error,
          onPressed: () => Navigator.pop(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = _calculateStrength(_newPasswordController.text);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text(
                'Inaagapay',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF68A5),
                ),
              ),
              const SizedBox(height: 40),
              const PageTitle(
                title: 'New Password',
                leadingIcon: Icons.lock,
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter your new password below',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              AppInputField(
                hintText: 'New Password',
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                leadingIcon: Icons.lock_outline,
                isRequired: true,
                trailingIcon: _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                onTrailingTap: () {
                  setState(() => _obscureNewPassword = !_obscureNewPassword);
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: PasswordStrengthIndicator(strength: strength),
              ),
              const SizedBox(height: 12),
              PasswordConstraints(password: _newPasswordController.text),
              const SizedBox(height: 20),
              AppInputField(
                hintText: 'Confirm Password',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                leadingIcon: Icons.lock_outline,
                isRequired: true,
                trailingIcon: _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                onTrailingTap: () {
                  setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                },
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
              const SizedBox(height: 32),
              MainButton(
                label: _isLoading ? 'Resetting...' : 'Reset Password',
                onPressed: _canSubmit ? _handleReset : null,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                },
                child: const Text(
                  'Back to Login',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}