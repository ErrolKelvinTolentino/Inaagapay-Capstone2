// lib/widgets/profile_header_card.dart
// Redesigned profile header with gradient banner and overlapping avatar.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProfileHeaderCard extends StatelessWidget {
  final String fullName;
  final String? email;
  final String? phone;
  final String? profilePictureUrl;

  /// BHC patient number, already formatted (e.g. "INA-004"). Null when the
  /// mother has no number assigned yet — the badge is then hidden rather than
  /// showing a placeholder identifier.
  final String? patientNumber;

  const ProfileHeaderCard({
    super.key,
    required this.fullName,
    this.email,
    this.phone,
    this.profilePictureUrl,
    this.patientNumber,
  });

  @override
  Widget build(BuildContext context) {
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'M';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // ── Gradient banner ──
            Container(
              width: double.infinity,
              height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.brandPrimary,
                    AppColors.brandAccent,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            // ── Card body with overlapping avatar ──
            Container(
              width: double.infinity,
              color: Colors.white,
              child: Transform.translate(
                offset: const Offset(0, -36),
                child: Column(
                  children: [
                    // Avatar
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.brandPrimary,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.brandPrimary.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        image: profilePictureUrl != null &&
                                profilePictureUrl!.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(profilePictureUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: profilePictureUrl == null ||
                              profilePictureUrl!.isEmpty
                          ? Center(
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : null,
                    ),

                    const SizedBox(height: 10),

                    // Name
                    Text(
                      fullName.isNotEmpty ? fullName : 'Unnamed',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // Patient number badge — the key the midwife uses to match
                    // this record to the physical chart, so it sits directly
                    // under the name rather than among the contact chips.
                    if (patientNumber != null && patientNumber!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                AppColors.brandPrimary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          patientNumber!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandPrimary,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Contact row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (phone != null && phone!.isNotEmpty) ...[
                            _ContactChip(
                              icon: Icons.phone_outlined,
                              text: phone!,
                            ),
                            if (email != null &&
                                email!.isNotEmpty &&
                                !email!.endsWith('@inaagapay.internal'))
                              const SizedBox(width: 12),
                          ],
                          if (email != null &&
                              email!.isNotEmpty &&
                              !email!.endsWith('@inaagapay.internal'))
                            _ContactChip(
                              icon: Icons.email_outlined,
                              text: email!,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ContactChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.brandPrimary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
