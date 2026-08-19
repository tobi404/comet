//! The Chat Note's **resting marker**: the small colour bar a Chat wears in
//! the sidebar when it has a note.
//!
//! One helper serves both row builders — [`super::Shell::render_chat_row`] for
//! the active list and the inline rows of the archived shelf
//! (`super::spaces::render_archived_section`) — because two copies of a 3px
//! stub drift apart the first time either row's padding moves.
//!
//! The bar is the note's only sign at rest. It is not the hover target (the
//! whole row is), which is what lets it stay this small. Its colour comes from
//! the theme, and the numbers behind that colour are pinned in
//! `crate::theme`'s `dump_note_bar_contrast`.

use gpui::prelude::*;
use gpui::{AnyElement, div, px};
use zeron_proto::ChatNote;

/// Bar width. A hair under the 4px that read as a stripe, a hair over the 2px
/// that read as an artefact.
const WIDTH: f32 = 3.0;

/// Bar height. Well inside the 61px active row and the 36px archived row, so
/// one stub centres in both without touching either row's corner radius.
const HEIGHT: f32 = 18.0;

/// Distance from the row's left edge. Both rows pad further than this (the
/// active row by `Theme::SPACE_SM`, the archived row by 10px), so the bar sits
/// INSIDE the padding either way: it costs no layout, and a Chat without a
/// note renders exactly as it did before notes existed.
const INSET: f32 = 2.0;

/// The resting marker for a Chat, or `None` when the Chat has no note.
///
/// An overlay, not a column. Append it as the row's LAST child: it is a child
/// of the row, so it paints over the row's own hover and selected washes — the
/// contrast numbers in `crate::theme`'s reproducer measure it that way. The
/// row must be positioned (`.relative()`) for the overlay to anchor to it.
///
/// The bar carries no id and no listener, so it never takes the pointer off
/// the row underneath it.
pub(super) fn note_bar(note: Option<&ChatNote>) -> Option<AnyElement> {
    let colour = crate::theme::note_slot_color(&note?.color);
    Some(
        div()
            .absolute()
            .left(px(INSET))
            .top_0()
            .bottom_0()
            .flex()
            .items_center()
            .child(
                div()
                    .w(px(WIDTH))
                    .h(px(HEIGHT))
                    // Fully rounded: at 3px wide this is a 1.5px radius, so
                    // the stub reads as a tick rather than a cut edge.
                    .rounded_full()
                    .bg(colour),
            )
            .into_any_element(),
    )
}
