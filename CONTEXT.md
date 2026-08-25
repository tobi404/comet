<<<<<<< HEAD
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
The surface that shows a Chat Note in full. It is named for what it shows, not for what
opens it: the desktop floats it beside the row under a resting pointer, and iOS lifts it
into the row's own place under a long press.
_Avoid_: Hover card, tooltip, popover, preview (iOS builds one from a context-menu preview
API, but the surface is still the Note Card)

**Note Editor**:
The dialog where the user writes a Chat Note and picks its Colour Slot. It is the only place a
note can be authored, and it is reached from the Chat's context menu.
_Avoid_: Note modal, note popup, swatch picker, colour picker

**Chat Indicator**:
The derived attention state of a Chat, computed from its Session and never stored.
_Avoid_: Status, state
=======
# Domain context

## Theme vocabulary

- **Theme family** — A named collection of related theme variants that share an origin, such as Night Owl and Night Owl Light.
- **Theme variant** — One complete, resolved palette for a single appearance (`light` or `dark`). Runtime UI consumes variants, not source-format tokens.
- **Theme source** — The durable origin of a custom family: an imported snapshot, linked file, linked package, or editable native file.
- **Imported snapshot** — A self-contained copy of a compiled theme family. It no longer follows changes to its original source.
- **Linked theme** — A custom family that follows a source on disk and can be reloaded without re-importing it.
- **Linked file** — A link to one VS Code-compatible theme definition.
- **Linked package** — A link to a VS Code extension folder or `package.json` that declares one or more related theme variants.
- **Editable theme** — A duplicate stored as a native resolved-family JSON file. Users edit the file directly and explicitly reload it; invalid edits preserve the last known good family.
- **Last known good** — The most recent successfully compiled family retained by a linked theme when its current source is missing or invalid.
- **Import report** — A per-variant summary of mapped roles, fallbacks, unsupported values, and inferred decisions produced during compilation.
- **Mapping review** — The optional advanced view of an import report. Normal theme selection and import do not expose token names.
- **Theme hardening** — Deterministic post-mapping repairs that prefer stronger semantically related source colors, minimally adjust only shared Zeron roles when needed, and record every decision in the mapping review.
- **Theme default accent** — The interaction accent chosen or inferred for a theme variant by its authoring source.
- **Accent override** — A Zeron preset that replaces interaction roles only; syntax, terminal ANSI, diff, warning, error, and success colors remain owned by the theme.
- **Recommended surface treatment** — A theme variant's authored recommendation for whether its surfaces are frosted or opaque. It is used only when the user keeps the surface preference at theme default.
- **Surface preference** — A device-local choice of theme default, frosted, or opaque that is independent of appearance, theme, and accent selections.
- **Resolved surface treatment** — The effective frosted or opaque treatment produced by applying the surface preference to the active variant's recommendation.
>>>>>>> upstream/main
