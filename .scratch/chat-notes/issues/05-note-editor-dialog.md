# 05 - The note editor dialog

Map: [Chat Notes in the sidebar](../map.md)
Type: prototype
Status: closed
Assignee: Beka Demuradze
Blocked by: 01, 02
Prototype: `prototype/chat-note-dialog`, `scripts/proto-note-dialog.sh`

## Question

What does the note dialog look like, and how does it behave?

Model it on Rename, which is the proven pattern: `Shell::open_rename_chat`
(`crates/ui/src/shell.rs:1990`), `submit_rename_chat` (`:2016`), and the dialog primitives
`dialog_card`, `dialog_title`, `dialog_field`, `btn_primary`, `btn_danger`
(`crates/ui/src/popover.rs:876`, `:891`, `:910`, `:947`, `:962`). Answer:

1. **The context menu entry.** One item whose label changes between "Add note" and
   "Edit note", or a fixed label? Where does it sit relative to Rename and Archive
   (`crates/ui/src/shell.rs:4396`)?
2. **Layout.** Multi-line text field, the row of five swatches, and the buttons. What is the
   order, and how is the selected swatch marked?
3. **The character cap.** About 280. Does the field block further typing, or show a counter,
   or both? When does the counter appear?
4. **Delete.** A Delete button plus the clear-the-text path both remove the note. Confirm the
   two agree, and decide whether Delete asks for confirmation.
5. **The default colour** for a new note, and whether the swatch row shows which colour is
   already in use when editing.
6. **Submit and cancel.** Keys, focus on open, and what happens on Escape with unsaved text.

Uses the model from `01` and the swatch colours from `02`. Link the prototype branch.

## Resolution

Prototype: branch `prototype/chat-note-dialog`, run with `scripts/proto-note-dialog.sh dark`.
It is built on ticket 04's branch, so the dialog was judged by what it does to the resolved
marker and the resolved Note Card: a save repaints both under the dialog. The seed `A11`
reproduces the resolved dialog. Every candidate that lost still cycles from the pill.

The notes are **mutable** in this prototype. Ticket 04 read a fixed per-slot fixture; the store
in `note_bar_prototype` now stands in for the registry doc plus the `WatchChats` frame, so a
save, a colour change and a delete all land where the list can show them.

### The resolved dialog

| | |
| --- | --- |
| title | **"Session note"** |
| order | title → **text field** → **slot row** → buttons |
| field | floors at **3 wrapped lines**, grows to **6**, then scrolls. 14px, the dialog-field frame |
| placeholder | **"Write a note about this session…"** |
| slot row | five **14px circles**, 6px apart, each in a 24px hit target |
| selected slot | a **1px ring** in `theme.text` at 0.85, one 24px cell around the dot |
| counter | **on the slot row, pushed right**. Hidden until 240, muted, `theme.text` at 280 |
| buttons | `justify_between`: **Delete far left**, `Cancel` and `Save` right |
| cap | **280 characters**, blocked where text enters |
| keys | **Enter** saves, **Shift+Enter** makes a newline, **Escape** discards |
| width | 360px, unchanged from `popover::dialog_card` |

### 1. The menu entry - contextual, under Rename

**One item whose label changes**: "Add note…" with no note, "Edit note…" with one. It sits
**directly under `Rename…`**, above `Archive`, and carries `icons::PEN_NEW_SQUARE`.

A fixed label was rejected for a reason specific to this feature. The note is **pointer-only**
([03], [04]), so nothing on screen says a Chat has a note except a 3px mark. The menu label is
the one place the shell can state it in words. A fixed "Note…" throws that away for nothing.

The position follows the menu's existing grouping. `Rename…` and the note both change what the
Chat *says about itself*. `Archive` and `Delete…` move or destroy the Chat. The note belongs
with the first pair, and the separator above `Delete…` already marks the boundary.

`icons::TAG` was rejected. The glossary rules "tag" out as a mental model for a Colour Slot,
and an icon teaches a mental model as readily as a word does.

### 2. Layout - text first, and the selected slot takes a ring

**Order: title, field, slot row, buttons.** The text is the payload, so it comes first and
takes the focus. The colour is a decoration on it ([02] settled that the five carry no system
meaning), so it follows the thing it decorates.

**Delete sits far left on the button row**, with `Cancel` and `Save` right. This keeps the
shell's existing right-aligned Cancel-plus-primary pair exactly as Rename and Delete-session
have it, and puts the destructive action where it cannot be hit by someone aiming for Save.
**Delete is absent entirely on a Chat with no note**, so the left side of a new note's button
row is simply empty.

**The selected slot takes a 1px ring** in `theme.text` at 0.85, held one 24px cell clear of the
dot. The check glyph and the grow-and-dim variants were both built and cycled. The check is
louder than the colours it marks, and [02] chose those colours to be quiet on purpose.
Grow-and-dim reads as a hover state rather than a selection, and it makes the row jitter as the
choice moves along it. The ring adds the least ink that still says "this one".

**The dot is a 14px circle**, not the marker's own stub. The stub echo was built and rejected:
the marker is 3px wide because it must be quiet in a dense list, and a picker is a thing you
aim at. Repeating the marker's geometry borrows the wrong constraint. Every shape sits in a
**24px hit target** regardless, so the choice was made on how the row reads, not on how hard it
is to click.

### 3. The cap - 280 exactly, blocked at the source, with a late counter

**280 characters**, which fixes charting's "about 280" as a number the spec can state.

**The keystroke is refused where text enters.** `ComposerInput` gained a `max_chars`, clamped
inside `replace_text_in_range`. Every input path funnels through that one function - typing, an
IME commit, `Shift+Enter`, and paste - so one clamp covers all of them **and the caret never
has to be put back**. The alternative was to truncate on the `Edited` event, which rewrites the
content after the user has already typed into it and then has to restore the selection. That
fights the caret on every keystroke at the ceiling.

Three properties of the clamp are not judgeable by eye, so they carry a test
(`the_character_cap_clamps_by_character_and_measures_room_after_the_deletion`,
`crates/ui/src/composer.rs`):

- **Characters, not bytes.** "280" must mean the same for an emoji as for an `a`.
- **Room is measured after the deletion.** A field sitting at 280 still accepts a paste over a
  selection. Measuring before it would freeze a full field completely.
- **The cut lands on a character boundary**, so a clamped paste can never split one.

**The counter shows both, late.** It appears at **240**, the last forty characters, in
`theme.text_muted`, and turns to `theme.text` at 280. A counter that is always on is a
permanent tally over a field most people fill to thirty characters. **It sits on the slot row,
pushed right**, whose right half is empty anyway, so it costs no new row and stays beside the
field it counts. The in-field variant was built and rejected: it appears exactly when the text
has grown enough to run under it, so it needs its own opaque plate to stay readable, and that
plate covers the text at the moment the user is fighting the limit.

**One accepted limit.** IME composition can exceed 280 while it is uncommitted; the commit
truncates. Only the commit path is clamped, because marked text is not yet text and clamping it
would fight the input method. This belongs in the spec's known limits.

### 4. Delete - no confirmation, and the two paths agree

**Delete does not ask.** The Delete button and the clear-the-text-and-save path do exactly the
same thing, and **the confirm is what would make them disagree**: one path would prompt and the
other would not, for the same outcome on the same note.

`Delete…` on a Chat earns its confirm because it destroys a transcript that cannot be retyped.
A note is one short text under a 280-character cap. The costs are not comparable, and this
shell should not spend the same ceremony on both.

**Both paths are the same write.** The dialog trims the text; empty text sends `note: null`.
This is [01]'s rule, and [01] also put a guard in the engine so no future caller can write a
blank note that renders as an invisible bar.

### 5. The default slot, and the row on open

**A new note starts on `rose`**, the first slot, already selected when the dialog opens.
[01] made colour required precisely so a colourless note cannot exist, and the marker is the
only way a note shows at rest, so the dialog must arrive with a slot already chosen.

Deriving the slot from a hash of the chat id was rejected. Two notes written the same way would
come out different colours for a reason the user cannot see or predict.

**Editing shows the stored slot as selected**, which is what makes the ring do a second job: it
tells you the note's current colour before you change anything.

### 6. Submit, focus, and cancel

**Enter saves. Shift+Enter makes a newline.** This is the composer's own contract, already
bound in the `Composer` key context, so the dialog adds no keymap. A multi-line field argues
for the opposite pairing, but the note is one short text, not a document, and a user who has
just used the composer has the habit already.

**Focus lands in the field on open, caret at the end, nothing selected.** `set_text` does this
already. Select-all was rejected: it would make one keystroke wipe an existing note.

**Escape discards with no prompt**, exactly as Rename does. This was the one inherited default
rather than a chosen one, so it was put to the user explicitly and confirmed. It was also the
one checklist item that could have silently failed - the input binds `escape` to a mention
action - and it was **verified working in the prototype**.

**Save is never disabled.** This shell has no disabled-button primitive, and inventing one for
a state the user reaches only by accident would spread a new pattern across every dialog.

### The word "swatch" is out

The ticket asked about "the row of five swatches". `CONTEXT.md` lists **Swatch** under
_Avoid_ for **Colour Slot**. The spec says **slot row** for the control and **slot dot** for
one cell. The concept stays **Colour Slot**.

### Artifacts written

- Branch `prototype/chat-note-dialog`, commit `8a81722`, plus
  `scripts/proto-note-dialog.sh`.
- [CONTEXT.md](../../../CONTEXT.md): **Note Editor** is a new term.
- `ComposerInput::set_max_chars` and `set_max_content_height` are the two mechanisms the spec
  hands the implementer. Neither exists on `main`; both are prototype code.

### Fixed in passing

Ticket 02's contrast reproducer, `cargo test -p zeron-ui --lib dump_note_bar_contrast`, had
stopped compiling on `prototype/chat-note-card` for a missing `Theme` import. [06] quotes those
numbers, so the command that produces them has to run. It runs on this branch. **The card
branch is still broken**, so [06] should take the numbers from here.

### Fog cleared

None, and none was left. The map's **Not yet specified** already read "Nothing". This ticket
adds no new question and invalidates no other ticket.

**[06 - Write the spec](./06-write-the-spec.md) is now the only open ticket**, and every one of
its blockers is closed. The map has no decisions left in it.

[01]: `./01-note-data-model-and-write-path.md`
[02]: `./02-resting-marker-and-colour-set.md`
[03]: `./03-hover-card-lifecycle.md`
[04]: `./04-hover-card-appearance.md`
[06]: `./06-write-the-spec.md`
