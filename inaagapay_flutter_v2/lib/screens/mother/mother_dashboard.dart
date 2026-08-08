// lib/screens/mother/mother_dashboard.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../widgets/hero_card.dart';
import '../../widgets/main_button.dart';
import '../../widgets/app_input_field.dart';
import '../../models/baby_growth_model.dart';
import '../../models/weight_gain_models.dart';
import '../../services/auth_storage.dart';
import '../../services/language_service.dart';
import '../../services/mother_profile_service.dart';
import '../../services/supabase_service.dart';
import '../../services/weight_gain_engine.dart';
import 'mother_pregnancy_detail_page.dart';
import 'mother_chatbot_page.dart';
import 'mother_vitals_page.dart';

class MotherDashboard extends StatefulWidget {
  const MotherDashboard({super.key});

  @override
  State<MotherDashboard> createState() => _MotherDashboardState();
}

class _MotherDashboardState extends State<MotherDashboard> {
  bool _isLoading = true;
  String? _errorMessage;
  bool _isUnlinked = false;
  bool _isUnlinkedBannerDismissed = false;
  bool _isVitalsIncomplete = false;
  bool _isVitalsBannerDismissed = false;

  // Dashboard data
  int _week = 0;
  int _weeksLeft = 0;
  String _trimester = '—';
  String _dueDate = '—';
  String _firstName = '';
  bool _hasPregnancy = false;
  int _pregnancyId = 0;
  String _babySize = '—';
  String _babyWeight = '—';
  String _riskLevel = 'low';
  int _fetalCount = 1;
  DateTime? _lmpDate;
  DateTime? _eddDate;
  List<String>? _riskFactors;
  List<String>? _suggestedActions;

  // Latest vitals tracking variables
  double? _latestWeight;
  String? _latestBp;
  DateTime? _latestVitalsDate;
  String? _latestVitalsSource;
  WeightGainResult? _weightGainResult;
  double? _prePregnancyWeight;
  double? _heightCm;
  DateTime? _nextScheduleDate;

  static const Map<int, Map<String, String>> _babySizeByWeek = {
    4: {'fruit': 'Poppy seed', 'image': 'poppy.png'},
    5: {'fruit': 'Sesame seed', 'image': 'sesame.png'},
    6: {'fruit': 'Green Pea', 'image': 'pea.png'},
    7: {'fruit': 'Coffee Bean', 'image': 'coffee.png'},
    8: {'fruit': 'Blueberry', 'image': 'blueberry.png'},
    9: {'fruit': 'Raspberry', 'image': 'raspberry.png'},
    10: {'fruit': 'Cherry', 'image': 'cherry.png'},
    11: {'fruit': 'Strawberry', 'image': 'strawberry.png'},
    12: {'fruit': 'Lime', 'image': 'lime.png'},
    13: {'fruit': 'Plum', 'image': 'plum.png'},
    14: {'fruit': 'Lemon', 'image': 'lemon.png'},
    15: {'fruit': 'Peach', 'image': 'peach.png'},
    16: {'fruit': 'Apple', 'image': 'apple.png'},
    17: {'fruit': 'Avocado', 'image': 'avocado.png'},
    18: {'fruit': 'Large White Onion', 'image': 'onion.png'},
    19: {'fruit': 'Beetroot', 'image': 'beetroot.png'},
    20: {'fruit': 'Sweet Potato', 'image': 'sweet potato.png'},
    21: {'fruit': 'Taro (Gabi)', 'image': 'taro.png'},
    22: {'fruit': 'Carrot', 'image': 'carrot.png'},
    23: {'fruit': 'Banana', 'image': 'banana.png'},
    24: {'fruit': 'Ear of Corn', 'image': 'corn.png'},
    25: {'fruit': 'Cucumber', 'image': 'cucumber.png'},
    26: {'fruit': 'Eggplant', 'image': 'eggplant.png'},
    27: {'fruit': 'Lettuce', 'image': 'lettuce.png'},
    28: {'fruit': 'Cauliflower', 'image': 'cauliflower.png'},
    29: {'fruit': 'Cabbage', 'image': 'cabbage.png'},
    30: {'fruit': 'Coconut', 'image': 'coconut.png'},
    31: {'fruit': 'Pomelo', 'image': 'pomelo.png'},
    32: {'fruit': 'Pineapple', 'image': 'pineapple.png'},
    33: {'fruit': 'Melon', 'image': 'melon.png'},
    34: {'fruit': 'Papaya', 'image': 'papaya.png'},
    35: {'fruit': 'Kabocha Squash', 'image': 'kabocha.png'},
    36: {'fruit': 'Durian', 'image': 'durian.png'},
    37: {'fruit': 'Pumpkin', 'image': 'pumpkin.png'},
    38: {'fruit': 'Watermelon', 'image': 'watermelon.png'},
    39: {'fruit': 'Watermelon', 'image': 'watermelon.png'},
    40: {'fruit': 'Watermelon', 'image': 'watermelon.png'},
  };

  static const Map<int, String> _weeklyTipsEn = {
    4: 'Start taking folic acid if you haven\'t already — it helps your baby\'s brain and spine develop.',
    5: 'Morning sickness may start. Eat small, frequent meals and keep crackers by your bed.',
    6: 'Stay hydrated, mama! Aim for at least 8 glasses of water a day.',
    7: 'Your baby\'s heart is beating now. Rest when you need to — your body is working hard.',
    8: 'Avoid raw or undercooked food. Your immune system is more sensitive during pregnancy.',
    9: 'Start a pregnancy journal! Writing down how you feel can help you process this beautiful journey.',
    10: 'Book your first prenatal checkup if you haven\'t yet. Early care means a healthier pregnancy.',
    11: 'Gentle walks can ease nausea and boost your mood. Even 15 minutes helps.',
    12: 'You\'re almost done with the first trimester! The risk of miscarriage drops significantly after this week.',
    13: 'Your energy may start returning soon. Enjoy the second trimester — many mamas feel their best!',
    14: 'Your baby can now make facial expressions. Talk to your little one — they can hear you.',
    15: 'Eat iron-rich foods like leafy greens and lean meat to support your growing blood supply.',
    16: 'You might start feeling tiny flutters — those are your baby\'s first movements!',
    17: 'Stretch gently before bed to help with leg cramps. Magnesium-rich foods like bananas can help too.',
    18: 'Your baby is the size of a pepper now. Consider starting a baby registry!',
    19: 'Sleep on your left side when you can — it improves blood flow to your baby.',
    20: 'Halfway there! Celebrate this milestone. You\'re doing amazing, mama.',
    21: 'Your baby can now taste what you eat through the amniotic fluid. Eat a variety of healthy foods!',
    22: 'Practice deep breathing exercises. They\'ll help you during labor and reduce stress now.',
    23: 'Your baby can hear sounds outside the womb. Play music or read stories to them.',
    24: 'Stay active with low-impact exercises like swimming or prenatal yoga.',
    25: 'Start thinking about your birth plan. Talk to your midwife about your preferences.',
    26: 'Your baby\'s eyes are opening! Keep up with your prenatal vitamins.',
    27: 'Third trimester is coming! Make sure you\'re getting enough calcium for baby\'s bones.',
    28: 'Welcome to the third trimester! Your baby is practicing breathing movements.',
    29: 'Pack a hospital bag soon — it\'s never too early to be prepared.',
    30: 'Kegel exercises can strengthen your pelvic floor for labor. Try doing them daily.',
    31: 'Rest with your feet elevated if you notice swelling. It\'s normal but tell your midwife if it\'s sudden.',
    32: 'Your baby is gaining weight fast now. Eat protein-rich meals to support their growth.',
    33: 'Practice relaxation techniques. A calm mama helps baby feel safe.',
    34: 'Count your baby\'s kicks — you should feel at least 10 movements in 2 hours.',
    35: 'Prepare your home for the baby. Nesting instincts are natural and healthy!',
    36: 'Your baby is almost full-term. Keep attending your prenatal checkups.',
    37: 'Baby is head-down by now in most cases. Talk to your midwife about your delivery plan.',
    38: 'Stay close to home and keep your phone charged — baby could come soon!',
    39: 'You\'re almost there, mama! Try to rest as much as possible. Your body knows what to do.',
    40: 'Your due date is here! Remember — babies come on their own time. Trust the process, mama.',
  };

  static const Map<int, String> _weeklyTipsTl = {
    4: 'Simulan ang pag-inom ng folic acid kung hindi pa — nakatutulong ito sa pagbuo ng utak at spine ng iyong baby.',
    5: 'Maaaring magsimula ang morning sickness. Kumain ng maliliit at madalas na bahagi, at magtabi ng biskwit sa tabi ng higaan.',
    6: 'Uminom ng sapat na tubig, mama! Sikaping uminom ng hindi bababa sa 8 basong tubig bawat araw.',
    7: 'Tumitibok na ang puso ng iyong baby ngayon. Magpahinga kapag kailangan — nagtatrabaho ng husto ang iyong katawan.',
    8: 'Iwasan ang hilaw o hindi gaanong lutong pagkain. Mas sensitibo ang iyong immune system habang buntis.',
    9: 'Magsimula ng pregnancy journal! Ang pagsulat ng iyong nararamdaman ay makatutulong sa magandang paglalakbay na ito.',
    10: 'Magpa-schedule na ng iyong unang prenatal checkup kung hindi pa nagagawa. Ang maagang pangangalaga ay nangangahulugan ng mas malusog na pagbubuntis.',
    11: 'Ang banayad na paglalakad ay makababawas sa pagduduwal at makapagpapabuti ng iyong mood. Kahit 15 minuto lang ay malaking tulong na.',
    12: 'Malapat ka nang matapos sa unang trimester! Malaki ang nababawas sa panganib ng pagkalaglag pagkatapos ng linggong ito.',
    13: 'Maaaring magbalik na ang iyong lakas sa lalong madaling panahon. I-enjoy ang ikalawang trimester — maraming nanay ang nakararamdam ng pinakamainam na lagay rito!',
    14: 'Nakagagawa na ng mga facial expression ang iyong baby. Kausapin ang iyong maliit — naririnig ka na nila.',
    15: 'Kumain ng mga pagkaing mayaman sa iron tulad ng madahong gulay at karne para suportahan ang iyong dumadaming blood supply.',
    16: 'Maaari ka nang makaramdam ng mahihinang sipa o flutters — iyan ang mga unang galaw ng iyong baby!',
    17: 'Mag-stretch nang dahan-dahan bago matulog para maiwasan ang leg cramps. Makatutulong din ang saging na mayaman sa magnesium.',
    18: 'Ang baby mo ay kasinglaki na ng sili ngayon. Pag-isipan ang paggawa ng baby registry!',
    19: 'Matulog sa iyong kaliwang bahagi kung maaari — nagpapabuti ito ng daloy ng dugo patungo sa iyong baby.',
    20: 'Nasa kalagitnaan ka na! Ipagdiwang ang milestone na ito. Mahusay ang ginagawa mo, mama.',
    21: 'Nalalasahan na ng iyong baby ang iyong kinakain sa pamamagitan ng amniotic fluid. Kumain ng iba\'t ibang masusustansyang pagkain!',
    22: 'Magsanay ng malalalim na paghinga. Makatutulong ito sa iyo sa oras ng panganganak at magpapababa ng stress ngayon.',
    23: 'Naririnig ng iyong baby ang mga tunog sa labas ng sinapupunan. Patugtugan ng musika o basahan sila ng mga kuwento.',
    24: 'Manatiling aktibo gamit ang mga ehersisyong low-impact tulad ng paglangoy o prenatal yoga.',
    25: 'Simulan nang pag-isipan ang iyong birth plan. Kausapin ang iyong midwife tungkol sa iyong mga kagustuhan.',
    26: 'Idinidilat na ng iyong baby ang kanyang mga mata! Ipatuloy ang pag-inom ng iyong mga prenatal vitamin.',
    27: 'Papalapit na ang ikatlong trimester! Siguraduhing nakakukuha ka ng sapat na calcium para sa mga buto ng baby.',
    28: 'Maligayang pagdating sa ikatlong trimester! Ang iyong baby ay nagsasanay na sa paghinga.',
    29: 'Mag-impake na ng hospital bag — hindi kailanman masyadong maaga para maging handa.',
    30: 'Ang Kegel exercises ay nagpapalakas ng pelvic floor para sa panganganak. Subukang gawin ito araw-araw.',
    31: 'Magpahinga na nakataas ang mga paa kung may pamamanas. Normal ito ngunit sabihin sa iyong midwife kung ito ay biglaan.',
    32: 'Mabilis nang nagkakalaman ang iyong baby ngayon. Kumain ng pagkaing mayaman sa protina para sa kanyang paglaki.',
    33: 'Magsanay ng mga relaxation technique. Ang kalmadong nanay ay tumutulong sa baby na makaramdam ng ligtas.',
    34: 'Bilangin ang mga sipa ng iyong baby — dapat makaramdam ng hindi bababa sa 10 galaw sa loob ng 2 oras.',
    35: 'Ihanda ang iyong tahanan para sa baby. Ang nesting instincts ay natural at malusog!',
    36: 'Malapit nang maging full-term ang iyong baby. Ipatuloy ang pagdalo sa iyong mga prenatal checkup.',
    37: 'Nasa head-down position na ang baby sa karamihan ng pagkakataon. Kausapin ang iyong midwife tungkol sa delivery plan.',
    38: 'Manatiling malapit sa bahay at laging naka-charge ang telepono — maaaring dumating na ang baby anumang oras!',
    39: 'Malapit na, mama! Subukang magpahinga hangga\'t maaari. Alam ng iyong katawan ang dapat gawin.',
    40: 'Dumating na ang iyong takdang araw! Tandaan — lumalabas ang baby sa sarili nilang oras. Magtiwala sa proseso, mama.',
  };

  int _parseInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? fallback;
    if (value is num) return value.toInt();
    return fallback;
  }

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  String _localizedTrimester() {
    switch (_trimester) {
      case 'First Trimester':
        return _t('First Trimester', 'Unang Trimester');
      case 'Second Trimester':
        return _t('Second Trimester', 'Ikalawang Trimester');
      case 'Third Trimester':
        return _t('Third Trimester', 'Ikatlong Trimester');
      default:
        return _trimester;
    }
  }

  void _resetPregnancyData() {
    _week = 0;
    _weeksLeft = 0;
    _trimester = '—';
    _dueDate = '—';
    _hasPregnancy = false;
    _pregnancyId = 0;
    _babySize = '—';
    _babyWeight = '—';
    _riskLevel = 'low';
    _fetalCount = 1;
    _lmpDate = null;
    _eddDate = null;
    _riskFactors = null;
    _suggestedActions = null;
    _isUnlinked = false;
    _isVitalsIncomplete = false;
    _isVitalsBannerDismissed = false;
    _latestWeight = null;
    _latestBp = null;
    _latestVitalsDate = null;
    _latestVitalsSource = null;
    _weightGainResult = null;
    _prePregnancyWeight = null;
    _heightCm = null;
    _nextScheduleDate = null;
  }

  bool _requiresDeliveryDetails(String outcome) {
    return outcome == 'live_birth' || outcome == 'stillbirth';
  }

  String _dateIso(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _resetPregnancyData();
    });

    try {
      final motherId = await AuthStorage.getMotherId();
      debugPrint('=== DASHBOARD DEBUG ===');
      debugPrint('Mother ID: $motherId');

      if (motherId == null) {
        throw Exception(
            'Mother ID not found. Please log out and log in again.');
      }

      // Check if mother is linked to a BHC and fetch height
      final motherResponse = await SupabaseService.client
          .from('mothers')
          .select('assigned_bhc_id, height')
          .eq('mother_id', motherId)
          .maybeSingle();
      _isUnlinked =
          motherResponse == null || motherResponse['assigned_bhc_id'] == null;
      final double? motherHeight = motherResponse != null && motherResponse['height'] != null
          ? (motherResponse['height'] as num).toDouble()
          : null;

      // Get account info for name
      final accountId = await AuthStorage.getUserId();
      debugPrint('Account ID: $accountId');

      if (accountId != null) {
        final accountResponse = await SupabaseService.client
            .from('accounts')
            .select('first_name, last_name')
            .eq('account_id', accountId)
            .maybeSingle();

        debugPrint('Account response: $accountResponse');

        if (accountResponse != null) {
          final firstName = accountResponse['first_name']?.toString() ?? '';
          final lastName = accountResponse['last_name']?.toString() ?? '';
          _firstName = '$firstName $lastName'.trim();
          if (_firstName.isEmpty) _firstName = firstName;
        }
      }

      // Get current pregnancy data
      final List<dynamic> pregnancyResponse = await SupabaseService.client
          .from('pregnancies')
          .select('*')
          .eq('mother_id', motherId)
          .eq('status', 'ongoing');

      debugPrint('Pregnancy response: $pregnancyResponse');

      if (pregnancyResponse.isNotEmpty) {
        final Map<String, dynamic> pregnancy =
            pregnancyResponse.first as Map<String, dynamic>;
        _hasPregnancy = true;
        _pregnancyId = _parseInt(pregnancy['pregnancy_id']);

        final double? ppw = pregnancy['pre_pregnancy_weight'] != null
            ? (pregnancy['pre_pregnancy_weight'] as num).toDouble()
            : null;
        
        _heightCm = motherHeight;
        _prePregnancyWeight = ppw;
        _isVitalsIncomplete = (motherHeight == null || ppw == null);

        final String? lmpStr = pregnancy['last_menstrual_period'] as String?;
        final String? eddStr =
            pregnancy['expected_date_of_delivery'] as String?;

        if (lmpStr != null && lmpStr.isNotEmpty) {
          final DateTime lmp = DateTime.parse(lmpStr);
          _lmpDate = lmp;
          final DateTime now = DateTime.now();
          _week = now.difference(lmp).inDays ~/ 7;
          if (_week < 1) _week = 1;
          if (_week > 40) _week = 40;

          final babyGrowth = BabyGrowthData.getForWeek(_week);
          _babySize = babyGrowth.size;
          _babyWeight = babyGrowth.weight;

          _riskLevel = (pregnancy['pregnancy_risk_level'] as String? ?? 'Low')
              .toLowerCase();
          _fetalCount = _parseInt(pregnancy['fetal_count'], 1);

          DateTime edd;
          if (eddStr != null && eddStr.isNotEmpty) {
            edd = DateTime.parse(eddStr);
          } else {
            edd = lmp.add(const Duration(days: 280));
          }

          _eddDate = edd;
          _dueDate = DateFormat('MMMM d, yyyy').format(edd);

          _weeksLeft = _week > 0 ? 40 - _week : 0;
          if (_weeksLeft < 0) _weeksLeft = 0;

          if (_week <= 13) {
            _trimester = 'First Trimester';
          } else if (_week <= 27) {
            _trimester = 'Second Trimester';
          } else {
            _trimester = 'Third Trimester';
          }

          // Fetch risk factors and suggested actions for the detail page
          await _loadRiskData();
          await _loadLatestVitals();
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadRiskData() async {
    try {
      // Fetch latest risk assessment
      final riskData = await SupabaseService.client
          .from('pregnancy_risk_assessments')
          .select('pregnancy_risk_id')
          .eq('pregnancy_id', _pregnancyId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (riskData != null) {
        final riskId = riskData['pregnancy_risk_id'];

        // Fetch risk factors
        final List<dynamic> factorsData = await SupabaseService.client
            .from('pregnancy_risk_factors')
            .select('factor')
            .eq('pregnancy_risk_id', riskId);

        if (factorsData.isNotEmpty) {
          _riskFactors = factorsData.map((f) => f['factor'] as String).toList();
        }

        // Fetch AI recommendations
        final aiData = await SupabaseService.client
            .from('ai_responses')
            .select('response')
            .eq('reference_table', 'pregnancies')
            .eq('reference_id', _pregnancyId)
            .eq('response_type', 'recommendation')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (aiData != null && aiData['response'] is String) {
          final response = aiData['response'] as String;
          _suggestedActions = response
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .map((line) =>
                  line.replaceAll(RegExp(r'^[\d\-\.\*]+\s*'), '').trim())
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error loading risk data: $e');
      // Non-critical - don't fail the whole dashboard
    }
  }

  Future<void> _loadLatestVitals() async {
    try {
      // 1. Fetch latest prenatal checkup via clinical_encounters
      final latestEncounter = await SupabaseService.client
          .from('clinical_encounters')
          .select('''
            encounter_datetime,
            checkup:prenatal_checkups (
              checkup_weight,
              blood_pressure_systolic,
              blood_pressure_diastolic
            )
          ''')
          .eq('pregnancy_id', _pregnancyId)
          .eq('encounter_type', 'checkup')
          .order('encounter_datetime', ascending: false)
          .limit(1)
          .maybeSingle();

      Map<String, dynamic>? latestCheckup;
      if (latestEncounter != null) {
        final innerCheckup = latestEncounter['checkup'] as Map<String, dynamic>?;
        if (innerCheckup != null) {
          latestCheckup = {
            'checkup_weight': innerCheckup['checkup_weight'],
            'blood_pressure_systolic': innerCheckup['blood_pressure_systolic'],
            'blood_pressure_diastolic': innerCheckup['blood_pressure_diastolic'],
            'checkup_datetime': latestEncounter['encounter_datetime'],
          };
        }
      }

      // 2. Fetch latest maternal vitals
      final latestMaternal = await SupabaseService.client
          .from('maternal_vitals')
          .select('weight_kg, height_cm, recorded_at')
          .eq('pregnancy_id', _pregnancyId)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final checkup = latestCheckup;
      final maternal = latestMaternal;

      DateTime? checkupTime;
      if (checkup != null && checkup['checkup_datetime'] != null) {
        checkupTime = DateTime.tryParse(checkup['checkup_datetime'].toString());
      }

      DateTime? vitalTime;
      if (maternal != null && maternal['recorded_at'] != null) {
        vitalTime = DateTime.tryParse(maternal['recorded_at'].toString());
      }

      if (checkupTime != null && checkup != null && (vitalTime == null || checkupTime.isAfter(vitalTime))) {
        // Use checkup vitals
        _latestWeight = checkup['checkup_weight'] != null
            ? (checkup['checkup_weight'] as num).toDouble()
            : null;
        final sys = checkup['blood_pressure_systolic'];
        final dia = checkup['blood_pressure_diastolic'];
        _latestBp = (sys != null && dia != null) ? '$sys/$dia' : null;
        _latestVitalsDate = checkupTime;
        _latestVitalsSource = 'prenatal_checkup';
      } else if (vitalTime != null && maternal != null) {
        // Use maternal vitals
        _latestWeight = maternal['weight_kg'] != null
            ? (maternal['weight_kg'] as num).toDouble()
            : null;
        _latestBp = null; // No BP in self-logged vitals
        _latestVitalsDate = vitalTime;
        _latestVitalsSource = 'mother_self';
      }

      // 3. Fetch checkups for weight gain engine via clinical_encounters
      final checkupsRaw = await SupabaseService.client
          .from('clinical_encounters')
          .select('''
            checkup_datetime:encounter_datetime,
            age_of_gestation_weeks,
            age_of_gestation_days,
            checkup:prenatal_checkups (
              checkup_weight
            )
          ''')
          .eq('pregnancy_id', _pregnancyId)
          .eq('encounter_type', 'checkup');

      // 4. Fetch maternal vitals for weight gain engine
      final vitalsRaw = await SupabaseService.client
          .from('maternal_vitals')
          .select('recorded_at, age_of_gestation, weight_kg, height_cm')
          .eq('pregnancy_id', _pregnancyId);

      final checkupsList = (checkupsRaw as List).map((enc) {
        final innerCheckup = enc['checkup'] as Map<String, dynamic>?;
        final weeks = (enc['age_of_gestation_weeks'] as num?)?.toDouble() ?? 0;
        final days = (enc['age_of_gestation_days'] as num?)?.toDouble() ?? 0;
        return {
          'checkup_datetime': enc['checkup_datetime'],
          'age_of_gestation': weeks + days / 7.0,
          'checkup_weight': innerCheckup?['checkup_weight'],
        };
      }).toList();
      final vitalsList = (vitalsRaw as List).cast<Map<String, dynamic>>();

      // Extract the latest non-null height from maternal vitals logs
      double? latestVitalHeight;
      final sortedVitals = List<Map<String, dynamic>>.from(vitalsList);
      sortedVitals.sort((a, b) {
        final da = DateTime.tryParse(a['recorded_at']?.toString() ?? '') ?? DateTime.now();
        final db = DateTime.tryParse(b['recorded_at']?.toString() ?? '') ?? DateTime.now();
        return db.compareTo(da);
      });

      for (final v in sortedVitals) {
        if (v['height_cm'] != null) {
          latestVitalHeight = (v['height_cm'] as num).toDouble();
          break;
        }
      }

      if (latestVitalHeight != null) {
        _heightCm = latestVitalHeight;
      }

      final List<Map<String, dynamic>> weightReadings = [
        ...checkupsList.map((c) => {
              'checkup_weight': c['checkup_weight'] != null ? (c['checkup_weight'] as num).toDouble() : null,
              'age_of_gestation': c['age_of_gestation'] != null ? (c['age_of_gestation'] as num).toDouble() : null,
              'checkup_datetime': c['checkup_datetime'],
            }),
        ...vitalsList.map((v) => {
              'checkup_weight': v['weight_kg'] != null ? (v['weight_kg'] as num).toDouble() : null,
              'age_of_gestation': v['age_of_gestation'] != null ? (v['age_of_gestation'] as num).toDouble() : null,
              'checkup_datetime': v['recorded_at'],
            }),
      ];

      final weightReadingsAsc = weightReadings
          .where((v) => v['checkup_weight'] != null)
          .toList();

      weightReadingsAsc.sort((a, b) {
        final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '') ?? DateTime.now();
        final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '') ?? DateTime.now();
        return da.compareTo(db);
      });

      if (weightReadingsAsc.isNotEmpty) {
        final latest = weightReadingsAsc.last;
        final currentWeight = (latest['checkup_weight'] as num).toDouble();

        double effectiveAog = (latest['age_of_gestation'] as num?)?.toDouble() ?? 0;
        if (effectiveAog == 0 && _lmpDate != null) {
          effectiveAog = DateTime.now().difference(_lmpDate!).inDays / 7.0;
        }

        _weightGainResult = WeightGainEngine.evaluate(
          currentWeight: currentWeight,
          aogWeeks: effectiveAog,
          allCheckups: weightReadingsAsc,
          prePregnancyWeight: _prePregnancyWeight,
          heightCm: _heightCm,
          fetalCount: _fetalCount,
        );
      } else {
        _weightGainResult = null;
      }

      // Fetch next scheduled checkup (future or today)
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final nextCheckup = await SupabaseService.client
          .from('prenatal_checkups')
          .select('next_schedule')
          .eq('pregnancy_id', _pregnancyId)
          .not('next_schedule', 'is', null)
          .gte('next_schedule', todayStr)
          .order('next_schedule', ascending: true)
          .limit(1)
          .maybeSingle();

      if (nextCheckup != null && nextCheckup['next_schedule'] != null) {
        _nextScheduleDate = DateTime.tryParse(nextCheckup['next_schedule'].toString());
      } else {
        _nextScheduleDate = null;
      }
    } catch (e) {
      debugPrint('Error loading latest vitals/evaluation: $e');
    }
  }

  Future<void> _showConcludePregnancyDialog() async {
    if (!_hasPregnancy || _pregnancyId == 0) {
      _showSnackBar(_t('No active pregnancy to conclude.',
          'Walang aktibong pagbubuntis na tatapusin.'));
      return;
    }

    final lmpDate = _lmpDate;
    if (lmpDate == null) {
      _showSnackBar(_t('Cannot conclude pregnancy because the LMP is missing.',
          'Hindi matatapos ang pagbubuntis dahil nawawala ang LMP.'));
      return;
    }

    final today = DateTime.now();
    if (DateUtils.dateOnly(lmpDate).isAfter(DateUtils.dateOnly(today))) {
      _showSnackBar(_t(
          'Cannot conclude pregnancy because the LMP is in the future.',
          'Hindi matatapos ang pagbubuntis dahil nasa hinaharap ang LMP.'));
      return;
    }

    final fetalCount = _fetalCount < 1 ? 1 : _fetalCount;
    final outcomes = List<String>.filled(fetalCount, 'live_birth');
    final outcomeDates =
        List<DateTime>.filled(fetalCount, DateUtils.dateOnly(today));
    final deliveryDates =
        List<DateTime?>.filled(fetalCount, DateUtils.dateOnly(today));
    final deliveryMethods = List<String?>.filled(fetalCount, null);
    final placeControllers =
        List.generate(fetalCount, (_) => TextEditingController());
    var isSubmitting = false;

    double? computeGestAge() {
      final earliest = outcomeDates.reduce((a, b) => a.isBefore(b) ? a : b);
      final weeks = earliest.difference(lmpDate).inDays / 7;
      return weeks < 0 ? null : double.parse(weeks.toStringAsFixed(1));
    }

    String? validateForm() {
      final dateOnlyLmp = DateUtils.dateOnly(lmpDate);
      final dateOnlyToday = DateUtils.dateOnly(DateTime.now());

      for (int i = 0; i < fetalCount; i++) {
        final fetusLabel = fetalCount > 1
            ? _t('Fetus ${i + 1}', 'Sanggol ${i + 1}')
            : _t('the pregnancy', 'ang pagbubuntis');
        final outcomeDate = DateUtils.dateOnly(outcomeDates[i]);

        if (outcomeDate.isBefore(dateOnlyLmp)) {
          return _t('Outcome date for $fetusLabel cannot be before the LMP.',
              'Ang petsa ng kinalabasan para sa $fetusLabel ay hindi maaaring mauna sa LMP.');
        }

        if (outcomeDate.isAfter(dateOnlyToday)) {
          return _t('Outcome date for $fetusLabel cannot be in the future.',
              'Ang petsa ng kinalabasan para sa $fetusLabel ay hindi maaaring nasa hinaharap.');
        }

        if (_requiresDeliveryDetails(outcomes[i])) {
          final place = placeControllers[i].text.trim();
          if (place.isEmpty) {
            return _t('Please enter the place of delivery for $fetusLabel.',
                'Pakilagay ang lugar ng panganganak para sa $fetusLabel.');
          }

          if (deliveryMethods[i] == null) {
            return _t('Please select the delivery method for $fetusLabel.',
                'Pakipili ang paraan ng panganganak para sa $fetusLabel.');
          }

          final deliveryDate = deliveryDates[i] ?? outcomeDates[i];
          final dateOnlyDelivery = DateUtils.dateOnly(deliveryDate);
          if (dateOnlyDelivery.isBefore(dateOnlyLmp)) {
            return _t('Delivery date for $fetusLabel cannot be before the LMP.',
                'Ang petsa ng panganganak para sa $fetusLabel ay hindi maaaring mauna sa LMP.');
          }

          if (dateOnlyDelivery.isAfter(dateOnlyToday)) {
            return _t('Delivery date for $fetusLabel cannot be in the future.',
                'Ang petsa ng panganganak para sa $fetusLabel ay hindi maaaring nasa hinaharap.');
          }
        }
      }

      if (computeGestAge() == null) {
        return _t('Gestational age cannot be computed from the selected dates.',
            'Hindi makuwenta ang edad ng pagbubuntis mula sa napiling mga petsa.');
      }

      return null;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final gestAge = computeGestAge();

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: AppColors.cardColorOf(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                        top: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.error.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.flag,
                                  color: AppColors.error,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _t('Conclude Pregnancy',
                                      'Tapusin ang Pagbubuntis'),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                          if (fetalCount > 1) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.info.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: AppColors.info,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _t(
                                        'This pregnancy has $fetalCount fetuses. Please fill out the outcome for each.',
                                        'May $fetalCount sanggol ang pagbubuntis na ito. Pakilagay ang kinalabasan para sa bawat isa.',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.info,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          for (int i = 0; i < fetalCount; i++) ...[
                            if (fetalCount > 1)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandPrimary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _t('Fetus ${i + 1} of $fetalCount',
                                        'Sanggol ${i + 1} sa $fetalCount'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.brandPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppColors.bgSecondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: DropdownButtonFormField<String>(
                                initialValue: outcomes[i],
                                decoration: InputDecoration(
                                  labelText: _t('Outcome', 'Kinalabasan'),
                                  border: InputBorder.none,
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'live_birth',
                                    child: Text(
                                        _t('Live Birth', 'Buhay na Sanggol')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'stillbirth',
                                    child: Text(
                                        _t('Stillbirth', 'Patay na Sanggol')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'miscarriage',
                                    child:
                                        Text(_t('Miscarriage', 'Pagkalaglag')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'abortion',
                                    child: Text(_t('Abortion', 'Aborsyon')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'ectopic',
                                    child: Text(_t('Ectopic', 'Ectopic')),
                                  ),
                                ],
                                onChanged: isSubmitting
                                    ? null
                                    : (value) {
                                        setModal(() {
                                          outcomes[i] = value ?? outcomes[i];
                                          if (_requiresDeliveryDetails(
                                              outcomes[i])) {
                                            deliveryDates[i] = outcomeDates[i];
                                          } else {
                                            deliveryDates[i] = null;
                                            deliveryMethods[i] = null;
                                          }
                                        });
                                      },
                              ),
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: outcomeDates[i],
                                        firstDate: DateUtils.dateOnly(lmpDate),
                                        lastDate: DateUtils.dateOnly(today),
                                      );
                                      if (picked != null) {
                                        setModal(() {
                                          outcomeDates[i] = picked;
                                          if (_requiresDeliveryDetails(
                                              outcomes[i])) {
                                            deliveryDates[i] = picked;
                                          }
                                        });
                                      }
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.bgSecondary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      size: 20,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _t('Outcome Date',
                                                'Petsa ng Kinalabasan'),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat('MMMM d, yyyy')
                                                .format(outcomeDates[i]),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_drop_down,
                                      color: AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_requiresDeliveryDetails(outcomes[i])) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: placeControllers[i],
                                enabled: !isSubmitting,
                                decoration: InputDecoration(
                                  labelText: _t('Place of Delivery',
                                      'Lugar ng Panganganak'),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: AppColors.bgSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: AppColors.bgSecondary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonFormField<String>(
                                  initialValue: deliveryMethods[i],
                                  decoration: InputDecoration(
                                    labelText: _t('Delivery Method',
                                        'Paraan ng Panganganak'),
                                    border: InputBorder.none,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'NSD',
                                      child: Text(_t(
                                          'Normal Spontaneous Delivery',
                                          'Normal na Panganganak')),
                                    ),
                                    DropdownMenuItem(
                                      value: 'CS',
                                      child: Text(_t('Cesarean Section',
                                          'Cesarean Section')),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Instrumental',
                                      child: Text(
                                          _t('Instrumental', 'Instrumental')),
                                    ),
                                  ],
                                  onChanged: isSubmitting
                                      ? null
                                      : (value) => setModal(
                                            () => deliveryMethods[i] = value,
                                          ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            if (i < fetalCount - 1)
                              const Divider(
                                height: 24,
                                color: AppColors.borderPrimary,
                              ),
                          ],
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.bgSecondary,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: AppColors.borderPrimary),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandPrimary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.timer_outlined,
                                    size: 18,
                                    color: AppColors.brandPrimary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t('Gestational Age at End',
                                            'Edad ng Pagbubuntis sa Pagtatapos'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        gestAge != null
                                            ? '${gestAge.toStringAsFixed(1)} ${_t('weeks', 'linggo')}'
                                            : _t('Unable to compute',
                                                'Hindi makuwenta'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: gestAge != null
                                              ? AppColors.textPrimary
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.lock_outline,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _t('Auto-computed from LMP and outcome date',
                                  'Awtomatikong kinuha mula sa LMP at petsa ng kinalabasan'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          MainButton(
                            label: isSubmitting
                                ? _t('Concluding...', 'Tinatapos...')
                                : _t('Conclude Pregnancy',
                                    'Tapusin ang Pagbubuntis'),
                            showIcons: false,
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final validationMessage = validateForm();
                                    if (validationMessage != null) {
                                      _showSnackBar(validationMessage);
                                      return;
                                    }

                                    final gestAgeAtEnd = computeGestAge();
                                    final fetalOutcomes =
                                        <Map<String, dynamic>>[];
                                    for (int i = 0; i < fetalCount; i++) {
                                      fetalOutcomes.add({
                                        'fetus_number': i + 1,
                                        'outcome': outcomes[i],
                                        'outcome_date':
                                            _dateIso(outcomeDates[i]),
                                        'delivery_date':
                                            deliveryDates[i] == null
                                                ? null
                                                : _dateIso(deliveryDates[i]!),
                                        'place_of_delivery':
                                            placeControllers[i].text.trim(),
                                        'delivery_method': deliveryMethods[i],
                                      });
                                    }

                                    setModal(() => isSubmitting = true);
                                    final success = await MotherProfileService
                                        .concludePregnancy(
                                      _pregnancyId,
                                      gestAgeAtEnd,
                                      fetalOutcomes,
                                    );

                                    if (!mounted) return;
                                    if (success) {
                                      Navigator.pop(ctx);
                                      _showSnackBar(_t(
                                          'Pregnancy concluded successfully.',
                                          'Matagumpay na natapos ang pagbubuntis.'));
                                      await _loadDashboardData();
                                    } else {
                                      setModal(() => isSubmitting = false);
                                      _showSnackBar(_t(
                                          'Failed to conclude pregnancy.',
                                          'Hindi natapos ang pagbubuntis.'));
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    for (final controller in placeControllers) {
      controller.dispose();
    }
  }

  String _localizedFruitName(String name) {
    const filipinoNames = {
      'Poppy seed': 'Buto ng Poppy',
      'Sesame seed': 'Linga',
      'Green Pea': 'Berdeng Gisantes',
      'Coffee Bean': 'Butil ng Kape',
      'Blueberry': 'Blueberry',
      'Raspberry': 'Raspberry',
      'Cherry': 'Cherry',
      'Strawberry': 'Strawberry',
      'Lime': 'Dayap',
      'Plum': 'Plum',
      'Lemon': 'Lemon',
      'Peach': 'Peach',
      'Apple': 'Mansanas',
      'Avocado': 'Abukado',
      'Large White Onion': 'Malaking Puting Sibuyas',
      'Beetroot': 'Beetroot',
      'Sweet Potato': 'Kamote',
      'Taro (Gabi)': 'Gabi',
      'Carrot': 'Karot',
      'Banana': 'Saging',
      'Ear of Corn': 'Mais',
      'Cucumber': 'Pipino',
      'Eggplant': 'Talong',
      'Lettuce': 'Litsugas',
      'Cauliflower': 'Cauliflower',
      'Cabbage': 'Repolyo',
      'Coconut': 'Niyog',
      'Pomelo': 'Suha',
      'Pineapple': 'Pinya',
      'Melon': 'Melon',
      'Papaya': 'Papaya',
      'Kabocha Squash': 'Kalabasa',
      'Durian': 'Durian',
      'Pumpkin': 'Kalabasa',
      'Watermelon': 'Pakwan',
    };
    return LanguageService.isFilipino ? (filipinoNames[name] ?? name) : name;
  }

  String _getEnglishAOrAn(String fruitName) {
    if (fruitName.isEmpty) return 'a';
    final firstChar = fruitName[0].toLowerCase();
    if (firstChar == 'a' || firstChar == 'e' || firstChar == 'i' || firstChar == 'o' || firstChar == 'u') {
      return 'an';
    }
    return 'a';
  }

  /// Greeting, name, and where she is in the pregnancy.
  ///
  /// Time-aware rather than a flat "Welcome": a mother opening this at 5am
  /// before a long trip to the health centre and one opening it at night are
  /// having different days, and greeting both identically is the small kind
  /// of coldness that adds up.
  /// Entry to the Mother Book, styled like the other navigation cards.
  ///
  /// Given a slightly warmer tint than the plain white rows so it still reads
  /// as the main destination on the page, without becoming a call to action.
  void _openPregnancyDetail() {
    if (!_hasPregnancy || _week == 0 || _pregnancyId == 0) {
      _showSnackBar(_t('No active pregnancy to show details for.',
          'Walang aktibong pagbubuntis na maaaring tingnan.'));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PregnancyDetailPage(
          week: _week,
          trimester: _trimester,
          dueDate: _dueDate,
          weeksLeft: _weeksLeft,
          babySize: _babySize,
          babyWeight: _babyWeight,
          firstName: _firstName,
          riskLevel: _riskLevel,
          fetalCount: _fetalCount,
          pregnancyId: _pregnancyId,
          riskFactors: _riskFactors,
          suggestedActions: _suggestedActions,
        ),
      ),
    );
  }

  Widget _buildPregnancyBookRow({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.brandSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.brandPrimary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pregnant_woman_rounded,
                  color: AppColors.brandPrimary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('My Pregnancy', 'Ang Aking Pagbubuntis'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t('Your body, warning signs, and checklists',
                        'Ang iyong katawan, mga babala, at checklist'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: AppColors.brandPrimary),
          ],
        ),
      ),
    );
  }

  Widget _buildGreeting() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? _t('Good morning', 'Magandang umaga')
        : hour < 18
            ? _t('Good afternoon', 'Magandang hapon')
            : _t('Good evening', 'Magandang gabi');

    final name = _firstName.isNotEmpty
        ? _firstName.split(' ').first
        : _t('Nanay', 'Nanay');

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Warmth comes from contrast, not weight. The greeting recedes and
          // her name carries the emphasis — an extra-bold full line reads as
          // a headline announcing her, which is louder than it is kind.
          Text(
            '$greeting,',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.2,
              color: AppColors.textSecondary.withValues(alpha: 0.9),
            ),
          ),
          Text(
            '$name 🌸',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: AppColors.brandText,
            ),
          ),
          const SizedBox(height: 8),
          if (_hasPregnancy && _week > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 13, color: AppColors.brandText),
                  const SizedBox(width: 6),
                  Text(
                    '${_t('Week', 'Linggo')} $_week · ${_localizedTrimester()}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandText,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              _t('No active pregnancy', 'Walang aktibong pagbubuntis'),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBabySizeCard() {
    final sizeData = _babySizeByWeek[_week];
    final fruitName = sizeData?['fruit'] ?? '';
    final imageName = sizeData?['image'] ?? '';
    final hasMapping = sizeData != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandPrimary.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: hasMapping
                ? ClipOval(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(
                        'assets/images/$imageName',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.child_care,
                          size: 40,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                  )
                : const Icon(
                    Icons.child_care,
                    size: 40,
                    color: AppColors.brandPrimary,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('Baby Size This Week', 'Sukat ng Sanggol Ngayong Linggo'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandPrimary.withValues(alpha: 0.7),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasMapping
                      ? (LanguageService.isFilipino
                          ? 'Ang iyong sanggol ay kasinlaki ng isang ${_localizedFruitName(fruitName)}!'
                          : 'Your baby is about the size of ${_getEnglishAOrAn(fruitName)} ${_localizedFruitName(fruitName)}!')
                      : _t('Your baby is growing!',
                          'Lumalaki ang iyong sanggol!'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                // The measurements used to live in two separate boxes near
                // the bottom of the page, far from the fruit they describe.
                // A mother comparing her baby to a grape wants the numbers in
                // the same breath, not four cards later.
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _babyMeasureChip(Icons.straighten, _babySize),
                    _babyMeasureChip(Icons.monitor_weight_outlined, _babyWeight),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Length or weight, as a small labelled pill.
  ///
  /// Icon plus number, no caption: "2.3 cm" beside a ruler needs no sentence,
  /// and the words "Estimated Baby Size" cost two lines to say nothing extra.
  Widget _babyMeasureChip(IconData icon, String value) {
    if (value.isEmpty || value == '—') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.brandPrimary),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextScheduleCard() {
    if (_nextScheduleDate == null) return const SizedBox.shrink();

    String formatScheduledDate(DateTime date) {
      final dayName = DateFormat('EEEE').format(date);
      final monthName = DateFormat('MMMM').format(date);
      final day = DateFormat('d').format(date);
      final year = DateFormat('yyyy').format(date);

      final dayEnToTl = {
        'Monday': 'Lunes',
        'Tuesday': 'Martes',
        'Wednesday': 'Miyerkules',
        'Thursday': 'Huwebes',
        'Friday': 'Biyernes',
        'Saturday': 'Sabado',
        'Sunday': 'Linggo',
      };

      final monthEnToTl = {
        'January': 'Enero',
        'February': 'Pebrero',
        'March': 'Marso',
        'April': 'Abril',
        'May': 'Mayo',
        'June': 'Hunyo',
        'July': 'Hulyo',
        'August': 'Agosto',
        'September': 'Setyembre',
        'October': 'Oktubre',
        'November': 'Nobyembre',
        'December': 'Disyembre',
      };

      final translatedDay = _t(dayName, dayEnToTl[dayName] ?? dayName);
      final translatedMonth = _t(monthName, monthEnToTl[monthName] ?? monthName);

      return '$translatedDay, $translatedMonth $day, $year';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // White like the rest. Only one card on this screen carries a tint —
        // My Pregnancy, the main destination — so the tint means something.
        // Two pink-filled cards among six white ones read as noise, not
        // emphasis.
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandPrimary.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_month,
              color: AppColors.brandPrimary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // "Scheduled" promised an appointment. What is stored is a
                  // recommended date with no time on it, so the label says
                  // recommended — a mother should not arrive expecting a slot
                  // that was never booked.
                  _t('Recommended Next Visit',
                      'Inirerekomendang Susunod na Bisita'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatScheduledDate(_nextScheduleDate!),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlinkedBhcBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t('Individual Mode (Unlinked)',
                      'Indibidwal na Mode (Hindi Naka-link)'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                onPressed: () {
                  setState(() {
                    _isUnlinkedBannerDismissed = true;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              'Your account is currently not linked to a Barangay Health Center (BHC). To schedule checkups and receive clinical care from a midwife, please link your account.',
              'Ang iyong account ay kasalukuyang hindi naka-link sa isang Barangay Health Center (BHC). Upang mag-iskedyul ng checkup at makatanggap ng klinikal na pangangalaga mula sa midwife, mangyaring i-link ang iyong account.',
            ),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _showHowToLinkDialog(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t('How to link your account',
                      'Paano i-link ang iyong account'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: AppColors.brandText,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('Features you\'ll unlock:', 'Mga feature na maa-access mo:'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _buildFeatureItem(Icons.medical_services_outlined, _t('Prenatal checkup records', 'Mga tala ng prenatal checkup')),
                _buildFeatureItem(Icons.science_outlined, _t('Lab test results', 'Mga resulta ng lab test')),
                _buildFeatureItem(Icons.image_outlined, _t('Ultrasound records', 'Mga tala ng ultrasound')),
                _buildFeatureItem(Icons.monitor_weight_outlined, _t('Weight gain tracking', 'Pagsubaybay sa timbang')),
                _buildFeatureItem(Icons.smart_toy_outlined, _t('AI health insights', 'AI health insights')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.brandPrimary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showHowToLinkDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.medical_services_outlined,
                      color: AppColors.brandPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('How to Link to a BHC', 'Paano I-link sa BHC'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _t(
                  'To link your account to a Barangay Health Center (BHC) and begin official midwife monitoring, follow these steps:',
                  'Upang i-link ang iyong account sa isang Barangay Health Center (BHC) at magsimula ng opisyal na pagsubaybay ng midwife, sundin ang mga hakbang na ito:',
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _buildStepRow(
                  '1',
                  _t('Visit your nearest Barangay Health Center (BHC).',
                      'Pumunta sa iyong pinakamalapit na Barangay Health Center (BHC).')),
              const SizedBox(height: 12),
              _buildStepRow(
                  '2',
                  _t('Provide the midwife with your registered email address or phone number.',
                      'Ibigay sa midwife ang iyong rehistradong email address o numero ng telepono.')),
              const SizedBox(height: 12),
              _buildStepRow(
                  '3',
                  _t('The midwife will complete your linking process in the system, and your record will update automatically.',
                      'Tatapusin ng midwife ang proseso ng pag-link sa system, at awtomatikong mag-a-update ang iyong tala.')),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(_t('Got it!', 'Nakuha ko!')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVitalsIncompleteBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.monitor_weight_outlined,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t('Action Required: Complete Vitals Setup',
                      'Kailangang Aksyon: Kumpletuhin ang Vitals Setup'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                onPressed: () {
                  setState(() {
                    _isVitalsBannerDismissed = true;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              'Please provide your height, current weight, and pre-pregnancy weight to unlock weight gain tracking and advanced clinical analysis features.',
              'Mangyaring ilagay ang iyong taas, kasalukuyang timbang, at timbang bago mabuntis upang ma-unlock ang weight gain tracking at iba pang advanced clinical features.',
            ),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _showSetupVitalsBottomSheet(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t('Complete Vitals Setup',
                      'Kumpletuhin ang Vitals Setup'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: AppColors.brandText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSetupVitalsBottomSheet() {
    final heightCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final ppwCtrl = TextEditingController();

    String? heightError;
    String? heightWarning;
    String? weightError;
    String? weightWarning;
    String? ppwError;
    String? ppwWarning;

    double? calculatedBMI;
    String? bmiClassification;
    String? bmiWarning;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          void calculateBMI() {
            final height = double.tryParse(heightCtrl.text.trim());
            final ppw = double.tryParse(ppwCtrl.text.trim());

            if (height != null && ppw != null && height > 0) {
              final heightM = height / 100;
              final bmi = ppw / (heightM * heightM);
              calculatedBMI = bmi;

              if (bmi < 18.5) {
                bmiClassification = _t('Underweight', 'Kulang sa Timbang');
              } else if (bmi < 25) {
                bmiClassification = _t('Normal', 'Normal');
              } else if (bmi < 30) {
                bmiClassification = _t('Overweight', 'Sobra sa Timbang');
              } else {
                bmiClassification = _t('Obese', 'Obese');
              }

              // Gestational weight gain recommendations based on BMI
              if (_week <= 12) {
                bmiWarning = _t(
                  'Recommended total weight gain for this week (Week $_week) is 0.5 - 2.0 kg.',
                  'Ang inirerekomendang kabuuang dagdag-timbang para sa linggong ito (Linggo $_week) ay 0.5 - 2.0 kg.',
                );
              } else {
                final double minRate;
                final double maxRate;
                if (bmi < 18.5) {
                  minRate = 0.44;
                  maxRate = 0.58;
                } else if (bmi < 25) {
                  minRate = 0.35;
                  maxRate = 0.50;
                } else if (bmi < 30) {
                  minRate = 0.23;
                  maxRate = 0.33;
                } else {
                  minRate = 0.17;
                  maxRate = 0.27;
                }
                final minGain = 0.5 + (_week - 12) * minRate;
                final maxGain = 2.0 + (_week - 12) * maxRate;
                bmiWarning = _t(
                  'Recommended total weight gain for this week (Week $_week) is ${minGain.toStringAsFixed(1)} - ${maxGain.toStringAsFixed(1)} kg.',
                  'Ang inirerekomendang kabuuang dagdag-timbang para sa linggong ito (Linggo $_week) ay ${minGain.toStringAsFixed(1)} - ${maxGain.toStringAsFixed(1)} kg.',
                );
              }
            } else {
              calculatedBMI = null;
              bmiClassification = null;
              bmiWarning = null;
            }
          }

          void validateInputs() {
            final height = double.tryParse(heightCtrl.text.trim());
            final weight = double.tryParse(weightCtrl.text.trim());
            final ppw = double.tryParse(ppwCtrl.text.trim());

            setModalState(() {
              // Height validation
              if (heightCtrl.text.trim().isEmpty) {
                heightError = _t('Height is required', 'Kailangan ang taas');
                heightWarning = null;
              } else if (height == null) {
                heightError = _t('Enter a valid number', 'Maglayag ng wastong numero');
                heightWarning = null;
              } else if (height < 50 || height > 250) {
                heightError = _t('Must be 50-250 cm', 'Dapat ay 50-250 cm');
                heightWarning = null;
              } else {
                heightError = null;
                if (height < 120) {
                  heightWarning = _t(
                    'Entered measurement is outside expected maternal ranges. Please verify.',
                    'Ang inilagay na sukat ay labas sa inaasahang maternal range. Mangyaring i-verify.',
                  );
                } else {
                  heightWarning = null;
                }
              }

              // Weight validation
              if (weightCtrl.text.trim().isEmpty) {
                weightError = _t('Weight is required', 'Kailangan ang timbang');
                weightWarning = null;
              } else if (weight == null) {
                weightError = _t('Enter a valid number', 'Maglayag ng wastong numero');
                weightWarning = null;
              } else if (weight < 10 || weight > 350) {
                weightError = _t('Must be 10-350 kg', 'Dapat ay 10-350 kg');
                weightWarning = null;
              } else {
                weightError = null;
                if (weight < 35) {
                  weightWarning = _t(
                    'Entered measurement is outside expected maternal ranges. Please verify.',
                    'Ang inilagay na sukat ay labas sa inaasahang maternal range. Mangyaring i-verify.',
                  );
                } else {
                  weightWarning = null;
                }
              }

              // Pre-pregnancy weight validation
              if (ppwCtrl.text.trim().isEmpty) {
                ppwError = _t('Pre-pregnancy weight is required', 'Kailangan ang timbang bago mabuntis');
                ppwWarning = null;
              } else if (ppw == null) {
                ppwError = _t('Enter a valid number', 'Maglayag ng wastong numero');
                ppwWarning = null;
              } else if (ppw < 10 || ppw > 350) {
                ppwError = _t('Must be 10-350 kg', 'Dapat ay 10-350 kg');
                ppwWarning = null;
              } else {
                ppwError = null;
                if (ppw < 35) {
                  ppwWarning = _t(
                    'Entered measurement is outside expected maternal ranges. Please verify.',
                    'Ang inilagay na sukat ay labas sa inaasahang maternal range. Mangyaring i-verify.',
                  );
                } else {
                  ppwWarning = null;
                }
              }

              calculateBMI();
            });
          }

          Future<void> saveVitals() async {
            validateInputs();
            if (heightError != null || weightError != null || ppwError != null) return;

            final height = double.parse(heightCtrl.text.trim());
            final weight = double.parse(weightCtrl.text.trim());
            final ppw = double.parse(ppwCtrl.text.trim());

            setModalState(() => isSaving = true);

            try {
              final motherId = await AuthStorage.getMotherId();
              if (motherId == null) throw Exception('Mother ID not found');

              // Update mothers table
              await SupabaseService.client
                  .from('mothers')
                  .update({'height': height})
                  .eq('mother_id', motherId);

              // Update pregnancies table
              await SupabaseService.client
                  .from('pregnancies')
                  .update({'pre_pregnancy_weight': ppw})
                  .eq('pregnancy_id', _pregnancyId);

              // Insert into maternal_vitals table
              double? aogWeeks;
              if (_lmpDate != null) {
                aogWeeks = DateTime.now().difference(_lmpDate!).inDays / 7.0;
              }
              await SupabaseService.client.from('maternal_vitals').insert({
                'pregnancy_id': _pregnancyId,
                'mother_id': motherId,
                'weight_kg': weight,
                'height_cm': height,
                'age_of_gestation': aogWeeks != null ? double.parse(aogWeeks.toStringAsFixed(1)) : null,
                'notes': 'Vitals entered during dashboard profile completion alert',
                'recorded_at': DateTime.now().toIso8601String(),
              });

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(_t('Vitals setup completed successfully!', 'Matagumpay na nakumpleto ang pag-setup ng vitals!')),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              if (mounted) {
                // Reload dashboard data
                _loadDashboardData();
              }
            } catch (e) {
              setModalState(() => isSaving = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(_t('Error saving vitals: ', 'Kamalian sa pag-save ng vitals: ') + e.toString()),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _t('Complete Vitals Setup', 'Kumpletuhin ang Vitals Setup'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _t(
                      'Please provide your measurements to unlock advanced weight gain tracking and insights.',
                      'Mangyaring ibigay ang iyong mga sukat upang ma-unlock ang advanced weight gain tracking at mga insight.',
                    ),
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),

                  // Height Input
                  Text(
                    _t('Height (cm)', 'Taas (cm)'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    hintText: 'e.g. 156.0',
                    controller: heightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    leadingIcon: Icons.height,
                    errorText: heightError,
                    onChanged: (_) => validateInputs(),
                  ),
                  if (heightWarning != null) ...[
                    const SizedBox(height: 4),
                    Text(heightWarning!, style: const TextStyle(color: Colors.orange, fontSize: 11)),
                  ],
                  const SizedBox(height: 16),

                  // Current Weight Input
                  Text(
                    _t('Current Weight (kg)', 'Kasalukuyang Timbang (kg)'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    hintText: 'e.g. 62.5',
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    leadingIcon: Icons.monitor_weight_outlined,
                    errorText: weightError,
                    onChanged: (_) => validateInputs(),
                  ),
                  if (weightWarning != null) ...[
                    const SizedBox(height: 4),
                    Text(weightWarning!, style: const TextStyle(color: Colors.orange, fontSize: 11)),
                  ],
                  const SizedBox(height: 16),

                  // Pre-pregnancy Weight Input
                  Text(
                    _t('Pre-pregnancy Weight (kg)', 'Timbang bago mabuntis (kg)'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    hintText: 'e.g. 58.0',
                    controller: ppwCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    leadingIcon: Icons.monitor_weight_outlined,
                    errorText: ppwError,
                    onChanged: (_) => validateInputs(),
                  ),
                  if (ppwWarning != null) ...[
                    const SizedBox(height: 4),
                    Text(ppwWarning!, style: const TextStyle(color: Colors.orange, fontSize: 11)),
                  ],
                  const SizedBox(height: 20),

                  // BMI Display Card
                  if (calculatedBMI != null && bmiClassification != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.brandPrimary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _t('Calculated BMI: ${calculatedBMI!.toStringAsFixed(1)}',
                                   'Kinalkulang BMI: ${calculatedBMI!.toStringAsFixed(1)}'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.brandPrimary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  bmiClassification!,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.brandPrimary),
                                ),
                              ),
                            ],
                          ),
                          if (bmiWarning != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              bmiWarning!,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Save Button
                  ElevatedButton(
                    onPressed: isSaving ? null : saveVitals,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _t('Save Vitals', 'I-save ang Vitals'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStepRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.bgSecondary,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.brandText,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownCard() {
    final now = DateTime.now();
    final edd = _eddDate!;
    final totalDaysLeft = edd.difference(now).inDays;
    final daysLeft = totalDaysLeft < 0 ? 0 : totalDaysLeft;
    final weeksRemaining = daysLeft ~/ 7;
    final extraDays = daysLeft % 7;
    final progress = (_week / 40).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandPrimary.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  color: AppColors.brandPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _t('Pregnancy Countdown', 'Countdown ng Pagbubuntis'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandPrimary.withValues(alpha: 0.7),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              daysLeft > 0
                  ? '$daysLeft ${_t('days to go!', 'araw na lang!')}'
                  : _t('Any day now!', 'Anumang araw na!'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.brandPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              daysLeft > 0
                  ? '$weeksRemaining ${_t('weeks', 'linggo')} ${_t('and', 'at')} $extraDays ${_t('days', 'araw')}'
                  : _t('Your due date has arrived!',
                      'Dumating na ang iyong takdang araw!'),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.1),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_t('Week', 'Linggo')} $_week ${_t('of', 'sa')} 40',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event,
                  size: 16,
                  color: AppColors.brandPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_t('EDD', 'Takdang Araw')}: $_dueDate',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyTipCard() {
    final tipEn = _weeklyTipsEn[_week];
    final tipTl = _weeklyTipsTl[_week];
    if (tipEn == null || tipTl == null) return const SizedBox.shrink();
    final tip = _t(tipEn, tipTl);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandPrimary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: AppColors.brandPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _t('Tip of the Week', 'Tip ng Linggo'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPrimary,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_t('Week', 'Linggo')} $_week',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tip,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimaryOf(context),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.brandPrimary,
                  ),
                )
              : _errorMessage != null
                  ? _buildErrorView()
                  : RefreshIndicator(
                      onRefresh: _loadDashboardData,
                      color: AppColors.brandPrimary,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // A page header, not a card. It used to be a pink
                            // box, which made it compete with the eight cards
                            // below it and added to a screen where almost
                            // everything was pink-filled. Left-aligned and
                            // unboxed, it reads as the top of a page and lets
                            // the hero image be the first real card.
                            _buildGreeting(),

                            if (_isUnlinked && !_isUnlinkedBannerDismissed) ...[
                              const SizedBox(height: 16),
                              _buildUnlinkedBhcBanner(),
                            ],

                            if (_isVitalsIncomplete && !_isVitalsBannerDismissed) ...[
                              const SizedBox(height: 16),
                              _buildVitalsIncompleteBanner(),
                            ],

                            // Her news comes before the clinic's. Greeting,
                            // week, countdown, baby size — the reason she
                            // opened the app — then the operational cards.
                            HeroCard(
                              image: const AssetImage(
                                  'assets/images/pregnant1.png'),
                              week: _hasPregnancy && _week > 0 ? _week : null,
                              showWeekBadge: _hasPregnancy && _week > 0,
                              showHeartRow: _hasPregnancy && _week > 0,
                            ),

                            if (_hasPregnancy &&
                                _week > 0 &&
                                _eddDate != null) ...[
                              const SizedBox(height: 16),
                              _buildCountdownCard(),
                            ],

                            if (_hasPregnancy && _week > 0) ...[
                              const SizedBox(height: 16),
                              _buildBabySizeCard(),
                              const SizedBox(height: 16),
                              _buildWeeklyTipCard(),
                            ],

                            // Reads as the natural "tell me more" after the
                            // week content, rather than a navigation row
                            // splitting the countdown from the baby size —
                            // those two answer one question together. At the
                            // bottom of the page it was invisible.
                            const SizedBox(height: 16),
                            _buildPregnancyBookRow(
                              onTap: _openPregnancyDetail,
                            ),

                            if (!_isUnlinked && _nextScheduleDate != null) ...[
                              const SizedBox(height: 16),
                              _buildNextScheduleCard(),
                            ],

                            // One card, not two. "My Vitals & Weight Gain"
                            // followed by "Weight Gain Analysis" read as the
                            // same subject twice, and a mother reasonably
                            // expects the first title to already contain the
                            // second card.
                            if (!_isUnlinked && _hasPregnancy) ...[
                              const SizedBox(height: 16),
                              _buildVitalsCard(),
                            ],

                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
          floatingActionButton: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MotherChatbotPage(
                        firstName: _firstName,
                        week: _week,
                        trimester: _trimester,
                        riskLevel: _riskLevel,
                        riskFactors: _riskFactors,
                        suggestedActions: _suggestedActions,
                        hasPregnancy: _hasPregnancy,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Image.asset(
                    'assets/images/chatbot_icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVitalsCard() {
    final hasVitals = _latestWeight != null || _latestBp != null;

    String getSourceLabel(String? src) {
      switch (src) {
        case 'prenatal_checkup':
          return _t('Official Checkup', 'Opisyal na Checkup');
        case 'midwife_quick':
          return _t('Midwife Log', 'Tala ng Midwife');
        case 'mother_self':
        default:
          return _t('Self-logged', 'Sariling Tala');
      }
    }

    Color getSourceColor(String? src) {
      switch (src) {
        case 'prenatal_checkup':
          return const Color(0xFF0369A1);
        case 'midwife_quick':
          return const Color(0xFF7E22CE);
        case 'mother_self':
        default:
          return const Color(0xFFB45309);
      }
    }

    Color getSourceBg(String? src) {
      switch (src) {
        case 'prenatal_checkup':
          return const Color(0xFFE0F2FE);
        case 'midwife_quick':
          return const Color(0xFFF3E8FF);
        case 'mother_self':
        default:
          return const Color(0xFFFEF3C7);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            final motherId = await AuthStorage.getMotherId();
            if (motherId == null || !mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MotherVitalsPage(
                  motherId: motherId,
                  pregnancyId: _pregnancyId,
                  lastMenstrualPeriod: _lmpDate != null ? _dateIso(_lmpDate!) : null,
                ),
              ),
            ).then((_) => _loadDashboardData());
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: AppColors.brandPrimary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('My Vitals & Weight Gain', 'Aking Vitals & Timbang'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (hasVitals) ...[
                        Row(
                          children: [
                            if (_latestWeight != null) ...[
                              const Icon(Icons.monitor_weight_outlined, size: 14, color: AppColors.brandAccent),
                              const SizedBox(width: 4),
                              Text(
                                '${_latestWeight!.toStringAsFixed(1)} kg',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inputText,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (_latestBp != null) ...[
                              const Icon(Icons.favorite_border, size: 14, color: AppColors.brandAccent),
                              const SizedBox(width: 4),
                              Text(
                                _latestBp!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inputText,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: getSourceBg(_latestVitalsSource),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                getSourceLabel(_latestVitalsSource),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: getSourceColor(_latestVitalsSource),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_t('on', 'noong')} ${DateFormat('MMM d, yyyy').format(_latestVitalsDate!)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          _t('No vitals logged yet. Tap to start tracking!', 
                             'Wala pang naitalang vitals. Tapikin upang magsimula!'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                ),
              ],
            ),

                // The weight-gain evaluation lives inside this card now.
                // It was a second card immediately below, titled "Weight Gain
                // Analysis" under a card already called "My Vitals & Weight
                // Gain" — the same subject announced twice.
                if (_weightGainResult != null) ...[
                  const SizedBox(height: 16),
                  Divider(color: Colors.grey.shade200, height: 1),
                  const SizedBox(height: 16),
                  _buildWeightGainSummary(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Where her gain sits against the range recommended for her BMI category.
  ///
  /// The green band is the IOM 2009 range for this week; the marker is her.
  /// Inside the band needs no explanation — that is the point of drawing it.
  ///
  /// The track runs to a little past whichever is larger, the top of the range
  /// or her actual gain, so a mother well above the range still sees her
  /// marker on the track rather than jammed against the end.
  Widget _weightGainRangeBar({
    required double actual,
    required double min,
    required double max,
    required Color statusColor,
  }) {
    final upper = (actual > max ? actual : max) * 1.15;
    final scaleMax = upper <= 0 ? 1.0 : upper;

    double frac(double v) => (v / scaleMax).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final bandLeft = frac(min < 0 ? 0 : min) * w;
        final bandWidth = (frac(max) * w) - bandLeft;
        final markerX = frac(actual < 0 ? 0 : actual) * w;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 26,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track
                  Positioned(
                    top: 9,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  // Recommended band
                  Positioned(
                    top: 9,
                    left: bandLeft,
                    child: Container(
                      height: 8,
                      width: bandWidth < 4 ? 4 : bandWidth,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  // Her marker — a shape as well as a colour, so the reading
                  // survives a colour-blind viewer and a washed-out screen.
                  Positioned(
                    top: 2,
                    left: (markerX - 9).clamp(0.0, w - 18),
                    child: Container(
                      width: 18,
                      height: 22,
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _t(
                'Recommended for you: ${min.toStringAsFixed(1)}–${max.toStringAsFixed(1)} kg by week $_week',
                'Inirerekomenda para sa iyo: ${min.toStringAsFixed(1)}–${max.toStringAsFixed(1)} kg sa linggo $_week',
              ),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The weight-gain evaluation, without card chrome, for embedding in the
  /// vitals card.
  ///
  /// Both cards previously navigated to the same MotherVitalsPage, so nothing
  /// is lost by folding one into the other — it was two doors to one room,
  /// announced with two titles about the same subject.
  Widget _buildWeightGainSummary() {
    final result = _weightGainResult;
    if (result == null) return const SizedBox.shrink();

    final (statusColor, statusLabel) = switch (result.status) {
      WeightGainStatus.normal => (
          AppColors.success,
          _t('On track', 'Nasa tamang landas')
        ),
      WeightGainStatus.low => (
          AppColors.warning,
          _t('A little below', 'Bahagyang mababa')
        ),
      WeightGainStatus.high => (
          AppColors.error,
          _t('A little above', 'Bahagyang mataas')
        ),
      WeightGainStatus.insufficient => (
          AppColors.textSecondary,
          _t('Not enough data yet', 'Kulang pa ang data')
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _t('Weight gain', 'Dagdag na timbang'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            // Word plus colour, so the status survives a colour-blind reader.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        if (result.actualGain != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${result.actualGain! >= 0 ? '+' : ''}${result.actualGain!.toStringAsFixed(1)} kg',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _t('so far', 'hanggang ngayon'),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (result.expectedGainMin != null &&
              result.expectedGainMax != null) ...[
            const SizedBox(height: 12),
            _weightGainRangeBar(
              actual: result.actualGain!,
              min: result.expectedGainMin!,
              max: result.expectedGainMax!,
              statusColor: statusColor,
            ),
          ],
        ],
      ],
    );
  }




  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDashboardData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
              ),
              child: Text(_t('Retry', 'Subukan Muli')),
            ),
          ],
        ),
      ),
    );
  }
}
