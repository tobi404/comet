# 04 - The long press: the Note Card and the menu

Spec: [chat-notes-ios/spec.md](../../chat-notes-ios/spec.md) §5, §6, and §8's clamp rule
Glossary: [CONTEXT.md](../../../CONTEXT.md)

**What to build:** a user long-presses a row and reads the whole note. On a noted row the **Note
Card** lifts in the row's place, carrying the note text, the row's `space @ device` line, the note's
colour as a tint and a hairline, and a real 12pt corner. On a row with no note the system lifts the
row itself. Under the card sits a menu: **Archive** (or **Unarchive** on the shelf) and, where a
note exists, **Clear note**.

After this ticket a note can be read in full and cleared. Writing one comes next.

**This is the hardest slice in the build.** Three of its mechanisms are counter-intuitive and each
one was settled by building the alternatives. Read spec §5 before writing anything.

**Blocked by:** 03.

**Status:** ready-for-agent

## Notes for the implementer

Three traps, each of which looks like a design flaw rather than a mistake.

**1. The preview does not size itself.** A `.contextMenu` preview lays its content out correctly and
then **masks** it, so a card taller than about two lines is cut mid-sentence. `.fixedSize` does not
help and neither does moving the attachment point - both were built. **Only an explicit
`.frame(height:)` fixes it.** So the card's height must be computed *before* the press, per chat,
at the card's width. If the forced height overshoots the content, the surplus draws as empty
container under the card, so height and content must agree.

**2. The height must take the content size category as an input.** Measuring with a raw `UIFont`
(which does not scale) while painting with a scaled font gives a default-size height whatever the
user's text size is, and **nothing warns**. The result: the card clips at every size above XXXL, a
short note is cut mid-glyph at AX-L, and at AX-XXXL a note renders three words and stops **with no
ellipsis at all**. Spec §5 names the scaled mirror to measure with.

**3. The clamp is a height, not a line count.** `10 lines at L, 7 at XXXL, 5 at AX-L, 3 at
AX-XXXL`. The tempting fix - measure with the scaled font and keep ten lines - makes the card honest
and pushes **"Clear note" off the bottom of the screen**. It was built and refused on the frame. The
`lineLimit` given to the text has to resolve to the same falling number, or the elide lands at line
ten while the mask cuts at line three and the ellipsis never appears.

**And the corner is a mechanism, not a number.** A plain radius does nothing: the system's preview
platter masks the card with a corner of its own, roughly half the card's height on a short note, so
every short card renders as a stadium and the 36pt shelf row's card renders as a full pill. The fix
is to inset the card **14pt inside the preview** and fill that margin **opaque** in the page's
colour *as the system's menu dim leaves it*. Spec §5 has the constant, the linear dim equation it
comes from, and the recipe for re-deriving it. Two things that will cost time if missed:

- **The margin must be opaque.** A transparent inset exposes the platter's own tray - a second
  surface under the card. That refusal is what proved the platter draws a background at all.
- **Veil with the page colour, which is `Theme.surface` `#0d0d0d` - not `Theme.bg` `#060606`.**
  `Theme.bg` gives `#09090E` and a margin four units darker than the page, which is a visible pop.
- **The veil goes OUTSIDE the forced height.** The preview is `card + 2 x 14` in both axes; the card
  is not. A height rule that starts measuring the padded box silently re-opens trap 1.

Two more things worth knowing:

- **The card carries the location line because the preview replaces the row.** The desktop's card
  floats beside its row, so the row stays readable. Here it does not, so at the moment the user is
  reading the note, the row's own location line is off screen. The card restates it. Adding the
  title as a third line was refused.
- **The bare row previews nothing custom.** A "No note on this session" card was built and refused:
  it carries no information, and "Add note…" in the menu (ticket 05) is the whole affordance. This
  is also the build's entire answer to discoverability - do not add a resting hint.
- **`.contentShape(.contextMenuPreview, _)` does not reach the platter.** Built at three attachment
  points, all three frames pixel-identical to the defect. Do not spend time on it.

## Acceptance criteria

- [ ] A long press on any row of either shape opens `.contextMenu(menuItems:preview:)`. A noted row
      previews the Note Card; a bare row passes **no preview closure at all**, so the system lifts
      the row.
- [ ] The menu carries **Archive** (**Unarchive** on the shelf) and, only where a note exists,
      **Clear note** with a destructive role. Clear does not ask for confirmation.
- [ ] The card is **324pt wide** (300pt of text), padded 12pt horizontal and 10pt vertical, on the
      app's surface under the note's Colour Slot at **0.10**, with a **1pt** hairline of the same
      slot at **0.32**, and the note in 13pt. Its second line is the row's `space @ device` string
      at 11pt, muted at 0.7.
- [ ] The card's height is computed before the press, per chat, **with the content size category as
      an input**, and the clamp falls **10 / 7 / 5 / 3** across L, XXXL, AX-L and AX-XXXL. Each one
      ends in an ellipsis and keeps the location line. The card never scrolls.
- [ ] The card's corner is **12pt continuous** and is the only corner on screen, held by a **14pt
      opaque veil** of the page colour under the system dim, applied **outside** the forced height.
- [ ] **One mechanism on both row shapes.** The 36pt shelf row opens the same card from the same
      gesture, with no degrade.
- [ ] Spec §9 tests **20-28** and **37** pass, including the four guards: the forced height equals
      the measured content height **at each content size category**; the forced height is the card's
      and not the preview's (`card + 2 x 14`); the rendered corner is the same on the shortest note
      and the longest, on both rows, at every text size; and the veil matches the page beside it to
      within 2 per channel in the same held-press frame.
- [ ] The trailing swipe still works on both row shapes. One gesture added must not cost the one
      that was there.
- [ ] The Chat Note adds no animation of its own outside the app's reduced-motion helper.
