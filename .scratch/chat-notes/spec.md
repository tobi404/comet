# Spec: Chat Notes in the sidebar

This document is self-contained. It is the hand-off from the planning map at
[.scratch/chat-notes/map.md](./map.md); an implementation session needs only this file, the
glossary at [CONTEXT.md](../../CONTEXT.md), and the ADR at
[docs/adr/0001-chat-notes-sync-in-the-registry-doc.md](../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md).
Every value below is resolved. Nothing here is open for redesign; where a judgement call
remains, it is named explicitly as one.

## What this builds

A **Chat Note**: one short user-authored text with one **Colour Slot** from a fixed set of
five, stored on the Chat and synced, shown in the desktop sidebar as a small colour bar on the
row's left edge, expanded into a floating **Note Card** when the pointer rests on the row, and
authored in a **Note Editor** dialog reached from the Chat's context menu.

Terms are the glossary's, and the glossary wins over habit: the entity is a **Chat** (never
thread or session in code or model), the feature is a **Chat Note** (never sticky note), the
colour is a **Colour Slot** (never swatch or tag), the surfaces are the **Note Card** and the
**Note Editor**. One deliberate exception: the dialog's visible title is the product copy
"Session note", resolved with the user. Carry it verbatim in the UI string only; identifiers
stay `ChatNote`.

## 1. Model

`Chat` (`crates/proto/src/entities.rs:88`) gains:

```rust
note: Option<ChatNote>
// ChatNote { text: String, color: String /* Colour Slot id */ }
```

- **One nested field.** The note serialises into a single registry field named `note`, replaced
  wholesale. Two flat fields are rejected: registry writes are per-field LWW, so flat
  `noteText`/`noteColor` would let two devices' concurrent edits merge into a note neither
  authored. `set_chat_config` (`crates/doc/src/registry.rs:1009`) is the in-repo precedent for
  a whole struct in one field.
- **Colour is required.** Every `ChatNote` carries a slot id. The marker is the only way a note
  shows at rest, so a colourless note would be invisible; the model excludes the state.
- **The slot ids are** `rose` `amber` `green` `sky` `violet` - short neutral strings, not
  indexes and not hex. They survive palette reorder and re-tune, and they carry no system
  meaning (the five colours are decorative).
- **`RawChat`** (`crates/doc/src/workspace.rs:621`) must also gain the field: the registry
  deserialises rows through it (`RegistryDoc::chat`, `registry.rs:906`, `row_to::<RawChat>`).
  Touching that file is not the same as writing through the legacy doc - see §2.

## 2. Write path, end to end

```
Note Editor save
  → Shell::mutate  json!({ "op": "setChatNote", "chatId": .., "note": <object> | null })
  → MutateParams::SetChatNote { chat_id: String, note: Option<ChatNote> }   crates/engine/src/rpc.rs:362 (enum)
  → EngineRpc mutate handler
  → WorkspaceHost::set_chat_note(chat_id, Option<&ChatNote>) -> Result<bool, EngineError>
        (crates/engine/src/workspace_host.rs - model on set_chat_archived at :899; mutate takes &mut RegistryDoc at :468)
  → RegistryDoc::set_chat_note(..)     OpKind::Update, fields([("note", <object> | Value::Null)])
        (crates/doc/src/registry.rs - model on set_chat_archived at :933)
  → registry room push → WatchChats frame
  → AppState::apply_chats              crates/ui/src/state.rs:701
```

Rules the path must carry:

- **Registry doc only.** Add no mutator to the legacy `WorkspaceDoc`
  (`crates/doc/src/workspace.rs`). It is a one-time read-only migration seed loaded in
  `WorkspaceHost::open` (`workspace_host.rs:199`); its `set_chat_archived` has no caller
  outside its own tests.
- **One op; `null` clears.** A set carries the object; a delete carries `"note": null`, mapping
  onto the registry's clear primitive (`Value::Null` deletes the field and is still a clocked
  write, `registry.rs:142`). `MarkChatSeen { chat_id, at: Option<i64> }` (`rpc.rs:378`) is the
  precedent for an `Option` inside one op.
- **`note` must not carry `#[serde(default)]`.** With a default, a caller omitting the field
  would silently delete the note. Omitted `note` is a deserialisation error; only explicit
  `null` clears.
- **Concurrent edits: whole-note LWW.** Two devices editing the same note concurrently resolve
  to one whole note, the one with the newer HLC. Neither note is merged, and one user's edit is
  lost outright. This is deliberate (see the ADR) and follows `title` and `archived`
  (`registry.rs:575`, `RowOp::clock_for` at `:604`).
- **Empty text means delete, enforced on both sides.** The dialog trims; empty text sends
  `note: null`. The engine also treats empty or all-whitespace text as a clear, so no future
  caller can write a blank note that renders as an invisible bar.
- **The engine truncates at 280 characters as a guard.** This is an affordance, not an
  invariant - see known limit 6.
- **No optimistic local echo.** The write waits for the next `WatchChats` frame, like
  `renameChat` and `setChatArchived`. The dialog closes on save, so nothing waits to update.
- **A write against a deleted chat is a no-op returning `false`**: `OpKind::Update` never
  creates a row (`registry.rs:130`), matching `set_chat_archived`.

## 3. The five colours

Generated through `crate::theme::oklch` (`crates/ui/src/theme.rs:978`), one lightness and one
chroma per theme across all five so no colour shouts louder than the rest:

- **Dark: L 0.660, C 0.112.  Light: L 0.650, C 0.105.**

| slot | hue | dark (reference hex) | light (reference hex) |
| --- | --- | --- | --- |
| `rose` | 20 | `#ce7575` | `#c77474` |
| `amber` | 78 | `#b88938` | `#b2873d` |
| `green` | 152 | `#58a670` | `#5aa26f` |
| `sky` | 232 | `#3b9ecb` | `#409ac4` |
| `violet` | 302 | `#9f81cb` | `#9b7fc5` |

**The values that ship are the oklch triples**, resolved per theme at paint time. The hexes are
reference only; a stored hex could not follow a light/dark re-tune, which is the same reason
the wire refuses hex.

**Contrast**, measured with `contrast_ratio` (`crates/ui/src/theme.rs:1081`), worst of the five
per background:

| background | dark | light |
| --- | --- | --- |
| `surface` (opaque platforms) | 5.93 | 2.81 |
| frost (resting row) | 6.08 | 2.93 |
| frost + hover wash | 4.87 | 2.60 |
| frost + selected wash | 4.87 | 2.60 |

**Separation** between the five is OKLab ΔE (a WCAG ratio between same-lightness colours reads
~1.00 and measures nothing). Closest pair is `rose`/`amber`: ΔE 0.109 dark, 0.102 light.

Reproducer: `cargo test -p zeron-ui --lib dump_note_bar_contrast -- --nocapture`. **Run it on
branch `prototype/chat-note-dialog`** - the copy on `prototype/chat-note-card` does not compile
(missing `Theme` import). The light-mode numbers under 3:1 are accepted decisions, not defects
to fix - see known limits 3 and 4.

## 4. The resting marker

**3px wide, 18px tall, fully rounded (radius 1.5px), inset 2px from the row's left edge,
centred vertically in the 61px row.** At this geometry the stub spans roughly y 21.5-39.5, so
it cannot collide with the row's 8px corner radius.

- **Overlay, not layout.** The stub is an overlay inside the row's existing
  `px(Theme::SPACE_SM)` left padding (`crates/ui/src/shell.rs:3324`). A row without a note is
  pixel-identical to today: no width is reserved, marked and unmarked rows stay aligned.
- **It paints over the selected wash**, not under it. `glass_selected_bg`
  (`crates/ui/src/theme.rs:896`) is a translucent wash across the row plate; the bar sits on
  the composited result. The contrast numbers above measure it that way.
- **The archived shelf shows the bar too.** The shelf builds its rows inline
  (`crates/ui/src/shell/spaces.rs`) rather than calling `Shell::render_chat_row`, so extract
  one shared bar-painting helper and call it from both row builders.
- **The bar is only the resting mark.** It is not the hover target - the whole row is (§5) -
  so it stays free to be this small.
- **A note does not change the sidebar sort order.**

## 5. The Note Card

The floating surface that shows the note in full. Everything here is the resolved end state;
the mechanism and the appearance ship together.

### Mechanism and render site

- **Primitive: `popover::Popup<NoteCard>` opened through `popover::menu_at`**
  (`crates/ui/src/popover.rs:67`, `:395`), rendered from `Shell::render_overlays` - the same
  pattern the row's right-click `chat_menu` already uses (`crates/ui/src/shell.rs:4372`).
- **Never inside a row.** `gpui::deferred` does not escape ancestor clipping
  (gpui `crates/gpui/src/window.rs:3168` restores the captured content mask), and the rows live
  inside `#sidebar-lists`, which is `.overflow_y_scroll()` (`crates/ui/src/shell.rs:3583`). A
  card mounted in a row is clipped to the sidebar. This is also why `anchored_menu` is not
  used: it attaches to the trigger and inherits the clip. `menu_at` takes an explicit window
  position from outside the scroll region.
- `menu_at` occludes (`crates/ui/src/popover.rs:554`). Wanted: the card floats over the
  conversation area and clicks must not fall through it.
- **One render site serves the active rows and the archived shelf.** One card, one place.

### Trigger

- **The whole row opens the card.** There is no separate hit zone. Add one more branch inside
  the row's existing hover listener at `crates/ui/src/shell.rs:3348`; the archived shelf gains
  the same branch in its own hover listener. `chat_status_hover` and `archived_hover` are not
  reused and not touched - the Archive pill swap is unchanged.
- **Delays: 350ms to open** (matches `crates/ui/src/history.rs:947`, the repo's existing
  hover-reveal number), **120ms to close** (absorbs pointer jitter without a flicker).
- **The card is not hoverable.** The pointer entering the card does not keep it alive; nothing
  in it is clickable.
- **The trigger stands down entirely** while `chat_menu`, the rename dialog, the
  delete confirmation, or the Note Editor is up. A right-click leaves the pointer on the row;
  without this the card opens under the context menu.

### State on `Shell`

Four new fields, one job each (03's shape, corrected for the whole-row trigger):

```rust
/// The visible Note Card plus its menu_out exit phase.
note_card: popover::Popup<NoteCard>,           // NoteCard { chat: String, anchor: Bounds<Pixels> }
/// The 350ms open delay. `generation` guards stale timers, as the composer does.
note_card_wait: Option<NoteCardWait>,          // { chat: String, generation: u64, _task: Task<()> }
/// The 120ms close delay. Cancelled by dropping the task.
note_card_leave: Option<Task<()>>,
/// The hovered row's bounds, captured by a `canvas` child of the row.
note_card_anchor: Option<(String, Bounds<Pixels>)>,
```

Sequence: the pointer enters the row, the hover branch sets `note_card_wait` and starts the
timer; the row's `canvas` writes `note_card_anchor` on the next frame; 350ms later the timer
fires with bounds present and `note_card.open(...)` runs. Only the target row writes bounds.

### Commanded closes

The card closes - it never follows the row and never stays at a stale point - on:

- **Resort.** `resort_epoch` increments on every reorder (`crates/ui/src/shell.rs:3483`);
  close when it changes while the card is open. Without this the card slides across the
  conversation for the whole 260ms FLIP glide, because the anchor refreshes every frame.
- **Scroll.** `self.sidebar_scroll` is already tracked.
- **Any mouse-down.** Left-click selects the Chat, right-click opens `chat_menu`; two floating
  layers from one row at once is a bug.
- **Click-dismiss latch.** After a mouse-down the card stays dismissed until the pointer leaves
  that row - the pointer is still on the row after a click, and without the latch the card
  returns 350ms later on top of the chat the click just opened. The latch lifts on the first
  pointer move to another row or off the list, never on a timer.

### Appearance

| | |
| --- | --- |
| base | `popover::popover_card_flush` (`crates/ui/src/popover.rs:307` area) - the app's frost, hairline, 12px radius and shadow |
| tint | the note's colour at **0.10** across the whole card, plus a hairline of the same colour at **0.32** |
| horizontal anchor | left edge at the **live sidebar width + 8px** - from `eval_tween(sidebar_tween, sidebar_target())`, never `SIDEBAR_DEFAULT`, so it rides the collapse tween. Alongside the row, never over it |
| vertical anchor | **centred on the row**, clamped to 8px from the window's top and bottom; once clamped it stops tracking the row |
| maximum width | **320px**; the card sizes to its content, so a five-word note is a five-word card. 320px is a `max_w` on the text, not a target |
| padding | **10px** horizontal, **8px** vertical |
| text | **13px**, line height **19px**, `theme.text` |
| overflow | **10 lines** via `line_clamp`, then elide. The card never scrolls |
| motion | `menu_in` / `menu_out`, plus a **10px leftward offset** resolving to zero over `MENU_IN`'s 140ms, so the card arrives from the sidebar |

Centring needs the card's height a frame before the card exists: measure it with a `canvas`
inside the card, cache per chat and width, and spend the first frame's estimate (derived from
text length) at the very start of the 140ms fade.

### The narrow window

`menu_at`'s `snap_to_window_with_margin` resolves overflow by **shifting the card left**
(gpui `crates/gpui/src/elements/anchored.rs:190`), which would slide it back over the sidebar
and over its own trigger - restarting the mount/unmount flicker loop recorded at
`crates/ui/src/shell.rs:3287`. The card must never be moved by the snap:

- **Cap the card's width against `viewport.width - (sidebar + 8px gap) - 8px margin`.**
- **Below 200px of room, do not open at all.** Flipping to the sidebar's left is impossible -
  the sidebar is flush with the window's left edge.

**Instruction carried from planning:** near the 200px floor a line holds roughly 28
characters, so a note inside the 280-character cap can need more than 10 lines and will elide.
Measure the real crossing width - the width where 280 characters fit in 10 lines - and if it is
comfortable to do so, **raise the floor to that width rather than raising the clamp**. The
clamp is what keeps a pathological (longer-than-280) note bounded, so it stays at 10 lines.

### One verification note

Whether `.relative().top()` (`crates/ui/src/shell.rs:3499`) shifts an element's hitbox was not
verified during planning. Nothing depends on it - the resort close is commanded off
`resort_epoch`, not inferred from a hover break - but it is worth confirming in passing.

## 6. The Note Editor

Modelled on Rename: `Shell::open_rename_chat` (`crates/ui/src/shell.rs:1990`),
`submit_rename_chat` (`:2016`), and the dialog primitives `dialog_card`, `dialog_title`,
`dialog_field`, `btn_primary`, `btn_danger` (`crates/ui/src/popover.rs:876`, `:891`, `:910`,
`:947`, `:962`).

### The menu entry

One contextual item: **"Add note…"** when the Chat has no note, **"Edit note…"** when it has
one. It sits **directly under `Rename…`, above `Archive`** (`crates/ui/src/shell.rs:4396`),
and carries `icons::PEN_NEW_SQUARE`. The label changes because the note is pointer-only (known
limit 1) and the menu is the one place the shell states in words that a note exists. Not
`icons::TAG` - the glossary rules "tag" out as a mental model for a Colour Slot.

### The dialog

| | |
| --- | --- |
| title | **"Session note"** (resolved product copy - carry verbatim; identifiers stay `ChatNote`) |
| width | 360px, unchanged from `popover::dialog_card` |
| order | title → **text field** → **slot row** → buttons |
| field | floors at **3 wrapped lines**, grows to **6**, then scrolls. 14px, the dialog-field frame |
| placeholder | **"Write a note about this session…"** |
| slot row | five **14px circles** (slot dots), 6px apart, each in a **24px hit target** |
| selected slot | a **1px ring** in `theme.text` at 0.85, held one 24px cell around the dot |
| counter | on the slot row, pushed right. **Hidden until 240**, `theme.text_muted`, turning `theme.text` at 280 |
| buttons | `justify_between`: **Delete far left** (absent entirely when the Chat has no note), `Cancel` and `Save` right. Save is never disabled |
| cap | **280 characters**, blocked where text enters |
| keys | **Enter** saves, **Shift+Enter** makes a newline, **Escape** discards with no prompt |
| focus | lands in the field on open, caret at the end, nothing selected (`set_text` does this) |
| default slot | a new note starts on **`rose`**, already selected; editing shows the stored slot ringed |

The control is the **slot row** and one cell is a **slot dot** - "swatch" is out per the
glossary.

### The cap mechanism

`ComposerInput` gains a `max_chars`, clamped inside `replace_text_in_range`. Every input path
funnels through that one function - typing, IME commit, `Shift+Enter`, paste - so one clamp
covers all of them and the caret never has to be restored. Three properties are not judgeable
by eye and carry a test
(`the_character_cap_clamps_by_character_and_measures_room_after_the_deletion`,
`crates/ui/src/composer.rs`):

- **Characters, not bytes** - 280 means the same for an emoji as for an `a`.
- **Room is measured after the deletion** - a field at 280 still accepts a paste over a
  selection.
- **The cut lands on a character boundary** - a clamped paste never splits one.

`ComposerInput::set_max_chars` and `set_max_content_height` exist only as prototype code on
branch `prototype/chat-note-dialog` (commit `8a81722`), not on `main`. Reimplement or port
them; do not assume they are present.

### Delete

**Delete does not ask for confirmation.** The Delete button and the clear-the-text-and-save
path do exactly the same thing - trim, and empty text sends `note: null` - and a confirm on
one path only would make them disagree. A note is one short capped text; it does not earn the
ceremony a transcript's `Delete…` does.

### One wiring hazard, verified in the prototype

The composer input binds `escape` to a mention action. Escape-discards was verified working in
the prototype anyway; re-verify it in the shipped dialog, because it is the one key that can
silently fail.

## 7. Test set

Carry these; each earned its place:

- **The clamp test** named in §6, on `replace_text_in_range`.
- **The contrast reproducer**: `cargo test -p zeron-ui --lib dump_note_bar_contrast --
  --nocapture` must keep producing §3's numbers.
- **A 671-character note fixture** - longer than the cap, because storage cannot promise a
  short note (known limit 6). It must elide cleanly at 320px.
- **A URL fixture** - an unbreakable token wider than the card clips rather than widening the
  card.
- **Escape discards** - the mention-action binding makes this the one key worth an explicit
  check.

## 8. Known limits

State these in code comments or tests where they bite; none is a defect to fix in this build.

1. **The note is pointer-only.** The whole row is the trigger; there is no keyboard or command
   path to the Note Card. The note text is otherwise reachable only through the context-menu
   Note Editor.
2. **Near the 200px narrow-window floor, a note inside the 280-character cap can exceed the
   card's 10-line clamp and elide.** Accepted. Measure the real crossing width and raise the
   floor rather than the clamp (§5, "The narrow window").
3. **Light-theme markers sit under 3:1 on hovered and selected rows (2.60).** Raised, measured,
   and accepted twice: a decorative mark in a near-monochrome sidebar should not meet the AA
   floor for a meaningful graphic, and nothing in the product depends on reading the bar. If
   ever revisited, the measured remedy is `soft+`: light at L 0.610, C 0.105, which measures
   3.04 on selected rows.
4. **Light theme over a dark wallpaper is worse, about 2.0.** The sidebar is vibrancy, so the
   frost rides the desktop; no light weight clears 3:1 there. Nothing fixes this inside a muted
   palette. Dark theme's worst wallpaper case is 3.50.
5. **IME composition can exceed 280 characters while uncommitted; the commit truncates.** Only
   the commit path is clamped, because marked text is not yet text.
6. **The 280-character cap is an authoring affordance, not a storage invariant.** iOS writes
   registry rows directly and never passes through the Mutate RPC, so no engine check bounds
   the stored text. Every renderer must tolerate any length - this is why the card clamps by
   lines.

## 9. Out of scope

Copied verbatim from the map. Do not widen this build into any of it.

- **iOS rendering of the note.** The synced storage choice keeps this possible later. It is not
  built or specified here.
- **The tab strip and the conversation header.** The sidebar row is the only surface.
- **Filtering or grouping the sidebar by note colour.**
- **Searching note text.**
- **Pinning or reordering a Chat because it has a note.**
- **More than one note per Chat, markdown in a note, and attachments on a note.**

## Reference

- ADR: [0001 - Chat Notes sync in the registry doc](../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md)
- Glossary: [CONTEXT.md](../../CONTEXT.md)
- Prototypes (throwaway; the numbers above survive them):
  `prototype/chat-note-bar` (`a880cd0`, `e751d3c`; `scripts/proto-note-demo.sh dark B13` /
  `light B11`), `prototype/chat-note-card` (seed `C22212m`; `scripts/proto-note-card.sh dark`;
  its contrast test does not compile), `prototype/chat-note-dialog` (`8a81722`, seed `A11`;
  `scripts/proto-note-dialog.sh dark`; the contrast test runs here).
