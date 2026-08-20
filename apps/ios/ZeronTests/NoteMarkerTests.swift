// The resting marker on both row shapes (spec §4 and §8; tests 14-19).
//
// The rule under test is "as tall as the row's own title line, clamped to the
// row less 3pt at each end", so every height assertion here MEASURES a
// rendered row rather than reading a constant back. The two row shapes are
// rendered on their own — `List` is collection-view backed and no renderer
// can measure it — with the list's own `listRowInsets` leading applied by
// hand, which is what puts the marker's leading edge 14pt from the screen
// edge.

import SwiftUI
import XCTest

@testable import Zeron

// MARK: - Rendering a row

/// The pixel scale the rows render at. 3 is a real device's, and it is what
/// makes a sub-point measurement honest: one pixel is 1/3 of a point.
private let renderScale: CGFloat = 3

/// An iPhone 17 Pro's width in points. The marker's position does not depend
/// on it; the title's truncation does.
private let screenWidth: CGFloat = 402

/// The list's `listRowInsets` leading, read off the two production
/// constants rather than restated. The marker's inset composes with this one;
/// it does not stack on it.
@MainActor private let sessionListInset = ChatRow.listInsets.leading
@MainActor private let shelfListInset = ArchivedSection.rowInsets.leading

/// The centre of the marker's 3pt column, in points from the screen edge.
@MainActor private let markerCentreX =
    sessionListInset + NoteMarker.leadingInset + NoteMarker.width / 2

private struct Raster {
    let pixels: [UInt8]  // RGBA8, premultiplied-last
    let width: Int
    let height: Int

    /// The colour at a POINT coordinate, sampled at the pixel that contains it.
    func at(x: CGFloat, y: CGFloat) -> [Double] {
        let px = min(width - 1, max(0, Int(x * renderScale)))
        let py = min(height - 1, max(0, Int(y * renderScale)))
        let i = (py * width + px) * 4
        return [Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255]
    }

    /// The vertical extent, in POINTS, of everything in the column at `x`
    /// that differs from `background` by more than half the way to `ink`.
    /// Half-way is the antialiased edge, so the run this returns is the mark's
    /// true extent to within a third of a point.
    func runHeight(atX x: CGFloat, ink: [Double], background: [Double]) -> CGFloat {
        let px = min(width - 1, max(0, Int(x * renderScale)))
        let full = distance(ink, background)
        var first = -1, last = -1
        for py in 0..<height {
            let i = (py * width + px) * 4
            let c = [Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255]
            if distance(c, background) > full / 2 {
                if first < 0 { first = py }
                last = py
            }
        }
        guard first >= 0 else { return 0 }
        return CGFloat(last - first + 1) / renderScale
    }

    private func distance(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }
}

@MainActor
private func raster<V: View>(_ view: V) -> Raster {
    let renderer = ImageRenderer(content: AnyView(view))
    renderer.scale = renderScale
    renderer.isOpaque = true
    guard let cg = renderer.cgImage else { preconditionFailure("row did not render") }
    let (w, h) = (cg.width, cg.height)
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(
        data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Raster(pixels: pixels, width: w, height: h)
}

/// Both row shapes, laid out exactly as their `List` lays them out: the
/// section's leading and trailing insets, on the page colour they really
/// paint on.
@MainActor
private func inList<V: View>(_ row: V, dynamicType: DynamicTypeSize = .large) -> some View {
    row
        .padding(.horizontal, sessionListInset)
        .frame(width: screenWidth)
        .background(Theme.surface)
        .environment(\.dynamicTypeSize, dynamicType)
        .environment(\.colorScheme, .dark)
}

// MARK: - Fixtures

@MainActor
private func demoModel() -> AppModel {
    let model = AppModel()
    model.demo = DemoDataset.standard()
    model.phase = .ready
    return model
}

private func fixture(note: ChatNote?) -> Chat {
    Chat(
        id: "c1", deviceId: "d1", title: "Streaming veil on transcript rows",
        archived: false, cwd: "/Users/x/zeron", branch: "veil-fade", checkoutId: nil,
        config: nil, lastMessagePreview: nil, lastMessageAt: nowMs() - 90_000,
        createdAt: nowMs() - 900_000, spaceId: nil, lastSeenAt: nowMs(), note: note
    )
}

private let slot = "sky"
private var ink: [Double] { channels(NoteSlot.color(for: slot)) }
private var page: [Double] { channels(Theme.surface) }

private func channels(_ color: Color) -> [Double] {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return [Double(r), Double(g), Double(b)]
}

// MARK: - The clamp arithmetic (§4)

final class NoteMarkerClampTests: XCTestCase {
    /// 15. The height never exceeds `rowHeight − 2 * cap`.
    func testHeightNeverExceedsTheRowLessACapAtEachEnd() {
        for rowHeight in stride(from: 8.0, through: 120.0, by: 0.5) {
            for titleLine in stride(from: 0.0, through: 200.0, by: 2.5) {
                let h = NoteMarker.height(titleLine: titleLine, rowHeight: rowHeight)
                XCTAssertLessThanOrEqual(h, rowHeight - 2 * NoteMarker.cap + 1e-9,
                                         "row \(rowHeight), title \(titleLine)")
                XCTAssertLessThanOrEqual(h, titleLine + 1e-9)
                XCTAssertGreaterThanOrEqual(h, 0)
            }
        }
    }

    /// 16. **Guard**: `cap` clears the wash's corner intrusion at the marker's
    /// inset — today 3.0 > 2.71. A future change to the inset or to the row's
    /// corner radius that broke this would push a clamped marker outside the
    /// wash it paints on, and would break it silently.
    func testCapClearsTheWashesCornerIntrusionAtTheMarkersInset() {
        let radius = PressWashButtonStyle().cornerRadius
        let intrusion = NoteMarker.cornerIntrusion(radius: radius)
        XCTAssertEqual(intrusion, 2.7085, accuracy: 0.0005)
        XCTAssertGreaterThan(NoteMarker.cap, intrusion)
    }
}

// MARK: - The rendered marker (§4)

@MainActor
final class NoteMarkerRenderTests: XCTestCase {
    private func sessionRow(note: ChatNote?, model: AppModel) -> some View {
        ChatRow(chat: fixture(note: note), showLocation: true) {}
            .environment(model)
    }

    private func shelfRow(note: ChatNote?) -> some View {
        ArchivedChatRow(chat: fixture(note: note)) {}
    }

    /// 14. The height rule resolves to the title's line box — 17pt on both row
    /// shapes at the default content size — and the clamp does not bind there.
    func testTheHeightIsTheRowsOwnTitleLineOnBothShapes() {
        let model = demoModel()
        let note = ChatNote(text: "Ask Dana before this merges", color: slot)

        for row in [AnyView(sessionRow(note: note, model: model)), AnyView(shelfRow(note: note))] {
            let r = raster(inList(row))
            let marked = r.runHeight(atX: markerCentreX, ink: ink, background: page)
            XCTAssertEqual(marked, 17.0, accuracy: 0.5)

            // And the clamp does not bind at the height that row actually
            // rendered to — read back off the raster, not restated.
            let rowHeight = CGFloat(r.height) / renderScale
            XCTAssertEqual(NoteMarker.height(titleLine: marked, rowHeight: rowHeight),
                           marked, accuracy: 0.001)
        }
    }

    /// 15's reproducer: the shelf at `accessibility-extra-extra-extra-large`,
    /// where the title outgrows the pinned 36pt row. Without the clamp,
    /// adjacent markers meet and three notes render as one stripe.
    func testTheShelfClampBindsAtTheLargestTextSize() {
        let note = ChatNote(text: "Gamut clamp was silent", color: slot)
        let shelf = raster(inList(shelfRow(note: note), dynamicType: .accessibility5))
        let h = shelf.runHeight(atX: markerCentreX, ink: ink, background: page)
        XCTAssertGreaterThan(h, 0)
        XCTAssertLessThanOrEqual(h, 36 - 2 * NoteMarker.cap + 0.5)
    }

    /// 17, directly: `.restingNote(nil, …)` renders as though the marker code
    /// were not there at all. This is the half the diff below cannot see —
    /// the modifier itself is present in both of those renders, so a layout
    /// shift caused by the plumbing would be invisible to it.
    func testTheModifierItselfIsANoOpWithoutANote() {
        let bare = HStack {
            Text("Streaming veil on transcript rows").font(Theme.sans(13))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 300)
        .background(Theme.surface)

        XCTAssertEqual(raster(bare).pixels,
                       raster(bare.restingNote(nil, titleLine: 17)).pixels)
    }

    /// 17. The overlay contributes no layout: a row with no note is not
    /// merely similar to the same row with a note — every pixel outside the
    /// marker's own 3pt column band is the same one, on both shapes. Nothing
    /// moves, so a bare row is identical to the row as it stands today.
    func testTheOverlayContributesNoLayoutOnBothShapes() {
        let model = demoModel()
        let note = ChatNote(text: "Ask Dana before this merges", color: slot)

        assertOnlyTheMarkerBandDiffers(
            bare: raster(inList(sessionRow(note: nil, model: model))),
            noted: raster(inList(sessionRow(note: note, model: model))),
            shape: "session row"
        )
        assertOnlyTheMarkerBandDiffers(
            bare: raster(inList(shelfRow(note: nil))),
            noted: raster(inList(shelfRow(note: note))),
            shape: "shelf row"
        )
    }

    private func assertOnlyTheMarkerBandDiffers(bare: Raster, noted: Raster, shape: String) {
        XCTAssertEqual(bare.width, noted.width, "\(shape): width moved")
        XCTAssertEqual(bare.height, noted.height, "\(shape): height moved")
        let band = (Int((sessionListInset + NoteMarker.leadingInset) * renderScale)
            ..< Int((sessionListInset + NoteMarker.leadingInset + NoteMarker.width) * renderScale))
        var outside = 0
        for py in 0..<bare.height {
            for px in 0..<bare.width where !band.contains(px) {
                let i = (py * bare.width + px) * 4
                if bare.pixels[i..<i + 4] != noted.pixels[i..<i + 4] { outside += 1 }
            }
        }
        XCTAssertEqual(outside, 0, "\(shape): \(outside) pixels changed outside the marker's band")
    }

    /// 18. The shelf marker paints at opacity 1.0, not the 0.55 its sibling
    /// content carries. At 55% it measures 2.51:1 and no tone fixes it.
    func testTheShelfMarkerIsNotDimmed() {
        let note = ChatNote(text: "Ask Dana", color: slot)
        let shelf = raster(inList(shelfRow(note: note)))
        // Mid-row on the pinned 36pt shelf row, well inside the marker's
        // 9.5-26.5pt span, where a 0.55 dim would be unmissable.
        let sampled = shelf.at(x: markerCentreX, y: 18)
        for (got, want) in zip(sampled, ink) {
            XCTAssertEqual(got, want, accuracy: 0.01)
        }
    }

    /// 19. The marker's leading edge sits 14pt from the screen edge on both
    /// sections, so a marked session row lines up with a marked shelf row.
    func testTheMarkersLeadingEdgeIs14ptFromTheScreenEdgeOnBothSections() {
        let model = demoModel()
        let note = ChatNote(text: "Ask Dana", color: slot)
        XCTAssertEqual(sessionListInset, shelfListInset, "the two sections' insets drifted")
        XCTAssertEqual(sessionListInset + NoteMarker.leadingInset, 14)

        for row in [AnyView(sessionRow(note: note, model: model)), AnyView(shelfRow(note: note))] {
            let r = raster(inList(row))
            let mid = CGFloat(r.height) / renderScale / 2
            // Inside the mark, and one point clear of it on the page side.
            for (got, want) in zip(r.at(x: markerCentreX, y: mid), ink) {
                XCTAssertEqual(got, want, accuracy: 0.01)
            }
            for (got, want) in zip(r.at(x: sessionListInset + 0.5, y: mid), page) {
                XCTAssertEqual(got, want, accuracy: 0.01)
            }
        }
    }
}

// MARK: - What a noted row says aloud (§8)

final class NoteRowValueTests: XCTestCase {
    /// The prefix is "Note, " and the note is not capped. Without the prefix a
    /// note that opens with a noun is indistinguishable from a fifth column.
    func testTheSpokenValueIsThePrefixAndTheWholeNote() {
        let long = String(repeating: "a", count: 779)
        XCTAssertEqual(noteSpokenValue(ChatNote(text: long, color: "rose")), "Note, " + long)
        XCTAssertNil(noteSpokenValue(nil))
    }
}

// MARK: - The list's order (§4)

final class NoteSortOrderTests: XCTestCase {
    /// A note does not change the list's sort order. The marker is paint; the
    /// order is time and id, and it stays that way.
    func testANoteDoesNotChangeTheSortOrder() {
        let bare = (0..<6).map { i in
            Chat(id: "c\(i)", deviceId: "d", title: "t\(i)", archived: false, cwd: nil,
                 branch: nil, checkoutId: nil, config: nil, lastMessagePreview: nil,
                 lastMessageAt: Int64(1_000 - (i % 3) * 100), createdAt: 0, spaceId: "s",
                 lastSeenAt: nil)
        }
        let noted = bare.enumerated().map { i, chat -> Chat in
            var c = chat
            if i.isMultiple(of: 2) {
                c.note = ChatNote(text: "n\(i)", color: NoteSlot.allCases[i % 5].rawValue)
            }
            return c
        }
        XCTAssertEqual(sortActive(bare).map(\.id), sortActive(noted).map(\.id))
    }
}
