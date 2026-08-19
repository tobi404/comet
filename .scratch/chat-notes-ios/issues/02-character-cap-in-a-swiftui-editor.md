# 02 - The character cap in a SwiftUI text editor

Map: [Chat Notes on iOS](../map.md)
Type: research
Status: resolved
Blocked by: none

## Question

How does a SwiftUI text editor hold a hard 280 character cap without fighting the IME, and
without the caret jumping?

This is the one place the phone cannot copy the desktop. The desktop clamps inside
`ComposerInput::replace_text_in_range`, one function every input path funnels through - typing,
IME commit, newline, paste - so one clamp covers all of them and the caret never needs
restoring (desktop spec §6, "The cap mechanism"). SwiftUI's `TextEditor` exposes no such hook.

The app's composer already uses `TextEditor` with the `AttributedString` and `selection`
overloads (`Composer/ComposerView.swift:150`), so that is the starting point, not a blank page.

Find and record, against primary sources - Apple's documentation, the SwiftUI and UIKit API
surface, and the app's own composer code:

1. **The available hooks.** What SwiftUI offers on `TextEditor` for intercepting or reacting to
   text change on iOS 26, and what each one costs. Cover at least `onChange` truncation, the
   `AttributedString` and `selection` overloads the composer already uses, and dropping to
   `UITextView` through `UIViewRepresentable` with `shouldChangeTextIn`.

2. **The caret.** Whether truncating in `onChange` moves the insertion point, and what has to
   be done to hold it. `selection` is a binding in the composer's overload, so record whether it
   can be written back and what happens when it is.

3. **Marked text.** What happens during IME composition. The desktop accepted a known limit
   here (limit 5: composition may exceed the cap while uncommitted; the commit truncates).
   Record whether the same limit is forced on iOS, or whether a `UITextView` path can do better.

4. **Characters, not bytes, and boundaries.** Confirm what Swift's `String` gives for free that
   the Rust side had to be explicit about: that a count is grapheme clusters, and that a cut
   cannot split one. Say plainly which of the desktop's three tested properties still need a
   test on iOS and which are free.

5. **Paste over a selection.** The desktop tests that room is measured after the deletion, so a
   field already at 280 still accepts a paste over selected text. Record whether each candidate
   mechanism preserves that.

Do not decide the editor's layout here - that is `06`. Answer only what the platform makes
possible, with a recommendation and the evidence for it.

## Context

This ticket is AFK. Resolve it with a subagent that calls the Skill tool with `research`, and
capture the findings at `.scratch/chat-notes-ios/research/swiftui-character-cap.md`. It writes
that one file and nothing else: no branch switch, because the working tree is live.

## Answer

Full findings, with sources and the verified absences:
[swiftui-character-cap.md](../research/swiftui-character-cap.md).

**Build the Note Editor's field as a `UIViewRepresentable` around `UITextView`. Clamp in
`textView(_:shouldChangeTextInRanges:replacementText:)`. Stand down while `markedTextRange` is
not nil. Add a second clamp in `textViewDidChange` as the floor.** Implement the plural delegate
only: the target is iOS 26.0, so the soft-deprecated singular `shouldChangeTextIn` is never
needed.

By question:

1. **The available hooks.** SwiftUI offers no character cap and no view of the input method at
   all. This is a verified absence, not an omission: neither iOS 26.5 SwiftUI swiftinterface
   carries a `characterLimit` or `maxLength` symbol, nor any `marked`, `composition`, `ime`, or
   `inputMethod` symbol on the text-input surface. Every SwiftUI hook runs **after** the edit
   lands. `shouldChangeTextInRanges` runs **before** it, which is the whole difference, and it is
   the true analogue of the desktop's `replace_text_in_range`.

2. **The caret.** Apple documents that mutating the text without updating the selection resets
   the caret to the end, on both the `TextEditor.init(text:selection:)` page and the
   `transform(updating:body:)` page. The selection binding is writeable and `ComposerText.replace`
   already writes it. On the recommended path the question does not arise, because nothing is
   mutated after the fact.

3. **Marked text.** Desktop known limit 5 carries to iOS unchanged, and **no path does better**.
   `UITextInput.h` states the selection always sits inside the marked text, so any clamp during
   composition is fighting the IME by definition. On a SwiftUI path it is strictly worse than the
   desktop's limit, not equal, so a SwiftUI path would need its own harsher known limit.

4. **Characters, not bytes.** Grapheme-cluster counting and boundary-safe cuts are free inside
   `String` space. They stop being free at the `NSRange` to `Range<String.Index>` conversion,
   which is where "characters, not bytes" earns a test again. Of the desktop's three tested
   properties, two carry to iOS as tests and one becomes a code comment: `String.prefix(_:)`
   makes a split grapheme impossible, so the boundary test cannot fail.

5. **Paste over a selection.** The plural delegate carries this property in its own signature: it
   passes the ranges to be deleted alongside the text to insert, which is exactly the input to
   "measure room after the deletion". It is free on the fallback too, so it is not what decides
   the choice. It still needs a test on whichever path ships.

**Costs, recorded rather than hidden.** This is the app's first `UIViewRepresentable` - grep
confirms zero today. The composer's placeholder overlay, hidden-`Text` height mirror, and
`.scrollContentBackground(.hidden)` are all `TextEditor`-shaped and do not port. The app ends up
with two text-editing stacks, and that belongs in the spec as a stated cost.

**Fallback**, if `06`'s prototype finds a representable cannot carry the sheet's look:
`TextEditor(text:selection:)` on the `String` overload, clamped in the **binding setter**, not in
`onChange` - the composer already documents why (`ComposerView.swift:270-273`). It accepts three
defects: it fights the IME, it draws then removes the over-cap character, and it inherits the
`clearDraft` write-back race (`ComposerView.swift:676-686`).

**Three things `06` must verify by typing, because no document settles them**: whether
`shouldChangeTextInRanges` fires during composition and where the commit lands (use a Japanese or
Pinyin keyboard, and paste 300 characters); whether a system paste reaches the delegate; and, only
if the fallback is taken, whether the caret holds through an over-cap paste into the middle of a
full note.

## Amended by 06

The recommendation above is **confirmed by typing** in
[06 - The long-press menu and the Note Editor sheet](./06-menu-and-note-editor-sheet.md): the
plural delegate fires, the composition stand-down works, the `textViewDidChange` floor catches
the commit, and a system paste arrives at the delegate and clamps. Nothing is retracted. Two
things above are wrong in a way that would cost an implementer real time.

**1. The Swift label is `shouldChangeTextInRanges`, not `shouldChangeTextIn`.** This answer names
the ObjC selector correctly and never names the Swift one, and the spelling that looks right -
`shouldChangeTextIn ranges: [NSValue]`, matching the singular's label - **compiles, satisfies no
protocol requirement, exports no selector and silently never fires**. There is no warning. The
cap then holds only from `textViewDidChange`, which draws the over-cap character and takes it
back, so the failure looks like a design flaw in the recommendation rather than a typo. Confirmed
at the ObjC runtime, not by reading: `responds(to:)` returns false for the wrong spelling and
true for the right one.

**2. "The caret never has to be restored" holds only for a PERMITTED edit.** Where the delegate
returns true, UIKit applies the edit and moves the caret, and the claim is right. On the clamped
path the delegate applies the edit itself, and `replace(_:withText:)` leaves the caret at offset
0 of what it wrote - so a 300-character paste clamped to the cap ends with the caret before the
first character. The restore must also be **deferred one run loop**; set inline it reads back
correctly and is then dragged back to 0 by the SwiftUI round trip.

**Also settled, from 06's three "verify by typing" items**: composition can exceed the cap (four
marked characters against a cap of three), so desktop known limit 5 carries unchanged; and a
system paste does reach the delegate. Not directly seen in one observation: an over-cap **commit**
being floor-cut - both halves are proved separately, and 06 names it as a test rather than a
claim.
