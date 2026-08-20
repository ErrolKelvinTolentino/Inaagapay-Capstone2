// lib/screens/midwife/child_immunization_list_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/immunization_schedule.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/hero_card.dart';

class ChildImmunizationListPage extends StatefulWidget {
  final int childId;

  const ChildImmunizationListPage({
    super.key,
    required this.childId,
  });

  @override
  State<ChildImmunizationListPage> createState() => _ChildImmunizationListPageState();
}

class _ChildImmunizationListPageState extends State<ChildImmunizationListPage> {
  bool loading = true;
  List<Map<String, dynamic>> records = [];
  Map<String, dynamic>? childData;
  DateTime? birthdate;

  // Roadmap data
  List<Map<String, dynamic>> _allVaccines = [];
  Set<int> _takenVaccineIds = {};

  @override
  void initState() {
    super.initState();
    fetchImmunizations();
  }

  Future<void> fetchImmunizations() async {
    setState(() => loading = true);

    try {
      // Fetch child details
      final childResponse = await Supabase.instance.client
          .from('children')
          .select('''
            child_id,
            first_name,
            last_name,
            sex
          ''')
          .eq('child_id', widget.childId)
          .single();

      // Fetch birth details separately (directly from birth_details table)
      final birthDetailsResponse = await Supabase.instance.client
          .from('birth_details')
          .select('birthdate')
          .eq('child_id', widget.childId)
          .maybeSingle();

      if (birthDetailsResponse != null && birthDetailsResponse['birthdate'] != null) {
        birthdate = DateTime.parse(birthDetailsResponse['birthdate']);
      }

      childData = childResponse;

      // Fetch immunization records with vaccine details and batch number
      final immunizationResponse = await Supabase.instance.client
          .from('immunization_records')
          .select('''
            *,
            vaccine:vaccine_id (
              vaccine_id,
              vaccine_name,
              dose_number,
              recommended_age_months,
              notes
            ),
            batch:inventory_batch_id (
              batch_number
            )
          ''')
          .eq('child_id', widget.childId)
          .order('vaccination_date', ascending: false);

      records = List<Map<String, dynamic>>.from(immunizationResponse);

      // Load all vaccines for the roadmap
      final vaccinesResponse = await Supabase.instance.client
          .from('vaccines')
          .select('*')
          .eq('target_recipients', 'child')
          .order('recommended_age_months')
          .order('vaccine_name');

      _allVaccines = List<Map<String, dynamic>>.from(vaccinesResponse);
      _takenVaccineIds = records
          .map((r) => r['vaccine_id'] as int?)
          .whereType<int>()
          .toSet();

      debugPrint('Loaded ${records.length} immunization records');

      if (mounted) {
        setState(() => loading = false);
      }
    } catch (e) {
      debugPrint('Error loading immunizations: $e');
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading immunizations: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String getChildName() {
    if (childData == null) return 'Child';
    return '${childData!['first_name'] ?? ''} ${childData!['last_name'] ?? ''}'.trim();
  }

  String calculateAge() {
    if (birthdate == null) return 'Unknown age';

    try {
      final now = DateTime.now();
      int years = now.year - birthdate!.year;
      int months = now.month - birthdate!.month;
      int days = now.day - birthdate!.day;

      if (days < 0) {
        months -= 1;
        final prevMonthDate = DateTime(now.year, now.month, 0);
        days += prevMonthDate.day;
      }
      if (months < 0) {
        years -= 1;
        months += 12;
      }

      if (years > 0) {
        final monthPart = months > 0 ? ', $months month${months != 1 ? 's' : ''}' : '';
        return '$years year${years != 1 ? 's' : ''}$monthPart old';
      } else if (months > 0) {
        final weeks = days ~/ 7;
        final weekPart = weeks > 0 ? ', $weeks week${weeks != 1 ? 's' : ''}' : '';
        return '$months month${months != 1 ? 's' : ''}$weekPart old';
      } else {
        if (days >= 7) {
          final weeks = days ~/ 7;
          final remainingDays = days % 7;
          final dayPart = remainingDays > 0 ? ', $remainingDays day${remainingDays != 1 ? 's' : ''}' : '';
          return '$weeks week${weeks != 1 ? 's' : ''}$dayPart old';
        } else if (days > 0) {
          return '$days day${days != 1 ? 's' : ''} old';
        } else {
          return 'Newborn';
        }
      }
    } catch (e) {
      return 'Unknown age';
    }
  }

  String formatDate(String? date) {
    if (date == null || date.isEmpty) return 'No date';
    try {
      final parsed = DateTime.parse(date);
      return DateFormat('MMM d, yyyy').format(parsed);
    } catch (e) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Immunization Records',
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: fetchImmunizations,
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.brandPrimary,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: HeroCard(
                        image: null,
                        title: getChildName(),
                        subtitle: calculateAge(),
                        sex: childData?['sex']?.toString(),
                        showWeekBadge: false,
                        showHeartRow: false,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Immunization Roadmap ──
                    if (_allVaccines.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildRoadmap(),
                      ),

                    if (_allVaccines.isNotEmpty)
                      const SizedBox(height: 8),

                    if (_allVaccines.isNotEmpty)
                      const Divider(indent: 20, endIndent: 20),

                    const SizedBox(height: 8),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Vaccination History',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    records.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.vaccines_outlined,
                                    size: 64,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No Immunization Records',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Add immunization records to track vaccinations',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                    onPressed: fetchImmunizations,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.brandPrimary,
                                    ),
                                    child: const Text(
                                      'Refresh',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            itemCount: records.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final record = records[index];
                              final vaccine = record['vaccine'] as Map<String, dynamic>?;
                              final batch = record['batch'] as Map<String, dynamic>?;
                              final vaccineName = vaccine?['vaccine_name']?.toString() ?? 'Unknown Vaccine';
                              final doseNumber = vaccine?['dose_number']?.toString() ?? '';
                              final notes = vaccine?['notes']?.toString() ?? '';
                              final date = record['vaccination_date']?.toString() ?? '';
                              final remarks = record['remarks']?.toString() ?? '';
                              final batchNumber = batch?['batch_number']?.toString();
                              final source = record['source']?.toString();
                              final facilityName = record['facility_name']?.toString();

                              return ImmunizationRecordCard(
                                vaccineName: vaccineName,
                                doseNumber: doseNumber,
                                notes: notes,
                                date: formatDate(date),
                                remarks: remarks,
                                batchNumber: batchNumber,
                                source: source,
                                facilityName: facilityName,
                              );
                            },
                          ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── Roadmap helpers ──

  double _getChildAgeMonths() {
    if (birthdate == null) return 0;
    final now = DateTime.now();
    final diff = now.difference(birthdate!);
    return diff.inDays / 30.44;
  }

  DoseStatus _getVaccineStatus(Map<String, dynamic> vaccine) {
    return ImmunizationSchedule.statusOfVaccine(
      vaccine,
      alreadyGiven: _takenVaccineIds.contains(vaccine['vaccine_id'] as int),
      childAgeMonths: _getChildAgeMonths(),
      ageIsKnown: birthdate != null,
      birthdate: birthdate,
      previousDoseGivenOn: _previousDoseGivenOn(vaccine),
    );
  }

  /// Ages as printed on the DOH card. Rounding to whole months rendered the
  /// 1½ / 2½ / 3½ month visits as 2 / 3 / 4, which appear nowhere on paper.
  String _getMilestoneLabel(double months) =>
      ImmunizationSchedule.formatScheduledAge(months);

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
            const Text(
              'Immunization Roadmap',
              style: TextStyle(
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
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value:
                _allVaccines.isEmpty ? 0 : givenCount / _allVaccines.length,
            backgroundColor: AppColors.borderPrimary,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            // Same vocabulary as the Add Immunization picker. "Recommended"
            // previously covered both a dose due today and one eight months
            // overdue, which are not the same situation.
            _legendDot(AppColors.success, 'Given'),
            _legendDot(AppColors.warning, 'Past due'),
            _legendDot(AppColors.brandPrimary, 'Due now'),
            _legendDot(AppColors.textSecondary, 'Not yet due'),
          ],
        ),
        const SizedBox(height: 12),
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

  /// One dose on the roadmap.
  ///
  /// Vaccine name on the first line, the child-specific facts on the second.
  /// The `notes` text is deliberately absent: it is a definition of the
  /// vaccine, identical on every child's screen, and it was consuming most of
  /// the row while the date the dose was actually given — the reason a midwife
  /// opens this page — was not shown at all.
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

    // Show the dose number only when the vaccine actually has more than one.
    final multiDose = _allVaccines.any((v) =>
        v['vaccine_name'] == vaccine['vaccine_name'] &&
        ((v['dose_number'] as num?)?.toInt() ?? 1) > 1);
    final title = multiDose ? '$vaccineName · Dose $doseNumber' : vaccineName;

    // Second line: what changes from child to child.
    final String detail;
    switch (status) {
      case DoseStatus.given:
        final givenOn = _givenDateFor(vaccine['vaccine_id'] as int);
        detail = givenOn == null
            ? 'Given'
            : 'Given ${DateFormat('MMMM d, yyyy').format(givenOn)}';
      case DoseStatus.pastDue:
        detail = ImmunizationSchedule.describeOverdue(
          childAgeMonths: _getChildAgeMonths(),
          scheduledAtMonths: scheduledAt,
        );
      case DoseStatus.noLongerGiven:
        detail = 'Past the age limit for this vaccine';
      case DoseStatus.dueSoon:
        // The date is what the midwife tells the mother to come back for.
        final earliest = ImmunizationSchedule.earliestAllowedDate(
          birthdate: birthdate,
          scheduledAtMonths: scheduledAt,
          previousDoseGivenOn: _previousDoseGivenOn(vaccine),
          minimumIntervalWeeks:
              (vaccine['minimum_interval_weeks'] as num?)?.toInt(),
        );
        detail = earliest == null
            ? ImmunizationSchedule.formatScheduledAge(scheduledAt)
            : 'Due ${DateFormat('MMMM d, yyyy').format(earliest)}';
      case DoseStatus.due:
      case DoseStatus.notYetDue:
        detail = ImmunizationSchedule.formatScheduledAge(scheduledAt);
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
    for (final record in records) {
      if (record['vaccine_id'] == vaccineId) {
        final raw = record['vaccination_date']?.toString();
        if (raw != null) return DateTime.tryParse(raw);
      }
    }
    return null;
  }

  /// When the dose immediately before this one was given, if it was. Drives
  /// the minimum-interval rule so a later dose shows its real due date rather
  /// than reporting itself overdue right after a catch-up.
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

class ImmunizationRecordCard extends StatelessWidget {
  final String vaccineName;
  final String doseNumber;
  final String notes;
  final String date;
  final String remarks;
  final String? batchNumber;
  final String? source;
  final String? facilityName;

  const ImmunizationRecordCard({
    super.key,
    required this.vaccineName,
    required this.doseNumber,
    required this.notes,
    required this.date,
    required this.remarks,
    this.batchNumber,
    this.source,
    this.facilityName,
  });

  @override
  Widget build(BuildContext context) {
    final isOutside = source == 'outside';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.vaccines,
                  color: AppColors.brandPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vaccineName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (doseNumber.isNotEmpty)
                      Text(
                        'Dose $doseNumber',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (notes.isNotEmpty)
                      Text(
                        notes,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 14,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Given',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.calendar_today,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (batchNumber != null && batchNumber!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.colorize_rounded, size: 11, color: Color(0xFF059669)),
                      const SizedBox(width: 4),
                      Text(
                        'Batch #$batchNumber',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                      ),
                    ],
                  ),
                )
              else if (isOutside)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 11, color: Color(0xFF2563EB)),
                      const SizedBox(width: 4),
                      Text(
                        facilityName != null && facilityName!.isNotEmpty ? facilityName! : 'External Clinic',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (remarks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.notes_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      remarks,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}