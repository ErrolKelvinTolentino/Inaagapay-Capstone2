import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/notification_service.dart';
import '../../services/auth_storage.dart';
import '../../theme/app_colors.dart';
import '../../services/language_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/secondary_header.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  int? _accountId;
  bool _isUnlinked = false;
  int? _motherId;
  int? _pregnancyId;
  DateTime? _lmpDate;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null || !mounted) return;
      _accountId = accountId;

      final motherId = await AuthStorage.getMotherId();
      _motherId = motherId;
      bool unlinked = false;
      bool vitalsIncomplete = false;
      if (motherId != null) {
        final motherResponse = await SupabaseService.client
            .from('mothers')
            .select('assigned_bhc_id, height')
            .eq('mother_id', motherId)
            .maybeSingle();
        unlinked = motherResponse == null || motherResponse['assigned_bhc_id'] == null;
        final double? motherHeight = motherResponse != null && motherResponse['height'] != null
            ? (motherResponse['height'] as num).toDouble()
            : null;

        final pregnancyResponse = await SupabaseService.client
            .from('pregnancies')
            .select('pregnancy_id, last_menstrual_period, pre_pregnancy_weight')
            .eq('mother_id', motherId)
            .eq('status', 'ongoing')
            .maybeSingle();

        if (pregnancyResponse != null) {
          _pregnancyId = pregnancyResponse['pregnancy_id'] as int?;
          final lmpStr = pregnancyResponse['last_menstrual_period'] as String?;
          if (lmpStr != null && lmpStr.isNotEmpty) {
            _lmpDate = DateTime.tryParse(lmpStr);
          }
          final double? ppw = pregnancyResponse['pre_pregnancy_weight'] != null
              ? (pregnancyResponse['pre_pregnancy_weight'] as num).toDouble()
              : null;
          vitalsIncomplete = (motherHeight == null || ppw == null);
        }
      }

      final notifications = await NotificationService.getNotifications(accountId);
      if (!mounted) return;
      setState(() {
        _isUnlinked = unlinked;
        _notifications = List<Map<String, dynamic>>.from(notifications);
        if (_isUnlinked) {
          _notifications.insert(0, {
            'notification_id': -999,
            'title': LanguageService.translate('Action Required: Link BHC', 'Kailangang Aksyon: I-link ang BHC'),
            'message': LanguageService.translate(
              'Your account is not linked to a Barangay Health Center. Tap to view linking instructions.',
              'Ang iyong account ay hindi naka-link sa isang Barangay Health Center. Pindutin para sa detalye ng pag-link.'
            ),
            'type': 'unlinked_bhc',
            'is_read': false,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        if (vitalsIncomplete) {
          _notifications.insert(0, {
            'notification_id': -998,
            'title': LanguageService.translate('Action Required: Complete Vitals Setup', 'Kailangang Aksyon: Kumpletuhin ang Vitals Setup'),
            'message': LanguageService.translate(
              'Please provide your height, current weight, and pre-pregnancy weight to unlock weight gain tracking and advanced features.',
              'Mangyaring ilagay ang iyong taas, kasalukuyang timbang, at timbang bago mabuntis upang ma-unlock ang weight gain tracking at iba pang features.'
            ),
            'type': 'vitals_incomplete',
            'is_read': false,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    if (_accountId == null) return;
    await NotificationService.markAllAsRead(_accountId!);
    if (!mounted) return;
    setState(() {
      for (var n in _notifications) {
        n['is_read'] = true;
      }
    });
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'checkup_reminder':
        return Icons.medical_services_outlined;
      case 'vaccine_reminder':
        return Icons.vaccines_outlined;
      case 'unlinked_bhc':
      case 'vitals_incomplete':
        return Icons.warning_amber_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String? type) {
    switch (type) {
      case 'checkup_reminder':
        return AppColors.brandPrimary;
      case 'vaccine_reminder':
        return AppColors.brandAccent;
      case 'unlinked_bhc':
      case 'vitals_incomplete':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  void _showHowToLinkDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.medical_services_outlined,
                      color: AppColors.brandPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      LanguageService.translate('How to Link to a BHC', 'Paano I-link sa BHC'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                LanguageService.translate(
                  'To link your account to a Barangay Health Center (BHC) and begin official midwife monitoring, follow these steps:',
                  'Upang i-link ang iyong account sa isang Barangay Health Center (BHC) at magsimula ng opisyal na pagsubaybay ng midwife, sundin ang mga hakbang na ito:',
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _buildStepRow(
                  '1',
                  LanguageService.translate('Visit your nearest Barangay Health Center (BHC).',
                      'Pumunta sa iyong pinakamalapit na Barangay Health Center (BHC).')),
              const SizedBox(height: 12),
              _buildStepRow(
                  '2',
                  LanguageService.translate('Provide the midwife with your registered email address or phone number.',
                      'Ibigay sa midwife ang iyong rehistradong email address o numero ng telepono.')),
              const SizedBox(height: 12),
              _buildStepRow(
                  '3',
                  LanguageService.translate('The midwife will complete your linking process in the system, and your record will update automatically.',
                      'Tatapusin ng midwife ang proseso ng pag-link sa system, at awtomatikong mag-a-update ang iyong tala.')),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(LanguageService.translate('Got it!', 'Nakuha ko!')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.bgSecondary,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.brandText,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => n['is_read'] == false);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      // SecondaryHeader instead of a bare AppBar: it is the shared header the
      // rest of the app's inner pages use, so this screen stops looking like
      // a different application — brand-pink centred title, back arrow on the
      // left, action on the right.
      body: Column(
        children: [
          SecondaryHeader(
            title: LanguageService.translate('Notifications', 'Mga Abiso'),
            onBack: () => Navigator.pop(context),
            trailing: hasUnread
                ? TextButton(
                    onPressed: _markAllRead,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandPrimary,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(LanguageService.translate(
                        'Mark all read', 'Markahang basa')),
                  )
                : null,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_none_rounded,
                            size: 40, color: AppColors.brandPrimary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        LanguageService.translate(
                            'No notifications yet', 'Wala pang abiso'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        LanguageService.translate(
                          'Reminders from your health center appear here.',
                          'Lalabas dito ang mga paalala mula sa health center.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final n = _notifications[index];
                      final isRead = n['is_read'] == true;
                      final type = n['type'] as String?;
                      final isUnlinkedBhc = type == 'unlinked_bhc';
                      final isVitalsIncomplete = type == 'vitals_incomplete';
                      // The two "do something" notices behave alike: they
                      // carry no timestamp and are never marked read by
                      // tapping, so they share one flag rather than repeating
                      // the pair at every branch.
                      final isAction = isUnlinkedBhc || isVitalsIncomplete;
                      final createdAt = DateTime.tryParse(n['created_at'] ?? '');
                      final timeText = createdAt != null
                          ? DateFormat('MMM d, h:mm a').format(createdAt.toLocal())
                          : '';

                      return GestureDetector(
                        onTap: () async {
                          if (isUnlinkedBhc) {
                            _showHowToLinkDialog();
                            return;
                          }
                          if (isVitalsIncomplete) {
                            if (_motherId != null && _pregnancyId != null) {
                              _showSetupVitalsBottomSheet(
                                motherId: _motherId!,
                                pregnancyId: _pregnancyId!,
                                lmpDate: _lmpDate,
                              );
                            }
                            return;
                          }
                          if (!isRead) {
                            await NotificationService.markAsRead(n['notification_id']);
                            setState(() => n['is_read'] = true);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            // Cards are white, like every other card in the
                            // app. Unread is carried by the accent bar, the
                            // dot and the bolder title rather than by tinting
                            // the whole surface — a page of pink-washed cards
                            // made everything look equally urgent.
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isAction
                                  ? AppColors.warning.withValues(alpha: 0.35)
                                  : AppColors.brandPrimary
                                      .withValues(alpha: 0.15),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon in a tinted disc, the same treatment the
                              // dashboard and Children cards use.
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: _colorForType(type)
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(_iconForType(type),
                                    color: _colorForType(type), size: 21),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n['title'] ?? 'Notification',
                                      style: TextStyle(
                                        fontWeight: isRead
                                            ? FontWeight.w600
                                            : FontWeight.w800,
                                        fontSize: 14.5,
                                        height: 1.25,
                                        color: isRead
                                            ? AppColors.textPrimary
                                            : AppColors.brandText,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      n['message'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.35,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (!isAction) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                              Icons.schedule_rounded,
                                              size: 11,
                                              color: AppColors.textSecondary),
                                          const SizedBox(width: 4),
                                          Text(
                                            timeText,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!isRead && !isAction) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 9,
                                  height: 9,
                                  margin: const EdgeInsets.only(top: 5),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.brandPrimary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
  }

  String _t(String en, String tl) {
    return LanguageService.translate(en, tl);
  }

  void _showSetupVitalsBottomSheet({
    required int motherId,
    required int pregnancyId,
    required DateTime? lmpDate,
  }) {
    final heightCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final ppwCtrl = TextEditingController();

    String? heightError;
    String? heightWarning;
    String? weightError;
    String? weightWarning;
    String? ppwError;
    String? ppwWarning;

    double? calculatedBMI;
    String? bmiClassification;
    String? bmiWarning;
    bool isSaving = false;

    // Calculate week from lmpDate
    final week = lmpDate != null ? DateTime.now().difference(lmpDate).inDays ~/ 7 : 0;
    final currentWeek = week < 1 ? 1 : (week > 40 ? 40 : week);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          void calculateBMI() {
            final height = double.tryParse(heightCtrl.text.trim());
            final ppw = double.tryParse(ppwCtrl.text.trim());

            if (height != null && ppw != null && height > 0) {
              final heightM = height / 100;
              final bmi = ppw / (heightM * heightM);
              calculatedBMI = bmi;

              if (bmi < 18.5) {
                bmiClassification = _t('Underweight', 'Kulang sa Timbang');
              } else if (bmi < 25) {
                bmiClassification = _t('Normal', 'Normal');
              } else if (bmi < 30) {
                bmiClassification = _t('Overweight', 'Sobra sa Timbang');
              } else {
                bmiClassification = _t('Obese', 'Obese');
              }

              // Gestational weight gain recommendations based on BMI
              if (currentWeek <= 12) {
                bmiWarning = _t(
                  'Recommended total weight gain for this week (Week $currentWeek) is 0.5 - 2.0 kg.',
                  'Ang inirerekomendang kabuuang dagdag-timbang para sa linggong ito (Linggo $currentWeek) ay 0.5 - 2.0 kg.',
                );
              } else {
                final double minRate;
                final double maxRate;
                if (bmi < 18.5) {
                  minRate = 0.44;
                  maxRate = 0.58;
                } else if (bmi < 25) {
                  minRate = 0.35;
                  maxRate = 0.50;
                } else if (bmi < 30) {
                  minRate = 0.23;
                  maxRate = 0.33;
                } else {
                  minRate = 0.17;
                  maxRate = 0.27;
                }
                final minGain = 0.5 + (currentWeek - 12) * minRate;
                final maxGain = 2.0 + (currentWeek - 12) * maxRate;
                bmiWarning = _t(
                  'Recommended total weight gain for this week (Week $currentWeek) is ${minGain.toStringAsFixed(1)} - ${maxGain.toStringAsFixed(1)} kg.',
                  'Ang inirerekomendang kabuuang dagdag-timbang para sa linggong ito (Linggo $currentWeek) ay ${minGain.toStringAsFixed(1)} - ${maxGain.toStringAsFixed(1)} kg.',
                );
              }
            } else {
              calculatedBMI = null;
              bmiClassification = null;
              bmiWarning = null;
            }
          }

          void validateInputs() {
            final height = double.tryParse(heightCtrl.text.trim());
            final weight = double.tryParse(weightCtrl.text.trim());
            final ppw = double.tryParse(ppwCtrl.text.trim());

            setModalState(() {
              // Height validation
              if (heightCtrl.text.trim().isEmpty) {
                heightError = _t('Height is required', 'Kailangan ang taas');
                heightWarning = null;
              } else if (height == null) {
                heightError = _t('Enter a valid number', 'Maglayag ng wastong numero');
                heightWarning = null;
              } else if (height < 50 || height > 250) {
                heightError = _t('Must be 50-250 cm', 'Dapat ay 50-250 cm');
                heightWarning = null;
              } else {
                heightError = null;
                if (height < 120) {
                  heightWarning = _t(
                    'Entered measurement is outside expected maternal ranges. Please verify.',
                    'Ang inilagay na sukat ay labas sa inaasahang maternal range. Mangyaring i-verify.',
                  );
                } else {
                  heightWarning = null;
                }
              }

              // Weight validation
              if (weightCtrl.text.trim().isEmpty) {
                weightError = _t('Weight is required', 'Kailangan ang timbang');
                weightWarning = null;
              } else if (weight == null) {
                weightError = _t('Enter a valid number', 'Maglayag ng wastong numero');
                weightWarning = null;
              } else if (weight < 10 || weight > 350) {
                weightError = _t('Must be 10-350 kg', 'Dapat ay 10-350 kg');
                weightWarning = null;
              } else {
                weightError = null;
                if (weight < 35) {
                  weightWarning = _t(
                    'Entered measurement is outside expected maternal ranges. Please verify.',
                    'Ang inilagay na sukat ay labas sa inaasahang maternal range. Mangyaring i-verify.',
                  );
                } else {
                  weightWarning = null;
                }
              }

              // Pre-pregnancy weight validation
              if (ppwCtrl.text.trim().isEmpty) {
                ppwError = _t('Pre-pregnancy weight is required', 'Kailangan ang timbang bago mabuntis');
                ppwWarning = null;
              } else if (ppw == null) {
                ppwError = _t('Enter a valid number', 'Maglayag ng wastong numero');
                ppwWarning = null;
              } else if (ppw < 10 || ppw > 350) {
                ppwError = _t('Must be 10-350 kg', 'Dapat ay 10-350 kg');
                ppwWarning = null;
              } else {
                ppwError = null;
                if (ppw < 35) {
                  ppwWarning = _t(
                    'Entered measurement is outside expected maternal ranges. Please verify.',
                    'Ang inilagay na sukat ay labas sa inaasahang maternal range. Mangyaring i-verify.',
                  );
                } else {
                  ppwWarning = null;
                }
              }

              calculateBMI();
            });
          }

          Future<void> saveVitals() async {
            validateInputs();
            if (heightError != null || weightError != null || ppwError != null) return;

            final height = double.parse(heightCtrl.text.trim());
            final weight = double.parse(weightCtrl.text.trim());
            final ppw = double.parse(ppwCtrl.text.trim());

            setModalState(() => isSaving = true);

            try {
              // Update mothers table
              await SupabaseService.client
                  .from('mothers')
                  .update({'height': height})
                  .eq('mother_id', motherId);

              // Update pregnancies table
              await SupabaseService.client
                  .from('pregnancies')
                  .update({'pre_pregnancy_weight': ppw})
                  .eq('pregnancy_id', pregnancyId);

              // Insert into maternal_vitals table
              double? aogWeeks;
              if (lmpDate != null) {
                aogWeeks = DateTime.now().difference(lmpDate).inDays / 7.0;
              }
              await SupabaseService.client.from('maternal_vitals').insert({
                'pregnancy_id': pregnancyId,
                'mother_id': motherId,
                'weight_kg': weight,
                'height_cm': height,
                'age_of_gestation': aogWeeks != null ? double.parse(aogWeeks.toStringAsFixed(1)) : null,
                'notes': 'Vitals entered during notifications profile completion alert',
                'recorded_at': DateTime.now().toIso8601String(),
              });

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(_t('Vitals setup completed successfully!', 'Matagumpay na nakumpleto ang pag-setup ng vitals!')),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              if (mounted) {
                // Reload notifications list
                _loadNotifications();
              }
            } catch (e) {
              setModalState(() => isSaving = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(_t('Error saving vitals: ', 'Kamalian sa pag-save ng vitals: ') + e.toString()),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _t('Complete Vitals Setup', 'Kumpletuhin ang Vitals Setup'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _t(
                      'Please provide your measurements to unlock advanced weight gain tracking and insights.',
                      'Mangyaring ibigay ang iyong mga sukat upang ma-unlock ang advanced weight gain tracking at mga insight.',
                    ),
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),

                  // Height Input
                  Text(
                    _t('Height (cm)', 'Taas (cm)'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    hintText: 'e.g. 156.0',
                    controller: heightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    leadingIcon: Icons.height,
                    errorText: heightError,
                    onChanged: (_) => validateInputs(),
                  ),
                  if (heightWarning != null) ...[
                    const SizedBox(height: 4),
                    Text(heightWarning!, style: const TextStyle(color: Colors.orange, fontSize: 11)),
                  ],
                  const SizedBox(height: 16),

                  // Current Weight Input
                  Text(
                    _t('Current Weight (kg)', 'Kasalukuyang Timbang (kg)'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    hintText: 'e.g. 62.5',
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    leadingIcon: Icons.monitor_weight_outlined,
                    errorText: weightError,
                    onChanged: (_) => validateInputs(),
                  ),
                  if (weightWarning != null) ...[
                    const SizedBox(height: 4),
                    Text(weightWarning!, style: const TextStyle(color: Colors.orange, fontSize: 11)),
                  ],
                  const SizedBox(height: 16),

                  // Pre-pregnancy Weight Input
                  Text(
                    _t('Pre-pregnancy Weight (kg)', 'Timbang bago mabuntis (kg)'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    hintText: 'e.g. 58.0',
                    controller: ppwCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    leadingIcon: Icons.monitor_weight_outlined,
                    errorText: ppwError,
                    onChanged: (_) => validateInputs(),
                  ),
                  if (ppwWarning != null) ...[
                    const SizedBox(height: 4),
                    Text(ppwWarning!, style: const TextStyle(color: Colors.orange, fontSize: 11)),
                  ],
                  const SizedBox(height: 20),

                  // BMI Display Card
                  if (calculatedBMI != null && bmiClassification != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.brandPrimary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _t('Calculated BMI: ${calculatedBMI!.toStringAsFixed(1)}',
                                   'Kinalkulang BMI: ${calculatedBMI!.toStringAsFixed(1)}'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.brandPrimary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  bmiClassification!,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.brandPrimary),
                                ),
                              ),
                            ],
                          ),
                          if (bmiWarning != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              bmiWarning!,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Save Button
                  ElevatedButton(
                    onPressed: isSaving ? null : saveVitals,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _t('Save Vitals', 'I-save ang Vitals'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
