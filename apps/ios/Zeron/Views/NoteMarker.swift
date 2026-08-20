// The resting marker: the Chat Note on a row, at rest — spec §4, and §8's
// row value.
//
// **The height is a rule, not a number.** `Theme.sans` scales with Dynamic
// Type, so a fixed marker is indistinguishable from the rule at the default
// size and comes apart at the accessibility sizes, where the row grows and
// the marker does not. The rule is "as tall as the row's own title line",
// clamped to the row less `cap` at each end.
//
// **The mechanism, and the simpler one the shelf refuses.** An overlay on the
// title `Text` inherits its host's line box for free — no measurement, no
// clamp — and it works on the session row. The archived shelf puts a dimmed
// harness mark BEFORE the title, so the same overlay lands 38pt from the
// screen edge instead of 14pt, and the badge is conditional (`if let
// harness`), so no fixed offset repairs it. What ships instead: the title
// publishes its height, and the marker is an overlay on the ROW's wash box.
// The title gives the height; the row gives the position.

import SwiftUI

// MARK: - The numbers

/// Every measured number the resting marker is built from (§4). They live in
/// one place because §9's tests measure the rule, not a literal, and because
/// two more tickets touch both row shapes the same way.
enum NoteMarker {
    /// 3pt is wide enough to tell the five Colour Slots apart, packed
    /// adjacent with no gap; 2pt is where `rose` and `amber` begin to merge.
    static let width: CGFloat = 3

    /// From the row's leading edge. The list's `listRowInsets` leading is 12pt
    /// on both sections, so the marker's leading edge lands 14pt from the
    /// screen edge on every row of both shapes — they compose, they do not
    /// stack.
    static let leadingInset: CGFloat = 2

    /// The clamp at each end of the row.
    ///
    /// **Why 3 and not 2 or 4.** At `leadingInset` the wash box's 8pt corner
    /// arc has retreated 2.71pt from the row's top edge. A clamp of 3 puts
    /// the marker's end at 3pt when the clamp binds, leaving +0.29pt of
    /// clearance against that arc. It is the smallest whole number that keeps
    /// the marker inside the wash in the one case that can force it.
    ///
    /// **Without it the shelf breaks, and it was seen breaking.** At
    /// `accessibility-extra-extra-extra-large` the shelf's title outgrows its
    /// pinned 36pt row, adjacent markers meet, and three separate notes render
    /// as one continuous multi-coloured stripe down the shelf.
    ///
    /// A change to `leadingInset` or to the wash's corner radius has to
    /// re-check that against `cornerIntrusion(radius:)`. Test 16 is the guard.
    static let cap: CGFloat = 3

    /// The rule: the row's own title line, clamped to the row less `cap` at
    /// each end.
    static func height(titleLine: CGFloat, rowHeight: CGFloat) -> CGFloat {
        max(0, min(titleLine, rowHeight - 2 * cap))
    }

    /// How far a rounded rect's corner arc has retreated from its top edge,
    /// `leadingInset` in from its leading edge. `cap` has to clear this, or a
    /// bound clamp puts the marker's end outside the wash it paints on.
    static func cornerIntrusion(radius: CGFloat, inset: CGFloat = leadingInset) -> CGFloat {
        guard inset > 0, inset < radius else { return 0 }
        let dx = radius - inset
        return radius - (radius * radius - dx * dx).squareRoot()
    }
}

// MARK: - The measurement channel

/// The row's own title line box, published out of the row's content so the
/// overlay on the row's wash box can take its height.
///
/// **A preference and not `onGeometryChange` on purpose.** The measured value
/// has to travel from inside the button's label to a modifier applied outside
/// its `ButtonStyle`, and the two row shapes have nowhere in common to keep
/// it: the session row is a `struct` that could hold `@State`, but the shelf
/// builds its row inline inside `ArchivedShelf` and cannot. A preference read
/// back through `overlayPreferenceValue` needs no per-row state at all, and
/// so it is one shared piece rather than two.
private struct NoteMarkerTitleHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Mark the row's title. Its laid-out line box becomes the marker's
    /// height, so the marker follows Dynamic Type without knowing a font size.
    func noteMarkerTitle() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: NoteMarkerTitleHeight.self,
                                       value: proxy.size.height)
            }
        )
    }

    /// The resting marker, on the row's wash box. Apply it AFTER the row's
    /// `.buttonStyle(PressWashButtonStyle())`, so the marker paints over the
    /// press wash rather than under it.
    ///
    /// **The overlay contributes no layout**, so a row with no note is not
    /// merely similar to today's row — it is identical.
    ///
    /// **The marker paints at full strength.** The archived shelf dims its
    /// own content to 55%; at 55% the marker measures 2.51:1 and no tone fixes
    /// it. The dim exists to quiet the row's CONTENT, and 3pt of ink is not
    /// content and cannot shout. The marker sits outside the dimmed views, so
    /// full strength is what it gets.
    ///
    /// **The marker announces nothing.** It is 3pt of colour carrying a Colour
    /// Slot, and a colour is not a label; the row's value (`noteValue`) is
    /// what speaks.
    func noteMarker(_ note: ChatNote?) -> some View {
        overlayPreferenceValue(NoteMarkerTitleHeight.self) { titleLine in
            GeometryReader { proxy in
                if let note {
                    Capsule()
                        .fill(NoteSlot.color(for: note.color))
                        .frame(
                            width: NoteMarker.width,
                            height: NoteMarker.height(titleLine: titleLine,
                                                      rowHeight: proxy.size.height)
                        )
                        .position(x: NoteMarker.leadingInset + NoteMarker.width / 2,
                                  y: proxy.size.height / 2)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// What a noted row says aloud (§8), on both row shapes.
    ///
    /// **A value, not a rebuilt label.** VoiceOver reads the label and then
    /// the value, so the note lands at the end of the row's existing
    /// announcement and nothing already there moves.
    ///
    /// **The prefix is "Note, ".** Without it a note that opens with a noun is
    /// indistinguishable from a fifth column of the row.
    ///
    /// **No length cap.** The Note Card clamps because it has a screen to fit
    /// into; speech has no such bound, and a user scanning a list swipes past.
    func noteValue(_ note: ChatNote?) -> some View {
        // An empty value is no value: VoiceOver skips it. Written as one
        // unconditional modifier rather than an `if let`, so adding or
        // clearing a note never re-identifies the row's subtree.
        accessibilityValue(Text(verbatim: noteSpokenValue(note) ?? ""))
    }
}

/// The row's spoken value, or `nil` when the row carries no note. Split out
/// so §9 can assert the string itself rather than an accessibility tree.
func noteSpokenValue(_ note: ChatNote?) -> String? {
    note.map { "Note, " + $0.text }
}
