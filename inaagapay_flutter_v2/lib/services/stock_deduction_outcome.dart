// lib/services/stock_deduction_outcome.dart

import '../widgets/dialog_box.dart';

/// What actually happened to facility stock when a clinical record was saved.
///
/// Three screens deduct stock through three different RPCs — child
/// immunisation, maternal Td, and prenatal supplements — and each used to read
/// its own reply in its own way. The immunisation screen told the midwife
/// exactly what moved; the Td screen showed a plain green success even when the
/// database had replied `mode: no_deduction`; and the prenatal screen swallowed
/// the whole thing into a one-line snackbar, or into `debugPrint` when it threw.
///
/// A midwife who is told "saved" when nothing left the shelf will keep giving
/// doses the system thinks are still there. So every reply now lands here, and
/// every screen says the same kind of thing about it.
enum StockOutcomeLevel {
  /// Stock moved exactly as asked.
  deducted,

  /// Something moved, but less than was recorded as given.
  partial,

  /// The record saved and stock did not move — no batch, no facility, or the
  /// database found nothing to draw from.
  notDeducted,

  /// The deduction call itself failed.
  failed,

  /// There was no facility stock to draw from by design, e.g. a dose given
  /// somewhere else and recorded after the fact.
  notApplicable,
}

class StockDeductionOutcome {
  const StockDeductionOutcome({
    required this.level,
    required this.headline,
    this.lines = const [],
    this.advice,
  });

  final StockOutcomeLevel level;

  /// One short sentence. Goes in a dialog title or a card heading.
  final String headline;

  /// At most a few short facts: what moved, from which batch, what is left.
  /// Kept deliberately short — a midwife reads this between patients.
  final List<String> lines;

  /// What to do about it, present only when there is something to do.
  final String? advice;

  bool get isProblem =>
      level == StockOutcomeLevel.partial ||
      level == StockOutcomeLevel.notDeducted ||
      level == StockOutcomeLevel.failed;

  DialogType get dialogType {
    switch (level) {
      case StockOutcomeLevel.deducted:
        return DialogType.success;
      case StockOutcomeLevel.partial:
      case StockOutcomeLevel.notDeducted:
        return DialogType.warning;
      case StockOutcomeLevel.failed:
        return DialogType.error;
      case StockOutcomeLevel.notApplicable:
        return DialogType.info;
    }
  }

  /// The dialog body: the facts, then the advice, blank line between.
  String get body {
    final buffer = StringBuffer();
    for (final line in lines) {
      buffer.writeln('• $line');
    }
    if (advice != null && advice!.trim().isNotEmpty) {
      if (lines.isNotEmpty) buffer.writeln();
      buffer.write(advice);
    }
    return buffer.toString().trim();
  }

  static const String _reconcileAdvice =
      'Ask your RHU to reconcile the batch, or record the movement in the '
      'inventory module.';

  // ───────────────────────────────────────────────────────── shared parsing

  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _batchLabel(Map res) {
    final number = res['batch_number']?.toString();
    return (number == null || number.isEmpty) ? 'the active batch' : 'Batch #$number';
  }

  static String _doses(int n) => '$n dose${n == 1 ? '' : 's'}';

  /// The vial modes every dose-deducting RPC shares.
  static StockDeductionOutcome? _fromVialMode(Map res, {required String what}) {
    final mode = res['mode']?.toString();
    final batch = _batchLabel(res);
    final left = _asInt(res['doses_left_in_vial']);

    switch (mode) {
      case 'open_vial_dose':
        return StockDeductionOutcome(
          level: StockOutcomeLevel.deducted,
          headline: 'Drawn from the open vial',
          lines: [
            '$what taken from $batch',
            '${_doses(left)} still usable in that vial',
          ],
        );

      case 'new_vial_opened':
        final perUnit = _asInt(res['doses_per_unit']);
        return StockDeductionOutcome(
          level: StockOutcomeLevel.deducted,
          headline: 'New vial opened',
          lines: [
            'Opened a sealed ${perUnit > 0 ? '$perUnit-dose ' : ''}vial from $batch',
            '${_doses(left)} left open for the next patient',
          ],
          advice: left > 0
              ? 'Use them before the vial reaches its shelf-life limit.'
              : null,
        );

      case 'single_dose':
        return StockDeductionOutcome(
          level: StockOutcomeLevel.deducted,
          headline: 'Stock deducted',
          lines: ['1 unit taken from $batch'],
        );

      case 'already_deducted':
        return const StockDeductionOutcome(
          level: StockOutcomeLevel.deducted,
          headline: 'Stock already deducted',
          lines: ['This record had already drawn its dose, so nothing moved twice.'],
        );

      case 'no_deduction':
        return const StockDeductionOutcome(
          level: StockOutcomeLevel.notDeducted,
          headline: 'Saved, but stock did not move',
          lines: ['No usable batch was found at this health center.'],
          advice: _reconcileAdvice,
        );

      case 'outside':
        return const StockDeductionOutcome(
          level: StockOutcomeLevel.notApplicable,
          headline: 'Recorded without deducting stock',
          lines: ['No health center was attached to this record.'],
          advice: 'Check that your account is assigned to a Barangay Health Center.',
        );
    }
    return null;
  }

  // ───────────────────────────────────────────────────── child immunisation

  /// [deduct_immunization_stock].
  factory StockDeductionOutcome.fromImmunization(
    Object? raw, {
    bool givenElsewhere = false,
  }) {
    if (givenElsewhere) {
      return const StockDeductionOutcome(
        level: StockOutcomeLevel.notApplicable,
        headline: 'Recorded as given elsewhere',
        lines: ['No stock was deducted from this health center.'],
      );
    }
    return StockDeductionOutcome._fromDoseRpc(raw, what: '1 dose');
  }

  // ───────────────────────────────────────────────────────────── maternal Td

  /// [administer_maternal_td_dose].
  factory StockDeductionOutcome.fromMaternalTd(Object? raw, {String? doseKey}) {
    return StockDeductionOutcome._fromDoseRpc(
      raw,
      what: doseKey == null ? '1 dose' : '1 $doseKey dose',
    );
  }

  factory StockDeductionOutcome._fromDoseRpc(Object? raw, {required String what}) {
    if (raw == null) {
      return const StockDeductionOutcome(
        level: StockOutcomeLevel.notDeducted,
        headline: 'Saved, stock unconfirmed',
        lines: ['The health center stock could not be confirmed.'],
        advice: 'Check the batch in the inventory module.',
      );
    }

    final res = raw is Map ? raw : const {};

    if (res['success'] == false) {
      final message = (res['error'] ?? res['message'])?.toString();
      return StockDeductionOutcome(
        level: StockOutcomeLevel.failed,
        headline: 'Saved, but stock was not deducted',
        lines: [message?.trim().isNotEmpty == true ? message!.trim() : 'The deduction was rejected.'],
        advice: _reconcileAdvice,
      );
    }

    final byMode = _fromVialMode(res, what: what);
    if (byMode != null) return byMode;

    // A success this file has not been taught to read. Report it plainly rather
    // than claiming a deduction that may not have happened.
    final message = res['message']?.toString();
    return StockDeductionOutcome(
      level: StockOutcomeLevel.deducted,
      headline: 'Stock updated',
      lines: [message?.trim().isNotEmpty == true ? message!.trim() : 'The health center stock was updated.'],
    );
  }

  // ──────────────────────────────────────────────────── prenatal encounter

  /// [deduct_prenatal_encounter_inventory], which reports several movements at
  /// once: the supplements dispensed and, optionally, a maternal Td dose.
  ///
  /// Its `warnings` array is the half that used to be dropped on the floor —
  /// it is where "insufficient stock" lands, and it is the only place a midwife
  /// would learn that the tablets they just handed over were never deducted.
  factory StockDeductionOutcome.fromPrenatalEncounter(
    Object? raw, {
    bool facilityKnown = true,
  }) {
    if (!facilityKnown) {
      return const StockDeductionOutcome(
        level: StockOutcomeLevel.notDeducted,
        headline: 'Checkup saved, stock did not move',
        lines: ['Your account is not assigned to a Barangay Health Center.'],
        advice: 'Ask your RHU to assign one so dispensing can draw from its stock.',
      );
    }

    if (raw == null) {
      return const StockDeductionOutcome(
        level: StockOutcomeLevel.notDeducted,
        headline: 'Checkup saved, stock unconfirmed',
        lines: ['The health center stock could not be confirmed.'],
        advice: 'Check the batches in the inventory module.',
      );
    }

    final res = raw is Map ? raw : const {};

    if (res['success'] == false) {
      final message = (res['error'] ?? res['message'])?.toString();
      return StockDeductionOutcome(
        level: StockOutcomeLevel.failed,
        headline: 'Checkup saved, stock was not deducted',
        lines: [message?.trim().isNotEmpty == true ? message!.trim() : 'The deduction was rejected.'],
        advice: _reconcileAdvice,
      );
    }

    final deductions = (res['deductions'] as List?) ?? const [];
    final warnings = ((res['warnings'] as List?) ?? const [])
        .map((w) => w?.toString().trim() ?? '')
        .where((w) => w.isNotEmpty)
        .toList();

    final lines = <String>[];
    var sawPartial = false;

    for (final entry in deductions) {
      if (entry is! Map) continue;
      final type = entry['item_type']?.toString();

      if (type == 'supplement') {
        final qty = _asInt(entry['quantity']);
        final name = entry['medication']?.toString() ?? 'supplement';
        final note = entry['note']?.toString();
        if (note != null && note.isNotEmpty) {
          sawPartial = true;
          lines.add('$name: only $qty tablet${qty == 1 ? '' : 's'} were in stock');
        } else {
          lines.add('$name: $qty tablet${qty == 1 ? '' : 's'} deducted');
        }
      } else if (type == 'vaccine') {
        final dose = entry['dose']?.toString() ?? 'Td dose';
        final left = _asInt(entry['doses_remaining_in_vial']);
        // 20260823 renamed this mode to match the other RPCs; a database
        // that has not run it yet still answers with the old spelling.
        final mode = entry['mode']?.toString();
        final opened = mode == 'new_vial_opened' || mode == 'new_sealed_vial_opened';
        lines.add(opened
            ? '$dose: new vial opened, ${_doses(left)} left in it'
            : '$dose: drawn from the open vial, ${_doses(left)} left in it');
      }
    }

    lines.addAll(warnings);

    if (lines.isEmpty) {
      // Nothing was dispensed at this visit, so nothing needed to move.
      return const StockDeductionOutcome(
        level: StockOutcomeLevel.notApplicable,
        headline: 'Checkup saved',
        lines: [],
      );
    }

    if (warnings.isNotEmpty || sawPartial) {
      return StockDeductionOutcome(
        level: deductions.isEmpty
            ? StockOutcomeLevel.notDeducted
            : StockOutcomeLevel.partial,
        headline: deductions.isEmpty
            ? 'Checkup saved, stock did not move'
            : 'Checkup saved, stock partly deducted',
        lines: lines,
        advice: 'The record shows what you handed over. Reconcile the shortfall '
            'with your RHU so the stock count matches.',
      );
    }

    return StockDeductionOutcome(
      level: StockOutcomeLevel.deducted,
      headline: 'Checkup saved and stock deducted',
      lines: lines,
    );
  }
}
