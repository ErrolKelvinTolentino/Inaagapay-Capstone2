// lib/screens/mother/mother_journal_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../services/journal_service.dart';
import '../../services/language_service.dart';
import '../../models/journal_model.dart';
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

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  Future<void> _openAddJournal() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddJournalPage()),
    );

    if (result == true && mounted) {
      setState(() {
        _loadJournals();
      });
    }
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                _t('Your personal space 🌷', 'Iyong sariling espasyo 🌷'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                    'Write your thoughts, feelings, and pregnancy moments.',
                    'Isulat ang iyong mga iniisip, nararamdaman, at mahahalagang sandali sa pagbubuntis.'),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: FutureBuilder<List<JournalEntry>>(
                  future: _journalsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandPrimary,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _t('Failed to load journal entries',
                                  'Hindi na-load ang mga tala sa journal'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              snapshot.error.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _loadJournals();
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandPrimary,
                              ),
                              child: Text(_t('Retry', 'Subukan Muli')),
                            ),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return _EmptyJournalState(onAdd: _openAddJournal);
                    }

                    final journals = snapshot.data!;

                    return RefreshIndicator(
                      onRefresh: () async {
                        setState(() {
                          _loadJournals();
                        });
                        return Future.value();
                      },
                      color: AppColors.brandPrimary,
                      child: ListView.separated(
                        itemCount: journals.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final entry = journals[index];
                          final date =
                              DateFormat('MMMM d, y').format(entry.createdAt);

                          return GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      JournalDetailsPage(entry: entry),
                                ),
                              );
                              if (mounted) {
                                setState(() => _loadJournals());
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.title.isNotEmpty
                                        ? entry.title
                                        : _t('Untitled Entry',
                                            'Walang Pamagat na Tala'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    date,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    entry.content,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: const [
                                      Icon(
                                        Icons.chevron_right,
                                        size: 20,
                                        color: AppColors.textSecondary,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
          floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.brandPrimary,
        onPressed: _openAddJournal,
        elevation: 2,
        child: const Icon(Icons.add, color: Colors.white),
          ),
        );
      },
    );
  }
}

/// 🌸 Empty State Widget
class _EmptyJournalState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyJournalState({required this.onAdd});

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              _t('No journal entries yet', 'Wala pang tala sa journal'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t('Start writing about your pregnancy journey.',
                  'Simulan ang pagsusulat tungkol sa iyong pagbubuntis.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(_t('Write your first entry',
                  'Isulat ang iyong unang tala')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
