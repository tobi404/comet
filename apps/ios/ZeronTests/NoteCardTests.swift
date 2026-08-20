// The Note Card and the long press (spec §5 and §6; tests 20-28 and 37).
//
// **What is measured here and what was measured on a device.** Four of these
// nine tests are guards on a system surface no renderer can produce: an
// `ImageRenderer` cannot hold a press, so the preview platter, its mask and
// the menu's dim are not on screen in any raster this file makes. Each guard
// is therefore split, and the split is named in place:
//
// - the half that is arithmetic or is the card's own paint is asserted here;
// - the half that needs the platter was measured on an iPhone 17 Pro
//   simulator during the effort that produced §5, and its numbers are quoted
//   in the test that carries them.
//
// The half that is here is the half that a future change can break silently.
// The platter's own behaviour is the system's and does not drift with this
// code; the constant that tracks it (`NoteCardMetrics.veil`) does, and that
// one is asserted.

import SwiftUI
import XCTest

@testable import Zeron

// MARK: - Fixtures

/// The card's own page colour, and the colour the veil is derived from.
private var page: [Double] { srgb(Theme.surface) }
private var veil: [Double] { srgb(NoteCardMetrics.veil) }

private let slot = "sky"
private let location = "zeron @ MacBook Pro"

/// The shortest card this build can make: one word, one line.
private let oneWord = "Ship"

/// Three lines at the default text size. §5's reproducer for the clip, and
/// for test 23 — one and two lines pass either way.
private let threeLines =
    "Ask Dana before this merges, and check the gamut clamp on the shelf "
    + "markers while you are in there — the sky slot was the one that moved."

/// The demo dataset's own over-cap fixture (779 characters) and its
/// unbreakable URL (one 118-character token). They are seeded notes, so they
/// are on screen on every launch rather than being a test someone remembers
/// to run.
@MainActor private var overCapNote: String { demoNote(chatId: "chat-tabs") }
@MainActor private var urlNote: String { demoNote(chatId: "chat-oklch") }

@MainActor private func demoNote(chatId: String) -> String {
    let chats = DemoDataset.standard().chats
    guard let note = chats.first(where: { $0.id == chatId })?.note else {
        preconditionFailure("demo fixture \(chatId) has lost its note")
    }
    return note.text
}

private func note(_ text: String) -> ChatNote { ChatNote(text: text, color: slot) }

private func chat(note: ChatNote?) -> Chat {
    Chat(
        id: "c1", deviceId: "d1", title: "Streaming veil on transcript rows",
        archived: false, cwd: "/Users/x/zeron", branch: "veil-fade", checkoutId: nil,
        config: nil, lastMessagePreview: nil, lastMessageAt: nowMs() - 90_000,
        createdAt: nowMs() - 900_000, spaceId: nil, lastSeenAt: nowMs(), note: note
    )
}

@MainActor private func demoModel() -> AppModel {
    let model = AppModel()
    model.demo = DemoDataset.standard()
    model.phase = .ready
    return model
}

/// The four content sizes §5 tabulates, and the line count each has to
/// resolve to.
private let clampTable: [(DynamicTypeSize, UIContentSizeCategory, Int)] = [
    (.large, .large, 10),
    (.xxxLarge, .extraExtraExtraLarge, 7),
    (.accessibility2, .accessibilityLarge, 5),
    (.accessibility5, .accessibilityExtraExtraExtraLarge, 3),
]

/// Every category the card can be asked for, so a guard that says "at each
/// content size category" means it.
private let everyCategory: [(DynamicTypeSize, UIContentSizeCategory)] = [
    (.xSmall, .extraSmall), (.small, .small), (.medium, .medium), (.large, .large),
    (.xLarge, .extraLarge), (.xxLarge, .extraExtraLarge), (.xxxLarge, .extraExtraExtraLarge),
    (.accessibility1, .accessibilityMedium), (.accessibility2, .accessibilityLarge),
    (.accessibility3, .accessibilityExtraLarge),
    (.accessibility4, .accessibilityExtraExtraLarge),
    (.accessibility5, .accessibilityExtraExtraExtraLarge),
]

@MainActor
private func card(_ text: String, size: DynamicTypeSize = .large,
                  category: UIContentSizeCategory = .large) -> some View {
    NoteCard(
        note: note(text),
        location: location,
        layout: NoteCardMetrics.layout(note: text, location: location, category: category)
    )
    .environment(\.dynamicTypeSize, size)
    .environment(\.colorScheme, .dark)
}

@MainActor
private func veiled(_ text: String, size: DynamicTypeSize = .large,
                     category: UIContentSizeCategory = .large) -> some View {
    VeiledNoteCard(
        note: note(text),
        location: location,
        layout: NoteCardMetrics.layout(note: text, location: location, category: category)
    )
    .environment(\.dynamicTypeSize, size)
    .environment(\.colorScheme, .dark)
}

// MARK: - The clamp, and the height it is (§5, §8)

@MainActor
final class NoteCardClampTests: XCTestCase {
    /// The clamp falls 10 / 7 / 5 / 3 across L, XXXL, AX-L and AX-XXXL.
    ///
    /// **The clamp is a height, not a line count.** The four numbers are what
    /// `clampLines` lines at the DEFAULT size divide into at each size; they
    /// are checkpoints the arithmetic passes through, not a table it reads.
    func testTheClampFallsAcrossTheFourTabulatedSizes() {
        for (_, category, expected) in clampTable {
            XCTAssertEqual(NoteCardMetrics.maxLines(category: category), expected,
                           "clamp at \(category.rawValue)")
        }
    }

    /// And it never rises, at any size in between: a user sitting on XL or
    /// AX-3 gets a card that fits too.
    func testTheClampNeverRisesAsTheTextGrows() {
        var previous = Int.max
        for (_, category) in everyCategory {
            let lines = NoteCardMetrics.maxLines(category: category)
            XCTAssertLessThanOrEqual(lines, previous, "clamp rose at \(category.rawValue)")
            XCTAssertGreaterThanOrEqual(lines, 1)
            previous = lines
        }
    }

    /// **The tempting fix, refused on the frame.** Measuring with the scaled
    /// font and keeping ten lines makes the card honest about its content and
    /// pushes "Clear note" off the bottom of the screen at AX-XXXL. The
    /// budget the clamp keeps is real and this pins it: ten scaled lines at
    /// AX-XXXL is more than three times the clamp's own height.
    func testKeepingTenLinesAtTheLargestSizeBlowsTheHeightBudget() {
        let ax = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        let scaledLine = NoteCardMetrics.scaledFont(NoteCardMetrics.noteSize, category: ax)
            .lineHeight
        let honest = CGFloat(NoteCardMetrics.clampLines) * scaledLine
        XCTAssertGreaterThan(honest, 2.5 * NoteCardMetrics.clampHeight)
        // What the card actually spends there instead.
        let clamped = CGFloat(NoteCardMetrics.maxLines(category: ax)) * scaledLine
        XCTAssertLessThanOrEqual(clamped, NoteCardMetrics.clampHeight)
    }

    /// 21. The over-cap fixture renders to the clamp and elides, and does not
    /// scroll. The note is 779 characters — far past the clamp at every size —
    /// so the card's height is the clamp's height and not the note's.
    func testTheOverCapFixtureRendersToTheClampAndNotToItsContent() {
        let text = overCapNote
        for (_, category) in everyCategory {
            let font = NoteCardMetrics.scaledFont(NoteCardMetrics.noteSize, category: category)
            let allowed = NoteCardMetrics.maxLines(category: category)
            let wanted = NoteCardMetrics.lineCount(text, font: font,
                                                   width: NoteCardMetrics.maxTextWidth)
            XCTAssertGreaterThan(wanted, allowed, "at \(category.rawValue)")

            // The height stops at the clamp: the surplus lines are elided,
            // not scrolled and not drawn.
            let layout = NoteCardMetrics.layout(note: text, location: location,
                                                category: category)
            XCTAssertEqual(layout.lines, allowed, "at \(category.rawValue)")
            let size = layout.cardSize
            let atClamp = 2 * NoteCardMetrics.vPadding
                + (CGFloat(allowed) * font.lineHeight).rounded(.up)
                + NoteCardMetrics.lineGap
                + NoteCardMetrics.scaledFont(NoteCardMetrics.locationSize,
                                             category: category).lineHeight.rounded(.up)
            XCTAssertEqual(size.height, atClamp, accuracy: 0.001, "at \(category.rawValue)")
            // And it fills the cap, so the clamp is the only thing bounding it.
            XCTAssertEqual(size.width, NoteCardMetrics.maxCardWidth, accuracy: 0.001)
        }
    }
}

// MARK: - The rendered card (§5)

@MainActor
final class NoteCardRenderTests: XCTestCase {
    /// 23. **Guard: the card's forced height equals its measured content
    /// height, at each content size category.**
    ///
    /// It guards both failures at once — too small clips the note, too large
    /// draws empty container under it. The reproducer is a three-line note,
    /// because one and two lines pass either way.
    ///
    /// **This is the test that catches the unscaled font.** A height measured
    /// with `Theme.sansUI` and painted with `Theme.sans` passes at L and fails
    /// at everything above it, with nothing else warning.
    func testTheForcedHeightEqualsTheMeasuredContentHeightAtEverySize() {
        for text in [oneWord, threeLines, overCapNote] {
            for (size, category) in everyCategory {
                let layout = NoteCardMetrics.layout(note: text, location: location,
                                                    category: category)
                let content = NoteCardContent(note: note(text), location: location,
                                              layout: layout)
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.colorScheme, .dark)

                let measured = raster(content).size
                XCTAssertEqual(layout.cardSize.height, measured.height, accuracy: 1.0,
                               "\(category.rawValue), \(text.prefix(12))…")
                XCTAssertEqual(layout.cardSize.width, measured.width, accuracy: 1.0,
                               "\(category.rawValue), \(text.prefix(12))…")
            }
        }
    }

    /// **Guard: the note draws every line the height paid for.**
    ///
    /// This is the guard on the defect the device found and the renderer did
    /// not. A card that forces only its OUTER height leaves the note whatever
    /// the location line did not take, and that leftover is exactly `N` line
    /// boxes with no slack; sub-point rounding in the host takes one away. On
    /// the device the 779-character note drew nine lines inside a ten-line
    /// card and the URL drew two inside a three-line one, and in both the
    /// missing line's worth rendered as empty container under the note.
    ///
    /// So this counts the lines of ink rather than measuring a box: the
    /// rendered note has to have `layout.lines` of them.
    func testTheNoteDrawsEveryLineTheHeightPaidFor() {
        for text in [oneWord, threeLines, overCapNote, urlNote] {
            for (size, category) in [everyCategory[3], everyCategory[6], everyCategory[11]] {
                let layout = NoteCardMetrics.layout(note: text, location: location,
                                                    category: category)
                let r = raster(card(text, size: size, category: category))
                // The note's own band, inside the padding and above the gap.
                let noteBox = CGRect(x: NoteCardMetrics.hPadding,
                                     y: NoteCardMetrics.vPadding,
                                     width: layout.textWidth,
                                     height: layout.noteHeight)
                let bands = r.inkBands(in: noteBox, minLuma: 0.35)
                XCTAssertEqual(bands.count, layout.lines,
                               "\(category.rawValue), \(text.prefix(12))…")
            }
        }
    }

    /// **Guard: the `lineLimit` agrees with the height.**
    ///
    /// §5: "the elide lands at line ten while the mask cuts at line three, and
    /// the ellipsis never appears - which is exactly the original defect, and
    /// is why this is two changes and not one."
    ///
    /// The layout carries ONE line count and the card spends it twice, so the
    /// two cannot drift. This pins that: the height is exactly `lines` line
    /// boxes at the size the card paints at, at every content size and on both
    /// a note under the clamp and one far over it.
    func testTheLineLimitAndTheHeightAreTheSameNumber() {
        for text in [oneWord, threeLines, overCapNote, urlNote] {
            for (_, category) in everyCategory {
                let layout = NoteCardMetrics.layout(note: text, location: location,
                                                    category: category)
                let line = NoteCardMetrics.scaledFont(NoteCardMetrics.noteSize,
                                                      category: category).lineHeight
                XCTAssertEqual(layout.noteHeight, (CGFloat(layout.lines) * line).rounded(.up),
                               accuracy: 0.001, "\(category.rawValue), \(text.prefix(12))…")
                XCTAssertLessThanOrEqual(layout.lines,
                                         NoteCardMetrics.maxLines(category: category))
                XCTAssertGreaterThanOrEqual(layout.lines, 1)
            }
        }
    }

    /// 24. **Guard: the forced height is the card's height, not the
    /// preview's.** The preview is `card + 2 x 14` in both axes. A rule that
    /// starts measuring the padded box silently re-opens the clip.
    func testTheForcedHeightIsTheCardsAndNotThePreviews() {
        for text in [oneWord, threeLines, overCapNote] {
            let forced = NoteCardMetrics.layout(note: text, location: location,
                                                category: .large).cardSize
            let card = raster(card(text)).size
            let preview = raster(veiled(text)).size

            XCTAssertEqual(card.height, forced.height, accuracy: 0.7)
            XCTAssertEqual(preview.height, forced.height + 2 * NoteCardMetrics.veilInset,
                           accuracy: 0.7)
            XCTAssertEqual(preview.width, card.width + 2 * NoteCardMetrics.veilInset,
                           accuracy: 0.7)
        }
    }

    /// 22. The unbreakable-URL fixture does not widen the card: one
    /// 118-character token with no space in it wraps at character boundaries
    /// inside the 300pt cap.
    ///
    /// This is the opposite of the desktop's problem — the desktop's card had
    /// to be told to clip, and SwiftUI breaks the token for free.
    func testTheUnbreakableURLDoesNotWidenTheCard() {
        for (size, category) in everyCategory {
            let width = raster(card(urlNote, size: size, category: category)).size.width
            XCTAssertLessThanOrEqual(width, NoteCardMetrics.maxCardWidth + 0.5,
                                     "at \(category.rawValue)")
        }
    }

    /// The card sizes to its content and never to the screen: a five-word note
    /// is a five-word card, and only a note that fills the cap reaches 324pt.
    func testTheCardSizesToItsContentUpToTheCap() {
        XCTAssertLessThan(raster(card(oneWord)).size.width, NoteCardMetrics.maxCardWidth)
        XCTAssertEqual(raster(card(threeLines)).size.width, NoteCardMetrics.maxCardWidth,
                       accuracy: 0.7)

        // And the two heights §5's corner table measured, which is what pins
        // `lineGap`: the shortest card this build can make is 57pt tall, and
        // a three-line note is 91pt.
        XCTAssertEqual(raster(card(oneWord)).size.height, 57, accuracy: 1.0)
        XCTAssertEqual(raster(card(threeLines)).size.height, 91, accuracy: 1.0)
    }

    /// 28. The card carries the location line, so a note read at full length
    /// still says where its session runs.
    ///
    /// The preview REPLACES the row for the length of the press, so the row's
    /// own `space @ device` line is not on screen while the note is being
    /// read. This asserts both halves: the height budgets a second line, and
    /// there is ink in it.
    func testTheCardCarriesTheLocationLine() {
        let withLocation = NoteCardMetrics.layout(note: threeLines, location: location,
                                                  category: .large).cardSize.height
        let locationLine = NoteCardMetrics.scaledFont(NoteCardMetrics.locationSize,
                                                      category: .large).lineHeight
        // Three note lines plus the padding, and then the second line's own
        // box and the gap above it.
        let noteLine = NoteCardMetrics.scaledFont(NoteCardMetrics.noteSize, category: .large)
            .lineHeight
        XCTAssertEqual(withLocation,
                       2 * NoteCardMetrics.vPadding + (3 * noteLine).rounded(.up)
                           + NoteCardMetrics.lineGap + locationLine.rounded(.up),
                       accuracy: 0.001)

        // And the band that line occupies is not empty. Sampled inside the
        // card's own padding, against the tinted base it paints on.
        let r = raster(card(threeLines))
        let base = r.at(x: NoteCardMetrics.maxCardWidth - 4, y: withLocation - 4)
        let band = CGRect(x: NoteCardMetrics.hPadding,
                          y: withLocation - NoteCardMetrics.vPadding - locationLine,
                          width: NoteCardMetrics.maxTextWidth,
                          height: locationLine)
        XCTAssertTrue(r.hasInk(in: band, background: base))
    }

    /// 25. **Guard: the card's rendered corner is the card's corner.** The
    /// measured arc is the same on the shortest note and the longest, on both
    /// row shapes, and at every text size. Under the defect it moved with the
    /// card, which is what made a short note a pill.
    ///
    /// **The half that is here.** The card's own corner, measured off the
    /// preview raster: how far the arc runs across the top edge and down the
    /// leading edge, from the card's own boundary inside the veil. A radius is
    /// a constant, so these do not move with the card's height — that is the
    /// whole claim the defect broke.
    ///
    /// **The half measured on device.** With the veil in place the platter's
    /// arc cuts flat colour instead of the card, and the corner a user sees is
    /// this one: 10.3 across, 8.3 down, ovalness 0.18, identical on every
    /// fixture and both row shapes. Without it the platter's own arc grew with
    /// the card — 24.3 across at 119 x 57pt (ovalness 0.79) up to 36.7 at
    /// 324 x 91pt, and a full pill at 1.06 on the 36pt shelf row. Confirmed
    /// again on a held press here: the 92pt card the 36pt shelf row opens
    /// carries the same rectangle corner as the 210pt card, not a pill.
    func testTheCardsCornerDoesNotMoveWithTheCard() {
        var arcs: [(CGFloat, CGFloat)] = []
        for text in [oneWord, threeLines, overCapNote] {
            for (size, category) in [everyCategory[3], everyCategory[6], everyCategory[11]] {
                let r = raster(veiled(text, size: size, category: category))
                let inset = NoteCardMetrics.veilInset
                // Along the card's first row, and down its first column: the
                // corner is where the card's fill has not started yet.
                let across = (r.firstDifferingX(atY: inset + 0.5, from: inset,
                                                background: veil) ?? inset) - inset
                let down = (r.firstDifferingY(atX: inset + 0.5, from: inset,
                                              background: veil) ?? inset) - inset
                arcs.append((across, down))

                // And it is a corner rather than an end cap: the arc is a
                // fraction of the card, not half of it. Under the defect the
                // shortest card measured 0.79 here and the shelf's 1.06.
                let height = r.size.height - 2 * inset
                XCTAssertLessThan(down / (height / 2), 0.5,
                                  "\(category.rawValue), \(text.prefix(12))…")
            }
        }
        // Identical everywhere. The radius is a constant; the arc it cuts has
        // to be one too.
        for arc in arcs {
            XCTAssertEqual(arc.0, arcs[0].0, accuracy: 0.7)
            XCTAssertEqual(arc.1, arcs[0].1, accuracy: 0.7)
        }
    }

    /// The veil's margin is opaque, and it is the page colour under the dim
    /// rather than the page colour. A transparent inset exposes the platter's
    /// own tray — a second surface under the card.
    func testTheVeilPaintsTheMarginOpaque() {
        let r = raster(veiled(threeLines))
        for point in [CGPoint(x: 2, y: 2),
                      CGPoint(x: r.size.width - 2, y: 2),
                      CGPoint(x: 2, y: r.size.height - 2),
                      CGPoint(x: r.size.width - 2, y: r.size.height - 2)] {
            let sampled = r.at(x: point.x, y: point.y)
            for (a, b) in zip(sampled, veil) {
                XCTAssertEqual(a * 255, b * 255, accuracy: 1.0, "veil at \(point)")
            }
        }
    }
}

// MARK: - The veil's constant (§5, §10 limit 9)

final class NoteCardVeilTests: XCTestCase {
    /// 26. **Guard: the veil equals the page under the dim.** One pixel inside
    /// the margin and one on the page beside it, in the same held-press frame,
    /// must not differ by more than 2 per channel.
    ///
    /// **The half that is here** is the arithmetic the constant comes from:
    /// the dim is linear, `pressed = 0.7917 x rest + (4.7, 4.7, 8.7)`, solved
    /// from 27 sample pairs across the tonal range. The page behind the list
    /// is `Theme.surface` `#0d0d0d` and goes to `#0F0F13`.
    ///
    /// **The half measured on device**: the veil and the page beside it stayed
    /// within 2/255 on every frame of a 30fps capture of the open, including
    /// the frames where the card is still translucent. Re-measured on a held
    /// press while building this ticket — veil `(15, 15, 19)`, page beside it
    /// `(14, 14, 18)`, one unit apart, which is the platter's own shadow and
    /// is the residual §5 names. An `ImageRenderer` cannot hold a press, so
    /// that half cannot live here.
    func testTheVeilIsThePageColourAsTheDimLeavesIt() {
        let derived = units(NoteCardMetrics.underMenuDim(Theme.surface))
        XCTAssertEqual(derived, [15, 15, 19])

        let shipped = units(NoteCardMetrics.veil)
        for (a, b) in zip(shipped, derived) {
            XCTAssertLessThanOrEqual(abs(a - b), 2)
        }
    }

    /// The correction §5 carries, kept as a test so it is not re-introduced.
    /// The prototype recorded this constant as "`Theme.bg`". `Theme.bg` is
    /// `#060606` and gives `#09090E` — a margin four units darker than the
    /// page, which is a visible pop.
    func testTheVeilIsNotDerivedFromThemeBg() {
        let wrong = units(NoteCardMetrics.underMenuDim(Theme.bg))
        XCTAssertEqual(wrong, [9, 9, 13])
        // And it would fail test 26 on its own tolerance, which is what
        // "a visible pop" means as a number.
        XCTAssertTrue(zip(wrong, units(NoteCardMetrics.veil)).contains { abs($0 - $1) > 2 })
    }

    /// 14pt is a measurement, not a taste: a corner of radius `r` cuts a
    /// square corner to a depth of about `0.3r`, and the largest platter arc
    /// measured is 44pt across, so under 14pt of margin the arc never reaches
    /// the card.
    func testTheVeilInsetClearsTheLargestPlatterArc() {
        let largestArcMeasured: CGFloat = 44
        let depth = largestArcMeasured * (1 - 1 / 2.0.squareRoot())
        XCTAssertGreaterThan(NoteCardMetrics.veilInset, depth)
    }
}

// MARK: - The gesture, on both row shapes (§5, §6)

@MainActor
final class NoteCardRowTests: XCTestCase {
    private func sessionRow(note: ChatNote?, model: AppModel) -> some View {
        ChatRow(chat: chat(note: note), showLocation: true) {}
            .environment(model)
    }

    private func shelfRow(note: ChatNote?, model: AppModel) -> some View {
        ArchivedChatRow(chat: chat(note: note), location: location) {}
            .environment(model)
    }

    @MainActor
    private func inList<V: View>(_ row: V) -> some View {
        row
            .padding(.horizontal, ChatRow.listInsets.leading)
            .frame(width: screenWidth)
            .background(Theme.surface)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .dark)
    }

    /// 20. A row with a note renders at the same height as the same row
    /// without one — 61.7pt on the session row, 36pt on the shelf.
    ///
    /// The long press costs no layout. `.contextMenu` is attached to every row
    /// of both shapes now, so if it contributed any the whole list would move.
    func testANotedRowIsTheSameHeightAsABareRow() {
        let model = demoModel()
        let noted = note("Ask Dana before this merges")

        let session = (raster(inList(sessionRow(note: noted, model: model))).size.height,
                       raster(inList(sessionRow(note: nil, model: model))).size.height)
        XCTAssertEqual(session.0, session.1, accuracy: 0.4)
        XCTAssertEqual(session.0, 61.7, accuracy: 0.7)

        let shelf = (raster(inList(shelfRow(note: noted, model: model))).size.height,
                     raster(inList(shelfRow(note: nil, model: model))).size.height)
        XCTAssertEqual(shelf.0, shelf.1, accuracy: 0.4)
        XCTAssertEqual(shelf.0, 36.0, accuracy: 0.4)
    }

    /// 27. The shelf row and the session row open the same card from the same
    /// gesture. A change to one that does not reach the other is a regression.
    ///
    /// **One mechanism, so one card.** Both row shapes go through
    /// `chatNoteMenu`, and neither the card nor its height rule takes a
    /// parameter that could tell them which shape asked — an archived chat and
    /// an active one with the same note render pixel-identically. The 36pt
    /// shelf row has no degrade because it has nothing of its own to degrade.
    func testBothRowShapesOpenTheSameCard() {
        var archived = chat(note: note(threeLines))
        archived.archived = true
        let active = chat(note: note(threeLines))

        let cards = [active, archived].map { c -> Raster in
            let layout = NoteCardMetrics.layout(note: c.note!.text, location: location,
                                                category: .large)
            return raster(
                VeiledNoteCard(note: c.note!, location: location, layout: layout)
                    .environment(\.dynamicTypeSize, .large)
                    .environment(\.colorScheme, .dark)
            )
        }
        XCTAssertEqual(cards[0].size, cards[1].size)
        XCTAssertEqual(cards[0].pixels, cards[1].pixels)
    }

    /// 37. A long press and a trailing swipe both still work on both row
    /// shapes. One gesture added must not cost the one that was there.
    ///
    /// **The half that is here.** Two things a change could break silently.
    /// The swipe's hit region is the row's rendered box, so the box has to be
    /// the one ticket 03 measured — that is test 20 above, and it holds with
    /// the press attached to every row. And the menu's Archive has to be the
    /// swipe's own act rather than a second one that drifts from it: both go
    /// through `AppModel.archive` / `unarchive`, and this drives that pair
    /// end to end on both sections.
    ///
    /// **The half measured on device**: all four combinations were driven and
    /// all four fired. A held press opens the card on the noted session row
    /// and on the 36pt shelf row; a trailing drag on the same two rows still
    /// reveals Archive and Unarchive. iOS tells a long press and a horizontal
    /// drag apart, and `HomeView`'s Archive and `ArchivedShelf`'s Unarchive
    /// are untouched by this build.
    func testTheMenusArchiveIsTheSwipesOwnAct() {
        let model = demoModel()
        let id = model.overviewChats.first!.id

        model.archive(chatId: id)
        XCTAssertTrue(model.archivedChats().contains { $0.id == id })
        XCTAssertFalse(model.overviewChats.contains { $0.id == id })

        model.unarchive(chatId: id)
        XCTAssertFalse(model.archivedChats().contains { $0.id == id })
        XCTAssertTrue(model.overviewChats.contains { $0.id == id })
    }

    /// The menu's "Clear note" clears and does not ask. A note is cleared,
    /// never deleted: the value goes and the Chat is untouched.
    func testTheMenusClearNoteClearsTheNoteAndNothingElse() {
        let model = demoModel()
        let before = model.overviewChats.first { $0.note != nil }!

        model.clearChatNote(chatId: before.id)

        let after = model.overviewChats.first { $0.id == before.id }!
        XCTAssertNil(after.note)
        XCTAssertEqual(after.displayTitle, before.displayTitle)
        XCTAssertEqual(after.archived, before.archived)
    }
}
