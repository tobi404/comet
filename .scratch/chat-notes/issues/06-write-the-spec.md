# 06 - Write the spec

Map: [Chat Notes in the sidebar](../map.md)
Type: task
Status: closed
Assignee: Beka Demuradze
Blocked by: 01, 02, 03, 04, 05

## Question

Nothing is left to decide. This ticket writes the destination document.

Assemble every resolved answer into one spec at `.scratch/chat-notes/spec.md`, sized for an
implementation session that has not read this map. It must carry:

- The model and the write path, end to end, with the exact file and function names to touch.
- The exact colour values, per theme, with their contrast numbers.
- The marker geometry and the empty-state rule.
- The card mechanism, lifecycle, anchor, and appearance.
- The dialog layout and behaviour.
- The known limit: the note is **pointer-only** - the whole row is the trigger since
  [04](./04-hover-card-appearance.md), and there is no keyboard or command path. The note text
  is otherwise reachable only through the context-menu dialog.
- The second known limit, from [04](./04-hover-card-appearance.md): near the 200px narrow-window
  floor, a note inside the 280-character cap can exceed the card's 10-line clamp and elide.
  Carry the instruction to measure the real crossing width and raise the floor rather than the
  clamp.
- The Out of scope list from the map, copied verbatim, so the implementer does not widen it.

The map is complete when this ticket closes.

## Resolution

Written: [.scratch/chat-notes/spec.md](../spec.md), self-contained for an implementation
session that has not read this map. It carries everything the question lists, plus the four
further limits the closed tickets marked "belongs in the spec's known limits": the two
light-mode contrast acceptances from [02](./02-resting-marker-and-colour-set.md), the IME
composition overshoot from [05](./05-note-editor-dialog.md), and [01]'s
cap-is-an-affordance rule - six known limits in all. Superseded values (the 12px hit zone,
250ms, the full-height bar) are absent; only the end state is specified. The contrast
reproducer is cited on `prototype/chat-note-dialog`, the one branch where it compiles, per
[05]'s "Fixed in passing". `ComposerInput::set_max_chars` and `set_max_content_height` are
flagged as prototype-only code.

The map is complete. No tickets remain open.

[01]: ./01-note-data-model-and-write-path.md
[05]: ./05-note-editor-dialog.md
