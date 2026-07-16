import 'package:flutter/material.dart';
// Change these:
import '../../theme/app_colors.dart';
import '../../widgets/headline.dart';
import '../../widgets/main_button.dart';
import '../../widgets/info_row.dart';
import '../../models/due_date_mode.dart';

class CongratsPage extends StatelessWidget {
  final DueDateMode mode;

  const CongratsPage({super.key, required this.mode});

  bool get isPregnant => mode == DueDateMode.pregnant;

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
                      const SizedBox(height: 32),
                      Container(
                        height: MediaQuery.of(context).size.height * 0.3,
                        decoration: BoxDecoration(
                          color: AppColors.brandAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            isPregnant ? Icons.favorite : Icons.people,
                            size: 100,
                            color: AppColors.brandAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Center(
                        child: Headline(
                          text: isPregnant
                              ? 'Congratulations, Nanay!'
                              : 'Congratulations!',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!isPregnant)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            "You're now supporting someone through their pregnancy journey!",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      const SizedBox(height: 32),
                      const Center(
                        child: Text(
                          'This means...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      InfoRow(
                        icon: Icons.calendar_today,
                        text: const TextSpan(
                          children: [
                            TextSpan(text: 'You are '),
                            TextSpan(
                              text: '12 weeks',
                              style: TextStyle(
                                color: AppColors.brandAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ' pregnant!'),
                          ],
                        ),
                      ),
                      InfoRow(
                        icon: Icons.child_care,
                        text: const TextSpan(
                          children: [
                            TextSpan(text: 'Your baby is expected on '),
                            TextSpan(
                              text: 'October 15, 2026',
                              style: TextStyle(
                                color: AppColors.brandAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: '!'),
                          ],
                        ),
                      ),
                      InfoRow(
                        icon: Icons.hourglass_bottom,
                        text: const TextSpan(
                          children: [
                            TextSpan(text: "You're just "),
                            TextSpan(
                              text: '6 months',
                              style: TextStyle(
                                color: AppColors.brandAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ' away from meeting!'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              MainButton(
                label: isPregnant
                    ? "Let's begin your journey!"
                    : "Let's begin the journey!",
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
}