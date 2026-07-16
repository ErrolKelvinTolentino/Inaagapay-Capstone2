// lib/screens/auth/reset_password_verify_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/main_button.dart';
import '../../widgets/otp_input_field.dart';
import '../../widgets/page_title.dart';
import '../../services/supabase_service.dart';

class ResetPasswordVerifyScreen extends StatefulWidget {
  const ResetPasswordVerifyScreen({super.key});

  @override
  State<ResetPasswordVerifyScreen> createState() =>
      _ResetPasswordVerifyScreenState();
}

class _ResetPasswordVerifyScreenState extends State<ResetPasswordVerifyScreen> {
  static const int _initialSeconds = 300;
  late String email;
  int _secondsRemaining = _initialSeconds;
  Timer? _timer;
  String _code = '';
  bool _isVerifying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    email = ModalRoute.of(context)!.settings.arguments as String;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsRemaining = _initialSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        timer.cancel();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  Future<void> _verifyCode() async {
    setState(() => _isVerifying = true);
    final isValid = await SupabaseService.verifyResetCode(email, _code);
    setState(() => _isVerifying = false);

    if (isValid) {
      Navigator.pushNamed(context, '/reset-password', arguments: email);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Invalid or expired code'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text('Inaagapay',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF68A5))),
              const SizedBox(height: 32),
              const PageTitle(title: 'Verify Code', leadingIcon: Icons.mail),
              const SizedBox(height: 16),
              Text('Enter the 6-digit code sent to\n$email',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 32),
              OtpInputField(onChanged: (value) => _code = value),
              const SizedBox(height: 32),
              MainButton(
                  label: _isVerifying ? 'Verifying...' : 'Verify',
                  onPressed:
                      _code.length == 6 && !_isVerifying ? _verifyCode : null),
              const SizedBox(height: 24),
              if (_secondsRemaining == 0)
                TextButton(
                    onPressed: () => SupabaseService.forgotPassword(email),
                    child: const Text('Resend Code'))
              else
                Text(
                    'Resend Code in ${_secondsRemaining ~/ 60}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
