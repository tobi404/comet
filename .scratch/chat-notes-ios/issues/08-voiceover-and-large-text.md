# 08 - The reveal, read aloud and at the largest text

Map: [Chat Notes on iOS](../map.md)
Type: grilling
Status: open
Claimed by: Beka Demuradze
Blocked by: 05 (resolved), 06 (resolved)

## Question

What does a Chat Note sound like, and what does it do when the text grows?

This graduated out of the map's **Not yet specified** the moment
[05](./05-the-reveal.md) chose the reveal. It could not be phrased before that, because each
candidate presented a different thing to read out; now there is exactly one, and it is the
hardest of the four for this question.

**05's winner shows no note text at rest.** The row carries a 3pt coloured mark and nothing
else, and the text lives behind a long press. So the note is, at rest, a decoration with no
words - which is precisely the shape that a screen reader cannot infer and a large-text user
cannot enlarge. The desktop accepted a version of this as its known limit 1, "the note is
pointer-only"; the phone should decide whether it accepts the same thing or does better, and
say which.

**This is typed `grilling`, but questions 3, 4, 5 and 7 cannot be answered in conversation** -
the card at the accessibility sizes, the clamp against large text, Reduce Motion, and the sheet
against a keyboard that does not shrink all have to be looked at. Start
**`proto/06-menu-and-editor`**, not `proto/05-the-reveal`: it stacks on 05, so it carries the
card and its dials **and** the Note Editor, which 05's branch does not have at all. Launch with
`-demo -proto-reveal` for the card and `-demo -proto-editor` for the sheet and the slot row, and
drive the simulator's own text-size dial
(`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`) rather than
re-deriving them.

Answer:

1. **The resting marker under VoiceOver.** Whether it is announced at all, and if so, as what.
   The marker is decorative by [04](./04-resting-marker-on-two-row-shapes.md)'s framing and
   carries a Colour Slot, which is a colour and therefore not a label. Decide whether the row's
   accessibility label gains the note, gains only that a note exists, or gains nothing.
   Both row shapes, since the same marker paints on both.

2. **The note text under VoiceOver.** A long press is not a VoiceOver gesture. Decide the path:
   a custom accessibility action on the row, the note folded into the row's own label or value,
   or an accepted limit stated as a decision. `ChatRow` builds its label out of several `Text`
   views today, so whatever is chosen has to say what the row's whole announcement becomes and
   in what order.

3. **The Note Card at the accessibility text sizes.** [05](./05-the-reveal.md) established that
   the card's height must be **computed before the press**, and `Theme.sans` scales with Dynamic
   Type ([04](./04-resting-marker-on-two-row-shapes.md)). So the computation has to take the
   content size category as an input, and the card has to stay on screen when the text is twice
   its default size. Decide what the card does when its ten clamped lines no longer fit the
   screen: fewer lines, a scroll, or a smaller cap.

4. **The 10-line clamp against large text.** The clamp exists to bound a pathological note. At
   `accessibility-extra-extra-extra-large` ten lines is most of a phone screen. Say whether the
   clamp is a line count at every text size or a height that resolves to fewer lines as the text
   grows.

5. **Reduce Motion.** The context menu's zoom transition is the system's, not the app's. Confirm
   whether it honours Reduce Motion on its own, and if the app has any say, decide what it says.
   The app already routes its own animations through `motionAnimation` (`Theme/Motion.swift:55`).

6. **The slot row under VoiceOver.** Added by
   [06](./06-menu-and-note-editor-sheet.md), which built the control: five 18pt dots in 44pt
   targets, the chosen one ringed. The targets clear the minimum, so this is about words and not
   about size. The prototype speaks the **raw slot id** - "rose", "amber", "green", "sky",
   "violet" - which is the id the wire carries and not necessarily a label a person wants read to
   them, and the ring is a visual selected state that has to become `.isSelected` or be spoken.
   Decide what the five are called aloud, and whether "rose" is a colour name or a leak of the
   storage format. This is the same class of question as 1: a Colour Slot is a colour, and a
   colour is not a label.

7. **The Note Editor at the accessibility text sizes.** Also added by
   [06](./06-menu-and-note-editor-sheet.md). Its sheet is a **content-sized detent**, computed
   from text that scales, and its field **floors at 3 wrapped lines and grows to 6** - both of
   which get taller as the text does, against a keyboard that does not shrink. Decide what the
   sheet does when its content plus the keyboard no longer fit: a taller detent, fewer floor
   lines, or `.large`. Question 3 asks the same thing of the card; the two answers should agree
   or say why they do not.

8. **What the menu says aloud.** [06](./06-menu-and-note-editor-sheet.md) made the menu's first
   item the **only** place the shell states in words that a note exists ("Add note…" against
   "Edit note…"), and refused a resting affordance on the strength of it. If question 2 lands on
   an accepted limit, that item is the whole VoiceOver story for "this session has a note", and
   the decision should say so out loud rather than leaving it implied.

9. **What the spec carries.** Whichever of the above end as accepted limits rather than
   solutions, state each one as a decision with its reason, in the form
   [07](./07-write-the-spec.md) can carry verbatim.
