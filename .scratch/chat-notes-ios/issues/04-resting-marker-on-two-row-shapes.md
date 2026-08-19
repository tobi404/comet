# 04 - The resting marker, on two row shapes

Map: [Chat Notes on iOS](../map.md)
Type: prototype
Status: open
Blocked by: 03

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
