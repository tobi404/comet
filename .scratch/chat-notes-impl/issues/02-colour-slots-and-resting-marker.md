# 02 - Colour Slots and the resting marker

**Spec:** [.scratch/chat-notes/spec.md](../../chat-notes/spec.md), §3 (The five colours) and
§4 (The resting marker). The spec carries the exact oklch triples, the geometry, and the
contrast tables. Read both sections in full before starting.

**What to build:** a Chat that has a note shows a small colour bar - a 3px by 18px fully
rounded stub, centred vertically, inset 2px from the row's left edge - in its Colour Slot's
colour, on active sidebar rows and on the archived shelf, in both themes. A row without a
note is pixel-identical to today: the stub is an overlay inside the row's existing padding,
and no width is reserved.

Demo: issue a `setChatNote` mutate (ticket 01's op) and watch the bar appear on the row,
including on a selected row, a hovered row, and an archived row.

**Blocked by:** 01 - Chat Note model and write path.

**Status:** ready-for-agent

- [ ] The five slot colours live in the theme as oklch triples resolved per theme at paint
      time (dark L 0.660 C 0.112, light L 0.650 C 0.105, hues 20/78/152/232/302), matching
      spec §3 exactly
- [ ] The stub matches spec §4 geometry and is an overlay: rows without a note are unchanged
      to the pixel
- [ ] The bar paints over the selected wash, not under it
- [ ] The archived shelf shows the bar through the same shared painting helper as the active
      rows
- [ ] A note does not change the sidebar sort order
- [ ] The contrast reproducer test compiles, runs, and reproduces the spec §3 tables (the
      accepted light-mode numbers under 3:1 are recorded as accepted, not "fixed")
