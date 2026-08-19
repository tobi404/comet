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
- **The reveal went to a prototype rather than to argument, and is now settled** by
  [05](./issues/05-the-reveal.md). Four candidates died in the grill and do not return: the note
  as a fourth line on every noted row, the note taking the harness and branch line instead (the
  same shape as V3 with a worse sacrifice), a full row tint (it fights the press wash and the
  selected wash, the row's only two interactive signals), and tap-to-expand on the marker (a 3pt
  target needs a 44pt hit area, which then fights the row's own tap-to-open; the desktop killed
  its 12px hit zone for this reason and wrote down why). **One of charting's reasons is wrong and
  does not carry**: the fourth-line candidate was said to damage the `Motion.resort` FLIP glide,
  and [05](./issues/05-the-reveal.md) recorded that glide surviving ragged heights frame by
  frame. That candidate stays dead on the 36pt shelf row and on the list's density, not on
  motion.

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
  degrade to marker-only there. **Superseded by [05](./issues/05-the-reveal.md)**: the winner
  puts nothing on a row's second line at all, so nothing degrades and both rows are told the
  same thing.

- **The session row measures 61.7pt, not the ~54 that was assumed, and both rows set their title
  in `Theme.sans(13)` for a 17.00pt line box.** Measured live by
  [04](./issues/04-resting-marker-on-two-row-shapes.md). The session row is therefore effectively
  the desktop's own 61px row, so desktop numbers port to it directly; the 36pt shelf is the only
  row shape that ever needed a real port.

- **`Theme.sans` scales with Dynamic Type.** `Font.custom(_:size:)` (`Theme/Theme.swift:86`) is
  the scaling variant, not `fixedSize:`. Found by
  [04](./issues/04-resting-marker-on-two-row-shapes.md). Any absolute point size this effort
  writes down has to say what it does when the text grows.

- **The shelf row clips its own content at the accessibility text sizes.** Pre-existing, found by
  [04](./issues/04-resting-marker-on-two-row-shapes.md): `ArchivedShelf.swift:153` pins the row at
  36pt while its title scales. Not caused by this effort and not fixed by it - this map plans.
  Named so a later reader does not mistake it for something a Chat Note introduced.
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

- **A `.contextMenu` preview does not adopt its content's height.** Found by
  [05](./issues/05-the-reveal.md), and it constrains every ticket that touches the long press.
  The preview lays its content out correctly and then masks it, so a card taller than about two
  lines of 13pt text is cut mid-sentence. `.fixedSize(vertical:)` does not help and neither does
  moving the attachment point; only an explicit `.frame(height:)` does. The height must therefore
  be known before the press. Ruled out by building each alternative, not by reading.

## Decisions so far

<!-- one line per resolved ticket -->

- [05 - The reveal: how the phone shows the note](./issues/05-the-reveal.md) - **V1**: the row
  gains 04's marker and nothing else, and a **long press opens the Note Card**. Chosen by the
  human on the real list, against three rivals that each put note text on a row: the phone's list
  is dense already, and every one of them spent the list's calm to save one press. The card is
  **324pt wide** (300pt of text), **13pt**, clamped at **10 lines** then elided, on `Theme.surface`
  under the slot at **0.10** with a **0.32** hairline, radius **12**, and it **carries the row's
  `space @ device` line** - because the preview covers the row while the finger is down, which the
  desktop's floating card never did. The desktop's 320px width does **not** port: it makes a 344pt
  card on a 402pt phone, between the 324 accepted here and the 364 refused, and nearer the refused
  one - though 344 itself was not built, so that is a direction and not a measurement.
  **One mechanism on both row shapes** - the same gesture opens the same card on the 36pt shelf,
  so there is no degrade at all. **No row height
  changes**, so the list motion question dissolves; it was answered anyway on the losing V6, whose
  ragged heights the `Motion.resort` glide survived frame by frame. The card's height must be
  measured before the press, which the desktop's spec §5 already does for its own reason.
  Prototype on branch `proto/05-the-reveal`.

- [04 - The resting marker, on two row shapes](./issues/04-resting-marker-on-two-row-shapes.md) -
  the marker is **3pt wide, as tall as the row's own title line, fully rounded, inset 2pt,
  centred**, clamped to the row less 3pt at each end. One rule on both shapes; at the default
  text size that is **3 x 17pt** on each. The height is a rule and not a number because
  `Theme.sans` scales with Dynamic Type: a fixed 18pt was indistinguishable at the default size
  and came apart at the accessibility sizes, which is the whole finding. **On the shelf it paints
  at full strength**, settling the one sub-3:1 number 03 left open - 3pt of ink cannot shout on a
  quiet row. The empty state is proved, not argued: markers on against markers off differ by
  exactly one 3.00pt column, 14.00pt from the screen edge, and no title moves. The clamp is 3pt
  because the wash's corner arc reaches 2.71pt at inset 2. A full-height rail was built and
  refused, so charting's "stub" stands. Prototype on branch `proto/04-resting-marker`.

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

- **Discoverability.** A user with no notes has nothing on screen that says a note is possible -
  and [05](./issues/05-the-reveal.md) sharpened the problem rather than easing it: the winner
  shows no note text at rest, so a user with six notes cannot read one without pressing. Whether
  that needs an affordance, and where, still waits on the menu's final shape in
  [06](./issues/06-menu-and-note-editor-sheet.md).

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
