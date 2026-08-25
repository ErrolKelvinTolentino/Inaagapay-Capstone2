import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/baby_growth_milestone_data.dart';
import '../data/pregnancy_growth_data.dart';
import '../models/baby_growth_milestone.dart';
import '../models/baby_memory.dart';
import '../models/milestone_template.dart';
import '../models/pregnancy_growth_stage.dart';
import '../services/asset_pdf_download_service.dart';
import '../services/baby_book_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/baby_memory_photo.dart';
import '../widgets/baby_book/baby_growth_milestones_section.dart';
import '../widgets/baby_book/memory_details_dialog.dart';
import '../widgets/baby_book/references_panel.dart';
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
  final GlobalKey _todayKey = GlobalKey();
  final GlobalKey _memoriesKey = GlobalKey();

  /// Whether the photo memories section is shown.
  ///
  /// Off while Supabase Storage is set up. Uploading returned "Bucket not
  /// found", so every attempt ended in "The photo could not be saved" — a
  /// feature that cannot succeed is worse on the page than absent, because a
  /// mother spends time on it and gets nothing back.
  ///
  /// Everything behind it is intact and tested: `saveMemory` and
  /// `loadMemories` in BabyBookRepository, the gallery page, the details
  /// dialog. Turning this back on is the whole job once a public bucket
  /// exists — see the bucket candidates in BabyBookRepository.
  ///
  /// Deliberately not `const`: a const false would make the block below dead
  /// code, and the analyzer would start reporting the parts of a working
  /// feature as unused.
  // ignore: prefer_final_fields
  bool _memoriesEnabled = false;

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

    // Her own photos, which nothing was reading before: the gallery rendered
    // the two sample images for every account, and a photo she added lived
    // only until the page was disposed.
    final memories = pregnancyId == null
        ? const <BabyMemory>[]
        : await _repository.loadMemories(pregnancyId: pregnancyId);

    if (!mounted) return;
    setState(() {
      _pregnancy = pregnancy;
      _milestones = milestones;
      _memories
        ..clear()
        ..addAll(memories);
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

  /// Sample photos, shown in preview only.
  ///
  /// Replaced wholesale by [_loadPregnancy] for a real account, so a mother
  /// never sees someone else's ultrasound in her own gallery.
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


  /// Guards against a second run while the first is still open.
  ///
  /// "Add photo" appears three times on this flow — the section action, the
  /// empty-state button and the gallery's own button — and none of them was
  /// disabled while a pick was in progress. Tapping again while the file
  /// chooser was up started a second pick and pushed a second dialog, so
  /// dismissing one left the other's barrier dimming the page with nothing
  /// visible on top of it.
  bool _isAddingMemory = false;

  Future<void> _addMemory() async {
    if (_isAddingMemory) return;
    _isAddingMemory = true;
    try {
      final selectedPhoto = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (selectedPhoto == null) return;

      final imageBytes = await selectedPhoto.readAsBytes();
      if (!mounted) return;

      final details = await showDialog<MemoryDetails>(
        context: context,
        builder: (_) => MemoryDetailsDialog(imageBytes: imageBytes),
      );

      if (details == null || !mounted) return;

      // Preview has no pregnancy to attach a photo to, so it keeps the old
      // in-memory behaviour and says so. Everywhere else the photo is saved
      // before she is told it was.
      final pregnancyId = _pregnancy?.pregnancyId;
      if (_isPreview || pregnancyId == null) {
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
            content: Text('Preview only — this photo is not saved.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final saved = await _repository.saveMemory(
        pregnancyId: pregnancyId,
        title: details.title,
        caption: details.caption,
        imageBytes: imageBytes,
      );
      if (!mounted) return;

      // Nothing is added to the list unless the write came back. The previous
      // version inserted first and announced success unconditionally, so a
      // failed save looked exactly like a good one until she reopened the app
      // and the photo was gone.
      if (saved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The photo could not be saved. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() => _memories.insert(0, saved));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo saved to your Memory Gallery.'),
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
    } finally {
      // In a finally rather than at each exit: the method returns from five
      // places, and a flag left true on any of them would disable adding
      // photos for the rest of the session with no way to recover.
      _isAddingMemory = false;
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
                      // The "Your body and your care" row is out while its
                      // destination is reworked. _openMyCare and the page it
                      // opens are untouched, so putting it back is a matter of
                      // restoring the row, not rebuilding the route.

                      if (_memoriesEnabled) ...[
                        const SizedBox(height: 34),
                        _MemoryCard(
                          key: _memoriesKey,
                          memories: _memories,
                          onAddMemory: _addMemory,
                          onOpenGallery: _openMemoryGallery,
                        ),
                      ],
                      // The eight-page care guide used to sit here. It is
                      // almost entirely about a baby who has been born —
                      // first days, feeding through the first year, home
                      // safety, checkups — and this page is read by a mother
                      // who is still pregnant. It now lives in the baby book
                      // of a registered child.
                      const SizedBox(height: 28),
                      ReferencesPanel(
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
                  color: AppColors.headingSoft,
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
          TextButton.icon(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandText,
              backgroundColor: const Color(0xFFFFEDF4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.add_a_photo_outlined, size: 17),
            label: Text(
              actionLabel!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
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

      // Nothing to advance while another page is on top of this one.
      //
      // Without this the slideshow keeps ticking behind the gallery and the
      // photo viewer, rebuilding a card carrying full-size images every four
      // seconds for as long as the Baby Book stays in the navigator stack.
      // Push the gallery, open a photo, come back, and that work is still
      // going on underneath — which is what made the app feel slow after
      // visiting the gallery rather than while using it.
      if (ModalRoute.of(context)?.isCurrent != true) return;

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
                                        // "SLIDESHOW 1/2" named the mechanism.
                                        // "1 of 2" says where she is in her
                                        // own photos, which is the only part
                                        // of it she needs.
                                        '${_currentIndex + 1} of ${widget.memories.length}',
                                        style: const TextStyle(
                                          color: AppColors.brandText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.2,
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
                                      color: AppColors.headingSoft,
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    memory.caption,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.inputText,
                                      fontSize: 13,
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



