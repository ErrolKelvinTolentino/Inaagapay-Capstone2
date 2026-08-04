// lib/screens/mother/mother_profile_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../services/mother_profile_service.dart';
import '../../services/auth_storage.dart';
import '../../services/push_notification_service.dart';
import '../../services/supabase_service.dart';
import '../midwife/add_ultrasound_page.dart';
import '../midwife/lab_test_analyzer_screen.dart';
import '../midwife/add_prenatal_checkup_screen.dart';
import '../../widgets/headline.dart';
import '../../widgets/page_title.dart';
import '../../widgets/main_button.dart';
import '../../widgets/secondary_button.dart';
import '../shared/record_detail_screen.dart';
import '../../widgets/profile_widgets.dart';
import '../../services/weight_gain_engine.dart';
import '../../models/weight_gain_models.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../widgets/mother_qr_code.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_dropdown_field.dart';

// Blood type options
const List<String> _bloodTypeOptions = [
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
  'Unknown'
];

const List<String> _commonConditions = [
  'Anemia',
  'Diabetes',
  'Hypertension',
  'Asthma',
  'Thyroid Disorder',
  'Heart Disease',
  'Kidney Disease',
  'Epilepsy',
  'Hepatitis',
  'Other'
];

const List<String> _commonAllergens = [
  'Peanuts',
  'Penicillin',
  'Dust Mites',
  'Pollen',
  'Shellfish',
  'Pet Dander',
  'Fish',
  'Milk',
  'Eggs',
  'Soy',
  'Wheat',
  'Latex',
  'Insect Stings',
  'Mold',
  'Fragrances',
  'Nickel',
  'Other'
];

const List<String> _relationshipOptions = [
  'Spouse/Partner',
  'Parent',
  'Child',
  'Sibling',
  'Relative',
  'Friend',
  'Neighbor',
  'Coworker',
  'Other',
];

enum _GestationMethod { lmp, edd, aog }

class MotherProfilePage extends StatefulWidget {
  final int motherId;
  final bool readOnly;

  const MotherProfilePage(
      {super.key, required this.motherId, this.readOnly = false});

  @override
  State<MotherProfilePage> createState() => _MotherProfilePageState();
}

class _MotherProfilePageState extends State<MotherProfilePage>
    with SingleTickerProviderStateMixin {
  late Future<Map<String, dynamic>> _profileFuture;
  late TabController _tabController;

  // Sort states
  String _checkupSort = 'desc';
  String _ultrasoundSort = 'desc';
  String _labSort = 'desc';
  String _vitalSort = 'desc';
  final String _childQuery = '';
  final String _childSort = 'recent';
  final Set<String> _expandedLabInsightAspects = <String>{};
  static const int _pageSize = 5;


  bool _isOpeningRecord = false;

  // Edit mode states
  bool _isEditingPersonal = false;
  bool _isEditingAddress = false;

  // FIX #1: Guard so controllers are only created once per profile load,
  // not on every rebuild.
  bool _controllersInitialized = false;
  final Map<String, TextEditingController> _personalControllers = {};
  final Map<String, TextEditingController> _addressControllers = {};

  // Dropdown selections for editing
  String _editingBloodType = '';

  // Editable medical conditions & allergies
  bool _isEditingConditions = false;
  bool _isEditingAllergies = false;
  final bool _isEditingContacts = false;
  List<dynamic> _currentMedicalConditions = [];
  List<dynamic> _currentAllergies = [];

  // Profile picture
  String? _profilePictureUrl;
  String? _patientNumber;



  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _profileFuture = MotherProfileService.fetchMotherProfile(widget.motherId);
    _loadProfilePicture();
    _loadPatientNumber();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in _personalControllers.values) {
      controller.dispose();
    }
    for (final controller in _addressControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfilePicture() async {
    final url = await SupabaseService.getProfilePictureUrl(widget.motherId);
    if (mounted) {
      setState(() => _profilePictureUrl = url);
    }
  }

  Future<void> _loadPatientNumber() async {
    final number =
        await SupabaseService.getPatientNumberForMother(widget.motherId);
    if (mounted) {
      setState(() => _patientNumber = number);
    }
  }

  /// Weight gain dashboard card.
  Widget _buildWeightGainDashboard(
      WeightGainResult result, List<Map<String, dynamic>> checkups, int fetalCount, {bool isEstimated = false}) {
    final alertIdx = result.message.indexOf('ALERT:');
    final hasAlert = alertIdx != -1;
    final alertText = hasAlert ? result.message.substring(alertIdx).trim() : '';
    // Status color & label
    Color statusColor;
    String statusText;
    switch (result.status) {
      case WeightGainStatus.normal:
        statusColor = AppColors.success;
        statusText = 'within ideal weight gain';
        break;
      case WeightGainStatus.low:
        statusColor = AppColors.warning;
        statusText = 'below ideal weight gain';
        break;
      case WeightGainStatus.high:
        statusColor = AppColors.error;
        statusText = 'above ideal weight gain';
        break;
      case WeightGainStatus.insufficient:
        statusColor = AppColors.textSecondary;
        statusText = 'insufficient data';
        break;
    }

    // Filter checkups for chart spots
    final validCheckups = checkups.where((c) {
      final w = c['checkup_weight'];
      final a = c['age_of_gestation'];
      return w != null && a != null && (w as num) > 0 && (a as num) > 0;
    }).toList();

    validCheckups.sort((a, b) =>
        (a['age_of_gestation'] as num).compareTo(b['age_of_gestation'] as num));

    final List<FlSpot> actualSpots = [];
    if (result.mode == WeightGainMode.full && result.baselineWeight != null) {
      actualSpots.add(FlSpot(0, result.baselineWeight!));
    }

    for (final c in validCheckups) {
      final w = (c['age_of_gestation'] as num).toDouble();
      final weight = (c['checkup_weight'] as num).toDouble();
      if (actualSpots.isNotEmpty && (w - actualSpots.last.x).abs() < 0.1) {
        continue;
      }
      actualSpots.add(FlSpot(w, weight));
    }

    actualSpots.sort((a, b) => a.x.compareTo(b.x));

    final List<FlSpot> minSpots = [];
    final List<FlSpot> maxSpots = [];
    double minY = 40.0;
    double maxY = 100.0;
    double minX = 0.0;
    double maxX = 40.0;

    if (actualSpots.isNotEmpty) {
      final maxAog = actualSpots.last.x;
      final endWeek = maxAog > 40 ? maxAog : 40.0;
      final startWeek = result.baselineWeek ?? 0.0;

      if (result.baselineWeight != null && result.baselineWeek != null) {
        for (double w = startWeek; w <= endWeek; w += 2) {
          final range = _getRecommendedRangeAt(
            aogWeeks: w,
            bmiCategory: result.bmiCategory,
            baselineWeight: result.baselineWeight!,
            baselineWeek: result.baselineWeek!,
            fetalCount: fetalCount,
          );
          minSpots.add(FlSpot(w, range['min']!));
          maxSpots.add(FlSpot(w, range['max']!));
        }
        final endRange = _getRecommendedRangeAt(
          aogWeeks: endWeek,
          bmiCategory: result.bmiCategory,
          baselineWeight: result.baselineWeight!,
          baselineWeek: result.baselineWeek!,
          fetalCount: fetalCount,
        );
        if (minSpots.isEmpty || minSpots.last.x != endWeek) {
          minSpots.add(FlSpot(endWeek, endRange['min']!));
          maxSpots.add(FlSpot(endWeek, endRange['max']!));
        }
      }

      final allSpots = [...actualSpots, ...minSpots, ...maxSpots];
      if (allSpots.isNotEmpty) {
        minY = allSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 2;
        maxY = allSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 2;
      }
      minX = startWeek;
      maxX = endWeek;
    }

    // Recommended weekly gain and expected weight range calculation
    final activeGuidelines = fetalCount >= 2
        ? WeightGainEngine.iomTwinGuidelines
        : WeightGainEngine.iomGuidelines;
    final guidelines = activeGuidelines[result.bmiCategory] ?? activeGuidelines['Normal']!;
    final weeklyRate = guidelines['weekly_rate']!;

    final double? baseline = result.baselineWeight;
    final double? expMin = result.expectedGainMin;
    final double? expMax = result.expectedGainMax;
    final bool hasExpectedWeight = baseline != null && expMin != null && expMax != null;
    
    final String expectedWeightText = hasExpectedWeight
        ? '${(baseline + expMin).toStringAsFixed(1)} kg - ${(baseline + expMax).toStringAsFixed(1)} kg'
        : 'N/A';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Title & Pill
          Row(
            children: [
              const Icon(Icons.monitor_weight_outlined, color: AppColors.brandPrimary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'WEIGHT GAIN ANALYSIS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: Color(0xFF5A5A5A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Line Chart / Placeholder
          if (actualSpots.length < 2)
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.show_chart_rounded, size: 28, color: Colors.grey),
                    SizedBox(height: 6),
                    Text(
                      'Chart requires at least two weights to display progression.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: maxX,
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: ((maxY - minY) / 5).clamp(1.0, 10.0),
                    verticalInterval: 4.0,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.shade100,
                      strokeWidth: 1,
                    ),
                    getDrawingVerticalLine: (value) => FlLine(
                      color: Colors.grey.shade100,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 4.0,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'W${value.toInt()}',
                            style: TextStyle(fontSize: 9, color: AppColors.textSecondaryOf(context)),
                          ),
                        ),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: ((maxY - minY) / 5).clamp(1.0, 10.0),
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()} kg',
                          style: TextStyle(fontSize: 9, color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    // Actual spots - Solid Pink
                    LineChartBarData(
                      spots: actualSpots,
                      isCurved: true,
                      color: AppColors.brandPrimary,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeWidth: 2,
                          strokeColor: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                    // Recommended Min - Gray broken
                    if (minSpots.isNotEmpty)
                      LineChartBarData(
                        spots: minSpots,
                        isCurved: true,
                        color: Colors.grey.shade400,
                        barWidth: 1.5,
                        dashArray: [5, 5],
                        dotData: const FlDotData(show: false),
                      ),
                    // Recommended Max - Gray broken
                    if (maxSpots.isNotEmpty)
                      LineChartBarData(
                        spots: maxSpots,
                        isCurved: true,
                        color: Colors.grey.shade400,
                        barWidth: 1.5,
                        dashArray: [5, 5],
                        dotData: const FlDotData(show: false),
                      ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          String prefix = '';
                          if (spot.barIndex == 0) {
                            prefix = 'Actual: ';
                          } else if (spot.barIndex == 1) {
                            prefix = 'IOM Min: ';
                          } else if (spot.barIndex == 2) {
                            prefix = 'IOM Max: ';
                          }
                          return LineTooltipItem(
                            '${prefix}Week ${spot.x.toInt()}\n${spot.y.toStringAsFixed(1)} kg',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Legend row
          if (actualSpots.length >= 2) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Actual Weight',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 20),
                Row(
                  children: List.generate(
                    3,
                    (index) => Container(
                      width: 4,
                      height: 1.5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Expected Bounds (${result.bmiCategory})',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Info Metrics
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recommended weekly gain',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${weeklyRate.toStringAsFixed(2)} kg',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total expected weight',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      expectedWeightText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Mini Explanation Alert Box (Only show when there is an ALERT)
          if (hasAlert) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alertText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          if (isEstimated) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue.shade600, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pre-pregnancy weight (W0) was estimated using backtracking as it wasn\'t provided.',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Expansion Tile for Disclaimer
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: const Text(
                'Clinical Disclaimer & References',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandPrimary,
                ),
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 2, bottom: 4),
              dense: true,
              children: [
                Text(
                  'Disclaimer: This analysis is based on the Institute of Medicine (IOM) 2009 Guidelines. It is for monitoring and educational support only and does not substitute for professional medical advice, clinical assessment, or diagnosis.',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.4,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'References:\n• Institute of Medicine (IOM) & National Research Council (NRC). (2009). Weight Gain During Pregnancy: Reexamining the Guidelines. Washington, DC: The National Academies Press.',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.4,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, double> _getRecommendedRangeAt({
    required double aogWeeks,
    required String bmiCategory,
    required double baselineWeight,
    required double baselineWeek,
    required int fetalCount,
  }) {
    return WeightGainEngine.getExpectedRangeAt(
      aogWeeks: aogWeeks,
      bmiCategory: bmiCategory,
      baselineWeight: baselineWeight,
      baselineWeek: baselineWeek,
      fetalCount: fetalCount,
    );
  }

  Future<double?> _getMotherHeight() async {
    try {
      final response = await SupabaseService.client
          .from('mothers')
          .select('height')
          .eq('mother_id', widget.motherId)
          .maybeSingle();

      if (response != null && response['height'] != null) {
        return (response['height'] as num).toDouble();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _refresh() async {
    // FIX #1 continued: reset the guard so controllers re-init from fresh data
    setState(() {
      _controllersInitialized = false;
      _isEditingPersonal = false;
      _isEditingAddress = false;
      _isEditingConditions = false;
      _isEditingAllergies = false;
      _profileFuture = MotherProfileService.fetchMotherProfile(widget.motherId);

    });
    await _loadProfilePicture();
  }

  Future<void> _logout() async {
    await PushNotificationService.removeToken();
    await AuthStorage.clearAll();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  // ── Navigation helpers ──────────────────────────────────────────────────

  void _goToUltrasoundAnalyzer(Map<String, dynamic> pregnancy) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddUltrasoundPage(
          motherId: widget.motherId,
          pregnancyId: pregnancy['pregnancy_id'] as int?,
        ),
      ),
    ).then((_) => _refresh());
  }

  void _goToLabTestAnalyzer(Map<String, dynamic> pregnancy) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LabTestAnalyzerScreen(
          motherId: widget.motherId,
          pregnancyId: pregnancy['pregnancy_id'],
        ),
      ),
    ).then((_) => _refresh());
  }

  // ── Formatting helpers ──────────────────────────────────────────────────

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final parsed = DateTime.tryParse(date.toString());
      if (parsed == null) return date.toString();
      return DateFormat('MMM d, yyyy').format(parsed);
    } catch (e) {
      return date.toString();
    }
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return '-';
    try {
      final parsed = DateTime.tryParse(dateTime.toString());
      if (parsed == null) return dateTime.toString();
      return DateFormat('MMM d, yyyy h:mm a').format(parsed);
    } catch (e) {
      return dateTime.toString();
    }
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String _formatValue(dynamic value) {
    if (value == null) return '-';
    final str = value.toString().trim();
    return str.isEmpty ? '-' : str;
  }

  String _formatOutcome(String? outcome) {
    if (outcome == null) return '-';
    switch (outcome.toLowerCase()) {
      case 'live_birth':
        return 'Live Birth';
      case 'stillbirth':
        return 'Stillbirth';
      case 'miscarriage':
        return 'Miscarriage';
      case 'abortion':
        return 'Abortion';
      case 'ectopic':
        return 'Ectopic';
      default:
        return outcome;
    }
  }

  // ── AI insight generators ───────────────────────────────────────────────

  String _generatePrenatalAIInsights(Map<String, dynamic> checkup) {
    final bpSys = _toDouble(checkup['blood_pressure_systolic']);
    final bpDia = _toDouble(checkup['blood_pressure_diastolic']);
    final weight = _toDouble(checkup['checkup_weight']);
    final edemaRaw = _formatValue(checkup['edema']);
    final edema = edemaRaw.toLowerCase();
    final tdDose = _formatValue(checkup['td_vaccine_dose']);
    final fhrRaw = _formatValue(checkup['fetal_heart_beat']);
    final fhr = int.tryParse(fhrRaw);

    String overallAssessment =
        'Current prenatal checkup findings appear stable overall.';
    if (bpSys != null && bpDia != null && (bpSys >= 140 || bpDia >= 90)) {
      overallAssessment =
          'Blood pressure is elevated and needs closer monitoring for hypertensive disorders of pregnancy.';
    } else if (bpSys != null && bpDia != null && (bpSys < 90 || bpDia < 60)) {
      overallAssessment =
          'Blood pressure is lower than typical range; monitor hydration, symptoms, and follow-up trends.';
    } else if (fhr != null && (fhr < 120 || fhr > 160)) {
      overallAssessment =
          'Fetal heart rate is outside the usual expected range and should be reviewed clinically.';
    } else if (edema != '-' && edema != 'none') {
      overallAssessment =
          'Mild edema is noted; monitor progression and correlate with blood pressure and symptoms.';
    }

    final buffer = StringBuffer();
    buffer.write('OVERALL ASSESSMENT: $overallAssessment\n\n');
    buffer.write('KEY OBSERVATIONS:\n');

    if (bpSys != null && bpDia != null) {
      if (bpSys >= 140 || bpDia >= 90) {
        buffer.write(
            '- Maternal Vitals - Blood Pressure: $bpSys/$bpDia mmHg [REVIEW].\n');
      } else if (bpSys < 90 || bpDia < 60) {
        buffer.write(
            '- Maternal Vitals - Blood Pressure: $bpSys/$bpDia mmHg [MONITOR].\n');
      } else {
        buffer.write(
            '- Maternal Vitals - Blood Pressure: $bpSys/$bpDia mmHg [WITHIN NORMAL LIMITS].\n');
      }
    } else {
      buffer.write(
          '- Maternal Vitals - Blood Pressure: Not documented in this record.\n');
    }

    if (weight != null) {
      buffer.write(
          '- Maternal Vitals - Weight: ${weight.toStringAsFixed(1)} kg.\n');
    }

    if (fhr != null) {
      if (fhr >= 120 && fhr <= 160) {
        buffer.write(
            '- Fetal Status - Heart Rate: $fhr bpm [WITHIN NORMAL LIMITS].\n');
      } else {
        buffer.write('- Fetal Status - Heart Rate: $fhr bpm [REVIEW].\n');
      }
    } else if (fhrRaw != '-') {
      buffer.write('- Fetal Status - Heart Rate: $fhrRaw [REVIEW MANUALLY].\n');
    }

    final fetalPosition = _formatValue(checkup['fetal_position']);
    if (fetalPosition != '-') {
      buffer.write('- Fetal Status - Position: $fetalPosition.\n');
    }

    if (edemaRaw != '-') {
      if (edema == 'none') {
        buffer.write('- Maternal Observation - Edema: None reported.\n');
      } else {
        buffer.write('- Maternal Observation - Edema: $edemaRaw [MONITOR].\n');
      }
    }

    if (tdDose != '-') {
      buffer.write('- Preventive Care - TD Vaccine: $tdDose documented.\n');
    }

    final nextSchedule = _formatDate(checkup['next_schedule']);
    if (nextSchedule != '-') {
      buffer.write('- Follow-up - Next Schedule: $nextSchedule.\n');
    }

    buffer.write('\nRECOMMENDATIONS:\n');
    buffer.write('- Continue scheduled prenatal follow-up visits.\n');
    buffer
        .write('- Monitor maternal warning signs and fetal movement daily.\n');
    if ((bpSys != null && bpDia != null && (bpSys >= 140 || bpDia >= 90)) ||
        (fhr != null && (fhr < 120 || fhr > 160))) {
      buffer.write(
          '- Prioritize clinician review for blood pressure and/or fetal heart findings.\n');
    }
    if (edema != '-' && edema != 'none') {
      buffer.write('- Reassess edema severity in next checkup.\n');
    }

    return buffer.toString().trim();
  }

  String _generateUltrasoundAIInsights(Map<String, dynamic> ultrasound) {
    final buffer = StringBuffer();
    buffer.write('Ultrasound AI Insights:\n\n');

    final remarks = ultrasound['remarks']?.toString().toLowerCase() ?? '';
    final date = _formatDate(ultrasound['ultrasound_date']);

    buffer.write('Ultrasound conducted on $date');

    final location = ultrasound['ultrasound_location'];
    if (location != null && location.toString().isNotEmpty) {
      buffer.write(' at $location');
    }

    final worker = ultrasound['health_worker_name'];
    if (worker != null && worker.toString().isNotEmpty) {
      buffer.write(' by $worker');
    }
    buffer.write(':\n\n');

    if (remarks.contains('normal') || remarks.contains('healthy')) {
      buffer.write(
          '**Normal Findings**: Ultrasound appears normal with healthy fetal development.\n\n');
    } else if (remarks.contains('follow') || remarks.contains('monitor')) {
      buffer.write(
          '**Follow-up Recommended**: Some findings require additional observation.\n\n');
    } else if (remarks.contains('concern') || remarks.contains('abnormal')) {
      buffer.write(
          '**Further Evaluation Needed**: Discuss findings with healthcare provider.\n\n');
    } else {
      buffer.write(
          '**Diagnostic Information**: The ultrasound provides important diagnostic information.\n\n');
    }

    buffer.write('**Key Recommendations**:\n');
    buffer.write('- Discuss findings with your healthcare provider\n');
    buffer.write('- Continue all scheduled prenatal appointments\n');

    return buffer.toString();
  }

  ({String cleanRemarks, String? extractedAi}) _splitRemarksAndAi(
      String? rawRemarks) {
    final source = rawRemarks?.trim() ?? '';
    if (source.isEmpty) return (cleanRemarks: '', extractedAi: null);

    final marker = RegExp(r'\bAI\s*Analysis\s*:', caseSensitive: false);
    final match = marker.firstMatch(source);
    if (match == null) return (cleanRemarks: source, extractedAi: null);

    final notesPart = source.substring(0, match.start).trim();
    final aiPart = source.substring(match.end).trim();

    return (
      cleanRemarks: notesPart,
      extractedAi: aiPart.isEmpty ? null : aiPart,
    );
  }

  Map<String, dynamic>? _latestRecordByDate(List records, String dateField) {
    if (records.isEmpty) return null;
    final typed = List<Map<String, dynamic>>.from(
        records.whereType<Map<String, dynamic>>());
    if (typed.isEmpty) return null;

    typed.sort((a, b) {
      final da = _parseDateForSort(a[dateField]);
      final db = _parseDateForSort(b[dateField]);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return typed.first;
  }

  // ── Markdown / AI text helpers ──────────────────────────────────────────

  String _normalizeMarkdownLine(String input) {
    var line = input;
    line = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
    line = line.replaceFirst(RegExp(r'^\s*(?:[-*]|-)\s+'), '');
    return line;
  }

  String _cleanResidualMarkdown(String input) {
    var text = input;
    text = text.replaceAll('**', '');
    text = text.replaceAll('##', '');
    text = text.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');
    return text;
  }

  List<TextSpan> _parseInlineMarkdown(String input) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    int current = 0;

    for (final match in pattern.allMatches(input)) {
      if (match.start > current) {
        spans.add(TextSpan(
            text:
                _cleanResidualMarkdown(input.substring(current, match.start))));
      }
      spans.add(TextSpan(
        text: match.group(1) ?? '',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
      current = match.end;
    }

    if (current < input.length) {
      spans.add(
          TextSpan(text: _cleanResidualMarkdown(input.substring(current))));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: _cleanResidualMarkdown(input)));
    }

    return spans;
  }

  Widget _buildFormattedAiText(String text) {
    if (text.isEmpty) return const SizedBox.shrink();

    final lines = text.split('\n');
    final List<TextSpan> spans = [];

    for (int i = 0; i < lines.length; i++) {
      final normalizedLine = _normalizeMarkdownLine(lines[i]);
      spans.addAll(_parseInlineMarkdown(normalizedLine));
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }

    return RichText(
      text: TextSpan(
        style:
            const TextStyle(color: Colors.black87, fontSize: 15, height: 1.5),
        children: spans,
      ),
    );
  }

  Map<String, List<String>> _extractAiSections(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => _cleanResidualMarkdown(_normalizeMarkdownLine(l)).trim())
        .toList();

    final Map<String, List<String>> sections = {};
    String currentSection = 'Summary';
    sections[currentSection] = [];

    final headingPattern = RegExp(
      r'^(?:\d+\.\s*)?(RELEVANCE CHECK|RELEVANCE REASON|LABORATORY RESULTS|ABNORMAL FINDINGS|NORMAL RANGES|REFERENCE RANGES|OVERALL ASSESSMENT|RECOMMENDATIONS|KEY OBSERVATIONS)\s*:\s*(.*)$',
      caseSensitive: false,
    );

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.toUpperCase() == 'COMPREHENSIVE LABORATORY ANALYSIS') continue;
      if (RegExp(r'^[-_=]{2,}$').hasMatch(line.replaceAll(' ', ''))) continue;

      final heading = headingPattern.firstMatch(line);
      if (heading != null) {
        currentSection = heading.group(1)!.toUpperCase();
        if (currentSection == 'REFERENCE RANGES') {
          currentSection = 'NORMAL RANGES';
        }
        sections.putIfAbsent(currentSection, () => []);
        final inlineContent = heading.group(2)?.trim() ?? '';
        if (inlineContent.isNotEmpty) {
          sections[currentSection]!.add(inlineContent);
        }
        continue;
      }

      sections.putIfAbsent(currentSection, () => []);
      sections[currentSection]!.add(line);
    }

    sections.removeWhere((_, value) => value.isEmpty);
    return sections;
  }

  bool _isConcerningAnalyte(String text) {
    return RegExp(
      r'protein|glucose|ketone|nitrite|leukocyte|blood|pus|bacteria|bilirubin|hiv|hbsag|vdrl|rpr|syphilis|infection|pathogen',
      caseSensitive: false,
    ).hasMatch(text.toLowerCase());
  }

  String _classifyLabStatus(String testName, String rawValue) {
    final test = testName.toLowerCase();
    final value = rawValue.toLowerCase();
    final merged = '$test $value';

    if (RegExp(r'within normal limits|within normal range|normal range|wnl',
            caseSensitive: false)
        .hasMatch(value)) {
      return 'WITHIN NORMAL LIMITS';
    }

    final isColorFinding = test.contains('color') || test.contains('colour');
    if (isColorFinding) {
      if (RegExp(r'\byellow\b|\bstraw\b|\bpale\b|\bclear\b',
              caseSensitive: false)
          .hasMatch(value)) {
        return 'WITHIN NORMAL LIMITS';
      }
      if (RegExp(r'\bdark\b|\bamber\b|\bbrown\b|\bred\b|\bbloody\b',
              caseSensitive: false)
          .hasMatch(value)) {
        return 'ABNORMAL (REVIEW)';
      }
      return 'OBSERVE';
    }

    if (RegExp(r'\bpositive\b', caseSensitive: false).hasMatch(value)) {
      if (_isConcerningAnalyte(merged)) return 'POSITIVE (REVIEW)';
      if (RegExp(r'pregnancy|hcg', caseSensitive: false).hasMatch(test)) {
        return 'POSITIVE (EXPECTED)';
      }
      return 'POSITIVE';
    }

    if (RegExp(r'\bnegative\b', caseSensitive: false).hasMatch(value)) {
      if (RegExp(r'pregnancy|hcg', caseSensitive: false).hasMatch(test)) {
        return 'NEGATIVE (REVIEW)';
      }
      if (_isConcerningAnalyte(merged)) return 'NEGATIVE (REASSURING)';
      return 'NEGATIVE';
    }

    if (RegExp(r'\btrace\b|\bfew\b|\bslight\b|\bmild\b|\bborderline\b',
            caseSensitive: false)
        .hasMatch(value)) {
      return 'BORDERLINE';
    }

    if (RegExp(
      r'\babnormal\b|\bcritical\b|outside normal range|higher than normal|lower than normal|\belevated\b|\bdecreased\b|\bincreased\b|!',
      caseSensitive: false,
    ).hasMatch(value)) {
      return 'ABNORMAL (REVIEW)';
    }

    if (RegExp(r'\bnormal\b', caseSensitive: false).hasMatch(value)) {
      return 'NORMAL';
    }

    return 'OBSERVE';
  }

  bool _isConcerningStatus(String status) {
    final s = status.toUpperCase();
    return s.contains('REVIEW') || s == 'ABNORMAL';
  }

  bool _isCautionStatus(String status) {
    final s = status.toUpperCase();
    return s == 'OBSERVE' || s == 'BORDERLINE' || s == 'POSITIVE';
  }

  Color _statusChipBackground(String status) {
    if (_isConcerningStatus(status)) {
      return AppColors.error.withValues(alpha: 0.08);
    }
    if (_isCautionStatus(status)) {
      return AppColors.warning.withValues(alpha: 0.08);
    }
    return AppColors.success.withValues(alpha: 0.08);
  }

  Color _statusChipBorder(String status) {
    if (_isConcerningStatus(status)) {
      return AppColors.error.withValues(alpha: 0.25);
    }
    if (_isCautionStatus(status)) {
      return AppColors.warning.withValues(alpha: 0.25);
    }
    return AppColors.success.withValues(alpha: 0.25);
  }

  Color _statusChipTextColor(String status) {
    if (_isConcerningStatus(status)) return AppColors.error;
    if (_isCautionStatus(status)) return AppColors.warning;
    return AppColors.success;
  }

  String _statusMeaning(String status) {
    switch (status.toUpperCase()) {
      case 'WITHIN NORMAL LIMITS':
        return 'Consistent with expected findings for this test.';
      case 'NORMAL':
        return 'Reported as normal for this parameter.';
      case 'ABNORMAL (REVIEW)':
      case 'ABNORMAL':
        return 'May need clinician review with symptoms and history.';
      case 'BORDERLINE':
        return 'Near threshold. Monitor trends and correlate clinically.';
      case 'OBSERVE':
        return 'Not clearly high-risk. Observe and compare with references.';
      case 'POSITIVE (REVIEW)':
        return 'Positive finding that may be clinically significant.';
      case 'POSITIVE (EXPECTED)':
        return 'Positive finding can be expected for this test context.';
      case 'NEGATIVE (REASSURING)':
        return 'No concerning marker detected for this parameter.';
      case 'NEGATIVE (REVIEW)':
        return 'Negative may be unexpected for this context; verify clinically.';
      case 'POSITIVE':
      case 'NEGATIVE':
        return 'Interpret this result based on the specific test context.';
      default:
        return 'Interpret this result together with reference ranges and overall assessment.';
    }
  }

  ({String testName, String value, String status}) _parseLabResultLine(
      String line) {
    final cleaned =
        _safeText(line).replaceFirst(RegExp(r'^[-\-*]\s*'), '').trim();
    final colonIndex = cleaned.indexOf(':');
    if (colonIndex == -1) {
      return (testName: cleaned, value: '', status: 'UNKNOWN');
    }

    final testName = cleaned.substring(0, colonIndex).trim();
    final rawValue = _safeText(cleaned.substring(colonIndex + 1)).trim();
    final status = _classifyLabStatus(testName, rawValue);

    final value = rawValue
        .replaceAll('!', '')
        .replaceAll(RegExp(r'\bABNORMAL\b', caseSensitive: false), '')
        .trim();

    return (
      testName: _stripDecorativeDashes(testName),
      value: _stripDecorativeDashes(value),
      status: status,
    );
  }

  String _safeText(Object? value) => value?.toString() ?? '';

  String _stripDecorativeDashes(String value) {
    final trimmed = value.trim();
    if (RegExp(r'^[-_=]{2,}$').hasMatch(trimmed)) return '';
    return trimmed.replaceAll(RegExp(r'\s+--+\s+'), ' ').trim();
  }

  String _normalizeAspectKey(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool _lineMatchesAspect(String line, String aspect) {
    final a = _normalizeAspectKey(_safeText(aspect));
    final l = _normalizeAspectKey(_safeText(line));
    return a.isNotEmpty && l.contains(a);
  }

  String _buildAspectDetails(
      String aspect, List<String> abnormalLines, List<String> rangeLines) {
    final matches = <String>[];
    for (final line in abnormalLines) {
      if (_lineMatchesAspect(line, aspect)) matches.add(line);
    }
    for (final line in rangeLines) {
      if (_lineMatchesAspect(line, aspect)) matches.add('Reference: $line');
    }
    return matches.join('\n\n').trim();
  }

  Widget _buildLabResultsSummaryCard(Map<String, List<String>> sections) {
    final labLines = sections['LABORATORY RESULTS'] ?? const <String>[];
    final abnormalLines = sections['ABNORMAL FINDINGS'] ?? const <String>[];
    final rangeLines = sections['NORMAL RANGES'] ?? const <String>[];

    final rows = labLines
        .map(_parseLabResultLine)
        .where((r) => r.testName.isNotEmpty && r.status != 'UNKNOWN')
        .toList();

    if (rows.isEmpty) {
      return _buildAiSectionCard('LABORATORY RESULTS', labLines);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science_outlined,
                  size: 18, color: AppColors.brandPrimary),
              SizedBox(width: 8),
              Text(
                'Laboratory Results',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Status guide: REVIEW = needs clinician review, BORDERLINE/OBSERVE = monitor and correlate, WITHIN NORMAL LIMITS = reassuring in context.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary, height: 1.35),
            ),
          ),
          const SizedBox(height: 10),
          ...rows.map((row) {
            final details =
                _buildAspectDetails(row.testName, abnormalLines, rangeLines);
            final aspectKey = _normalizeAspectKey(row.testName);
            final isExpanded = _expandedLabInsightAspects.contains(aspectKey);
            final hasDetails = details.isNotEmpty;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderPrimary),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(row.testName,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                      SizedBox(
                        width: 24,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          splashRadius: 16,
                          onPressed: hasDetails
                              ? () {
                                  setState(() {
                                    if (isExpanded) {
                                      _expandedLabInsightAspects
                                          .remove(aspectKey);
                                    } else {
                                      _expandedLabInsightAspects.add(aspectKey);
                                    }
                                  });
                                }
                              : null,
                          icon: Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusChipBackground(row.status),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: _statusChipBorder(row.status)),
                        ),
                        child: Text(
                          row.status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _statusChipTextColor(row.status),
                          ),
                        ),
                      ),
                      if (row.value.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.bgSecondary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            row.value,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _statusMeaning(row.status),
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.35),
                  ),
                  if (isExpanded && hasDetails)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildFormattedAiText(details),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _friendlyAiSectionTitle(String title) {
    switch (title) {
      case 'LABORATORY RESULTS':
        return 'Laboratory Results';
      case 'ABNORMAL FINDINGS':
        return 'Abnormal Findings';
      case 'NORMAL RANGES':
        return 'Reference Ranges';
      case 'OVERALL ASSESSMENT':
        return 'Overall Assessment';
      case 'RECOMMENDATIONS':
        return 'Recommendations';
      case 'RELEVANCE CHECK':
        return 'Relevance Check';
      case 'RELEVANCE REASON':
        return 'Relevance Reason';
      case 'KEY OBSERVATIONS':
        return 'Key Observations';
      default:
        return title
            .split(' ')
            .map(
                (w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
            .join(' ');
    }
  }

  Widget _buildAiSectionCard(String title, List<String> lines) {
    final safeTitle = _safeText(title).toUpperCase();
    final isAbnormal = safeTitle.contains('ABNORMAL');
    final isRecommendation = safeTitle.contains('RECOMMENDATION');
    final isAssessment = safeTitle.contains('ASSESSMENT');

    final Color accent = isAbnormal
        ? AppColors.error
        : isRecommendation
            ? Colors.blue
            : isAssessment
                ? AppColors.brandAccent
                : AppColors.brandPrimary;

    final IconData icon = isAbnormal
        ? Icons.warning_amber_rounded
        : isRecommendation
            ? Icons.lightbulb_outline
            : isAssessment
                ? Icons.health_and_safety_outlined
                : Icons.article_outlined;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _friendlyAiSectionTitle(safeTitle),
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (safeTitle == 'LABORATORY RESULTS')
            _buildLabResultRows(lines)
          else
            ...lines.map((line) {
              final cleaned =
                  line.replaceFirst(RegExp(r'^[-\-*]\s*'), '').trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6, right: 8),
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                    Expanded(child: _buildFormattedAiText(cleaned)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildLabResultRows(List<String> lines) {
    return Column(
      children: lines.map((line) {
        final parsed = _parseLabResultLine(line);
        final concerning = _isConcerningStatus(parsed.status);
        final caution = _isCautionStatus(parsed.status);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: concerning
                ? AppColors.error.withValues(alpha: 0.08)
                : caution
                    ? AppColors.warning.withValues(alpha: 0.08)
                    : AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: concerning
                  ? AppColors.error.withValues(alpha: 0.25)
                  : caution
                      ? AppColors.warning.withValues(alpha: 0.25)
                      : AppColors.success.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(parsed.testName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    if (parsed.value.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(parsed.value,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _statusMeaning(parsed.status),
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: concerning
                      ? AppColors.error
                      : caution
                          ? AppColors.warning
                          : AppColors.success,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  parsed.status,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Record detail navigation ────────────────────────────────────────────

  void _showRecordDetails({
    required String title,
    required List<MapEntry<String, String>> rows,
    IconData icon = Icons.receipt_long,
    String? subtitle,
    List<String>? imageUrls,
    String? aiAnalysis,
    bool useStructuredAiInsights = false,
    String? riskLevel,
    String? riskFactors,
    List<String>? suggestedActions,
    Map<String, dynamic>? weightGainEval,
    String? approvedByName,
    bool? isMidwifeApproved,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordDetailScreen(
          approvedByName: approvedByName,
          isMidwifeApproved: isMidwifeApproved,
          title: title,
          rows: rows,
          icon: icon,
          subtitle: subtitle,
          imageUrls: imageUrls,
          aiAnalysis: aiAnalysis,
          useStructuredAiInsights: useStructuredAiInsights,
          riskLevel: (riskLevel != null && riskLevel.trim().isNotEmpty)
              ? riskLevel
              : null,
          riskFactors: (riskFactors != null && riskFactors.trim().isNotEmpty)
              ? riskFactors.split(';').map((s) => s.trim()).toList()
              : null,
          suggestedActions: suggestedActions,
          weightGainEval: weightGainEval,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchCheckupDetails(
      int prenatalCheckupId, dynamic checkupDateTime) async {
    try {
      final aiRow = await SupabaseService.client
          .from('ai_responses')
          .select('ai_response_id, response')
          .eq('reference_table', 'prenatal_checkups')
          .eq('reference_id', prenatalCheckupId)
          .eq('response_type', 'risk_assessment')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      String? aiResponse = aiRow?['response'] as String?;
      String? riskLevel;
      String riskFactors = '';
      String medicationPlans = 'None';
      String givenMedications = 'None';
      String ferrousQuantity = 'Not given';
      String calciumQuantity = 'Not given';

      if (aiRow != null) {
        final aiResponseId = aiRow['ai_response_id'] != null
            ? int.tryParse(aiRow['ai_response_id'].toString())
            : null;
        if (aiResponseId != null) {
          final riskRow = await SupabaseService.client
              .from('pregnancy_risk_assessments')
              .select('pregnancy_risk_id, risk_level')
              .eq('ai_response_id', aiResponseId)
              .maybeSingle();

          if (riskRow != null) {
            riskLevel = riskRow['risk_level']?.toString();
            final factorRows = await SupabaseService.client
                .from('pregnancy_risk_factors')
                .select('factor, risk_influence')
                .eq('pregnancy_risk_id', riskRow['pregnancy_risk_id'])
                .order('risk_factor_id', ascending: true);

            final factorList = <String>[];
            for (final factor
                in (factorRows as List).cast<Map<String, dynamic>>()) {
              final factorText = factor['factor']?.toString() ?? '';
              final influence = factor['risk_influence']?.toString() ?? '';
              if (factorText.isNotEmpty) {
                factorList.add(
                    '$factorText${influence.isNotEmpty ? ' ($influence)' : ''}');
              }
            }
            riskFactors = factorList.join('; ');
          }
        }
      }

      if (checkupDateTime != null) {
        final date = DateTime.tryParse(checkupDateTime.toString());
        final checkupDateString =
            date != null ? date.toIso8601String().split('T')[0] : null;
        if (checkupDateString != null) {
          final givenRows = await SupabaseService.client
              .from('given_medications')
              .select('given_medication_name, quantity')
              .eq('mother_id', widget.motherId)
              .eq('date_given', checkupDateString);

          final medicationRows = await SupabaseService.client
              .from('mother_medications')
              .select(
                  'mother_medication_name, quantity, frequency, start_date, end_date')
              .eq('mother_id', widget.motherId)
              .eq('start_date', checkupDateString);

          final givenItems = <String>[];
          for (final row in (givenRows as List).cast<Map<String, dynamic>>()) {
            final name = row['given_medication_name']?.toString() ?? 'Unknown';
            final quantity = row['quantity']?.toString() ?? '1';
            givenItems.add('$name x$quantity');
            if (name.toLowerCase().contains('ferrous')) {
              ferrousQuantity = quantity;
            }
            if (name.toLowerCase().contains('calcium')) {
              calciumQuantity = quantity;
            }
          }
          if (givenItems.isNotEmpty) givenMedications = givenItems.join('; ');

          final planItems = <String>[];
          for (final row
              in (medicationRows as List).cast<Map<String, dynamic>>()) {
            final name = row['mother_medication_name']?.toString() ?? 'Unknown';
            final qty = row['quantity']?.toString() ?? '1';
            final freq = row['frequency']?.toString();
            final start = row['start_date']?.toString();
            final end = row['end_date']?.toString();
            final details = [
              qty != 'null' ? 'Qty $qty' : null,
              freq,
              start != null ? 'Start $start' : null,
              end != null ? 'End $end' : null,
            ].whereType<String>().join(' · ');
            planItems.add('$name${details.isNotEmpty ? ' ($details)' : ''}');
          }
          if (planItems.isNotEmpty) medicationPlans = planItems.join('; ');
        }
      }

      String symptomSummaryStr = 'None recorded';
      try {
        final symRows = await SupabaseService.client
            .from('pregnancy_symptoms')
            .select(
                'symptom_type_id, notes, symptom_type:symptom_types(symptom_name, risk_category)')
            .eq('prenatal_checkup_id', prenatalCheckupId);

        if ((symRows as List).isNotEmpty) {
          final items = <String>[];
          for (final row in symRows.cast<Map<String, dynamic>>()) {
            final symptomType = row['symptom_type'] as Map<String, dynamic>?;
            final symName =
                symptomType?['symptom_name']?.toString() ?? 'Unknown symptom';
            final risk = symptomType?['risk_category']?.toString() ?? 'unknown';
            final note = (row['notes'] as String?)?.trim();
            items.add(note != null && note.isNotEmpty
                ? '$symName ($risk): $note'
                : '$symName ($risk)');
          }
          symptomSummaryStr = items.join('; ');
        }
      } catch (_) {}

      return {
        'aiResponse': aiResponse,
        'riskLevel': riskLevel,
        'riskFactors': riskFactors,
        'medicationPlans': medicationPlans,
        'givenMedications': givenMedications,
        'ferrousQuantity': ferrousQuantity,
        'calciumQuantity': calciumQuantity,
        'symptomSummary': symptomSummaryStr,
      };
    } catch (_) {
      return null;
    }
  }

  // ── Record cards ────────────────────────────────────────────────────────

  Widget _buildCheckupCard(
      Map<String, dynamic> checkup, int pregnancyId, int fetalCount) {
    final date = _formatDateTime(checkup['checkup_datetime']);
    final bpSys = _formatValue(checkup['blood_pressure_systolic']);
    final bpDia = _formatValue(checkup['blood_pressure_diastolic']);

    return CheckupRecordCard(
      checkup: checkup,
      onTap: () async {
        if (_isOpeningRecord) return;
        setState(() => _isOpeningRecord = true);
        bool hasClosedLoading = false;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(
                color: AppColors.brandPrimary),
          ),
        );

        try {
          final aog = _formatValue(checkup['age_of_gestation']);
          final weight = _formatValue(checkup['checkup_weight']);
          String? aiAnalysis;
          String? riskLevel;
          String riskFactors = '';
          String medicationPlansSummary = 'None';
          String givenMedicationsSummary = 'None';
          String ferrousSummary = 'Not given';
          String calciumSummary = 'Not given';
          String symptomSummary = 'None recorded';

          final checkupId = checkup['prenatal_checkup_id'];

          if (checkupId is int) {
            final checkupDetails = await _fetchCheckupDetails(
                checkupId, checkup['checkup_datetime']);

            if (checkupDetails != null) {
              riskLevel = checkupDetails['riskLevel'] as String?;
              riskFactors = checkupDetails['riskFactors'] ?? '';
              aiAnalysis = checkupDetails['aiResponse'] as String?;
              medicationPlansSummary =
                  checkupDetails['medicationPlans'] ?? 'None';
              givenMedicationsSummary =
                  checkupDetails['givenMedications'] ?? 'None';
              ferrousSummary = checkupDetails['ferrousQuantity'] ?? 'Not given';
              calciumSummary = checkupDetails['calciumQuantity'] ?? 'Not given';
              symptomSummary =
                  checkupDetails['symptomSummary'] ?? 'None recorded';
            }

            if (aiAnalysis == null || aiAnalysis.trim().isEmpty) {
              aiAnalysis =
                  await MotherProfileService.getCheckupAIAnalysis(checkupId);
            }
          }

          if (aiAnalysis == null || aiAnalysis.trim().isEmpty) {
            aiAnalysis = _generatePrenatalAIInsights(checkup);
          } else {
            aiAnalysis = aiAnalysis.trim();
          }

          if (!mounted) return;

          final double? height = await _getMotherHeight();
          if (!mounted) return;

          final heightText =
              height == null ? 'Not recorded' : '${height.toStringAsFixed(1)} cm';
          String bmiText = '—';
          String bmiStatus = '—';
          try {
            final w =
                double.tryParse(checkup['checkup_weight']?.toString() ?? '');
            if (w != null && height != null && height > 0) {
              final hm = height / 100;
              final bmi = w / (hm * hm);
              bmiText = bmi.toStringAsFixed(1);
              if (bmi < 18.5) {
                bmiStatus = 'Underweight';
              } else if (bmi < 25) {
                bmiStatus = 'Normal';
              } else if (bmi < 30) {
                bmiStatus = 'Overweight';
              } else {
                bmiStatus = 'Obese';
              }
            }
          } catch (_) {}

          if (mounted && !hasClosedLoading) {
            Navigator.of(context, rootNavigator: true).pop();
            hasClosedLoading = true;
          }

          String midwifeName = '—';
          if (checkup['midwife'] != null) {
            final midwife = checkup['midwife'] as Map<String, dynamic>;
            final account = midwife['account'] as Map<String, dynamic>?;
            if (account != null) {
              midwifeName = '${account['first_name'] ?? ''} ${account['last_name'] ?? ''}'.trim();
            }
          }

          _showRecordDetails(
            title: 'Prenatal Checkup',
            subtitle: date,
            icon: Icons.medical_services,
            approvedByName: midwifeName == '—' ? null : midwifeName,
            isMidwifeApproved: checkup['is_midwife_approved'] == true,
            rows: [
              MapEntry('Conducted by', midwifeName),
              MapEntry('Fetal Count', fetalCount.toString()),
              MapEntry('Age of Gestation', aog),
              MapEntry('Weight (kg)', weight),
              MapEntry('Height', heightText),
              MapEntry('BMI', bmiText),
              MapEntry('BMI Status', bmiStatus),
              MapEntry('Blood Pressure', '$bpSys/$bpDia'),
              MapEntry('Fetal Position', _formatValue(checkup['fetal_position'])),
              MapEntry(
                  'Fetal Heart Tone', _formatValue(checkup['fetal_heart_tone'])),
              MapEntry(
                  'Fetal Heart Beat', _formatValue(checkup['fetal_heart_beat'])),
              MapEntry('Symptoms', symptomSummary),
              MapEntry('Medication Plans', medicationPlansSummary),
              MapEntry('Given Medications', givenMedicationsSummary),
              MapEntry('Ferrous + FA', ferrousSummary),
              MapEntry('Calcium', calciumSummary),
              MapEntry('TD Vaccine', _formatValue(checkup['td_vaccine_dose'])),
              MapEntry('Edema', _formatValue(checkup['edema'])),
              MapEntry('Remarks', _formatValue(checkup['remarks'])),
              MapEntry('Next Schedule', _formatDate(checkup['next_schedule'])),
            ],
            aiAnalysis: aiAnalysis,
            riskLevel: riskLevel,
            riskFactors: riskFactors,
            weightGainEval: (checkup['weight_gain'] as List?)?.isNotEmpty == true
                ? (checkup['weight_gain'] as List).first as Map<String, dynamic>
                : null,
          );
        } finally {
          if (mounted && !hasClosedLoading) {
            Navigator.of(context, rootNavigator: true).pop();
            hasClosedLoading = true;
          }
          if (mounted) {
            setState(() => _isOpeningRecord = false);
          }
        }
      },
    );
  }

  Widget _buildUltrasoundCard(Map<String, dynamic> ultrasound) {
    final date = _formatDate(ultrasound['ultrasound_date']);

    return UltrasoundRecordCard(
      ultrasound: ultrasound,
      onTap: () async {
        if (_isOpeningRecord) return;
        setState(() => _isOpeningRecord = true);
        bool hasClosedLoading = false;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(
                color: AppColors.brandPrimary),
          ),
        );

        try {
          List<String> imageUrls = [];

          if (ultrasound['ultrasound_image'] != null) {
            final imageField = ultrasound['ultrasound_image'].toString();
            if (imageField.contains(',')) {
              imageUrls = imageField.split(',').map((url) => url.trim()).toList();
            } else if (imageField.isNotEmpty) {
              imageUrls = [imageField];
            }
          }

          final split = _splitRemarksAndAi(ultrasound['remarks']?.toString());

          String? aiAnalysis;
          final ultrasoundId = ultrasound['ultrasound_id'];
          if (ultrasoundId is int) {
            aiAnalysis =
                await MotherProfileService.getUltrasoundAIAnalysis(ultrasoundId);
          }

          if (!mounted) return;

          String finalRemarks = split.cleanRemarks;
          if (aiAnalysis != null && aiAnalysis.trim() == finalRemarks.trim()) {
            finalRemarks = '';
          }

          aiAnalysis = (aiAnalysis != null && aiAnalysis.trim().isNotEmpty)
              ? aiAnalysis.trim()
              : split.extractedAi ?? _generateUltrasoundAIInsights(ultrasound);

          String midwifeName = '—';
          if (ultrasound['recorded_by'] != null) {
            final recordedBy = ultrasound['recorded_by'] as Map<String, dynamic>;
            final account = recordedBy['account'] as Map<String, dynamic>?;
            if (account != null) {
              midwifeName = '${account['first_name'] ?? ''} ${account['last_name'] ?? ''}'.trim();
            }
          }

          if (mounted && !hasClosedLoading) {
            Navigator.of(context, rootNavigator: true).pop();
            hasClosedLoading = true;
          }

          _showRecordDetails(
            title: 'Ultrasound',
            subtitle: date,
            icon: Icons.monitor_heart,
            imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
            approvedByName: midwifeName == '—' ? null : midwifeName,
            isMidwifeApproved: ultrasound['is_midwife_approved'] == true,
            rows: [
              MapEntry('Recorded by', midwifeName),
              MapEntry(
                  'Ultrasound Date', _formatDate(ultrasound['ultrasound_date'])),
              MapEntry(
                  'Location', _formatValue(ultrasound['ultrasound_location'])),
              MapEntry(
                  'Full Name', _formatValue(ultrasound['health_worker_name'])),
              MapEntry('Institution',
                  _formatValue(ultrasound['health_worker_institution'])),
              MapEntry('Profession',
                  _formatValue(ultrasound['health_worker_profession'])),
              MapEntry('Remarks', _formatValue(finalRemarks)),
            ],
            aiAnalysis: aiAnalysis,
            useStructuredAiInsights: aiAnalysis.isNotEmpty,
          );
        } finally {
          if (mounted && !hasClosedLoading) {
            Navigator.of(context, rootNavigator: true).pop();
            hasClosedLoading = true;
          }
          if (mounted) {
            setState(() => _isOpeningRecord = false);
          }
        }
      },
    );
  }

  Widget _buildLabTestCard(Map<String, dynamic> labTest) {
    final date = _formatDate(labTest['lab_test_date']);
    final type = labTest['lab_test_type'] ?? 'Lab Test';

    return LabTestRecordCard(
      labTest: labTest,
      onTap: () async {
        if (_isOpeningRecord) return;
        setState(() => _isOpeningRecord = true);
        bool hasClosedLoading = false;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(
                color: AppColors.brandPrimary),
          ),
        );

        try {
          List<String> imageUrls = [];

          if (labTest['lab_test_image'] != null) {
            final imageField = labTest['lab_test_image'].toString();
            if (imageField.contains(',')) {
              imageUrls = imageField.split(',').map((url) => url.trim()).toList();
            } else if (imageField.isNotEmpty) {
              imageUrls = [imageField];
            }
          }

          final split = _splitRemarksAndAi(labTest['remarks']?.toString());

          String? aiAnalysis;
          final labTestId = labTest['lab_test_id'];
          if (labTestId is int) {
            aiAnalysis =
                await MotherProfileService.getLabTestAIAnalysis(labTestId);
          }

           if (!mounted) return;

          aiAnalysis = (aiAnalysis != null && aiAnalysis.trim().isNotEmpty)
              ? aiAnalysis.trim()
              : split.extractedAi;

          String midwifeName = '—';
          if (labTest['recorded_by'] != null) {
            final recordedBy = labTest['recorded_by'] as Map<String, dynamic>;
            final account = recordedBy['account'] as Map<String, dynamic>?;
            if (account != null) {
              midwifeName = '${account['first_name'] ?? ''} ${account['last_name'] ?? ''}'.trim();
            }
          }

          if (mounted && !hasClosedLoading) {
            Navigator.of(context, rootNavigator: true).pop();
            hasClosedLoading = true;
          }

          _showRecordDetails(
            title: type,
            subtitle: date,
            icon: Icons.science,
            imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
            approvedByName: midwifeName == '—' ? null : midwifeName,
            isMidwifeApproved: labTest['is_midwife_approved'] == true,
            rows: [
              MapEntry('Recorded by', midwifeName),
              MapEntry('Lab Test Type', type),
              MapEntry('Lab Test Date', _formatDate(labTest['lab_test_date'])),
              MapEntry('Full Name', _formatValue(labTest['health_worker_name'])),
              MapEntry('Institution',
                  _formatValue(labTest['health_worker_institution'])),
              MapEntry('Profession',
                  _formatValue(labTest['health_worker_profession'])),
              MapEntry('Notes', _formatValue(split.cleanRemarks)),
            ],
            aiAnalysis: aiAnalysis,
            useStructuredAiInsights: aiAnalysis != null && aiAnalysis.isNotEmpty,
          );
        } finally {
          if (mounted && !hasClosedLoading) {
            Navigator.of(context, rootNavigator: true).pop();
            hasClosedLoading = true;
          }
          if (mounted) {
            setState(() => _isOpeningRecord = false);
          }
        }
      },
    );
  }

  Widget _buildMaternalVitalCard(Map<String, dynamic> vital) {
    return MaternalVitalRecordCard(
      vital: vital,
      onTap: () async {
        if (_isOpeningRecord) return;
        setState(() => _isOpeningRecord = true);
        bool hasClosedLoading = false;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(
                color: AppColors.brandPrimary),
          ),
        );

        try {
          final recDate = _formatDateTime(vital['recorded_at']);
          
          if (mounted && !hasClosedLoading) {
            Navigator.of(context, rootNavigator: true).pop();
            hasClosedLoading = true;
          }

          _showRecordDetails(
            title: 'Self-logged Vitals',
            subtitle: 'Recorded on $recDate',
            icon: Icons.monitor_weight_outlined,
            rows: [
              MapEntry('Date', recDate),
              MapEntry(
                'Age of Gestation',
                vital['age_of_gestation'] != null ? '${vital['age_of_gestation']} wks' : '-',
              ),
              MapEntry(
                'Weight (kg)',
                vital['weight_kg'] != null ? '${vital['weight_kg']} kg' : '-',
              ),
              MapEntry(
                'Height (cm)',
                vital['height_cm'] != null ? '${vital['height_cm']} cm' : '-',
              ),
              MapEntry(
                'Notes',
                _formatValue(vital['notes']),
              ),
            ],
          );
        } finally {
          if (mounted && !hasClosedLoading) {
            Navigator.of(context, rootNavigator: true).pop();
            hasClosedLoading = true;
          }
          if (mounted) {
            setState(() => _isOpeningRecord = false);
          }
        }
      },
    );
  }

  // ── Sorting / filtering helpers ─────────────────────────────────────────

  DateTime? _parseDateForSort(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  List<Map<String, dynamic>> _sortByDate(
      List list, String field, String order) {
    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final dateA = _parseDateForSort(a[field]);
      final dateB = _parseDateForSort(b[field]);
      if (dateA == null || dateB == null) return 0;
      return order == 'desc' ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
    });
    return sorted;
  }

  List<Map<String, dynamic>> _filterAndSortChildren(List children) {
    var filtered = List<Map<String, dynamic>>.from(children).where((c) {
      final name = [c['first_name'], c['middle_name'], c['last_name']]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      return name.contains(_childQuery.toLowerCase());
    }).toList();

    if (_childSort == 'name') {
      filtered.sort((a, b) {
        final nameA = '${a['last_name'] ?? ''}${a['first_name'] ?? ''}';
        final nameB = '${b['last_name'] ?? ''}${b['first_name'] ?? ''}';
        return nameA.compareTo(nameB);
      });
    }

    return filtered;
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────

  Future<void> _showConcludePregnancyDialog(
      Map<String, dynamic> pregnancy) async {
    final int fetalCount =
        int.tryParse(pregnancy['fetal_count']?.toString() ?? '') ?? 1;
    final lmpDate = DateTime.tryParse(pregnancy['last_menstrual_period'] ?? '');

    List<String> outcomes = List.filled(fetalCount, 'live_birth');
    List<DateTime> outcomeDates = List.filled(fetalCount, DateTime.now());
    List<DateTime?> deliveryDates = List.filled(fetalCount, null);
    List<String?> placesOfDelivery = List.filled(fetalCount, null);
    List<String?> deliveryMethods = List.filled(fetalCount, null);

    final placeControllers =
        List.generate(fetalCount, (_) => TextEditingController());
    final outcomeDateControllers = List.generate(
      fetalCount,
      (i) => TextEditingController(
        text: DateFormat('MMMM d, yyyy').format(outcomeDates[i]),
      ),
    );

    // Helper: compute gestational age from LMP to earliest outcome date
    double? computeGestAge(List<DateTime> dates) {
      if (lmpDate == null) return null;
      final earliest = dates.reduce((a, b) => a.isBefore(b) ? a : b);
      final weeks = earliest.difference(lmpDate).inDays / 7;
      return weeks < 0 ? null : double.parse(weeks.toStringAsFixed(1));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final gestAge = computeGestAge(outcomeDates);

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: AppColors.cardColorOf(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Drag handle
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
                          // ── Header ──
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.error.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.flag, color: AppColors.error),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                  child: Headline(text: 'Conclude Pregnancy')),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),

                          // ── Fetal count badge ──
                          if (fetalCount > 1) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color:
                                        AppColors.info.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline,
                                      size: 16, color: AppColors.info),
                                  const SizedBox(width: 8),
                                  Text(
                                    'This pregnancy has $fetalCount fetuses. '
                                    'Please fill out the outcome for each.',
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.info),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // ── Per-fetus forms ──
                          for (int i = 0; i < fetalCount; i++) ...[
                            if (fetalCount > 1)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandPrimary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Fetus ${i + 1} of $fetalCount',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.brandPrimary)),
                                ),
                              ),

                            // Outcome dropdown
                            AppDropdownField<String>(
                              hintText: 'Outcome',
                              leadingIcon: Icons.pregnant_woman_outlined,
                              value: outcomes[i],
                              options: const [
                                'live_birth',
                                'stillbirth',
                                'miscarriage',
                                'abortion',
                                'ectopic'
                              ],
                              displayStringForOption: (val) {
                                switch (val) {
                                  case 'live_birth':
                                    return 'Live Birth';
                                  case 'stillbirth':
                                    return 'Stillbirth';
                                  case 'miscarriage':
                                    return 'Miscarriage';
                                  case 'abortion':
                                    return 'Abortion';
                                  case 'ectopic':
                                    return 'Ectopic';
                                  default:
                                    return 'Live Birth';
                                }
                              },
                              onSelected: (val) {
                                setModal(() {
                                  outcomes[i] = val;
                                  if (val == 'live_birth' || val == 'stillbirth') {
                                    deliveryDates[i] = outcomeDates[i];
                                  } else {
                                    deliveryDates[i] = null;
                                    placesOfDelivery[i] = null;
                                    deliveryMethods[i] = null;
                                    placeControllers[i].clear();
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 16),

                            // Outcome date picker
                            AppInputField(
                              hintText: 'Outcome Date',
                              controller: outcomeDateControllers[i],
                              isRequired: true,
                              leadingIcon: Icons.calendar_today_outlined,
                              readOnly: true,
                              onTap: () async {
                                final picked = await _showBrandedDatePicker(
                                  context: ctx,
                                  initialDate: outcomeDates[i],
                                  firstDate: lmpDate ?? DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setModal(() {
                                    outcomeDates[i] = picked;
                                    outcomeDateControllers[i].text =
                                        DateFormat('MMMM d, yyyy').format(picked);
                                    if (outcomes[i] == 'live_birth' ||
                                        outcomes[i] == 'stillbirth') {
                                      deliveryDates[i] = picked;
                                    }
                                  });
                                }
                              },
                            ),

                            // Delivery fields (only for live_birth / stillbirth)
                            if (outcomes[i] == 'live_birth' ||
                                outcomes[i] == 'stillbirth') ...[
                              const SizedBox(height: 16),
                              AppInputField(
                                hintText: 'Place of Delivery',
                                controller: placeControllers[i],
                                leadingIcon: Icons.local_hospital_outlined,
                                isRequired: true,
                                onChanged: (v) => placesOfDelivery[i] = v,
                              ),
                              const SizedBox(height: 16),
                              AppDropdownField<String>(
                                hintText: 'Delivery Method',
                                leadingIcon: Icons.healing_outlined,
                                value: deliveryMethods[i],
                                options: const ['NSD', 'CS', 'Instrumental'],
                                displayStringForOption: (val) {
                                  switch (val) {
                                    case 'NSD':
                                      return 'Normal Spontaneous Delivery';
                                    case 'CS':
                                      return 'Cesarean Section';
                                    case 'Instrumental':
                                      return 'Instrumental';
                                    default:
                                      return 'Normal Spontaneous Delivery';
                                  }
                                },
                                onSelected: (val) {
                                  setModal(() {
                                    deliveryMethods[i] = val;
                                  });
                                },
                              ),
                            ],
                            const SizedBox(height: 20),
                            if (i < fetalCount - 1)
                              const Divider(
                                  height: 24, color: AppColors.borderPrimary),
                          ],

                          // ── Gestational age (auto-computed, read-only) ──
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.bgSecondary,
                              borderRadius: BorderRadius.circular(28),
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
                                  child: const Icon(Icons.timer_outlined,
                                      size: 18, color: AppColors.brandPrimary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Gestational Age at End',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        gestAge != null
                                            ? '${gestAge.toStringAsFixed(1)} weeks'
                                            : 'Unable to compute (no LMP)',
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
                                const Icon(Icons.lock_outline,
                                    size: 16, color: AppColors.textSecondary),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'Auto-computed from LMP and outcome date',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  fontStyle: FontStyle.italic),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ── Submit ──
                          MainButton(
                            label: 'Conclude Pregnancy',
                            onPressed: () async {
                              // Validate delivery method for live/stillbirth
                              for (int i = 0; i < fetalCount; i++) {
                                if (outcomes[i] == 'live_birth' ||
                                    outcomes[i] == 'stillbirth') {
                                  if (placesOfDelivery[i] == null ||
                                      placesOfDelivery[i]!.trim().isEmpty) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                          'Please enter place of delivery for Fetus ${i + 1}'),
                                    ));
                                    return;
                                  }
                                  if (deliveryMethods[i] == null) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                          'Please select delivery method for Fetus ${i + 1}'),
                                    ));
                                    return;
                                  }
                                }
                              }

                              // Validate outcome dates are not before LMP
                              if (lmpDate != null) {
                                for (int i = 0; i < fetalCount; i++) {
                                  if (outcomeDates[i].isBefore(lmpDate)) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                          'Outcome date for Fetus ${i + 1} cannot be before LMP'),
                                    ));
                                    return;
                                  }
                                }
                              }

                              final fetalOutcomes = <Map<String, dynamic>>[];
                              for (int i = 0; i < fetalCount; i++) {
                                fetalOutcomes.add({
                                  'fetus_number': i + 1,
                                  'outcome': outcomes[i],
                                  'outcome_date': outcomeDates[i]
                                      .toIso8601String()
                                      .split('T')[0],
                                  'delivery_date': deliveryDates[i]
                                      ?.toIso8601String()
                                      .split('T')[0],
                                  'place_of_delivery': placesOfDelivery[i] ??
                                      placeControllers[i].text,
                                  'delivery_method': deliveryMethods[i],
                                });
                              }

                              final success =
                                  await MotherProfileService.concludePregnancy(
                                pregnancy['pregnancy_id'],
                                gestAge,
                                fetalOutcomes,
                              );

                              if (!mounted) return;
                              if (success) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Pregnancy concluded successfully')),
                                );
                                _refresh();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Failed to conclude pregnancy')),
                                );
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

    for (final pc in placeControllers) {
      pc.dispose();
    }
    for (final oc in outcomeDateControllers) {
      oc.dispose();
    }
  }

  Future<void> _startNewPregnancyDialog([List? pastPregnancies]) async {
    // ── Pre-emptive Postpartum Recovery Window Validation ──
    const minGapDays = 42;
    if (pastPregnancies != null && pastPregnancies.isNotEmpty) {
      DateTime? latestOutcomeDate;
      for (final past in pastPregnancies) {
        final outcomesList = past['outcomes'] as List?;
        if (outcomesList != null && outcomesList.isNotEmpty) {
          for (final o in outcomesList) {
            final oDate = DateTime.tryParse(o['outcome_date'] ?? '');
            if (oDate != null && (latestOutcomeDate == null || oDate.isAfter(latestOutcomeDate))) {
              latestOutcomeDate = oDate;
            }
          }
        }
        
        // Fallback to ended_at or expected_date_of_delivery
        if (latestOutcomeDate == null) {
          final endedAtStr = past['ended_at'] ?? past['expected_date_of_delivery'];
          final endedDate = DateTime.tryParse(endedAtStr ?? '');
          if (endedDate != null && (latestOutcomeDate == null || endedDate.isAfter(latestOutcomeDate))) {
            latestOutcomeDate = endedDate;
          }
        }
      }

      if (latestOutcomeDate != null) {
        final gap = DateTime.now().difference(latestOutcomeDate).inDays;
        if (gap >= 0 && gap < minGapDays) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PageTitle(
                      title: 'Postpartum Recovery',
                      leadingIcon: Icons.warning_amber_rounded,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Cannot start a new pregnancy yet.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The mother\'s previous pregnancy concluded on '
                      '${DateFormat('MMMM d, yyyy').format(latestOutcomeDate!)} '
                      '(only $gap days ago).\n\n'
                      'To protect maternal health, a minimum recovery period of '
                      '42 days (6 weeks) is clinically required.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: MainButton(
                        label: 'Understood',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          return; // Stop here! Do not open the Start New Pregnancy dialog!
        }
      }
    }

    _GestationMethod gestationMethod = _GestationMethod.lmp;
    DateTime? lmp;
    DateTime? edd;
    final lmpCtrl = TextEditingController();
    final eddCtrl = TextEditingController();
    final aogWeeksCtrl = TextEditingController();
    final aogDaysCtrl = TextEditingController();

    String? gestationError;
    String? weeksError;
    String? daysError;

    await showDialog(
      context: context,
      builder: (modalCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialog) {
          // Helper validations
          String? validateLmp(DateTime date) {
            final now = DateTime.now();
            final twoWeeksAgo = now.subtract(const Duration(days: 2 * 7));
            if (date.isAfter(twoWeeksAgo)) {
              return 'LMP must be at least 2 weeks ago.';
            }
            final daysSinceLmp = now.difference(date).inDays;
            if (daysSinceLmp > 42 * 7) {
              return 'LMP is more than 42 weeks ago. Please verify the date.';
            }
            
            // Spacing check (42 days)
            const minGapDays = 42;
            if (pastPregnancies != null && pastPregnancies.isNotEmpty) {
              for (final past in pastPregnancies) {
                final outcomesList = past['outcomes'] as List?;
                DateTime? latestOutcomeDate;
                if (outcomesList != null && outcomesList.isNotEmpty) {
                  for (final o in outcomesList) {
                    final oDate = DateTime.tryParse(o['outcome_date'] ?? '');
                    if (oDate != null && (latestOutcomeDate == null || oDate.isAfter(latestOutcomeDate))) {
                      latestOutcomeDate = oDate;
                    }
                  }
                }
                if (latestOutcomeDate == null) {
                  final endedAtStr = past['ended_at'] ?? past['expected_date_of_delivery'];
                  latestOutcomeDate = DateTime.tryParse(endedAtStr ?? '');
                }
                if (latestOutcomeDate != null) {
                  final gap = date.difference(latestOutcomeDate).inDays;
                  if (gap >= 0 && gap < minGapDays) {
                    return 'Pregnancy interval too short ($gap days). Minimum interval is 42 days (6 weeks) after a previous pregnancy.';
                  }
                }
              }
            }
            return null;
          }

          String? validateEdd(DateTime date) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final eddDate = DateTime(date.year, date.month, date.day);
            if (eddDate.isBefore(today)) {
              return 'EDD cannot be in the past.';
            }
            final maxEdd = today.add(const Duration(days: 43 * 7));
            if (eddDate.isAfter(maxEdd)) {
              return 'EDD cannot be more than 43 weeks from today.';
            }
            return null;
          }

          void updateFromLmp(DateTime date) {
            lmp = date;
            edd = date.add(const Duration(days: 280));
            lmpCtrl.text = DateFormat('MMMM d, yyyy').format(date);
            eddCtrl.text = DateFormat('MMMM d, yyyy').format(edd!);
            gestationError = validateLmp(date);

            final days = DateTime.now().difference(date).inDays;
            if (days >= 0) {
              aogWeeksCtrl.text = (days ~/ 7).toString();
              aogDaysCtrl.text = (days % 7).toString();
            } else {
              aogWeeksCtrl.clear();
              aogDaysCtrl.clear();
            }
            weeksError = null;
            daysError = null;
          }

          void updateFromEdd(DateTime date) {
            edd = date;
            lmp = date.subtract(const Duration(days: 280));
            eddCtrl.text = DateFormat('MMMM d, yyyy').format(date);
            lmpCtrl.text = DateFormat('MMMM d, yyyy').format(lmp!);
            gestationError = validateEdd(date) ?? validateLmp(lmp!);

            final days = DateTime.now().difference(lmp!).inDays;
            if (days >= 0) {
              aogWeeksCtrl.text = (days ~/ 7).toString();
              aogDaysCtrl.text = (days % 7).toString();
            } else {
              aogWeeksCtrl.clear();
              aogDaysCtrl.clear();
            }
            weeksError = null;
            daysError = null;
          }

          void updateFromAog() {
            final wStr = aogWeeksCtrl.text.trim();
            final dStr = aogDaysCtrl.text.trim();

            if (wStr.isEmpty && dStr.isEmpty) {
              lmp = null;
              edd = null;
              lmpCtrl.clear();
              eddCtrl.clear();
              weeksError = null;
              daysError = null;
              gestationError = null;
              return;
            }

            final w = int.tryParse(wStr);
            final d = int.tryParse(dStr);

            String? wErr;
            String? dErr;

            if (w == null && wStr.isNotEmpty) {
              wErr = 'Enter a valid number';
            } else if (w != null && (w < 2 || w > 42)) {
              wErr = 'Must be 2-42';
            }

            if (d == null && dStr.isNotEmpty) {
              dErr = 'Enter a valid number';
            } else if (d != null && (d < 0 || d > 6)) {
              dErr = 'Must be 0-6';
            }

            weeksError = wErr;
            daysError = dErr;
            gestationError = (wErr != null || dErr != null) ? 'Invalid AOG weeks or days' : null;

            if (wErr == null && dErr == null && w != null && d != null) {
              final date = DateTime.now().subtract(Duration(days: w * 7 + d));
              lmp = date;
              edd = date.add(const Duration(days: 280));
              lmpCtrl.text = DateFormat('MMMM d, yyyy').format(date);
              eddCtrl.text = DateFormat('MMMM d, yyyy').format(edd!);
              gestationError = validateLmp(date);
            }
          }

          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            backgroundColor: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PageTitle(
                    title: 'Start New Pregnancy',
                    leadingIcon: Icons.pregnant_woman,
                  ),
                  const SizedBox(height: 20),
                  
                  // Gestational Method Selector
                  AppDropdownField<_GestationMethod>(
                    hintText: 'Calculation Method',
                    leadingIcon: Icons.calculate_outlined,
                    value: gestationMethod,
                    options: const [
                      _GestationMethod.lmp,
                      _GestationMethod.edd,
                      _GestationMethod.aog
                    ],
                    displayStringForOption: (val) {
                      switch (val) {
                        case _GestationMethod.lmp:
                          return 'Last Menstrual Period (LMP)';
                        case _GestationMethod.edd:
                          return 'Estimated Delivery Date (EDD)';
                        case _GestationMethod.aog:
                          return 'Age of Gestation (AOG)';
                      }
                    },
                    onSelected: (val) {
                      setDialog(() {
                        gestationMethod = val;
                        lmp = null;
                        edd = null;
                        lmpCtrl.clear();
                        eddCtrl.clear();
                        aogWeeksCtrl.clear();
                        aogDaysCtrl.clear();
                        gestationError = null;
                        weeksError = null;
                        daysError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Gestation Method Fields
                  if (gestationMethod == _GestationMethod.lmp) ...[
                    AppInputField(
                      hintText: 'Last Menstrual Period',
                      controller: lmpCtrl,
                      isRequired: true,
                      leadingIcon: Icons.calendar_today_outlined,
                      readOnly: true,
                      errorText: gestationError,
                      onTap: () async {
                        final picked = await _showBrandedDatePicker(
                          context: modalCtx,
                          initialDate: DateTime.now().subtract(const Duration(days: 14)),
                          firstDate: DateTime.now().subtract(const Duration(days: 42 * 7)),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialog(() => updateFromLmp(picked));
                        }
                      },
                    ),
                    if (edd != null && gestationError == null) ...[
                      const SizedBox(height: 16),
                      AppInputField(
                        hintText: 'Estimated Due Date',
                        controller: eddCtrl,
                        leadingIcon: Icons.event_available_outlined,
                        readOnly: true,
                      ),
                    ],
                  ] else if (gestationMethod == _GestationMethod.edd) ...[
                    AppInputField(
                      hintText: 'Estimated Due Date',
                      controller: eddCtrl,
                      isRequired: true,
                      leadingIcon: Icons.event_available_outlined,
                      readOnly: true,
                      errorText: gestationError,
                      onTap: () async {
                        final picked = await _showBrandedDatePicker(
                          context: modalCtx,
                          initialDate: DateTime.now().add(const Duration(days: 266)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 43 * 7)),
                        );
                        if (picked != null) {
                          setDialog(() => updateFromEdd(picked));
                        }
                      },
                    ),
                    if (lmp != null && gestationError == null) ...[
                      const SizedBox(height: 16),
                      AppInputField(
                        hintText: 'Last Menstrual Period',
                        controller: lmpCtrl,
                        leadingIcon: Icons.calendar_today_outlined,
                        readOnly: true,
                      ),
                    ],
                  ] else if (gestationMethod == _GestationMethod.aog) ...[
                    Row(
                      children: [
                        Expanded(
                          child: AppInputField(
                            hintText: 'AOG Weeks',
                            controller: aogWeeksCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            errorText: weeksError,
                            onChanged: (v) {
                              setDialog(() => updateFromAog());
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppInputField(
                            hintText: 'AOG Days',
                            controller: aogDaysCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            errorText: daysError,
                            onChanged: (v) {
                              setDialog(() => updateFromAog());
                            },
                          ),
                        ),
                      ],
                    ),
                    if (lmp != null && edd != null && gestationError == null) ...[
                      const SizedBox(height: 16),
                      AppInputField(
                        hintText: 'Last Menstrual Period',
                        controller: lmpCtrl,
                        leadingIcon: Icons.calendar_today_outlined,
                        readOnly: true,
                      ),
                      const SizedBox(height: 16),
                      AppInputField(
                        hintText: 'Estimated Due Date',
                        controller: eddCtrl,
                        leadingIcon: Icons.event_available_outlined,
                        readOnly: true,
                      ),
                    ],
                  ],

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: 'Cancel',
                          onPressed: () => Navigator.pop(modalCtx),
                          showIcons: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MainButton(
                          label: 'Start',
                          onPressed: (lmp == null || gestationError != null)
                              ? null
                              : () async {
                                  final success = await MotherProfileService
                                      .startNewPregnancy(
                                    widget.motherId,
                                    lmp!,
                                    edd!,
                                  );
                                  if (!mounted) return;
                                  if (success) {
                                    Navigator.pop(modalCtx);
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                      content: Text('New pregnancy started'),
                                    ));
                                    _refresh();
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    lmpCtrl.dispose();
    eddCtrl.dispose();
    aogWeeksCtrl.dispose();
    aogDaysCtrl.dispose();
  }

  // ── Editable profile controllers ────────────────────────────────────────

  void _initializePersonalControllers(Map<String, dynamic> profile, Map<String, dynamic>? currentPregnancy) {
    // Dispose existing controllers before creating new ones
    for (final c in _personalControllers.values) {
      c.dispose();
    }
    _personalControllers.clear();

    _personalControllers['height'] =
        TextEditingController(text: profile['height']?.toString() ?? '');
    _personalControllers['weight'] =
        TextEditingController(text: profile['weight']?.toString() ?? '');

    final ppw = currentPregnancy?['pre_pregnancy_weight'];
    _personalControllers['pre_pregnancy_weight'] =
        TextEditingController(text: ppw?.toString() ?? '');

    _editingBloodType = profile['blood_type'] ?? '';
  }

  Future<void> _savePersonalInfo() async {
    final bloodType = _editingBloodType;
    final ppwText = _personalControllers['pre_pregnancy_weight']?.text.trim() ?? '';
    final double? ppw = ppwText.isEmpty ? null : double.tryParse(ppwText);

    try {
      // 1. Update blood type in mothers table
      await SupabaseService.client.from('mothers').update({
        'blood_type': bloodType.isEmpty ? null : bloodType,
      }).eq('mother_id', widget.motherId);

      // 2. Update pre-pregnancy weight in pregnancies table for ongoing pregnancy
      final ongoingPregnancy = await SupabaseService.client
          .from('pregnancies')
          .select('pregnancy_id')
          .eq('mother_id', widget.motherId)
          .eq('status', 'ongoing')
          .maybeSingle();

      if (ongoingPregnancy != null) {
        final pregnancyId = ongoingPregnancy['pregnancy_id'] as int;
        await SupabaseService.client.from('pregnancies').update({
          'pre_pregnancy_weight': ppw,
        }).eq('pregnancy_id', pregnancyId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Medical information updated'),
              backgroundColor: AppColors.success),
        );
        setState(() {
          _isEditingPersonal = false;
          _controllersInitialized = false;
        });
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _initializeAddressControllers(Map<String, dynamic> profile) {
    for (final c in _addressControllers.values) {
      c.dispose();
    }
    _addressControllers.clear();

    _addressControllers['house_number'] =
        TextEditingController(text: profile['house_number'] ?? '');
    _addressControllers['street'] =
        TextEditingController(text: profile['street'] ?? '');
    _addressControllers['barangay'] =
        TextEditingController(text: profile['barangay'] ?? '');
    _addressControllers['city'] =
        TextEditingController(text: profile['city_municipality'] ?? '');
    _addressControllers['province'] =
        TextEditingController(text: profile['province'] ?? '');
  }

  Future<void> _saveAddress() async {
    try {
      await SupabaseService.client.from('mothers').update({
        'house_number': _addressControllers['house_number']?.text.trim(),
        'street': _addressControllers['street']?.text.trim(),
        'barangay': _addressControllers['barangay']?.text.trim(),
        'city_municipality': _addressControllers['city']?.text.trim(),
        'province': _addressControllers['province']?.text.trim(),
      }).eq('mother_id', widget.motherId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Address updated'),
              backgroundColor: AppColors.success),
        );
        // FIX: Force controllers to re-initialize on next build with fresh data
        setState(() {
          _isEditingAddress = false;
          _controllersInitialized = false;
        });
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ── Date Picker Helper ────────────────────────────────────────────────
  Future<DateTime?> _showBrandedDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    DateTime clampedInitial = initialDate;
    if (clampedInitial.isBefore(firstDate)) {
      clampedInitial = firstDate;
    } else if (clampedInitial.isAfter(lastDate)) {
      clampedInitial = lastDate;
    }

    return showDatePicker(
      context: context,
      initialDate: clampedInitial,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.brandPrimary,
              onPrimary: Colors.white,
              onSurface: AppColors.brandText,
              secondary: AppColors.brandPrimary,
              surface: Colors.white,
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor: Colors.white,
              elevation: 4,
              surfaceTintColor: Colors.transparent,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandPrimary,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  // ── Add/Edit/Remove medical conditions ───────────────────────────────────
  Future<void> _showMedicalConditionDialog({Map<String, dynamic>? prefill}) async {
    final nameCtrl = TextEditingController(text: prefill?['condition_name'] ?? '');
    DateTime? diagDate = prefill?['diagnosis_date'] != null ? DateTime.tryParse(prefill!['diagnosis_date'].toString()) : null;
    String status = prefill?['status'] ?? 'active';
    final remarksCtrl = TextEditingController(text: prefill?['remarks'] ?? '');
    final diagDateCtrl = TextEditingController(
        text: diagDate != null ? DateFormat('MMMM d, yyyy').format(diagDate) : '');

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            width: MediaQuery.of(ctx).size.width * 0.9,
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                final inputName = nameCtrl.text.trim();
                final alreadyAdded = _currentMedicalConditions
                    .where((c) =>
                        prefill == null ||
                        c['medical_condition_id'] != prefill['medical_condition_id'])
                    .map((c) => c['condition_name']?.toString().toLowerCase())
                    .toSet();
                
                final isDuplicate = alreadyAdded.contains(inputName.toLowerCase());
                final isFormValid = inputName.isNotEmpty && !isDuplicate;

                final displayedConditions = _commonConditions.where((cond) {
                  if (cond == 'Other') return true;
                  return !alreadyAdded.contains(cond.toLowerCase());
                }).toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.brandText),
                          onPressed: () => Navigator.pop(dialogCtx, false),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              prefill != null ? 'Edit Medical Condition' : 'Medical Condition',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.brandText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (displayedConditions.isNotEmpty) ...[
                              const Text('Common Conditions',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: displayedConditions.map((cond) {
                                  final isSelected = inputName.toLowerCase() ==
                                      cond.toLowerCase();
                                  return ActionChip(
                                    label: Text(cond,
                                        style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : AppColors.brandPrimary,
                                            fontSize: 12)),
                                    backgroundColor: isSelected
                                        ? AppColors.brandPrimary
                                        : Colors.white,
                                    side:
                                        const BorderSide(color: AppColors.brandPrimary),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20)),
                                    onPressed: () {
                                      setDialogState(() {
                                        if (cond == 'Other') {
                                          nameCtrl.clear();
                                        } else {
                                          nameCtrl.text = cond;
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                            ],
                            AppInputField(
                              controller: nameCtrl,
                              hintText: 'Condition Name',
                              isRequired: true,
                              leadingIcon: Icons.medical_services_outlined,
                              errorText: isDuplicate
                                  ? 'Condition already added'
                                  : null,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: diagDateCtrl,
                              hintText: 'Diagnosis Date (Optional)',
                              readOnly: true,
                              leadingIcon: Icons.calendar_today_outlined,
                              onTap: () async {
                                final picked = await _showBrandedDatePicker(
                                  context: dialogCtx,
                                  initialDate: diagDate ?? DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    diagDate = picked;
                                    diagDateCtrl.text = DateFormat('MMMM d, yyyy').format(picked);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            const Text('Status',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setDialogState(() => status = 'active'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'active'
                                            ? AppColors.brandPrimary
                                                .withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: status == 'active'
                                                ? AppColors.brandPrimary
                                                : AppColors.borderPrimary),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Active',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: status == 'active'
                                                  ? AppColors.brandPrimary
                                                  : AppColors.textSecondary)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setDialogState(
                                        () => status = 'resolved'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'resolved'
                                            ? AppColors.brandPrimary
                                                .withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: status == 'resolved'
                                                ? AppColors.brandPrimary
                                                : AppColors.borderPrimary),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Resolved',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: status == 'resolved'
                                                  ? AppColors.brandPrimary
                                                  : AppColors.textSecondary)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: remarksCtrl,
                              hintText: 'Remarks (Optional)',
                              leadingIcon: Icons.notes_outlined,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isFormValid
                            ? () => Navigator.pop(dialogCtx, true)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          prefill != null ? 'Save Changes' : 'Add Condition',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    nameCtrl.dispose();
    remarksCtrl.dispose();
    diagDateCtrl.dispose();

    if (result == true) {
      try {
        final Map<String, dynamic> data = {
          'condition_name': nameCtrl.text.trim(),
          'status': status,
          'diagnosis_date': diagDate?.toIso8601String().split('T')[0],
          'remarks': remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
        };

        if (prefill != null) {
          final condId = prefill['medical_condition_id'];
          await SupabaseService.client
              .from('medical_conditions')
              .update(data)
              .eq('medical_condition_id', condId);
        } else {
          data['mother_id'] = widget.motherId;
          await SupabaseService.client
              .from('medical_conditions')
              .insert(data);
        }
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _addMedicalCondition() async {
    await _showMedicalConditionDialog();
  }

  Future<void> _editMedicalCondition(Map<String, dynamic> condition) async {
    await _showMedicalConditionDialog(prefill: condition);
  }

  Future<void> _removeMedicalCondition(Map<String, dynamic> condition) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Condition'),
        content: Text(
            'Remove "${condition['condition_name']}"? This will mark it as resolved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final conditionId = condition['medical_condition_id'];
        if (conditionId != null) {
          await SupabaseService.client.from('medical_conditions').update(
              {'status': 'resolved'}).eq('medical_condition_id', conditionId);
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  // ── Add/Edit/Remove allergies ───────────────────────────────────────────
  Future<void> _showAllergyDialog({Map<String, dynamic>? prefill}) async {
    final allergenCtrl = TextEditingController(text: prefill?['allergen'] ?? '');
    DateTime? diagDate = prefill?['diagnosis_date'] != null ? DateTime.tryParse(prefill!['diagnosis_date'].toString()) : null;
    String status = prefill?['status'] ?? 'active';
    final treatmentCtrl = TextEditingController(text: prefill?['treatment'] ?? '');
    final remarksCtrl = TextEditingController(text: prefill?['remarks'] ?? '');
    final diagDateCtrl = TextEditingController(
        text: diagDate != null ? DateFormat('MMMM d, yyyy').format(diagDate) : '');

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            width: MediaQuery.of(ctx).size.width * 0.9,
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                final inputName = allergenCtrl.text.trim();
                final alreadyAdded = _currentAllergies
                    .where((a) =>
                        prefill == null ||
                        a['allergy_id'] != prefill['allergy_id'])
                    .map((a) => a['allergen']?.toString().toLowerCase())
                    .toSet();
                
                final isDuplicate = alreadyAdded.contains(inputName.toLowerCase());
                final isFormValid = inputName.isNotEmpty && !isDuplicate;

                final displayedAllergens = _commonAllergens.where((cond) {
                  if (cond == 'Other') return true;
                  return !alreadyAdded.contains(cond.toLowerCase());
                }).toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.brandText),
                          onPressed: () => Navigator.pop(dialogCtx, false),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              prefill != null ? 'Edit Allergy' : 'Add Allergy',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.brandText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (displayedAllergens.isNotEmpty) ...[
                              const Text('Common Allergens',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: displayedAllergens.map((cond) {
                                  final isSelected = inputName.toLowerCase() ==
                                      cond.toLowerCase();
                                  return ActionChip(
                                    label: Text(cond,
                                        style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : AppColors.brandPrimary,
                                            fontSize: 12)),
                                    backgroundColor: isSelected
                                        ? AppColors.brandPrimary
                                        : Colors.white,
                                    side:
                                        const BorderSide(color: AppColors.brandPrimary),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20)),
                                    onPressed: () {
                                      setDialogState(() {
                                        allergenCtrl.text = cond;
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                            ],
                            AppInputField(
                              controller: allergenCtrl,
                              hintText: 'Allergen Name',
                              isRequired: true,
                              leadingIcon: Icons.warning_amber_rounded,
                              errorText: isDuplicate
                                  ? 'Allergen already added'
                                  : null,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: diagDateCtrl,
                              hintText: 'Diagnosis Date (Optional)',
                              readOnly: true,
                              leadingIcon: Icons.calendar_today_outlined,
                              onTap: () async {
                                final picked = await _showBrandedDatePicker(
                                  context: dialogCtx,
                                  initialDate: diagDate ?? DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    diagDate = picked;
                                    diagDateCtrl.text = DateFormat('MMMM d, yyyy').format(picked);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            const Text('Status',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setDialogState(() => status = 'active'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'active'
                                            ? AppColors.brandPrimary
                                                .withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: status == 'active'
                                                ? AppColors.brandPrimary
                                                : AppColors.borderPrimary),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Active',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: status == 'active'
                                                  ? AppColors.brandPrimary
                                                  : AppColors.textSecondary)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setDialogState(
                                        () => status = 'resolved'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: status == 'resolved'
                                            ? AppColors.brandPrimary
                                                .withValues(alpha: 0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: status == 'resolved'
                                                ? AppColors.brandPrimary
                                                : AppColors.borderPrimary),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Resolved',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: status == 'resolved'
                                                  ? AppColors.brandPrimary
                                                  : AppColors.textSecondary)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: treatmentCtrl,
                              hintText: 'Treatment (Optional)',
                              leadingIcon: Icons.medical_services_outlined,
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: remarksCtrl,
                              hintText: 'Remarks (Optional)',
                              leadingIcon: Icons.notes_outlined,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isFormValid
                            ? () => Navigator.pop(dialogCtx, true)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          prefill != null ? 'Save Changes' : 'Add Allergy',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    allergenCtrl.dispose();
    treatmentCtrl.dispose();
    remarksCtrl.dispose();
    diagDateCtrl.dispose();

    if (result == true) {
      try {
        final Map<String, dynamic> data = {
          'allergen': allergenCtrl.text.trim(),
          'status': status,
          'diagnosis_date': diagDate?.toIso8601String().split('T')[0],
          'treatment': treatmentCtrl.text.trim().isEmpty ? null : treatmentCtrl.text.trim(),
          'remarks': remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
        };

        if (prefill != null) {
          final allergyId = prefill['allergy_id'];
          await SupabaseService.client
              .from('allergies')
              .update(data)
              .eq('allergy_id', allergyId);
        } else {
          data['mother_id'] = widget.motherId;
          await SupabaseService.client
              .from('allergies')
              .insert(data);
        }
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _addAllergy() async {
    await _showAllergyDialog();
  }

  Future<void> _editAllergy(Map<String, dynamic> allergy) async {
    await _showAllergyDialog(prefill: allergy);
  }

  Future<void> _removeAllergy(Map<String, dynamic> allergy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Allergy'),
        content: Text(
            'Remove "${allergy['allergen']}"? This will mark it as resolved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final allergyId = allergy['allergy_id'];
        if (allergyId != null) {
          await SupabaseService.client
              .from('allergies')
              .update({'status': 'resolved'}).eq('allergy_id', allergyId);
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  // ── Add/Edit/Remove emergency contacts ───────────────────────────────────
  Future<void> _showEmergencyContactDialog({Map<String, dynamic>? prefill}) async {
    final relationshipOptionsNoOther = [
      'Spouse/Partner',
      'Parent',
      'Child',
      'Sibling',
      'Relative',
      'Friend',
      'Neighbor',
      'Coworker'
    ];
    final isCustomRel = prefill != null &&
        !relationshipOptionsNoOther.contains(prefill['affiliation']);

    final firstNameCtrl = TextEditingController(text: prefill?['first_name'] ?? '');
    final lastNameCtrl = TextEditingController(text: prefill?['last_name'] ?? '');
    final phoneCtrl = TextEditingController(text: prefill?['phone_number'] ?? '');
    final relationshipCtrl = TextEditingController(
        text: isCustomRel
            ? 'Other'
            : (prefill != null ? (prefill['affiliation']?.toString() ?? '') : ''));
    final customRelationshipCtrl = TextEditingController(
        text: isCustomRel ? (prefill['affiliation']?.toString() ?? '') : '');

    bool showRelationshipDropdown = false;
    String? phoneError;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                void validatePhone(String val) {
                  final normalized = val.trim().replaceAll(RegExp(r'[^0-9+]'), '');
                  final isValid = RegExp(r'^(\+?63|0)9\d{9}$').hasMatch(normalized);
                  setDialogState(() {
                    phoneError = val.isEmpty
                        ? null
                        : (isValid ? null : 'Enter a valid PH mobile number');
                  });
                }

                final isPhoneValid = phoneCtrl.text.trim().isNotEmpty && phoneError == null;
                final isRelationshipValid = relationshipCtrl.text.trim().isNotEmpty &&
                    (relationshipCtrl.text.trim() != 'Other' ||
                        customRelationshipCtrl.text.trim().isNotEmpty);
                final isFormValid = firstNameCtrl.text.trim().isNotEmpty &&
                    lastNameCtrl.text.trim().isNotEmpty &&
                    isPhoneValid &&
                    isRelationshipValid;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.brandText),
                          onPressed: () => Navigator.pop(dialogCtx, false),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              prefill != null ? 'Edit Emergency Contact' : 'Add Emergency Contact',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.brandText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppInputField(
                              controller: firstNameCtrl,
                              hintText: 'First Name',
                              isRequired: true,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: lastNameCtrl,
                              hintText: 'Last Name',
                              isRequired: true,
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: phoneCtrl,
                              hintText: 'Contact Number',
                              isRequired: true,
                              keyboardType: TextInputType.phone,
                              errorText: phoneError,
                              onChanged: (val) {
                                validatePhone(val);
                                setDialogState(() {});
                              },
                            ),
                            const SizedBox(height: 16),
                            AppInputField(
                              controller: relationshipCtrl,
                              hintText: 'Relationship',
                              isRequired: true,
                              readOnly: true,
                              trailingIcon: Icons.keyboard_arrow_down_rounded,
                              onTrailingTap: () {
                                setDialogState(() {
                                  showRelationshipDropdown = !showRelationshipDropdown;
                                });
                              },
                              onTap: () {
                                setDialogState(() {
                                  showRelationshipDropdown = !showRelationshipDropdown;
                                });
                              },
                            ),
                            if (showRelationshipDropdown) ...[
                              const SizedBox(height: 4),
                              Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                color: Colors.white,
                                child: Container(
                                  constraints: const BoxConstraints(maxHeight: 200),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: _relationshipOptions.length,
                                    itemBuilder: (context, idx) {
                                      final rel = _relationshipOptions[idx];
                                      return ListTile(
                                        title: Text(rel, style: const TextStyle(fontSize: 14)),
                                        dense: true,
                                        onTap: () {
                                          setDialogState(() {
                                            relationshipCtrl.text = rel;
                                            showRelationshipDropdown = false;
                                            if (rel != 'Other') {
                                              customRelationshipCtrl.clear();
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                            if (relationshipCtrl.text == 'Other') ...[
                              const SizedBox(height: 16),
                              AppInputField(
                                controller: customRelationshipCtrl,
                                hintText: 'Specify Relationship',
                                isRequired: true,
                                onChanged: (val) => setDialogState(() {}),
                              ),
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isFormValid ? () => Navigator.pop(dialogCtx, true) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          prefill != null ? 'Save Changes' : 'Add Contact',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    phoneCtrl.dispose();
    relationshipCtrl.dispose();
    customRelationshipCtrl.dispose();

    if (result == true) {
      final finalRel = relationshipCtrl.text == 'Other'
          ? customRelationshipCtrl.text.trim()
          : relationshipCtrl.text.trim();

      try {
        final Map<String, dynamic> data = {
          'first_name': firstNameCtrl.text.trim(),
          'last_name': lastNameCtrl.text.trim(),
          'phone_number': phoneCtrl.text.trim(),
          'affiliation': finalRel,
        };

        if (prefill != null) {
          final contactId = prefill['emergency_contact_id'];
          await SupabaseService.client
              .from('emergency_contacts')
              .update(data)
              .eq('emergency_contact_id', contactId);
        } else {
          data['mother_id'] = widget.motherId;
          data['status'] = 'active';
          await SupabaseService.client
              .from('emergency_contacts')
              .insert(data);
        }
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _removeEmergencyContact(Map<String, dynamic> contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Emergency Contact'),
        content: Text(
            'Remove "${contact['first_name']} ${contact['last_name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final contactId = contact['emergency_contact_id'];
        if (contactId != null) {
          await SupabaseService.client
              .from('emergency_contacts')
              .delete()
              .eq('emergency_contact_id', contactId);
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  // ── Modal Sheet Helpers for Editing Overview Sections ───────────────────────

  void _showEditMedicalInfoModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderPrimary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.medical_information, color: AppColors.brandPrimary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Edit Medical Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brandText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildEditableMedicalForm(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: MainButton(
                          label: 'Cancel',
                          isWhiteVariant: true,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MainButton(
                          label: 'Save Changes',
                          onPressed: () async {
                            Navigator.pop(context);
                            await _savePersonalInfo();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEditAddressModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.home_outlined, color: AppColors.brandPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Edit Address',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildEditableAddressForm(),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: MainButton(
                      label: 'Cancel',
                      isWhiteVariant: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MainButton(
                      label: 'Save Changes',
                      onPressed: () async {
                        Navigator.pop(context);
                        await _saveAddress();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showManageMedicalConditionsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.medical_services_outlined, color: AppColors.brandPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Medical Conditions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandText,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _addMedicalCondition();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_currentMedicalConditions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'No medical conditions recorded',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _currentMedicalConditions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = _currentMedicalConditions[index] as Map<String, dynamic>;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: c['status'] == 'active' ? AppColors.warning : AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(
                          c['condition_name'] ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${c['status'] ?? 'active'} • ${_formatDate(c['diagnosis_date'])}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppColors.brandPrimary, size: 20),
                              onPressed: () {
                                Navigator.pop(context);
                                _editMedicalCondition(c);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                              onPressed: () {
                                Navigator.pop(context);
                                _removeMedicalCondition(c);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showManageAllergiesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warning_amber_outlined, color: AppColors.brandPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Allergies',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandText,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _addAllergy();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_currentAllergies.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'No allergies recorded',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _currentAllergies.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final a = _currentAllergies[index] as Map<String, dynamic>;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: a['status'] == 'active' ? AppColors.warning : AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(
                          a['allergen'] ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${a['status'] ?? 'active'} • ${_formatDate(a['diagnosis_date'])}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppColors.brandPrimary, size: 20),
                              onPressed: () {
                                Navigator.pop(context);
                                _editAllergy(a);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                              onPressed: () {
                                Navigator.pop(context);
                                _removeAllergy(a);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showManageEmergencyContactsModal(List emergencyContacts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.contacts_outlined, color: AppColors.brandPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Emergency Contacts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandText,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showEmergencyContactDialog();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (emergencyContacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'No emergency contacts',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: emergencyContacts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = emergencyContacts[index] as Map<String, dynamic>;
                      final name = [c['first_name'], c['middle_name'], c['last_name'], c['extension_name']].whereType<String>().join(' ');
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${c['phone_number'] ?? '-'} ${c['affiliation'] != null ? '• ${c['affiliation']}' : ''}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppColors.brandPrimary, size: 20),
                              onPressed: () {
                                Navigator.pop(context);
                                _showEmergencyContactDialog(prefill: c);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                              onPressed: () {
                                Navigator.pop(context);
                                _removeEmergencyContact(c);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Overview tab static section builders (Pic 2 style) ──────────────────────

  Widget _buildMedicalInfoSection(Map<String, dynamic> profile) {
    final double? heightCm = double.tryParse(_personalControllers['height']?.text ?? '') ??
        (profile['height'] != null ? (profile['height'] as num).toDouble() : null);

    final double? prePregWeight = double.tryParse(_personalControllers['pre_pregnancy_weight']?.text ?? '') ??
        (profile['pre_pregnancy_weight'] != null ? (profile['pre_pregnancy_weight'] as num).toDouble() : null);

    final double? currWeight = double.tryParse(_personalControllers['weight']?.text ?? '') ??
        (profile['weight'] != null ? (profile['weight'] as num).toDouble() : null);

    final double? bmi = computePregnancyBMI(
      prePregnancyWeight: prePregWeight,
      currentWeight: currWeight,
      heightCm: heightCm,
    );

    final String? bmiStatus = bmi != null ? getBMIStatus(bmi) : null;
    final Color bmiColor = bmiStatus != null ? getBMIStatusColor(bmiStatus) : AppColors.textSecondary;

    return ProfileCardSection(
      title: 'Medical Information',
      icon: Icons.medical_information,
      actionButton: !widget.readOnly
          ? IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.brandPrimary),
              onPressed: _showEditMedicalInfoModal,
              tooltip: 'Edit Medical Info',
            )
          : null,
      children: [
        ProfileInfoRow(icon: Icons.cake_outlined, label: 'Birthdate', value: _formatDate(profile['birthdate'])),
        ProfileInfoRow(
          icon: Icons.straighten,
          label: 'Height',
          value: _personalControllers['height']?.text.isNotEmpty == true
              ? '${_personalControllers['height']!.text} cm'
              : 'Not set',
        ),
        ProfileInfoRow(
          icon: Icons.scale_outlined,
          label: 'Weight',
          value: _personalControllers['weight']?.text.isNotEmpty == true
              ? '${_personalControllers['weight']!.text} kg'
              : 'Not set',
        ),
        ProfileInfoRow(
          icon: Icons.monitor_weight_outlined,
          label: 'Pre-Pregnancy Weight',
          value: _personalControllers['pre_pregnancy_weight']?.text.isNotEmpty == true
              ? '${_personalControllers['pre_pregnancy_weight']!.text} kg'
              : 'Unknown',
        ),
        ProfileInfoRow(
          icon: Icons.speed_rounded,
          labelWidget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'BMI',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (bmiStatus != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: bmiColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: bmiColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    bmiStatus,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: bmiColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          value: bmi != null ? bmi.toStringAsFixed(1) : 'Not calculated',
        ),
        ProfileInfoRow(icon: Icons.bloodtype_outlined, label: 'Blood Type', value: profile['blood_type'] ?? 'Not set'),
        ProfileInfoRow(
          icon: Icons.medical_services_outlined,
          label: 'Obstetric Score',
          value: 'G${profile['gravida'] ?? 0} P${profile['para'] ?? 0} A${profile['abortus'] ?? 0}',
        ),
        ProfileInfoRow(
          icon: Icons.person_outline,
          label: 'Registered by',
          value: () {
            String rbName = '—';
            if (profile['registered_by'] != null) {
              final rb = profile['registered_by'] as Map<String, dynamic>;
              final account = rb['account'] as Map<String, dynamic>?;
              if (account != null) {
                rbName = '${account['first_name'] ?? ''} ${account['last_name'] ?? ''}'.trim();
              }
            }
            return rbName;
          }(),
        ),
      ],
    );
  }

  Widget _buildAddressSection(Map<String, dynamic> profile) {
    return ProfileCardSection(
      title: 'Address',
      icon: Icons.home_outlined,
      actionButton: !widget.readOnly
          ? IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.brandPrimary),
              onPressed: _showEditAddressModal,
              tooltip: 'Edit Address',
            )
          : null,
      children: [
        ProfileInfoRow(icon: Icons.numbers_outlined, label: 'House No.', value: profile['house_number'] ?? '-'),
        ProfileInfoRow(icon: Icons.add_road_outlined, label: 'Street', value: profile['street'] ?? '-'),
        ProfileInfoRow(icon: Icons.location_city_outlined, label: 'Barangay', value: profile['barangay'] ?? '-'),
        ProfileInfoRow(icon: Icons.location_on_outlined, label: 'City', value: profile['city_municipality'] ?? '-'),
        ProfileInfoRow(icon: Icons.map_outlined, label: 'Province', value: profile['province'] ?? '-'),
      ],
    );
  }

  Widget _buildMedicalConditionsSection(List medicalConditions) {
    return ProfileCardSection(
      title: 'Medical Conditions',
      icon: Icons.medical_services_outlined,
      actionButton: !widget.readOnly
          ? IconButton(
              icon: const Icon(Icons.edit_note_outlined, size: 20, color: AppColors.brandPrimary),
              onPressed: _showManageMedicalConditionsModal,
              tooltip: 'Manage Medical Conditions',
            )
          : null,
      children: [
        if (medicalConditions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'No medical conditions recorded',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          )
        else
          ...medicalConditions.map<Widget>((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c['status'] == 'active' ? AppColors.warning : AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c['condition_name'] ?? '-',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.inputText),
                          ),
                          Text(
                            '${c['status'] ?? 'active'} • ${_formatDate(c['diagnosis_date'])}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildAllergiesSection(List allergies) {
    return ProfileCardSection(
      title: 'Allergies',
      icon: Icons.warning_amber_outlined,
      actionButton: !widget.readOnly
          ? IconButton(
              icon: const Icon(Icons.edit_note_outlined, size: 20, color: AppColors.brandPrimary),
              onPressed: _showManageAllergiesModal,
              tooltip: 'Manage Allergies',
            )
          : null,
      children: [
        if (allergies.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'No allergies recorded',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          )
        else
          ...allergies.map<Widget>((a) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: a['status'] == 'active' ? AppColors.warning : AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a['allergen'] ?? '-',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.inputText),
                          ),
                          Text(
                            '${a['status'] ?? 'active'} • ${_formatDate(a['diagnosis_date'])}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildEmergencyContactsSection(List emergencyContacts) {
    return ProfileCardSection(
      title: 'Emergency Contacts',
      icon: Icons.contacts_outlined,
      actionButton: !widget.readOnly
          ? IconButton(
              icon: const Icon(Icons.edit_note_outlined, size: 20, color: AppColors.brandPrimary),
              onPressed: () => _showManageEmergencyContactsModal(emergencyContacts),
              tooltip: 'Manage Emergency Contacts',
            )
          : null,
      children: [
        if (emergencyContacts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'No emergency contacts',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          )
        else
          ...emergencyContacts.map<Widget>((c) {
            final name = [c['first_name'], c['middle_name'], c['last_name'], c['extension_name']].whereType<String>().join(' ');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16, color: AppColors.brandPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.inputText),
                        ),
                        Text(
                          '${c['phone_number'] ?? '-'} ${c['affiliation'] != null ? '• ${c['affiliation']}' : ''}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildChildrenSection(List children) {
    return ProfileCardSection(
      title: 'Children',
      icon: Icons.child_care_outlined,
      children: [
        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'No children registered',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          )
        else
          ...children.map<Widget>((c) {
            final childName = [c['first_name'], c['middle_name'], c['last_name']].whereType<String>().join(' ');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.12),
                    child: Text(
                      c['first_name']?.toString().substring(0, 1).toUpperCase() ?? 'C',
                      style: const TextStyle(color: AppColors.brandPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          childName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.inputText),
                        ),
                        if (c['added_at'] != null)
                          Text(
                            'Added: ${_formatDate(c['added_at'])}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEditableMedicalForm() {
    return Column(
      children: [
        AppInputField(
          controller: _personalControllers['height']!,
          hintText: 'Height (cm)',
          readOnly: true,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        AppInputField(
          controller: _personalControllers['weight']!,
          hintText: 'Weight (kg)',
          readOnly: true,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        AppInputField(
          controller: _personalControllers['pre_pregnancy_weight']!,
          hintText: 'Pre-Pregnancy Weight (kg) - leave empty if unknown',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?$')),
          ],
        ),
        const SizedBox(height: 12),
        AppDropdownField<String>(
          hintText: 'Blood Type',
          options: _bloodTypeOptions,
          displayStringForOption: (type) => type,
          value: _editingBloodType.isEmpty ? null : _editingBloodType,
          onSelected: (value) => setState(() => _editingBloodType = value),
        ),
      ],
    );
  }

  Widget _buildEditableAddressForm() {
    return Column(
      children: [
        AppInputField(
          controller: _addressControllers['house_number']!,
          hintText: 'House Number',
        ),
        const SizedBox(height: 12),
        AppInputField(
          controller: _addressControllers['street']!,
          hintText: 'Street',
        ),
        const SizedBox(height: 12),
        AppInputField(
          controller: _addressControllers['barangay']!,
          hintText: 'Barangay',
        ),
        const SizedBox(height: 12),
        AppInputField(
          controller: _addressControllers['city']!,
          hintText: 'City/Municipality',
        ),
        const SizedBox(height: 12),
        AppInputField(
          controller: _addressControllers['province']!,
          hintText: 'Province',
        ),
      ],
    );
  }

  Widget _buildReadOnlySection(
      String title, IconData icon, List<Widget> children) {
    return ProfileSection(
      title: title,
      icon: icon,
      children: children,
    );
  }

  // ── Prominent Pregnancy Stage Card (Task 5.1) ─────────────────────────
  Widget _buildPregnancyStageCard(Map<String, dynamic> pregnancy) {
    final lmp = DateTime.tryParse(pregnancy['last_menstrual_period'] ?? '');
    final edd = DateTime.tryParse(pregnancy['expected_date_of_delivery'] ?? '');
    final now = DateTime.now();

    final gestWeeks =
        lmp != null ? (now.difference(lmp).inDays / 7).floor() : null;
    final weeksToGo = gestWeeks != null ? 40 - gestWeeks : null;

    String trimester = '--';
    Color trimesterColor = AppColors.brandPrimary;
    if (gestWeeks != null) {
      if (gestWeeks <= 12) {
        trimester = '1st Trimester';
        trimesterColor = AppColors.success;
      } else if (gestWeeks <= 27) {
        trimester = '2nd Trimester';
        trimesterColor = AppColors.warning;
      } else {
        trimester = '3rd Trimester';
        trimesterColor = AppColors.brandPrimary;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            trimesterColor.withValues(alpha: 0.15),
            trimesterColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: trimesterColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Trimester badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: trimesterColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              trimester,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Weeks pregnant
          Text(
            gestWeeks != null ? 'Week $gestWeeks of 40' : 'Weeks unknown',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: trimesterColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          // EDD countdown
          if (weeksToGo != null && weeksToGo > 0)
            Text(
              '$weeksToGo weeks left until expected delivery',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),

          // Progress bar
          if (gestWeeks != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (gestWeeks / 40).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.6),
                valueColor: AlwaysStoppedAnimation<Color>(trimesterColor),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Week 1',
                    style: TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
                Text('Week 40',
                    style: TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OVERVIEW TAB (Task 5.2 - Focus on what mothers need)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildOverviewTab(
    Map<String, dynamic> profile,
    List medicalConditions,
    List allergies,
    List emergencyContacts,
    List children,
    Map<String, dynamic>? currentPregnancy,
  ) {
    _currentMedicalConditions = medicalConditions;
    _currentAllergies = allergies;

    // FIX #1: initialise controllers only once per profile load
    if (!_controllersInitialized) {
      _initializePersonalControllers(profile, currentPregnancy);
      _initializeAddressControllers(profile);
      _controllersInitialized = true;
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.brandPrimary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            ProfileHeaderCard(
              fullName: profile['full_name'] ?? '',
              email: profile['email_address'],
              phone: profile['phone_number'],
              profilePictureUrl: _profilePictureUrl,
              patientNumber: _patientNumber,
            ),
            const SizedBox(height: 16),

            // Quick stats
            ProfileQuickStats(
              age: profile['birthdate'] != null
                  ? DateTime.now()
                          .difference(DateTime.parse(profile['birthdate']))
                          .inDays ~/
                      365
                  : 0,
              childrenCount: profile['children_count'] ?? 0,
              pregnanciesCount: profile['pregnancies_count'] ?? 0,
            ),
            const SizedBox(height: 16),

            // ProfileRiskCard
            if (currentPregnancy != null)
              ProfileRiskCard(profile: profile, pregnancy: currentPregnancy),
            if (currentPregnancy != null) const SizedBox(height: 16),

            // Overview Section Cards (Pic 2 style)
            _buildMedicalInfoSection(profile),
            const SizedBox(height: 14),

            _buildAddressSection(profile),
            const SizedBox(height: 14),

            _buildMedicalConditionsSection(medicalConditions),
            const SizedBox(height: 14),

            _buildAllergiesSection(allergies),
            const SizedBox(height: 14),

            _buildEmergencyContactsSection(emergencyContacts),
            const SizedBox(height: 14),

            _buildChildrenSection(children),
          ],
        ),
      ),
    );
  }


  Widget _buildInfoRow(String label, String value) {
    return ProfileInfoRow(label: label, value: value);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CURRENT PREGNANCY TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildPregnancyDetailsCard({
    required Map<String, dynamic> pregnancy,
    required int? gestWeeks,
    required int? daysToEdd,
    required int checkupCount,
  }) {
    final lmp = DateTime.tryParse(pregnancy['last_menstrual_period'] ?? '');
    final now = DateTime.now();
    final ultrasoundsList = (pregnancy['ultrasounds'] as List?) ?? [];
    final hasUltrasounds = ultrasoundsList.isNotEmpty;
    final rawFc = pregnancy['fetal_count']?.toString() ?? '';
    String fetalLabel = 'Unknown';
    String fetalSubtext = 'Not specified';
    if (!hasUltrasounds || rawFc.toLowerCase() == 'unknown' || rawFc.isEmpty) {
      fetalLabel = 'Unknown';
      fetalSubtext = 'Not specified';
    } else {
      final fc = int.tryParse(rawFc) ?? 1;
      if (fc == 1) {
        fetalLabel = 'Singleton';
        fetalSubtext = 'Single baby';
      } else if (fc == 2) {
        fetalLabel = 'Twins';
        fetalSubtext = 'Multiple (2 babies)';
      } else {
        fetalLabel = '$fc Multiple';
        fetalSubtext = 'Multiple babies';
      }
    }

    final lmpStr = _formatDate(pregnancy['last_menstrual_period']);
    final eddStr = _formatDate(pregnancy['expected_date_of_delivery']);
    final days = lmp != null ? (now.difference(lmp).inDays % 7) : 0;
    final aogStr = gestWeeks != null
        ? '$gestWeeks Week${gestWeeks == 1 ? "" : "s"}${days > 0 ? " $days Day${days == 1 ? "" : "s"}" : ""}'
        : 'Unknown';
    final weeksToGo = gestWeeks != null ? (40 - gestWeeks) : null;
    final aogSubtext = weeksToGo != null && weeksToGo > 0
        ? '$weeksToGo wks remaining'
        : 'On track';

    return ProfileCardSection(
      title: 'PREGNANCY INFORMATION',
      icon: Icons.info_outline_rounded,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDetailsItem(
                icon: Icons.calendar_month_rounded,
                color: AppColors.brandPrimary,
                label: 'LMP (Last Menstrual)',
                value: lmpStr,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDetailsItem(
                icon: Icons.event_available_rounded,
                color: Colors.purple.shade600,
                label: 'EDD (Expected Delivery)',
                value: eddStr,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildDetailsItem(
                icon: Icons.hourglass_bottom_rounded,
                color: Colors.blue.shade600,
                label: 'AOG (Age of Gestation)',
                value: aogStr,
                subtext: aogSubtext,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDetailsItem(
                icon: Icons.child_care_rounded,
                color: Colors.teal.shade600,
                label: 'Fetus Count',
                value: fetalLabel,
                subtext: fetalSubtext,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailsItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    String? subtext,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: color.withValues(alpha: 0.8),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtext != null && subtext.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtext,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPregnancyTab(
      Map<String, dynamic> profile, Map<String, dynamic>? pregnancy) {
    if (pregnancy == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: AppColors.bgSecondary, shape: BoxShape.circle),
                child: const Icon(Icons.pregnant_woman,
                    size: 64, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              const Headline(text: 'No Ongoing Pregnancy'),
              const SizedBox(height: 8),
              const Text('Start a new pregnancy to begin tracking',
                  style: TextStyle(color: AppColors.textSecondary)),
              if (!widget.readOnly) ...[
                const SizedBox(height: 24),
                MainButton(
                    label: 'Start New Pregnancy',
                    onPressed: () => _startNewPregnancyDialog(profile['past_pregnancies'] as List?)),
              ],
            ],
          ),
        ),
      );
    }

    final checkups = (pregnancy['checkups'] as List?) ?? [];
    final ultrasounds = (pregnancy['ultrasounds'] as List?) ?? [];
    final labTests = (pregnancy['lab_tests'] as List?) ?? [];
    final vitals = (pregnancy['maternal_vitals'] as List?) ?? [];

    final sortedCheckups = List<Map<String, dynamic>>.from(checkups);
    sortedCheckups.sort((a, b) {
      final dateA = DateTime.tryParse(a['checkup_datetime'] ?? '');
      final dateB = DateTime.tryParse(b['checkup_datetime'] ?? '');
      if (dateA == null || dateB == null) return 0;
      return _checkupSort == 'desc'
          ? dateB.compareTo(dateA)
          : dateA.compareTo(dateB);
    });

    final lmp = DateTime.tryParse(pregnancy['last_menstrual_period'] ?? '');
    final edd = DateTime.tryParse(pregnancy['expected_date_of_delivery'] ?? '');
    final now = DateTime.now();
    final gestWeeks =
        lmp != null ? (now.difference(lmp).inDays / 7).floor() : null;
    final daysToEdd = edd?.difference(now).inDays;

    // ── Build checkupList for WeightGainEngine ────────────────────────────
    final rawList = <Map<String, dynamic>>[];
    for (final c in checkups) {
      final w = c['checkup_weight'];
      if (w != null) {
        final dtStr = c['checkup_datetime']?.toString() ?? c['encounter']?['encounter_datetime']?.toString();
        final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
        double aogVal = c['age_of_gestation'] != null ? (c['age_of_gestation'] as num).toDouble() : 0.0;
        if (dt != null && lmp != null) {
          aogVal = (dt.difference(lmp).inDays / 7.0).clamp(0.0, 42.0);
        }
        rawList.add({
          'prenatal_checkup_id': c['encounter_id'] ?? -1,
          'checkup_datetime': dtStr,
          'age_of_gestation': aogVal,
          'checkup_weight': (w as num).toDouble(),
          'is_checkup': true,
        });
      }
    }
    for (final v in vitals) {
      final w = v['weight_kg'];
      if (w != null) {
        final dtStr = v['recorded_at']?.toString();
        final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
        double aogVal = v['age_of_gestation'] != null ? (v['age_of_gestation'] as num).toDouble() : 0.0;
        if (dt != null && lmp != null) {
          aogVal = (dt.difference(lmp).inDays / 7.0).clamp(0.0, 42.0);
        }
        rawList.add({
          'prenatal_checkup_id': v['vital_id'] ?? -1,
          'checkup_datetime': dtStr,
          'age_of_gestation': aogVal,
          'checkup_weight': (w as num).toDouble(),
          'is_checkup': false,
        });
      }
    }

    // Sort chronological ascending
    rawList.sort((a, b) {
      final da = DateTime.tryParse(a['checkup_datetime']?.toString() ?? '');
      final db = DateTime.tryParse(b['checkup_datetime']?.toString() ?? '');
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

    // Deduplicate by AOG/date (prefer official prenatal checkup over self-reported vitals)
    final checkupList = <Map<String, dynamic>>[];
    for (final item in rawList) {
      if (checkupList.isEmpty) {
        checkupList.add(item);
      } else {
        final last = checkupList.last;
        final double diff = (item['age_of_gestation'] - last['age_of_gestation']).abs();
        if (diff < 0.2) {
          if (item['is_checkup'] == true && last['is_checkup'] == false) {
            checkupList[checkupList.length - 1] = item;
          }
        } else {
          checkupList.add(item);
        }
      }
    }

    double? prePregnancyWeight = pregnancy['pre_pregnancy_weight'] != null
        ? (pregnancy['pre_pregnancy_weight'] as num).toDouble()
        : null;
    final height = profile['height'] != null
        ? (profile['height'] as num).toDouble()
        : null;

    // Dynamic pre-pregnancy weight backtracking if missing in DB but checkups/vitals exist
    if (prePregnancyWeight == null && checkupList.isNotEmpty && height != null && height > 0) {
      final earliest = checkupList.first;
      final earliestWeight = earliest['checkup_weight'];
      final earliestAog = earliest['age_of_gestation'];
      final fetalCount = int.tryParse(pregnancy['fetal_count']?.toString() ?? '') ?? 1;
      final estResult = WeightGainEngine.estimatePrePregnancyBMI(
        currentWeightKg: earliestWeight,
        heightCm: height,
        aogWeeks: earliestAog,
        fetalCount: fetalCount,
      );
      prePregnancyWeight = (estResult['estimatedWeight'] as num?)?.toDouble();
    }

    WeightGainResult? weightGainResult;
    final fetalCount = int.tryParse(pregnancy['fetal_count']?.toString() ?? '') ?? 1;

    if (checkupList.isEmpty) {
      if (prePregnancyWeight != null) {
        double effectiveAog = 0;
        if (pregnancy['last_menstrual_period'] != null) {
          final lmpVal = DateTime.tryParse(pregnancy['last_menstrual_period']);
          if (lmpVal != null) {
            effectiveAog = DateTime.now().difference(lmpVal).inDays / 7.0;
          }
        }
        weightGainResult = WeightGainEngine.evaluate(
          currentWeight: prePregnancyWeight,
          aogWeeks: effectiveAog,
          allCheckups: [],
          prePregnancyWeight: prePregnancyWeight,
          heightCm: height,
          fetalCount: fetalCount,
        );
      }
    } else {
      final latest = checkupList.last;
      final currentWeight = (latest['checkup_weight'] as num?)?.toDouble();
      final aogWeeks = (latest['age_of_gestation'] as num?)?.toDouble();

      double effectiveAog = aogWeeks ?? 0;
      if (effectiveAog == 0 && pregnancy['last_menstrual_period'] != null) {
        final lmpVal = DateTime.tryParse(pregnancy['last_menstrual_period']);
        if (lmpVal != null) {
          effectiveAog = DateTime.now().difference(lmpVal).inDays / 7.0;
        }
      }

      if (currentWeight != null && currentWeight > 0) {
        weightGainResult = WeightGainEngine.evaluate(
          currentWeight: currentWeight,
          aogWeeks: effectiveAog,
          allCheckups: checkupList,
          prePregnancyWeight: prePregnancyWeight,
          heightCm: height,
          fetalCount: fetalCount,
        );
      }
    }

    Map<String, dynamic>? latestGrowthData;

    if (checkupList.isNotEmpty) {
      final latest = checkupList.last;
      final weight = (latest['checkup_weight'] as num?)?.toDouble();
      final aog = latest['age_of_gestation'];

      final bmiWeight = prePregnancyWeight ?? weight;
      double? bmi;
      String? bmiStatus;
      String bmiSource = 'BMI Unavailable';

      if (bmiWeight != null && height != null && height > 0) {
        final heightM = height / 100;
        bmi = bmiWeight / (heightM * heightM);
        bmiStatus = getBMIStatus(bmi);
        bmiSource = prePregnancyWeight != null
            ? 'Pre-Pregnancy BMI'
            : 'Estimated BMI (current weight)';
      }

      latestGrowthData = {
        'date': latest['checkup_datetime'],
        'aog': aog?.toString() ?? 'N/A',
        'weight': weight ?? 0,
        'height': height ?? 0,
        'bmi': bmi,
        'bmi_status': bmiStatus,
        'bmi_source': bmiSource,
        'pre_pregnancy_weight': prePregnancyWeight,
      };
    } else if (prePregnancyWeight != null) {
      double? aogWeeks;
      if (pregnancy['last_menstrual_period'] != null) {
        final lmpVal = DateTime.tryParse(pregnancy['last_menstrual_period']);
        if (lmpVal != null) {
          aogWeeks = DateTime.now().difference(lmpVal).inDays / 7.0;
        }
      }

      double? bmi;
      String? bmiStatus;
      if (height != null && height > 0) {
        final heightM = height / 100;
        bmi = prePregnancyWeight / (heightM * heightM);
        bmiStatus = getBMIStatus(bmi);
      }

      latestGrowthData = {
        'date': DateTime.now().toIso8601String(),
        'aog': aogWeeks != null ? aogWeeks.toStringAsFixed(1) : 'N/A',
        'weight': prePregnancyWeight,
        'height': height ?? 0,
        'bmi': bmi,
        'bmi_status': bmiStatus ?? 'Normal',
        'bmi_source': 'Pre-Pregnancy BMI',
        'pre_pregnancy_weight': prePregnancyWeight,
      };
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.brandPrimary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPregnancyStageCard(pregnancy),
            const SizedBox(height: 16),

            _buildPregnancyDetailsCard(
              pregnancy: pregnancy,
              gestWeeks: gestWeeks,
              daysToEdd: daysToEdd,
              checkupCount: sortedCheckups.length,
            ),
            const SizedBox(height: 16),

            ProfileRiskCard(profile: profile, pregnancy: pregnancy),
            const SizedBox(height: 16),

            ProfileGrowthCard(
              isLoading: false,
              growthData: latestGrowthData,
            ),
            const SizedBox(height: 16),

            // ── Weight Gain Dashboard ──────────────────────────────────
            if (weightGainResult != null) ...[
              _buildWeightGainDashboard(
                weightGainResult,
                checkupList,
                fetalCount,
                isEstimated: pregnancy['pre_pregnancy_weight'] == null,
              ),
              const SizedBox(height: 12),
            ],
            // ── Prenatal Checkups ──
            _buildPreviewRecordSection(
              title: 'PRENATAL CHECKUPS',
              icon: Icons.medical_services_outlined,
              totalCount: sortedCheckups.length,
              previewWidgets: sortedCheckups.take(3).map((c) =>
                  _buildCheckupCard(
                      c,
                      pregnancy['pregnancy_id'] ?? -1,
                      int.tryParse(
                              pregnancy['fetal_count']?.toString() ?? '') ??
                          1)).toList(),
              allWidgets: sortedCheckups.map((c) =>
                  _buildCheckupCard(
                      c,
                      pregnancy['pregnancy_id'] ?? -1,
                      int.tryParse(
                              pregnancy['fetal_count']?.toString() ?? '') ??
                          1)).toList(),
              emptyText: 'No checkups recorded yet',
              modalTitle: 'Prenatal Checkups History',
              sortValue: _checkupSort,
              onSortChanged: (v) => setState(() => _checkupSort = v ?? 'desc'),
            ),
            const SizedBox(height: 14),

            // ── Ultrasounds ──
            () {
              final sortedUltrasounds = _sortByDate(ultrasounds, 'ultrasound_date', _ultrasoundSort);
              return _buildPreviewRecordSection(
                title: 'ULTRASOUNDS',
                icon: Icons.photo_outlined,
                totalCount: ultrasounds.length,
                previewWidgets: sortedUltrasounds.take(3).map((u) => _buildUltrasoundCard(u)).toList(),
                allWidgets: sortedUltrasounds.map((u) => _buildUltrasoundCard(u)).toList(),
                emptyText: 'No ultrasounds recorded yet',
                modalTitle: 'Ultrasound Records',
                sortValue: _ultrasoundSort,
                onSortChanged: (v) => setState(() => _ultrasoundSort = v ?? 'desc'),
              );
            }(),
            const SizedBox(height: 14),

            // ── Lab Tests ──
            () {
              final sortedLabTests = _sortByDate(labTests, 'lab_test_date', _labSort);
              return _buildPreviewRecordSection(
                title: 'LAB TESTS',
                icon: Icons.science_outlined,
                totalCount: labTests.length,
                previewWidgets: sortedLabTests.take(3).map((l) => _buildLabTestCard(l)).toList(),
                allWidgets: sortedLabTests.map((l) => _buildLabTestCard(l)).toList(),
                emptyText: 'No lab tests recorded yet',
                modalTitle: 'Lab Test Results',
                sortValue: _labSort,
                onSortChanged: (v) => setState(() => _labSort = v ?? 'desc'),
              );
            }(),
            const SizedBox(height: 14),

            // ── Self-logged Vitals ──
            () {
              final sortedVitals = _sortByDate(vitals, 'recorded_at', _vitalSort);
              return _buildPreviewRecordSection(
                title: 'SELF-LOGGED VITALS',
                icon: Icons.monitor_weight_outlined,
                totalCount: vitals.length,
                previewWidgets: sortedVitals.take(3).map((v) => _buildMaternalVitalCard(v)).toList(),
                allWidgets: sortedVitals.map((v) => _buildMaternalVitalCard(v)).toList(),
                emptyText: 'No vitals logged yet',
                modalTitle: 'Self-logged Vitals History',
                sortValue: _vitalSort,
                onSortChanged: (v) => setState(() => _vitalSort = v ?? 'desc'),
              );
            }(),
            if (!widget.readOnly) ...[
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                color: AppColors.error.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: InkWell(
                  onTap: () => _showConcludePregnancyDialog(pregnancy),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.flag_outlined,
                          color: AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Conclude Current Pregnancy',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  /// Shared sort-dropdown row used in each record section.
  Widget _buildSortRow(String currentValue, ValueChanged<String?> onChanged) {
    return RecordSortRow(currentValue: currentValue, onChanged: onChanged);
  }

  /// "Load More" button shown when a list has more items than currently displayed.
  Widget _buildLoadMoreButton({
    required int current,
    required int total,
    required VoidCallback onPressed,
  }) {
    return RecordLoadMoreButton(
      current: current,
      total: total,
      pageSize: _pageSize,
      onPressed: onPressed,
    );
  }

  Widget _buildPreviewRecordSection({
    required String title,
    required IconData icon,
    required int totalCount,
    required List<Widget> previewWidgets,
    required List<Widget> allWidgets,
    required String emptyText,
    required String modalTitle,
    required String sortValue,
    required ValueChanged<String?> onSortChanged,
  }) {
    final hasRecords = allWidgets.isNotEmpty;

    return ProfileCardSection(
      title: '$title ($totalCount)',
      icon: icon,
      actionButton: hasRecords
          ? InkWell(
              onTap: () => _showAllRecordsModal(
                context: context,
                title: modalTitle,
                icon: icon,
                recordWidgets: allWidgets,
                currentSort: sortValue,
                onSortChanged: onSortChanged,
              ),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All ($totalCount)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppColors.brandPrimary,
                    ),
                  ],
                ),
              ),
            )
          : null,
      children: [
        if (!hasRecords)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  emptyText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else ...[
          for (int i = 0; i < previewWidgets.length; i++) ...[
            previewWidgets[i],
            if (i < previewWidgets.length - 1) const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  void _showAllRecordsModal({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> recordWidgets,
    required String currentSort,
    required ValueChanged<String?> onSortChanged,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomPadding = MediaQuery.of(sheetContext).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.78,
              minChildSize: 0.4,
              maxChildSize: 0.94,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.borderPrimary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.brandPrimary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: AppColors.brandPrimary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${recordWidgets.length} record(s) total',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            _buildSortRow(currentSort, (v) {
                              onSortChanged(v);
                              setModalState(() {});
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: AppColors.borderPrimary),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding + 24),
                          itemCount: recordWidgets.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, index) => recordWidgets[index],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HISTORY TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildOutcomeBadge(String outcomeStr) {
    final lower = outcomeStr.toLowerCase();
    final isLiveBirth = lower.contains('live birth') || lower.contains('live_birth');

    final bgColor = isLiveBirth
        ? const Color(0xFFE6F4EA)
        : const Color(0xFFF1F3F4);

    final textColor = isLiveBirth
        ? const Color(0xFF137333)
        : const Color(0xFF5F6368);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.2), width: 1),
      ),
      child: Text(
        outcomeStr,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildHistoryTab(List pastPregnancies) {
    if (pastPregnancies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.bgSecondary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.history_edu_rounded,
                    size: 56, color: AppColors.brandPrimary),
              ),
              const SizedBox(height: 20),
              const Headline(text: 'No Past Pregnancies'),
              const SizedBox(height: 8),
              const Text('Past pregnancy records will appear here',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.brandPrimary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: pastPregnancies.length,
        itemBuilder: (context, index) {
          final p = Map<String, dynamic>.from(pastPregnancies[index] as Map);
          final checkups = (p['checkups'] as List?) ?? [];
          final ultrasounds = (p['ultrasounds'] as List?) ?? [];
          final labTests = (p['lab_tests'] as List?) ?? [];
          final vitals = (p['maternal_vitals'] as List?) ?? [];
          final deliveries = (p['delivery'] as List?)
                  ?.map((item) => Map<String, dynamic>.from(item as Map))
                  .toList() ??
              [];
          final outcomesList = (p['outcomes'] as List?)
                  ?.map((item) => Map<String, dynamic>.from(item as Map))
                  .toList() ??
              [];

          final normalizedOutcomes = outcomesList.isNotEmpty
              ? outcomesList
              : (p['outcome'] != null || p['outcome_date'] != null)
                  ? [
                      {
                        'fetus_number': 1,
                        'outcome': p['outcome'],
                        'outcome_date': p['outcome_date'],
                      }
                    ]
                  : <Map<String, dynamic>>[];

          final String primaryOutcomeStr = normalizedOutcomes.isNotEmpty
              ? normalizedOutcomes
                  .map((o) => _formatOutcome(o['outcome'] as String?))
                  .join(', ')
              : 'Past Pregnancy';

          final String primaryOutcomeDate = normalizedOutcomes.isNotEmpty
              ? _formatDate(normalizedOutcomes.first['outcome_date'] as String?)
              : (p['ended_at'] != null ? _formatDate(p['ended_at']) : '-');

          final String titleStr = 'PAST PREGNANCY #${pastPregnancies.length - index}';

          final pregnancyId = int.tryParse(p['pregnancy_id']?.toString() ?? '') ?? -1;

          final sortedHistCheckups = List<Map<String, dynamic>>.from(
              checkups.map((c) => Map<String, dynamic>.from(c as Map)))
            ..sort((a, b) {
              final da = _parseDateForSort(a['checkup_datetime']);
              final db = _parseDateForSort(b['checkup_datetime']);
              if (da == null || db == null) return 0;
              return db.compareTo(da);
            });

          final sortedHistUltrasounds = _sortByDate(
              ultrasounds.map((u) => Map<String, dynamic>.from(u as Map)).toList(),
              'ultrasound_date',
              'desc');

          final sortedHistLabTests = _sortByDate(
              labTests.map((l) => Map<String, dynamic>.from(l as Map)).toList(),
              'lab_test_date',
              'desc');

          final sortedHistVitals = _sortByDate(
              vitals.map((v) => Map<String, dynamic>.from(v as Map)).toList(),
              'recorded_at',
              'desc');

          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            child: ProfileCardSection(
              title: titleStr,
              icon: Icons.history_edu_rounded,
              actionButton: _buildOutcomeBadge(primaryOutcomeStr),
              children: [
                // ── Medical Summary Box ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.brandPrimary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Gestational Age at End',
                          p['gestational_age_at_end'] != null ? '${p['gestational_age_at_end']} weeks' : '-'),
                      const SizedBox(height: 6),
                      _buildInfoRow('Outcome Date', primaryOutcomeDate),
                      const SizedBox(height: 6),
                      for (int i = 0; i < normalizedOutcomes.length; i++) ...[
                        if (normalizedOutcomes.length > 1) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Fetus ${normalizedOutcomes[i]['fetus_number'] ?? (i + 1)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brandPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        _buildInfoRow('Result', _formatOutcome(normalizedOutcomes[i]['outcome'] as String?)),
                        ...() {
                          final deliveryList = deliveries
                              .where((d) => d['fetus_number'] == normalizedOutcomes[i]['fetus_number'])
                              .toList();
                          if (deliveryList.isNotEmpty) {
                            final delivery = deliveryList.first;
                            final place = delivery['place_of_delivery']?.toString() ?? '';
                            final method = delivery['delivery_method']?.toString() ?? '';
                            return [
                              if (place.isNotEmpty && place != '-') _buildInfoRow('Delivery Facility', place),
                              if (method.isNotEmpty && method != '-') _buildInfoRow('Delivery Method', method),
                            ];
                          }
                          return <Widget>[];
                        }(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Sub-records Preview Sections ──
                _buildPreviewRecordSection(
                  title: 'PRENATAL CHECKUPS',
                  icon: Icons.medical_services_outlined,
                  totalCount: checkups.length,
                  previewWidgets: sortedHistCheckups.take(3).map((c) =>
                      _buildCheckupCard(
                          c,
                          pregnancyId,
                          int.tryParse(p['fetal_count']?.toString() ?? '') ?? 1)).toList(),
                  allWidgets: sortedHistCheckups.map((c) =>
                      _buildCheckupCard(
                          c,
                          pregnancyId,
                          int.tryParse(p['fetal_count']?.toString() ?? '') ?? 1)).toList(),
                  emptyText: 'No checkup records for this pregnancy',
                  modalTitle: 'Checkups ($titleStr)',
                  sortValue: 'desc',
                  onSortChanged: (_) {},
                ),
                const SizedBox(height: 12),

                _buildPreviewRecordSection(
                  title: 'ULTRASOUNDS',
                  icon: Icons.photo_outlined,
                  totalCount: ultrasounds.length,
                  previewWidgets: sortedHistUltrasounds.take(3).map((u) => _buildUltrasoundCard(u)).toList(),
                  allWidgets: sortedHistUltrasounds.map((u) => _buildUltrasoundCard(u)).toList(),
                  emptyText: 'No ultrasound records for this pregnancy',
                  modalTitle: 'Ultrasounds ($titleStr)',
                  sortValue: 'desc',
                  onSortChanged: (_) {},
                ),
                const SizedBox(height: 12),

                _buildPreviewRecordSection(
                  title: 'LAB TESTS',
                  icon: Icons.science_outlined,
                  totalCount: labTests.length,
                  previewWidgets: sortedHistLabTests.take(3).map((l) => _buildLabTestCard(l)).toList(),
                  allWidgets: sortedHistLabTests.map((l) => _buildLabTestCard(l)).toList(),
                  emptyText: 'No lab test records for this pregnancy',
                  modalTitle: 'Lab Tests ($titleStr)',
                  sortValue: 'desc',
                  onSortChanged: (_) {},
                ),
                const SizedBox(height: 12),

                _buildPreviewRecordSection(
                  title: 'SELF-LOGGED VITALS',
                  icon: Icons.monitor_weight_outlined,
                  totalCount: vitals.length,
                  previewWidgets: sortedHistVitals.take(3).map((v) => _buildMaternalVitalCard(v)).toList(),
                  allWidgets: sortedHistVitals.map((v) => _buildMaternalVitalCard(v)).toList(),
                  emptyText: 'No vitals logged for this pregnancy',
                  modalTitle: 'Vitals ($titleStr)',
                  sortValue: 'desc',
                  onSortChanged: (_) {},
                ),
              ],
            ),
          );
        },
      ),
    );
  }


  // ══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                    color: AppColors.bgSecondary, shape: BoxShape.circle),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 36,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.favorite,
                      color: AppColors.brandPrimary,
                      size: 30),
                ),
              ),
              const Text(
                'PROFILE',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandText,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    showMotherQrCodeDialog(context, widget.motherId),
                icon: const Icon(Icons.qr_code_rounded,
                    size: 24, color: AppColors.textPrimary),
                tooltip: 'Show QR Code',
              ),
              const SizedBox(width: 14),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded,
                    size: 24, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () => _showProfileMenu(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brandPrimary,
                    image: _profilePictureUrl != null &&
                            _profilePictureUrl!.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(_profilePictureUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _profilePictureUrl == null ||
                          _profilePictureUrl!.isEmpty
                      ? const Icon(Icons.person, size: 20, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          GestureDetector(
              onTap: () => entry.remove(),
              child: Container(color: Colors.black.withValues(alpha: 0.35))),
          Positioned(
            top: 90,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 200,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8))
                    ]),
                child: Column(
                  children: [
                    _MenuItem(
                        icon: Icons.person_outline,
                        label: 'View Profile',
                        onTap: () => entry.remove()),
                    _MenuItem(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        onTap: () {
                          entry.remove();
                          Navigator.pushNamed(context, '/settings');
                        }),
                    _MenuItem(
                        icon: Icons.help_outline,
                        label: 'Help',
                        onTap: () {
                          entry.remove();
                          Navigator.pushNamed(context, '/help');
                        }),
                    const Divider(height: 8, color: AppColors.borderPrimary),
                    _MenuItem(
                        icon: Icons.logout_rounded,
                        label: 'Log out',
                        isDanger: true,
                        onTap: () {
                          entry.remove();
                          _confirmLogout(context);
                        }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _logout();
              },
              child: const Text('Log out',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  Widget? _buildFAB(BuildContext context, Map<String, dynamic>? pregnancy, Map<String, dynamic> profile) {
    if (widget.readOnly || pregnancy == null || _tabController.index != 1) {
      return null;
    }
    return FloatingActionButton(
      onPressed: () => _showQuickActionsMenu(context, pregnancy, profile),
      backgroundColor: AppColors.brandPrimaryOf(context),
      shape: const CircleBorder(),
      child: const Icon(Icons.add, color: Colors.white, size: 28),
    );
  }

  void _showQuickActionsMenu(BuildContext context, Map<String, dynamic> pregnancy, Map<String, dynamic> profile) {
    double? latestWeight;
    final checkupsList = (pregnancy['checkups'] as List?) ?? [];
    final vitalsList = (pregnancy['maternal_vitals'] as List?) ?? [];
    final allWeightReadings = <Map<String, dynamic>>[];
    for (final c in checkupsList) {
      final w = c['checkup_weight'];
      if (w != null) {
        allWeightReadings.add({
          'weight': (w as num).toDouble(),
          'date': DateTime.tryParse(c['checkup_datetime']?.toString() ?? ''),
          'is_checkup': true,
        });
      }
    }
    for (final v in vitalsList) {
      final w = v['weight_kg'];
      if (w != null) {
        allWeightReadings.add({
          'weight': (w as num).toDouble(),
          'date': DateTime.tryParse(v['recorded_at']?.toString() ?? ''),
          'is_checkup': false,
        });
      }
    }

    allWeightReadings.sort((a, b) {
      final da = a['date'] as DateTime?;
      final db = b['date'] as DateTime?;
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

    final deduplicatedReadings = <Map<String, dynamic>>[];
    for (final item in allWeightReadings) {
      if (deduplicatedReadings.isEmpty) {
        deduplicatedReadings.add(item);
      } else {
        final last = deduplicatedReadings.last;
        final da = item['date'] as DateTime?;
        final db = last['date'] as DateTime?;
        if (da != null && db != null) {
          final diffHours = da.difference(db).inHours.abs();
          if (diffHours < 33) {
            if (item['is_checkup'] == true && last['is_checkup'] == false) {
              deduplicatedReadings[deduplicatedReadings.length - 1] = item;
            }
          } else {
            deduplicatedReadings.add(item);
          }
        } else {
          deduplicatedReadings.add(item);
        }
      }
    }

    if (deduplicatedReadings.isNotEmpty) {
      latestWeight = deduplicatedReadings.last['weight'] as double?;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Assessment & Record',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimaryOf(ctx),
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select the type of record to add to this pregnancy',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryOf(ctx),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildQuickActionCard(
                  context: ctx,
                  icon: Icons.calendar_today_outlined,
                  title: 'Prenatal Check Up',
                  subtitle: 'Record a regular checkup session',
                  baseColor: AppColors.brandPrimaryOf(ctx),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final pregnancyId = pregnancy['pregnancy_id'];
                    if (pregnancyId == null) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddPrenatalCheckupScreen(
                          motherId: widget.motherId,
                          pregnancyId: pregnancyId as int,
                          lmp: DateTime.tryParse(
                              pregnancy['last_menstrual_period'] ?? ''),
                          motherWeight: latestWeight ?? _toDouble(profile['weight']),
                        ),
                      ),
                    );
                    _refresh();
                  },
                ),
                _buildQuickActionCard(
                  context: ctx,
                  icon: Icons.science_outlined,
                  title: 'Lab Test',
                  subtitle: 'Scan or analyze CBC lab results',
                  baseColor: const Color(0xFFFFB300), // warm amber
                  onTap: () {
                    Navigator.pop(ctx);
                    _goToLabTestAnalyzer(pregnancy);
                  },
                ),
                _buildQuickActionCard(
                  context: ctx,
                  icon: Icons.monitor_heart_outlined,
                  title: 'Ultrasound',
                  subtitle: 'Scan or analyze fetal ultrasound findings',
                  baseColor: AppColors.brandAccent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _goToUltrasoundAnalyzer(pregnancy);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color baseColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: baseColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: baseColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimaryOf(context),
            body: Column(
              children: [
                _buildHeader(),
                const Expanded(
                    child: Center(
                        child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.brandPrimary)))),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimaryOf(context),
            body: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: AppColors.error),
                          const SizedBox(height: 16),
                          const Headline(text: 'Error Loading Profile'),
                          const SizedBox(height: 8),
                          Text(snapshot.error.toString(),
                              style: const TextStyle(
                                  color: AppColors.textSecondary),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 24),
                          MainButton(label: 'Retry', onPressed: _refresh),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimaryOf(context),
            body: Column(
              children: [
                _buildHeader(),
                const Expanded(
                    child: Center(child: Text('No profile data found'))),
              ],
            ),
          );
        }

        final profile = snapshot.data!;
        final currentPregnancyRaw = profile['current_pregnancy'];
        final currentPregnancy = currentPregnancyRaw != null
            ? Map<String, dynamic>.from(currentPregnancyRaw as Map)
            : null;
        final pastPregnancies = profile['past_pregnancies'] as List? ?? [];
        final medicalConditions =
            profile['medical_conditions'] as List? ?? [];
        final allergies = profile['allergies'] as List? ?? [];
        final emergencyContacts =
            profile['emergency_contacts'] as List? ?? [];
        final children = profile['children'] as List? ?? [];

        return Scaffold(
          backgroundColor: AppColors.bgPrimaryOf(context),
          floatingActionButton: _buildFAB(context, currentPregnancy, profile),
          body: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardColorOf(context),
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.borderOf(context)
                                .withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicatorColor: AppColors.brandPrimaryOf(context),
                        indicatorWeight: 3,
                        labelColor: AppColors.brandPrimaryOf(context),
                        labelStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                        unselectedLabelColor:
                            AppColors.textSecondaryOf(context),
                        unselectedLabelStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        tabs: const [
                          Tab(text: 'Overview'),
                          Tab(text: 'Current'),
                          Tab(text: 'History'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewTab(
                              profile,
                              medicalConditions,
                              allergies,
                              emergencyContacts,
                              children,
                              currentPregnancy),
                          _buildCurrentPregnancyTab(profile, currentPregnancy),
                          _buildHistoryTab(pastPregnancies),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Menu item widget ──────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? AppColors.error : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }
}
