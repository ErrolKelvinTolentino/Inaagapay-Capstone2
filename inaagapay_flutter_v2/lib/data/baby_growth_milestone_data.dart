import '../models/baby_growth_milestone.dart';

/// The prenatal care a pregnancy is generally expected to receive, in order.
///
/// This list replaced a mix of care events and developmental moments — "heart
/// activity documented", "baby's first movement", "entered second trimester".
/// Those are things that happen to a pregnancy, not things anyone schedules,
/// and putting them in the same list as a checkup made the list impossible to
/// act on: a mother could not tell which rows she was supposed to do something
/// about. Fetal development is covered by the growth journey above this
/// section. What is left here is only care she can actually attend.
///
/// Two rules hold for every entry.
///
/// First, no entry states whether it has happened. That sentence comes from
/// [BabyGrowthMilestone.recordGuidance], which reads the status, so it cannot
/// contradict the record. Written into `description` it would keep saying
/// "not yet recorded" after her midwife recorded it.
///
/// Second, no entry decides anything clinical. The week ranges are the usual
/// ones and are labelled as usual, not as her due dates, and every entry ends
/// by pointing at her midwife. Whether a test is appropriate for a particular
/// pregnancy is not a question this list is in a position to answer.
///
/// The week ranges and the tests named here still need an adviser's sign-off
/// against the DOH prenatal schedule before defense.
final List<BabyGrowthMilestone> babyGrowthMilestoneSampleData = [
  BabyGrowthMilestone(
    id: 'first-prenatal-checkup',
    title: 'First prenatal checkup',
    description:
        'A first prenatal checkup is recommended within the first 12 weeks of '
        'pregnancy.',
    expectedStartWeek: 1,
    expectedEndWeek: 12,
    recordedPregnancyWeek: 9,
    completedDate: DateTime(2026, 5, 4),
    category: BabyGrowthMilestoneCategory.checkup,
    status: BabyGrowthMilestoneStatus.completed,
    recordedBy: 'Midwife',
  ),
  // Four rows, not one "Early-pregnancy laboratory tests".
  //
  // Bundled together they could only ever be marked as a set, so a mother who
  // had her blood typed but no HIV screening had no way to say so — she was
  // left choosing between claiming all four and recording none. They are
  // separately ordered, separately reported and separately outstanding, so
  // they are separately markable here.
  const BabyGrowthMilestone(
    id: 'haemoglobin-test',
    title: 'Haemoglobin test',
    description:
        'A haemoglobin test checks for anaemia, which is common in pregnancy '
        'and treatable. It is commonly done during early prenatal care.',
    expectedStartWeek: 1,
    expectedEndWeek: 12,
    category: BabyGrowthMilestoneCategory.checkup,
    status: BabyGrowthMilestoneStatus.notRecorded,
  ),
  const BabyGrowthMilestone(
    id: 'blood-typing',
    title: 'Blood group and Rh typing',
    description:
        'This finds your blood type and whether you are Rh positive or '
        'negative. It is commonly done once during early prenatal care.',
    expectedStartWeek: 1,
    expectedEndWeek: 12,
    category: BabyGrowthMilestoneCategory.checkup,
    status: BabyGrowthMilestoneStatus.notRecorded,
  ),
  const BabyGrowthMilestone(
    id: 'hiv-screening',
    title: 'HIV screening',
    description:
        'HIV screening is commonly offered during early prenatal care. Your '
        'midwife can explain what the test involves and what happens next.',
    expectedStartWeek: 1,
    expectedEndWeek: 12,
    category: BabyGrowthMilestoneCategory.checkup,
    status: BabyGrowthMilestoneStatus.notRecorded,
  ),
  const BabyGrowthMilestone(
    id: 'urinalysis',
    title: 'Urinalysis',
    description:
        'A urine test checks for infection and for protein in the urine. It '
        'is commonly done during early prenatal care.',
    expectedStartWeek: 1,
    expectedEndWeek: 12,
    category: BabyGrowthMilestoneCategory.checkup,
    status: BabyGrowthMilestoneStatus.notRecorded,
  ),
  const BabyGrowthMilestone(
    id: 'ultrasound-record',
    title: 'Ultrasound record',
    description:
        'At least one ultrasound is recommended before 24 weeks of pregnancy.',
    // Weeks 1-24, not a bare deadline of 24. The window is what she can act
    // in; a milestone carrying only its deadline sorts to where it is due
    // rather than to where it becomes possible, which would file an
    // ultrasound she can have now below her third-trimester checkups.
    expectedStartWeek: 1,
    expectedEndWeek: 24,
    category: BabyGrowthMilestoneCategory.ultrasound,
    status: BabyGrowthMilestoneStatus.notRecorded,
  ),
  const BabyGrowthMilestone(
    id: 'second-trimester-checkups',
    title: 'Second-trimester prenatal checkups',
    description:
        'Prenatal checkups continue through the second trimester. Follow the '
        'schedule your midwife gives you.',
    expectedStartWeek: 13,
    expectedEndWeek: 27,
    category: BabyGrowthMilestoneCategory.checkup,
    status: BabyGrowthMilestoneStatus.current,
  ),
  const BabyGrowthMilestone(
    id: 'gestational-diabetes-screening',
    title: 'Gestational-diabetes screening',
    description:
        'Screening for gestational diabetes is generally recommended between '
        '24 and 28 weeks of pregnancy. Ask your midwife whether it is right '
        'for your pregnancy.',
    expectedStartWeek: 24,
    expectedEndWeek: 28,
    category: BabyGrowthMilestoneCategory.checkup,
    status: BabyGrowthMilestoneStatus.upcoming,
  ),
  const BabyGrowthMilestone(
    id: 'third-trimester-checkups',
    title: 'Third-trimester prenatal checkups',
    description:
        'Prenatal checkups continue from 28 weeks and may become more frequent. '
        'Follow the schedule your midwife gives you.',
    expectedStartWeek: 28,
    category: BabyGrowthMilestoneCategory.checkup,
    status: BabyGrowthMilestoneStatus.upcoming,
  ),
];
