# Map: Chat Notes on iOS

Label: `wayfinder:map`

## Destination

A written spec, handed to an implementation session, for the **Chat Note** on the iOS app: the
same synced note the desktop already writes, painted on the phone's session rows and on the
archived shelf, revealed by a phone-native gesture, and authored on the phone in a **Note
Editor** sheet.

The spec is reached when every ticket below is resolved. The map is not the build.

**Reached.** All nine tickets are resolved, the frontier is empty and the fog is clear. The
destination document is [spec.md](./spec.md), written by
[07](./issues/07-write-the-spec.md). The next session is an implementation session and it starts
from the spec, not from here.

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

- **`UITextViewDelegate`'s plural method has a Swift label the obvious spelling gets wrong, and
  getting it wrong is silent.** Found by [06](./issues/06-menu-and-note-editor-sheet.md). It is
  `shouldChangeTextInRanges`, not `shouldChangeTextIn`; Swift keeps "Ranges" so the plural does
  not collide with the singular. The wrong spelling compiles, satisfies no protocol requirement,
  exports no selector and never fires, with no warning. Recorded here and not only in the ticket,
  because it is the kind of trap an implementer hits again on a different delegate.

- **`Theme.sans` scales and `Theme.sansUI` does not, and measuring one with the other is
  silent.** Found by [08](./issues/08-voiceover-and-large-text.md). `Theme.sans` is
  `Font.custom(_:size:)`, which scales relative to the **body** text style; `Theme.sansUI`
  (`Theme/Theme.swift:93`) is a raw `UIFont` and scales not at all. Any height computed for text
  drawn by the first and measured with the second is a default-size height, whatever the user's
  text size is - and nothing warns. The mirror is
  `UIFontMetrics(forTextStyle: .body).scaledFont(for:)`, which 06's field already used and 06's
  card did not. Recorded here and not only in the ticket, because it is the same trap class as
  `shouldChangeTextInRanges` and an implementer will hit it again on a different measurement.

- **`.accessibilityActions` reverses the declared order, and `.swipeActions`' own action is not
  orderable against it.** Found by [08](./issues/08-voiceover-and-large-text.md), by building
  both orders. The rotor shows the last-declared action first, and the swipe's action lands after
  every declared one. So an action list has to be written backwards to be heard forwards, and one
  position in it cannot be chosen at all.

- **A `.contextMenu` preview is exempt from the dim the system puts over everything else, and the
  dim is linear.** Found by [09](./issues/09-the-note-cards-corner.md), by solving it from 27
  sample pairs: `pressed = 0.7917 x rest + (4.7, 4.7, 8.7)`, a dark blue-grey at about 21%. So a
  colour authored inside a preview renders exactly as authored while the same colour outside it
  does not, and the page reads `#0F0F13` beside a preview. Recorded here and not only
  in the ticket, because it is the same trap class as `Theme.sansUI`: two things that look like the
  same colour, measured with the wrong one, and nothing warns.

- **The Sessions list and the archived shelf paint on `Theme.surface` `#0d0d0d`, not on `Theme.bg`
  `#060606`.** Found by [07](./issues/07-write-the-spec.md) while writing the spec.
  `Views/HomeView.swift:41` and `Views/SpaceView.swift:48` set that background; `Theme.bg`
  (`Theme/Theme.swift:14`) is the app root **behind** the list. Two resolved tickets label it wrong:
  [03](./issues/03-colour-slots-on-the-phone.md) calls `#060606` the "resting list row" and
  composites both of its wash rows over it - re-derived over the real page, pressed **≈ 5.20** and
  selected **≈ 4.64** against its 5.53 and 4.99, and every verdict holds - and
  [09](./issues/09-the-note-cards-corner.md) names the veil's source `Theme.bg` while its arithmetic
  and its measured `(15, 15, 19)` both belong to `#0d0d0d`. The tickets are left as their sessions
  wrote them; [spec.md](./spec.md) carries the corrected version and the warning.

- **The `.contextMenu` preview platter draws a surface of its own, and owns its corner.** Found by
  [09](./issues/09-the-note-cards-corner.md). The tray is invisible whenever the preview's content
  covers it exactly, which is why 05 and 06 never saw it. Its corner is not a constant - it grew
  from 24pt across on the smallest card built to 44pt on the largest - and
  `.contentShape(.contextMenuPreview, _)` does not reach it from any of three attachment points.

- **A `.contextMenu` preview does not adopt its content's height.** Found by
  [05](./issues/05-the-reveal.md), and it constrains every ticket that touches the long press.
  The preview lays its content out correctly and then masks it, so a card taller than about two
  lines of 13pt text is cut mid-sentence. `.fixedSize(vertical:)` does not help and neither does
  moving the attachment point; only an explicit `.frame(height:)` does. The height must therefore
  be known before the press. Ruled out by building each alternative, not by reading.

## Decisions so far

<!-- one line per resolved ticket -->

- [07 - Write the spec](./issues/07-write-the-spec.md) - **the spec is written at
  [spec.md](./spec.md)** and the map is complete. Eleven sections in the desktop spec's shape,
  self-contained: an implementation session needs the spec, [CONTEXT.md](../../CONTEXT.md) and the
  ADR, and nothing from here. **No desktop amendment is needed** - the desktop spec is silent or
  non-porting in six places and wrong in none, so the report is a table of differences rather than a
  fix. **No new glossary term**: `Note Card` was **stretched**, because the phone exposed two faults
  in its definition - "floating" was a desktop detail (the preview *replaces* the row), and
  `preview` sat on its `_Avoid_` list while iOS builds the card from a preview API. The prediction
  inside the old definition came true exactly, which is the argument against minting a rival.
  **Two errors in resolved work were found while writing**, both the same mistake: the list paints on
  **`Theme.surface` `#0d0d0d`**, not `Theme.bg` `#060606` (`HomeView.swift:41`, `SpaceView.swift:48`).
  03's two wash rows composited over the wrong background - re-derived, pressed **≈ 5.20** and
  selected **≈ 4.64** against its 5.53 and 4.99, **no verdict moves** - and 09 misnamed the veil's
  source constant, which **would have cost an implementer the whole decision**, because veiling with
  `Theme.bg` gives `#09090E` and the visible pop 09 proved the veil does not have. Fifteen known
  limits, thirty-seven tests with the seven non-obvious ones marked as guards, the clamp rule stated
  once and applied three times, and the values this map refused to pin still unpinned. **One drift
  named and not resolved**: the 3pt mark is "bar" and "stub" on the desktop and **resting marker**
  here, and minting a term would reach into desktop vocabulary this map ruled out.

- [09 - The Note Card's corner, on the system's preview platter](./issues/09-the-note-cards-corner.md) -
  the card is **inset 14pt inside the preview and the margin is filled with `#0F0F13`**, the page's
  own colour as the system's menu dim leaves it, so the platter's arc cuts flat colour and the
  card's own **12pt continuous** corner is the only corner on screen. **05's 12 was never drawn**:
  the platter masks the preview with a corner of its own that is about half the card's height on a
  short note, so every short card was a stadium - ovalness **0.79** on the one-word note, 0.63 on
  three lines, a full pill on the 36pt shelf. **`.contentShape(.contextMenuPreview, _)` does
  nothing**, built at three attachment points - on the row, outermost on the preview, and inside
  the forced height - all three frames pixel-identical to the defect. The **UIKit
  `visiblePath`** route was priced and declined, not tried: it would replace the SwiftUI
  `.contextMenu` and force 06's menu, 08's actions and the swipe to be re-established. A plain
  transparent inset was built and refused - it exposes **the platter's own tray**, which is the
  finding that made the veil obvious. After: ovalness **0.18**, the same number on every fixture
  and every text size, on both row shapes, and **05's height rule and 08's clamp are untouched**
  because the veil sits outside the forced height. **The cost is one constant tracking a system
  effect**, with the recipe to re-derive it: the dim is linear, `pressed = 0.7917 x rest +
  (4.7, 4.7, 8.7)`. Chosen by the human; the radius swept at 8, 12, 16, 20. Prototype on branch
  `proto/09-the-cards-corner`.

- [08 - The reveal, read aloud and at the largest text](./issues/08-voiceover-and-large-text.md) -
  **a clamp is a height, fixed at what N lines occupy at the default text size**, so the line
  count falls as the text grows: the Note Card runs **10 lines at L, 7 at XXXL, 5 at AX-L, 3 at
  AX-XXXL**, and the field's 3-line floor and 6-line ceiling become the same kind of number. One
  rule, because the card and the sheet were asked the same question. It fixes two defects found
  by looking: the card **clipped at every size above XXXL** (its height measured with
  `Theme.sansUI`, which does not scale, while it paints with `Theme.sans`, which does), and the
  sheet's fitted detent **had no ceiling**, so at AX-XXXL with a long note its top reached 57pt
  and the Colour Slots sat behind the keyboard, unreachable. A ten-line clamp measured with the
  scaled font was built and refused: the card is then honest and pushes **"Clear note" off the
  screen**. A scroll was never a candidate - a `.contextMenu` preview is not interactive.
  **The phone speaks the note**, so the desktop's known limit 1 does not carry: the row gains
  `value='Note, <the note>'` on both row shapes, uncapped, and the marker stays silent because a
  colour is not a label. **The `.contextMenu` adds nothing to the accessibility tree** - dumped
  with and without, identical - so the row carries **`Edit note`, `Clear note`, `Archive`** as
  custom actions instead. That order is the platform's: `.accessibilityActions` reverses the
  declaration order and `Archive` comes from `.swipeActions` and is not orderable. "Destructive
  last" was recommended, built, and **found unreachable**. The five dots become **"Rose note
  colour"** and so on, with `sky` spoken as **Blue**, and the ring gains an explicit `Selected`
  value because `.isSelected` is reported by no tool here. The Note Editor's field **had no
  accessibility label at all** and gains "Note". **Reduce Motion: the app says nothing**, because
  there is no API to influence `UIContextMenuInteraction` and the app's own animations already
  route through `motionAnimation`. **06 is amended once**: its `protoCardHeight` must take the
  content size category as an input. Eight accepted limits are written for 07 to carry verbatim.
  Prototype on branch `proto/08-voiceover-and-large-text`.

- [06 - The long-press menu and the Note Editor sheet](./issues/06-menu-and-note-editor-sheet.md) -
  the menu carries **three items** on every row, noted or not: **"Add note…"/"Edit note…"**,
  **Archive** (Unarchive on the shelf), and **Clear note** only where a note exists. A bare row
  previews nothing custom; the system lifts the row. The Note Editor is a **content-sized
  `.height()` detent** (`content + 60`, the 60 measured) with **nav bar Cancel and Save** - not the
  app's pinned pill - running field then **five 18pt dots, 6pt apart, in 44pt targets, ringed**.
  `.medium` is refused on a measurement: with the keyboard up it swells to near-full-screen and
  leaves ~470pt of void. The counter is the desktop's rule verbatim, verified at 239/245/280.
  **Nothing confirms anything** - the desktop's reasoning holds on a phone, and Clear lives in the
  menu only. **Return saves and dismisses**, which costs the phone the ability to author a newline
  at all (an existing multi-line note survives editing). A swipe-down discards, driven with dirty
  text. The slot row fires selection feedback; Save fires nothing, named as a device question.
  The card and the menu ride one gesture without fighting, and the trailing swipe survives on both
  row shapes. **05's over-cap fixture is 779 characters, not 671** - amended there, findings
  unchanged. **02 is confirmed and amended twice**: the plural delegate's Swift label, and the
  caret. Prototype on branch `proto/06-menu-and-editor`.

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

**Empty.** Discoverability was the last patch and
[06](./issues/06-menu-and-note-editor-sheet.md) cleared it rather than graduating it: the phone
adds no affordance, because "Add note…" in the long-press menu is the whole one and a card whose
only content is "there is no note here" is noise on a list 05 chose to keep calm. The sharper
half - a user with six notes reads none of them at rest - is not a new question but 05's verdict,
taken on the real list.

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
