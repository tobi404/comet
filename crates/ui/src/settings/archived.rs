//! Settings → Archived (feature-inventory §1.5): archived chats across
//! devices, with Unarchive (Mutate setChatArchived false) and a page-level
//! Clear archived (Mutate clearArchivedChats — a permanent, all-device wipe
//! behind a confirm dialog).

use gpui::{
    AnyElement, Context, Entity, SharedString, Subscription, Task, Window, div, prelude::*, px,
};

use zeron_proto::Chat;
use zeron_rpc::methods;

use crate::popover;
use crate::state::AppState;
use crate::theme::Theme;

/// Archived rows in sidebar (recency) order. Pure.
pub fn archived_chats(chats: &[Chat]) -> Vec<&Chat> {
    chats.iter().filter(|c| c.archived).collect()
}

/// Whether the headline shows "Clear archived". Nothing archived → no action,
/// so the empty state stays a single centered message. Pure.
pub fn shows_clear_action(count: usize) -> bool {
    count > 0
}

/// Confirm-dialog body copy. Names the count, and says the delete reaches
/// every device — the list is cross-device. Pure.
pub fn clear_confirm_copy(count: usize) -> String {
    let sessions = if count == 1 { "session" } else { "sessions" };
    format!(
        "{count} archived {sessions} will be permanently deleted from all your devices. This can\u{2019}t be undone."
    )
}

pub struct ArchivedPage {
    state: Entity<AppState>,
    error: Option<SharedString>,
    /// Chat with an in-flight unarchive (button shows working state).
    busy: Option<String>,
    /// Row index under the pointer — drives the original's `group-hover`
    /// Unarchive reveal (`opacity-0 group-hover:opacity-100`).
    hovered: Option<usize>,
    /// Confirm dialog is open, holding the count it was opened with.
    confirm: Option<usize>,
    /// Clear-archived call is in flight (button shows a working state).
    clearing: bool,
    task: Option<Task<()>>,
    clear_task: Option<Task<()>>,
    _observe: Subscription,
}

impl ArchivedPage {
    pub fn new(state: Entity<AppState>, cx: &mut Context<Self>) -> Self {
        let observe = cx.observe(&state, |_, _, cx| cx.notify());
        Self {
            state,
            error: None,
            busy: None,
            hovered: None,
            confirm: None,
            clearing: false,
            task: None,
            clear_task: None,
            _observe: observe,
        }
    }

    fn unarchive(&mut self, chat_id: String, cx: &mut Context<Self>) {
        let Some(engine) = self.state.read(cx).engine().cloned() else {
            return;
        };
        self.busy = Some(chat_id.clone());
        self.error = None;
        let params = serde_json::json!({
            "op": "setChatArchived",
            "chatId": chat_id,
            "archived": false,
        });
        self.task = Some(cx.spawn(async move |this, cx| {
            let result = engine.client().call(methods::MUTATE, params).await;
            this.update(cx, |page, cx| {
                page.busy = None;
                if let Err(err) = result {
                    page.error = Some(format!("Unarchive failed: {err}").into());
                }
                cx.notify();
            })
            .ok();
        }));
        cx.notify();
    }

    /// One `clearArchivedChats` call: the engine tombstones every archived row
    /// in a single transaction, so the list empties as one update rather than
    /// draining row by row.
    fn clear_archived(&mut self, cx: &mut Context<Self>) {
        let Some(engine) = self.state.read(cx).engine().cloned() else {
            return;
        };
        self.confirm = None;
        self.clearing = true;
        self.error = None;
        let params = serde_json::json!({ "op": "clearArchivedChats" });
        self.clear_task = Some(cx.spawn(async move |this, cx| {
            let result = engine.client().call(methods::MUTATE, params).await;
            this.update(cx, |page, cx| {
                page.clearing = false;
                if let Err(err) = result {
                    page.error = Some(format!("Clear archived failed: {err}").into());
                }
                cx.notify();
            })
            .ok();
        }));
        cx.notify();
    }

    /// Headline action. Danger-toned but quiet — it sits next to a page title,
    /// not inside the dialog it opens.
    fn render_clear_button(&mut self, cx: &mut Context<Self>) -> AnyElement {
        let theme = Theme::of(cx).clone();
        let clearing = self.clearing;
        div()
            .id("clear-archived")
            .flex()
            .flex_row()
            .items_center()
            .gap(px(6.0))
            .px(px(10.0))
            .py(px(4.0))
            .rounded(px(6.0))
            .border_1()
            .border_color(theme.border)
            .text_size(px(12.0))
            .text_color(theme.danger_strong)
            .when(clearing, |el| el.opacity(0.4))
            .cursor_pointer()
            .hover(|s| s.bg(theme.surface_raised))
            .on_click(cx.listener(|this, _, _, cx| {
                if this.clearing {
                    return;
                }
                this.confirm = Some(archived_chats(&this.state.read(cx).chats).len());
                cx.notify();
            }))
            .child(SharedString::from(if clearing {
                "Clearing\u{2026}"
            } else {
                "Clear archived"
            }))
            .into_any_element()
    }

    fn render_confirm_dialog(
        &mut self,
        viewport: gpui::Size<gpui::Pixels>,
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        let theme = Theme::of(cx).clone();
        let count = *self.confirm.as_ref()?;
        let card = popover::dialog_card(&theme)
            .child(popover::dialog_title(&theme, "Clear archived sessions?"))
            .child(
                div()
                    .mt(px(6.0))
                    .child(popover::dialog_body(&theme, clear_confirm_copy(count))),
            )
            .child(
                div()
                    .mt(px(16.0))
                    .flex()
                    .flex_row()
                    .justify_end()
                    .gap(px(8.0))
                    .child(
                        popover::btn_ghost(&theme, "Cancel", "clear-archived-cancel")
                            .id("clear-archived-cancel")
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.confirm = None;
                                cx.notify();
                            })),
                    )
                    .child(
                        popover::btn_danger(&theme, "Clear archived")
                            .id("clear-archived-confirm")
                            .on_click(cx.listener(|this, _, _, cx| this.clear_archived(cx))),
                    ),
            )
            .into_any_element();
        Some(popover::modal("clear-archived-dialog", viewport, card))
    }
}

impl Render for ArchivedPage {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        use crate::settings::widgets;
        let theme = Theme::of(cx).clone();
        let now = chrono::Utc::now();
        let (rows, device_names): (Vec<Chat>, std::collections::HashMap<String, String>) = {
            let state = self.state.read(cx);
            let rows = archived_chats(&state.chats).into_iter().cloned().collect();
            let names = state
                .devices
                .iter()
                .map(|d| (d.id.clone(), d.name.clone()))
                .collect();
            (rows, names)
        };
        let busy = self.busy.clone();
        let count = rows.len();

        let items: Vec<AnyElement> = rows
            .into_iter()
            .enumerate()
            .map(|(ix, chat)| {
                let title: SharedString = chat
                    .title
                    .clone()
                    .unwrap_or_else(|| "Untitled session".into())
                    .into();
                // Unknown device → no fragment at all (zeron renders the
                // device span only when the name resolves).
                let device: Option<SharedString> =
                    device_names.get(&chat.device_id).cloned().map(Into::into);
                let time_ago: SharedString = crate::state::format_time_ago(
                    chat.last_message_at.unwrap_or(chat.created_at),
                    now,
                )
                .into();
                let location: Option<SharedString> =
                    crate::state::chat_location(&chat).map(Into::into);
                let is_busy = busy.as_deref() == Some(chat.id.as_str());
                let row_hovered = self.hovered == Some(ix);
                let chat_id = chat.id.clone();
                // zeron settings.archived.tsx row: archive tile, medium title
                // + tabular time, quiet device · location meta, Unarchive.
                div()
                    .id(("archived-row", ix))
                    .flex()
                    .flex_row()
                    .items_center()
                    .gap(px(12.0))
                    .rounded(px(8.0))
                    .px(px(12.0))
                    .py(px(8.0))
                    .hover(|s| s.bg(crate::theme::ink(0.03)))
                    .on_hover(cx.listener(move |this, hovered: &bool, _, cx| {
                        if *hovered {
                            this.hovered = Some(ix);
                        } else if this.hovered == Some(ix) {
                            this.hovered = None;
                        }
                        cx.notify();
                    }))
                    .child(
                        div()
                            .flex_none()
                            .size(px(32.0))
                            .rounded(px(6.0))
                            .border_1()
                            .border_color(theme.border)
                            .flex()
                            .items_center()
                            .justify_center()
                            .child(
                                crate::icons::icon(crate::icons::ARCHIVE_MINIMALISTIC)
                                    .size(px(16.0))
                                    .text_color(theme.text_muted.opacity(0.6)),
                            ),
                    )
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .child(
                                div()
                                    .flex()
                                    .flex_row()
                                    .items_center()
                                    .gap(px(8.0))
                                    .child(
                                        div()
                                            .min_w_0()
                                            .truncate()
                                            .text_size(px(13.0))
                                            .font_weight(gpui::FontWeight::MEDIUM)
                                            .text_color(theme.text)
                                            .child(title),
                                    )
                                    .child(
                                        div()
                                            .flex_none()
                                            .text_size(px(11.0))
                                            .text_color(theme.text_muted.opacity(0.5))
                                            .child(time_ago),
                                    ),
                            )
                            .child({
                                // device · location, separator at the line's
                                // own tone (zeron: a plain span inheriting
                                // `text-muted-foreground/55`).
                                let mut meta = div()
                                    .mt(px(2.0))
                                    .flex()
                                    .flex_row()
                                    .items_center()
                                    .gap(px(6.0))
                                    .text_size(px(11.0))
                                    .text_color(theme.text_muted.opacity(0.55));
                                let both = device.is_some() && location.is_some();
                                if let Some(device) = device {
                                    meta = meta.child(device);
                                }
                                if both {
                                    meta = meta.child(SharedString::from("·"));
                                }
                                if let Some(location) = location {
                                    meta = meta.child(div().min_w_0().truncate().child(location));
                                }
                                meta
                            }),
                    )
                    .child(
                        // Hidden until the row is hovered (zeron `opacity-0
                        // group-hover:opacity-100`); hover fill is the solid
                        // accent tone (`hover:bg-accent`).
                        div()
                            .id(("unarchive", ix))
                            .flex_none()
                            .flex()
                            .flex_row()
                            .items_center()
                            .gap(px(6.0))
                            .px(px(10.0))
                            .py(px(4.0))
                            .rounded(px(6.0))
                            .border_1()
                            .border_color(theme.border)
                            .text_size(px(12.0))
                            .text_color(theme.text_muted)
                            .opacity(if row_hovered || is_busy { 1.0 } else { 0.0 })
                            .when(is_busy, |el| el.opacity(0.4))
                            .cursor_pointer()
                            .hover(|s| s.bg(theme.surface_raised).text_color(theme.text))
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.unarchive(chat_id.clone(), cx);
                            }))
                            .child(
                                crate::icons::icon(crate::icons::ARCHIVE_UP_MINIMALISTIC)
                                    .size(px(14.0))
                                    .text_color(theme.text_muted),
                            )
                            .child(SharedString::from(if is_busy {
                                "Unarchiving…"
                            } else {
                                "Unarchive"
                            })),
                    )
                    .into_any_element()
            })
            .collect();

        let body: AnyElement = if items.is_empty() {
            // Centered empty state (zeron settings.archived.tsx).
            div()
                .mt(px(96.0))
                .flex()
                .flex_col()
                .items_center()
                .text_center()
                .text_color(theme.text_muted.opacity(0.5))
                .child(
                    // `opacity-40` on top of the inherited muted/50 — an
                    // effectively ~20% glyph (zeron settings.archived.tsx).
                    crate::icons::icon(crate::icons::ARCHIVE_MINIMALISTIC)
                        .size(px(28.0))
                        .text_color(theme.text_muted.opacity(0.2)),
                )
                .child(
                    div()
                        .mt(px(12.0))
                        .text_size(px(14.0))
                        .child(SharedString::from("Nothing archived")),
                )
                .child(
                    div()
                        .mt(px(4.0))
                        .text_size(px(12.0))
                        .text_color(theme.text_muted.opacity(0.4))
                        .child(SharedString::from(
                            "Right-click a session in the sidebar to archive it.",
                        )),
                )
                .into_any_element()
        } else {
            div()
                .mt(px(24.0))
                .flex()
                .flex_col()
                .gap(px(2.0))
                .children(items)
                .into_any_element()
        };

        let header = {
            let header =
                widgets::page_header(&theme, "Archived sessions", (count > 0).then_some(count));
            if shows_clear_action(count) {
                let action = self.render_clear_button(cx);
                widgets::page_header_action(header, action)
            } else {
                header
            }
        };
        let dialog = self.render_confirm_dialog(window.viewport_size(), cx);

        div()
            .id("archived-page")
            .size_full()
            .overflow_y_scroll()
            .child(
                widgets::page_column()
                    .child(header)
                    .child(widgets::page_subtitle(
                        &theme,
                        "Hidden from the sidebar. Unarchiving puts a session back on its device.",
                    ))
                    .when_some(self.error.clone(), |el, message| {
                        el.child(
                            widgets::error_strip(&theme, message)
                                .id("archived-error")
                                .cursor_pointer()
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.error = None;
                                    cx.notify();
                                })),
                        )
                    })
                    .child(body),
            )
            .when_some(dialog, |el, dialog| el.child(dialog))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    fn chat(id: &str, archived: bool) -> Chat {
        Chat {
            id: id.into(),
            device_id: "d".into(),
            title: None,
            archived,
            cwd: None,
            branch: None,
            checkout_id: None,
            source_context: None,
            config: None,
            last_message_preview: None,
            last_message_at: None,
            created_at: Utc::now(),
            harness_session_id: None,
            harness_session_cwd: None,
            space_id: None,
            last_seen_at: None,
            room_gen: None,
            note: None,
        }
    }

    /// The confirm dialog is a permanent delete, so exactly ONE thing may open
    /// it: pressing the button. A capture knob here once armed it from an env
    /// var and popped it on page open, unasked. Nothing may re-introduce a
    /// second opener.
    #[test]
    fn only_the_button_opens_the_confirm_dialog() {
        // `concat!` so these needles do not match themselves in the scan.
        let source = include_str!("archived.rs");
        let openers = source.matches(concat!("confirm = ", "Some")).count();
        assert_eq!(
            openers, 1,
            "exactly one code path may open the confirm dialog; found {openers}"
        );
        assert!(
            !source.contains(concat!("ZERON_OPEN", "_DIALOG")),
            "no env var may open a destructive dialog"
        );
    }

    #[test]
    fn clear_action_hides_on_an_empty_page() {
        assert!(!shows_clear_action(0));
        assert!(shows_clear_action(1));
    }

    #[test]
    fn confirm_copy_counts_and_names_every_device() {
        assert_eq!(
            clear_confirm_copy(1),
            "1 archived session will be permanently deleted from all your devices. This can\u{2019}t be undone."
        );
        assert!(clear_confirm_copy(12).starts_with("12 archived sessions will be"));
    }

    #[test]
    fn only_archived_rows_show() {
        let chats = vec![chat("a", false), chat("b", true), chat("c", true)];
        let rows = archived_chats(&chats);
        let ids: Vec<&str> = rows.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(ids, ["b", "c"]);
    }
}
