import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// What a multi-dose vial actually holds right now, stated plainly: how many
/// sealed vials are left, how many doses are already drawn into an open one,
/// and the one number that answers "how much can I give today" -- the total.
///
/// Built for the places a midwife decides whether to break a fresh seal or
/// draw from what is already open: dispensing stock, giving a Td dose,
/// recording a child's immunisation. One white card, the brand's own pink for
/// the figure that matters, laid out as short lines and chips rather than one
/// long sentence -- easy to scan without stopping to read it.
///
/// Single-dose items have nothing to say here; callers should not build this
/// widget for one (`item.isMultiDose` on the inventory catalogue is the
/// existing test) rather than have it render an empty card.
class VialDoseStatus extends StatelessWidget {
  const VialDoseStatus({
    super.key,
    required this.dosesPerUnit,
    required this.sealedUnits,
    required this.openVialDoses,
    this.unitLabel = 'vials',
    this.expiryLabel,
    this.dense = false,
  });

  /// Doses in one sealed unit, e.g. 10 for a 10-dose Td vial.
  final int dosesPerUnit;

  /// Sealed, unopened units still on the shelf.
  final int sealedUnits;

  /// Doses already drawn into the one vial currently open, if any.
  final int openVialDoses;

  /// What a sealed unit is called here -- "vials" for a vaccine, "units" is
  /// also common on the inventory side.
  final String unitLabel;

  /// A short, already-formatted expiry phrase ("Expires Jun 10, 2027"), shown
  /// as a third chip when given. Omit where expiry is shown elsewhere on the
  /// same screen already, so it is not said twice.
  final String? expiryLabel;

  /// A tighter version for a context that already has a lot on screen -- a
  /// list row, say -- rather than a dedicated card. Smaller text, thinner
  /// padding, same information.
  final bool dense;

  int get _totalDoses => openVialDoses + sealedUnits * dosesPerUnit;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      StatusChip(
        icon: Icons.inventory_2_outlined,
        label: '$sealedUnits sealed $unitLabel',
      ),
      if (openVialDoses > 0)
        StatusChip(
          icon: Icons.colorize_rounded,
          label:
              'Open vial: $openVialDoses dose${openVialDoses == 1 ? '' : 's'}',
        ),
      if (expiryLabel != null)
        StatusChip(icon: Icons.event_outlined, label: expiryLabel!),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dense ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(dense ? 11 : 13),
        border:
            Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The one number worth reading first: what can actually be given
          // right now, sealed and open stock combined. Bold and brand-pink
          // because it is the answer, not a supporting fact.
          Row(
            children: [
              Icon(
                Icons.medication_liquid_outlined,
                size: dense ? 14 : 16,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                '$_totalDoses dose${_totalDoses == 1 ? '' : 's'} usable',
                style: TextStyle(
                  fontSize: dense ? 12.5 : 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '• $dosesPerUnit doses/unit',
                style: TextStyle(
                  fontSize: dense ? 10.5 : 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: dense ? 6 : 8),
          // Sealed count, open-vial count, expiry: three separate facts on
          // their own line as chips rather than one run-on sentence, so the
          // eye can pick out just the one it came here for.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: chips,
          ),
        ],
      ),
    );
  }
}

/// A small, muted pill: an icon and a short label. Used wherever a fact
/// deserves its own line rather than being folded into a run-on sentence --
/// batch pickers, stock summaries -- anywhere several short facts sit
/// side by side.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
