// lib/screens/mother/add_journal_page.dart
//
// Writing a journal entry, and editing one already written.
//
// The same page does both. An entry a mother cannot correct is an entry she
// hesitates to write, and `JournalService.updateJournal` existed with no caller
// at all — there was no way to fix so much as a typo.

import 'package:flutter/material.dart';

import '../../models/journal_model.dart';
import '../../models/journal_mood.dart';
import '../../services/journal_service.dart';
import '../../services/language_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/main_button.dart';
import '../../widgets/secondary_header.dart';

class AddJournalPage extends StatefulWidget {
  /// The entry being edited, or null when writing a new one.
  final JournalEntry? existing;

  const AddJournalPage({super.key, this.existing});

  @override
  State<AddJournalPage> createState() => _AddJournalPageState();
}

class _AddJournalPageState extends State<AddJournalPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  JournalMood? _mood;
  bool _saving = false;
  String? _errorMessage;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title ?? '');
    _contentController =
        TextEditingController(text: widget.existing?.content ?? '');
    _mood = widget.existing?.mood;
    _contentController.addListener(_clearError);
  }

  @override
  void dispose() {
    _contentController.removeListener(_clearError);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  String _t(String english, String filipino) =>
      LanguageService.translate(english, filipino);

  /// An entry needs a mood or some words — not necessarily both.
  ///
  /// Requiring text shut out the mothers this page matters most for. A tapped
  /// face on a hard day is a real entry, and her midwife can read it.
  bool get _canSave =>
      _mood != null || _contentController.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) {
      setState(() => _errorMessage = _t(
            'Choose how you feel, or write something.',
            'Pumili kung ano ang nararamdaman mo, o magsulat ng kahit ano.',
          ));
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final title = _titleController.text.trim();
      final content = _contentController.text.trim();

      if (_isEditing) {
        await JournalService.updateJournal(
          widget.existing!.entryId,
          UpdateJournalEntry(title: title, content: content, mood: _mood),
        );
      } else {
        await JournalService.createJournal(
          CreateJournalEntry(title: title, content: content, mood: _mood),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? _t('Your entry was updated.', 'Na-update ang iyong tala.')
              : _t('Your entry was saved.', 'Na-save ang iyong tala.')),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      // The service throws rather than returning false, so every call site
      // needs this. Without it a failed save left the button reading "Saving…"
      // for as long as she cared to look at it.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = _t(
          'Your entry could not be saved. Please check your connection and try again.',
          'Hindi na-save ang iyong tala. Pakisuri ang koneksyon at subukan muli.',
        );
      });
    }
  }

  /// Confirms before throwing away typing.
  Future<bool> _confirmDiscard() async {
    final titleChanged =
        _titleController.text.trim() != (widget.existing?.title ?? '');
    final contentChanged =
        _contentController.text.trim() != (widget.existing?.content ?? '');
    final moodChanged = _mood != widget.existing?.mood;
    if (!titleChanged && !contentChanged && !moodChanged) return true;

    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _t('Leave without saving?', 'Aalis nang hindi nagse-save?'),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.inputText,
          ),
        ),
        content: Text(
          _t('What you wrote will not be kept.',
              'Hindi maitatago ang isinulat mo.'),
          style: const TextStyle(
              fontSize: 14, height: 1.4, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                shape: const StadiumBorder()),
            child: Text(_t('Keep writing', 'Magpatuloy')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                shape: const StadiumBorder()),
            child: Text(_t('Leave', 'Umalis')),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _confirmDiscard() && mounted) {
              if (!context.mounted) return;
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.bgPrimary,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              // The app's own header, in brand pink, instead of a Material
              // AppBar with a near-black title.
              child: SecondaryHeader(
                title: _isEditing
                    ? _t('Edit Entry', 'I-edit ang Tala')
                    : _t('New Entry', 'Bagong Tala'),
                onBack: () async {
                  if (await _confirmDiscard() && context.mounted) {
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  _t('How are you today?', 'Kumusta ka ngayon?'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _t('Tap a face. Writing is up to you.',
                      'Pumili ng mukha. Nasa iyo kung magsusulat ka.'),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                _buildMoodPicker(),
                const SizedBox(height: 24),
                _fieldLabel(_t('Give it a name', 'Bigyan ng pangalan')),
                const SizedBox(height: 8),
                _softField(
                  controller: _titleController,
                  hint: _t('Optional', 'Opsyonal'),
                  maxLines: 1,
                ),
                const SizedBox(height: 20),
                _fieldLabel(_t('Write anything', 'Isulat ang kahit ano')),
                const SizedBox(height: 8),
                _softField(
                  controller: _contentController,
                  hint: _t('What happened today? How do you feel?',
                      'Ano ang nangyari ngayon? Ano ang nararamdaman mo?'),
                  maxLines: 9,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  _buildError(_errorMessage!),
                ],
                const SizedBox(height: 26),
                MainButton(
                  label: _saving
                      ? _t('Saving…', 'Sine-save…')
                      : (_isEditing
                          ? _t('Save changes', 'I-save ang pagbabago')
                          : _t('Save my entry', 'I-save ang tala ko')),
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _t('Only you and your midwife can see this.',
                        'Ikaw at ang iyong midwife lang ang makakakita nito.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.inputText,
        ),
      );

  /// A rounded, borderless field on a soft fill.
  ///
  /// Hairline outlines around a large writing area read as a form to fill in.
  /// A journal should feel like paper.
  Widget _softField({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(
          fontSize: 15,
          height: 1.5,
          color: AppColors.inputText,
        ),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          hintStyle: const TextStyle(
            fontSize: 14.5,
            color: AppColors.textSecondary,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildMoodPicker() {
    return Row(
      children: [
        for (final mood in JournalMood.values) ...[
          Expanded(child: _moodButton(mood)),
          if (mood != JournalMood.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _moodButton(JournalMood mood) {
    final selected = _mood == mood;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Tapping the chosen face again clears it, so a mis-tap is not
        // permanent on a form with no other way to undo one.
        onTap: () => setState(() => _mood = selected ? null : mood),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? mood.color.withValues(alpha: 0.18)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? mood.color : AppColors.borderPrimary,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(mood.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 6),
              Text(
                mood.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  height: 1.2,
                  color: selected ? AppColors.inputText : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFAD1D1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 17, color: Color(0xFFD98080)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Color(0xFF9E5A5A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
