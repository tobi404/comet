# 05 - The Note Editor sheet

Spec: [chat-notes-ios/spec.md](../../chat-notes-ios/spec.md) §7, and §8's clamp rule
Glossary: [CONTEXT.md](../../../CONTEXT.md)

**What to build:** the phone authors notes. **"Add note…"** (or **"Edit note…"** where one exists)
joins the long-press menu and opens the **Note Editor**: a bottom sheet sized to its own content,
with the note text in a field capped at 280 characters and the five Colour Slots as dots below it.
Cancel and Save sit in the nav bar. Return saves and dismisses. A swipe down discards.

After this ticket the feature is complete for a sighted user: a note can be written, recoloured,
read and cleared, entirely on the phone.

**Blocked by:** 04 (the menu it launches from), 01 (the write path it saves through).

**Status:** ready-for-agent

## Notes for the implementer

**The field is a `UIViewRepresentable` around `UITextView`, and this is not a preference.** SwiftUI
offers no character cap and **no view of the input method at all** - a verified absence, not an
omission. Every SwiftUI hook runs *after* the edit lands. The delegate's pre-edit hook runs
*before* it, which is the whole difference. This makes the field the app's **first**
`UIViewRepresentable` and leaves the app with two text-editing stacks. That cost is accepted and
recorded in spec §10, limit 13.

Five traps, all of which compile clean.

**1. The Swift label is `shouldChangeTextInRanges`.** Swift keeps "Ranges" on the plural so it does
not collide with the singular. The spelling that looks right - matching the singular's label -
**compiles, satisfies no protocol requirement, exports no selector, and never fires.** There is no
warning. The cap then holds only from the fallback, which draws the over-cap character and takes it
back, so the failure looks like a design flaw rather than a typo. **Test 29 is the only test that
catches this.**

**2. A clamped edit leaves the caret at offset 0 of what it wrote, and the restore must be deferred
one run loop.** "The caret never has to be restored" is true only for an edit the delegate
*permits*. On the clamped path the delegate applies the edit itself, so a 300-character paste
clamped to the cap ends with the caret before the first character. Setting the selection inline
reads back correctly and is then dragged back to 0 by the SwiftUI round trip.

**3. A `UITextView` in SwiftUI needs its horizontal compression resistance lowered.** Its intrinsic
content size is its *content* size, so left alone a long single-paragraph note makes the field
hundreds of points wide: the note draws as one clipped line and the slot row is shoved off the sheet
entirely.

**4. Focus needs `didMoveToWindow`.** Asking for first responder from `makeUIView`, even deferred
one run loop, is too early - the view is not in a window and the keyboard never comes up. The caret
appears and the keyboard does not, which reads as a simulator problem and is not one.

**5. The floor and ceiling must be measured, not multiplied.** `font.lineHeight * n` is not the
height of n laid-out lines - TextKit's line fragment is slightly taller - so a ceiling built on the
font clips its last line.

**The detent is content-sized, and the ceiling is what keeps it usable.** `.medium` is refused on a
measurement: with the keyboard up it swells to near-full-screen and leaves roughly 470pt of void.
And the field's floor and ceiling are **heights**, per the same rule the card obeys - as line counts
they grow with the text, and at AX-XXXL with a long note the sheet's top reaches **57pt**, the
fitted detent has silently become `.large`, and **the Colour Slots sit behind the keyboard where
they cannot be reached at all.**

Two smaller decisions worth not re-litigating:

- **Return saves, and the price is that the phone cannot author a newline.** A multi-line note
  written on the desktop loads, edits and saves back intact, but none can be typed here. Taken
  deliberately.
- **Clear note lives in the menu only.** It was built in the sheet too and refused: two Clears for
  one act, when the in-sheet path is already select-all, delete, Save. Nothing asks for
  confirmation on either path - a confirm on one path only would make the two disagree.

## Acceptance criteria

- [ ] The menu's first item reads **"Add note…"** with no note and **"Edit note…"** with one, on
      every row of both shapes.
- [ ] The sheet is titled **"Session note"** (product copy - carry it verbatim; identifiers stay
      `ChatNote`), inline, with **Cancel left and Save right in the nav bar**, on a custom
      `.height()` detent sized to its own content and growing with the field. It runs **field →
      slot row** and nothing else.
- [ ] The field caps at **280 characters** in the pre-edit delegate, **stands down while text is
      marked**, and carries a second clamp as the floor. The over-cap character is **never drawn**.
- [ ] The field's floor of **3 wrapped lines** and ceiling of **6** are **heights**, fixed at what
      those counts occupy at the default text size, so the sheet stays above the keyboard and the
      slot row stays reachable at every text size.
- [ ] The slot row is **five 18pt dots, 6pt apart, in 44pt hit targets**, with a **1pt ring** held
      4pt out from the chosen dot. It fires selection feedback; Save fires nothing.
- [ ] The counter sits on the slot row pushed right, **hidden until 240**, muted, turning full at
      280.
- [ ] **Return saves and dismisses.** A swipe down discards with no prompt. Nothing asks for
      confirmation anywhere.
- [ ] The field carries the accessibility label **"Note"**, and the five dots are spoken as
      **"Rose note colour"** and so on, with `sky` spoken as **"Blue"** and the chosen one carrying
      an explicit **"Selected"** value. The wire id stays `sky`.
- [ ] Spec §9 tests **29-36** pass, including the guard that the clamp **refuses rather than trims**
      (the only test that catches trap 1); a 300-character paste leaving exactly 280 characters
      **and the caret at 280**; an over-cap input-method commit being truncated; a long
      single-paragraph note not widening the field; the floor and ceiling measured against laid-out
      line height; and the detent equalling content height plus chrome.
