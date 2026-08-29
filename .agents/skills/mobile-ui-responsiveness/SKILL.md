---
name: mobile-ui-responsiveness
description: Fix mobile UI overflow and responsiveness defects in the InaAgapay Flutter app from annotated screenshots. Use when the user sends a screenshot with circled/marked regions, or reports RenderFlex overflow, clipped text, cut-off cards, squeezed rows, or "not responsive on my phone" on any midwife, mother, or admin screen. Layout-only — never changes behavior, data, or features.
---

# InaAgapay mobile UI responsiveness

Turn an annotated screenshot into a minimal, layout-only diff. The app is
`inaagapay_flutter_v2/` (Flutter). Screens live in `lib/screens/<role>/`, shared
widgets in `lib/widgets/`, colors in `lib/theme/app_colors.dart`.

## The one hard rule

**Layout only. Nothing else.** Every edit must be a pure rendering change: the
same data, the same taps, the same navigation, the same network calls, the same
validation before and after.

Allowed to touch:

- Layout widgets and their properties — `Expanded`, `Flexible`, `Wrap`, `Row`,
  `Column`, `SingleChildScrollView`, `FittedBox`, `SizedBox`, `ConstrainedBox`,
  `LayoutBuilder`, `IntrinsicHeight`
- Text rendering — `overflow`, `maxLines`, `softWrap`, `textAlign`, `fontSize`
- Sizing and spacing — `width`, `height`, `padding`, `margin`, `constraints`,
  `mainAxisSize`, `crossAxisAlignment`, `spacing`/`runSpacing`
- Grid/list geometry — `crossAxisCount`, `childAspectRatio`, `mainAxisExtent`
- Wrapping an existing subtree in a layout widget, or extracting an unchanged
  subtree into a private `_Widget` purely to keep the file readable

Never touch, even if it looks wrong:

- `onTap` / `onPressed` / `onChanged` bodies, navigation targets, route args
- State fields, `setState` calls, controllers, `initState`/`dispose`
- Repository, service, or Supabase calls; models; parsing; validation rules
- Business copy — do not shorten a label to make it fit. Make the layout hold
  the label. (Truncation via `TextOverflow.ellipsis` is a rendering choice and
  is allowed; rewriting the string is not.)
- Brand colors, shadows, radii — unless the user asked about them specifically

If a genuine fix is impossible without a behavior change, stop and say so
instead of doing it.

**Never run `dart format`.** The repo predates the current style; it rewrites
whole files and buries the real diff. Match the surrounding formatting by hand.

## Workflow

### 1. Read the screenshot precisely

Before touching code, write down for each marked region:

- What is on screen (exact visible strings — these are your grep keys)
- What is wrong: text clipped mid-word / ellipsis too early / yellow-black
  overflow stripes / card taller than viewport / element pushed off-screen /
  row squeezed / element overlapping another / content under the bottom nav
  or the keyboard
- Which axis it overflows on, horizontal or vertical

If a region is ambiguous, ask before editing. A wrong guess here means editing
the wrong widget in a 200 KB file.

### 2. Locate the widget

Grep the exact visible text first — it is far more reliable than guessing files:

```bash
grep -rn "Active Pregnancies" inaagapay_flutter_v2/lib
```

If the string is built dynamically, grep the nearest static neighbor label, the
icon name, or the section heading. `references/screen-map.md` maps screens to
files when the text search comes up empty.

Then read enough surrounding code to see the full constraint chain: the widget,
its parent, and the scroll/`Row`/`Column` it sits in. Overflows are almost
always caused by a parent, not by the leaf that renders the stripes.

### 3. Diagnose against the pattern catalogue

`references/overflow-patterns.md` lists the recurring causes in this codebase
with the canonical fix for each. Name the pattern before you edit. If none of
them fit, say so explicitly rather than reaching for a band-aid.

Prefer, in order:

1. Give the flexible child room (`Expanded` / `Flexible`)
2. Let content wrap or scroll (`Wrap`, `SingleChildScrollView`)
3. Let text truncate (`maxLines` + `TextOverflow.ellipsis`)
4. Relax a hard-coded size into a constraint (`maxWidth` instead of `width`)
5. Scale down as a last resort (`FittedBox`, smaller `fontSize`)

Never fix an overflow by shrinking the viewport assumption — no
`MediaQuery.of(context).size.width * 0.9` sprinkled onto a child that should
just be `Expanded`.

### 4. Edit minimally

One pattern, one edit. Keep the diff small enough that the user can see at a
glance that nothing functional moved. Do not reformat neighbors, do not reorder
properties, do not add comments explaining the obvious.

### 5. Verify

- `flutter analyze` on the touched files — must be clean of new issues
- If a preview is running, check the screen at 360x800 (small Android) and
  confirm the marked region renders correctly
- Re-check the same screen with a long value in the offending field (long
  mother name, 4-digit count, longest vaccine name) — the original screenshot
  may have had short data hiding the real limit

Target the small end: **360x640 logical px** is the floor this app should hold.
Also sanity-check at 320 px wide if the region is a dense row.

## Reporting

Report in two blocks, matching how work is reviewed on this project.

**TASK ANALYSIS** — per marked region: what is wrong, the file and line, the
pattern from the catalogue, and the fix you intend. State anything you could
not diagnose from the screenshot.

**IMPLEMENTATION SUMMARY** — per region: the actual edit, and one line
confirming behavior is untouched. List anything you deliberately left alone and
why.

## Batching

The user works screen by screen and sends several screenshots per screen. When
multiple regions map to the same widget file, fix them in one pass. When the
same pattern appears across several screens (a stat row, a card header, a chip
list), fix the shared widget in `lib/widgets/` once rather than patching each
screen — but confirm the shared widget's other call sites still look right.
