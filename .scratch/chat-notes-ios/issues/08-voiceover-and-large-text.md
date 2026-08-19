# 08 - The reveal, read aloud and at the largest text

Map: [Chat Notes on iOS](../map.md)
Type: grilling
Status: resolved
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

## Answer

**A clamp is a height, not a line count, and the phone speaks the note.**

Two defects were found by looking, and neither could have been found by reading. The Note Card
**clips at every text size above XXXL**, because its forced height is measured with a font that
does not scale while it paints with one that does. The Note Editor's fitted detent **has no
ceiling**, so at the largest text size with a long note the sheet runs off the top of the screen
and the Colour Slots go behind the keyboard, where they cannot be reached. One rule fixes both.

**All eleven verdicts are the human's**, taken by looking at the frames linked below and at the
accessibility trees quoted inline. The agent decided nothing alone. One of the agent's own
recommendations was **wrong and was corrected by building it**: "put the destructive action
last" is not reachable, and section 4 says why.

### The one rule

> **A clamp is a height, fixed at what N lines occupy at the DEFAULT text size. The line count
> falls as the text grows.**

It governs the Note Card's ten-line clamp and the Note Editor field's three-line floor and
six-line ceiling. It is one sentence because the card and the sheet were asked the same question
and gave the same answer, which is what the ticket asked them to do.

### 1. The Note Card at the accessibility text sizes (questions 3 and 4)

**The defect.** `protoCardHeight` measures with `Theme.sansUI(13)`. That is a raw `UIFont` and it
does **not** scale with Dynamic Type. The card paints with `Theme.sans(13)`, which is
`Font.custom(_:size:)` and **does** scale. So the `.frame(height:)` that 05 proved mandatory is a
default-size height under accessibility-size text. See [the card at four
sizes](../assets/08-card-at-size.png):

| size | the short note | the 779-character note |
| --- | --- | --- |
| L | whole, plus the `space @ device` line | 10 lines, elided with `…` |
| XXXL | whole | 8 lines, **cut with no ellipsis**, location line gone |
| AX-L | **cut mid-line** | 6 lines, cut mid-line |
| AX-XXXL | **"Ask Dana before" and nothing else** | 4 lines, cut, no ellipsis |

The mid-glyph slice is the ugliest available failure, and the missing ellipsis is worse than the
slice: the note simply stops, and nothing on screen says it was cut.

**Three rules were built and shot at AX-XXXL.** See [the three rules](../assets/08-card-rules.png).

| rule | the short note | the 779-character note | the menu |
| --- | --- | --- | --- |
| `today` | clipped to one line | 4 lines, no ellipsis | whole |
| `scaled` | whole | 10 lines, elided, honest | **"Clear note" is off the bottom of the screen** |
| `budget` | whole | 3 lines, elided, location line kept | whole |

**`budget` wins, and it is the only one that leaves both the card and the menu on screen.**
`scaled` is the tempting one - it makes the card honest about its own content - and it trades a
clipped card for a menu item a user cannot reach. That is a worse trade, and it was refused on
the frame, not on the argument.

**The resolved line counts, counted off [the budget rule at four
sizes](../assets/08-card-budget.png):** **10 at L, 7 at XXXL, 5 at AX-L, 3 at AX-XXXL.** Each one
ends in an ellipsis and each one keeps the `space @ device` line 05 put there.

**A scroll was never a candidate.** A `.contextMenu` preview is not interactive, so the third
option the ticket named does not exist on this surface.

**The clamp the `Text` is given has to agree with the height.** Under the budget rule
`lineLimit` resolves to the same falling number, otherwise the elide lands at line ten while the
mask cuts at line three, and the ellipsis never appears at all. That is exactly the `today`
failure, and it is why the rule is two changes and not one.

### 2. The Note Editor against a keyboard that does not shrink (question 7)

**The same rule, and the ticket's request that the two answers agree is satisfied by them being
one answer.** The field's floor of 3 wrapped lines and ceiling of 6 become heights, fixed at
what those line counts occupy at the default size.

**The overrun, measured.** Sheet top, with the software keyboard up and the 779-character note in
the field:

| size | ceiling as lines (06) | ceiling as height |
| --- | --- | --- |
| L | 224pt | - |
| AX-L | 133pt | 224pt |
| AX-XXXL | **57pt** | **188pt** |

At 57pt the sheet is behind the status bar and the fitted detent has silently become `.large`.
See [the overrun](../assets/08-sheet-overrun.png): the slot row is behind the keyboard and the
counter is cut in half. **A user at that text size cannot recolour a note at all.** With the
height ceiling both come back above the keyboard - see [the ceiling](../assets/08-sheet-ceiling.png).

**The cost is on the floor, and it was looked at rather than assumed.** See [the
floor](../assets/08-field-floor.png): a short note at AX-XXXL now gets a field exactly as tall as
its content plus a little slack, where 06 reserved three scaled lines. **The trade is right.** A
roomy field above a Save button you cannot reach is not a trade.

**`.large` was not needed.** The ticket offered it as the third option. The height ceiling keeps
the fitted detent under the screen at every size, so the sheet never has to change kind.

### 3. What a noted row says aloud (questions 1 and 2)

**The row gains a value, and the value is the note.** Proved in the tree on both row shapes:

```
Button 'zeron @ MacBook Pro, Working, Streaming veil on transcript rows, veil-fade'
       value='Note, Ask Dana before this merges'   actions=[...]
Button 'OKLCH conversion drift, 3d'
       value='Note, Gamut clamp was silent; write the test'   actions=[...]
```

**The desktop's known limit 1 does not carry.** "The note is pointer-only" was the desktop's
accepted cost. The phone does better, and it costs one line.

**A value, not a rebuilt label.** VoiceOver reads the label and then the value, so the note lands
at the end of the row's existing announcement and nothing already there moves. The alternative -
`.accessibilityElement(children: .ignore)` with an explicit label - would mean hard-coding
location, status, title and branch into one string, and `ChatRow` builds those from several
`Text` views today. That cost is not paid.

**"Has a note" was refused.** It is the worst of the three candidates: it tells a user something
is there and then refuses to say what.

**The marker stays silent.** It is 3pt of colour and carries a Colour Slot, and a colour is not a
label. This is the same class of answer as section 5.

**No length cap on the spoken note.** New, and not in the ticket. The card clamps because it has
a screen to fit into; speech has no such bound, and a user scanning a list swipes past. A cap
would reintroduce the desktop's known limit 1 in a quieter form.

**The prefix is "Note, ".** Without it a note that opens with a noun is indistinguishable from a
fifth column of the row.

### 4. The menu's items as accessibility actions (question 2's other half)

**The `.contextMenu` adds nothing to the accessibility tree.** The tree was dumped with the menu
attached and without it, and the two are identical: `actions=['Archive']` either way, and that
one comes from `.swipeActions`. A long press is not a VoiceOver gesture, and nothing the map
could measure gives it a substitute.

**So the row carries the items itself.** With the actions on:

```
noted row     actions=['Edit note', 'Clear note', 'Archive']
bare row      actions=['Add note', 'Archive']
shelf row     actions=['Edit note', 'Clear note', 'Unarchive']
```

**The agent's recommendation was wrong here and building it is what showed that.** "Put the
destructive action last" is not reachable. `.accessibilityActions` presents the **reverse** of
the declared order, and `Archive` comes from `.swipeActions` and lands after both whatever is
declared. The two reachable orders are `Clear note, Edit note, Archive` and `Edit note, Clear
note, Archive`. **The second is chosen**, and its `Archive` is last because the platform put it
there, not because this map did.

**The consequence is that the two note actions must be declared in the reverse of the order they
should be heard in.** That is a trap of the same shape as 06's `shouldChangeTextInRanges`: it
compiles, it runs, and it is wrong silently.

### 5. The five dots (question 6)

**They are named, and the ring is spoken.** 06's slot row speaks the raw wire id and marks the
chosen dot with `.isSelected`:

```
raw       'rose'  'amber'  'green'  'sky'  'violet'         value=''
spoken    'Rose note colour' … 'Blue note colour' …          value='Selected' on the chosen one
```

**`sky` becomes "Blue".** It is a storage token, not a word a person uses for a colour they are
picking. The other four are ordinary colour words and survive unchanged. This does not touch the
wire: the id stays `sky` and 01's decision to keep the Colour Slot id a `String` is untouched.

**The role is spoken because the control has no other name.** Five bare colour words in a sheet
say nothing about what choosing one does.

**The explicit "Selected" value exists because the trait could not be verified.**
`.accessibilityAddTraits(.isSelected)` does not appear in any tree this map can produce, so the
ring's selected state is claimed by nothing. The value is what makes it provable.

**The dots do not scale with Dynamic Type and should not.** 18pt in 44pt targets, measured at
`x` steps of 48pt. A colour swatch is not text.

### 6. Reduce Motion (question 5)

**The app says nothing, because it has nothing to say.**

**The app does see the setting**, which had to be proved before anything else meant anything. The
probe reads `RM ON` - see [Reduce Motion](../assets/08-reduce-motion.png). The app's own
animations already fall to nil through `motionAnimation` (`apps/ios/Zeron/Theme/Motion.swift:52`),
and the Chat Note adds no animation of its own: the card and the menu are both presented by
`UIContextMenuInteraction`.

**There is no API to influence that presentation**, so whatever it does under Reduce Motion is
the system's and is correct by definition.

**The one rule worth writing down** is that the Chat Note adds no animation outside
`motionAnimation`. That is a rule for the implementer, not a finding.

**Not measured, and named as such:** whether the system swaps the zoom for a cross-fade. A 30fps
capture over a 0.15s transition, on a simulator whose video omits the background blur, cannot
tell those apart.

### 7. The Note Editor field has no name (found, not asked)

Not in the ticket. 06 never looked, and the tree says:

```
TextArea  y=371 h=76 w=348  AXLabel=None  AXValue='Ask Dana before this merges'
```

**The field announces its value and its role and has no name.** VoiceOver reads the note text and
then "text field". **It gets the label "Note".** One line, and it is the difference between a
named control and an anonymous one.

### 8. What the menu says aloud (question 8)

**06's dual label survives, and its VoiceOver justification moves.**

06 kept "Add note…" against "Edit note…" partly because the menu was the only place the shell
said in words that a note exists. Sections 3 and 4 have dissolved that: the row carries the note
in its value, and "Add note" / "Edit note" are custom actions on every row. **The label now
survives on its sighted reasoning alone, which was always the stronger half.**

**06's refusal of a resting affordance gets stronger, not weaker.** A VoiceOver user reaches "Add
note" on every row without going near the menu.

### 9. What 07 carries as accepted limits (question 9)

Each stated as a decision with its reason, in the form 07 can carry verbatim.

1. **The Colour Slot is never spoken on a row.** A colour is not a label, and the marker carries
   nothing else. The note text is spoken instead, so nothing is lost.
2. **The context menu's own items are unreachable to VoiceOver**, as far as this map can measure.
   The custom actions exist *because* of that, not beside it.
3. **The rotor's order is the platform's, not ours.** `Edit note, Clear note, Archive`.
   Declaration order is reversed and `Archive` is not orderable against it.
4. **The ring's `.isSelected` trait is unverified.** No tool available here reports it. The
   explicit "Selected" value exists for that reason.
5. **Reduce Motion on the context menu's transition is unverified**, and the app has no API to
   influence it.
6. **The counter wraps to two lines at AX-XXXL, and the field's last visible line is cut by its
   own scroll.** Both are cosmetic and both survive the fix.
7. **Everything above was judged on a simulator, without live VoiceOver.** The same limit 03
   accepted for colour. It weakens the wording answers, not the geometry ones.
8. **The archived shelf row still clips its own content at the accessibility sizes.**
   Pre-existing, already on the map, not caused or fixed here.

### What this amends

**06 is amended once.** Its answer says `protoCardHeight` "computes" the card's height, per chat,
cached. That computation has to **take the content size category as an input**, and the clamp it
applies has to be a height. 06's mechanism is right and its measurement was not. Everything else
in 06 stands.

**05 is untouched.** Its rule that the height must be known before the press is unchanged and
still mandatory; this ticket only says what number that height is.

**04 is confirmed.** Its marker is a rule and not a number precisely because `Theme.sans` scales,
and the marker tracks the title line correctly at every size: the row measures 61.7pt at L and
145pt at AX-XXXL, and the marker follows.

### Assets

- [The card at four sizes](../assets/08-card-at-size.png) - the defect, on a short note and on
  the 779-character one.
- [The three rules](../assets/08-card-rules.png) - `today`, `scaled` and `budget` at AX-XXXL.
- [The budget rule at four sizes](../assets/08-card-budget.png) - 10, 7, 5 and 3 lines.
- [The sheet at four sizes](../assets/08-sheet-at-size.png) - the fitted detent tracking Dynamic
  Type, keyboard up.
- [The overrun](../assets/08-sheet-overrun.png) - the slot row behind the keyboard at AX-XXXL.
- [The ceiling](../assets/08-sheet-ceiling.png) - lines against height, at two sizes.
- [The floor](../assets/08-field-floor.png) - the cost side of the rule.
- [Reduce Motion](../assets/08-reduce-motion.png) - the probe that proves the app saw it, and the
  two transitions.

Prototype on branch `proto/08-voiceover-and-large-text`, which stacks on
`proto/06-menu-and-editor`. Dials: `-a8card`, `-a8ceiling`, `-a8row`, `-a8act`, `-a8order`,
`-a8slot`, `-a8probe`.

### Two automation traps, recorded so they are not paid twice

Both cost time in this session, and both read as app bugs.

1. **`axe` leaves the simulator believing a hardware keyboard is attached**, and then no software
   keyboard appears for any app, including Settings. `ConnectHardwareKeyboard` was already `0`.
   Only quitting and relaunching `Simulator.app` clears it. Question 7 is meaningless without the
   software keyboard, so this blocks the measurement rather than degrading it.
2. **Writing `VoiceOverTouchEnabled` through `simctl spawn defaults` clears
   `AccessibilityEnabled` and `ApplicationAccessibilityEnabled`**, and `axe describe-ui` then
   returns an empty 0x0 tree instead of an error. Write all three back to `true` to recover.
