import 'package:flutter/material.dart';

import '../models/baby_memory.dart';

class BabyMemoryPhoto extends StatelessWidget {
  final BabyMemory memory;
  final BoxFit fit;

  const BabyMemoryPhoto({
    super.key,
    required this.memory,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = memory.imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: double.infinity,
        height: double.infinity,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: _errorBuilder,
      );
    }

    return Image.asset(
      memory.assetPath!,
      width: double.infinity,
      height: double.infinity,
      fit: fit,
      errorBuilder: _errorBuilder,
    );
  }

  Widget _errorBuilder(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return Container(
      color: const Color(0xFFFFEDF4),
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        color: Color(0xFFFF68A5),
        size: 42,
      ),
    );
  }
}
