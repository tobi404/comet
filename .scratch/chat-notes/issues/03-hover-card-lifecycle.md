# 03 - Hover card lifecycle and mechanism

Map: [Chat Notes in the sidebar](../map.md)
Type: grilling
Status: closed
Assignee: Beka Demuradze
Blocked by: none

## Question

Which primitive drives the expanded card, and what is its full lifecycle?

The app has no shared tooltip primitive. Two patterns exist, and this ticket picks one:

- The composer's bespoke delayed tooltip state machine (`MentionTooltipPhase`,
  `mention_tooltip_reduce`, `crates/ui/src/composer.rs:806`), which already solves the
  "wait, then show, then reduce" problem.
- `popover::Popup<T>` plus an anchored menu helper (`crates/ui/src/popover.rs:67`, `:395`),
  which the row's right-click menu already uses (`chat_menu`, `crates/ui/src/shell.rs:825`).

Settle:

1. **The primitive**, with the reason.
2. **Where the hover state lives.** The row already carries `chat_status_hover`
   (`crates/ui/src/shell.rs:3339`) for the Archive pill swap. Is the bar's hover a second
   field, or the same one? They must not interfere.
3. **The delay**, opening and closing. About 250ms to open was chosen while charting. Is
   there a close delay, so a pointer that crosses the bar by accident does not flash the card?
4. **What happens when the row moves.** The sidebar resorts with a FLIP glide and rows are
   keyed for it (`crates/ui/src/shell.rs:3459`). If the row glides or scrolls out of view
   while the card is open, does the card follow, close instantly, or stay anchored to a stale
   point?
5. **The `.occlude()` trap.** The row deliberately does not occlude its corner, because
   occluding caused a mount and unmount flicker loop (comment at
   `crates/ui/src/shell.rs:3287`). State how the bar's hover target avoids the same loop.
6. **The archived shelf.** It has its own hover field (`archived_hover`,
   `crates/ui/src/shell/spaces.rs:729`). Does the chosen mechanism cover both paths, or does
   the shelf need its own? If this cannot be answered here, graduate it from the map's fog
   into its own ticket.

## Resolution

The floating surface is now called the **Note Card**. See [CONTEXT.md](../../../CONTEXT.md).

### Premise correction

The ticket's framing was wrong on both counts, and later tickets should not inherit it.

- **The app does have a shared tooltip primitive.** gpui ships a full lifecycle:
  `ActiveTooltip` with `WaitingForShow`, `Visible` and `WaitingForHide`
  (gpui `crates/gpui/src/elements/div.rs:3392`), a per-call `.tooltip_show_delay()`, and
  `.hoverable_tooltip()`. This repo already uses it at `crates/ui/src/history.rs:941` and
  `:980`, `crates/ui/src/badges.rs:93`, and `crates/ui/src/composer.rs:4006`.
- **The composer machine is not an alternative to it.** `mention_tooltip_reduce` only
  hit-tests mention chips, which are painted inside a custom Element and have no `div` to
  hang `.tooltip()` on. It then hands off to that same primitive through
  `window.set_tooltip` (`crates/ui/src/composer.rs:2959`). The colour bar is a real `div`,
  so the reason the composer went bespoke does not apply here.

Three candidates were graded, not two.

### 1. The primitive

**`popover::Popup<T>` plus `popover::menu_at`,** rendered from `Shell::render_overlays`.
This is the same pattern `chat_menu` already uses from these same rows
(`crates/ui/src/shell.rs:4372`).

gpui's own tooltip was rejected on four counts, any one of which is disqualifying:

- **Pointer anchor.** The tooltip position is frozen at the pointer plus 1px when the delay
  expires (`crates/gpui/src/window.rs:3023`, `:3026`). The map fixed a bar-derived anchor
  ("the card floats rightward"). A card that lands wherever the pointer crossed the strip
  reads as accidental.
- **No commanded close.** `clear_active_tooltip` is `pub(crate)`. The Shell cannot close a
  gpui tooltip. Decision 5 below requires exactly that.
- **Hardcoded hide delay.** `HOVERABLE_TOOLTIP_HIDE_DELAY` is 500ms
  (gpui `div.rs:50`), not configurable without a fork.
- **No exit animation.** gpui's tooltip has no closing phase and unmounts in one frame.
  Every other floating surface in this app plays `motion::menu_out`.

### 2. The render site, which is the decisive constraint

**The Note Card renders at the Shell's top level, in `render_overlays`, never inside a row.**

`gpui::deferred` does **not** escape ancestor clipping. `paint_deferred_draws` restores the
content mask captured where the deferred layer was declared
(`crates/gpui/src/window.rs:3168`, `with_content_mask(content_mask, ...)`). The chat rows and
the archived shelf both live inside `#sidebar-lists`, which is `.overflow_y_scroll()`
(`crates/ui/src/shell.rs:3583`). A card mounted in a row would be clipped to the sidebar and
could never reach the conversation area. The comment at `crates/ui/src/shell.rs:3556` records
the same finding: the space filter was hoisted above the scroll region for this reason.

This is why `anchored_menu` is not used. It attaches to the trigger, so it inherits the clip.
`menu_at` takes an explicit window position and is called from outside the scroll region.

The card is positioned to clear the sidebar horizontally: its left edge sits at the sidebar's
right edge plus a gap. Ticket `04` owns the gap and the vertical detail.

### 3. Where the hover state lives

A **new** set of fields on `Shell`. `chat_status_hover` is not reused and is not touched.
There is no interference: the hit zone is a child element of the row with its own listener,
so the row keeps its single hover listener and its Archive pill swap is unchanged. Hovering
the bar also hovers the row, which is correct.

Proposed shape, four fields with one job each:

```rust
/// The visible Note Card plus its menu_out exit phase.
note_card: popover::Popup<NoteCard>,          // NoteCard { chat: String, anchor: Bounds<Pixels> }
/// The 350ms open delay. `generation` guards stale timers, as the composer does.
note_card_wait: Option<NoteCardWait>,          // { chat: String, generation: u64, _task: Task<()> }
/// The 120ms close delay. Cancelled by dropping the task.
note_card_leave: Option<Task<()>>,
/// Hit-zone bounds for the current target, captured by a `canvas` child.
note_card_anchor: Option<(String, Bounds<Pixels>)>,
```

Sequence: the pointer enters the hit zone, `on_hover` sets `note_card_wait` and starts the
timer. On the next frame that row's `canvas` sees it is the target and writes
`note_card_anchor`. 350ms later the timer fires, the bounds are present, and
`note_card.open(...)` runs. Only the target row writes bounds, so nothing accumulates.

### 4. The delays

- **Open: 350ms.** Matches `crates/ui/src/history.rs:947`, the repo's existing number for a
  hover reveal. The 250ms chosen while charting is overturned: it fires when the pointer
  merely crosses the sidebar's left edge on its way elsewhere. Rejected 500ms (gpui default)
  and 420ms (`MENTION_TOOLTIP_DELAY`) as a fourth and fifth number to remember.
- **Close: 120ms.** This absorbs pointer jitter: brief exits from a 12px strip while the card
  is already open, without a flicker. It is **not** what stops a passing pointer from flashing
  a card. The 350ms open delay does that on its own, because the card never appears at all.
- **The card is not hoverable.** The pointer entering the card does not keep it alive.
  Nothing in the card is clickable, so travelling to it buys the user nothing.

### 5. What happens when the row moves

**The card closes.** It does not follow and it does not stay at a stale point.

Three triggers, all commanded from the Shell:

- **Resort.** `resort_epoch` already increments on every reorder
  (`crates/ui/src/shell.rs:3483`). Close whenever it changes while the card is open. This
  matters because `note_card_anchor` refreshes every frame, so without an explicit close the
  card would slide across the conversation for the whole 260ms glide.
- **Scroll.** `self.sidebar_scroll` is already tracked.
- **Any mouse-down on the row.** Left-click selects the Chat, right-click opens `chat_menu`.
  Two floating layers from one row at once is a bug a user would report. gpui's tooltip gets
  this for free (`div.rs:3481`, `:3490`); a `Popup` must be told.

### 6. The `.occlude()` trap

**The Note Card never overlaps the row or the hit zone, so the loop cannot start.**

The `crates/ui/src/shell.rs:3287` flicker was caused by an occluding element sitting on top of
the very row that drove the hover: the pill mounted, stole the pointer, the row un-hovered,
the pill unmounted, repeat. Decision 2 puts the card outside the sidebar entirely. This is a
second, independent reason the card must clear the sidebar horizontally rather than sit a few
pixels right of the bar.

The hit zone itself must **not** call `.occlude()`, for the same reason the corner does not.

**One precondition, and it is not free.** "Outside the sidebar" holds only while the card fits.
`menu_at` uses `snap_to_window_with_margin`, and that mode **shifts the card left** when it
overflows the right edge (`crates/gpui/src/elements/anchored.rs:190`). It does not clip. The
sidebar can be 400px wide (`SIDEBAR_MAX`), so a narrow enough window slides the card back over
the sidebar and possibly over the hit zone. That would restart the loop in slow motion: the
card occludes the hit zone, hover breaks, 120ms close, unmount, hover restores, 350ms reopen.
The implementer must clamp so this cannot happen. See the implementer notes.

### 7. The archived shelf

**One mechanism covers both paths. Nothing graduates from the fog.**

The card is rendered once, at the Shell's top level, so there is only one render site. The
shelf needs only the same bar and hit zone, which is a shared helper called from both
`Shell::render_chat_row` and the shelf's row builder in `crates/ui/src/shell/spaces.rs`.
`archived_hover` is untouched, exactly as `chat_status_hover` is.

### 8. The hit zone

**A transparent child at the row's left edge, 12px wide, full row height,** inside the
existing `px(Theme::SPACE_SM)` padding so no layout shifts.

Deliberately decoupled from the painted bar. Ticket `02` owns the bar's geometry and may pick
a short centred stub; a hit zone matched to a 3px by 16px stub would be unhittable. Ticket
`02` stays free to make the bar as quiet as it likes.

### Considered and rejected

**Moving the marker beside the loader.** Raised mid-grill, then withdrawn. Recorded because
the reasons are durable. `mini_gradient_spinner` is called with `cell_px = 2.0`
(`crates/ui/src/shell.rs:3438`), a 2x3 grid of 2px dots with 1px gaps
(`crates/ui/src/loaders.rs:158`), so it is **5px by 8px**. Against it: a chip that small is
not catchable while scanning a list, which is the marker's whole job; it would sit beside an
animated multi-coloured block of the same size and read as a stalled loader; the loader only
renders when the Chat is `Working` (`crates/ui/src/shell.rs:3434`), so the position is
undefined for most rows; and line 3's right end has no spare padding to grow a usable hit zone
into. The map's left-edge bar stands.

### Implementer notes

- Whether `.relative().top()` (`crates/ui/src/shell.rs:3499`) shifts an element's hitbox was
  **not** verified. It does not block anything: the resort close is commanded off
  `resort_epoch`, not inferred from a hover break. Worth confirming anyway.
- `menu_at` occludes (`crates/ui/src/popover.rs:554`). That is wanted here, because the card
  floats over the conversation area and clicks should not fall through it.
- The sidebar can be collapsed (`crates/ui/src/shell.rs:2841`, `open_width`). The card's X
  offset must be derived from the live width, not `SIDEBAR_DEFAULT`.
- **The card must never be allowed to cover the hit zone.** `snap_to_window_with_margin` will
  slide it left to fit, so cap the card's width against the space actually left of the window's
  right edge instead of letting the snap move it. If that space is too small to be usable,
  decide with ticket `04` whether the card flips to the sidebar's left or simply does not open.
  Ticket `04` owns the window-edge behaviour; this note only fixes the constraint it must meet.
