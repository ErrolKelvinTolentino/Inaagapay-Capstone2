// lib/screens/shared/immunization_poster_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../theme/app_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/language_service.dart';
import '../../widgets/secondary_header.dart';
import '../../services/immunization_reminder_service.dart';

class ImmunizationPosterScreen extends StatefulWidget {
  const ImmunizationPosterScreen({super.key});

  @override
  State<ImmunizationPosterScreen> createState() => _ImmunizationPosterScreenState();
}

class _ImmunizationPosterScreenState extends State<ImmunizationPosterScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  bool _syncing = false;
  String? _role;
  int? _assignedBhcId;
  
  // Selection states
  int? _selectedBhcId;
  int _selectedYear = DateTime.now().year;

  // Dropdown lists
  List<Map<String, dynamic>> _bhcs = [];
  final List<int> _years = List.generate(5, (index) => DateTime.now().year + index);

  // Data states
  List<Map<String, dynamic>> _vaccines = [];
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _midwives = [];
  List<Map<String, dynamic>> _columns = [];

  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  final List<String> _monthsFilipino = [
    'Enero', 'Pebrero', 'Marso', 'Abril', 'Mayo', 'Hunyo',
    'Hulyo', 'Agosto', 'Setyembre', 'Oktubre', 'Nobyembre', 'Disyembre'
  ];

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    setState(() => _loading = true);
    try {
      // 1. Get user role and context
      _role = await AuthStorage.getUserRole();
      final accountId = await AuthStorage.getUserId();

      if (_role == 'midwife' && accountId != null) {
        final midwifeRes = await _client
            .from('midwives')
            .select('midwife_id, assigned_bhc_id')
            .eq('account_id', accountId)
            .maybeSingle();

        if (midwifeRes != null) {
          _assignedBhcId = midwifeRes['assigned_bhc_id'] as int?;
          _selectedBhcId = _assignedBhcId;
        }
      } else if (_role == 'mother') {
        final motherId = await AuthStorage.getMotherId();
        if (motherId != null) {
          final motherRes = await _client
              .from('mothers')
              .select('assigned_bhc_id')
              .eq('mother_id', motherId)
              .maybeSingle();
          if (motherRes != null) {
            _assignedBhcId = motherRes['assigned_bhc_id'] as int?;
            _selectedBhcId = _assignedBhcId;
          }
        }
      }

      // 2. Fetch BHCs list (only BHCs with valid IDs)
      final bhcsRes = await _client
          .from('bhc')
          .select('bhc_id, bhc_name')
          .not('bhc_id', 'is', null)
          .order('bhc_name');
      
      _bhcs = List<Map<String, dynamic>>.from(bhcsRes)
          .where((b) => b['bhc_id'] != null && b['bhc_name'] != null && b['bhc_name'].toString().trim().isNotEmpty)
          .toList();

      if (_selectedBhcId == null && _bhcs.isNotEmpty) {
        _selectedBhcId = _bhcs.first['bhc_id'] as int?;
      }

      // 3. Fetch Vaccines
      final vaccinesRes = await _client
          .from('vaccines')
          .select('vaccine_id, vaccine_name, dose_number, target_recipients');
      _vaccines = List<Map<String, dynamic>>.from(vaccinesRes);

      // 4. Fetch/Seed poster columns & midwives for default selected BHC
      if (_selectedBhcId != null) {
        await _loadColumnsAndSeedIfEmpty();
        await Future.wait([
          _loadSchedules(),
          _loadBhcMidwives(),
        ]);
      }
    } catch (e) {
      debugPrint('Error initializing screen: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadColumnsAndSeedIfEmpty() async {
    if (_selectedBhcId == null) return;
    try {
      final res = await _client
          .from('poster_columns')
          .select('column_id, bhc_id, title, subtitle, vaccine_ids, display_order')
          .eq('bhc_id', _selectedBhcId!)
          .order('display_order');

      final list = List<Map<String, dynamic>>.from(res);
      if (list.isNotEmpty) {
        setState(() {
          _columns = list;
        });
        return;
      }

      // If empty, seed default columns
      final cat1Ids = <int>[];
      final cat2Ids = <int>[];
      final cat3Ids = <int>[];

      for (final v in _vaccines) {
        final id = v['vaccine_id'] as int;
        final name = v['vaccine_name']?.toString() ?? '';
        final target = v['target_recipients']?.toString() ?? '';
        
        final cat = _getCategoryForVaccine(name, target, null);
        if (cat == 1) {
          cat1Ids.add(id);
        } else if (cat == 3) {
          cat3Ids.add(id);
        } else {
          cat2Ids.add(id);
        }
      }

      final defaultCols = [
        {
          'bhc_id': _selectedBhcId!,
          'title': 'M.M.R.',
          'subtitle': 'Edad 1 Taon Pataas',
          'vaccine_ids': cat1Ids,
          'display_order': 0,
        },
        {
          'bhc_id': _selectedBhcId!,
          'title': 'BCG, PENTA, OPV',
          'subtitle': 'Edad 1 Buwan Pataas',
          'vaccine_ids': cat2Ids,
          'display_order': 1,
        },
        {
          'bhc_id': _selectedBhcId!,
          'title': 'BUNTIS TETANUS',
          'subtitle': '2 Hanggang 7 Buwang Buntis',
          'vaccine_ids': cat3Ids,
          'display_order': 2,
        },
      ];

      await _client.from('poster_columns').insert(defaultCols);

      // Re-fetch columns
      final reFetch = await _client
          .from('poster_columns')
          .select('column_id, bhc_id, title, subtitle, vaccine_ids, display_order')
          .eq('bhc_id', _selectedBhcId!)
          .order('display_order');

      setState(() {
        _columns = List<Map<String, dynamic>>.from(reFetch);
      });
    } catch (e) {
      debugPrint('Error loading/seeding columns: $e');
    }
  }

  int _getCategoryForVaccine(String name, String targetRecipients, int? dbCategory) {
    if (dbCategory != null) {
      return dbCategory;
    }
    final lowerName = name.toLowerCase();
    
    // Column 3: Tetanus Toxoid for pregnant mothers
    if (targetRecipients == 'mother' || lowerName.contains('tetanus') || lowerName.contains('toxoid') || lowerName.contains('td')) {
      return 3;
    }
    
    // Column 1: MMR / Measles (measles is MMR-related, recommended age >= 9/12 months)
    if (lowerName.contains('mmr') || lowerName.contains('measles') || lowerName.contains('tigdas') || lowerName.contains('beke')) {
      return 1;
    }
    
    // Column 2: BCG, Penta, Polio, PCV, Rotavirus, HepB (Standard childhood vaccines)
    return 2;
  }

  List<int> _getVaccineIdsForColumn(int columnId) {
    final col = _columns.firstWhere(
      (c) => c['column_id'] == columnId,
      orElse: () => <String, dynamic>{},
    );
    final ids = col['vaccine_ids'];
    if (ids is List) {
      return ids.map((e) => int.tryParse(e.toString()) ?? 0).where((id) => id != 0).toList();
    }
    return [];
  }

  Future<void> _loadSchedules() async {
    if (_selectedBhcId == null) return;
    try {
      final startOfYear = '$_selectedYear-01-01';
      final endOfYear = '$_selectedYear-12-31';

      final res = await _client
          .from('immunization_schedule')
          .select('''
            immunization_schedule_id,
            schedule_date,
            vaccine_id,
            notes,
            vaccine:vaccine_id (
              vaccine_name,
              target_recipients
            )
          ''')
          .eq('bhc_id', _selectedBhcId!)
          .gte('schedule_date', startOfYear)
          .lte('schedule_date', endOfYear);

      setState(() {
        _schedules = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      debugPrint('Error loading schedules: $e');
    }
  }

  Future<void> _loadBhcMidwives() async {
    if (_selectedBhcId == null) return;
    try {
      final res = await _client
          .from('midwives')
          .select('''
            midwife_id,
            account:account_id (
              first_name,
              last_name,
              phone_number
            )
          ''')
          .eq('assigned_bhc_id', _selectedBhcId!);

      setState(() {
        _midwives = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      debugPrint('Error loading BHC midwives: $e');
    }
  }

  // Get list of distinct dates scheduled for a specific column and month
  List<DateTime> _getDatesForCell(int columnId, int monthNumber) {
    final Set<String> uniqueDateStrings = {};
    final List<DateTime> dates = [];

    final vaccineIds = _getVaccineIdsForColumn(columnId);
    if (vaccineIds.isEmpty) return [];

    for (final s in _schedules) {
      final sDateStr = s['schedule_date']?.toString();
      final vId = s['vaccine_id'] as int?;

      if (sDateStr != null && vId != null && vaccineIds.contains(vId)) {
        final parsedDate = DateTime.tryParse(sDateStr);
        if (parsedDate != null && parsedDate.month == monthNumber) {
          final formattedStr = DateFormat('yyyy-MM-dd').format(parsedDate);
          if (!uniqueDateStrings.contains(formattedStr)) {
            uniqueDateStrings.add(formattedStr);
            dates.add(parsedDate);
          }
        }
      }
    }
    return dates;
  }

  String _formatDatesCell(List<DateTime> dates) {
    if (dates.isEmpty) return '—';
    dates.sort();
    return dates.map((d) => DateFormat('dd').format(d)).join(', ');
  }

  String _translate(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  bool get _canEditSelectedBhc {
    return _role == 'midwife' && _assignedBhcId == _selectedBhcId;
  }

  List<Map<String, dynamic>> _getSchedulesForDateAndColumn(DateTime date, int columnId) {
    final formattedStr = DateFormat('yyyy-MM-dd').format(date);
    final vaccineIds = _getVaccineIdsForColumn(columnId);
    return _schedules.where((s) {
      final sDateStr = s['schedule_date']?.toString();
      final vId = s['vaccine_id'] as int?;
      return sDateStr == formattedStr && vId != null && vaccineIds.contains(vId);
    }).toList();
  }

  String? _getNoteForDateAndColumn(DateTime date, int columnId) {
    final schedules = _getSchedulesForDateAndColumn(date, columnId);
    for (final s in schedules) {
      if (s['notes'] != null && s['notes'].toString().isNotEmpty) {
        return s['notes'].toString();
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _getVaccinesForColumn(int columnId) {
    final vaccineIds = _getVaccineIdsForColumn(columnId);
    return _vaccines.where((v) => vaccineIds.contains(v['vaccine_id'])).toList();
  }

  Future<void> _onCellTapped(int columnId, int monthNumber, String categoryTitle) async {
    final vaccineIds = _getVaccineIdsForColumn(columnId);
    if (vaccineIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate(
            'No vaccines are mapped to this column.',
            'Walang bakunang naka-map sa kolum na ito.',
          )),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_canEditSelectedBhc) {
      _showEditDetailsDialog(columnId, monthNumber, categoryTitle);
    } else {
      _showReadOnlyDetailsDialog(columnId, monthNumber, categoryTitle);
    }
  }

  void _showReadOnlyDetailsDialog(int columnId, int monthNumber, String categoryTitle) {
    final monthName = _months[monthNumber - 1];
    final monthNameFil = _monthsFilipino[monthNumber - 1];
    final displayMonth = _translate(monthName, monthNameFil);
    final cellDates = _getDatesForCell(columnId, monthNumber);
    cellDates.sort();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$displayMonth $_selectedYear',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppColors.brandText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            categoryTitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const Divider(height: 24, color: AppColors.borderPrimary),
                cellDates.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            _translate('No scheduled dates yet.', 'Walang nakatakdang petsa.'),
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 350),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: cellDates.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (ctx, index) {
                            final date = cellDates[index];
                            final schedules = _getSchedulesForDateAndColumn(date, columnId);
                            final note = _getNoteForDateAndColumn(date, columnId);

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.bgSecondary,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('MMMM dd, yyyy').format(date),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.brandText),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _translate('Vaccines Offered:', 'Mga Bakuna:'),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: schedules.map((s) {
                                      final vaccine = s['vaccine'] as Map<String, dynamic>?;
                                      final name = vaccine?['vaccine_name']?.toString() ?? 'Vaccine';
                                      final dose = s['vaccine']?['dose_number'] as int?;
                                      final display = (dose != null && dose > 0) ? '$name (Dose $dose)' : name;

                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          display,
                                          style: const TextStyle(fontSize: 11, color: AppColors.brandText, fontWeight: FontWeight.w500),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  if (note != null && note.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.info_outline, size: 14, color: AppColors.brandPrimary),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              note,
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.3),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      side: const BorderSide(color: AppColors.borderPrimary),
                    ),
                    child: Text(
                      _translate('Close', 'Isara'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
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

  void _showEditDetailsDialog(int columnId, int monthNumber, String categoryTitle) {
    final monthName = _months[monthNumber - 1];
    final monthNameFil = _monthsFilipino[monthNumber - 1];
    final displayMonth = _translate(monthName, monthNameFil);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cellDates = _getDatesForCell(columnId, monthNumber);
            cellDates.sort();
            final columnVaccineIds = _getVaccineIdsForColumn(columnId);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$displayMonth $_selectedYear',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: AppColors.brandText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                categoryTitle,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(context),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppColors.borderPrimary),
                    if (cellDates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            _translate('No scheduled dates yet.', 'Walang nakatakdang petsa.'),
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: cellDates.length,
                          separatorBuilder: (_, __) => const Divider(height: 12, color: AppColors.borderPrimary),
                          itemBuilder: (ctx, index) {
                            final date = cellDates[index];
                            final schedules = _getSchedulesForDateAndColumn(date, columnId);
                            final note = _getNoteForDateAndColumn(date, columnId);

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                DateFormat('MMMM dd, yyyy').format(date),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    schedules.map((s) {
                                      final vaccine = s['vaccine'] as Map<String, dynamic>?;
                                      final name = vaccine?['vaccine_name']?.toString() ?? '';
                                      final dose = s['vaccine']?['dose_number'] as int?;
                                      return (dose != null && dose > 0) ? '$name (Dose $dose)' : name;
                                    }).join(', '),
                                    style: const TextStyle(fontSize: 12, color: AppColors.brandText),
                                  ),
                                  if (note != null && note.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_translate('Note', 'Paalala')}: $note',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: AppColors.brandPrimary),
                                    onPressed: () async {
                                      await _showDateEditorDialog(
                                        columnId,
                                        monthNumber,
                                        categoryTitle,
                                        editingDate: date,
                                        initialNote: note,
                                      );
                                      setDialogState(() {});
                                    },
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                                    onPressed: () async {
                                      await _deleteScheduleDate(date, columnVaccineIds);
                                      setDialogState(() {});
                                    },
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              side: const BorderSide(color: AppColors.borderPrimary),
                            ),
                            child: Text(
                              _translate('Close', 'Isara'),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _showDateEditorDialog(columnId, monthNumber, categoryTitle);
                              setDialogState(() {});
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandPrimary,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: Text(
                              _translate('Add Date', 'Magdagdag ng Petsa'),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showDateEditorDialog(
    int columnId,
    int monthNumber,
    String categoryTitle, {
    DateTime? editingDate,
    String? initialNote,
  }) async {
    final isEditing = editingDate != null;
    DateTime selectedDate = editingDate ?? DateTime(_selectedYear, monthNumber, 1);
    final columnVaccineIds = _getVaccineIdsForColumn(columnId);

    final TextEditingController noteController = TextEditingController(text: initialNote ?? '');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setEditorState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? _translate('Edit Details', 'I-edit ang Detalye') : _translate('Add Scheduled Date', 'Magdagdag ng Petsa'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.brandText),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: isSaving ? null : () => Navigator.pop(context),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppColors.borderPrimary),
                    // Date Selector Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _translate('Date:', 'Petsa:'),
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('MMMM dd, yyyy').format(selectedDate),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final initial = selectedDate;
                            final firstDate = DateTime(_selectedYear, monthNumber, 1);
                            final lastDay = DateTime(_selectedYear, monthNumber + 1, 0).day;
                            final lastDate = DateTime(_selectedYear, monthNumber, lastDay);

                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: firstDate,
                              lastDate: lastDate,
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.light(
                                      primary: AppColors.brandPrimary,
                                      onPrimary: Colors.white,
                                      onSurface: AppColors.textPrimary,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );

                            if (picked != null) {
                              setEditorState(() {
                                selectedDate = picked;
                              });
                            }
                          },
                          icon: const Icon(Icons.edit_calendar, size: 16, color: AppColors.brandPrimary),
                          label: Text(_translate('Change', 'Palitan'), style: const TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppColors.borderPrimary),

                    // Notes Input field
                    Text(
                      _translate('Notes / Remarks:', 'Paalala / Remarks:'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: _translate(
                          'e.g., Time schedule, instructions...',
                          'Hal., Oras ng schedule, mga kailangan...',
                        ),
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: AppColors.bgSecondary.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.borderPrimary)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.borderPrimary)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.brandPrimary, width: 1.5)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSaving ? null : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              side: const BorderSide(color: AppColors.borderPrimary),
                            ),
                            child: Text(
                              _translate('Cancel', 'Kanselahin'),
                              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (columnVaccineIds.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(_translate('No vaccines currently mapped to this column.', 'Walang bakuna sa kolum na ito.')),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                      return;
                                    }
                                    setEditorState(() {
                                      isSaving = true;
                                    });
                                    try {
                                      await _saveScheduleDetails(
                                        date: selectedDate,
                                        originalDate: isEditing ? editingDate : null,
                                        notes: noteController.text,
                                        categoryVaccineIds: columnVaccineIds,
                                      );
                                      if (context.mounted) {
                                        Navigator.pop(context, true); // Close Editor
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        setEditorState(() {
                                          isSaving = false;
                                        });
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandPrimary,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            child: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(_translate('Save', 'I-save'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveScheduleDetails({
    required DateTime date,
    DateTime? originalDate,
    required String notes,
    required List<int> categoryVaccineIds,
  }) async {
    if (_selectedBhcId == null) return;
    
    setState(() => _syncing = true);
    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);
      
      // 1. Delete original entries if editing
      if (originalDate != null) {
        final formattedOriginalDate = DateFormat('yyyy-MM-dd').format(originalDate);
        await _client
            .from('immunization_schedule')
            .delete()
            .eq('bhc_id', _selectedBhcId!)
            .eq('schedule_date', formattedOriginalDate)
            .inFilter('vaccine_id', categoryVaccineIds);
      } else {
        // If adding new, clear existing for this date & category to avoid conflicts
        await _client
            .from('immunization_schedule')
            .delete()
            .eq('bhc_id', _selectedBhcId!)
            .eq('schedule_date', formattedDate)
            .inFilter('vaccine_id', categoryVaccineIds);
      }

      // 2. Insert new entries for all category vaccines
      final toInsert = categoryVaccineIds.map((id) => {
        'bhc_id': _selectedBhcId!,
        'vaccine_id': id,
        'schedule_date': formattedDate,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
      }).toList();

      if (toInsert.isNotEmpty) {
        await _client.from('immunization_schedule').insert(toInsert);
      }

      await _loadSchedules();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate('Schedule saved successfully.', 'Matagumpay na nai-save ang iskedyul.')),
          backgroundColor: AppColors.success,
        ),
      );

      // Get BHC Name for the notification context
      final bhcName = _bhcs.firstWhere(
        (b) => b['bhc_id'] == _selectedBhcId,
        orElse: () => {'bhc_name': 'Barangay Health Center'},
      )['bhc_name']?.toString() ?? 'Barangay Health Center';

      // Call the reminder service in the background (fire-and-forget)
      _notifyBeneficiariesInBackground(
        bhcId: _selectedBhcId!,
        vaccineIds: categoryVaccineIds,
        scheduleDate: date,
        bhcName: bhcName,
      );
    } catch (e) {
      debugPrint('Error saving schedule: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate('Failed to save schedule.', 'Bigo sa pag-save ng iskedyul.')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _syncing = false);
    }
  }

  void _notifyBeneficiariesInBackground({
    required int bhcId,
    required List<int> vaccineIds,
    required DateTime scheduleDate,
    required String bhcName,
  }) {
    // Show initial informational SnackBar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate(
            'Checking eligible mothers and children to notify...',
            'Sinusuri ang mga kwalipikadong nanay at bata na aabisuhan...',
          )),
          backgroundColor: AppColors.brandPrimary.withAlpha(200),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Fire and forget
    unawaited(
      ImmunizationReminderService.notifyEligibleBeneficiaries(
        bhcId: bhcId,
        vaccineIds: vaccineIds,
        scheduleDate: scheduleDate,
        bhcName: bhcName,
      ).then((result) {
        if (!mounted) return;
        
        // Show result SnackBar
        final msg = _translate(
          'Notifications sent: ${result.pushSent} push, ${result.smsSent} SMS.',
          'Mga abisong naipadala: ${result.pushSent} push, ${result.smsSent} SMS.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
        
        if (result.errors.isNotEmpty) {
          debugPrint('Notification Service Errors: ${result.errors.join(", ")}');
        }
      }).catchError((err) {
        debugPrint('Error sending immunization reminders: $err');
      }),
    );
  }

  Future<void> _deleteScheduleDate(DateTime date, List<int> categoryVaccineIds) async {
    if (_selectedBhcId == null) return;
    
    setState(() => _syncing = true);
    try {
      final formattedOriginalDate = DateFormat('yyyy-MM-dd').format(date);
      await _client
          .from('immunization_schedule')
          .delete()
          .eq('bhc_id', _selectedBhcId!)
          .eq('schedule_date', formattedOriginalDate)
          .inFilter('vaccine_id', categoryVaccineIds);

      await _loadSchedules();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate('Schedule deleted successfully.', 'Matagumpay na tinanggal ang iskedyul.')),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      debugPrint('Error deleting schedule: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate('Failed to delete schedule.', 'Bigo sa pagtanggal ng iskedyul.')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _syncing = false);
    }
  }

  void _showManageColumnsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _translate('Manage Columns', 'I-manage ang mga Kolum'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.brandText),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(context),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppColors.borderPrimary),
                    if (_columns.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            _translate('No columns configured yet.', 'Walang kolum na naka-configure.'),
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _columns.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (ctx, index) {
                            final col = _columns[index];
                            final columnId = col['column_id'] as int;
                            final title = col['title']?.toString() ?? '';
                            final subtitle = col['subtitle']?.toString() ?? '';

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.bgSecondary,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.1)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.brandText),
                                        ),
                                        if (subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            subtitle,
                                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: _getVaccinesForColumn(columnId).map((v) {
                                            final name = v['vaccine_name']?.toString() ?? '';
                                            final dose = v['dose_number'] as int?;
                                            final display = (dose != null && dose > 0) ? '$name (D$dose)' : name;
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.15)),
                                              ),
                                              child: Text(
                                                display,
                                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.brandPrimary),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: AppColors.brandPrimary, size: 20),
                                    onPressed: () async {
                                      await _showAddEditColumnDialog(column: col);
                                      setDialogState(() {});
                                    },
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                                    onPressed: () async {
                                      final confirm = await _showConfirmDeleteDialog(title);
                                      if (confirm == true) {
                                        await _deleteColumn(columnId);
                                        setDialogState(() {});
                                      }
                                    },
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              side: const BorderSide(color: AppColors.borderPrimary),
                            ),
                            child: Text(
                              _translate('Close', 'Isara'),
                              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _columns.length >= 6
                                ? null
                                : () async {
                                    await _showAddEditColumnDialog();
                                    setDialogState(() {});
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandPrimary,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              disabledBackgroundColor: Colors.grey.shade200,
                              disabledForegroundColor: Colors.grey.shade400,
                            ),
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: Text(
                              _translate('Add Column', 'Magdagdag ng Kolum'),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_columns.length >= 6) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          _translate(
                            '⚠️ Maximum limit of 6 columns reached to maintain readability on mobile screens.',
                            '⚠️ Naabot na ang limitasyon na 6 na kolum upang manatiling madaling basahin sa mobile.',
                          ),
                          style: const TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddEditColumnDialog({Map<String, dynamic>? column}) async {
    final isEditing = column != null;
    final titleController = TextEditingController(text: column?['title']?.toString() ?? '');
    final subtitleController = TextEditingController(text: column?['subtitle']?.toString() ?? '');
    
    final List<int> selectedVaccineIds = [];
    if (isEditing) {
      final ids = column['vaccine_ids'];
      if (ids is List) {
        selectedVaccineIds.addAll(ids.map((e) => int.tryParse(e.toString()) ?? 0).where((id) => id != 0));
      }
    }

    String? titleError;
    String? subtitleError;
    String? vaccineError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setSubDialogState) {
            
            // Validation helper called on input changes
            bool validateInputs() {
              bool isValid = true;
              final valTitle = titleController.text.trim();
              final valSub = subtitleController.text.trim();

              // 1. Title Validation
              if (valTitle.isEmpty) {
                titleError = _translate('Title is required.', 'Kailangan ng pamagat.');
                isValid = false;
              } else if (valTitle.length > 20) {
                titleError = _translate('Max 20 characters.', 'Hanggang 20 karakter lamang.');
                isValid = false;
              } else {
                final duplicate = _columns.any((c) =>
                    c['title']?.toString().toLowerCase().trim() == valTitle.toLowerCase() &&
                    (column == null || c['column_id'] != column['column_id']));
                if (duplicate) {
                  titleError = _translate('Title already exists.', 'Mayroon nang kolum na may ganitong pamagat.');
                  isValid = false;
                } else {
                  titleError = null;
                }
              }

              // 2. Subtitle Validation
              if (valSub.length > 40) {
                subtitleError = _translate('Max 40 characters.', 'Hanggang 40 karakter lamang.');
                isValid = false;
              } else {
                subtitleError = null;
              }

              // 3. Vaccines Validation
              if (selectedVaccineIds.isEmpty) {
                vaccineError = _translate('Select at least one vaccine.', 'Pumili ng kahit isang bakuna.');
                isValid = false;
              } else {
                vaccineError = null;
              }

              return isValid;
            }

            // Split vaccines into groups
            final childVaccines = _vaccines.where((v) => v['target_recipients']?.toString().toLowerCase() == 'child').toList();
            final motherVaccines = _vaccines.where((v) => v['target_recipients']?.toString().toLowerCase() == 'mother').toList();
            final otherVaccines = _vaccines.where((v) {
              final target = v['target_recipients']?.toString().toLowerCase() ?? '';
              return target != 'child' && target != 'mother';
            }).toList();

            // Find details of selected vaccines for chips display
            final selectedVaccineDetails = _vaccines.where((v) => selectedVaccineIds.contains(v['vaccine_id'] as int)).toList();

            Widget buildGroupHeader(String title, List<Map<String, dynamic>> groupList) {
              final groupIds = groupList.map((v) => v['vaccine_id'] as int).toList();
              final isAllSelected = groupIds.isNotEmpty && groupIds.every((id) => selectedVaccineIds.contains(id));

              return Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandText),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setSubDialogState(() {
                          if (isAllSelected) {
                            // Deselect all in this group
                            selectedVaccineIds.removeWhere((id) => groupIds.contains(id));
                          } else {
                            // Select all in this group
                            for (final id in groupIds) {
                              if (!selectedVaccineIds.contains(id)) {
                                selectedVaccineIds.add(id);
                              }
                            }
                          }
                          validateInputs();
                        });
                      },
                      child: Text(
                        isAllSelected 
                            ? _translate('Deselect All', 'I-deselect Lahat') 
                            : _translate('Select All', 'Piliin Lahat'),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandPrimary),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget buildVaccineList(List<Map<String, dynamic>> groupList) {
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: groupList.length,
                itemBuilder: (ctx, idx) {
                  final v = groupList[idx];
                  final id = v['vaccine_id'] as int;
                  final name = v['vaccine_name']?.toString() ?? 'Vaccine';
                  final dose = v['dose_number'] as int?;
                  final display = (dose != null && dose > 0) ? '$name (Dose $dose)' : name;
                  final isChecked = selectedVaccineIds.contains(id);

                  return CheckboxListTile(
                    value: isChecked,
                    activeColor: AppColors.brandPrimary,
                    checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                    title: Text(display, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (val) {
                      setSubDialogState(() {
                        if (val == true) {
                          selectedVaccineIds.add(id);
                        } else {
                          selectedVaccineIds.remove(id);
                        }
                        validateInputs();
                      });
                    },
                  );
                },
              );
            }

            InputDecoration fieldDecoration({required String hintText, String? errorText}) {
              return InputDecoration(
                hintText: hintText,
                errorText: errorText,
                filled: true,
                fillColor: AppColors.bgSecondary.withValues(alpha: 0.35),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                counterText: '',
                errorStyle: const TextStyle(fontSize: 11, color: AppColors.error),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.borderPrimary),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.borderPrimary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: AppColors.brandPrimary.withValues(alpha: 0.75),
                    width: 1.5,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.error),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.error, width: 1.5),
                ),
              );
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? _translate('Edit Column', 'I-edit ang Kolum') : _translate('Add Column', 'Magdagdag ng Kolum'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.brandText),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: isSaving ? null : () => Navigator.pop(context),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppColors.borderPrimary),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title input
                            Text(
                              _translate('Column Title:', 'Pamagat ng Kolum:'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: titleController,
                              maxLength: 20,
                              onChanged: (_) => setSubDialogState(() => validateInputs()),
                              decoration: fieldDecoration(
                                hintText: _translate('e.g., M.M.R. or BCG', 'Hal., M.M.R. o BCG'),
                                errorText: titleError,
                              ),
                              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 14),

                            // Subtitle input
                            Text(
                              _translate('Subtitle / Description:', 'Subtitle / Paglalarawan:'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: subtitleController,
                              maxLength: 40,
                              onChanged: (_) => setSubDialogState(() => validateInputs()),
                              decoration: fieldDecoration(
                                hintText: _translate('e.g., Edad 1 Taon Pataas', 'Hal., Edad 1 Taon Pataas'),
                                errorText: subtitleError,
                              ),
                              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 18),

                            // Selected Vaccines Badge / Chip Flow
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _translate('Selected Vaccines:', 'Mga Piniling Bakuna:'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandPrimary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${selectedVaccineIds.length}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.brandPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (selectedVaccineDetails.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  _translate('No vaccines selected yet.', 'Wala pang napipiling bakuna.'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.bgSecondary.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.borderPrimary),
                                ),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: selectedVaccineDetails.map((v) {
                                    final id = v['vaccine_id'] as int;
                                    final name = v['vaccine_name']?.toString() ?? '';
                                    final dose = v['dose_number'] as int?;
                                    final display = (dose != null && dose > 0) ? '$name (D$dose)' : name;

                                    return InputChip(
                                      label: Text(
                                        display,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.brandText,
                                        ),
                                      ),
                                      backgroundColor: Colors.white,
                                      deleteIcon: const Icon(
                                        Icons.close,
                                        size: 12,
                                        color: AppColors.brandPrimary,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                          color: AppColors.brandPrimary.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      onDeleted: () {
                                        setSubDialogState(() {
                                          selectedVaccineIds.remove(id);
                                          validateInputs();
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            if (vaccineError != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                vaccineError!,
                                style: const TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ],
                            const SizedBox(height: 12),

                            Divider(color: Colors.grey.shade200, height: 24, thickness: 1),

                            // Grouped Checkboxes
                            if (_vaccines.isEmpty)
                              Text(
                                _translate('No vaccines found.', 'Walang bakunang nahanap.'),
                                style: const TextStyle(color: AppColors.textSecondary),
                              )
                            else ...[
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 250),
                                child: ListView(
                                  shrinkWrap: true,
                                  children: [
                                    if (childVaccines.isNotEmpty) ...[
                                      buildGroupHeader(_translate('👶 Child Vaccines', '👶 Bakuna sa Bata'), childVaccines),
                                      buildVaccineList(childVaccines),
                                    ],
                                    if (motherVaccines.isNotEmpty) ...[
                                      buildGroupHeader(_translate('🤰 Maternal Vaccines', '🤰 Bakuna sa Ina'), motherVaccines),
                                      buildVaccineList(motherVaccines),
                                    ],
                                    if (otherVaccines.isNotEmpty) ...[
                                      buildGroupHeader(_translate('💉 Other Vaccines', '💉 Ibang Bakuna'), otherVaccines),
                                      buildVaccineList(otherVaccines),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSaving ? null : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              side: const BorderSide(color: AppColors.borderPrimary),
                            ),
                            child: Text(
                              _translate('Cancel', 'Kanselahin'),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (validateInputs()) {
                                      setSubDialogState(() {
                                        isSaving = true;
                                      });
                                      try {
                                        await _saveColumn(
                                          columnId: column?['column_id'] as int?,
                                          title: titleController.text.trim(),
                                          subtitle: subtitleController.text.trim(),
                                          vaccineIds: selectedVaccineIds,
                                        );
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          setSubDialogState(() {
                                            isSaving = false;
                                          });
                                        }
                                      }
                                    } else {
                                      // Trigger a visual update so errors show up
                                      setSubDialogState(() {});
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandPrimary,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            child: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _translate('Save', 'I-save'),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool?> _showConfirmDeleteDialog(String title) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    _translate('Delete Column?', 'I-delete ang Kolum?'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.error),
                  ),
                ],
              ),
              const Divider(height: 24, color: AppColors.borderPrimary),
              Text(
                _translate(
                  'Are you sure you want to delete column "$title"?',
                  'Sigurado ka bang nais mong i-delete ang kolum na "$title"?',
                ),
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _translate(
                          'Warning: All dates scheduled under this column will be permanently deleted.',
                          'Babala: Lahat ng petsang naka-iskedyul sa kolum na ito ay permanenteng mabubura.',
                        ),
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w500, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        side: const BorderSide(color: AppColors.borderPrimary),
                      ),
                      child: Text(
                        _translate('No, Keep It', 'Hindi, Panatilihin'),
                        style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: Text(
                        _translate('Yes, Delete', 'Oo, I-delete'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteColumn(int columnId) async {
    // Capture vaccine IDs before optimistic removal
    final vaccineIds = _getVaccineIdsForColumn(columnId);

    setState(() {
      _columns.removeWhere((c) => c['column_id'] == columnId);
      _syncing = true;
    });
    try {
      // 1. Delete all immunization_schedule entries for this BHC whose vaccine is in this column
      if (_selectedBhcId != null && vaccineIds.isNotEmpty) {
        await _client
            .from('immunization_schedule')
            .delete()
            .eq('bhc_id', _selectedBhcId!)
            .inFilter('vaccine_id', vaccineIds);
      }

      // 2. Delete the column itself
      await _client.from('poster_columns').delete().eq('column_id', columnId);
      
      // 3. Update display_order for remaining columns to keep them sequential
      final remaining = _columns.toList();
      for (int i = 0; i < remaining.length; i++) {
        await _client
            .from('poster_columns')
            .update({'display_order': i})
            .eq('column_id', remaining[i]['column_id'] as int);
      }

      // 4. Reload columns and schedules
      await Future.wait([
        _loadColumnsAndSeedIfEmpty(),
        _loadSchedules(),
      ]);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate(
            'Column and its schedules deleted successfully.',
            'Matagumpay na na-delete ang kolum at ang mga iskedyul nito.',
          )),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      debugPrint('Error deleting column: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate('Failed to delete column.', 'Bigo sa pag-delete ng kolum.')),
          backgroundColor: AppColors.error,
        ),
      );
      await _loadColumnsAndSeedIfEmpty();
    } finally {
      setState(() => _syncing = false);
    }
  }

  Future<void> _saveColumn({
    int? columnId,
    required String title,
    required String subtitle,
    required List<int> vaccineIds,
  }) async {
    if (_selectedBhcId == null) return;
    setState(() => _syncing = true);
    try {
      if (columnId != null) {
        // Optimistic local update
        final idx = _columns.indexWhere((c) => c['column_id'] == columnId);
        if (idx != -1) {
          setState(() {
            _columns[idx] = {
              ..._columns[idx],
              'title': title,
              'subtitle': subtitle,
              'vaccine_ids': vaccineIds,
            };
          });
        }
        await _client.from('poster_columns').update({
          'title': title,
          'subtitle': subtitle,
          'vaccine_ids': vaccineIds,
        }).eq('column_id', columnId);
      } else {
        // Insert new column
        final insertRes = await _client.from('poster_columns').insert({
          'bhc_id': _selectedBhcId!,
          'title': title,
          'subtitle': subtitle,
          'vaccine_ids': vaccineIds,
          'display_order': _columns.length,
        }).select().single();
        
        setState(() {
          _columns.add(insertRes);
        });
      }

      await _loadColumnsAndSeedIfEmpty();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate('Column saved successfully.', 'Matagumpay na nai-save ang kolum.')),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      debugPrint('Error saving column: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate('Failed to save column.', 'Bigo sa pag-save ng kolum.')),
          backgroundColor: AppColors.error,
        ),
      );
      await _loadColumnsAndSeedIfEmpty();
    } finally {
      setState(() => _syncing = false);
    }
  }

  String _getVaccineNamesForColumn(int columnId) {
    final list = _getVaccinesForColumn(columnId);
    if (list.isEmpty) return '—';
    final names = list.map((v) => v['vaccine_name']?.toString() ?? '').toSet().toList();
    return names.join(', ');
  }

  Widget _buildPosterTable() {
    if (_columns.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: Text(_translate('No columns configured.', 'Walang kolum na naka-configure.')),
      );
    }

    final showAddColumn = _canEditSelectedBhc && _columns.isNotEmpty;

    final Map<int, TableColumnWidth> colWidths = {
      0: const FlexColumnWidth(1.2),
    };
    for (int i = 0; i < _columns.length; i++) {
      colWidths[i + 1] = const FlexColumnWidth(1.6);
    }
    if (showAddColumn) {
      colWidths[_columns.length + 1] = const FlexColumnWidth(0.6);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Table(
          border: TableBorder.symmetric(
            inside: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          columnWidths: colWidths,
          children: [
            // Table Header
            TableRow(
              decoration: const BoxDecoration(color: AppColors.bgSecondary),
              children: [
                _buildHeaderCell(_translate('PETSA', 'PETSA'), _translate('Buwan', 'Buwan')),
                ..._columns.asMap().entries.map((entry) {
                  return _buildDraggableHeaderCell(entry.key, entry.value);
                }),
                if (showAddColumn)
                  _buildAddColumnHeaderCell(),
              ],
            ),
            // Month Rows
            ...List.generate(12, (index) {
              final monthNum = index + 1;
              final monthEng = _months[index];
              final monthFil = _monthsFilipino[index];
              final monthName = _translate(monthEng, monthFil).toUpperCase();

              return TableRow(
                children: [
                  _buildMonthCell(monthName),
                  ..._columns.map((col) {
                    final columnId = col['column_id'] as int;
                    final title = col['title']?.toString() ?? '';
                    final subtitle = col['subtitle']?.toString() ?? '';
                    final sub = '${_getVaccineNamesForColumn(columnId)}\n$subtitle';
                    final colDates = _getDatesForCell(columnId, monthNum);
                    return _buildDataCell(columnId, monthNum, colDates, '$title $sub');
                  }),
                  if (showAddColumn)
                    Container(
                      height: 52,
                      decoration: const BoxDecoration(color: AppColors.bgSecondary),
                      child: const SizedBox.shrink(),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableHeaderCell(int index, Map<String, dynamic> col) {
    final columnId = col['column_id'] as int;
    final title = col['title']?.toString() ?? '';
    final subtitle = col['subtitle']?.toString() ?? '';
    final sub = '${_getVaccineNamesForColumn(columnId)}\n$subtitle';
    
    final cellContent = _buildHeaderCell(title, sub);

    if (!_canEditSelectedBhc) return cellContent;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) async {
        final fromIndex = details.data;
        final toIndex = index;
        await _reorderColumns(fromIndex, toIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isOver = candidateData.isNotEmpty;
        return Draggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.brandText),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: cellContent,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isOver ? AppColors.brandPrimary.withValues(alpha: 0.08) : Colors.transparent,
            ),
            child: cellContent,
          ),
        );
      },
    );
  }

  Widget _buildAddColumnHeaderCell() {
    return Container(
      height: 58,
      alignment: Alignment.center,
      child: IconButton(
        tooltip: _translate('Add Column', 'Magdagdag ng Kolum'),
        icon: const Icon(
          Icons.add_circle_outline_rounded,
          color: AppColors.brandPrimary,
          size: 22,
        ),
        onPressed: _columns.length >= 6
            ? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_translate(
                      '⚠️ Maximum limit of 6 columns reached.',
                      '⚠️ Naabot na ang limitasyon na 6 na kolum.',
                    )),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            : () => _showAddEditColumnDialog(),
      ),
    );
  }

  Future<void> _reorderColumns(int fromIndex, int toIndex) async {
    if (fromIndex == toIndex) return;

    // Optimistic UI update
    setState(() {
      final item = _columns.removeAt(fromIndex);
      _columns.insert(toIndex, item);
      _syncing = true;
    });

    try {
      for (int i = 0; i < _columns.length; i++) {
        final colId = _columns[i]['column_id'] as int;
        await _client
            .from('poster_columns')
            .update({'display_order': i})
            .eq('column_id', colId);
      }
    } catch (e) {
      debugPrint('Error reordering columns: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_translate('Failed to save columns order.', 'Bigo sa pag-save ng pagkasunod-sunod ng mga kolum.')),
            backgroundColor: AppColors.error,
          ),
        );
      }
      await _loadColumnsAndSeedIfEmpty();
    } finally {
      setState(() => _syncing = false);
    }
  }

  Widget _buildHeaderCell(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: AppColors.brandText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey.shade600,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCell(String name) {
    return Container(
      height: 52,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      child: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
          color: AppColors.textPrimary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDataCell(int categoryId, int monthNum, List<DateTime> dates, String catTitle) {
    final displayText = _formatDatesCell(dates);
    final hasDates = dates.isNotEmpty;

    return InkWell(
      onTap: () => _onCellTapped(categoryId, monthNum, catTitle),
      child: Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  displayText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: hasDates ? FontWeight.bold : FontWeight.normal,
                    color: hasDates ? AppColors.brandText : AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (_canEditSelectedBhc)
              Positioned(
                bottom: 0,
                right: 0,
                child: Icon(
                  Icons.edit_calendar_rounded,
                  size: 11,
                  color: AppColors.brandPrimary.withValues(alpha: 0.8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemindersCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.brandText, size: 20),
              const SizedBox(width: 8),
              Text(
                _translate('PAALALA:', 'PAALALA:'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _reminderItem(_translate(
            'SANGGOL: Hindi maaaring bakunahan ang batang may ubo, sipon at lagnat.',
            'SANGGOL: Hindi maaaring bakunahan ang batang may ubo, sipon at lagnat.',
          )),
          _reminderItem(_translate(
            'BUNTIS: Hindi maaaring bakunahan ang gutom at sumasakit ang tiyan.',
            'BUNTIS: Hindi maaaring bakunahan ang gutom at sumasakit ang tiyan.',
          )),
          _reminderItem(_translate(
            'SA WALA PANG RECORD: Magparecord bago ang nasabing petsa ng bakuna.',
            'SA WALA PANG RECORD: Magparecord bago ang nasabing petsa ng bakuna.',
          )),
        ],
      ),
    );
  }

  Widget _reminderItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppColors.brandPrimary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterCard() {
    final bhcName = _bhcs.firstWhere(
      (b) => b['bhc_id'] == _selectedBhcId,
      orElse: () => {'bhc_name': 'Health Center'},
    )['bhc_name']?.toString() ?? 'Health Center';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            _translate('Paalala mula sa iyong $bhcName Midwives:', 'Paalala mula sa iyong $bhcName Midwives:'),
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          if (_midwives.isEmpty)
            Text(
              _translate('No active midwives registered for this center.', 'Walang rehistradong midwife para sa health center na ito.'),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: _midwives.map((m) {
                final account = m['account'] as Map<String, dynamic>?;
                final first = account?['first_name']?.toString() ?? '';
                final last = account?['last_name']?.toString() ?? '';
                final name = 'Midwife $first $last'.trim();
                final phone = account?['phone_number']?.toString() ?? 'No contact';

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brandText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_iphone_rounded, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        final bhcName = _bhcs.firstWhere(
          (b) => b['bhc_id'] == _selectedBhcId,
          orElse: () => {'bhc_name': 'Health Center'},
        )['bhc_name']?.toString().toUpperCase() ?? 'BARANGAY HEALTH CENTER';

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: SecondaryHeader(
              title: _translate('Vaccine Poster Schedule', 'Iskedyul ng Bakuna'),
              onBack: () => Navigator.pop(context),
              trailing: _canEditSelectedBhc
                  ? IconButton(
                      icon: const Icon(Icons.settings_outlined, color: AppColors.brandPrimary),
                      onPressed: _showManageColumnsDialog,
                      tooltip: _translate('Manage Columns', 'I-manage ang mga Kolum'),
                    )
                  : null,
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(
                    children: [
                      if (_syncing) ...[
                        const LinearProgressIndicator(
                          color: AppColors.brandPrimary,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 12),
                      ],
                      // selectors: BHC and Year dropdowns
                      Row(
                        children: [
                          // BHC Dropdown selector — pill style matching AppInputField
                          Expanded(
                            child: Container(
                              height: 52,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _selectedBhcId,
                                  hint: Text(
                                    _translate('Select Barangay', 'Piliin ang Barangay'),
                                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                  ),
                                  isExpanded: true,
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.brandPrimary, size: 22),
                                  dropdownColor: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                                  items: _bhcs.map((b) {
                                    return DropdownMenuItem<int>(
                                      value: b['bhc_id'] as int,
                                      child: Text(
                                        b['bhc_name']?.toString() ?? '',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) async {
                                    if (value != null && value != _selectedBhcId) {
                                      setState(() {
                                        _selectedBhcId = value;
                                        _loading = true;
                                        _columns = [];
                                        _schedules = [];
                                      });
                                      await Future.wait([
                                        _loadColumnsAndSeedIfEmpty(),
                                        _loadSchedules(),
                                        _loadBhcMidwives(),
                                      ]);
                                      setState(() => _loading = false);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Year Dropdown selector — pill style matching AppInputField
                          Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _selectedYear,
                                icon: const Icon(Icons.calendar_month, color: AppColors.brandPrimary, size: 20),
                                dropdownColor: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                items: _years.map((y) {
                                  return DropdownMenuItem<int>(
                                    value: y,
                                    child: Text(
                                      '$y',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) async {
                                  if (value != null && value != _selectedYear) {
                                    setState(() {
                                      _selectedYear = value;
                                      _loading = true;
                                    });
                                    await _loadSchedules();
                                    setState(() => _loading = false);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // The Main Poster Container
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.15)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandPrimary.withValues(alpha: 0.05),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Title header in pink container
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.bgSecondary,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    bhcName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.brandText,
                                      letterSpacing: 0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_translate('SCHEDULE NG BAKUNA', 'SCHEDULE NG BAKUNA')} — $_selectedYear',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Warnings box
                            _buildRemindersCard(),
                            const SizedBox(height: 16),

                            // The Schedule Grid
                            _buildPosterTable(),
                            const SizedBox(height: 16),

                            // Footer
                            _buildFooterCard(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
