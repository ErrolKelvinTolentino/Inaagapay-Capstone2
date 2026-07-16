// lib/screens/mother/journal_details_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../services/journal_service.dart';
import '../../services/language_service.dart';
import '../../models/journal_model.dart';
import '../../widgets/main_button.dart';

class JournalDetailsPage extends StatefulWidget {
  final JournalEntry entry;

  const JournalDetailsPage({super.key, required this.entry});

  @override
  State<JournalDetailsPage> createState() => _JournalDetailsPageState();
}

class _JournalDetailsPageState extends State<JournalDetailsPage> {
  late JournalEntry _entry;
  bool _deleting = false;

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  String get _formattedDate {
    return DateFormat('MMMM d, y • h:mm a').format(_entry.createdAt);
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_t('Delete Journal Entry', 'Burahin ang Tala sa Journal')),
        content: Text(
          _t(
            'Are you sure you want to delete this journal entry? This action cannot be undone.',
            'Sigurado ka bang gusto mong burahin ang tala na ito? Hindi na ito mababawi.',
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: Text(_t('Cancel', 'Kanselahin')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: Text(_t('Delete', 'Burahin')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deleting = true);

    final success = await JournalService.deleteJournal(_entry.entryId);

    if (!mounted) return;

    setState(() => _deleting = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _t('Journal entry deleted', 'Nabura ang tala sa journal')),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Failed to delete journal entry.',
              'Hindi nabura ang tala sa journal.')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: AppBar(
        title: Text(
          _t('Journal Entry', 'Tala sa Journal'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
      ),
          body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🗓 Date
              Text(
                _formattedDate,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: 12),

              // 📌 Title
              Text(
                _entry.title.isNotEmpty
                    ? _entry.title
                    : _t('Untitled Entry', 'Walang Pamagat na Tala'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 20),

              // 📖 Content
              Expanded(
                child: Container(
                  width: double.infinity,
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
                  child: SingleChildScrollView(
                    child: Text(
                      _entry.content,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 🔙 BACK BUTTON
              MainButton(
                label: _t('Back', 'Bumalik'),
                showIcons: true,
                leftIcon: Icons.arrow_back,
                onPressed: () {
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 12),

              // 🗑 DELETE BUTTON
              MainButton(
                label: _deleting
                    ? _t('Deleting...', 'Binubura...')
                    : _t('Delete Entry', 'Burahin ang Tala'),
                showIcons: true,
                leftIcon: Icons.delete_outline,
                onPressed: _deleting ? null : _confirmDelete,
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
        );
      },
    );
  }
}
