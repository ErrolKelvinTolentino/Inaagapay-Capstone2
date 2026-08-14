import 'package:flutter/material.dart';

import '../../models/pregnancy_health_record.dart';
import '../../theme/app_colors.dart';
import 'baby_book_section_components.dart';

class PregnancyHealthRecordsSection extends StatefulWidget {
  final List<PregnancyHealthRecord> initialRecords;

  const PregnancyHealthRecordsSection({
    super.key,
    required this.initialRecords,
  });

  @override
  State<PregnancyHealthRecordsSection> createState() =>
      _PregnancyHealthRecordsSectionState();
}

class _PregnancyHealthRecordsSectionState
    extends State<PregnancyHealthRecordsSection> {
  late final List<PregnancyHealthRecord> _records;
  PregnancyRecordType _selectedType = PregnancyRecordType.vaccination;

  @override
  void initState() {
    super.initState();
    _records = List<PregnancyHealthRecord>.from(widget.initialRecords);
  }

  List<PregnancyHealthRecord> get _filteredRecords => _records
      .where((record) => record.type == _selectedType)
      .toList(growable: false);

  PregnancyHealthRecord? get _nextScheduledRecord {
    final now = DateTime.now();
    final scheduled = _records
        .where(
          (record) =>
              record.nextScheduledDate != null &&
              record.nextScheduledDate!.isAfter(now),
        )
        .toList()
      ..sort(
        (a, b) => a.nextScheduledDate!.compareTo(b.nextScheduledDate!),
      );
    return scheduled.isEmpty ? null : scheduled.first;
  }

  Future<void> _openRecordForm([PregnancyHealthRecord? existing]) async {
    final saved = await showModalBottomSheet<PregnancyHealthRecord>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _PregnancyHealthRecordForm(
        existing: existing,
        initialType: existing?.type ?? _selectedType,
      ),
    );
    if (saved == null || !mounted) return;

    setState(() {
      final existingIndex = _records.indexWhere((item) => item.id == saved.id);
      if (existingIndex == -1) {
        _records.insert(0, saved);
      } else {
        _records[existingIndex] = saved;
      }
      _selectedType = saved.type;
    });
  }

  void _updateStatus(
    PregnancyHealthRecord record,
    PregnancyRecordStatus status,
  ) {
    setState(() {
      final index = _records.indexWhere((item) => item.id == record.id);
      if (index != -1) {
        _records[index] = record.copyWith(status: status, isSample: false);
      }
    });
  }

  Future<void> _confirmDelete(PregnancyHealthRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete this record?'),
        content: Text(
          '“${record.name}” will be removed from this local Baby Book mockup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep record'),
          ),
          FilledButton(
            key: const ValueKey('health-confirm-delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _records.removeWhere((item) => item.id == record.id));
  }

  Future<void> _showRecordDetails(PregnancyHealthRecord record) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final rows = <(String, String)>[
          ('Record type', record.type.label),
          ('Recorded date', babyBookFormatDate(record.recordDate)),
          if (record.dosage?.isNotEmpty == true) ('Dosage', record.dosage!),
          if (record.frequency?.isNotEmpty == true)
            ('Frequency', record.frequency!),
          if (record.startDate != null)
            ('Start date', babyBookFormatDate(record.startDate!)),
          if (record.endDate != null)
            ('End date', babyBookFormatDate(record.endDate!)),
          if (record.providerName?.isNotEmpty == true)
            ('Healthcare provider', record.providerName!),
          if (record.healthFacility?.isNotEmpty == true)
            ('Health facility', record.healthFacility!),
          if (record.instructions?.isNotEmpty == true)
            ('Instructions', record.instructions!),
          if (record.notes?.isNotEmpty == true) ('Notes', record.notes!),
          ('Status', record.status.label),
          if (record.nextScheduledDate != null)
            (
              'Next scheduled date',
              babyBookFormatDate(record.nextScheduledDate!),
            ),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5DDE0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  record.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (record.isSample) ...[
                  const SizedBox(height: 7),
                  const BabyBookStatusPill(
                    label: 'SAMPLE DATA',
                    color: AppColors.brandText,
                    icon: Icons.science_outlined,
                  ),
                ],
                const SizedBox(height: 18),
                for (final row in rows) ...[
                  _RecordDetailRow(label: row.$1, value: row.$2),
                  const Divider(color: AppColors.borderPrimary, height: 20),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _openRecordForm(record);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandPrimary,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit record'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final nextRecord = _nextScheduledRecord;
    final filtered = _filteredRecords;

    return Column(
      key: const ValueKey('pregnancy-health-records-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BabyBookSectionHeader(
          eyebrow: 'PROVIDER-RECORDED CARE',
          title: 'Vaccinations and Supplements',
          description:
              'Keep track of vaccinations and supplements prescribed or recorded by your doctor, nurse, or midwife.',
          actionLabel: 'Add Record',
          actionIcon: Icons.add_rounded,
          onAction: () => _openRecordForm(),
        ),
        const SizedBox(height: 14),
        const BabyBookPictureBanner(
          key: ValueKey<String>('health-records-picture-card'),
          assetPath: 'assets/images/health_records_card.png',
          semanticLabel:
              'Pregnant mother reviewing her provider-recorded care plan with a midwife',
          eyebrow: 'CARE, RECORDED TOGETHER',
          title: 'Provider-guided care in one place.',
          subtitle:
              'Keep the details your doctor, nurse, or midwife has prescribed or recorded.',
        ),
        if (nextRecord != null) ...[
          const SizedBox(height: 13),
          BabyBookPanel(
            color: const Color(0xFFFFF5F9),
            borderColor: const Color(0xFFFFD7E7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  color: AppColors.brandPrimary,
                  size: 22,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Upcoming provider-recorded schedule',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${nextRecord.name} • ${babyBookFormatDate(nextRecord.nextScheduledDate!)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _RecordFilterButton(
                key: const ValueKey('health-filter-vaccination'),
                label: 'Vaccinations',
                icon: Icons.vaccines_outlined,
                selected: _selectedType == PregnancyRecordType.vaccination,
                onTap: () => setState(
                  () => _selectedType = PregnancyRecordType.vaccination,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _RecordFilterButton(
                key: const ValueKey('health-filter-supplement'),
                label: 'Supplements',
                icon: Icons.medication_outlined,
                selected: _selectedType == PregnancyRecordType.supplement,
                onTap: () => setState(
                  () => _selectedType = PregnancyRecordType.supplement,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          _HealthRecordEmptyState(
            type: _selectedType,
            onAdd: () => _openRecordForm(),
          )
        else
          for (var index = 0; index < filtered.length; index++) ...[
            _PregnancyHealthRecordCard(
              record: filtered[index],
              onView: () => _showRecordDetails(filtered[index]),
              onEdit: () => _openRecordForm(filtered[index]),
              onComplete: () => _updateStatus(
                filtered[index],
                PregnancyRecordStatus.completed,
              ),
              onDiscontinue: () => _updateStatus(
                filtered[index],
                PregnancyRecordStatus.discontinued,
              ),
              onDelete: () => _confirmDelete(filtered[index]),
            ),
            if (index != filtered.length - 1) const SizedBox(height: 10),
          ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8EA),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFFFE1A3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                color: Color(0xFFD78C28),
                size: 18,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Only take medicines or supplements according to the instructions of your doctor, nurse, or midwife. Do not start, stop, or change a prescribed product without consulting your healthcare provider.',
                  style: TextStyle(
                    color: Color(0xFF8A632D),
                    fontSize: 10,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordFilterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RecordFilterButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.brandPrimary : Colors.white,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color:
                    selected ? AppColors.brandPrimary : const Color(0xFFFFD7E6),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : AppColors.brandText,
                  size: 17,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PregnancyHealthRecordCard extends StatelessWidget {
  final PregnancyHealthRecord record;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onComplete;
  final VoidCallback onDiscontinue;
  final VoidCallback onDelete;

  const _PregnancyHealthRecordCard({
    required this.record,
    required this.onView,
    required this.onEdit,
    required this.onComplete,
    required this.onDiscontinue,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(record.status);

    return BabyBookPanel(
      key: ValueKey<String>('health-record-${record.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  record.type == PregnancyRecordType.vaccination
                      ? Icons.vaccines_outlined
                      : Icons.medication_outlined,
                  color: AppColors.brandText,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.type.label} • ${babyBookFormatDate(record.recordDate)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey<String>('health-record-menu-${record.id}'),
                tooltip: 'Record actions',
                color: Colors.white,
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      onEdit();
                    case 'complete':
                      onComplete();
                    case 'discontinue':
                      onDiscontinue();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit record')),
                  PopupMenuItem(
                    value: 'complete',
                    child: Text('Mark as completed'),
                  ),
                  PopupMenuItem(
                    value: 'discontinue',
                    child: Text('Mark as discontinued'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text('Delete record')),
                ],
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              BabyBookStatusPill(
                label: record.status.label,
                color: style.$1,
                icon: style.$2,
              ),
              if (record.isSample)
                const BabyBookStatusPill(
                  label: 'SAMPLE DATA',
                  color: AppColors.brandText,
                  icon: Icons.science_outlined,
                ),
            ],
          ),
          if (record.providerName?.isNotEmpty == true ||
              record.healthFacility?.isNotEmpty == true) ...[
            const SizedBox(height: 11),
            Text(
              [record.providerName, record.healthFacility]
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' • '),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 9,
                height: 1.4,
              ),
            ),
          ],
          if (record.dosage?.isNotEmpty == true ||
              record.frequency?.isNotEmpty == true) ...[
            const SizedBox(height: 7),
            Text(
              [record.dosage, record.frequency]
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' • '),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (record.nextScheduledDate != null) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: AppColors.brandText,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Next schedule: ${babyBookFormatDate(record.nextScheduledDate!)}',
                    style: const TextStyle(
                      color: AppColors.brandText,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onView,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandText,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text(
                'View record',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthRecordEmptyState extends StatelessWidget {
  final PregnancyRecordType type;
  final VoidCallback onAdd;

  const _HealthRecordEmptyState({required this.type, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return BabyBookPanel(
      child: Column(
        children: [
          Icon(
            type == PregnancyRecordType.vaccination
                ? Icons.vaccines_outlined
                : Icons.medication_outlined,
            color: AppColors.brandPrimary,
            size: 34,
          ),
          const SizedBox(height: 9),
          Text(
            type == PregnancyRecordType.vaccination
                ? 'No provider-recorded vaccination has been added yet.'
                : 'No prescribed supplement has been added yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Add Record'),
          ),
        ],
      ),
    );
  }
}

class _PregnancyHealthRecordForm extends StatefulWidget {
  final PregnancyHealthRecord? existing;
  final PregnancyRecordType initialType;

  const _PregnancyHealthRecordForm({
    required this.existing,
    required this.initialType,
  });

  @override
  State<_PregnancyHealthRecordForm> createState() =>
      _PregnancyHealthRecordFormState();
}

class _PregnancyHealthRecordFormState
    extends State<_PregnancyHealthRecordForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _frequencyController;
  late final TextEditingController _providerController;
  late final TextEditingController _facilityController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _notesController;
  late PregnancyRecordType _type;
  late PregnancyRecordStatus _status;
  late DateTime _recordDate;
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _nextScheduledDate;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    final record = widget.existing;
    _type = record?.type ?? widget.initialType;
    _status = record?.status ?? PregnancyRecordStatus.active;
    _recordDate = record?.recordDate ?? DateTime.now();
    _startDate = record?.startDate;
    _endDate = record?.endDate;
    _nextScheduledDate = record?.nextScheduledDate;
    _nameController = TextEditingController(text: record?.name ?? '');
    _dosageController = TextEditingController(text: record?.dosage ?? '');
    _frequencyController = TextEditingController(text: record?.frequency ?? '');
    _providerController =
        TextEditingController(text: record?.providerName ?? '');
    _facilityController =
        TextEditingController(text: record?.healthFacility ?? '');
    _instructionsController =
        TextEditingController(text: record?.instructions ?? '');
    _notesController = TextEditingController(text: record?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _frequencyController.dispose();
    _providerController.dispose();
    _facilityController.dispose();
    _instructionsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<DateTime?> _pickDate(DateTime initial) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      setState(
          () => _dateError = 'End date cannot be earlier than start date.');
      return;
    }
    if (_nextScheduledDate != null &&
        _nextScheduledDate!.isBefore(_recordDate)) {
      setState(
        () => _dateError =
            'Next scheduled date cannot be earlier than the recorded date.',
      );
      return;
    }
    setState(() => _dateError = null);
    final existing = widget.existing;
    Navigator.of(context).pop(
      PregnancyHealthRecord(
        id: existing?.id ?? 'health-${DateTime.now().microsecondsSinceEpoch}',
        type: _type,
        name: _nameController.text.trim(),
        recordDate: _recordDate,
        dosage: _optional(_dosageController),
        frequency: _optional(_frequencyController),
        startDate: _startDate,
        endDate: _endDate,
        providerName: _optional(_providerController),
        healthFacility: _optional(_facilityController),
        instructions: _optional(_instructionsController),
        notes: _optional(_notesController),
        status: _status,
        nextScheduledDate: _nextScheduledDate,
        isSample: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'Add Record' : 'Edit Record',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close form',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderPrimary),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<PregnancyRecordType>(
                        key: const ValueKey('health-record-type'),
                        initialValue: _type,
                        decoration: const InputDecoration(
                          labelText: 'Record type *',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: PregnancyRecordType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _type = value);
                        },
                        validator: (value) =>
                            value == null ? 'Record type is required.' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('health-record-name'),
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Vaccination or supplement name *',
                          prefixIcon: Icon(Icons.edit_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Record name is required.'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      _DateFormField(
                        label: 'Recorded date *',
                        date: _recordDate,
                        required: true,
                        onTap: () async {
                          final picked = await _pickDate(_recordDate);
                          if (picked != null) {
                            setState(() => _recordDate = picked);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dosageController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Dosage (optional)',
                          hintText: 'As prescribed',
                          prefixIcon: Icon(Icons.straighten_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _frequencyController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Frequency (optional)',
                          hintText: 'As prescribed',
                          prefixIcon: Icon(Icons.repeat_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _DateFormField(
                              label: 'Start date',
                              date: _startDate,
                              onTap: () async {
                                final picked = await _pickDate(
                                  _startDate ?? _recordDate,
                                );
                                if (picked != null) {
                                  setState(() => _startDate = picked);
                                }
                              },
                              onClear: _startDate == null
                                  ? null
                                  : () => setState(() => _startDate = null),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DateFormField(
                              label: 'End date',
                              date: _endDate,
                              onTap: () async {
                                final picked = await _pickDate(
                                  _endDate ?? _startDate ?? _recordDate,
                                );
                                if (picked != null) {
                                  setState(() => _endDate = picked);
                                }
                              },
                              onClear: _endDate == null
                                  ? null
                                  : () => setState(() => _endDate = null),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _providerController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Healthcare provider',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _facilityController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Health facility',
                          prefixIcon: Icon(Icons.local_hospital_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _instructionsController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Provider instructions',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.list_alt_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<PregnancyRecordStatus>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          prefixIcon: Icon(Icons.flag_outlined),
                        ),
                        items: PregnancyRecordStatus.values
                            .map(
                              (status) => DropdownMenuItem(
                                value: status,
                                child: Text(status.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _status = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      _DateFormField(
                        label: 'Next scheduled date',
                        date: _nextScheduledDate,
                        onTap: () async {
                          final picked = await _pickDate(
                            _nextScheduledDate ?? _recordDate,
                          );
                          if (picked != null) {
                            setState(() => _nextScheduledDate = picked);
                          }
                        },
                        onClear: _nextScheduledDate == null
                            ? null
                            : () => setState(() => _nextScheduledDate = null),
                      ),
                      if (_dateError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _dateError!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const ValueKey('health-save-record'),
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brandPrimary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        icon: const Icon(Icons.save_outlined, size: 19),
                        label: Text(
                          widget.existing == null
                              ? 'Add provider record'
                              : 'Save changes',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateFormField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool required;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateFormField({
    required this.label,
    required this.date,
    this.required = false,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined),
          suffixIcon: onClear == null
              ? const Icon(Icons.edit_calendar_outlined, size: 18)
              : IconButton(
                  tooltip: 'Clear $label',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
        ),
        child: Text(
          date == null
              ? required
                  ? 'Select a date'
                  : 'Not set'
              : babyBookFormatDate(date!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                date == null ? AppColors.textSecondary : AppColors.textPrimary,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _RecordDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _RecordDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

(Color, IconData) _statusStyle(PregnancyRecordStatus status) {
  return switch (status) {
    PregnancyRecordStatus.upcoming => (
        const Color(0xFF6687C8),
        Icons.schedule_rounded
      ),
    PregnancyRecordStatus.active => (
        const Color(0xFF4E9D8E),
        Icons.play_circle_outline_rounded
      ),
    PregnancyRecordStatus.completed => (
        const Color(0xFF4E9D8E),
        Icons.check_circle_outline_rounded
      ),
    PregnancyRecordStatus.missed => (
        const Color(0xFFD38A43),
        Icons.event_busy_outlined
      ),
    PregnancyRecordStatus.discontinued => (
        const Color(0xFF80777B),
        Icons.stop_circle_outlined
      ),
  };
}
