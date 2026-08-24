// lib/screens/mother/mother_vitals_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme/app_colors.dart';
import '../../services/supabase_service.dart';
import '../../services/language_service.dart';
import '../../services/weight_gain_engine.dart';
import '../../models/weight_gain_models.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/secondary_header.dart';

class MotherVitalsPage extends StatefulWidget {
  final int motherId;
  final int pregnancyId;
  final String? lastMenstrualPeriod;

  const MotherVitalsPage({
    super.key,
    required this.motherId,
    required this.pregnancyId,
    this.lastMenstrualPeriod,
  });

  @override
  State<MotherVitalsPage> createState() => _MotherVitalsPageState();
}

class _MotherVitalsPageState extends State<MotherVitalsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allVitals = [];
  WeightGainResult? _weightGainResult;
  double? _prePregnancyWeight;
  double? _heightCm;
  int _fetalCount = 1;
  bool _isUnlinked = false;
  bool _isPrePregnancyWeightEstimated = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString());
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Fetch pregnancy info (fetal count, pre pregnancy weight)
      final pregRow = await SupabaseService.client
          .from('pregnancies')
          .select('pre_pregnancy_weight, fetal_count')
          .eq('pregnancy_id', widget.pregnancyId)
          .maybeSingle();

      if (pregRow != null) {
        _prePregnancyWeight = pregRow['pre_pregnancy_weight'] != null
            ? _toDouble(pregRow['pre_pregnancy_weight'])
            : null;
        _isPrePregnancyWeightEstimated = pregRow['pre_pregnancy_weight'] == null;
        _fetalCount = pregRow['fetal_count'] != null
            ? _toInt(pregRow['fetal_count']) ?? 1
            : 1;
      }

      // 2. Fetch mother height
      final motherRow = await SupabaseService.client
          .from('mothers')
          .select('height, assigned_bhc_id')
          .eq('mother_id', widget.motherId)
          .maybeSingle();

      if (motherRow != null) {
        if (motherRow['height'] != null) {
          _heightCm = _toDouble(motherRow['height']);
        }
        _isUnlinked = motherRow['assigned_bhc_id'] == null;
      }

      // 3. Fetch checkups, through clinical_encounters.
      //
      // This used to select prenatal_checkup_id, checkup_datetime,
      // age_of_gestation and remarks straight off prenatal_checkups. None of
      // those columns exist there — the date, gestational age and notes live
      // on the parent encounter, and the primary key is encounter_id. PostgREST
      // rejected the whole request, the outer catch swallowed it, and the page
      // silently rendered with no official checkups at all: no blood pressure,
      // and a weight-gain analysis built only from what the mother typed
      // herself. Mirrors the working query in mother_dashboard.dart.
      final checkupsRaw = await SupabaseService.client
          .from('clinical_encounters')
          .select('''
            encounter_datetime,
            midwife_notes,
            age_of_gestation_weeks,
            age_of_gestation_days,
            checkup:prenatal_checkups!inner (
              encounter_id,
              checkup_weight,
              blood_pressure_systolic,
              blood_pressure_diastolic
            )
          ''')
          .eq('pregnancy_id', widget.pregnancyId)
          .eq('encounter_type', 'checkup');

      // 4. Fetch maternal vitals
      final vitalsRaw = await SupabaseService.client
          .from('maternal_vitals')
          .select('vital_id, recorded_at, age_of_gestation, weight_kg, height_cm, notes')
          .eq('pregnancy_id', widget.pregnancyId);

      final checkups = (checkupsRaw as List).cast<Map<String, dynamic>>();
      final vitals = (vitalsRaw as List).cast<Map<String, dynamic>>();

      // 5. Merge records
      final List<Map<String, dynamic>> merged = [
        ...checkups.map((enc) {
          // The embed comes back as a Map, or as a single-element List
          // depending on how PostgREST resolves the relationship. Every other
          // call site in this app unwraps both, so this does too.
          final rawCheckup = enc['checkup'];
          final checkup = rawCheckup is Map
              ? Map<String, dynamic>.from(rawCheckup)
              : (rawCheckup is List && rawCheckup.isNotEmpty
                  ? Map<String, dynamic>.from(rawCheckup.first as Map)
                  : <String, dynamic>{});

          // Left null rather than zero when the encounter never recorded it —
          // week 0 is a real gestational age and would be plotted as one.
          final weeks = _toDouble(enc['age_of_gestation_weeks']);
          final days = _toDouble(enc['age_of_gestation_days']);
          final double? aog = (weeks == null && days == null)
              ? null
              : (weeks ?? 0) + (days ?? 0) / 7.0;

          return {
            'id': checkup['encounter_id'],
            'date': DateTime.tryParse(
                    enc['encounter_datetime']?.toString() ?? '') ??
                DateTime.now(),
            'age_of_gestation': aog,
            'weight_kg': _toDouble(checkup['checkup_weight']),
            'bp_systolic': _toInt(checkup['blood_pressure_systolic']),
            'bp_diastolic': _toInt(checkup['blood_pressure_diastolic']),
            'height_cm': null,
            'notes': enc['midwife_notes'] ?? 'Official Prenatal Checkup',
            'source': 'prenatal_checkup',
          };
        }),
        ...vitals.map((v) => {
              'id': v['vital_id'],
              'date': DateTime.tryParse(v['recorded_at']?.toString() ?? '') ?? DateTime.now(),
              'age_of_gestation': _toDouble(v['age_of_gestation']),
              'weight_kg': _toDouble(v['weight_kg']),
              'bp_systolic': null,
              'bp_diastolic': null,
              'height_cm': _toDouble(v['height_cm']),
              'notes': v['notes'],
              'source': 'mother_self',
            }),
      ];

      // Sort chronological descending for history list
      merged.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      _allVitals = merged;

      // Prefill height from the latest history record if local height is null
      double? latestHeight = _heightCm;
      for (final v in _allVitals) {
        if (v['height_cm'] != null) {
          latestHeight = v['height_cm'];
          break;
        }
      }
      _heightCm = latestHeight;

      // 6. Run Weight Gain Engine evaluation if we have at least one weight reading
      final weightReadingsAsc = _allVitals
          .where((v) => v['weight_kg'] != null)
          .map((v) => {
                'checkup_weight': v['weight_kg'],
                'age_of_gestation': v['age_of_gestation'],
                'checkup_datetime': (v['date'] as DateTime).toIso8601String(),
                'is_checkup': v['source'] == 'prenatal_checkup',
              })
          .toList()
          .reversed // Convert descending list back to chronological ascending order
          .toList();

      // Deduplicate by AOG/date (prefer official prenatal checkup over self-reported vitals)
      final deduplicatedReadings = <Map<String, dynamic>>[];
      for (final item in weightReadingsAsc) {
        if (deduplicatedReadings.isEmpty) {
          deduplicatedReadings.add(item);
        } else {
          final last = deduplicatedReadings.last;
          final double diff = (((item['age_of_gestation'] ?? 0) as num).toDouble() - ((last['age_of_gestation'] ?? 0) as num).toDouble()).abs();
          if (diff < 0.2) {
            // Same rule as the mother profile: an official checkup beats a
            // self-logged weight, and between two records of the same kind the
            // later one wins. The previous condition dropped a second official
            // checkup taken within a day and a half of the first.
            final keepExisting =
                item['is_checkup'] != true && last['is_checkup'] == true;
            if (!keepExisting) {
              deduplicatedReadings[deduplicatedReadings.length - 1] = item;
            }
          } else {
            deduplicatedReadings.add(item);
          }
        }
      }

      // Same derivation the dashboard uses, so both screens start their series
      // from the same weight. This was written out here and nowhere else, which
      // is why the dashboard fell back to a limited evaluation for exactly the
      // mothers this page could still chart.
      final baseline = WeightGainEngine.baselineWeightFor(
        statedPrePregnancyWeight: _prePregnancyWeight,
        readingsAscending: deduplicatedReadings,
        heightCm: _heightCm,
        fetalCount: _fetalCount,
      );
      final double? prePregnancyWeight = baseline.weight;
      _prePregnancyWeight = prePregnancyWeight; // Cache locally
      _isPrePregnancyWeightEstimated = baseline.isEstimated;

      if (deduplicatedReadings.isNotEmpty) {
        final latest = deduplicatedReadings.last;
        final currentWeight = (latest['checkup_weight'] as num).toDouble();

        // Effective AOG calculation fallback
        double effectiveAog = (latest['age_of_gestation'] as num?)?.toDouble() ?? 0;
        if (effectiveAog == 0 && widget.lastMenstrualPeriod != null) {
          final lmp = DateTime.tryParse(widget.lastMenstrualPeriod!);
          if (lmp != null) {
            effectiveAog = DateTime.now().difference(lmp).inDays / 7.0;
          }
        }

        _weightGainResult = WeightGainEngine.evaluate(
          currentWeight: currentWeight,
          aogWeeks: effectiveAog,
          allCheckups: deduplicatedReadings,
          prePregnancyWeight: prePregnancyWeight,
          heightCm: _heightCm,
          fetalCount: _fetalCount,
        );
      } else {
        _weightGainResult = null;
      }    } catch (e) {
      debugPrint('Error loading vitals: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double? get _computedAogWeeks {
    if (widget.lastMenstrualPeriod == null) return null;
    final lmp = DateTime.tryParse(widget.lastMenstrualPeriod!);
    if (lmp == null) return null;
    return DateTime.now().difference(lmp).inDays / 7.0;
  }

  void _showAddVitalsBottomSheet() {
    final weightController = TextEditingController();
    final heightController = TextEditingController(text: _heightCm != null ? _heightCm!.toStringAsFixed(1) : '');
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;
    String? weightErrorText;
    String? heightErrorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> save() async {
            final weightStr = weightController.text.trim();
            final heightStr = heightController.text.trim();
            final weight = double.tryParse(weightStr);
            final height = double.tryParse(heightStr);

            setModalState(() {
              weightErrorText = null;
              heightErrorText = null;

              if (weightStr.isEmpty) {
                weightErrorText = _t('Weight is required', 'Kailangan ang timbang');
              } else if (weight == null || weight < 20 || weight > 200) {
                weightErrorText = _t('Enter a valid weight (20-200 kg)', 'Magpasok ng wastong timbang (20-200 kg)');
              }

              if (heightStr.isEmpty) {
                heightErrorText = _t('Height is required', 'Kailangan ang taas');
              } else if (height == null || height < 50 || height > 250) {
                heightErrorText = _t('Enter a valid height (50-250 cm)', 'Magpasok ng wastong taas (50-250 cm)');
              }
            });

            if (weightErrorText != null || heightErrorText != null) return;

            setModalState(() => isSaving = true);
            try {
              final notes = notesController.text.trim();

              final data = <String, dynamic>{
                'pregnancy_id': widget.pregnancyId,
                'mother_id': widget.motherId,
                'recorded_at': DateTime.now().toIso8601String(),
                'weight_kg': weight,
                'height_cm': height,
              };

              final aog = _computedAogWeeks;
              if (aog != null) {
                data['age_of_gestation'] = double.parse(aog.toStringAsFixed(1));
              }

              data['notes'] = notes.isNotEmpty ? notes : 'Self-logged vitals';

              await SupabaseService.client.from('maternal_vitals').insert(data);

              if (height != null) {
                await SupabaseService.client
                    .from('mothers')
                    .update({'height': height})
                    .eq('mother_id', widget.motherId);
                _heightCm = height;
              }

              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(_t('Your weight was saved.', 'Na-save ang timbang mo.')),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                _loadData();
              }
            } catch (e) {
              setModalState(() => isSaving = false);
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: AppColors.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _t('Add my weight', 'Idagdag ang timbang ko'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        'Your midwife will see this too.',
                        'Makikita rin ito ng iyong midwife.',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),

                     // Height Input
                    Text(
                      _t('Height (cm)', 'Taas (cm)'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppInputField(
                      hintText: _t('e.g. 156.2', 'hal. 156.2'),
                      controller: heightController,
                      isRequired: true,
                      readOnly: !_isUnlinked,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                      ],
                      leadingIcon: Icons.height,
                      errorText: heightErrorText,
                    ),
                    if (!_isUnlinked) ...[
                      const SizedBox(height: 6),
                      Text(
                        _t('Height is managed by your Barangay Health Center. Contact your midwife to update it.',
                           'Ang taas ay pinamamahalaan ng iyong Barangay Health Center. Makipag-ugnayan sa midwife upang i-update ito.'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Weight Input
                    Text(
                      _t('Weight (kg)', 'Timbang (kg)'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppInputField(
                      hintText: _t('e.g. 58.5', 'hal. 58.5'),
                      controller: weightController,
                      isRequired: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                      ],
                      leadingIcon: Icons.monitor_weight_outlined,
                      errorText: weightErrorText,
                    ),
                    const SizedBox(height: 16),

                    // Notes
                    Text(
                      _t('Notes (optional)', 'Mga Tala (opsyonal)'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppInputField(
                      hintText: _t('How are you feeling today?', 'Ano ang iyong nararamdaman ngayon?'),
                      controller: notesController,
                      leadingIcon: Icons.notes,
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _t('Save', 'I-save'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWeightChart() {
    final result = _weightGainResult;
    // Filter and prepare weights chronologically ascending
    final chartVitals = _allVitals
        .where((v) => v['weight_kg'] != null && v['age_of_gestation'] != null)
        .toList()
        .reversed
        .toList();

    final List<FlSpot> actualSpots = [];
    if (result != null && result.mode == WeightGainMode.full && result.baselineWeight != null) {
      actualSpots.add(FlSpot(0, result.baselineWeight!));
    }

    for (final v in chartVitals) {
      final double aog = (v['age_of_gestation'] as num).toDouble();
      final double weight = (v['weight_kg'] as num).toDouble();
      if (actualSpots.isNotEmpty && (aog - actualSpots.last.x).abs() < 0.1) {
        continue;
      }
      actualSpots.add(FlSpot(aog, weight));
    }

    actualSpots.sort((a, b) => a.x.compareTo(b.x));

    if (result == null || actualSpots.length < 2) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cardColorOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            const Icon(Icons.show_chart, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 8),
            Text(
              _t('Log at least 2 entries to see the weight trend chart.', 'Itala ang hindi bababa sa 2 timbang upang makita ang tsart.'),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final maxAog = actualSpots.last.x;
    final endWeek = maxAog > 40 ? maxAog : 40.0;
    final startWeek = result.baselineWeek ?? 0.0;

    final List<FlSpot> minSpots = [];
    final List<FlSpot> maxSpots = [];

    if (result.baselineWeight != null && result.baselineWeek != null) {
      for (double w = startWeek; w <= endWeek; w += 2) {
        final range = _getRecommendedRangeAt(
          aogWeeks: w,
          bmiCategory: result.bmiCategory,
          baselineWeight: result.baselineWeight!,
          baselineWeek: result.baselineWeek!,
          fetalCount: _fetalCount,
        );
        minSpots.add(FlSpot(w, range['min']!));
        maxSpots.add(FlSpot(w, range['max']!));
      }
      // Ensure endWeek is included
      final endRange = _getRecommendedRangeAt(
        aogWeeks: endWeek,
        bmiCategory: result.bmiCategory,
        baselineWeight: result.baselineWeight!,
        baselineWeek: result.baselineWeek!,
        fetalCount: _fetalCount,
      );
      if (minSpots.isEmpty || minSpots.last.x != endWeek) {
        minSpots.add(FlSpot(endWeek, endRange['min']!));
        maxSpots.add(FlSpot(endWeek, endRange['max']!));
      }
    }

    final allSpots = [...actualSpots, ...minSpots, ...maxSpots];
    final minY = allSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 2;
    final maxY = allSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 2;
    final minX = startWeek;
    final maxX = endWeek;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart,
                  size: 20, color: AppColors.brandPrimary),
              const SizedBox(width: 8),
              Text(
                _t('Your Weight Over Time', 'Timbang Mo sa Paglipas ng Panahon'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _t('Your weight at each entry, next to the ideal range',
               'Aktwal na timbang (kg) kumpara sa inirerekomendang saklaw ng IOM'),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          
          // Legend row
          Row(
            children: [
              Container(
                width: 14,
                height: 3,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                _t('Your weight', 'Timbang mo'),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 16),
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
                // "IOM Recommended Bounds (Normal)" names the guideline body
                // and the BMI category in a chart legend. Both are already
                // stated where they belong — the category in the rows above,
                // the source in the references expander.
                _t('Ideal range', 'Tamang saklaw'),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 200,
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
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 4.0,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'W${value.toInt()}',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: ((maxY - minY) / 5).clamp(1.0, 10.0),
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()} kg',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                // Order matters: fl_chart paints these in sequence, so the band
                // is laid down first and her own line goes on top of it. Drawn
                // the other way round, the lower bound's opaque fill would
                // erase her line exactly when she is below the range — the one
                // case she most needs to see.
                lineBarsData: [
                  // The ideal range as one shaded band, not two dashed lines.
                  //
                  // Two grey dashed curves ask the reader to work out that the
                  // space between them is the target — a convention borrowed
                  // from clinical growth charts. Filling it turns the whole
                  // idea into one instruction anybody can follow: keep the
                  // pink line in the green.
                  if (maxSpots.isNotEmpty && minSpots.isNotEmpty)
                    LineChartBarData(
                      spots: maxSpots,
                      isCurved: true,
                      color: AppColors.success.withValues(alpha: 0.45),
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.success.withValues(alpha: 0.13),
                        applyCutOffY: false,
                        spotsLine: const BarAreaSpotsLine(show: false),
                      ),
                    ),
                  if (minSpots.isNotEmpty)
                    LineChartBarData(
                      spots: minSpots,
                      isCurved: true,
                      color: AppColors.success.withValues(alpha: 0.45),
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                      // Paints the card colour back over everything below the
                      // lower bound, leaving only the corridor tinted.
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.white,
                        applyCutOffY: false,
                        spotsLine: const BarAreaSpotsLine(show: false),
                      ),
                    ),
                  // Her own weight, last, so nothing can cover it.
                  LineChartBarData(
                    spots: actualSpots,
                    isCurved: true,
                    color: AppColors.brandPrimary,
                    barWidth: 3.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 5,
                        color: Colors.white,
                        strokeWidth: 2.5,
                        strokeColor: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      // Only her own line answers a tap now.
                      //
                      // The band is context, not data — three tooltips saying
                      // "IOM Min", "IOM Max" and her weight on one tap was
                      // three readings where she asked for one. The prefixes
                      // were also keyed to the old drawing order and would now
                      // label the wrong lines.
                      final lastIndex =
                          touchedSpots.isEmpty ? -1 : touchedSpots.length - 1;
                      return [
                        for (var i = 0; i < touchedSpots.length; i++)
                          if (i == lastIndex)
                            LineTooltipItem(
                              '${_t('Week', 'Linggo')} '
                              '${touchedSpots[i].x.toInt()}\n'
                              '${_kg(touchedSpots[i].y)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            )
                          else
                            null,
                      ];
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSourceBadge(String source) {
    Color bg;
    Color fg;
    String text;

    switch (source) {
      case 'prenatal_checkup':
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0369A1);
        text = _t('Official', 'Opisyal');
        break;
      case 'midwife_quick':
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF7E22CE);
        text = _t('Midwife Log', 'Tala ng Midwife');
        break;
      case 'mother_self':
      default:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        text = _t('Self-logged', 'Sariling Tala');
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildEvaluationCard() {
    final result = _weightGainResult;
    if (result == null) return const SizedBox.shrink();

    Color statusColor;
    switch (result.status) {
      case WeightGainStatus.normal:
        statusColor = AppColors.success;
        break;
      case WeightGainStatus.low:
        statusColor = AppColors.warning;
        break;
      case WeightGainStatus.high:
        statusColor = AppColors.error;
        break;
      case WeightGainStatus.insufficient:
        statusColor = AppColors.textSecondary;
        break;
    }

    // The same three words as her dashboard and the midwife's card.
    //
    // "Within expected monitoring range" is a phrase from a monitoring system,
    // not from a conversation, and it was long enough to fill the pill on its
    // own. "Slightly above" also understated a mother well over the range.
    String getStatusDisplayLabel(WeightGainStatus status) {
      switch (status) {
        case WeightGainStatus.normal:
          return _t('Within ideal', 'Nasa tamang saklaw');
        case WeightGainStatus.low:
          return _t('Below ideal', 'Mababa sa saklaw');
        case WeightGainStatus.high:
          return _t('Above ideal', 'Mataas sa saklaw');
        case WeightGainStatus.insufficient:
          return _t('Need more weights', 'Kulang pa ang timbang');
      }
    }

    String getBmiCategoryLabel(String category) {
      switch (category) {
        case 'Underweight':
          return _t('Underweight', 'Mababa ang Timbang');
        case 'Normal':
          return _t('Normal', 'Normal');
        case 'Overweight':
          return _t('Overweight', 'Sobra sa Timbang');
        case 'Obese':
          return _t('Obese', 'Mataba');
        default:
          return _t(category, category);
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monitor_weight_outlined,
                        color: statusColor, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      _t('How your weight is going', 'Kumusta ang timbang mo'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    getStatusDisplayLabel(result.status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Her own words for her own numbers. "BMI Category", "Actual
                // Gain" and "Baseline Weight" are column headings from a
                // clinical form; a mother reading her own record should not
                // have to translate them.
                _weightInfoRow(
                  _t('Body size before pregnancy', 'Sukat bago mabuntis'),
                  getBmiCategoryLabel(result.bmiCategory),
                ),
                _weightInfoRow(
                  _t('Weight now', 'Timbang ngayon'),
                  _kg(result.currentWeight),
                ),
                if (result.baselineWeight != null)
                  _weightInfoRow(
                    result.mode == WeightGainMode.full
                        ? _t('Weight before pregnancy', 'Timbang bago mabuntis')
                        : _t('Starting weight', 'Panimulang timbang'),
                    _kg(result.baselineWeight!),
                  ),
                if (result.actualGain != null)
                  _weightInfoRow(
                    _t('Gained so far', 'Nadagdag na'),
                    '${result.actualGain! >= 0 ? '+' : ''}${_kg(result.actualGain!)}',
                  ),
                if (result.expectedGainMin != null && result.expectedGainMax != null)
                  _weightInfoRow(
                    _t('Ideal by now', 'Tamang dagdag ngayon'),
                    '${_kg(result.expectedGainMin!)} – ${_kg(result.expectedGainMax!)}',
                  )
                else if (result.expectedGain != null)
                  _weightInfoRow(
                    _t('Ideal by now', 'Tamang dagdag ngayon'),
                    _kg(result.expectedGain!),
                  ),
                if (result.weeklyGain != null)
                  _weightInfoRow(
                    _t('Gain each week', 'Dagdag kada linggo'),
                    // Two decimals, not three. A weight scale a mother owns
                    // does not measure to a gram.
                    '${result.weeklyGain!.toStringAsFixed(2)} kg',
                  ),

                const SizedBox(height: 12),
                // Flags
                if (result.hasFlags) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: result.flags.map((flag) {
                      String label;
                      Color flagColor = AppColors.error;
                      if (flag == 'weight_loss') {
                        label = _t('⚠️ Weight Loss Detected', '⚠️ May Bawas sa Timbang');
                      } else if (flag == 'plateau') {
                        label = _t('ℹ️ Weight Plateau', 'ℹ️ Patag na Timbang');
                        flagColor = AppColors.warning;
                      } else if (flag == 'abnormal_spike') {
                        label = _t('⚠️ Rapid Weight Gain Spike', '⚠️ Mabilis na Pagtaas ng Timbang');
                      } else {
                        label = flag.replaceAll('_', ' ').toUpperCase();
                      }
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: flagColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: flagColor,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                ],

                // Advisory message box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    // The engine's own message is written for a midwife —
                    // "Full BMI-Based Evaluation at Week 8.0. BMI category:
                    // Normal. Total weight gain: 1.0 kg…" — and every fact in
                    // it already appears in the rows directly above. What she
                    // gets instead is the one thing the rows do not say: what
                    // it means for her.
                    _plainSummary(result),
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),

                // The engine can append an ALERT about a sudden gain, which is
                // the one part of its message a mother must not miss. Kept,
                // but said in a way she can act on rather than as a note to
                // rule out edema.
                if (result.message.contains('ALERT:')) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 16, color: Color(0xFFD97706)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _t(
                              'Your weight went up quickly. Please tell your midwife at your next visit, or sooner if you feel swelling in your hands, face or feet.',
                              'Mabilis na tumaas ang timbang mo. Sabihin sa iyong midwife sa susunod na bisita, o mas maaga kung may pamamaga sa kamay, mukha o paa.',
                            ),
                            style: const TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_isPrePregnancyWeightEstimated) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.blue.shade600, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _t(
                            'Pre-pregnancy weight (W0) was estimated using backtracking as it wasn\'t provided.',
                            'Ang timbang bago mabuntis (W0) ay tinantya gamit ang backtracking dahil walang naitalang baseline.',
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      _t('Clinical Disclaimer & References', 'Klinikal na Disclaimer at mga Sanggunian'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                    dense: true,
                    children: [
                      Text(
                        _t(
                          'Disclaimer: This analysis is based on the Institute of Medicine (IOM) 2009 Guidelines. It is for monitoring and educational support only and does not substitute for professional medical advice, clinical assessment, or diagnosis.',
                          'Disclaimer: Ang pagsusuring ito ay batay sa Institute of Medicine (IOM) 2009 Guidelines. Ito ay para sa pagsubaybay at suportang pang-edukasyon lamang at hindi pamalit sa propesyonal na payong medikal, klinikal na pagtatasa, o diagnosis.',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          'References:\n• Institute of Medicine (IOM) & National Research Council (NRC). (2009). Weight Gain During Pregnancy: Reexamining the Guidelines. Washington, DC: The National Academies Press.',
                          'Mga Sanggunian:\n• Institute of Medicine (IOM) & National Research Council (NRC). (2009). Weight Gain During Pregnancy: Reexamining the Guidelines. Washington, DC: The National Academies Press.',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: Colors.grey.shade600,
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

  /// What her numbers mean, in one sentence.
  ///
  /// Stated, never instructed: it says where her gain sits and who to ask.
  /// Telling a mother to eat more or less is advice, and this screen is not
  /// the one qualified to give it.
  String _plainSummary(WeightGainResult result) {
    switch (result.status) {
      case WeightGainStatus.normal:
        return _t(
          'Your weight gain is where it should be for this stage of your pregnancy. Keep logging it so your midwife can follow along.',
          'Nasa tamang saklaw ang dagdag ng timbang mo para sa yugtong ito ng pagbubuntis. Ipagpatuloy ang pagtatala para masubaybayan ito ng iyong midwife.',
        );
      case WeightGainStatus.low:
        return _t(
          'You have gained less than the ideal range for this stage. Bring this up with your midwife at your next visit.',
          'Mas mababa sa tamang saklaw ang nadagdag mo para sa yugtong ito. Banggitin ito sa iyong midwife sa susunod na bisita.',
        );
      case WeightGainStatus.high:
        return _t(
          'You have gained more than the ideal range for this stage. Bring this up with your midwife at your next visit.',
          'Mas mataas sa tamang saklaw ang nadagdag mo para sa yugtong ito. Banggitin ito sa iyong midwife sa susunod na bisita.',
        );
      case WeightGainStatus.insufficient:
        return _t(
          'Log a few more weights and we can show how your gain is going.',
          'Magtala pa ng ilang timbang para maipakita namin ang takbo ng pagdagdag mo.',
        );
    }
  }

  /// A weight in kilos without a pointless decimal — "45 kg", not "45.0 kg".
  String _kg(double value) {
    final rounded = (value * 10).round() / 10;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toStringAsFixed(1);
    return '$text kg';
  }

  Widget _weightInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          Text(
            value,
            // Softened off near-black. A column of bold #2D2D2D figures on
            // white is the hardest contrast on the page, and none of these
            // numbers needs to shout.
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.inputText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimaryOf(context),
      // The app's own header, in brand pink. This was a Material AppBar with
      // a near-black title and a hairline shadow — the one screen in the
      // mother's app that still looked like a settings page.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: _t('My Weight', 'Aking Timbang'),
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.brandPrimary,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppColors.brandPrimary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                children: [
                  _buildEvaluationCard(),
                  const SizedBox(height: 16),
                  _buildWeightChart(),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.history, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        _t('Every weight you saved', 'Lahat ng timbang na na-save mo'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_allVitals.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.favorite_border, size: 40, color: Colors.grey),
                          const SizedBox(height: 8),
                          Text(
                            _t('No weight saved yet. Tap the pink button below to add your first one.', 
                               'Wala pang naitalang vitals. Tapikin ang button sa ibaba upang magsimula!'),
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ..._allVitals.map((v) {
                      final double? weight = v['weight_kg'];
                      final double? height = v['height_cm'] ?? _heightCm;
                      final int? sys = v['bp_systolic'];
                      final int? dia = v['bp_diastolic'];
                      final double? aog = v['age_of_gestation'];
                      final String notes = v['notes'] ?? '';
                      final DateTime date = v['date'];
                      final String formattedDate = DateFormat('MMMM d, yyyy · h:mm a').format(date);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    formattedDate,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                _buildSourceBadge(v['source']),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (weight != null) ...[
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.monitor_weight_outlined, size: 18, color: AppColors.brandPrimary),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _t('Weight', 'Timbang'),
                                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                            ),
                                            Text(
                                              '${weight.toStringAsFixed(1)} kg',
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (height != null) ...[
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.height, size: 18, color: AppColors.brandPrimary),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _t('Height', 'Taas'),
                                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                            ),
                                            Text(
                                              '${height.toStringAsFixed(1)} cm',
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                 ],
                                if (aog != null) ...[
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.baby_changing_station, size: 18, color: AppColors.brandPrimary),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _t('AOG', 'Edad ng Gest.'),
                                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                            ),
                                            Text(
                                              '${aog.toStringAsFixed(1)} wks',
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            // Blood pressure, on its own row because the row
                            // above already carries three columns and a fourth
                            // squeezes them on a phone. Only checkups have it —
                            // she cannot log her own — so this appears on
                            // official rows only.
                            //
                            // Shown as the plain reading with no interpretation.
                            // Telling a mother her reading is "above threshold"
                            // on a screen with no midwife present is alarming
                            // without being actionable; the classification lives
                            // on the midwife's side of the app.
                            if (sys != null && dia != null) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.monitor_heart_outlined,
                                      size: 18, color: AppColors.brandPrimary),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t('Blood Pressure', 'Presyon ng Dugo'),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary),
                                      ),
                                      Text(
                                        '$sys/$dia mmHg',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                            if (notes.isNotEmpty) ...[
                              const Divider(height: 20, color: AppColors.borderPrimary),
                              Text(
                                notes,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inputText,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddVitalsBottomSheet,
        backgroundColor: AppColors.brandPrimary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.add),
        label: Text(_t('Add weight', 'Idagdag ang timbang')),
      ),
    );
  }
}
