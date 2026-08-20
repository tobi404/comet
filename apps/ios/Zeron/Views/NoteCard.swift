// The Note Card and the long-press menu — spec §5 and §6.
//
// A long press on a row opens `.contextMenu(menuItems:preview:)`. On a noted
// row the card lifts in the row's place; on a bare row no `preview:` closure
// is passed at all, so the system lifts the row itself.
//
// Three mechanisms here are counter-intuitive, and each one was settled by
// building the alternatives. They are documented where they are implemented,
// but in one sentence each:
//
// 1. **A `.contextMenu` preview does not adopt its content's height.** It lays
//    the content out correctly and then MASKS it, so a card taller than about
//    two lines is cut mid-sentence. `.fixedSize` does not help and neither
//    does moving the attachment point. Only an explicit `.frame(height:)`
//    fixes it — so the height is computed BEFORE the press, per chat, at the
//    card's width.
// 2. **The height takes the content size category as an input.** Measuring
//    with a raw `UIFont` while painting with a scaled one gives a
//    default-size height whatever the user's text size is, and nothing warns.
// 3. **The corner is a mechanism, not a number.** The system's preview
//    platter masks the card with a corner of its own, so the card steps 14pt
//    inside the preview and fills that margin opaque in the page's colour as
//    the system's dim leaves it.

import SwiftUI

// MARK: - The numbers, and the rules built from them

/// Every measured number the Note Card is built from (§5), and the two rules
/// that are arithmetic rather than constants: the falling line clamp and the
/// card's forced height.
///
/// A pure enum with no view in it, because §9's tests 23-26 assert the rules
/// at content size categories no renderer can be asked for one at a time.
enum NoteCardMetrics {
    /// The widest the text runs. Swept at 240, 280, 300 and 340pt of text on
    /// the same note: 240 turns a three-line note into four for no gain, 280
    /// is the close runner-up, 340 reads as a banner across the list.
    static let maxTextWidth: CGFloat = 300
    static let hPadding: CGFloat = 12
    static let vPadding: CGFloat = 10

    /// The card at its widest. It sizes to its content — a five-word note is
    /// a five-word card — so this is a cap and not a width.
    static let maxCardWidth: CGFloat = maxTextWidth + 2 * hPadding  // 324

    /// 12pt, continuous. Swept at 8, 12, 16 and 20 on the three-line card:
    /// 8 stops registering as a corner at the small card sizes, and 20 starts
    /// going round again on the shortest notes.
    static let corner: CGFloat = 12

    /// The veil's margin, and it is a measurement rather than a taste.
    ///
    /// A corner of radius `r` cuts a square corner to a depth of
    /// `r(1 − 1/√2)`, about `0.3r`. The largest platter arc measured is 44pt
    /// across, so under 14pt of margin the arc never reaches the card — at the
    /// largest card this build can make, at AX-XXXL.
    static let veilInset: CGFloat = 14

    static let noteSize: CGFloat = 13
    static let locationSize: CGFloat = 11

    /// Between the note and the `space @ device` line. Derived from the
    /// three-line card the prototype measured at 324 x 91pt: 91 less 2 x 10 of
    /// padding, less three note lines and one location line, leaves this.
    static let lineGap: CGFloat = 6

    /// The note's Colour Slot across the card, and the same slot in the
    /// hairline. Carried from the desktop unchanged; §10 limit 15 names them
    /// as the one pair in §5 that rests on the eye alone.
    static let tintOpacity: Double = 0.10
    static let hairlineOpacity: Double = 0.32
    static let hairlineWidth: CGFloat = 1

    /// The `space @ device` line, muted.
    static let locationOpacity: Double = 0.7

    /// The clamp, stated the only way it is true: **N lines at the DEFAULT
    /// text size**. The line count falls out of that height as the text grows;
    /// it is not a per-size table (§8's one rule).
    static let clampLines = 10

    // MARK: The scaled mirror

    /// The measuring mirror of `Theme.sans`, which is what the card paints
    /// with.
    ///
    /// **The defect this exists to prevent.** `Theme.sansUI` is a raw
    /// `UIFont` and does not scale. Measure with one while painting with the
    /// other and the forced height is a default-size height whatever the
    /// user's text size is: the card clips at every size above XXXL, a short
    /// note is cut mid-glyph at AX-L, and at AX-XXXL a three-line note renders
    /// its first three words and stops with no ellipsis at all.
    ///
    /// The category is a PARAMETER and never read from the process, so a test
    /// can ask for a size the simulator is not set to.
    static func scaledFont(_ size: CGFloat, category: UIContentSizeCategory) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: Theme.sansUI(size),
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        )
    }

    /// The clamp as the `Text` has to receive it.
    ///
    /// **`lineLimit` has to agree with the forced height**, or the elide lands
    /// at line ten while the mask cuts at line three and the ellipsis never
    /// appears. That is why the clamp is two changes and not one.
    ///
    /// The four numbers §5 tabulates — 10 at L, 7 at XXXL, 5 at AX-L, 3 at
    /// AX-XXXL — are checkpoints this arithmetic passes through, not the
    /// arithmetic itself. Users sit on the sizes between them too.
    static func maxLines(category: UIContentSizeCategory) -> Int {
        let clamp = clampHeight
        let line = scaledFont(noteSize, category: category).lineHeight
        guard line > 0 else { return clampLines }
        // A hair of slack, so a size whose line height divides the clamp
        // exactly is not pushed a line down by float error.
        return max(1, Int(((clamp + 0.01) / line).rounded(.down)))
    }

    /// What `clampLines` lines occupy at the default text size. The one height
    /// the clamp is.
    static var clampHeight: CGFloat {
        CGFloat(clampLines) * scaledFont(noteSize, category: .large).lineHeight
    }

    /// The card's own height, computed before the press.
    ///
    /// **This is the card's height and not the preview's.** The preview is
    /// `card + 2 * veilInset` in both axes; the card is not. A rule that
    /// starts measuring the padded box silently re-opens the clip (test 24).
    ///
    /// **Named as a cost, not hidden**: if this overshoots the content, the
    /// surplus draws as empty container under the card. Height and content
    /// have to agree, so a stale number is visible rather than silent.
    /// **Both axes, and both are computed rather than proposed.** A
    /// `.contextMenu` preview proposes no size at all, so a `maxWidth` frame
    /// hands the text an unbounded width, gets a one-line ideal back and then
    /// clips it — the note renders as a single truncated line and the height
    /// rule, which measured honestly, disagrees with it. The width is
    /// therefore measured the same way the height is and given to the card
    /// outright.
    ///
    /// **And each line block gets its own height, not the leftover.**
    /// A card that forces only its outer height leaves the note whatever the
    /// location line did not take, and that residue is exactly `N` line boxes
    /// with no slack at all. Sub-point rounding in the host then takes one
    /// line away: the note draws nine lines inside a ten-line card and the
    /// tenth line's worth of surplus renders as empty container. Seen on the
    /// device on both seeded fixtures — the 779-character note lost its tenth
    /// line and the URL its third — and invisible to a renderer, which rounds
    /// the other way. Giving each block its own frame removes the residue.
    static func layout(
        note: String,
        location: String,
        category: UIContentSizeCategory
    ) -> NoteCardLayout {
        let noteFont = scaledFont(noteSize, category: category)
        let locationFont = scaledFont(locationSize, category: category)
        let width = textWidth(note: note, noteFont: noteFont,
                              location: location, locationFont: locationFont)
        let lines = min(lineCount(note, font: noteFont, width: width),
                        maxLines(category: category))
        return NoteCardLayout(
            textWidth: width,
            lines: lines,
            // Rounded up, so a fractional line box can never round a line
            // away. The cost is at most a point of container.
            noteHeight: (CGFloat(lines) * noteFont.lineHeight).rounded(.up),
            locationHeight: locationFont.lineHeight.rounded(.up),
            maxLines: maxLines(category: category)
        )
    }

    /// The width the two lines run at: their own, up to the cap.
    ///
    /// **The card sizes to its content** — a five-word note is a five-word
    /// card — and an unbreakable token wraps at character boundaries inside
    /// the cap rather than widening it. That is the opposite of the desktop's
    /// problem: the desktop's card had to be told to clip, and the text system
    /// breaks the token for free.
    static func textWidth(note: String, noteFont: UIFont,
                          location: String, locationFont: UIFont) -> CGFloat {
        let ideal = max(idealWidth(note, font: noteFont),
                        idealWidth(location, font: locationFont))
        return min(maxTextWidth, ideal.rounded(.up))
    }

    private static func idealWidth(_ text: String, font: UIFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return bounds(text, font: font, width: .greatestFiniteMagnitude).width
    }

    /// How many lines the note wraps to at `width`, before the clamp.
    ///
    /// Rounded to whole line boxes on purpose: SwiftUI lays a `Text` out at
    /// exactly `lines * lineHeight`, so a measurement that carried a fraction
    /// would disagree with the thing it is measuring.
    ///
    /// **It may under-count by a line and never over-count.** This measures
    /// with character wrapping and `Text` breaks on words and on a URL's own
    /// punctuation, so `Text` can want a line more than this says — never a
    /// line fewer. Under-counting elides one line early; over-counting would
    /// draw empty container, which is the failure that shows.
    static func lineCount(_ text: String, font: UIFont, width: CGFloat) -> Int {
        guard !text.isEmpty, font.lineHeight > 0 else { return 1 }
        return max(1, Int((bounds(text, font: font, width: width).height
                            / font.lineHeight).rounded()))
    }

    /// **The bounding height is asked for over a large FINITE box.**
    /// `.greatestFiniteMagnitude` makes the text system return a height only a
    /// few lines tall whatever the string is, so a 779-character note measures
    /// as three lines and the card clips exactly the way the unscaled font
    /// clipped it. Neither one warns.
    private static func bounds(_ text: String, font: UIFont, width: CGFloat) -> CGRect {
        NSAttributedString(string: text, attributes: [.font: font]).boundingRect(
            with: CGSize(width: width, height: measuringBox),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
    }

    /// Taller and wider than any card this build can make, by orders of
    /// magnitude, and finite.
    private static let measuringBox: CGFloat = 100_000

    // MARK: The veil

    /// **The one constant this build introduces, and it tracks a system
    /// effect.**
    ///
    /// While a context menu is up, iOS dims everything EXCEPT the preview, so
    /// a colour authored inside the preview renders exactly as authored while
    /// the page beside it does not. The veil therefore cannot be the page
    /// colour; it has to be the page colour *as the dim leaves it*.
    ///
    /// The dim is linear, solved from 27 sample pairs across the tonal range:
    ///
    ///     pressed = 0.7917 * rest + (4.7, 4.7, 8.7)
    ///
    /// a dark blue-grey at about 21%. The page behind the list is
    /// `Theme.surface` `#0d0d0d`, which goes to `#0F0F13` — `(15, 15, 19)`.
    ///
    /// **Not `Theme.bg`.** `Theme.bg` is `#060606` and gives `#09090E`, a
    /// margin four units darker than the page, which is a visible pop.
    ///
    /// A future iOS that changes the dim makes this wrong. It is a
    /// re-measurement and not a redesign (§10, limit 9): shoot the same screen
    /// at rest and under a press, sample pairs across the tonal range, fit the
    /// line, re-derive. Test 26 fails first if it drifts.
    static let veil: Color = underMenuDim(Theme.surface)

    /// The dim's line, applied to one colour. Public so test 26 can assert the
    /// arithmetic rather than a hex.
    static func underMenuDim(_ color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func dim(_ channel: CGFloat, _ offset: Double) -> Double {
            let out = 0.7917 * Double(channel) * 255 + offset
            return (out.rounded() / 255).clamped()
        }
        return Color(red: dim(r, 4.7), green: dim(g, 4.7), blue: dim(b, 8.7))
    }
}

/// Every number the card needs, resolved before the press.
///
/// The card is handed this and measures nothing itself, so it cannot measure
/// with one font and paint with another (§5's second trap).
struct NoteCardLayout: Equatable {
    let textWidth: CGFloat
    /// What the note actually draws to, after the clamp.
    let lines: Int
    let noteHeight: CGFloat
    let locationHeight: CGFloat
    /// The clamp, as the `Text` receives it. It has to agree with
    /// `noteHeight`, or the elide lands at one line while the frame cuts at
    /// another and the ellipsis never appears.
    let maxLines: Int

    /// **The card's size, and not the preview's.** The preview is
    /// `card + 2 * veilInset` in both axes (test 24).
    var cardSize: CGSize {
        CGSize(
            width: textWidth + 2 * NoteCardMetrics.hPadding,
            height: noteHeight + NoteCardMetrics.lineGap + locationHeight
                + 2 * NoteCardMetrics.vPadding
        )
    }
}

private extension Double {
    func clamped() -> Double { Swift.min(1, Swift.max(0, self)) }
}

// MARK: - Content size category, from the environment's word for it

extension UIContentSizeCategory {
    /// SwiftUI's `DynamicTypeSize` in UIKit's vocabulary.
    ///
    /// Written out rather than bridged, because the card's height rule takes
    /// the category as an input and there is no public initializer that maps
    /// the two. Exhaustive, so a size the platform adds later fails to compile
    /// rather than silently measuring at the default.
    init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        @unknown default: self = .large
        }
    }
}

// MARK: - The card

/// The note in full, at the size the press will lift it to.
///
/// **The card carries the location line, and that is not a decoration.** A
/// `.contextMenu` preview REPLACES the row for the length of the press, so at
/// the exact moment a user is reading the note, the row's own `space @ device`
/// line is not on screen. The card restates it. The desktop's card floats
/// beside its row and never had this problem.
///
/// Adding the title as a third line was refused: it is redundant with the note
/// in almost every real case, and three registers in a card that exists to
/// show one sentence is a card that has stopped being a card.
struct NoteCard: View {
    let note: ChatNote
    let location: String
    /// Resolved by `NoteCardMetrics.layout` before the press.
    let layout: NoteCardLayout

    private var slot: Color { NoteSlot.color(for: note.color) }

    var body: some View {
        NoteCardContent(note: note, location: location, layout: layout)
            // Trap 1's fix, and the only one that works: an explicit frame.
            .frame(width: layout.cardSize.width, height: layout.cardSize.height,
                   alignment: .topLeading)
            .background {
                ZStack {
                    Theme.surface
                    slot.opacity(NoteCardMetrics.tintOpacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: NoteCardMetrics.corner,
                                        style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NoteCardMetrics.corner, style: .continuous)
                    .strokeBorder(slot.opacity(NoteCardMetrics.hairlineOpacity),
                                  lineWidth: NoteCardMetrics.hairlineWidth)
            }
    }
}

/// The card's two lines and its padding, at the height they actually want.
///
/// Split out so §9's test 23 can measure the content the forced height claims
/// to equal. It is the guard on both failures at once: a height too small
/// clips the note, and a height too large draws empty container under it.
struct NoteCardContent: View {
    let note: ChatNote
    let location: String
    /// Given and not proposed: a `.contextMenu` preview proposes nothing, and
    /// a block sized from what the other block left over loses a line to
    /// rounding.
    let layout: NoteCardLayout

    var body: some View {
        VStack(alignment: .leading, spacing: NoteCardMetrics.lineGap) {
            // The note. It elides at the clamp and never scrolls — a
            // `.contextMenu` preview is not interactive, so a scroll was never
            // a candidate.
            Text(note.text)
                .font(Theme.sans(NoteCardMetrics.noteSize))
                .foregroundStyle(Theme.text)
                .lineLimit(layout.maxLines)
                .truncationMode(.tail)
                .frame(width: layout.textWidth, height: layout.noteHeight,
                       alignment: .topLeading)
            // The row's own string, restated.
            Text(location)
                .font(Theme.sans(NoteCardMetrics.locationSize))
                .foregroundStyle(Theme.textMuted.opacity(NoteCardMetrics.locationOpacity))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: layout.textWidth, height: layout.locationHeight,
                       alignment: .topLeading)
        }
        .padding(.horizontal, NoteCardMetrics.hPadding)
        .padding(.vertical, NoteCardMetrics.vPadding)
    }
}

/// The card, inset inside the preview and veiled — the corner's whole
/// mechanism (§5, "The corner").
///
/// **A plain radius does nothing here.** The system's preview platter masks
/// the preview with a corner of its own, roughly half the card's height on a
/// short note, so the card's own 12pt is drawn and then masked over: every
/// short card renders as a stadium and the 36pt shelf row's card renders as a
/// full pill. Inset the card 14pt and the platter's arc cuts flat colour
/// instead, and the card's corner is the only corner on screen. Measured
/// after: 10.3 across, 8.3 down, and those numbers are identical on every
/// fixture, on both row shapes, and at every text size.
///
/// **The margin must be opaque.** A transparent inset exposes the platter's
/// own tray — a grey rounded surface the card then visibly sits on. Two
/// surfaces where the design has one.
///
/// **The veil goes OUTSIDE the forced height.** The preview is
/// `card + 2 * veilInset` in both axes; the card is not.
///
/// `.contentShape(.contextMenuPreview, _)` does not reach the platter. It was
/// built at three attachment points — on the row immediately before
/// `.contextMenu`, outermost over the forced height, and inside the forced
/// height directly on the card — and all three frames are pixel-identical to
/// the defect. Do not spend time on it.
struct NoteCardPreview: View {
    let note: ChatNote
    let location: String
    let layout: NoteCardLayout

    var body: some View {
        NoteCard(note: note, location: location, layout: layout)
            .padding(NoteCardMetrics.veilInset)
            .background(NoteCardMetrics.veil)
    }
}

// MARK: - The long press, on both row shapes

extension View {
    /// The long-press menu, and the Note Card under it. One shared piece,
    /// called from both row shapes — the 36pt shelf row opens the same card
    /// from the same gesture, so there is no degrade anywhere. A change to one
    /// that does not reach the other is a regression (test 27).
    ///
    /// **Apply it to the whole row**, so the system lifts everything the row
    /// draws when there is no note to preview.
    ///
    /// The trailing swipe is untouched: a long press and a horizontal drag are
    /// different gestures and iOS tells them apart (test 37).
    func chatNoteMenu(_ chat: Chat, location: String, archived: Bool) -> some View {
        modifier(ChatNoteMenu(chat: chat, location: location, archived: archived))
    }
}

private struct ChatNoteMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let chat: Chat
    let location: String
    let archived: Bool

    /// The card's numbers, resolved while the row is at rest. The press reads
    /// them; it does not compute them.
    private var category: UIContentSizeCategory { UIContentSizeCategory(dynamicTypeSize) }

    @ViewBuilder func body(content: Content) -> some View {
        if let note = chat.note {
            content.contextMenu {
                items(hasNote: true)
            } preview: {
                NoteCardPreview(
                    note: note,
                    location: location,
                    layout: NoteCardMetrics.layout(note: note.text,
                                                   location: location,
                                                   category: category)
                )
            }
        } else {
            // **No `preview:` closure at all**, and not one returning an empty
            // view — that would still register a custom preview. With none the
            // system lifts the row itself, which is the whole answer for a
            // bare row: a "No note on this session" card was built and refused
            // because it carries no information.
            content.contextMenu { items(hasNote: false) }
        }
    }

    @ViewBuilder private func items(hasNote: Bool) -> some View {
        // **Archive earns its place.** A menu holding one item under a
        // full-width card reads as an accident. Archive is what the row
        // already knows how to do and what the trailing swipe already does, so
        // the menu and the swipe say the same thing rather than two different
        // things — and this is the swipe's own call, animation included.
        Button {
            withAnimation(Motion.resort) {
                if archived { model.unarchive(chatId: chat.id) }
                else { model.archive(chatId: chat.id) }
            }
        } label: {
            archived
                ? Label("Unarchive", systemImage: "arrow.up.bin")
                : Label("Archive", systemImage: "archivebox")
        }

        // **Clear note lives in the menu only**, never in the sheet, and it
        // asks for no confirmation: clearing from the menu and saving blank
        // text produce the same stored result, so there is one act and not two.
        if hasNote {
            Button(role: .destructive) {
                model.clearChatNote(chatId: chat.id)
            } label: {
                Label("Clear note", systemImage: "trash")
            }
        }
    }
}
