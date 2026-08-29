# Overflow patterns in this codebase

Each entry: the symptom you see in the screenshot, the cause, the canonical fix.
Name the pattern in TASK ANALYSIS before editing.

---

## P1 — Unbounded Text in a Row

**Symptom:** yellow/black stripes on the right edge of a row; a label clipped
mid-word; an icon pushed off-screen.

**Cause:** `Row(children: [Icon(...), SizedBox(), Text(longString)])` — `Text`
asks for its full intrinsic width and the `Row` has no slack.

**Fix:** wrap the text in `Expanded` (or `Flexible` if it should not steal
leftover space) and give it truncation.

```dart
Expanded(
  child: Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  ),
),
```

`Flexible` when the row should stay centered around its content (e.g. the
centered icon + title in `midwife_statistics_card.dart`); `Expanded` when the
text is the row's main content and the trailing widget is fixed.

---

## P2 — Two-sided Row with no give

**Symptom:** a label on the left and a value/badge on the right; the right side
gets cut, or the two collide.

**Cause:** both sides unbounded. Common in `info_row.dart`-style pairs and card
headers across the midwife screens.

**Fix:** `Expanded` the label, keep the trailing widget intrinsic, and add a
`SizedBox(width: 8)` gutter so they can never touch. If the value itself can be
long (names, vaccine names), give both sides a flex and weight them:

```dart
Row(
  children: [
    Expanded(flex: 3, child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis)),
    const SizedBox(width: 8),
    Flexible(flex: 2, child: Text(value, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis)),
  ],
)
```

---

## P3 — Chip / tag / button row that should wrap

**Symptom:** a row of status chips, filter buttons, or action pills clipped at
the right edge on a narrow phone.

**Cause:** `Row` used where the content count is data-driven.

**Fix:** swap `Row` → `Wrap` with `spacing` and `runSpacing`. This is a pure
layout swap; children are unchanged.

```dart
Wrap(
  spacing: 8,
  runSpacing: 8,
  children: chips,
)
```

If the items must stay on one line by design (a tab strip), wrap in a
horizontal `SingleChildScrollView` instead — the codebase already does this in
two places.

---

## P4 — Fixed pixel width on a flexible child

**Symptom:** a card or field that fits a 412 px phone but overflows a 360 px
one; a horizontal gap that collapses to nothing.

**Cause:** hard-coded `width: 120` / `width: 160` / `width: 125` inside a `Row`
or a scroll list. Known sites include `add_child_select_mother.dart:294`,
`add_prenatal_checkup_screen.dart:1577`, `midwife_add_mother_screen.dart:3872`,
`midwife_schedules_screen.dart:849`.

**Fix:** either `Expanded`, or relax to a constraint that can shrink:

```dart
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 160),
  child: ...,
)
```

Keep fixed sizes only for genuinely fixed things — thumbnails, avatars, icons.

---

## P5 — Column taller than the viewport

**Symptom:** stripes at the bottom of the screen; the last field or the save
button unreachable; keyboard opens and the form overflows.

**Cause:** a `Column` directly under `Scaffold.body` with no scroll, or a
`Column` inside a fixed-height dialog.

**Fix:** wrap in `SingleChildScrollView`. For forms, also respect the keyboard:

```dart
SingleChildScrollView(
  padding: EdgeInsets.only(
    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
  ),
  child: Column(...),
)
```

The codebase already does this in `midwife_sms_reminders_screen.dart:1049` —
match that idiom.

---

## P6 — Bottom sheet / dialog sized by screen fraction

**Symptom:** sheet content clipped on small phones, or a huge empty gap on
tall ones.

**Cause:** `height: MediaQuery.of(ctx).size.height * 0.8` forces an exact
height regardless of content. Sites: `add_child_step3_child.dart:288`,
`maternal_td_screen.dart:488`.

**Fix:** convert the fixed height to a max constraint and let the content size
itself:

```dart
ConstrainedBox(
  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
  child: SingleChildScrollView(child: ...),
)
```

The `maxHeight` variants already in `midwife_add_mother_screen.dart` are the
pattern to copy.

---

## P7 — Grid cell too short for its content

**Symptom:** vertical stripes inside a grid tile; a number and its caption
squeezed together.

**Cause:** `childAspectRatio` tuned on one device. Only current site:
`midwife_calendar.dart:147-148`.

**Fix:** prefer `SliverGridDelegateWithFixedCrossAxisCount(mainAxisExtent: …)`
so the cell height is explicit and independent of width, or compute the ratio
inside a `LayoutBuilder`. Do not just nudge the magic number.

---

## P8 — Content hidden under the bottom navigation

**Symptom:** the last list item or a floating action sits under the midwife
bottom nav bar.

**Cause:** list padding does not account for the shell's nav bar
(`midwife_shell.dart` owns the header and nav; tabs render inside it).

**Fix:** add bottom padding to the scrollable, not a `SizedBox` at the end of
the list:

```dart
padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
```

---

## P9 — Header title collides with back/action buttons

**Symptom:** a long page title overlapping the back arrow or trailing icon.

**Cause:** `SecondaryHeader` centers the title in a `Stack` with a fixed
`horizontal: 48` padding (`lib/widgets/secondary_header.dart:29`). A title
longer than the remaining width wraps or clips.

**Fix:** in the shared widget, give the title `maxLines: 1` +
`TextOverflow.ellipsis`, and widen the reserved padding when a `trailing` is
present. Because this is shared chrome, check the other screens that use it
after editing.

---

## P10 — Large text scale breaks an otherwise fine layout

**Symptom:** reported by the user as "fine on my phone, broken on theirs";
everything overflows slightly.

**Cause:** the app never clamps `textScaler`, and none of the cards budget for
it. A 1.3x system font size adds ~30% to every label.

**Fix:** fix the layout so it survives the scale — `Flexible` + `maxLines`,
`Wrap`, `FittedBox` on big numeric displays. Do **not** clamp `textScaler`
globally to hide it; that hurts accessibility for the mothers using this app.

---

## Anti-patterns — do not use these as fixes

- Shortening a user-facing label so it fits
- `overflow: TextOverflow.clip` without `maxLines` (hides the bug, no ellipsis)
- Wrapping everything in `FittedBox` — text becomes unreadably small
- `MediaQuery.size.width * 0.9` on a child that should be `Expanded`
- `SingleChildScrollView` around a `Row` to silence a horizontal overflow the
  user cannot discover is scrollable
- Reducing `fontSize` below 12 on body text or below 11 on captions
- Removing padding to buy space — it makes the whole screen feel cramped
