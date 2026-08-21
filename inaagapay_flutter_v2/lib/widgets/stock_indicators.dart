// lib/widgets/stock_indicators.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/stock_deduction_outcome.dart';
import 'modal_button.dart';

/// Shared stock affordances for the three screens that draw from facility
/// stock: prenatal supplements, maternal Td, and child immunisation.
///
/// Each screen had grown its own version of the same card, in its own palette —
/// emerald #F0FDF4, amber #FFFBEB, red #FEF2F2 — none of which appear anywhere
/// else in this app. Pink is the app's resting state, so a stock line that is
/// simply *fine* is pink like everything else, and the eye is spent only on the
/// two states that need it: something is short, or something is blocked.
enum StockTone {
  /// Stock is there. The ordinary case, and therefore the brand colour.
  ready,

  /// Usable but wants attention — low, or an open vial nearing its limit.
  caution,

  /// Nothing can be given from here.
  blocked,
}

class _ToneColors {
  const _ToneColors(this.fg, this.bg, this.border);
  final Color fg;
  final Color bg;
  final Color border;
}

_ToneColors _colorsFor(StockTone tone) {
  switch (tone) {
    case StockTone.ready:
      return const _ToneColors(
        AppColors.brandText,
        AppColors.brandSecondary,
        Color(0xFFFBCFE8),
      );
    case StockTone.caution:
      return _ToneColors(
        const Color(0xFF9A5B18),
        AppColors.warning.withValues(alpha: 0.14),
        AppColors.warning.withValues(alpha: 0.45),
      );
    case StockTone.blocked:
      return _ToneColors(
        const Color(0xFF9B3B3B),
        AppColors.error.withValues(alpha: 0.12),
        AppColors.error.withValues(alpha: 0.40),
      );
  }
}

/// A compact "how much is on the shelf" pill, for sitting beside an item name.
class StockLevelChip extends StatelessWidget {
  const StockLevelChip({
    super.key,
    required this.label,
    this.tone = StockTone.ready,
    this.icon,
  });

  /// Builds the chip from a count, choosing its own tone.
  factory StockLevelChip.count({
    Key? key,
    required int available,
    required String unit,
    int? lowThreshold,
  }) {
    final isOut = available <= 0;
    final isLow = !isOut && lowThreshold != null && available <= lowThreshold;
    return StockLevelChip(
      key: key,
      label: isOut ? 'Out of stock' : '$available $unit',
      tone: isOut
          ? StockTone.blocked
          : (isLow ? StockTone.caution : StockTone.ready),
      icon: isOut ? Icons.remove_circle_outline_rounded : null,
    );
  }

  final String label;
  final StockTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = _colorsFor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c.fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: c.fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of stock context above an action: what is on the shelf, and what
/// the next dose will draw from.
///
/// Deliberately one sentence and at most one trailing fact. The screens it
/// replaces were stacking three coloured boxes describing the same batch.
class StockStatusCard extends StatelessWidget {
  const StockStatusCard({
    super.key,
    required this.message,
    this.tone = StockTone.ready,
    this.icon,
    this.trailing,
    this.margin,
  });

  final String message;
  final StockTone tone;
  final IconData? icon;

  /// A short fact that survives being read on its own, e.g. "+3 sealed".
  final String? trailing;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = _colorsFor(tone);
    final resolvedIcon = icon ??
        switch (tone) {
          StockTone.ready => Icons.inventory_2_outlined,
          StockTone.caution => Icons.error_outline_rounded,
          StockTone.blocked => Icons.warning_amber_rounded,
        };

    return Container(
      margin: margin ?? const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(resolvedIcon, size: 16, color: c.fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c.fg,
                height: 1.35,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.fg.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A loading placeholder shaped like [StockStatusCard], so the layout does not
/// jump when the count arrives.
class StockStatusLoading extends StatelessWidget {
  const StockStatusLoading({super.key, this.label = 'Checking stock…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.brandPrimary),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The stock half of a post-save confirmation.
///
/// Rendered under the clinical message so the midwife reads "the record saved"
/// first and "here is what left the shelf" second — and, when stock did not
/// move, sees that in the same glance instead of in a snackbar that has already
/// gone.
class StockOutcomePanel extends StatelessWidget {
  const StockOutcomePanel({super.key, required this.outcome});

  final StockDeductionOutcome outcome;

  StockTone get _tone {
    switch (outcome.level) {
      case StockOutcomeLevel.deducted:
      case StockOutcomeLevel.notApplicable:
        return StockTone.ready;
      case StockOutcomeLevel.partial:
      case StockOutcomeLevel.notDeducted:
        return StockTone.caution;
      case StockOutcomeLevel.failed:
        return StockTone.blocked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colorsFor(_tone);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                outcome.isProblem
                    ? Icons.error_outline_rounded
                    : Icons.inventory_2_outlined,
                size: 15,
                color: c.fg,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  outcome.headline,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: c.fg,
                  ),
                ),
              ),
            ],
          ),
          for (final line in outcome.lines) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, left: 2, right: 6),
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: c.fg.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.fg,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (outcome.advice != null) ...[
            const SizedBox(height: 7),
            Text(
              outcome.advice!,
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: c.fg.withValues(alpha: 0.9),
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Post-save confirmation: the clinical result first, the stock result second.
///
/// Matches [DialogBox]'s shape so it reads as the same family, but keeps the
/// stock detail inside a panel rather than flattening it into one paragraph.
/// The three screens previously reported the same event three ways — a dialog
/// with emoji, a dialog without, and a snackbar — and one of them stayed green
/// when nothing had actually left the shelf.
class StockOutcomeDialog extends StatelessWidget {
  const StockOutcomeDialog({
    super.key,
    required this.title,
    required this.message,
    required this.outcome,
    required this.onPressed,
    this.buttonText = 'OK',
  });

  final String title;

  /// What happened clinically, e.g. "Td2 recorded for Ana Cruz on 21 Aug 2026."
  final String message;

  final StockDeductionOutcome outcome;
  final VoidCallback onPressed;
  final String buttonText;

  Color get _accent {
    switch (outcome.level) {
      case StockOutcomeLevel.failed:
        return AppColors.error;
      case StockOutcomeLevel.partial:
      case StockOutcomeLevel.notDeducted:
        return AppColors.warning;
      case StockOutcomeLevel.deducted:
      case StockOutcomeLevel.notApplicable:
        return AppColors.brandPrimary;
    }
  }

  IconData get _icon {
    switch (outcome.level) {
      case StockOutcomeLevel.failed:
        return Icons.close_rounded;
      case StockOutcomeLevel.partial:
      case StockOutcomeLevel.notDeducted:
        return Icons.warning_amber_rounded;
      case StockOutcomeLevel.deducted:
      case StockOutcomeLevel.notApplicable:
        return Icons.check_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
        decoration: BoxDecoration(
          color: AppColors.faintWhite,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 3),
              ),
              child: Icon(_icon, size: 32, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            // Nothing was dispensed, so there is no stock story to tell.
            if (outcome.lines.isNotEmpty || outcome.advice != null) ...[
              const SizedBox(height: 16),
              StockOutcomePanel(outcome: outcome),
            ],
            const SizedBox(height: 22),
            ModalButton(label: buttonText, onPressed: onPressed),
          ],
        ),
      ),
    );
  }
}
