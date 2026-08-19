# 06 - The rotor: the row's custom actions

Spec: [chat-notes-ios/spec.md](../../chat-notes-ios/spec.md) §8
Glossary: [CONTEXT.md](../../../CONTEXT.md)

**What to build:** a VoiceOver user can author a note. Every row gains the long-press menu's items
as custom accessibility actions, so **Add note**, **Edit note**, **Clear note** and **Archive** are
all reachable from the rotor without the long press.

This is the last ticket. After it the feature is complete for every user, not only a sighted one.

**Blocked by:** 05 (all three menu items have to exist before they can be mirrored).

**Status:** ready-for-agent

## Notes for the implementer

**A long press is not a VoiceOver gesture, and the context menu adds nothing to the accessibility
tree.** The tree was dumped with the menu attached and without it and the two are identical. So the
row has to carry the items itself - the actions exist **because** the menu is unreachable, not
beside it.

**The order is the platform's, and it is a trap of the same shape as the delegate's Swift label: it
compiles, it runs, and it is wrong silently.**

- `.accessibilityActions` presents the **reverse** of the declared order.
- `Archive` comes from the trailing swipe and lands **after** everything declared, and is not
  orderable against it.

So the two note actions must be **declared in the reverse of the order they should be heard in**.
"Put the destructive action last" was recommended, built, and **found unreachable** - the only two
reachable orders are `Clear note, Edit note, Archive` and `Edit note, Clear note, Archive`. The
second is the one to ship, and its `Archive` is last because the platform put it there.

The row's spoken **value** (`Note, <text>`) already landed in ticket 03 and is not touched here.

## Acceptance criteria

- [ ] A noted session row exposes actions in this heard order: **Edit note, Clear note, Archive**.
- [ ] A bare row exposes **Add note, Archive**.
- [ ] A noted shelf row exposes **Edit note, Clear note, Unarchive**.
- [ ] The actions are declared in the reverse of the heard order, with a comment saying why, so the
      next reader does not "fix" it.
- [ ] Each action does the same thing as its menu item: Add and Edit open the Note Editor, Clear
      clears without confirmation, and Archive is the swipe's existing action.
- [ ] Nothing already in the row's announcement moves.

## The accepted limits this ticket ships against

None of these is a defect to fix here. They are spec §10, limits 1-7, and they belong in code
comments where they bite:

- The Colour Slot is never spoken on a row - a colour is not a label, and the note text is spoken
  instead, so nothing is lost.
- The context menu's own items are unreachable to VoiceOver, as far as this effort could measure.
- The rotor's order is the platform's, not ours.
- The chosen dot's selected **trait** is unverified - no tool available here reports it, which is
  why the explicit "Selected" value exists.
- Reduce Motion on the context menu's transition is unverified, and the app has no API to influence
  it.
- The counter wraps to two lines at AX-XXXL and the field's last visible line is cut by its own
  scroll. Both cosmetic.
- All of this was judged on a simulator, without live VoiceOver. It weakens the wording answers, not
  the geometry ones.
