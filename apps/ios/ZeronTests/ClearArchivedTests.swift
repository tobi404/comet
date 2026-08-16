// "Clear archived" (shelf header): the scope filter that picks which rows go,
// and the one-batch tombstone that removes them. Mirrors the desktop's
// `delete_archived_chats` — archived rows only, chat + session row per chat.

import XCTest
@testable import Zeron

private func chat(_ id: String, archived: Bool, space: String?) -> Chat {
    Chat(id: id, deviceId: "dev-a", title: nil, archived: archived, cwd: nil,
         branch: nil, checkoutId: nil, config: nil, lastMessagePreview: nil,
         lastMessageAt: nil, createdAt: 1_754_000_000_000, spaceId: space,
         lastSeenAt: nil)
}

final class ArchivedClearKeysTests: XCTestCase {
    private let rows = [
        chat("a", archived: true, space: "sp-1"),
        chat("b", archived: false, space: "sp-1"),
        chat("c", archived: true, space: "sp-2"),
        chat("d", archived: true, space: nil),
    ]

    /// "All" scope clears every archived row, whatever space it belongs to —
    /// including a space-less one.
    func testAllScopeTakesEveryArchivedRow() {
        let keys = archivedClearKeys(chats: rows, spaceId: nil)
        XCTAssertEqual(keys.map(\.kind), ["chats", "sessions", "chats", "sessions",
                                          "chats", "sessions"])
        XCTAssertEqual(Set(keys.filter { $0.kind == "chats" }.map(\.id)), ["a", "c", "d"])
    }

    /// A selected space clears only that space's archived rows — never a row
    /// the shelf is not showing.
    func testSpaceScopeStaysInsideTheSpace() {
        let keys = archivedClearKeys(chats: rows, spaceId: "sp-1")
        XCTAssertEqual(keys.map(\.id), ["a", "a"])
        XCTAssertEqual(keys.map(\.kind), ["chats", "sessions"])
    }

    func testNothingArchivedYieldsNoKeys() {
        let keys = archivedClearKeys(chats: [chat("b", archived: false, space: "sp-1")],
                                     spaceId: nil)
        XCTAssertTrue(keys.isEmpty)
    }
}

final class ArchivedClearCopyTests: XCTestCase {
    /// Word-for-word the desktop's `clear_confirm_copy`, so the two apps read
    /// the same at the moment of a permanent delete.
    func testCopyMatchesTheDesktopWording() {
        XCTAssertEqual(
            clearArchivedConfirmCopy(count: 1),
            "1 archived session will be permanently deleted from all your devices. "
                + "This can\u{2019}t be undone.")
        XCTAssertTrue(clearArchivedConfirmCopy(count: 12)
            .hasPrefix("12 archived sessions will be"))
    }
}

final class ArchivedClearBatchTests: XCTestCase {
    /// One `deleteRows` batch tombstones the chat row AND its session row, and
    /// leaves the unarchived chat alone.
    func testBatchTombstonesChatAndSessionRows() {
        let doc = RegistryDoc(deviceId: "ios-test")
        doc.applyState(seq: 1, full: true, gcFloor: 0, rows: [
            RegistryRow(kind: "chats", id: "a", seq: 1, deleted: false, delHlc: nil,
                        fields: ["archived": .bool(true)], clocks: [:]),
            RegistryRow(kind: "sessions", id: "a", seq: 1, deleted: false, delHlc: nil,
                        fields: ["chatId": .string("a")], clocks: [:]),
            RegistryRow(kind: "chats", id: "b", seq: 1, deleted: false, delHlc: nil,
                        fields: ["archived": .bool(false)], clocks: [:]),
            RegistryRow(kind: "sessions", id: "b", seq: 1, deleted: false, delHlc: nil,
                        fields: ["chatId": .string("b")], clocks: [:]),
        ])

        let keys = archivedClearKeys(
            chats: [chat("a", archived: true, space: nil),
                    chat("b", archived: false, space: nil)],
            spaceId: nil)
        doc.deleteRows(keys)

        XCTAssertNil(doc.overlayRow(kind: "chats", id: "a"))
        XCTAssertNil(doc.overlayRow(kind: "sessions", id: "a"))
        XCTAssertNotNil(doc.overlayRow(kind: "chats", id: "b"))
        XCTAssertNotNil(doc.overlayRow(kind: "sessions", id: "b"))
    }
}
