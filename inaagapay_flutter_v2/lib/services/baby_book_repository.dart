import 'package:flutter/foundation.dart';

import '../data/pregnancy_growth_data.dart';
import '../models/baby_growth_milestone.dart';
import '../models/baby_memory.dart';
import '../models/milestone_template.dart';
import '../models/pregnancy_growth_stage.dart';
import 'supabase_service.dart';

/// Reads and writes for the Baby Book.
///
/// Backs `baby_book_milestones`, `baby_memories` and `milestone_templates`
/// (migrations `20260808_baby_book_foundation` and
/// `20260808_baby_book_prenatal_templates`).
///
/// Two rules are worth stating because they are easy to break later:
///
/// 1. **A milestone's status is computed, never stored.** Whether something
///    is upcoming, current or completed depends on today's date. Persisting
///    it would repeat the immunization defect fixed in `20260807`, where an
///    "On Time" badge was a hardcoded literal and so called every dose
///    timely — including one given ten months late.
///
/// 2. **Prenatal entries attach to a pregnancy, postnatal ones to a child.**
///    Twins share one gestation but develop separately. The database
///    enforces this with `baby_book_milestones_scope_check`; this class does
///    not work around it.
class BabyBookRepository {
  const BabyBookRepository();

  static const int _fullTermWeeks = 40;

  /// The mother's ongoing pregnancy, shaped for the Baby Book header.
  ///
  /// Returns null when she has no ongoing pregnancy — a mother between
  /// pregnancies is a normal state, not an error, and the caller should fall
  /// back rather than show a broken header.
  Future<CurrentPregnancyState?> loadCurrentPregnancy(int motherId) async {
    try {
      final row = await SupabaseService.client
          .from('pregnancies')
          .select(
              'pregnancy_id, last_menstrual_period, expected_date_of_delivery, fetal_count')
          .eq('mother_id', motherId)
          .eq('status', 'ongoing')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) return null;
      return currentPregnancyFromRow(row);
    } catch (e) {
      if (kDebugMode) debugPrint('loadCurrentPregnancy failed: $e');
      return null;
    }
  }

  /// Builds the header state from a `pregnancies` row.
  ///
  /// Exposed separately from the query so it can be exercised without a
  /// database, and reused by callers that already hold the row.
  @visibleForTesting
  static CurrentPregnancyState? currentPregnancyFromRow(
      Map<String, dynamic> row) {
    final lmp = _parseDate(row['last_menstrual_period']);
    final edd = _parseDate(row['expected_date_of_delivery']);

    // Either date pins the timeline: EDD is defined as LMP + 280 days, so one
    // can always be recovered from the other. With neither, there is no
    // gestational age to show and guessing one would be worse than nothing.
    final effectiveLmp = lmp ?? edd?.subtract(const Duration(days: 280));
    if (effectiveLmp == null) return null;

    final effectiveEdd = edd ?? effectiveLmp.add(const Duration(days: 280));

    final currentWeek = gestationalWeek(effectiveLmp);
    final stage = stageForWeek(currentWeek);

    // fetal_count is a varchar holding a number; the rest of the app parses it
    // the same way and falls back to a singleton (add_prenatal_checkup_screen).
    final fetalCount = int.tryParse(row['fetal_count']?.toString() ?? '') ?? 1;

    return CurrentPregnancyState(
      pregnancyId: (row['pregnancy_id'] as num?)?.toInt(),
      currentWeek: currentWeek,
      currentMonth: stage?.month ?? 1,
      estimatedDueDate: effectiveEdd,
      numberOfBabies: fetalCount,
      pregnancyProgress: (currentWeek / _fullTermWeeks).clamp(0.0, 1.0),
      trimester: stage?.trimester ?? 'First Trimester',
    );
  }

  /// Completed weeks of gestation as of [asOf], counted from [lmp].
  ///
  /// Clamped to 0–42. Beyond 42 weeks is post-term and no longer a number the
  /// Baby Book should be rendering on a timeline built for 40.
  @visibleForTesting
  static int gestationalWeek(DateTime lmp, {DateTime? asOf}) {
    final days = (asOf ?? DateTime.now()).difference(lmp).inDays;
    return (days ~/ 7).clamp(0, 42);
  }

  /// The pregnancy stage containing [week].
  ///
  /// Read from `pregnancyGrowthStages` rather than a second month/week table.
  /// The mapping exists once; a copy here would be free to drift from what
  /// the timeline actually draws — which is also why this is public: the
  /// My Pregnancy page needs the same week-to-month answer, and a second
  /// implementation there would be free to disagree with this one.
  static PregnancyGrowthStage? stageForWeek(int week) {
    for (final stage in pregnancyGrowthStages) {
      if (week >= stage.startWeek && week <= stage.endWeek) return stage;
    }
    // Before week 1, or past week 40: clamp to the nearest end of the timeline.
    if (pregnancyGrowthStages.isEmpty) return null;
    return week < pregnancyGrowthStages.first.startWeek
        ? pregnancyGrowthStages.first
        : pregnancyGrowthStages.last;
  }

  /// The prenatal milestone catalogue, in display order.
  ///
  /// [owner] selects which book's entries to return. The Baby Book asks for
  /// the baby's — his heartbeat, his first kick — and leaves the mother's
  /// checkups and birth plan to the Mother Book. Omit it to get both.
  Future<List<MilestoneTemplate>> loadPrenatalTemplates({
    MilestoneOwner? owner,
  }) async {
    try {
      var query = SupabaseService.client
          .from('milestone_templates')
          .select()
          .eq('phase', MilestonePhase.prenatal.dbValue)
          .eq('is_active', true);

      if (owner != null) query = query.eq('owner', owner.dbValue);

      final rows = await query.order('sort_order');

      return (rows as List)
          .map((r) => MilestoneTemplate.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('loadPrenatalTemplates failed: $e');
      return const [];
    }
  }

  /// The postnatal milestone catalogue — the DOH ECCD set, birth to five
  /// years, seeded by `20260809_postnatal_milestones_doh`.
  ///
  /// [upToAgeMonths] limits the list to what a child of that age could
  /// plausibly have reached. A newborn's book should not open on "hops on one
  /// foot"; passing her age keeps the page about her.
  Future<List<MilestoneTemplate>> loadPostnatalTemplates({
    int? upToAgeMonths,
  }) async {
    try {
      var query = SupabaseService.client
          .from('milestone_templates')
          .select()
          .eq('phase', MilestonePhase.postnatal.dbValue)
          .eq('is_active', true);

      if (upToAgeMonths != null) {
        // One checkpoint beyond her age, so the next thing to look forward to
        // is visible. A Baby Book is partly anticipation.
        query = query.lte('age_months_target', upToAgeMonths + 6);
      }

      final rows = await query.order('sort_order');

      return (rows as List)
          .map((r) => MilestoneTemplate.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('loadPostnatalTemplates failed: $e');
      return const [];
    }
  }

  /// The prenatal milestones for [pregnancyId], catalogue merged with what
  /// has actually been recorded.
  ///
  /// Every catalogue entry appears, recorded or not — a Baby Book that hid
  /// unrecorded milestones would show a mother only what she has already
  /// done, which is the opposite of a timeline. Milestones she added herself
  /// are appended with `isCustom: true`.
  Future<List<BabyGrowthMilestone>> loadPrenatalMilestones({
    required int pregnancyId,
    required int currentWeek,
    MilestoneOwner? owner,
  }) async {
    try {
      final templates = await loadPrenatalTemplates(owner: owner);

      final rows = await SupabaseService.client
          .from('baby_book_milestones')
          .select(
              'entry_id, template_id, title, description, recorded_pregnancy_week, '
              'observed_on, note, recorded_by')
          .eq('pregnancy_id', pregnancyId);

      final recorded = <int, Map<String, dynamic>>{};
      final custom = <Map<String, dynamic>>[];
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final templateId = (r['template_id'] as num?)?.toInt();
        if (templateId == null) {
          custom.add(r);
        } else {
          recorded[templateId] = r;
        }
      }

      final merged = <BabyGrowthMilestone>[
        for (final t in templates)
          _fromTemplate(t, recorded[t.templateId], currentWeek),
        for (final r in custom) _fromCustomRow(r),
      ];

      return merged;
    } catch (e) {
      if (kDebugMode) debugPrint('loadPrenatalMilestones failed: $e');
      return const [];
    }
  }

  /// Completed months since [birthdate].
  ///
  /// Public rather than test-only: the child's book shows her age in its
  /// header, and a second implementation there would be free to disagree with
  /// the one deciding which milestones to show.
  static int ageInMonths(DateTime birthdate, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    var months =
        (now.year - birthdate.year) * 12 + (now.month - birthdate.month);
    if (now.day < birthdate.day) months -= 1;
    return months < 0 ? 0 : months;
  }

  /// Where a postnatal milestone stands for a child of [childAgeMonths].
  ///
  /// Mirrors the prenatal rule, on the age axis instead of the gestational
  /// one, and keeps its most important property: nothing is ever "missed".
  /// The DOH book frames these as what a caregiver may expect and points the
  /// parent at their health worker; telling a mother her child has failed a
  /// milestone is not this screen's job and would be wrong as often as not.
  @visibleForTesting
  static BabyGrowthMilestoneStatus postnatalStatusFor({
    required DateTime? observedOn,
    required int? targetMonths,
    required int childAgeMonths,
  }) {
    if (observedOn != null) return BabyGrowthMilestoneStatus.completed;
    if (targetMonths == null) return BabyGrowthMilestoneStatus.notRecorded;
    if (childAgeMonths < targetMonths) {
      return BabyGrowthMilestoneStatus.upcoming;
    }
    // The checkpoint is a guide, not a deadline. A window of a few months
    // around it is what "around now" honestly means for development.
    if (childAgeMonths <= targetMonths + 3) {
      return BabyGrowthMilestoneStatus.current;
    }
    return BabyGrowthMilestoneStatus.notRecorded;
  }

  /// One child's own milestones — the DOH catalogue merged with what has been
  /// recorded for them.
  Future<List<ChildMilestone>> loadChildMilestones({
    required int childId,
    required DateTime? birthdate,
  }) async {
    try {
      final ageMonths = birthdate == null ? 0 : ageInMonths(birthdate);

      final templates =
          await loadPostnatalTemplates(upToAgeMonths: ageMonths);

      final rows = await SupabaseService.client
          .from('baby_book_milestones')
          .select('entry_id, template_id, title, observed_on, note')
          .eq('child_id', childId);

      final recorded = <int, Map<String, dynamic>>{};
      final custom = <Map<String, dynamic>>[];
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final templateId = (r['template_id'] as num?)?.toInt();
        if (templateId == null) {
          custom.add(r);
        } else {
          recorded[templateId] = r;
        }
      }

      return [
        for (final t in templates)
          _childMilestone(t, recorded[t.templateId], ageMonths),
        for (final r in custom)
          ChildMilestone(
            title: r['title']?.toString() ?? 'Milestone',
            status: BabyGrowthMilestoneStatus.completed,
            observedOn: _parseDate(r['observed_on']),
            note: r['note']?.toString(),
            entryId: (r['entry_id'] as num?)?.toInt(),
          ),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('loadChildMilestones failed: $e');
      return const [];
    }
  }

  ChildMilestone _childMilestone(
    MilestoneTemplate template,
    Map<String, dynamic>? row,
    int childAgeMonths,
  ) {
    final observedOn = _parseDate(row?['observed_on']);
    return ChildMilestone(
      template: template,
      title: template.titleEn,
      observedOn: observedOn,
      note: row?['note']?.toString(),
      entryId: (row?['entry_id'] as num?)?.toInt(),
      status: postnatalStatusFor(
        observedOn: observedOn,
        targetMonths: template.ageMonthsTarget,
        childAgeMonths: childAgeMonths,
      ),
    );
  }

  /// The chapter a child inherits from the pregnancy that carried them.
  ///
  /// Read through `children.pregnancy_id` rather than copied, so twins share
  /// one set of before-birth entries instead of owning duplicates.
  Future<List<BabyGrowthMilestone>> loadChildPrenatalChapter(
      int childId) async {
    try {
      final child = await SupabaseService.client
          .from('children')
          .select('pregnancy_id')
          .eq('child_id', childId)
          .maybeSingle();

      final pregnancyId = (child?['pregnancy_id'] as num?)?.toInt();
      if (pregnancyId == null) return const [];

      // Everything is in the past by now, so the window is closed: 42 weeks
      // means no entry is left reading "upcoming" in a book about someone
      // already born.
      return loadPrenatalMilestones(
        pregnancyId: pregnancyId,
        currentWeek: 42,
        owner: MilestoneOwner.baby,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('loadChildPrenatalChapter failed: $e');
      return const [];
    }
  }

  /// Records a milestone against a child.
  Future<bool> recordChildMilestone({
    required int childId,
    String? templateKey,
    String? title,
    DateTime? observedOn,
    String? note,
    int? recordedByAccountId,
    int? photoFileId,
  }) async {
    try {
      int? templateId;
      if (templateKey != null) {
        final t = await SupabaseService.client
            .from('milestone_templates')
            .select('template_id')
            .eq('template_key', templateKey)
            .maybeSingle();
        templateId = (t?['template_id'] as num?)?.toInt();
      }

      if (templateId == null && (title == null || title.trim().isEmpty)) {
        return false;
      }

      await SupabaseService.client.from('baby_book_milestones').insert({
        'child_id': childId,
        // pregnancy_id stays unset: this is the child's side, and setting both
        // is rejected by baby_book_milestones_scope_check.
        'template_id': templateId,
        'title': title?.trim(),
        'observed_on':
            (observedOn ?? DateTime.now()).toIso8601String().split('T').first,
        'note': note,
        'recorded_by': recordedByAccountId,
        'photo_file_id': photoFileId,
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('recordChildMilestone failed: $e');
      return false;
    }
  }

  /// Removes a recorded milestone from a child's book.
  ///
  /// Recording had no counterpart at first, on the reasoning that a keepsake
  /// should not be easy to delete. That was the wrong trade: it made a mis-tap
  /// permanent, and a book you cannot correct is worse than one with a
  /// confirmable undo. The confirmation lives in the UI; this just deletes.
  Future<bool> removeChildMilestone(int entryId) async {
    try {
      await SupabaseService.client
          .from('baby_book_milestones')
          .delete()
          .eq('entry_id', entryId);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('removeChildMilestone failed: $e');
      return false;
    }
  }

  BabyGrowthMilestone _fromTemplate(
    MilestoneTemplate template,
    Map<String, dynamic>? row,
    int currentWeek,
  ) {
    final observedOn = _parseDate(row?['observed_on']);
    return BabyGrowthMilestone(
      id: template.key,
      title: template.titleEn,
      description: template.descriptionEn ?? '',
      expectedStartWeek: template.expectedStartWeek,
      expectedEndWeek: template.expectedEndWeek,
      recordedPregnancyWeek:
          (row?['recorded_pregnancy_week'] as num?)?.toInt(),
      pregnancyMonth: template.expectedStartWeek == null
          ? null
          : stageForWeek(template.expectedStartWeek!)?.month,
      completedDate: observedOn,
      category: template.prenatalCategory,
      status: statusFor(
        observedOn: observedOn,
        expectedStartWeek: template.expectedStartWeek,
        expectedEndWeek: template.expectedEndWeek,
        currentWeek: currentWeek,
      ),
      note: row?['note']?.toString(),
    );
  }

  BabyGrowthMilestone _fromCustomRow(Map<String, dynamic> row) {
    final observedOn = _parseDate(row['observed_on']);
    return BabyGrowthMilestone(
      id: 'entry-${row['entry_id']}',
      title: row['title']?.toString() ?? 'Milestone',
      description: row['description']?.toString() ?? '',
      recordedPregnancyWeek: (row['recorded_pregnancy_week'] as num?)?.toInt(),
      completedDate: observedOn,
      category: BabyGrowthMilestoneCategory.personalMemory,
      // A milestone a mother added exists because it happened. There is no
      // expected window to be early or late against.
      status: observedOn == null
          ? BabyGrowthMilestoneStatus.notRecorded
          : BabyGrowthMilestoneStatus.completed,
      note: row['note']?.toString(),
      isCustom: true,
    );
  }

  /// Where a milestone stands right now.
  ///
  /// Derived on every read. See the class note on why this is not a column.
  @visibleForTesting
  static BabyGrowthMilestoneStatus statusFor({
    required DateTime? observedOn,
    required int? expectedStartWeek,
    required int? expectedEndWeek,
    required int currentWeek,
  }) {
    if (observedOn != null) return BabyGrowthMilestoneStatus.completed;
    if (expectedStartWeek == null) return BabyGrowthMilestoneStatus.notRecorded;

    final end = expectedEndWeek ?? expectedStartWeek;
    if (currentWeek < expectedStartWeek) {
      return BabyGrowthMilestoneStatus.upcoming;
    }
    if (currentWeek <= end) return BabyGrowthMilestoneStatus.current;

    // The window has passed with nothing recorded. Deliberately *not* called
    // "missed": many of these depend on a provider documenting something, and
    // telling a mother she missed a milestone that was never hers to record
    // would be both wrong and unkind.
    return BabyGrowthMilestoneStatus.notRecorded;
  }

  /// Records a prenatal milestone against a pregnancy.
  ///
  /// One of [templateKey] or [title] must be given — the database rejects an
  /// unnamed entry via `baby_book_milestones_named_check`.
  Future<bool> recordPrenatalMilestone({
    required int pregnancyId,
    String? templateKey,
    String? title,
    String? description,
    DateTime? observedOn,
    int? recordedPregnancyWeek,
    String? note,
    int? recordedByAccountId,
    int? photoFileId,
  }) async {
    try {
      int? templateId;
      if (templateKey != null) {
        final t = await SupabaseService.client
            .from('milestone_templates')
            .select('template_id')
            .eq('template_key', templateKey)
            .maybeSingle();
        templateId = (t?['template_id'] as num?)?.toInt();
      }

      if (templateId == null && (title == null || title.trim().isEmpty)) {
        if (kDebugMode) {
          debugPrint('recordPrenatalMilestone: needs a template or a title');
        }
        return false;
      }

      await SupabaseService.client.from('baby_book_milestones').insert({
        'pregnancy_id': pregnancyId,
        // child_id is left unset: this is the prenatal side, and setting both
        // would be rejected by baby_book_milestones_scope_check.
        'template_id': templateId,
        'title': title?.trim(),
        'description': description,
        'observed_on': observedOn?.toIso8601String().split('T').first,
        'recorded_pregnancy_week': recordedPregnancyWeek,
        'note': note,
        'recorded_by': recordedByAccountId,
        'photo_file_id': photoFileId,
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('recordPrenatalMilestone failed: $e');
      return false;
    }
  }

  /// Memories for a pregnancy or a child. Exactly one id should be given.
  Future<List<BabyMemory>> loadMemories({
    int? pregnancyId,
    int? childId,
  }) async {
    if ((pregnancyId == null) == (childId == null)) {
      if (kDebugMode) {
        debugPrint('loadMemories: pass exactly one of pregnancyId / childId');
      }
      return const [];
    }

    try {
      var query = SupabaseService.client
          .from('baby_memories')
          .select('memory_id, title, caption, memory_date');

      query = pregnancyId != null
          ? query.eq('pregnancy_id', pregnancyId)
          : query.eq('child_id', childId!);

      final rows = await query.order('memory_date', ascending: false);

      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        return BabyMemory(
          id: 'memory-${r['memory_id']}',
          title: r['title']?.toString() ?? '',
          caption: r['caption']?.toString() ?? '',
          date: _parseDate(r['memory_date']) ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('loadMemories failed: $e');
      return const [];
    }
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
