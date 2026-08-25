// lib/screens/mother/pregnancy_detail_page.dart
//
// "More Info" page — personalized pregnancy companion
// Opened from MotherDashboard when the user taps "More Info"
// Connects to Supabase for risk assessments, symptoms, and personalized data

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/language_service.dart';
import '../../data/pregnancy_growth_data.dart';
import '../../models/baby_growth_milestone.dart';
import '../../models/milestone_template.dart';
import '../../models/pregnancy_growth_stage.dart';
import '../../services/baby_book_repository.dart';
import '../../services/supabase_service.dart';
import '../../widgets/baby_book/baby_growth_milestones_section.dart';
import '../../services/auth_storage.dart';
import '../../services/asset_pdf_download_service.dart';
import '../../widgets/baby_book/references_panel.dart';
import 'package:flutter/foundation.dart';
import '../../widgets/pregnancy_growth_journey.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================
// DATA MODELS (moved to separate file in production)
// ============================================

class _TrimesterData {
  final String name;
  final String weeks;
  final IconData icon;
  final String headline;
  final String summary;
  final List<String> babyDevelopment;
  final List<String> motherChanges;
  final List<_Symptom> commonSymptoms;
  final List<_NutritionTip> nutritionTips;
  final List<_WarningSigns> warningSigns;
  final List<String> medicalVisits;
  final String emotionalNote;

  _TrimesterData({
    required this.name,
    required this.weeks,
    required this.icon,
    required this.headline,
    required this.summary,
    required this.babyDevelopment,
    required this.motherChanges,
    required this.commonSymptoms,
    required this.nutritionTips,
    required this.warningSigns,
    required this.medicalVisits,
    required this.emotionalNote,
  });
}

class _Symptom {
  final String name;
  final String tip;
  final IconData icon;
  const _Symptom(this.name, this.tip, this.icon);
}


class _NutritionTip {
  final String food;
  final String benefit;
  final IconData icon;
  _NutritionTip(this.food, this.benefit, this.icon);
}

class _WarningSigns {
  final String sign;
  final bool isEmergency;
  const _WarningSigns(this.sign, {this.isEmergency = false});
}

// ============================================
// STATIC CONTENT (Trimesters 1-3)
// ============================================

final _trimesterContent = [
  _TrimesterData(
    name: 'First Trimester',
    weeks: 'Weeks 1 – 13',
    icon: Icons.spa_outlined,
    headline: 'Your baby is just beginning!',
    summary:
        'The first trimester is a time of incredible transformation. Your body is working overtime to build a life, and your baby grows from a single cell into a fully formed tiny human with a heartbeat.',
    babyDevelopment: [
      'Week 4 – Embryo implants; neural tube begins forming',
      'Week 6 – Heart starts beating',
      'Week 8 – All major organs are forming; fingers and toes appear',
      'Week 10 – Baby can move, though you can\'t feel it yet',
      'Week 12 – Kidneys produce urine; baby can yawn and hiccup',
      'Week 13 – Fingerprints are forming; the baby continues to grow rapidly',
    ],
    motherChanges: [
      'Breast tenderness and swelling',
      'Frequent urination',
      'Fatigue and needing more sleep',
      'Heightened sense of smell',
      'Uterus growing but not yet visible',
      'Blood volume increases by up to 50%',
    ],
    commonSymptoms: [
      _Symptom('Morning sickness',
          'Eat small, frequent meals. Ginger tea helps.', Icons.sick_outlined),
      _Symptom('Fatigue', 'Rest as much as possible. Short naps are fine.',
          Icons.bedtime_outlined),
      _Symptom(
          'Food aversions',
          'Eat what you can tolerate. Bland foods often work.',
          Icons.no_food_outlined),
      _Symptom('Mood swings', 'Hormones are shifting. Journaling can help.',
          Icons.mood_outlined),
      _Symptom('Bloating', 'Avoid gas-producing foods; eat slowly.',
          Icons.bubble_chart_outlined),
    ],

    nutritionTips: [
      _NutritionTip('Folic acid (leafy greens)', 'Prevents neural tube defects',
          Icons.emoji_food_beverage),
      _NutritionTip('Iron (red meat, beans)', 'Supports baby\'s blood supply',
          Icons.health_and_safety_outlined),
      _NutritionTip(
          'Calcium (dairy, tofu)', 'Builds bones and teeth', Icons.egg),
      _NutritionTip('Vitamin B6 (bananas)',
          'Reduces nausea and supports energy', Icons.emoji_food_beverage),
      _NutritionTip('Water (8+ glasses/day)', 'Prevents dehydration and UTIs',
          Icons.opacity),
    ],
    warningSigns: [
      _WarningSigns('Heavy vaginal bleeding', isEmergency: true),
      _WarningSigns('Severe abdominal pain', isEmergency: true),
      _WarningSigns('High fever above 38°C', isEmergency: true),
      _WarningSigns('Painful or burning urination'),
      _WarningSigns('Signs of depression or anxiety'),
    ],
    medicalVisits: [
      'First prenatal visit (blood tests)',
      'Ultrasound dating scan (Weeks 8–12)',
      'Nuchal translucency screening (Weeks 11–13)',
      'Blood pressure and weight baseline',
    ],
    emotionalNote:
        'It\'s completely normal to feel overwhelmed, anxious, or even unsure. Your feelings are valid. Share them with someone you trust — or with your midwife.',
  ),
  _TrimesterData(
    name: 'Second Trimester',
    weeks: 'Weeks 14 – 27',
    icon: Icons.monitor_heart_outlined,
    headline: 'The golden period of pregnancy',
    summary:
        'Most people feel much better in the second trimester. Morning sickness often fades, energy returns, and you\'ll begin to feel your baby move for the first time.',
    babyDevelopment: [
      'Week 14 – Baby can make facial expressions',
      'Week 16 – Eyes can move; tiny eyebrows forming',
      'Week 18 – Yawning, hiccupping, and swallowing amniotic fluid',
      'Week 20 – You may feel first movements',
      'Week 22 – Lips, eyelids, and eyebrows clearly visible',
      'Week 26 – Eyes begin to open and respond to sound',
      'Week 27 – Brain developing rapidly and the baby gains more strength',
    ],
    motherChanges: [
      'Baby bump becomes visible',
      'Skin may stretch; stretch marks may appear',
      'Back pain begins as posture shifts',
      'Braxton Hicks contractions may start',
      'Increased appetite and food cravings',
      'Nasal congestion (pregnancy rhinitis)',
    ],
    commonSymptoms: [
      _Symptom('Back pain', 'Use a pregnancy pillow; avoid heavy lifting.',
          Icons.accessibility_new),
      _Symptom(
          'Round ligament pain',
          'Sharp pain on lower belly sides — normal. Move slowly.',
          Icons.healing_outlined),
      _Symptom('Heartburn', 'Eat smaller meals; avoid spicy and acidic foods.',
          Icons.local_fire_department_outlined),
      _Symptom('Leg cramps', 'Stay hydrated; stretch calves before bed.',
          Icons.directions_walk),
      _Symptom('Stretch marks', 'Moisturize daily with oil or lotion.',
          Icons.spa_outlined),
    ],

    nutritionTips: [
      _NutritionTip('Omega-3 (fish, chia seeds)',
          'Supports baby\'s brain development', Icons.egg),
      _NutritionTip(
          'Vitamin D (eggs, sunlight)', 'Supports bone health', Icons.wb_sunny),
      _NutritionTip('Protein (chicken, legumes)',
          'Supports tissue and muscle growth', Icons.restaurant),
      _NutritionTip('Fiber (oats, vegetables)', 'Helps prevent constipation',
          Icons.grass),
      _NutritionTip('Magnesium (nuts, seeds)', 'May reduce leg cramps',
          Icons.local_dining),
    ],
    warningSigns: [
      _WarningSigns('Preterm labor contractions before Week 37',
          isEmergency: true),
      _WarningSigns('Sudden swelling of face or hands', isEmergency: true),
      _WarningSigns('Decreased or no fetal movement'),
      _WarningSigns('Severe headaches or vision changes'),
      _WarningSigns('Signs of urinary tract infection'),
    ],
    medicalVisits: [
      'Anatomy ultrasound scan (Weeks 18–20)',
      'Gestational diabetes screening (Weeks 24–28)',
      'Regular blood pressure monitoring',
      'Iron levels and anemia check',
    ],
    emotionalNote:
        'Many mothers feel a surge of connection as they feel their baby move. It\'s also normal to feel anxious about the changes ahead. Take it one day at a time.',
  ),
  _TrimesterData(
    name: 'Third Trimester',
    weeks: 'Weeks 28 – 40+',
    icon: Icons.baby_changing_station_outlined,
    headline: 'Almost there — prepare to meet your baby',
    summary:
        'The final stretch. Your baby is gaining weight and preparing for life outside the womb, and your body is getting ready for labor and delivery.',
    babyDevelopment: [
      'Week 28 – Bone marrow produces red blood cells',
      'Week 30 – Brain developing billions of neurons',
      'Week 32 – Practices breathing movements and gains fat',
      'Week 35 – Kidneys fully developed; most organs ready',
      'Week 36 – Baby is considered early term',
      'Week 38 – Considered full term and ready for delivery',
      'Week 40 – Average due date and baby continues gaining strength',
    ],
    motherChanges: [
      'Difficulty sleeping due to baby\'s size',
      'Frequent urination returns as baby presses bladder',
      'Shortness of breath as uterus pushes up',
      'Braxton Hicks contractions may become more noticeable',
      'Pelvic pressure as baby drops lower',
      'Colostrum may leak from breasts',
    ],
    commonSymptoms: [
      _Symptom(
          'Insomnia',
          'Use a pregnancy pillow and sleep on your left side.',
          Icons.nightlight_outlined),
      _Symptom(
          'Swollen ankles',
          'Elevate feet; avoid standing for long periods.',
          Icons.airline_seat_legroom_extra),
      _Symptom(
          'Pelvic pain',
          'Wear a support belt and avoid stairs when possible.',
          Icons.health_and_safety_outlined),
      _Symptom(
          'Braxton Hicks',
          'Drink water and change positions. Not real labor.',
          Icons.favorite_border),
      _Symptom('Shortness of breath',
          'Sleep slightly propped up; avoid overexertion.', Icons.air_outlined),
    ],

    nutritionTips: [
      _NutritionTip(
          'Iron (spinach, red meat)',
          'Prepare for blood loss during delivery',
          Icons.health_and_safety_outlined),
      _NutritionTip(
          'Vitamin K (broccoli, eggs)', 'Supports blood clotting', Icons.egg),
      _NutritionTip('Dates (6/day from Week 36)',
          'May support cervical ripening', Icons.inventory_2),
      _NutritionTip('Collagen (bone broth)',
          'Supports tissue repair postpartum', Icons.ramen_dining),
      _NutritionTip(
          'Hydration',
          'Helps prevent Braxton Hicks and supports circulation',
          Icons.opacity),
    ],
    warningSigns: [
      _WarningSigns('Regular contractions before Week 37', isEmergency: true),
      _WarningSigns('Water breaking with gush or trickle', isEmergency: true),
      _WarningSigns('Baby not moving for 12+ hours', isEmergency: true),
      _WarningSigns('Severe headache with vision changes', isEmergency: true),
      _WarningSigns('Bleeding heavier than spotting', isEmergency: true),
    ],
    medicalVisits: [
      'Biweekly checkups from Week 28–36',
      'Weekly checkups from Week 36 onward',
      'Group B Streptococcus (GBS) test (Week 35–37)',
      'Non-stress test if high-risk or overdue',
    ],
    emotionalNote:
        'Anticipation, excitement, and fear are all normal. Talk to your midwife about your birth preferences and fears. You are stronger than you know.',
  ),
];

const _weeklyFacts = <int, String>{
  4: 'Your baby is the size of a poppy seed.',
  5: 'Your baby is the size of a sesame seed and the heart is beginning to form.',
  6: 'Heartbeat detectable by ultrasound.',
  7: 'Brain growing quickly.',
  8: 'All major organs are forming.',
  9: 'Fingers and toes are defined.',
  10: 'Baby can move, but you cannot feel it yet.',
  11: 'Tooth buds are forming under gums.',
  12: 'Baby can yawn and hiccup.',
  13: 'Fingerprints are unique to your baby.',
  14: 'Baby can make facial expressions.',
  15: 'Skeleton is changing from cartilage to bone.',
  16: 'Eyes slowly moving beneath fused eyelids.',
  17: 'Baby can hear your voice.',
  18: 'You may feel first flutters this week.',
  19: 'Protective coating forms on baby skin.',
  20: 'Halfway there! Baby is about 25 cm long.',
  21: 'Baby sleeps and wakes in cycles.',
  22: 'Lips, eyelids, and eyebrows are visible.',
  23: 'Sense of movement is developed.',
  24: 'Lungs are developing air sacs.',
  25: 'Baby responds to your touch.',
  26: 'Eyes begin to open for the first time.',
  27: 'Brain is developing rapidly.',
  28: 'Bone marrow is producing red blood cells.',
  29: 'Muscles and lungs are maturing.',
  30: 'Baby gains more weight each week.',
  31: 'All five senses are functioning.',
  32: 'Baby is practicing breathing movements.',
  33: 'Skull bones remain soft and flexible for birth.',
  34: 'Fingernails reach the tips of the fingers.',
  35: 'Kidneys are fully developed and organs are ready.',
  36: 'Early term — baby could arrive any day.',
  37: 'Full term — the baby is ready for the world.',
  38: 'Your baby is fully developed.',
  39: 'Baby continues to gain weight steadily.',
  40: 'Due date week — baby may arrive soon.',
};

// ============================================
// FILIPINO TRANSLATIONS (Complete coverage)
// ============================================

const _trimesterNameFilipino = [
  'Unang Trimester',
  'Ikalawang Trimester',
  'Ikatlong Trimester',
];

const _trimesterHeadlineFilipino = [
  'Nagsisimula pa lamang ang iyong sanggol!',
  'Ang ginintuang yugto ng pagbubuntis',
  'Malapit nang dumating — maghanda na sa iyong baby',
];

const _trimesterSummaryFilipino = [
  'Ang unang trimester ay panahon ng kamangha-manghang pagbabago. Ang iyong katawan ay nagpupunyagi upang bumuo ng buhay, at ang iyong sanggol ay lumalaki mula sa isang maliit na selula tungo sa isang maliit na tao na may pintig ng puso.',
  'Kadalasan, mas magaan ang pakiramdam sa ikalawang trimester. Bumabawas ang morning sickness, bumabalik ang iyong enerhiya, at mararamdaman mo na ang mga paggalaw ng sanggol.',
  'Ang huling bahagi ng pagbubuntis. Tumitimbang ang iyong sanggol at naghahanda na para sa paglabas, habang ang iyong katawan ay inihahanda ang sarili para sa labor at delivery.',
];

const _trimesterNoteFilipino = [
  'Normal lamang na makaramdam ng pagod, pag-aalala, o pagkalito. Valid ang iyong nararamdaman. Ibahagi ito sa taong pinagkakatiwalaan mo o sa iyong midwife.',
  'Maraming ina ang nakakaramdam ng koneksyon sa paggalaw ng sanggol. Normal din ang kaba tungkol sa pagbabago. Isang hakbang lamang bawat araw.',
  'Normal ang halo-halong damdamin ng excitement at takot. Ipaalam sa iyong midwife ang iyong mga plano at mga pangamba. Mas malakas ka kaysa sa inaakala mo.',
];

const _weeklyFactsFilipino = <int, String>{
  4: 'Kasing laki ng buto ng poppy ang iyong sanggol.',
  5: 'Kasing laki ng linga ang iyong sanggol at nagsisimulang mabuo ang puso.',
  6: 'Maaaring marinig ang tibok ng puso sa ultrasound.',
  7: 'Mabilis na lumalaki ang utak.',
  8: 'Ang lahat ng pangunahing organ ay nabubuo.',
  9: 'Dahan-dahang lumilitaw ang mga daliri at daliri sa paa.',
  10: 'Nakakagalaw ang sanggol, pero hindi mo pa nararamdaman.',
  11: 'Nabubuo ang mga ngipin sa ilalim ng gilagid.',
  12: 'Nakakagawa ng hikab at pag-ubo ang sanggol.',
  13: 'Natatangi ang fingerprints ng iyong baby.',
  14: 'Nakagagawa ng ekspresyon sa mukha ang sanggol.',
  15: 'Naglilipat ang skeletong kartilago tungo sa buto.',
  16: 'Dahan-dahang kumikilos ang mga mata sa ilalim ng fused eyelids.',
  17: 'Naririnig ng sanggol ang iyong boses.',
  18: 'Maaring maramdaman mo ang unang kumikindat ngayong linggo.',
  19: 'Nabubuo ang proteksiyon na balat ng sanggol.',
  20: 'Kalahati na! Mga 25 cm na ang haba ng sanggol.',
  21: 'Natutulog at nagigising sa mga cycle ang sanggol.',
  22: 'Maliwanag na makikita ang labi, talukap, at kilay.',
  23: 'Nade-develop na ang sense of movement.',
  24: 'Nade-develop ang mga baga at air sacs.',
  25: 'Tumutugon ang sanggol sa iyong paghipo.',
  26: 'Nagsisimulang bumukas ang mata ng sanggol.',
  27: 'Mabilis na lumalaki ang utak.',
  28: 'Gumagawa na ng pulang selula ng dugo ang bone marrow.',
  29: 'Nagmumuni-muni ang mga kalamnan at baga.',
  30: 'Lumalakas ang timbang ng sanggol bawat linggo.',
  31: 'Gumagana na ang lahat ng limang pandama.',
  32: 'Nagsasanay maghinga ang sanggol.',
  33: 'Lumanay ang buto ng bungo para sa kapanganakan.',
  34: 'Umaabot na sa dulo ng daliri ang mga kuko.',
  35: 'Ganap na nabubuo ang mga bato at iba pang organo.',
  36: 'Maaaring dumating ang sanggol anumang araw.',
  37: 'Nasa full term na ang sanggol at handa nang lumabas.',
  38: 'Buong-buo na ang iyong baby.',
  39: 'Patuloy ang pagdagdag ng timbang ng sanggol.',
  40: 'Linggo ng due date — malapit na ang pagdating.',
};

// Comprehensive translation map (complete coverage for all used strings)
const _contentTranslationsFilipino = {
  // Baby Development
  'Week 4 – Embryo implants; neural tube begins forming':
      'Linggo 4 – Na-i-implant ang embryo; nagsisimula ang neural tube.',
  'Week 6 – Heart starts beating': 'Linggo 6 – Nagsisimulang tumibok ang puso.',
  'Week 8 – All major organs are forming; fingers and toes appear':
      'Linggo 8 – Nabubuo ang lahat ng pangunahing organo; lumilitaw ang mga daliri sa kamay at paa.',
  'Week 10 – Baby can move, though you can\'t feel it yet':
      'Linggo 10 – Nakakagalaw na ang sanggol, ngunit hindi mo pa ito nararamdaman.',
  'Week 12 – Kidneys produce urine; baby can yawn and hiccup':
      'Linggo 12 – Gumagawa ng ihi ang mga bato; nakakabuka at nakakakuha ng hikab ang sanggol.',
  'Week 13 – Fingerprints are forming; the baby continues to grow rapidly':
      'Linggo 13 – Nabubuo na ang fingerprints; patuloy na mabilis ang paglaki ng sanggol.',
  'Week 14 – Baby can make facial expressions':
      'Linggo 14 – Nakakagawa ng ekspresyon sa mukha ang sanggol.',
  'Week 16 – Eyes can move; tiny eyebrows forming':
      'Linggo 16 – Nakakagalaw ang mga mata; nabubuo ang maliliit na kilay.',
  'Week 18 – Yawning, hiccupping, and swallowing amniotic fluid':
      'Linggo 18 – Bumubuka, humihikab, at lumulunok ng amniotic fluid.',
  'Week 20 – You may feel first movements':
      'Linggo 20 – Maaaring maramdaman mo ang unang paggalaw.',
  'Week 22 – Lips, eyelids, and eyebrows clearly visible':
      'Linggo 22 – Kitang-kita na ang labi, talukap ng mata, at kilay.',
  'Week 26 – Eyes begin to open and respond to sound':
      'Linggo 26 – Nagsisimulang bumukas ang mga mata at tumutugon sa tunog.',
  'Week 27 – Brain developing rapidly and the baby gains more strength':
      'Linggo 27 – Mabilis na lumalago ang utak at lumalakas ang sanggol.',
  'Week 28 – Bone marrow produces red blood cells':
      'Linggo 28 – Gumagawa ang bone marrow ng pulang selula ng dugo.',
  'Week 30 – Brain developing billions of neurons':
      'Linggo 30 – Lumalaki ang utak at bumubuo ng bilyon-bilyong neuron.',
  'Week 32 – Practices breathing movements and gains fat':
      'Linggo 32 – Nagsasanay ng paghinga at nadadagdagan ang taba.',
  'Week 35 – Kidneys fully developed; most organs ready':
      'Linggo 35 – Ganap na nabuo ang mga bato; handa na ang karamihan sa mga organo.',
  'Week 36 – Baby is considered early term':
      'Linggo 36 – Itinuturing na early term ang sanggol.',
  'Week 38 – Considered full term and ready for delivery':
      'Linggo 38 – Itinuturing na full term at handa nang ipanganak.',
  'Week 40 – Average due date and baby continues gaining strength':
      'Linggo 40 – Karaniwang araw ng due date at patuloy ang pagdagdag ng lakas ng sanggol.',

  // Nutrition
  'Folic acid (leafy greens)': 'Folic acid (mga dahong gulay)',
  'Prevents neural tube defects': 'Nagiiwas sa depekto sa neural tube',
  'Iron (red meat, beans)': 'Iron (pulang karne, beans)',
  'Supports baby\'s blood supply': 'Sumusuporta sa dugo ng sanggol',
  'Calcium (dairy, tofu)': 'Calcium (gatas, tofu)',
  'Builds bones and teeth': 'Nagpapalakas ng buto at ngipin',
  'Vitamin B6 (bananas)': 'Vitamin B6 (saging)',
  'Reduces nausea and supports energy':
      'Nagpapabawas ng pagduduwal at sumusuporta sa enerhiya',
  'Water (8+ glasses/day)': 'Tubig (8+ baso/araw)',
  'Prevents dehydration and UTIs': 'Nagiiwas sa dehydration at UTI',
  'Omega-3 (fish, chia seeds)': 'Omega-3 (isda, chia seeds)',
  'Supports baby\'s brain development':
      'Sumusuporta sa pag-unlad ng utak ng sanggol',
  'Vitamin D (eggs, sunlight)': 'Vitamin D (itlog, sikat ng araw)',
  'Supports bone health': 'Sumusuporta sa kalusugan ng buto',
  'Protein (chicken, legumes)': 'Protein (manok, legumes)',
  'Supports tissue and muscle growth':
      'Sumusuporta sa paglaki ng tisyu at kalamnan',
  'Fiber (oats, vegetables)': 'Fiber (oats, gulay)',
  'Helps prevent constipation': 'Nakakatulong umiwas sa constipation',
  'Magnesium (nuts, seeds)': 'Magnesium (mani, buto)',
  'May reduce leg cramps': 'Maaaring magpabawas ng pulikat sa binti',
  'Iron (spinach, red meat)': 'Iron (spinach, pulang karne)',
  'Prepare for blood loss during delivery':
      'Ihanda ang katawan para sa pagdurugo sa panganganak',
  'Vitamin K (broccoli, eggs)': 'Vitamin K (brokoli, itlog)',
  'Supports blood clotting': 'Sumusuporta sa pamumuo ng dugo',
  'Dates (6/day from Week 36)': 'Dates (6/araw mula Linggo 36)',
  'May support cervical ripening': 'Maaaring sumuporta sa paghinog ng cervix',
  'Collagen (bone broth)': 'Collagen (sabaw ng buto)',
  'Supports tissue repair postpartum':
      'Sumusuporta sa pag-ayos ng tisyu pagkatapos manganak',
  'Hydration': 'Pag-inom ng sapat na tubig',
  'Helps prevent Braxton Hicks and supports circulation':
      'Nakakatulong maiwasan ang Braxton Hicks at sumusuporta sa daloy ng dugo',

  // Checklist
  'Schedule first prenatal checkup': 'Mag-iskedyul ng unang prenatal checkup',
  'Start prenatal vitamins with folic acid':
      'Simulan ang prenatal vitamins na may folic acid',
  'Avoid alcohol, smoking, and raw foods':
      'Iwasan ang alak, paninigarilyo, at hilaw na pagkain',
  'Inform your midwife of all medications':
      'Ipagbigay-alam sa iyong midwife ang lahat ng gamot',
  'Morning sickness': 'Pagkakasuka sa umaga',
  'Eat small, frequent meals. Ginger tea helps.':
      'Kumain ng maliit at madalas. Nakakatulong ang ginger tea.',
  'Fatigue': 'Pagkapagod',
  'Rest as much as possible. Short naps are fine.':
      'Magpahinga nang sapat hangga\'t maaari. Ayos lang ang maiikling tulog.',
  'Food aversions': 'Pag-ayaw sa pagkain',
  'Eat what you can tolerate. Bland foods often work.':
      'Kumain ng kaya mong tiisin. Madalas na epektibo ang mga bland na pagkain.',
  'Mood swings': 'Pagbabago ng mood',
  'Hormones are shifting. Journaling can help.':
      'Nagbabago ang hormones. Makakatulong ang pag-journal.',
  'Bloating': 'Panunumpa',
  'Avoid gas-producing foods; eat slowly.':
      'Iwasan ang mga pagkain na nagdudulot ng hangin; kumain nang dahan-dahan.',
  'Back pain': 'Pananakit ng likod',
  'Use a pregnancy pillow; avoid heavy lifting.':
      'Gumamit ng pregnancy pillow; iwasan ang mabibigat na buhat.',
  'Round ligament pain': 'Pananakit ng round ligament',
  'Sharp pain on lower belly sides — normal. Move slowly.':
      'Matalim na sakit sa gilid ng ibabang tiyan — normal ito. Kumilos nang dahan-dahan.',
  'Heartburn': 'Pangangasim ng sikmura',
  'Eat smaller meals; avoid spicy and acidic foods.':
      'Kumain ng mas maliliit na meal; iwasan ang maaanghang at acidic na pagkain.',
  'Leg cramps': 'Pulikat sa binti',
  'Stay hydrated; stretch calves before bed.':
      'Uminom ng sapat na tubig; i-stretch ang binti bago matulog.',
  'Stretch marks': 'Stretch marks',
  'Moisturize daily with oil or lotion.':
      'Maglagay araw-araw ng langis o lotion sa balat.',
  'Back pain begins as posture shifts':
      'Nagsisimula ang pananakit ng likod habang nagbabago ang postura',
  'Get blood type and Rh factor confirmed':
      'Kumpirmahin ang blood type at Rh factor',
  'Discuss genetic screening options':
      'Pag-usapan ang mga opsyon sa genetic screening',
  'Start a pregnancy journal': 'Magsimula ng pregnancy journal',
  'Schedule anatomy scan (Week 18–20)':
      'Mag-iskedyul ng anatomy scan (Linggo 18–20)',
  'Discuss gestational diabetes screening':
      'Pag-usapan ang gestational diabetes screening',
  'Start shopping for maternity clothes':
      'Magsimula nang mamili ng damit-pang-maternity',
  'Begin researching childbirth classes':
      'Magsaliksik tungkol sa mga klase sa panganganak',
  'Plan your birth plan preferences':
      'Planuhin ang iyong birth plan preferences',
  'Set up emergency contact list': 'Ihanda ang listahan ng emergency contact',
  'Discuss hospital or birthing center choice':
      'Pag-usapan ang pagpili ng ospital o birthing center',
  'Install and test baby car seat': 'I-install at subukan ang baby car seat',
  'Prepare the nursery or baby space':
      'Ihanda ang nursery o espasyo ng sanggol',
  'Learn signs of true versus false labor':
      'Alamin ang mga palatandaan ng tunay at hindi tunay na labor',
  'Arrange postpartum help at home': 'Ayusin ang postpartum na tulong sa bahay',
  'Stock up on postpartum supplies':
      'Mag-stock ng mga gamit para sa postpartum',
  'Pack your hospital bag': 'I-empake ang iyong hospital bag',
  'Finalize birth plan with midwife':
      'Tapusin ang birth plan kasama ang midwife',

  // Hospital bag items
  'Government-issued ID and PhilHealth card':
      'Government-issued ID at PhilHealth card',
  'Maternity card or prenatal records': 'Maternity card o prenatal records',
  'Comfortable loose clothing and slippers':
      'Komportableng maluwag na damit at tsinelas',
  'Newborn onesies, blanket, and diapers':
      'Mga onesies ng bagong silang, kumot, at lampin',
  'Toiletries for you and baby': 'Toiletries para sa iyo at sa baby',
  'Snacks and drinks for labor': 'Meryenda at inumin para sa labor',
  'Phone charger': 'Phone charger',
  'Cash for hospital fees': 'Cash para sa bayarin sa ospital',

  // Warning signs
  'Heavy vaginal bleeding': 'Malakas na pagdurugo mula sa ari',
  'Severe abdominal pain': 'Matinding pananakit ng tiyan',
  'High fever above 38°C': 'Mataas na lagnat higit sa 38°C',
  'Painful or burning urination': 'Masakit o nasusunog na pag-ihi',
  'Signs of depression or anxiety': 'Palatandaan ng depression o anxiety',
  'Preterm labor contractions before Week 37':
      'Pagkakaroon ng kontraksiyon bago ang Linggo 37',
  'Sudden swelling of face or hands': 'Biglaang pamamaga ng mukha o kamay',
  'Decreased or no fetal movement': 'Bawas o walang paggalaw ng sanggol',
  'Severe headaches or vision changes':
      'Matinding sakit ng ulo o pagbabago sa paningin',
  'Signs of urinary tract infection': 'Palatandaan ng impeksyon sa ihi',
  'Regular contractions before Week 37':
      'Regular na kontraksiyon bago ang Linggo 37',
  'Water breaking with gush or trickle':
      'Pagputok ng tubig na may umagos o tumutulo',
  'Baby not moving for 12+ hours':
      'Hindi gumagalaw ang sanggol ng higit sa 12 oras',
  'Severe headache with vision changes':
      'Matinding sakit ng ulo na may pagbabago sa paningin',
  'Bleeding heavier than spotting': 'Pagdurugo na mas malakas kaysa spotting',

  // Food to avoid
  'Raw or undercooked meat and eggs':
      'Hilaw o hindi lutong lubos na karne at itlog',
  'High-mercury fish such as shark and swordfish':
      'Isdang mataas sa mercury tulad ng pating at espadon',
  'Unpasteurized dairy and soft cheeses':
      'Gatas na hindi pasteurized at malambot na keso',
  'Alcohol of any kind': 'Alak ng anumang uri',
  'Excess caffeine (limit to 200mg/day)':
      'Sobra sa caffeine (limitahan sa 200mg/bawat araw)',
  'Processed junk food and excess sugar':
      'Pinrosesong junk food at labis na asukal',

  // Medical visits
  'First prenatal visit (blood tests)':
      'Unang prenatal visit (pagsusuri sa dugo)',
  'Ultrasound dating scan (Weeks 8–12)': 'Ultrasound dating scan (Linggo 8–12)',
  'Nuchal translucency screening (Weeks 11–13)':
      'Nuchal translucency screening (Linggo 11–13)',
  'Blood pressure and weight baseline': 'Blood pressure at weight baseline',
  'Anatomy ultrasound scan (Weeks 18–20)':
      'Anatomy ultrasound scan (Linggo 18–20)',
  'Gestational diabetes screening (Weeks 24–28)':
      'Gestational diabetes screening (Linggo 24–28)',
  'Regular blood pressure monitoring': 'Regular na blood pressure monitoring',
  'Iron levels and anemia check': 'Pagsusuri ng iron levels at anemia',
  'Biweekly checkups from Week 28–36':
      'Checkup kada dalawang linggo mula Linggo 28–36',
  'Weekly checkups from Week 36 onward': 'Checkup linggu-linggo mula Linggo 36',
  'Group B Streptococcus (GBS) test (Week 35–37)':
      'Group B Streptococcus (GBS) test (Linggo 35–37)',
  'Non-stress test if high-risk or overdue':
      'Non-stress test kung high-risk o overdue',

  // UI Labels
  'Go to the hospital immediately': 'Agad na pumunta sa ospital',
  'Watch and monitor': 'Bantayan at subaybayan',
  'Pregnancy Progress': 'Progreso ng Pagbubuntis',
  'Overview': 'Pangkalahatan',
  'Baby': 'Sanggol',
  'Symptoms': 'Sintomas',
  'Nutrition': 'Nutrisyon',
  'Checklist': 'Checklist',
  'Warnings': 'Babala',
  'THIS WEEK': 'NGAYONG LINGGO',
  'A Note for You': 'Tandaan Para sa Iyo',
  'Trimester Journey': 'Paglalakbay ng Trimester',
  'Medical Visits This Trimester': 'Mga Medikal na Pagbisita ngayong Trimester',
  'Development Milestones': 'Mga Milestone ng Pag-unlad',
  'Changes in Your Body': 'Mga Pagbabago sa Iyong Katawan',
  'Key Nutrients This Trimester': 'Pangunahing Nutrisyon ngayong Trimester',
  'Foods to Avoid': 'Mga Pagkaing Iwasan',
  'Eating for Two': 'Pagkain para sa Dalawa',
  'Priority Tasks': 'Pangunahing Gawain',
  'When You Can': 'Kapag Maaari',
  'Hospital Bag Essentials': 'Mga Kailangan sa Bag ng Ospital',
  'Emergency Contacts': 'Mga Emergency na Kontak',
  'Daily kick count': 'Araw-araw na bilang ng sipa',
  'Baby this week': 'Sanggol ngayong linggo',
  'Size': 'Sukat',
  'Weight': 'Timbang',
  'Baby Size': 'Sukat ng Sanggol',
  'Baby Weight': 'Timbang ng Sanggol',
  'Due Date': 'Araw ng Pagbubuntis',
  'Weeks Left': 'Natitirang Linggo',
  'Risk Level': 'Antas ng Panganib',
  'Fetal Count': 'Bilang ng Sanggol',
  'Prenatal Risk Summary': 'Buod ng Panganib',
  'Risk Factors': 'Mga Salik ng Panganib',
  'Recommended Actions': 'Rinerekomendang Hakbang',
  'NOW': 'NGAYON',
  'YOU ARE HERE': 'NANDITO KA',

  // Dynamic translations
  '1 baby': '1 sanggol',
  'babies': 'mga sanggol',
  'weeks': 'linggo',
  'w left': 'natitirang linggo',
};

/// Safely translate content with fallback
String _translateContent(String text, AppLanguage language) {
  if (language != AppLanguage.filipino) return text;

  // Try exact match first
  if (_contentTranslationsFilipino.containsKey(text)) {
    return _contentTranslationsFilipino[text]!;
  }

  // Try case-insensitive match
  final lowerText = text.toLowerCase();
  for (final entry in _contentTranslationsFilipino.entries) {
    if (entry.key.toLowerCase() == lowerText) {
      return entry.value;
    }
  }

  return text;
}

// ============================================
// MAIN WIDGET
// ============================================

class PregnancyDetailPage extends StatefulWidget {
  final int week;
  final String trimester;
  final String dueDate;
  final int weeksLeft;
  final String babySize;
  final String babyWeight;
  final String firstName;
  final String riskLevel;
  final int fetalCount;
  final int pregnancyId; // Added to fetch personalized data
  final List<String>? riskFactors;
  final List<String>? suggestedActions;

  const PregnancyDetailPage({
    super.key,
    required this.week,
    required this.trimester,
    required this.dueDate,
    required this.weeksLeft,
    required this.babySize,
    required this.babyWeight,
    required this.firstName,
    required this.riskLevel,
    required this.fetalCount,
    required this.pregnancyId,
    this.riskFactors,
    this.suggestedActions,
  });

  @override
  State<PregnancyDetailPage> createState() => _PregnancyDetailPageState();
}

class _PregnancyDetailPageState extends State<PregnancyDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final _TrimesterData _data;

  // Personalized data from database
  List<String> _personalizedSymptoms = [];
  List<String> _personalizedWarnings = [];

  List<String> _activeAllergies = [];

  final Set<String> _checkedTasks = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _data = _trimesterForWeek(widget.week);
    _loadPersonalizedData();
    _loadBabyMilestones();
    _loadBhcRegistration();
  }

  /// The Baby Book sections need a CurrentPregnancyState, which this page
  /// already holds the parts of. Built once rather than per rebuild.
  CurrentPregnancyState get _pregnancyState => CurrentPregnancyState(
        pregnancyId: widget.pregnancyId,
        currentWeek: widget.week,
        currentMonth: BabyBookRepository.stageForWeek(widget.week)?.month ?? 1,
        estimatedDueDate:
            DateTime.now().add(Duration(days: widget.weeksLeft * 7)),
        numberOfBabies: widget.fetalCount <= 0 ? 1 : widget.fetalCount,
        pregnancyProgress: (widget.week / 40).clamp(0.0, 1.0),
        trimester: widget.trimester,
      );

  List<BabyGrowthMilestone> _babyMilestones = const [];

  /// Whether a barangay health centre has this mother on its books.
  ///
  /// Gates the risk banner. Starts false and is only raised once the answer
  /// comes back — the wrong way to fail is to show a risk status to someone
  /// nobody has assessed.
  bool _isBhcRegistered = false;

  /// Which guide PDF is currently downloading, by file name.
  String? _downloadingGuide;

  /// Reads whether she is registered, cache first so the banner does not
  /// flicker in on every visit.
  Future<void> _loadBhcRegistration() async {
    final cached = await AuthStorage.wasBhcRegistered();
    if (mounted && cached != _isBhcRegistered) {
      setState(() => _isBhcRegistered = cached);
    }

    final motherId = await AuthStorage.getMotherId();
    if (motherId == null) return;
    try {
      final row = await SupabaseService.client
          .from('mothers')
          .select('assigned_bhc_id')
          .eq('mother_id', motherId)
          .maybeSingle();
      final registered = row != null && row['assigned_bhc_id'] != null;
      await AuthStorage.saveBhcRegistered(registered);
      if (mounted && registered != _isBhcRegistered) {
        setState(() => _isBhcRegistered = registered);
      }
    } catch (e) {
      // She keeps whatever the cache said. Guessing "registered" would show a
      // risk status nobody assigned.
      if (kDebugMode) debugPrint('BHC registration check failed: $e');
    }
  }

  Future<void> _downloadGuidePdf({
    required String assetPath,
    required String fileName,
  }) async {
    if (_downloadingGuide != null) return;
    setState(() => _downloadingGuide = fileName);
    try {
      await downloadAssetPdf(assetPath: assetPath, fileName: fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The guide could not be downloaded. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingGuide = null);
    }
  }

  Future<void> _loadBabyMilestones() async {
    if (widget.pregnancyId == 0) return;
    // The recommended prenatal care, which is what the milestone catalogue
    // now holds — see 20260827_pregnancy_care_milestones.
    final list = await const BabyBookRepository().loadPrenatalMilestones(
      pregnancyId: widget.pregnancyId,
      currentWeek: widget.week,
      owner: MilestoneOwner.mother,
    );
    if (!mounted) return;
    setState(() => _babyMilestones = list);
  }

  /// Saves a mark going on or coming off a recommended milestone.
  ///
  /// Writes only to the Baby Book's own table. No midwife screen reads it, so
  /// a mother recording a checkup she had at a private clinic never appears
  /// as a barangay record.
  Future<bool> _persistMilestoneMark(
    BabyGrowthMilestone milestone,
    bool markingDone,
  ) async {
    if (widget.pregnancyId == 0) return false;
    const repository = BabyBookRepository();

    if (!markingDone) {
      final entryId = milestone.entryId;
      if (entryId == null) return true;
      return repository.unrecordPrenatalMilestone(entryId);
    }

    return repository.recordPrenatalMilestone(
      pregnancyId: widget.pregnancyId,
      templateKey: milestone.id,
      observedOn: DateTime.now(),
      recordedPregnancyWeek: widget.week,
    );
  }

  Future<void> _loadPersonalizedData() async {


    try {
      final supabase = SupabaseService.client;

      // Fetch actual symptoms from database
      final List<dynamic>? symptomsData = await supabase
          .from('pregnancy_symptoms')
          .select('symptom_type_id, symptom_types(symptom_name, risk_category)')
          .eq('pregnancy_id', widget.pregnancyId) as List<dynamic>?;

      if (symptomsData != null) {
        _personalizedSymptoms = symptomsData
            .where((s) => s['symptom_types'] != null)
            .map((s) => s['symptom_types']['symptom_name'] as String)
            .toList();
      }

      // Fetch risk assessment
      final riskData = await supabase
          .from('pregnancy_risk_assessments')
          .select('pregnancy_risk_id, risk_level')
          .eq('pregnancy_id', widget.pregnancyId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (riskData != null) {
        final riskId = riskData['pregnancy_risk_id'];

        // Fetch risk factors
        final List<dynamic>? factorsData = await supabase
            .from('pregnancy_risk_factors')
            .select('factor')
            .eq('pregnancy_risk_id', riskId) as List<dynamic>?;

        if (factorsData != null) {
          _personalizedWarnings =
              factorsData.map((f) => f['factor'] as String).toList();
        }
      }



      // Fetch active allergies for the mother (to filter nutrition tips)
      final motherRow = await supabase
          .from('pregnancies')
          .select('mother_id')
          .eq('pregnancy_id', widget.pregnancyId)
          .maybeSingle();

      if (motherRow != null) {
        final motherId = motherRow['mother_id'] as int;
        final allergyRows = await supabase
            .from('allergies')
            .select('allergen')
            .eq('mother_id', motherId)
            .eq('status', 'active');

        _activeAllergies = (allergyRows as List)
            .cast<Map<String, dynamic>>()
            .map((a) => (a['allergen'] as String? ?? '').toLowerCase())
            .where((a) => a.isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading personalized data: $e');
    }

    if (mounted) {
      setState(() {});
    }
  }

  _TrimesterData _trimesterForWeek(int week) {
    if (week <= 13) return _trimesterContent[0];
    if (week <= 27) return _trimesterContent[1];
    return _trimesterContent[2];
  }

  int _trimesterIndexForWeek(int week) {
    if (week <= 13) return 0;
    if (week <= 27) return 1;
    return 2;
  }

  Color _riskColor(String riskLevel) {
    final normalized = riskLevel.toLowerCase().trim();
    if (normalized == 'high') return AppColors.error;
    if (normalized == 'medium') return AppColors.warning;
    return AppColors.success;
  }

  String _translate(String english, String filipino, AppLanguage language) {
    return language == AppLanguage.filipino ? filipino : english;
  }


  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, language, _) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerScrolled) => [
                _buildSliverHeader(language),
              ],
              body: Column(
                children: [
                  _buildTabBar(language),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOverviewTab(language),
                        _buildBabyTab(language),
                        _buildSymptomsTab(language),
                        _buildNutritionTab(language),
                        _buildWarningsTab(language),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }




  /// The Baby Book's cover card, standing in for the page header.
  ///
  /// The solid pink SliverAppBar said Week 11, Month 3, First Trimester, the
  /// mother's name, the week range, "28% Completed" and the weeks left — and
  /// then the Overview tab opened with a card saying all of it again, in a
  /// different layout. Two headers for one pregnancy, disagreeing on nothing
  /// but their design.
  ///
  /// The cover card wins because it is the one the Baby Book already uses, so
  /// the page a mother reaches from "Mother and Baby Book" now looks like the
  /// book it is named after. The back arrow rides on top of it, since a pushed
  /// page still needs a way out.
  Widget _buildSliverHeader(AppLanguage language) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + 10,
          16,
          10,
        ),
        child: Stack(
          children: [
            // The inset is the back arrow's height plus a gap, so the card's
            // first line starts below it rather than under it.
            PregnancyCoverCard(
              pregnancy: _pregnancyState,
              contentTopInset: 44,
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.22),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: _translate('Back', 'Bumalik', language),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20),
                  constraints:
                      const BoxConstraints(minWidth: 38, minHeight: 38),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(AppLanguage language) {
    final tabs = [
      _translate('Overview', 'Pangkalahatan', language),
      _translate('Baby', 'Sanggol', language),
      _translate('Symptoms', 'Sintomas', language),
      _translate('Nutrition', 'Nutrisyon', language),
      _translate('Warnings', 'Babala', language),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: AppColors.brandPrimary,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 3.5,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        labelColor: AppColors.brandPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        tabs: tabs.map((label) => Tab(text: label, height: 48)).toList(),
      ),
    );
  }

  Widget _buildOverviewTab(AppLanguage language) {
    // Only the trimester index survives: the headline, summary and weekly fact
    // belonged to the cards this tab no longer draws. The Baby Book's growth
    // journey says what is happening this month, from the same catalogue, and
    // says it once.
    final trimesterIndex = _trimesterIndexForWeek(widget.week);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // The cover card is the page header now, so it is not drawn again
        // here — see _buildSliverHeader.

        // Shown only to a mother her barangay health centre has registered.
        //
        // A risk level is an assessment a midwife makes from a record. Without
        // a health centre there is no record and no one has made one, so the
        // banner was reporting a status nobody had assigned — and "HIGH RISK
        // STATUS" in red is the last thing to show a mother on the strength of
        // a default value.
        if (_isBhcRegistered) ...[
          const SizedBox(height: 12),
          _buildRiskSummaryCard(language),
        ],

        // The Baby Book's month browser: illustration, approximate length and
        // weight, size comparison, and what is developing this month. Placed
        // here rather than on a separate screen because it answers the same
        // question as the cards above it — how is my baby right now — and a
        // mother should not have to change pages to finish the thought.
        const SizedBox(height: 20),
        PregnancyGrowthJourney(
          currentPregnancy: _pregnancyState,
          stages: pregnancyGrowthStages,
        ),

        // The pregnancy timeline: recorded moments from early pregnancy to
        // birth preparation, reading the same baby_book_milestones rows the
        // child's Baby Book will inherit after delivery.
        const SizedBox(height: 20),
        BabyGrowthMilestonesSection(
          currentPregnancy: _pregnancyState,
          initialMilestones: _babyMilestones,
          onToggleCompleted: _persistMilestoneMark,
        ),

        // Trimester Journey, Medical Visits This Trimester and the Hospital
        // Bag checklist used to sit here.
        //
        // The first restated the trimester the header already names. The other
        // two were static checklists of what a pregnancy generally involves,
        // which is the same job the Pregnancy Milestones section above does —
        // except that section reads the real catalogue and knows which items
        // have actually happened, while these did not.
        const SizedBox(height: 16),
        _buildEmotionalNote(language, trimesterIndex),

        // References last, and folded away.
        //
        // It sat above the note, which put a bibliography between a mother and
        // the one paragraph on the page written to reassure her. Sources are
        // the least urgent thing here and belong at the foot of the page.
        const SizedBox(height: 16),
        ReferencesPanel(
          onDownloadDoh: () => _downloadGuidePdf(
            assetPath: 'assets/pdf/DOH.pdf',
            fileName: 'DOH-Mother-and-Baby-Book.pdf',
          ),
          onDownloadWho: () => _downloadGuidePdf(
            assetPath: 'assets/pdf/WHO.pdf',
            fileName: 'WHO-Home-Based-Records-Guide.pdf',
          ),
          downloadingDoh: _downloadingGuide == 'DOH-Mother-and-Baby-Book.pdf',
          downloadingWho:
              _downloadingGuide == 'WHO-Home-Based-Records-Guide.pdf',
        ),

        const SizedBox(height: 24),
      ],
    );
  }



  Widget _buildRiskSummaryCard(AppLanguage language) {
    if (widget.riskLevel.isEmpty) return const SizedBox.shrink();

    final riskLevel = widget.riskLevel.toUpperCase().trim();
    final isHigh = riskLevel == 'HIGH';
    final isMedium = riskLevel == 'MEDIUM';
    final badgeColor = _riskColor(riskLevel);

    // The midwife's palette, not a saturated warning banner.
    //
    // ProfileRiskCard states a high-risk pregnancy on pale rose with a soft
    // border and deep rose text. This card was a solid red-to-crimson gradient
    // with white type — the visual language of an emergency — for a status
    // that means "your midwife will want to see you more often". Same
    // information, told the way the clinician's own screen tells it.
    final Color surface = isHigh
        ? const Color(0xFFFFF1F2)
        : isMedium
            ? const Color(0xFFFFF8EA)
            : const Color(0xFFF0FDF4);
    final Color outline = isHigh
        ? const Color(0xFFFECDD3)
        : isMedium
            ? const Color(0xFFFFE1A3)
            : const Color(0xFFBBF7D0);
    final Color ink = isHigh
        ? const Color(0xFF9F1239)
        : isMedium
            ? const Color(0xFF8A632D)
            : const Color(0xFF15803D);

    final riskFactors = _personalizedWarnings.isNotEmpty
        ? _personalizedWarnings
        : (widget.riskFactors ?? []);

    String riskNote = '';
    if (isHigh) {
      riskNote = _translate(
        'Tap to see what your midwife is watching.',
        'I-tap para makita kung ano ang binabantayan ng iyong midwife.',
        language,
      );
    } else if (isMedium) {
      riskNote = _translate(
        'Tap to see what to keep an eye on.',
        'I-tap para makita kung ano ang dapat bantayan.',
        language,
      );
    } else {
      riskNote = _translate(
        'Keep going to your checkups as usual.',
        'Ipagpatuloy lang ang mga karaniwang checkup.',
        language,
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _showSmartRiskSheet(language, riskLevel, badgeColor, riskFactors, riskNote),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: outline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  // An outlined mark rather than a filled warning triangle.
                  // The triangle is the icon an app uses when something has
                  // gone wrong right now.
                  isHigh
                      ? Icons.info_outline_rounded
                      : isMedium
                          ? Icons.info_outline_rounded
                          : Icons.check_circle_outline_rounded,
                  color: ink,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // No "Prenatal Risk Summary" eyebrow. It labelled the card
                    // with the name of a clinical artefact before saying
                    // anything, and the line beneath it says what this is.
                    Text(
                      // Named for what happens next, not for a risk tier.
                      // "HIGH RISK STATUS" is a label a mother carries around
                      // all day; "needs closer monitoring" is a plan, and it
                      // is the same thing the record actually means.
                      _translate(
                        isHigh
                            ? 'Your pregnancy needs closer monitoring'
                            : isMedium
                                ? 'A few things to keep an eye on'
                                : 'Your pregnancy is on track',
                        isHigh
                            ? 'Kailangan ng mas malapit na pagbantay ang iyong pagbubuntis'
                            : isMedium
                                ? 'May ilang bagay na dapat bantayan'
                                : 'Maayos ang takbo ng iyong pagbubuntis',
                        language,
                      ),
                      style: TextStyle(
                        color: ink,
                        fontSize: 16.5,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      riskNote,
                      style: TextStyle(
                        color: ink.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: ink, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showSmartRiskSheet(
    AppLanguage language,
    String riskLevel,
    Color badgeColor,
    List<String> riskFactors,
    String riskNote,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _translate('Smart Risk Assessment', 'Pagsusuri ng Panganib', language),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          riskLevel == 'HIGH' ? Icons.warning_rounded : riskLevel == 'MEDIUM' ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                          color: badgeColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                riskLevel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: badgeColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                riskNote,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textPrimary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _translate('Key Risk Factors & Findings', 'Mga Salik ng Panganib at Natuklasan', language),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (riskFactors.isNotEmpty) ...[
                    ...riskFactors.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Icon(Icons.circle, size: 6, color: badgeColor),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  f,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ))
                  ] else ...[
                    Text(
                      _translate('No active risk factors detected during recent consultations.', 'Walang nakitang aktibong salik ng panganib sa mga nakaraang checkup.', language),
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (widget.suggestedActions != null && widget.suggestedActions!.isNotEmpty) ...[
                    Text(
                      _translate('Recommended Care Plan Actions', 'Mga Rekomendasyon sa Pangangalaga', language),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...widget.suggestedActions!.map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Icon(Icons.check, size: 10, color: AppColors.brandPrimary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  a,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ))
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(_translate('Understand & Close', 'Naiintindihan ko at Isara', language)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }









  Widget _buildEmotionalNote(AppLanguage language, int trimesterIndex) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF8F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5E4DC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFBEBE3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.format_quote_rounded,
              size: 22,
              color: Color(0xFFE07A5F),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _translate('A Note for You', 'Paalala Para sa Iyo', language),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8D5B4C),
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  language == AppLanguage.filipino
                      ? _trimesterNoteFilipino[trimesterIndex]
                      : _data.emotionalNote,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B5149),
                    height: 1.6,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The illustration for the month she is in, from the same growth catalogue
  /// the Overview tab draws from. Null when the week falls outside it.
  ///
  /// Drawn cropped rather than letterboxed: the artwork is a close view of a
  /// belly with the baby at that stage, and filling the frame is what makes it
  /// read at a glance. Fitting the whole image inside left it small in a band
  /// of white.
  String? get _stageIllustration =>
      BabyBookRepository.stageForWeek(widget.week)?.imageAsset;

  /// The week a development entry belongs to, read from its own text.
  ///
  /// The entries are written as "Week 8 – All major organs are forming", so
  /// the number is already there; parsing it is what lets the rail know which
  /// ones she has passed. Null for an entry that names no week, which is
  /// treated as neither past nor current rather than guessed at.
  int? _milestoneWeek(String milestone) {
    final match = RegExp(r'week\s*(\d+)', caseSensitive: false)
        .firstMatch(milestone);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  Widget _buildBabyDevelopmentRail(AppLanguage language) {
    final entries = _data.babyDevelopment;
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF5E8ED)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++)
            Builder(builder: (context) {
              final week = _milestoneWeek(entries[index]);
              final isPast = week != null && week < widget.week;
              final isNow = week != null &&
                  (week == widget.week ||
                      (week > widget.week - 2 && week <= widget.week));

              final Color markerColour = isNow
                  ? AppColors.brandPrimary
                  : isPast
                      ? const Color(0xFF4E9D8E)
                      : const Color(0xFFD9CFD4);

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Column(
                        children: [
                          if (index == 0)
                            const Spacer()
                          else
                            Expanded(
                              child: Container(
                                width: 2,
                                color: const Color(0xFFFFD7E5),
                              ),
                            ),
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: markerColour,
                              shape: BoxShape.circle,
                              border: isNow
                                  ? Border.all(color: Colors.white, width: 3)
                                  : null,
                              boxShadow: isNow
                                  ? [
                                      BoxShadow(
                                        color: markerColour.withValues(
                                            alpha: 0.3),
                                        blurRadius: 0,
                                        spreadRadius: 3,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isPast
                                ? const Icon(Icons.check_rounded,
                                    size: 11, color: Colors.white)
                                : null,
                          ),
                          if (index == entries.length - 1)
                            const Spacer()
                          else
                            Expanded(
                              child: Container(
                                width: 2,
                                color: const Color(0xFFFFD7E5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: index == 0 ? 0 : 8,
                          bottom: index == entries.length - 1 ? 0 : 8,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isNow
                                ? const Color(0xFFFFF4F8)
                                : const Color(0xFFFFFCFD),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isNow
                                  ? const Color(0xFFFFC7DB)
                                  : const Color(0xFFF5E8ED),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _translateContent(entries[index], language),
                                style: TextStyle(
                                  color: isNow
                                      ? AppColors.headingSoft
                                      : AppColors.inputText,
                                  fontSize: 13.5,
                                  height: 1.45,
                                  fontWeight: isNow
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              if (isNow) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _translate('Around now', 'Malapit na ngayon',
                                      language),
                                  style: const TextStyle(
                                    color: AppColors.brandText,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBabyTab(AppLanguage language) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // The same container the growth journey's stage card uses — white,
        // 24 radius, soft pink edge, one lifted shadow. The pink-on-pink panel
        // was a third card style on a page that already has two.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFFDFEB)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF69243F).withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // The month's illustration, the same artwork the Overview tab's
              // growth journey draws.
              //
              // This was a 👶 emoji in a white circle — a generic cartoon
              // where the other tab shows her baby at this stage. Using the
              // same picture is most of what makes the two tabs read as one
              // book rather than two designs.
              if (_stageIllustration != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    _stageIllustration!,
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => const SizedBox(
                      height: 72,
                      child: Center(
                        child: Text('👶', style: TextStyle(fontSize: 38)),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                _translate('Your Baby this Week', 'Ang Iyong Sanggol Ngayong Linggo', language),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _translate(
                  'Let\'s see how your little one is growing and developing.',
                  'Tingnan natin ang paglaki at pag-unlad ng iyong maliit na sanggol.',
                  language,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildBabyMeasurementChip(
                        label: _translate('Estimated Length', 'Tinatayang Haba', language),
                        value: widget.babySize,
                        icon: Icons.straighten_rounded,
                        color: const Color(0xFFF39C12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildBabyMeasurementChip(
                        label: _translate('Estimated Weight', 'Tinatayang Timbang', language),
                        value: widget.babyWeight,
                        icon: Icons.monitor_weight_outlined,
                        color: const Color(0xFF3498DB),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          title: _translate('Development Milestones', 'Mga Milestone ng Pag-unlad', language),
          icon: Icons.auto_awesome,
        ),
        const SizedBox(height: 10),
        // A connected rail, not a stack of separate cards.
        //
        // These entries are a sequence — week 4, then 6, then 8 — and drawing
        // them as loose boxes lost that, so a mother could not see at a glance
        // which ones her baby has already passed. The rail borrows the visual
        // grammar of the Pregnancy Milestones timeline on the Overview tab:
        // a spine, a marker per entry, and the ones behind her marked done.
        _buildBabyDevelopmentRail(language),
        const SizedBox(height: 20),
        _SectionHeader(
          title: _translate('Changes in Your Body', 'Mga Pagbabago sa Iyong Katawan', language),
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 10),
        _buildMotherChangesPanel(language),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildBabyMeasurementChip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMotherChangesPanel(AppLanguage language) {
    return _Card(
      child: Column(
        children: _data.motherChanges.map((change) {
          String tip = '';
          final changeLower = change.toLowerCase();
          if (changeLower.contains('breast')) {
            tip = _translate('Supportive maternity bras and cool compresses provide comfort.', 'Ang pagsuot ng malambot na maternity bra at malamig na compress ay makakatulong.', language);
          } else if (changeLower.contains('urination')) {
            tip = _translate('Empty your bladder fully. Do not restrict water intake; stay hydrated.', 'Umihi nang buo. Huwag bawasan ang pag-inom ng tubig upang maiwasan ang dehydration at UTI.', language);
          } else if (changeLower.contains('fatigue')) {
            tip = _translate('Listen to your body. Take 20-minute power naps and prioritize sleep.', 'Makinig sa iyong katawan. Matulog nang maaga at magkaroon ng maikling naps sa maghapon.', language);
          } else if (changeLower.contains('stretch')) {
            tip = _translate('Apply safe moisturizers or natural oils to ease itching and dry skin.', 'Maglagay ng moisturizer o natural na langis upang maibsan ang pangangati at dry skin.', language);
          } else if (changeLower.contains('back pain') || changeLower.contains('posture')) {
            tip = _translate('Maintain good posture, wear low-heeled shoes, and use support pillows.', 'Panatilihin ang maayos na tindig, iwasan ang takong, at gumamit ng unan sa likod kapag natutulog.', language);
          } else if (changeLower.contains('braxton')) {
            tip = _translate('Change your position or walk around. Drink a large glass of warm water.', 'Magpalit ng posisyon o maglakad-lakad. Uminom din ng isang basong maligamgam na tubig.', language);
          } else {
            tip = _translate('Talk to your midwife if this causes you significant discomfort.', 'Kausapin ang iyong midwife kung ito ay nagdudulot ng matinding abala sa iyo.', language);
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.brandPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _translateContent(change, language),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tip,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSymptomsTab(AppLanguage language) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          color: const Color(0xFFF7F9FC),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.brandPrimary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _translate('Midwife Symptom Guidance', 'Gabay sa Sintomas mula sa Midwife', language),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _translate(
                        'Many body changes are normal. Below are symptoms reported in your consultations and general information for your trimester. Report any new severe changes to your midwife.',
                        'Maraming pagbabago sa katawan ang normal. Nasa ibaba ang mga sintomas na naitala sa iyong checkup at pangkalahatang payo para sa iyong trimester. Report anumang bagong malalang sintomas sa iyong midwife.',
                        language,
                      ),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_personalizedSymptoms.isNotEmpty) ...[
          _SectionHeader(
            title: _translate('Active & Reported Symptoms', 'Iyong Mga Naiulat na Sintomas', language),
            icon: Icons.assignment_turned_in_outlined,
          ),
          const SizedBox(height: 10),
          ..._personalizedSymptoms.map((symptom) => _buildSymptomTile(
                name: symptom,
                desc: _translate(
                  'This symptom is officially recorded in your prenatal chart. Follow the care guidelines provided by your midwife.',
                  'Ang sintomas na ito ay opisyal na nakatala sa iyong prenatal chart. Sundin ang mga tagubilin ng iyong midwife.',
                  language,
                ),
                icon: Icons.checklist_rounded,
                isReported: true,
                language: language,
              )),
          const SizedBox(height: 16),
        ],
        _SectionHeader(
          // "Normal Physiological Changes" is a phrase from a textbook. This
          // says the same thing and also says the reassuring part out loud.
          title: _translate('What many mothers feel now',
              'Ang nararamdaman ng maraming ina ngayon', language),
          icon: Icons.spa_outlined,
        ),
        const SizedBox(height: 10),
        ..._data.commonSymptoms.map((symptom) {
          String whyItHappens = '';
          final sName = symptom.name.toLowerCase();
          if (sName.contains('morning') || sName.contains('nausea')) {
            whyItHappens = _translate('Triggered by rising hCG hormone and estrogen levels in early pregnancy.', 'Sanhi ng tumataas na hCG hormone at estrogen sa unang yugto ng pagbubuntis.', language);
          } else if (sName.contains('fatigue')) {
            whyItHappens = _translate('Your body is producing more blood and using energy to build the placenta.', 'Ang iyong katawan ay gumagawa ng mas maraming dugo at gumagamit ng enerhiya para mabuo ang inunan.', language);
          } else if (sName.contains('heartburn')) {
            whyItHappens = _translate('Pregnancy hormones relax the valve between your stomach and esophagus.', 'Rinirelaks ng hormones ang balbula sa pagitan ng sikmura at esophagus, kaya umaakyat ang asido.', language);
          } else if (sName.contains('back pain')) {
            whyItHappens = _translate('As your baby grows, your center of gravity shifts and ligaments loosen.', 'Habang lumalaki ang sanggol, nagbabago ang sentro ng balanse at lumuluwag ang mga ligament.', language);
          } else {
            // No filler.
            //
            // Everything without a specific explanation used to get "A normal
            // physiological response to gestational hormonal shifts" — the
            // same sentence, in the same italics, under three cards in a row.
            // Repetition on that scale teaches a mother to skip the line, and
            // it takes the specific explanations above down with it. An entry
            // with nothing particular to say now says nothing.
            whyItHappens = '';
          }

          return _buildSymptomTile(
            name: symptom.name,
            desc: symptom.tip,
            why: whyItHappens,
            icon: symptom.icon,
            isReported: false,
            language: language,
          );
        }),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSymptomTile({
    required String name,
    required String desc,
    String? why,
    required IconData icon,
    required bool isReported,
    required AppLanguage language,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isReported ? AppColors.brandPrimary.withValues(alpha: 0.4) : const Color(0xFFF5E8ED),
          width: isReported ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pink, not the cold blue-grey it used. That grey tile was the one
          // piece of slate in a pink app, and it made every ordinary symptom
          // look switched off.
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDF4),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              icon,
              size: 23,
              color: isReported ? AppColors.brandPrimary : AppColors.brandText,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _translateContent(name, language),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    height: 1.3,
                    color: AppColors.headingSoft,
                  ),
                ),
                if (why != null && why.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    why,
                    // Upright, not italic. A whole paragraph set in italics is
                    // harder to read, and it made the explanation look like an
                    // aside rather than the answer to "why is this happening".
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.inputText,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                // The tip in its own tinted strip.
                //
                // It is the only line on the card she can act on, and it was
                // the smallest and faintest thing there — a 12pt grey line
                // below a 11pt grey line.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7FA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded,
                          size: 18, color: AppColors.brandText),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _translateContent(desc, language),
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AppColors.inputText,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionTab(AppLanguage language) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // The app's own palette, not the teal-on-mint this card used — the
        // only green surface in the mother's app, which made the tab look
        // borrowed from somewhere else.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF5E4EC)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFFFF8FBC), AppColors.brandPrimary],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.restaurant_rounded,
                    color: Colors.white, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // "Eating for Two" is the phrase most often taken to
                      // mean double portions, which is the opposite of the
                      // advice underneath it.
                      _translate('Eating well while pregnant',
                          'Wastong pagkain habang buntis', language),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16.5,
                        color: AppColors.headingSoft,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _translate(
                        'You do not need to eat twice as much — what matters is what you eat. Aim for foods rich in iron, calcium, folate and protein.',
                        'Hindi mo kailangang kumain nang doble — ang mahalaga ay kung ano ang kinakain mo. Piliin ang mga pagkaing mayaman sa iron, calcium, folate at protina.',
                        language,
                      ),
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.inputText,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_activeAllergies.isNotEmpty) ...[
          _buildAllergySubstitutesCard(language),
          const SizedBox(height: 16),
        ],
        _SectionHeader(
          title: _translate('Key Nutrients This Trimester', 'Pangunahing Nutrisyon ngayong Trimester', language),
          icon: Icons.food_bank_outlined,
        ),
        const SizedBox(height: 10),
        ..._data.nutritionTips
            .where((tip) {
              if (_activeAllergies.isEmpty) return true;
              final foodLower = tip.food.toLowerCase();
              for (final allergen in _activeAllergies) {
                if (foodLower.contains(allergen) || allergen.contains(foodLower.split('(').first.trim())) {
                  return false;
                }
              }
              return true;
            })
            .map((tip) => _NutritionCard(
              tip: tip,
              language: language,
            )),
        const SizedBox(height: 20),
        _SectionHeader(
          title: _translate('Foods to skip for now', 'Mga pagkaing iwasan muna', language),
          icon: Icons.block_outlined,
        ),
        const SizedBox(height: 10),
        _buildFoodsToAvoidCard(language),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildAllergySubstitutesCard(AppLanguage language) {
    List<String> substituteTips = [];
    bool hasDairy = false;
    bool hasPeanut = false;
    bool hasSeafood = false;
    
    for (final allergen in _activeAllergies) {
      if (allergen.contains('dairy') || allergen.contains('gatas') || allergen.contains('milk')) {
        hasDairy = true;
      } else if (allergen.contains('peanut') || allergen.contains('mani') || allergen.contains('nut')) {
        hasPeanut = true;
      } else if (allergen.contains('seafood') || allergen.contains('isda') || allergen.contains('fish') || allergen.contains('shrimp')) {
        hasSeafood = true;
      }
    }

    if (hasDairy) {
      substituteTips.add(_translate(
        '• Calcium alternatives: Broccoli, kale, spinach, almonds, sesame seeds, and calcium-fortified plant milks (soy/almond).',
        '• Kapalit sa Calcium: Brokoli, kale, spinach, almonds, buto ng linga, at gatas na gawa sa halaman (toyo/almond) na may dagdag na calcium.',
        language,
      ));
    }
    if (hasPeanut) {
      substituteTips.add(_translate(
        '• Healthy fat alternatives: Pumpkin seeds, sunflower seeds, chia seeds, avocados, and olive oil.',
        '• Kapalit sa Healthy Fats: Buto ng kalabasa, buto ng sunflower, chia seeds, abokado, at olive oil.',
        language,
      ));
    }
    if (hasSeafood) {
      substituteTips.add(_translate(
        '• Omega-3 / DHA alternatives: Chia seeds, flaxseeds, walnuts, Brussels sprouts, or high-quality prenatal vitamins containing algal oil.',
        '• Kapalit sa Omega-3: Chia seeds, flaxseeds, walnuts, Brussels sprouts, o prenatal vitamins na may langis ng lumot (algal oil).',
        language,
      ));
    }
    if (substituteTips.isEmpty) {
      substituteTips.add(_translate(
        '• Focus on green leafy vegetables, lean chicken, beans, lentils, and safe seeds to meet protein and iron needs.',
        '• Kumain ng mga madahong gulay, manok, beans, lentils, at ligtas na buto para sa sapat na protina at iron.',
        language,
      ));
    }

    // Not an alert.
    //
    // This was an orange panel headed "Active Allergy Alert" behind a warning
    // triangle, for a fact her midwife recorded and she has lived with for
    // years. Nothing is wrong; the list below simply has her allergens taken
    // out of it. Stated calmly, in the app's palette, as what it is: the food
    // list adjusted to her record.
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF5E4EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDF4),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: AppColors.brandText, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _translate(
                    'Adjusted for your allergies',
                    'Inayon sa iyong mga allergy',
                    language,
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.headingSoft,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The allergens themselves, as chips rather than buried in a
          // sentence — this is the line she would check for a mistake.
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final allergen in _activeAllergies)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7FA),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFF7DCE7)),
                  ),
                  child: Text(
                    allergen,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandText,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _translate(
              'Foods you are allergic to have been left out of the list below.',
              'Ang mga pagkaing ikaw ay allergic ay hindi kasama sa listahan sa ibaba.',
              language,
            ),
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.inputText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            // Not "Clinician Recommended Substitutes". No clinician chose
            // these for her — they are general swaps the app applies from her
            // recorded allergens, and claiming otherwise borrows an authority
            // the list does not have.
            _translate('What you can eat instead',
                'Mga puwede mong kainin sa halip', language),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.headingSoft,
            ),
          ),
          const SizedBox(height: 8),
          ...substituteTips.map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 7),
                      decoration: const BoxDecoration(
                        color: AppColors.brandPrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        // The stored strings start with a literal bullet,
                        // which would sit beside the drawn one.
                        tip.startsWith('•') ? tip.substring(1).trim() : tip,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.inputText,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
          Text(
            _translate(
              'These are general swaps. Your midwife can tell you what suits your pregnancy.',
              'Mga karaniwang kapalit ito. Ang iyong midwife ang makakapagsabi kung ano ang bagay sa iyong pagbubuntis.',
              language,
            ),
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodsToAvoidCard(AppLanguage language) {
    final listToAvoid = [
      (
        _translate('Raw or undercooked meat and eggs', 'Hilaw o hindi lutong lubos na karne at itlog', language),
        _translate('These can carry germs that make you very sick and can reach your baby. Cook meat and eggs all the way through.', 'May mga mikrobyo ito na puwedeng magpasakit sa iyo at makaabot sa sanggol. Lutuin nang husto ang karne at itlog.', language)
      ),
      (
        _translate('High-mercury fish (shark, swordfish, king mackerel)', 'Isdang mataas sa mercury tulad ng pating, swordfish', language),
        _translate('These fish hold a lot of mercury, which can harm your baby\'s growing brain. Smaller fish like tilapia, bangus and galunggong are fine.', 'Marami itong mercury na puwedeng makasama sa utak ng sanggol. Ayos lang ang maliliit na isda tulad ng tilapia, bangus at galunggong.', language)
      ),
      (
        _translate('Unpasteurized dairy and soft cheeses', 'Gatas na hindi pasteurized at malambot na keso', language),
        _translate('These can carry germs that are dangerous for your baby. Boiled or pasteurised milk is safe.', 'May mga mikrobyo ito na delikado sa sanggol. Ligtas ang pinakuluang o pasteurised na gatas.', language)
      ),
      (
        _translate('Alcohol of any kind', 'Alak ng anumang uri', language),
        _translate('There is no amount that is known to be safe in pregnancy, so it is best skipped altogether.', 'Walang dami ng alak na alam na ligtas sa pagbubuntis, kaya mas mabuting iwasan ito nang tuluyan.', language)
      ),
      (
        _translate('Too much coffee or tea', 'Sobrang kape o tsaa', language),
        _translate('About two cups of coffee a day is the usual limit. More than that can slow your baby\'s growth.', 'Mga dalawang tasa ng kape sa isang araw ang karaniwang limitasyon. Ang sobra ay puwedeng makabagal sa paglaki ng sanggol.', language)
      ),
      (
        _translate('Processed junk food and excess sugar', 'Pinrosesong junk food at labis na asukal', language),
        _translate('These fill you up without feeding your baby, and too much sugar makes diabetes in pregnancy more likely.', 'Nakakabusog ito pero walang sustansya para sa sanggol, at ang sobrang asukal ay nagpapataas ng tsansa ng diabetes sa pagbubuntis.', language)
      ),
    ];

    return _Card(
      child: Column(
        children: listToAvoid.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A muted stop mark, not a red cancel sign repeated six times
                // down the card. The list is advice about the weekly shop, not
                // six errors.
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.do_not_disturb_on_outlined,
                      size: 18, color: Color(0xFF9F1239)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: AppColors.headingSoft,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$2,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.inputText,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWarningsTab(AppLanguage language) {
    final emergencies = _data.warningSigns.where((w) => w.isEmergency).toList();
    final watchFor = _data.warningSigns.where((w) => !w.isEmergency).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildEmergencyPanicBar(language),
        const SizedBox(height: 16),
        _Card(
          color: const Color(0xFFF9EBEA).withValues(alpha: 0.3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: AppColors.brandPrimary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _translate(
                    'Most pregnancies progress smoothly. These signs are shared so you feel prepared — not to worry you. Trust your instincts, and seek care immediately if you feel something is wrong.',
                    'Karamihan ng pagbubuntis ay maayos ang takbo. Ibinahagi ang mga palatandaang ito para maging handa ka — hindi para mag-alala. Magtiwala sa iyong sarili, at humingi agad ng tulong kung may kakaiba.',
                    language,
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_personalizedWarnings.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9E7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFADBD8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.medical_services_outlined, color: AppColors.warning, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _translate('Your Active Risk Concerns (From Consultations)', 'Salik ng Panganib na Naitala sa Checkup', language),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: Color(0xFF78281F),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._personalizedWarnings.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              w,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFDEDEC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFADBD8), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.error.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.gpp_maybe_rounded, color: AppColors.error, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _translate('🚨 OBSTETRIC EMERGENCIES - GO TO HOSPITAL NOW', '🚨 AGAD PUMUNTA SA OSPITAL SA MGA PALATANDAANG ITO', language),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.error,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFFADBD8), height: 20),
              ...emergencies.map((warning) => _buildWarningRow(
                    sign: warning.sign,
                    isEmergency: true,
                    language: language,
                  )),
            ],
          ),
        ),
        if (watchFor.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9E7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFCF3CF), width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.visibility_outlined, color: AppColors.warning, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _translate('⚠️ Signs to Monitor & Inform Midwife', '⚠️ Mga Palatandaang Dapat Ipaalam sa Midwife', language),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Color(0xFF7E5109),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFFFCF3CF), height: 20),
                ...watchFor.map((warning) => _buildWarningRow(
                      sign: warning.sign,
                      isEmergency: false,
                      language: language,
                    )),
              ],
            ),
          ),
        ],
        if (widget.week >= 20) ...[
          const SizedBox(height: 16),
          _Card(
            color: const Color(0xFFF5EEF8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.favorite_rounded, color: AppColors.brandPrimary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _translate('Fetal Kick Counts (From Week 20)', 'Bilang ng Sipa ng Sanggol (Mula Linggo 20)', language),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.brandText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _translate(
                    'Find a comfortable position daily and count baby movements. You should feel at least 10 kicks/flutters within 2 hours. If you feel fewer, contact your midwife immediately.',
                    'Humanap ng komportableng posisyon araw-araw at bilangin ang galaw ng sanggol. Dapat makaramdam ng hindi bababa sa 10 sipa sa loob ng 2 oras. Kung mas kaunti, tawagan agad ang midwife.',
                    language,
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildEmergencyContactsList(language),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildWarningRow({
    required String sign,
    required bool isEmergency,
    required AppLanguage language,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isEmergency ? Icons.report_problem_rounded : Icons.info_outline_rounded,
            size: 16,
            color: isEmergency ? AppColors.error : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _translateContent(sign, language),
              style: TextStyle(
                fontSize: 13,
                color: isEmergency ? const Color(0xFF78281F) : const Color(0xFF7E5109),
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyPanicBar(AppLanguage language) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE74C3C), Color(0xFFC0392B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE74C3C).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_in_talk, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _translate('EMERGENCY SPEED DIAL', 'BILIS-TAWAG SA EMERGENCY', language),
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  _translate('Instantly call for immediate obstetric assistance.', 'Mabilis na tawag para sa agarang tulong sa panganganak.', language),
                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _launchPhoneDialer('911'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFC0392B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              elevation: 2,
            ),
            child: Text(
              _translate('CALL NOW', 'TAWAG NA', language),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContactsList(AppLanguage language) {
    final contacts = [
      (
        _translate('Barangay Health Station (Midwife)', 'Barangay Health Station (Midwife)', language),
        '09123456789',
        Icons.local_hospital
      ),
      (
        _translate('Municipal Health Office', 'Municipal Health Office', language),
        '09234567890',
        Icons.health_and_safety
      ),
      (
        _translate('Local Disaster Risk Reduction Management Office (LDRRMO)', 'Lokal na Ambulansya o NDRRMO', language),
        '09345678901',
        Icons.airport_shuttle
      ),
      (
        _translate('General Emergency Services', 'Pangkalahatang Emergency Services', language),
        '911',
        Icons.phone_in_talk
      ),
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.contact_phone_outlined, color: AppColors.brandPrimary, size: 20),
              const SizedBox(width: 8),
              Text(
                _translate('Direct Dial Contacts', 'Mga Numerong Matatawagan Agad', language),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _translate(
              'Tap on any row below to launch your phone dialer app with the number pre-filled.',
              'Pindutin ang kahit aling hilera sa ibaba upang tawagan ang numero sa iyong telepono.',
              language,
            ),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const Divider(height: 20),
          ...contacts.map((contact) => InkWell(
                onTap: () => _launchPhoneDialer(contact.$2),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(contact.$3, color: AppColors.brandPrimary, size: 18),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              contact.$1,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              contact.$2,
                              style: const TextStyle(fontSize: 12, color: AppColors.brandPrimary, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.phone_forwarded, size: 16, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _launchPhoneDialer(String number) async {
    try {
      final Uri uri = Uri(scheme: 'tel', path: number);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        debugPrint('Could not launch dialer for number: $number');
      }
    } catch (e) {
      debugPrint('Error launching dialer: $e');
    }
  }
}

// ============================================
// REUSABLE WIDGETS
// ============================================

class _Card extends StatelessWidget {
  final Widget child;
  final Color? color;

  const _Card({required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    // The Baby Book's panel treatment, applied here so the two pregnancy
    // screens read as one product: a wider 22px radius, the warm #F5E8ED
    // border instead of a grey hairline, and a soft plum shadow with enough
    // blur to lift the card off the page. The structure of this page is
    // unchanged — only its surface.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF5E8ED)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69243F).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.brandPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 16, color: AppColors.brandPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(
          // Larger and tighter, matching the Baby Book's section titles.
          // A heading that sat at the same size as its own body text was
          // doing none of the work a heading exists to do.
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppColors.headingSoft,
            ),
          ),
        ),
      ],
    );
  }
}

class _NutritionCard extends StatelessWidget {
  final _NutritionTip tip;
  final AppLanguage language;

  const _NutritionCard({required this.tip, required this.language});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5E8ED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDF4),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(tip.icon, size: 23, color: AppColors.brandText),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _translateContent(tip.food, language),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.3,
                    color: AppColors.headingSoft,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _translateContent(tip.benefit, language),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.inputText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Static hospital bag items
const _hospitalBagItems = [
  'Government-issued ID and PhilHealth card',
  'Maternity card or prenatal records',
  'Comfortable loose clothing and slippers',
  'Newborn onesies, blanket, and diapers',
  'Toiletries for you and baby',
  'Snacks and drinks for labor',
  'Phone charger',
  'Cash for hospital fees',
];
