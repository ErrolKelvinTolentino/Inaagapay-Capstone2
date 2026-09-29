import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'language_service.dart';
import 'maternal_td_service.dart';

/// How pressing a Td notice is.
enum TdAlertLevel {
  /// The next dose opens within [MaternalTdAlert.soonWindowDays].
  soon,

  /// The next dose can be given today.
  due,

  /// Due, late in pregnancy, and her baby is not yet protected at birth.
  urgent,
}

/// What a mother should be told about her Td series, if anything.
///
/// The home card, the home banner, the notice in her bell and the badge on it
/// all ask [evaluate], so they cannot disagree about whether a dose is due.
///
/// It only speaks from a successful read. When [MaternalTdStatus.readFailed]
/// is set the answer is "nothing to say", never "unprotected": telling a
/// mother with a full history that her baby is at risk is worse than silence.
@immutable
class MaternalTdAlert {
  const MaternalTdAlert._({
    required this.level,
    required this.doseKey,
    this.opensOn,
  });

  final TdAlertLevel level;

  /// The dose the notice is about, `Td1`..`Td5`.
  final String doseKey;

  /// For [TdAlertLevel.soon], the first day the dose may be given.
  final DateTime? opensOn;

  /// How far ahead of an opening dose she is told about it.
  static const int soonWindowDays = 14;

  /// From this week, a baby not yet protected at birth is urgent: Td2 needs
  /// time to take effect before delivery, and the weeks left are running out.
  static const int urgentFromWeek = 28;

  /// A key per dose and level, for the notice's read state.
  ///
  /// Reading "Td 2 is due" must not also mark "Td 3 is due" read a year later,
  /// and a notice that escalates from due to urgent should reach her again.
  String get noticeType => 'td_${level.name}_$doseKey';

  /// `Td 2`, the way the rest of her screens write it.
  String get doseLabel => 'Td ${doseKey.substring(2)}';

  static String _t(String english, String filipino) =>
      LanguageService.translate(english, filipino);

  String get title {
    switch (level) {
      case TdAlertLevel.urgent:
        return _t('Get your $doseLabel shot before birth',
            'Magpaturok ng $doseLabel bago manganak');
      case TdAlertLevel.due:
        return _t('Your $doseLabel shot is due',
            'Takdang turok na ng $doseLabel');
      case TdAlertLevel.soon:
        return _t('$doseLabel opens soon', 'Malapit na ang $doseLabel');
    }
  }

  String get message {
    switch (level) {
      case TdAlertLevel.urgent:
        return _t(
          'Your baby is not yet protected against tetanus at birth. Visit your health center for your $doseLabel shot as soon as you can.',
          'Hindi pa protektado ang iyong sanggol laban sa tetano pagkapanganak. Pumunta sa health center para sa iyong $doseLabel sa lalong madaling panahon.',
        );
      case TdAlertLevel.due:
        return _t(
          'You can get your $doseLabel (tetanus-diphtheria) shot at your health center now. It protects you and your baby from tetanus.',
          'Maaari ka nang magpaturok ng $doseLabel (tetanus-diphtheria) sa iyong health center. Pinoprotektahan ka nito at ang iyong sanggol laban sa tetano.',
        );
      case TdAlertLevel.soon:
        final on = opensOn == null
            ? ''
            : DateFormat('MMM d, yyyy').format(opensOn!);
        return _t(
          'From $on you can get your $doseLabel shot at your health center.',
          'Simula $on, maaari ka nang magpaturok ng $doseLabel sa iyong health center.',
        );
    }
  }

  /// The notice for [status], or null when there is nothing to tell her.
  ///
  /// [week] is her week of pregnancy, 0 when unknown.
  static MaternalTdAlert? evaluate(
    MaternalTdStatus status, {
    required bool isPregnant,
    int week = 0,
  }) {
    if (status.readFailed) return null;
    final next = status.nextDoseKey;
    if (next == null) return null;

    switch (status.nextAction) {
      case TdNextAction.complete:
        return null;
      case TdNextAction.missingPrevious:
        // An earlier dose has no date, so the next one cannot be timed. That
        // is the midwife's record to fix, not something for her to act on;
        // the home card says so without raising a notice.
        return null;
      case TdNextAction.eligibleNow:
        // Td1 is timed to pregnancy ("as early as possible in pregnancy").
        // Without one, "your first dose is due" would sit on her home page
        // indefinitely, for a dose nobody is asking her to get.
        if (next == 'Td1' && !isPregnant) return null;
        final urgent = isPregnant &&
            week >= urgentFromWeek &&
            !status.isProtectedAtBirth;
        return MaternalTdAlert._(
          level: urgent ? TdAlertLevel.urgent : TdAlertLevel.due,
          doseKey: next,
        );
      case TdNextAction.waiting:
        final days = status.daysUntilEligible;
        if (days <= 0 || days > soonWindowDays) return null;
        return MaternalTdAlert._(
          level: TdAlertLevel.soon,
          doseKey: next,
          opensOn: status.nextEligibleDate,
        );
    }
  }

  /// Her pregnancy week from an ongoing pregnancy's LMP, the way Home counts
  /// it. 0 when there is no pregnancy or no LMP.
  static int weekFromLmp(DateTime? lmp) {
    if (lmp == null) return 0;
    final week = DateTime.now().difference(lmp).inDays ~/ 7;
    return week.clamp(1, 40);
  }

  /// Reads everything [evaluate] needs for one mother.
  ///
  /// For the screens that do not already hold her Td status and pregnancy:
  /// the bell's badge and the notifications list. Null on any failure, for the
  /// reason given on the class.
  static Future<MaternalTdAlert?> loadFor(int motherId) async {
    try {
      final status = await MaternalTdService.fetchStatus(motherId);
      if (status.readFailed) return null;

      final List<dynamic> pregnancies = await Supabase.instance.client
          .from('pregnancies')
          .select('last_menstrual_period')
          .eq('mother_id', motherId)
          .eq('status', 'ongoing')
          .limit(1);
      final isPregnant = pregnancies.isNotEmpty;
      final lmp = isPregnant
          ? DateTime.tryParse(
              (pregnancies.first as Map)['last_menstrual_period']?.toString() ??
                  '')
          : null;

      return evaluate(status, isPregnant: isPregnant, week: weekFromLmp(lmp));
    } catch (e) {
      debugPrint('MaternalTdAlert: could not load: $e');
      return null;
    }
  }
}
