# 09 - The Note Card's corner, on the system's preview platter

Map: [Chat Notes on iOS](../map.md)
Type: prototype
Status: claimed
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
