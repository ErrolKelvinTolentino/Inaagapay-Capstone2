import 'package:flutter/material.dart';

import 'screens/baby_book_mockup_page.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InaagapayApp());
}

class InaagapayApp extends StatelessWidget {
  const InaagapayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'InaAgapay Baby Book',
      theme: AppTheme.lightTheme.copyWith(
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      themeMode: ThemeMode.light,
      home: const BabyBookMockupPage(),
    );
  }
}
