//! The **Note Editor**: the "Session note" dialog the Chat's context menu
//! opens, and the only way a Chat Note is authored.
//!
//! Modelled on the row's Rename dialog ([`Shell::open_rename_chat`]), which is
//! the proven dialog pattern in this shell: the same `popover::dialog_card`
//! frame, the same `ComposerInput`, the same focus-on-first-paint, the same
//! Escape-discards. It adds two things Rename has no need for — a Colour Slot
//! picker, and a 280-character cap blocked where text enters
//! (`ComposerInput::set_max_chars`).
//!
//! The write goes through [`Shell::mutate`] as one `setChatNote` op and waits
//! for the next `WatchChats` frame; there is no optimistic local echo, exactly
//! as `renameChat` and `setChatArchived` do. The dialog closes on save, so
//! nothing on screen is waiting for the round trip.
//!
//! Delete asks for no confirmation, and that is a decision, not an omission:
//! the Delete button and clearing the text and saving are the SAME write —
//! both go through [`Shell::commit_note`], and trimmed-empty text clears — so
//! a confirmation on one of them would make the two disagree.

use gpui::{Focusable, MouseButton, Size};

use super::*;
use crate::composer::INPUT_LINE_HEIGHT;
use crate::theme::{DEFAULT_NOTE_SLOT, note_slot_color, note_slot_ids};
use zeron_proto::ChatNote;

/// The authoring cap, exactly. It is an affordance and not an invariant:
/// storage cannot promise it, because iOS writes registry rows directly and
/// never passes the Mutate RPC (`docs/adr/0001-chat-notes-sync-in-the-registry-
/// doc.md`). Every renderer still handles a longer note.
///
/// `pub(super)` for one reader: the Note Card's narrow-window floor is sized to
/// hold exactly this many characters inside its ten-line clamp, and a copy of
/// the number there would let the floor go stale the day this one moves.
pub(super) const MAX_CHARS: usize = 280;

/// The counter stays hidden until the last 40 characters. A field most people
/// fill to thirty characters does not need a permanent tally.
const COUNTER_FROM: usize = MAX_CHARS - 40;

/// Floor and ceiling for the text box, in wrapped lines. Three says "write a
/// sentence or two" where one would say "put a title here". Six is above
/// almost every real note, so the dialog stops growing before it gets tall.
const MIN_LINES: f32 = 3.0;
const MAX_LINES: f32 = 6.0;

const PLACEHOLDER: &str = "Write a note about this session…";

/// The open dialog. One per shell; the menu that opens it closes first.
pub(super) struct NoteEditor {
    chat_id: String,
    input: Entity<ComposerInput>,
    /// The Colour Slot the note would take. Committed only on save, so
    /// cancelling a colour change discards it with everything else.
    slot: SharedString,
    /// Whether the Chat had a note when the dialog opened. Decides whether
    /// Delete is on screen at all.
    had_note: bool,
    /// Focus the input on the dialog's first paint (opened without a window).
    focus_pending: bool,
    _events: Subscription,
}

/// The note a save writes, or `None` when it clears. The engine trims again —
/// this side is the affordance, that side is the guard.
fn note_write(text: &str, slot: &str) -> Option<ChatNote> {
    let text = text.trim();
    (!text.is_empty()).then(|| ChatNote {
        text: text.to_string(),
        color: slot.to_string(),
    })
}

/// The `setChatNote` mutate op. `note: null` clears; the field is never
/// omitted, because an omitted field is a deserialisation error on the engine
/// side by design (`docs/adr/0001-chat-notes-sync-in-the-registry-doc.md`).
fn mutate_payload(chat_id: &str, note: Option<&ChatNote>) -> serde_json::Value {
    serde_json::json!({ "op": "setChatNote", "chatId": chat_id, "note": note })
}

/// The context-menu label for a Chat. The note is pointer-only, so this label
/// is the one place the shell says in words that a note exists.
pub(super) fn menu_label(has_note: bool) -> &'static str {
    if has_note {
        "Edit note…"
    } else {
        "Add note…"
    }
}

impl Shell {
    pub(super) fn open_note_editor(&mut self, chat_id: String, cx: &mut Context<Self>) {
        self.close_chat_menu(cx);

        let existing = self
            .state
            .read(cx)
            .chats
            .iter()
            .find(|c| c.id == chat_id)
            .and_then(|c| c.note.clone());
        let had_note = existing.is_some();
        let slot: SharedString = existing
            .as_ref()
            .map(|note| note.color.clone().into())
            .unwrap_or_else(|| DEFAULT_NOTE_SLOT.into());

        let input = cx.new(|cx| ComposerInput::new(PLACEHOLDER, cx));
        input.update(cx, |input, cx| {
            input.set_max_chars(MAX_CHARS);
            input.set_max_content_height(MAX_LINES * INPUT_LINE_HEIGHT);
            if let Some(existing) = &existing {
                // `set_text` leaves the caret at the end with nothing selected.
                // Select-all would make one keystroke wipe an existing note.
                input.set_text(existing.text.clone(), cx);
            }
        });
        let events = cx.subscribe(&input, |shell: &mut Shell, _, event, cx| match event {
            ComposerInputEvent::Submitted => shell.save_note(cx),
            // The counter reads the input's length, so it needs the repaint.
            ComposerInputEvent::Edited => cx.notify(),
            _ => {}
        });

        self.note_editor = Some(NoteEditor {
            chat_id,
            input,
            slot,
            had_note,
            focus_pending: true,
            _events: events,
        });
        cx.notify();
    }

    /// Enter and the Save button. Empty text deletes.
    fn save_note(&mut self, cx: &mut Context<Self>) {
        let Some(text) = self
            .note_editor
            .as_ref()
            .map(|dialog| dialog.input.read(cx).text().to_string())
        else {
            return;
        };
        self.commit_note(&text, cx);
    }

    /// The Delete button: the same write as saving an empty field, by
    /// construction rather than by promise.
    fn delete_note(&mut self, cx: &mut Context<Self>) {
        self.commit_note("", cx);
    }

    /// The one write the Note Editor makes. Closes the dialog either way; the
    /// marker repaints from the next `WatchChats` frame, not from here.
    fn commit_note(&mut self, text: &str, cx: &mut Context<Self>) {
        let Some(dialog) = self.note_editor.take() else {
            return;
        };
        let note = note_write(text, &dialog.slot);
        self.mutate(mutate_payload(&dialog.chat_id, note.as_ref()), cx);
        cx.notify();
    }

    /// Escape and Cancel. Discards with no prompt, exactly as Rename does.
    fn cancel_note_editor(&mut self, cx: &mut Context<Self>) {
        if self.note_editor.take().is_some() {
            cx.notify();
        }
    }

    fn pick_note_slot(&mut self, slot: SharedString, cx: &mut Context<Self>) {
        if let Some(dialog) = &mut self.note_editor {
            dialog.slot = slot;
            cx.notify();
        }
    }

    /// The dialog, rendered from [`Shell::render_overlays`] beside Rename's.
    pub(super) fn render_note_editor(
        &mut self,
        viewport: Size<Pixels>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        let theme = Theme::of(cx).clone();
        let dialog = self.note_editor.as_mut()?;
        if std::mem::take(&mut dialog.focus_pending) {
            window.focus(&dialog.input.focus_handle(cx), cx);
        }
        let input = dialog.input.clone();
        let selected = dialog.slot.clone();
        let had_note = dialog.had_note;
        let used = input.read(cx).char_count();
        let focus = input.focus_handle(cx);

        let field = popover::dialog_field(input.into_any_element())
            // The box is taller than one line, so the whole box has to take the
            // caret — clicking the empty space below the text must not be dead.
            .min_h(px(
                MIN_LINES * INPUT_LINE_HEIGHT + 2.0 * popover::DIALOG_FIELD_PAD_Y
            ))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |_, _, window, cx| {
                    window.focus(&focus, cx);
                    cx.notify();
                }),
            );

        let slot_row = div()
            .mt(px(12.0))
            .flex()
            .flex_row()
            .items_center()
            .justify_between()
            .child(
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .gap(px(6.0))
                    .children(
                        note_slot_ids()
                            .into_iter()
                            .map(|slot| slot_cell(slot, slot == selected.as_ref(), &theme, cx)),
                    ),
            )
            .children(counter(used, &theme));

        let buttons = div()
            .mt(px(16.0))
            .flex()
            .flex_row()
            .items_center()
            .justify_between()
            .child(
                // Only a note that exists can be deleted. On a new note the
                // left side is simply empty.
                div().children(had_note.then(|| {
                    popover::btn_ghost(&theme, "Delete", "note-editor-delete")
                        .id("note-editor-delete")
                        .text_color(theme.danger)
                        .on_click(cx.listener(|shell, _, _, cx| shell.delete_note(cx)))
                })),
            )
            .child(
                div()
                    .flex()
                    .flex_row()
                    .gap(px(8.0))
                    .child(
                        popover::btn_ghost(&theme, "Cancel", "note-editor-cancel")
                            .id("note-editor-cancel")
                            .on_click(cx.listener(|shell, _, _, cx| shell.cancel_note_editor(cx))),
                    )
                    .child(
                        popover::btn_primary(&theme, "Save")
                            .id("note-editor-save")
                            // Never disabled: an empty field is a delete, not
                            // an error, so Save always has something to do.
                            .on_click(cx.listener(|shell, _, _, cx| shell.save_note(cx))),
                    ),
            );

        let card = popover::dialog_card(&theme)
            // The input binds `escape` to its mention action, which propagates
            // when no mention popup is open — this is the one key in the dialog
            // that can silently fail, so it is worth reading twice.
            .on_key_down(cx.listener(|shell, ev: &gpui::KeyDownEvent, _, cx| {
                if ev.keystroke.key == "escape" {
                    shell.cancel_note_editor(cx);
                }
            }))
            // Product copy, resolved with the user: the dialog says "Session
            // note" where every identifier says Chat Note.
            .child(popover::dialog_title(&theme, "Session note"))
            .child(div().mt(px(12.0)).child(field))
            .child(slot_row)
            .child(buttons)
            .into_any_element();

        Some(popover::modal("note-editor-dialog", viewport, card))
    }
}

/// One cell of the slot row: a 14px dot centred in a 24px hit target, so a
/// small dot is still easy to aim at. The selected slot wears a hairline ring
/// held one cell out from the dot — quiet, and it puts no second shape inside
/// the dot.
fn slot_cell(
    slot: &'static str,
    selected: bool,
    theme: &Theme,
    cx: &mut Context<Shell>,
) -> AnyElement {
    div()
        .id(SharedString::from(format!("note-slot-{slot}")))
        .size(px(24.0))
        .flex()
        .items_center()
        .justify_center()
        .rounded_full()
        .cursor_pointer()
        .border_1()
        .border_color(if selected {
            theme.text.opacity(0.85)
        } else {
            gpui::transparent_black()
        })
        .on_click(cx.listener(move |shell, _, _, cx| shell.pick_note_slot(slot.into(), cx)))
        .child(
            div()
                .size(px(14.0))
                .rounded_full()
                .bg(note_slot_color(slot)),
        )
        .into_any_element()
}

/// `240/280` once the field is inside the last forty characters, going from
/// muted to full ink at the cap itself.
fn counter(used: usize, theme: &Theme) -> Option<gpui::Div> {
    if used < COUNTER_FROM {
        return None;
    }
    let tone = if used >= MAX_CHARS {
        theme.text
    } else {
        theme.text_muted
    };
    Some(
        div()
            .text_size(px(11.0))
            .text_color(tone)
            .child(SharedString::from(format!("{used}/{MAX_CHARS}"))),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Delete and clear-the-text-and-save are one write, which is what makes
    /// a confirmation on either path wrong: they could not disagree.
    #[test]
    fn delete_and_clear_and_save_make_the_same_write() {
        let cleared = mutate_payload("chat-1", note_write("   \n  ", "amber").as_ref());
        let deleted = mutate_payload("chat-1", note_write("", "amber").as_ref());
        assert_eq!(cleared, deleted);
        assert_eq!(
            deleted,
            serde_json::json!({ "op": "setChatNote", "chatId": "chat-1", "note": null })
        );
    }

    /// A saved note is trimmed and carries the slot id, never an index and
    /// never a colour.
    #[test]
    fn a_saved_note_is_trimmed_and_carries_the_slot_id() {
        assert_eq!(
            mutate_payload("chat-1", note_write("  ship it  ", "sky").as_ref()),
            serde_json::json!({
                "op": "setChatNote",
                "chatId": "chat-1",
                "note": { "text": "ship it", "color": "sky" },
            })
        );
    }

    /// The label is the only place the shell states a note exists without one
    /// being on screen.
    #[test]
    fn the_menu_label_says_which_of_the_two_jobs_it_does() {
        assert_eq!(menu_label(false), "Add note…");
        assert_eq!(menu_label(true), "Edit note…");
    }
}
