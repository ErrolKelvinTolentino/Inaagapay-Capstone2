// lib/screens/midwife/midwife_shell.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/push_notification_service.dart';
import 'midwife_dashboard.dart';
import 'midwife_mothers_screen.dart';
import 'midwife_children_screen.dart';
import 'midwife_schedules_screen.dart';
import '../../widgets/main_header.dart';

class MidwifeShell extends StatefulWidget {
  const MidwifeShell({super.key});

  @override
  State<MidwifeShell> createState() => _MidwifeShellState();
}

class _MidwifeShellState extends State<MidwifeShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    MidwifeDashboard(),
    MidwifeMothersScreen(),
    MidwifeChildrenScreen(),
    MidwifeSchedulesScreen(),
  ];

  final List<String> _titles = [
    'HOME',
    'MOTHERS',
    'CHILDREN',
    'SCHEDULES',
  ];

  Future<void> _logout() async {
    await PushNotificationService.removeToken();
    await AuthStorage.clearAll();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimaryOf(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header is here - only once
            MainHeader(
              title: _titles[_currentIndex],
              onViewProfile: () => Navigator.pushNamed(context, '/profile'),
              onSettings: () => Navigator.pushNamed(context, '/settings'),
              onHelp: () => Navigator.pushNamed(context, '/help'),
              onLogout: _logout,
            ),
            // Screen content
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
              label: 'Home',
              isActive: _currentIndex == 0,
              onTap: () => setState(() => _currentIndex = 0),
            ),
            _NavItem(
              icon: Icons.pregnant_woman_outlined,
              activeIcon: Icons.pregnant_woman,
              label: 'Mothers',
              isActive: _currentIndex == 1,
              onTap: () => setState(() => _currentIndex = 1),
            ),
            _NavItem(
              icon: Icons.child_care_outlined,
              activeIcon: Icons.child_care,
              label: 'Children',
              isActive: _currentIndex == 2,
              onTap: () => setState(() => _currentIndex = 2),
            ),
            _NavItem(
              icon: Icons.calendar_today_outlined,
              activeIcon: Icons.calendar_today,
              label: 'Schedules',
              isActive: _currentIndex == 3,
              onTap: () => setState(() => _currentIndex = 3),
            ),
          ],
        ),
      ),
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
    final Color color =
        isActive ? AppColors.brandPrimaryOf(context) : AppColors.textSecondaryOf(context);

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
