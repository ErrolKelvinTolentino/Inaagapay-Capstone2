import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/main_button.dart';
import '../../widgets/clickable_text.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_storage.dart';
import '../../widgets/validation_message.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/dialog_box.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  String? _getIdentifierType() {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) return null;
    
    // Check if it's an email
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(identifier)) {
      return 'email';
    }
    
    // Check if it's a valid Philippine phone number
    if (SupabaseService.isValidPhilippineNumber(identifier)) {
      return 'phone';
    }
    
    return 'invalid';
  }

  bool get _isIdentifierValid {
    final type = _getIdentifierType();
    return type == 'email' || type == 'phone';
  }

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('=== LOGIN SCREEN INITIALIZED ===');
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();
    
    if (identifier.isEmpty || password.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Please fill in all fields';
      });
      return;
    }

    final identifierType = _getIdentifierType();
    if (identifierType != 'email' && identifierType != 'phone') {
      setState(() {
        _hasError = true;
        _errorMessage = 'Please enter a valid email address or Philippine mobile number (e.g., 09123456789)';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final response = await SupabaseService.login(
        identifier,
        password,
      );

      if (!mounted) {
        setState(() => _isLoading = false);
        return;
      }
      
      setState(() => _isLoading = false);

      if (response['success'] == true && response['token'] != null) {
        await AuthStorage.saveToken(response['token']);
        await AuthStorage.saveUserRole(response['user']['role']);
        await AuthStorage.saveUserId(response['user']['id']);


      try {        await PushNotificationService.initialize();
      } catch (_) {}
        if (response['user']['role'] == 'mother') {
          final motherId = response['user']['mother_id'];
          if (motherId != null) {
            await AuthStorage.saveMotherId(motherId);
          }
          
          final needsPasswordChange = response['user']['needs_password_change'] == true;
          final createdBy = response['user']['created_by'] as String? ?? 'self';
          await AuthStorage.saveTemporaryPasswordChanged(!needsPasswordChange);
          
          if (createdBy == 'midwife') {
            await AuthStorage.saveProfileComplete(true);
            
            if (needsPasswordChange) {
              if (!mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/change-temporary-password',
                (route) => false,
              );
            } else {
              if (!mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/mother-dashboard',
                (route) => false,
              );
            }
          } else {
            final isActuallyComplete = await _checkProfileCompleteness(motherId);
            
            if (!isActuallyComplete) {
              await AuthStorage.saveProfileComplete(false);
              if (!mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/complete-profile',
                (route) => false,
              );
            } else {
              await AuthStorage.saveProfileComplete(true);
              if (!mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/mother-dashboard',
                (route) => false,
              );
            }
          }
        } else if (response['user']['role'] == 'midwife') {
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/midwife-dashboard',
            (route) => false,
          );
        } else if (response['user']['role'] == 'admin') {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (_) => DialogBox(
              type: DialogType.error,
              title: 'Access Denied',
              content: 'Admin accounts must use the administrative web portal.',
              buttonText: 'OK',
              onPressed: () => Navigator.pop(context),
            ),
          );
        } else {
          if (!mounted) return;
          setState(() {
            _hasError = true;
            _errorMessage = 'Unknown user role';
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = response['message'] ?? 'Login failed';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Network error. Please try again.';
      });
    }
  }

  Future<bool> _checkProfileCompleteness(int? motherId) async {
    if (motherId == null) return false;
    
    try {
      final response = await SupabaseService.client
          .from('mothers')
          .select('birthdate')
          .eq('mother_id', motherId)
          .maybeSingle();
      
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) return false;
      
      final accountResponse = await SupabaseService.client
          .from('accounts')
          .select('first_name, last_name, phone_number, created_by')
          .eq('account_id', accountId)
          .maybeSingle();
      
      final hasFirstName = accountResponse != null && 
                           accountResponse['first_name'] != null && 
                           accountResponse['first_name'].toString().isNotEmpty;
      final hasLastName = accountResponse != null && 
                          accountResponse['last_name'] != null && 
                          accountResponse['last_name'].toString().isNotEmpty;
      final hasBirthdate = response != null && response['birthdate'] != null;
      final hasPhone = accountResponse != null && 
                       accountResponse['phone_number'] != null && 
                       accountResponse['phone_number'].toString().isNotEmpty;
      
      return hasFirstName && hasLastName && hasBirthdate && hasPhone;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final identifierType = _getIdentifierType();
    final helperText = identifierType == 'invalid' && _identifierController.text.isNotEmpty
        ? 'Please enter a valid email address or Philippine mobile number'
        : null;

    return Scaffold(
      backgroundColor: AppColors.bgPrimaryOf(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // Logo
              Image.asset('assets/images/logo.png', height: 146),

              const SizedBox(height: 20),

              // App name
              Image.asset(
                'assets/images/inaagapay_name.png',
                width: 282,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 8),

              // Tagline
              Text(
                'Supporting you through every step',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondaryOf(context),
                  fontWeight: FontWeight.w400,
                ),
              ),

              const SizedBox(height: 56),

              // Identifier Field (Email or Phone)
              AppInputField(
                hintText: 'Email or Phone Number',
                controller: _identifierController,
                keyboardType: TextInputType.text,
                leadingIcon: Icons.person_outline,
                onChanged: (_) {
                  setState(() {});
                  if (_hasError) setState(() => _hasError = false);
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

              const SizedBox(height: 20),

              // Password
              AppInputField(
                hintText: 'Password',
                controller: _passwordController,
                obscureText: _obscurePassword,
                leadingIcon: Icons.lock_outline,
                trailingIcon:
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                onTrailingTap: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                onChanged: (_) {
                  if (_hasError) setState(() => _hasError = false);
                },
              ),

              if (_hasError) ...[
                const SizedBox(height: 12),
                ValidationMessage(
                  message: _errorMessage,
                  type: ValidationType.error,
                ),
              ],

              const SizedBox(height: 20),

              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: ClickableText(
                  text: 'Forgot Password?',
                  onTap: () => Navigator.pushNamed(context, '/forgot-password'),
                ),
              ),

              const SizedBox(height: 56),

              // Sign in button
              MainButton(
                label: _isLoading ? 'Signing in...' : 'Sign in',
                showIcons: false,
                onPressed: _isLoading ? null : _handleLogin,
              ),

              const SizedBox(height: 32),

              // Register link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'No account yet? ',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  ClickableText(
                    text: 'Register Here',
                    onTap: () => Navigator.pushNamed(context, '/register'),
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
