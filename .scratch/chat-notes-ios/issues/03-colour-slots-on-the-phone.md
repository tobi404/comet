# 03 - The Colour Slots on the phone

Map: [Chat Notes on iOS](../map.md)
Type: prototype
Status: resolved
Claimed by: Beka Demuradze
Blocked by: none

## Question

Do the desktop's five Colour Slot values survive this app's surfaces, and where do they live in
`Theme`?

The slot ids are fixed by sync: `rose` `amber` `green` `sky` `violet`. The desktop's dark values
are one lightness and one chroma across all five, so no colour shouts louder than the rest:
**L 0.660, C 0.112**, at hues **20 / 78 / 152 / 232 / 302** (desktop spec §3).

The iOS theme is always dark and already carries the same `oklch()` helper
(`Theme/Theme.swift:1`), so the port looks free. It is not quite free: the backgrounds differ.
The desktop measured against its sidebar frost over vibrancy. This app paints on `Theme.bg`
(`#060606`) and `Theme.surface` (`#0d0d0d`), with list rows on a clear background and a press
wash of `whiteAlpha(0.06)` over that.

Build a throwaway prototype and answer:

1. **The values.** Do the desktop's dark L and C hold on this app's darker backgrounds, or does
   a near-black background want a different lightness? Give the exact triples that ship.

2. **Contrast, measured.** Port or write the equivalent of `contrast_ratio`
   (`crates/ui/src/theme.rs:1081`) and record the worst of the five against `Theme.bg`,
   against a pressed row, and against the archived shelf's dimmed row. Say plainly which
   numbers clear 3:1 and which do not. Note that the desktop accepted sub-3:1 markers as a
   decision, not a defect, because the marker is decorative and nothing depends on reading it -
   decide whether that reasoning still holds here or whether the phone can do better for free.

3. **Separation.** OKLab ΔE between the five, since a WCAG ratio between same-lightness colours
   measures nothing. The desktop's closest pair was `rose`/`amber` at ΔE 0.109. Confirm or
   improve.

4. **Where they live.** `Theme` is organised as paint constants with the layout numbers kept
   separate and commented as such. Decide the shape: five named constants, a slot-id lookup, or
   an enum. Whatever it is must answer an unknown slot id, which `01` may also touch.

5. **Small sizes.** The marker is a few points wide and the editor's slot dots are small too.
   Confirm the five are still told apart at both sizes on a real device, not in a screenshot.

## Answer

**The five slots become a `NoteSlot` enum at the paint layer, at L 0.660 / C 0.130 - the
desktop's lightness, at the largest chroma every hue can actually reach in sRGB.** The phone
clears 3:1 everywhere it paints on a session row, with room the desktop never had. An unknown
slot id paints as `rose`, matching the desktop.

Judged live on an iPhone 17 Pro simulator, not from a screenshot, flipping four tone candidates
on the real Sessions list and the real archived shelf. **Named cost of the method**: the ticket
asked for a physical device; the iPhone was offline and the simulator was chosen instead. The
Mac panel is not the phone's OLED, so the small-size verdict below (question 5) is one notch
weaker than the ticket wanted. Every other answer here is measured, not seen, so the substitution
does not reach them.

### 1. The values

| slot | hue | oklch | reference hex |
| --- | --- | --- | --- |
| `rose` | 20 | L 0.660 C 0.130 | `#d66f71` |
| `amber` | 78 | L 0.660 C 0.130 | `#bd871c` |
| `green` | 152 | L 0.660 C 0.130 | `#4aa969` |
| `sky` | 232 | L 0.660 C 0.130 | `#179fd4` |
| `violet` | 302 | L 0.660 C 0.130 | `#a17dd4` |

**The lightness holds; the chroma does not.** A near-black background does *not* want a different
lightness - the desktop's L 0.660 already clears 3:1 against `#060606` by more than it cleared
against the desktop's own frost, because `#060606` is darker than what the desktop measured
against. Lifting the lightness was built and looked at (L 0.720 / C 0.120) and buys contrast the
phone does not need.

What the darker background *does* buy is headroom to separate the five harder. The chroma goes
from the desktop's 0.112 to **0.130**, which raises the closest pair from ΔE 0.109 to 0.126 and
costs 0.05 of contrast ratio at the worst background. That is the whole trade, and it is worth
taking: separation is the number that matters on a 3pt mark, and contrast is the number that is
already won.

**The oklch triples are what ship**, resolved at paint time. The hexes above are reference only,
same as the desktop spec's.

### The gamut ceiling, and why the chroma is not higher

Chroma 0.150 was built, looked at, and rejected on measurement, not on taste. **At L 0.660 the
largest chroma all five hues can reach inside sRGB is 0.1346, and `sky` is what limits it.**
Above that, `oklchToSrgb`'s per-channel clamp in `gammaEncode` silently drags the out-of-gamut
slots back:

| slot | asked for | actually paints |
| --- | --- | --- |
| `rose` `green` `violet` | L .6600 C .1500 | L .6600 C .1500 |
| `amber` | L .6600 C .1500 | L .6612 **C .1395** |
| `sky` | L .6600 C .1500 | **L .6657** **C .1411** |

That breaks the premise the palette rests on - one lightness and one chroma across all five, so
no slot shouts louder - and it breaks it invisibly, which is worse. **0.130 sits inside the
ceiling with headroom**, so every slot reaches the tone exactly. The desktop never met this
because 0.112 is far inside the gamut.

This is the reason the iOS values are allowed to differ from the desktop's at all, and it is a
constraint on any future re-tune, not a preference.

### 2. Contrast, measured

`contrast_ratio` (`crates/ui/src/theme.rs:1081`) ported to Swift, worst of the five per
background. The two washes composite in gamma space, which is what CoreAnimation does over an
opaque sRGB surface.

| background | worst | best | clears 3:1 |
| --- | --- | --- | --- |
| `Theme.bg` `#060606`, resting list row | **6.13** (`rose`) | 6.89 (`green`) | yes |
| `Theme.surface` `#0d0d0d` | **5.88** | 6.61 | yes |
| pressed row (`elementHover`, white 0.06) | **5.53** | 6.21 | yes |
| selected row (`elementActive`, white 0.10) | **4.99** | 5.61 | yes |
| archived shelf, marker dimmed to 55% | **2.51** | 2.72 | **no** |

**The desktop's accepted sub-3:1 does not carry over, because the phone does not need it.** Every
surface the marker actually paints on a session row clears 3:1 with 1.99 to spare at the worst.
The phone beats the desktop's 5.93/6.08/4.87 for free, and the reason is structural: `#060606` is
darker than frost over vibrancy, and the theme is always dark, so there is no light appearance to
lose to. Both of the desktop's contrast-driven known limits are gone here, not accepted.

**One case is under 3:1, and it is not a colour problem.** A marker dimmed with the shelf's 55%
lands at 2.51 and no tone fixes it: lifting the lightness only reaches 2.95. What fixes it is not
dimming the marker - at full strength on the shelf the same marker reads 6.13. The shelf's dim
exists to quiet the row's *content*, and the marker is not content. **That decision belongs to
[04 - The resting marker, on two row shapes](./04-resting-marker-on-two-row-shapes.md)**, which
owns the shelf row; this ticket hands it the two numbers and the recommendation.

### 3. Separation

OKLab ΔE between the five, which is the honest measure between colours of one lightness (a WCAG
ratio between them reads ~1.00 and measures nothing).

**Closest pair `rose`/`amber` at ΔE 0.126**, improved from the desktop's 0.109. The pair is the
same one the desktop found, so the ordering of the wheel is confirmed, not changed. Chroma 0.150
would have reached 0.134, and is refused for the gamut reason above.

### 4. Where they live

**A `NoteSlot` enum in a new `Theme/NoteSlots.swift`**, not five constants and not a bare
dictionary. The desktop's `NOTE_SLOTS` table is the model.

```swift
/// A Colour Slot a Chat Note can carry. The wire id is the raw value.
///
/// The MODEL keeps the slot id as a String (ticket 01) so no parse can
/// downgrade an id a newer desktop wrote. This enum lives at the PAINT layer
/// only: it turns a stored id into a colour, and answers an id it has never
/// heard of.
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

Why the enum and not the alternatives:

- **Five named constants** cannot answer an unknown id at all, and give the Note Editor no order
  to draw its slot row in.
- **A slot-id lookup** answers the unknown id but scatters the same slot across an ids array and
  a colours map, so a sixth slot is two edits that can disagree.
- **The enum** is one edit for a sixth slot, `CaseIterable` *is* the editor's row order,
  `rawValue` *is* the wire id, and `init?(rawValue:)` returning `nil` *is* the unknown-id branch.
  A slot is its id plus its hue, and the enum is the only shape that says so.

**The hue stays private**, like the desktop's - a caller that could see a hue would be tempted to
store one, and a stored hue could not follow a re-tune. **The tone constants stay private and
file-local**: they are not `Theme` paint constants because they are not a colour, they are the
recipe for five, and `Theme`'s own rule is that paint constants are colours and layout numbers
are kept separate. The file is the third thing and says so.

**`Theme` itself gains nothing.** `NoteSlots.swift` sits beside `Theme.swift` and uses its
`oklch` and `neutral` primitives.

### The unknown slot id

**An unknown id paints as `rose`, matching the desktop** (`note_slot_color_for`,
`crates/ui/src/theme.rs:966`). Both fallbacks were built and looked at side by side.

Ticket 01 settled that the parse **keeps** a note with an unknown slot id, because the text is
user content and the colour is decorative. This ticket settles what that kept note paints as.
Dropping the mark is excluded - the model has no colourless note, and a note the user cannot see
is a note they cannot find.

A neutral grey fallback was the alternative, and its argument is real: an unknown id would then
never impersonate a real slot. It is refused because it **breaks the map's one-visual-language
rule at the worst moment**. The same synced note would be violet on the desktop and grey on the
phone, and the user would read that as the phone being broken, not as the phone being honest. The
desktop already chose rose and wrote its cost down; the phone matching it means the two apps are
wrong in the same direction, which is a far cheaper failure than being wrong in two directions.

**The cost, restated for this app**: a sixth Colour Slot shipped by a newer desktop paints as
rose on an older iOS build, and reads there as a real rose note. Named, not hidden.

### 5. Small sizes

**3pt is enough.** At 3pt wide and 18pt tall the five read as five, both spaced along a row and
packed adjacent with no gap. 2pt was built too and is where it starts to go: adjacent `rose` and
`amber` begin to merge. The editor's slot dots were checked at 28, 22, and 16pt and are not close
to a limit.

So the marker geometry ticket 04 picks is free to stay near the desktop's ported 3pt, and 0.126
of separation is what makes that true - at the desktop's 0.109 this call would have been closer.

**Named weakness**: this was judged on a simulator on a Mac panel, not on the phone's OLED, per
the method note at the top. It is the one answer here that a real device could still move, and
the direction it could move is toward wanting more width - which is ticket 04's dial, not this
ticket's.

### The prototype

Branch **`proto/03-colour-slots`**, commits `5072033` and `5258120`. Launch with
`-demo -proto-slots`.

Four tone candidates ride the real Sessions list and the real archived shelf in demo mode, so the
slots were judged against real density and not in a vacuum. A floating bar flips the tone,
switches the unknown-id fallback, and toggles the shelf dim. A Lab sheet carries the swatches on
every background, the small-size strip, the editor dots, the fallback comparison, and the measured
contrast, ΔE, and gamut numbers for all four tones at once. The demo dataset is padded to 8 active
and 4 shelf rows so all five slots, an unknown id, and unnoted rows are on screen together.

The marker geometry in it (3 x 18pt, 2pt inset) is a **placeholder** so the colours had something
to paint. Ticket 04 owns it.

### Tests this ticket fixes

For [07 - Write the spec](./07-write-the-spec.md):

1. `NoteSlot.color(for:)` returns `rose`'s colour for an id no case matches, and for the empty
   string.
2. `NoteSlot.color(for:)` round-trips each of the five ids to its own colour.
3. **All five slots are inside sRGB at the shipping tone** - no channel clamps. This is the test
   that stops a future chroma bump from silently breaking the one-chroma premise, and it is the
   one test here that is not obvious from reading the code.
4. Worst-of-five contrast against `Theme.bg`, the pressed wash, and the selected wash is at or
   above 3.0, mirroring the desktop's contrast reproducer.
5. Closest-pair OKLab ΔE is at or above 0.12.
6. `NoteSlot.allCases` is in wheel order `rose amber green sky violet`, which is the Note Editor's
   row order.

### For the spec's amendment report

**The desktop spec is not wrong, and needs no change.** Its §3 already says the oklch triples
resolve per theme at paint time and that a stored hex could not follow a re-tune - which is
exactly the licence the phone uses to run a different chroma. The iOS spec records the difference
and its reason: **L 0.660 shared, C 0.130 instead of 0.112, because the phone's near-black
background pays for more separation and the sRGB gamut ceiling at that lightness is 0.1346.**

Worth reporting sideways, not as an amendment: the desktop's own dark chroma has the same
headroom, and could reach 0.130 with the same gain. That would be a fresh effort against the
desktop, which this map has ruled out of scope.
