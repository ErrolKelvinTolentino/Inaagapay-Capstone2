// lib/screens/mother/mother_journal_screen.dart
//
// Her journal: a list of entries, newest first.
//
// Written for a mother who may not write much. Each row leads with the face
// she tapped, so the list can be read at a glance without reading a word of
// it — and a month of moods is something she and her midwife can both see.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/journal_model.dart';
import '../../models/journal_mood.dart';
import '../../services/journal_service.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import 'add_journal_page.dart';
import 'journal_details_page.dart';

class MotherJournalScreen extends StatefulWidget {
  const MotherJournalScreen({super.key});

  @override
  State<MotherJournalScreen> createState() => _MotherJournalScreenState();
}

class _MotherJournalScreenState extends State<MotherJournalScreen> {
  late Future<List<JournalEntry>> _journalsFuture;

  @override
  void initState() {
    super.initState();
    _loadJournals();
  }

  void _loadJournals() {
    _journalsFuture = JournalService.fetchJournals();
  }

  void _reload() => setState(_loadJournals);

  String _t(String english, String filipino) =>
      LanguageService.translate(english, filipino);

  Future<void> _openAddJournal() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddJournalPage()),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _openEntry(JournalEntry entry) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => JournalDetailsPage(entry: entry)),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('Your personal space 🌷',
                            'Iyong sariling espasyo 🌷'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          // Brand pink instead of near-black. This is the
                          // warmest page in the app and it opened on the
                          // hardest text colour available.
                          color: AppColors.brandText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t('However you feel today is worth keeping.',
                            'Anuman ang nararamdaman mo ngayon ay tala-talaga.'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: FutureBuilder<List<JournalEntry>>(
                    future: _journalsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.brandPrimary),
                        );
                      }
                      if (snapshot.hasError) {
                        return _buildErrorState();
                      }
                      final journals = snapshot.data ?? const <JournalEntry>[];
                      if (journals.isEmpty) {
                        return _buildEmptyState();
                      }
                      return RefreshIndicator(
                        color: AppColors.brandPrimary,
                        onRefresh: () async => _reload(),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                          itemCount: journals.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) =>
                              _buildEntryCard(journals[index]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Round, like every other add button in the app.
          floatingActionButton: FloatingActionButton(
            heroTag: 'journalAdd',
            onPressed: _openAddJournal,
            backgroundColor: AppColors.brandPrimary,
            shape: const CircleBorder(),
            elevation: 3,
            tooltip: _t('Write an entry', 'Magsulat ng tala'),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
        );
      },
    );
  }

  Widget _buildEntryCard(JournalEntry entry) {
    final mood = entry.mood;
    final hasContent = entry.content.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openEntry(entry),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderPrimary),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The face first. A mother scanning her journal recognises how a
              // day felt before she reads what she wrote about it.
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (mood?.color ?? AppColors.brandPrimary)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: mood != null
                    ? Text(mood.emoji, style: const TextStyle(fontSize: 22))
                    : const Icon(Icons.edit_note_rounded,
                        size: 22, color: AppColors.brandPrimary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title.isNotEmpty
                          ? entry.title
                          : (mood?.label ??
                              _t('Untitled', 'Walang pamagat')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inputText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('MMMM d, y').format(entry.createdAt),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (hasContent) ...[
                      const SizedBox(height: 8),
                      Text(
                        entry.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 22, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 96),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: const BoxDecoration(
                    color: AppColors.brandSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_stories_rounded,
                      size: 42, color: AppColors.brandPrimary),
                ),
                const SizedBox(height: 20),
                Text(
                  _t('Your first page is waiting',
                      'Naghihintay ang unang pahina mo'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _t('Tap the pink button to save how you feel today. You do not have to write much.',
                      'Pindutin ang pink na buton para itala ang nararamdaman mo ngayon. Hindi mo kailangang magsulat nang marami.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                // The five faces, shown rather than described — so she can see
                // what "you do not have to write much" actually means before
                // she opens anything.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final mood in JournalMood.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: mood.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Text(mood.emoji,
                              style: const TextStyle(fontSize: 19)),
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

  Widget _buildErrorState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 96),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_off_rounded,
                      size: 36, color: AppColors.warning),
                ),
                const SizedBox(height: 18),
                Text(
                  _t('We could not open your journal',
                      'Hindi namin nabuksan ang journal mo'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inputText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  // The raw exception used to be printed here. It named the
                  // table and the driver, which tells a mother nothing and
                  // worries her about her own entries.
                  _t('Your entries are safe. Please check your connection and try again.',
                      'Ligtas ang mga tala mo. Pakisuri ang koneksyon at subukan muli.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_t('Try again', 'Subukan muli')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
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
