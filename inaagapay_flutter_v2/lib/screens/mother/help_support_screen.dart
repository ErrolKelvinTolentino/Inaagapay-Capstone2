import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../services/language_service.dart';
import '../../services/auth_storage.dart';
import '../../widgets/main_button.dart';
import '../../widgets/secondary_header.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  bool _isLoading = true;
  String? _bhcName;
  int? _bhcId;
  List<Map<String, dynamic>> _midwives = [];

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  @override
  void initState() {
    super.initState();
    _loadBhcAndMidwives();
  }

  Future<void> _loadBhcAndMidwives() async {
    try {
      final motherId = await AuthStorage.getMotherId();
      if (motherId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final client = Supabase.instance.client;

      // 1. Fetch mother's assigned BHC
      final motherRes = await client
          .from('mothers')
          .select('assigned_bhc_id, bhc:assigned_bhc_id (bhc_name)')
          .eq('mother_id', motherId)
          .maybeSingle();

      if (motherRes != null && motherRes['assigned_bhc_id'] != null) {
        _bhcId = motherRes['assigned_bhc_id'] as int;
        _bhcName = motherRes['bhc']?['bhc_name']?.toString() ?? 'Barangay Health Center';

        // 2. Fetch midwives assigned to this BHC
        final midwivesRes = await client
            .from('midwives')
            .select('''
              midwife_id,
              account:account_id (
                first_name,
                last_name,
                phone_number
              )
            ''')
            .eq('assigned_bhc_id', _bhcId!);

        final List<Map<String, dynamic>> loadedMidwives = [];
        for (var item in midwivesRes) {
          final acc = item['account'] as Map<String, dynamic>?;
          if (acc != null) {
            loadedMidwives.add({
              'name': '${acc['first_name'] ?? ''} ${acc['last_name'] ?? ''}'.trim(),
              'phone': acc['phone_number']?.toString() ?? '',
            });
          }
        }
        _midwives = loadedMidwives;
      }
    } catch (e) {
      debugPrint('Error loading Help & Support contact data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _makeCall(String phone) async {
    if (phone.isEmpty) return;
    final Uri uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendSms(String phone) async {
    if (phone.isEmpty) return;
    final Uri uri = Uri(scheme: 'sms', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendEmail(String email) async {
    final Uri uri = Uri(scheme: 'mailto', path: email, query: 'subject=Inaagapay App Support');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 18),
      child: Row(
        children: [
          Icon(icon, color: AppColors.brandPrimary, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.brandText,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimaryOf(context),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: SecondaryHeader(
              title: _t('Help & Support', 'Tulong at Suporta'),
              onBack: () => Navigator.pop(context),
            ),
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.brandPrimary,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Barangay Health Center & Midwife Section
                      _buildBhcSupportCard(),

                      // 2. Interactive App Guide
                      _buildSectionHeader(_t('App Features Guide', 'Gabay sa mga Tampok ng App'), Icons.explore_outlined),
                      _buildFeaturesGuide(),

                      // 3. App FAQs
                      _buildSectionHeader(_t('Frequently Asked Questions', 'Mga Madalas Itanong'), Icons.help_outline_rounded),
                      _buildFaqSection(),
                      const SizedBox(height: 12),

                      // 4. Contact Technical Support
                      _buildTechSupportCard(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildBhcSupportCard() {
    final isLinked = _bhcName != null && _bhcId != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandPrimary.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Pink whether or not she is linked.
              //
              // The grey variant read as "disabled" — the tile went colourless
              // for exactly the mother this card is written for, the one who
              // still needs to register. Not being linked is a step she has
              // not taken, not a fault in her account.
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDF4),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.local_hospital_rounded,
                  color: AppColors.brandText,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('Your Assigned Health Center', 'Iyong Barangay Health Center'),
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        color: AppColors.headingSoft,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isLinked ? _bhcName! : _t('Not Linked', 'Hindi Nakakonekta'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isLinked ? AppColors.brandPrimary : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // A soft brand rule. A bare Divider takes the theme default, which
          // on this page drew a hard black line across the card.
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(
                height: 1, thickness: 1, color: Color(0xFFF5E4EC)),
          ),
          if (isLinked) ...[
            if (_midwives.isEmpty)
              Text(
                _t('No midwives are registered at this center yet.',
                    'Wala pang rehistradong midwife sa health center na ito.'),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              )
            else ...[
              Text(
                _t('Contact Midwives:', 'Makipag-ugnayan sa mga Midwife:'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.headingSoft,
                ),
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _midwives.length,
                itemBuilder: (context, index) {
                  final midwife = _midwives[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: AppColors.brandPrimary,
                          radius: 16,
                          child: Icon(Icons.person, size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                midwife['name'],
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.headingSoft,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                midwife['phone'],
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (midwife['phone'].isNotEmpty) ...[
                          IconButton(
                            icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.brandPrimary, size: 20),
                            onPressed: () => _makeCall(midwife['phone']),
                            tooltip: _t('Call Midwife', 'Tawagan'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.sms_rounded, color: AppColors.brandPrimary, size: 20),
                            onPressed: () => _sendSms(midwife['phone']),
                            tooltip: _t('Send SMS', 'I-text'),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ]
          ] else ...[
            Text(
              _t(
                'To connect your account to a local health center and get regular checkups, please visit your nearest Barangay Health Station (BHS). A registered midwife will link your profile using your registered name.',
                'Upang maikonekta ang iyong account sa isang lokal na health center at makatanggap ng checkups, pumunta sa pinakamalapit na Barangay Health Station (BHS). Ikokonekta ng midwife ang iyong profile gamit ang iyong pangalan.',
              ),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeaturesGuide() {
    final List<Map<String, dynamic>> features = [
      {
        'title': _t('Home (Bahay)', 'Home (Bahay)'),
        'desc': _t(
            'Displays your pregnancy countdown, estimated due date, upcoming midwife schedules, baby growth comparisons (size/weight), and personalized weight gain evaluations.',
            'Dito makikita ang countdown ng iyong pagbubuntis, takdang araw, mga schedule ng checkup, sukat at timbang ng iyong baby, at pagsusuri sa iyong timbang.'),
        'icon': Icons.home_outlined,
      },
      {
        'title': _t('Chat w/ Ate (Chatbot)', 'Chat kay Ate (Chatbot)'),
        'desc': _t(
            'Your virtual midwife helper. Ask anything about pregnancy symptoms, foods, baby milestones, or traditional remedies. Ate dynamically cross-references your active allergies and medical conditions to keep her recommendations 100% safe.',
            'Ang iyong virtual midwife helper. Magtanong tungkol sa mga sintomas, pagkain, o paglaki ng baby. Awtomatikong babasahin ni Ate ang iyong allergies at medical conditions para sa iyong kaligtasan.'),
        'icon': Icons.chat_bubble_outline_rounded,
      },
      {
        'title': _t('Journal (Talaarawan)', 'Journal (Talaarawan)'),
        'desc': _t(
            'Log your mood, physical symptoms, notes, and photos daily to create a beautiful diary of your motherhood journey.',
            'Itala ang iyong mood, pisikal na sintomas, mga tala, at kumuha ng litrato araw-araw para magkaroon ng diary ng iyong pagbubuntis.'),
        'icon': Icons.menu_book_outlined,
      },
      {
        'title': _t('Children (Mga Anak)', 'Children (Mga Anak)'),
        'desc': _t(
            'Manage vaccines and health profiles for your registered children. View their full immunization roadmaps and growth logs.',
            'Pamahalaan ang mga bakuna at profile ng iyong mga anak. Tingnan ang kanilang immunization roadmap at mga rekord ng paglaki.'),
        'icon': Icons.child_care_outlined,
      },
      {
        'title': _t('Records (Mga Tala)', 'Records (Mga Tala)'),
        'desc': _t(
            'View checkups, vitals histories, lab test results, and ultrasound records uploaded by your Barangay Health Center midwives.',
            'Tingnan ang iyong checkups, vitals history, resulta ng lab tests, at ultrasound records na in-upload ng iyong mga midwife.'),
        'icon': Icons.folder_outlined,
      },
      {
        'title': _t('Hotlines (Emergency)', 'Hotlines (Emergency)'),
        'desc': _t(
            'Direct access to national and local emergency hotlines including DOH Health (1555), Red Cross (143), general emergency (911), and mental health hotlines.',
            'Direktang tawag sa mga emergency hotline tulad ng DOH Health (1555), Red Cross (143), general emergency (911), at mental health hotlines.'),
        'icon': Icons.phone_outlined,
      },
    ];

    return Column(
      children: features.map((f) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.cardColorOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.brandPrimary.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandPrimary.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              shape: const RoundedRectangleBorder(
                side: BorderSide.none,
              ),
              collapsedShape: const RoundedRectangleBorder(
                side: BorderSide.none,
              ),
              leading: Icon(f['icon'], color: AppColors.brandPrimary),
              title: Text(
                f['title'],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.headingSoft,
                ),
              ),
              iconColor: AppColors.brandPrimary,
              collapsedIconColor: AppColors.textSecondary,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedAlignment: Alignment.topLeft,
              children: [
                Text(
                  f['desc'],
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFaqSection() {
    final List<Map<String, String>> faqs = [
      {
        'q': _t('How do I update my profile details?', 'Paano ko babaguhin ang aking profile?'),
        'a': _t(
            'Tap your Profile Picture avatar in the top-right corner of the Home screen, and select "View Profile". From there, you can view your personal details and change your avatar or passwords.',
            'I-tap ang iyong Profile Picture avatar sa kanang itaas ng Home screen at piliin ang "View Profile". Doon ay maaari mong makita ang personal na detalye at mapalitan ang iyong larawan o password.'),
      },
      {
        'q': _t('Why is my health center status listed as "Not Linked"?', 'Bakit nakalagay na "Not Linked" ang aking health center?'),
        'a': _t(
            'This means you haven\'t been officially assigned to a Barangay Health Center in our database. Please ask your midwife during your next health checkup to link your account so you can view records, receive SMS reminders, and synchronize schedules.',
            'Ito ay dahil hindi pa naidudugtong ang iyong account sa Barangay Health Center sa database. Sabihan ang iyong midwife sa susunod mong checkup na i-link ang iyong profile para makita mo ang mga tala, makatanggap ng paalala, at makuha ang schedules.'),
      },
      {
        'q': _t('What should I do if I notice a pregnancy danger sign?', 'Ano ang dapat kong gawin kung makaranas ng danger sign?'),
        'a': _t(
            'If you experience vaginal bleeding, severe abdominal pain, high fever, blurred vision, severe headaches, or sudden reduction of baby movements, please seek immediate medical attention. Use the "Hotlines" tab to call emergency medical hotlines directly.',
            'Kung nakaranas ng pagdurugo, matinding sakit ng tiyan, mataas na lagnat, panlalabo ng paningin, matinding sakit ng ulo, o biglang pagbawas ng galaw ng baby, magpatingin agad sa ospital. Gamitin ang "Hotlines" tab para direktang makatawag sa emergency services.'),
      },
      {
        'q': _t('How does the chatbot know my allergies?', 'Paano nalalaman ng chatbot ang aking allergies?'),
        'a': _t(
            'The app retrieves your active allergies and medical conditions recorded by your midwife. The chatbot reads these details to customize diet or exercise suggestions. You can hide specific categories from the AI by clicking the Shield icon in the chatbot screen.',
            'Kinukuha ng app ang iyong allergies at medical conditions na itinala ng midwife. Binabasa ito ng chatbot para maging ligtas ang rekomendasyon. Maaari mong itago ang iba pang detalye sa AI sa pamamagitan ng pag-tap sa Shield icon sa chatbot page.'),
      },
    ];

    return Column(
      children: faqs.map((faq) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.cardColorOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.brandPrimary.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandPrimary.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              shape: const RoundedRectangleBorder(
                side: BorderSide.none,
              ),
              collapsedShape: const RoundedRectangleBorder(
                side: BorderSide.none,
              ),
              title: Text(
                faq['q']!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.headingSoft,
                ),
              ),
              iconColor: AppColors.brandPrimary,
              collapsedIconColor: AppColors.textSecondary,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedAlignment: Alignment.topLeft,
              children: [
                Text(
                  faq['a']!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTechSupportCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandPrimary.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.support_agent_rounded,
            color: AppColors.brandPrimary,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            _t('Need Technical Help?', 'Kailangan ng Teknikal na Tulong?'),
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: AppColors.headingSoft,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'If you are experiencing issues with the app, passwords, or offline synchronization, contact our technical support team.',
              'Kung nakararanas ng problema sa app, password, o synchronization, makipag-ugnayan sa aming technical support team.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          MainButton(
            onPressed: () => _sendEmail('support@inaagapay.gov.ph'),
            leftIcon: Icons.email_outlined,
            label: _t('Email App Support', 'I-email ang App Support'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Inaagapay Capstone v2.0.0',
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
