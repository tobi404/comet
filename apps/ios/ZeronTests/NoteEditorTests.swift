// The Note Editor (spec §7; tests 29-36).
//
// **The delegate is never called by programmatic mutation.** `insertText`,
// `text =` and `setMarkedText` do not route through
// `shouldChangeTextInRanges`, so a test that mutates the field and then reads
// it back proves nothing about the cap. Every test here that is about the cap
// drives the delegate the way UIKit does — compute the range, call the hook,
// apply the edit only if it said yes — through `edit(_:_:range:text:)` below.

import SwiftUI
import XCTest

@testable import Zeron

@MainActor
final class NoteEditorTests: XCTestCase {

    // MARK: - Harness

    private func field(_ text: String = "") -> (NoteUITextView, NoteFieldCoordinator) {
        let coordinator = NoteFieldCoordinator()
        let view = NoteUITextView()
        view.delegate = coordinator
        view.text = text
        view.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        return (view, coordinator)
    }

    /// UIKit's own loop around the pre-edit hook: ask, and apply only if the
    /// answer is yes. Returns what the delegate said.
    @discardableResult
    private func edit(
        _ view: UITextView, _ coordinator: NoteFieldCoordinator,
        range: NSRange, text: String
    ) -> Bool {
        let allowed = coordinator.textView(
            view,
            shouldChangeTextInRanges: [NSValue(range: range)],
            replacementText: text
        )
        if allowed, let uiRange = view.uiRange(range) {
            view.replace(uiRange, withText: text)
        }
        coordinator.textViewDidChange(view)
        return allowed
    }

    private func caret(_ view: UITextView) -> NSRange { view.selectedRange }

    /// One turn of the run loop, so a `DispatchQueue.main.async` posted before
    /// this call has run by the time it returns.
    private func settle() {
        let done = expectation(description: "run loop")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    private func filler(_ count: Int) -> String { String(repeating: "a", count: count) }

    /// §9's unbreakable-URL fixture: one 118-character token with no space in
    /// it. Restated here because `DemoDataset`'s copy is file-private.
    private let unbreakableToken =
        "https://github.com/zeronsh/comet/blob/main/apps/ios/Zeron/Views/NoteEditor.swift"
        + "#L1-L400?tab=readme-ov-file"

    private func end(_ view: UITextView) -> NSRange {
        NSRange(location: (view.text as NSString).length, length: 0)
    }

    // MARK: - 29. Guard: the clamp refuses rather than trims

    /// **The test that catches the wrong Swift label, and the only one that
    /// does.** `textView(_:shouldChangeTextIn ranges:replacementText:)` —
    /// which is what the singular's label looks like — compiles, satisfies no
    /// protocol requirement, exports no selector, and never fires. There is no
    /// warning. Calling the method from Swift would pass either way, so the
    /// half that catches the typo asks the ObjC runtime.
    func testTheClampIsWiredToTheSelectorUIKitActuallyCalls() {
        let coordinator = NoteFieldCoordinator()
        XCTAssertTrue(
            coordinator.responds(
                to: Selector(("textView:shouldChangeTextInRanges:replacementText:"))),
            "the plural delegate is not exported — the cap holds only from the "
                + "textViewDidChange floor, which draws the over-cap character and takes it back"
        )
    }

    /// The other half: the over-cap character is **never drawn**. The delegate
    /// refuses the edit, so UIKit never applies it — the field is already at
    /// the cap when the hook returns.
    func testTheOverCapCharacterIsNeverDrawn() {
        let (view, coordinator) = field(filler(279))

        // Two characters into one character of room.
        let allowed = edit(view, coordinator, range: end(view), text: "bc")

        XCTAssertFalse(allowed, "a trim-after-the-fact clamp would have said yes here")
        XCTAssertEqual(view.text.count, NoteEditorMetrics.cap)
        XCTAssertTrue(view.text.hasSuffix("b"), "the delegate applies the shortened edit itself")
    }

    /// And at the cap exactly, with no room at all, nothing is applied.
    func testAFullFieldRefusesOneMoreCharacter() {
        let (view, coordinator) = field(filler(280))

        let allowed = edit(view, coordinator, range: end(view), text: "b")

        XCTAssertFalse(allowed)
        XCTAssertEqual(view.text.count, NoteEditorMetrics.cap)
        XCTAssertFalse(view.text.contains("b"))
    }

    // MARK: - 30. The 300-character paste

    /// One test, both of the delegate's two traps: the clamp and the caret.
    ///
    /// The caret trap is the second one — `replace(_:withText:)` leaves the
    /// caret at offset 0 of the replacement, so an unrestored clamp ends with
    /// the caret before the first character rather than after the last.
    func testA300CharacterPasteLeaves280CharactersAndTheCaretAt280() {
        let (view, coordinator) = field()

        let allowed = edit(view, coordinator, range: NSRange(location: 0, length: 0),
                           text: filler(300))
        settle()

        XCTAssertFalse(allowed)
        XCTAssertEqual(view.text.count, 280)
        XCTAssertEqual(caret(view), NSRange(location: 280, length: 0))
    }

    // MARK: - 31. Characters, not bytes

    /// 280 means the same for an emoji as for an `a`. The cut landing on a
    /// character boundary is a **code comment instead**, because
    /// `String.prefix(_:)` makes it impossible to fail.
    func testTheCapCountsCharactersAndNotBytes() {
        let (view, coordinator) = field()

        // 280 emoji is 560 UTF-16 units and 1120 bytes. It is 280 characters.
        XCTAssertTrue(edit(view, coordinator, range: NSRange(location: 0, length: 0),
                           text: String(repeating: "👍", count: 280)))
        XCTAssertEqual(view.text.count, 280)

        XCTAssertFalse(edit(view, coordinator, range: end(view), text: "👍"))
        XCTAssertEqual(view.text.count, 280)
    }

    /// The one place the distinction stops being free: room made by deleting
    /// an emoji selection is counted in characters, not in the UTF-16 units
    /// the `NSRange` carries.
    func testRoomFromADeletionIsCountedInCharacters() {
        let emoji = String(repeating: "👍", count: 10)
        let (view, coordinator) = field(emoji + filler(270))

        // Delete the ten emoji — ten characters of room, not twenty.
        let selection = NSRange(location: 0, length: (emoji as NSString).length)
        XCTAssertTrue(edit(view, coordinator, range: selection, text: filler(10)))
        XCTAssertEqual(view.text.count, 280)

        XCTAssertFalse(edit(view, coordinator, range: end(view), text: "b"))
    }

    // MARK: - 32. Room is measured after the deletion

    func testAFullFieldAcceptsAPasteOverASelection() {
        let (view, coordinator) = field(filler(280))

        let allowed = edit(view, coordinator, range: NSRange(location: 0, length: 40),
                           text: filler(40))

        XCTAssertTrue(allowed, "room is measured after the deletion, not before it")
        XCTAssertEqual(view.text.count, 280)
    }

    // MARK: - 33. The input-method commit

    /// The one thing the prototype proved only in halves — the delegate's
    /// stand-down and the `textViewDidChange` floor were each proved
    /// separately — so it is carried as a test rather than as a claim.
    ///
    /// Composition **can** exceed the cap: the pre-edit hook stands down while
    /// text is marked, because cutting there would fight the input method. The
    /// commit is what the floor exists to cut.
    func testAnOverCapInputMethodCommitIsTruncatedToTheCap() {
        let (view, coordinator) = field(filler(279))
        view.selectedRange = end(view)

        // Four marked kana against one character of room.
        view.setMarkedText("かかかか", selectedRange: NSRange(location: 4, length: 0))
        XCTAssertNotNil(view.markedTextRange)

        // The floor stands down too, so the counter reads what the field
        // holds — 283 — rather than what it will hold.
        coordinator.textViewDidChange(view)
        XCTAssertEqual(view.text.count, 283, "the composition is left alone while it is marked")

        view.unmarkText()
        coordinator.textViewDidChange(view)

        XCTAssertEqual(view.text.count, NoteEditorMetrics.cap)
    }

    /// And the stand-down is the pre-edit hook's, not only the floor's.
    func testThePreEditHookStandsDownWhileTextIsMarked() {
        let (view, coordinator) = field(filler(280))
        view.selectedRange = end(view)
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0))

        let allowed = coordinator.textView(
            view,
            shouldChangeTextInRanges: [NSValue(range: end(view))],
            replacementText: "か"
        )

        XCTAssertTrue(allowed, "the clamp must not fight the input method mid-composition")
    }

    // MARK: - Return, and the newline

    /// **Return saves and dismisses**, and the newline is refused before it
    /// lands. Its price, stated plainly: the phone cannot author a multi-line
    /// note.
    func testReturnSavesAndNeverInsertsANewline() {
        let (view, coordinator) = field("hello")
        var saved = 0
        coordinator.onSubmit = { saved += 1 }

        let allowed = edit(view, coordinator, range: end(view), text: "\n")

        XCTAssertFalse(allowed)
        XCTAssertEqual(saved, 1)
        XCTAssertEqual(view.text, "hello")
    }

    /// A note written with line breaks on the desktop is unharmed — it loads
    /// into the field and saves back with its newlines intact. Only the Return
    /// key is refused, never a newline arriving inside a paste.
    func testAPastedNewlineSurvives() {
        let (view, coordinator) = field()

        XCTAssertTrue(edit(view, coordinator, range: NSRange(location: 0, length: 0),
                           text: "one\ntwo"))
        XCTAssertEqual(view.text, "one\ntwo")
    }

    // MARK: - 34. A long note does not widen the field

    /// **The guard on the compression resistance.** A `UITextView`'s intrinsic
    /// content size is its CONTENT size and it resists compression at
    /// `.defaultHigh`. Left alone, a long single-paragraph note makes the
    /// field hundreds of points wide: the note draws as one clipped line and
    /// the slot row is shoved off the sheet entirely. The reproducer is a
    /// single-paragraph fixture with no spaces — the seeded unbreakable URL.
    func testALongSingleParagraphNoteDoesNotWidenTheField() {
        let view = NoteUITextView()
        view.text = unbreakableToken

        let proposed: CGFloat = 300
        let fitted = view.sizeThatFits(CGSize(width: proposed, height: .greatestFiniteMagnitude))

        XCTAssertLessThanOrEqual(fitted.width, proposed)
        XCTAssertGreaterThan(fitted.height, NoteEditorMetrics.linesHeight(1),
                             "the note wraps rather than running off as one line")
    }

    func testTheFieldDoesNotResistHorizontalCompression() {
        let view = NoteUITextView()

        XCTAssertEqual(view.contentCompressionResistancePriority(for: .horizontal),
                       .defaultLow)
        XCTAssertEqual(view.contentHuggingPriority(for: .horizontal), .defaultLow)
    }

    // MARK: - 35. The floor and the ceiling are measured

    /// **The floor and ceiling are measured against laid-out line height and
    /// not against `font.lineHeight * n`.**
    ///
    /// §7 gives the reason as the font under-counting, because TextKit's line
    /// fragment is slightly taller. **On Geist at 15pt the two coincide** —
    /// the fragment is 19.5pt and so is `font.lineHeight` — so an assertion
    /// that the measurement is strictly taller would be false here. The guard
    /// that survives is the one that matters: the numbers the sheet is built
    /// from are what the FIELD ITSELF lays out, whatever the font's own
    /// metrics say. A font whose leading is not zero moves them and this test
    /// follows it.
    func testTheFloorAndCeilingAreWhatTheFieldItselfLaysOut() {
        for (lines, clamp) in [(NoteEditorMetrics.floorLines, NoteEditorMetrics.floorHeight),
                               (NoteEditorMetrics.ceilingLines, NoteEditorMetrics.ceilingHeight)] {
            let view = NoteUITextView()
            view.text = Array(repeating: "A", count: lines).joined(separator: "\n")
            let fitted = view.sizeThatFits(
                CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)).height

            // At or above what the field lays out, and by under a point: the
            // rounding up is what stops a fractional line box clipping its
            // last line, and it must not buy more than that.
            XCTAssertGreaterThanOrEqual(clamp, fitted)
            XCTAssertLessThan(clamp, fitted + 1)
        }

        XCTAssertEqual(NoteEditorMetrics.floorHeight,
                       NoteEditorMetrics.linesHeight(3) + 2 * NoteEditorMetrics.insetV)
        XCTAssertEqual(NoteEditorMetrics.ceilingHeight,
                       NoteEditorMetrics.linesHeight(6) + 2 * NoteEditorMetrics.insetV)
    }

    /// The field floors at three lines and stops growing at six.
    func testTheFieldHeightIsHeldBetweenTheFloorAndTheCeiling() {
        XCTAssertEqual(NoteEditorMetrics.fieldHeight(content: 0),
                       NoteEditorMetrics.floorHeight)
        XCTAssertEqual(NoteEditorMetrics.fieldHeight(content: 10_000),
                       NoteEditorMetrics.ceilingHeight)

        let between = (NoteEditorMetrics.floorHeight + NoteEditorMetrics.ceilingHeight) / 2
        XCTAssertEqual(NoteEditorMetrics.fieldHeight(content: between), between)
    }

    /// **The floor and ceiling are HEIGHTS**, fixed at what their line counts
    /// occupy at the DEFAULT text size (§8's one rule). As line counts they
    /// grow with the text, and at AX-XXXL with a long note the sheet's top
    /// reaches 57pt, the fitted detent has silently become `.large`, and the
    /// Colour Slots sit behind the keyboard where they cannot be reached at
    /// all.
    func testTheCeilingDoesNotGrowWithTheUsersTextSize() {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: Theme.sansUI(NoteEditorMetrics.fontSize),
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )

        XCTAssertLessThan(NoteEditorMetrics.ceilingHeight,
                          scaled.lineHeight * CGFloat(NoteEditorMetrics.ceilingLines),
                          "a scaled ceiling is the defect: six AX-XXXL lines is the sheet")
    }

    // MARK: - 36. The detent

    /// **`detent = content height + chrome`**, where the chrome is the nav
    /// bar, the grabber above it, and the room under the content. Too small
    /// scrolls a sheet that should not scroll; too large draws the void
    /// `.medium` draws.
    ///
    /// Both failure modes are a gap between the detent and the content, so
    /// this pins the gap: it is the chrome exactly, at both ends of the
    /// field's range and everywhere between, and the chrome is the swept
    /// number and not §7's carried 60. Asserting `detentHeight` against its
    /// own definition would restate the code and could not fail.
    func testTheDetentIsTheContentPlusTheSweptChrome() {
        XCTAssertEqual(NoteEditorMetrics.chrome, 41,
                       "swept on an iPhone 17 Pro: 60 leaves 17.5pt of void, 20 falls short")

        let range = [NoteEditorMetrics.floorHeight,
                     (NoteEditorMetrics.floorHeight + NoteEditorMetrics.ceilingHeight) / 2,
                     NoteEditorMetrics.ceilingHeight]
        for height in range {
            let gap = NoteEditorMetrics.detentHeight(fieldHeight: height)
                - NoteEditorMetrics.contentHeight(fieldHeight: height)
            XCTAssertEqual(gap, 41, accuracy: 0.001)
        }

        // And it grows with the field, point for point — a detent that stopped
        // tracking would clip the note or draw container under the slot row.
        XCTAssertEqual(
            NoteEditorMetrics.detentHeight(fieldHeight: NoteEditorMetrics.ceilingHeight)
                - NoteEditorMetrics.detentHeight(fieldHeight: NoteEditorMetrics.floorHeight),
            NoteEditorMetrics.ceilingHeight - NoteEditorMetrics.floorHeight,
            accuracy: 0.001)
    }

    /// The content is padding, field, gap and slot row — **field → slot row
    /// and nothing else** — and §7's two quoted numbers fall out of it.
    func testTheContentFloorsAtTheBareNoteAndRisesToTheCeiling() {
        let floor = NoteEditorMetrics.contentHeight(fieldHeight: NoteEditorMetrics.floorHeight)
        let ceiling = NoteEditorMetrics.contentHeight(
            fieldHeight: NoteEditorMetrics.ceilingHeight)

        XCTAssertEqual(floor,
                       2 * NoteEditorMetrics.contentPadding + NoteEditorMetrics.floorHeight
                           + NoteEditorMetrics.fieldSlotGap + NoteEditorMetrics.hitTarget)
        // §7 quotes about 173pt and about 230pt, on a field of 75pt and a line
        // of about 18.3pt. Geist's line is 19.5pt, so the measured numbers are
        // 177 and 235. The detent is arithmetic precisely so this drift lands
        // in a number rather than in a clipped sheet.
        XCTAssertEqual(floor, 177, accuracy: 1)
        XCTAssertEqual(ceiling, 235, accuracy: 1)
        XCTAssertGreaterThan(ceiling, floor)
    }

    // MARK: - The slot row

    /// **`sky` becomes "Blue"** — a storage token is not a word a person uses
    /// for a colour they are picking. **This does not touch the wire**: the id
    /// stays `sky`.
    /// **The role is spoken because the control has no other name.** Five bare
    /// colour words in a sheet say nothing about what choosing one does.
    func testTheSlotsAreSpokenAsColourWordsAndSkyIsBlue() {
        XCTAssertEqual(NoteSlot.allCases.map(\.spokenLabel),
                       ["Rose note colour", "Amber note colour", "Green note colour",
                        "Blue note colour", "Violet note colour"])
        XCTAssertEqual(NoteSlot.sky.rawValue, "sky", "the wire id is untouched")
    }

    /// **The field's name.** Without it VoiceOver reads the note text and then
    /// "text field" — a named control instead of an anonymous one.
    func testTheFieldIsNamedNote() {
        XCTAssertEqual(NoteUITextView().accessibilityLabel, "Note")
    }

    /// **The ring gains an explicit `Selected` value**, because
    /// `.accessibilityAddTraits(.isSelected)` does not appear in any tree this
    /// effort could produce, so the ring's selected state would otherwise be
    /// claimed by nothing.
    func testTheChosenSlotCarriesAnExplicitSelectedValue() {
        XCTAssertEqual(NoteSlotRow.accessibilityValue(selected: true), "Selected")
        XCTAssertEqual(NoteSlotRow.accessibilityValue(selected: false), "")
    }

    /// An id no case matches rings `rose`, which is the same answer
    /// `NoteSlot.color(for:)` paints the row's marker with. The two must not
    /// disagree: a sheet ringing one slot over a row marked another reads as
    /// the phone being broken.
    func testAnUnknownStoredIdRingsTheSlotTheRowPaints() {
        XCTAssertEqual(NoteSlot.slot(for: "chartreuse"), .rose)
        XCTAssertEqual(NoteSlot.slot(for: ""), .rose)
        XCTAssertEqual(NoteSlot.slot(for: "violet"), .violet)
    }

    /// The ring is held one cell out from the **dot**, not from the 44pt
    /// target: at 44 it becomes a hoop with the dot rattling inside it.
    func testTheRingIsHeldOutFromTheDotAndNotFromTheHitTarget() {
        XCTAssertEqual(NoteEditorMetrics.ringDiameter, 26)
        XCTAssertLessThan(NoteEditorMetrics.ringDiameter, NoteEditorMetrics.hitTarget)
        XCTAssertGreaterThanOrEqual(NoteEditorMetrics.hitTarget, 44,
                                    "the phone's minimum, which the desktop's 24 is under")
    }

    /// Hidden until 240, muted, turning full at 280. Verified at its real
    /// thresholds: absent at 239, muted at 245, full at 280.
    func testTheCounterAppearsAt240AndTurnsFullAtTheCap() {
        XCTAssertEqual(NoteEditorMetrics.counterFrom, 240)
        XCTAssertLessThan(239, NoteEditorMetrics.counterFrom)
        XCTAssertGreaterThanOrEqual(245, NoteEditorMetrics.counterFrom)
        XCTAssertEqual(NoteEditorMetrics.cap, 280)
    }
}
