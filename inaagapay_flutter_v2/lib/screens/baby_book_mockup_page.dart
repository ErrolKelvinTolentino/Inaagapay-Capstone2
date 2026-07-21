import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/baby_memory.dart';
import '../services/asset_pdf_download_service.dart';
import '../theme/app_colors.dart';
import '../widgets/baby_memory_photo.dart';
import '../widgets/main_header.dart';
import 'baby_book_memory_gallery_page.dart';

String _t(String english, String _) => english;

typedef _MockAction = void Function(String english, String filipino);

class BabyBookMockupPage extends StatefulWidget {
  const BabyBookMockupPage({super.key});

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
  final GlobalKey _milestonesKey = GlobalKey();
  final GlobalKey _memoriesKey = GlobalKey();
  final GlobalKey _guideKey = GlobalKey();

  String? _downloadingPdf;
  final List<bool> _milestones = <bool>[true, true, true, false];
  final ImagePicker _imagePicker = ImagePicker();
  final List<BabyMemory> _memories = <BabyMemory>[
    BabyMemory(
      id: 'sample-crawling',
      title: 'First time crawling! ✨',
      caption: 'From the play mat to Mama—you were so fast!',
      date: DateTime(2026, 7, 18),
      assetPath: 'assets/images/baby.png',
    ),
    BabyMemory(
      id: 'sample-cuddle',
      title: 'Safe in Mama’s arms',
      caption: 'A quiet cuddle that made the whole day feel warm.',
      date: DateTime(2026, 7, 20),
      assetPath: 'assets/images/mother_baby_hero.png',
    ),
  ];

  int get _completedMilestones =>
      _milestones.where((isComplete) => isComplete).length;

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

  Future<void> _goToSection(int index) async {
    final keys = <GlobalKey>[
      _todayKey,
      _milestonesKey,
      _memoriesKey,
      _guideKey,
    ];

    final sectionContext = keys[index].currentContext;
    if (sectionContext != null) {
      await Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
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
                      hintText: 'First smile, family day…',
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
                      _BabyCoverCard(key: _todayKey),
                      const SizedBox(height: 24),
                      const _SectionHeading(
                        eyebrow: 'TODAY',
                        title: 'How is baby?',
                      ),
                      const SizedBox(height: 12),
                      const _BabyStatsCard(),
                      const SizedBox(height: 14),
                      _AppointmentCard(
                        onTap: () =>
                            _showMockupMessage('Appointment details', ''),
                      ),
                      const SizedBox(height: 28),
                      _SectionHeading(
                        eyebrow: 'QUICK LOOK',
                        title: 'Everything important, in one book',
                        actionLabel: 'See all',
                        onAction: () =>
                            _showMockupMessage('Baby book sections', ''),
                      ),
                      const SizedBox(height: 12),
                      _QuickLinksGrid(
                        onMilestonesTap: () => _goToSection(1),
                        onMemoriesTap: () => _goToSection(2),
                        onMockTap: _showMockupMessage,
                      ),
                      const SizedBox(height: 30),
                      _MilestonesCard(
                        key: _milestonesKey,
                        milestones: _milestones,
                        completed: _completedMilestones,
                        onChanged: (index) {
                          setState(() {
                            _milestones[index] = !_milestones[index];
                          });
                        },
                      ),
                      const SizedBox(height: 30),
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

class _MemoryDetails {
  final String title;
  final String caption;

  const _MemoryDetails({required this.title, required this.caption});
}

class _BabyCoverCard extends StatelessWidget {
  const _BabyCoverCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 244,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF86B7), Color(0xFFFF5A9B)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/mother_baby_hero.png',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0, 0.52, 1],
                  colors: [
                    const Color(0xFFF65299).withValues(alpha: 0.97),
                    const Color(0xFFF85CA0).withValues(alpha: 0.83),
                    const Color(0xFFFF8DBA).withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 190, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      _t('SAMPLE PROFILE', 'HALIMBAWANG PROFILE'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _t('Hello, I am', 'Hello, ako si'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Amara! 👋',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 31,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      const Icon(
                        Icons.cake_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _t('8 months old', '8 buwang gulang'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      'A little story of growth,\nhealth, and happy memories.',
                      'Munting kuwento ng paglaki,\nkalusugan, at masasayang alaala.',
                    ),
                    maxLines: 2,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.90),
                      height: 1.35,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
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
  const _BabyStatsCard();

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: _StatItem(
              icon: Icons.calendar_month_rounded,
              value: _t('Nov 12, 2025', 'Nob 12, 2025'),
              label: _t('Birth date', 'Kapanganakan'),
              color: const Color(0xFFFF68A5),
            ),
          ),
          const _VerticalDivider(),
          Expanded(
            child: _StatItem(
              icon: Icons.monitor_weight_outlined,
              value: '7.8 kg',
              label: _t('Weight', 'Timbang'),
              color: const Color(0xFF68CBB8),
            ),
          ),
          const _VerticalDivider(),
          Expanded(
            child: _StatItem(
              icon: Icons.height_rounded,
              value: '68 cm',
              label: _t('Height', 'Tangkad'),
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
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 58,
      color: AppColors.borderPrimary,
    );
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
                      _t('Next checkup', 'Susunod na checkup'),
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

class _QuickLinksGrid extends StatelessWidget {
  final VoidCallback onMilestonesTap;
  final VoidCallback onMemoriesTap;
  final _MockAction onMockTap;

  const _QuickLinksGrid({
    required this.onMilestonesTap,
    required this.onMemoriesTap,
    required this.onMockTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _QuickLinkCard(
          icon: Icons.show_chart_rounded,
          title: _t('Growth', 'Paglaki'),
          subtitle: _t('3 new records', '3 bagong tala'),
          color: const Color(0xFF68CBB8),
          onTap: () => onMockTap('Growth records', 'Mga tala ng paglaki'),
        ),
        _QuickLinkCard(
          icon: Icons.vaccines_rounded,
          title: _t('Vaccines', 'Bakuna'),
          subtitle: _t('6 of 8 completed', '6 sa 8 kumpleto'),
          color: const Color(0xFF7A8FE7),
          onTap: () => onMockTap('Vaccination records', 'Mga tala ng bakuna'),
        ),
        _QuickLinkCard(
          icon: Icons.emoji_events_rounded,
          title: _t('Milestones', 'Mga Tagumpay'),
          subtitle: _completedLabel,
          color: const Color(0xFFFFA85A),
          onTap: onMilestonesTap,
        ),
        _QuickLinkCard(
          icon: Icons.auto_awesome_rounded,
          title: _t('Memories', 'Mga Alaala'),
          subtitle: _t('12 happy moments', '12 masasayang sandali'),
          color: AppColors.brandPrimary,
          onTap: onMemoriesTap,
        ),
      ],
    );
  }

  String get _completedLabel =>
      _t('3 milestones this month', '3 milestone ngayong buwan');
}

class _QuickLinkCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickLinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 39,
                      height: 39,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const Icon(
                      Icons.arrow_outward_rounded,
                      color: Color(0xFFCBC5C8),
                      size: 18,
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MilestonesCard extends StatelessWidget {
  final List<bool> milestones;
  final int completed;
  final ValueChanged<int> onChanged;

  const _MilestonesCard({
    super.key,
    required this.milestones,
    required this.completed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      _t('Sits without support', 'Nakakaupo nang walang alalay'),
      _t(
        'Looks when their name is called',
        'Tumitingin kapag tinatawag ang pangalan',
      ),
      _t(
        'Passes a toy from one hand to the other',
        'Nagpapasa ng laruan sa kabilang kamay',
      ),
      _t('Crawls or tries to crawl', 'Gumagapang o sumusubok gumapang'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          eyebrow: _t('LITTLE WINS', 'MUNTING TAGUMPAY'),
          title: _t('Milestones this month', 'Milestones ngayong buwan'),
        ),
        const SizedBox(height: 12),
        _WhiteCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 58,
                        height: 58,
                        child: CircularProgressIndicator(
                          value: completed / milestones.length,
                          strokeWidth: 7,
                          backgroundColor: const Color(0xFFFFE5EF),
                          color: AppColors.brandPrimary,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Text(
                        '$completed/${milestones.length}',
                        style: const TextStyle(
                          color: AppColors.brandText,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(
                            '$completed of ${milestones.length} achieved',
                            '$completed sa ${milestones.length} nakamit',
                          ),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            'Tap a box to mark a new achievement.',
                            'I-tap ang kahon para markahan ang bagong achievement.',
                          ),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.borderPrimary, height: 1),
              const SizedBox(height: 8),
              for (var index = 0; index < labels.length; index++)
                _MilestoneRow(
                  label: labels[index],
                  isComplete: milestones[index],
                  onTap: () => onChanged(index),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final String label;
  final bool isComplete;
  final VoidCallback onTap;

  const _MilestoneRow({
    required this.label,
    required this.isComplete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: isComplete,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isComplete
                      ? AppColors.brandPrimary
                      : const Color(0xFFFFF5F8),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isComplete
                        ? AppColors.brandPrimary
                        : const Color(0xFFFFC5DA),
                    width: 1.5,
                  ),
                ),
                child: isComplete
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 17)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isComplete
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: isComplete ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
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
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 3),
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
                        icon:
                            const Icon(Icons.photo_library_outlined, size: 18),
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
  final List<String> paragraphs;
  final String source;
  final Color accent;

  const _GuidePageData({
    required this.number,
    required this.icon,
    required this.imagePath,
    required this.title,
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
                    for (var index = 0;
                        index < data.paragraphs.length;
                        index++) ...[
                      Text(
                        data.paragraphs[index],
                        textAlign: TextAlign.justify,
                        style: const TextStyle(
                          color: Color(0xFF544C45),
                          fontFamily: 'Georgia',
                          fontSize: 13,
                          height: 1.65,
                        ),
                      ),
                      if (index != data.paragraphs.length - 1)
                        const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 17),
                    Container(height: 1, color: const Color(0xFFEDE4D7)),
                    const SizedBox(height: 10),
                    Text(
                      'SOURCE NOTES  •  ${data.source}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.15,
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
            'The mockup\'s health-record and milestone sections were informed by these guides.',
            'Ang health-record at milestone sections ng mockup ay hinango sa mga gabay na ito.',
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
                      disabledBackgroundColor:
                          badgeColor.withValues(alpha: 0.45),
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
                'This is a UI mockup. Sample milestones and health data do not replace advice or assessment from a pediatrician or health worker.',
                'UI mockup lamang ito. Ang sample milestones at health data ay hindi kapalit ng payo o assessment ng pediatrician o health worker.',
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
