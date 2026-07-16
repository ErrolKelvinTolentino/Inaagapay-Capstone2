import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../theme/app_colors.dart';
import '../../services/sms_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/secondary_header.dart';

class MidwifeSmsRemindersScreen extends StatefulWidget {
  const MidwifeSmsRemindersScreen({super.key});

  @override
  State<MidwifeSmsRemindersScreen> createState() => _MidwifeSmsRemindersScreenState();
}

class _MidwifeSmsRemindersScreenState extends State<MidwifeSmsRemindersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int? _smsCredits;
  bool _isLoadingCredits = true;
  bool _isLoadingData = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _vaccineReminders = [];
  String _bhcName = 'Barangay Health Center';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingCredits = true;
      _isLoadingData = true;
    });

    await Future.wait([
      _fetchBalanceAndBhc(),
      _loadCheckupReminders(),
      _loadVaccineReminders(),
    ]);

    setState(() {
      _isLoadingCredits = false;
      _isLoadingData = false;
    });
  }

  Future<void> _fetchBalanceAndBhc() async {
    try {
      final balance = await SmsService.getCreditBalance();
      
      // Fetch BHC name assigned to this midwife
      final session = Supabase.instance.client.auth.currentSession;
      final accountId = session?.user.id;
      
      if (accountId != null) {
        final midwifeResponse = await Supabase.instance.client
            .from('midwives')
            .select('assigned_bhc_id, bhc:assigned_bhc_id (bhc_name)')
            .eq('account_id', accountId)
            .maybeSingle();

        if (midwifeResponse != null && midwifeResponse['bhc'] != null) {
          _bhcName = midwifeResponse['bhc']['bhc_name']?.toString() ?? 'Barangay Health Center';
        }
      }

      setState(() {
        _smsCredits = balance;
        _isLoadingCredits = false;
      });
    } catch (e) {
      debugPrint('Error loading balance or BHC: $e');
      setState(() {
        _isLoadingCredits = false;
      });
    }
  }

  Future<void> _loadCheckupReminders() async {
    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 1. Fetch from checkup_schedule
      final scheduleRes = await Supabase.instance.client
          .from('checkup_schedule')
          .select('''
            schedule_id,
            scheduled_date,
            notes,
            status,
            mother:mother_id (
              mother_id,
              account:account_id (
                first_name,
                last_name,
                phone_number
              )
            )
          ''')
          .gte('scheduled_date', todayStr)
          .eq('status', 'scheduled')
          .order('scheduled_date');

      // 2. Fetch from prenatal_checkups next_schedule
      final checkupsRes = await Supabase.instance.client
          .from('prenatal_checkups')
          .select('''
            prenatal_checkup_id,
            next_schedule,
            remarks,
            pregnancy:pregnancy_id (
              mother:mother_id (
                mother_id,
                account:account_id (
                  first_name,
                  last_name,
                  phone_number
                )
              )
            )
          ''')
          .gte('next_schedule', todayStr)
          .order('next_schedule');

      final List<Map<String, dynamic>> list = [];
      final seenCheckups = <String>{};

      // Add prenatal checkups next schedules
      for (final pc in checkupsRes) {
          if (pc['next_schedule'] == null) continue;
          final dateStr = pc['next_schedule'].toString();
          final pregnancy = pc['pregnancy'] as Map<String, dynamic>?;
          final mother = pregnancy?['mother'] as Map<String, dynamic>?;
          if (mother == null) continue;
          final motherId = mother['mother_id'] as int;
          final account = mother['account'] as Map<String, dynamic>?;
          if (account == null) continue;

          final firstName = account['first_name']?.toString() ?? '';
          final lastName = account['last_name']?.toString() ?? '';
          final motherName = '$firstName $lastName'.trim();
          final phoneNumber = account['phone_number']?.toString() ?? '';

          if (phoneNumber.isEmpty) continue;

          final key = '${motherId}_$dateStr';
          if (!seenCheckups.contains(key)) {
            seenCheckups.add(key);
            list.add({
              'type': 'Prenatal Checkup',
              'mother_name': motherName.isNotEmpty ? motherName : 'Mother',
              'phone_number': phoneNumber,
              'scheduled_date': DateTime.parse(dateStr),
              'notes': pc['remarks']?.toString() ?? 'Routine Prenatal Checkup',
            });
          }
      }

      // Add checkup schedule entries
      for (final cs in scheduleRes) {
          if (cs['scheduled_date'] == null) continue;
          final dateStr = cs['scheduled_date'].toString();
          final mother = cs['mother'] as Map<String, dynamic>?;
          if (mother == null) continue;
          final motherId = mother['mother_id'] as int;
          final account = mother['account'] as Map<String, dynamic>?;
          if (account == null) continue;

          final firstName = account['first_name']?.toString() ?? '';
          final lastName = account['last_name']?.toString() ?? '';
          final motherName = '$firstName $lastName'.trim();
          final phoneNumber = account['phone_number']?.toString() ?? '';

          if (phoneNumber.isEmpty) continue;

          final key = '${motherId}_$dateStr';
          if (!seenCheckups.contains(key)) {
            seenCheckups.add(key);
            list.add({
              'type': 'Scheduled Checkup',
              'mother_name': motherName.isNotEmpty ? motherName : 'Mother',
              'phone_number': phoneNumber,
              'scheduled_date': DateTime.parse(dateStr),
              'notes': cs['notes']?.toString() ?? 'General Checkup Visit',
            });
          }
      }

      // Sort by date
      list.sort((a, b) => (a['scheduled_date'] as DateTime).compareTo(b['scheduled_date'] as DateTime));

      setState(() {
        _schedules = list;
      });
    } catch (e) {
      debugPrint('Error loading checkup reminders: $e');
    }
  }

  Future<void> _loadVaccineReminders() async {
    try {
      // 1. Fetch children
      final childrenRes = await Supabase.instance.client
          .from('children')
          .select('''
            child_id,
            first_name,
            last_name,
            mother:mother_id (
              mother_id,
              account:account_id (
                first_name,
                last_name,
                phone_number
              )
            ),
            birth_details:child_id (
              birthdate
            )
          ''');

      // 2. Fetch vaccines for children
      final vaccinesRes = await Supabase.instance.client
          .from('vaccines')
          .select('vaccine_id, vaccine_name, dose_number, recommended_age_months')
          .eq('target_recipients', 'child');

      // 3. Fetch completed immunization records
      final recordsRes = await Supabase.instance.client
          .from('immunization_record')
          .select('child_id, vaccine_id');

      final recordsMap = <int, Set<int>>{};
      for (final rec in recordsRes) {
          final childId = rec['child_id'] as int;
          final vaccineId = rec['vaccine_id'] as int;
          recordsMap.putIfAbsent(childId, () => {}).add(vaccineId);
      }

      final List<Map<String, dynamic>> vaccines = [];
      for (final v in vaccinesRes) {
          vaccines.add({
            'vaccine_id': v['vaccine_id'] as int,
            'vaccine_name': v['vaccine_name'] as String,
            'dose_number': v['dose_number'] as int,
            'recommended_age_months': (v['recommended_age_months'] as num).toDouble(),
          });
      }

      final List<Map<String, dynamic>> list = [];
      final now = DateTime.now();

      for (final c in childrenRes) {
          final childId = c['child_id'] as int;
          final childFirstName = c['first_name']?.toString() ?? '';
          final childLastName = c['last_name']?.toString() ?? '';
          final childName = '$childFirstName $childLastName'.trim();

          final birthDetailsList = c['birth_details'] as List?;
          final birthDetails = (birthDetailsList != null && birthDetailsList.isNotEmpty)
              ? birthDetailsList[0] as Map<String, dynamic>?
              : null;

          if (birthDetails == null || birthDetails['birthdate'] == null) continue;
          final birthdate = DateTime.parse(birthDetails['birthdate'].toString());

          // Calculate age in months
          final diffDays = now.difference(birthdate).inDays;
          final ageMonths = diffDays / 30.43;

          final mother = c['mother'] as Map<String, dynamic>?;
          if (mother == null) continue;
          final account = mother['account'] as Map<String, dynamic>?;
          if (account == null) continue;

          final motherFirstName = account['first_name']?.toString() ?? '';
          final motherLastName = account['last_name']?.toString() ?? '';
          final motherName = '$motherFirstName $motherLastName'.trim();
          final phoneNumber = account['phone_number']?.toString() ?? '';

          if (phoneNumber.isEmpty) continue;

          final completed = recordsMap[childId] ?? {};
          final List<Map<String, dynamic>> due = [];

          for (final v in vaccines) {
            if (ageMonths >= v['recommended_age_months'] && !completed.contains(v['vaccine_id'])) {
              due.add(v);
            }
          }

          if (due.isNotEmpty) {
            list.add({
              'child_id': childId,
              'child_name': childName.isNotEmpty ? childName : 'Child',
              'age_months': ageMonths,
              'birthdate': birthdate,
              'mother_name': motherName.isNotEmpty ? motherName : 'Mother',
              'phone_number': phoneNumber,
              'due_vaccines': due,
              'vaccines_list_str': due.map((v) => '${v['vaccine_name']} (Dose ${v['dose_number']})').join(', '),
            });
          }
      }

      setState(() {
        _vaccineReminders = list;
      });
    } catch (e) {
      debugPrint('Error loading vaccine reminders: $e');
    }
  }

  void _openSmsDialog({
    required String recipientName,
    required String phoneNumber,
    required String type, // 'checkup' or 'vaccine'
    String? dateStr,
    String? details,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _SmsComposeSheet(
          recipientName: recipientName,
          phoneNumber: phoneNumber,
          type: type,
          dateStr: dateStr,
          details: details,
          bhcName: _bhcName,
          onSentSuccess: () {
            _fetchBalanceAndBhc(); // reload balance
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> get _filteredSchedules {
    if (_searchQuery.trim().isEmpty) return _schedules;
    return _schedules.where((s) {
      final name = s['mother_name'].toString().toLowerCase();
      final phone = s['phone_number'].toString();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || phone.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredVaccines {
    if (_searchQuery.trim().isEmpty) return _vaccineReminders;
    return _vaccineReminders.where((v) {
      final childName = v['child_name'].toString().toLowerCase();
      final motherName = v['mother_name'].toString().toLowerCase();
      final phone = v['phone_number'].toString();
      final query = _searchQuery.toLowerCase();
      return childName.contains(query) || motherName.contains(query) || phone.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimaryOf(context),
      body: Column(
        children: [
          // Sleek dynamic header
          SecondaryHeader(
            title: 'SMS REMINDERS',
            onBack: () => Navigator.pop(context),
          ),

          // Dynamic credits widget
          _buildCreditsCard(),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: _tabController.index == 0
                      ? 'Search mothers...'
                      : 'Search children or mothers...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // Custom animated Tab Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderPrimary),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: AppColors.brandPrimary,
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: 'Checkup Schedule'),
                  Tab(text: 'Child Vaccines'),
                ],
              ),
            ),
          ),

          // Tab content view
          Expanded(
            child: _isLoadingData
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.brandPrimary),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCheckupsTab(),
                      _buildVaccinesTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditsCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brandPrimary, Color(0xFFFF85A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bhcName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Semaphore SMS Gateway',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _isLoadingCredits
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    children: [
                      const Icon(Icons.sms, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _smsCredits != null ? '$_smsCredits Credits' : 'Offline',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckupsTab() {
    final list = _filteredSchedules;

    if (list.isEmpty) {
      return _buildEmptyState(
        icon: Icons.calendar_today,
        title: _searchQuery.isEmpty ? 'No upcoming schedules found' : 'No matching schedules',
        subtitle: _searchQuery.isEmpty ? 'Mothers with next scheduled visits will appear here.' : 'Try searching another mother name or phone.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: AppColors.brandPrimary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final s = list[index];
          final date = s['scheduled_date'] as DateTime;
          final dateStr = DateFormat('MMMM d, yyyy').format(date);
          final daysLeft = date.difference(DateTime.now()).inDays;
          
          String urgencyLabel;
          Color urgencyColor;
          if (daysLeft <= 0) {
            urgencyLabel = 'Today';
            urgencyColor = AppColors.error;
          } else if (daysLeft == 1) {
            urgencyLabel = 'Tomorrow';
            urgencyColor = AppColors.warning;
          } else {
            urgencyLabel = 'In $daysLeft days';
            urgencyColor = AppColors.brandPrimary;
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderPrimary),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.1),
                  child: const Icon(Icons.pregnant_woman, color: AppColors.brandPrimary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              s['mother_name'],
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.brandText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: urgencyColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              urgencyLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: urgencyColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Phone: ${SmsService.formatDisplayNumber(s['phone_number'])}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.event, size: 14, color: AppColors.brandPrimary),
                          const SizedBox(width: 6),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brandText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.bgSecondary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          s['notes'],
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () => _openSmsDialog(
                            recipientName: s['mother_name'],
                            phoneNumber: s['phone_number'],
                            type: 'checkup',
                            dateStr: dateStr,
                            details: s['notes'],
                          ),
                          icon: const Icon(Icons.send_rounded, size: 14, color: Colors.white),
                          label: const Text('Send SMS Reminder', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildVaccinesTab() {
    final list = _filteredVaccines;

    if (list.isEmpty) {
      return _buildEmptyState(
        icon: Icons.vaccines,
        title: _searchQuery.isEmpty ? 'No due immunizations found' : 'No matching children',
        subtitle: _searchQuery.isEmpty ? 'Children with recommended and pending vaccines will appear here.' : 'Try searching another name.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: AppColors.brandPrimary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final v = list[index];
          final ageMonths = v['age_months'] as double;
          
          String ageStr;
          if (ageMonths < 1.0) {
            ageStr = '${(ageMonths * 30).toInt()} days';
          } else {
            ageStr = '${ageMonths.toStringAsFixed(1)} mos';
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderPrimary),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE3F2FD),
                  child: Icon(Icons.child_care, color: Colors.blue.shade700),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              v['child_name'],
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.brandText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              ageStr,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mother: ${v['mother_name']}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.brandText,
                        ),
                      ),
                      Text(
                        'Phone: ${SmsService.formatDisplayNumber(v['phone_number'])}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.medical_services, size: 14, color: AppColors.brandPrimary),
                          const SizedBox(width: 6),
                          const Text(
                            'Due Vaccines:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brandPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: Text(
                          v['vaccines_list_str'],
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandText,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () => _openSmsDialog(
                            recipientName: v['mother_name'],
                            phoneNumber: v['phone_number'],
                            type: 'vaccine',
                            details: v['vaccines_list_str'],
                            dateStr: v['child_name'], // pass child name in dateStr for vaccine message
                          ),
                          icon: const Icon(Icons.send_rounded, size: 14, color: Colors.white),
                          label: const Text('Send SMS Reminder', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.brandPrimary.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.brandText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── SMS COMPOSE SHEET ────────────────────────────────────────────────────────
class _SmsComposeSheet extends StatefulWidget {
  const _SmsComposeSheet({
    required this.recipientName,
    required this.phoneNumber,
    required this.type,
    this.dateStr,
    this.details,
    required this.bhcName,
    required this.onSentSuccess,
  });

  final String recipientName;
  final String phoneNumber;
  final String type;
  final String? dateStr;
  final String? details;
  final String bhcName;
  final VoidCallback onSentSuccess;

  @override
  State<_SmsComposeSheet> createState() => _SmsComposeSheetState();
}

class _SmsComposeSheetState extends State<_SmsComposeSheet> {
  final TextEditingController _msgCtrl = TextEditingController();
  String _language = 'fil'; // 'fil' or 'eng'
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _populateTemplate();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  void _populateTemplate() {
    final motherName = widget.recipientName;
    final bhcName = widget.bhcName;

    if (widget.type == 'checkup') {
      final checkupDate = widget.dateStr ?? 'Checkup Date';
      if (_language == 'fil') {
        _msgCtrl.text = 'InaAgapay: Magandang araw po Nanay $motherName! Remind lang po namin kayo mula sa $bhcName para sa inyong prenatal check-up sa $checkupDate. Mangyaring pumunta po sa health center at mag-ingat po kayo. Salamat!';
      } else {
        _msgCtrl.text = 'InaAgapay: Hello Mother $motherName! This is a reminder from $bhcName for your next prenatal check-up scheduled on $checkupDate. Please visit the health center and take care. Thank you!';
      }
    } else {
      final childName = widget.dateStr ?? 'Your child';
      final vaccineNames = widget.details ?? 'Recommended vaccines';
      if (_language == 'fil') {
        _msgCtrl.text = 'InaAgapay: Magandang araw po Nanay $motherName! Remind lang po namin kayo mula sa $bhcName na ang inyong anak na si $childName ay nakatakdang tumanggap ng mga sumusunod na bakuna: $vaccineNames. Mangyaring bumisita sa health center para sa kanilang pagbabakuna. Salamat po!';
      } else {
        _msgCtrl.text = 'InaAgapay: Hello Mother $motherName! This is a reminder from $bhcName that your child $childName is due for the following vaccine(s): $vaccineNames. Please visit the health center for immunization. Thank you!';
      }
    }
    setState(() {});
  }

  Future<void> _sendSms() async {
    final message = _msgCtrl.text.trim();
    if (message.isEmpty) {
      AppSnackbar.show(context, 'Please compose a message.', type: AppSnackType.warning);
      return;
    }

    setState(() => _sending = true);

    try {
      final success = await SmsService.sendSmsMessage(widget.phoneNumber, message);
      if (!mounted) return;

      if (success) {
        AppSnackbar.show(context, 'SMS Reminder sent successfully!', type: AppSnackType.success);
        widget.onSentSuccess();
        Navigator.pop(context);
      } else {
        AppSnackbar.show(context, 'Failed to send SMS message. Please check API credits.', type: AppSnackType.error);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, 'An error occurred: $e', type: AppSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final charCount = _msgCtrl.text.length;
    final smsCount = (charCount / 160).ceil();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slide indicator
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Compose SMS Reminder',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.brandText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'To: ${widget.recipientName} (${SmsService.formatDisplayNumber(widget.phoneNumber)})',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const Divider(height: 24, color: AppColors.borderPrimary),

            // Language Selector
            const Text(
              'Select Language Template:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandText),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _LanguageButton(
                  label: 'Filipino / Tagalog',
                  selected: _language == 'fil',
                  onTap: () {
                    setState(() => _language = 'fil');
                    _populateTemplate();
                  },
                ),
                const SizedBox(width: 10),
                _LanguageButton(
                  label: 'English',
                  selected: _language == 'eng',
                  onTap: () {
                    setState(() => _language = 'eng');
                    _populateTemplate();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // SMS Body Text Field
            const Text(
              'Message Content:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandText),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderPrimary),
              ),
              child: TextField(
                controller: _msgCtrl,
                maxLines: 5,
                maxLength: 400,
                onChanged: (val) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Type your custom SMS reminder here...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                  counterText: '',
                ),
                style: const TextStyle(fontSize: 14, color: AppColors.brandText, height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            
            // SMS Character and page counter
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$charCount characters',
                  style: TextStyle(
                    fontSize: 11,
                    color: charCount > 160 ? AppColors.warning : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$smsCount SMS Part(s)',
                  style: TextStyle(
                    fontSize: 11,
                    color: smsCount > 1 ? AppColors.warning : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Send Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _sendSms,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white),
                label: Text(
                  _sending ? 'Sending...' : 'Send SMS Message',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: selected ? AppColors.brandPrimary.withValues(alpha: 0.1) : Colors.white,
            border: Border.all(
              color: selected ? AppColors.brandPrimary : AppColors.borderPrimary,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(19),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: selected ? AppColors.brandPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
