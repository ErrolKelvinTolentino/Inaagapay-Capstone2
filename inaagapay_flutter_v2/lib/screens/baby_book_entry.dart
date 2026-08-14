import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import '../theme/app_colors.dart';
import 'baby_book_mockup_page.dart';

/// Resolves the signed-in mother before opening her Baby Book.
///
/// [BabyBookMockupPage] takes a `motherId` and shows the sample pregnancy
/// when given none. That fallback is right for a preview and wrong for a
/// signed-in mother, so this sits in front of the `/baby-book` route and
/// resolves the id first. A session with no mother id is an error worth
/// saying out loud rather than quietly answering with sample data.
class BabyBookEntry extends StatefulWidget {
  const BabyBookEntry({super.key});

  @override
  State<BabyBookEntry> createState() => _BabyBookEntryState();
}

class _BabyBookEntryState extends State<BabyBookEntry> {
  late final Future<int?> _motherId = AuthStorage.getMotherId();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int?>(
      future: _motherId,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.bgPrimary,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final motherId = snapshot.data;
        if (motherId == null) return const _BabyBookUnavailable();

        return BabyBookMockupPage(motherId: motherId);
      },
    );
  }
}

class _BabyBookUnavailable extends StatelessWidget {
  const _BabyBookUnavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 44, color: AppColors.brandPrimary.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              const Text(
                'Your Baby Book is not available right now',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We could not find your record on this device. Please sign in '
                'again, or ask your midwife to check that your account is '
                'linked to your health center.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
