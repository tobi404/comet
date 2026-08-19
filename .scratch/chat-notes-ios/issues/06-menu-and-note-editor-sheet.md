# 06 - The long-press menu and the Note Editor sheet

Map: [Chat Notes on iOS](../map.md)
Type: prototype
Status: open
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
