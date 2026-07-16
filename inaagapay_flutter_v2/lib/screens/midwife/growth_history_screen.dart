import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_colors.dart';
import '../../widgets/growth_record_card.dart';

class GrowthHistoryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> records;
  final DateTime? birthdate;

  const GrowthHistoryScreen({
    super.key,
    required this.records,
    this.birthdate,
  });

  @override
  State<GrowthHistoryScreen> createState() => _GrowthHistoryScreenState();
}

class _GrowthHistoryScreenState extends State<GrowthHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final int _pageSize = 10;

  String _searchQuery = '';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _sortOldestFirst = false;
  bool _isLoadingMore = false;

  List<Map<String, dynamic>> _filteredRecords = [];
  List<Map<String, dynamic>> _displayedRecords = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _applyFilters();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchQuery = _searchController.text.trim();
    _applyFilters();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 120 &&
        !_isLoadingMore) {
      _loadMoreRecords();
    }
  }

  void _applyFilters() {
    _filteredRecords = widget.records.where((record) {
      final dateString = record['created_at']?.toString() ?? '';
      final recordDate = _parseDate(dateString);
      if (recordDate == null) return false;

      final height = ((record['child_height'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(1);
      final weight = ((record['child_weight'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(1);
      final weeks = _calculateWeeks(recordDate).toString();
      final formattedDate = _formatDate(dateString).toLowerCase();
      final query = _searchQuery.toLowerCase();

      if (query.isNotEmpty) {
        if (!formattedDate.contains(query) &&
            !height.contains(query) &&
            !weight.contains(query) &&
            !weeks.contains(query)) {
          return false;
        }
      }

      if (_fromDate != null && recordDate.isBefore(_dateOnly(_fromDate!))) {
        return false;
      }
      if (_toDate != null &&
          recordDate
              .isAfter(_dateOnly(_toDate!).add(const Duration(days: 1)))) {
        return false;
      }

      return true;
    }).toList();

    _filteredRecords.sort((a, b) {
      final aDate = _parseDate(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = _parseDate(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return _sortOldestFirst ? aDate.compareTo(bDate) : bDate.compareTo(aDate);
    });

    _displayedRecords = _filteredRecords.take(_pageSize).toList();
    setState(() {});
  }

  void _loadMoreRecords() {
    if (_displayedRecords.length >= _filteredRecords.length) return;

    setState(() {
      _isLoadingMore = true;
    });

    Future.delayed(const Duration(milliseconds: 250), () {
      final nextRecords = _filteredRecords
          .skip(_displayedRecords.length)
          .take(_pageSize)
          .toList();
      _displayedRecords.addAll(nextRecords);

      setState(() {
        _isLoadingMore = false;
      });
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _sortOldestFirst = !_sortOldestFirst;
      _applyFilters();
    });
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked;
      });
      _applyFilters();
    }
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _toDate = picked;
      });
      _applyFilters();
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _fromDate = null;
      _toDate = null;
    });
    _applyFilters();
  }

  DateTime? _parseDate(String? date) {
    if (date == null || date.isEmpty) return null;
    try {
      return DateTime.parse(date);
    } catch (_) {
      return null;
    }
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _formatDate(String? date) {
    if (date == null || date.isEmpty) return 'Unknown';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(date));
    } catch (_) {
      return date;
    }
  }

  int _calculateWeeks(DateTime recordDate) {
    if (widget.birthdate == null) return 0;
    final difference = recordDate.difference(widget.birthdate!);
    return (difference.inDays / 7).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Growth Records'),
        backgroundColor: AppColors.brandPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: AppColors.bgPrimary,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.brandPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by date, height, weight, week',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickFromDate,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _fromDate != null
                              ? 'From ${DateFormat('MMM d').format(_fromDate!)}'
                              : 'From date',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickToDate,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _toDate != null
                              ? 'To ${DateFormat('MMM d').format(_toDate!)}'
                              : 'To date',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _toggleSortOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _sortOldestFirst ? 'Oldest first' : 'Newest first',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _clearFilters,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.brandPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildRecordList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordList() {
    if (_displayedRecords.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No growth records match your filters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _displayedRecords.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _displayedRecords.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final record = _displayedRecords[index];
        final height = (record['child_height'] as num?)?.toDouble() ?? 0;
        final weight = (record['child_weight'] as num?)?.toDouble() ?? 0;
        final date = record['created_at']?.toString() ?? '';
        final weeks = _calculateWeeks(_parseDate(date) ?? DateTime.now());

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GrowthRecordCard(
            height: height,
            weight: weight,
            date: _formatDate(date),
            weekNumber: weeks,
            isLatest: false,
          ),
        );
      },
    );
  }
}
