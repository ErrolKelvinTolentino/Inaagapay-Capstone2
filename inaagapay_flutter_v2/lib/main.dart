import 'package:flutter/material.dart';

import 'screens/midwife_inventory/midwife_inventory_mock_page.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

/// Entry point for the inventory-flow presentation branch.
///
/// The normal authentication and dashboard code remains in the project, but
/// this branch intentionally opens the midwife inventory mock directly so it
/// can be demonstrated with a single `flutter run`.
void main() {
  runApp(const InaagapayInventoryMockApp());
}

class InaagapayInventoryMockApp extends StatelessWidget {
  const InaagapayInventoryMockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inaagapay Inventory',
      theme: AppTheme.lightTheme.copyWith(
        appBarTheme: const AppBarTheme(elevation: 0, centerTitle: true),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          selectedItemColor: AppColors.brandPrimary,
          unselectedItemColor: Colors.grey.shade600,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
        ),
      ),
      home: const MidwifeInventoryMockPage(),
    );
  }
}
