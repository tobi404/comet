# 01 - The note on the wire, and in demo mode

Map: [Chat Notes on iOS](../map.md)
Type: grilling
Status: resolved
Claimed by: Beka Demuradze
Blocked by: none

## Question

How does the iOS app read, write, and clear the `note` field, without ever clobbering what the
desktop wrote?

The wire format is fixed (see the map's Settled list and the desktop spec §1 and §2). This
ticket is not free to change it. What it settles is the Swift side of that contract.

1. **The Swift model.** `Chat` (`Models/Entities.swift:46`) gains what, exactly? A
   `note: ChatNote?` with `ChatNote { text: String, color: String }` mirrors the Rust. Confirm
   the Colour Slot id stays a `String` on the model rather than an enum, or decide it becomes an
   enum and say what happens to an id this build does not know.

2. **Unknown keys inside the note object.** `ChatConfig` carries a warning worth reading first
   (`Models/Entities.swift:41`): `modelOptions` is round-tripped precisely so a mobile config
   edit never clobbers options the desktop pickers set, because `setChatConfig` rewrites the
   whole `config` field under per-field LWW. The note has the identical shape - one whole object
   replaced wholesale. Decide whether `ChatNote` must round-trip unknown keys the same way, or
   whether a two-field object is small enough that it never earns the machinery.

3. **The write.** Confirm the set is `updateChat(chatId, set: ["note": <object>])` and the clear
   is `updateChat(chatId, set: ["note": .null])`, matching `setArchived`
   (`Sync/WorkspaceStore.swift:652`) and `setChatConfig` (`:673`). Name the functions
   `WorkspaceStore` gains.

4. **Empty text means delete, on the phone too.** The desktop enforces this on both sides. The
   phone has no engine to be the second side. Decide where the trim-and-clear rule lives so no
   iOS caller can write a blank note that paints an invisible marker.

5. **Demo mode.** `AppModel` mirrors every chat mutation into `DemoDataset` as well as
   `WorkspaceStore` - see `setArchived` (`App/AppModel.swift:474`) for the shape. Decide what
   the note's demo path looks like, and whether the shipped demo dataset should carry a note or
   two so the surfaces have something to render.

6. **The read.** `WorkspaceStore.swift:287` currently drops the field. Confirm the parse, and
   decide what the phone does with a stored note that is malformed: missing `color`, an unknown
   slot id, or text far longer than 280 characters. The desktop model says colour is required,
   so a note with no colour is a state the model excludes - decide whether the phone drops such
   a row's note, or paints it on a fallback slot.

## Answer

**The phone carries the note as a closed two-field value, keeps the Colour Slot id as text, and
normalises once above the demo fork.** No new machinery. Two premises in the question were wrong
and are corrected below.

### Corrections to the question

- **Demo mode is a fork, not a mirror.** `AppModel.setArchived` (`App/AppModel.swift:474`) reads
  `if let demo { ...; return }`. A mutation reaches `DemoDataset` **or** `WorkspaceStore`, never
  both. So the map's Facts entry claiming a mirrored write is wrong, and there is no
  reaches-only-one-of-two bug to guard. The real job is placement: any rule both paths need must
  sit **above** the fork. The map has been corrected.
- **`ChatConfig` does not round-trip unknown keys.** `setChatConfig` (`Sync/WorkspaceStore.swift:673`)
  encodes the whole struct through `JSONValue(encodable:)`, so a new top-level `config.foo` from
  the desktop **would** be dropped by an iOS edit. What iOS preserves is `modelOptions`, an open
  map it cannot author. That is a narrower precedent than the question assumed, and it argues
  against the machinery rather than for it.

### 1. The Swift model

`Chat` (`Models/Entities.swift:46`) gains `var note: ChatNote? = nil`.

```swift
struct ChatNote: Hashable, Codable {
    var text: String
    var color: String   // Colour Slot id
}
```

**`color` stays a `String` on the model.** It does not become an enum. The phone must read a
note, open a menu, and write it back without downgrading a slot id a newer desktop wrote; an
enum forces a lossy choice at the parse boundary, which is exactly where the phone knows least.
The id resolves to a colour at the paint layer, and
[03 - The Colour Slots on the phone](./03-colour-slots-on-the-phone.md) owns that enum and its
fallback.

### 2. Unknown keys inside the note object

**No round-trip bag.** `ChatNote` encodes through `Codable`, like `ChatConfig`. The note is a
closed two-field object; the desktop spec §1 fixes its shape and replaces it wholesale, and it
carries no open sub-map of the `modelOptions` kind. If the desktop ever adds a third field, that
is a wire change and both apps change together.

### 3. The write path

One function at the store, two verbs above it.

- `WorkspaceStore.setChatNote(chatId: String, note: ChatNote?)` - a value writes
  `updateChat(chatId, set: ["note": <object>])`, `nil` writes
  `updateChat(chatId, set: ["note": .null])`. One function, matching `setArchived` (`:652`) and
  the desktop's one-op, null-clears contract. Two store functions would let set and clear drift.
- `AppModel.setChatNote(chatId: String, text: String, color: String)` and
  `AppModel.clearChatNote(chatId: String)`. The Note Editor's Save calls the first; the menu's
  Delete item calls the second. Two verbs at the app layer reflect two user intents; one function
  below reflects one wire op.

Confirmed as facts, not decisions: `updateChat` (`:714`) guards `doc.rowExists`, so a write
against a deleted chat is a no-op, matching the desktop's `set_chat_archived`.

**The phone echoes locally, and keeps it.** `doc.write` enqueues into the pending overlay and
`afterLocalWrite()` calls `project()` on the same run loop (`Sync/WorkspaceStore.swift:242`,
`Sync/RegistryCore.swift:540`); `overlayRows` reads pending over authoritative (`:540`). The
desktop spec §2's "no optimistic local echo" therefore **does not port**. This is a stated
difference for the spec, not a defect: the desktop's dialog has no overlay to read, and the
phone's overlay is the purpose of the pending queue. The sheet closes on Save and the row
repaints at once.

### 4. Empty text means clear, on the phone too

The rule lives in one pure function:

```swift
extension ChatNote {
    static func normalized(text: String, color: String) -> ChatNote?
}
```

It trims both ends and returns `nil` for empty or whitespace-only text. **`AppModel.setChatNote`
calls it above the demo fork**, so both paths obey it. `WorkspaceStore.setChatNote` keeps its own
guard as the floor, so no future caller can bypass it. Together these are the phone's honest
replacement for the desktop engine's second side, which the phone does not have.

Vocabulary, settled with `domain-modeling` and written into
[CONTEXT.md](../../../CONTEXT.md): a note is **cleared**, never deleted, in code and model.
"Delete note" survives in product copy only, because that is the word a user reads first, and
because "delete" in a phone's long-press menu sits beside deleting the Chat itself.

### 5. Demo mode

`AppModel.setChatNote` normalises, then forks: demo assigns
`demo.chats[ix].note = note`, real calls `workspace?.setChatNote(...)`. `clearChatNote` does the
same with `nil`. `DemoDataset` needs no new type, because it stores the same `Chat`.

**Seed the shipped dataset with three notes** in `DemoDataset.standard()`
(`App/DemoDataset.swift:33`): one short, one long enough to elide, one on an archived chat so
the shelf row has something to show. Three different Colour Slots.
[04 - The resting marker, on two row shapes](./04-resting-marker-on-two-row-shapes.md) and
[05 - The reveal](./05-the-reveal.md) are prototypes that must judge against a real list, and
they cannot judge an empty one.

### 6. The read, and malformed notes

Parse in `project()` (`Sync/WorkspaceStore.swift:287`), beside the existing `config` parse:
read `f["note"]?.objectValue`, take `text` and `color` as strings.

The four malformed cases do **not** get the same answer, and the asymmetry is the point:

| stored state | phone does |
|---|---|
| no `color` | **drops the note** |
| no `text`, or blank `text` | **drops the note** |
| unknown slot id | **keeps the note**, keeps the id unchanged |
| text far longer than 280 | **keeps it whole**, elides at every surface |

An **absent** colour breaks the model - the desktop makes colour required, and inventing a
fallback would show the user a colour nobody picked. An **unrecognised** colour does not break
it: the text is user content and must survive, and the colour is decorative, so the paint layer
falls back and [03](./03-colour-slots-on-the-phone.md) says how. Long text is the map's settled
rule, restated.

### Tests this ticket fixes

For [07 - Write the spec](./07-write-the-spec.md):

1. `normalized` returns `nil` for empty text and for whitespace-only text.
2. `normalized` trims the ends and keeps the middle intact.
3. Parse drops a stored note with no `color`, and drops one with no `text`.
4. Parse keeps a note with an unknown slot id, with the id unchanged.
5. Parse keeps text longer than 280 characters whole.
6. The clear writes `.null`, not an absent key.

The demo fork gets no test: three lines, no branching worth one.

### For the spec's amendment report

The desktop spec is not wrong here. It is **silent on iOS in one place that matters**: §2's "no
optimistic local echo" is a statement about the desktop's write path, and the phone's overlay
inverts it. That belongs in the iOS spec as a difference, and needs no desktop change.
