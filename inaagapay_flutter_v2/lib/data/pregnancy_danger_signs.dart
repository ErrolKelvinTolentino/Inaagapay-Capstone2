import 'package:flutter/material.dart';

import '../services/language_service.dart';

/// The signs that mean "go to the health center now".
///
/// These already existed inside `mother_pregnancy_detail_page.dart`, as
/// `_WarningSigns(..., isEmergency: true)` scattered across three trimester
/// blocks and reachable only by tapping a button labelled "More Info". That is
/// the most time-critical content in the app sitting behind the vaguest label
/// in it — a woman bleeding at 2am does not go exploring. Lifting them here
/// lets Home and the Hotlines tab show the same list without copying it.
///
/// Deliberately **not** trimester-specific. A mother in trouble should not
/// have to work out which trimester she is in before she learns what to do,
/// and every sign below is an emergency in any week.
///
/// The source listed near-duplicates separately — "heavy vaginal bleeding"
/// and "bleeding heavier than spotting", "regular contractions before Week 37"
/// and "preterm labor contractions before Week 37". They are merged here: a
/// list you can scan in one breath is worth more than a complete one.
class PregnancyDangerSign {
  const PregnancyDangerSign(this.english, this.filipino, this.icon);

  final String english;
  final String filipino;

  /// Carries the meaning for a mother who reads slowly or not at all. Every
  /// sign has a distinct icon; none repeat.
  final IconData icon;

  String get label => LanguageService.translate(english, filipino);
}

const List<PregnancyDangerSign> pregnancyDangerSigns = [
  PregnancyDangerSign(
    'Heavy bleeding from your private part',
    'Malakas na pagdurugo mula sa ari',
    Icons.water_drop_rounded,
  ),
  PregnancyDangerSign(
    'Severe stomach pain',
    'Matinding pananakit ng tiyan',
    Icons.personal_injury_rounded,
  ),
  PregnancyDangerSign(
    'Fever higher than 38°C',
    'Mataas na lagnat higit sa 38°C',
    Icons.thermostat_rounded,
  ),
  PregnancyDangerSign(
    'Bad headache with blurry eyes',
    'Matinding sakit ng ulo na may malabong paningin',
    Icons.visibility_off_rounded,
  ),
  PregnancyDangerSign(
    'Sudden swelling of face or hands',
    'Biglaang pamamaga ng mukha o kamay',
    Icons.back_hand_rounded,
  ),
  PregnancyDangerSign(
    'Baby has not moved for 12 hours',
    'Hindi gumagalaw ang sanggol ng 12 oras',
    Icons.bedtime_off_rounded,
  ),
  PregnancyDangerSign(
    'Contractions before week 37',
    'Kontraksiyon bago ang linggo 37',
    Icons.timer_rounded,
  ),
  PregnancyDangerSign(
    'Your water breaks',
    'Pumutok ang iyong panubigan',
    Icons.water_rounded,
  ),
];
