import 'package:flutter/material.dart';

import '../models/baby_memory.dart';
import '../theme/app_colors.dart';
import '../widgets/baby_memory_photo.dart';
import '../widgets/secondary_header.dart';

class BabyBookMemoryGalleryPage extends StatefulWidget {
  final List<BabyMemory> memories;
  final Future<void> Function() onAddMemory;

  const BabyBookMemoryGalleryPage({
    super.key,
    required this.memories,
    required this.onAddMemory,
  });

  @override
  State<BabyBookMemoryGalleryPage> createState() =>
      _BabyBookMemoryGalleryPageState();
}

class _BabyBookMemoryGalleryPageState extends State<BabyBookMemoryGalleryPage> {
  Future<void> _addMemory() async {
    await widget.onAddMemory();
    if (mounted) setState(() {});
  }

  void _openMemory(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MemoryViewerPage(
          memories: widget.memories,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.memories.length;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7FA),
      body: Column(
        children: [
          // The shared header every pushed mother-side page uses, rather than
          // a bespoke AppBar with an all-caps title. One back arrow, one
          // title treatment, in the same place on every screen.
          SecondaryHeader(
            title: 'Memory Gallery',
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: widget.memories.isEmpty
                ? _EmptyGallery(onAddMemory: _addMemory)
                : CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: <Color>[
                                      Color(0xFFFF8FBC),
                                      AppColors.brandPrimary,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: AppColors.brandPrimary
                                          .withValues(alpha: 0.28),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.photo_library_rounded,
                                  color: Colors.white,
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Little moments, lovingly kept',
                                      style: TextStyle(
                                        color: AppColors.headingSoft,
                                        fontSize: 20,
                                        height: 1.2,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      count == 1
                                          ? '1 photo • tap it to see it bigger'
                                          : '$count photos • tap one to see it bigger',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12.5,
                                        height: 1.4,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: count,
                          itemBuilder: (context, index) {
                            final memory = widget.memories[index];
                            return _MemoryGalleryTile(
                              memory: memory,
                              onTap: () => _openMemory(index),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      // Round, not the extended pill. The label sat across the bottom-right
      // corner of the grid and covered part of the last photo; a circle
      // covers less of what the page is for, and the tooltip and semantics
      // label carry the wording the pill was spelling out.
      floatingActionButton: Semantics(
        button: true,
        label: 'Add photo to the memory gallery',
        child: FloatingActionButton(
          key: const ValueKey('gallery-add-photo'),
          onPressed: _addMemory,
          tooltip: 'Add photo',
          backgroundColor: AppColors.brandPrimary,
          foregroundColor: Colors.white,
          elevation: 5,
          shape: const CircleBorder(),
          child: const Icon(Icons.add_a_photo_rounded, size: 24),
        ),
      ),
    );
  }
}

class _MemoryGalleryTile extends StatelessWidget {
  final BabyMemory memory;
  final VoidCallback onTap;

  const _MemoryGalleryTile({required this.memory, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFFE1EC)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Hero(
                  tag: 'baby-memory-${memory.id}',
                  child: BabyMemoryPhoto(memory: memory),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      memory.shortDate,
                      style: const TextStyle(
                        color: AppColors.brandText,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  final Future<void> Function() onAddMemory;

  const _EmptyGallery({required this.onAddMemory});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEDF4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.brandPrimary,
                size: 42,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your memory gallery is ready',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add the first photo you want to remember in Baby’s story.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddMemory,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Add a photo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryViewerPage extends StatefulWidget {
  final List<BabyMemory> memories;
  final int initialIndex;

  const _MemoryViewerPage({
    required this.memories,
    required this.initialIndex,
  });

  @override
  State<_MemoryViewerPage> createState() => _MemoryViewerPageState();
}

class _MemoryViewerPageState extends State<_MemoryViewerPage> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memories[_currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF271E23),
      appBar: AppBar(
        backgroundColor: const Color(0xFF271E23),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_currentIndex + 1} of ${widget.memories.length}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.memories.length,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                },
                itemBuilder: (context, index) {
                  final item = widget.memories[index];
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Hero(
                      tag: 'baby-memory-${item.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BabyMemoryPhoto(
                          memory: item,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              decoration: const BoxDecoration(
                color: Color(0xFF33272E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memory.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    memory.caption,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    memory.fullDate,
                    style: const TextStyle(
                      color: Color(0xFFFF8FBC),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
