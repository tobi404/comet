# Map: Chat Notes on iOS

Label: `wayfinder:map`

## Destination

A written spec, handed to an implementation session, for the **Chat Note** on the iOS app: the
same synced note the desktop already writes, painted on the phone's session rows and on the
archived shelf, revealed by a phone-native gesture, and authored on the phone in a **Note
Editor** sheet.

The spec is reached when every ticket below is resolved. The map is not the build.

## Notes

**This is the fresh effort the desktop map deferred.** The completed map at
[.scratch/chat-notes/map.md](../chat-notes/map.md) put "iOS rendering of the note" in its
Out of scope list and said it returns with a redrawn destination. This is that redraw. Do not
edit the desktop map or its tickets.

**Read first**: the desktop spec at [.scratch/chat-notes/spec.md](../chat-notes/spec.md), the
glossary at [CONTEXT.md](../../CONTEXT.md), and the ADR at
[docs/adr/0001-chat-notes-sync-in-the-registry-doc.md](../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md).

**Domain**: the glossary's terms carry over unchanged. The entity is a **Chat**. The feature is
a **Chat Note**. The colour is a **Colour Slot**. The authoring surface is the **Note Editor**.
The surface that shows a note in full is the **Note Card**, named for what it shows and not for
what opens it, which is exactly why the name survives a platform with no pointer.

**Skills every session should consult**: `grilling` and `domain-modeling` by default;
`prototype` for the tickets marked `Type: prototype`.

**Execution override**: this map plans, with one exception. The last ticket,
`07-write-the-spec`, writes the destination document. Every other ticket resolves a decision
and writes no product code.

### Settled while charting

These came out of the charting grill. They are the standing shape of the effort. A ticket may
sharpen them, but a ticket that wants to overturn one should say so out loud.

- **The wire format is fixed and is not up for redesign.** One whole `note: { text, color }`
  object field on the chat row, replaced wholesale under LWW, with slot ids `rose` `amber`
  `green` `sky` `violet`, and `null` clears. The desktop shipped it and sync makes it a
  contract, not a preference.
- **The phone authors notes.** It does not only read them. A phone-only moment is exactly when
  a user wants to leave themselves a note.
- **The interaction is phone-native, not a port.** The model and the Colour Slots are fixed by
  sync, so they carry over untouched. The desktop's hover has no honest phone equivalent, so
  the reveal is redesigned rather than approximated.
- **The surfaces are the session rows and the archived shelf.** `ChatRow` (`HomeView.swift:292`,
  used by `HomeView` and `SpaceView`) and the shelf row (`ArchivedShelf.swift:132`). The session
  detail screen is out of scope, matching the desktop's exclusion of the conversation header.
- **Authoring is reached from a long-press context menu.** The app has no `.contextMenu` today;
  this introduces its first. It is the phone's true analogue of the desktop's right-click menu,
  and on iOS 26 the same gesture can carry both the preview card and the menu items.
- **The Note Editor is a detent bottom sheet**, built from the app's existing `SheetCard` and
  friends (`Views/SheetUI.swift`). Every other authoring surface in the app is one, and the
  desktop dialog's content maps onto it with nothing lost.
- **The 280 character cap lives in the iOS editor**, and every iOS surface tolerates any stored
  length by eliding. This inverts the desktop's known limit 6: the phone writes registry rows
  directly and never passes the engine, so the phone's own editor is the only place a cap can
  exist.
- **The resting marker carries over as a stub on the row's leading edge**, ported to points.
  One visual language across the two apps, and it costs no layout. A coloured dot on one of the
  row's lines was rejected: it would collide with the status dot the row already carries.
- **The reveal is not settled by argument.** Three candidates survive charting and go to a
  prototype: marker only with a long-press card (V1), the note taking the row's location line
  (V3), and both together (V6). Four candidates died in the grill and do not return: the note
  as a fourth line on every noted row (ragged heights damage the `Motion.resort` FLIP glide,
  and the 36pt shelf row cannot take it), the note taking the harness and branch line instead
  (the same shape as V3 with a worse sacrifice), a full row tint (it fights the press wash and
  the selected wash, the row's only two interactive signals), and tap-to-expand on the marker
  (a 3pt target needs a 44pt hit area, which then fights the row's own tap-to-open; the desktop
  killed its 12px hit zone for this reason and wrote down why).

### Facts established while charting

Looked up, not decided. A ticket does not need to re-check these.

- **iOS has no Chat Note support at all today.** `WorkspaceStore.swift:287` maps the chat row
  and stops at `roomGen`, so the phone silently drops the `note` field on read.
- **The iOS theme is always dark and already has `oklch()`**, ported from
  `crates/ui/src/theme.rs` (`Theme/Theme.swift:1`). The entire light-theme contrast problem,
  which cost the desktop two accepted known limits, does not exist here. The charting guess that
  the five would port at the desktop's dark values was half right and is superseded by
  [03](./issues/03-colour-slots-on-the-phone.md): the lightness ports, the chroma does not.
- **`JSONValue.null` deletes a field and is documented as such** (`Sync/RegistryCore.swift:15`).
  The desktop's "null clears" contract works unchanged from the phone.
- **The deployment target is iOS 26.0** (`Zeron.xcodeproj/project.pbxproj:227`). No modern API
  is off the table, including `.contextMenu(menuItems:preview:)` with its zoom transition.
- **The archived shelf row is a fixed 36pt single line** (`ArchivedShelf.swift:132`): harness
  mark, title, time-ago. A second line does not fit it. Whatever wins on the session rows must
  degrade to marker-only there.
- **The app has a demo mode, and it is a fork, not a mirror.** `AppModel.setArchived`
  (`App/AppModel.swift:474`) reads `if let demo { ...; return }`: a mutation reaches
  `DemoDataset` **or** `WorkspaceStore`, never both. Corrected by
  [01](./issues/01-note-on-the-wire-and-in-demo-mode.md), which found the earlier "mirror"
  claim wrong. The consequence is placement, not a bug class: any rule both paths need must sit
  **above** the fork.

- **The phone echoes a local write for free, so desktop spec §2's "no optimistic local echo"
  does not port.** Found by [01](./issues/01-note-on-the-wire-and-in-demo-mode.md), not while
  charting. `doc.write` enqueues into the pending overlay and `afterLocalWrite()` calls
  `project()` on the same run loop (`Sync/WorkspaceStore.swift:242`), and `overlayRows` reads
  pending over authoritative (`Sync/RegistryCore.swift:540`).

- **The sRGB gamut ceiling at L 0.660 is chroma 0.1346, and `sky` is what limits it.** Found by
  [03](./issues/03-colour-slots-on-the-phone.md). Above it, `oklchToSrgb`'s per-channel clamp in
  `gammaEncode` drags the out-of-gamut slots back silently, so "one lightness and one chroma
  across all five" stops being true without anything saying so. This is a constraint on any
  future re-tune of the Colour Slots, on either app.

- **The phone clears 3:1 on every surface a session-row marker paints on, with room the desktop
  never had.** Found by [03](./issues/03-colour-slots-on-the-phone.md). `#060606` is darker than
  the desktop's frost over vibrancy, and the theme is always dark, so both of the desktop's
  contrast-driven known limits are gone here rather than accepted.

- **`ChatConfig` does not round-trip unknown keys**, found by
  [01](./issues/01-note-on-the-wire-and-in-demo-mode.md). `setChatConfig`
  (`Sync/WorkspaceStore.swift:673`) encodes the whole struct, so a new top-level `config.foo`
  from the desktop would be dropped by an iOS edit. What iOS preserves is `modelOptions`, an
  open map it cannot author. Read the file's warning comment narrowly.

## Decisions so far

<!-- one line per resolved ticket -->

- [03 - The Colour Slots on the phone](./issues/03-colour-slots-on-the-phone.md) - the five
  become a `NoteSlot` enum at the paint layer in a new `Theme/NoteSlots.swift`, at **L 0.660,
  C 0.130**: the desktop's lightness, at the largest chroma every hue can actually reach in sRGB.
  The near-black background does not want a different lightness - it wants more separation, and
  the closest pair rises from ΔE 0.109 to 0.126. Chroma 0.150 was built and refused because it
  clips `amber` and `sky`. Worst contrast is 6.13 at rest, 5.53 pressed, 4.99 selected: every
  session-row surface clears 3:1, so the desktop's accepted sub-3:1 does not carry over. The one
  case under 3:1 is a shelf marker dimmed to 55% at 2.51, which is [04](./issues/04-resting-marker-on-two-row-shapes.md)'s
  to answer by not dimming it. An unknown slot id paints as `rose`, matching the desktop, because
  a neutral fallback would make the same synced note two colours across the two apps. 3pt is wide
  enough to tell the five apart. Judged on a simulator, not the physical phone, which weakens only
  the small-size answer. Prototype on branch `proto/03-colour-slots`.

- [02 - The character cap in a SwiftUI text editor](./issues/02-character-cap-in-a-swiftui-editor.md) -
  the field is a `UIViewRepresentable` around `UITextView`, clamped in
  `textView(_:shouldChangeTextInRanges:replacementText:)` and standing down while
  `markedTextRange` is not nil, because every SwiftUI hook runs after the edit lands and none of
  them can see the input method at all. Desktop known limit 5 carries over unchanged and no path
  does better. The cost is the app's first `UIViewRepresentable` and a second text-editing stack
  beside the composer's.

- [01 - The note on the wire, and in demo mode](./issues/01-note-on-the-wire-and-in-demo-mode.md) -
  `Chat` gains `note: ChatNote?` with `ChatNote { text: String, color: String }`, the Colour Slot
  id staying a `String` so no parse can downgrade an id a newer desktop wrote. No unknown-key
  round-trip: the note is a closed two-field object and `ChatConfig` is a narrower precedent than
  it looked. One store function `setChatNote(chatId:note:)` where `nil` writes `.null`, under two
  app verbs `setChatNote` and `clearChatNote`. `ChatNote.normalized` trims and returns `nil` for
  blank text, called **above** the demo fork so both paths obey it. On read, a note with no
  colour or no text is dropped, and a note with an unknown slot id or over-long text is kept.
  The demo dataset gains three seeded notes. In code and model a note is **cleared**, never
  deleted, now recorded in [CONTEXT.md](../../CONTEXT.md).

## Not yet specified

In-scope fog. Each patch graduates into tickets once the frontier reaches it.

- **Accessibility.** VoiceOver for the marker and for the note text, and what Dynamic Type does
  to whichever row shape wins. This cannot be phrased sharply until the reveal is chosen,
  because V1, V3, and V6 each present a different thing to read out.
- **List motion.** Whether the chosen reveal forces any change to `Motion.resort` or to how the
  List diffs rows. V3 changes no heights and V6 changes them per row, so the answer is
  downstream of the reveal.
- **Discoverability of authoring.** A user with no notes has nothing on screen that says a note
  is possible. Whether that needs an affordance, and where, waits on the menu's final shape.

## Out of scope

Ruled beyond this destination. None of it graduates. Each would be a fresh effort with a
redrawn destination.

- **The session detail screen.** `SessionView` and the header above the transcript. The rows
  are the only surface, matching the desktop's exclusion of its conversation header.
- **Any change to the desktop app.** The wire format is a contract this effort consumes.
- **Notifications, widgets, and Live Activities carrying the note.**

Inherited unchanged from the desktop map, and still ruled out:

- **Filtering or grouping the session list by note colour.**
- **Searching note text.**
- **Pinning or reordering a Chat because it has a note.**
- **More than one note per Chat, markdown in a note, and attachments on a note.**
