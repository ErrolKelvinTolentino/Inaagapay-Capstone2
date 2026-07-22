import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/baby_growth_milestone.dart';
import '../../models/pregnancy_growth_stage.dart';
import '../../theme/app_colors.dart';
import 'baby_book_section_components.dart';
import 'baby_growth_timeline.dart';

class BabyGrowthMilestonesSection extends StatefulWidget {
  final List<BabyGrowthMilestone> initialMilestones;
  final CurrentPregnancyState currentPregnancy;

  const BabyGrowthMilestonesSection({
    super.key,
    required this.initialMilestones,
    required this.currentPregnancy,
  });

  @override
  State<BabyGrowthMilestonesSection> createState() =>
      _BabyGrowthMilestonesSectionState();
}

class _BabyGrowthMilestonesSectionState
    extends State<BabyGrowthMilestonesSection> {
  late final List<BabyGrowthMilestone> _milestones;
  bool _showAllMilestones = false;

  bool get _isTwin => widget.currentPregnancy.isTwinPregnancy;

  List<BabyGrowthMilestone> get _sortedMilestones {
    final result = List<BabyGrowthMilestone>.from(_milestones);
    result.sort((a, b) {
      final aWeek = a.expectedStartWeek ?? a.recordedPregnancyWeek ?? 100;
      final bWeek = b.expectedStartWeek ?? b.recordedPregnancyWeek ?? 100;
      final weekComparison = aWeek.compareTo(bWeek);
      if (weekComparison != 0) return weekComparison;
      return _milestones.indexOf(a).compareTo(_milestones.indexOf(b));
    });
    return result;
  }

  @override
  void initState() {
    super.initState();
    _milestones = List<BabyGrowthMilestone>.from(widget.initialMilestones);
  }

  Future<void> _openForm([BabyGrowthMilestone? existing]) async {
    final saved = await showModalBottomSheet<BabyGrowthMilestone>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _MilestoneForm(
        existing: existing,
        currentWeek: widget.currentPregnancy.currentWeek,
        currentMonth: widget.currentPregnancy.currentMonth,
      ),
    );
    if (saved == null || !mounted) return;

    setState(() {
      final index = _milestones.indexWhere((item) => item.id == saved.id);
      if (index == -1) {
        _milestones.add(saved);
      } else {
        _milestones[index] = saved;
      }
    });
  }

  void _markCompleted(BabyGrowthMilestone milestone) {
    setState(() {
      final index = _milestones.indexWhere((item) => item.id == milestone.id);
      if (index != -1) {
        _milestones[index] = milestone.copyWith(
          status: BabyGrowthMilestoneStatus.completed,
          completedDate: milestone.completedDate ?? DateTime.now(),
          recordedPregnancyWeek: milestone.recordedPregnancyWeek ??
              widget.currentPregnancy.currentWeek,
          pregnancyMonth:
              milestone.pregnancyMonth ?? widget.currentPregnancy.currentMonth,
        );
      }
    });
  }

  Future<void> _confirmDelete(BabyGrowthMilestone milestone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete this milestone?'),
        content: Text(
          '“${milestone.title}” will be removed from this pregnancy timeline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep milestone'),
          ),
          FilledButton(
            key: const ValueKey<String>('milestone-confirm-delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB64E62),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(
          () => _milestones.removeWhere((item) => item.id == milestone.id));
    }
  }

  void _viewDetails(BabyGrowthMilestone milestone) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5DADF),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              milestone.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              milestone.description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.55,
              ),
            ),
            if (milestone.photoBytes != null) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(
                  milestone.photoBytes!,
                  height: 210,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _DetailRow(label: 'Category', value: milestone.category.label),
            _DetailRow(label: 'Status', value: milestone.status.label),
            if (milestone.expectedStartWeek != null)
              _DetailRow(
                label: 'General timing',
                value: milestone.expectedStartWeek == milestone.expectedEndWeek
                    ? 'Around week ${milestone.expectedStartWeek}'
                    : 'Weeks ${milestone.expectedStartWeek}–${milestone.expectedEndWeek ?? 'onward'}',
              ),
            if (milestone.recordedPregnancyWeek != null)
              _DetailRow(
                label: 'Recorded week',
                value: 'Week ${milestone.recordedPregnancyWeek}',
              ),
            if (milestone.pregnancyMonth != null)
              _DetailRow(
                label: 'Pregnancy month',
                value: 'Month ${milestone.pregnancyMonth}',
              ),
            if (milestone.completedDate != null)
              _DetailRow(
                label: 'Recorded date',
                value: babyBookFormatDate(milestone.completedDate!),
              ),
            if (milestone.note?.isNotEmpty == true)
              _DetailRow(label: 'Note', value: milestone.note!),
            if (milestone.recordedBy?.isNotEmpty == true)
              _DetailRow(label: 'Recorded by', value: milestone.recordedBy!),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _openForm(milestone);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit milestone'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPersonalMilestone = _milestones.any((item) => item.isCustom);
    final subject = _isTwin ? 'your babies' : 'your baby';
    final growthVerb = _isTwin ? 'continue' : 'continues';
    final sortedMilestones = _sortedMilestones;
    final visibleMilestones = _showAllMilestones
        ? sortedMilestones
        : sortedMilestones.take(3).toList(growable: false);

    return Semantics(
      container: true,
      label: _isTwin
          ? 'Babies growth milestones section'
          : 'Baby growth milestones section',
      child: Column(
        key: const ValueKey<String>('baby-growth-milestones-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BabyBookSectionHeader(
            eyebrow: 'PREGNANCY TIMELINE',
            title: _isTwin
                ? 'Babies’ Growth Milestones'
                : 'Baby Growth Milestones',
            description:
                'Follow recorded pregnancy moments from early pregnancy to birth preparation. The growth viewer above remains your month-by-month development guide.',
            actionLabel: 'Add Milestone',
            actionIcon: Icons.add_rounded,
            onAction: _openForm,
          ),
          if (_isTwin) ...[
            const SizedBox(height: 10),
            const BabyBookTwinPregnancyBadge(light: false),
          ],
          const SizedBox(height: 14),
          const BabyBookPictureBanner(
            key: ValueKey<String>('milestone-picture-card'),
            assetPath: 'assets/images/milestone_story_card.png',
            semanticLabel:
                'Pregnant mother recording moments in her pregnancy journal',
            eyebrow: 'YOUR PREGNANCY STORY',
            title: 'Small moments become milestones.',
            subtitle:
                'Keep meaningful changes, checkups, and memories together as the journey grows.',
          ),
          const SizedBox(height: 14),
          BabyBookPanel(
            key: const ValueKey<String>('current-growth-stage'),
            color: const Color(0xFFFFE8F1),
            borderColor: const Color(0xFFFFC5D9),
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: AppColors.brandPrimary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Text(
                        'Your Current Growth Stage',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Week ${widget.currentPregnancy.currentWeek} of approximately 40 weeks',
                  key: const ValueKey<String>('milestone-progress-label'),
                  style: const TextStyle(
                    color: AppColors.brandText,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'At this stage, $subject $growthVerb growing and developing. Movement may be noticed, body structures continue becoming more defined, and an ultrasound may be recorded depending on the healthcare plan.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'This is general educational guidance, not a medical diagnosis.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!hasPersonalMilestone) ...[
            BabyBookPanel(
              color: const Color(0xFFFFFCFD),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_outlined,
                    color: AppColors.brandPrimary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'No personal pregnancy milestone has been recorded yet.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add a personal milestone',
                    onPressed: _openForm,
                    icon: const Icon(
                      Icons.add_circle_rounded,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: BabyGrowthTimeline(
              milestones: visibleMilestones,
              onView: _viewDetails,
              onEdit: _openForm,
              onComplete: _markCompleted,
              onDelete: _confirmDelete,
            ),
          ),
          if (sortedMilestones.length > 3) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('milestone-see-all'),
                onPressed: () => setState(
                  () => _showAllMilestones = !_showAllMilestones,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandText,
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: Color(0xFFFFBCD2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: AnimatedRotation(
                  turns: _showAllMilestones ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                label: Text(
                  _showAllMilestones ? 'Show Less' : 'See All',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Expected weeks are general ranges. Record medical milestones only when confirmed by you or your healthcare provider.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              height: 1.45,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _MilestoneForm extends StatefulWidget {
  final BabyGrowthMilestone? existing;
  final int currentWeek;
  final int currentMonth;

  const _MilestoneForm({
    this.existing,
    required this.currentWeek,
    required this.currentMonth,
  });

  @override
  State<_MilestoneForm> createState() => _MilestoneFormState();
}

class _MilestoneFormState extends State<_MilestoneForm> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _titleController;
  late final TextEditingController _weekController;
  late final TextEditingController _monthController;
  late final TextEditingController _noteController;
  late final TextEditingController _recordedByController;
  late BabyGrowthMilestoneCategory _category;
  late BabyGrowthMilestoneStatus _status;
  DateTime? _date;
  Uint8List? _photoBytes;
  bool _isPickingPhoto = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _weekController = TextEditingController(
      text: (existing?.recordedPregnancyWeek ?? widget.currentWeek).toString(),
    );
    _monthController = TextEditingController(
      text: (existing?.pregnancyMonth ?? widget.currentMonth).toString(),
    );
    _noteController = TextEditingController(text: existing?.note ?? '');
    _recordedByController = TextEditingController(
      text: existing?.recordedBy ?? 'Mother',
    );
    _category =
        existing?.category ?? BabyGrowthMilestoneCategory.personalMemory;
    _status = existing?.status ?? BabyGrowthMilestoneStatus.completed;
    _date = existing?.completedDate ?? DateTime.now();
    _photoBytes = existing?.photoBytes;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _weekController.dispose();
    _monthController.dispose();
    _noteController.dispose();
    _recordedByController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_isPickingPhoto) return;
    setState(() => _isPickingPhoto = true);
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (photo != null && mounted) {
        final bytes = await photo.readAsBytes();
        if (mounted) setState(() => _photoBytes = bytes);
      }
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  String? _validateNumber(String? value, int min, int max, String label) {
    if (value == null || value.trim().isEmpty) return null;
    final number = int.tryParse(value);
    if (number == null || number < min || number > max) {
      return '$label must be between $min and $max.';
    }
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final title = _titleController.text.trim();
    final note = _noteController.text.trim();
    final existing = widget.existing;
    Navigator.of(context).pop(
      BabyGrowthMilestone(
        id: existing?.id ?? 'personal-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        description: existing?.description ??
            (note.isEmpty
                ? 'A personal pregnancy moment recorded in the Baby Book.'
                : note),
        expectedStartWeek: existing?.expectedStartWeek,
        expectedEndWeek: existing?.expectedEndWeek,
        recordedPregnancyWeek: int.tryParse(_weekController.text.trim()),
        pregnancyMonth: int.tryParse(_monthController.text.trim()),
        completedDate: _date,
        category: _category,
        status: _status,
        note: note.isEmpty ? null : note,
        photoPath: existing?.photoPath,
        photoBytes: _photoBytes,
        recordedBy: _recordedByController.text.trim().isEmpty
            ? null
            : _recordedByController.text.trim(),
        isCustom: existing?.isCustom ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5DADF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.existing == null ? 'Add Milestone' : 'Edit Milestone',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Save a personally felt moment or a milestone documented by your healthcare provider.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const ValueKey<String>('milestone-title'),
                  controller: _titleController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Milestone title *',
                    prefixIcon: Icon(Icons.auto_awesome_outlined),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Milestone title is required.'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BabyGrowthMilestoneCategory>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: BabyGrowthMilestoneCategory.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Recorded date (optional)',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    child: Text(
                      _date == null ? 'Not set' : babyBookFormatDate(_date!),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _weekController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pregnancy week',
                          prefixIcon: Icon(Icons.calendar_view_week_outlined),
                        ),
                        validator: (value) =>
                            _validateNumber(value, 1, 42, 'Week'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _monthController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Month',
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                        validator: (value) =>
                            _validateNumber(value, 1, 10, 'Month'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BabyGrowthMilestoneStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Completion status',
                    prefixIcon: Icon(Icons.task_alt_rounded),
                  ),
                  items: BabyGrowthMilestoneStatus.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _recordedByController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Recorded by (optional)',
                    hintText: 'Mother or healthcare provider',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Short note (optional)',
                    hintText: 'Baby A or Baby B only when medically recorded',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                if (_photoBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      _photoBytes!,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _photoBytes = null),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Remove photo'),
                    ),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _isPickingPhoto ? null : _pickPhoto,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: AppColors.brandText,
                    side: const BorderSide(color: Color(0xFFFFBCD2)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isPickingPhoto
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _photoBytes == null ? 'Attach a photo' : 'Replace photo',
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const ValueKey<String>('milestone-save'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save milestone'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
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
                fontSize: 10,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
