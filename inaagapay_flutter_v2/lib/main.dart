import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'services/auth_storage.dart';
import 'services/supabase_service.dart';
import 'screens/auth/login.dart';
import 'screens/auth/mother_registration.dart';
import 'screens/auth/account_verification_registration.dart';
import 'screens/auth/forgot_password.dart';
import 'screens/auth/forgot_password_verification.dart';
import 'screens/auth/change_forgot_password.dart';
import 'screens/mother/complete_profile.dart';
import 'screens/mother/welcome_screen.dart';
import 'screens/mother/mother_dashboard_shell.dart';
import 'screens/mother/mother_profile_page.dart';
import 'screens/mother/change_password_screen.dart';
import 'screens/mother/change_temporary_password.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/midwife/midwife_shell.dart';
import 'screens/midwife/ultrasound_analyzer_screen.dart';
import 'screens/midwife/lab_test_analyzer_screen.dart';
import 'screens/mother/records_screen.dart';
import 'screens/mother/mother_journal_screen.dart';
import 'screens/baby_book_entry.dart';
import 'screens/mother/mother_children_screen.dart';
import 'screens/midwife/midwife_mothers_screen.dart';
import 'screens/midwife/midwife_children_screen.dart';
import 'screens/midwife/midwife_schedules_screen.dart';
import 'screens/midwife/midwife_add_mother_screen.dart';
import 'screens/midwife_inventory/midwife_inventory_page.dart';
import 'screens/settings_screen.dart';
import 'screens/shared/immunization_poster_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      if (kDebugMode) print('✅ Firebase initialized successfully');
    } catch (e) {
      if (kDebugMode) print('⚠️ Firebase init error: $e');
    }
  }

  const fallbackSupabaseUrl = 'https://buvseyqcdacctlupznya.supabase.co';
  const fallbackSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1dnNleXFjZGFjY3RsdXB6bnlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MzE2NTUsImV4cCI6MjA4ODIwNzY1NX0.VPh8ZZFqdeFyb8YuMxllbJJa-nWl4VXNq74o6-Itjjw';

  try {
    await dotenv.load(fileName: ".env");
    if (kDebugMode) print('✅ .env file loaded successfully');
  } catch (e) {
    if (kDebugMode) print('⚠️ Could not load .env: $e');
  }

  final envSupabaseUrl = dotenv.env['SUPABASE_URL']?.trim();
  final envSupabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim();

  final supabaseUrl = (envSupabaseUrl != null && envSupabaseUrl.isNotEmpty)
      ? envSupabaseUrl
      : fallbackSupabaseUrl;
  final supabaseAnonKey =
      (envSupabaseAnonKey != null && envSupabaseAnonKey.isNotEmpty)
          ? envSupabaseAnonKey
          : fallbackSupabaseAnonKey;

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
    if (kDebugMode) print('✅ Supabase initialized successfully');
  } catch (e) {
    if (kDebugMode) print('❌ Supabase init error: $e');
  }

  try {
    await PushNotificationService.initialize();
    if (kDebugMode) print('✅ Push notifications initialized');
  } catch (e) {
    if (kDebugMode) print('⚠️ Push notification init error: $e');
  }

  runApp(const InaagapayApp());
}

class InaagapayApp extends StatefulWidget {
  const InaagapayApp({super.key});

  @override
  State<InaagapayApp> createState() => _InaagapayAppState();
}

/// Call from anywhere to refresh the app theme after dark mode toggle.
void refreshAppTheme() {}

class _InaagapayAppState extends State<InaagapayApp> {
  static _InaagapayAppState? _instance;

  @override
  void initState() {
    super.initState();
    _instance = this;
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
    super.dispose();
  }

  Future<Widget> _determineStartScreen() async {
    final isLoggedIn = await AuthStorage.isLoggedIn();
    if (!isLoggedIn) return const LoginScreen();

    final role = await AuthStorage.getUserRole();

    if (role == 'mother') {
      final profileComplete = await AuthStorage.isProfileComplete();
      final temporaryPasswordAlreadyChanged =
          await AuthStorage.isTemporaryPasswordChanged();
      final motherId = await AuthStorage.getMotherId();
      final accountId = await AuthStorage.getUserId();

      if (kDebugMode) {
        debugPrint('=== STARTUP SCREEN DETERMINATION ===');
        debugPrint('Role: $role');
        debugPrint('profileComplete flag: $profileComplete');
        debugPrint(
            'temporaryPasswordAlreadyChanged flag: $temporaryPasswordAlreadyChanged');
        debugPrint('motherId: $motherId');
        debugPrint('accountId: $accountId');
      }

      if (motherId != null && accountId != null) {
        try {
          final accountResponse = await SupabaseService.client
              .from('accounts')
              .select(
                  'created_by, first_name, last_name, phone_number, is_temporary_password')
              .eq('account_id', accountId)
              .maybeSingle();

          final createdBy = accountResponse?['created_by'] as String? ?? 'self';
          final needsPasswordChange =
              accountResponse?['is_temporary_password'] == true &&
                  !temporaryPasswordAlreadyChanged;

          if (SupabaseService.isMidwifeCreated(
              createdBy: createdBy, accountId: accountId)) {
            if (!profileComplete) {
              await AuthStorage.saveProfileComplete(true);
            }
            if (needsPasswordChange) {
              return const ChangeTemporaryPasswordScreen();
            }
            return const MotherDashboardShell();
          }

          final response = await SupabaseService.client
              .from('mothers')
              .select('birthdate')
              .eq('mother_id', motherId)
              .maybeSingle();

          final hasFirstName = accountResponse?['first_name'] != null &&
              (accountResponse?['first_name']?.toString() ?? '').isNotEmpty;
          final hasLastName = accountResponse?['last_name'] != null &&
              (accountResponse?['last_name']?.toString() ?? '').isNotEmpty;
          final hasBirthdate =
              response != null && response['birthdate'] != null;
          final hasPhone = accountResponse?['phone_number'] != null &&
              (accountResponse?['phone_number']?.toString() ?? '').isNotEmpty;

          final isActuallyComplete =
              hasFirstName && hasLastName && hasBirthdate && hasPhone;

          if (isActuallyComplete && !profileComplete) {
            await AuthStorage.saveProfileComplete(true);
          }

          if (!isActuallyComplete && !profileComplete) {
            return const CompleteProfileScreen();
          }

          if (needsPasswordChange) {
            return const ChangeTemporaryPasswordScreen();
          }

          return const MotherDashboardShell();
        } catch (e) {
          return const MotherDashboardShell();
        }
      }
      return const MotherDashboardShell();
    }

    switch (role) {
      case 'midwife':
        return const MidwifeShell();
      case 'admin':
        return const AdminDashboard();
      default:
        return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _determineStartScreen(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF68A5)),
                ),
              ),
            ),
          );
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Inaagapay',
          theme: AppTheme.lightTheme.copyWith(
            appBarTheme: const AppBarTheme(elevation: 0, centerTitle: true),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              selectedItemColor: AppColors.brandPrimary,
              unselectedItemColor: Colors.grey.shade600,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
            ),
          ),
          themeMode: ThemeMode.light,
          home: snapshot.data ?? const LoginScreen(),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const MotherRegistrationScreen(),
            '/verify-registration': (context) =>
                const AccountVerificationRegistration(),
            '/forgot-password': (context) => const ForgotPasswordScreen(),
            '/forgot-password-verify': (context) =>
                const ForgotPasswordVerificationScreen(),
            '/change-forgot-password': (context) =>
                const ChangeForgotPasswordScreen(),
            '/complete-profile': (context) => const CompleteProfileScreen(),
            '/welcome': (context) => const WelcomeScreen(),
            '/change-password': (context) => const ChangePasswordScreen(),
            '/change-temporary-password': (context) =>
                const ChangeTemporaryPasswordScreen(),
            '/mother-dashboard': (context) => const MotherDashboardShell(),
            '/midwife-dashboard': (context) => const MidwifeShell(),
            '/admin-dashboard': (context) => const AdminDashboard(),
            '/mother-profile': (context) {
              final args = ModalRoute.of(context)!.settings.arguments;
              if (args is int) {
                return MotherProfilePage(motherId: args);
              }
              return const MotherProfilePage(motherId: 0);
            },
            '/mother-records': (context) => const RecordsScreen(),
            '/mother-journal': (context) => const MotherJournalScreen(),
            '/mother-children': (context) => const MotherChildrenScreen(),
            // Resolves the signed-in mother before opening the book, so the
            // sample-pregnancy fallback in BabyBookMockupPage stays a preview
            // path and is never what a real mother is shown.
            '/baby-book': (context) => const BabyBookEntry(),
            '/settings': (context) => const SettingsScreen(),
            '/midwife-mothers': (context) => const MidwifeMothersScreen(),
            '/midwife-children': (context) => const MidwifeChildrenScreen(),
            '/midwife-schedules': (context) => const MidwifeSchedulesScreen(),
            '/midwife-add-mother': (context) => const MidwifeAddMotherScreen(),
            '/midwife-inventory': (context) => const MidwifeInventoryPage(),
            '/immunization-poster': (context) => const ImmunizationPosterScreen(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/ultrasound-analyzer') {
              final args = settings.arguments as Map<String, int>;
              return MaterialPageRoute(
                builder: (_) => UltrasoundAnalyzerScreen(
                  motherId: args['motherId']!,
                  pregnancyId: args['pregnancyId']!,
                ),
              );
            }
            if (settings.name == '/lab-test-analyzer') {
              final args = settings.arguments as Map<String, int>;
              return MaterialPageRoute(
                builder: (_) => LabTestAnalyzerScreen(
                  motherId: args['motherId']!,
                  pregnancyId: args['pregnancyId']!,
                ),
              );
            }
            if (settings.name == '/child-profile') {
              return MaterialPageRoute(
                builder: (_) => const MidwifeChildrenScreen(),
              );
            }
            return null;
          },
        );
      },
    );
  }
}
