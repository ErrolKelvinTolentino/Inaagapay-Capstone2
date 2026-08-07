# Baby Book — Data Model & Scoping

**Status:** Phase 1 (foundation). Migration: `database/migrations/20260808_baby_book_foundation.sql`
**Last updated:** 2026-08-08

---

## 1. The rule

> A Baby Book entry belongs to **a pregnancy** or **a child** — never both, never neither.

Enforced in the database by `baby_book_milestones_scope_check` and `baby_memories_scope_check`, not by convention.

**Why twins decide this.** One gestation produces the bump photos, the fetal-growth timeline, and the mother's own prenatal care — copying that into two books would be wrong on the facts. Two children then develop separately; one may sit at six months and the other at eight, and merging their firsts destroys the record the book exists to keep.

`children.pregnancy_id` already links the two, so a child's book opens with the shared pregnancy chapter without duplicating a row.

```
pregnancies ──< children              (fetal_count > 1 → twins)
     │                │
     │ prenatal       │ postnatal
     ▼                ▼
   baby_book_milestones / baby_memories
   (exactly one FK set per row)
```

---

## 2. Section-by-section

| UI section | Scope | Data source | Status |
|---|---|---|---|
| Pregnancy growth journey | pregnancy | `pregnancies` (LMP/EDD → current week) + static fetal-growth reference | 🔴 sample |
| Prenatal milestones | pregnancy | `baby_book_milestones` where `pregnancy_id` | 🟡 table ready |
| Pregnancy health records | pregnancy | **`mother_medications`** + `given_medications` + TD dose on `prenatal_checkups` | 🔴 sample |
| Memory gallery | either | `baby_memories` + `files` | 🟡 table ready |
| Child milestones (firsts) | **child** | `baby_book_milestones` where `child_id` | ❌ no UI yet |
| Child growth | child | existing `growth_records` | ✅ exists elsewhere |
| Child immunization | child | existing `immunization_records` | ✅ exists elsewhere |

**No new table for health records.** `mother_medications` already holds name, frequency, start/end date and an `active/completed/stopped` status; `given_medications` holds what was administered. That section is a read and a mapping, not storage.

---

## 3. Two decisions worth keeping

**Status is computed, never stored.** Whether a milestone is upcoming, current, or completed follows from `observed_on` and either the child's age or the current gestational week. It is a function of today's date. Storing it would repeat the immunization defect fixed in `20260807`: an "On Time" badge that was a hardcoded literal and so called every dose timely, including one given ten months late.

**Photos reference `files`.** No `photo_url` column. Uploads keep one code path and inherit `file_size`, `mime_type`, and `uploaded_by`, which the panel already asked about.

---

## 4. Dart models vs. the tables

The section widgets already take injected data, so they need no rewrite — only a real source:

```dart
PregnancyGrowthJourney(currentPregnancy:, stages:)
PregnancyHealthRecordsSection(initialRecords:)
BabyGrowthMilestonesSection(currentPregnancy:, initialMilestones:)
```

`BabyGrowthMilestone` is **prenatal**: `expectedStartWeek`, `expectedEndWeek`, `recordedPregnancyWeek`, `pregnancyMonth`. Its categories (development, movement, checkup, ultrasound, trimester, personal memory) map to `milestone_templates` where `phase = 'prenatal'`.

Post-birth firsts need a **sibling widget**, not a reuse — `BabyGrowthMilestonesSection` takes `currentPregnancy`, which a child's book does not have. Postnatal templates use the four standard developmental domains (motor, language, social, cognitive) keyed by age in months.

---

## 5. The birth transition

This is what makes the feature deliver E7-05's promise — *"so the app stays useful past delivery."*

1. **During pregnancy** — one book, opened from the pregnancy. Prenatal chapter only.
2. **At delivery** — midwife records the birth; `children` rows are created carrying `pregnancy_id`.
3. **After birth** — each child gets a book that opens with the shared pregnancy chapter, then continues with their own firsts, growth, and immunizations.

For twins: two books, one shared first chapter.

---

## 6. Remaining work

- [x] Seed prenatal `milestone_templates` — `20260808_baby_book_prenatal_templates.sql`, 9 rows
- [x] Repository layer — `lib/services/baby_book_repository.dart`
- [x] De-mock the pregnancy sections — cover card, stats card, growth journey, milestone timeline
- [x] Mother entry point — dashboard card → `/baby-book` → `BabyBookEntry` resolves her `motherId`
- [ ] De-mock health records (read `mother_medications` + `given_medications`)
- [ ] De-mock the memory gallery (`baby_memories` exists; gallery still uses asset images)
- [ ] Seed postnatal templates — **needs DOH/WHO sourcing with citations**
- [ ] Child-scoped milestones widget
- [ ] Child card → that child's book
- [ ] Rename `baby_book_mockup_page.dart` → `baby_book_page.dart` once no sample path remains
- [ ] Birth transition

**On the sample-data fallback.** The original plan kept `demoCurrentPregnancy` as a fallback so the page always rendered. That was dropped: showing a real mother a sample "20 weeks pregnant" when she has no ongoing pregnancy is worse than showing nothing. Sample data is now reachable only when no `motherId` is supplied — the preview path used by widget tests, never by a signed-in mother.

**RLS is disabled** on these three tables, consistent with `notifications` and `device_tokens`. The app authenticates against `accounts` with bcrypt and reaches Postgres with the anon key. This is a capstone-scope decision and belongs in the study's limitations.
