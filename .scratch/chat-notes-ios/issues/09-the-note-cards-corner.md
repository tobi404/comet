# 09 - The Note Card's corner, on the system's preview platter

Map: [Chat Notes on iOS](../map.md)
Type: prototype
Status: resolved
Claimed by: Beka Demuradze
Blocked by: 05 (resolved), 06 (resolved), 08 (resolved)

## Question

**The Note Card reads as an oval, not as a card. Can it be a rectangle with a corner radius, and
at what radius?**

[05](./05-the-reveal.md) set the card's own corner radius at **12pt**. The rendered shape is not
12pt. Look at [the card's content](../assets/05-note-card-content.png) and at the short card in
[the menu and the card](../assets/06-menu-and-card.png): the corner arc is a large fraction of the
card's own height, so a two-line note reads as a pill.

The cause is almost certainly **the system's preview platter, not the card**. 05 already proved
the `.contextMenu` preview masks its content - that is the finding under its question 4. The mask
carries the platter's own corner radius, which is the system's number and not this app's. On a
short card that radius approaches half the height, and half the height is an oval.

Build it and look. Do not settle it by reading.

### What to answer

1. **What the shape actually is today.** Measure the rendered corner radius off a held-press
   frame, at a short note and at a ten-line note. Say whether the card's 12pt is doing anything at
   all, or whether the platter's mask is the only shape on screen. This is the ticket's premise and
   it should be proved before anything is changed.

2. **Whether SwiftUI can reshape the platter.** The discriminating experiment, and it runs first:
   `.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))`.
   That API is documented against the source view's lift preview, and this card comes from a
   custom `preview:` closure instead, so it may not reach the platter at all. **Test both
   attachment points** - on the row, and on the card inside the preview closure - because a null
   result at one is not a null result.

3. **The fallback, and its price.** If SwiftUI cannot reach it, `UIContextMenuInteraction` with
   `UIPreviewParameters.visiblePath` can, through a `UIViewRepresentable`. That replaces the
   SwiftUI `.contextMenu` outright, so the answer must confirm what survives the swap:
   iOS 26's zoom transition, [06](./06-menu-and-note-editor-sheet.md)'s three menu items, the
   trailing swipe on both row shapes, and [08](./08-voiceover-and-large-text.md)'s finding that
   the menu adds nothing to the accessibility tree. **Name the cost the way
   [02](./02-character-cap-in-a-swiftui-editor.md) named its own**: this would be the app's second
   `UIViewRepresentable` and it would put the whole reveal on UIKit. The price may be worth more
   than the corner - that is the human's call, which is why this is a prototype and not a fix.

4. **The radius, chosen by looking.** Sweep the system default as the comparator against at least
   two candidates. The worst case for ovalness is the **short note**, so the sweep leads with one,
   and it must also be looked at on the ten-line clamp - a radius that reads right on a tall card
   can read mean on a short one.

5. **Both row shapes.** The session row and the 36pt shelf row open the same card from the same
   gesture, and 05 calls that V1's strongest property. Whatever the answer is, it is the same
   answer on both, or it is a regression in 05's terms.

6. **What it does to the height that must be known before the press.** 05's central card
   constraint is that the preview does not size itself, and [08](./08-voiceover-and-large-text.md)
   fixed the clamp as a height measured at the default text size. A mask should not touch either.
   Check it rather than assume it, and say which of the two answers this ticket leaves standing.

### What this ticket does not reopen

The reveal itself. V1 is settled and the card's width, tint, hairline, clamp, padding and content
are 05's and 08's. This ticket changes one number and the mechanism that carries it, or it changes
nothing and says so.

### For 07

Whatever this resolves, [07 - Write the spec](./07-write-the-spec.md) carries: either the radius
as a real number with the mechanism that makes it true, or an accepted limit written as a decision
- *the platter owns the corner and the app does not* - in the same voice as 08's eight.

## Answer

**The card is inset 14pt inside the preview, and the margin is filled with the page's own colour
under the system's dim, `#0F0F13`. The platter's arc then cuts flat colour instead of the card,
and the card's own corner - 12pt, continuous - becomes the only corner on screen.**

**The premise was right and the cause was not the card.** 05's 12pt was never drawn. The system's
preview platter masks the preview with a corner of its own, and that corner is roughly half the
card's height on a short note, which is a stadium. **This one was chosen by the human**, on the
real list, from three mechanisms and a radius sweep.

### 1. What the shape actually is today

Measured off held-press frames with `proto09-corner.py`, which reports each corner as how far in
the fill starts at the card's first row (**across**), how far down the arc runs before the card
reaches full width (**down**), and **ovalness** - `down / (height / 2)`, where **1.0 is a pill**.

| fixture | card | corner | ovalness |
| --- | --- | --- | --- |
| `chat-beta`, one word | 119 x 57pt | 24.3 across, 22.3 down | **0.79** |
| `chat-veil`, short | 195 x 58pt | 32.7 across, 23.0 down | **0.79** |
| `chat-picker`, three lines | 324 x 91pt | 36.7 across, 28.7 down | **0.63** |
| `chat-oklch`, on the 36pt shelf | 253 x 51pt | 26.7 across | a full stadium |

**The card's 12pt does nothing at all.** The tint, the hairline and the clip are all drawn and
then masked over, which is why the hairline is visible running straight into the arc and stopping.
**The arc grows with the card**, so it is not a constant the layout could design around: 24pt
across on the smallest card, 44pt on the largest.

### 2. SwiftUI cannot name the shape, and this is a measured null

`.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))` was
built at **three** attachment points, because a null result at one proves nothing about another:

- **on the row**, immediately before `.contextMenu` - where the modifier is documented to work
- **outermost on the preview content**, over the forced height
- **inside the forced height**, directly on the card

**All three frames are pixel-identical to today**, at the same fixture and the same measurements
(324 x 91pt, 36.7 across, 28.7 down, ovalness 0.63). The claim this ticket makes is exactly that
and no wider: those three placements do nothing. The modifier is documented against the source
view's lift preview, and this card comes from a custom `preview:` closure.

### 3. The fallback was priced and not built

`UIContextMenuInteraction` with `UIPreviewParameters.visiblePath` would own the mask outright. It
was **offered to the human with its price and declined in favour of the veil**: it replaces the
SwiftUI `.contextMenu`, so [06](./06-menu-and-note-editor-sheet.md)'s three menu items,
[08](./08-voiceover-and-large-text.md)'s custom actions and its finding that the menu adds nothing
to the accessibility tree, the trailing swipe, and iOS 26's zoom transition would all have to be
re-established rather than inherited. **Nothing here says it would not work** - it was not tried,
and that is the honest state of it.

### 4. The mechanism that won, and the one in between

Three were built and looked at on the short note - see
[the mechanisms](../assets/09-mechanisms.png):

- **today** - one surface, and its shape is the platter's. A stadium.
- **inset** - the card padded 14pt inside the preview, margin transparent. The card is rectangular
  **and the platter's own tray shows around it**: a grey rounded surface the card now sits on. Two
  surfaces where the design has one. Refused.
- **veil** - the same inset, with the margin filled opaque in the page's colour. One surface, and
  it is the card. **Chosen.**

The inset is what proved the platter draws a background of its own. That fact is invisible under
`today`, because the card covers the tray exactly.

**Measured, on the three-line card**: 324 x 91.3pt, corner **10.3 across, 8.3 down**, ovalness
**0.18** against today's 0.63. The 10.3 and 8.3 are a 12pt continuous corner as this method
measures one, and they are **identical on every fixture and every text size** - the card's corner
is now a number the app owns, so it stops moving with the card's size.

The margin is **14pt** and that is a measurement, not a taste. A corner of radius `r` cuts a
square corner to a depth of `r(1 - 1/√2)`, about `0.3r`; the largest arc measured is 44pt across,
so under 14pt of margin the arc never reaches the card - proved at the largest card this build can
make, at AX-XXXL.

### 5. The radius

**12pt, continuous** - 05's own number, kept now that it is the number on screen. Swept at 8, 12,
16 and 20 on the three-line card, in [the radius sweep](../assets/09-radius.png). All four read as
rectangles; 8 stops registering as a corner at the small card sizes and 20 starts going round
again on the shortest notes. The human chose 12 by looking.

### 6. Both row shapes, and the largest text

- **The shelf.** One mechanism, one code path, no degrade - 05's strongest property survives
  untouched. The 36pt row's card goes from a full stadium to a rectangle:
  [the shelf](../assets/09-shelf.png).
- **AX-XXXL.** The card's corner measures **10.3 across, 8.3 down, ovalness 0.08**, against today's
  55.7 across on the same fixture: [the largest text](../assets/09-at-size.png). The margin is a
  fixed 14pt and does not scale, and it does not need to - the arc it has to clear grows with the
  card and stays far short of it.

### 7. The height rule is untouched

**05's central card constraint and 08's clamp both stand exactly as written.** The veil is applied
**outside** the forced height, so `protoCardHeight` still computes the card's height and still
means the card. The preview is 28pt taller and wider than the card; the card is not.

### 8. The open, frame by frame

**The veil does not pop.** Recorded at 30fps and stepped -
[the open](../assets/09-open.png) - the veil and the page beside it stay **within 2/255 of each
other on every frame** of the zoom, including the frames where the card is still translucent.
This had to be checked rather than assumed: the veil is a colour matched to a system effect, and
the system applies that effect over the open rather than instantly.

### 9. The cost, stated plainly

**The veil is a constant that tracks a system effect.** While a context menu is up, iOS puts a dim
over everything except the preview, and the preview is exempt - so a colour authored inside the
preview renders exactly as authored while the page beside it does not. The veil therefore cannot
be `Theme.bg`; it has to be `Theme.bg` **as the dim leaves it**.

The dim is linear and was solved from 27 sample pairs across the whole tonal range, at rest
against under the finger:

```
pressed = 0.7917 x rest + (4.7, 4.7, 8.7)
```

which is a dark blue-grey at about 21%. `Theme.bg` `#0D0D0D` goes to **`#0F0F13`**, and the frames
confirm it: the veil renders `(15, 15, 19)` and the page beside it reads `(15, 15, 19)`.

What this costs, and what it does not:

- **It is one number, and it is derivable.** The recipe is in this ticket: shoot the same screen at
  rest and under a press, sample pairs, fit the line. A future iOS that changes the dim is a
  re-measurement, not a redesign.
- **The residual is the platter's own shadow, not the veil.** The page is 1 to 2 units darker
  immediately around the platter than it is further away, because the platter casts a shadow. That
  gradient exists under `today` too, and no flat colour can match a gradient. It is below
  perception at these values.
- **Increase Contrast changes nothing.** Verified with the setting actually queried back as
  `enabled`, not merely set: same card, same corner numbers, same page colour.
- **The card covers 14pt more of its neighbours** while it is up, because the preview is 28pt
  taller and wider. Visible in [the corner](../assets/09-the-corner.png) as slightly more of the
  row above being hidden. It is the price of the margin.
- **It works because this theme is always dark and the list's background is one flat colour.** On
  an app with a light appearance this would be a hack with a bug in it. Here it is a constant -
  the same property that saved [03](./03-colour-slots-on-the-phone.md) two contrast limits.

### 10. Named cost of the method

**Judged on an iPhone 17 Pro simulator, not the physical phone**, as 03, 04, 05 and 08 were. The
corner numbers are measurements and do not weaken. The radius choice between 12 and 16 is the one
judgement here that a device could still move, and the branch stays installable.

### Tests this ticket fixes

For [07 - Write the spec](./07-write-the-spec.md):

1. **The card's rendered corner is the card's corner.** The measured arc is the same on the
   shortest note and the ten-line one, on both row shapes, and at every text size. Under the
   defect it moved with the card, which is what made a short note a pill.
2. **The veil equals the page under the dim.** One pixel inside the margin and one pixel on the
   page beside it, in the same held-press frame, must not differ by more than 2 per channel. This
   is the guard on the one constant this decision introduces.
3. **The forced height is the card's height, not the preview's.** The preview is `card + 2 x 14`
   in both axes. A rule that starts measuring the padded box silently re-opens 05's clip.

### For the spec's amendment report

**The desktop spec needs no change.** Its card is a floating panel the app draws itself, so it
owns its own corner and has no platter. There is nothing here to port and nothing there to correct.

**05 is amended once.** Its card table's "corner radius **12pt**" is right about the number and
silent about the mechanism, and silence is what let the oval ship into the frames. The row now
reads: 12pt, continuous, **held by the veil** - see section 4 above.

### The prototype

Branch **`proto/09-the-cards-corner`** (off `proto/08-voiceover-and-large-text`, so 03's Colour
Slots, 04's marker, 05's card, 06's menu and sheet, and 08's clamp all come with it). Launch with
`-demo -proto-editor`. **The defaults are the answer**; every refused mechanism survives as a flag.

```
-c9m today|preview|row|both|inner|inset|veil    the mechanism; `today` is the oval
-c9r <pt>        the card's own corner radius       -c9s continuous|circular
-c9pad <pt>      the veil's margin                  -c9veil <RRGGBB>
-c9probe         puts the mechanism and the radius on the frame

proto09-card.sh <name> <y-pt> [args...]    # holds the press, shoots, lifts
proto09-open.sh <name> <y-pt> [args...]    # records the open, splits it to frames
proto09-corner.py <frame.png>              # the rendered corner, and ovalness
proto09-strip.py <out> <x0 y0 x1 y1> <names...>
```

`proto09-corner.py` finds the card by luminance and not by chroma, and picks its band by chroma:
the card's own text is white, so a tint test splits every row that carries a word, and the menu
panel passes a luminance test but is the only surface that is not tinted. Both tests are there
because the obvious single test fails.

### Assets

- [The three mechanisms](../assets/09-mechanisms.png) - today, inset, veil, on the short note. The
  decision.
- [The corner](../assets/09-the-corner.png) - today against the veil on a three-line note.
- [The radius sweep](../assets/09-radius.png) - 8, 12, 16, 20.
- [The shelf](../assets/09-shelf.png) - the same gesture on the 36pt row.
- [The largest text](../assets/09-at-size.png) - AX-XXXL.
- [The open](../assets/09-open.png) - the zoom, frame by frame, with the veil against the page.
