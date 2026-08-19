# 01 - The note on the wire, and in demo mode

Spec: [chat-notes-ios/spec.md](../../chat-notes-ios/spec.md) §1, §2
Glossary: [CONTEXT.md](../../../CONTEXT.md) · ADR:
[0001](../../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md)

**What to build:** a Chat carries its Chat Note end to end on the phone. A note the desktop wrote
arrives on the phone's model intact, survives a malformed row by a stated rule rather than by
accident, and a note the phone writes or clears lands in the registry and repaints the same run
loop. Nothing is on screen yet - this ticket makes the note *exist* on the phone, and the three
surfaces that paint it come next.

Demo mode gets the same treatment, so the three prototype tickets that follow have a real list to
judge against rather than an empty one.

**Blocked by:** None - can start immediately.

**Status:** ready-for-agent

## Notes for the implementer

- **Read spec §1 and §2 in full.** They are short and every value in them is resolved.
- **The wire format is a contract, not a preference.** One whole `note: { text, color }` object
  field, replaced wholesale under per-field LWW. The desktop shipped it. The ADR says why it is one
  nested field and not two flat ones.
- **The Colour Slot id stays a `String` on the model.** It does not become an enum here. An enum at
  the parse boundary forces a lossy choice exactly where the phone knows least, and a newer desktop
  may write a slot id this build has never heard of. The enum lives at the paint layer and arrives
  in ticket 02.
- **The four malformed cases do not get the same answer**, and the asymmetry is the point. Spec §2
  has the table. An absent colour breaks the model; an unrecognised one does not.
- **`normalized` is called ABOVE the demo fork.** Demo mode is a fork, not a mirror - a mutation
  reaches `DemoDataset` **or** `WorkspaceStore`, never both - so any rule both paths need has to sit
  above the branch. The store keeps its own guard as the floor.
- **The phone echoes a local write for free.** The desktop spec's "no optimistic local echo" does
  not port. Do not add waiting or reconciliation; the pending overlay already does this.

## Acceptance criteria

- [ ] `Chat` carries `note: ChatNote?`, with `ChatNote { text: String, color: String }` encoding
      through `Codable` and no unknown-key round-trip bag.
- [ ] The parse reads the `note` field beside the existing `config` parse, and follows §2's table:
      drops a note with no `color`; drops one with no `text` or blank `text`; keeps one with an
      unknown slot id, with the id unchanged; keeps text longer than 280 characters whole.
- [ ] One store function writes the note, where a value writes the object and `nil` writes explicit
      `null`. Two app verbs sit above it, one for setting and one for clearing.
- [ ] `ChatNote.normalized(text:color:)` trims both ends and returns `nil` for empty or
      whitespace-only text, and is called above the demo fork so both paths obey it.
- [ ] A write against a deleted chat is a no-op. (This should fall out of the existing row guard -
      confirm rather than add.)
- [ ] The demo dataset seeds **exactly three** notes on three different Colour Slots: a short note
      on an active chat, the **779-character** fixture on an active chat, and the
      **118-character unbreakable-URL** fixture on an archived chat.
- [ ] Spec §9 tests **1-7** pass: `normalized` returns nil for empty and whitespace-only text;
      `normalized` trims the ends and keeps the middle; the parse drops a note with no `color` and
      one with no `text`; the parse keeps an unknown slot id unchanged; the parse keeps over-long
      text whole; the clear writes explicit `null` and not an absent key; and clearing produces the
      same stored result as saving blank text.
- [ ] The demo fork itself gets no test - three lines, no branching worth one.
