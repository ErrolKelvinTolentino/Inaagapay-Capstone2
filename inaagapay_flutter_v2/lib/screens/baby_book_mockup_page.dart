import 'dart:async';

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/baby_growth_milestone_data.dart';
import '../data/pregnancy_growth_data.dart';
import '../models/baby_growth_milestone.dart';
import '../models/baby_memory.dart';
import '../models/milestone_template.dart';
import '../models/pregnancy_growth_stage.dart';
import '../services/asset_pdf_download_service.dart';
import '../services/baby_book_repository.dart';
import 'mother/mother_pregnancy_detail_page.dart';
import '../theme/app_colors.dart';
import '../widgets/baby_memory_photo.dart';
import '../widgets/baby_book/baby_growth_milestones_section.dart';
import '../widgets/baby_book/baby_book_section_components.dart';
import '../widgets/main_header.dart';
import '../widgets/pregnancy_growth_journey.dart';
import 'baby_book_memory_gallery_page.dart';

String _t(String english, String _) => english;

class BabyBookMockupPage extends StatefulWidget {
  /// The mother whose Baby Book this is.
  ///
  /// When null the page renders the sample pregnancy — the preview mode the
  /// widget tests and the `/baby-book` route still use while the remaining
  /// sections are migrated. When set, the pregnancy sections read from the
  /// database and the sample data is not consulted at all.
  final int? motherId;

  /// Overridable so the loading and empty states can be exercised without a
  /// database. Production callers leave this null.
  @visibleForTesting
  final BabyBookRepository? repository;

  const BabyBookMockupPage({super.key, this.motherId, this.repository});

  @override
  State<BabyBookMockupPage> createState() => _BabyBookMockupPageState();
}

class _BabyBookMockupPageState extends State<BabyBookMockupPage> {
  static final Uri _dohGuideUri = Uri.parse(
    'https://www.foi.gov.ph/agencies/doh/mother-and-baby-book/',
  );
  static final Uri _whoGuideUri = Uri.parse(
    'https://www.who.int/publications/i/item/9789241550352',
  );

  final GlobalKey _todayKey = GlobalKey();
  final GlobalKey _memoriesKey = GlobalKey();
  final GlobalKey _guideKey = GlobalKey();

  String? _downloadingPdf;
  final ImagePicker _imagePicker = ImagePicker();

  BabyBookRepository get _repository =>
      widget.repository ?? const BabyBookRepository();

  /// Null in preview mode, and also for a mother with no ongoing pregnancy —
  /// the two are told apart by [_isPreview], because they must render
  /// differently. Showing a real mother a sample "20 weeks pregnant" would be
  /// alarming and false.
  CurrentPregnancyState? _pregnancy;
  List<BabyGrowthMilestone> _milestones = const [];
  bool _isLoadingPregnancy = false;

  bool get _isPreview => widget.motherId == null;

  CurrentPregnancyState? get _effectivePregnancy =>
      _isPreview ? demoCurrentPregnancy : _pregnancy;

  List<BabyGrowthMilestone> get _effectiveMilestones =>
      _isPreview ? babyGrowthMilestoneSampleData : _milestones;

  Future<void> _loadPregnancy() async {
    setState(() => _isLoadingPregnancy = true);

    final pregnancy = await _repository.loadCurrentPregnancy(widget.motherId!);

    // Milestones are keyed to a pregnancy, so there is nothing to fetch
    // without one.
    final pregnancyId = pregnancy?.pregnancyId;
    final milestones = pregnancyId == null
        ? const <BabyGrowthMilestone>[]
        : await _repository.loadPrenatalMilestones(
            pregnancyId: pregnancyId,
            currentWeek: pregnancy!.currentWeek,
            // The baby's story only. Her checkups and birth plan are the
            // Mother Book's, and showing them here is what made this page
            // duplicate the Records tab.
            owner: MilestoneOwner.baby,
          );

    if (!mounted) return;
    setState(() {
      _pregnancy = pregnancy;
      _milestones = milestones;
      _isLoadingPregnancy = false;
    });
  }

  @override
  void initState() {
    super.initState();
    // Preview mode touches no network, which is what keeps the widget tests
    // synchronous and offline.
    if (!_isPreview) _loadPregnancy();
  }

  /// Opens the deeper page about her own body — risk level, warning signs,
  /// checklists, nutrition. Reached from inside this book rather than from a
  /// competing card on Home.
  void _openMyCare() {
    final p = _effectivePregnancy;
    if (p == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PregnancyDetailPage(
          week: p.currentWeek,
          trimester: p.trimester,
          dueDate: DateFormat('MMMM d, y').format(p.estimatedDueDate),
          weeksLeft: (40 - p.currentWeek).clamp(0, 40),
          babySize: '',
          babyWeight: '',
          firstName: '',
          riskLevel: '',
          fetalCount: p.numberOfBabies,
          pregnancyId: p.pregnancyId ?? 0,
          riskFactors: const [],
          suggestedActions: const [],
        ),
      ),
    );
  }

  final List<BabyMemory> _memories = <BabyMemory>[
    BabyMemory(
      id: 'sample-ultrasound',
      title: 'Our first ultrasound ✨',
      caption: 'The first little glimpse of our growing baby.',
      date: DateTime(2026, 7, 18),
      assetPath: 'assets/images/ultrasound.png',
    ),
    BabyMemory(
      id: 'sample-bump',
      title: 'Five-month bump photo',
      caption: 'Halfway through our pregnancy journey together.',
      date: DateTime(2026, 7, 20),
      assetPath: 'assets/images/pregnant1.png',
    ),
  ];

  Future<void> _openGuide(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'The source link cannot be opened right now.',
              'Hindi mabuksan ang source link sa ngayon.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _downloadPdf({
    required String assetPath,
    required String fileName,
    required String label,
  }) async {
    if (_downloadingPdf != null) return;
    setState(() => _downloadingPdf = fileName);

    try {
      final result = await downloadAssetPdf(
        assetPath: assetPath,
        fileName: fileName,
      );
      if (!mounted) return;

      final message = result.handledByBrowser
          ? _t(
              '$label download started. Check your browser downloads.',
              'Sinimulan na ang pag-download ng $label. Tingnan ang downloads ng browser.',
            )
          : _t(
              '$label saved to ${result.destination}',
              'Nai-save ang $label sa ${result.destination}',
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'The PDF could not be downloaded. Please try again.',
              'Hindi ma-download ang PDF. Pakisubukan muli.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingPdf = null);
    }
  }

  void _showMockupMessage(String englishFeature, String filipinoFeature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            '$englishFeature — mockup preview only for now.',
            '$filipinoFeature — mockup preview lamang muna.',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addMemory() async {
    try {
      final selectedPhoto = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (selectedPhoto == null) return;

      final imageBytes = await selectedPhoto.readAsBytes();
      if (!mounted) return;

      final titleController = TextEditingController(text: 'A beautiful memory');
      final captionController = TextEditingController();
      final details = await showDialog<_MemoryDetails>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text(
              'Add this memory',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      imageBytes,
                      width: double.infinity,
                      height: 130,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Memory title',
                      hintText: 'Ultrasound, bump photo…',
                      prefixIcon: Icon(Icons.favorite_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: captionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Short story',
                      hintText: 'What made this moment special?',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    _MemoryDetails(
                      title: titleController.text.trim().isEmpty
                          ? 'A beautiful memory'
                          : titleController.text.trim(),
                      caption: captionController.text.trim().isEmpty
                          ? 'A special moment in Baby’s growing story.'
                          : captionController.text.trim(),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                label: const Text('Save memory'),
              ),
            ],
          );
        },
      );
      titleController.dispose();
      captionController.dispose();

      if (details == null || !mounted) return;
      setState(() {
        _memories.insert(
          0,
          BabyMemory(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: details.title,
            caption: details.caption,
            date: DateTime.now(),
            imageBytes: imageBytes,
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo added to the Memory Gallery.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The photo could not be added. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openMemoryGallery() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BabyBookMemoryGalleryPage(
          memories: _memories,
          onAddMemory: _addMemory,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAFC),
      body: Column(
        children: [
          MainHeader(
            title: 'Baby Book',
            onNotificationTap: () => _showMockupMessage('Notifications', ''),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BabyCoverCard(
                          key: _todayKey, pregnancy: _effectivePregnancy),
                      const SizedBox(height: 24),
                      const _SectionHeading(
                        eyebrow: 'TODAY',
                        title: 'Your pregnancy today',
                      ),
                      const SizedBox(height: 12),
                      _BabyStatsCard(pregnancy: _effectivePregnancy),
                      const SizedBox(height: 14),
                      _AppointmentCard(
                        onTap: () =>
                            _showMockupMessage('Appointment details', ''),
                      ),
                      const SizedBox(height: 32),
                      if (_isLoadingPregnancy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_effectivePregnancy == null)
                        // A mother between pregnancies is a normal state, not
                        // an error — and never a reason to show her the sample
                        // pregnancy, which would tell her she is 20 weeks along.
                        const _NoOngoingPregnancyNotice()
                      else ...[
                        PregnancyGrowthJourney(
                          currentPregnancy: _effectivePregnancy!,
                          stages: pregnancyGrowthStages,
                        ),
                        const SizedBox(height: 34),
                        BabyGrowthMilestonesSection(
                          currentPregnancy: _effectivePregnancy!,
                          initialMilestones: _effectiveMilestones,
                        ),
                      ],
                      // Her vaccines and supplements used to sit here. They
                      // are her care, not the baby's story, and records_screen
                      // already reads given_medications — so this was both a
                      // category error and a second copy. They belong to the
                      // Mother Book.
                      // Her own care, one level in rather than behind a
                      // second door on Home. Before birth "my pregnancy" and
                      // "my baby" are one experience; the split only becomes
                      // meaningful afterwards, when the baby is a separate
                      // person with a book of their own.
                      if (_effectivePregnancy != null) ...[
                        const SizedBox(height: 34),
                        _MyCareRow(onTap: _openMyCare),
                      ],

                      const SizedBox(height: 34),
                      _MemoryCard(
                        key: _memoriesKey,
                        memories: _memories,
                        onAddMemory: _addMemory,
                        onOpenGallery: _openMemoryGallery,
                      ),
                      const SizedBox(height: 34),
                      _BabyCareGuideBook(key: _guideKey),
                      const SizedBox(height: 34),
                      _GuideReferencesCard(
                        onOpenDoh: () => _openGuide(_dohGuideUri),
                        onOpenWho: () => _openGuide(_whoGuideUri),
                        onDownloadDoh: () => _downloadPdf(
                          assetPath: 'assets/pdf/DOH.pdf',
                          fileName: 'DOH-Mother-and-Baby-Book.pdf',
                          label: 'DOH PDF',
                        ),
                        onDownloadWho: () => _downloadPdf(
                          assetPath: 'assets/pdf/WHO.pdf',
                          fileName: 'WHO-Home-Based-Records-Guide.pdf',
                          label: 'WHO PDF',
                        ),
                        downloadingDoh:
                            _downloadingPdf == 'DOH-Mother-and-Baby-Book.pdf',
                        downloadingWho: _downloadingPdf ==
                            'WHO-Home-Based-Records-Guide.pdf',
                      ),
                      const SizedBox(height: 18),
                      const _HealthDisclaimer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when a mother has no ongoing pregnancy on record.
///
/// Deliberately not an error and not empty space. She may be between
/// pregnancies, or her record may simply not be set up yet, and neither is
/// something she did wrong — so this says what is missing and who can add it,
/// without alarming her.
class _NoOngoingPregnancyNotice extends StatelessWidget {
  const _NoOngoingPregnancyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.favorite_outline,
              size: 40, color: AppColors.brandPrimary.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            _t('No pregnancy recorded yet', 'Wala pang naitalang pagbubuntis'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              'Your pregnancy timeline will appear here once your midwife '
                  'records it at the health center.',
              'Lalabas dito ang iyong pregnancy timeline kapag naitala na ito '
                  'ng iyong midwife sa health center.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryDetails {
  final String title;
  final String caption;

  const _MemoryDetails({required this.title, required this.caption});
}

class _BabyCoverCard extends StatelessWidget {
  const _BabyCoverCard({super.key, this.pregnancy});

  /// Null when there is no ongoing pregnancy. The card then shows the book's
  /// title without a gestational age, rather than a number belonging to
  /// nobody.
  final CurrentPregnancyState? pregnancy;

  @override
  Widget build(BuildContext context) {
    return BabyBookPictureCardShell(
      key: const ValueKey<String>('pregnancy-cover-picture-card'),
      assetPath: 'assets/images/mother_baby_hero.png',
      semanticLabel: 'Mother holding her baby in the pregnancy story cover',
      height: 196,
      imageKey: const ValueKey<String>('pregnancy-cover-artwork'),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 235),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR PREGNANCY',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                if (pregnancy != null)
                  const Text(
                    'Currently',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  pregnancy == null
                      ? 'Your Baby Book'
                      : '${pregnancy!.currentWeek} Weeks Pregnant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.45,
                  ),
                ),
                const SizedBox(height: 8),
                if (pregnancy != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.pregnant_woman_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Month ${pregnancy!.currentMonth} • ${pregnancy!.trimester}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.94),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  'Your baby is still growing inside the womb.',
                  maxLines: 2,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.35,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
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

class _SectionHeading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  color: AppColors.brandText,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandText,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              actionLabel!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _BabyStatsCard extends StatelessWidget {
  const _BabyStatsCard({this.pregnancy});

  final CurrentPregnancyState? pregnancy;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
      child: Row(
        children: [
          // All three were hardcoded: 'Dec 8, 2026' and '50%' never touched
          // the pregnancy at all, so a real mother was shown a fabricated due
          // date beside her own week. Same failure as the sample "20 Weeks
          // Pregnant" that leaked earlier — a page half-migrated to real data
          // is worse than one honestly full of samples.
          Expanded(
            child: _StatItem(
              icon: Icons.calendar_month_rounded,
              value: pregnancy == null
                  ? '—'
                  : DateFormat('MMM d, y').format(pregnancy!.estimatedDueDate),
              label: 'Estimated due date',
              color: const Color(0xFFFF68A5),
            ),
          ),
          const _VerticalDivider(),
          Expanded(
            child: _StatItem(
              icon: Icons.timelapse_rounded,
              // Was "Current month", which the cover card already states.
              // Weeks remaining is the one thing on this card she cannot read
              // anywhere else on the page.
              value: pregnancy == null
                  ? '—'
                  : '${(40 - pregnancy!.currentWeek).clamp(0, 40)}',
              label: 'Weeks to go',
              color: const Color(0xFF68CBB8),
            ),
          ),
          const _VerticalDivider(),
          Expanded(
            child: _StatItem(
              icon: Icons.donut_large_rounded,
              value: pregnancy == null
                  ? '—'
                  : '${(pregnancy!.pregnancyProgress * 100).round()}%',
              label: 'Pregnancy progress',
              color: const Color(0xFFFFA85A),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(height: 9),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 58, color: AppColors.borderPrimary);
  }
}

class _AppointmentCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AppointmentCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF0F6),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: AppColors.brandPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next prenatal checkup',
                      style: const TextStyle(
                        color: AppColors.brandText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _t('July 28 • 9:30 AM', 'Hulyo 28 • 9:30 AM'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Barangay Health Center',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.brandText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryCard extends StatefulWidget {
  final List<BabyMemory> memories;
  final Future<void> Function() onAddMemory;
  final VoidCallback onOpenGallery;

  const _MemoryCard({
    super.key,
    required this.memories,
    required this.onAddMemory,
    required this.onOpenGallery,
  });

  @override
  State<_MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<_MemoryCard> {
  Timer? _slideTimer;
  int _currentIndex = 0;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _scheduleSlideshow();
  }

  @override
  void didUpdateWidget(covariant _MemoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentIndex >= widget.memories.length) _currentIndex = 0;
    _scheduleSlideshow();
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    super.dispose();
  }

  void _scheduleSlideshow() {
    _slideTimer?.cancel();
    if (!_isPlaying || widget.memories.length < 2) return;
    _slideTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.memories.length < 2) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.memories.length;
      });
    });
  }

  void _toggleSlideshow() {
    setState(() => _isPlaying = !_isPlaying);
    _scheduleSlideshow();
  }

  void _showAdjacentMemory(int direction) {
    if (widget.memories.length < 2) return;
    setState(() {
      _currentIndex = (_currentIndex + direction + widget.memories.length) %
          widget.memories.length;
    });
    _scheduleSlideshow();
  }

  @override
  Widget build(BuildContext context) {
    final hasMemories = widget.memories.isNotEmpty;
    final memory = hasMemories ? widget.memories[_currentIndex] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          eyebrow: 'PRECIOUS MEMORIES',
          title: 'Our favorite moment',
          actionLabel: 'Add photo',
          onAction: widget.onAddMemory,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFFFE2ED)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF69243F).withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: hasMemories
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 190,
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFF0F6), Color(0xFFFFE4EF)],
                        ),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 600),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: BabyMemoryPhoto(
                              key: ValueKey<String>(memory!.id),
                              memory: memory,
                              fit: memory.assetPath == 'assets/images/baby.png'
                                  ? BoxFit.contain
                                  : BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            left: 10,
                            top: 0,
                            bottom: 0,
                            child: _MemoryArrowButton(
                              tooltip: 'Previous memory',
                              icon: Icons.chevron_left_rounded,
                              onTap: widget.memories.length < 2
                                  ? null
                                  : () => _showAdjacentMemory(-1),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 0,
                            bottom: 0,
                            child: _MemoryArrowButton(
                              tooltip: 'Next memory',
                              icon: Icons.chevron_right_rounded,
                              onTap: widget.memories.length < 2
                                  ? null
                                  : () => _showAdjacentMemory(1),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                onTap: widget.memories.length < 2
                                    ? null
                                    : _toggleSlideshow,
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        size: 14,
                                        color: AppColors.brandText,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'SLIDESHOW ${_currentIndex + 1}/${widget.memories.length}',
                                        style: const TextStyle(
                                          color: AppColors.brandText,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 10,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                widget.memories.length,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: index == _currentIndex ? 15 : 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: index == _currentIndex
                                        ? AppColors.brandPrimary
                                        : Colors.white.withValues(alpha: 0.82),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x22000000),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 15, 4, 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Column(
                                key: ValueKey<String>('copy-${memory.id}'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    memory.title,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    memory.caption,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            memory.shortDate,
                            style: const TextStyle(
                              color: AppColors.brandText,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('view-memory-gallery'),
                        onPressed: widget.onOpenGallery,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brandText,
                          side: const BorderSide(color: Color(0xFFFFC7DD)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: Text(
                          'View gallery • ${widget.memories.length} photos',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : _EmptyMemoryCard(onAddMemory: widget.onAddMemory),
        ),
      ],
    );
  }
}

class _MemoryArrowButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  const _MemoryArrowButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.88),
          foregroundColor: AppColors.brandText,
          disabledForegroundColor: AppColors.textSecondary,
          minimumSize: const Size(36, 36),
        ),
        icon: Icon(icon, size: 22),
      ),
    );
  }
}

class _EmptyMemoryCard extends StatelessWidget {
  final Future<void> Function() onAddMemory;

  const _EmptyMemoryCard({required this.onAddMemory});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.add_photo_alternate_outlined,
              color: AppColors.brandPrimary,
              size: 44,
            ),
            const SizedBox(height: 10),
            const Text(
              'Add Baby’s first memory',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAddMemory,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Choose photo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BabyCareGuideBook extends StatefulWidget {
  const _BabyCareGuideBook({super.key});

  static const List<_GuidePageData> _pages = [
    _GuidePageData(
      number: 1,
      icon: Icons.auto_stories_rounded,
      imagePath: 'assets/images/baby_guide_page_1.png',
      title: 'How to use this baby book',
      takeaway: 'Bring this book to every visit.',
      paragraphs: [
        'Keep this Baby Book where every caregiver can find it. Read it together, write down your baby’s growth, vaccines, checkups and special moments, and bring it to every visit so you can discuss each entry with a doctor, nurse, midwife or barangay health worker.',
        'The record belongs with your family, but it works alongside the clinic’s records—not as a replacement for them. Use the questions and notes pages to prepare for appointments, and ask a health worker whenever an instruction is unclear.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF p. 4 • WHO guideline: pp. 9, 21–22',
      accent: Color(0xFFFF68A5),
    ),
    _GuidePageData(
      number: 2,
      icon: Icons.child_friendly_rounded,
      imagePath: 'assets/images/baby_guide_page_2.png',
      title: 'Baby’s first days',
      takeaway: 'Hold baby skin-to-skin and feed early.',
      paragraphs: [
        'After birth, keep baby warm with immediate skin-to-skin contact when possible and begin breastfeeding early. Colostrum is baby’s important first milk. The DOH guide also recommends delaying the first bath for about 24 hours while keeping baby clean, warm and close.',
        'Before going home, ask about the newborn examination, newborn screening, vitamin K, eye care, BCG and hepatitis B vaccination. Register the birth certificate within 30 days, then keep the official details and health results together in this book.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 5, 34–37',
      accent: Color(0xFF8E7CC3),
    ),
    _GuidePageData(
      number: 3,
      icon: Icons.restaurant_rounded,
      imagePath: 'assets/images/baby_guide_page_3.png',
      title: 'Feeding through the first year',
      takeaway: 'Only breast milk until six months.',
      paragraphs: [
        'From birth through six months, give only breast milk—no other food or water—unless a qualified health professional gives different advice for your baby. Feed responsively by noticing early hunger and fullness cues. If feeding is painful or difficult, ask the health center for support.',
        'At about six months, begin safe and nutritious complementary food while continuing breastfeeding. Start with soft mashed food in small amounts, then gradually offer thicker textures, finger foods and varied family foods as baby develops. Use fresh ingredients, sit with baby during meals and never force-feed.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 21–23, 51, 57–60, 68',
      accent: Color(0xFFF29B61),
    ),
    _GuidePageData(
      number: 4,
      icon: Icons.health_and_safety_rounded,
      imagePath: 'assets/images/baby_guide_page_4.png',
      title: 'Make every space safer',
      takeaway: 'Keep baby within reach, always.',
      paragraphs: [
        'A baby needs an attentive adult nearby. For sleep, place baby on a safe, firm sleep surface and keep pillows, loose blankets and soft objects away. Prevent falls, and keep hot liquids, medicines, cleaning products, matches, plastic bags, cords and small choking hazards locked away or out of reach.',
        'Choose age-appropriate toys and supervise all play. Use an appropriate child restraint when travelling, never leave a child alone in a vehicle, and stay within reach around a bath, pool, river or any open water—even for a moment. Keep baby away from tobacco smoke.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 13–17',
      accent: Color(0xFF4B8FD8),
    ),
    _GuidePageData(
      number: 5,
      icon: Icons.soap_rounded,
      imagePath: 'assets/images/baby_guide_page_5.png',
      title: 'Clean hands, food and surroundings',
      takeaway: 'Wash hands before every feed.',
      paragraphs: [
        'Wash hands with soap and safe water for at least 20 seconds before preparing food or feeding baby, and after using the toilet or changing a diaper. Let hands air-dry or use a clean towel. Dispose of stool safely, clean reusable diaper materials carefully and wash the child’s hands too.',
        'Prepare food with clean tools and safe water, keep raw and cooked food separate, cook food thoroughly and protect it from pests. A clean feeding area and safely grown or selected food help make everyday nutrition safer.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 24–29',
      accent: Color(0xFF54B6A5),
    ),
    _GuidePageData(
      number: 6,
      icon: Icons.show_chart_rounded,
      imagePath: 'assets/images/baby_guide_page_6.png',
      title: 'Follow growth and development',
      takeaway: 'Every child grows at their own pace.',
      paragraphs: [
        'Record weight and length during checkups and review the growth chart with a health worker. Development includes movement, hand skills, self-help, language, thinking, and social-emotional skills. The examples in this book are guides, not strict deadlines, because every child develops at an individual pace.',
        'Help development every day through warm, responsive care. Talk, sing, smile, read and play using clean, safe objects. Notice what interests your child, praise new attempts and write down new skills or concerns so they can be discussed early.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 32–33, 38, 41, 58, 74, 88',
      accent: Color(0xFFEE7E9D),
    ),
    _GuidePageData(
      number: 7,
      icon: Icons.medical_services_rounded,
      imagePath: 'assets/images/baby_guide_page_7.png',
      title: 'Checkups, vaccines and warning signs',
      takeaway: 'Do not wait if baby seems unwell.',
      paragraphs: [
        'The DOH booklet lists routine visits for the newborn period, 3–5 days, and months 1, 2, 4, 6, 9 and 12; then months 15, 18, 24 and 30, followed by annual visits from ages 3 to 10. Bring this book each time and ask the health worker to update growth, findings, vaccines and the return date.',
        'Do not wait for a scheduled visit if baby has trouble breathing, blue or gray skin, fever, seizures, signs of dehydration, poor feeding, unusual sleepiness or another sudden worrying change. Seek prompt care from a health facility. Follow the current national vaccine schedule given by your health center because schedules may be updated.',
      ],
      source: 'DOH/UNICEF Baby Book: PDF pp. 6, 30–31, 126',
      accent: Color(0xFFE06B65),
    ),
    _GuidePageData(
      number: 8,
      icon: Icons.diversity_1_rounded,
      imagePath: 'assets/images/baby_guide_page_8.png',
      title: 'Care is a team effort',
      takeaway: 'You do not have to do this alone.',
      paragraphs: [
        'Caring for a child takes a village. List the relatives, friends, neighbors and community workers who can offer practical or emotional support. Share the baby’s routines and important instructions with trusted caregivers, and encourage them to record useful observations in the same place.',
        'WHO recommends home-based records to improve communication, care-seeking and support at home. Keep personal health information private, allow only trusted people to view it, and remember that written education works best when it is paired with continuing care and conversation with trained health workers.',
      ],
      source:
          'DOH/UNICEF Baby Book: PDF pp. 4, 10 • WHO guideline: pp. 9, 21–22',
      accent: Color(0xFF9A76B9),
    ),
  ];

  @override
  State<_BabyCareGuideBook> createState() => _BabyCareGuideBookState();
}

class _BabyCareGuideBookState extends State<_BabyCareGuideBook> {
  int _currentPageIndex = 0;

  void _showPreviousPage() {
    if (_currentPageIndex == 0) return;
    setState(() => _currentPageIndex--);
  }

  void _showNextPage() {
    if (_currentPageIndex == _BabyCareGuideBook._pages.length - 1) return;
    setState(() => _currentPageIndex++);
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = _BabyCareGuideBook._pages[_currentPageIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          eyebrow: 'BABY CARE GUIDE',
          title: 'Read the book, page by page',
        ),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFEFF5), Color(0xFFFFF9F1)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFFDCE9)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GuideBookIcon(),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ONE CONTINUOUS BOOK',
                      style: TextStyle(
                        color: AppColors.brandText,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Use the Back and Next arrows to read all eight pages. Each page turns official DOH and WHO guidance into a short, readable family instruction.',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
                child: child,
              ),
            );
          },
          child: _GuidePaperPage(
            key: ValueKey<int>(currentPage.number),
            data: currentPage,
          ),
        ),
        const SizedBox(height: 16),
        _GuidePageNavigation(
          currentPage: _currentPageIndex + 1,
          totalPages: _BabyCareGuideBook._pages.length,
          onPrevious: _currentPageIndex == 0 ? null : _showPreviousPage,
          onNext: _currentPageIndex == _BabyCareGuideBook._pages.length - 1
              ? null
              : _showNextPage,
        ),
      ],
    );
  }
}

class _GuidePageNavigation extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _GuidePageNavigation({
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF3E4EA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69243F).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: onPrevious,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandText,
              disabledForegroundColor: AppColors.textSecondary,
              side: BorderSide(
                color: onPrevious == null
                    ? const Color(0xFFEAEAEA)
                    : const Color(0xFFFFC5DC),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text(
              'Back',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Page $currentPage of $totalPages',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(totalPages, (index) {
                    final isCurrent = index == currentPage - 1;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: isCurrent ? 13 : 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppColors.brandPrimary
                            : const Color(0xFFFFD8E7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFFD5E5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Next',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                SizedBox(width: 5),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidePageData {
  final int number;
  final IconData icon;
  final String imagePath;
  final String title;

  /// The one line to take away, for a mother who reads no further.
  ///
  /// Every page is two paragraphs of 45–55 words — around 1,100 words across
  /// the book — written in the register of a public-health booklet. That is a
  /// lot to ask of someone reading on a phone, in a second language, possibly
  /// with a baby in the other arm. Each takeaway is drawn from the paragraphs
  /// beneath it and adds nothing to them; it is a way in, not a replacement.
  final String takeaway;

  final List<String> paragraphs;
  final String source;
  final Color accent;

  const _GuidePageData({
    required this.number,
    required this.icon,
    required this.imagePath,
    required this.title,
    required this.takeaway,
    required this.paragraphs,
    required this.source,
    required this.accent,
  });
}

class _GuideBookIcon extends StatelessWidget {
  const _GuideBookIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.brandPrimary,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(7),
          right: Radius.circular(13),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 27),
    );
  }
}

class _GuidePaperPage extends StatelessWidget {
  final _GuidePageData data;

  const _GuidePaperPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEDE4D7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B4632).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: data.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: data.accent.withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            'PAGE ${data.number}',
                            style: TextStyle(
                              color: data.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(data.icon, color: data.accent, size: 23),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      data.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Georgia',
                        fontSize: 21,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 13),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: AspectRatio(
                        aspectRatio: 2,
                        child: Image.asset(
                          data.imagePath,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: data.accent.withValues(alpha: 0.08),
                              alignment: Alignment.center,
                              child: Icon(
                                data.icon,
                                color: data.accent,
                                size: 40,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    // The takeaway, before the prose.
                    //
                    // A mother who reads only this has still got the page.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: data.accent.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.push_pin_rounded,
                              size: 15, color: data.accent),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              data.takeaway,
                              style: TextStyle(
                                color: data.accent,
                                fontSize: 14.5,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    for (var index = 0;
                        index < data.paragraphs.length;
                        index++) ...[
                      Text(
                        data.paragraphs[index],
                        // Ragged right, not justified.
                        //
                        // Justifying a narrow column stretches the spaces to
                        // force each line flush, which opens rivers of white
                        // down the paragraph and gives the eye nothing to track
                        // — it is measurably harder to read, and hardest for
                        // people who already read slowly. On a phone-width
                        // column of 50-word paragraphs it was the worst
                        // possible setting.
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                          color: Color(0xFF544C45),
                          fontFamily: 'Georgia',
                          // 13pt serif on a low-density screen is small. The
                          // book feel is worth keeping; the strain is not.
                          fontSize: 14.5,
                          height: 1.7,
                        ),
                      ),
                      if (index != data.paragraphs.length - 1)
                        const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 17),
                    Container(height: 1, color: const Color(0xFFEDE4D7)),
                    const SizedBox(height: 4),
                    // The citation, folded away.
                    //
                    // "SOURCE NOTES • DOH/UNICEF Baby Book: PDF pp. 32–33, 38,
                    // 41, 58, 74, 88" sat open at the foot of all eight pages.
                    // A source should be available — a mother is entitled to
                    // know where advice about her baby comes from — but page
                    // numbers into a PDF she has never seen are apparatus, not
                    // information, and they closed every page on a line she
                    // could not use.
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          'Where this comes from',
                          style: TextStyle(
                            color: data.accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding:
                            const EdgeInsets.only(bottom: 6),
                        dense: true,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              data.source,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideReferencesCard extends StatelessWidget {
  final VoidCallback onOpenDoh;
  final VoidCallback onOpenWho;
  final VoidCallback onDownloadDoh;
  final VoidCallback onDownloadWho;
  final bool downloadingDoh;
  final bool downloadingWho;

  const _GuideReferencesCard({
    required this.onOpenDoh,
    required this.onOpenWho,
    required this.onDownloadDoh,
    required this.onDownloadWho,
    required this.downloadingDoh,
    required this.downloadingWho,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          eyebrow: _t('GUIDE REFERENCES', 'PINAGBATAYANG GABAY'),
          title: _t(
            'Read or download the official guides',
            'Basahin o i-download ang official guides',
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _t(
            'The pregnancy guidance and Baby Book reader were informed by these maternal and child health references.',
            '',
          ),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        _ReferenceTile(
          badge: 'DOH',
          badgeColor: AppColors.brandPrimary,
          title: 'Mother and Baby Book',
          organization: _t(
            'Department of Health • Philippines',
            'Kagawaran ng Kalusugan • Pilipinas',
          ),
          description: _t(
            'Primary local reference for a mother-and-baby home health record.',
            'Pangunahing lokal na sanggunian para sa health record ng ina at sanggol sa tahanan.',
          ),
          urlLabel: 'foi.gov.ph/agencies/doh/mother-and-baby-book',
          onOpenSource: onOpenDoh,
          onDownload: onDownloadDoh,
          isDownloading: downloadingDoh,
        ),
        const SizedBox(height: 10),
        _ReferenceTile(
          badge: 'WHO',
          badgeColor: const Color(0xFF4B8FD8),
          title: 'Home-based records for maternal, newborn & child health',
          organization: _t(
            'World Health Organization',
            'Pandaigdigang Organisasyon sa Kalusugan',
          ),
          description: _t(
            'Guidance for child health books that complement facility records.',
            'Gabay para sa child health books na umaakma sa records ng health facility.',
          ),
          urlLabel: 'who.int/publications/i/item/9789241550352',
          onOpenSource: onOpenWho,
          onDownload: onDownloadWho,
          isDownloading: downloadingWho,
        ),
      ],
    );
  }
}

class _ReferenceTile extends StatelessWidget {
  final String badge;
  final Color badgeColor;
  final String title;
  final String organization;
  final String description;
  final String urlLabel;
  final VoidCallback onOpenSource;
  final VoidCallback onDownload;
  final bool isDownloading;

  const _ReferenceTile({
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.organization,
    required this.description,
    required this.urlLabel,
    required this.onOpenSource,
    required this.onDownload,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: badgeColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  organization,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: onOpenSource,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            urlLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.brandText,
                              fontSize: 9,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.brandText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 16,
                          color: badgeColor,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isDownloading ? null : onDownload,
                    style: FilledButton.styleFrom(
                      backgroundColor: badgeColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: badgeColor.withValues(
                        alpha: 0.45,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: isDownloading
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      isDownloading
                          ? _t('Downloading…', 'Dina-download…')
                          : _t('Download PDF', 'I-download ang PDF'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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

class _HealthDisclaimer extends StatelessWidget {
  const _HealthDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFE3A8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFD78C28),
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _t(
                'This is a UI mockup. General pregnancy and health information does not replace advice or assessment from your doctor, midwife, or health worker.',
                '',
              ),
              style: const TextStyle(
                color: Color(0xFF8A632D),
                fontSize: 10,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _WhiteCard({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF8EEF2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69243F).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Way into the deeper page about the mother's own care.
///
/// Sits inside the pregnancy book rather than as a second banner on Home.
/// Two doors to "my pregnancy" made a mother choose between them without
/// knowing what was behind either.
class _MyCareRow extends StatelessWidget {
  const _MyCareRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BabyBookPanel(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded,
                  color: AppColors.brandPrimary, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('Your body and your care', 'Ang iyong katawan at pag-aalaga'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandText,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _t('Changes, warning signs, and checklists',
                        'Mga pagbabago, babala, at checklist'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: Colors.grey.shade600,
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
}
