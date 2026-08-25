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

class ForgotPasswordVerificationScreen extends StatefulWidget {
  const ForgotPasswordVerificationScreen({super.key});

  @override
  State<ForgotPasswordVerificationScreen> createState() =>
      _ForgotPasswordVerificationScreenState();
}

class _ForgotPasswordVerificationScreenState
    extends State<ForgotPasswordVerificationScreen> {
  static const int _initialSeconds = 300;

  late String contact;
  late String channel;
  int _secondsRemaining = _initialSeconds;
  Timer? _timer;

  String _code = '';
  bool _hasError = false;
  bool _isVerifying = false;
  String _errorMessage = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args is Map<String, dynamic>) {
      contact = args['contact'] as String;
      channel = args['channel'] as String;
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
    if (_code.length != 6) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Please enter the 6-digit verification code';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _hasError = false;
      _errorMessage = '';
    });

    final isValid = await SupabaseService.verifyResetCode(contact, _code);

    if (!mounted) return;

    setState(() {
      _isVerifying = false;
      _hasError = !isValid;
      if (!isValid) {
        _errorMessage = 'Invalid or expired code. Please try again.';
      }
    });

    if (isValid) {
      Navigator.pushNamed(
        context,
        '/change-forgot-password',
        arguments: {'contact': contact, 'channel': channel},
      );
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isVerifying = true);

    final result = await SupabaseService.forgotPassword(contact);

    if (!mounted) return;

    setState(() => _isVerifying = false);

    if (result['success'] == true) {
      _startTimer();
      await showDialog(
        context: context,
        builder: (_) => DialogBox(
          type: DialogType.success,
          title: 'Code Sent',
          content: result['message'],
          buttonText: 'OK',
          onPressed: () => Navigator.pop(context),
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (_) => DialogBox(
          type: DialogType.error,
          title: 'Failed',
          content: result['message'] ?? 'Failed to resend code',
          buttonText: 'OK',
          onPressed: () => Navigator.pop(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayContact = channel == 'sms' 
        ? SupabaseService.isValidPhilippineNumber(contact)
            ? SmsService.formatDisplayNumber(contact)
            : contact
        : contact;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        // Centred inside a capped column, and only scrolling when it has to.
        //
        // The page was a bare SingleChildScrollView, so on a tall window
        // everything piled at the top under a fixed 40px gap, and on a wide
        // one the OTP boxes and the button stretched the full width. A code
        // entry screen is six boxes and a button; it should sit in the middle
        // of whatever it is given.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 48,
                maxWidth: 420,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
              // The same logo and wordmark the registration verification
              // screen shows, so the two halves of one flow do not look like
              // two different apps. This was the word "Inaagapay" typed out in
              // bold text beside nothing else.
              Image.asset('assets/images/logo.png', height: 84),
              const SizedBox(height: 10),
              Image.asset(
                'assets/images/inaagapay_name.png',
                width: 180,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 28),

              // Plain pink text, matching every other titled screen. The mail
              // icon is gone with the all-caps: the pill below already says
              // which address the code went to, and says it in a place a
              // person can actually check.
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

              // The address itself, in a pill — if the code never arrives, a
              // typo here is the first thing to rule out, so it should not be
              // the tail of a wrapped sentence.
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
                        displayContact,
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
                    _errorMessage = '';
                  });
                },
                showError: _hasError,
              ),
              
              if (_hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ValidationMessage(
                    message: _errorMessage,
                    type: ValidationType.error,
                  ),
                ),
              
              const SizedBox(height: 28),

              MainButton(
                label: _isVerifying ? 'Verifying...' : 'Verify',
                showIcons: false,
                onPressed: _code.length == 6 && !_isVerifying
                    ? _verifyCode
                    : null,
              ),

              const SizedBox(height: 20),

              // Resending is the action here, so it looks like one once it is
              // available. While the timer runs it is a muted line saying why
              // it is not — the countdown and "Back to Login" used to be the
              // same grey text stacked together, so a dead-end wait and a live
              // way out were indistinguishable.
              if (_isVerifying)
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
                ClickableText(
                  text: 'Resend Code',
                  onTap: _resendCode,
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'You can ask for a new code in $_formattedTime',
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 20),
              const Divider(height: 1, color: AppColors.borderPrimary),
              const SizedBox(height: 8),

              TextButton.icon(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                },
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
                  ],
                ),
              ),
            ),
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