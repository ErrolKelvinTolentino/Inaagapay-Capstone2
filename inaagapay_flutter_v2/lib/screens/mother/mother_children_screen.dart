// lib/screens/mother/mother_children_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_input_field.dart';
import '../../services/auth_storage.dart';
import '../../services/language_service.dart';
import '../../models/child_model.dart';
import '../../models/pregnancy_growth_stage.dart';
import '../../services/baby_book_repository.dart';
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

  /// The pregnancy in progress, if any.
  ///
  /// An unborn baby belongs in the answer to "who are my children", and his
  /// story starts before he has a row in `children` — a heartbeat heard, a
  /// first kick. The Expecting card is where that story lives until birth,
  /// and at delivery it simply becomes the child (or, for twins, two).
  CurrentPregnancyState? _expecting;

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
      _expecting =
          await const BabyBookRepository().loadCurrentPregnancy(_motherId!);
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

  String _childrenCountLabel() {
    final count = _filteredChildren.length;
    if (LanguageService.isFilipino) {
      return '$count ${count == 1 ? 'Anak' : 'Mga Anak'}!';
    }
    return '$count Beautiful ${count == 1 ? 'Child' : 'Children'}!';
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
              height: 110,
              decoration: BoxDecoration(
                image: const DecorationImage(
                  image: AssetImage('assets/images/pinkbg.png'),
                  fit: BoxFit.cover,
                ),
                borderRadius: BorderRadius.circular(20),
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('You have', 'Mayroon kang'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _childrenCountLabel(),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppInputField(
                hintText: _t('Search child by name',
                    'Hanapin ang pangalan ng anak'),
                controller: _searchController,
                leadingIcon: Icons.search,
              ),
            ),

            const SizedBox(height: 16),

            // Helper Text
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Text(
                _t('Tap a child to view health records',
                    'Pindutin ang anak para makita ang health records'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const SizedBox(height: 8),

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
                        : (_filteredChildren.isEmpty && _expecting == null)
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
                                  // The unborn baby comes first: he is the
                                  // one she is thinking about today.
                                  if (_expecting != null) ...[
                                    _ExpectingCard(
                                      pregnancy: _expecting!,
                                      onTap: () => Navigator.pushNamed(
                                          context, '/baby-book'),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  for (final child in _filteredChildren) ...[
                                    _ChildCard(
                                      firstName: child.firstName,
                                      lastName: child.lastName,
                                      age: _localizedAge(child),
                                      onTap: () => _openChildProfile(child),
                                    ),
                                    const SizedBox(height: 12),
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
class _ExpectingCard extends StatelessWidget {
  const _ExpectingCard({required this.pregnancy, required this.onTap});

  final CurrentPregnancyState pregnancy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final expectingMany = pregnancy.isMultiplePregnancy;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        // Deliberately warmer than a child card, so the difference is visible
        // before any word is read.
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF1F7), Color(0xFFFFE4EF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: AppColors.brandPrimary.withValues(alpha: 0.25)),
        ),
        child: Padding(
          // 48dp minimum touch target, assuming a thumb.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.brandPrimary.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.pregnant_woman_rounded,
                    color: AppColors.brandPrimary, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expectingMany
                          ? LanguageService.translate('Your babies', 'Ang iyong mga baby')
                          : LanguageService.translate('Your baby', 'Ang iyong baby'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      LanguageService.translate('${pregnancy.currentWeek} weeks',
                          '${pregnancy.currentWeek} na linggo'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Status by shape and word, never colour alone.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite_rounded,
                              size: 11, color: AppColors.brandPrimary),
                          const SizedBox(width: 4),
                          Text(
                            LanguageService.translate('On the way', 'Paparating na'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: AppColors.brandPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final String firstName;
  final String lastName;
  final String age;
  final VoidCallback onTap;

  const _ChildCard({
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.onTap,
  });

  String get fullName => '$firstName $lastName'.trim();

  String get _initials {
    final firstInitial = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final lastInitial = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    if (firstInitial.isNotEmpty && lastInitial.isNotEmpty) {
      return '$firstInitial$lastInitial';
    }
    return firstInitial.isNotEmpty ? firstInitial : 'C';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
              child: Row(
                children: [
                  // Avatar - Pink background with pink text initials (matching mother list)
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _initials,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Child Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          age,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Arrow
                  const Icon(
                    Icons.chevron_right,
                    size: 24,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
