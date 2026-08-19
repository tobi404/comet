# Map: Chat Notes in the sidebar

Label: `wayfinder:map`

## Destination

A written spec, handed to an implementation session, for a **Chat Note**: one short
user-authored text with one colour from a fixed set of five, stored on the Chat and synced,
shown in the desktop sidebar as a colour bar on the left edge of the row, and expanded into
a floating card on hover.

The spec is reached when every ticket below is resolved. The map is not the build.

## Notes

**Domain**: see [CONTEXT.md](../../CONTEXT.md). The entity is a **Chat**, not a thread. The
feature is a **Chat Note**. "Sticky note" may appear in prose that describes the look, never
in the model or the code.

**Skills every session should consult**: `grilling` and `domain-modeling` by default;
`prototype` for the tickets marked `Type: prototype`.

**Execution override**: this map plans, with one exception. The last ticket,
`06-write-the-spec`, writes the destination document. Every other ticket resolves a decision
and writes no product code.

### Settled while charting

These came out of the charting grill. They are the standing shape of the effort. A ticket may
sharpen them, but a ticket that wants to overturn one should say so out loud.

- **Storage is synced**, in the Loro registry doc, on the same path as `title` and `archived`.
  A note is about the Chat, not about one device's view of it.
- **The marker is a colour bar on the far left edge of the row.** ~~Full row height~~ -
  overturned by [02 - The resting marker](./issues/02-resting-marker-and-colour-set.md), which
  judged it against the real list and chose a short centred stub. The left edge itself stands.
  It is not
  next to the loader: the loader (`loaders::mini_gradient_spinner`) only renders when the Chat
  is `Working`, and it sits bottom-right of the row's third line
  (`crates/ui/src/shell.rs:3434`). The left edge is the only anchor that is stable in every
  state.
- **One note per Chat**, plain text, no title, no markdown, capped at about 280 characters.
- **The five colours are decorative.** They carry no system meaning and no naming.
- ~~**Hover the bar opens the card**~~, and it closes when the pointer leaves. ~~Hovering the
  whole
  row is not available: the row's top-right corner already swaps to an Archive pill on hover
  (`crates/ui/src/shell.rs:3193`).~~ **Overturned by
  [04 - The Note Card](./issues/04-hover-card-appearance.md)**: the whole row opens it, and the
  Archive pill is no obstacle because one hover listener can do three jobs as easily as two. A
  12px strip is a target you have to aim at, for a payload worth no aiming at all. The bar
  stays as the resting mark, which is all `02` ever made it. The "about 250ms" chosen here was
  **overturned by `03`**, which set 350ms to match the repo's existing hover-reveal delay.
- **The card floats rightward** over the conversation area. It never relayouts the list,
  which runs a FLIP resort glide. `03` found this is not a preference but a constraint: a
  card mounted inside a row is clipped by the sidebar's scroll region.
- **Authoring is a context-menu item plus a dialog**, matching Rename exactly
  (`Shell::open_rename_chat`, `crates/ui/src/shell.rs:1990`). The dialog holds the text field,
  the five swatches, and Delete. Clearing the text deletes the note.
- **The archived shelf shows the bar too.**
- **A note does not change the sidebar sort order.**
- **Hover-only is accepted for now.** The note text stays reachable through the context-menu
  dialog. The spec records this as a known limit.

### ADR

Written. [docs/adr/0001-chat-notes-sync-in-the-registry-doc.md](../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md)
records synced-versus-device-local storage together with the single-field encoding. It came out
of [01 - Chat Note data model and write path](./issues/01-note-data-model-and-write-path.md).

## Decisions so far

<!-- one line per resolved ticket -->

- [01 - Chat Note data model and write path](./issues/01-note-data-model-and-write-path.md) -
  a note is one indivisible `note: { text, color }` field on the Chat row in the registry doc
  only, colour is a required neutral slot id, one `setChatNote` op where `null` clears, and
  concurrent edits resolve to one whole note under LWW.
- [02 - The resting marker: geometry, empty state, and the five colours](./issues/02-resting-marker-and-colour-set.md) -
  a 3px by 18px fully-rounded stub, centred, inset 2px, overlaid inside the row's existing
  padding so bare rows are unchanged; five oklch hues 20/78/152/232/302 at L 0.660 C 0.112 dark
  and L 0.650 C 0.105 light, with slot ids `rose` `amber` `green` `sky` `violet`. Charting's
  full-height bar is overturned, and light markers sit under 3:1 by an accepted decision.
- [03 - Hover card lifecycle and mechanism](./issues/03-hover-card-lifecycle.md) - the
  **Note Card** is a `popover::Popup` drawn by `menu_at` from `Shell::render_overlays`, never
  inside a row, because `gpui::deferred` inherits the sidebar's scroll clip. It opens after
  350ms on a 12px transparent left-edge hit zone, closes after 120ms, is not hoverable, and is
  commanded closed on resort, scroll, and any mouse-down. One mechanism serves the active rows
  and the archived shelf.
- [04 - The Note Card: surface, anchor, size, motion](./issues/04-hover-card-appearance.md) -
  a tinted card carrying the note's colour at 0.10 with a 0.32 hairline, alongside the row at
  the live sidebar width plus 8px, centred on it, 320px maximum and sized to its content, 13px
  on 19px, clamped to 10 lines and elided, entering from the sidebar over `menu_in`. **The
  whole row is the trigger and the 12px hit zone is gone**, overturning charting and `03`'s
  decision 8. A click dismisses until the pointer leaves the row. In a narrow window the card
  clamps to the room available and, below 200px of it, does not open.

- [05 - The note editor dialog](./issues/05-note-editor-dialog.md) - one contextual menu item
  ("Add note…" / "Edit note…") under `Rename…`, opening a "Session note" dialog ordered title,
  field, slot row, buttons, with Delete far left and no confirmation because clear-and-save
  deletes too. A 3-line field growing to 6, five 14px slot dots with the chosen one ringed, a
  280-character cap refused at the keystroke, and a counter that appears only in the last 40.
  Enter saves, Shift+Enter breaks the line, Escape discards. A new note starts on `rose`.
- [06 - Write the spec](./issues/06-write-the-spec.md) - the destination document is written
  at [spec.md](./spec.md), self-contained, end-state only, with all six known limits and the
  Out of scope list carried verbatim. **The map is complete: no tickets remain open.**

## Not yet specified

<!--
  Cleared by 03: the card's survival during list movement (it closes, commanded off
  `resort_epoch` and the scroll handle) and the archived shelf's hover path (one render site
  at the Shell's top level serves both). Also cleared: whether the note needs a keyboard or
  command surface. That waited on 03, and 03 settled a pointer-only mechanism with no keyboard
  path, so the charting decision "Hover-only is accepted for now" stands unchanged and `06`
  records it as the known limit.
-->

Nothing. The map is complete.

## Out of scope

Ruled beyond this destination while charting. None of it graduates. Each would be a fresh
effort with a redrawn destination.

- **iOS rendering of the note.** The synced storage choice keeps this possible later. It is not
  built or specified here.
- **The tab strip and the conversation header.** The sidebar row is the only surface.
- **Filtering or grouping the sidebar by note colour.**
- **Searching note text.**
- **Pinning or reordering a Chat because it has a note.**
- **More than one note per Chat, markdown in a note, and attachments on a note.**
