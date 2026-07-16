// lib/screens/mother/mother_dashboard_shell.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/language_service.dart';
import '../../services/supabase_service.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import 'mother_dashboard.dart';
import 'mother_journal_screen.dart';
import 'mother_children_screen.dart';
import 'records_screen.dart';
import 'mother_self_profile_page.dart';
import 'notifications_screen.dart';
import 'help_support_screen.dart';
import '../../widgets/main_button.dart';

class MotherDashboardShell extends StatefulWidget {
  const MotherDashboardShell({super.key});

  @override
  State<MotherDashboardShell> createState() => _MotherDashboardShellState();
}

class _MotherDashboardShellState extends State<MotherDashboardShell> {
  int _currentIndex = 0;
  String? _profilePictureUrl;
  int? _motherId;
  int _unreadCount = 0;
  RealtimeChannel? _notifChannel;
  String _riskLevel = '';
  List<String> _riskFactors = [];

  final bool _showBHCRequiredDialog = false;
  bool _isOffline = false;
  Timer? _connectivityTimer;

  final List<Widget> _screens = const [
    MotherDashboard(),
    MotherJournalScreen(),
    MotherChildrenScreen(),
    RecordsScreen(),
    _HotlinesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadMotherData();
    _setupNotifications();
    _checkConnectivity();
    // Re-check connectivity every 30 seconds
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectivity(),
    );
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _connectivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    // Skip connectivity check on web (dart:io not available)
    // On mobile, this would use InternetAddress.lookup
    // For now, assume online — Supabase client handles errors gracefully
    if (mounted && _isOffline) setState(() => _isOffline = false);
  }

  Future<void> _setupNotifications() async {
    _notifChannel?.unsubscribe();
    final accountId = await AuthStorage.getUserId();
    if (accountId == null || !mounted) return;

    final motherId = await AuthStorage.getMotherId();
    bool unlinked = false;
    if (motherId != null) {
      final motherResponse = await SupabaseService.client
          .from('mothers')
          .select('assigned_bhc_id')
          .eq('mother_id', motherId)
          .maybeSingle();
      unlinked = motherResponse == null || motherResponse['assigned_bhc_id'] == null;
    }

    final count = await NotificationService.getUnreadCount(accountId);
    if (mounted) {
      setState(() {
        _unreadCount = count + (unlinked ? 1 : 0);
      });
    }

    _notifChannel =
        NotificationService.subscribeToNotifications(accountId, (payload) {
      if (mounted) setState(() => _unreadCount++);
    });
  }

  Future<void> _loadMotherData() async {
    _motherId = await AuthStorage.getMotherId();
    if (_motherId != null) {
      final url = await SupabaseService.getProfilePictureUrl(_motherId!);
      if (mounted) {
        setState(() {
          _profilePictureUrl = url;
        });
      }
    } else {
      _checkAndShowBHCRequiredDialog();
    }
  }

  Future<void> _checkAndShowBHCRequiredDialog() async {
    if (_showBHCRequiredDialog) return;

    final accountId = await AuthStorage.getUserId();
    if (accountId == null) return;

    try {
      final motherResponse = await SupabaseService.client
          .from('mothers')
          .select(
              'mother_id, assigned_bhc_id, pregnancies(status, risk_level, risk_factors)')
          .eq('account_id', accountId)
          .maybeSingle();

      if (motherResponse != null) {
        final motherId = motherResponse['mother_id'] as int;
        await AuthStorage.saveMotherId(motherId);

        String riskLevel = '';
        List<String> riskFactors = [];
        final pregnancies = motherResponse['pregnancies'] as List?;
        if (pregnancies != null && pregnancies.isNotEmpty) {
          final activePregnancy = pregnancies.firstWhere(
            (p) => p['status'] == 'active',
            orElse: () => null,
          );
          if (activePregnancy != null) {
            riskLevel = activePregnancy['risk_level']?.toString() ?? '';
            final rf = activePregnancy['risk_factors']?.toString() ?? '';
            if (rf.isNotEmpty) {
              riskFactors = rf
                  .split(';')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
          }
        }

        setState(() {
          _motherId = motherId;
          _riskLevel = riskLevel;
          _riskFactors = riskFactors;
        });
      }
    } catch (e) {
      debugPrint('Error checking mother record: $e');
    }
  }

  Future<void> _logout() async {
    await PushNotificationService.removeToken();
    await AuthStorage.clearAll();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toUpperCase().trim()) {
      case 'HIGH':
        return AppColors.error;
      case 'MODERATE':
        return AppColors.warning;
      case 'LOW':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }

  void _showRiskSummaryBottomSheet() {
    final badgeColor = _getRiskColor(_riskLevel);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.68,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.shield_outlined,
                            color: badgeColor, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              LanguageService.translate(
                                  'Prenatal Risk Summary', 'Buod ng Panganib'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _riskLevel.toUpperCase(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: badgeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_riskFactors.isNotEmpty) ...[
                    Text(
                      LanguageService.translate(
                          'Risk Factors', 'Mga Salik ng Panganib'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._riskFactors.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Icon(Icons.circle,
                                    size: 8, color: badgeColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  f,
                                  style: const TextStyle(
                                      fontSize: 15, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ] else ...[
                    Text(
                      LanguageService.translate(
                          'No active risk factors detected.',
                          'Walang nakitang aktibong salik ng panganib.'),
                      style: const TextStyle(
                          fontSize: 15, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 32),
                  MainButton(
                    label: LanguageService.translate('Close', 'Isara'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showProfileMenu(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          GestureDetector(
            onTap: () => entry.remove(),
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
          Positioned(
            top: 80,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 220, // ← FIXED: Increased width slightly
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.cardColorOf(context),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // ← FIXED: Use min size
                  children: [
                    _MenuItem(
                      icon: Icons.person_outline,
                      label: LanguageService.translate(
                          'View Profile', 'Tingnan ang Profile'),
                      onTap: () {
                        entry.remove();
                        if (_motherId != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  MotherSelfProfilePage(motherId: _motherId!),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                LanguageService.translate(
                                  'Please complete your account setup with a midwife first.',
                                  'Kumpletuhin muna ang pag-setup ng account kasama ang midwife.',
                                ),
                              ),
                              backgroundColor: AppColors.warning,
                            ),
                          );
                        }
                      },
                    ),
                    if (_riskLevel.isNotEmpty) ...[
                      _MenuItem(
                        icon: Icons.shield_outlined,
                        label: LanguageService.translate(
                            'Risk Summary', 'Buod ng Panganib'),
                        iconColor: _getRiskColor(_riskLevel),
                        onTap: () {
                          entry.remove();
                          _showRiskSummaryBottomSheet();
                        },
                      ),
                    ],
                    _MenuItem(
                      icon: Icons.settings_outlined,
                      label:
                          LanguageService.translate('Settings', 'Mga Setting'),
                      onTap: () {
                        entry.remove();
                        Navigator.pushNamed(context, '/settings');
                      },
                    ),
                    _MenuItem(
                      icon: Icons.help_outline,
                      label: LanguageService.translate('Help', 'Tulong'),
                      onTap: () {
                        entry.remove();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HelpSupportScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.borderPrimary),
                    _MenuItem(
                      icon: Icons.logout_rounded,
                      label: LanguageService.translate('Log out', 'Mag-logout'),
                      isDanger: true,
                      onTap: () {
                        entry.remove();
                        _confirmLogout(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  size: 32,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                LanguageService.translate('Log out', 'Mag-logout'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                LanguageService.translate(
                  'Are you sure you want to log out of your account?',
                  'Sigurado ka bang mag-logout sa iyong account?',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                          LanguageService.translate('Cancel', 'Kanselahin')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _logout();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                          LanguageService.translate('Log out', 'Mag-logout')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, language, _) {
        final titles = [
          LanguageService.translate('HOME', 'Bahay'),
          LanguageService.translate('JOURNAL', 'Journal'),
          LanguageService.translate('CHILDREN', 'Mga Anak'),
          LanguageService.translate('RECORDS', 'Mga Tala'),
          LanguageService.translate('HOTLINES', 'Hotlines'),
        ];

        return Scaffold(
          backgroundColor: AppColors.bgPrimaryOf(context),
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cardColorOf(context),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Image.asset(
                          'assets/images/logo.png',
                          height: 36,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.favorite,
                                  color: AppColors.brandPrimary, size: 30),
                        ),
                      ),
                      Text(
                        titles[_currentIndex],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandText,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationsScreen()),
                          );
                          _setupNotifications();
                        },
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(
                              Icons.notifications_none_rounded,
                              size: 24,
                              color: AppColors.textPrimary,
                            ),
                            if (_unreadCount > 0)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: AppColors.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    _unreadCount > 9 ? '9+' : '$_unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: () => _showProfileMenu(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.brandPrimary,
                            image: _profilePictureUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(_profilePictureUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _profilePictureUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 20,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),

                // Offline banner
                if (_isOffline)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: AppColors.error,
                    child: Row(
                      children: const [
                        Icon(Icons.wifi_off, size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No internet connection — some features may not work.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Content
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: Container(
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.cardColorOf(context),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: LanguageService.translate('Home', 'Bahay'),
                  isActive: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _NavItem(
                  icon: Icons.menu_book_outlined,
                  activeIcon: Icons.menu_book,
                  label: LanguageService.translate('Journal', 'Journal'),
                  isActive: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                _NavItem(
                  icon: Icons.child_care_outlined,
                  activeIcon: Icons.child_care,
                  label: LanguageService.translate('Children', 'Mga Anak'),
                  isActive: _currentIndex == 2,
                  onTap: () => setState(() => _currentIndex = 2),
                ),
                _NavItem(
                  icon: Icons.folder_outlined,
                  activeIcon: Icons.folder,
                  label: LanguageService.translate('Records', 'Mga Tala'),
                  isActive: _currentIndex == 3,
                  onTap: () => setState(() => _currentIndex = 3),
                ),
                _NavItem(
                  icon: Icons.phone_outlined,
                  activeIcon: Icons.phone,
                  label: LanguageService.translate('Hotlines', 'Hotlines'),
                  isActive: _currentIndex == 4,
                  onTap: () => setState(() => _currentIndex = 4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = isActive
        ? AppColors.brandPrimaryOf(context)
        : AppColors.textSecondaryOf(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? activeIcon : icon,
            size: 26,
            color: color,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          if (isActive)
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.brandPrimaryOf(context),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;
  final Color? iconColor;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? AppColors.error : AppColors.textPrimaryOf(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? color),
            const SizedBox(width: 12),
            Expanded(
              // ← FIXED: Added Expanded to prevent overflow
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotlinesScreen extends StatelessWidget {
  const _HotlinesScreen();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LanguageService.translate(
                  'Emergency Hotlines',
                  'Mga Emergency Hotline',
                ),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                LanguageService.translate(
                  'Tap to call the number. Long press to copy to clipboard.',
                  'I-tap para tawagan ang numero. Pindutin nang matagal para kopyahin sa clipboard.',
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 20),
              _HotlineButton(
                label: LanguageService.translate(
                    'National Emergency Hotline', 'Pambansang Emergency Hotline'),
                number: '911',
                icon: Icons.local_hospital,
                color: AppColors.error,
              ),
              const SizedBox(height: 12),
              _HotlineButton(
                label: LanguageService.translate(
                    'DOH Health Hotline', 'DOH Health Hotline'),
                number: '1555',
                icon: Icons.phone,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(height: 12),
              _HotlineButton(
                label: LanguageService.translate(
                    'Philippine Red Cross', 'Philippine Red Cross'),
                number: '143',
                icon: Icons.health_and_safety,
                color: const Color(0xFFD32F2F),
              ),
              const SizedBox(height: 12),
              _HotlineButton(
                label: LanguageService.translate('PNP Emergency', 'PNP Emergency'),
                number: '117',
                icon: Icons.shield,
                color: const Color(0xFF1565C0),
              ),
              const SizedBox(height: 12),
              _HotlineButton(
                label: LanguageService.translate(
                    'Bureau of Fire Protection', 'Bureau of Fire Protection'),
                number: '160',
                icon: Icons.local_fire_department,
                color: const Color(0xFFE65100),
              ),
              const SizedBox(height: 12),
              _HotlineButton(
                label: LanguageService.translate(
                    'Mental Health Crisis Line', 'Mental Health Crisis Line'),
                number: '1553',
                icon: Icons.psychology,
                color: const Color(0xFF7B1FA2),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HotlineButton extends StatelessWidget {
  final String label;
  final String number;
  final IconData icon;
  final Color color;

  const _HotlineButton({
    required this.label,
    required this.number,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final uri = Uri.parse('tel:$number');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(LanguageService.translate(
                      'Could not launch $number',
                      'Hindi mabuksan ang $number')),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          }
        },
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: number));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                LanguageService.translate(
                  '$number copied to clipboard',
                  '$number kinopya sa clipboard',
                ),
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: color,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
