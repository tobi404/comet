# 01 - Chat Note data model and write path

Map: [Chat Notes in the sidebar](../map.md)
Type: grilling
Status: closed
Assignee: Beka Demuradze
Blocked by: none

## Question

What is a Chat Note in the model, and how does a write reach every device?

Settle all of the following in one session:

1. **Shape on `Chat`** (`crates/proto/src/entities.rs:88`). One nested field
   `note: Option<ChatNote>` holding `{ text, color }`, or two flat optional fields? The
   registry doc writes field-by-field with last-writer-wins
   (`RegistryDoc::set_chat_archived`, `crates/doc/src/registry.rs:933`, writes
   `fields([("archived", json!(...))])`), so the shape decides whether text and colour can
   diverge under concurrent edits from two devices.
2. **How colour is stored.** An index into the fixed five, or a named variant? Consider what
   happens if the palette is ever re-tuned.
3. **The Mutate op.** One `setChatNote`, or separate set and clear ops? What does deleting
   look like on the wire, given the dialog deletes by clearing the text?
4. **Which doc layer.** The Explore pass found two: the `RegistryDoc`
   (`crates/doc/src/registry.rs`, the path `archived` and `title` take from the UI) and a
   legacy workspace doc (`crates/doc/src/workspace.rs:328`) still used by engine-internal
   logic. Does the note write one or both?
5. **Concurrent edit behaviour.** Confirm last-writer-wins matches `title`'s precedent, and
   state it explicitly rather than inheriting it silently.
6. **The full path, named end to end**: UI mutate call → `MutateParams` variant
   (`crates/engine/src/rpc.rs:362`) → handler → `WorkspaceHost` method
   (`crates/engine/src/workspace_host.rs:899` is the `archived` analogue) → `RegistryDoc`
   method → `WatchChats` frame → `AppState::apply_chats` (`crates/ui/src/state.rs:701`).

Consult `domain-modeling`: the resolution updates [CONTEXT.md](../../../CONTEXT.md) if any
term sharpens.

## Evidence gathered in session

Read from the tree before the grill. These are facts, not decisions.

- **The registry is the only live write path.** `WorkspaceHost::mutate`
  (`crates/engine/src/workspace_host.rs:468`) takes `&mut RegistryDoc`. Nothing else.
- **The legacy workspace doc is a one-time read-only migration seed.**
  `WorkspaceHost::open` (`crates/engine/src/workspace_host.rs:199`) loads
  `WorkspaceDoc::from_doc` only when no registry snapshot exists, calls `read_all` and
  `seed_from_workspace`, then never touches it again. `WorkspaceDoc::set_chat_archived`
  (`crates/doc/src/workspace.rs:328`) has no caller outside its own tests.
- **`RawChat` is shared.** It lives in `crates/doc/src/workspace.rs:621` but the registry
  deserialises rows through it (`RegistryDoc::chat`, `registry.rs:906`, `row_to::<RawChat>`).
  A new field touches that file even though no write goes through the legacy doc.
- **Writes are per-field LWW on an HLC.** `RegistryDoc::write` (`registry.rs:575`) stamps one
  HLC over a `BTreeMap<String, Value>` of field writes. `RowOp::clock_for` (`registry.rs:604`)
  resolves per field. Every field in one `write` call shares one clock.
- **`Value::Null` deletes a field and is still a clocked write** (`registry.rs:142`). This is
  the existing clear primitive.
- **A nested object in one field is precedented.** `set_chat_config` (`registry.rs:1009`)
  serialises the whole `ChatConfig` into one field value and replaces it wholesale.
- **`OpKind::Update` never creates a row** (`registry.rs:130`), so a note write on a dead chat
  is a no-op that returns `false`, matching `set_chat_archived`.
- **The UI mutate call is a JSON op envelope**, e.g.
  `json!({ "op": "setChatArchived", "chatId": .., "archived": .. })`
  (`crates/ui/src/shell.rs:2044`).

## Resolution

A Chat Note is **one indivisible value on the Chat row**: text and colour together, stored
in a single registry field, replaced whole. It reaches other devices on the same per-field
LWW path that `title` and `archived` already use.

### 1. Shape - one nested field

`Chat` gains `note: Option<ChatNote>`, where `ChatNote { text: String, color: <slot id> }`.
It serialises into **one** registry field named `note`.

Two flat fields were rejected. Registry writes are per-field LWW, so `noteText` and
`noteColor` would carry independent clocks. Two devices editing the same note concurrently
would merge into device A's text beside device B's colour - a note no user authored. Flat
fields also admit `text = None, color = Some(..)`, a colour-only note that is not a real
state. The nested field makes "has a note" one check and one clock.

`set_chat_config` (`registry.rs:1009`) is the in-repo precedent: a whole struct in one field,
replaced wholesale.

### 2. Colour - a neutral slot id string

`color` holds a short neutral string identifying a palette slot, not an index and not hex.

An index breaks on **reorder**: moving slot 2 to position 4 silently repaints every existing
note. A slot id survives it. Hex breaks on **re-tune** and on theming, because a stored
literal cannot follow light and dark.

The name stays neutral. The map settled that the five colours are decorative and carry no
system meaning, so a semantic name such as `Urgent` is out. The five actual values belong to
[02 - resting marker and colour set](./02-resting-marker-and-colour-set.md).

### 3. Colour is required

Every `ChatNote` carries a colour. The dialog picks a default slot when the user does not
choose one. The marker is the only way a note shows at rest, so a colourless note would be an
invisible note. Requiring it removes that state from the model entirely.

### 4. Doc layer - the registry doc only

`WorkspaceHost::mutate` (`workspace_host.rs:468`) takes `&mut RegistryDoc` and nothing else.
The legacy `WorkspaceDoc` is loaded once in `WorkspaceHost::open` (`workspace_host.rs:199`),
only when no registry snapshot exists, purely as a read-only migration seed.
`WorkspaceDoc::set_chat_archived` has no caller outside its own tests.

So: **add no mutator to `WorkspaceDoc`.**

One nuance for the implementer. `RawChat` lives in `crates/doc/src/workspace.rs:621`, but the
registry deserialises rows through it (`RegistryDoc::chat`, `registry.rs:906`). The new field
**must be added to that struct**. Touching the file is not the same as writing through the
legacy doc.

### 5. Concurrent edits - whole-note LWW

Two devices that edit the same note concurrently resolve to **one whole note, the one with the
newer HLC. Neither note is merged.** This follows from the single-field shape and is the same
rule `title` and `archived` already get (`registry.rs:575`, `RowOp::clock_for` at
`registry.rs:604`). The spec states it in these words rather than inheriting it silently.

### 6. The Mutate op - one op, `null` clears

```rust
SetChatNote { chat_id: String, note: Option<ChatNote> }
```

A set carries the object. A delete carries `"note": null`, which maps onto the registry's
existing clear primitive: `Value::Null` deletes the field and is still a clocked write
(`registry.rs:142`). So a delete on one device beats an older set on another under the same
LWW rule. `MarkChatSeen { chat_id, at: Option<i64> }` (`rpc.rs:378`) is the precedent for an
`Option` inside one op.

Separate set and clear ops were rejected: two variants, two handlers and two host methods for
one field.

**`note` must not carry `#[serde(default)]`.** With a default, a caller that omits the field
would silently delete the note. Without it, an omitted `note` is a deserialisation error and
only an explicit `null` clears.

### 7. Empty text means delete, enforced on both sides

The dialog trims the text. If it is empty, the dialog sends `note: null`. The engine **also**
treats empty or all-whitespace text as a clear. The UI keeps the rule where the user acts; the
engine guard stops any future caller from writing a blank note that renders as an invisible
bar.

### 8. The 280 character cap is an affordance, not an invariant

The UI stops the user at the cap. The engine truncates as a guard.

The stored text has **no guaranteed maximum**. iOS writes registry rows directly and never
passes through the Mutate RPC, so no engine check can promise the doc holds only short notes.
Every renderer must handle a long note. That constraint is handed to
[04 - hover card appearance](./04-hover-card-appearance.md).

### 9. No optimistic local echo

The note write waits for the next `WatchChats` frame, like `renameChat` and `setChatArchived`.
`apply_chat_config` (`state.rs:742`) is the only echo in `AppState`, and it exists because the
composer chips sit under the user's cursor and must change on click. The note dialog closes on
save, so nothing is waiting to update.

### 10. The full path, end to end

```
Shell dialog save
  → Shell::mutate  json!({ "op": "setChatNote", "chatId": .., "note": .. })
  → MutateParams::SetChatNote { chat_id, note: Option<ChatNote> }      crates/engine/src/rpc.rs
  → EngineRpc mutate handler
  → WorkspaceHost::set_chat_note(chat_id, Option<&ChatNote>) -> Result<bool, EngineError>
  → RegistryDoc::set_chat_note(..)   OpKind::Update,
        fields([("note", <object> | Value::Null)])
  → registry room push  →  WatchChats frame
  → AppState::apply_chats                                             crates/ui/src/state.rs:701
```

`OpKind::Update` never creates a row (`registry.rs:130`), so a note write against a deleted
chat is a no-op returning `false`, exactly like `set_chat_archived`.

### Artifacts written

- [docs/adr/0001-chat-notes-sync-in-the-registry-doc.md](../../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md)
  records the synced-storage and single-field decision. This closes the map's **Open offer**.
- [CONTEXT.md](../../../CONTEXT.md): the **Chat Note** entry now says the note is one
  indivisible value. **Colour Slot** is a new term.

### Fog cleared

None. No new ticket, and nothing in **Not yet specified** became specifiable. Every remaining
fog patch is about the card and the archived shelf, which this decision does not touch.
