import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../services/auth_storage.dart';

// layout
import '../widgets/main_header.dart';

// reusable widgets
import '../widgets/hero_card.dart';
import '../widgets/overview_info.dart';
import '../widgets/midwife_statistics_card.dart';
import '../widgets/midwife_history_card.dart';
import '../widgets/chart_card.dart';

class MidwifeDashboard extends StatelessWidget {
  const MidwifeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔧 TEMP MOCK DATA (backend later)
    const int ferrousGiven = 90;
    const int calciumGiven = 65;
    const int tdDosesGiven = 12;

    const int totalPregnancies = 13;
    const int firstTrimester = 4;
    const int secondTrimester = 5;
    const int thirdTrimester = 4;

    // BHC visits mock data
    final List<double> bhcVisitValues = [5, 7, 6, 8, 9, 4, 3];
    final List<String> bhcVisitDays = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,

      body: Column(
        children: [
          /// 🔝 HEADER
          MainHeader(
            title: 'Home',
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

          /// 🔽 BODY
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  /// 👋 HERO
                  HeroCard(
                    image: const AssetImage('assets/images/midwife.png'),
                    title: 'Welcome, [First Name]! 🌸',
                    subtitle: 'Barangay Sta. Barbara Midwife',
                    showWeekBadge: false,
                    showHeartRow: false,
                  ),

                  const SizedBox(height: 20),

                  /// 📊 QUICK OVERVIEW
                  Row(
                    children: const [
                      Expanded(
                        child: OverviewInfo(
                          value: 12,
                          label: 'Registered\nChildren',
                          icon: Icons.child_care_rounded,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: OverviewInfo(
                          value: 24,
                          label: 'Registered\nMothers',
                          icon: Icons.pregnant_woman,
                        ),
                      ),
                      SizedBox(width: 12),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OverviewInfo(
                          value: ferrousGiven,
                          label: 'Ferrous FA\ngiven',
                          icon: Icons.medication,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OverviewInfo(
                          value: calciumGiven,
                          label: 'Calcium\ngiven',
                          icon: Icons.local_pharmacy,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OverviewInfo(
                          value: tdDosesGiven,
                          label: 'TD Vaccine\ndoses given',
                          icon: Icons.vaccines,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  /// 🤰 ACTIVE PREGNANCIES CARD  ✅ ADDED
                  const MidwifeStatisticsCard(
                    totalPregnancies: totalPregnancies,
                    firstTrimester: firstTrimester,
                    secondTrimester: secondTrimester,
                    thirdTrimester: thirdTrimester,
                  ),

                  const SizedBox(height: 20),

                  const SizedBox(height: 20),

                  /// 🕘 RECENT VISITS
                  MidwifeHistoryCard(
                    visits: const [
                      MidwifeVisitItem(
                        name: 'First Name Last Name',
                        displayId: 'INA-001',
                        visitType: 'Prenatal Check-up',
                        timeLabel: 'Today',
                      ),
                      MidwifeVisitItem(
                        name: 'First Name Last Name',
                        displayId: 'INA-002',
                        visitType: 'Prenatal Check-up',
                        timeLabel: 'Yesterday',
                      ),
                      MidwifeVisitItem(
                        name: 'First Name Last Name',
                        displayId: 'INA-003',
                        visitType: 'Prenatal Check-up',
                        timeLabel: '2 days ago',
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  /// 📈 BHC VISITS CHART  ✅ ADDED
                  ChartCard(
                    title: 'BHC Daily Visits Chart',
                    headerIcon: Icons.show_chart_rounded,
                    values: bhcVisitValues,
                    labels: bhcVisitDays,
                    unit: 'visits',
                    lineColor: AppColors.brandPrimary,
                    startingLabel: 'Lowest',
                    startingValue: '3 visits',
                    latestLabel: 'Highest',
                    latestValue: '9 visits',
                    insightText:
                        'Tuesday had the most prenatal visits this week!',
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
