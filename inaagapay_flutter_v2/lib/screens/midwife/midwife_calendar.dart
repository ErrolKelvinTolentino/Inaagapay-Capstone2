// lib/screens/midwife/midwife_calendar.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';

class MidwifeCalendar extends StatefulWidget {
  const MidwifeCalendar({super.key});

  @override
  State<MidwifeCalendar> createState() => _MidwifeCalendarState();
}

class _MidwifeCalendarState extends State<MidwifeCalendar> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDate;

  final Map<String, List<Map<String, dynamic>>> _events = {
    '2026-05-15': [
      {
        'time': '09:00',
        'title': 'Prenatal Checkup',
        'patient': 'Maria Santos',
        'type': 'checkup'
      },
      {
        'time': '14:00',
        'title': 'Ultrasound Review',
        'patient': 'Juana Dela Cruz',
        'type': 'ultrasound'
      },
    ],
    '2026-05-16': [
      {
        'time': '10:00',
        'title': 'Lab Results Discussion',
        'patient': 'Ana Lopez',
        'type': 'lab'
      },
    ],
    '2026-05-18': [
      {
        'time': '08:30',
        'title': 'New Patient Registration',
        'patient': 'New Mother',
        'type': 'registration'
      },
      {
        'time': '11:00',
        'title': 'Follow-up Checkup',
        'patient': 'Maria Santos',
        'type': 'checkup'
      },
    ],
    '2026-05-20': [
      {
        'time': '13:00',
        'title': 'Home Visit',
        'patient': 'Juana Dela Cruz',
        'type': 'visit'
      },
    ],
  };

  void _previousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Calendar Header with Month Navigation
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _previousMonth,
                  icon: const Icon(Icons.chevron_left),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_focusedMonth),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: _nextMonth,
                  icon: const Icon(Icons.chevron_right),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Weekday Headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                  .map((day) => SizedBox(
                        width: 40,
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),

          const SizedBox(height: 10),

          // Calendar Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.9,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: _getDaysInMonth().length,
              itemBuilder: (context, index) {
                final date = _getDaysInMonth()[index];
                if (date == null) {
                  return const SizedBox.shrink();
                }

                final isToday = _isSameDay(date, DateTime.now());
                final isSelected =
                    _selectedDate != null && _isSameDay(date, _selectedDate!);
                final hasEvents = _getEventsForDate(date).isNotEmpty;
                final isCurrentMonth = date.month == _focusedMonth.month;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.brandSecondary
                          : (isToday
                              ? AppColors.brandSecondary.withValues(alpha: 0.1)
                              : Colors.transparent),
                      borderRadius: BorderRadius.circular(8),
                      border: isToday && !isSelected
                          ? Border.all(color: AppColors.brandSecondary)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected || isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : (isCurrentMonth
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary
                                        .withValues(alpha: 0.5)),
                          ),
                        ),
                        if (hasEvents)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.brandSecondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // Legend
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('Checkup', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 16),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.purple,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('Ultrasound', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 16),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('Lab Test', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Selected Date Events
          if (_selectedDate != null)
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate!),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Add new schedule
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('+ Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildEventList(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<DateTime?> _getDaysInMonth() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;

    final firstDayOfMonth = DateTime(year, month, 1);
    final firstDayOfGrid =
        firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));

    final days = <DateTime?>[];
    for (int i = 0; i < 42; i++) {
      days.add(firstDayOfGrid.add(Duration(days: i)));
    }

    return days;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<Map<String, dynamic>> _getEventsForDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    return _events[dateKey] ?? [];
  }

  Widget _buildEventList() {
    final events = _getEventsForDate(_selectedDate!);

    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.event_busy,
                size: 32,
                color: AppColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(
              'No schedules for this day',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: events.map((event) {
        Color eventColor;
        IconData eventIcon;

        switch (event['type']) {
          case 'ultrasound':
            eventColor = Colors.purple;
            eventIcon = Icons.photo;
            break;
          case 'lab':
            eventColor = Colors.orange;
            eventIcon = Icons.science;
            break;
          case 'registration':
            eventColor = Colors.green;
            eventIcon = Icons.person_add;
            break;
          case 'visit':
            eventColor = Colors.blue;
            eventIcon = Icons.home;
            break;
          default:
            eventColor = AppColors.brandSecondary;
            eventIcon = Icons.medical_services;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: eventColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: eventColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: eventColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(eventIcon, color: eventColor, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event['title'],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${event['patient']} • ${event['time']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_vert, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
