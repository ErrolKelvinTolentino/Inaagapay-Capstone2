import '../models/pregnancy_growth_stage.dart';

// Written for a mother reading on her own phone, not for a chart.
//
// Two rules were applied to every line below. First, the words are the ones
// she would use herself: "your baby" rather than "the fetus", "the soft bone
// hardens" rather than "cartilage begins developing into bone", "fine soft
// hair" rather than "lanugo". A term she has to decode is a term she skips,
// and the skipped line is often the one that mattered.
//
// Second, the hedging stays exactly as it was. "May", "commonly" and "around
// this stage" are not padding — they are the difference between describing a
// normal range and telling a particular mother what is true of her pregnancy,
// which this page is in no position to know. Where a line names something she
// should act on, it still points her to her midwife or doctor rather than
// resolving it here.

final CurrentPregnancyState demoCurrentPregnancy = CurrentPregnancyState(
  currentWeek: 20,
  currentMonth: 5,
  estimatedDueDate: DateTime(2026, 12, 8),
  numberOfBabies: 1,
  pregnancyProgress: 0.50,
  trimester: 'Second Trimester',
);

const List<PregnancyGrowthStage> pregnancyGrowthStages = [
  PregnancyGrowthStage(
    month: 1,
    startWeek: 1,
    endWeek: 4,
    trimester: 'First Trimester',
    sizeComparison: 'Poppy seed',
    approximateLength: 'Under 0.5 cm',
    approximateWeight: 'Under 1 g',
    developmentSummary:
        'Pregnancy weeks are counted from your last monthly period, so the first weeks are counted before the baby starts. By the end of this month, a tiny group of cells may settle into your womb and begin to grow.',
    twinDevelopmentSummary:
        'With twins, two tiny groups of cells may be growing. Each one may have its own sac and its own placenta, depending on the kind of twins.',
    developmentHighlights: [
      'The tiny group of cells settles into your womb',
      'The placenta, which will feed your baby, starts to form',
      'The beginnings of the brain and spine appear',
    ],
    motherChanges: [
      'A missed monthly period is often the first sign',
      'You may feel tired, or your breasts may feel sore',
    ],
    healthReminder:
        'Have your pregnancy confirmed at the health center. Ask about folic acid, and show them any medicine you are already taking.',
    imageAsset: 'assets/images/fetal_growth/month_1.png',
  ),
  PregnancyGrowthStage(
    month: 2,
    startWeek: 5,
    endWeek: 8,
    trimester: 'First Trimester',
    sizeComparison: 'Raspberry',
    approximateLength: 'About 1.6 cm',
    approximateWeight: 'About 1 g',
    developmentSummary:
        'Your baby is growing fast. The brain, spine, face and heart are starting to form, and tiny buds that will become the arms and legs begin to show.',
    twinDevelopmentSummary:
        'Both babies are forming their early organs and their tiny arm and leg buds. An ultrasound can show your midwife or doctor what kind of twins they are and how far along you are.',
    developmentHighlights: [
      'The brain and spine keep forming',
      'The heart begins to form and starts beating',
      'Hands, feet, eyes and inner ears begin to take shape',
    ],
    motherChanges: [
      'You may feel sick, go off certain foods, or need to pass urine often',
      'You may feel more tired than usual',
    ],
    healthReminder:
        'Go for your first prenatal check-up. Avoid alcohol and cigarettes, and do not take any medicine your doctor or midwife has not approved.',
    imageAsset: 'assets/images/fetal_growth/month_2.png',
  ),
  PregnancyGrowthStage(
    month: 3,
    startWeek: 9,
    endWeek: 13,
    trimester: 'First Trimester',
    sizeComparison: 'Lime',
    approximateLength: 'About 7.4 cm',
    approximateWeight: 'About 23 g',
    developmentSummary:
        'Your baby now has clearer arms, legs and face. The eyelids and fingernails are forming, and the organs inside are starting to do their work.',
    twinDevelopmentSummary:
        'Both babies keep forming their arms, legs and faces. One may grow a little faster than the other, so your midwife or doctor follows each baby on its own.',
    developmentHighlights: [
      'The soft bone starts to harden into real bone',
      'The kidneys begin making urine',
      'Eyelids and fingernails form',
    ],
    motherChanges: [
      'The sick feeling may start to ease near the end of this month',
      'Your mood or your appetite may still change from day to day',
    ],
    healthReminder:
        'Keep going to your check-ups, and ask your midwife or doctor which tests are right for your pregnancy.',
    imageAsset: 'assets/images/fetal_growth/month_3.png',
  ),
  PregnancyGrowthStage(
    month: 4,
    startWeek: 14,
    endWeek: 17,
    trimester: 'Second Trimester',
    sizeComparison: 'Avocado',
    approximateLength: 'About 14 cm',
    approximateWeight: 'About 100 g',
    developmentSummary:
        'Your baby grows quickly this month. The bones are getting harder, the neck and legs are clearer, and the ears keep forming.',
    twinDevelopmentSummary:
        'Both babies grow quickly this month. Their bones, ears and movements keep developing, and your midwife or doctor watches how each one is growing.',
    developmentHighlights: [
      'The long bones in the arms and legs get harder',
      'Hearing begins to develop',
      'Movements become smoother and more controlled',
    ],
    motherChanges: [
      'You may feel more energy, and your bump may start to show',
      'You may feel hungrier, or feel a mild pulling in your belly',
    ],
    healthReminder:
        'Keep eating balanced meals, take the vitamins you were given, and do gentle activity your midwife or doctor says is safe for you.',
    imageAsset: 'assets/images/fetal_growth/month_4.png',
  ),
  PregnancyGrowthStage(
    month: 5,
    startWeek: 18,
    endWeek: 22,
    trimester: 'Second Trimester',
    sizeComparison: 'Banana',
    approximateLength: 'About 25 cm',
    approximateWeight: 'About 320 g',
    developmentSummary:
        'You can now make out your baby’s face, and the stomach and gut are starting to work. Many mothers begin to feel movement around this time, but it comes earlier for some and later for others.',
    twinDevelopmentSummary:
        'Both babies are becoming more active and their faces are easier to make out. One may move more than the other, and they may not grow at exactly the same rate.',
    developmentHighlights: [
      'The ears, nose and lips are easy to make out',
      'The part of the brain that controls movement is developing',
      'Fine soft hair begins to cover the body',
    ],
    motherChanges: [
      'You may start to feel your baby move — small flutters at first',
      'You may have back pain, leg cramps, or changes in your skin',
    ],
    healthReminder:
        'Go for the ultrasound that checks your baby’s body from head to toe. Tell your midwife or doctor about your baby’s movements, what you are eating, and anything that hurts.',
    imageAsset: 'assets/images/fetal_growth/month_5.png',
  ),
  PregnancyGrowthStage(
    month: 6,
    startWeek: 23,
    endWeek: 27,
    trimester: 'Second Trimester',
    sizeComparison: 'Ear of corn',
    approximateLength: 'About 30 cm',
    approximateWeight: 'About 600 g',
    developmentSummary:
        'Kicks and turns usually get stronger. Your baby is learning to suck, the fingerprints are forming, and fat is starting to build up under the skin.',
    twinDevelopmentSummary:
        'Both babies usually start moving more strongly, and you may begin to tell one from the other. Their sucking, fingerprints and body fat each develop at their own pace.',
    developmentHighlights: [
      'Your baby practises sucking',
      'The prints on the fingers and feet form',
      'Your baby may start to react to sounds',
    ],
    motherChanges: [
      'The movements may feel stronger and come more often',
      'You may have heartburn, swollen feet, or trouble sleeping',
    ],
    healthReminder:
        'Keep every prenatal check-up. Ask your midwife or doctor which changes in movement or in how you feel should make you call them right away.',
    imageAsset: 'assets/images/fetal_growth/month_6.png',
  ),
  PregnancyGrowthStage(
    month: 7,
    startWeek: 28,
    endWeek: 31,
    trimester: 'Third Trimester',
    sizeComparison: 'Eggplant',
    approximateLength: 'About 38 cm',
    approximateWeight: 'About 1.1 kg',
    developmentSummary:
        'Your baby’s brain and nerves are developing fast. The eyes can open and close, your baby may react to loud sounds, and more fat is building up.',
    twinDevelopmentSummary:
        'Both babies keep developing their brains and nerves and adding body fat. With twins, your midwife or doctor may want to check their growth more often.',
    developmentHighlights: [
      'The eyes open and can tell light from dark',
      'The brain and nerves develop quickly',
      'The lungs keep getting ready to breathe air',
    ],
    motherChanges: [
      'You may get short of breath, or find it harder to sleep',
      'You may feel practice tightenings — your womb rehearsing for labour',
    ],
    healthReminder:
        'Ask your midwife or doctor how often to come in from now on, which warning signs to watch for, and how they want you to count your baby’s movements.',
    imageAsset: 'assets/images/fetal_growth/month_7.png',
  ),
  PregnancyGrowthStage(
    month: 8,
    startWeek: 32,
    endWeek: 35,
    trimester: 'Third Trimester',
    sizeComparison: 'Squash',
    approximateLength: 'About 43 cm',
    approximateWeight: 'About 1.9 kg',
    developmentSummary:
        'Your baby keeps adding fat and practising movements like stretching and gripping. The bones are hardening, but the head stays soft so it can pass through during birth.',
    twinDevelopmentSummary:
        'Both babies keep adding fat and practising their movements, now in a tighter space. With twins, your midwife or doctor watches their growth and which way each one is lying.',
    developmentHighlights: [
      'The bones keep getting harder',
      'Your baby stretches and grips',
      'The body looks rounder as more fat builds up',
    ],
    motherChanges: [
      'You may feel more pressure below, pass urine more often, or feel very tired',
      'It may be harder to find a comfortable way to sleep',
    ],
    healthReminder:
        'Start getting ready for the birth, and keep going to your check-ups. Call your midwife or doctor straight away if something worries you or if your baby moves less than usual.',
    imageAsset: 'assets/images/fetal_growth/month_8.png',
  ),
  PregnancyGrowthStage(
    month: 9,
    startWeek: 36,
    endWeek: 40,
    trimester: 'Third Trimester',
    sizeComparison: 'Small watermelon',
    approximateLength: 'About 50 cm',
    approximateWeight: 'About 3.2 kg',
    developmentSummary:
        'Your baby’s lungs, brain and nerves are finishing the last of their growing. Your baby keeps adding fat and may turn to face down, ready to be born.',
    twinDevelopmentSummary:
        'Both babies are finishing the last of their growing and may settle into the position they will be born in. With twins, your midwife or doctor plans the timing and the kind of birth with you.',
    developmentHighlights: [
      'The lungs and nerves finish getting ready',
      'Body fat will help your baby stay warm after birth',
      'Your baby may turn head-down, ready for birth',
    ],
    motherChanges: [
      'The pressure below and the practice tightenings may get stronger',
      'You may feel excited, very tired, or unable to sleep',
    ],
    healthReminder:
        'Go over your birth plan with your midwife or doctor, ask them which signs mean you must go in at once, and keep every check-up until your baby comes.',
    imageAsset: 'assets/images/fetal_growth/month_9.png',
  ),
];
