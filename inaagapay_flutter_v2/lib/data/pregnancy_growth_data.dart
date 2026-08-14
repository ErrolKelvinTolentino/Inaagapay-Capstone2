import '../models/pregnancy_growth_stage.dart';

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
        'Pregnancy dating begins before conception. By the end of this stage, a tiny cluster of cells may be implanting and beginning the earliest foundations of development.',
    twinDevelopmentSummary:
        'In a twin pregnancy, two early embryos may be developing. Each may have its own support structures, depending on the type of twin pregnancy.',
    developmentHighlights: [
      'Implantation commonly begins',
      'The earliest placenta structures start forming',
      'Foundations for the brain and spinal cord begin',
    ],
    motherChanges: [
      'A missed period may be the first sign',
      'Tiredness or breast tenderness may begin',
    ],
    healthReminder:
        'Confirm the pregnancy with a health professional and ask about folic acid and medicines you currently take.',
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
        'The embryo is growing quickly. Early brain, spine, facial structures and cardiac tissue are developing, while small limb buds become more noticeable.',
    twinDevelopmentSummary:
        'Both embryos are developing early organs and limb buds. A clinician may use ultrasound to understand the type of twin pregnancy and dating.',
    developmentHighlights: [
      'Brain and spine continue forming',
      'Early cardiac tissue develops',
      'Hands, feet, eyes and inner ears begin taking shape',
    ],
    motherChanges: [
      'Nausea, food aversions or frequent urination may occur',
      'Energy levels may feel lower than usual',
    ],
    healthReminder:
        'Arrange an early prenatal visit and avoid alcohol, smoking and medicines not approved by your doctor or midwife.',
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
        'The fetus now has more defined arms, legs and facial features. Eyelids, fingernails and early organ functions continue to develop.',
    twinDevelopmentSummary:
        'Both fetuses continue forming defined limbs and facial features. Growth can differ slightly, so each fetus is followed individually during care.',
    developmentHighlights: [
      'Cartilage begins developing into bone',
      'Kidneys begin making urine',
      'Eyelids and fingernails form',
    ],
    motherChanges: [
      'Nausea may begin to ease near the end of the trimester',
      'Mood or appetite changes may continue',
    ],
    healthReminder:
        'Keep prenatal appointments and ask which screening tests are appropriate for your pregnancy.',
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
        'Growth becomes more rapid. Bones are hardening, the neck and lower limbs are more defined, and hearing structures continue developing.',
    twinDevelopmentSummary:
        'Both fetuses enter a period of rapid growth. Their bones, hearing structures and movements continue developing, with each growth pattern monitored separately.',
    developmentHighlights: [
      'Long bones begin hardening',
      'Hearing starts to develop',
      'Movement becomes more coordinated',
    ],
    motherChanges: [
      'Energy may improve and the pregnancy may become more visible',
      'A growing appetite or mild stretching sensations may occur',
    ],
    healthReminder:
        'Continue balanced meals, prenatal supplements as prescribed, and gentle activity approved by your care team.',
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
        'Facial features are recognizable and the digestive system is working. Movement may become easier to notice around this stage, though timing differs for every pregnancy.',
    twinDevelopmentSummary:
        'Both fetuses are becoming more active and their facial features are recognizable. Movement patterns and growth may differ between the two.',
    developmentHighlights: [
      'Ears, nose and lips are recognizable',
      'The motor-control area of the brain is developing',
      'Soft lanugo hair begins covering the body',
    ],
    motherChanges: [
      'You may begin feeling movement, commonly called quickening',
      'Backache, leg cramps or skin changes may occur',
    ],
    healthReminder:
        'Attend the recommended anatomy scan and discuss movement, nutrition or discomforts with your doctor or midwife.',
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
        'Kicks and turns commonly grow stronger. The sucking reflex is developing, fingerprints are forming and fat starts building under the skin.',
    twinDevelopmentSummary:
        'Both fetuses commonly show stronger individual movements. Their reflexes, fingerprints and fat stores continue developing at their own rates.',
    developmentHighlights: [
      'Sucking reflex continues developing',
      'Fingerprints and footprints form',
      'Responses to sound may become noticeable',
    ],
    motherChanges: [
      'Movement may feel stronger and more regular',
      'Heartburn, swelling or sleep changes may occur',
    ],
    healthReminder:
        'Keep all prenatal checks and ask your care team what changes in movement or symptoms should prompt a call.',
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
        'The nervous system is developing quickly. The eyes can open and close, the fetus may respond to louder sounds, and more body fat is added.',
    twinDevelopmentSummary:
        'Both fetuses continue maturing their nervous systems and adding body fat. Twin pregnancies may need more frequent growth monitoring.',
    developmentHighlights: [
      'Eyes open and can sense changes in light',
      'The nervous system develops rapidly',
      'Lungs continue preparing for breathing after birth',
    ],
    motherChanges: [
      'Shortness of breath or sleep difficulty may increase',
      'Practice contractions may sometimes be felt',
    ],
    healthReminder:
        'Ask about third-trimester visit frequency, warning signs and how your care team wants you to monitor movement.',
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
        'The fetus continues adding fat and practicing movements such as stretching and grasping. Bones harden while the skull remains flexible.',
    twinDevelopmentSummary:
        'Both fetuses continue adding fat and practicing movements in a more limited space. Position and growth are followed carefully during twin care.',
    developmentHighlights: [
      'Bones continue hardening',
      'Stretching and grasping movements continue',
      'The body becomes rounder as fat increases',
    ],
    motherChanges: [
      'Pelvic pressure, frequent urination or fatigue may increase',
      'Finding a comfortable sleeping position may be harder',
    ],
    healthReminder:
        'Prepare for birth while continuing scheduled care. Contact your care team promptly for concerning symptoms or movement changes.',
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
        'The lungs, brain and nervous system are finishing important development. The fetus continues adding fat and may settle into a birth position.',
    twinDevelopmentSummary:
        'Both fetuses continue final maturation and may settle into their birth positions. The timing and birth plan for twins are individualized by the care team.',
    developmentHighlights: [
      'Lungs and nervous system continue maturing',
      'Body fat helps prepare for temperature control',
      'The fetus may move into a head-down position',
    ],
    motherChanges: [
      'Pelvic pressure and practice contractions may become stronger',
      'Excitement, tiredness or difficulty sleeping may occur',
    ],
    healthReminder:
        'Review the birth plan and urgent warning signs with your doctor or midwife, and keep all late-pregnancy appointments.',
    imageAsset: 'assets/images/fetal_growth/month_9.png',
  ),
];
