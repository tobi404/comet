# Spec: Chat Notes on iOS

This document is self-contained. It is the hand-off from the planning map at
[.scratch/chat-notes-ios/map.md](./map.md); an implementation session needs only this file, the
glossary at [CONTEXT.md](../../CONTEXT.md), and the ADR at
[docs/adr/0001-chat-notes-sync-in-the-registry-doc.md](../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md).
It does not need the map, any ticket, or the desktop's spec. Every value below is resolved.
Nothing here is open for redesign; where a judgement call remains, it is named explicitly as one.

The desktop's own spec ([.scratch/chat-notes/spec.md](../chat-notes/spec.md)) is referenced only
where this build deliberately departs from it. It is not required reading.

## What this builds

The **Chat Note** on the phone: the same synced note the desktop already writes, marked on the
session rows and on the archived shelf by a small colour stub on the row's leading edge, shown in
full in a **Note Card** lifted under a long press, and authored on the phone in a **Note Editor**
sheet reached from the same long press.

Terms are the glossary's, and the glossary wins over habit: the entity is a **Chat** (never
thread or session in code or model), the feature is a **Chat Note** (never sticky note), the
colour is a **Colour Slot** (never swatch or tag), the surfaces are the **Note Card** and the
**Note Editor**. A note is **cleared**, never deleted, in code and model - "Clear note" is also
the product copy here, so the two agree. One deliberate exception, carried from the desktop: the
Note Editor's visible title is the product copy **"Session note"**. Carry it verbatim in the UI
string only; identifiers stay `ChatNote`.

The small mark on the row has no glossary term and is called the **resting marker** throughout
this document. The desktop's spec calls the same mark "the bar" and "the stub"; the drift is
noted and not resolved here, because the desktop is out of scope (§11).

**The deployment target is iOS 26.0** (`apps/ios/Zeron.xcodeproj/project.pbxproj:227`). No modern
API is off the table. **The iOS theme is always dark**, which is why two of the desktop's six
known limits are absent here rather than accepted.

### The one thing that makes this build different from the desktop's

The desktop's own known limit 6 says the 280-character cap is an authoring affordance and not a
storage invariant, *because iOS writes registry rows directly and never passes the Mutate RPC*.
Read from this side, that is not a limit at all - it is this build's central constraint:

> **The phone writes registry rows directly. There is no engine below it, so the phone's own
> editor is the only cap there is, and every iOS surface must tolerate any stored length by
> eliding.**

That single sentence is why §7's cap mechanism has to be airtight, and why §5's card clamps by
height rather than trusting the text to be short.

## 1. Model

`Chat` (`apps/ios/Zeron/Models/Entities.swift:47`) gains:

```swift
var note: ChatNote? = nil

struct ChatNote: Hashable, Codable {
    var text: String
    var color: String   // Colour Slot id
}
```

- **`color` stays a `String` on the model.** It does not become an enum. The phone must read a
  note, open a menu, and write it back without downgrading a slot id a newer desktop wrote; an
  enum forces a lossy choice at the parse boundary, which is exactly where the phone knows least.
  The id resolves to a colour at the paint layer only (§3).
- **No unknown-key round-trip bag.** `ChatNote` encodes through `Codable`. The note is a closed
  two-field object, replaced wholesale, and it carries no open sub-map. If the desktop ever adds a
  third field, that is a wire change and both apps change together.
- **`ChatConfig` is a narrower precedent than it looks.** Its comment
  (`apps/ios/Zeron/Models/Entities.swift:35`) is about `modelOptions`, an open map iOS preserves
  because it cannot author it. `setChatConfig` (`apps/ios/Zeron/Sync/WorkspaceStore.swift:672`)
  encodes the whole struct, so a new top-level `config.foo` from the desktop **would** be dropped
  by an iOS edit today. Read that warning narrowly; it argues against the machinery, not for it.
- **The wire format is fixed and is not up for redesign.** One whole `note: { text, color }`
  object field on the chat row, replaced wholesale under per-field LWW, with slot ids `rose`
  `amber` `green` `sky` `violet`, and `null` clears. The desktop shipped it and sync makes it a
  contract. The reasoning is in the ADR.

## 2. Read, write, and demo mode

### The read

Parse in `project()` (`apps/ios/Zeron/Sync/WorkspaceStore.swift:287`), beside the existing
`config` parse, which drops the field today. Read `f["note"]?.objectValue`, take `text` and
`color` as strings.

The four malformed cases do **not** get the same answer, and the asymmetry is the point:

| stored state | the phone |
| --- | --- |
| no `color` | **drops the note** |
| no `text`, or blank `text` | **drops the note** |
| unknown slot id | **keeps the note**, keeps the id unchanged |
| text far longer than 280 | **keeps it whole**, elides at every surface |

An **absent** colour breaks the model - the desktop makes colour required, and inventing a
fallback would show the user a colour nobody picked. An **unrecognised** colour does not break it:
the text is user content and must survive, the colour is decorative, so the paint layer falls back
(§3).

### The write

One function at the store, two verbs above it.

```
Note Editor Save / menu "Clear note"
  → AppModel.setChatNote(chatId:text:color:) | AppModel.clearChatNote(chatId:)
  → ChatNote.normalized(text:color:)                    ← ABOVE the demo fork
  → if let demo { demo.chats[ix].note = note; return }  ← the fork
  → WorkspaceStore.setChatNote(chatId:note:)
  → updateChat(chatId, set: ["note": <object>])   or   ["note": .null]
        (apps/ios/Zeron/Sync/WorkspaceStore.swift:714)
  → doc.write → pending overlay → afterLocalWrite() → project()
```

- **One store function, two app verbs.** `WorkspaceStore.setChatNote(chatId:note:)` where a value
  writes the object and `nil` writes `.null`, matching `setArchived` (`:652`) and the desktop's
  one-op, null-clears contract. Two store functions would let set and clear drift. Above it,
  `AppModel.setChatNote(chatId:text:color:)` and `AppModel.clearChatNote(chatId:)` reflect two
  user intents over one wire op.
- **`null` clears.** `JSONValue.null` deletes a field and is documented as such
  (`apps/ios/Zeron/Sync/RegistryCore.swift:15`). The clear writes `.null`, never an absent key.
- **Empty text means clear, enforced on the phone alone.** The desktop enforces this on both the
  dialog and the engine. The phone has no engine to be the second side, so the rule lives in one
  pure function:

  ```swift
  extension ChatNote {
      static func normalized(text: String, color: String) -> ChatNote?
  }
  ```

  It trims both ends and returns `nil` for empty or whitespace-only text.
  **`AppModel.setChatNote` calls it above the demo fork**, so both paths obey it, and
  `WorkspaceStore.setChatNote` keeps its own guard as the floor so no future caller can bypass it.
- **A write against a deleted chat is a no-op.** `updateChat` (`:714`) guards `doc.rowExists`,
  matching the desktop's `set_chat_archived`. This is a fact, not a decision.
- **Concurrent edits: whole-note LWW.** Two devices editing the same note resolve to one whole
  note, the one with the newer clock. Neither is merged and one user's edit is lost outright. This
  is deliberate; the ADR states it in those words.

### The phone echoes locally, and keeps it

**Desktop spec §2's "no optimistic local echo" does not port, and this is a difference rather than
a defect.** `doc.write` enqueues into the pending overlay and `afterLocalWrite()` calls
`project()` on the same run loop (`apps/ios/Zeron/Sync/WorkspaceStore.swift:242`), and
`overlayRows` reads pending over authoritative
(`apps/ios/Zeron/Sync/RegistryCore.swift:540`). The desktop's dialog has no overlay to read; the
phone's overlay is the purpose of the pending queue. The sheet closes on Save and the row repaints
at once, with no extra code.

### Demo mode

**Demo mode is a fork, not a mirror.** `AppModel.setArchived`
(`apps/ios/Zeron/App/AppModel.swift:474`) reads `if let demo { ...; return }`: a mutation reaches
`DemoDataset` **or** `WorkspaceStore`, never both. There is therefore no reaches-only-one-of-two
bug to guard against. The consequence is placement, and it is the reason `normalized` is called
above the fork rather than inside either arm.

`DemoDataset` needs no new type, because it stores the same `Chat`.

**Seed the shipped dataset with exactly three notes** in `DemoDataset.standard()`
(`apps/ios/Zeron/App/DemoDataset.swift:33`), on three different Colour Slots. Two of the three are
§9's fixtures, so both are on screen on every launch rather than being a test someone remembers to
run:

1. **A short note** on an active chat - the ordinary case.
2. **The 779-character note** on an active chat - longer than the cap, so the card's clamp and its
   elide are always visible.
3. **The unbreakable-URL note** on an archived chat - the shelf row gets something to show, and the
   118-character token is always on screen.

Three notes, three slots, both fixtures covered. Do not add a fourth: the fixtures are the reason
the seeds exist.

The demo fork gets no test: three lines, no branching worth one.

## 3. The five colours

**The five slots become a `NoteSlot` enum at the paint layer**, in a new
`apps/ios/Zeron/Theme/NoteSlots.swift` beside `Theme.swift`, at **L 0.660, C 0.130** - the
desktop's lightness, at the largest chroma every hue can actually reach in sRGB.

| slot | hue | oklch | reference hex |
| --- | --- | --- | --- |
| `rose` | 20 | L 0.660 C 0.130 | `#d66f71` |
| `amber` | 78 | L 0.660 C 0.130 | `#bd871c` |
| `green` | 152 | L 0.660 C 0.130 | `#4aa969` |
| `sky` | 232 | L 0.660 C 0.130 | `#179fd4` |
| `violet` | 302 | L 0.660 C 0.130 | `#a17dd4` |

**The oklch triples are what ship**, resolved at paint time through the existing `oklch()` helper
(`apps/ios/Zeron/Theme/Theme.swift`). The hexes are reference only; a stored hex could not follow
a re-tune, which is the same reason the wire refuses hex.

**The lightness holds; the chroma does not.** A near-black background does not want a different
lightness - L 0.660 already clears 3:1 by more than it did on the desktop, because this app's
surfaces are darker than frost over vibrancy and the theme is always dark. What the darker
background buys is headroom to separate the five harder, so the chroma rises from the desktop's
0.112 to 0.130. That raises the closest pair from ΔE 0.109 to **0.126** and costs 0.05 of contrast
ratio. Separation is the number that matters on a 3pt mark; contrast is the number already won.

### The gamut ceiling, and why the chroma is not higher

**At L 0.660 the largest chroma all five hues can reach inside sRGB is 0.1346, and `sky` is what
limits it.** Above it, `oklchToSrgb`'s per-channel clamp in `gammaEncode` silently drags the
out-of-gamut slots back:

| slot | asked for | actually paints |
| --- | --- | --- |
| `rose` `green` `violet` | L .6600 C .1500 | L .6600 C .1500 |
| `amber` | L .6600 C .1500 | L .6612 **C .1395** |
| `sky` | L .6600 C .1500 | **L .6657** **C .1411** |

That breaks the premise the palette rests on - one lightness and one chroma across all five, so no
slot shouts louder - and it breaks it invisibly, which is worse. **0.130 sits inside the ceiling
with headroom**, so every slot reaches the tone exactly. This is a constraint on any future
re-tune, on either app, and it is the reason the iOS values are allowed to differ from the
desktop's at all.

### Contrast, measured

Worst of the five per background, with `contrast_ratio` ported to Swift. The washes composite in
gamma space, which is what CoreAnimation does over an opaque sRGB surface.

| background | worst | best | clears 3:1 |
| --- | --- | --- | --- |
| `Theme.surface` `#0d0d0d` - **the real page colour** | **5.88** | 6.61 | yes |
| `Theme.bg` `#060606` - the app root behind the list | 6.13 | 6.89 | yes |
| pressed row, `elementHover` white 0.06 over the page | **≈ 5.20** | ≈ 5.85 | yes |
| selected row, `elementActive` white 0.10 over the page | **≈ 4.64** | ≈ 5.22 | yes |
| archived shelf marker dimmed to 55% | 2.51 | 2.72 | **no - and §4 does not dim it** |

**One correction, made while writing this spec and carried as a decision.** The prototype's wash
rows composited over `Theme.bg` `#060606` and reported 5.53 and 4.99. The Sessions list and the
archived shelf actually paint on `Theme.surface` `#0d0d0d`
(`apps/ios/Zeron/Views/HomeView.swift:41`, `apps/ios/Zeron/Views/SpaceView.swift:48`); `Theme.bg`
(`apps/ios/Zeron/Theme/Theme.swift:14`) is the app root behind them. The two wash numbers above
are **re-derived by the same arithmetic and are not prototype measurements** - they are marked
`≈` for that reason, and §9's contrast test is what pins them. **No verdict moves**: the worst case
falls from 4.99 to about 4.64 and still clears 3:1 with 1.64 to spare.

**The desktop's two contrast-driven known limits do not carry.** Every surface the marker paints
on clears 3:1, and the reason is structural rather than lucky: this app's page is darker than
frost over vibrancy, and there is no light appearance to lose to. The single sub-3:1 number in the
table is the shelf's dim, and §4 answers it by not dimming the marker.

### Separation

OKLab ΔE between the five, which is the honest measure between colours of one lightness (a WCAG
ratio between them reads ~1.00 and measures nothing). **Closest pair `rose`/`amber` at ΔE 0.126.**
It is the same pair the desktop found, so the ordering of the wheel is confirmed, not changed.

### Where they live

```swift
/// A Colour Slot a Chat Note can carry. The wire id is the raw value.
///
/// The MODEL keeps the slot id as a String (§1) so no parse can downgrade an
/// id a newer desktop wrote. This enum lives at the PAINT layer only: it turns
/// a stored id into a colour, and answers an id it has never heard of.
enum NoteSlot: String, CaseIterable {
    case rose, amber, green, sky, violet

    private var hue: Double { ... }          // 20 / 78 / 152 / 232 / 302

    /// The slot a new note starts on, and the fallback for an unknown id.
    static let fallback: NoteSlot = .rose

    var color: Color { oklch(noteSlotL, noteSlotC, hue) }

    /// The colour a STORED slot id paints. The only entry point a view uses.
    static func color(for id: String) -> Color {
        (NoteSlot(rawValue: id) ?? .fallback).color
    }
}

private let noteSlotL = 0.660
private let noteSlotC = 0.130   // ceiling is 0.1346 at this L, limited by sky
```

The enum is one edit for a sixth slot, `CaseIterable` **is** the Note Editor's row order, `rawValue`
**is** the wire id, and `init?(rawValue:)` returning `nil` **is** the unknown-id branch. Five named
constants cannot answer an unknown id at all; a lookup scatters one slot across an ids array and a
colours map, so a sixth slot becomes two edits that can disagree.

**The hue stays private** - a caller that could see a hue would be tempted to store one, and a
stored hue could not follow a re-tune. **The tone constants stay private and file-local**: they are
not `Theme` paint constants because they are not a colour, they are the recipe for five, and
`Theme`'s own rule is that paint constants are colours and layout numbers are kept apart. `Theme`
itself gains nothing.

**An unknown slot id paints as `rose`, matching the desktop.** A neutral grey fallback was built
and refused: it would make the same synced note violet on the desktop and grey on the phone, and a
user reads that as the phone being broken rather than as the phone being honest. Both apps being
wrong in the same direction is a far cheaper failure than being wrong in two directions. The cost
is named in §10.

**3pt is wide enough to tell the five apart**, spaced along a row and packed adjacent with no gap.
2pt is where it starts to go - adjacent `rose` and `amber` begin to merge. The slot dots in the
Note Editor were checked at 28, 22 and 16pt and are nowhere near a limit.

## 4. The resting marker

**3pt wide, as tall as the row's own title line, fully rounded, inset 2pt from the row's leading
edge, centred vertically - clamped to never exceed the row height less 3pt at each end.** One rule,
one set of numbers, on both row shapes.

| | session row (`ChatRow`) | archived shelf row |
| --- | --- | --- |
| where | `apps/ios/Zeron/Views/HomeView.swift:292`, used by `HomeView.swift:255` and `SpaceView.swift:23` | `apps/ios/Zeron/Views/ArchivedShelf.swift:134` |
| row height | **61.7pt** at the default text size | **36pt**, pinned (`ArchivedShelf.swift:153`) |
| width | **3pt** | **3pt** |
| height | **the row's title line** - 17.00pt at default type | **the row's title line** - 17.00pt at default type |
| height clamp | row − 3pt at each end (never binds; 55.7pt available) | row − 3pt at each end (binds only at the accessibility sizes) |
| corner radius | fully rounded - a capsule, so radius is half the width | same |
| inset from the row's leading edge | **2pt** | **2pt** |
| vertical placement | centred | centred |
| opacity | 1.0 | **1.0 - never the row's 0.55** |

**The height is a rule, not a number, and this is the section's whole point.** `Theme.sans` is
`Font.custom(_:size:)` (`apps/ios/Zeron/Theme/Theme.swift:73`), which **scales with Dynamic Type**.
A fixed 18pt marker is indistinguishable from the rule at the default size and comes apart at the
accessibility sizes, where the row grows and the marker does not: it reads as a tick against a
title twice its size. Both rows set their title in `Theme.sans(13)` for a 17.00pt line box, so at
the default size the rule resolves to **3 x 17pt** on each, within a point of the desktop's ported
3 x 18px.

**Why the clamp is 3pt and not 2 or 4.** At inset 2pt the wash box's 8pt corner arc has retreated
**2.71pt** from the row's top edge. A clamp of 3 puts the marker's end at 3pt when the clamp binds,
leaving **+0.29pt** of clearance against that arc. It is the smallest whole number that keeps the
marker inside the wash in the one case that can force it. A future change to the inset or the wash
radius has to re-check that, and §9 has the test.

**Without the clamp the shelf breaks, and it was seen breaking.** At
`accessibility-extra-extra-extra-large` the shelf's title outgrows its pinned 36pt row, adjacent
markers meet, and three separate notes render as one continuous multi-coloured stripe down the
shelf.

### The empty state stays free

**The marker is an `.overlay` on the row's wash box, so it takes part in no layout: a row with no
note is not merely similar to today's, it is identical.** Diffing the same list with markers on
against markers off leaves exactly one changed column band - **3.00pt wide, 14.00pt from the screen
edge** - and no title moves by a pixel on either row shape.

**The insets compose, they do not stack.** The list's `listRowInsets` leading is 12pt on both
sections, so the marker's leading edge lands 14.00pt from the screen edge on every row of both
shapes, and a marked session row lines up with a marked shelf row. The trailing gap between the
marker and the title is +3pt on the session row and +5pt on the shelf; both positive, so the marker
never crowds the text.

**Centring is unambiguous on the session row.** Its vertical padding is symmetric (6pt each end),
so the content box and the wash box share a centre. Centring in one centres in the other.

### The mechanism, and the simpler one that the shelf refuses

**What ships: an overlay on the row's wash box**, its height measured off the row's own title with
`onGeometryChange` and clamped to the row. It costs one piece of per-row state and it works on both
shapes.

**What an implementer will reach for, and why it fails: an overlay on the title `Text` itself.**
Given a width and no height, an overlay inherits its host's line box for free - no measurement, no
clamp, and it follows Dynamic Type automatically. It is strictly simpler and it works on the
session row. **The shelf refuses it**: the shelf puts a dimmed `HarnessBadge` *before* the title, so
the same overlay lands **38pt** from the screen edge, between the mark and the title, instead of
14pt on the row's leading edge. The badge is conditional (`if let harness`), so no fixed offset
repairs it, and anchoring to the `HStack` instead just returns to measuring. This is written down
because the simpler mechanism fails on exactly one of the two rows.

### The shelf's dim, and what does not collide

**The marker paints at full strength and does not take the shelf's 55% dim.** At 55% it measures
2.51:1, `violet` is close to gone and `sky` is muddied, and no tone fixes it - lifting the lightness
only reaches 2.95. The shelf's dim exists to quiet the row's *content*: 13pt of title and a 14pt
harness mark. The marker is 3pt wide and there is not enough ink in it to shout. So the map's one
remaining sub-3:1 number is gone rather than accepted.

**Nothing collides.** The PR badge and the `MiniSpinner` both ride the row's bottom-**trailing**
corner and the marker owns the leading edge. Corner clearance, computed:

| | marker top | corner arc at inset 2pt | clearance |
| --- | --- | --- | --- |
| session row | 22.4pt | 2.71pt | +19.6pt |
| shelf row | 9.5pt | 2.71pt | +6.8pt |
| either row, clamp binding | 3.0pt | 2.71pt | +0.29pt |

**A note does not change the list's sort order.**

## 5. The Note Card

The surface that shows the note in full. **A long press on the row opens it** - there is no hover
on a phone, and the desktop's hover apparatus is redesigned rather than approximated.

### Mechanism, and the constraint that governs everything else

- **Primitive: `.contextMenu(menuItems:preview:)` on the row**, with iOS 26's zoom transition. The
  same modifier carries §6's menu items, so the card and the menu ride one gesture.
- **One mechanism on both row shapes.** The 36pt shelf row opens the same card from the same
  gesture, so there is no degrade anywhere. A change to one that does not reach the other is a
  regression.
- **The preview attaches only to a row that has a note.** A bare row passes no `preview:` closure
  at all, so the system lifts the row itself (§6).

> **A `.contextMenu` preview does not adopt its content's height. It must be given one, or a card
> taller than about two lines is clipped mid-sentence.**

This is the phone's central card constraint. The preview lays its content out correctly and then
masks it: a three-line note lays out at 324 x 91pt and only part of it is drawn.
`.fixedSize(horizontal: false, vertical: true)` does not help - the card is not being squeezed -
and neither does moving the attachment point; the same press was built with the menu on the row's
wash box and on the row's own content stack inside the Button's label, and both clip identically.
**Only an explicit `.frame(height:)` fixes it**, and it fixes it completely.

**So the card's height must be known before the press**, which means measuring the note's rendered
height at the card's width, per chat, and **taking the content size category as an input** (see
"Dynamic Type" below - this is the one place the mechanism is easy to get subtly wrong). The
desktop measures its card a frame early too, for centring rather than for sizing, so the mechanism
ports even though the reason does not.

**Named as a cost, not hidden**: if the forced height overshoots the content, the surplus draws as
empty container under the card. Height and content must agree, so a stale cache is visible rather
than silent.

**Named as deliberately unpinned**: the exact height at which the preview's own mask starts cutting
was never reduced to a number. It sits between two and three lines of 13pt text on the 61.7pt
session row. Do not write a number here - the forced height removes the need for one.

### Appearance

| | |
| --- | --- |
| base | `Theme.surface` |
| tint | the note's Colour Slot at **0.10** across the card |
| hairline | **1pt** of the same Colour Slot at **0.32** |
| corner | **12pt, continuous** - and it is a mechanism, not just a number. See "The corner" below |
| padding | **12pt** horizontal, **10pt** vertical |
| text | **13pt** `Theme.sans`, `Theme.text` |
| maximum text width | **300pt**, so the card is **324pt** wide. It sizes to its content: a five-word note is a five-word card |
| overflow | a height clamp resolving to **10 lines at the default text size**, then elide. The card never scrolls |
| second line | the row's `space @ device` string, **11pt**, `Theme.textMuted` at 0.7 |

**The card carries the location line, and that is not a decoration.** A `.contextMenu` preview
**replaces** the row for the length of the press - the row is lifted out and the card is drawn in
its place - so at the exact moment a user is reading the note, the row's own location line is not
on screen. The card restates it. The desktop's card floats beside its row and never had this
problem. The string is `ChatRow`'s own (`apps/ios/Zeron/Views/HomeView.swift:378`), read at
`HomeView.swift:322`. Adding the title as a third line was refused: it is redundant with the note
in almost every real case, and three registers in a card that exists to show one sentence is a card
that has stopped being a card.

**The desktop's 320px maximum text width does not port.** With this card's 12pt padding it makes a
344pt card on a 402pt phone. Swept at 240, 280, 300 and 340pt of text - 264, 304, 324 and 364pt of
card - on the same note: 240 turns a three-line note into four for no gain; 280 is correct and is
the close runner-up; **300 is the answer**, three lines where 240 needs four and still 39pt of
margin each side; 340 is refused, because at 364pt of card it reads as a banner across the list.
344 itself was never built, so it is a direction and not a measurement - but the sweep establishes
that the card gets worse as it approaches the screen's width.

**The card never scrolls and never widens.** A note far longer than the cap fills to the clamp and
elides with a tail ellipsis. An unbreakable token - a 118-character URL with no space in it - wraps
at character boundaries inside the 300pt cap and never widens the card. That last one is worth
noting because it is the opposite of the desktop's problem: the desktop's card had to be told to
clip, and SwiftUI breaks the token for free.

### The corner

> **12pt continuous, held by a 14pt veil of page colour inside the preview, because the platter
> owns the mask.**

**A plain radius does nothing here, and this has to be built the stated way or the card ships as an
oval.** The system's preview platter masks the preview with a corner of its own, and that corner is
roughly half the card's height on a short note. Measured, with *ovalness* defined as
`arc-depth / (height / 2)`, where 1.0 is a pill:

| fixture | card | corner | ovalness |
| --- | --- | --- | --- |
| one word | 119 x 57pt | 24.3 across, 22.3 down | **0.79** |
| a short note | 195 x 58pt | 32.7 across, 23.0 down | **0.79** |
| three lines | 324 x 91pt | 36.7 across, 28.7 down | **0.63** |
| the 36pt shelf row | 255 x 37pt | 21.0 across, 19.7 down | **1.06 - a pill** |

The card's own 12pt was drawn and then masked over, which is why the hairline runs straight into the
arc and stops. **The arc grows with the card** - 24pt across on the smallest, 44pt on the largest -
so it is not a constant a layout could design around.

**The mechanism:** inset the card **14pt inside the preview**, and fill that margin **opaque** in
the page's own colour as the system's dim leaves it. The platter's arc then cuts flat colour instead
of the card, and the card's own corner is the only corner on screen. Measured after: **10.3 across,
8.3 down, ovalness 0.18**, and those numbers are **identical on every fixture, on both row shapes,
and at every text size**. The corner stops moving with the card.

- **14pt is a measurement, not a taste.** A corner of radius `r` cuts a square corner to a depth of
  `r(1 − 1/√2)`, about `0.3r`. The largest arc measured is 44pt across, so under 14pt of margin the
  arc never reaches the card - proved at the largest card this build can make, at AX-XXXL.
- **The margin must be opaque.** A transparent inset was built and refused: it exposes **the
  platter's own tray**, a grey rounded surface the card then visibly sits on. Two surfaces where the
  design has one. That refusal is what proved the platter draws a background at all - it is
  invisible while the card covers it exactly.
- **The veil is applied OUTSIDE the forced height.** The preview is `card + 2 x 14` in both axes;
  the card is not. A height rule that starts measuring the padded box silently re-opens the clip
  above.
- **The radius is 12pt, continuous.** Swept at 8, 12, 16 and 20 on the three-line card: all four read
  as rectangles, 8 stops registering as a corner at the small card sizes, and 20 starts going round
  again on the shortest notes.
- **`.contentShape(.contextMenuPreview, _)` does not reach the platter**, built at three attachment
  points - on the row immediately before `.contextMenu`, outermost on the preview content over the
  forced height, and inside the forced height directly on the card. All three frames are
  pixel-identical to the defect. The claim is exactly that and no wider: those three placements do
  nothing.
- **The `UIContextMenuInteraction` / `UIPreviewParameters.visiblePath` route was priced and
  declined, not tried.** It would own the mask outright, and it would replace the SwiftUI
  `.contextMenu`, so §6's three menu items, §8's custom actions and its finding that the menu adds
  nothing to the accessibility tree, the trailing swipe, and iOS 26's zoom transition would all have
  to be re-established rather than inherited. Nothing says it would not work.

**The veil's colour, and the recipe for re-deriving it.** While a context menu is up, iOS puts a dim
over everything **except** the preview, and the preview is exempt - so a colour authored inside the
preview renders exactly as authored while the page beside it does not. The veil therefore cannot be
the page colour; it has to be the page colour **as the dim leaves it**. The dim is linear, solved
from 27 sample pairs across the tonal range:

```
pressed = 0.7917 x rest + (4.7, 4.7, 8.7)
```

which is a dark blue-grey at about 21%. The page behind the list is **`Theme.surface` `#0d0d0d`**
(`apps/ios/Zeron/Views/HomeView.swift:41`, `apps/ios/Zeron/Views/SpaceView.swift:48`), and it goes
to **`#0F0F13`**: the veil renders `(15, 15, 19)` and the page beside it reads `(15, 15, 19)`.

> **Correction carried into this spec.** The prototype recorded this constant as "`Theme.bg`
> `#0D0D0D`". `Theme.bg` is `#060606` (`apps/ios/Zeron/Theme/Theme.swift:14`) and `Theme.surface` is
> `#0d0d0d` (`:16`). The arithmetic and the measured `(15, 15, 19)` both belong to `#0d0d0d`, which
> is the list's actual page, so the number is right and the constant was misnamed. An implementer
> who veils with `Theme.bg` gets `#09090E` and a veil that visibly pops.

**The veil does not pop on the open**, which had to be checked rather than assumed, because the
system applies the dim over the course of the zoom rather than instantly. Recorded at 30fps and
stepped: the veil and the page beside it stay within 2/255 of each other on every frame, including
the frames where the card is still translucent.

Two residuals, both named and neither fixable with a flat colour: the platter casts a **shadow**, so
the page is 1 to 2 units darker immediately around it than further away - a gradient that exists
under the defect too, and is below perception at these values. And the card covers **14pt more of
its neighbours** while it is up, because the preview is 28pt taller and wider. That is the price of
the margin.

**Increase Contrast changes nothing** - verified with the setting queried back as `enabled` rather
than merely set: same card, same corner numbers, same page colour.

### Dynamic Type

> **A clamp is a height, fixed at what N lines occupy at the DEFAULT text size. The line count falls
> as the text grows.**

This is the one rule §5, §7 and §8 all obey, and it is stated once here and applied three times.
For the card it resolves to:

| content size | the card's clamp |
| --- | --- |
| L (default) | **10 lines** |
| XXXL | **7 lines** |
| AX-L | **5 lines** |
| AX-XXXL | **3 lines** |

Each one ends in an ellipsis and each keeps the `space @ device` line.

**The defect this fixes, so nobody re-introduces it.** A height computed with `Theme.sansUI`
(`apps/ios/Zeron/Theme/Theme.swift:93`) is a raw `UIFont` and does **not** scale, while the card
paints with `Theme.sans` (`:73`), which **does**. Measure one with the other and the forced height
is a default-size height whatever the user's text size is, with nothing warning: the card clips at
every size above XXXL, a short note is cut mid-glyph at AX-L, and at AX-XXXL a three-line note
renders its first three words and stops **with no ellipsis at all**. The mirror of `Theme.sans` for
measurement is `UIFontMetrics(forTextStyle: .body).scaledFont(for:)`.

**The tempting fix is wrong and was refused on the frame.** Measuring with the scaled font and
keeping ten lines makes the card honest about its own content and pushes **"Clear note" off the
bottom of the screen** at AX-XXXL. A card that is honest and a menu item that cannot be reached is
the worse trade. The height budget is what keeps both the card and the menu on screen.

**The clamp the `Text` is given has to agree with the height.** `lineLimit` resolves to the same
falling number. Otherwise the elide lands at line ten while the mask cuts at line three, and the
ellipsis never appears - which is exactly the original defect, and is why this is two changes and
not one.

**A scroll was never a candidate**: a `.contextMenu` preview is not interactive.

### What does not port, and is a genuine simplification

**The desktop's whole hover apparatus has no phone equivalent and correctly does not port**: the
350ms open, the 120ms close, the click-dismiss latch, the resort close, the scroll close, the four
fields of `Shell` state and the narrow-window floor. A long press is its own gesture and the system
owns its lifecycle. The phone inherits none of that state. **No row height changes**, so the list's
`Motion.resort` FLIP glide is untouched.

## 6. The long-press menu

**Three items on every row, noted or not.** The app has no `.contextMenu` today; this introduces
its first.

| | |
| --- | --- |
| mechanism | `.contextMenu(menuItems:preview:)`, on **every** row of both shapes |
| item 1 | **"Add note…"** with no note, **"Edit note…"** with one. `square.and.pencil` |
| item 2 | **"Archive"**, or **"Unarchive"** on the shelf. `archivebox` / `arrow.up.bin` |
| item 3 | **"Clear note"**, destructive role, **only when a note exists**. `trash` |
| preview | the Note Card (§5) on a noted row; on a bare row **no preview closure at all**, so the system lifts the row itself |

- **The label changes with state**, carried from the desktop. That reasoning gets stronger on the
  phone, not weaker: on a row with no note, the menu item is the only thing on screen that says a
  note is possible.
- **Archive earns its place.** A menu holding one item under a full-width card reads as an accident.
  Archive is what the row already knows how to do and what the trailing swipe already does, so the
  menu and the swipe say the same thing rather than two different things.
- **The bare row previews nothing custom.** A muted "No note on this session" card was built and
  refused: it carries no information, and "Add note…" in the menu is the whole affordance. **This is
  also the phone's whole answer to discoverability** - the phone adds no resting affordance, because
  a list that §5 chose specifically to keep calm should not carry a surface whose only content is
  "there is no note here".
- **Clear note lives in the menu only**, never in the sheet. It was built in the sheet too and
  refused: two Clears for one act, when the in-sheet path is already select-all, delete, Save.
- **The card and the menu do not fight for room**, including on a note long enough to run to the
  full clamp: iOS 26 lays the card above the items and shifts the pair to fit, with both whole on
  screen. This holds *because* §5's clamp is a height; it is the `scaled` rule that pushed "Clear
  note" off the bottom.
- **The trailing swipe survives on both row shapes.** A long press and a horizontal drag are
  different gestures and iOS tells them apart. Archive on the session row
  (`apps/ios/Zeron/Views/HomeView.swift:261`) and Unarchive on the shelf
  (`apps/ios/Zeron/Views/ArchivedShelf.swift:160`) are both unchanged.

## 7. The Note Editor

A detent bottom sheet built from the app's own `SheetCard` and friends
(`apps/ios/Zeron/Views/SheetUI.swift`). Every other authoring surface in the app is one.

| | |
| --- | --- |
| title | **"Session note"**, inline, in a `NavigationStack` |
| chrome | **Cancel left, Save right**, in the nav bar. Not the app's pinned pill |
| detent | a custom **`.height()` sized to the sheet's own content**, growing with the field |
| order | **field → slot row.** Nothing else |
| background | `SheetStyle.panel`, drag indicator visible, corner radius 32 - the app's own sheet, unchanged |
| default slot | a new note starts on **`rose`**, already selected; editing shows the stored slot ringed |

**The detent rule, and its one measured number.** `detent = content height + 60`, where 60 is the
nav bar, the grabber above it, and the room under the content. **60 is measured off the frames, not
derived** - re-check it if the nav bar changes. Content floors at about **173pt** for a bare note
(padding 40 + field 75 + 14 + slot row 44) and rises to about **230pt** as the field grows to its
ceiling.

**`.medium` is refused on a measurement, not on taste.** With the keyboard up it swells to
near-full-screen and leaves roughly **470pt** of empty container between the slot row and the
keyboard. A pinned 280pt was the first fix and is still wrong on a long note; the content-sized
detent is the rule.

**The pill lost, and it was close.** `SheetPrimaryButton` (`apps/ios/Zeron/Views/SheetUI.swift:143`)
is the app's own shape and `SpaceView` uses it, but it needs a taller detent to hold the pill clear
of the keyboard and it puts Save a thumb-stretch from the field.

### The field

| | |
| --- | --- |
| control | a `UIViewRepresentable` around `UITextView` |
| font | **15pt**, matching `SheetSelectRow`'s title, through `UIFontMetrics` so it scales |
| floor | **3 wrapped lines**, grows to **6**, then scrolls - both as **heights**, per §5's one rule |
| placeholder | **"Write a note about this session…"**, a `UILabel` child pinned to the text container inset |
| chrome | `backgroundColor = .clear`, `textContainerInset` 10/12, `lineFragmentPadding = 0`, `keyboardAppearance = .dark` |
| focus | lands in the field on open, from **`didMoveToWindow`** |
| accessibility label | **"Note"** (§8) |
| cap | **280 characters** |

**The representable carries this app's glass**, so the `TextEditor` fallback is not taken. Inside
`SheetCard` it is indistinguishable from the composer's `TextEditor` at rest.

Four things a `UITextView` in SwiftUI does not give for free, each found by building it:

- **Focus needs `didMoveToWindow`.** `becomeFirstResponder()` from `makeUIView`, even deferred one
  run loop, is too early: the view is not in a window and the keyboard never comes up. The caret
  appears and the keyboard does not, which reads as a simulator problem and is not one.
- **Growth belongs in `sizeThatFits(_:uiView:context:)`, not in the delegate.** That is the only
  place SwiftUI hands over the **proposed width**, and the height is a function of it. Measuring off
  `bounds.width` gives a floor computed at width zero on the first pass.
- **The floor and ceiling must be measured, not multiplied.** `font.lineHeight * 6` is not the height
  of six laid-out lines - TextKit's line fragment is slightly taller - so a ceiling built on the font
  clips its last line. Measure with `boundingRect` on a probe of N lines in the same font.
- **Horizontal compression resistance must be lowered.** A `UITextView`'s intrinsic content size is
  its *content* size and it resists compression at `.defaultHigh`. Left alone, a long
  single-paragraph note makes the field hundreds of points wide: the note draws as one clipped line
  and the slot row is shoved off the sheet entirely. `.defaultLow` on both compression resistance
  and hugging, horizontally, fixes it.

### The cap mechanism

**Clamp in `textView(_:shouldChangeTextInRanges:replacementText:)`. Stand down while
`markedTextRange` is not nil. Add a second clamp in `textViewDidChange` as the floor.** Implement
the plural delegate only; the target is iOS 26.0, so the soft-deprecated singular is never needed.

> **The Swift label is `shouldChangeTextInRanges`, and the obvious spelling silently does nothing.**
> Swift keeps "Ranges" on the plural so it does not collide with the singular. Writing
> `shouldChangeTextIn ranges: [NSValue]` - which is what the singular's label looks like -
> **compiles, satisfies no protocol requirement, exports no selector, and never fires.** There is no
> warning. The cap then holds only from `textViewDidChange`, which draws the over-cap character and
> takes it back, so the failure looks like a design flaw rather than a typo. Confirmed at the ObjC
> runtime: `responds(to: Selector(("textView:shouldChangeTextInRanges:replacementText:")))` is
> `false` for the wrong spelling and `true` for the right one.

Why this hook and not a SwiftUI one: **SwiftUI offers no character cap and no view of the input
method at all.** That is a verified absence - neither iOS 26.5 SwiftUI swiftinterface carries a
`characterLimit` or `maxLength` symbol, nor any `marked`, `composition`, `ime` or `inputMethod`
symbol on the text-input surface. Every SwiftUI hook runs **after** the edit lands.
`shouldChangeTextInRanges` runs **before** it, which is the whole difference, and it is the true
analogue of the desktop's one clamp point.

Two properties the mechanism carries, and one it does not:

- **Characters, not bytes.** Grapheme-cluster counting is free inside `String` space. It stops being
  free at the `NSRange` to `Range<String.Index>` conversion, which is where it earns a test again.
- **Room is measured after the deletion.** The plural signature hands this over for free: it passes
  the ranges to be deleted alongside the text to insert. A field already at 280 still accepts a paste
  over a selection.
- **The cut lands on a character boundary** carries as a **code comment, not a test**:
  `String.prefix(_:)` makes a split grapheme impossible, so the test cannot fail.

> **A clamped edit leaves the caret at the start of what it wrote, and the restore must be deferred
> one run loop.** "The caret never has to be restored" holds only for an edit the delegate
> **permits** - UIKit applies it and moves the caret. On the clamped path the delegate applies the
> edit itself, and `replace(_:withText:)` leaves the caret at offset 0 of the replacement, so a
> 300-character paste clamped to the cap ends with the caret before the first character. Setting
> `selectedRange` inline reads back correctly and is then dragged back to 0 by the SwiftUI round
> trip; posting it to the next run loop holds.

**Verified by typing, not by reading**: a 300-character system paste reaches the delegate and clamps
exactly; every keystroke of a Japanese composition arrives with `markedTextRange` non-nil and stands
down; and composition **can** exceed the cap - four marked kana against a cap of three, counter
reading 4/3 - so the commit is what the `textViewDidChange` floor exists to cut.

### The slot row

**Five dots at 18pt, 6pt apart, in 44pt hit targets, with a 1pt ring in `Theme.text` at 0.85 held
4pt out from the chosen dot.** Row order is `NoteSlot.allCases`: rose, amber, green, sky, violet.

The desktop's 14px dot does not port and its 24px target certainly does not - 24 is under the
phone's 44pt minimum. The ring is held one cell out from the **dot**, not from the 44pt target: at
44 it becomes a hoop with the dot rattling inside it. A check mark was refused - a tick sized to the
dot crowds it and eats the colour the row exists to show - and so was growing the chosen dot, which
cannot be read without a second dot to compare against, which is exactly what a selected state must
not need.

**The dots do not scale with Dynamic Type and should not.** A colour swatch is not text.

### The counter

**The desktop's rule ports verbatim: hidden until 240, `Theme.textMuted`, turning `Theme.text` at
280.** It sits on the slot row, pushed right. Verified at its real thresholds: absent at 239, muted
at 245, full at 280.

### Keys, dismissal, and clearing

- **Return saves and dismisses.** The newline is refused before it lands.
- **Its price, stated plainly: the phone cannot author a multi-line note.** A note written with line
  breaks on the desktop is unharmed - it loads into the field and saves back with its newlines
  intact - but no newline can be typed here. This is a real narrowing against the desktop, taken
  deliberately because Save is one thumb away and a note is one sentence.
- **A swipe-down discards, with no prompt.** The desktop's Escape, unchanged, so Cancel and the drag
  mean one thing rather than two. Driven with dirty text: forty characters typed, dragged shut, and
  the row has no marker.
- **Nothing asks for confirmation, on either path.** The desktop's reasoning holds on a phone where
  a mis-tap is likelier than a mis-click: "Clear note" and the clear-the-text-and-save path do
  exactly the same thing, and a confirm on one path only would make them disagree. The app's
  `.confirmationDialog` precedent (`apps/ios/Zeron/Views/ArchivedShelf.swift:114`) is for *Clear
  archived*, which destroys many sessions at once; a note is one short capped text.

### Haptics

**The slot row fires `UISelectionFeedbackGenerator().selectionChanged()`. Save fires nothing.**
Tapping a slot is a selection and the app already gives selections exactly this feedback
(`apps/ios/Zeron/Views/SheetUI.swift:49`), so the Note Editor feels like the app's other sheets
rather than like a new thing. Save is deliberately silent: the sheet closing and the marker
appearing is the feedback, and the app has no success-haptic anywhere for this to match.

### The stated cost of this section

**The app ends up with two text-editing stacks.** The composer is `TextEditor` with the
`AttributedString` and `selection` overloads (`apps/ios/Zeron/Composer/ComposerView.swift:150`); the
Note Editor's field is the app's **first** `UIViewRepresentable`. The composer's placeholder
overlay, its hidden-`Text` height mirror and its `.scrollContentBackground(.hidden)` are all
`TextEditor`-shaped and none of them port. This is a real maintenance cost, accepted because no
SwiftUI path can hold the cap without fighting the input method, and it is written here so a future
reader finds it stated rather than discovers it.

## 8. Accessibility and Dynamic Type

### The one rule

> **A clamp is a height, fixed at what N lines occupy at the DEFAULT text size. The line count falls
> as the text grows.**

Stated once in §5 and applied three times: the Note Card's ten-line clamp (§5), and the Note Editor
field's three-line floor and six-line ceiling (§7). One rule, because the card and the sheet were
asked the same question and gave the same answer.

**The sheet's overrun, which is what the ceiling prevents.** Sheet top, keyboard up, with a long
note in the field:

| content size | ceiling as a line count | ceiling as a height |
| --- | --- | --- |
| L | 224pt | - |
| AX-L | 133pt | 224pt |
| AX-XXXL | **57pt** | **188pt** |

At 57pt the sheet is behind the status bar, the fitted detent has silently become `.large`, the slot
row is behind the keyboard and the counter is cut in half. **A user at that text size cannot
recolour a note at all.** With the height ceiling both come back above the keyboard, and the sheet
never has to change kind - `.large` is not needed.

**The cost is on the floor, and it was looked at rather than assumed.** A short note at AX-XXXL now
gets a field as tall as its content plus a little slack, where a scaled floor reserved three scaled
lines. The trade is right: a roomy field above a Save button you cannot reach is not a trade.

### What a noted row says aloud

**The row gains a value, and the value is the note**, on both row shapes:

```
Button 'zeron @ MacBook Pro, Working, Streaming veil on transcript rows, veil-fade'
       value='Note, Ask Dana before this merges'
Button 'OKLCH conversion drift, 3d'
       value='Note, Gamut clamp was silent; write the test'
```

- **The desktop's known limit 1 - "the note is pointer-only" - does not carry.** The phone does
  better, and it costs one line.
- **A value, not a rebuilt label.** VoiceOver reads the label and then the value, so the note lands
  at the end of the row's existing announcement and nothing already there moves. The alternative -
  `.accessibilityElement(children: .ignore)` with an explicit label - would mean hard-coding
  location, status, title and branch into one string, and `ChatRow` builds those from several `Text`
  views. That cost is not paid.
- **The prefix is "Note, ".** Without it a note that opens with a noun is indistinguishable from a
  fifth column of the row.
- **No length cap on the spoken note.** The card clamps because it has a screen to fit into; speech
  has no such bound, and a user scanning a list swipes past.
- **"Has a note" was refused.** It tells a user something is there and then refuses to say what.
- **The marker stays silent.** It is 3pt of colour carrying a Colour Slot, and a colour is not a
  label.

### The menu's items as custom actions

**The `.contextMenu` adds nothing to the accessibility tree.** The tree was dumped with the menu
attached and without it and the two are identical. A long press is not a VoiceOver gesture. **So the
row carries the items itself**, as `.accessibilityActions`:

```
noted row     actions=['Edit note', 'Clear note', 'Archive']
bare row      actions=['Add note', 'Archive']
shelf row     actions=['Edit note', 'Clear note', 'Unarchive']
```

> **`.accessibilityActions` presents the REVERSE of the declared order, and the `.swipeActions`
> action is not orderable against it.** `Archive` comes from the swipe and lands after everything
> declared. So the two note actions must be **declared in the reverse of the order they should be
> heard in**. This is a trap of the same shape as `shouldChangeTextInRanges`: it compiles, it runs,
> and it is wrong silently.

"Destructive last" was recommended, built, and **found unreachable** - the only two reachable orders
are `Clear note, Edit note, Archive` and `Edit note, Clear note, Archive`. The second is chosen, and
its `Archive` is last because the platform put it there.

**06's dual menu label survives on its sighted reasoning alone.** It was partly justified by the
menu being the only place the shell said in words that a note exists; the row's value and these
actions have dissolved that half. And the refusal of a resting affordance (§6) gets *stronger*: a
VoiceOver user reaches "Add note" on every row without going near the menu.

### The slot row aloud

```
spoken    'Rose note colour'  'Amber note colour'  'Green note colour'
          'Blue note colour'  'Violet note colour'
value     'Selected' on the chosen one
```

- **`sky` becomes "Blue".** It is a storage token, not a word a person uses for a colour they are
  picking. The other four are ordinary colour words and survive unchanged. **This does not touch the
  wire**: the id stays `sky`.
- **The role is spoken because the control has no other name.** Five bare colour words in a sheet say
  nothing about what choosing one does.
- **The ring gains an explicit `Selected` value.** `.accessibilityAddTraits(.isSelected)` does not
  appear in any tree this effort could produce, so the ring's selected state would otherwise be
  claimed by nothing.

### The field's name

**The Note Editor's field has no accessibility label at all** until this build gives it one -
VoiceOver reads the note text and then "text field". **It gets the label "Note".** One line, and it
is the difference between a named control and an anonymous one.

### Reduce Motion

**The app says nothing, because it has nothing to say.** The app does see the setting, and its own
animations already fall to nil through `motionAnimation`
(`apps/ios/Zeron/Theme/Motion.swift:55`). The Chat Note adds no animation of its own: the card and
the menu are both presented by `UIContextMenuInteraction`, and there is no API to influence that
presentation, so whatever it does under Reduce Motion is the system's and is correct by definition.

**The rule for the implementer: the Chat Note adds no animation outside `motionAnimation`.**

## 9. Test set

Thirty-seven tests. Each earned its place; the **seven** marked **guard** are the non-obvious ones
that exist to stop a future change from breaking something silently.

### Model, read and write (§1, §2)

1. `ChatNote.normalized` returns `nil` for empty text and for whitespace-only text.
2. `ChatNote.normalized` trims the ends and keeps the middle intact.
3. The parse drops a stored note with no `color`, and drops one with no `text`.
4. The parse keeps a note with an unknown slot id, with the id unchanged.
5. The parse keeps text longer than 280 characters whole.
6. The clear writes `.null`, not an absent key.
7. Clearing from the menu and saving blank text produce the same stored result. This is what makes
   "no confirmation" honest rather than convenient.

### Colour Slots (§3)

8. `NoteSlot.color(for:)` returns `rose`'s colour for an id no case matches, and for the empty
   string.
9. `NoteSlot.color(for:)` round-trips each of the five ids to its own colour.
10. **Guard: all five slots are inside sRGB at the shipping tone** - no channel clamps. This is what
    stops a future chroma bump from silently breaking the one-lightness-one-chroma premise, and it is
    the one test here that is not obvious from reading the code.
11. Worst-of-five contrast is at or above 3.0 against **`Theme.surface`, the pressed wash and the
    selected wash composited over `Theme.surface`** - the real page colour, not `Theme.bg`. This test
    is also what pins §3's two `≈` numbers.
12. Closest-pair OKLab ΔE is at or above 0.12.
13. `NoteSlot.allCases` is in wheel order `rose amber green sky violet`, which is the Note Editor's
    row order.

### The resting marker (§4)

14. The height rule resolves to the title's line box - 17pt on both row shapes at the default content
    size - and the clamp does not bind there.
15. The marker's height never exceeds `rowHeight − 2 * cap`. The reproducer is the shelf row at
    `accessibility-extra-extra-extra-large`.
16. **Guard: `cap` is greater than the wash's corner intrusion at the marker's inset.** Today that
    reads 3.0 > 2.71. It stops a future change to the inset or the row's corner radius from silently
    pushing the marker outside the wash when the clamp binds.
17. A row with no note renders identically to the same row with the marker code removed - the overlay
    contributes no layout, on both row shapes.
18. The shelf marker's opacity is 1.0, not the 0.55 its sibling content carries.
19. The marker's leading edge sits 14pt from the screen edge on both sections, so a marked session
    row and a marked shelf row line up with each other.

### The Note Card (§5)

20. A row with a note renders at the same height as the same row without one - 61.7pt on the session
    row, 36pt on the shelf.
21. The over-cap fixture renders to the clamp and elides, and does not scroll.
22. The unbreakable-URL fixture does not widen the card: the card's width stays at or below 324pt
    with the token present.
23. **Guard: the card's forced height equals its measured content height, at each content size
    category.** It guards both failures at once - too small clips the note, too large draws empty
    container under it. The reproducer is a three-line note, because one and two lines pass either
    way.
24. **Guard: the forced height is the card's height, not the preview's.** The preview is
    `card + 2 x 14` in both axes. A rule that starts measuring the padded box silently re-opens the
    clip.
25. **Guard: the card's rendered corner is the card's corner.** The measured arc is the same on the
    shortest note and the longest, on both row shapes, and at every text size. Under the defect it
    moved with the card, which is what made a short note a pill.
26. **Guard: the veil equals the page under the dim.** One pixel inside the margin and one pixel on
    the page beside it, in the same held-press frame, must not differ by more than 2 per channel.
    This is the guard on the one constant this build introduces.
27. The shelf row and the session row open the same card from the same gesture. A change to one that
    does not reach the other is a regression.
28. The card carries the location line, so a note read at full length still says where its session
    runs.

### The Note Editor (§7)

29. **Guard: the clamp refuses rather than trims after the fact - the over-cap character is never
    drawn.** This is the test that catches the wrong Swift label, and it is the only one that does.
30. A 300-character paste into an empty field leaves exactly 280 characters **and the caret at 280**.
    One test, both of the delegate's two traps.
31. The cap counts characters, not bytes - 280 means the same for an emoji as for an `a`. The cut
    landing on a character boundary is a **code comment instead**, because `String.prefix(_:)` makes
    it impossible to fail.
32. Room is measured after the deletion: a field already at 280 accepts a paste over a selection.
33. A commit from an input method that lands over the cap is truncated to the cap. This is the one
    thing the prototype proved only in halves - the delegate's stand-down and the
    `textViewDidChange` floor were each proved separately - so it is carried as a test rather than as
    a claim.
34. A note longer than one line does not widen the field. The guard on the compression resistance; a
    single-paragraph fixture with no spaces is the reproducer.
35. The field floors at three lines and stops growing at six, measured against laid-out line height
    and not `font.lineHeight * n`.
36. The sheet's detent equals its content height plus the chrome. Too small scrolls a sheet that
    should not scroll; too large draws the void `.medium` draws.

### Gestures (§6)

37. A long press and a trailing swipe both still work on both row shapes. One gesture added must not
    cost the one that was there.

### Fixtures

Both are seeded demo notes (§2), so they are on screen on every launch rather than being a test
someone remembers to run:

- **A 779-character note** - longer than the cap, because storage cannot promise a short note (§10,
  limit 10). **It is 779, not the desktop's 671.** The iOS fixture was written to match the
  desktop's and did not; it was counted, not eyeballed, and every finding about it holds at 779.
- **An unbreakable URL** - one 118-character token with no space in it.

## 10. Known limits

State these in code comments or tests where they bite. **None is a defect to fix in this build.**
Limits 1 to 8 are §8's, carried as written.

1. **The Colour Slot is never spoken on a row.** A colour is not a label, and the marker carries
   nothing else. The note text is spoken instead, so nothing is lost.
2. **The context menu's own items are unreachable to VoiceOver**, as far as this effort could
   measure. The custom actions exist *because* of that, not beside it.
3. **The rotor's order is the platform's, not ours**: `Edit note, Clear note, Archive`. Declaration
   order is reversed and `Archive` is not orderable against it.
4. **The ring's `.isSelected` trait is unverified.** No tool available here reports it. The explicit
   "Selected" value exists for that reason.
5. **Reduce Motion on the context menu's transition is unverified**, and the app has no API to
   influence it. Whether the system swaps the zoom for a cross-fade was not measured: a 30fps capture
   over a 0.15s transition, on a simulator whose video omits the background blur, cannot tell those
   apart.
6. **The counter wraps to two lines at AX-XXXL, and the field's last visible line is cut by its own
   scroll.** Both cosmetic, and both survive the height rule.
7. **The accessibility answers were judged on a simulator, without live VoiceOver.** It weakens the
   wording answers, not the geometry ones.
8. **The archived shelf row still clips its own content at the accessibility text sizes.**
   Pre-existing - `ArchivedShelf.swift:153` pins the row at 36pt while its 13pt title scales with
   Dynamic Type. Not caused by this build and not fixed by it; §4's clamp keeps the marker inside a
   row the text is already leaving. It wants its own fix, outside this build.

And this build's own, in the same voice:

9. **The Note Card's corner costs one constant that tracks a system effect.** The veil is the page
   colour *as the system's menu dim leaves it*, so a future iOS that changes the dim makes the veil
   wrong. It is a **re-measurement, not a redesign**: shoot the same screen at rest and under a
   press, sample pairs across the tonal range, fit the line, and re-derive `#0F0F13` from
   `pressed = 0.7917 x rest + (4.7, 4.7, 8.7)`. §9's test 26 fails first if it drifts. The mechanism
   also **works because this theme is always dark and the list's background is one flat colour**; on
   an app with a light appearance it would be a hack with a bug in it.
10. **The 280-character cap is an authoring affordance, not a storage invariant, and on the phone
    that is not a limitation inherited - it is the whole shape of the build.** The phone writes
    registry rows directly and never passes the engine's Mutate RPC, so **its own editor is the only
    cap there is**. Nothing below it can enforce one, and a longer note can arrive from any device
    the desktop's guard did not cover. Every iOS surface therefore tolerates any length by eliding:
    the card by a height clamp, the row by never showing text at all, and speech by not capping.
11. **IME composition can exceed 280 characters while uncommitted; the commit truncates.** The
    desktop's limit 5, carried unchanged, and **no path does better**: the selection always sits
    inside the marked text, so any clamp during composition is fighting the input method by
    definition.
12. **The phone cannot author a newline.** Return saves. A multi-line note written on the desktop
    loads, edits and saves back with its newlines intact, but none can be typed here. Taken
    deliberately: Save is one thumb away and a note is one sentence.
13. **The app carries two text-editing stacks** - the composer on `TextEditor`, the Note Editor's
    field on a `UIViewRepresentable`. A real maintenance cost, paid because no SwiftUI hook can see
    the input method (§7).
14. **A sixth Colour Slot shipped by a newer desktop paints as rose on an older iOS build**, and
    reads there as a real rose note. The alternative - a neutral grey - was refused because it would
    make one synced note two different colours across the two apps.
15. **Four values were judged on an iPhone 17 Pro simulator rather than a physical device**, and each
    is a judgement call a device could still move. Named individually so none is mistaken for a
    measurement:
    - **The marker's 3pt width.** The honest range is 3pt, possibly 3.5pt on the device, never 4pt -
      4pt already competes with the title on a Mac panel. A phone's OLED at arm's length subtends
      less, so the direction a device could move it is wider.
    - **The Note Card's 300pt text width.** 280 is the close runner-up.
    - **The card's tint at 0.10 and its hairline at 0.32.** Carried from the desktop unchanged and
      **never re-derived for this app**. They looked right on every slot, but they were not measured
      for contrast the way §3 measured the marker, so they are the one pair of numbers in §5 that
      rests on the eye alone.
    - **The card's 12pt corner radius**, between 12 and 16.
    - **Haptics entirely.** The simulator renders none; §7's haptic answer is reasoning, not
      observation. The 18pt slot dot and its 44pt target were also chosen for an arm's length the
      answer never met.

    Everything else in this spec is a measurement, a diff, a frame-by-frame recording, or a decision
    a human made by looking. The contrast, separation and gamut numbers are computed and the
    substitution does not reach them.

## 11. Out of scope

Copied verbatim from the map. Do not widen this build into any of it.

- **The session detail screen.** `SessionView` and the header above the transcript. The rows are the
  only surface, matching the desktop's exclusion of its conversation header.
- **Any change to the desktop app.** The wire format is a contract this effort consumes.
- **Notifications, widgets, and Live Activities carrying the note.**

Inherited unchanged from the desktop map, and still ruled out:

- **Filtering or grouping the session list by note colour.**
- **Searching note text.**
- **Pinning or reordering a Chat because it has a note.**
- **More than one note per Chat, markdown in a note, and attachments on a note.**

## Reference

- ADR: [0001 - Chat Notes sync in the registry doc](../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md)
- Glossary: [CONTEXT.md](../../CONTEXT.md)
- The desktop's spec, for the contract this build consumes:
  [.scratch/chat-notes/spec.md](../chat-notes/spec.md). **Where the two disagree, this one is right
  about the phone.** The differences are stated in place: the local echo (§2), the chroma (§3), the
  marker as a rule rather than a number (§4), the card's width and its corner mechanism (§5), the
  dialog becoming a sheet and the keys (§7), and the phone speaking the note (§8).
- Platform research, for the verified absences behind §7's cap mechanism:
  [research/swiftui-character-cap.md](./research/swiftui-character-cap.md).
- Prototypes (throwaway; the numbers above survive them). Each branch stacks on the one above it, so
  the last carries everything:
  `proto/03-colour-slots` (`-demo -proto-slots`), `proto/04-resting-marker` (`-demo -proto-marker`),
  `proto/05-the-reveal` (`-demo -proto-reveal`), `proto/06-menu-and-editor` (`-demo -proto-editor`),
  `proto/08-voiceover-and-large-text`, `proto/09-the-cards-corner`. **The defaults on the last two
  are the answer**; every refused option survives as a launch flag.
- The frames behind the verdicts made by eye rather than by measurement are in
  [assets/](./assets/), named by the ticket that produced them.

### Two automation traps, recorded so they are not paid a third time

Both read as app bugs and neither is one.

- **`axe` leaves the simulator believing a hardware keyboard is attached**, and then no software
  keyboard appears for any app, including Settings. Only quitting and relaunching `Simulator.app`
  clears it. `axe type` also swallows a trailing newline, and a headless-booted simulator shows no
  software keyboard at all until `Simulator.app` is attached.
- **Writing `VoiceOverTouchEnabled` through `simctl spawn defaults` clears `AccessibilityEnabled` and
  `ApplicationAccessibilityEnabled`**, and `axe describe-ui` then returns an empty 0x0 tree instead
  of an error. Write all three back to `true` to recover.
