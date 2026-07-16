import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/auth_storage.dart';
import '../widgets/main_header.dart';

class MidwifeSchedulesScreen extends StatelessWidget {
  const MidwifeSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Column(
        children: [
          MainHeader(
            title: 'Schedules',
            onViewProfile: () => Navigator.pushNamed(context, '/profile'),
            onSettings: () => Navigator.pushNamed(context, '/settings'),
            onHelp: () => Navigator.pushNamed(context, '/help'),
            onLogout: () async {
              await AuthStorage.clearAll();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              }
            },
          ),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 72,
                    color: AppColors.brandPrimary,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Schedules',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Coming soon',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
