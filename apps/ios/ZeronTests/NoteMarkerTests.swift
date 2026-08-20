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

// `Raster`, `raster(_:)` and `srgb(_:)` live in `RasterSupport.swift` —
// the Note Card's tests (§5) measure rendered output the same way.

/// The list's `listRowInsets` leading, read off the two production
/// constants rather than restated. The marker's inset composes with this one;
/// it does not stack on it.
@MainActor private let sessionListInset = ChatRow.listInsets.leading
@MainActor private let shelfListInset = ArchivedSection.rowInsets.leading

/// The centre of the marker's 3pt column, in points from the screen edge.
@MainActor private let markerCentreX =
    sessionListInset + NoteMarker.leadingInset + NoteMarker.width / 2

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

/// The row's own `space @ device` string. The shelf row takes it as a
/// parameter for the Note Card it opens (§5); it never draws it.
private let fixtureLocation = "zeron @ MacBook Pro"

private let slot = "sky"
private var ink: [Double] { srgb(NoteSlot.color(for: slot)) }
private var page: [Double] { srgb(Theme.surface) }

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

    /// The shelf row reads `AppModel` now — the long press it carries needs
    /// the archive and clear verbs (§6).
    private func shelfRow(note: ChatNote?, model: AppModel) -> some View {
        ArchivedChatRow(chat: fixture(note: note), location: fixtureLocation) {}
            .environment(model)
    }

    /// 14. The height rule resolves to the title's line box — 17pt on both row
    /// shapes at the default content size — and the clamp does not bind there.
    func testTheHeightIsTheRowsOwnTitleLineOnBothShapes() {
        let model = demoModel()
        let note = ChatNote(text: "Ask Dana before this merges", color: slot)

        for row in [AnyView(sessionRow(note: note, model: model)), AnyView(shelfRow(note: note, model: model))] {
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
        let shelf = raster(inList(shelfRow(note: note, model: demoModel()),
                                  dynamicType: .accessibility5))
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
            bare: raster(inList(shelfRow(note: nil, model: model))),
            noted: raster(inList(shelfRow(note: note, model: model))),
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
        let shelf = raster(inList(shelfRow(note: note, model: demoModel())))
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

        for row in [AnyView(sessionRow(note: note, model: model)), AnyView(shelfRow(note: note, model: model))] {
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

// MARK: - The row's custom actions (§8)

@MainActor
final class NoteRowActionTests: XCTestCase {
    /// The heard order is `Edit note, Clear note` on a noted row and
    /// `Add note` on a bare one. The labels carry no ellipsis: the menu's
    /// "Edit note…" is a pointer convention, and a screen reader speaks the
    /// three dots.
    ///
    /// The row's archive verb is not in this list. It comes from the trailing
    /// swipe, the platform puts it after everything declared, and it is not
    /// orderable against these — so it cannot be asserted here without
    /// restating the swipe's own label. It is measured instead, below.
    func testTheHeardOrderIsEditThenClear() {
        XCTAssertEqual(chatNoteHeardActions(hasNote: true).map(\.title),
                       ["Edit note", "Clear note"])
        XCTAssertEqual(chatNoteHeardActions(hasNote: false).map(\.title), ["Add note"])
    }

    /// **Guard: the declaration is the reverse of the heard order.**
    /// `.accessibilityActions` presents the reverse of what is declared, so
    /// the row declares `Clear note, Edit note` to be heard the other way
    /// round. It compiles and runs either way; only VoiceOver tells them
    /// apart. A future reader who "fixes" the reversal breaks this test.
    func testTheDeclaredOrderIsTheReverseOfTheHeardOrder() {
        XCTAssertEqual(chatNoteDeclaredActions(hasNote: true),
                       chatNoteHeardActions(hasNote: true).reversed())
        XCTAssertEqual(chatNoteDeclaredActions(hasNote: true).map(\.title),
                       ["Clear note", "Edit note"])
    }

    /// Each action does its menu item's own act. This drives
    /// `ChatNoteAction.perform` itself, which is the single copy of the act
    /// the menu's item and the row's action both call — the row and the menu
    /// cannot drift apart, because there is nothing to drift.
    ///
    /// Archive is not here. It is the swipe's own act, and test 37 owns it.
    func testEachActionDoesItsMenuItemsOwnAct() {
        let model = demoModel()
        let noted = model.overviewChats.first { $0.note != nil }!
        var editing = false
        let binding = Binding(get: { editing }, set: { editing = $0 })

        ChatNoteAction.edit.perform(on: noted, model: model, editing: binding)
        XCTAssertTrue(editing)
        XCTAssertNotNil(model.overviewChats.first { $0.id == noted.id }!.note)

        editing = false
        ChatNoteAction.add.perform(on: noted, model: model, editing: binding)
        XCTAssertTrue(editing)

        editing = false
        ChatNoteAction.clear.perform(on: noted, model: model, editing: binding)
        XCTAssertNil(model.overviewChats.first { $0.id == noted.id }!.note)
        // Clearing does not open the editor, and it asks for nothing first.
        XCTAssertFalse(editing)
    }

    /// The four row shapes, as AXe dumped them off a running build. The archive
    /// verb lands last because the platform put it there, not because it was
    /// declared there — it cannot be asserted in a unit test without restating
    /// the swipe's own label, so it is recorded here as measured.
    ///
    /// ```
    /// noted chat row    ['Edit note', 'Clear note', 'Archive']
    /// bare chat row     ['Add note', 'Archive']
    /// noted shelf row   ['Edit note', 'Clear note', 'Unarchive']
    /// bare shelf row    ['Add note', 'Unarchive']
    /// PullRequestBadge  ['Archive']
    /// ```
    ///
    /// The badge's lone `Archive` is the List's own, on a second element inside
    /// the same cell. The note actions are not on it because they are declared
    /// on the row's element and not on the row — see `View.chatNoteActions`,
    /// which records what the leak looked like.
    ///
    /// The rows kept their spoken value through all of it, which is the
    /// assertion this test can make: `Note, <text>` on a noted row, and no
    /// value at all on a bare one.
    func testTheActionsDoNotMoveTheRowsSpokenValue() {
        let model = demoModel()
        let noted = model.overviewChats.first { $0.note != nil }!
        let bare = model.overviewChats.first { $0.note == nil }!

        XCTAssertEqual(noteSpokenValue(noted.note), "Note, " + noted.note!.text)
        XCTAssertNil(noteSpokenValue(bare.note))
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
