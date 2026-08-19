# 03 - The resting marker on both row shapes

Spec: [chat-notes-ios/spec.md](../../chat-notes-ios/spec.md) §4, and §8's row value
Glossary: [CONTEXT.md](../../../CONTEXT.md)

**What to build:** **the first thing on screen.** A user opens the Sessions list and sees which
sessions carry a note: each one gains a small coloured stub on its leading edge, and the archived
shelf below shows the same mark on its own row shape. A session with no note looks exactly as it
does today. A VoiceOver user hears the note read out at the end of the row's existing announcement.

After this ticket the note is visible and audible at rest. Reading it in full and writing one come
next.

**Blocked by:** 01 (the note has to exist on the model), 02 (the id has to resolve to a colour).

**Status:** ready-for-agent

## Notes for the implementer

- **Read spec §4 in full.** It is the section with the most numbers and every one of them is
  measured.
- **The height is a rule, not a number, and that is the whole point.** `Theme.sans` scales with
  Dynamic Type. A fixed 18pt marker is indistinguishable from the rule at the default size and comes
  apart at the accessibility sizes, where the row grows and the marker does not. At the default size
  the rule resolves to 3 x 17pt on both rows.
- **The clamp is what stops the shelf breaking.** Without it, at the largest text size the shelf's
  markers meet and three separate notes render as one continuous multi-coloured stripe. The clamp is
  3pt at each end because the wash's corner arc reaches 2.71pt at inset 2 - 3.0 is the smallest
  whole number that clears it, with 0.29pt to spare.
- **The simpler mechanism fails on exactly one of the two rows, and you will reach for it.** An
  overlay on the title `Text` inherits its host's line box for free - no measurement, no clamp - and
  it works on the session row. The shelf puts a dimmed harness mark *before* the title, so the same
  overlay lands 38pt from the screen edge instead of 14pt, and the badge is conditional so no fixed
  offset repairs it. Ship the overlay on the row's wash box, with the height measured off the row's
  own title.
- **The shelf marker does not take the row's 55% dim.** At 55% it measures 2.51:1 and no tone fixes
  it. The dim exists to quiet the row's *content*; 3pt of ink is not content and cannot shout.
- **Build the marker as one shared piece and call it from both row builders.** The shelf builds its
  row inline while the session row is a struct, and two more tickets (04 and 06) have to touch both
  files the same way. Pay that cost once here.
- **The row's spoken value is one line and belongs here**, because it is the resting state's
  accessibility. The prefix is `Note, ` - without it a note that opens with a noun is
  indistinguishable from a fifth column of the row. Do not cap the spoken length. The marker itself
  stays silent: a colour is not a label.

## Acceptance criteria

- [ ] A noted row on the Sessions list and on the archived shelf carries a **3pt wide** stub, **as
      tall as the row's own title line**, fully rounded, **inset 2pt** from the row's leading edge,
      centred vertically, clamped to the row less 3pt at each end.
- [ ] The marker is an **overlay** and contributes no layout, so a row with no note is identical to
      the same row today. It paints **over** the press and selected washes, not under them.
- [ ] The shelf marker paints at **opacity 1.0**, never the row's 0.55.
- [ ] Both row shapes use one shared piece, called from both builders.
- [ ] Both row shapes gain `value='Note, <the note text>'`, uncapped, on top of their existing
      announcement. The marker itself announces nothing.
- [ ] Spec §9 tests **14-19** pass: the height rule resolves to the title's line box (17pt on both
      rows at the default size) and the clamp does not bind there; the height never exceeds
      `rowHeight − 2 * cap`, with the shelf at `accessibility-extra-extra-extra-large` as the
      reproducer; **`cap` is greater than the wash's corner intrusion at the marker's inset** (today
      3.0 > 2.71 - the guard against a future inset or corner-radius change); a row with no note
      renders identically to the same row with the marker code removed, on both shapes; the shelf
      marker's opacity is 1.0; and the marker's leading edge sits 14pt from the screen edge on both
      sections, so a marked session row lines up with a marked shelf row.
- [ ] The list's sort order is unchanged by a note.
