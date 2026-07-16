// lib/screens/mother/add_journal_page.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/journal_service.dart';
import '../../services/language_service.dart';
import '../../widgets/main_button.dart';
import '../../models/journal_model.dart';

class AddJournalPage extends StatefulWidget {
  const AddJournalPage({super.key});

  @override
  State<AddJournalPage> createState() => _AddJournalPageState();
}

class _AddJournalPageState extends State<AddJournalPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  bool _saving = false;
  bool _hasError = false;
  String _errorMessage = '';

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveJournal() async {
    if (_contentController.text.trim().isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = _t('Please write something before saving.',
            'Pakisulat muna ang iyong tala bago i-save.');
      });
      return;
    }

    setState(() {
      _saving = true;
      _hasError = false;
      _errorMessage = '';
    });

    final entry = CreateJournalEntry(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
    );

    final success = await JournalService.createJournal(entry);

    setState(() => _saving = false);

    if (!mounted) return;

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('Journal entry saved successfully!',
                'Matagumpay na na-save ang tala sa journal!')),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      Navigator.pop(context, true);
    } else {
      setState(() {
        _hasError = true;
        _errorMessage = _t('Failed to save journal. Please try again.',
            'Hindi na-save ang journal. Pakisubukan muli.');
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
          appBar: AppBar(
        title: Text(
          _t('New Journal', 'Bagong Journal'),
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
              Text(
                _t('Write freely 🌷', 'Malayang magsulat 🌷'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                    'This is your personal space. Write anything you feel or experience today.',
                    'Ito ang iyong sariling espasyo. Isulat ang anumang nararamdaman o naranasan mo ngayong araw.'),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // 📌 TITLE FIELD
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: _t('Title (optional)', 'Pamagat (opsyonal)'),
                    hintStyle:
                        const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 📝 CONTENT FIELD
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _contentController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: _t('How are you feeling today?',
                          'Ano ang nararamdaman mo ngayon?'),
                      hintStyle:
                          const TextStyle(color: AppColors.textSecondary),
                    ),
                    onChanged: (_) {
                      if (_hasError) {
                        setState(() {
                          _hasError = false;
                          _errorMessage = '';
                        });
                      }
                    },
                  ),
                ),
              ),

              if (_hasError) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // 💾 SAVE BUTTON
              MainButton(
                label: _saving
                    ? _t('Saving...', 'Sine-save...')
                    : _t('Save Journal', 'I-save ang Journal'),
                showIcons: true,
                leftIcon: Icons.save,
                onPressed: _saving ? null : _saveJournal,
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
