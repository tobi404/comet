//! The **Note Card**: the floating surface that shows a Chat Note in full when
//! the pointer rests on the Chat's sidebar row.
//!
//! Two things about this surface decide its whole shape.
//!
//! **It cannot live in the row.** `gpui::deferred` does not escape ancestor
//! clipping, and the rows sit inside `#sidebar-lists`, which scrolls. A card
//! mounted in a row is clipped to the sidebar. So the card is a
//! [`popover::Popup`] rendered from [`Shell::render_overlays`], placed with
//! [`popover::menu_at`] at an explicit window point — the same primitive the
//! row's right-click menu uses, and one render site serves the active rows and
//! the archived shelf alike.
//!
//! **It must never be moved by `menu_at`'s snap.** `snap_to_window_with_margin`
//! resolves an overflow by shifting the card LEFT, which would slide it back
//! over the sidebar and over its own trigger — remounting the flicker loop the
//! Archive pill already paid for. So the width is capped against the room that
//! actually exists ([`width_cap`]) and, below [`FLOOR_WIDTH`], the card simply
//! does not open. Flipping to the sidebar's other side is not available: the
//! sidebar is flush with the window's left edge.
//!
//! The pure parts — the room math, the vertical clamp, the first-frame height
//! estimate, and the trigger reducer — are free functions with tests. The
//! element only feeds them measurements.
//!
//! One thing planning left open and this build confirmed in passing: the resort
//! glide's `.relative().top()` DOES move the row's hitbox, because gpui hands
//! `inset` straight to taffy (`gpui/src/taffy.rs`) and hitboxes come from the
//! resulting bounds. Nothing here depends on it — the resort close is commanded
//! off `resort_epoch`, never inferred from a hover break — but it is why the
//! anchor a mid-glide row reports is its glided position and not its final one.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::time::Duration;

use gpui::{Bounds, Size, point};

use super::*;

// ---------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------

/// Gap between the sidebar's right edge and the card. The card sits ALONGSIDE
/// the row, never over it.
pub(super) const GAP: f32 = 8.0;

/// Clearance kept from the window's edges, matching every other floating
/// layer's `snap_to_window_with_margin(8)`. Held by our own arithmetic, so the
/// snap never has anything to correct.
pub(super) const MARGIN: f32 = 8.0;

/// The card's ceiling. Not a target: the card sizes to its content, so a
/// five-word note is a five-word card.
pub(super) const MAX_WIDTH: f32 = 320.0;

/// Text metrics. 13px on 19px, in a 10px/8px padded card.
pub(super) const TEXT_SIZE: f32 = 13.0;
pub(super) const LINE_HEIGHT: f32 = 19.0;
pub(super) const PAD_X: f32 = 10.0;
pub(super) const PAD_Y: f32 = 8.0;

/// The overflow clamp. Ten lines, then elide — the card never scrolls, and
/// storage cannot promise a short note (ADR 0001: iOS writes registry rows
/// directly, so no engine check bounds the text). This number is load-bearing
/// for a pathological note and is NOT the knob to turn when a capped note
/// elides; [`FLOOR_WIDTH`] is.
pub(super) const LINE_CLAMP: usize = 10;

/// The Note Editor's authoring cap, repeated here as the size the floor is
/// sized to hold. The editor owns the cap itself; this is only what the floor
/// is checked against.
#[cfg(test)]
const AUTHORING_CAP: usize = 280;

/// Mean advance of one character of the sidebar's text at [`TEXT_SIZE`].
///
/// Derived, not measured live: planning measured ~28 characters on a line of a
/// 200px card, whose text box is 180px wide (`200 - 2 *` [`PAD_X`]) — 6.43px a
/// character. It is used only to size [`FLOOR_WIDTH`] and the first frame's
/// height estimate, and both of those are self-correcting (the floor errs
/// wide, the estimate is replaced by the measured height on the next frame).
const AVG_ADVANCE: f32 = 180.0 / 28.0;

/// How much of a line word wrapping gives away to the ragged right edge.
/// English prose at this measure loses roughly a word off the end of most
/// lines; 0.93 is the conservative end of the usual 0.93–0.95 range.
const WRAP_EFFICIENCY: f32 = 0.93;

/// The narrow-window floor: below this much room, the card does not open at
/// all.
///
/// Planning set it at 200px and recorded the consequence as known limit 2 — at
/// 200px a line holds ~28 characters, so a note at the 280-character
/// authoring cap needs all ten lines with nothing spare and elides the moment
/// wrapping wastes a single character. The spec's instruction was to measure
/// the real crossing width and raise the FLOOR to it rather than raise the
/// clamp, and that is what this is: the crossing width under the model above,
/// rounded up to a whole ten. The 10-line clamp stays where it is, because it
/// is what keeps a longer-than-cap note bounded.
pub(super) const FLOOR_WIDTH: f32 = 220.0;

/// The 350ms open delay — the repo's existing hover-reveal number
/// (`crates/ui/src/history.rs`'s `tooltip_show_delay`).
pub(super) const OPEN_DELAY: Duration = Duration::from_millis(350);

/// The 120ms close delay. Long enough to absorb pointer jitter across the
/// row's own inner boundaries without a flicker, short enough that the card is
/// gone before the pointer arrives anywhere else.
pub(super) const CLOSE_DELAY: Duration = Duration::from_millis(120);

/// How far left the card starts before settling, over `motion::MENU_IN` — so it
/// arrives FROM the sidebar rather than fading in on the spot.
pub(super) const SLIDE: f32 = 10.0;

// ---------------------------------------------------------------------------
// Geometry (pure)
// ---------------------------------------------------------------------------

/// The card's left edge: alongside the LIVE sidebar, so it rides the collapse
/// tween instead of jumping when the sidebar animates.
pub(super) fn left_for(sidebar_now: f32) -> f32 {
    sidebar_now + GAP
}

/// The card's width cap for this window, or `None` when the window is too
/// narrow to show a card at all.
///
/// The cap is the room that actually exists — never a width that would make
/// `menu_at`'s snap shift the card back over the sidebar.
pub(super) fn width_cap(viewport_w: f32, sidebar_now: f32) -> Option<f32> {
    let room = viewport_w - left_for(sidebar_now) - MARGIN;
    (room >= FLOOR_WIDTH).then(|| room.min(MAX_WIDTH))
}

/// The card's top edge: centred on the row, then clamped [`MARGIN`] from the
/// window's top and bottom.
///
/// Once clamped the result no longer tracks the row — that is the clamp doing
/// its job, not a bug: a card pinned to the window edge must not creep with a
/// row it can no longer be level with. A card taller than the window keeps its
/// top margin and lets the bottom run over, the same way [`gpui::anchored`]'s
/// own snap resolves an oversized layer.
pub(super) fn top_for(row_center_y: f32, card_h: f32, viewport_h: f32) -> f32 {
    let ideal = row_center_y - card_h / 2.0;
    let lowest = viewport_h - MARGIN - card_h;
    ideal.clamp(MARGIN, lowest.max(MARGIN))
}

/// Characters a line holds at this card width, under [`AVG_ADVANCE`].
fn chars_per_line(card_w: f32) -> f32 {
    ((card_w - 2.0 * PAD_X) / AVG_ADVANCE).max(1.0)
}

/// The narrowest card that fits `chars` characters of wrapped prose inside
/// [`LINE_CLAMP`] lines — the "crossing width" the spec asked to be measured.
/// [`FLOOR_WIDTH`] is this, rounded up to a whole ten, and the test below is
/// what holds the two together.
#[cfg(test)]
fn crossing_width(chars: usize) -> f32 {
    let needed_per_line = chars as f32 / (LINE_CLAMP as f32 * WRAP_EFFICIENCY);
    needed_per_line * AVG_ADVANCE + 2.0 * PAD_X
}

/// The height to place the card at on its FIRST frame, before a real one has
/// been measured. Deliberately cheap and deliberately wrong-ish: it is spent at
/// the very start of the 140ms fade, where the card is still near-transparent,
/// and the measured height replaces it on the next frame.
pub(super) fn estimate_height(chars: usize, card_w: f32) -> f32 {
    let lines = (chars as f32 / (chars_per_line(card_w) * WRAP_EFFICIENCY))
        .ceil()
        .clamp(1.0, LINE_CLAMP as f32);
    lines * LINE_HEIGHT + 2.0 * PAD_Y
}

// ---------------------------------------------------------------------------
// The trigger (pure)
// ---------------------------------------------------------------------------

/// What the pointer just did to a row.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Pointer {
    /// The pointer entered a row that HAS a note, with no dialog or menu up.
    EnteredNoted,
    /// The pointer entered a row that cannot show a card — no note, or a menu
    /// or dialog is up. Distinct from [`Self::Left`]: the pointer is on the
    /// row, so the latch must still lift.
    EnteredMute,
    Left,
    /// A mouse button went down ON the row.
    Pressed,
}

/// Everything the reducer needs to know about the card's current state.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(super) struct TriggerState {
    /// A card is open (or closing) for THIS row.
    pub showing: bool,
    /// The 350ms timer is running for THIS row.
    pub waiting: bool,
    /// THIS row is the one holding the click-dismiss latch.
    pub latched: bool,
}

/// What the shell should do about it. One command, so the caller cannot half-
/// apply a transition.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Trigger {
    Nothing,
    /// Start the 350ms open delay for this row.
    StartWait,
    /// The pointer came back to the row its own card is on: cancel the pending
    /// 120ms close.
    CancelLeave,
    /// Start the 120ms close, drop any pending wait, and lift this row's latch.
    BeginLeave,
    /// Close now and latch this row until the pointer leaves it.
    Dismiss,
}

/// The whole-row trigger, as a reducer.
///
/// The two rules that are easy to lose when this is written inline:
///
/// - **Entering a DIFFERENT row does not cancel the open card's leave.** Only
///   the card's own row cancels it. Otherwise the old card hangs over the
///   conversation until the new one is ready 350ms later.
/// - **The latch is set only by a press on the row itself.** After a click the
///   pointer is still on the row; without the latch the card returns 350ms
///   later on top of the Chat the click just opened. It lifts when the pointer
///   leaves — never on a timer.
pub(super) fn trigger(state: TriggerState, event: Pointer) -> Trigger {
    match event {
        Pointer::Pressed => Trigger::Dismiss,
        Pointer::Left => {
            if state.showing || state.waiting || state.latched {
                Trigger::BeginLeave
            } else {
                Trigger::Nothing
            }
        }
        // A muted row still lifts its own latch by being entered — but it
        // cannot be entered while latched without having been left first, so
        // there is nothing else to do.
        Pointer::EnteredMute => Trigger::Nothing,
        Pointer::EnteredNoted => {
            if state.latched {
                // Still dismissed. The pointer never left, so nothing lifted it.
                Trigger::Nothing
            } else if state.showing {
                Trigger::CancelLeave
            } else if state.waiting {
                Trigger::Nothing
            } else {
                Trigger::StartWait
            }
        }
    }
}

// ---------------------------------------------------------------------------
// State carried on the Shell
// ---------------------------------------------------------------------------

/// The open card. `anchor` is the row's bounds as of the frame the card
/// opened; while the pointer is still on that row the live anchor cell
/// overrides it each frame, so the card stays level with a row that moves for
/// any reason short of the resort and scroll closes below.
pub(super) struct NoteCard {
    pub chat: String,
    pub anchor: Bounds<Pixels>,
    /// `resort_epoch` when the card opened. A change closes it: the resort's
    /// 260ms FLIP glide would otherwise drag the card across the conversation.
    pub epoch: usize,
    /// The sidebar's scroll offset when the card opened. A change closes it.
    pub scroll: Point<Pixels>,
    /// The wait generation that opened this card — the entrance animation's
    /// id, so every open plays the fade from the start. A reused id would
    /// inherit the previous open's finished clock and snap to the end state.
    pub entrance: u64,
}

/// The 350ms open delay. `generation` guards a stale timer — a fresh wait for
/// the same row must not be opened by the previous one's task.
pub(super) struct NoteCardWait {
    pub chat: String,
    pub generation: u64,
    pub _task: Task<()>,
}

/// The hovered row's bounds, written by a `canvas` child of the row and read by
/// the open timer and the render site.
///
/// A shared cell rather than a plain field because a `canvas` prepaint closure
/// gets `&mut Window, &mut App` and cannot reach `&mut Shell` — the same reason
/// `Shell::bottom_stack` is one.
pub(super) type AnchorCell = Rc<RefCell<Option<(String, Bounds<Pixels>)>>>;

/// Card heights, measured one frame late.
///
/// Centring needs the card's height before the card exists, so a `canvas`
/// inside the card writes its measured height into [`Self::measured`] and the
/// next frame drains it into [`Self::cache`]. A repeat open of the same note at
/// the same width is exact from its first frame; a first open spends
/// [`estimate_height`] on the opening frame of the fade, where the card is
/// still all but transparent.
///
/// Keyed by the note's TEXT and the whole-pixel card width, not by the Chat: an
/// edited note is a different height, and so is the same note in a window that
/// resized under it. Keying on the text is what makes both cases invalidate
/// themselves instead of needing to be noticed.
#[derive(Default)]
pub(super) struct HeightCache {
    measured: Rc<RefCell<Option<(Key, f32)>>>,
    cache: HashMap<Key, f32>,
}

/// (note text, card width in whole pixels).
type Key = (SharedString, u32);

/// Enough for every note on screen at a handful of window widths. Past it the
/// cache starts over rather than growing for the life of the process — the
/// cost of a miss is one frame at the estimate.
const HEIGHT_CACHE_MAX: usize = 64;

impl HeightCache {
    /// Fold in whatever the last frame's card measured. Call once at the top of
    /// the render site.
    pub(super) fn drain(&mut self) {
        if let Some((key, height)) = self.measured.borrow_mut().take() {
            if self.cache.len() >= HEIGHT_CACHE_MAX {
                self.cache.clear();
            }
            self.cache.insert(key, height);
        }
    }

    pub(super) fn get(&self, text: &SharedString, width: f32) -> Option<f32> {
        self.cache.get(&(text.clone(), key_width(width))).copied()
    }

    /// The sink a card's measuring `canvas` writes through.
    pub(super) fn writer(&self, text: &SharedString, width: f32) -> impl Fn(f32) + 'static {
        let cell = self.measured.clone();
        let key: Key = (text.clone(), key_width(width));
        move |height| {
            let mut slot = cell.borrow_mut();
            if slot.as_ref().is_none_or(|(_, prev)| *prev != height) {
                *slot = Some((key.clone(), height));
            }
        }
    }
}

fn key_width(width: f32) -> u32 {
    width.round().max(0.0) as u32
}

// ---------------------------------------------------------------------------
// The trigger, wired to the Shell
// ---------------------------------------------------------------------------

impl Shell {
    /// The whole-row trigger. Both row builders call this from the hover
    /// listener they already have — the Archive pill's `chat_status_hover` and
    /// the shelf's `archived_hover` are untouched.
    pub(super) fn note_card_hover(
        &mut self,
        chat: &str,
        entered: bool,
        has_note: bool,
        cx: &mut Context<Self>,
    ) {
        let event = if !entered {
            Pointer::Left
        } else if has_note && !self.note_card_stood_down() {
            Pointer::EnteredNoted
        } else {
            Pointer::EnteredMute
        };
        self.note_card_trigger(chat, event, cx);
    }

    /// Any mouse-down on a row: left selects the Chat, right opens the context
    /// menu, and two floating layers off one row at once is a bug.
    pub(super) fn note_card_press(&mut self, chat: &str, cx: &mut Context<Self>) {
        self.note_card_trigger(chat, Pointer::Pressed, cx);
    }

    fn note_card_trigger(&mut self, chat: &str, event: Pointer, cx: &mut Context<Self>) {
        let state = TriggerState {
            showing: self.note_card.get().is_some_and(|card| card.chat == chat),
            waiting: self
                .note_card_wait
                .as_ref()
                .is_some_and(|wait| wait.chat == chat),
            latched: self.note_card_latch.as_deref() == Some(chat),
        };
        match trigger(state, event) {
            Trigger::Nothing => {}
            Trigger::StartWait => self.start_note_card_wait(chat.to_string(), cx),
            // Only the card's OWN row cancels the pending close. Entering a
            // different row leaves it running, so the old card is gone long
            // before the new one is due.
            Trigger::CancelLeave => self.note_card_leave = None,
            Trigger::BeginLeave => {
                if state.waiting {
                    self.note_card_wait = None;
                }
                self.note_card_latch = None;
                if state.showing {
                    self.begin_note_card_leave(cx);
                }
            }
            Trigger::Dismiss => {
                self.note_card_latch = Some(chat.to_string());
                self.dismiss_note_card(cx);
            }
        }
    }

    /// The trigger stands down entirely while another layer owns the row. A
    /// right-click leaves the pointer ON the row; without this the card opens
    /// under the context menu.
    fn note_card_stood_down(&self) -> bool {
        // `get`, not `is_open`: a card opening under a still-fading menu is the
        // same flash.
        self.chat_menu.get().is_some()
            || self.rename_dialog.is_some()
            || self.delete_confirm.is_some()
            || self.note_editor.is_some()
    }

    fn start_note_card_wait(&mut self, chat: String, cx: &mut Context<Self>) {
        self.note_card_generation = self.note_card_generation.wrapping_add(1);
        let generation = self.note_card_generation;
        let target = chat.clone();
        let task = cx.spawn(async move |shell, cx| {
            cx.background_executor().timer(OPEN_DELAY).await;
            shell
                .update(cx, |shell, cx| {
                    shell.open_note_card(&target, generation, cx);
                })
                .ok();
        });
        self.note_card_wait = Some(NoteCardWait {
            chat,
            generation,
            _task: task,
        });
        // The repaint is not cosmetic: it is what mounts the row's anchor
        // probe, and the timer has nothing to open without it.
        cx.notify();
    }

    /// The 350ms timer's landing. Everything it checked when the wait started
    /// is checked again here: 350ms is long enough for a menu to open, a note
    /// to be deleted from another device, or the row to go away.
    fn open_note_card(&mut self, chat: &str, generation: u64, cx: &mut Context<Self>) {
        if self
            .note_card_wait
            .as_ref()
            .is_none_or(|wait| wait.generation != generation)
        {
            return;
        }
        self.note_card_wait = None;
        if self.note_card_stood_down() || self.note_card_latch.is_some() {
            return;
        }
        if !self
            .state
            .read(cx)
            .chats
            .iter()
            .any(|c| c.id == chat && c.note.is_some())
        {
            return;
        }
        // The row writes its own bounds through a `canvas`; only the row this
        // wait is for mounts one, so a missing anchor means the row is gone.
        let Some(anchor) = self
            .note_card_anchor
            .borrow()
            .as_ref()
            .filter(|(id, _)| id == chat)
            .map(|(_, bounds)| *bounds)
        else {
            return;
        };
        // A close still queued from the row this card is replacing would fire
        // 120ms into the new card's life.
        self.note_card_leave = None;
        self.note_card.open(NoteCard {
            chat: chat.to_string(),
            anchor,
            epoch: self.resort_epoch,
            scroll: self.sidebar_scroll.offset(),
            entrance: generation,
        });
        cx.notify();
    }

    fn begin_note_card_leave(&mut self, cx: &mut Context<Self>) {
        self.note_card_leave = Some(cx.spawn(async move |shell, cx| {
            cx.background_executor().timer(CLOSE_DELAY).await;
            shell
                .update(cx, |shell, cx| {
                    shell.note_card_leave = None;
                    shell.close_note_card(cx);
                })
                .ok();
        }));
    }

    /// Close now, through the `menu_out` exit phase. Idempotent — every
    /// commanded close funnels here and `begin_close` fires once.
    ///
    /// It deliberately leaves a pending 350ms wait alone: crossing from a row
    /// with a card onto its neighbour starts that neighbour's wait and this
    /// close in the same instant, and the close must not take the wait with it.
    fn close_note_card(&mut self, cx: &mut Context<Self>) {
        self.note_card_leave = None;
        if self.note_card.begin_close() {
            popover::reap_popup(cx, |shell| &mut shell.note_card);
            cx.notify();
        }
    }

    /// A mouse-down's close: the card goes AND nothing pending may bring one
    /// back, because the press means the pointer is busy doing something else.
    fn dismiss_note_card(&mut self, cx: &mut Context<Self>) {
        self.note_card_wait = None;
        self.close_note_card(cx);
    }

    /// The row's bounds writer: a `canvas` that measures and paints nothing.
    /// Mounted only on the row the card is waiting for or open on, so exactly
    /// one row writes the cell.
    pub(super) fn note_card_anchor_probe(&self, chat: &str) -> Option<AnyElement> {
        let tracked = self
            .note_card_wait
            .as_ref()
            .is_some_and(|wait| wait.chat == chat)
            || self.note_card.get().is_some_and(|card| card.chat == chat);
        if !tracked {
            return None;
        }
        let cell = self.note_card_anchor.clone();
        let id = chat.to_string();
        Some(
            gpui::canvas(
                move |bounds, _, _| {
                    let mut slot = cell.borrow_mut();
                    if slot.as_ref() != Some(&(id.clone(), bounds)) {
                        *slot = Some((id.clone(), bounds));
                    }
                },
                |_, _: (), _, _| {},
            )
            // No id and no listener: the probe must never take the pointer off
            // the row it is measuring.
            .absolute()
            .inset_0()
            .into_any_element(),
        )
    }

    /// The one render site, called from [`Shell::render_overlays`]. It serves
    /// the active rows and the archived shelf alike — the card does not care
    /// which list its row came from.
    pub(super) fn render_note_card(
        &mut self,
        viewport: Size<Pixels>,
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        self.note_card_heights.drain();

        // Commanded closes that are CONDITIONS rather than events, so they are
        // read where the frame is built. A resort must close the card or it
        // rides the 260ms FLIP glide across the conversation; a sidebar scroll
        // must close it or it hangs beside the row that used to be there.
        if let Some(card) = self.note_card.as_open() {
            let moved =
                card.epoch != self.resort_epoch || card.scroll != self.sidebar_scroll.offset();
            if moved || self.note_card_stood_down() {
                self.close_note_card(cx);
            }
        }

        let theme = Theme::of(cx).clone();
        let closing = self.note_card.closing_since();
        let (chat, opened_at, entrance) = {
            let card = self.note_card.get()?;
            (card.chat.clone(), card.anchor, card.entrance)
        };
        // The live anchor while the pointer is still on the row; the bounds the
        // card opened at once it is not (the probe unmounts with the hover, and
        // a card mid-exit must not jump).
        let anchor = self
            .note_card_anchor
            .borrow()
            .as_ref()
            .filter(|(id, _)| *id == chat)
            .map_or(opened_at, |(_, bounds)| *bounds);

        // A `WatchChats` frame can clear the note while its card is up.
        let Some(note) = self
            .state
            .read(cx)
            .chats
            .iter()
            .find(|c| c.id == chat)
            .and_then(|c| c.note.clone())
        else {
            self.close_note_card(cx);
            return None;
        };
        let text = SharedString::from(note.text);

        // The LIVE sidebar width, never `SIDEBAR_DEFAULT`, so the card rides
        // the collapse tween instead of jumping when it ends.
        let sidebar_now = self.eval_tween(self.sidebar_tween, self.sidebar_target());
        let Some(width) = width_cap(f32::from(viewport.width), sidebar_now) else {
            // The window shrank under an open card past the point where one
            // fits. Closing beats letting `menu_at`'s snap drag it back over
            // its own trigger.
            self.close_note_card(cx);
            return None;
        };

        let height = self
            .note_card_heights
            .get(&text, width)
            .unwrap_or_else(|| estimate_height(text.chars().count(), width));
        let position = point(
            px(left_for(sidebar_now)),
            px(top_for(
                f32::from(anchor.center().y),
                height,
                f32::from(viewport.height),
            )),
        );

        let colour = crate::theme::note_slot_color(&note.color);
        let measure = self.note_card_heights.writer(&text, width);
        let card = popover::popover_card_flush(&theme)
            // The card's own hairline, in the note's colour.
            .border_color(colour.opacity(0.32))
            .relative()
            // The tint, first so the text paints over it. `popover_card`'s
            // `overflow_hidden` clips it to the 12px radius.
            .child(div().absolute().inset_0().bg(colour.opacity(0.10)))
            .child(
                div()
                    .relative()
                    // A cap on the TEXT, not a target: the card sizes to its
                    // content, so a five-word note is a five-word card. An
                    // unbreakable token wider than this clips against the
                    // card's `overflow_hidden` instead of widening it.
                    .max_w(px(width))
                    .px(px(PAD_X))
                    .py(px(PAD_Y))
                    .text_size(px(TEXT_SIZE))
                    .line_height(px(LINE_HEIGHT))
                    .text_color(theme.text)
                    // The card never scrolls: ten lines, then elide.
                    .line_clamp(LINE_CLAMP)
                    .text_ellipsis()
                    .child(text.clone()),
            )
            // Any mouse-down closes the card. `_out` covers the row underneath
            // and everything else in the window; the pointer can also be over
            // the card itself during the 120ms leave, so it takes its own.
            .on_mouse_down_out(cx.listener(|shell, _, _, cx| shell.dismiss_note_card(cx)))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|shell, _, _, cx| shell.dismiss_note_card(cx)),
            );

        let content = div()
            .relative()
            // Measured a frame late and cached by note text and width —
            // centring needs a height before the card exists. Outside the card
            // so the hairline counts.
            .child(
                gpui::canvas(
                    move |bounds, _, _| measure(f32::from(bounds.size.height)),
                    |_, _: (), _, _| {},
                )
                .absolute()
                .inset_0(),
            )
            .child(card)
            // Arrives FROM the sidebar: 10px of leftward offset resolving to
            // zero across `MENU_IN`, under the fade `menu_at` already plays.
            .with_animation(
                SharedString::from(format!("note-card-slide-{entrance}")),
                motion::MENU_IN.animation(),
                |el, t| el.left(px(-SLIDE * (1.0 - t))),
            )
            .into_any_element();

        Some(popover::menu_at(
            format!("note-card-{entrance}"),
            position,
            content,
            closing,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The window is only wide enough for a card once the room beside the
    /// sidebar clears the floor; the card never grows past 320px, and it never
    /// asks for a pixel the window cannot give.
    #[test]
    fn the_width_cap_is_the_room_that_actually_exists() {
        // Roomy window: the 320px ceiling wins.
        assert_eq!(width_cap(1200.0, 256.0), Some(MAX_WIDTH));
        // Tight window: the room wins, and it is exactly what is left over.
        let cap = width_cap(540.0, 256.0).expect("above the floor");
        assert_eq!(cap, 540.0 - 256.0 - GAP - MARGIN);
        assert!(cap < MAX_WIDTH);
        // Exactly at the floor still opens.
        let at_floor = 256.0 + GAP + MARGIN + FLOOR_WIDTH;
        assert_eq!(width_cap(at_floor, 256.0), Some(FLOOR_WIDTH));
        // A hair under it does not open at all — flipping to the sidebar's
        // other side is impossible, the sidebar is flush with the window edge.
        assert_eq!(width_cap(at_floor - 1.0, 256.0), None);
        // A wide sidebar eats the room just as a narrow window does.
        assert_eq!(width_cap(600.0, 400.0), None);
    }

    /// The card is centred on its row until a window edge is nearer than the
    /// margin, and then it stops tracking the row.
    #[test]
    fn the_card_centres_on_the_row_and_clamps_at_the_window_edges() {
        // Mid-window: dead centre on the row.
        assert_eq!(top_for(400.0, 100.0, 800.0), 350.0);
        // Near the top: clamped to the margin, and it stays there as the row
        // keeps climbing.
        assert_eq!(top_for(40.0, 100.0, 800.0), MARGIN);
        assert_eq!(top_for(10.0, 100.0, 800.0), MARGIN);
        // Near the bottom: clamped the same way.
        assert_eq!(top_for(780.0, 100.0, 800.0), 800.0 - MARGIN - 100.0);
        // Taller than the window: keep the top margin, let the bottom run over
        // — the clamp must never produce a card hanging off the TOP.
        assert_eq!(top_for(400.0, 900.0, 800.0), MARGIN);
    }

    /// Known limit 2 says a note inside the authoring cap can elide near the
    /// floor, and the remedy the spec named is a HIGHER FLOOR, never a taller
    /// clamp. This is that floor: a full 280-character note fits in ten lines
    /// at [`FLOOR_WIDTH`], and would not have at planning's 200px.
    #[test]
    fn the_narrow_window_floor_holds_a_capped_note_in_ten_lines() {
        assert!(
            crossing_width(AUTHORING_CAP) <= FLOOR_WIDTH,
            "the floor must be at or above the crossing width ({})",
            crossing_width(AUTHORING_CAP)
        );
        // The floor is not gratuitously wide either — it is the crossing width
        // rounded up, not a round number picked for comfort.
        assert!(crossing_width(AUTHORING_CAP) > FLOOR_WIDTH - 10.0);
        // The number planning started from does NOT hold a capped note, which
        // is exactly why the floor moved.
        assert!(crossing_width(AUTHORING_CAP) > 200.0);
        // The clamp itself never moves.
        assert_eq!(LINE_CLAMP, 10);
    }

    /// The first frame's estimate only has to be close, but it must never ask
    /// for more than the clamp allows or the card would open too tall and
    /// jump back.
    #[test]
    fn the_first_frame_height_estimate_stays_inside_the_clamp() {
        let short = estimate_height("ship it".len(), MAX_WIDTH);
        assert_eq!(short, LINE_HEIGHT + 2.0 * PAD_Y);
        // A note past the cap cannot estimate past ten lines.
        let ceiling = LINE_CLAMP as f32 * LINE_HEIGHT + 2.0 * PAD_Y;
        assert_eq!(estimate_height(671, MAX_WIDTH), ceiling);
        assert_eq!(estimate_height(10_000, FLOOR_WIDTH), ceiling);
        // Empty text still occupies a line, never zero.
        assert_eq!(estimate_height(0, MAX_WIDTH), LINE_HEIGHT + 2.0 * PAD_Y);
        // Narrower card, more lines for the same note.
        assert!(estimate_height(200, FLOOR_WIDTH) > estimate_height(200, MAX_WIDTH));
    }

    /// The measurement lands one frame late, and it is keyed by what actually
    /// decides the height.
    #[test]
    fn a_measured_height_is_remembered_per_note_text_and_width() {
        let mut cache = HeightCache::default();
        let text = SharedString::from("ship it");
        assert_eq!(cache.get(&text, MAX_WIDTH), None);

        // The card's canvas writes during prepaint; the next frame's render
        // drains. Nothing is visible until it does.
        cache.writer(&text, MAX_WIDTH)(27.0);
        assert_eq!(cache.get(&text, MAX_WIDTH), None);
        cache.drain();
        assert_eq!(cache.get(&text, MAX_WIDTH), Some(27.0));

        // An edited note and a resized window both miss — which is the whole
        // reason the key is the text and not the Chat.
        assert_eq!(
            cache.get(&SharedString::from("ship it now"), MAX_WIDTH),
            None
        );
        assert_eq!(cache.get(&text, FLOOR_WIDTH), None);
        // Sub-pixel width jitter does not miss.
        assert_eq!(cache.get(&text, MAX_WIDTH + 0.4), Some(27.0));

        // It starts over rather than growing for the life of the process.
        for i in 0..HEIGHT_CACHE_MAX {
            cache.writer(&SharedString::from(format!("note {i}")), MAX_WIDTH)(19.0);
            cache.drain();
        }
        assert!(cache.cache.len() <= HEIGHT_CACHE_MAX);
    }

    /// Resting on a noted row opens the card; resting on a row that cannot
    /// show one does nothing at all.
    #[test]
    fn resting_on_a_noted_row_starts_the_open_delay() {
        let rest = TriggerState::default();
        assert_eq!(trigger(rest, Pointer::EnteredNoted), Trigger::StartWait);
        assert_eq!(trigger(rest, Pointer::EnteredMute), Trigger::Nothing);
        // Re-entering while the timer already runs must not restart it.
        let waiting = TriggerState {
            waiting: true,
            ..rest
        };
        assert_eq!(trigger(waiting, Pointer::EnteredNoted), Trigger::Nothing);
    }

    /// Jitter across a row's own inner elements re-enters the row while its
    /// card is up: that cancels the pending close instead of flickering the
    /// card away and back.
    #[test]
    fn returning_to_the_cards_own_row_cancels_the_pending_close() {
        let showing = TriggerState {
            showing: true,
            ..Default::default()
        };
        assert_eq!(
            trigger(showing, Pointer::EnteredNoted),
            Trigger::CancelLeave
        );
        assert_eq!(trigger(showing, Pointer::Left), Trigger::BeginLeave);
        // A row with nothing pending has nothing to close.
        assert_eq!(
            trigger(TriggerState::default(), Pointer::Left),
            Trigger::Nothing
        );
        // Leaving mid-wait still has to drop the wait.
        let waiting = TriggerState {
            waiting: true,
            ..Default::default()
        };
        assert_eq!(trigger(waiting, Pointer::Left), Trigger::BeginLeave);
    }

    /// A click leaves the pointer sitting on the row. Without the latch the
    /// card returns 350ms later on top of the Chat the click just opened.
    #[test]
    fn a_click_keeps_the_card_away_until_the_pointer_leaves_the_row() {
        let showing = TriggerState {
            showing: true,
            ..Default::default()
        };
        assert_eq!(trigger(showing, Pointer::Pressed), Trigger::Dismiss);
        // Latched: resting on the same row does nothing, however long.
        let latched = TriggerState {
            latched: true,
            ..Default::default()
        };
        assert_eq!(trigger(latched, Pointer::EnteredNoted), Trigger::Nothing);
        // Leaving lifts it — and only leaving.
        assert_eq!(trigger(latched, Pointer::Left), Trigger::BeginLeave);
        // A press before the card ever opened still latches, or the card would
        // arrive 350ms after the click that was meant to select the Chat.
        let waiting = TriggerState {
            waiting: true,
            ..Default::default()
        };
        assert_eq!(trigger(waiting, Pointer::Pressed), Trigger::Dismiss);
    }
}
