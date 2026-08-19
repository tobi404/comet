# 04 - The resting marker, on two row shapes

Map: [Chat Notes on iOS](../map.md)
Type: prototype
Status: resolved
Claimed by: Beka Demuradze
Blocked by: 03 (resolved)

## Question

What does the marker look like at rest, on both of the phone's row shapes?

Charting settled that the marker carries over as a stub on the row's leading edge. This ticket
gives it numbers, and it has a harder job than the desktop's equivalent had: there are two rows,
not one, and they are shaped very differently.

- **The session row**, `ChatRow` (`Views/HomeView.swift:292`): three lines, about 54pt tall,
  8pt horizontal padding inside a 12pt list inset, with a PR badge and a spinner riding
  bottom-right, and a `PressWashButtonStyle` over a clear list row background.
- **The archived shelf row** (`Views/ArchivedShelf.swift:132`): a fixed 36pt single line, 10pt
  horizontal padding, dimmed harness mark, title at 55% opacity, time-ago.

Build a throwaway prototype against the real list and answer:

1. **Geometry, per row.** Width, height, corner radius, and inset, for each of the two shapes.
   The desktop landed on 3px by 18px, fully rounded, inset 2px, centred in a 61px row. Points
   are not pixels and 36pt is not 61px, so port the intent rather than the numbers.

2. **The empty state stays free.** The desktop overlaid the stub inside the row's existing
   padding so a row with no note is pixel-identical to today, and marked and unmarked rows stay
   aligned. Confirm that holds here, or say what it costs. Watch the list's 12pt `listRowInsets`
   and the row's own 8pt padding: the marker must not push the title.

3. **The dimmed shelf.** The shelf dims its content to 55%. Decide whether the marker dims with
   it or paints at full strength. A dimmed decorative mark at a few points wide may vanish.

4. **The washes.** The marker must stay readable under `PressWashButtonStyle` and while the row
   is pressed. Look at it, do not reason about it.

5. **The PR badge and the spinner.** Both ride bottom-right, so they do not collide with a
   leading marker. Confirm by eye, and confirm the marker does not collide with the row's
   rounded corners the way the desktop had to check.

## Answer

**The marker is 3pt wide, as tall as the row's own title line, fully rounded, inset 2pt from
the row's leading edge, centred vertically - clamped to never exceed the row height less 3pt
at each end.** One rule, one set of numbers, on both row shapes. At the default text size the
title line measures **17.00pt on both rows**, so both markers are **3 x 17pt** and the clamp
does not bind. **On the archived shelf the marker paints at full strength and does not take
the row's 55% dim.**

The height is a **rule, not a number**. That is the ticket's "port the intent rather than the
numbers" taken literally, and the reason is not aesthetic: the app's `Theme.sans` is
`Font.custom(_:size:)`, which **scales with Dynamic Type**. A fixed 18pt marker looks correct
at the default size and comes apart at the accessibility sizes, where the row grows and the
marker does not. This was the whole finding of the ticket and it is not visible at the default
size at all.

Judged live on an iPhone 17 Pro simulator, flipping seven geometry candidates on the real
Sessions list and the real archived shelf.

**Named cost of the method**: the same substitution [03](./03-colour-slots-on-the-phone.md)
made - the physical iPhone was not used, so the Mac panel is not the phone's OLED. Exactly one
answer here is weakened by it: **the 3pt width**. Everything else is measured, diffed, or
resolved at three text sizes, and none of that reaches the panel. The width call carries its
own headroom below, and the branch stays installable so it can be re-confirmed on the physical
phone before [07](./07-write-the-spec.md) freezes the spec.

### The facts the ticket got wrong, measured

The ticket's own numbers were off, and the correction changes the shape of the answer.

| | ticket said | measured live |
| --- | --- | --- |
| session row (`ChatRow` wash box) | "about 54pt tall" | **61.7pt** |
| shelf row | 36pt | 36pt, confirmed |
| title line box, both rows | not stated | **17.00pt**, `Theme.sans(13)` |

**The session row is effectively the desktop's row.** 61.7pt against the desktop's 61px. So on
the session row the desktop's 3 x 18px / inset 2px is not a rough port at all - the two rows are
the same size, and the desktop's numbers land within a point of the rule. The genuine porting
problem was only ever the 36pt shelf, and the ticket's framing ("36pt is not 61px") was right
about the shelf and wrong about the session row.

### 1. Geometry, per row

| | session row | archived shelf row |
| --- | --- | --- |
| width | **3pt** | **3pt** |
| height | **the row's title line** - 17pt at default type | **the row's title line** - 17pt at default type |
| height clamp | row − 3pt at each end (never binds: 55.7pt available) | row − 3pt at each end (binds only at the accessibility sizes) |
| corner radius | fully rounded - a capsule, so radius is half the width | same |
| inset from the row's leading edge | **2pt** | **2pt** |
| vertical placement | centred | centred |
| opacity | 1.0 | **1.0** - never the row's 0.55 |

**The insets compose, they do not stack.** The list's `listRowInsets` leading is 12pt on both
sections, so the marker's leading edge lands **14.00pt from the screen edge** on every row of
both shapes. Measured, not computed - see question 2.

**Centring is unambiguous on the session row.** Its vertical padding is symmetric (6pt each
end), so the content box and the wash box share a centre. Centring in one centres in the other,
and the spec does not have to say which.

**Why the clamp is 3pt and not 2pt or 4pt.** At inset 2pt the wash box's 8pt corner arc has
retreated **2.71pt** from the row's top edge. A clamp of 3 puts the marker's end at 3pt when the
clamp binds, which leaves **+0.29pt** of clearance against that arc. The clamp is therefore the
smallest whole number that keeps question 5's answer true in the one case that can force it.
That is deliberate, and a future change to either the inset or the wash radius has to re-check
it - there is a test for exactly this below.

### 2. The empty state stays free

**It holds, and it costs nothing.** The marker is an `.overlay` on the row's wash box, so it
takes part in no layout: a row with no note is not merely similar to today's, it is identical.

Proved rather than asserted. `proto04-diff.py` diffs the same list with markers on and markers
off, and reports every column band that changed:

```
changed column bands (px, 3x scale):
  x 42..50   (3.00pt wide, starts 14.00pt from the screen edge)   <- the marker
  x 991..996, 1002..1007                                          <- see below
```

The two trailing bands also appear in the **control** - two frames with markers on in *both* -
so they are the `MiniSpinner` animating on the Working row (y 489..516), not the marker.
Subtracting the control leaves **exactly one changed band: 3.00pt wide, 14.00pt from the screen
edge.** No title moved by a pixel, on either row shape, marked or unmarked.

Confirmed by eye as well, with a hairline guide drawn down every row at the title's leading edge
(20pt = the list's 12pt inset plus the row's 8pt padding): every title sits on the line, and the
marker sits entirely to its left inside the row's own padding.

The trailing gap between the marker and the title is **+3pt** on the session row and **+5pt** on
the shelf. Both positive, so the marker never crowds the text.

### 3. The dimmed shelf

**The marker paints at full strength. It does not dim with the row.** This is the question
[03](./03-colour-slots-on-the-phone.md) delegated, and it is settled the way 03 recommended,
now with the look behind the numbers.

03 measured 55% at **2.51:1** against `#060606` and full strength at **6.13:1**, and found that
no tone fixes the dimmed case - lifting the lightness only reaches 2.95. Built at 100%, 75% and
55% side by side on the real shelf: at 55% `violet` is close to gone and `sky` is muddied, and it
looks like the 2.51 it measures. 75% is legible but weak for no gain.

**The worry that full strength would shout on a deliberately quiet surface does not survive
looking at it.** The shelf's dim exists to quiet the row's *content* - 13pt of title and a 14pt
harness mark. The marker is 3pt wide. It cannot shout; there is not enough ink in it to. It
reads as "this row has a note" and adds nothing else, which is the entire job.

So the map's one remaining sub-3:1 number is **gone, not accepted**. Every surface the marker
paints on now clears 3:1.

### 4. The washes

**The marker stays fully readable under both washes, and it was looked at, not reasoned about.**
Forced `PressWashButtonStyle`'s pressed wash (`elementHover`, white 0.06) and the selected wash
(`elementActive`, white 0.10) as static states so they could be held next to rest.

The marker sits in an overlay *over* the wash, which is what 03's numbers assume, and it survives
both: 03 measured worst-of-five at **5.53** pressed and **4.99** selected, and that is how it
looks. Nothing washes out, and nothing about the mark changes except the surface behind it.

### 5. The PR badge, the spinner, and the corners

**No collision with either, and none possible.** The badge and the spinner both ride the row's
bottom-**trailing** corner and the marker owns the leading edge; on the busiest row in the demo
list - `chat-veil`, which is Working with a spinner *and* carries PR badge #90 *and* has a note -
the three never come within 300pt of each other.

The corner question is computed rather than squinted at, and drawn at 4x beside the number:

| | marker top | corner arc at inset 2pt | clearance |
| --- | --- | --- | --- |
| session row | 22.4pt | 2.71pt | **+19.6pt** |
| shelf row | 9.5pt | 2.71pt | **+6.8pt** |
| either row, clamp binding | 3.0pt | 2.71pt | **+0.29pt** |

Every case is positive, including the worst case the clamp can produce. The desktop wrote "the
stub spans roughly y 21.5-39.5, so it cannot collide with the row's 8px corner radius"; the
phone's session row reproduces that almost exactly, and the shelf row has less room but still
2.5x what it needs.

### The mechanism, and the simpler one that the shelf refuses

The spec ships a rule that needs the title's line box at runtime. Two mechanisms were built.

**What ships: an overlay on the row's wash box**, height measured off the row's own title
(`onGeometryChange`) and clamped to the row. It costs one piece of per-row state and it works on
both shapes.

**What was refused: an overlay on the title `Text` itself.** Given a width and no height, an
overlay inherits its host's line box for free - no measurement, no clamp, and it follows Dynamic
Type automatically. It is strictly simpler, and it works on the session row, where the title is
the first thing on its line.

**The shelf row refuses it.** The shelf puts a dimmed `HarnessBadge` *before* the title, so the
same overlay lands **38pt** from the screen edge - between the mark and the title - instead of
14pt on the row's leading edge. The badge is conditional (`if let harness`), so no fixed offset
repairs it, and anchoring to the `HStack` instead just returns to measuring. Built, looked at,
and rejected on the picture: see `-mmech titleOverlay`.

This is worth writing down because the simpler mechanism is the one an implementer will reach
for, and it fails on exactly one of the two rows.

### Candidates built and refused

Seven geometries rode the real list. All are in the prototype and can be flipped back.

- **A - Desktop literal, 3 x 18pt fixed.** The strongest loser, and the one that nearly won: at
  the default text size it is indistinguishable from the answer, because the desktop's 18px and
  the phone's 17pt title line agree to within a point. **Refused on Dynamic Type**: at
  `accessibility-large` the row grows and the fixed marker does not, so it reads as a tick
  against a title twice its size and loses its relationship to the row.
- **B - Proportional, 30% of the row.** The desktop's 18-in-61 as a ratio. Refused by eye: 30% of
  the 36pt shelf is 11pt, which reads as a bullet, not a mark.
- **C - Wide short stub, 4pt x 26%.** Refused twice: 4pt competes with the title on the session
  row, and 26% of the shelf is 9pt, which becomes the coloured dot charting already rejected for
  colliding with the row's status dot.
- **D - Full-height rail, row less 4pt.** The candidate that would have had to overturn charting's
  "the marker carries over as a stub", so it was held to that. It is legible and deliberate, and
  it is refused: on the 36pt shelf a 28pt rail is 78% of a row whose entire purpose is to be
  quiet, and on a list with six noted rows it turns the leading edge into a barcode. Charting's
  decision stands and did not need overturning.
- **E - Title line, unclamped.** The right rule with a missing guard. **Refused on a defect the
  prototype found**: at `accessibility-extra-extra-extra-large` the shelf's title outgrows its
  pinned 36pt row, adjacent markers meet, and three separate notes render as one continuous
  multi-coloured stripe down the shelf. This is what the clamp exists for.
- **F - Tuned per row, 18pt session / 14pt shelf.** Two numbers where one works. Refused: the
  shorter shelf mark is visibly meeker for no gain, and a second number is a second thing to keep
  right.
- **G - Title line, clamped.** The answer.

### The width, and the one dial a real device could still move

**3pt, with the headroom named.** Isolated from height and built at 3, 3.5, 4 and 5pt:

- **3pt** reads as a mark: crisp and restrained.
- **3.5pt** is heavier and still correct. **This is the one notch the physical phone could move
  the answer to**, and 03 predicted the direction - a phone's OLED at arm's length subtends less
  than a Mac panel, so a 3pt mark can read thinner there than it does here.
- **4pt** already competes with the title on the Mac panel, so it is the ceiling, not a candidate.
- **5pt** is a bar, not a mark.

So the honest range is **3pt, possibly 3.5pt on the device, never 4pt.** 03's separation number
is what makes 3pt safe at all: at ΔE 0.126 the five are told apart at 3pt, and 03 recorded that
at the desktop's 0.109 this call would have been closer.

### Tests this ticket fixes

For [07 - Write the spec](./07-write-the-spec.md):

1. The height rule resolves to the title's line box - **17pt on both row shapes** at the default
   content size - and the clamp does not bind there.
2. The marker's height never exceeds `rowHeight − 2 * cap`. The reproducer is the shelf row at
   `accessibility-extra-extra-extra-large`, which is where candidate E broke.
3. **`cap` is greater than the wash's corner intrusion at the marker's inset.** This is the
   non-obvious one: it is the guard that stops a future change to the inset or the row's corner
   radius from silently pushing the marker outside the wash when the clamp binds. Today that
   reads 3.0 > 2.71.
4. A row with no note renders identically to the same row with the marker code removed - the
   overlay contributes no layout, on both row shapes.
5. **The shelf marker's opacity is 1.0**, not the 0.55 its sibling content carries.
6. The marker's leading edge sits 14pt from the screen edge on both sections, so a marked session
   row and a marked shelf row line up with each other.

### Reported sideways, not an amendment

**The archived shelf row clips its own content at the accessibility text sizes**, and has done
since before this effort. `ArchivedShelf.swift:153` pins the row at `.frame(height: 36)` while
its 13pt title scales with Dynamic Type, so at `accessibility-large` and above the text overflows
the row. It is not caused by the marker and the marker does not make it worse - the clamp above
keeps the marker inside the row that the text is already leaving. It wants its own fix, outside
this map, which plans rather than builds.

### For the spec's amendment report

**The desktop spec is not wrong, and needs no change.** Its §4 gives an absolute geometry
("3px wide, 18px tall ... centred vertically in the 61px row") for a platform with one row shape
and no Dynamic Type. The phone has two row shapes and text that scales, so it states the same
mark as a rule instead of a number - and at the default size that rule lands within a point of
the desktop's number, on a session row that measures within a point of the desktop's row.

Worth reporting sideways, and **flagged as an inference rather than a fact**: the desktop's 18px
looks like it is also one title line, which would mean the two apps are describing the same mark.
The desktop row's title is `text_size(px(13.0))` (`shell.rs`, `render_chat_row`) - the same size
as the Note Card's text, whose line height the desktop spec records as 19px - but the *row's* own
line height is stated nowhere and was not measured here. Do not carry this into
[07](./07-write-the-spec.md) as established. It is a pleasing reading of the desktop's number and
nothing in this ticket's answer depends on it: the rule is chosen for the phone's Dynamic Type,
not for symmetry with the desktop.

Either way, if the desktop ever gains a second row shape or a text-size setting, a rule is the
form that survives it and a number is not.

### The prototype

Branch **`proto/04-resting-marker`** (off `proto/03-colour-slots`, so 03's Colour Slots and
seeded demo notes come with it), commits `c4c4617` and `d68ed54`. Launch with
`-demo -proto-marker`.

Seven geometries on the real Sessions list and the real archived shelf in demo mode. A floating
bar flips the candidate, nudges width and inset live, forces the press and selected washes, sets
the shelf marker's alpha, draws the title-alignment guide, and turns every marker off. The Lab
sheet measures both row heights and both title line boxes live, resolves every candidate against
them, and computes the corner and content clearances.

Every dial is also a launch argument, so the whole screenshot matrix is reproducible rather than
tapped:

```
./proto04-shot.sh <name> -mv A|B|C|D|E|F|G  -mw <width>  -mi <inset>
                         -mwash rest|pressed|selected  -mshelf 1|0.75|0.55
                         -mmech rowOverlay|titleOverlay  -mmarkers off  -mguide
./proto04-strip.py out.png <y0> <y1> <name>...   # candidates side by side
./proto04-diff.py <on> <off>                     # the empty-state proof
```

The Dynamic Type findings need the simulator's own dial, which is not a launch argument:
`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`.

### Assets

The four verdicts that were made by eye rather than by measurement, so they can be audited
without a simulator. Everything else in this answer is a number and is reproducible from the
commands above.

- [Dynamic Type: fixed 18pt against the rule](../assets/04-dynamic-type-fixed-vs-rule.png) -
  candidates A and E at `accessibility-large`. The decision.
- [The clamp on the shelf](../assets/04-clamp-shelf-xxxl.png) - E against G at
  `accessibility-extra-extra-extra-large`. Left, three markers meet and read as one stripe;
  right, the clamp keeps them apart.
- [The shelf's dim](../assets/04-shelf-dim.png) - the marker at 100%, 75% and 55% on the real
  shelf. Question 3.
- [The mechanism the shelf refuses](../assets/04-mechanism-shelf-refusal.png) - `rowOverlay`
  against `titleOverlay`. Right, the harness mark pushes the marker off the row's leading edge.
