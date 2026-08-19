# 03 - Note Editor

**Spec:** [.scratch/chat-notes/spec.md](../../chat-notes/spec.md), §6 (The Note Editor) and
the editor items of §7 (Test set). The spec carries the full dialog table, the cap mechanism,
and the wiring hazard. Read them in full before starting.

**What to build:** the full authoring loop. The Chat's context menu gains one contextual
item - "Add note…" when the Chat has no note, "Edit note…" when it has one - directly under
Rename. It opens the "Session note" dialog: text field, slot row of five slot dots, and
buttons. The user writes, picks a Colour Slot, saves, and the resting marker appears on the
row. Delete and clear-the-text-and-save both remove the note, with no confirmation.

Note: `ComposerInput::set_max_chars` and `set_max_content_height` exist only as prototype
code, not on `main`. Port or reimplement them as part of this ticket - the cap must clamp
inside the input's single text-entry function so typing, IME commit, and paste all funnel
through one clamp.

**Blocked by:** 01 - Chat Note model and write path, 02 - Colour Slots and the resting
marker. Runs in parallel with 04.

**Status:** done - `8ed9616 feat(ui): the Note Editor - author a Chat Note from the chat menu`

- [x] The menu item is contextual, positioned under Rename and above Archive, with the icon
      the spec names
- [x] The dialog matches the spec §6 table: title, order, field growth 3 to 6 lines,
      placeholder, 14px slot dots in 24px hit targets, ring on the selected slot, late
      counter (hidden until 240), Delete far left and absent when there is no note, Save
      never disabled
- [x] The 280-character cap is blocked where text enters; the clamp test passes (characters
      not bytes, room measured after the deletion, cut on a character boundary)
- [x] Enter saves, Shift+Enter makes a newline, Escape discards with no prompt - and Escape
      is explicitly re-verified, because the input binds escape to a mention action
- [x] Focus lands in the field on open, caret at the end, nothing selected
- [x] A new note starts on `rose`; editing shows the stored slot ringed
- [x] Delete and clear-and-save produce the same write (trim; empty sends null) and neither
      asks for confirmation
- [x] End to end: add a note from the menu, see the bar appear; edit its colour, see the bar
      repaint; delete it, see the bar vanish

## Closing notes

- The build session could not see the app: macOS blocked screen capture for the host, and
  synthetic input reached the wrong window. The eye pass and the interactive keys were
  checked by the user in the running app instead. Reopen the two key rows if that pass was
  narrower than it looked.
- The character cap needed `ComposerInput::set_max_chars` and `set_max_content_height`, which
  existed only on `prototype/chat-note-dialog`. Both are now product code, plus
  `popover::DIALOG_FIELD_PAD_Y` so the three-line floor stops copying the field's padding.
- Also added, in the shell's existing idiom: `ZERON_OPEN_DIALOG=note` opens the dialog for
  the first chat, next to the `rename` and `delete` capture knobs.
- Follow-up raised by the user and NOT in this ticket: a double click inside a text input
  does nothing anywhere in the app (`ComposerInput::on_mouse_down` never reads
  `event.click_count`). The user takes that on separately, app-wide.
- Demo for a later pass: `ZERON_OPEN_DIALOG=note .scratch/chat-notes-impl/note-editor-demo.sh
  dark`, with `.scratch/chat-notes-impl/chats.sh` to read back what the engine stored.
