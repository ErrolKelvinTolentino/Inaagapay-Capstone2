import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/main_button.dart';
import '../../widgets/otp_input_field.dart';
import '../../widgets/validation_message.dart';
import '../../widgets/clickable_text.dart';
import '../../widgets/page_title.dart';
import '../../widgets/dialog_box.dart';
import '../../services/supabase_service.dart';
import '../../services/sms_service.dart';

class AccountVerificationRegistration extends StatefulWidget {
  const AccountVerificationRegistration({super.key});

  @override
  State<AccountVerificationRegistration> createState() => _AccountVerificationRegistrationState();
}

class _AccountVerificationRegistrationState extends State<AccountVerificationRegistration> {
  static const int _initialSeconds = 300;

  late String contact;
  late String channel; // 'email' or 'sms'
  int _secondsRemaining = _initialSeconds;
  Timer? _timer;
  bool _isResending = false;

  String _code = '';
  bool _hasError = false;
  bool _isVerifying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args is Map<String, dynamic>) {
      contact = args['contact'] as String;
      channel = args['channel'] as String;
    } else if (args is String) {
      contact = args;
      channel = 'email';
    } else {
      contact = '';
      channel = 'email';
    }
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

  String get _formattedTime {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _verifyCode() async {
    setState(() {
      _isVerifying = true;
      _hasError = false;
    });

    final success = await SupabaseService.verifyCode(contact, _code);

    if (!mounted) return;

    setState(() {
      _isVerifying = false;
      _hasError = !success;
    });

    if (success) {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DialogBox(
          type: DialogType.success,
          title: 'Verification Successful',
          content: 'Your ${channel == 'email' ? 'email' : 'phone number'} has been verified!',
          buttonText: 'Continue',
          onPressed: () => Navigator.pop(context),
        ),
      );
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _isResending = true;
    });

    final result = await SupabaseService.resendVerificationCode(contact);

    if (!mounted) return;

    setState(() => _isResending = false);

    if (result['success']) {
      _startTimer();
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => DialogBox(
            type: DialogType.success,
            title: 'Code Resent',
            content: result['message'],
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );
      }
    } else {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => DialogBox(
            type: DialogType.error,
            title: 'Failed to Resend',
            content: result['message'],
            buttonText: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        );
      }
    }
  }

  String _getDisplayContact() {
    if (channel == 'sms') {
      if (SupabaseService.isValidPhilippineNumber(contact)) {
        return SmsService.formatDisplayNumber(contact);
      }
      return contact;
    }
    return contact;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              const Text(
                'Inaagapay',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFDE3A53),
                ),
              ),
              const SizedBox(height: 32),
              const PageTitle(title: 'VERIFY CODE', leadingIcon: Icons.mail, trailingIcon: Icons.check),
              const SizedBox(height: 16),
              Text(
                'Enter the 6-digit code sent to your ${channel == 'email' ? 'email' : 'phone'}\n${_getDisplayContact()}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              OtpInputField(
                onChanged: (value) {
                  setState(() {
                    _code = value;
                    _hasError = false;
                  });
                }, 
                showError: _hasError,
              ),
              if (_hasError) const Padding(
                padding: EdgeInsets.only(top: 12),
                child: ValidationMessage(message: 'Incorrect or expired code. Please try again.'),
              ),
              const SizedBox(height: 32),
              MainButton(
                label: _isVerifying ? 'Verifying...' : 'Verify',
                onPressed: _code.length == 6 && !_isVerifying ? _verifyCode : null,
              ),
              const SizedBox(height: 32),
              if (_isResending) 
                const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDE3A53)))
              else if (_secondsRemaining == 0) 
                ClickableText(text: 'Resend Code', onTap: _resendCode)
              else 
                Text('Resend Code in $_formattedTime', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                child: const Text('Back to Login', style: TextStyle(color: AppColors.textSecondary)),
              ),
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