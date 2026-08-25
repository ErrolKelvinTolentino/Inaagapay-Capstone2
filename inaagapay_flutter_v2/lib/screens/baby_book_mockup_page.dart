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
import '../widgets/secondary_header.dart';
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

  /// Saves a mother marking a recommended milestone done, or un-marking it.
  ///
  /// Returns false rather than throwing, so the section can put the row back
  /// the way it was and tell her — the alternative is a checkmark that exists
  /// only until she reopens the page.
  ///
  /// In preview there is no pregnancy to attach anything to, so this reports
  /// success without writing: the preview is a picture of the screen, and
  /// failing a tap there would be a lie in the other direction.
  Future<bool> _persistMilestoneMark(
    BabyGrowthMilestone milestone,
    bool markingDone,
  ) async {
    final pregnancyId = _pregnancy?.pregnancyId;
    if (_isPreview || pregnancyId == null) return true;

    if (!markingDone) {
      final entryId = milestone.entryId;
      // Nothing was ever written, so there is nothing to remove. This happens
      // when she marks and un-marks without the first write landing.
      if (entryId == null) return true;
      return _repository.unrecordPrenatalMilestone(entryId);
    }

    return _repository.recordPrenatalMilestone(
      pregnancyId: pregnancyId,
      templateKey: milestone.id,
      observedOn: DateTime.now(),
      recordedPregnancyWeek: _effectivePregnancy?.currentWeek,
    );
  }

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
            // Her care. This section is titled "Pregnancy Milestones" and
            // lists the checkups, tests and scans a pregnancy is generally
            // expected to receive, so the mother-owned catalogue is the one
            // it wants — see 20260827_pregnancy_care_milestones.
            owner: MilestoneOwner.mother,
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
          // A pushed page, so it gets a back arrow.
          //
          // This used MainHeader — the shell's top bar, built for the tabs a
          // mother lands on, which by design has no way back. The baby book is
          // only ever pushed from the Children page, so a mother who opened it
          // had no route out but the system gesture, and the bell and avatar
          // it carried were duplicates of the ones on the tab behind it.
          SecondaryHeader(
            title: 'Baby Book',
            onBack: () => Navigator.pop(context),
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
                      // One card carrying every fact about where she is:
                      // weeks, month, trimester, progress and due date.
                      //
                      // Those five were spread across three cards — a cover
                      // card, a "Your pregnancy today" stat row, and the
                      // pregnancy card inside the growth journey — so the due
                      // date appeared twice, the progress twice and the month
                      // three times before she reached anything new.
                      if (_effectivePregnancy != null)
                        Padding(
                          key: _todayKey,
                          padding: const EdgeInsets.only(bottom: 8),
                          child: PregnancyCoverCard(
                              pregnancy: _effectivePregnancy!),
                        ),
                      const SizedBox(height: 24),
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
                          onToggleCompleted: _persistMilestoneMark,
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
                      // The eight-page care guide used to sit here. It is
                      // almost entirely about a baby who has been born —
                      // first days, feeding through the first year, home
                      // safety, checkups — and this page is read by a mother
                      // who is still pregnant. It now lives in the baby book
                      // of a registered child.
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
