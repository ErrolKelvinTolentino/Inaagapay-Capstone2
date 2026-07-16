// lib/screens/mother/records_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/language_service.dart';
import '../../services/mother_profile_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/headline.dart';
import '../../widgets/main_button.dart';
import '../../widgets/full_screen_image_viewer.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_dropdown_field.dart';
import '../shared/record_detail_screen.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isOpeningRecord = false;
  String? _errorMessage;
  int? _motherId;
  bool _isUnlinked = false;
  bool _isUnlinkedBannerDismissed = false;

  List<Map<String, dynamic>> _checkups = [];
  List<Map<String, dynamic>> _ultrasounds = [];
  List<Map<String, dynamic>> _labTests = [];
  List<Map<String, dynamic>> _maternalVitals = [];
  Map<int, int> _pregnancyFetalCounts = {};
  Map<int, String> _checkupSymptomSummaries = {};

  String _selectedFilter = 'all';
  String _sortOrder = 'desc';
  String _searchQuery = '';
  final Set<String> _expandedLabInsightAspects = <String>{};
  StateSetter? _recordDetailsModalSetState;

  late final TextEditingController _searchController;

  // Pagination — show 5 records at a time
  static const int _pageSize = 5;
  int _displayCount = _pageSize;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _tabController = TabController(length: 1, vsync: this);
    _loadMotherData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  String _notInputted() => _t('Not inputted', 'Hindi nailagay');

  String _noneRecorded() => _t('None recorded', 'Walang naitala');


  void _refreshRecordDetailsUi() {
    final modalSetState = _recordDetailsModalSetState;
    if (modalSetState != null) {
      modalSetState(() {});
      return;
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadMotherData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _motherId = await AuthStorage.getMotherId();

      if (_motherId == null) {
        throw Exception('Mother ID not found');
      }

      final motherResponse = await SupabaseService.client
          .from('mothers')
          .select('assigned_bhc_id')
          .eq('mother_id', _motherId!)
          .maybeSingle();
      _isUnlinked =
          motherResponse == null || motherResponse['assigned_bhc_id'] == null;

      final pregnanciesResponse = await SupabaseService.client
          .from('pregnancies')
          .select('pregnancy_id')
          .eq('mother_id', _motherId!);

      if (pregnanciesResponse.isEmpty) {
        setState(() {
          _ultrasounds = [];
          _labTests = [];
        });
      } else {
        final pregnancyIds = pregnanciesResponse
            .map<int?>((p) => _toInt(p['pregnancy_id']))
            .whereType<int>()
            .toList();
        await _loadRecordsForPregnancies(pregnancyIds);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
        _displayCount = _pageSize; // Reset pagination on reload
      });
    }
  }

  Future<void> _loadRecordsForPregnancies(List<int> pregnancyIds) async {
    if (pregnancyIds.isNotEmpty) {
      final checkupsResponse = await SupabaseService.client
          .from('prenatal_checkups')
          .select(
              '*, weight_gain:weight_gain_evaluations (evaluation_id, mode, status, confidence, message, flags, actual_gain, weekly_gain)')
          .inFilter('pregnancy_id', pregnancyIds)
          .order('checkup_datetime', ascending: false);

      final ultrasoundsResponse = await SupabaseService.client
          .from('ultrasounds')
          .select('*')
          .inFilter('pregnancy_id', pregnancyIds)
          .order('ultrasound_date', ascending: false);

      final labTestsResponse = await SupabaseService.client
          .from('lab_tests')
          .select('*')
          .inFilter('pregnancy_id', pregnancyIds)
          .order('lab_test_date', ascending: false);

      final maternalVitalsResponse = await SupabaseService.client
          .from('maternal_vitals')
          .select('*')
          .inFilter('pregnancy_id', pregnancyIds)
          .order('recorded_at', ascending: false);

      final pregnancyResponse = await SupabaseService.client
          .from('pregnancies')
          .select('pregnancy_id, fetal_count')
          .inFilter('pregnancy_id', pregnancyIds);

      final checkupIds = (checkupsResponse as List)
          .map<int?>((c) => _toInt(c['prenatal_checkup_id']))
          .whereType<int>()
          .toList();

      Map<int, String> symptomSummaries = {};
      if (checkupIds.isNotEmpty) {
        final symptomRows = await SupabaseService.client
            .from('pregnancy_symptoms')
            .select(
                'prenatal_checkup_id, symptom_type_id, notes, symptom_type:symptom_types(symptom_name, risk_category)')
            .inFilter('prenatal_checkup_id', checkupIds);

        for (final symbol
            in (symptomRows as List).cast<Map<String, dynamic>>()) {
          final checkupId = _toInt(symbol['prenatal_checkup_id']);
          if (checkupId == null) continue;
          final symptomType = symbol['symptom_type'] as Map<String, dynamic>?;
          final name = symptomType?['symptom_name']?.toString() ??
              _t('Unknown symptom', 'Hindi alam na sintomas');
          final risk = symptomType?['risk_category']?.toString() ??
              _t('unknown', 'hindi alam');
          final note = (symbol['notes'] as String?)?.trim();
          final label = note != null && note.isNotEmpty
              ? '$name ($risk): $note'
              : '$name ($risk)';
          symptomSummaries.update(
            checkupId,
            (existing) {
              final items = existing.split('; ');
              items.add(label);
              return items.join('; ');
            },
            ifAbsent: () => label,
          );
        }
      }

      final fetalCounts = <int, int>{};
      for (final pregnancy
          in (pregnancyResponse as List).cast<Map<String, dynamic>>()) {
        final id = _toInt(pregnancy['pregnancy_id']);
        final count = _toInt(pregnancy['fetal_count']);
        if (id != null && count != null) {
          fetalCounts[id] = count;
        }
      }

      setState(() {
        _checkups = List<Map<String, dynamic>>.from(checkupsResponse);
        _ultrasounds = List<Map<String, dynamic>>.from(ultrasoundsResponse);
        _labTests = List<Map<String, dynamic>>.from(labTestsResponse);
        _maternalVitals = List<Map<String, dynamic>>.from(maternalVitalsResponse);
        _pregnancyFetalCounts = fetalCounts;
        _checkupSymptomSummaries = symptomSummaries;
      });
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '—';
    try {
      final parsed = DateTime.tryParse(date.toString());
      if (parsed == null) return date.toString();
      return DateFormat('MMM d, yyyy').format(parsed);
    } catch (e) {
      return date.toString();
    }
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return '—';
    try {
      final parsed = DateTime.tryParse(dateTime.toString());
      if (parsed == null) return dateTime.toString();
      return DateFormat('MMM d, yyyy h:mm a').format(parsed);
    } catch (e) {
      return dateTime.toString();
    }
  }

  String _formatValue(dynamic value) {
    if (value == null) return '—';
    final str = value.toString().trim();
    return str.isEmpty ? '—' : str;
  }

  String _formatInputValue(dynamic value) {
    final formatted = _formatValue(value);
    return formatted == '—' ? _notInputted() : formatted;
  }

  bool _isSameDay(dynamic dateVal1, dynamic dateVal2) {
    if (dateVal1 == null || dateVal2 == null) return false;
    try {
      var d1 = DateTime.tryParse(dateVal1.toString());
      var d2 = DateTime.tryParse(dateVal2.toString());
      if (d1 == null || d2 == null) return false;
      d1 = d1.toLocal();
      d2 = d2.toLocal();
      return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
    } catch (_) {
      return false;
    }
  }

  List<String> _parseImageUrls(dynamic imageField) {
    List<String> urls = [];
    if (imageField != null) {
      final imageString = imageField.toString();
      if (imageString.contains(',')) {
        urls = imageString.split(',').map((url) => url.trim()).toList();
      } else if (imageString.isNotEmpty) {
        urls = [imageString];
      }
    }
    return urls;
  }

  ({String cleanRemarks, String? extractedAi}) _splitRemarksAndAi(
      String? rawRemarks) {
    final source = rawRemarks?.trim() ?? '';
    if (source.isEmpty) {
      return (cleanRemarks: '', extractedAi: null);
    }

    final marker = RegExp(r'\bAI\s*Analysis\s*:', caseSensitive: false);
    final match = marker.firstMatch(source);
    if (match == null) {
      return (cleanRemarks: source, extractedAi: null);
    }

    final notesPart = source.substring(0, match.start).trim();
    final aiPart = source.substring(match.end).trim();
    return (
      cleanRemarks: notesPart,
      extractedAi: aiPart.isEmpty ? null : aiPart,
    );
  }

  ({String cleanRemarks, String? extractedAi}) _splitLabRemarksAndAi(
      String? rawRemarks) {
    return _splitRemarksAndAi(rawRemarks);
  }

  void _showFullScreenImage(List<String> imageUrls, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _showRecordDetails({
    required String title,
    required List<MapEntry<String, String>> rows,
    IconData icon = Icons.receipt_long,
    String? subtitle,
    List<String>? imageUrls,
    String? aiAnalysis,
    bool useStructuredAiInsights = false,
    String? riskLevel,
    String? riskFactors,
    List<String>? suggestedActions,
    Map<String, dynamic>? weightGainEval,
    String? ultrasoundClassification,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordDetailScreen(
          title: title,
          rows: rows,
          icon: icon,
          subtitle: subtitle,
          imageUrls: imageUrls,
          aiAnalysis: aiAnalysis,
          useStructuredAiInsights: useStructuredAiInsights,
          riskLevel: (riskLevel != null && riskLevel.trim().isNotEmpty)
              ? riskLevel
              : null,
          riskFactors: (riskFactors != null && riskFactors.trim().isNotEmpty)
              ? riskFactors.split(';').map((s) => s.trim()).toList()
              : null,
          suggestedActions: suggestedActions,
          weightGainEval: weightGainEval,
          ultrasoundClassification: ultrasoundClassification,
        ),
      ),
    );
  }

  // Legacy modal-based method (kept for non-prenatal records if needed)
  void _showRecordDetailsModal({
    required String title,
    required List<MapEntry<String, String>> rows,
    IconData icon = Icons.receipt_long,
    String? subtitle,
    List<String>? imageUrls,
    String? aiAnalysis,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        bool showFullAi = false;
        bool isEditing = false;
        final editController = TextEditingController(text: aiAnalysis ?? '');

        return StatefulBuilder(
          builder: (context, setModalState) {
            _recordDetailsModalSetState = setModalState;
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.bgSecondary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child:
                                    Icon(icon, color: AppColors.brandPrimary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (subtitle != null && subtitle.isNotEmpty)
                                      Text(
                                        subtitle,
                                        style: const TextStyle(
                                            color: AppColors.textSecondary),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (imageUrls != null && imageUrls.isNotEmpty) ...[
                            SizedBox(
                              height: 200,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: imageUrls.length,
                                itemBuilder: (context, index) {
                                  return GestureDetector(
                                    onTap: () =>
                                        _showFullScreenImage(imageUrls, index),
                                    child: Container(
                                      width: 200,
                                      margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Image.network(
                                              imageUrls[index],
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                color: AppColors.bgSecondary,
                                                child: Center(
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(Icons.broken_image,
                                                          size: 32,
                                                          color: Colors.grey),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        LanguageService.translate(
                                                            'Image not available',
                                                            'Hindi available ang larawan'),
                                                        style: const TextStyle(
                                                            fontSize: 10),
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              loadingBuilder: (context, child,
                                                  loadingProgress) {
                                                if (loadingProgress == null) {
                                                  return child;
                                                }
                                                return Container(
                                                  color: AppColors.bgSecondary,
                                                  child: const Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              AppColors
                                                                  .brandPrimary),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            if (imageUrls.length > 1 &&
                                                index == 0)
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.6),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Text(
                                                    '+${imageUrls.length - 1} ${_t('more', 'pa')}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.bgSecondary,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: AppColors.borderPrimary),
                            ),
                            child: Column(
                              children: rows
                                  .map((entry) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                entry.key,
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                entry.value,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                          if (aiAnalysis != null && aiAnalysis.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3E5F5),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: const Color(0xFF7E57C2)
                                        .withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.psychology_rounded,
                                          color: const Color(0xFF7E57C2),
                                          size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        _t('AI-Powered Insights',
                                            'AI na Pagsusuri'),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF5E35B1),
                                        ),
                                      ),
                                      const Spacer(),
                                      TextButton.icon(
                                        onPressed: () {
                                          setModalState(() {
                                            isEditing = !isEditing;
                                            if (!isEditing) {
                                              editController.text = aiAnalysis;
                                            }
                                          });
                                        },
                                        icon: Icon(Icons.edit_outlined,
                                            size: 16,
                                            color: isEditing
                                                ? AppColors.success
                                                : AppColors.brandPrimary),
                                        label: Text(
                                          isEditing
                                              ? _t('Cancel', 'Kanselahin')
                                              : _t('Edit', 'I-edit'),
                                          style: TextStyle(
                                              color: isEditing
                                                  ? AppColors.success
                                                  : AppColors.brandPrimary),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (!isEditing)
                                    Text(
                                      aiAnalysis,
                                      style: const TextStyle(
                                          fontSize: 13, height: 1.5),
                                    )
                                  else
                                    Column(
                                      children: [
                                        TextField(
                                          controller: editController,
                                          maxLines: 10,
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(),
                                            hintText: _t('Edit AI insights...',
                                                'I-edit ang AI na pagsusuri...'),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            TextButton(
                                              onPressed: () {
                                                setModalState(() {
                                                  isEditing = false;
                                                  editController.text =
                                                      aiAnalysis;
                                                });
                                              },
                                              child:
                                                  Text(_t('Discard', 'Itapon')),
                                            ),
                                            const SizedBox(width: 8),
                                            ElevatedButton(
                                              onPressed: () {
                                                setModalState(() {
                                                  isEditing = false;
                                                });
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(_t(
                                                        'AI insights updated locally',
                                                        'Na-update ang AI na pagsusuri sa lokal')),
                                                    backgroundColor:
                                                        AppColors.success,
                                                  ),
                                                );
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.brandPrimary,
                                              ),
                                              child: Text(_t('Save', 'I-save')),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _t('Note: This is AI-generated analysis for informational purposes only.',
                                          'Paalala: Ang pagsusuring ito ay gawa ng AI at para lamang sa impormasyon.'),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString());
  }

  // REMOVED: _generatePrenatalAIInsights - this was the culprit generating fake AI text

  String _generateUltrasoundAIInsights(Map<String, dynamic> ultrasound) {
    final remarks = ultrasound['remarks']?.toString().toLowerCase() ?? '';
    final buffer = StringBuffer();

    buffer.write(
        '${_t('Ultrasound AI Insights', 'AI na Pagsusuri ng Ultrasound')}:\n\n');

    if (remarks.contains('normal') || remarks.contains('healthy')) {
      buffer.write(_t(
          'Normal Findings: Ultrasound appears normal with healthy fetal development.\n\n',
          'Normal na Resulta: Mukhang normal ang ultrasound at malusog ang paglaki ng sanggol.\n\n'));
    } else if (remarks.contains('follow') || remarks.contains('monitor')) {
      buffer.write(_t(
          'Follow-up Recommended: Some findings require additional observation.\n\n',
          'Kailangan ng Follow-up: May ilang resulta na kailangang masubaybayan pa.\n\n'));
    } else if (remarks.contains('concern') || remarks.contains('abnormal')) {
      buffer.write(_t(
          'Further Evaluation Needed: Discuss findings with healthcare provider.\n\n',
          'Kailangan ng Dagdag na Pagsusuri: Ipag-usap ang resulta sa healthcare provider.\n\n'));
    } else {
      buffer.write(_t(
          'Diagnostic Information: The ultrasound provides important diagnostic information.\n\n',
          'Impormasyong Diagnostic: Nagbibigay ang ultrasound ng mahalagang impormasyon.\n\n'));
    }

    buffer
        .write('${_t('Key Recommendations', 'Mahahalagang Rekomendasyon')}:\n');
    buffer.write(
        '• ${_t('Discuss findings with your healthcare provider', 'Ipag-usap ang resulta sa iyong healthcare provider')}\n');
    buffer.write(
        '• ${_t('Continue all scheduled prenatal appointments', 'Ipagpatuloy ang lahat ng nakatakdang prenatal appointment')}\n');

    return buffer.toString();
  }

  Future<Map<String, dynamic>?> _fetchCheckupDetails(
      int prenatalCheckupId, dynamic checkupDateTime) async {
    try {
      final aiRow = await SupabaseService.client
          .from('ai_responses')
          .select('ai_response_id, response, status')
          .eq('reference_table', 'prenatal_checkups')
          .eq('reference_id', prenatalCheckupId)
          .eq('response_type', 'risk_assessment')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      String? aiResponse = aiRow?['response'] as String?;
      final status = aiRow?['status'] as String?;
      if (status != 'approved') {
        aiResponse = null;
      }
      String? riskLevel;
      String riskFactors = '';
      String medicationPlans = _t('None', 'Wala');
      String givenMedications = _t('None', 'Wala');
      String ferrousQuantity = _t('Not given', 'Hindi ibinigay');
      String calciumQuantity = _t('Not given', 'Hindi ibinigay');

      if (aiRow != null) {
        final aiResponseId = _toInt(aiRow['ai_response_id']);
        if (aiResponseId != null) {
          final riskRow = await SupabaseService.client
              .from('pregnancy_risk_assessments')
              .select('pregnancy_risk_id, risk_level')
              .eq('ai_response_id', aiResponseId)
              .maybeSingle();

          if (riskRow != null) {
            riskLevel = riskRow['risk_level']?.toString();
            final factorRows = await SupabaseService.client
                .from('pregnancy_risk_factors')
                .select('factor, risk_influence')
                .eq('pregnancy_risk_id', riskRow['pregnancy_risk_id'])
                .order('risk_factor_id', ascending: true);

            final factorList = <String>[];
            for (final factor
                in (factorRows as List).cast<Map<String, dynamic>>()) {
              final factorText = factor['factor']?.toString() ?? '';
              final influence = factor['risk_influence']?.toString() ?? '';
              if (factorText.isNotEmpty) {
                factorList.add(
                    '$factorText${influence.isNotEmpty ? ' ($influence)' : ''}');
              }
            }
            riskFactors = factorList.join('; ');
          }
        }
      }

      if (checkupDateTime != null) {
        final date = DateTime.tryParse(checkupDateTime.toString());
        final checkupDateString =
            date != null ? date.toIso8601String().split('T')[0] : null;
        if (checkupDateString != null && _motherId != null) {
          final givenRows = await SupabaseService.client
              .from('given_medications')
              .select('given_medication_name, quantity')
              .eq('mother_id', _motherId!)
              .eq('date_given', checkupDateString);

          final medicationRows = await SupabaseService.client
              .from('mother_medications')
              .select(
                  'mother_medication_name, quantity, frequency, start_date, end_date')
              .eq('mother_id', _motherId!)
              .eq('start_date', checkupDateString);

          final givenItems = <String>[];
          for (final row in (givenRows as List).cast<Map<String, dynamic>>()) {
            final name = row['given_medication_name']?.toString() ??
                _t('Unknown', 'Hindi alam');
            final quantity = row['quantity']?.toString() ?? '1';
            givenItems.add('$name x$quantity');
            if (name.toLowerCase().contains('ferrous')) {
              ferrousQuantity = quantity;
            }
            if (name.toLowerCase().contains('calcium')) {
              calciumQuantity = quantity;
            }
          }
          if (givenItems.isNotEmpty) {
            givenMedications = givenItems.join('; ');
          }

          final planItems = <String>[];
          for (final row
              in (medicationRows as List).cast<Map<String, dynamic>>()) {
            final name = row['mother_medication_name']?.toString() ??
                _t('Unknown', 'Hindi alam');
            final qty = row['quantity']?.toString() ?? '1';
            final freq = row['frequency']?.toString();
            final start = row['start_date']?.toString();
            final end = row['end_date']?.toString();
            final details = [
              qty != 'null' ? '${_t('Qty', 'Dami')} $qty' : null,
              freq,
              start != null ? '${_t('Start', 'Simula')} $start' : null,
              end != null ? '${_t('End', 'Katapusan')} $end' : null
            ].where((element) => element != null).join(' · ');
            planItems.add('$name${details.isNotEmpty ? ' ($details)' : ''}');
          }
          if (planItems.isNotEmpty) {
            medicationPlans = planItems.join('; ');
          }
        }
      }

      return {
        'aiResponse': aiResponse,
        'riskLevel': riskLevel,
        'riskFactors': riskFactors,
        'medicationPlans': medicationPlans,
        'givenMedications': givenMedications,
        'ferrousQuantity': ferrousQuantity,
        'calciumQuantity': calciumQuantity,
      };
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _getFilteredAndSortedRecords() {
    List<Map<String, dynamic>> allRecords = [];

    for (var checkup in _checkups) {
      allRecords.add({
        ...checkup,
        'record_type': 'checkup',
        'record_date': checkup['checkup_datetime'],
      });
    }

    for (var ultrasound in _ultrasounds) {
      allRecords.add({
        ...ultrasound,
        'record_type': 'ultrasound',
        'record_date': ultrasound['ultrasound_date'],
      });
    }

    for (var labTest in _labTests) {
      allRecords.add({
        ...labTest,
        'record_type': 'labtest',
        'record_date': labTest['lab_test_date'],
      });
    }

    for (var vital in _maternalVitals) {
      allRecords.add({
        ...vital,
        'record_type': 'maternal_vital',
        'record_date': vital['recorded_at'],
      });
    }

    if (_selectedFilter != 'all') {
      allRecords = allRecords
          .where((record) => record['record_type'] == _selectedFilter)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      allRecords = allRecords.where((record) {
        if (record['record_type'] == 'checkup') {
          return _formatDateTime(record['checkup_datetime'])
                  .toLowerCase()
                  .contains(query) ||
              (record['remarks']?.toString().toLowerCase().contains(query) ??
                  false) ||
              (record['blood_pressure_systolic']
                      ?.toString()
                      .toLowerCase()
                      .contains(query) ??
                  false) ||
              (record['blood_pressure_diastolic']
                      ?.toString()
                      .toLowerCase()
                      .contains(query) ??
                  false);
        }

        if (record['record_type'] == 'ultrasound') {
          return _formatDate(record['ultrasound_date'])
                  .toLowerCase()
                  .contains(query) ||
              (record['remarks']?.toString().toLowerCase().contains(query) ??
                  false);
        }

        if (record['record_type'] == 'labtest') {
          return _formatDate(record['lab_test_date'])
                  .toLowerCase()
                  .contains(query) ||
              (record['lab_test_type']
                      ?.toString()
                      .toLowerCase()
                      .contains(query) ??
                  false) ||
              (record['remarks']?.toString().toLowerCase().contains(query) ??
                  false);
        }

        if (record['record_type'] == 'maternal_vital') {
          return _formatDateTime(record['recorded_at'])
                  .toLowerCase()
                  .contains(query) ||
              (record['notes']?.toString().toLowerCase().contains(query) ??
                  false) ||
              (record['weight_kg']?.toString().toLowerCase().contains(query) ??
                  false) ||
              (record['height_cm']?.toString().toLowerCase().contains(query) ??
                  false);
        }

        return false;
      }).toList();
    }

    allRecords.sort((a, b) {
      final dateA = DateTime.tryParse(a['record_date'] ?? '');
      final dateB = DateTime.tryParse(b['record_date'] ?? '');
      if (dateA == null || dateB == null) return 0;
      return _sortOrder == 'desc'
          ? dateB.compareTo(dateA)
          : dateA.compareTo(dateB);
    });

    return allRecords;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        if (_isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.brandPrimary),
                ),
                const SizedBox(height: 16),
                Text(
                  _t('Loading records...', 'Naglo-load ng records...'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        if (_errorMessage != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Headline(
                      text: _t('Failed to Load Records',
                          'Hindi Na-load ang Records')),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  MainButton(
                    label: _t('Retry', 'Subukan Muli'),
                    onPressed: _loadMotherData,
                  ),
                ],
              ),
            ),
          );
        }

        final allRecords = _getFilteredAndSortedRecords();

        return _buildRecordsTab(allRecords);
      },
    );
  }

  Widget _buildRecordsTab(List<Map<String, dynamic>> allRecords) {
    return Column(
      children: [
        if (_isUnlinked && !_isUnlinkedBannerDismissed)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(
                      'Individual Mode: Clinical records uploaded by midwives (checkups, lab tests, ultrasounds) are only available when linked to a BHC.',
                      'Indibidwal na Mode: Ang mga klinikal na record (checkup, lab test, ultrasound) na in-upload ng midwife ay magagamit lamang kapag naka-link sa BHC.',
                    ),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    setState(() {
                      _isUnlinkedBannerDismissed = true;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              AppInputField(
                hintText: _t('Search records...', 'Maghanap ng records...'),
                controller: _searchController,
                leadingIcon: Icons.search,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _displayCount = _pageSize; // Reset on search change
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppDropdownField<String>(
                      hintText: _t('All Records', 'Lahat ng Records'),
                      value: _selectedFilter,
                      options: const ['all', 'checkup', 'ultrasound', 'labtest', 'maternal_vital'],
                      displayStringForOption: (value) {
                        switch (value) {
                          case 'all':
                            return _t('All Records', 'Lahat ng Records');
                          case 'checkup':
                            return _t('Checkups Only', 'Checkups Lang');
                          case 'ultrasound':
                            return _t('Ultrasounds Only', 'Ultrasounds Lang');
                          case 'labtest':
                            return _t('Lab Tests Only', 'Lab Tests Lang');
                          case 'maternal_vital':
                            return _t('Self-logged Vitals Only', 'Sariling Vitals Lang');
                          default:
                            return '';
                        }
                      },
                      onSelected: (value) {
                        setState(() {
                          _selectedFilter = value;
                          _displayCount = _pageSize; // Reset on filter change
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: AppDropdownField<String>(
                      hintText: _t('Newest First', 'Pinakabago Muna'),
                      value: _sortOrder,
                      options: const ['desc', 'asc'],
                      displayStringForOption: (value) {
                        switch (value) {
                          case 'desc':
                            return _t('Newest First', 'Pinakabago Muna');
                          case 'asc':
                            return _t('Oldest First', 'Pinakaluma Muna');
                          default:
                            return '';
                        }
                      },
                      onSelected: (value) {
                        setState(() {
                          _sortOrder = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: allRecords.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchQuery.isNotEmpty
                            ? Icons.search_off
                            : Icons.folder_open,
                        size: 64,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? _t('No matching records found',
                                'Walang record na tumugma')
                            : (_isUnlinked
                                ? _t('Individual Mode (Unlinked)',
                                    'Indibidwal na Mode (Hindi Naka-link)')
                                : _t('No records available',
                                    'Walang available na records')),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? _t('Try adjusting your search or filters',
                                  'Subukang baguhin ang paghahanap o filter')
                              : (_isUnlinked
                                  ? _t(
                                      'To receive clinical midwife checkups, lab results, and ultrasound records, link your account to a Barangay Health Center (BHC). You can still log journals and add child records here.',
                                      'Upang makatanggap ng klinikal na checkup, lab test at ultrasound, i-link ang iyong account sa BHC. Maaari ka pa ring mag-tala ng journals at anak dito.')
                                  : _t('Your medical records will appear here',
                                      'Lalabas dito ang iyong medical records')),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMotherData,
                  color: AppColors.brandPrimary,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: allRecords.length <= _displayCount
                        ? allRecords.length
                        : _displayCount + 1, // +1 for the Load More button
                    itemBuilder: (context, index) {
                      // Show "Load More" button at the end
                      if (index == _displayCount &&
                          allRecords.length > _displayCount) {
                        final remaining = allRecords.length - _displayCount;
                        final nextBatch =
                            remaining > _pageSize ? _pageSize : remaining;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _displayCount += _pageSize),
                              icon: const Icon(Icons.expand_more, size: 18),
                              label: Text(
                                _t(
                                  'Load More ($nextBatch of $remaining remaining)',
                                  'Mag-load Pa ($nextBatch sa $remaining natitira)',
                                ),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.brandPrimary,
                                side: BorderSide(
                                    color: AppColors.brandPrimary
                                        .withValues(alpha: 0.3)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        );
                      }

                      final record = allRecords[index];
                      final isCheckup = record['record_type'] == 'checkup';
                      final isUltrasound =
                          record['record_type'] == 'ultrasound';
                      final isLabTest = record['record_type'] == 'labtest';
                      final isMaternalVital =
                          record['record_type'] == 'maternal_vital';

                      final typeColor = isCheckup
                          ? AppColors.brandPrimary
                          : isUltrasound
                              ? AppColors.brandAccent
                              : isLabTest
                                  ? AppColors.warning
                                  : Colors.teal;

                      final dateCreated = _formatDateTime(
                          record['recorded_at'] ??
                              record['created_at'] ??
                              record['createdAt'] ??
                              record['checkup_datetime']);

                      final titleText = isCheckup
                          ? _t('Prenatal Checkup', 'Prenatal Checkup')
                          : isUltrasound
                              ? _t('Ultrasound', 'Ultrasound')
                              : isLabTest
                                  ? (record['lab_test_type'] ?? _t('Lab Test', 'Lab Test'))
                                  : _t('Self-logged Vitals', 'Sariling Vitals');

                      final showConductDate = (isUltrasound || isLabTest) &&
                          !_isSameDay(
                            record['created_at'] ?? record['createdAt'],
                            isUltrasound ? record['ultrasound_date'] : record['lab_test_date'],
                          );

                      final conductDateStr = showConductDate
                          ? '${_t('Conducted on', 'Isinagawa noong')} ${_formatDate(isUltrasound ? record['ultrasound_date'] : record['lab_test_date'])}'
                          : null;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.borderPrimary,
                                ),
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    // Left accent strip
                                    Container(
                                      width: 4,
                                      decoration: BoxDecoration(
                                        color: typeColor,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(12),
                                          bottomLeft: Radius.circular(12),
                                        ),
                                      ),
                                    ),

                                    // Icon
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: typeColor.withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          isCheckup
                                              ? Icons.medical_services_outlined
                                              : isUltrasound
                                                  ? Icons.monitor_heart_outlined
                                                  : isLabTest
                                                      ? Icons.science_outlined
                                                      : Icons.monitor_weight_outlined,
                                          color: typeColor,
                                          size: 18,
                                        ),
                                      ),
                                    ),

                                    // Content
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              titleText,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              dateCreated,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                            if (conductDateStr != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                conductDateStr,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Chevron
                                    const Padding(
                                      padding: EdgeInsets.only(right: 12),
                                      child: Icon(
                                        Icons.chevron_right,
                                        color: AppColors.textSecondary,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            onTap: () async {
                            if (_isOpeningRecord) return;
                            setState(() => _isOpeningRecord = true);
                            bool hasClosedLoading = false;

                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.brandPrimary),
                              ),
                            );

                            try {
                              if (isCheckup) {
                                final bpSys = _formatInputValue(
                                    record['blood_pressure_systolic']);
                                final bpDia = _formatInputValue(
                                    record['blood_pressure_diastolic']);
                                final checkupId = record['prenatal_checkup_id'];
                                String? aiAnalysis;
                                String? riskLevel;
                                String riskFactors = '';
                                List<String> riskFactorList = [];
                                List<String> suggestedActionsList = [];
                                String medicationPlansSummary =
                                    _t('None', 'Wala');
                                String givenMedicationsSummary =
                                    _t('None', 'Wala');
                                String ferrousSummary =
                                    _t('Not given', 'Hindi ibinigay');
                                String calciumSummary =
                                    _t('Not given', 'Hindi ibinigay');

                                if (checkupId is int) {
                                  final checkupDetails =
                                      await _fetchCheckupDetails(checkupId,
                                          record['checkup_datetime']);
                                  if (checkupDetails != null) {
                                    riskLevel =
                                        checkupDetails['riskLevel'] as String?;

                                    final rf = checkupDetails['riskFactors']
                                            as String? ??
                                        '';
                                    if (rf.trim().isNotEmpty) {
                                      riskFactors = rf;
                                      riskFactorList = rf
                                          .split('; ')
                                          .where((s) => s.trim().isNotEmpty)
                                          .toList();
                                    }

                                    // PRIMARY SOURCE: Database AI response
                                    aiAnalysis =
                                        checkupDetails['aiResponse'] as String?;

                                    // FALLBACK: MotherProfileService
                                    if (aiAnalysis == null ||
                                        aiAnalysis.trim().isEmpty) {
                                      aiAnalysis = await MotherProfileService
                                          .getCheckupAIAnalysis(checkupId);
                                    }

                                    // NO FALLBACK to _generatePrenatalAIInsights
                                    // If still empty, leave as null (no AI section shown)

                                    medicationPlansSummary =
                                        checkupDetails['medicationPlans']
                                            as String;
                                    givenMedicationsSummary =
                                        checkupDetails['givenMedications']
                                            as String;
                                    ferrousSummary =
                                        checkupDetails['ferrousQuantity']
                                            as String;
                                    calciumSummary =
                                        checkupDetails['calciumQuantity']
                                            as String;
                                  }
                                }

                                final symptomSummary = _checkupSymptomSummaries[
                                        _toInt(record['prenatal_checkup_id']) ??
                                            -1] ??
                                    _noneRecorded();
                                final fetalCount = (_pregnancyFetalCounts[
                                            _toInt(record['pregnancy_id']) ??
                                                -1]
                                        ?.toString()) ??
                                    _notInputted();
                                final riskLevelValue = (riskLevel != null &&
                                        riskLevel.trim().isNotEmpty)
                                    ? riskLevel
                                    : '';
                                final riskFactorsValue =
                                    riskFactors.trim().isNotEmpty
                                        ? riskFactors
                                        : '';

                                if (mounted && !hasClosedLoading) {
                                  Navigator.of(context, rootNavigator: true)
                                      .pop();
                                  hasClosedLoading = true;
                                }

                                _showRecordDetails(
                                  title: _t(
                                      'Prenatal Checkup', 'Prenatal Checkup'),
                                  subtitle: _formatDateTime(
                                      record['checkup_datetime']),
                                  icon: Icons.medical_services,
                                  rows: [
                                    MapEntry(
                                        _t('Date', 'Petsa'),
                                        record['checkup_datetime'] == null
                                            ? _notInputted()
                                            : _formatDateTime(
                                                record['checkup_datetime'])),
                                    MapEntry(
                                        _t('Fetal Count', 'Bilang ng Sanggol'),
                                        fetalCount),
                                    MapEntry(
                                        _t('Age of Gestation',
                                            'Edad ng Pagbubuntis'),
                                        _formatInputValue(
                                            record['age_of_gestation'])),
                                    MapEntry(
                                        _t('Weight (kg)', 'Timbang (kg)'),
                                        _formatInputValue(
                                            record['checkup_weight'])),
                                    MapEntry(
                                        _t('Blood Pressure', 'Blood Pressure'),
                                        '$bpSys/$bpDia'),
                                    MapEntry(
                                        _t('Fetal Position',
                                            'Posisyon ng Sanggol'),
                                        _formatInputValue(
                                            record['fetal_position'])),
                                    MapEntry(
                                        _t('Fetal Heart Tone',
                                            'Tono ng Tibok ng Sanggol'),
                                        _formatInputValue(
                                            record['fetal_heart_tone'])),
                                    MapEntry(
                                        _t('Fetal Heart Beat',
                                            'Tibok ng Puso ng Sanggol'),
                                        _formatInputValue(
                                            record['fetal_heart_beat'])),
                                    MapEntry(_t('Symptoms', 'Mga Sintomas'),
                                        symptomSummary),
                                    MapEntry(
                                        _t('Medication Plans',
                                            'Plano sa Gamot'),
                                        medicationPlansSummary),
                                    MapEntry(
                                        _t('Given Medications',
                                            'Mga Gamot na Ibinigay'),
                                        givenMedicationsSummary),
                                    MapEntry('Ferrous + FA', ferrousSummary),
                                    MapEntry('Calcium', calciumSummary),
                                    MapEntry(
                                        _t('Risk Level', 'Antas ng Panganib'),
                                        riskLevelValue.isNotEmpty
                                            ? riskLevelValue
                                            : _notInputted()),
                                    MapEntry(
                                        _t('Risk Factors',
                                            'Mga Salik ng Panganib'),
                                        riskFactorsValue.isNotEmpty
                                            ? riskFactorsValue
                                            : _notInputted()),
                                    MapEntry(
                                        _t('TD Vaccine', 'Bakunang TD'),
                                        _formatInputValue(
                                            record['td_vaccine_dose'])),
                                    MapEntry(_t('Edema', 'Pamamaga'),
                                        _formatInputValue(record['edema'])),
                                    MapEntry(_t('Remarks', 'Mga Tala'),
                                        _formatInputValue(record['remarks'])),
                                    MapEntry(
                                        _t('Next Schedule',
                                            'Susunod na Schedule'),
                                        record['next_schedule'] == null
                                            ? _notInputted()
                                            : _formatDate(
                                                record['next_schedule'])),
                                  ],
                                  aiAnalysis: aiAnalysis,
                                  useStructuredAiInsights: false,
                                  riskLevel: riskLevel,
                                  riskFactors: riskFactors,
                                  weightGainEval: (record['weight_gain']
                                                  as List?)
                                              ?.isNotEmpty ==
                                          true
                                      ? (record['weight_gain'] as List).first
                                          as Map<String, dynamic>
                                      : null,
                                );
                              } else if (isUltrasound) {
                                final imageUrls =
                                    _parseImageUrls(record['ultrasound_image']);
                                final split = _splitRemarksAndAi(
                                    record['remarks']?.toString());
                                String? aiAnalysis;
                                final ultrasoundId = record['ultrasound_id'];
                                if (ultrasoundId is int) {
                                  aiAnalysis = await MotherProfileService
                                      .getUltrasoundAIAnalysis(
                                    ultrasoundId,
                                  );
                                }

                                String finalRemarks = split.cleanRemarks;
                                if (aiAnalysis != null &&
                                    aiAnalysis.trim() == finalRemarks.trim()) {
                                  finalRemarks = '';
                                }

                                aiAnalysis = (aiAnalysis != null && aiAnalysis.trim().isNotEmpty) ? aiAnalysis.trim() : split.extractedAi;
                                if (mounted && !hasClosedLoading) {
                                  Navigator.of(context, rootNavigator: true)
                                      .pop();
                                  hasClosedLoading = true;
                                }
                                final addedDate = _formatDateTime(
                                    record['created_at'] ??
                                        record['createdAt']);
                                _showRecordDetails(
                                  title: _t('Ultrasound', 'Ultrasound'),
                                  subtitle:
                                      '${_t('Added on', 'Inayos noong')} $addedDate',
                                  icon: Icons.monitor_heart,
                                  imageUrls:
                                      imageUrls.isNotEmpty ? imageUrls : null,
                                  rows: [
                                    MapEntry(
                                        _t('Record Added', 'Pinasok Noong'),
                                        addedDate),
                                    MapEntry(
                                        _t('Ultrasound Date',
                                            'Petsa ng Ultrasound'),
                                        _formatDate(record['ultrasound_date'])),
                                    MapEntry(
                                        _t('Location', 'Lokasyon'),
                                        _formatValue(
                                            record['ultrasound_location'])),
                                    MapEntry(
                                        _t('Full Name', 'Buong Pangalan'),
                                        _formatValue(
                                            record['health_worker_name'])),
                                    MapEntry(
                                        _t('Institution', 'Institusyon'),
                                        _formatValue(record[
                                            'health_worker_institution'])),
                                    MapEntry(
                                        _t('Profession', 'Propesyon'),
                                        _formatValue(record[
                                            'health_worker_profession'])),
                                    MapEntry(_t('Remarks', 'Mga Tala'),
                                        _formatValue(finalRemarks)),
                                  ],
                                  aiAnalysis: aiAnalysis,
                                  useStructuredAiInsights: aiAnalysis != null &&
                                      aiAnalysis.isNotEmpty,
                                  ultrasoundClassification: record['monitoring_classification']?.toString(),
                                );
                              } else if (isLabTest) {
                                final imageUrls =
                                    _parseImageUrls(record['lab_test_image']);
                                final split = _splitRemarksAndAi(
                                    record['remarks']?.toString());

                                String? aiAnalysis;
                                final labTestId = record['lab_test_id'];
                                if (labTestId is int) {
                                  aiAnalysis = await MotherProfileService
                                      .getLabTestAIAnalysis(
                                    labTestId,
                                  );
                                }

                                aiAnalysis = (aiAnalysis != null &&
                                        aiAnalysis.trim().isNotEmpty)
                                    ? aiAnalysis.trim()
                                    : split.extractedAi;
                                if (mounted && !hasClosedLoading) {
                                  Navigator.of(context, rootNavigator: true)
                                      .pop();
                                  hasClosedLoading = true;
                                }
                                final addedDate = _formatDateTime(
                                    record['created_at'] ??
                                        record['createdAt']);
                                _showRecordDetails(
                                  title: record['lab_test_type'] ??
                                      _t('Lab Test', 'Lab Test'),
                                  subtitle:
                                      '${_t('Added on', 'Inayos noong')} $addedDate',
                                  icon: Icons.science,
                                  imageUrls:
                                      imageUrls.isNotEmpty ? imageUrls : null,
                                  rows: [
                                    MapEntry(
                                        _t('Record Added', 'Pinasok Noong'),
                                        addedDate),
                                    MapEntry(
                                        _t('Lab Test Type', 'Uri ng Lab Test'),
                                        _formatValue(record['lab_test_type'])),
                                    MapEntry(
                                        _t('Lab Test Date',
                                            'Petsa ng Lab Test'),
                                        _formatDate(record['lab_test_date'])),
                                    MapEntry(
                                        _t('Full Name', 'Buong Pangalan'),
                                        _formatValue(
                                            record['health_worker_name'])),
                                    MapEntry(
                                        _t('Institution', 'Institusyon'),
                                        _formatValue(record[
                                            'health_worker_institution'])),
                                    MapEntry(
                                        _t('Profession', 'Propesyon'),
                                        _formatValue(record[
                                            'health_worker_profession'])),
                                    MapEntry(_t('Notes', 'Mga Tala'),
                                        _formatValue(split.cleanRemarks)),
                                  ],
                                  aiAnalysis: aiAnalysis,
                                  useStructuredAiInsights: aiAnalysis != null &&
                                      aiAnalysis.isNotEmpty,
                                );
                              } else if (isMaternalVital) {
                                if (mounted && !hasClosedLoading) {
                                  Navigator.of(context, rootNavigator: true)
                                      .pop();
                                  hasClosedLoading = true;
                                }
                                final recDate = _formatDateTime(record['recorded_at']);
                                _showRecordDetails(
                                  title: _t('Self-logged Vitals', 'Sariling Vitals'),
                                  subtitle: '${_t('Recorded on', 'Itinala noong')} $recDate',
                                  icon: Icons.monitor_weight_outlined,
                                  rows: [
                                    MapEntry(_t('Date', 'Petsa'), recDate),
                                    MapEntry(
                                      _t('Age of Gestation', 'Edad ng Pagbubuntis'),
                                      _formatInputValue(record['age_of_gestation'] != null ? '${record['age_of_gestation']} wks' : null),
                                    ),
                                    MapEntry(
                                      _t('Weight (kg)', 'Timbang (kg)'),
                                      _formatInputValue(record['weight_kg'] != null ? '${record['weight_kg']} kg' : null),
                                    ),
                                    MapEntry(
                                      _t('Height (cm)', 'Taas (cm)'),
                                      _formatInputValue(record['height_cm'] != null ? '${record['height_cm']} cm' : null),
                                    ),
                                    MapEntry(
                                      _t('Notes', 'Mga Tala'),
                                      _formatInputValue(record['notes']),
                                    ),
                                  ],
                                );
                              }
                            } finally {
                              if (mounted && !hasClosedLoading) {
                                Navigator.of(context, rootNavigator: true)
                                    .pop(); // dismiss dialog
                              }
                              if (mounted) {
                                setState(() => _isOpeningRecord = false);
                              }
                            }
                          },
                        ),
                      ),
                    );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStatisticsTab() {
    final totalCheckups = _checkups.length;
    final totalUltrasounds = _ultrasounds.length;
    final totalLabTests = _labTests.length;
    final totalRecords = totalCheckups + totalUltrasounds + totalLabTests;

    final allRecords = _getFilteredAndSortedRecords();
    final latestRecord = allRecords.isNotEmpty ? allRecords.first : null;

    final now = DateTime.now();
    final last6Months =
        List.generate(6, (i) => DateTime(now.year, now.month - i, 1))
            .reversed
            .toList();

    final Map<String, int> recordsByMonth = {};
    for (final month in last6Months) {
      recordsByMonth[DateFormat('MMM yyyy').format(month)] = 0;
    }

    for (final record in allRecords) {
      final dateStr = record['record_date'];
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      final monthKey = DateFormat('MMM yyyy').format(date);
      if (recordsByMonth.containsKey(monthKey)) {
        recordsByMonth[monthKey] = (recordsByMonth[monthKey] ?? 0) + 1;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  _t('Total Records', 'Kabuuang Records'),
                  totalRecords.toString(),
                  Icons.folder,
                  AppColors.brandPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  _t('Checkups', 'Checkups'),
                  totalCheckups.toString(),
                  Icons.medical_services,
                  AppColors.brandPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  _t('Ultrasounds', 'Ultrasounds'),
                  totalUltrasounds.toString(),
                  Icons.photo,
                  AppColors.brandAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  _t('Lab Tests', 'Lab Tests'),
                  totalLabTests.toString(),
                  Icons.science,
                  AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (latestRecord != null) ...[
            Text(
              _t('LATEST RECORD', 'PINAKABAGONG RECORD'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (latestRecord['record_type'] == 'ultrasound'
                              ? AppColors.brandAccent
                              : latestRecord['record_type'] == 'checkup'
                                  ? AppColors.brandPrimary
                                  : AppColors.warning)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      latestRecord['record_type'] == 'ultrasound'
                          ? Icons.photo
                          : latestRecord['record_type'] == 'checkup'
                              ? Icons.medical_services
                              : Icons.science,
                      color: latestRecord['record_type'] == 'ultrasound'
                          ? AppColors.brandAccent
                          : latestRecord['record_type'] == 'checkup'
                              ? AppColors.brandPrimary
                              : AppColors.warning,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          latestRecord['record_type'] == 'checkup'
                              ? _t('Prenatal Checkup', 'Prenatal Checkup')
                              : latestRecord['record_type'] == 'ultrasound'
                                  ? _t('Ultrasound', 'Ultrasound')
                                  : (latestRecord['lab_test_type'] ??
                                      _t('Lab Test', 'Lab Test')),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latestRecord['record_type'] == 'checkup'
                              ? _formatDateTime(latestRecord['record_date'])
                              : _formatDate(latestRecord['record_date']),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            _t('RECORDS BY MONTH', 'RECORDS BAWAT BUWAN'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          ...recordsByMonth.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.bgSecondary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        Container(
                          height: 30,
                          width: (entry.value / 10) *
                              MediaQuery.of(context).size.width *
                              0.5,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.brandPrimary,
                                AppColors.brandSecondary,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                entry.value.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('QUICK ACTIONS', 'MABILIS NA AKSYON'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        _t('View Checkups', 'Tingnan ang Checkups'),
                        Icons.medical_services,
                        AppColors.brandPrimary,
                        () {
                          setState(() {
                            _selectedFilter = 'checkup';
                            _tabController.animateTo(0);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionButton(
                        _t('View Lab Tests', 'Tingnan ang Lab Tests'),
                        Icons.science,
                        AppColors.warning,
                        () {
                          setState(() {
                            _selectedFilter = 'labtest';
                            _tabController.animateTo(0);
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        _t('View Ultrasounds', 'Tingnan ang Ultrasounds'),
                        Icons.photo,
                        AppColors.brandAccent,
                        () {
                          setState(() {
                            _selectedFilter = 'ultrasound';
                            _tabController.animateTo(0);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionButton(
                        _t('View Self-logged Vitals', 'Tingnan ang Sariling Vitals'),
                        Icons.monitor_weight_outlined,
                        Colors.teal,
                        () {
                          setState(() {
                            _selectedFilter = 'maternal_vital';
                            _tabController.animateTo(0);
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}


