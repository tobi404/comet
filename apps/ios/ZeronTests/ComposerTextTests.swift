// The rich-text composer model. These tests pin the two-clause invariant:
// a run keeps its mention attribute only if (1) its visible text is exactly
// "@basename" and (2) the serialized draft re-parses to that mention at that
// position. Neither clause implies the other — see the spec's "round-trip
// invariant" section.

import XCTest
import SwiftUI
@testable import Zeron

final class ComposerTextTests: XCTestCase {

    /// A draft reading "see @a.rs " with the chip attributed.
    private func draftWithChip(prefix: String = "see ",
                               path: String = "a.rs",
                               isDir: Bool = false) -> ComposerText {
        var text = ComposerText(prefix)
        var selection = AttributedTextSelection(insertionPoint: text.attributed.endIndex)
        let end = text.plainText.count
        text.apply(path: path, isDir: isDir, over: end..<end, selection: &selection)
        return text
    }

    // MARK: Serialization

    func testIntactChipSerializesToTheCanonicalLink() {
        let text = draftWithChip()
        XCTAssertEqual(text.markdown(), "see [a.rs](zeron-file:a.rs) ")
    }

    func testPlainTextShowsTheChipAsAtBasename() {
        XCTAssertEqual(draftWithChip().plainText, "see @a.rs ")
    }

    func testDirectoryPickSerializesWithTrailingSlash() {
        let text = draftWithChip(prefix: "", path: "src/one", isDir: true)
        XCTAssertEqual(text.markdown(), "[one](zeron-file:src/one/) ")
    }

    func testDraftWithNoChipsSerializesUnchanged() {
        XCTAssertEqual(ComposerText("plain words").markdown(), "plain words")
    }

    // MARK: Clause 1 — visible text

    func testTypingInsideAChipDropsTheAttribute() {
        var text = draftWithChip()          // "see @a.rs "
        text.replaceForTesting(6..<6, with: "X")   // "see @aX.rs "
        XCTAssertEqual(text.markdown(), "see @aX.rs ")
    }

    func testBackspaceAtTheChipEdgeDropsTheAttribute() {
        var text = draftWithChip()          // "see @a.rs "
        text.replaceForTesting(8..<9, with: "")   // "see @a.r "
        XCTAssertEqual(text.markdown(), "see @a.r ")
    }

    func testDeletingTheSpaceBetweenTwoSameFileChipsDropsBoth() {
        var text = draftWithChip(prefix: "")            // "@a.rs "
        var selection = AttributedTextSelection(insertionPoint: text.attributed.endIndex)
        let end = text.plainText.count
        text.apply(path: "a.rs", isDir: false, over: end..<end, selection: &selection)
        XCTAssertEqual(text.plainText, "@a.rs @a.rs ")
        text.replaceForTesting(5..<6, with: "")         // "@a.rs@a.rs "
        XCTAssertEqual(text.markdown(), "@a.rs@a.rs ")
    }

    func testAnUntouchedChipSurvivesAnEditElsewhere() {
        var text = draftWithChip()
        text.replaceForTesting(0..<0, with: "hey ")
        XCTAssertEqual(text.markdown(), "hey see [a.rs](zeron-file:a.rs) ")
    }

    func testTextTypedAfterAChipDoesNotInheritTheAttribute() {
        var text = draftWithChip()               // "see @a.rs "
        text.replaceForTesting(9..<9, with: "Z") // "see @a.rsZ "
        // `inheritedByAddedText = false` means "Z" lands OUTSIDE the run, so
        // the chip still reads exactly "@a.rs" and both clauses hold. The chip
        // survives and "Z" is plain text beside it. If this ever asserts the
        // chip was dropped, the attribute is bleeding into typed text.
        XCTAssertEqual(text.markdown(), "see [a.rs](zeron-file:a.rs)Z ")
        XCTAssertEqual(text.plainText, "see @a.rsZ ")
    }

    // MARK: Clause 2 — round trip

    /// THE REVIEW'S FAILURE CASE.
    func testStrayOpenBracketBeforeAChipDropsThatChip() {
        var text = draftWithChip(prefix: "see ")   // "see @a.rs "
        text.replaceForTesting(4..<4, with: "[ notes ")  // "see [ notes @a.rs "
        XCTAssertEqual(text.markdown(), "see [ notes @a.rs ")
    }

    func testAnUnsafePathNeverGetsAnAttribute() {
        var text = ComposerText("")
        var selection = AttributedTextSelection(insertionPoint: text.attributed.startIndex)
        text.apply(path: "../secret", isDir: false, over: 0..<0, selection: &selection)
        XCTAssertEqual(text.markdown(), "@secret ")
    }

    // MARK: Trigger veto

    func testCaretInsideAnIntactChipOpensNoTrigger() {
        let text = draftWithChip()          // "see @a.rs "
        let index = text.attributed.index(text.attributed.startIndex, offsetByCharacters: 7)
        XCTAssertNil(text.trigger(at: AttributedTextSelection(insertionPoint: index)))
    }

    func testCaretAtTheChipTrailingEdgeOpensNoTrigger() {
        let text = draftWithChip()
        let index = text.attributed.index(text.attributed.startIndex, offsetByCharacters: 9)
        XCTAssertNil(text.trigger(at: AttributedTextSelection(insertionPoint: index)))
    }

    func testAFreshlyTypedAtStillTriggers() {
        let text = ComposerText("look @Inf")
        let index = text.attributed.index(text.attributed.startIndex, offsetByCharacters: 9)
        XCTAssertEqual(text.trigger(at: AttributedTextSelection(insertionPoint: index))?.query, "Inf")
    }

    // MARK: Index adapter

    func testCaretOffsetCountsCharactersAcrossMultibyteText() {
        let text = ComposerText("é🙂ab")
        let index = text.attributed.index(text.attributed.startIndex, offsetByCharacters: 3)
        XCTAssertEqual(text.caretOffset(AttributedTextSelection(insertionPoint: index)), 3)
    }

    func testARangeSelectionHasNoCaretAndNoTrigger() {
        let text = ComposerText("/td")
        let start = text.attributed.startIndex
        let end = text.attributed.index(start, offsetByCharacters: 3)
        let selection = AttributedTextSelection(range: start..<end)
        XCTAssertNil(text.caretOffset(selection))
        XCTAssertNil(text.trigger(at: selection))
    }

    // MARK: Command insertion

    func testCommandPickInsertsPlainTextWithNoAttribute() {
        var text = ComposerText("/td")
        var selection = AttributedTextSelection(insertionPoint: text.attributed.endIndex)
        text.apply(command: "tdd", over: 0..<3, selection: &selection)
        XCTAssertEqual(text.plainText, "/tdd ")
        XCTAssertEqual(text.markdown(), "/tdd ")
    }
}
