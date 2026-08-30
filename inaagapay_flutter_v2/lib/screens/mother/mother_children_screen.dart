// lib/screens/mother/mother_children_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/language_service.dart';
import '../../models/child_model.dart';
import 'child_baby_book_page.dart';
import 'mother_child_stack.dart';

class MotherChildrenScreen extends StatefulWidget {
  const MotherChildrenScreen({super.key});

  @override
  State<MotherChildrenScreen> createState() => _MotherChildrenScreenState();
}

class _MotherChildrenScreenState extends State<MotherChildrenScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<ChildModel> _children = [];
  List<ChildModel> _filteredChildren = [];
  bool _loading = true;
  String? _errorMessage;
  int? _motherId;

  @override
  void initState() {
    super.initState();
    _loadMotherId();
    _searchController.addListener(_filterChildren);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMotherId() async {
    try {
      _motherId = await AuthStorage.getMotherId();
      if (_motherId == null) {
        throw Exception('Mother ID not found');
      }
      // The pregnancy lookup that fed the Expecting card went with it. This
      // screen is her registered children; the pregnancy has its own book.
      await _fetchChildren();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchChildren() async {
    if (_motherId == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final response =
          await Supabase.instance.client.from('children').select('''
            *,
            birth_details (
              birthdate,
              birth_weight,
              birth_length,
              birthplace_city_municipality,
              birthplace_province
            )
          ''').eq('mother_id', _motherId!).order('added_at', ascending: false);

      final List<dynamic> data = response;

      final children = data.map((json) {
        final birthDetails = json['birth_details'] as Map<String, dynamic>?;
        return ChildModel(
          childId: json['child_id'] as int,
          motherId: json['mother_id'] as int,
          firstName: json['first_name'] as String? ?? '',
          middleName: json['middle_name'] as String?,
          lastName: json['last_name'] as String? ?? '',
          extensionName: json['extension_name'] as String?,
          sex: json['sex'] as String? ?? 'male',
          addedAt: DateTime.parse(json['added_at']),
          birthdate: birthDetails != null && birthDetails['birthdate'] != null
              ? DateTime.parse(birthDetails['birthdate'])
              : null,
          birthWeight: (birthDetails?['birth_weight'] as num?)?.toDouble(),
          birthLength: (birthDetails?['birth_length'] as num?)?.toDouble(),
          birthplaceCity:
              birthDetails?['birthplace_city_municipality'] as String?,
          birthplaceProvince: birthDetails?['birthplace_province'] as String?,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _children = children;
          _filteredChildren = children;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _filterChildren() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredChildren = List.from(_children);
      });
    } else {
      setState(() {
        _filteredChildren = _children.where((child) {
          return child.fullName.toLowerCase().contains(query);
        }).toList();
      });
    }
  }

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  String _localizedAge(ChildModel child) {
    final birthdate = child.birthdate;
    if (birthdate == null) {
      return _t('Age unknown', 'Hindi alam ang edad');
    }

    final now = DateTime.now();
    int years = now.year - birthdate.year;
    int months = now.month - birthdate.month;
    int days = now.day - birthdate.day;

    if (days < 0) {
      months -= 1;
      final prevMonthDate = DateTime(now.year, now.month, 0);
      days += prevMonthDate.day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }

    if (LanguageService.isFilipino) {
      if (years > 0) {
        final monthPart = months > 0 ? ' at $months buwan' : '';
        return '$years taon$monthPart gulang';
      } else if (months > 0) {
        final weeks = days ~/ 7;
        final weekPart = weeks > 0 ? ' at $weeks linggo' : '';
        return '$months buwan$weekPart gulang';
      } else {
        if (days >= 7) {
          final weeks = days ~/ 7;
          final remainingDays = days % 7;
          final dayPart = remainingDays > 0 ? ' at $remainingDays araw' : '';
          return '$weeks linggo$dayPart gulang';
        } else if (days > 0) {
          return '$days araw gulang';
        } else {
          return 'Bagong Silang';
        }
      }
    }

    return child.ageText;
  }

  /// Whether the free-vaccine-schedule shortcut appears on this screen.
  ///
  /// Off at the mother's request. Nothing behind it was removed: the poster
  /// page, its route and its data all still exist.
  static const bool _showVaccinePosterRow = false;

  void _openBabyBook(ChildModel child) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChildBabyBookPage(
          childId: child.childId,
          childName: child.fullName,
          birthdate: child.birthdate,
        ),
      ),
    );
  }

  void _openChildProfile(ChildModel child) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MotherChildStack(
          childId: child.childId,
          childName: child.fullName,
          childAge: _localizedAge(child),
          childGender: child.sex,
        ),
      ),
    ).then((_) => _fetchChildren());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Stats Card - Pink background with baby image
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              // The midwife's Children banner, exactly: a soft brand gradient
              // behind a hairline border, brand-pink text, same baby artwork.
              //
              // This was a saturated `pinkbg.png` photograph with white text on
              // top — the only full-bleed image used as a background anywhere
              // in her app, and loud enough that it outweighed the children
              // listed beneath it. A banner naming a count should sit behind
              // the names, not in front of them.
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.brandPrimary.withValues(alpha: 0.08),
                    AppColors.brandPrimary.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.brandPrimary.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    bottom: 0,
                    top: 0,
                    child: Padding(
                      padding: const EdgeInsets.only(
                          right: 16.0, top: 4.0, bottom: 4.0),
                      child: Image.asset(
                        'assets/images/baby.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 0,
                    bottom: 0,
                    right: 110,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('My Children', 'Aking mga Anak'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brandText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            'Track their growth, baby book, and health records',
                            'Subaybayan ang paglaki, baby book, at talaan ng kalusugan',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                            color: AppColors.brandText.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Children List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchChildren,
                color: AppColors.brandPrimary,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandPrimary,
                        ),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: AppColors.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _fetchChildren,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brandPrimary,
                                  ),
                                  child: Text(_t('Retry', 'Subukan Muli')),
                                ),
                              ],
                            ),
                          )
                        // The empty state used to be suppressed while a
                        // pregnancy was in progress, because the Expecting
                        // card filled the list on its own. With that card
                        // gone, a mother expecting her first would have met an
                        // empty screen with nothing on it at all.
                        : _filteredChildren.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.child_care_outlined,
                                      size: 64,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _t('No children found',
                                          'Walang anak na nahanap'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _t(
                                        'Children will appear here once registered by your midwife',
                                        'Lalabas dito ang mga anak kapag nairehistro na ng iyong midwife',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                children: [
                                  // The "Your baby — 11 weeks — On the way"
                                  // card stood here.
                                  //
                                  // The Mother and Baby Book now opens on a
                                  // cover carrying the same week, and Home
                                  // leads straight to it, so this was a third
                                  // door to one page — and the only one that
                                  // put an unborn baby in a list of children
                                  // she can tap into records for.
                                  //
                                  // This page is her registered children.
                                  for (final child in _filteredChildren) ...[
                                    _ChildCard(
                                      child: child,
                                      age: _localizedAge(child),
                                      onTap: () => _openChildProfile(child),
                                      onOpenBabyBook: () =>
                                          _openBabyBook(child),
                                    ),
                                    const SizedBox(height: 14),
                                  ],

                                  // Hidden for now, not deleted. The poster
                                  // page and its `/immunization-poster` route
                                  // are untouched — flip
                                  // [_showVaccinePosterRow] to bring the entry
                                  // point back.
                                  if (_showVaccinePosterRow) ...[
                                    const SizedBox(height: 4),
                                    _VaccinePosterRow(
                                      onTap: () => Navigator.pushNamed(
                                          context, '/immunization-poster'),
                                    ),
                                  ],
                                ],
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
}

/// The baby on the way, shown above her born children.
///
/// Built to the rural-mother rules: an illustration carries the meaning, the
/// heading is three words, and the only number is the week — large enough to
/// read at arm's length in poor light. No clinical vocabulary.

/// Link to the BHC vaccine poster schedule.
///
/// Was on the mother's Home tab, among cards about her pregnancy. It is about
/// childhood immunisation, so it sits with her children instead — and Home is
/// shorter for it.
class _VaccinePosterRow extends StatelessWidget {
  const _VaccinePosterRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.brandPrimary.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign_rounded,
                  color: AppColors.brandPrimary, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LanguageService.translate(
                        'Free vaccine schedule', 'Iskedyul ng libreng bakuna'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    LanguageService.translate('At your health center',
                        'Sa inyong health center'),
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 15, color: AppColors.brandPrimary),
          ],
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final ChildModel child;
  final String age;
  final VoidCallback onTap;
  final VoidCallback onOpenBabyBook;

  const _ChildCard({
    required this.child,
    required this.age,
    required this.onTap,
    required this.onOpenBabyBook,
  });

  String get fullName => '${child.firstName} ${child.lastName}'.trim();

  String get _initials {
    final firstInitial =
        child.firstName.isNotEmpty ? child.firstName[0].toUpperCase() : '';
    final lastInitial =
        child.lastName.isNotEmpty ? child.lastName[0].toUpperCase() : '';
    if (firstInitial.isNotEmpty && lastInitial.isNotEmpty) {
      return '$firstInitial$lastInitial';
    }
    return firstInitial.isNotEmpty ? firstInitial : 'C';
  }

  String get _formattedBirthdate {
    if (child.birthdate == null) return '';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[child.birthdate!.month - 1]} ${child.birthdate!.day}, ${child.birthdate!.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.brandPrimary.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Child Avatar Circle
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _initials,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Child Name & Age
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        age,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_formattedBirthdate.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.cake_outlined,
                    size: 16,
                    color: AppColors.brandPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Born on $_formattedBirthdate',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5A5A5A),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.borderPrimary),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenBabyBook,
                    icon: const Icon(Icons.auto_stories_rounded, size: 17),
                    label: const Text('Baby Book'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandPrimary,
                      side: BorderSide(
                        color: AppColors.brandPrimary.withValues(alpha: 0.35),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                    label: const Text('View Info'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
