import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/baby_growth_milestone.dart';
import 'package:inaagapay_flutter_v2/models/milestone_template.dart';
import 'package:inaagapay_flutter_v2/models/pregnancy_growth_stage.dart';
import 'package:inaagapay_flutter_v2/screens/baby_book_mockup_page.dart';
import 'package:inaagapay_flutter_v2/services/baby_book_repository.dart';

/// Covers the page's behaviour once a real mother is attached.
///
/// The case that matters most is the empty one. A mother between pregnancies
/// must not be shown the sample pregnancy — being told she is 20 weeks along
/// and due in December, when she is not pregnant, is the kind of wrong that
/// upsets someone rather than merely confusing them.
class _FakeRepository extends BabyBookRepository {
  const _FakeRepository({this.pregnancy, this.milestones = const []});

  final CurrentPregnancyState? pregnancy;
  final List<BabyGrowthMilestone> milestones;

  @override
  Future<CurrentPregnancyState?> loadCurrentPregnancy(int motherId) async =>
      pregnancy;

  @override
  Future<List<BabyGrowthMilestone>> loadPrenatalMilestones({
    required int pregnancyId,
    required int currentWeek,
    MilestoneOwner? owner,
  }) async =>
      milestones;
}

void main() {
  Widget page({int? motherId, BabyBookRepository? repository}) => MaterialApp(
        home: BabyBookMockupPage(motherId: motherId, repository: repository),
      );

  testWidgets('a mother with no ongoing pregnancy sees a notice, not samples',
      (tester) async {
    await tester.pumpWidget(page(
      motherId: 42,
      repository: const _FakeRepository(pregnancy: null),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No pregnancy recorded yet'), findsOneWidget);

    // The sample pregnancy must not leak through.
    expect(find.text('20 Weeks Pregnant'), findsNothing);
    expect(find.textContaining('Weeks Pregnant'), findsNothing);
  });

  testWidgets('a real pregnancy renders its own week, not the sample week',
      (tester) async {
    final pregnancy = CurrentPregnancyState(
      pregnancyId: 7,
      currentWeek: 30,
      currentMonth: 7,
      estimatedDueDate: DateTime(2026, 11, 2),
      numberOfBabies: 1,
      pregnancyProgress: 0.75,
      trimester: 'Third Trimester',
    );

    await tester.pumpWidget(page(
      motherId: 42,
      repository: _FakeRepository(pregnancy: pregnancy),
    ));
    await tester.pumpAndSettle();

    expect(find.text('30 Weeks Pregnant'), findsOneWidget);
    expect(find.text('20 Weeks Pregnant'), findsNothing);
    expect(find.text('No pregnancy recorded yet'), findsNothing);
  });

  testWidgets('preview mode still renders the sample pregnancy', (tester) async {
    // No motherId: the /baby-book route and the existing widget tests rely on
    // this path, and it must not touch the network.
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(find.text('20 Weeks Pregnant'), findsOneWidget);
    expect(find.text('No pregnancy recorded yet'), findsNothing);
  });

  testWidgets('milestones from the repository reach the timeline',
      (tester) async {
    final pregnancy = CurrentPregnancyState(
      pregnancyId: 9,
      currentWeek: 20,
      currentMonth: 5,
      estimatedDueDate: DateTime(2026, 12, 8),
      numberOfBabies: 1,
      pregnancyProgress: 0.5,
      trimester: 'Second Trimester',
    );

    await tester.pumpWidget(page(
      motherId: 42,
      repository: _FakeRepository(
        pregnancy: pregnancy,
        milestones: const [
          BabyGrowthMilestone(
            id: 'anatomy-scan',
            title: 'Anatomy scan recorded',
            description: 'Recorded by the healthcare team.',
            expectedStartWeek: 18,
            expectedEndWeek: 22,
            category: BabyGrowthMilestoneCategory.ultrasound,
            status: BabyGrowthMilestoneStatus.current,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('Anatomy scan recorded', skipOffstage: false),
      findsWidgets,
    );
    // The Dart sample list is not consulted once a mother is attached.
    expect(
      find.text('Pregnancy confirmed', skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('a twin pregnancy reaches the journey heading', (tester) async {
    final twins = CurrentPregnancyState(
      pregnancyId: 8,
      currentWeek: 20,
      currentMonth: 5,
      estimatedDueDate: DateTime(2026, 12, 8),
      numberOfBabies: 2,
      pregnancyProgress: 0.5,
      trimester: 'Second Trimester',
    );

    await tester.pumpWidget(page(
      motherId: 42,
      repository: _FakeRepository(pregnancy: twins),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Your Babies’ Growth Journey'), findsOneWidget);
  });
}
