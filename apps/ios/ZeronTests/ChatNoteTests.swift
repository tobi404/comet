// Chat Note model, read and write (spec §1, §2; tests 1-7).
//
// Three pure seams carry the whole ticket: `ChatNote.normalized` is the one
// place "empty text means clear" lives, `parseChatNote` is the read, and
// `chatNoteField` is the write's wire value. The store and the app verbs are
// thin wrappers over these, so testing them here tests the feature.

import XCTest
@testable import Zeron

// MARK: - normalized (tests 1, 2)

final class ChatNoteNormalizedTests: XCTestCase {
    /// Test 1. Empty text means clear, and the phone is the only side that can
    /// enforce it — there is no engine below iOS to be the second guard.
    func testEmptyAndWhitespaceOnlyTextYieldNoNote() {
        XCTAssertNil(ChatNote.normalized(text: "", color: "rose"))
        XCTAssertNil(ChatNote.normalized(text: "   ", color: "rose"))
        XCTAssertNil(ChatNote.normalized(text: "\n\t  \n", color: "amber"))
    }

    /// Test 2. Trimming is at the ends only — inner whitespace is the user's.
    func testTrimsTheEndsAndKeepsTheMiddle() {
        let note = ChatNote.normalized(text: "  ask  Dana   first \n", color: "sky")
        XCTAssertEqual(note?.text, "ask  Dana   first")
        XCTAssertEqual(note?.color, "sky")
    }

    /// The colour is carried through untouched: an id this build never heard
    /// of survives a save, so a phone edit cannot downgrade a newer desktop's
    /// slot (§1).
    func testAnUnknownSlotIdSurvivesNormalization() {
        XCTAssertEqual(ChatNote.normalized(text: "note", color: "teal")?.color, "teal")
    }
}

// MARK: - The read (tests 3, 4, 5)

final class ChatNoteParseTests: XCTestCase {
    private func field(_ pairs: [String: JSONValue]) -> JSONValue { .object(pairs) }

    /// Test 3. An ABSENT colour breaks the model — the desktop makes colour
    /// required, and inventing a fallback would show a colour nobody picked.
    func testDropsANoteWithNoColor() {
        XCTAssertNil(parseChatNote(field(["text": .string("orphaned")])))
        XCTAssertNil(parseChatNote(field(["text": .string("orphaned"), "color": .null])))
        // A non-string colour reads as absent, not as an unknown id.
        XCTAssertNil(parseChatNote(field(["text": .string("orphaned"), "color": .int(3)])))
    }

    /// Test 3, second half. No text, and blank text, both drop: a colour with
    /// no text is not a note.
    func testDropsANoteWithNoTextOrBlankText() {
        XCTAssertNil(parseChatNote(field(["color": .string("rose")])))
        XCTAssertNil(parseChatNote(field(["text": .string(""), "color": .string("rose")])))
        XCTAssertNil(parseChatNote(field(["text": .string("  \n "), "color": .string("rose")])))
        XCTAssertNil(parseChatNote(field(["text": .int(7), "color": .string("rose")])))
    }

    /// A cleared note is `null` on the wire, and an unnoted chat has no key.
    func testDropsAnAbsentOrNullField() {
        XCTAssertNil(parseChatNote(nil))
        XCTAssertNil(parseChatNote(.null))
        XCTAssertNil(parseChatNote(.string("not an object")))
    }

    /// Test 4. An UNRECOGNISED colour does not break the model: the text is
    /// user content and must survive, the colour is decorative. The id is kept
    /// byte-for-byte so a save cannot downgrade it.
    func testKeepsAnUnknownSlotIdUnchanged() {
        let note = parseChatNote(field(["text": .string("Wrangler 4 dropped the routes block"),
                                        "color": .string("teal")]))
        XCTAssertEqual(note?.color, "teal")
        XCTAssertEqual(note?.text, "Wrangler 4 dropped the routes block")
        // The empty string is present-but-unknown, so it is kept too; the
        // paint layer answers it (§3).
        XCTAssertEqual(parseChatNote(field(["text": .string("x"), "color": .string("")]))?.color, "")
    }

    /// Test 5. The 280-character cap is an authoring affordance, not a storage
    /// invariant — the phone writes registry rows directly and any device can
    /// leave a longer note. The read keeps it whole; every surface elides.
    func testKeepsTextLongerThanTheCapWhole() {
        let long = String(repeating: "a", count: 900)
        XCTAssertEqual(parseChatNote(field(["text": .string(long),
                                            "color": .string("rose")]))?.text.count, 900)
    }

    /// The read does NOT trim. `normalized` is the write path only: trimming
    /// here would rewrite desktop-authored text on every read-modify-write.
    func testKeepsStoredTextVerbatim() {
        let stored = "  padded on both ends  "
        XCTAssertEqual(parseChatNote(field(["text": .string(stored),
                                            "color": .string("rose")]))?.text, stored)
    }
}

// MARK: - The write (tests 6, 7)

final class ChatNoteFieldTests: XCTestCase {
    /// The wire shape is a contract the desktop already shipped: one whole
    /// `note: { text, color }` object, replaced wholesale under per-field LWW.
    func testAValueWritesTheWholeObject() {
        XCTAssertEqual(chatNoteField(ChatNote(text: "Ask Dana before this merges", color: "rose")),
                       .object(["text": .string("Ask Dana before this merges"),
                                "color": .string("rose")]))
    }

    /// Test 6. `JSONValue.null` DELETES a field and is documented as such
    /// (RegistryCore.swift:15). An absent key is not a write at all, so the
    /// old note would stand.
    func testTheClearWritesExplicitNullAndNotAnAbsentKey() {
        XCTAssertEqual(chatNoteField(nil), .null)
    }

    /// Test 7. "Clear note" in the menu and saving blank text in the sheet are
    /// the same act, so they must reach the same stored value. This is what
    /// makes §7's "nothing asks for confirmation" honest rather than
    /// convenient: a confirm on one path only would make them disagree.
    func testClearingAndSavingBlankTextStoreTheSameThing() {
        let cleared = chatNoteField(nil)
        let blankSaved = chatNoteField(ChatNote.normalized(text: "   \n ", color: "violet"))
        XCTAssertEqual(blankSaved, cleared)
        XCTAssertEqual(blankSaved, .null)
    }

    /// The write and the read agree: what `chatNoteField` stores is what
    /// `parseChatNote` reads back, unknown id and over-cap length included.
    func testTheWireValueRoundTripsThroughTheRead() {
        let note = ChatNote(text: String(repeating: "z", count: 400), color: "teal")
        XCTAssertEqual(parseChatNote(chatNoteField(note)), note)
    }
}
