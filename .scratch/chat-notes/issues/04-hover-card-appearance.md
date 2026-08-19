# 04 - Hover card appearance

Map: [Chat Notes in the sidebar](../map.md)
Type: prototype
Status: closed
Assignee: Beka Demuradze
Blocked by: 02, 03
Prototype: `prototype/chat-note-card`, `scripts/proto-note-card.sh`

## Question

What does the expanded card look like?

Build it with the primitive `03` chose and the colours `02` produced, then judge it against a
real conversation behind it. Answer:

1. **The surface.** Start from `popover::popover_card` (`crates/ui/src/popover.rs:307`). How
   much of the note's colour does the card carry: a tinted background, a coloured left edge
   that continues the bar, or only a small colour dot?
2. **The anchor.** Where exactly does it sit relative to the bar? What is the gap? What
   happens near the top and bottom edges of the window, and when the sidebar is at its
   narrowest.
3. **Size and text.** Maximum width, padding, font size, line height, and how a full
   280-character note wraps. The card must never scroll.
4. **The short note.** A five-word note must not produce a card of the same size as a full
   one. State how the card sizes to its content.
5. **Motion.** Does it fade, scale, or grow out of the bar? Match `crates/ui/src/motion.rs`.

Link the prototype branch from the answer.

## Note from 03 (closed)

[03 - Hover card lifecycle and mechanism](./03-hover-card-lifecycle.md) constrains this ticket.
Read its resolution before starting; three of the five questions above are already narrowed.

- **The surface is called the Note Card.** Use that term. See
  [CONTEXT.md](../../../CONTEXT.md).
- **Item 1, the surface.** It is `popover::popover_card` inside `popover::menu_at`, drawn from
  `Shell::render_overlays`, not `anchored_menu`. `menu_at` occludes, which is wanted.
- **Item 2, the anchor.** The X is already fixed: the card's left edge sits at the sidebar's
  right edge plus a gap, derived from the live sidebar width, not `SIDEBAR_DEFAULT`. This is a
  constraint, not a preference: `gpui::deferred` inherits the sidebar's scroll clip, so the
  card cannot sit over the row at all. **You still own the gap**, the vertical alignment to the
  row, and the window edge behaviour.
- **Item 2 carries a hard constraint, and it is a narrow-window problem, not a narrow-sidebar
  one.** `menu_at` snaps by **shifting the card left** when it overflows the right edge
  (`crates/gpui/src/elements/anchored.rs:190`). A card pushed back over the sidebar would
  occlude the hit zone and restart the `crates/ui/src/shell.rs:3287` flicker loop. So the
  maximum width in item 3 is not only a reading-comfort choice: it must be capped against the
  space left of the window's right edge. If that space is too small to be usable, this ticket
  decides what happens - flip to the sidebar's left, or do not open at all.
- **Item 5, motion.** `menu_in` and `menu_out` are already chosen, because a commanded close
  and a real exit animation are why `Popup` beat gpui's own tooltip. You own whether anything
  further should grow out of the bar.

## Handed down by 01

[01 - Chat Note data model and write path](./01-note-data-model-and-write-path.md) settled that
the 280 character cap is an **authoring affordance, not a storage invariant**. iOS writes
registry rows directly and never passes through the Mutate RPC, so no engine check can promise
the stored text is short. The card must therefore stay sane for a note far longer than 280
characters. Point 3 above must say what the card does in that case, given that it may never
scroll.

## Resolution

Prototype: branch `prototype/chat-note-card`, run with `scripts/proto-note-card.sh dark`.
Every value below was judged in that build, against the real list and a real transcript, in
three passes. The seed `C22212m` reproduces the resolved card exactly; the switcher pill still
carries every candidate that lost.

### The resolved card

| | |
| --- | --- |
| surface | tinted: the note's colour at **0.10** across the whole card, plus a hairline of the same colour at **0.32** |
| horizontal anchor | left edge at the **live sidebar width + 8px**. Alongside the row, never over it |
| vertical anchor | **centred on the row**, clamped to 8px from the window's top and bottom |
| maximum width | **320px**, and the card sizes to its content |
| padding | **10px** horizontal, **8px** vertical |
| text | **13px**, line height **19px**, `theme.text` |
| overflow | **10 lines**, then elide. The card never scrolls |
| trigger | **the whole row** |
| delays | **350ms** to open, **120ms** to close, both from [03] |
| motion | `menu_in` and `menu_out` ([03]), plus a **10px leftward offset** resolving over `MENU_IN`'s 140ms, so the card arrives from the sidebar rather than appearing beside it |
| narrow window | clamp the width to the room available; below **200px** of room, do not open |
| click | dismiss, and stay dismissed until the pointer leaves that row |

### 1. The surface

**The tinted surface.** The colour dot, the left rail and the plain no-colour card were all
built and cycled against the same notes. The dot reads as a bullet, which invites a second
bullet the note will never have. The rail is the marker enlarged, so the card looks like a
bigger version of a thing whose whole job was to be small. No colour at all loses the link to
the mark that opened it. The wash keeps the tie without spending a shape on it.

`popover::popover_card_flush` is the base, so the frost, hairline, 12px radius and shadow are
the app's, not this feature's. Only the tint and the border colour are new.

### 2. The anchor, and 03's constraint read correctly

**X: the live sidebar width plus 8px.** From `eval_tween(sidebar_tween, sidebar_target())`, so
it rides the collapse tween and is never `SIDEBAR_DEFAULT`. This is what [03] specified.

[03] said the card "must clear the sidebar", but **neither reason it gave says that**, and the
difference was worth the pass it took to find:

- The scroll clip binds a card mounted **inside** a row. This card renders at the Shell's top
  level, so it paints over the sidebar freely.
- The flicker loop needs an occluder on top of the element that **drives** the hover.

So the floor is the hover target's right edge, not the sidebar's. A **hug** placement was built
on that finding, tried, and **rejected on use, not on principle**: the card covers the row it
belongs to, which costs the Archive pill (`crates/ui/src/shell.rs:3193`) a dismissal before it
can be clicked, and forces the card to keep itself alive under the pointer. Standing clear
costs nothing and keeps the list readable while the note is up.

A **tail** variant - the card clear of the sidebar with a 3px rounded stub in the note's colour
bridging the gap, in the marker's own vocabulary from [02] - was built and not chosen. It is
recorded because it is the cheapest answer if the card ever reads as disconnected.

**Y: centred on the row.** Row-top and row-bottom were both built. Centring is the only one
that reads as belonging to the row rather than hanging off it. It needs the card's height a
frame before the card exists, so the height is measured by a `canvas` inside the card and
cached per chat and width; the first frame uses an estimate from the text length and is spent
at the very start of the 140ms fade.

Near the window's top and bottom the card is clamped to 8px and stops tracking the row. It is
never allowed to snap: `snap_to_window_with_margin` moves the card, and everything here depends
on the card not moving on its own.

### 3. Size and text

**320px maximum, and the card sizes to its content.** 280px crowded the 280-character note;
360px let a one-line note become a wide, thin slab. The width is a maximum, never a target.

**10 lines, then elide, via `line_clamp`.** [01] settled that the 280-character cap is an
authoring affordance and storage cannot promise a short note, so the card is bounded by lines
rather than by trust. A 671-character note was in the fixtures for exactly this and elides
cleanly at 320px.

**One accepted limit.** Near the 200px floor a line holds roughly 28 characters, so a note
inside the 280-character cap can need more than 10 lines and would elide. This is accepted: at
that width the window is so narrow the sidebar dominates, and the alternative is an unbounded
card in the smallest window. The implementer should measure the real crossing width. If it is
comfortable to do so, **raise the floor** to the width where 280 characters fit in 10 lines,
rather than raise the clamp - the clamp is what keeps the pathological note bounded.

The URL fixture stays in the spec's test set: an unbreakable token wider than the card clips
rather than widening it.

### 4. The short note

**It sizes to content, so a five-word note is a five-word card.** Nothing is stretched to the
maximum and nothing is padded to a minimum. This is a property of the layout, not a rule to
implement: the card is inside an `anchored` layer, which sizes to its children, and 320px is a
`max_w` on the text.

### 5. Motion

`menu_in` and `menu_out` are [03]'s, and stand. Added: **the card arrives from the sidebar**,
a 10px leftward offset resolving to zero over `MENU_IN`'s 140ms curve, so the entrance carries
a direction instead of only an opacity. Judged against no offset, which reads as the card
appearing already in place.

### 6. The trigger, which this ticket re-opened

**The whole row opens the card. The 12px hit zone is gone.**

This overturns charting's "hovering the whole row is not available" and [03] decision 8. The
reason charting gave - the row's hover already swaps the corner to an Archive pill - is real
but not blocking: gpui allows one hover listener per element, and that listener can do three
jobs as easily as two. In use, a 12px strip is a target you have to aim at, for a payload that
is worth no aiming at all.

**Because the card stands clear, the row's own `on_hover` can drive this.** That is the shape
to ship: one more branch inside the listener at `crates/ui/src/shell.rs:3348`, no new hover
field, no window-wide listener.

The prototype instead tracks the pointer geometrically, through
`Window::on_mouse_event` (gpui `window.rs:4782`) against cached row rectangles, because it also
had to support the hug placement, where the card covers the row and `hitbox.is_hovered`
(gpui `elements/div.rs:305`) goes false under it. **That machinery is not part of this
resolution.** It is only needed if a future change lets the card cover its own trigger.

### 7. What a click means

**A mouse-down dismisses the card, and it stays dismissed until the pointer leaves that row.**

Plain closing is not enough once the row is the trigger: the pointer is still on the row after
the click, so the card returns 350ms later, on top of the chat the click just opened. The
dismissal lifts on the first pointer move to another row or off the list, never on a timer.

[03] decision 5's other commanded closes stand unchanged: the resort epoch, the sidebar scroll,
and any mouse-down. One addition, found by building it: while `chat_menu`, the rename dialog or
the delete confirmation is up, the trigger stands down entirely. A right-click leaves the
pointer resting on the row, and without this the card opens under the context menu.

### 8. The narrow window, which 03 handed down

**Clamp the width to the room actually available, and below 200px of room do not open at all.**

`menu_at` snaps by shifting the card left (`crates/gpui/src/elements/anchored.rs:190`), which
would slide it back over the sidebar. So the card is capped against
`viewport.width - (sidebar + gap) - 8` instead of being allowed to move. Flipping to the
sidebar's left was considered and is impossible: the sidebar is flush to the window's left edge,
so there is no left to flip to.

### What this overturns

Said out loud, as the map asks:

- **Charting: "hover the bar opens the card".** Overturned. The whole row opens it. The bar
  stays as the resting mark, which is all [02] ever made it.
- **[03] decision 8, the 12px hit zone.** Overturned, and deleted rather than widened.
- **[03] decision 6, "the card must clear the sidebar".** Corrected, not overturned. The
  conclusion survives; the reason given for it did not. The real floor is the hover target's
  right edge, and the card clears the sidebar by choice.
- **[03] decision 4, "the card is not hoverable".** Stands. It was re-opened by the hug
  placement and closed again when hug lost.
- **[02]'s marker, and [03] decisions 1, 2, 3, 5 and 7.** Untouched.

### Implementer notes

- The row's hover listener at `crates/ui/src/shell.rs:3348` gains the open and close calls.
  `chat_status_hover` is still not reused, exactly as [03] said.
- **The row's bounds are still captured.** Section 6 retires the window-wide mouse listener,
  not the measurement: centring the card on its row needs that row's rectangle, so [03]'s
  `note_card_anchor` capture survives unchanged, sourced from the row itself now that the hit
  zone is gone. The card's own height is measured the same way, and cached.
- The archived shelf builds its rows inline (`crates/ui/src/shell/spaces.rs`), so it needs the
  same branch in its own hover listener. [03]'s single render site at the Shell's top level is
  unchanged: one card, one place.
- If the card is ever allowed to cover its own trigger, none of the hover wiring survives. The
  prototype carries the geometric replacement, and a note holding the covered row's hover wash
  up, because gpui un-hovers a covered row and it goes cold under the card.
