# 06 - The long-press menu and the Note Editor sheet

Map: [Chat Notes on iOS](../map.md)
Type: prototype
Status: resolved
Claimed by: Beka Demuradze
Blocked by: 02 (resolved), 05 (resolved)

## Question

How does a user write, recolour, and delete a note on the phone?

Charting settled the two surfaces: a long-press context menu, and a detent bottom sheet built
from the app's own `SheetCard` and friends (`Views/SheetUI.swift`). This ticket gives them their
shape. The desktop's Note Editor (spec §6) is the reference for content, not for layout.

**Read [02 - The character cap in a SwiftUI text editor](./02-character-cap-in-a-swiftui-editor.md)
before drawing anything.** It is resolved, and it does not merely inform this ticket - it
constrains it. The field is a `UIViewRepresentable` around `UITextView`, so this ticket cannot
reach for `TextEditor` and cannot reuse the composer's placeholder overlay or its hidden-`Text`
height mirror. `02` also names three things only this prototype can settle, by typing rather than
by reading, and it names the fallback and its exact price if a representable turns out not to
carry the sheet's look.

Build a throwaway prototype and answer:

1. **The menu.** Its items, their labels, their order, their icons, and their roles. The desktop
   uses one item that changes label - "Add note…" with no note, "Edit note…" with one - because
   the menu is the one place the shell says in words that a note exists. Decide whether the
   phone keeps that, and whether Delete lives in the menu, in the sheet, or in both. Decide what
   else the menu carries, if anything: the app's row actions today are a trailing swipe to
   Archive and Unarchive, and a menu that holds only one item may look thin.

2. **The menu against `05`.** If `05` chose V1 or V6, the long press already shows the preview
   card, so the menu and the card ride one gesture. Confirm that works in practice on iOS 26 and
   that the card does not fight the menu for room. If `05` chose V3, decide whether the long
   press still previews anything at all.

3. **The menu against the swipe.** `ChatRow` already has a trailing swipe to Archive
   (`Views/HomeView.swift:261`). Confirm a long press and a swipe do not fight each other, and
   confirm the shelf's Unarchive swipe survives the same addition.

4. **The sheet.** Detent height, and the order of its parts. The desktop runs title, field, slot
   row, buttons. Decide what the phone runs, and whether the sheet has a nav bar with Cancel and
   Save or the app's pinned pill button (`Views/SheetUI.swift:143`).

5. **The field.** Its floor, its growth, and its placeholder. Which control it is, is already
   settled by `02` and is not reopened here. The desktop floors at 3 wrapped lines, grows to 6,
   then scrolls, with the placeholder "Write a note about this session…". A `UITextView` gets
   none of that for free: it needs its own placeholder, its own intrinsic height, and
   `backgroundColor = .clear` plus a `textContainerInset` to sit on this app's glass.

6. **The slot row.** Five dots, their size, their spacing, their hit targets, and how the chosen
   one is marked. The desktop uses 14px circles, 6px apart, in 24px hit targets, with a 1px ring
   on the chosen one. 24px is well under the phone's 44pt minimum, so this cannot be a port.

7. **The counter.** Whether the phone shows one, and from what count. The desktop hides it until
   240 and turns it from muted to full at 280.

8. **Delete without ceremony.** The desktop refuses a confirmation, because the Delete button
   and the clear-the-text-and-save path do exactly the same thing, and a confirm on one path
   only would make them disagree. Confirm that reasoning holds on a phone, where a mis-tap is
   more likely than a mis-click. Note that the app does use `.confirmationDialog` elsewhere
   (`Views/ArchivedShelf.swift:114`), for Clear archived, so the phone has a precedent for
   asking.

9. **Keys and dismissal.** The desktop binds Enter to save and Shift+Enter to a newline, which a
   phone keyboard cannot mean. Decide what the return key does, and what a swipe-down dismissal
   of the sheet does to unsaved text.

10. **Haptics.** The app fires `UISelectionFeedbackGenerator` on sheet row selection
    (`Views/SheetUI.swift:48`). Decide what, if anything, the slot row and the save fire.

## Answer

**The menu carries three items and the sheet carries none of them.** A long press on any row -
noted or not - opens `.contextMenu(menuItems:preview:)` with **Add note… / Edit note…**,
**Archive** (Unarchive on the shelf), and, only where a note exists, **Clear note**. The Note
Editor is a **fitted-height detent sheet** with a nav bar Cancel and Save, a `UITextView` field,
five 18pt slot dots under it, and nothing else. Nothing asks for confirmation anywhere.

**Nine of the ten verdicts are the human's**, taken by looking at the frames linked below. The
agent decided **one** alone: the label changes with state ("Add note…" against "Edit note…"),
carried from the desktop on the desktop's own reasoning. That reasoning gets stronger on the
phone, not weaker: on a row with no note the menu item is the *only* thing on screen that says
a note is possible.

**Three things the field needed that no amount of reading would have found.** They are in
section 5, and one of them is a trap that compiles clean.

### 1. The menu

| | |
| --- | --- |
| mechanism | `.contextMenu(menuItems:preview:)`, on **every** row. 05 attached only to noted rows because it had no authoring to reach |
| item 1 | **"Add note…"** with no note, **"Edit note…"** with one. `square.and.pencil` |
| item 2 | **"Archive"**, or **"Unarchive"** on the shelf. `archivebox` / `arrow.up.bin` |
| item 3 | **"Clear note"**, destructive, **only when a note exists**. `trash` |
| preview | the Note Card on a noted row (05, unchanged); on a bare row **no preview closure at all**, so the system lifts the row itself |

**Archive earns its place and the thin menu lost.** A menu holding one item under a full-width
card reads as an accident - see [the menu shapes](../assets/06-menu-shapes.png), first frame.
Archive is the one thing the row already knows how to do, and it is what the trailing swipe
already does, so the menu and the swipe say the same thing rather than two different things.

**The bare row previews nothing custom.** A muted "No note on this session" card was built and
refused - third frame of the same strip. It is a surface that carries no information, and
"Add note…" in the menu is the whole affordance. This is also the map's **Discoverability**
patch, and it closes here; see the end of this answer.

**Question 2 is answered and the answer is easy.** The card and the menu ride one gesture and do
not fight for room, including on the 779-character fixture where the card runs to its full
ten-line clamp: iOS 26 lays the card above the items and shifts the pair to fit, with both whole
on screen. See [the menu and the card](../assets/06-menu-and-card.png). 05's forced-height rule
is unchanged and still mandatory - but where 05 dialled that height by hand, 06 **computes** it
(`protoCardHeight`, rendered height at the card's width, per chat), because a menu on every row
cannot be hand-dialled. That computation is the mechanism 07 has to describe.

**Question 3 is answered and costs nothing.** The trailing swipe survives on both row shapes,
driven rather than reasoned about: [the swipe](../assets/06-swipe-survives.png) shows Archive on
a session row and Unarchive on a shelf row after the menu was added. A long press and a
horizontal drag are different gestures and iOS tells them apart.

**The shelf is unchanged from 05**: same gesture, same card, and the menu's second item flips to
Unarchive. See [the shelf](../assets/06-shelf-menu.png).

### 2. The sheet

| | |
| --- | --- |
| title | **"Session note"**, inline, in a `NavigationStack` |
| chrome | **Cancel left, Save right**, in the nav bar. Not the app's pinned pill |
| detent | a **custom `.height()` sized to the sheet's own content**, growing with the field. `.medium` is not a candidate |
| order | **field → slot row**. The desktop's order, minus the buttons that moved into the bar |
| background | `SheetStyle.panel`, drag indicator visible, corner radius 32 - the app's own sheet, unchanged |
| clear | **not here.** Clear note lives in the menu only |

**`.medium` is refused on a measurement, not on taste.** With the keyboard up it swells to
near-full-screen and leaves roughly 470pt of empty container between the slot row and the
keyboard. See [the detent](../assets/06-detent.png): `.medium` on the left, the fitted height on
the right, both with the keyboard up. A pinned 280pt was the first fix and is still wrong on a
long note; the content-sized detent is the rule.

**The rule, and its one measured number.** `detent = content height + 60`, where 60 is the nav
bar, the grabber above it, and the room under the content. **60 is measured off the frames, not
derived** - 07 should carry it as a measurement and re-check it if the nav bar changes. Content
floors at about 173pt for a bare row (padding 40 + field 75 + 14 + slot row 44) and rises to
about 230 as the field grows to its ceiling.

**The pill lost, and it was close.** `SheetPrimaryButton` (`SheetUI.swift:143`) is the app's own
shape and SpaceView uses it, but it needs a taller detent to hold the pill clear of the keyboard
and it puts Save a thumb-stretch from the field. Both were built - see
[the chrome](../assets/06-sheet-chrome.png), which also shows "both" and the double Save that
makes it obviously wrong.

### 3. The slot row

**Five dots at 18pt, 6pt apart, in 44pt hit targets, with a 1pt ring in `Theme.text` at 0.85
held 4pt out from the chosen dot.**

The desktop's 14px dot does **not** port and its 24px target certainly does not. See
[the slot row](../assets/06-slot-row.png), which holds all three marks and two geometries at
full scale:

- **ring at 18pt** - the answer. The ring reads instantly and the dot is big enough for an OLED
  at arm's length.
- **ring at 14pt** - the desktop's size, ported. Legible, and smaller than the phone wants.
- **check** - refused. A tick sized to a 14pt dot crowds it and eats the colour the row exists
  to show.
- **grow** - refused. 14 against 18 cannot be read without a second dot to compare against, which
  is exactly what a selected state must not need.

The ring is held one cell out from the **dot**, not from the 44pt target: at 44 it becomes a hoop
with the dot rattling inside it.

### 4. The field

02 settled the mechanism and this ticket did not reopen it. What 06 adds is the arithmetic 02
correctly said a `UITextView` gets none of for free.

| | |
| --- | --- |
| control | `UIViewRepresentable` around `UITextView`, per 02 |
| font | **15pt**, matching `SheetSelectRow`'s title, through `UIFontMetrics` so it scales |
| floor | **3 wrapped lines**, grows to **6**, then scrolls. The desktop's numbers, unchanged |
| placeholder | **"Write a note about this session…"**, a `UILabel` child pinned to the text container inset |
| chrome | `backgroundColor = .clear`, `textContainerInset` 10/12, `lineFragmentPadding = 0`, `keyboardAppearance = .dark` |
| focus | lands in the field on open, from **`didMoveToWindow`** |
| cap | **280 characters** |

**The representable carries this app's glass, so 02's fallback is not taken.** Inside `SheetCard`
it is indistinguishable from the composer's `TextEditor` at rest - the fallback was built anyway
and sits beside it in [the field](../assets/06-sheet-order-field.png), third frame. 02's three
named defects therefore stay unpaid.

**Focus needs `didMoveToWindow`.** `becomeFirstResponder()` from `makeUIView`, even deferred one
run loop, is too early: the view is not in a window and the keyboard never comes up. The caret
appears and the keyboard does not, which reads as a simulator problem and is not one.

**Growth belongs in `sizeThatFits(_:uiView:context:)`, not in the delegate.** That is the only
place SwiftUI hands over the **proposed width**, and the height is a function of it. Measuring off
`bounds.width` gives a floor computed at width zero on the first pass.

**The floor and the ceiling must be measured, not multiplied.** `font.lineHeight * 6` is not the
height of six laid-out lines - TextKit's line fragment is slightly taller - so a ceiling built on
the font clips its last line. Found by looking at a six-line note cut through the middle of line
six. Measure with `boundingRect` on a probe of N lines, in the same font.

### 5. The three findings, and the one that compiles clean

**a. The plural delegate's Swift label is `shouldChangeTextInRanges`, and the obvious spelling
silently does nothing.**

Swift keeps "Ranges" on the plural so it does not collide with the singular. Writing
`shouldChangeTextIn ranges: [NSValue]` - which is what the singular's label looks like and what
02's prose reads like - **compiles, satisfies no protocol requirement, exports no selector, and
never fires**. The cap then holds only from `textViewDidChange`, which draws the over-cap
character and takes it back. There is no warning.

Caught because the log showed a clamp that could only have come from the floor, then confirmed at
the ObjC runtime rather than by reading:

```
class A: NSObject, UITextViewDelegate {   // shouldChangeTextInRanges ranges:
class B: NSObject, UITextViewDelegate {   // shouldChangeTextIn        ranges:
let sel = Selector(("textView:shouldChangeTextInRanges:replacementText:"))
A().responds(to: sel)  ->  true
B().responds(to: sel)  ->  false
```

**02's recommendation is right and is confirmed, once the label is.** See
[the delegate](../assets/06-delegate.png): `plural=true`, `plural(1) +1`, `full — refused 1`, and
the over-cap character never drawn. The right frame hides the singular from the runtime, proving
the plural is not merely winning a tie - it is called on its own. Implementing both, the plural
wins.

**b. A clamped edit leaves the caret at the start of what it wrote, and the restore has to be
deferred.**

02 says "the caret never has to be restored". That holds for an edit the delegate **permits** -
UIKit applies it and moves the caret. It does **not** hold on the clamped path, where the
delegate applies the edit itself: `replace(_:withText:)` leaves the caret at offset 0 of the
replacement, so a 300-character paste clamped to the cap ends with the caret before the first
character. Setting `selectedRange` inline reads back correctly and is then dragged back to 0 by
the SwiftUI round trip; posting it to the next run loop holds. See
[the caret](../assets/06-paste-caret.png) - `caret 0` on the left, `caret 40` on the right.

**c. A `UITextView` in SwiftUI needs its horizontal compression resistance lowered.**

Its intrinsic content size is its *content* size, and it resists compression at `.defaultHigh`.
Left alone, a long single-paragraph note makes the field hundreds of points wide: the note draws
as one clipped line and the slot row is shoved off the sheet entirely. `.defaultLow` on both
compression resistance and hugging, horizontally, fixes it. This is the third thing the
composer's `TextEditor` got for free.

### 6. The cap, verified by typing

02 named three things only typing could settle. Two are now settled and one is partly settled.

**Paste reaches the delegate.** A 300-character system paste against a cap of 40 arrives as
`plural(1) +300` and clamps to exactly 40. Room is measured after the deletion, which the plural
signature hands over for free.

**The IME fires the delegate, and the stand-down works.** With a Japanese keyboard, every
keystroke of a `nihongo` composition arrives as `plural(1) +1` with `markedTextRange` non-nil, and
stands down. See [the IME](../assets/06-ime.png).

**Composition exceeds the cap, so desktop known limit 5 carries unchanged.** Four marked kana
against a cap of three, counter reading **4/3**. Committing a candidate arrives through the same
delegate while the range is still marked, so the delegate cannot clamp a commit - the floor in
`textViewDidChange` is the only thing that can, and the floor is separately proved (`floor cut
41 → 40`).

**Named as not directly seen**: an over-cap **commit** being floor-cut in one observation. Both
halves are proved separately; the combination needs a specific IME candidate, and the simulator's
input-source cycling is not deterministic under HID automation. 07 should carry this as a test,
not as a claim.

### 7. The counter

**The desktop's rule ports unchanged: hidden until 240, `Theme.textMuted`, turning `Theme.text`
at 280.** It sits on the slot row, pushed right. Verified at its real thresholds rather than at a
convenient small cap - see [the counter](../assets/06-counter.png): absent at 239, muted at 245,
full at 280.

### 8. Clearing, without ceremony

**No confirmation, on either path.** The desktop's reasoning holds on a phone and the human took
it knowing the menu item is one mis-tap away: Clear note and the clear-the-text-and-save path do
exactly the same thing, and a confirm on one path only would make them disagree. The app's
`.confirmationDialog` precedent (`ArchivedShelf.swift:114`) is for *Clear archived*, which
destroys many sessions at once; a note is one short capped text.

**Clear lives in the menu only.** It was built in the sheet too and refused: two Clears for one
act, when the in-sheet path is already select-all, delete, Save. A confirmation was built and
photographed anyway - fourth frame of
[the round trip](../assets/06-save-round-trip.png) - so the option that was refused can be seen.

### 9. Keys and dismissal

**Return saves and dismisses.** The newline is refused before it lands. Verified end to end: the
sheet closes and the row gains its marker.

**Its price, and 07 must write it down: the phone cannot author a multi-line note.** A note
written with line breaks on the desktop is unharmed - it loads into the field and saves back with
its newlines intact - but no newline can be typed here. This is a real narrowing against the
desktop, taken deliberately because Save is one thumb away and a note is one sentence.

**A swipe-down discards, with no prompt.** The desktop's Escape, unchanged, so Cancel and the drag
mean one thing rather than two. Driven with dirty text rather than reasoned about: forty
characters typed, dragged shut, and the row has no marker. See
[the drag](../assets/06-drag-discard.png).

### 10. Haptics

**The slot row fires `UISelectionFeedbackGenerator().selectionChanged()`. Save fires nothing.**

Tapping a slot is a selection and the app already gives selections exactly this feedback
(`SheetUI.swift:48`); using the same generator makes the Note Editor feel like the app's other
sheets rather than like a new thing. Save is deliberately silent: the sheet closing and the marker
appearing is the feedback, and the app has no success-haptic anywhere for this to match.

**Named as unverified: the simulator renders no haptics at all.** The code path is real and was
exercised; how it feels is a device question. This is a reasoned answer, not a prototype one.

### Discoverability, which the map left in the fog

**It closes here, and the answer is that the phone does not add an affordance.**

The map's fog said the question waited on the menu's final shape. The menu now has one, and the
human answered the question directly by refusing the hint card: **"Add note…" in the long-press
menu is the whole affordance**, and a surface whose only content is "there is no note here" is
noise on a list that 05 chose specifically to keep calm.

The sharper half of the fog - "a user with six notes cannot read one without pressing" - is not
a new question. It is 05's verdict, taken on the real list against three candidates that each put
note text on a row, and the map already records why: the phone's list is dense, and every one of
them spent the list's calm to save one press. Reopening it here would re-litigate a decision the
human made by looking.

So the patch is cleared rather than graduated. **No ticket.**

### Corrections to resolved work

**05's "671-character note" is 779 characters.** The desktop spec's own fixture is 671 (§7) and
the iOS fixture was written to match it; it did not. Counted, not eyeballed. **Every claim 05
makes about it stands** - it still fills the card to ten lines, still elides, still never scrolls
- they stand at 779. The fixture text is deliberately left alone, because changing it would
invalidate 05's frames. 07 must not write "671" for the iOS fixture.

**02 needs two repairs and no retraction.** Its recommendation - the plural delegate, the
composition stand-down, the `textViewDidChange` floor - is confirmed by typing. But: it never
names the Swift label, which is where the recommendation actually fails, and its "the caret never
has to be restored" is true only for permitted edits. Both are section 5 above.

### Tests this ticket fixes

For [07 - Write the spec](./07-write-the-spec.md):

1. **The clamp refuses rather than trims after the fact.** The over-cap character is never drawn.
   This is the test that catches the wrong Swift label, and it is the only one that does.
2. **A 300-character paste into an empty field leaves exactly 280 characters and the caret at
   280.** One test, both of section 5's first two findings.
3. **A note longer than one line does not widen the field.** The guard on the compression
   resistance; a single-paragraph fixture with no spaces is the reproducer.
4. **The field floors at three lines and stops growing at six.** Measured against laid-out line
   height, not `font.lineHeight * n`.
5. **A commit from an input method that lands over the cap is truncated to the cap.** The floor,
   and the one thing this ticket proved only in halves.
6. **The sheet's detent equals its content height plus the chrome.** Too small scrolls a sheet
   that should not scroll; too large draws the void `.medium` draws.
7. **Clearing from the menu and saving blank text produce the same stored result.** This is what
   makes "no confirmation" honest rather than convenient.
8. **A long press and a trailing swipe both still work on both row shapes.** One gesture added
   must not cost the one that was there.

### For the spec's amendment report

- **§6's menu entry ports and gains two neighbours.** The desktop's one contextual item is right;
  the phone's menu needs Archive beside it or it does not read as a menu, and Clear note moves
  *into* the menu because the phone has no dialog button row to put it in.
- **§6's dialog does not port as a dialog.** Title, field, slot row, buttons becomes nav bar,
  field, slot row - the buttons move into the chrome and the title becomes the nav title.
- **§6's 14px dots in 24px targets do not port.** 24 is under the phone's 44pt minimum, and 14pt
  is under what the phone wants. 18pt dots in 44pt targets.
- **§6's keys do not port and cannot.** Enter saves - kept, at the cost of authoring a newline at
  all. Shift+Enter has no phone meaning. Escape becomes the swipe-down, and discards.
- **§6's cap mechanism ports in shape and not in code.** One pre-edit hook, one clamp, every input
  path through it - all true. The hook is `shouldChangeTextInRanges`, not
  `replace_text_in_range`, and it does not cover the input method.
- **§6's "Delete does not ask" carries verbatim**, including its reasoning, on a phone where a
  mis-tap is likelier. The word is **Clear**, not Delete (CONTEXT.md).
- **§6's counter rule carries verbatim.**

### The prototype

Branch **`proto/06-menu-and-editor`** (off `proto/05-the-reveal`, so 03's Colour Slots, 04's
marker, 05's Note Card and the fixtures come with it). Launch with `-demo -proto-editor`.

**The notes are live.** Save, recolour and Clear land in `ProtoNoteStore` and the list's marker
and the long press's card repaint from it. Questions 8 and 9 are both about what happens to text
a user entered, so a sheet that discarded its typing could not have answered either.

**The defaults ARE the answer** - the verdicts were folded back in as they were given, so a bare
launch shows the shape 07 has to write down. Every losing option survives as a dial:

```
proto06-shot.sh <name> [args...]              # the list, or the sheet with -sopen
proto06-menu.sh <name> <y-pt> [args...]       # holds the long press, shoots, lifts
proto06-strip.py out.png y0 y1 <names...>     # the side-by-side strips
proto06-build.sh                              # build and install, quiet unless it fails

-mlabel dual|fixed     -mclear none|menu|sheet|both   -mconfirm none|menu|both
-mextras none|archive  -mbare system|hint             -micon <sf symbol>
-schrome navbar|pill|both   -sorder fieldSlots|slotsField
-sdetent <pt>          # 0 = fitted to content, <0 = .medium
-sfield uikit|swiftui  -sfloor <n>  -sgrow <n>
-sdot <pt>  -sgap <pt>  -shit <pt>  -smark ring|check|grow
-scount <n>  -scap <n>  -sreturn newline|save  -sdismiss discard|save|ask
-shaptic none|slot|save|both   -ssingular 0   -slog   -sopen <chatId>
```

`-slog` draws the delegate's own record on the sheet, which is how sections 5 and 6 are
screenshots instead of assertions. `-ssingular 0` hides the singular delegate from the ObjC
runtime, which is the only way to tell "the plural loses a tie" apart from "the plural is dead".

### Named cost of the method

**Judged on an iPhone 17 Pro simulator**, the same substitution 03, 04 and 05 made. What it
weakens here:

1. **Haptics entirely.** Section 10 is reasoning, not observation.
2. **The 18pt dot and the 44pt target.** Chosen for arm's length on a device the answer never met.
3. **The fitted detent while the keyboard animates.** The detent is proved to track the content;
   whether the keyboard survives every growth step is not, because `axe type` drops the software
   keyboard at the end of a run and the artefact sits exactly on top of the question.

Two automation traps are recorded in the scripts so they are not re-discovered: `axe type`
**swallows a trailing newline**, and a headless-booted simulator shows no software keyboard until
`Simulator.app` is attached.

### Assets

- [The answer](../assets/06-answer.png) - the menu on a noted row and a bare row, and the sheet
  editing and adding. Everything below is the working that led here.
- [The menu and the card](../assets/06-menu-and-card.png) - question 2, on a short note, the
  779-character note, and a bare row.
- [The menu shapes](../assets/06-menu-shapes.png) - thin, with Clear, and the refused hint card.
- [The shelf](../assets/06-shelf-menu.png) - the same gesture on the 36pt row.
- [The swipe](../assets/06-swipe-survives.png) - question 3, driven on both row shapes.
- [The detent](../assets/06-detent.png) - `.medium` against the fitted height, keyboard up.
- [The chrome](../assets/06-sheet-chrome.png) - medium, pinned 280, the pill, and both.
- [The fixtures](../assets/06-sheet-fixtures.png) - the over-cap note, a wrapping note, and empty.
- [The field](../assets/06-sheet-order-field.png) - field-first, slots-first, and 02's fallback.
- [The slot row](../assets/06-slot-row.png) - three marks and two geometries, at full scale.
- [The counter](../assets/06-counter.png) - 239, 245, 280.
- [The delegate](../assets/06-delegate.png) - the plural firing, and the singular hidden.
- [The IME](../assets/06-ime.png) - composition past the cap, 4/3.
- [The caret](../assets/06-paste-caret.png) - a clamped paste, before and after the deferred
  restore.
- [The round trip](../assets/06-save-round-trip.png) - type, recolour, save, and the row's new
  marker. The fourth frame is the refused confirmation.
- [The drag](../assets/06-drag-discard.png) - dirty text, dragged shut, nothing stored.
