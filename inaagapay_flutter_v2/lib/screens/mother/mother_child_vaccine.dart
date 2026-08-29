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
                          // A bare Divider draws the theme's default rule,
                          // which on this page came out as a hard black line
                          // across the width — the only one in the mother's
                          // app. The spacing already separates the roadmap
                          // from the records below it.
                          const SizedBox(height: 24),
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
                                  // No "COMPLETED" beside the timeliness pill.
                                  //
                                  // Every card in this list is a dose that was
                                  // given — it has a date on the line above —
                                  // so the word restated the fact of the card
                                  // and left "Very late" reading as a second,
                                  // contradicting verdict beside it. The pill
                                  // says the only thing that varies.
                                  RecordItem(
                                    leadingIcon: Icons.verified,
                                    label: _t('Status', 'Status'),
                                    value: '',
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

  /// Same judgement the midwife's roadmap uses, so a mother and her midwife
  /// never see different statuses for the same dose.
  DoseStatus _getVaccineStatus(Map<String, dynamic> vaccine) {
    return ImmunizationSchedule.statusOfVaccine(
      vaccine,
      alreadyGiven: _takenVaccineIds.contains(vaccine['vaccine_id'] as int),
      childAgeMonths: _getChildAgeMonths(),
      ageIsKnown: _birthdate != null,
    );
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
            // Same four states as the midwife's roadmap. "Recommended" covered
            // both a dose due today and one months overdue.
            _legendDot(AppColors.success, _t('Given', 'Ibinigay')),
            _legendDot(AppColors.warning,
                _t('Catch-up needed', 'Kailangang habulin')),
            _legendDot(AppColors.brandPrimary, _t('Due now', 'Takda na')),
            _legendDot(
                AppColors.textSecondary, _t('Not yet due', 'Hindi pa takda')),
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

  /// One dose on the mother's roadmap.
  ///
  /// Mirrors the midwife's row: vaccine name, then the one fact that changes
  /// from child to child. The vaccine description is left out — it is the same
  /// sentence on every screen and was crowding out the date.
  Widget _buildVaccineStatusRow(Map<String, dynamic> vaccine) {
    final status = _getVaccineStatus(vaccine);
    final vaccineName = vaccine['vaccine_name']?.toString() ?? '';
    final doseNumber = (vaccine['dose_number'] as num?)?.toInt() ?? 1;
    final scheduledAt =
        (vaccine['recommended_age_months'] as num?)?.toDouble() ?? 0;

    final Color statusColor = switch (status) {
      DoseStatus.given => AppColors.success,
      DoseStatus.pastDue => AppColors.warning,
      DoseStatus.due => AppColors.brandPrimary,
      DoseStatus.dueSoon => AppColors.brandAccent,
      DoseStatus.noLongerGiven => AppColors.error,
      DoseStatus.notYetDue => AppColors.textSecondary,
    };

    final IconData statusIcon = switch (status) {
      DoseStatus.given => Icons.check_circle,
      DoseStatus.pastDue => Icons.schedule_rounded,
      DoseStatus.due => Icons.radio_button_unchecked,
      DoseStatus.dueSoon => Icons.event_available_outlined,
      DoseStatus.noLongerGiven => Icons.block_outlined,
      DoseStatus.notYetDue => Icons.lock_outline,
    };

    final multiDose = _allVaccines.any((v) =>
        v['vaccine_name'] == vaccine['vaccine_name'] &&
        ((v['dose_number'] as num?)?.toInt() ?? 1) > 1);
    final title = multiDose
        ? '$vaccineName · ${_t('Dose', 'Dose')} $doseNumber'
        : vaccineName;

    final String detail;
    switch (status) {
      case DoseStatus.given:
        final givenOn = _givenDateFor(vaccine['vaccine_id'] as int);
        detail = givenOn == null
            ? _t('Given', 'Naibigay na')
            : '${_t('Given', 'Naibigay')} ${_formatDate(givenOn)}';
      case DoseStatus.pastDue:
        // Stated plainly rather than softened: a mother needs to know this is
        // outstanding so she can bring the child in.
        detail = _t('Catch-up needed', 'Kailangan nang habulin');
      case DoseStatus.noLongerGiven:
        detail = _t('No longer given at this age',
            'Hindi na ibinibigay sa edad na ito');
      case DoseStatus.dueSoon:
        // The most useful thing a mother can be told: when to come back.
        final earliest = ImmunizationSchedule.earliestAllowedDate(
          birthdate: _birthdate,
          scheduledAtMonths: scheduledAt,
          previousDoseGivenOn: _previousDoseGivenOn(vaccine),
          minimumIntervalWeeks:
              (vaccine['minimum_interval_weeks'] as num?)?.toInt(),
        );
        detail = earliest == null
            ? _formatRecommendedAge(scheduledAt)
            : '${_t('Due', 'Takda')} ${_formatDate(earliest)}';
      case DoseStatus.due:
      case DoseStatus.notYetDue:
        detail = _formatRecommendedAge(scheduledAt);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(statusIcon, color: statusColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: status == DoseStatus.notYetDue
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: status == DoseStatus.pastDue ||
                            status == DoseStatus.noLongerGiven
                        ? statusColor
                        : Colors.grey.shade500,
                    fontWeight: status == DoseStatus.pastDue
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// When a given dose was administered, from the loaded records.
  DateTime? _givenDateFor(int vaccineId) {
    for (final record in _immunizations) {
      if (record.vaccineId == vaccineId) return record.vaccinationDate;
    }
    return null;
  }

  /// When the dose immediately before this one was given, if it was. Drives
  /// the minimum-interval rule so a later dose shows its real due date.
  DateTime? _previousDoseGivenOn(Map<String, dynamic> vaccine) {
    final doseNumber = (vaccine['dose_number'] as num?)?.toInt() ?? 1;
    if (doseNumber <= 1) return null;

    final name = vaccine['vaccine_name']?.toString();
    for (final v in _allVaccines) {
      if (v['vaccine_name']?.toString() == name &&
          ((v['dose_number'] as num?)?.toInt() ?? 1) == doseNumber - 1) {
        return _givenDateFor(v['vaccine_id'] as int);
      }
    }
    return null;
  }
}
