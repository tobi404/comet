# The 280 character cap in a SwiftUI text editor

Resolves: [02 - The character cap in a SwiftUI text editor](../issues/02-character-cap-in-a-swiftui-editor.md)
Map: [Chat Notes on iOS](../map.md)
Desktop reference: [.scratch/chat-notes/spec.md](../../chat-notes/spec.md), section 6, "The cap mechanism"

## How to read this

Each claim is marked. **Verified** means I read it in a primary source, and the source is named.
**Inference** means the source does not state it, and I reasoned to it. Every inference below
carries a way to test it.

This note answers only what the platform makes possible. It does not lay out the Note Editor.
That is ticket 06.

## Sources

Primary sources, all read directly:

- **The iOS 26.5 SDK API surface**, from the Xcode toolchain on this machine:
  - `.../iPhoneOS26.5.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`
  - `.../iPhoneOS26.5.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface`
  - `.../iPhoneOS26.5.sdk/System/Library/Frameworks/UIKit.framework/Headers/UITextView.h`
  - `.../iPhoneOS26.5.sdk/System/Library/Frameworks/UIKit.framework/Headers/UITextInput.h`
  - `.../iPhoneOS26.5.sdk/System/Library/Frameworks/UIKit.framework/Headers/UITextInputTraits.h`
- **Apple developer documentation**, fetched from the DocC data endpoints:
  - `TextEditor` and `init(text:selection:)`
  - `UITextViewDelegate.textView(_:shouldChangeTextIn:replacementText:)`
  - `UITextViewDelegate.textView(_:shouldChangeTextInRanges:replacementText:)`
  - `UITextInput.markedTextRange`
  - `AttributedString.transform(updating:body:)`
  - `Swift.Character`
  - `View.onChange(of:initial:_:)`
- **The app's own code**: `apps/ios/Zeron/Composer/ComposerView.swift`,
  `apps/ios/Zeron/Composer/ComposerText.swift`.

The deployment target is iOS 26.0. The SDK is iOS 26.5.

## Short answer

SwiftUI gives no character cap and no view of the input method. The one editor that can hold a
hard cap the desktop's way is a `UITextView` inside a `UIViewRepresentable`. Its iOS 26
delegate method `textView(_:shouldChangeTextInRanges:replacementText:)` is the true analogue of
the desktop's `replace_text_in_range`. The full argument and the fallback are at the end.

---

## 1. The available hooks

### 1a. There is no built-in cap, anywhere in SwiftUI

**Verified.** I searched both SwiftUI swiftinterface files, case-insensitive, for
`characterLimit`, `maxLength`, `maximumLength`, `inputLimit` and `charactersLimit`. There are
zero matches. SwiftUI ships no length limit for `TextEditor` or `TextField` on iOS 26.

### 1b. There is no view of the input method, anywhere in SwiftUI

**Verified.** I searched both SwiftUI swiftinterface files, case-insensitive, for `marked`,
`composition`, `ime` and `inputMethod`. The only matches for `marked` are the `Gauge` type's
`MarkedValueLabels`, which is a chart label and nothing to do with text. The other three terms
return nothing.

This is the load-bearing fact of the whole ticket. SwiftUI cannot tell you that an input method
is composing. A SwiftUI-level cap therefore cannot stand down during composition, because it
cannot know composition is happening.

### 1c. `TextEditor` on iOS 26 has three initialisers

**Verified**, `SwiftUI.swiftinterface:2936-2944`:

| Initialiser | Since |
| --- | --- |
| `init(text: Binding<String>)` | iOS 14.0 |
| `init(text: Binding<String>, selection: Binding<TextSelection?>)` | iOS 18.0 |
| `init(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>? = nil)` | iOS 26.0 |

The composer uses the third one (`ComposerView.swift:150`).

### 1d. Four candidate mechanisms, not three

The ticket names three. The app's code holds a fourth, and it is different enough to list apart.

**A. `.onChange` truncation.** Apple documents `onChange` as firing *after* the value changes.
The system may call the closure on the main actor (**verified**, Apple's `onChange` page). So
the over-long text has already reached the binding and the editor before you can act. You then
write a shorter value back. Cost: one full round trip through the view update per over-cap
keystroke, and a re-entrant write to the binding from inside its own change notification. The
app's own composer rejects this pattern by name (`ComposerView.swift:270-273`: "mutating the
binding from inside its own change notification is the re-entrancy the `clearDraft` comment
warns about").

**B. The binding-setter clamp.** The composer wraps the editor's binding and enforces its
invariant inside the setter (`ComposerView.swift:274-284`). The comment above it says this is
"THE ONLY PATH USER TYPING TAKES", because a keystroke writes straight to the binding and never
goes through the model's own mutation helpers. A cap can live there, and it settles in one step.
This is strictly better than A: no `onChange` round trip, and no re-entrancy. It is still after
the fact. The text view has already accepted and drawn the character; you shorten it afterwards.

**C. The `AttributedTextFormattingDefinition`.** Ruled out. **Verified**,
`SwiftUICore.swiftinterface:9517-9519`: an `AttributedTextValueConstraint` declares one
`AttributeKey` and gets one `constrain(_ container: inout Self.Attributes)` call. `Attributes`
is an `AttributeContainerProxy<Self.Scope, Self.AttributeKey>`
(`SwiftUICore.swiftinterface:9530`). It sees attributes only. It never sees or changes the
text content. It cannot count characters and it cannot delete any.

**D. `UITextView` through `UIViewRepresentable`.** This is the only mechanism that runs *before*
the edit lands. Two facts make it work:

- **Verified**, `UITextView.h:219`: `UITextView` adopts `UITextInput`. So `markedTextRange` and
  `selectedTextRange` (**verified**, `UITextInput.h:135` and `:125`) are available on the view.
- **Verified**, `UITextView.h:42` and `:54`, and Apple's two documentation pages:
  - `textView(_:shouldChangeTextIn:replacementText:)` is marked `API_TO_BE_DEPRECATED` in the
    26.5 header, with `textView:shouldChangeTextInRanges:replacementText:` named as its
    replacement. Apple's documentation page lists it as deprecated as of version 27.0. So in the
    26.5 SDK it is a soft deprecation: the symbol still exists and still compiles.
  - `textView(_:shouldChangeTextInRanges:replacementText:)` is new in iOS 26.0. It takes an
    array of ranges and one replacement string. The header states the fallback chain: if the
    delegate does not implement the plural method, the singular one is called with the union
    range; if neither exists, `true` is assumed.
- Apple documents the singular method's purpose as "You can use this method to replace text
  before it is committed to the text view storage" (**verified**, Apple's documentation page).
  Rejecting and re-applying a clamped edit inside the delegate is therefore a sanctioned use,
  not a trick.

Because the deployment target is 26.0, implement **only the plural method**. That avoids the
soft-deprecated symbol entirely.

Cost of D: it is the app's first `UIViewRepresentable`. **Verified** by grep over
`apps/ios/**/*.swift`: there are zero matches for `UIViewRepresentable`, `UITextView` and
`markedTextRange` today, and exactly two text inputs in the whole app
(`ComposerView.swift:150`, `ComposerView.swift:749`). Everything the composer rebuilt around
`TextEditor` (the placeholder overlay, the hidden `Text` height mirror, the hidden scroll
background) does not port to a representable. Ticket 06 would rebuild the equivalents.

---

## 2. The caret

### 2a. Truncating without touching the selection moves the caret to the end

**Verified**, and Apple says it twice.

Apple's `TextEditor.init(text:selection:)` page carries this note: when you bind the selection,
always update it after you mutate the text, or the editor resets the selection to the end of the
text.

Apple's `AttributedString.transform(updating:body:)` page says the same from the other side. The
method tracks the selection through the mutation so it points at the same effective locations
afterwards. If the mutation defeats tracking, for example when the closure replaces the whole
value with a different `AttributedString`, the selection is reset to a fallback location at the
end of the text.

So a naive clamp such as `text = AttributedString(String(plain.prefix(280)))` throws the caret to
the end. That is the caret jump the ticket asks about, and it is documented behaviour, not a bug.

### 2b. The selection binding can be written back, and the app already does it

**Verified**, `SwiftUI.swiftinterface:14631-14636`: `AttributedTextSelection` has public
initialisers, including `init(insertionPoint:)` and `init(range:)`. It is an ordinary value.

**Verified in the repo**: `ComposerText.replace` (`ComposerText.swift:264-282`) mutates the text
inside `attributed.transform(updating: &selection)` and then assigns
`selection = AttributedTextSelection(insertionPoint: caret)`. Its own comment says the final
assignment, not the `updating:` argument, is what decides where the caret ends up. This path
ships today and works for command and path picks.

So the recipe on any SwiftUI path is: mutate inside `transform(updating:)`, then place the caret
yourself. Deleting only the tail keeps every earlier index valid, so tracking succeeds and the
caret holds.

### 2c. What this still cannot fix

**Inference.** On paths A and B the character reaches the text view first and is drawn, then the
shorter string is written back on the next update. That is a write-back race, not a caret
calculation. The repo already has empirical evidence of it: the `clearDraft` comment
(`ComposerView.swift:676-686`) records that "A focused multiline editor commits pending
autocorrect/marked text through the binding AFTER a programmatic change, which restores the
prompt", and the workaround is a deferred second clear on the next main-actor turn. A cap on
path A or B inherits that same race.

On path D no write-back happens. The character never enters storage, so there is nothing to
restore and no race. This is exactly the desktop's property: "one clamp covers all of them and
the caret never has to be restored".

### 2d. The plain `String` overloads

**Verified**, `SwiftUI.swiftinterface:19014-19039`: `TextSelection` (iOS 18.0) carries
`Range<String.Index>` or a `RangeSet<String.Index>`, and has `init(insertionPoint:)`. It is
writeable in the same way.

**Inference**: the AttributedString overload's documented "resets the selection to the end" rule
applies to the `String` overload as well, because it is the same editor and the same problem.
Apple does not state it for the `String` overload. If ticket 06 goes down a SwiftUI path,
verify it in the prototype with one over-cap paste into the middle of a full note.

---

## 3. Marked text

### 3a. What marked text is, by contract

**Verified**, `UITextInput.h:127-135` and Apple's `markedTextRange` page. Marked text is
provisionally inserted text that the user has not yet confirmed. It happens in multistage text
input. The selection, whether a caret or a range, always sits inside the marked text.

Read that contract back against the ticket's question. Any clamp applied while
`markedTextRange` is not nil deletes text the input method still owns, and it moves a selection
that lives inside that text. That is fighting the IME, by definition of the contract. It is not a
tuning problem.

### 3b. The desktop's known limit 5 carries to iOS unchanged

**Conclusion, resting on 3a and on the verified absence in 1b.**

- On any SwiftUI path the situation is **worse than the desktop**, not equal. SwiftUI exposes no
  composition signal at all, so a SwiftUI clamp cannot even know to stand down. It will fire
  mid-composition on every over-cap keystroke.
- On the `UITextView` path the situation is **the same as the desktop**, and no better. You can
  see composition, so you can stand down. Standing down is the correct behaviour, so the
  composition can exceed 280 while it is uncommitted, and the commit truncates. That is desktop
  known limit 5, word for word.

There is no path that does better. "Better" would mean truncating a live composition, which
breaks the candidate state of the input method. The limit is inherent to multistage input, not a
shortcut anyone took.

### 3c. Where "the commit" is on the `UITextView` path

**Inference.** The header and the documentation do not say whether the delegate gate fires during
composition. The standard shape is a stand-down guard at the top of the delegate method:

```swift
if textView.markedTextRange != nil { return true }
```

and then a second clamp in `textViewDidChange` (**verified**, `UITextView.h:56`) that runs only
when `markedTextRange` is nil. The second clamp is the commit clamp.

The second clamp earns its place for a further reason. It is also the floor under every edit path
the delegate gate does not see: dictation, drag and drop (`UITextView.h:329` lists
`UITextDroppable`), and Writing Tools (`UITextView.h:307`, `isWritingToolsActive`). Writing Tools
can be closed off entirely by setting `writingToolsBehavior` to `.none` (**verified**,
`UITextView.h:310` and `UITextInputTraits.h:178-190`, where `UIWritingToolsBehaviorNone = -1` is
documented as "Writing Tools will ignore this view"). SwiftUI has an equivalent modifier,
`writingToolsBehavior(_:)`, whose `WritingToolsBehavior` type carries `.disabled` (**verified**,
`SwiftUI.swiftinterface:1450` and `:1456-1460`; the SwiftUI case is `.disabled`, not `.none`).
So this is not an argument for either path. It is a hardening step for whichever path wins.

**Verify in ticket 06's prototype**, with a Japanese or Pinyin keyboard: whether the delegate
fires during composition, and whether the commit arrives through the delegate or only through
`textViewDidChange`. Do not test this by reading code. Type into it.

---

## 4. Characters, not bytes, and boundaries

### 4a. What Swift gives for free

**Verified**, Apple's `Swift.Character` page. A `Character` is a single extended grapheme cluster
that approximates one user-perceived character. `String` is a collection of `Character`, so
`String.count` counts grapheme clusters. Apple's own example on that page shows
`"Hello! 🐥".count == 8` while `.utf8.count == 11`, and shows the United States flag as one
`Character` built from two Unicode scalars.

Two consequences follow directly:

- **Characters, not bytes** is free, but only inside `String` space. `"🇺🇸".count` is 1.
- **The cut lands on a character boundary** is free, and not merely free but impossible to get
  wrong. `String.prefix(280)` returns a `Substring` sliced on `Character` boundaries. There is no
  API on `String` that can cut a grapheme cluster in half. You have to leave `String` for
  `utf8` or `utf16` to do that.

`AttributedString` gives the same guarantee through its `characters` view, which the composer
already uses (`ComposerText.swift:97`, `String(attributed.characters)`).

### 4b. Where it stops being free

**Verified**, `UITextView.h:42` and `:54`: the delegate hands you `NSRange`, not a Swift range.
**Verified**, `UITextView.h:223`: `UITextView.text` is `@property NSString *text`, so the range
is an `NSString` range. **Verified**, Apple's `NSString.length` page: that length is the number
of UTF-16 code units, and Apple's own discussion warns that it counts the individual characters
of composed character sequences. So the delegate's ranges are in UTF-16 code units.

So on the recommended path there is exactly one dangerous boundary, and it is the
`NSRange` to `Range<String.Index>` conversion. Use `Range(nsRange, in: string)`, then count in
`Characters`. Count the raw `NSRange.length` and a flag emoji costs 4, not 1.

### 4c. Which desktop tests still need writing on iOS

The desktop test is
`the_character_cap_clamps_by_character_and_measures_room_after_the_deletion`
(`crates/ui/src/composer.rs`). Its three properties split as follows.

| Desktop property | On iOS |
| --- | --- |
| **Characters, not bytes** | **Still needs a test**, on the `UITextView` path only. Not because Swift counts wrongly, but because the UTF-16 `NSRange` conversion is the one place the count can silently become code units. On a pure SwiftUI path this one is free. |
| **The cut lands on a character boundary** | **Free.** `String.prefix(_:)` cannot split a grapheme cluster. What is worth writing is not a test of the cut but a rule in the code: never leave `String` or `AttributedString.CharacterView` for `utf16`. A test here would only prove that the standard library works. |
| **Room is measured after the deletion** | **Still needs a test**, on every path. It is arithmetic in our own code and nothing on the platform provides it. See section 5. |

So: one test on a SwiftUI path, two tests on the `UITextView` path, and both of the remaining two
are pure logic that can be unit tested without a running text view.

---

## 5. Paste over a selection

The desktop property: a note already at 280 must still accept a paste that replaces selected
text, because room is measured after the deletion.

**Whole-value mechanisms (A, `onChange`, and B, the binding setter): free.** The value you receive
already reflects the deletion and the insertion together. A plain `count > 280` check on the new
value is by construction a post-deletion measurement. There is nothing to compute.

**The `UITextView` delegate (D): not free, and it must be computed.** The delegate runs before the
edit, so you hold the old text plus a description of the edit. The arithmetic, in `Characters`:

```
room = 280 - (currentCount - deletedCount)
accepted = replacement.prefix(room)
```

where `deletedCount` is the sum of the character counts of every range passed in. The plural
signature makes this explicit and the header spells out why the sum is right: the text view will
replace one of the ranges with the replacement text and delete the text at the other ranges
(**verified**, `UITextView.h:46` and Apple's documentation page). So every range contributes to
the deletion, and only one contributes an insertion.

When `accepted.count == replacement.count`, return `true` and let the text view do the work. When
it is shorter, return `false`, apply the clamped replacement yourself, and set
`selectedTextRange` past the inserted text. That is one branch, and it is the branch that carries
the test.

**Inference**: a system paste reaches the delegate. Apple's abstract for the singular method only
mentions typing and deleting, so this is not stated. The plural method exists precisely to
describe a replacement across several ranges, which is what a paste over a discontiguous
selection is, so the intent is clear. Verify with a real paste in ticket 06's prototype.

**Note for whichever path wins:** the `textViewDidChange` floor described in 3c also covers this.
If a paste ever slips past the gate, the floor clamps it.

---

## Recommendation

**Build the Note Editor's field as a `UIViewRepresentable` around `UITextView`. Clamp in
`textView(_:shouldChangeTextInRanges:replacementText:)`. Stand down while `markedTextRange` is
not nil. Add a second clamp in `textViewDidChange` as the floor.**

Implement only the plural delegate method. The deployment target is 26.0, so the soft-deprecated
singular method is never needed.

### Why

1. **It is the only mechanism that runs before the edit lands.** Every SwiftUI hook runs after.
   That single difference is what removes the caret problem rather than managing it. The desktop
   spec's own words for its clamp, "the caret never has to be restored", are true on this path and
   on no other.

2. **It is the only mechanism that can see the input method.** *Verified absence*: neither
   SwiftUI swiftinterface contains any `marked`, `composition`, `ime` or `inputMethod` symbol on
   the text-input surface. The `UITextInput` contract (`UITextInput.h:127-135`) says the selection
   always sits inside the marked text, so a clamp that fires during composition is fighting the
   IME by definition. Only this path can decline to fire.

3. **The repo already has scar tissue from the SwiftUI write-back race.** `clearDraft`
   (`ComposerView.swift:676-686`) documents a focused editor writing pending autocorrect and
   marked text back over a programmatic change, and works around it with a deferred second clear.
   A SwiftUI cap inherits that race on every over-cap keystroke, not once per send.

4. **The plural delegate signature carries the desktop's paste property in its own shape.** It
   passes the ranges to be deleted and the text to insert, which is exactly the input to
   "measure room after the deletion".

5. **The note is plain text, so nothing is given up.** The wire format is
   `note: { text, color }`. There are no mention chips and no rich text in a Chat Note. The
   composer's `AttributedString` overload exists for chips (`ComposerText.swift:1-9`), so the
   Note Editor gains nothing from it and would pay for the formatting-definition machinery for
   nothing.

### The costs, stated plainly

- **It is the app's first `UIViewRepresentable`.** Verified by grep: zero today.
- **The composer's toolkit does not port.** The placeholder overlay, the hidden `Text` height
  mirror and `.scrollContentBackground(.hidden)` are all `TextEditor`-shaped
  (`ComposerView.swift:149-243`). A `UITextView` needs its own placeholder, its own intrinsic
  height, and `backgroundColor = .clear` plus `textContainerInset` to sit on glass.
- **Two text-editing stacks in one app.** The composer stays on `TextEditor`. This is a real
  maintenance cost, and it should be written down, not hidden.
- **This constrains ticket 06.** Ticket 06 owns the layout, but the mechanism decided here forces
  a representable at the centre of that layout. Ticket 06 should read this section before it
  draws anything.

### The fallback, and exactly what it costs

If ticket 06 finds that a representable cannot carry the sheet's look, the fallback is
`TextEditor(text: Binding<String>, selection: Binding<TextSelection?>)` with the clamp in the
**binding setter**, in the composer's own shape (`ComposerView.swift:274-284`). Not `onChange`;
the composer already documents why (`ComposerView.swift:270-273`).

The fallback must then write the selection back on the same pass, or the caret goes to the end of
the text. That is Apple's documented behaviour on both the `TextEditor.init(text:selection:)`
page and the `transform(updating:body:)` page.

The fallback accepts three defects the recommended path does not have:

1. **It fights the IME.** It cannot see composition, so it clamps mid-composition. Desktop known
   limit 5 becomes something worse on iOS, and it must be restated as its own iOS known limit.
2. **The over-cap character is drawn, then removed.** A one-frame flicker at the cap.
3. **It inherits the `clearDraft` write-back race** for pending autocorrect and marked text.

Paste over a selection and grapheme-cluster counting are both free on the fallback. Those are not
what decides this.

### What to verify in ticket 06's prototype

Three things, none of which the documentation settles. Type into a real editor; do not read code.

1. Whether `shouldChangeTextInRanges` fires during composition, and where the commit shows up.
   Use a Japanese or Pinyin keyboard. Paste a 300-character string too.
2. Whether a system paste reaches the delegate.
3. If the fallback is taken instead: whether the caret holds through an over-cap paste into the
   middle of a full note, on the `String` overload.

### Tests to carry, from the desktop's three

- **Characters, not bytes** - carry it, as a unit test on the `NSRange` to `Range<String.Index>`
  conversion. Fixture: a flag emoji and a family emoji at the cap boundary.
- **Room is measured after the deletion** - carry it, as a unit test on the clamp arithmetic. A
  note at exactly 280 must accept a paste over a selection.
- **The cut lands on a character boundary** - do not carry it as a test. `String.prefix(_:)` makes
  it impossible to fail. Carry it as a code comment instead: this file never touches `utf16`.
