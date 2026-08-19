# 04 - Note Card on hover

**Spec:** [.scratch/chat-notes/spec.md](../../chat-notes/spec.md), §5 (The Note Card) and the
card items of §7 (Test set). The spec carries the mechanism, the state shape, every commanded
close, the appearance table, and the narrow-window rule. Read it in full before starting -
§5 is the largest section of the spec and all of it is this ticket.

**What to build:** rest the pointer anywhere on a sidebar row that has a note, and after
350ms a floating card opens alongside the sidebar - tinted with the note's colour, centred on
the row, sized to its content - showing the note text in full. It closes 120ms after the
pointer leaves the row, and immediately on list resort, sidebar scroll, or any mouse-down. A
click keeps it dismissed until the pointer leaves that row. The card never opens while a
context menu or dialog is up, never scrolls, clamps at 10 lines, and in a narrow window
shrinks to the room available or does not open at all. The archived shelf gets the same
behaviour through the same single render site.

The state shape from the spec came out of a prototype and encodes the design precisely, so it
is worth carrying:

```rust
note_card: popover::Popup<NoteCard>,           // the visible card plus its exit phase
note_card_wait: Option<NoteCardWait>,          // { chat, generation, _task } - the 350ms open delay
note_card_leave: Option<Task<()>>,             // the 120ms close delay; cancel by dropping
note_card_anchor: Option<(String, Bounds<Pixels>)>,  // hovered row bounds, captured per frame
```

**Blocked by:** 01 - Chat Note model and write path, 02 - Colour Slots and the resting
marker. Runs in parallel with 03.

**Status:** ready-for-agent

- [ ] The card renders from the Shell's top-level overlay pass, never inside a row (the
      sidebar's scroll clip makes a row-mounted card impossible - spec §5)
- [ ] The whole row is the trigger, as a new branch in the row's existing hover listener; the
      existing hover fields for the Archive pill and the shelf are untouched
- [ ] 350ms open, 120ms close; the card itself is not hoverable
- [ ] Appearance matches the spec §5 table: 0.10 tint plus 0.32 hairline in the note's
      colour, live-sidebar-width + 8px anchor, centred on the row and clamped 8px from the
      window edges, 320px max sized to content, 13px on 19px, 10-line clamp with elide,
      menu-in/out motion with the 10px arrival offset
- [ ] All commanded closes work: resort epoch, sidebar scroll, any mouse-down, plus the
      click-dismiss latch that lifts only when the pointer leaves the row
- [ ] The trigger stands down while the context menu, rename, delete confirmation, or Note
      Editor is open
- [ ] Narrow window: the card's width is capped against the room actually available and it
      never gets moved by the anchor snap; below the floor it does not open. Measure the real
      crossing width where 280 characters fit in 10 lines and raise the floor to it if
      comfortable - never raise the clamp (spec §5 and known limit 2)
- [ ] The 671-character fixture elides cleanly; the URL fixture clips rather than widening
      the card
- [ ] The archived shelf opens the same card through the same render site
