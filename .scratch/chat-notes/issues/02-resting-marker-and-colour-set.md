# 02 - The resting marker: geometry, empty state, and the five colours

Map: [Chat Notes in the sidebar](../map.md)
Type: prototype
Status: closed
Assignee: Beka Demuradze
Blocked by: none

## Question

What does the colour bar look like at rest, and what are the five colours?

Build a throwaway prototype of the sidebar row with the bar in place, in both light and dark
themes, and judge it against the real list. Answer:

1. **Geometry.** Width, height, corner radius, and inset of the bar. Does it run the full row
   height, or a shorter centred stub?
2. **The empty state.** Charting chose to overlay the bar inside the row's existing padding
   (`px SPACE_SM`, `crates/ui/src/shell.rs:3324`) so rows with a note and rows without stay
   perfectly aligned and no width is spent on the common case. Confirm or overturn this by
   looking at it. Check that the bar does not collide with the selected-row background or the
   row's rounded corners (`rounded 8px`).
3. **The five colours.** Generate them through the existing `oklch()` helper
   (`crates/ui/src/theme.rs:978`), tuned separately for light and dark. They must be muted
   enough to sit inside a near-monochrome sidebar, and separated enough to be told apart at
   a few pixels wide. Give the exact lightness, chroma, and hue values per theme.
4. **Contrast.** Run the values through `contrast_ratio` (`crates/ui/src/theme.rs:1081`)
   against both theme backgrounds and record the numbers.
5. **The selected and hovered row.** The bar must stay readable when the row is selected
   (`glass_selected_bg`, `crates/ui/src/theme.rs:896`) and while the row hover blend runs.

Link the prototype branch from the answer. The prototype is thrown away; the numbers survive.

## Note from 03 (closed)

[03 - Hover card lifecycle and mechanism](./03-hover-card-lifecycle.md) settled two things
that touch this ticket.

- **You do not design the hover target.** `03` owns it: a transparent 12px-wide, full-row-height
  child at the row's left edge, inside the existing `px(Theme::SPACE_SM)` padding. It is
  deliberately decoupled from the painted bar, so this ticket stays free to make the bar as
  small and quiet as it likes. A 3px by 16px stub is a fine bar and a hopeless hit target; that
  is fine, because they are not the same rectangle.
- **The left edge was re-confirmed.** Moving the marker beside the loader was raised and
  withdrawn during the `03` grill. The reasons are recorded in `03`'s resolution under
  "Considered and rejected". The short version: the loader is 5px by 8px, it only renders when
  the Chat is `Working`, and a chip that small cannot be scanned down a list.

## Handed down by 01

[01 - Chat Note data model and write path](./01-note-data-model-and-write-path.md) settled that
a note stores a **Colour Slot id**, a short neutral string, not an index and not hex. So this
ticket owns **two** things, not one: the five shades per theme, and the five **slot id
strings** that go on the wire. The ids must stay neutral - they carry no system meaning - and
they must survive a palette reorder, so do not encode position in them.

## The prototype

Branch `prototype/chat-note-bar`, commits `a880cd0` and `e751d3c`. Thrown away; the numbers
below survive it.

```
scripts/proto-note-demo.sh dark  B13     # the resolved dark setting
scripts/proto-note-demo.sh light B11     # the resolved light setting
```

Four geometries crossed with two palettes and four ink weights, rendered on the real sidebar
rows and cycled from a floating pill. Ten seeded chats, two of them deliberately without a
note, so the empty state was always on screen beside a marked row.

## Resolution

### 1. Geometry - a short centred stub, and charting is overturned

**3px wide, 18px tall, fully rounded (radius 1.5px), inset 2px from the row's left edge,
centred vertically in the 61px row.**

The map's **Settled while charting** block says the marker runs the **full row height**. That
was judged against the real list and **rejected**. Saying so out loud, as the map asks: the
full-height bar read as a structural spine dividing the row, while the list's own job is to be
scanned. The stub reads as a mark on the row instead of a frame around it.

The row is 61px: 6px padding, lines of 14/17/14, two 2px gaps, 6px padding
(`crates/ui/src/shell.rs`, the chat row's `flex_col`). A centred 18px stub spans roughly
y 21.5 to 39.5, so it comes nowhere near the 8px corner radius. **No corner collision is
possible at this geometry**, which is what question 2 asked to be checked.

### 2. The empty state - overlay confirmed

The stub is an **overlay inside the row's existing `px(Theme::SPACE_SM)` padding**. Charting's
choice here is **confirmed**, not overturned - picking a stub did not change it, because a stub
is still an overlay.

A row without a note is **pixel-identical to today**. No width is spent on the common case, and
marked and unmarked rows stay aligned. The reserved-gutter variant (C) was built and rejected:
it taxes every row for a marker most rows do not carry.

The bar paints **over** the selected wash, not under it. `glass_selected_bg` is a translucent
wash across the whole row plate, so the bar sits on top of an already-composited background.
The contrast numbers below measure it that way.

**The bar is not the hover target.** [03](./03-hover-card-lifecycle.md) owns that: a
transparent 12px-wide, full-row-height child. A 3px by 18px stub would be an unhittable target,
and does not have to be one, because they are two different rectangles.

### 3. The five colours

Palette **1, spread hues**. One lightness and one chroma per theme across all five, so no
single colour shouts louder than the rest. Generated through `crate::theme::oklch`.

| slot | hue | dark `#` | light `#` |
| --- | --- | --- | --- |
| `rose` | 20 | `#ce7575` | `#c77474` |
| `amber` | 78 | `#b88938` | `#b2873d` |
| `green` | 152 | `#58a670` | `#5aa26f` |
| `sky` | 232 | `#3b9ecb` | `#409ac4` |
| `violet` | 302 | `#9f81cb` | `#9b7fc5` |

- **Dark: L 0.660, C 0.112.**
- **Light: L 0.650, C 0.105.**

The hexes are for reference only. **The values that ship are the oklch triples**, resolved per
theme at paint time. A stored hex could not follow the light and dark re-tune, which is the
same reason [01](./01-note-data-model-and-write-path.md) refused hex on the wire.

The palette offset from the status hues (2) was built and rejected by eye. The risk it guarded
against is small in practice: the status signal is a word plus a dot in the row's top-right,
and the note is a bar on the far left.

### 4. Contrast

`cargo test -p zeron-ui --lib dump_note_bar_contrast -- --nocapture` reproduces all of it.
Worst of the five, at the resolved weights:

| background | dark | light |
| --- | --- | --- |
| `surface` (opaque platforms) | 5.93 | 2.81 |
| frost (resting row) | 6.08 | 2.93 |
| frost + hover wash | 4.87 | 2.60 |
| frost + selected wash | 4.87 | 2.60 |

**Separation** is measured as OKLab ΔE, not as a contrast ratio between the five. All five
share one lightness by design, so a WCAG ratio between them reads ~1.00 and measures nothing.
Closest pair is `rose`/`amber`: **ΔE 0.109 dark, 0.102 light**.

### 5. Two accepted limits, both light-mode only

**Light markers sit under 3:1 on hovered and selected rows (2.60).** Raised, measured, and
accepted by the user twice. A sweep found the 3:1 crossing at L 0.610, and a `soft+` variant
(L 0.610, C 0.105, holding light's chroma at that floor, measuring 3.04 selected) was built and
offered. It was declined in favour of the quieter mark. The user's call: in a near-monochrome
sidebar, a decorative mark that meets the AA floor for a *meaningful* graphic is louder than
this one should be. Nothing in the product depends on reading the bar - the note's text lives
in the card and the dialog.

**Light over a dark wallpaper is worse: about 2.0.** The sidebar is vibrancy, so the frost tone
rides the desktop; a black wallpaper lifts light's frost to about `#c8c8c8`. No light weight
clears 3:1 there - not even `strong`. This follows from the same acceptance and is recorded the
same way. Dark theme has no matching cliff: at the resolved `std` weight its worst wallpaper
case is **3.50**, over a white desktop.

Both belong in the spec's known limits. If either is ever revisited, `soft+` is the measured
step that fixes the first one, and nothing fixes the second inside a muted palette.

### 6. The five Colour Slot ids

`rose` `amber` `green` `sky` `violet`

Handed down by [01](./01-note-data-model-and-write-path.md): a short neutral string, no index,
no hex. These are hue-family names, so they

- carry **no system meaning** - the map settled that the five are decorative,
- **survive a reorder**, because nothing about them is positional, and
- **survive the light/dark re-tune**, because a name follows a slot where a hex cannot.

They stay honest through any re-tune that keeps a slot inside its own hue family, which is the
only kind of re-tune that leaves the set recognisable at all.

### Fog cleared

None. [03](./03-hover-card-lifecycle.md) had already settled the archived shelf: one shared
bar-and-hit-zone helper, called from both `Shell::render_chat_row` and the shelf's row builder
in `crates/ui/src/shell/spaces.rs`. This ticket confirms the shelf builds its row inline rather
than calling `render_chat_row`, so that helper is genuinely needed - but that is an
implementation note for the spec, not a decision, and it graduates nothing.
