// lib/screens/mother/change_password_screen.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/main_button.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/page_title.dart';
import '../../widgets/password_constraints.dart';
import '../../widgets/password_strength_indicator.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_storage.dart';
import '../../models/password_strength.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

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

  Future<void> _handleChangePassword() async {
    if (!_canSubmit) return;

    setState(() => _isLoading = true);

    try {
      final userId = await AuthStorage.getUserId();
      if (userId == null) {
        throw Exception('User not found');
      }

      final success = await SupabaseService.updatePassword(
        userId,
        _newPasswordController.text,
      );

      if (!mounted) return;

      if (success) {
        // Clear the temporary password flag
        await SupabaseService.clearTemporaryPasswordFlag(userId);
        await AuthStorage.saveTemporaryPasswordChanged(true);
        
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password changed successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        
        // Update profile complete status
        await AuthStorage.saveProfileComplete(true);
        
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/mother-dashboard',
          (route) => false,
        );
      } else {
        throw Exception('Failed to change password');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = _calculateStrength(_newPasswordController.text);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              
              // Icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_reset,
                  size: 48,
                  color: AppColors.brandPrimary,
                ),
              ),
              
              const SizedBox(height: 24),
              
              const PageTitle(
                title: 'Change Password',
                leadingIcon: Icons.lock,
              ),
              
              const SizedBox(height: 16),
              
              const Text(
                'Please set a new password for your account.\nThis will be your permanent password.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // New Password
              AppInputField(
                hintText: 'New Password',
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                leadingIcon: Icons.lock_outline,
                isRequired: true,
                trailingIcon: _obscureNewPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                onTrailingTap: () =>
                    setState(() => _obscureNewPassword = !_obscureNewPassword),
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
              
              // Confirm Password
              AppInputField(
                hintText: 'Confirm Password',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                leadingIcon: Icons.lock_outline,
                isRequired: true,
                trailingIcon: _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                onTrailingTap: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
                onChanged: (_) => setState(() {}),
              ),
              
              if (_confirmPasswordController.text.isNotEmpty &&
                  !_passwordsMatch) ...[
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
                label: _isLoading ? 'Changing Password...' : 'Change Password',
                onPressed: _canSubmit ? _handleChangePassword : null,
                leftIcon: Icons.save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
