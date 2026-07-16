// lib/screens/midwife/midwife_mother_list.dart
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/search_bar.dart' as local_widgets;

class MidwifeMotherList extends StatefulWidget {
  const MidwifeMotherList({super.key});

  @override
  State<MidwifeMotherList> createState() => _MidwifeMotherListState();
}

class _MidwifeMotherListState extends State<MidwifeMotherList> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';

  final List<String> _filters = ['All', 'High Risk', 'Low Risk', 'Due Soon'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: local_widgets.SearchBar(
              controller: _searchController,
              hintText: 'Search mothers...',
              onChanged: (value) {
                // Implement search
              },
              onClear: () {
                _searchController.clear();
                setState(() {});
              },
            ),
          ),

          // Filter Chips
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = filter == _selectedFilter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                    backgroundColor: Colors.white,
                    selectedColor: AppColors.brandSecondary.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.brandSecondary,
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.brandSecondary : AppColors.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // Mother List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: 10, // Replace with actual count
              itemBuilder: (context, index) {
                return _buildMotherCard(index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMotherCard(int index) {
    // Sample data - replace with actual data
    final mothers = [
      {
        'name': 'Maria Santos',
        'age': 28,
        'weeks': 24,
        'risk': 'low',
        'nextCheckup': 'May 20, 2026',
        'bhc': 'Barangay San Jose',
      },
      {
        'name': 'Juana Dela Cruz',
        'age': 32,
        'weeks': 32,
        'risk': 'high',
        'nextCheckup': 'May 18, 2026',
        'bhc': 'Barangay San Isidro',
      },
      {
        'name': 'Ana Lopez',
        'age': 25,
        'weeks': 16,
        'risk': 'low',
        'nextCheckup': 'May 22, 2026',
        'bhc': 'Barangay San Jose',
      },
    ];

    final mother = mothers[index % mothers.length];

    Color riskColor;
    IconData riskIcon;
    if (mother['risk'] == 'high') {
      riskColor = AppColors.error;
      riskIcon = Icons.error;
    } else {
      riskColor = AppColors.success;
      riskIcon = Icons.check_circle;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.brandSecondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    mother['name'].toString().substring(0, 1),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            mother['name'].toString(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: riskColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(riskIcon, size: 12, color: riskColor),
                              const SizedBox(width: 4),
                              Text(
                                mother['risk'].toString().toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: riskColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${mother['weeks']} weeks',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.location_on, size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            mother['bhc'].toString(),
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.borderPrimary),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.event, size: 14, color: AppColors.brandSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Next: ${mother['nextCheckup']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.brandSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      // View details
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('View'),
                  ),
                  TextButton(
                    onPressed: () {
                      // Schedule
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Schedule'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}