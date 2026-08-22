import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/main_button.dart';
import '../../widgets/otp_input_field.dart';
import '../../widgets/validation_message.dart';
import '../../widgets/clickable_text.dart';
import '../../widgets/headline.dart';
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

              // The same logo and wordmark the registration screen shows, so
              // the second step of one flow does not look like a different
              // app. This was the word "Inaagapay" typed out in a crimson
              // (0xFFDE3A53) that appears nowhere in the palette — beside the
              // pink logo it read as a different brand entirely.
              Image.asset('assets/images/logo.png', height: 84),
              const SizedBox(height: 10),
              Image.asset(
                'assets/images/inaagapay_name.png',
                width: 180,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 28),

              // Plain pink text, matching every other titled screen. The mail
              // and tick icons are gone: a tick beside "Verify Code" claims the
              // thing that has not happened yet, on the one screen whose whole
              // purpose is that it has not happened yet.
              const Headline(text: 'Verify Code'),
              const SizedBox(height: 10),
              Text(
                'Enter the 6-digit code we sent to your '
                '${channel == 'email' ? 'email' : 'phone'}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),

              // The address itself, in a pill.
              //
              // It was the tail of a wrapped sentence, which is the wrong
              // weight for the one line on this screen a person needs to check
              // — if the code never arrives, a typo here is the first thing to
              // rule out.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.brandSecondary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: AppColors.brandPrimary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      channel == 'email'
                          ? Icons.mail_outline_rounded
                          : Icons.smartphone_rounded,
                      size: 15,
                      color: AppColors.brandPrimary,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _getDisplayContact(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
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
              const SizedBox(height: 28),
              MainButton(
                label: _isVerifying ? 'Verifying...' : 'Verify',
                onPressed: _code.length == 6 && !_isVerifying ? _verifyCode : null,
              ),
              const SizedBox(height: 20),

              // Resending is the action here, so it looks like one once it is
              // available. While the timer runs it is a muted line stating why
              // it is not — previously the countdown and "Back to Login" were
              // the same grey text stacked together, so a dead-end wait and a
              // live escape hatch were indistinguishable.
              if (_isResending)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
                  ),
                )
              else if (_secondsRemaining == 0)
                ClickableText(text: 'Resend Code', onTap: _resendCode)
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'You can ask for a new code in $_formattedTime',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: AppColors.borderPrimary),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/login'),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Back to Login'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  shape: const StadiumBorder(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 24),
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