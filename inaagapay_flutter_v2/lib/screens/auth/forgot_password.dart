import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/main_button.dart';
import '../../widgets/page_title.dart';
import '../../widgets/dialog_box.dart';
import '../../services/supabase_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _contactController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  String? _getContactType() {
    final contact = _contactController.text.trim();
    if (contact.isEmpty) return null;
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(contact)) return 'email';
    if (SupabaseService.isValidPhilippineNumber(contact)) return 'phone';
    return 'invalid';
  }

  Future<void> _handleSubmit() async {
    final contact = _contactController.text.trim();
    final contactType = _getContactType();
    
    if (contact.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email address or phone number');
      return;
    }
    
    if (contactType != 'email' && contactType != 'phone') {
      setState(() => _errorMessage = 'Please enter a valid email address or Philippine mobile number (e.g., 09123456789)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await SupabaseService.forgotPassword(contact);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DialogBox(
          type: DialogType.success,
          title: 'Code Sent',
          content: result['message'],
          buttonText: 'Continue',
          onPressed: () => Navigator.pop(context),
        ),
      );
      
      Navigator.pushNamed(
        context,
        '/forgot-password-verify',
        arguments: {
          'contact': contact,
          'channel': result['channel'],
        },
      );
    } else {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DialogBox(
          type: DialogType.error,
          title: 'Failed',
          content: result['message'],
          buttonText: 'OK',
          onPressed: () => Navigator.pop(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactType = _getContactType();
    final helperText = _contactController.text.isNotEmpty && contactType == 'invalid'
        ? 'Please enter a valid email address or Philippine mobile number'
        : null;

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
                title: 'Reset Password',
                leadingIcon: Icons.lock_reset,
              ),
              
              const SizedBox(height: 16),
              
              const Text(
                'Enter your email address or phone number to receive a verification code',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              
              const SizedBox(height: 32),
              
              // Single field for email or phone
              AppInputField(
                hintText: 'Email or Phone Number',
                controller: _contactController,
                keyboardType: TextInputType.text,
                leadingIcon: Icons.person_outline,
                errorText: _errorMessage,
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
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
              ],
              
              const SizedBox(height: 32),
              
              MainButton(
                label: _isLoading ? 'Sending...' : 'Send Reset Code',
                onPressed: _isLoading ? null : _handleSubmit,
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