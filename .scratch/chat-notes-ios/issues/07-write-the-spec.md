# 07 - Write the spec

Map: [Chat Notes on iOS](../map.md)
Type: task
Status: resolved
Claimed by: Beka Demuradze
Blocked by: 01 (resolved), 02 (resolved), 03 (resolved), 04 (resolved), 05 (resolved),
            06 (resolved), 08 (resolved), 09 (resolved)

**Unblocked. This is the last ticket on the map.**

## Question

Write the destination document at `.scratch/chat-notes-ios/spec.md`.

This is the one ticket on this map that produces a deliverable rather than a decision. It is the
map's execution override, and it is deliberately last.

The desktop spec at [.scratch/chat-notes/spec.md](../../chat-notes/spec.md) is the model for
shape and for standard. Match it:

- **Self-contained.** An implementation session should need only the spec, the glossary at
  [CONTEXT.md](../../../CONTEXT.md), and the ADR at
  [docs/adr/0001-chat-notes-sync-in-the-registry-doc.md](../../../docs/adr/0001-chat-notes-sync-in-the-registry-doc.md).
  It should not need to read this map or any ticket.
- **End state only.** Not a history of what was considered. Where a judgement call remains, name
  it explicitly as one.
- **Every value resolved.** Real numbers, real colours, real file and line references.
- **Known limits carried in full**, each stated as a decision and not as a defect. The desktop's
  known limit 6 becomes this build's central constraint and should be restated from the phone's
  side: the phone writes registry rows directly, so its own editor is the only cap there is.
- **Stated costs, not only limits.** [02](./02-character-cap-in-a-swiftui-editor.md) leaves the
  app with two text-editing stacks: the composer on `TextEditor`, the Note Editor on a
  `UIViewRepresentable`. That is a real maintenance cost and the spec should write it down rather
  than let a future reader find it.
- **A test set**, each entry earning its place. [02](./02-character-cap-in-a-swiftui-editor.md)
  already fixes three of them: characters-not-bytes and room-after-the-deletion carry as tests,
  and the boundary property carries as a code comment instead, because `String.prefix(_:)` makes
  it impossible to fail.
- **The Out of scope list carried verbatim** from the map.
- **An accessibility section, and one rule stated once.**
  [08](./08-voiceover-and-large-text.md) section 9 holds **eight** accepted limits already
  written as decisions with reasons; carry them. Its one rule - *a clamp is a height, fixed at
  what N lines occupy at the default text size* - governs the Note Card, the Note Editor field's
  floor, and its ceiling, so state it once and apply it three times rather than writing three
  numbers. 08 also amends [06](./06-menu-and-note-editor-sheet.md): read that amendment before
  describing `protoCardHeight`'s mechanism, because the mechanism is right and 06's measurement
  was not.

- **The card's corner from [09](./09-the-note-cards-corner.md), not from
  [05](./05-the-reveal.md).** 05's table says radius 12pt and 09 found that the number was never
  drawn. The corner is a **mechanism and not a number**: 12pt continuous, held by a 14pt veil of
  page colour inside the preview, because the platter owns the mask. Write the mechanism, the one
  constant it introduces, and the recipe for re-deriving that constant - 09 section 9 holds all
  three. State the constant's cost in the same voice as 08's eight limits.

Two things to settle while writing, not before:

1. **Whether the desktop spec needs an amendment.** If any ticket found that the desktop's
   stated contract is wrong or incomplete - not merely silent on iOS - say so in the answer.
   Changing the desktop is out of scope for this effort, so this is a report, not a fix.

2. **Whether the glossary needs a new term.** The reveal `05` chose may have no name in
   [CONTEXT.md](../../../CONTEXT.md) yet. If it does not, call the Skill tool with
   `domain-modeling` and add it. The existing terms - Chat Note, Colour Slot, Note Card, Note
   Editor - were written to be platform-neutral, so prefer stretching one over minting a rival.

## Answer

**The spec is written at [.scratch/chat-notes-ios/spec.md](../spec.md).** Eleven sections, in the
desktop spec's shape: model, write path, colours, marker, card, menu, editor, accessibility, test
set, known limits, out of scope. It is self-contained - an implementation session needs it, the
glossary and the ADR, and nothing from this map.

**No desktop amendment is needed. One term was stretched, not minted. Two errors in resolved work
were found while writing and are corrected in the spec**, both in the same place: what colour the
list actually paints on.

### 1. Whether the desktop spec needs an amendment

**It does not.** Every ticket that reported on this reached the same verdict independently, and
assembling them does not change it. The desktop spec is **silent on iOS or non-porting in six
places, and wrong in none of them**:

| desktop spec | the phone | why it is silence and not error |
|---|---|---|
| §2 "no optimistic local echo" | the phone echoes for free | a statement about the desktop's write path; the phone's pending overlay inverts it |
| §3 L 0.660 / C 0.112 | C 0.130 | §3 already says the triples resolve at paint time, which is the licence the phone uses |
| §4 3 x 18px, centred in a 61px row | a rule, not a number | one row shape and no Dynamic Type against two rows and text that scales |
| §5 320px text width | 300pt | a number for a window, applied to a 402pt phone |
| §5 the whole hover apparatus | no equivalent | a long press is its own gesture and the system owns its lifecycle |
| §6 dialog, keys, 14px dots in 24px targets | sheet, Return-saves, 18pt in 44pt | 24px is under the phone's 44pt minimum, and Shift+Enter has no phone meaning |

Two things are worth reporting sideways, and **neither is in scope for this map**:

- **The desktop's own dark chroma has the same gamut headroom** and could reach 0.130 with the same
  gain in separation. That would be a fresh effort against the desktop.
- **The desktop spec's §5 measures its card a frame early for centring.** The phone needs the same
  measurement for a harder reason - the preview will not size itself at all. The mechanism ports
  and the reason does not, which the iOS spec says in §5.

The one thing that is **not** a difference and reads like one: the desktop's known limit 6 ("the
cap is not a storage invariant, because iOS bypasses the Mutate RPC"). That is the desktop
correctly describing this build's central constraint from the far side. The spec restates it from
the phone's side as limit 10 rather than carrying the desktop's wording.

### 2. Whether the glossary needs a new term

**No new term. `Note Card` was stretched, and its definition had two faults the phone exposed.**
Resolved with `domain-modeling` and edited in [CONTEXT.md](../../../CONTEXT.md).

The old definition read *"The **floating** surface that shows a Chat Note in full … because the
pointer may not stay the only trigger"*, with `preview` on its `_Avoid_` list.

- **"Floating" was a desktop implementation detail in a glossary entry.** On the phone the card does
  not float beside the row; the preview **replaces** the row for the length of the press. The term
  survives, the adjective did not.
- **The `_Avoid_` list forbade the word the platform API uses.** iOS builds the card from
  `.contextMenu(menuItems:preview:)`. "Preview" is still wrong as a name for the *surface* and is
  still on the list, now scoped so an implementer is not told the API is off-limits.

The prediction inside the old definition - *named for what it shows, not for what opens it, because
the pointer may not stay the only trigger* - came true exactly, which is the argument for stretching
rather than minting. A rival term would have been the definition failing on the one case it was
written to survive.

**One naming drift found and deliberately not resolved.** The 3pt mark has no glossary term, and the
two specs call it three things: the desktop says "bar" and "stub", this map and this spec say
**resting marker**. Minting one would impose a term on the desktop's shipped vocabulary, which this
map ruled out of scope, so the spec uses "resting marker" throughout and says in its opening section
that the drift exists and is unresolved. It is a fair first ticket for whoever redraws the
destination.

### 3. Two corrections to resolved work, found while writing

Both are the same mistake, and the spec carries the corrected version.

**a. The list paints on `Theme.surface` `#0d0d0d`, not on `Theme.bg` `#060606`.** `Theme.bg`
(`apps/ios/Zeron/Theme/Theme.swift:14`) is the app root behind the list; the Sessions list and the
archived shelf set their own background at `Views/HomeView.swift:41` and `Views/SpaceView.swift:48`,
and it is `Theme.surface` (`Theme.swift:16`).

- **[03](./03-colour-slots-on-the-phone.md) labelled its `#060606` row "resting list row".** Its
  numbers are right and its labels are not. 03's own `Theme.surface` row - **5.88** - is the true
  resting number, and its two wash rows composite over the wrong background. Re-derived over
  `Theme.surface` by 03's own arithmetic: pressed **≈ 5.20** against its 5.53, selected **≈ 4.64**
  against its 4.99. The spec marks both `≈` because they are derived here and not measured by any
  prototype, and it makes the shipped contrast test assert against the real page.
  **No verdict moves**: the worst case still clears 3:1 with 1.64 to spare, so the desktop's two
  contrast-driven known limits are still gone rather than accepted, and 04's decision not to dim the
  shelf marker is untouched.
- **[09](./09-the-note-cards-corner.md) wrote "`Theme.bg` `#0D0D0D` goes to `#0F0F13`".** The hex and
  the measurement are right and the constant name is wrong - `0.7917 x 13 + (4.7, 4.7, 8.7)` is
  exactly `(15, 15, 19)`, and `#060606` would have given `#09090E`. This one **would have cost an
  implementer the whole decision**: veiling with `Theme.bg` produces a margin four units darker than
  the page, which is the visible pop 09 spent a frame-by-frame recording proving the veil does not
  have. The spec names `Theme.surface` and carries the wrong turn as an explicit warning.

Recorded here rather than edited into 03 and 09, because a resolved ticket is the record of what its
session found.

### 4. What the spec does with the ticket's other instructions

- **Known limits: fifteen**, each written as a decision with its reason. 08's eight are carried as
  written; 09's veil constant is limit 9, in the same voice and with the re-derivation recipe; the
  desktop's limit 6 is restated from the phone's side as limit 10; and the costs this ticket asked
  to be stated rather than found - two text-editing stacks, no newline authoring, the rose fallback,
  the four simulator-weakened judgements - are limits 12 to 15.
- **The one rule is stated once and applied three times.** §5 states *a clamp is a height, fixed at
  what N lines occupy at the default text size*, and the card's ten lines, the field's three-line
  floor and its six-line ceiling all cite it rather than restating a number. §8 repeats the sentence
  once, as the header of the accessibility section, because that is where its second consequence
  lives.
- **06's `protoCardHeight` is described with 08's amendment folded in**, not beside it: the spec
  says the height computation takes the content size category as an input, and names
  `Theme.sansUI`-against-`Theme.sans` as the defect rather than as a footnote.
- **The card's corner is written as a mechanism**, with the one constant, its cost, and the recipe.
  05's bare "radius 12" appears nowhere.
- **Thirty-seven tests**, grouped by section, with the seven non-obvious ones marked **guard**. 02's
  boundary property is a code comment and says why. The fixture is **779**.
- **Values this map deliberately did not pin are still not pinned**: the preview's exact clip
  ceiling, the unbuilt 344pt card, and 04's reading of the desktop's 18px as one title line.

### Where this leaves the map

**The frontier is empty and the destination is reached.** Eight decisions and one deliverable; the
fog cleared at [06](./06-menu-and-note-editor-sheet.md) and never returned. The next session is an
implementation session, and it starts from the spec.
