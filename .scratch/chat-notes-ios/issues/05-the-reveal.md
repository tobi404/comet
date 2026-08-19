# 05 - The reveal: how the phone shows the note

Map: [Chat Notes on iOS](../map.md)
Type: prototype
Status: resolved
Claimed by: Beka Demuradze
Blocked by: 03 (resolved), 04 (resolved)

## Question

How does a phone show a Chat Note, given that it has no hover?

This is the heart of the effort, and charting deliberately refused to close it in conversation.
Three candidates survived the grill. Build all three against the real chat list, on a device,
and choose by looking.

- **V1 - Marker only, long press reveals.** The row gains the marker and nothing else. A long
  press opens a `.contextMenu` preview card holding the full text. One mechanism serves both row
  shapes.
- **V3 - The note takes a line it outranks.** When a Chat has a note, the note text replaces
  line 1, the `space @ device` line. Row height never changes.
- **V6 - Both.** Marker, one elided line of note text, and a long press for the full card.

Four candidates are already dead and do not return. The map's Settled list records each one and
why. Do not re-litigate them; overturn one only by saying so out loud.

Answer:

1. **The choice**, with the reason stated in terms of what the real list looked like, not in
   terms of the argument for it.

2. **What the archived shelf does.** Its row is a fixed 36pt single line, so it cannot take a
   second line. If V3 or V6 wins on the session row, decide whether the shelf degrades to
   marker-only, or whether the winner is forced to be one mechanism everywhere.

3. **The location line, if V3 or V6 wins.** V3 spends it. That line was added deliberately for
   the phone, because this list interleaves devices and the desktop sidebar does not
   (`Views/HomeView.swift:284`). Decide where the location goes when a note takes its place -
   into the preview card, or nowhere.

4. **The card itself, if V1 or V6 wins.** Its surface, its width, how many lines it holds before
   eliding, and whether it carries anything besides the note text. The desktop's card clamps at
   10 lines and elides, precisely because storage cannot promise a short note.

5. **Long text and pathological text.** A note is capped at 280 characters by the phone's own
   editor, but the desktop's known limit 6 says storage promises nothing. Test a note far longer
   than the cap, and a single unbreakable URL wider than the row. Both must clip, never widen or
   wrap the layout.

6. **What happens to row heights.** V6 makes noted rows taller than bare rows. The list runs a
   `Motion.resort` FLIP glide on every reorder. Watch a reorder with mixed heights and say
   whether the glide survives it.

## Answer

**V1 wins. The row gains the resting marker and nothing else, and a long press opens the Note
Card.** One mechanism on both row shapes, and the session list keeps the density it has today.
**The card carries the note text and the `space @ device` line, in that order** - not because
V1 spends the location line, but because the card covers the row while the finger is down.

**This one was chosen by the human, not by the agent.** Charting refused to close it in
conversation and sent it here to be decided by looking; four candidates rode the real list and
the verdict is the human's. The agent's own reading before the answer favoured V6R, and it was
wrong to the eye that matters.

### 1. The choice, in terms of what the list looked like

Four candidates, on the real Sessions list in demo mode, at the default text size and at
`accessibility-large`. Both strips are linked below.

**V1** leaves the list exactly as it is today plus one 3pt column of colour. Nothing moves,
nothing is given up, and eight sessions plus four shelf rows stay on one screen. The list still
reads as a list of sessions that some of them happen to be marked.

**V6R** - the fourth candidate, built here (see below) - looked strongest on paper and lost on
the screen. Its notes land on line 1 in the same 11pt the location used, so on a list with six
notes the eye stops reading rows and starts reading a column of sentences. It is a note list
wearing a session list's shape.

**V6** is the same objection plus a real cost: every noted row grows by one line, and on a list
with five notes the archived shelf falls below the fold. The list holds fewer sessions for as
long as the notes exist.

**V3** loses the Colour Slot from the session list entirely - 03's five colours paint nowhere on
the active rows - and it gives no path at all to a note longer than one elided line.

The shape of the finding: **the phone's list is dense already, and every candidate that puts note
text on a row spends the list's calm to save one press.** V1 spends nothing and charges one
press. The list is the surface people scan; the note is what they reach for.

### 2. The archived shelf

**One mechanism everywhere, and no degrade at all.** This is V1's strongest property and it is
the reason question 2 has no second half.

The same `.contextMenu(menuItems:preview:)` attaches to the shelf row unchanged and opens the
same card - built and pressed, see [the shelf card](../assets/05-shelf-card.png). The 36pt row's
inability to take a second line never comes up, because V1 never asks it to. The shelf's resting
signal is 04's marker at full strength, which 04 already settled.

Every other candidate needed the shelf to behave differently from the session row. V1 is the only
one where the two rows are told the same thing.

### 3. The location line

**It is not spent, and the card carries it anyway.** V1 leaves `space @ device` on line 1 of
every row, noted or not, so the question's premise does not arise - but the answer is still
"into the card", and for a reason V1 creates rather than inherits.

**The preview REPLACES the row for the length of the press.** The desktop's card floats beside
its row, so the row stays readable underneath. A `.contextMenu` preview does not: the row is
lifted out and the card is drawn in its place. So at the exact moment a user is reading the note,
the row's own location line is not on screen. The card restates it.

Held against the alternatives on the real list - see
[the card's content](../assets/05-note-card-content.png):

- **note text alone** - the desktop's card. Correct on a pointer machine where the row is still
  visible. Here it drops the context for as long as it is up.
- **note + location** - the answer. The location reads muted under the note and never competes
  with it.
- **title + note + location** - refused. The title is redundant with the note in almost every
  real case, and three registers in a card that exists to show one sentence is a card that has
  stopped being a card.

### 4. The card

| | |
| --- | --- |
| mechanism | `.contextMenu(menuItems:preview:)` on the row, iOS 26's zoom transition |
| base | `Theme.surface` |
| tint | the note's Colour Slot at **0.10** across the card, plus a **1pt** hairline of the same colour at **0.32** |
| corner radius | **12pt** |
| padding | **12pt** horizontal, **10pt** vertical |
| text | **13pt** `Theme.sans`, `Theme.text` |
| maximum text width | **300pt**, so the card is **324pt** wide. It sizes to its content: a five-word note is a five-word card |
| overflow | **10 lines**, then elide. The card never scrolls |
| second line | the row's `space @ device`, 11pt, `Theme.textMuted` at 0.7 |

**The desktop's 320 does not port, and the phone's width is why.** The desktop caps the *text* at
320px; with this card's 12pt padding that is a **344pt card** on a 402pt phone, or 29pt of margin
each side. Swept at 240, 280, 300 and 340pt of text - so 264, 304, 324 and 364pt of card - all on
the same note, in [the width sweep](../assets/05-note-card-width.png):

- **240pt** turns a three-line note into four. Tall and narrow for no gain.
- **280pt** is correct and is the close runner-up. Nothing separates it from 300 but one line on
  some notes.
- **300pt** is the answer: three lines where 240 needs four, and still 39pt of margin each side.
- **340pt** is refused. At 364pt of card it is nearly the full screen and reads as a banner
  across the list.

**The ported 344 was not built, and this answer does not claim it was.** It sits between the
accepted 324 and the refused 364, closer to the refused one. The direction the sweep establishes
is that the card gets worse as it approaches the screen's width, so 320 is very likely too wide -
but "likely" is the honest word, and 300 is chosen on what was looked at rather than on what 344
would have shown.

#### The constraint that decides the clamp, and it is not the clamp

**A `.contextMenu` preview does not adopt its content's height. It must be given one, or a card
taller than about two lines is clipped mid-sentence.** This is the prototype's hardest finding
and it is invisible on a short note.

Measured from inside the app while the finger was down: the card **lays out correctly at
324 x 71pt** for a three-line note - and only part of it is drawn. Held at clamps 1, 2, 3 and 6:
one and two lines render whole, three and six are cut through the first and last line, and 3 and
6 are cut identically, so the ceiling is fixed and is not the clamp. See
[the clip](../assets/05-note-card-clip.png).

What was ruled out:

- **`.fixedSize(horizontal: false, vertical: true)` does not fix it.** The card is not being
  squeezed; it is laid out right and then masked.
- **The attachment point is not the cause.** The same press was built with the menu on the row's
  wash box and on the row's own content stack inside the Button's label (`-rinner`). Both clip
  identically, so no attachment escapes it.
- **An explicit `.frame(height:)` does fix it**, completely: at that point the 779-character
  fixture renders ten whole lines and elides. See
  [the over-cap note](../assets/05-note-card-over-cap.png).

So the implementation has to know the card's height **before the press**, which means measuring
the note's rendered height at the card's width and caching it per chat. **The desktop hit exactly
this and wrote down the same answer** - spec §5, "Centring needs the card's height a frame before
the card exists: measure it with a `canvas` inside the card, cache per chat and width". The phone
needs the measurement for a different reason (the container will not size itself, rather than
centring), and the mechanism ports.

**Named as a cost, not hidden**: if the forced height overshoots the content, the surplus draws as
empty container under the card. Height and content must agree, so a stale cache is visible rather
than silent. **Also named as not pinned**: the exact ceiling was not reduced to a number. It sits
between two and three lines of 13pt text on the 61.7pt session row; the reproducer below produces
it on demand, and 07 should not write a number this ticket did not measure.

### 5. Long text and pathological text

**Both clip. Neither widens or wraps the layout, on any candidate.**

- **The 779-character note** (written to match the desktop's own fixture, past the 280 cap) fills the card to
  ten lines and elides with a tail ellipsis. On a row - which only the losing candidates do - it
  elides to one line. Nothing scrolls.
- **The unbreakable URL** - one 118-character token with no space in it - **wraps at character
  boundaries inside the 300pt cap** and never widens the card:
  [the URL in the card](../assets/05-note-card-url.png). On a row it truncates with a tail
  ellipsis and the row's own width is untouched. This is worth writing down because it is the
  opposite of what the desktop had to do: the desktop's card had to be told to clip, and SwiftUI
  breaks the token for free.

Both fixtures live in the prototype's demo notes, so they are on screen on every launch rather
than being a test someone remembers to run.

### 6. Row heights

**V1 changes no row height, so the question dissolves for the winner - and it was answered
anyway, because a losing candidate is the only place it could be.**

Measured live off the list: under V1 a noted row and a bare row are **both 61.7pt**, matching 04's
measurement of the untouched row. The marker is an overlay and contributes no layout, which 04
already proved by diffing markers on against markers off.

Under V6, which is the only candidate that makes ragged heights, **the `Motion.resort` FLIP glide
survives them.** Recorded at 30fps and stepped frame by frame -
[the glide](../assets/05-v6-mixed-height-resort.png) - the bottom row was stamped to the top and
travelled the whole list: it keeps its own taller height throughout, the rows below close the gap
smoothly, and everything settles inside the 260ms with no jump and no snap. The one artefact is
that the travelling row is drawn over its neighbours in transit, which is how the List draws a
moving row and is more visible when that row is taller. It reads as motion, not as breakage.

So the map's charting note - that a fourth line "damages the `Motion.resort` FLIP glide" - is
**too strong and should not be carried into 07 as a fact.** The fourth-line candidate is still
dead, but on the shelf's 36pt row and on the list's density, not on the glide. Reported here
because a spec that repeats a wrong reason teaches the wrong lesson.

### Dynamic Type

**V1 adds no text, so it adds no Dynamic Type behaviour.** At `accessibility-large` the list is
04's list: the marker tracks the title's line box and stays clamped inside the row. See
[the accessibility strip](../assets/05-four-candidates-accessibility.png), where V1 is the only
candidate that looks the same as it does at the default size.

The card's own behaviour at the accessibility sizes was **not** resolved here and is fog, not an
answer: the height that must be computed before the press is computed from text that scales.

### The fourth candidate, and why it exists

**The ticket's V6 and the ticket's question 6 disagree, so both readings were built.**

- V6's description - "Marker, one elided line of note text, and a long press for the full card" -
  is a line **added** to the row, which is what question 6's "V6 makes noted rows taller than bare
  rows" describes.
- "Both", read as V1 + V3, is the marker and the card of V1 with V3's **substitution** instead of
  an added line, and it changes no heights.

Building one would have decided the other by assumption. **V6R** is the substitution reading; it
came second and lost on the same ground as V3.

Also built rather than assumed: **V3's marker.** V3's description never mentions the marker, so
the default reading is that it has none - which costs V3 the Colour Slot entirely. That is a
strong claim to bake into a candidate, so it is a dial (`-rmarker byVariant|on|off`) and V3 was
looked at both ways. With the marker forced on, V3 becomes V6R without the card, and loses to it.

### Named cost of the method

**Judged on an iPhone 17 Pro simulator, not the physical phone** - the same substitution 03 and 04
made. Two answers here are weakened by it and no others:

1. **The card's 300pt width.** A Mac panel at desk distance is not an OLED at arm's length. 280 is
   the close runner-up and the branch stays installable, so the pair can be re-looked at on the
   device before 07 freezes it.
2. **The tint at 0.10 and the hairline at 0.32**, carried from the desktop unchanged and not
   re-derived here. They looked right on every slot; they were not measured for contrast the way
   03 measured the marker.

Everything else in this answer is a measurement, a frame-by-frame recording, or a decision the
human made by looking.

### Tests this ticket fixes

For [07 - Write the spec](./07-write-the-spec.md):

1. **A row with a note renders at the same height as the same row without one** - 61.7pt on the
   session row, 36pt on the shelf. V1 adds no layout anywhere.
2. **The 779-character fixture renders ten lines and elides**, and does not scroll.
3. **The unbreakable-URL fixture does not widen the card**: the card's width stays at or below
   324pt with the token present.
4. **The card's forced height equals its measured content height.** This is the non-obvious one:
   it is the guard against both failures at once - too small clips the note, too large draws empty
   container under it. The reproducer is a three-line note, because one and two lines pass either
   way.
5. **The shelf row and the session row open the same card from the same gesture.** One mechanism;
   a change to one that does not reach the other is a regression.
6. **The card carries the location line**, so a note read at full length still says where its
   session runs.

### For the spec's amendment report

**The desktop spec is not wrong, and needs no change - but two of its numbers do not port and 07
should say so rather than restating them.**

- **§5's 320px maximum text width does not port.** It makes a **344pt** card on a 402pt phone -
  between the 324 this ticket accepted and the 364 it refused, and much nearer the refused one.
  344 itself was not built, so carry this as the direction it is: 300pt is the phone's number,
  chosen on the sweep rather than on the port.
- **§5's whole hover apparatus has no phone equivalent and correctly does not port**: the 350ms
  open, the 120ms close, the click-dismiss latch, the resort and scroll closes. A long press is
  its own gesture and the system owns its lifecycle. The phone inherits none of that state, which
  is a genuine simplification and is worth the spec saying out loud.
- **§5's height-before-the-card measurement DOES port**, for a different reason, and is the
  phone's central card constraint rather than a centring detail.

### The prototype

Branch **`proto/05-the-reveal`** (off `proto/04-resting-marker`, so 03's Colour Slots, 04's
marker geometry and the seeded demo notes come with it). Launch with `-demo -proto-reveal`.

Four candidates on the real Sessions list and the real archived shelf. A floating bar flips the
candidate, moves the note line's weight and placement, dials the card's width, clamp, content and
forced height, forces or suppresses the marker, turns the shelf's card off, and fires a **real
reorder** through the real sort and the real List diff so the FLIP glide can be watched. The bar
also reports the card's laid-out size and both row heights live, so a held-press screenshot
carries its own numbers.

Every dial is a launch argument, so the matrix is reproducible rather than tapped:

```
proto05-shot.sh <name> -rv v1|v3|v6|v6r   -rplace underTitle|bottom
                       -rweight subline|muted|bright   -rmarker byVariant|on|off
                       -rcard note|titled  -rcardw <pt>  -rclamp <n>  -rcardh <pt>
                       -rtint <a>  -rstroke <a>  -rcardloc  -rshelfcard 0|1
                       -rinner  -rprobe  -rcollapse  -rnobar

proto05-card.sh <name> <y-pt> [args...]    # holds the press, shoots, lifts
proto05-cardbox.py <frame.png>             # the card's rendered box
```

The card only exists while a finger is down, so `proto05-card.sh` drives AXe's `touch --down` /
`touch --up` around the screenshot. Row y positions are in its header comment. The Dynamic Type
frames need the simulator's own dial:
`xcrun simctl ui <udid> content_size accessibility-large`.

The reorder recording:
`xcrun simctl io <udid> recordVideo`, tap `resort` on the bar, then step the frames.

### Amended by 06

**The over-cap fixture is 779 characters, not 671.** Counted by
[06 - The long-press menu and the Note Editor sheet](./06-menu-and-note-editor-sheet.md). The
desktop spec's own fixture is 671 (§7) and this one was written to match it; it did not. **Every
finding above stands** - the card still fills to ten lines, still elides, still never scrolls -
and now stands at the right number. The fixture text is deliberately unchanged, because editing
it would invalidate the frames below.

### Assets

The verdicts made by eye rather than by measurement, so they can be audited without a simulator.

- [The four candidates on the real list](../assets/05-four-candidates.png) - default text size.
  The decision. Cropped below the first two rows, so `chat-veil` - the busiest row, with the
  spinner and PR badge #90 - is not in this frame; it is in the full frames the shot script
  produces.
- [The same four at accessibility-large](../assets/05-four-candidates-accessibility.png).
- [The card's content](../assets/05-note-card-content.png) - note alone, note + location, and
  title + note + location. Question 3.
- [The card's width](../assets/05-note-card-width.png) - 240, 280, 300 and 340pt. Question 4.
- [The preview's clip](../assets/05-note-card-clip.png) - self-sizing against an explicit height.
  The finding under question 4.
- [The 779-character note](../assets/05-note-card-over-cap.png) - ten lines, elided. Question 5.
- [The unbreakable URL](../assets/05-note-card-url.png) - wrapped, never widened. Question 5.
- [The shelf card](../assets/05-shelf-card.png) - the same gesture on the 36pt row. Question 2.
- [V6's mixed-height reorder](../assets/05-v6-mixed-height-resort.png) - the FLIP glide, frame by
  frame. Question 6.
