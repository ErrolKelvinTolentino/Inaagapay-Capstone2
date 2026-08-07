// lib/screens/midwife/add_immunization_choice.dart
//
// Asks the one question that changes everything downstream: was this dose given
// here, or somewhere else?
//
// The two answers want different defaults, different fields and different
// consequences — today's date versus a historical one, an administering midwife
// versus none, and (once wired) a stock deduction versus none. A checkbox
// inside a single form would leave both paths compromised, so the fork happens
// before the form opens.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import 'add_immunization_page.dart';

/// Where a recorded dose was administered.
enum ImmunizationSource {
  /// Given at this barangay health centre. Attributed to the midwife and,
  /// once the inventory link lands, drawn from stock.
  thisBhc,

  /// Given at a hospital, private clinic or another health centre, and
  /// transcribed here so the child's history is complete.
  outside;

  /// Value stored in `immunization_records.source`.
  String get dbValue =>
      this == ImmunizationSource.thisBhc ? 'this_bhc' : 'outside';
}

class AddImmunizationChoicePage extends StatelessWidget {
  final int childId;

  const AddImmunizationChoicePage({super.key, required this.childId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SecondaryHeader(
              title: 'Add Immunization',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Where was this vaccine given?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'A child\'s record should include every dose, wherever it '
                      'was given. This tells the record who administered it.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _ChoiceCard(
                      icon: Icons.local_hospital_outlined,
                      title: 'Given here',
                      subtitle: 'At this barangay health center, by you',
                      detail:
                          'Recorded under your name and counted in this center\'s '
                          'doses administered.',
                      accent: AppColors.brandPrimary,
                      onTap: () => _open(context, ImmunizationSource.thisBhc),
                    ),
                    const SizedBox(height: 14),
                    _ChoiceCard(
                      icon: Icons.assignment_outlined,
                      title: 'Given somewhere else',
                      subtitle:
                          'Hospital, private clinic, or another health center',
                      detail:
                          'Added to the child\'s history for monitoring. No '
                          'midwife here is recorded as having given it.',
                      accent: AppColors.brandAccent,
                      onTap: () => _open(context, ImmunizationSource.outside),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the form and hands its result back to whoever opened this screen.
  ///
  /// Deliberately not pushReplacement: replacing this route completes the
  /// caller's await straight away, with null, before the form has even been
  /// filled in. The child profile therefore never learned that a record had
  /// been added and did not refresh. Pushing and then popping this screen with
  /// the form's result keeps the caller waiting for the real outcome, while the
  /// midwife still never returns to this choice screen.
  Future<void> _open(BuildContext context, ImmunizationSource source) async {
    final navigator = Navigator.of(context);

    final recordAdded = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => AddImmunizationPage(childId: childId, source: source),
      ),
    );

    if (!context.mounted) return;
    navigator.pop(recordAdded);
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final Color accent;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.28), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 24, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: accent),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                detail,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
