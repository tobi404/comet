# 07 - Write the spec

Map: [Chat Notes on iOS](../map.md)
Type: task
Status: open
Blocked by: 01 (resolved), 02 (resolved), 03 (resolved), 04 (resolved), 05 (resolved),
            06 (resolved), 08

## Question

Write the destination document at `.scratch/chat-notes-ios/spec.md`.

This is the one ticket on this map that produces a deliverable rather than a decision. It is the
map's execution override, and it is deliberately last.

The desktop spec at [.scratch/chat-notes/spec.md](../../chat-notes/spec.md) is the model for
shape and for standard. Match it:

- **Self-contained.** An implementation session should need only the spec, the glossary at
  [CONTEXT.md](../../../CONTEXT.md), and the ADR at
  [docs/adr/0001-chat-notes-sync-in-the-registry-doc.md](../../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md).
  It should not need to read this map or any ticket.
- **End state only.** Not a history of what was considered. Where a judgement call remains, name
  it explicitly as one.
- **Every value resolved.** Real numbers, real colours, real file and line references.
- **Known limits carried in full**, each stated as a decision and not as a defect. The desktop's
  known limit 6 becomes this build's central constraint and should be restated from the phone's
  side: the phone writes registry rows directly, so its own editor is the only cap there is.
- **Stated costs, not only limits.** [02](./02-character-cap-in-a-swiftui-editor.md) leaves the
  app with two text-editing stacks: the composer on `TextEditor`, the Note Editor on a
  `UIViewRepresentable`. That is a real maintenance cost and the spec should write it down rather
  than let a future reader find it.
- **A test set**, each entry earning its place. [02](./02-character-cap-in-a-swiftui-editor.md)
  already fixes three of them: characters-not-bytes and room-after-the-deletion carry as tests,
  and the boundary property carries as a code comment instead, because `String.prefix(_:)` makes
  it impossible to fail.
- **The Out of scope list carried verbatim** from the map.

Two things to settle while writing, not before:

1. **Whether the desktop spec needs an amendment.** If any ticket found that the desktop's
   stated contract is wrong or incomplete - not merely silent on iOS - say so in the answer.
   Changing the desktop is out of scope for this effort, so this is a report, not a fix.

2. **Whether the glossary needs a new term.** The reveal `05` chose may have no name in
   [CONTEXT.md](../../../CONTEXT.md) yet. If it does not, call the Skill tool with
   `domain-modeling` and add it. The existing terms - Chat Note, Colour Slot, Note Card, Note
   Editor - were written to be platform-neutral, so prefer stretching one over minting a rival.
