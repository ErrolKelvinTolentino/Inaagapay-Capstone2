// lib/screens/midwife/midwife_help_page.dart
//
// Help for the midwife side. Mothers have their own at
// `screens/mother/help_support_screen.dart`; the two audiences ask different
// questions, and a single page trying to answer both would bury each.
//
// The answers here describe what this app actually does, including where it
// stops. Several of the most confusing moments in the app are confusing
// because the app is deliberately not making a clinical call — so the honest
// answer to "why won't it tell me X" is a section, not a missing feature.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/profile_section.dart';
import '../../widgets/secondary_header.dart';

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

class _FaqGroup {
  final String title;
  final IconData icon;
  final List<_Faq> items;
  const _FaqGroup({
    required this.title,
    required this.icon,
    required this.items,
  });
}

const _groups = <_FaqGroup>[
  _FaqGroup(
    title: 'Records',
    icon: Icons.folder_open_rounded,
    items: [
      _Faq(
        'A record I just saved is not showing up.',
        'Pull down on the list to refresh. If it is still missing, check that '
            'you saved it under the right mother — records are attached to the '
            'pregnancy that was open when you tapped Save. Ultrasound and lab '
            'entries are ordered by their recording date, so a record dated '
            'earlier will appear further down rather than at the top.',
      ),
      _Faq(
        'Why do ultrasound and lab images take a moment to appear?',
        'Images load after the rest of the record so the details are readable '
            'straight away rather than waiting on the picture. If an image '
            'never appears, open the record again while on a stronger '
            'connection — the file is on the server, not on the phone.',
      ),
      _Faq(
        'Can I edit or delete a record after saving it?',
        'Records are kept as entered. If something was recorded wrongly, add a '
            'new entry with the correct values and note the correction in the '
            'remarks, so the history shows what was believed at the time and '
            'what replaced it. Nothing that was used to make a decision '
            'silently disappears.',
      ),
      _Faq(
        'What is the difference between the conducting date and the recording '
        'date?',
        'The conducting date is when the ultrasound or laboratory test was '
            'actually performed. The recording date is when it was entered '
            'here. They differ whenever you enter a result brought in from '
            'another facility, and both are shown so the gap is visible.',
      ),
    ],
  ),
  _FaqGroup(
    title: 'Assessments and analysis',
    icon: Icons.insights_rounded,
    items: [
      _Faq(
        'Why does the app not say whether a mother has a condition?',
        'Because that is your call, not the app\'s. InaAgapay compares a '
            'reading against published thresholds and reports where it sits — '
            '"at or above 140/90", "samples at or above the screening '
            'threshold". It does not diagnose gestational hypertension, '
            'pre-eclampsia or gestational diabetes. Those are clinical '
            'diagnoses, and a record system that appears to make them invites '
            'someone to act on it without an assessment.',
      ),
      _Faq(
        'Where do the thresholds come from?',
        'Each analysis card carries a "Clinical Disclaimer & References" '
            'section listing the source it applies — ACOG and DOH for blood '
            'pressure, IOM/NRC for weight gain in pregnancy, and the WHO Child '
            'Growth Standards for child growth. Open it on any card to see '
            'exactly which rule produced what you are looking at.',
      ),
      _Faq(
        'The app flagged a reading but I disagree with it.',
        'Use the risk override on the record. Your assessment is what is '
            'stored against the pregnancy — the automatic reading is a prompt '
            'to look, not a decision. Overrides are recorded, so the profile '
            'shows the judgement you made rather than the value that triggered '
            'it.',
      ),
      _Faq(
        'What does the AI actually do?',
        'It rewrites findings already recorded into plainer wording, mostly '
            'for the mother\'s app. It does not decide risk levels, does not '
            'generate results, and nothing it writes reaches a mother until a '
            'midwife has approved it. Where a summary is AI-assisted, the card '
            'says so.',
      ),
    ],
  ),
  _FaqGroup(
    title: 'Immunization and stock',
    icon: Icons.vaccines_outlined,
    items: [
      _Faq(
        'Why can I not administer the next Td dose yet?',
        'The DOH schedule sets a minimum interval between doses, and the Td '
            'page shows the exact date the next one becomes due along with the '
            'interval it is waiting on. Administering earlier does not extend '
            'protection, which is why the form stays closed until the date.',
      ),
      _Faq(
        'A vaccine shows as "Past due" — has the child missed it?',
        'It means the recommended age has passed without a dose recorded. It '
            'does not mean the series has to restart. Record the dose when it '
            'is given and the roadmap will update; the vaccination history '
            'shows the age at each dose so the delay stays visible.',
      ),
      _Faq(
        'An open vial alert says doses will be discarded.',
        'A multi-dose vial has a shelf limit once opened. The alert appears '
            'while there are still doses in the vial so they can be used '
            'before the limit, and again once the limit has passed so the vial '
            'is discarded rather than drawn from.',
      ),
      _Faq(
        'How do I get more stock?',
        'Open the alert and tap Request Stock, or go to Inventory and raise '
            'the request there. The request goes to your RHU; the '
            'notifications page tells you when it is approved, rejected, or in '
            'transit.',
      ),
    ],
  ),
  _FaqGroup(
    title: 'Notifications and schedules',
    icon: Icons.notifications_none_rounded,
    items: [
      _Faq(
        'Alerts I marked as read keep coming back.',
        'Clinical notifications are stored on the server and stay read '
            'everywhere. Stock and expiry alerts are worked out from your '
            'current inventory each time the page opens, so their read state '
            'is kept on this device only — signing in on another phone will '
            'show them as unread. If a warning appears at the top of the page '
            'saying read marks cannot be saved, tell your administrator.',
      ),
      _Faq(
        'Can I turn some alerts off?',
        'Yes — Settings, then Alerts. Switching a category off hides it from '
            'your notifications page. It does not change the underlying '
            'situation: stock still runs out whether or not you are being '
            'told about it.',
      ),
      _Faq(
        'Does a mother get reminded about her appointment?',
        'Scheduled visits and vaccination drives send an SMS reminder the day '
            'before, to the number on her account. If her number is wrong or '
            'missing, the reminder cannot reach her — check it on her profile.',
      ),
    ],
  ),
  _FaqGroup(
    title: 'Account and access',
    icon: Icons.lock_outline_rounded,
    items: [
      _Faq(
        'How do I change my password?',
        'Open the account menu, then My Profile, then Change password. You '
            'will need your current password. If you are still on the '
            'temporary password issued with your account, the profile page '
            'says so until you replace it.',
      ),
      _Faq(
        'How do I change my profile photo?',
        'My Profile, then Add a photo or Change photo. The photo is stored '
            'with your account and appears on the avatar in the top corner.',
      ),
      _Faq(
        'I forgot my password.',
        'Sign out and use Forgot Password on the sign-in screen. A code is '
            'sent to the mobile number or email on your account. If neither is '
            'reachable, your administrator can reset the account for you.',
      ),
      _Faq(
        'Who can see the records I enter?',
        'Records are visible to staff at your health centre and to the mother '
            'herself, in her own app. Treat what you enter as part of her '
            'permanent health record.',
      ),
    ],
  ),
];

class MidwifeHelpPage extends StatefulWidget {
  const MidwifeHelpPage({super.key});

  @override
  State<MidwifeHelpPage> createState() => _MidwifeHelpPageState();
}

class _MidwifeHelpPageState extends State<MidwifeHelpPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Groups with only the questions matching the search, dropping groups that
  /// end up empty.
  List<_FaqGroup> get _visibleGroups {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _groups;

    final result = <_FaqGroup>[];
    for (final group in _groups) {
      final matches = group.items
          .where((f) =>
              f.question.toLowerCase().contains(q) ||
              f.answer.toLowerCase().contains(q))
          .toList();
      if (matches.isNotEmpty) {
        result.add(_FaqGroup(
          title: group.title,
          icon: group.icon,
          items: matches,
        ));
      }
    }
    return result;
  }

  int get _totalQuestions =>
      _groups.fold(0, (sum, group) => sum + group.items.length);

  @override
  Widget build(BuildContext context) {
    final groups = _visibleGroups;
    final matchCount = groups.fold<int>(0, (sum, g) => sum + g.items.length);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: 'Help',
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildSearch(matchCount),
          const SizedBox(height: 14),
          if (groups.isEmpty)
            _buildNoMatches()
          else
            for (final group in groups) ...[
              _buildGroup(group),
              const SizedBox(height: 14),
            ],
          _buildContactCard(),
        ],
      ),
    );
  }

  Widget _buildSearch(int matchCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.search_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search help',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                    hintStyle: TextStyle(
                        fontSize: 13.5, color: AppColors.textSecondary),
                  ),
                  style: const TextStyle(
                      fontSize: 13.5, color: AppColors.textPrimary),
                ),
              ),
              if (_query.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            _query.isEmpty
                ? '$_totalQuestions questions across ${_groups.length} topics'
                : '$matchCount of $_totalQuestions questions match',
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildGroup(_FaqGroup group) {
    return ProfileCardSection(
      title: group.title,
      icon: group.icon,
      actionButton: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${group.items.length}',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
      ),
      children: [
        for (final faq in group.items) _FaqTile(faq: faq),
      ],
    );
  }

  Widget _buildNoMatches() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded,
              size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            'Nothing here matches "${_search.text.trim()}"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a shorter word, or ask your RHU supervisor.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    return ProfileCardSection(
      title: 'Still stuck',
      icon: Icons.support_agent_rounded,
      children: [
        const Text(
          'For anything this page does not answer — an account that will not '
          'sign in, stock that looks wrong in the system, or a record you '
          'believe is attached to the wrong mother — contact your RHU '
          'supervisor or the system administrator at your health centre.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.brandSecondary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.brandPrimary.withValues(alpha: 0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.brandPrimary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'In an obstetric emergency, follow your facility\'s referral '
                  'protocol. Do not wait on anything in this app.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FaqTile extends StatefulWidget {
  final _Faq faq;
  const _FaqTile({required this.faq});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.faq.question,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              _open ? FontWeight.w700 : FontWeight.w600,
                          height: 1.35,
                          color: _open
                              ? AppColors.brandText
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.brandPrimary,
                    ),
                  ],
                ),
                if (_open) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.faq.answer,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
