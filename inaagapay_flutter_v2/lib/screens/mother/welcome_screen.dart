// lib/screens/mother/welcome_screen.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/headline.dart';
import '../../widgets/main_button.dart';
import '../../services/language_service.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Container(
                        height: MediaQuery.of(context).size.height * 0.3,
                        decoration: BoxDecoration(
                          color: AppColors.brandAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.favorite,
                            size: 100,
                            color: AppColors.brandAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Headline(text: 'Welcome, Nanay!'),
                      const SizedBox(height: 16),
                      const Text(
                        'Your pregnancy journey has been set up successfully!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              icon: Icons.calendar_today,
                              title: 'What\'s Next?',
                              description: LanguageService.translate(
                                  'Track your pregnancy journey, get weekly updates, and access health resources.',
                                  'Subaybayan ang iyong pagbubuntis, makatanggap ng lingguhang balita, at magbasa ng gabay sa kalusugan.'),
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              icon: Icons.notifications_active,
                              title: LanguageService.translate(
                                  'Stay Informed', 'Manatiling May Alam'),
                              description: LanguageService.translate(
                                  'Receive timely reminders for checkups and important milestones.',
                                  'Makatanggap ng paalala para sa mga checkup at mahahalagang yugto.'),
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              icon: Icons.health_and_safety,
                              title: LanguageService.translate(
                                  'Health Tracking', 'Pagsubaybay sa Kalusugan'),
                              description: 'Record symptoms, track weight, and monitor your baby\'s development.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              MainButton(
                label: "Go to Dashboard",
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/mother-dashboard',
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.brandAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: AppColors.brandAccent,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}