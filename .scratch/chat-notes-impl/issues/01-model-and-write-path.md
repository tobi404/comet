# 01 - Chat Note model and write path

**Spec:** [.scratch/chat-notes/spec.md](../../chat-notes/spec.md), §1 (Model) and §2 (Write
path). The spec names every file, function, and precedent. Read those two sections in full
before starting. The glossary is [CONTEXT.md](../../../CONTEXT.md); the storage decision is
recorded in ADR 0001.

**What to build:** a Chat Note - one indivisible `note: { text, color }` value on the Chat -
can be set and cleared through a single `setChatNote` mutate op, and the change reaches the
UI state on every device. A set on one device lands in the registry doc, syncs, and arrives
in the app state through the watch stream. A clear (`null`) removes it. No visible UI ships
in this ticket; tests prove the slice end to end.

**Blocked by:** None - can start immediately.

**Status:** ready-for-agent

- [x] `ChatNote { text, color }` exists on the Chat as one optional nested field, serialised
      into a single registry field named `note`, replaced wholesale
- [x] Colour is a required Colour Slot id string (`rose` `amber` `green` `sky` `violet`),
      never an index and never hex
- [x] One mutate op `setChatNote` where `null` clears; an omitted `note` field is a
      deserialisation error, not a clear (no serde default)
- [x] The legacy workspace doc gains no mutator; the raw-row struct the registry deserialises
      through gains the field
- [x] Concurrent edits resolve to one whole note under LWW - the newer clock wins outright,
      nothing merges - and a test states this in those words
- [x] The engine treats empty or all-whitespace text as a clear
- [x] The engine truncates text at 280 characters as a guard (spec known limit 6: this is an
      affordance, not a storage invariant)
- [x] A note write against a deleted chat is a no-op returning false
- [x] No optimistic local echo: the UI state updates only from the watch frame
- [x] Tests cover: set, clear via null, clear via empty text, LWW conflict, truncate guard,
      dead-chat no-op
