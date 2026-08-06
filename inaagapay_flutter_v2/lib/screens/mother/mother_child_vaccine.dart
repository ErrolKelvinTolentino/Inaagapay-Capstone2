// lib/screens/mother/mother_child_vaccine.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/small_description.dart';
import '../../widgets/hero_card.dart';
import '../../widgets/records_display_card.dart';
import '../../services/immunization_schedule.dart';
import '../../widgets/status_indicator.dart';
import '../../services/child_service.dart';
import '../../services/language_service.dart';
import '../../models/child_model.dart';

class MotherChildVaccinePage extends StatefulWidget {
  final VoidCallback onBack;
  final int childId;
  final String childName;
  final String childAge;
  final String childGender;

  const MotherChildVaccinePage({
    super.key,
    required this.onBack,
    required this.childId,
    required this.childName,
    required this.childAge,
    required this.childGender,
  });

  @override
  State<MotherChildVaccinePage> createState() => _MotherChildVaccinePageState();
}

class _MotherChildVaccinePageState extends State<MotherChildVaccinePage> {
  List<ImmunizationRecord> _immunizations = [];
  bool _loading = true;
  String? _errorMessage;

  // Roadmap data
  List<Map<String, dynamic>> _allVaccines = [];
  Set<int> _takenVaccineIds = {};
  DateTime? _birthdate;

  @override
  void initState() {
    super.initState();
    _fetchVaccines();
  }

  Future<void> _fetchVaccines() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final client = Supabase.instance.client;

      // Fetch birth details separately (directly from birth_details table)
      final birthDetailsResponse = await client
          .from('birth_details')
          .select('birthdate')
          .eq('child_id', widget.childId)
          .maybeSingle();

      if (birthDetailsResponse != null && birthDetailsResponse['birthdate'] != null) {
        _birthdate = DateTime.parse(birthDetailsResponse['birthdate']);
      }

      // Fetch taken immunizations
      final immunizations = await ChildService.fetchImmunizations(widget.childId);

      // Load all vaccines for the roadmap
      final vaccinesResponse = await client
          .from('vaccines')
          .select('*')
          .eq('target_recipients', 'child')
          .order('recommended_age_months')
          .order('vaccine_name');

      if (mounted) {
        setState(() {
          _immunizations = immunizations;
          _allVaccines = List<Map<String, dynamic>>.from(vaccinesResponse);
          _takenVaccineIds = immunizations
              .map((r) => r.vaccineId)
              .toSet();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  String _formatRecommendedAge(double months) {
    if (months == 0) return _t('At birth', 'Sa kapanganakan');
    if (months < 1) {
      final weeks = (months * 4).round();
      if (LanguageService.isFilipino) return '$weeks linggo';
      return '$weeks week${weeks != 1 ? 's' : ''}';
    }
    if (months == 1) return _t('1 month', '1 buwan');
    if (LanguageService.isFilipino && months < 12) {
      return '${months.toInt()} buwan';
    }
    if (months < 12) return '${months.toInt()} months';
    final years = (months / 12).floor();
    if (LanguageService.isFilipino) return '$years taon';
    return '$years year${years != 1 ? 's' : ''}';
  }

  /// How timely this dose was.
  ///
  /// This previously returned onTime unconditionally, reasoning that every row
  /// in immunization_records had been given. It had — that is what makes it a
  /// record. Whether it was *timely* is the question the badge answers, and a
  /// dose given ten months late was still shown as "On Time".
  StatusIndicatorType? _getStatusIcon(ImmunizationRecord record) {
    return ImmunizationSchedule.timelinessOf(
      birthdate: _birthdate,
      givenOn: record.vaccinationDate,
      scheduledAtMonths: record.recommendedAgeMonths,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: SecondaryHeader(
          title: _t('Vaccination Details', 'Detalye ng Bakuna'),
          onBack: widget.onBack,
        ),
      ),
          body: RefreshIndicator(
        onRefresh: _fetchVaccines,
        color: AppColors.brandPrimary,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.brandPrimary,
                ),
              )
            : _errorMessage != null
                ? Center(
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
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchVaccines,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandPrimary,
                          ),
                          child: Text(_t('Retry', 'Subukan Muli')),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HeroCard(
                          image: null,
                          title: widget.childName,
                          subtitle: widget.childAge,
                          sex: widget.childGender,
                          showWeekBadge: false,
                          showHeartRow: false,
                        ),
                        const SizedBox(height: 20),

                        // ── Immunization Roadmap ──
                        if (_allVaccines.isNotEmpty) ...[
                          _buildRoadmap(),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                        ],

                        SmallDescription(
                          text: _t(
                              'Vaccines administered based on immunization schedule',
                              'Mga bakunang ibinigay batay sa immunization schedule'),
                        ),
                        const SizedBox(height: 16),
                        if (_immunizations.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.vaccines_outlined,
                                  size: 48,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _t('No immunizations recorded yet',
                                      'Wala pang naitalang bakuna'),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ..._immunizations.map((v) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: RecordsDisplayCard(
                                title:
                                    '${v.vaccineName} (${_t('Dose', 'Dose')} ${v.doseNumber})',
                                headerIcon: Icons.vaccines_outlined,
                                items: [
                                  RecordItem(
                                    leadingIcon: Icons.schedule,
                                    label: _t('Recommended', 'Inirerekomenda'),
                                    value: _formatRecommendedAge(v.recommendedAgeMonths),
                                  ),
                                  RecordItem(
                                    leadingIcon: Icons.calendar_month_rounded,
                                    label: _t('Date Given', 'Petsa ng Pagbigay'),
                                    value: _formatDate(v.vaccinationDate),
                                  ),
                                  RecordItem(
                                    leadingIcon: Icons.verified,
                                    label: _t('Status', 'Status'),
                                    value: _t('COMPLETED', 'KUMPLETO'),
                                    trailingWidget: () {
                                      final timeliness = _getStatusIcon(v);
                                      return timeliness == null
                                          ? null
                                          : StatusIndicator(status: timeliness);
                                    }(),
                                  ),
                                  if (v.remarks != null && v.remarks!.isNotEmpty)
                                    RecordItem(
                                      leadingIcon: Icons.notes_outlined,
                                      label: _t('Remarks', 'Mga Tala'),
                                      value: v.remarks!,
                                    ),
                                ],
                              ),
                            );
                          }),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
      ),
        );
      },
    );
  }

  // ── Roadmap Helpers ──

  double _getChildAgeMonths() {
    if (_birthdate == null) return 0;
    final now = DateTime.now();
    final diff = now.difference(_birthdate!);
    return diff.inDays / 30.44;
  }

  String _getVaccineStatus(Map<String, dynamic> vaccine) {
    final vaccineId = vaccine['vaccine_id'] as int;
    if (_takenVaccineIds.contains(vaccineId)) return 'given';
    final recommendedAge =
        (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0;
    if (_getChildAgeMonths() >= recommendedAge) return 'recommended';
    return 'not_due';
  }

  String _getMilestoneLabel(double months) {
    if (months == 0) return _t('At Birth', 'Sa Kapanganakan');
    if (months < 1) {
      final weeks = (months * 4).round();
      if (LanguageService.isFilipino) return '$weeks Linggo';
      return '$weeks Week${weeks != 1 ? 's' : ''}';
    }
    if (months < 12) {
      if (LanguageService.isFilipino) return '${months.toStringAsFixed(0)} Buwan';
      return '${months.toStringAsFixed(0)} Month${months.round() != 1 ? 's' : ''}';
    }
    final years = months / 12;
    if (years == years.roundToDouble()) {
      final yearsInt = years.round();
      if (LanguageService.isFilipino) return '$yearsInt Taon';
      return '$yearsInt Year${yearsInt != 1 ? 's' : ''}';
    }
    if (LanguageService.isFilipino) return '${months.toStringAsFixed(0)} Buwan';
    return '${months.toStringAsFixed(0)} Months';
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _getGroupedVaccines() {
    final Map<double, List<Map<String, dynamic>>> grouped = {};
    for (final v in _allVaccines) {
      final age = (v['recommended_age_months'] as num?)?.toDouble() ?? 0;
      grouped.putIfAbsent(age, () => []);
      grouped[age]!.add(v);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    return sortedKeys
        .map((age) => MapEntry(_getMilestoneLabel(age), grouped[age]!))
        .toList();
  }

  Widget _buildRoadmap() {
    final groups = _getGroupedVaccines();
    if (groups.isEmpty) return const SizedBox.shrink();

    final givenCount = _allVaccines
        .where((v) => _takenVaccineIds.contains(v['vaccine_id'] as int))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.map_outlined,
                color: AppColors.brandPrimary, size: 20),
            const SizedBox(width: 8),
            Text(
              _t('Immunization Roadmap', 'Roadmap ng Bakuna'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '$givenCount / ${_allVaccines.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value:
                _allVaccines.isEmpty ? 0 : givenCount / _allVaccines.length,
            backgroundColor: AppColors.borderPrimary,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.success),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _legendDot(AppColors.success, _t('Given', 'Ibinigay')),
            _legendDot(AppColors.warning, _t('Recommended', 'Inirerekomenda')),
            _legendDot(AppColors.textSecondary, _t('Not due yet', 'Hindi pa takda')),
          ],
        ),
        const SizedBox(height: 16),
        ...groups.map(
            (entry) => _buildMilestoneGroup(entry.key, entry.value)),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildMilestoneGroup(
      String label, List<Map<String, dynamic>> vaccines) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.brandAccent,
              ),
            ),
            const SizedBox(height: 6),
            ...vaccines.map((v) => _buildVaccineStatusRow(v)),
          ],
        ),
      ),
    );
  }

  Widget _buildVaccineStatusRow(Map<String, dynamic> vaccine) {
    final status = _getVaccineStatus(vaccine);
    final vaccineName = vaccine['vaccine_name']?.toString() ?? '';
    final doseNumber = vaccine['dose_number']?.toString() ?? '';
    final notes = vaccine['notes']?.toString() ?? '';

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (status) {
      case 'given':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        statusLabel = _t('Already given', 'Naibigay na');
        break;
      case 'recommended':
        statusColor = AppColors.warning;
        statusIcon = Icons.schedule;
        statusLabel = _t('Recommended', 'Inirerekomenda');
        break;
      default:
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.lock_outline;
        statusLabel = _t('Not due yet', 'Hindi pa takda');
    }

    final displayText = notes.isNotEmpty
        ? '$vaccineName (${_t('Dose', 'Dose')} $doseNumber) - $notes'
        : '$vaccineName (${_t('Dose', 'Dose')} $doseNumber)';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 12,
                color: status == 'not_due'
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                decoration: status == 'given'
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
