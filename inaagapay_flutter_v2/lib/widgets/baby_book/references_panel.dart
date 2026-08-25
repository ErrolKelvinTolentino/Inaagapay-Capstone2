import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The sources behind the guidance on a page, folded away until asked for.
///
/// This was an open section: a heading, a paragraph explaining what references
/// are, and two tall cards each carrying a badge, a title, an organisation, a
/// description, a raw URL, an open-in-browser button and a full-width download
/// button. It was among the largest things on the Baby Book and the least
/// useful to a mother — she is there about her pregnancy, not about where the
/// wording came from.
///
/// It cannot simply be deleted. Citing the DOH and WHO sources is part of what
/// keeps the guidance honest, and it is what a defense panel will ask about.
/// Collapsed, it stays on the record and out of the way, and opens to two
/// plain rows carrying the one thing she might actually want: the booklet.
class ReferencesPanel extends StatefulWidget {
  final VoidCallback onDownloadDoh;
  final VoidCallback onDownloadWho;
  final bool downloadingDoh;
  final bool downloadingWho;

  const ReferencesPanel({
    super.key,
    required this.onDownloadDoh,
    required this.onDownloadWho,
    required this.downloadingDoh,
    required this.downloadingWho,
  });

  @override
  State<ReferencesPanel> createState() => _ReferencesPanelState();
}

class _ReferencesPanelState extends State<ReferencesPanel> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF5E4EC)),
      ),
      child: Column(
        children: [
          InkWell(
            key: const ValueKey<String>('references-toggle'),
            onTap: () => setState(() => _isOpen = !_isOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEDF4),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: AppColors.brandText,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'References',
                          style: TextStyle(
                            color: AppColors.headingSoft,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Where this guidance comes from',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.brandPrimary,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // AnimatedSize over a conditional child, not AnimatedCrossFade.
          //
          // CrossFade keeps both children in the tree, so the sources were
          // built and findable while collapsed — a screen reader would have
          // read them out of a closed panel, and the page paid to lay them out
          // on every build. Not building them is both the honest collapse and
          // the cheaper one.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_isOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Color(0xFFF5E4EC), height: 1),
                  const SizedBox(height: 14),
                  _ReferenceRow(
                    badge: 'DOH',
                    title: 'Mother and Baby Book',
                    organisation: 'Department of Health, Philippines',
                    onDownload: widget.onDownloadDoh,
                    isDownloading: widget.downloadingDoh,
                  ),
                  const SizedBox(height: 12),
                  _ReferenceRow(
                    badge: 'WHO',
                    title: 'Home-based records for mothers and children',
                    organisation: 'World Health Organization',
                    onDownload: widget.onDownloadWho,
                    isDownloading: widget.downloadingWho,
                  ),
                  const SizedBox(height: 16),
                  // The old wording opened "This is a UI mockup", which
                  // stopped being true once the page started reading a real
                  // pregnancy. A mother who read that had no reason to trust
                  // anything else on the screen.
                  const Text(
                    'This guidance is general. It does not replace advice from '
                    'your doctor, midwife, or health worker.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
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

/// One source: who it came from, and the booklet itself.
///
/// No raw URL. "foi.gov.ph/agencies/doh/mother-and-baby-book" is not something
/// a mother reads or types, and it took a whole line of the card to say what
/// the organisation line says in words. The PDF is the part she can use.
class _ReferenceRow extends StatelessWidget {
  final String badge;
  final String title;
  final String organisation;
  final VoidCallback onDownload;
  final bool isDownloading;

  const _ReferenceRow({
    required this.badge,
    required this.title,
    required this.organisation,
    required this.onDownload,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF7EAF0)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // One palette. The WHO row carried a blue badge and a blue
              // download button, which made it read as another app's card
              // sitting inside this one.
              color: const Color(0xFFFFEDF4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: AppColors.brandText,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
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
                    color: AppColors.headingSoft,
                    fontSize: 14.5,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  organisation,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Download the $badge booklet as a PDF',
            child: IconButton(
              key: ValueKey<String>('reference-download-$badge'),
              tooltip: 'Download PDF',
              onPressed: isDownloading ? null : onDownload,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFFFD5E5),
                minimumSize: const Size(46, 46),
                shape: const CircleBorder(),
              ),
              icon: isDownloading
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 21),
            ),
          ),
        ],
      ),
    );
  }
}
