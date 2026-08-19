# Chat Notes on iOS - the build

The implementation tickets for [chat-notes-ios/spec.md](../chat-notes-ios/spec.md).

**The spec is not here.** It lives with the planning effort that produced it, at
`.scratch/chat-notes-ios/spec.md`, beside the map and the nine wayfinder tickets that answered its
questions. This directory holds only the build, so the two kinds of ticket do not share a numbering
sequence. An implementer needs the spec, [CONTEXT.md](../../CONTEXT.md) and the
[ADR](../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md) - and nothing from the map.

## The order

```
01 the note on the wire ─┐
                         ├─→ 03 the resting marker ─→ 04 the long press ─→ 05 the Note Editor ─→ 06 the rotor
02 the Colour Slots ─────┘                                                      ↑
                                                                          01 also gates 05
```

| # | ticket | blocked by | on screen after it |
| --- | --- | --- | --- |
| [01](./issues/01-the-note-on-the-wire-and-in-demo-mode.md) | The note on the wire, and in demo mode | none | nothing yet |
| [02](./issues/02-the-five-colour-slots.md) | The five Colour Slots | none | nothing yet |
| [03](./issues/03-the-resting-marker-on-both-row-shapes.md) | The resting marker on both row shapes | 01, 02 | **a note is visible, and audible** |
| [04](./issues/04-the-long-press-the-note-card-and-the-menu.md) | The long press: the Note Card and the menu | 03 | a note can be **read in full and cleared** |
| [05](./issues/05-the-note-editor-sheet.md) | The Note Editor sheet | 04, 01 | a note can be **written** |
| [06](./issues/06-the-rotor-the-rows-custom-actions.md) | The rotor: the row's custom actions | 05 | a note can be written **without sight** |

**01 and 02 are independent of each other** and can run in parallel. Everything after 03 is a chain.

## What each ticket already knows

Every ticket carries the traps its section of the spec found by building, not by reading - the
delegate label that compiles and never fires, the font that measures without scaling, the preview
that will not size itself, the platter that owns the corner, and the rotor order that cannot be
chosen. They are in each ticket's notes, above the acceptance criteria, because each one costs real
time and none is visible in the code that has it wrong.
