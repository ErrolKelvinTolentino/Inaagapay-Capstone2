// lib/screens/mother/journal_details_page.dart
//
// One entry, read back.
//
// Reads as a page from a notebook rather than a record from a system: the
// mood she chose, the day, and her own words on soft paper.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/journal_model.dart';
import '../../services/journal_service.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/secondary_header.dart';
import 'add_journal_page.dart';

class JournalDetailsPage extends StatefulWidget {
  final JournalEntry entry;

  const JournalDetailsPage({super.key, required this.entry});

  @override
  State<JournalDetailsPage> createState() => _JournalDetailsPageState();
}

class _JournalDetailsPageState extends State<JournalDetailsPage> {
  late JournalEntry _entry;
  bool _deleting = false;

  /// True once anything changed, so the list behind knows to reload even if
  /// she leaves with the back arrow rather than after a delete.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  String _t(String english, String filipino) =>
      LanguageService.translate(english, filipino);

  String get _formattedDate =>
      DateFormat('MMMM d, y').format(_entry.createdAt);

  bool get _wasEdited =>
      _entry.updatedAt.difference(_entry.createdAt).inMinutes > 1;

  Future<void> _openEdit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddJournalPage(existing: _entry)),
    );
    if (saved != true || !mounted) return;

    // Re-read rather than patching the copy in memory, so what she sees is
    // what was actually stored.
    try {
      final fresh = await JournalService.getJournal(_entry.entryId);
      if (!mounted) return;
      setState(() {
        _entry = fresh;
        _changed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _changed = true);
      _say(
        _t('Saved, but this page could not refresh. Go back to see it.',
            'Na-save, ngunit hindi na-refresh ang pahina. Bumalik para makita ito.'),
        AppColors.warning,
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _t('Delete this entry?', 'Burahin ang tala na ito?'),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.inputText,
          ),
        ),
        content: Text(
          _t('It cannot be brought back.', 'Hindi na ito mababawi.'),
          style: const TextStyle(
              fontSize: 14, height: 1.4, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                shape: const StadiumBorder()),
            child: Text(_t('Keep it', 'Itago')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                shape: const StadiumBorder()),
            child: Text(_t('Delete', 'Burahin')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deleting = true);
    try {
      await JournalService.deleteJournal(_entry.entryId);
      if (!mounted) return;
      _say(_t('Entry deleted.', 'Nabura ang tala.'), AppColors.success);
      Navigator.pop(context, true);
    } catch (e) {
      // The service throws; the old code tested a bool it never returns, so a
      // failed delete left the button reading "Deleting…" indefinitely.
      if (!mounted) return;
      setState(() => _deleting = false);
      _say(
        _t('Could not delete it. Please try again.',
            'Hindi nabura. Pakisubukan muli.'),
        AppColors.error,
      );
    }
  }

  void _say(String message, Color colour) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colour,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        final mood = _entry.mood;

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: SecondaryHeader(
              title: _t('My Entry', 'Aking Tala'),
              onBack: () => Navigator.pop(context, _changed),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                color: AppColors.brandPrimary,
                tooltip: _t('Edit', 'I-edit'),
                onPressed: _deleting ? null : _openEdit,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Row(
                children: [
                  if (mood != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: mood.color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(mood.emoji,
                              style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 6),
                          Text(
                            mood.label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.inputText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      _formattedDate,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _entry.title.isNotEmpty
                    ? _entry.title
                    : _t('Untitled', 'Walang pamagat'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  // Softer than near-black, which on a page of her own words
                  // read as a headline in a newspaper.
                  color: AppColors.brandText,
                ),
              ),
              if (_wasEdited) ...[
                const SizedBox(height: 6),
                Text(
                  '${_t('Edited', 'Na-edit')} '
                  '${DateFormat('MMM d, y').format(_entry.updatedAt)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_entry.content.trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.borderPrimary),
                  ),
                  child: Text(
                    _entry.content,
                    style: const TextStyle(
                      fontSize: 15.5,
                      height: 1.65,
                      color: AppColors.inputText,
                    ),
                  ),
                )
              else
                // A mood on its own is a complete entry. Saying so stops it
                // looking like something failed to save.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.brandSecondary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    _t('You saved how you felt on this day.',
                        'Itinala mo ang nararamdaman mo sa araw na ito.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: AppColors.brandText,
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              // Deleting is rare and permanent, so it is a quiet text button
              // rather than a second full-width button competing with Edit.
              Center(
                child: TextButton.icon(
                  onPressed: _deleting ? null : _confirmDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(_deleting
                      ? _t('Deleting…', 'Binubura…')
                      : _t('Delete this entry', 'Burahin ang tala na ito')),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    textStyle: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
