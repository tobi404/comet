# 02 - The five Colour Slots

Spec: [chat-notes-ios/spec.md](../../chat-notes-ios/spec.md) §3
Glossary: [CONTEXT.md](../../../CONTEXT.md)

**What to build:** the five Colour Slots become paintable on the phone. A stored slot id resolves to
a colour, an id this build has never heard of resolves to rose rather than to nothing, and the five
are far enough apart to be told from each other on a 3pt mark.

Nothing is on screen yet - this ticket and ticket 01 are the two halves the marker needs, and they
are independent of each other, so they can run in parallel.

**Blocked by:** None - can start immediately. (Independent of 01: this is the paint layer, and it
never touches the model.)

**Status:** ready-for-agent

## Notes for the implementer

- **Read spec §3 in full**, including the gamut section. Every triple, hue and threshold is there.
- **The tone is L 0.660, C 0.130.** The lightness is the desktop's and the chroma is not, and §3
  says why: the phone's darker page buys headroom to separate the five harder, and the closest pair
  rises from ΔE 0.109 to 0.126.
- **0.130 is a ceiling decision, not a taste one.** At L 0.660 the largest chroma every hue can
  reach inside sRGB is **0.1346**, and `sky` is what limits it. Above that the per-channel clamp
  silently drags the out-of-gamut slots back, which breaks the one-lightness-one-chroma premise
  invisibly. Do not raise the chroma without re-deriving that ceiling.
- **Contrast is measured against the real page colour.** The Sessions list and the archived shelf
  paint on `Theme.surface` `#0d0d0d`, not on `Theme.bg` `#060606` - spec §3 has the correction and
  the two `≈` numbers this ticket's test is what pins.
- **An unknown slot id paints as rose**, matching the desktop. A neutral grey was refused: it would
  make one synced note two different colours across the two apps, and a user reads that as the phone
  being broken. The cost is named in spec §10, limit 14.
- **The hue stays private** and the tone constants stay file-local. A caller that could see a hue
  would be tempted to store one, and a stored hue cannot follow a re-tune.

## Acceptance criteria

- [ ] A `NoteSlot` enum at the paint layer carries the five cases, with the wire id as the raw value
      and the hue private. It is the only thing a view calls to turn a stored id into a colour.
- [ ] The oklch triples are what ship, resolved at paint time through the existing `oklch()` helper.
      The reference hexes in §3 are reference only; nothing stores one.
- [ ] An id no case matches - and the empty string - resolves to rose. The same slot is also the one
      a new note starts on.
- [ ] Spec §9 tests **8-13** pass: the unknown id and the empty string return rose's colour; each of
      the five ids round-trips to its own colour; **all five slots are inside sRGB at the shipping
      tone with no channel clamps** (the guard that stops a future chroma bump from silently
      breaking the premise); worst-of-five contrast is at or above 3.0 against `Theme.surface` and
      against both washes composited over it; the closest-pair OKLab ΔE is at or above 0.12; and
      `allCases` is in wheel order, which is the Note Editor's row order.
- [ ] The contrast test asserts against the **real page colour**, not `Theme.bg`, and its output
      pins §3's two derived numbers. §3 carried them as `≈ 5.20` and `≈ 4.64`; the test
      resolves them to **5.18** and **4.62**, and §3's table is corrected to match.
