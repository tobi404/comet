# 05 - The reveal: how the phone shows the note

Map: [Chat Notes on iOS](../map.md)
Type: prototype
Status: claimed
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
