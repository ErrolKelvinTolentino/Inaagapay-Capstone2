// lib/screens/midwife/midwife_schedules_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../theme/app_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/supabase_service.dart';
import 'midwife_sms_reminders_screen.dart';

class MidwifeSchedulesScreen extends StatefulWidget {
  const MidwifeSchedulesScreen({super.key});

  @override
  State<MidwifeSchedulesScreen> createState() => _MidwifeSchedulesScreenState();
}

class _MidwifeSchedulesScreenState extends State<MidwifeSchedulesScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  late Future<List<Map<String, dynamic>>> _schedulesFuture;
  int? _midwifeId;
  int? _assignedBhcId;
  bool _isLoading = true;
  // Dates that have immunization schedules (for calendar markers)
  final Set<String> _immunizationDates = {};
  final Set<String> _prenatalDates = {};
  final Set<String> _checkupDates = {};

  @override
  void initState() {
    super.initState();
    _loadMidwifeId();
  }

  Future<void> _loadMidwifeId() async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId != null) {
        final ctx = await SupabaseService.getMidwifeContext(accountId);
        if (ctx['success'] == true) {
          _midwifeId = ctx['midwife_id'] as int?;
          _assignedBhcId = ctx['assigned_bhc_id'] as int?;
          setState(() {
            _isLoading = false;
          });
          await _loadAllEventDates();
          _refreshSchedules();
        } else {
          setState(() {
            _midwifeId = null;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading midwife ID: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Load all calendar event dates for the BHC/Midwife for this year (for calendar markers)
  Future<void> _loadAllEventDates() async {
    if (_midwifeId == null) return;
    try {
      final now = DateTime.now();
      final startOfYear = '${now.year}-01-01';
      final endOfYear = '${now.year}-12-31';

      // 1. Fetch immunization dates
      if (_assignedBhcId != null) {
        final resImm = await Supabase.instance.client
            .from('immunization_schedule')
            .select('schedule_date')
            .eq('bhc_id', _assignedBhcId!)
            .gte('schedule_date', startOfYear)
            .lte('schedule_date', endOfYear);

        final datesImm = (resImm as List)
            .map((r) => r['schedule_date']?.toString() ?? '')
            .where((d) => d.isNotEmpty)
            .toSet();

        _immunizationDates.clear();
        _immunizationDates.addAll(datesImm);
      }

      // 2. Fetch prenatal checkups next scheduled dates
      final resPrenatal = await Supabase.instance.client
          .from('prenatal_checkups')
          .select('next_schedule')
          .eq('midwife_id', _midwifeId!)
          .gte('next_schedule', startOfYear)
          .lte('next_schedule', endOfYear);

      final datesPrenatal = (resPrenatal as List)
          .map((r) => r['next_schedule']?.toString() ?? '')
          .where((d) => d.isNotEmpty)
          .toSet();

      _prenatalDates.clear();
      _prenatalDates.addAll(datesPrenatal);

      // 3. Fetch checkup schedules (for mothers/children assigned)
      final resCheckup = await Supabase.instance.client
          .from('checkup_schedule')
          .select('scheduled_date')
          .eq('status', 'scheduled')
          .gte('scheduled_date', startOfYear)
          .lte('scheduled_date', endOfYear);

      final datesCheckup = (resCheckup as List)
          .map((r) => r['scheduled_date']?.toString() ?? '')
          .where((d) => d.isNotEmpty)
          .toSet();

      _checkupDates.clear();
      _checkupDates.addAll(datesCheckup);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading event dates: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchSchedulesForDate(
      DateTime date) async {
    if (_midwifeId == null) return [];

    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);
      final midwifeIdValue = _midwifeId!;

      // Fetch prenatal checkups whose NEXT scheduled date falls on this day
      final checkupsResponse = await Supabase.instance.client
          .from('prenatal_checkups')
          .select('''
            prenatal_checkup_id,
            checkup_datetime,
            next_schedule,
            remarks,
            pregnancy:pregnancy_id (
              mother:mother_id (
                account:account_id (
                  first_name,
                  last_name
                )
              )
            )
          ''')
          .eq('midwife_id', midwifeIdValue)
          .eq('next_schedule', formattedDate)
          .order('next_schedule');

      // Also fetch from checkup_schedule table (only scheduled/upcoming entries)
      final scheduleResponse =
          await Supabase.instance.client.from('checkup_schedule').select('''
            schedule_id,
            scheduled_date,
            notes,
            status,
            mother:mother_id (
              account:account_id (
                first_name,
                last_name
              )
            )
          ''').eq('scheduled_date', formattedDate).eq('status', 'scheduled').order('scheduled_date');

      final List<Map<String, dynamic>> schedules = [];

      // Add prenatal checkups
      for (final checkup in checkupsResponse) {
        final pregnancy = checkup['pregnancy'] as Map<String, dynamic>?;
        final mother = pregnancy?['mother'] as Map<String, dynamic>?;
        final account = mother?['account'] as Map<String, dynamic>?;
        final firstName = account?['first_name']?.toString() ?? '';
        final lastName = account?['last_name']?.toString() ?? '';
        final motherName = '$firstName $lastName'.trim();

        schedules.add({
          'time': 'All Day',
          'mother_name': motherName.isNotEmpty ? motherName : 'Unknown Mother',
          'type': 'Prenatal Checkup',
          'status': 'upcoming',
          'notes': checkup['remarks']?.toString(),
          'icon': Icons.medical_services,
          'next_schedule': checkup['next_schedule']?.toString(),
        });
      }

      // Add scheduled checkups
      for (final schedule in scheduleResponse) {
        final mother = schedule['mother'] as Map<String, dynamic>?;
        final account = mother?['account'] as Map<String, dynamic>?;
        final firstName = account?['first_name']?.toString() ?? '';
        final lastName = account?['last_name']?.toString() ?? '';
        final motherName = '$firstName $lastName'.trim();

        final status = schedule['status']?.toString() ?? 'scheduled';
        final displayStatus = status == 'scheduled' ? 'upcoming' : status;

        schedules.add({
          'time': 'All Day',
          'mother_name': motherName.isNotEmpty ? motherName : 'Unknown Mother',
          'type': 'Scheduled Checkup',
          'status': displayStatus,
          'notes': schedule['notes']?.toString(),
          'icon': Icons.calendar_today,
        });
      }

      // Fetch immunization schedules for the BHC on this date
      if (_assignedBhcId != null) {
        try {
          final immunizationResponse = await Supabase.instance.client
              .from('immunization_schedule')
              .select('''
                immunization_schedule_id,
                schedule_date,
                notes,
                vaccine:vaccine_id (
                  vaccine_name,
                  target_recipients
                )
              ''')
              .eq('bhc_id', _assignedBhcId!)
              .eq('schedule_date', formattedDate);

          if ((immunizationResponse as List).isNotEmpty) {
            final vaccineNames = immunizationResponse
                .map((r) => (r['vaccine'] as Map<String, dynamic>?)?['vaccine_name']?.toString() ?? '')
                .where((n) => n.isNotEmpty)
                .toSet()
                .toList();

            final firstNote = immunizationResponse
                .map((r) => r['notes']?.toString())
                .where((n) => n != null && n.isNotEmpty)
                .firstOrNull;

            schedules.add({
              'time': 'All Day',
              'mother_name': 'Barangay Vaccine Day',
              'type': 'Immunization Schedule',
              'status': 'upcoming',
              'notes': firstNote,
              'vaccines': vaccineNames,
              'icon': Icons.vaccines,
            });
          }
        } catch (e) {
          debugPrint('Error loading immunization schedules for date: $e');
        }
      }

      // Sort by time (All Day events go to bottom)
      schedules.sort((a, b) {
        final timeA = a['time'] as String;
        final timeB = b['time'] as String;
        if (timeA == 'All Day') return 1;
        if (timeB == 'All Day') return -1;
        return timeA.compareTo(timeB);
      });

      return schedules;
    } catch (e) {
      debugPrint('Error fetching schedules: $e');
      return [];
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppColors.success;
      case 'upcoming':
        return AppColors.brandPrimary;
      case 'cancelled':
        return AppColors.error;
      case 'missed':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getScheduleIcon(String type) {
    switch (type.toLowerCase()) {
      case 'prenatal checkup':
        return Icons.pregnant_woman;
      case 'vaccination':
      case 'immunization schedule':
        return Icons.vaccines;
      case 'scheduled checkup':
        return Icons.calendar_today;
      case 'followup':
        return Icons.health_and_safety;
      default:
        return Icons.medical_services;
    }
  }

  void _refreshSchedules() {
    _loadAllEventDates();
    setState(() {
      _schedulesFuture = fetchSchedulesForDate(_selectedDay);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.brandPrimary,
          ),
        ),
      );
    }

    if (_midwifeId == null) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.error,
              ),
              const SizedBox(height: 16),
              const Text(
                'Midwife profile not found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please ensure your account is properly set up.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadMidwifeId,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            _refreshSchedules();
            return Future.value();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 📢 BARANGAY VACCINE SCHEDULE LINK CARD
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/immunization-poster'),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8, top: 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.15)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandPrimary.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.brandPrimary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.campaign_rounded,
                            color: AppColors.brandPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '📢 Barangay Vaccine Schedule (Tarpaulin Posting)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.brandText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'View and customize the yearly immunization calendar for mothers.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: AppColors.brandPrimary,
                        ),
                      ],
                    ),
                  ),
                ),

                /// 📅 CALENDAR SECTION
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: TableCalendar(
                    firstDay:
                        DateTime.now().subtract(const Duration(days: 365)),
                    lastDay: DateTime.now().add(const Duration(days: 365)),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                        _refreshSchedules();
                      });
                    },
                    // Show schedule markers on calendar days
                    eventLoader: (day) {
                      final dateKey = DateFormat('yyyy-MM-dd').format(day);
                      final List<String> events = [];
                      if (_immunizationDates.contains(dateKey)) {
                        events.add('immunization');
                      }
                      if (_prenatalDates.contains(dateKey)) {
                        events.add('prenatal');
                      }
                      if (_checkupDates.contains(dateKey)) {
                        events.add('checkup');
                      }
                      return events;
                    },
                    calendarBuilders: CalendarBuilders(
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) return const SizedBox.shrink();
                        return Positioned(
                          bottom: 2,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: events.map((event) {
                              Color color;
                              if (event == 'immunization') {
                                color = const Color(0xFF00796B); // Teal
                              } else if (event == 'prenatal') {
                                color = AppColors.brandPrimary; // Pink
                              } else {
                                color = Colors.blue.shade700; // Blue
                              }
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: AppColors.brandPrimary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: AppColors.brandPrimary,
                        shape: BoxShape.circle,
                      ),
                      weekendTextStyle: const TextStyle(color: Colors.black87),
                      outsideTextStyle: const TextStyle(color: Colors.grey),
                      defaultTextStyle: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      selectedTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      todayTextStyle: const TextStyle(
                        color: AppColors.brandPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      markersMaxCount: 1,
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      leftChevronIcon: Icon(
                        Icons.chevron_left,
                        color: AppColors.brandPrimary,
                      ),
                      rightChevronIcon: Icon(
                        Icons.chevron_right,
                        color: AppColors.brandPrimary,
                      ),
                      headerPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      weekendStyle: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                /// ℹ️ CALENDAR LEGEND
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLegendItem(
                        color: const Color(0xFF00796B),
                        label: 'Immunization Day',
                      ),
                      _buildLegendItem(
                        color: AppColors.brandPrimary,
                        label: 'Prenatal Checkup',
                      ),
                      _buildLegendItem(
                        color: Colors.blue.shade700,
                        label: 'Scheduled Checkup',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                /// 📋 SELECTED DATE HEADER
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('EEEE, MMMM d').format(_selectedDay),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandText,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _refreshSchedules,
                            icon: const Icon(Icons.refresh),
                            color: AppColors.brandPrimary,
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _selectedDay = DateTime.now();
                                _focusedDay = DateTime.now();
                                _refreshSchedules();
                              });
                            },
                            icon: const Icon(Icons.today),
                            color: AppColors.brandPrimary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                /// 📋 SCHEDULE LIST
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _schedulesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(
                            color: AppColors.brandPrimary,
                          ),
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
                              color: AppColors.error,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Error loading schedules',
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _refreshSchedules,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandPrimary,
                              ),
                              child: const Text(
                                'Retry',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final schedules = snapshot.data!;

                    if (schedules.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              /// 📅 NO SCHEDULES ILLUSTRATION
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppColors.brandPrimary
                                      .withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.calendar_today,
                                  size: 50,
                                  color: AppColors.brandPrimary
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                DateFormat('EEEE, MMMM d').format(_selectedDay),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.brandText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'No scheduled appointments',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Enjoy your free time! 🎉',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: schedules.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final schedule = schedules[index];

                        if (schedule['type'] == 'Immunization Schedule') {
                          return ImmunizationDayCard(
                            time: schedule['time'] as String,
                            title: schedule['mother_name'] as String,
                            notes: schedule['notes'] as String?,
                            vaccines: List<String>.from(schedule['vaccines'] ?? []),
                            status: schedule['status'] as String,
                          );
                        }

                        return ScheduleCard(
                          time: schedule['time'] as String,
                          motherName: schedule['mother_name'] as String,
                          scheduleType: schedule['type'] as String,
                          status: schedule['status'] as String,
                          notes: schedule['notes'] as String?,
                          icon: schedule['icon'] as IconData? ??
                              _getScheduleIcon(schedule['type'] as String),
                          statusColor:
                              _getStatusColor(schedule['status'] as String),
                          nextSchedule: schedule['next_schedule'] as String?,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MidwifeSmsRemindersScreen(),
            ),
          );
        },
        backgroundColor: AppColors.brandPrimary,
        icon: const Icon(Icons.sms_rounded, color: Colors.white),
        label: const Text(
          'SMS Reminders',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

/// 🧩 SCHEDULE CARD WIDGET
class ScheduleCard extends StatelessWidget {
  final String time;
  final String motherName;
  final String scheduleType;
  final String status;
  final String? notes;
  final IconData icon;
  final Color statusColor;
  final String? nextSchedule;

  const ScheduleCard({
    super.key,
    required this.time,
    required this.motherName,
    required this.scheduleType,
    required this.status,
    this.notes,
    required this.icon,
    required this.statusColor,
    this.nextSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final showTime = time.isNotEmpty && time.toLowerCase() != 'all day';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// 🕐 TIME INDICATOR
          if (showTime) ...[
            SizedBox(
              width: 70,
              child: Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      time,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],

          /// 📝 SCHEDULE DETAILS
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    /// 👤 MOTHER NAME
                    Expanded(
                      child: Text(
                        motherName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    /// 🏷️ STATUS BADGE
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                /// 📋 TYPE AND ICON
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      scheduleType,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),

                /// 📅 NEXT SCHEDULE (if available)
                if (nextSchedule != null && nextSchedule!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Next: ${DateFormat('MMM d, yyyy').format(DateTime.parse(nextSchedule!))}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],

                /// 📝 NOTES (IF ANY)
                if (notes != null && notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.note,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            notes!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImmunizationDayCard extends StatelessWidget {
  final String time;
  final String title;
  final String? notes;
  final List<String> vaccines;
  final String status;
  final Color accentColor = const Color(0xFF00796B);

  const ImmunizationDayCard({
    super.key,
    required this.time,
    required this.title,
    this.notes,
    required this.vaccines,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final showTime = time.isNotEmpty && time.toLowerCase() != 'all day';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withAlpha(50),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withAlpha(15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// 🕐 TIME INDICATOR (Teal theme)
          if (showTime) ...[
            SizedBox(
              width: 70,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      time,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],

          /// 📝 CARD DETAILS
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    /// 👤 BHC TITLE
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    /// 🏷️ STATUS BADGE (Teal)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentColor.withAlpha(70)),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                /// 📋 TYPE AND ICON
                Row(
                  children: [
                    Icon(
                      Icons.vaccines,
                      size: 16,
                      color: accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Immunization Day',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                /// 💊 VACCINES PILL CHIPS
                if (vaccines.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: vaccines.map((vacName) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.teal.shade100),
                        ),
                        child: Text(
                          vacName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],

                /// 📝 NOTES (IF ANY)
                if (notes != null && notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        height: 1.3,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
