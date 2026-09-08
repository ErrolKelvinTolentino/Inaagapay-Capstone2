// lib/widgets/terms_and_conditions_dialog.dart

import 'package:flutter/material.dart';

import '../data/terms_and_conditions_content.dart';
import '../theme/app_colors.dart';
import 'modal_button.dart';

/// The full Terms and Conditions of Use, in the same shell every other dialog
/// in the app uses: transparent [Dialog], `faintWhite` card, 24pt corners, the
/// outlined circle icon, a pink title, and the Cancel/Confirm button pair from
/// [ConfirmationDialogBox].
///
/// The one departure is the body. Every other dialog states one thing in two
/// lines; this one is eleven clauses, so the card holds its header and buttons
/// still and scrolls only the prose between them. A woman reading terms on a
/// phone at 11pm should never lose the "I Agree" button off the bottom of a
/// page she is still scrolling.
///
/// Returns `true` when the user pressed **I Agree**, `false` when they closed
/// it or dismissed it by tapping outside. Agreement is only ever recorded from
/// the button — dismissing the dialog leaves the checkbox exactly as it was.
///
/// Pass `askForAgreement: false` where the terms are only being *read back* —
/// Settings, for instance. Consent was given once, at registration; offering
/// "I Agree" again to someone who is just looking something up implies their
/// agreement is being collected a second time, and the button would have
/// nothing to record. That call gets a single Close button instead.
Future<bool> showTermsAndConditionsDialog(
  BuildContext context, {
  bool askForAgreement = true,
}) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (_) => TermsAndConditionsDialog(askForAgreement: askForAgreement),
  );
  return agreed ?? false;
}

class TermsAndConditionsDialog extends StatefulWidget {
  const TermsAndConditionsDialog({super.key, this.askForAgreement = true});

  /// Whether the footer offers "I Agree" alongside Close, or Close alone.
  final bool askForAgreement;

  @override
  State<TermsAndConditionsDialog> createState() =>
      _TermsAndConditionsDialogState();
}

class _TermsAndConditionsDialogState extends State<TermsAndConditionsDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // Tall enough that scrolling is worth it, short enough that the card
          // still reads as a dialog rather than a page.
          maxHeight: screenHeight * 0.86,
          maxWidth: 460,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.faintWhite,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _TermsHeader(),
              const _HairlineDivider(),

              Flexible(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                    child: const _TermsBody(),
                  ),
                ),
              ),

              const _HairlineDivider(),
              _TermsActions(askForAgreement: widget.askForAgreement),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsHeader extends StatelessWidget {
  const _TermsHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandPrimary, width: 3),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 30,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Terms and Conditions of Use',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'InaAgapay Research Prototype',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (termsEffectiveDate.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Effective $termsEffectiveDate',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TermsBody extends StatelessWidget {
  const _TermsBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          termsIntroduction,
          style: TextStyle(
            fontSize: 13,
            height: 1.55,
            color: AppColors.inputText,
          ),
        ),
        const SizedBox(height: 20),

        for (final section in termsSections) ...[
          _SectionBlock(section: section),
          // Section 11 carries the contact cards, so its spacing is handled
          // below instead.
          if (section != termsSections.last) const SizedBox(height: 18),
        ],

        const SizedBox(height: 12),
        for (final contact in termsContacts) ...[
          _ContactCard(contact: contact),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 14),
        const _AcknowledgmentBox(),
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section});

  final TermsSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Text(
                section.number,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandText,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.headingSoft,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Indented to the title, so the numbers stay a readable left rail.
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final paragraph in section.paragraphs) ...[
                Text(paragraph, style: _bodyStyle),
                const SizedBox(height: 8),
              ],

              if (section.bullets.isNotEmpty) ...[
                const SizedBox(height: 2),
                for (final bullet in section.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(top: 7, right: 10),
                          decoration: const BoxDecoration(
                            color: AppColors.brandPrimary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(child: Text(bullet, style: _bodyStyle)),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
              ],

              if (section.closing != null) Text(section.closing!, style: _bodyStyle),

              if (section.callout != null) ...[
                const SizedBox(height: 6),
                _Callout(text: section.callout!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The one sentence in the terms that is time-critical. Tinted, iconed, and
/// pulled out of the paragraph flow so it survives skim-reading.
class _Callout extends StatelessWidget {
  const _Callout({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact});

  final TermsContact contact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            contact.role,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.brandText,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in contact.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                entry,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.inputText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AcknowledgmentBox extends StatelessWidget {
  const _AcknowledgmentBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.verified_user_outlined,
                size: 17,
                color: AppColors.brandText,
              ),
              SizedBox(width: 8),
              Text(
                'User Acknowledgment',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            termsAcknowledgment,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.inputText,
            ),
          ),
        ],
      ),
    );
  }
}

/// The same Cancel/Confirm pair [ConfirmationDialogBox] uses — outlined pill on
/// the left, filled pink pill on the right, both 30pt radius. When the dialog
/// is not asking for agreement it falls back to the single full-width
/// [ModalButton] that [DialogBox] ends with.
class _TermsActions extends StatelessWidget {
  const _TermsActions({required this.askForAgreement});

  final bool askForAgreement;

  @override
  Widget build(BuildContext context) {
    if (!askForAgreement) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: ModalButton(
          label: 'Close',
          onPressed: () => Navigator.pop(context, false),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                side: const BorderSide(color: AppColors.borderPrimary),
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 4,
              ),
              child: const Text(
                'I Agree',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textOnColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HairlineDivider extends StatelessWidget {
  const _HairlineDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppColors.borderPrimary);
  }
}

const TextStyle _bodyStyle = TextStyle(
  fontSize: 13,
  height: 1.55,
  color: AppColors.inputText,
);
