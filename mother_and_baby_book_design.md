# Mother Book & Baby Book — Information Architecture and Data Model

**Last updated:** 2026-08-08
**Migrations:** `20260808_baby_book_foundation`, `20260808_baby_book_prenatal_templates`, `20260808_milestone_owner`

---

## 1. The rule everything follows

> **A record belongs to whoever it is *about*, not to when it happened.**

An anatomy scan produces two things: a clinical report, which is the mother's, and a first picture, which is the baby's. Both happen before birth. They belong in different books.

This replaces the earlier prenatal/postnatal split, which put the mother's iron and folic acid inside something called a Baby Book and duplicated two screens that already existed.

| | **Mother Book** | **Baby Book** |
|---|---|---|
| About | her care | the baby's story |
| One per | pregnancy | child |
| Contains | prenatal checkups, her TT/Td, iron & folic acid, lab tests, ultrasound reports, weight gain vs IOM, BP, risk flags and who approved them | before-you-were-born chapter, birth details, firsts, growth, immunizations, photos |
| Ends | at delivery, then readable as history | never |

---

## 2. Where they live — no new tabs

| Tab | Role |
|---|---|
| **Home** | Covers only. What is happening now, and the way in. |
| **Journal** | Her private diary. Belongs to neither book. |
| **Children** | Every child, **plus an Expecting card while pregnant** → each opens a Baby Book |
| **My Health** *(was Records)* | The Mother Book, organised per pregnancy |
| **Hotlines** | Unchanged |

### Why the Expecting card

During pregnancy there is no child row yet, but the baby already has a story — a heartbeat heard, a first kick, a first picture. That story needs somewhere to live before birth.

Putting an **Expecting** card in the Children list solves it without inventing a screen: the list is already the place that answers "who are my children," and an unborn one belongs in that answer. At delivery the card becomes the child. For twins it becomes two children, and both their books open with the same chapter.

It also removes the Baby Book card from Home, which duplicated this.

---

## 3. Home is state-driven

Home shows the cover of what is current, never a whole book — a book on Home can only ever be one book, which fails the moment there are twins or a second child.

| Her state | Home shows |
|---|---|
| Pregnant | Pregnancy card — week, next visit, this week's tip → **My Health** |
| Recently gave birth | Newborn card — age, next immunization → **that baby's Baby Book** |
| Both | Both, pregnancy first |
| Neither | Children, summarised |

---

## 4. Content moves, it never duplicates

Fetal growth — *"this week your baby is the size of a banana"* — is live content while she is pregnant and a keepsake afterwards. It is the same content with one home at a time:

```
pregnant   →  Home + Expecting card      "your baby this week"
after birth →  that child's Baby Book     "how you grew before we met you"
```

Two duplications found and removed:

- **Her supplements** appeared in the Baby Book while `records_screen.dart:970` already read `given_medications`. They belong to the Mother Book only.
- **Week-by-week pregnancy** appeared in the Baby Book while `mother_dashboard.dart:67` already had `_babySizeByWeek`, trimester and weekly tips. Home keeps the summary; the detail lives in one place.

---

## 5. Multiplicity

```
mother
 ├── pregnancy 1 ──── Mother Book 1        (history)
 │      └── child A ── Baby Book A ─┐
 │      └── child B ── Baby Book B ─┴─ share one before-birth chapter (twins)
 └── pregnancy 2 ──── Mother Book 2        (current)
        └── Expecting card → becomes child C at delivery
```

Enforced by `baby_book_milestones_scope_check`: a row carries `pregnancy_id` **or** `child_id`, never both. Prenatal entries attach to the pregnancy, so twins share them rather than owning copies. `children.pregnancy_id` links a child back to the chapter.

---

## 6. UX rules for rural mothers

These are constraints, not preferences. Users may have limited literacy, may read Filipino more comfortably than English, and are often on a small, older phone in poor light.

1. **A picture carries the meaning; text confirms it.** Every card leads with an illustration, icon, or photo. Never an unlabelled icon and never a wall of text.
2. **One idea per card.** If a card needs a paragraph, it is two cards.
3. **Short lines.** Headings ≤ 5 words. Body ≤ 2 lines at a glance; anything longer goes behind "Learn more".
4. **Status by colour *and* shape.** Never colour alone — add an icon or word, for colour-blind users and for cheap screens with poor contrast.
5. **Plain words.** "Tubig sa paligid ng baby", not "amniotic fluid index". Clinical terms may appear as a secondary line, never as the label.
6. **Numbers need a sentence.** A Z-score or a BP reading always carries "this is normal" / "let's watch this".
7. **Big targets.** Minimum 48dp; assume a thumb, not a fingertip.
8. **Never blame her.** A milestone with no record reads "not recorded", never "missed" — many depend on a provider documenting something.
9. **Both languages, always.** Use the existing `_t('English','Filipino')` pattern; never ship an English-only string on a mother-facing screen.

---

## 7. Data model

Three tables (`20260808_baby_book_foundation`):

- **`milestone_templates`** — catalogue. `phase` (prenatal / postnatal) places it on a timeline; **`owner`** (mother / baby) decides which book it appears in.
- **`baby_book_milestones`** — recorded entries, `pregnancy_id` XOR `child_id`.
- **`baby_memories`** — photo keepsakes, scoped the same way.

**Status is computed, never stored.** Upcoming / current / completed follows from `observed_on` and today's date. Storing it would repeat the immunization defect fixed in `20260807`, where an "On Time" badge was a hardcoded literal that called every dose timely — including one given ten months late.

**Photos reference `files`.** No `photo_url` column, so uploads keep one path and inherit `file_size`, `mime_type`, `uploaded_by`.

**No table for her medications.** `mother_medications` and `given_medications` already hold them.

### Owner assignment of the nine prenatal templates

| Template | Owner | Why |
|---|---|---|
| `pregnancy-confirmed` | baby | the day she learned about him |
| `first-prenatal-checkup` | mother | her care |
| `first-ultrasound` | baby | his first picture |
| `heart-activity` | baby | his heartbeat |
| `second-trimester` | mother | her pregnancy progressing |
| `first-movement` | baby | his first kick |
| `anatomy-scan` | baby | his picture; the report is hers |
| `third-trimester` | mother | her pregnancy progressing |
| `birth-preparation` | mother | her birth plan |

---

## 8. Status

- [x] Tables, scoping constraint, indexes
- [x] Prenatal templates seeded (9)
- [x] Repository with derived status
- [x] Pregnancy sections reading real data
- [x] `owner` split and templates re-sorted
- [x] Expecting card in the Children tab
- [x] Supplements removed from the Baby Book
- [ ] Rename Records tab → **My Health**, organise per pregnancy
- [ ] Newborn card on Home
- [ ] Postnatal templates — **needs DOH/WHO sourcing with citations**
- [ ] Child-scoped Baby Book screen
- [ ] Birth transition
- [ ] Memory gallery on `baby_memories` instead of asset images

**RLS is disabled** on these tables, consistent with `notifications` and `device_tokens`. The app authenticates against `accounts` with bcrypt and uses the anon key. A capstone-scope decision that belongs in the study's limitations.
