# zeron

A multi-device controller for coding agents. One Rust engine holds the state, one or more
gpui viewports render it, and optional sync carries the state between devices as Loro CRDT
documents.

## Language

**Chat**:
One conversation with a coding agent, owned by a device and belonging to a space. It is the
entity behind a sidebar row.
_Avoid_: Thread, session, conversation

**Session**:
The live run state of a Chat's agent process. A Chat has at most one Session, and the
Session is what makes a Chat look busy.
_Avoid_: Run, process

**Chat Note**:
A short piece of text the user writes about a Chat, with one Colour Slot. It is a label the
user authors, not something the agent produces. Text and colour are one indivisible value: a
Chat has a whole note or no note, never half of one. A note is **cleared**, never deleted:
removal takes the whole value away and leaves the Chat untouched. Product copy may still read
"Delete note", because a user reads that word first.
_Avoid_: Sticky note, sticky, annotation, comment, memo; deleting a note (in code or model)

**Colour Slot**:
One position in the fixed set of colours a Chat Note can carry. A slot keeps its identity when
its shade is re-tuned, so a note refers to the slot rather than to the colour itself. The
slots are decorative and carry no system meaning.
_Avoid_: Swatch, tag, label colour, category

**Note Card**:
The floating surface that shows a Chat Note in full. It is named for what it shows, not for
what opens it, because the pointer may not stay the only trigger.
_Avoid_: Hover card, tooltip, popover, preview

**Note Editor**:
The dialog where the user writes a Chat Note and picks its Colour Slot. It is the only place a
note can be authored, and it is reached from the Chat's context menu.
_Avoid_: Note modal, note popup, swatch picker, colour picker

**Chat Indicator**:
The derived attention state of a Chat, computed from its Session and never stored.
_Avoid_: Status, state
