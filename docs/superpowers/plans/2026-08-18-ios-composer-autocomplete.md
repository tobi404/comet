# iOS Composer Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the iOS composer slash-command (`/`) and file-mention (`@`) autocomplete, with mention chips, matching the desktop app.

**Architecture:** A pure trigger detector and a pure Markdown-link codec sit under a rich-text model (`ComposerText`) that wraps `AttributedString`. The detector and the suggestion cache never see attributed text, so the risky rich-text layer is contained in one file. Command and file lists come from the host device over the existing device relay, using RPCs the engine already serves.

**Tech Stack:** Swift 6, SwiftUI (iOS 26 deployment target), XCTest, `xcodebuild`. Existing app at `apps/ios/Zeron`.

**Spec:** `docs/superpowers/specs/2026-08-18-ios-composer-autocomplete-design.md`

## Global Constraints

- **iOS deployment target is 26.0** (`apps/ios/Zeron.xcodeproj/project.pbxproj:227`). `TextEditor(text:selection:)` over `AttributedString` and `AttributedTextSelection` are iOS 26.0+. Do not add availability guards for older versions.
- **Both Xcode groups are `PBXFileSystemSynchronizedRootGroup`** (`project.pbxproj:40-52`). New `.swift` files under `apps/ios/Zeron/` and `apps/ios/ZeronTests/` are picked up automatically. **Never edit `project.pbxproj`.**
- **Tests use XCTest**, not Swift Testing. Match `apps/ios/ZeronTests/RegistryCoreTests.swift`: `import XCTest`, `@testable import Zeron`, `final class …: XCTestCase`.
- **The build and test command is:**
  ```
  xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
  ```
  Run it from the repo root, `/Users/bekademuradze/Documents/AppDev/comet`.
- **Character offsets, not byte offsets.** Rust uses UTF-8 byte offsets. Every Swift offset in this plan counts `Character`s. Be consistent; the tests pin it.
- **The mention wire format is fixed** and must match Rust byte for byte: `[escaped-basename](zeron-file:percent-encoded-path)`. The Rust original is `local_file_link` at `crates/ui/src/composer.rs:713-726`.
- **Commit message style:** lowercase `area: summary`. Look at `git log --oneline -10` for examples. **Never add a `Co-Authored-By` trailer.**
- **Do not modify `CHANGELOG.md`** or any auto-generated file.

---

## File Structure

**Create, in `apps/ios/Zeron/Composer/`:**

| File | Responsibility |
|---|---|
| `ComposerTrigger.swift` | Pure. Detects a `/` or `@` trigger from plain text plus a caret offset. |
| `MentionLink.swift` | Pure. Swift port of the Rust mention codec: encode, decode, escape, safety, serialize, whole-text parse. |
| `ComposerText.swift` | The only file that knows `AttributedString`. Owns the mention attribute, the index adapter, serialization, and the invariant. |
| `ComposerSuggestions.swift` | `@Observable`. Owns the request state, the caches, ranking, and the dismissal rule. |
| `ComposerPopover.swift` | Presentation only. Renders the suggestion list. |

**Create, in `apps/ios/ZeronTests/`:**

| File | Covers |
|---|---|
| `ComposerTriggerTests.swift` | Task 1 |
| `MentionLinkTests.swift` | Task 2 |
| `ComposerTextTests.swift` | Task 3 |
| `ComposerSuggestionsTests.swift` | Task 5 |

**Modify:**

| File | Change |
|---|---|
| `apps/ios/Zeron/Models/Entities.swift` | Add `SlashCommand` and `FileSearchMatch`. |
| `apps/ios/Zeron/Sync/DeviceRelayClient.swift` | Add the `isUnknownMethod` helper. |
| `apps/ios/Zeron/Sync/WorkspaceStore.swift` | Add `listCommands` and `searchFiles`. |
| `apps/ios/Zeron/Composer/ComposerView.swift` | `ComposerShell` swaps to `TextEditor`; `ComposerView` wires the popover and the send path. |
| `apps/ios/Zeron/Views/NewSessionView.swift` | Adopt the new draft type. |
| `apps/ios/Zeron/Markdown/MarkdownBlockView.swift:56-62` | Make a `zeron-file:` link inert in the transcript. |

---

## Task 0: Spike — is the rich-text composer viable?

**This task is throwaway. Its output is a go / no-go answer, not code you keep.**

Nothing else in this plan depends on it except Tasks 3, 7, and 8. Tasks 1, 2, 4, 5, and 6 are safe to build in parallel with it.

**Files:**
- Create: `apps/ios/Zeron/Views/SpikeComposerView.swift` (**delete before Task 7**)

- [ ] **Step 1: Build a throwaway screen**

Create `apps/ios/Zeron/Views/SpikeComposerView.swift`:

```swift
import SwiftUI

/// THROWAWAY. Delete before Task 7. Answers whether a rich-text composer is
/// viable on iOS 26 before the real composer is rewritten against it.
struct SpikeComposerView: View {
    @State private var text: AttributedString = {
        var base = AttributedString("see ")
        var chip = AttributedString("@Info.plist")
        chip.font = .system(.body, design: .monospaced)
        chip.backgroundColor = .gray.opacity(0.25)
        base.append(chip)
        base.append(AttributedString(" ok"))
        return base
    }()
    @State private var selection = AttributedTextSelection()

    var body: some View {
        VStack(alignment: .leading) {
            TextEditor(text: $text, selection: $selection)
                .scrollContentBackground(.hidden)
                .background(.black.opacity(0.2))
                .frame(minHeight: 60, maxHeight: 220)
            Text(debugLine).font(.caption).monospaced()
        }
        .padding()
    }

    private var debugLine: String {
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            return "caret \(text.characters.distance(from: text.startIndex, to: index))"
        case .ranges:
            return "range selection"
        }
    }
}
```

- [ ] **Step 2: Run it and answer every question on the checklist**

Point the app at this view temporarily (or add it to a debug sheet). Then answer each, in writing:

1. Does the chip run paint with the mono font and the background wash?
2. Type immediately after the chip. Does the new text inherit the chip styling?
3. Type in the middle of the chip. What happens to the run?
4. Backspace at the chip's trailing edge. Does one character go, or the whole chip?
5. Switch to a Japanese or Chinese keyboard and type. Does mutating `text` mid-composition cancel the marked text?
6. Shake to undo (or `⌘Z` on a hardware keyboard) after an edit. Does undo work?
7. Set `text = AttributedString("")` while the editor is focused. Does it clear, or does the old string come back? Does `selection` survive?
8. Select the chip, copy, paste. Does the styling survive the round trip?
9. Add `.frame(minHeight:)` steps for 1 to 7 lines. Can you drive the height from the line count?
10. Add a placeholder overlay that hides when `text.characters.isEmpty` is false. Does it look right?

- [ ] **Step 3: Test `invalidationConditions`**

Add this above `SpikeComposerView` and re-run question 3:

```swift
struct SpikeValue: Hashable, Sendable { let path: String }

enum SpikeAttribute: AttributedStringKey {
    typealias Value = SpikeValue
    static let name = "spikeMention"
    static let inheritedByAddedText = false
    static let invalidationConditions: Set<AttributedString.AttributeInvalidationCondition>? = [.textChanged]
}
```

Attach it to the chip run. Type inside the chip. **Does the framework remove the attribute on its own?** Record yes or no. If yes, Task 3's manual clause-1 pass becomes a cheap belt-and-braces check rather than the only mechanism.

- [ ] **Step 4: Write the findings down and decide**

Write the ten answers plus the `invalidationConditions` result into the plan file under this task, as a short list.

**Go:** questions 1, 2, 7, 9, and 10 all behave. Continue to Task 1.

**No-go:** any of those five fails. **Stop and report.** Tasks 1, 2, 4, 5, and 6 still ship. Task 3 collapses to a plain `String` model with the Markdown visible, and Tasks 7 and 8 keep `TextField`. That is the fallback the spec's module boundary exists to protect.

- [ ] **Step 5: Delete the spike file**

```bash
rm apps/ios/Zeron/Views/SpikeComposerView.swift
```

Do not commit the spike.

---

## Task 1: Trigger detection

**Files:**
- Create: `apps/ios/Zeron/Composer/ComposerTrigger.swift`
- Test: `apps/ios/ZeronTests/ComposerTriggerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum TriggerKind { case command, path }`
  - `struct Trigger: Equatable { let kind: TriggerKind; let query: String; let token: String; let range: Range<Int> }`
  - `enum ComposerTrigger { static func detect(text: String, caret: Int) -> Trigger?; static func replace(_ text: String, range: Range<Int>, with: String) -> (text: String, caret: Int) }`

The rules are a port of `slash_token` (`crates/ui/src/composer.rs:3212-3233`) and `mention_token` (`composer.rs:3179-3208`). Read both before you start.

- [ ] **Step 1: Write the failing tests**

Create `apps/ios/ZeronTests/ComposerTriggerTests.swift`:

```swift
// Trigger rules ported from the desktop composer: slash_token
// (crates/ui/src/composer.rs:3212-3233) and mention_token (3179-3208).
// Desktop and iOS must agree on what counts as a trigger, or the same draft
// behaves differently on two clients.

import XCTest
@testable import Zeron

final class ComposerTriggerTests: XCTestCase {

    // MARK: Command

    func testSlashAtStartTriggers() {
        let t = ComposerTrigger.detect(text: "/td", caret: 3)
        XCTAssertEqual(t, Trigger(kind: .command, query: "td", token: "/td", range: 0..<3))
    }

    func testSlashNotAtStartDoesNotTrigger() {
        // Slash commands are whole-prompt prefixes: only offset 0 counts.
        XCTAssertNil(ComposerTrigger.detect(text: "hi /td", caret: 6))
        XCTAssertNil(ComposerTrigger.detect(text: "hi\n/td", caret: 6))
    }

    func testCaretPastCommandTokenDoesNotTrigger() {
        // Typing the argument closes the popup.
        XCTAssertNil(ComposerTrigger.detect(text: "/goal ship it", caret: 13))
    }

    func testCaretInsideCommandTokenTriggersWithFullTokenRange() {
        let t = ComposerTrigger.detect(text: "/goal ship it", caret: 3)
        XCTAssertEqual(t, Trigger(kind: .command, query: "go", token: "/goal", range: 0..<5))
    }

    func testCommandQueryWithSlashDoesNotTrigger() {
        // A typed path must not open the command popup.
        XCTAssertNil(ComposerTrigger.detect(text: "/src/main", caret: 9))
    }

    func testCaretAtZeroDoesNotTrigger() {
        XCTAssertNil(ComposerTrigger.detect(text: "/td", caret: 0))
    }

    // MARK: Path

    func testAtBeginningTokenTriggers() {
        let t = ComposerTrigger.detect(text: "look @Inf", caret: 9)
        XCTAssertEqual(t, Trigger(kind: .path, query: "Inf", token: "@Inf", range: 5..<9))
    }

    func testEmailDoesNotTrigger() {
        XCTAssertNil(ComposerTrigger.detect(text: "name@example.com", caret: 16))
    }

    func testOpenParenBoundaryTriggers() {
        let t = ComposerTrigger.detect(text: "(@src", caret: 5)
        XCTAssertEqual(t, Trigger(kind: .path, query: "src", token: "@src", range: 1..<5))
    }

    func testSecondAtInQueryDoesNotTrigger() {
        XCTAssertNil(ComposerTrigger.detect(text: "@a@b", caret: 4))
    }

    func testPathRangeExtendsPastCaretToWhitespace() {
        // Editing the middle of a mention replaces the whole token.
        let t = ComposerTrigger.detect(text: "@Info.plist tail", caret: 5)
        XCTAssertEqual(t, Trigger(kind: .path, query: "Info", token: "@Info.plist", range: 0..<11))
    }

    func testAtWithNoTriggerReturnsNil() {
        XCTAssertNil(ComposerTrigger.detect(text: "plain words", caret: 11))
    }

    // MARK: Replace

    func testReplaceSubstitutesRangeAndMovesCaret() {
        let result = ComposerTrigger.replace("look @Inf here", range: 5..<9, with: "@Info.plist ")
        XCTAssertEqual(result.text, "look @Info.plist  here")
        XCTAssertEqual(result.caret, 17)
    }

    func testReplaceClampsOutOfRangeBounds() {
        let result = ComposerTrigger.replace("ab", range: 1..<99, with: "X")
        XCTAssertEqual(result.text, "aX")
        XCTAssertEqual(result.caret, 2)
    }

    func testOffsetsCountCharactersNotBytes() {
        // "é" and "🙂" are one Character each.
        let t = ComposerTrigger.detect(text: "é🙂 @a", caret: 5)
        XCTAssertEqual(t, Trigger(kind: .path, query: "a", token: "@a", range: 3..<5))
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet \
  -only-testing:ZeronTests/ComposerTriggerTests
```

Expected: the build fails with "cannot find 'ComposerTrigger' in scope".

- [ ] **Step 3: Implement**

Create `apps/ios/Zeron/Composer/ComposerTrigger.swift`:

```swift
// Composer trigger detection: a port of the desktop composer's slash_token
// and mention_token (crates/ui/src/composer.rs:3179-3233). Pure — no SwiftUI,
// no attributed text, no I/O — so it is testable without a simulator and it
// stays correct if the rich-text layer above it is ever replaced.
//
// All offsets count Characters. Rust counts UTF-8 bytes; do not mix them.

import Foundation

enum TriggerKind {
    case command
    case path
}

struct Trigger: Equatable {
    let kind: TriggerKind
    /// Text between the sigil and the caret. What the popover filters on.
    let query: String
    /// The FULL text of `range`, including the sigil and anything after the
    /// caret. The dismissal rule keys on this, not on `query`: moving the caret
    /// inside a dismissed token must keep it closed, while any edit reopens it
    /// (crates/ui/src/composer.rs:3302-3304). `query` changes on a caret move;
    /// `token` does not.
    let token: String
    /// The span the pick replaces, including the sigil. For a path this
    /// extends past the caret to the end of the token.
    let range: Range<Int>
}

enum ComposerTrigger {

    static func detect(text: String, caret: Int) -> Trigger? {
        let chars = Array(text)
        guard caret >= 0, caret <= chars.count else { return nil }
        return command(chars, caret) ?? path(chars, caret)
    }

    static func replace(_ text: String, range: Range<Int>,
                        with replacement: String) -> (text: String, caret: Int) {
        let chars = Array(text)
        let lower = max(0, min(chars.count, range.lowerBound))
        let upper = max(lower, min(chars.count, range.upperBound))
        let next = String(chars[0..<lower]) + replacement + String(chars[upper...])
        return (next, lower + replacement.count)
    }

    // MARK: Command

    /// The `/` must open the whole draft: slash commands are whole-prompt
    /// prefixes (`/compact`, `/goal ship it`), so only the first token
    /// triggers, and a query holding another `/` (a typed path) never does.
    private static func command(_ chars: [Character], _ caret: Int) -> Trigger? {
        guard chars.first == "/" else { return nil }
        let end = chars.firstIndex(where: \.isWhitespace) ?? chars.count
        guard caret > 0, caret <= end else { return nil }
        let query = String(chars[1..<caret])
        guard !query.contains("/") else { return nil }
        return Trigger(kind: .command, query: query,
                       token: String(chars[0..<end]), range: 0..<end)
    }

    // MARK: Path

    /// The `@` must begin a token. This excludes `name@example.com` and
    /// ordinary words while allowing punctuation such as `(@src`.
    private static func path(_ chars: [Character], _ caret: Int) -> Trigger? {
        var tokenStart = 0
        var back = caret - 1
        while back >= 0 {
            if chars[back].isWhitespace {
                tokenStart = back + 1
                break
            }
            back -= 1
        }

        var at: Int?
        var scan = caret - 1
        while scan >= tokenStart {
            if chars[scan] == "@" {
                at = scan
                break
            }
            scan -= 1
        }
        guard let at else { return nil }

        let validBoundary: Bool
        if at == 0 {
            validBoundary = true
        } else {
            let previous = chars[at - 1]
            validBoundary = previous.isWhitespace
                || previous == "(" || previous == "[" || previous == "{"
        }
        guard validBoundary else { return nil }

        let query = String(chars[(at + 1)..<caret])
        guard !query.contains("@") else { return nil }

        // The token ends at the first whitespace AT OR AFTER the caret, so
        // editing the middle of a mention replaces the whole token.
        var end = chars.count
        var forward = caret
        while forward < chars.count {
            if chars[forward].isWhitespace {
                end = forward
                break
            }
            forward += 1
        }

        return Trigger(kind: .path, query: query,
                       token: String(chars[at..<end]), range: at..<end)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet \
  -only-testing:ZeronTests/ComposerTriggerTests
```

Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/Zeron/Composer/ComposerTrigger.swift apps/ios/ZeronTests/ComposerTriggerTests.swift
git commit -m "ios: port the desktop composer's slash and mention trigger rules"
```

---

## Task 2: The mention link codec

**Files:**
- Create: `apps/ios/Zeron/Composer/MentionLink.swift`
- Test: `apps/ios/ZeronTests/MentionLinkTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct ParsedMention: Equatable { let range: Range<Int>; let basename: String; let path: String; let isDir: Bool }`
  - `enum MentionLink { static let scheme: String; static func percentEncode(_:) -> String; static func percentDecode(_:) -> String?; static func escapeLabel(_:) -> String; static func isSafe(_:) -> Bool; static func basename(of:) -> String; static func serialize(path:isDir:) -> String; static func parse(_:) -> [ParsedMention] }`

This is a line-by-line port of four Rust functions. **Open `crates/ui/src/composer.rs` and read `percent_encode_path` (670-682), `percent_decode_path` (684-704), `escape_mention_label` (706-711), `local_file_link` (713-726), `local_path_is_safe` (728-736), `label_close` (738-750), and `file_mention_links` (752-795) before writing any Swift.** The output must match byte for byte.

- [ ] **Step 1: Write the failing tests**

Create `apps/ios/ZeronTests/MentionLinkTests.swift`:

```swift
// Conformance vectors for the mention link codec. Every expected value here
// is lifted from the Rust tests in crates/ui/src/composer.rs; the two
// implementations must agree byte for byte or a chip written on the phone
// renders as raw Markdown on the desktop.

import XCTest
@testable import Zeron

final class MentionLinkTests: XCTestCase {

    // MARK: Encoding

    func testPercentEncodeLeavesUnreservedBytes() {
        XCTAssertEqual(MentionLink.percentEncode("src/a-b_c.d~e"), "src/a-b_c.d~e")
    }

    func testPercentEncodeUsesUppercaseHex() {
        XCTAssertEqual(MentionLink.percentEncode("a b"), "a%20b")
        XCTAssertEqual(MentionLink.percentEncode("a\nb"), "a%0Ab")
    }

    func testPercentEncodeIsPerByteForMultibyte() {
        XCTAssertEqual(MentionLink.percentEncode("é"), "%C3%A9")
    }

    func testPercentDecodeRoundTrips() {
        for raw in ["src/a.rs", "a b", "é", "a\nb", "sr(c)/x"] {
            XCTAssertEqual(MentionLink.percentDecode(MentionLink.percentEncode(raw)), raw)
        }
    }

    func testPercentDecodeRejectsTruncatedEscape() {
        XCTAssertNil(MentionLink.percentDecode("a%2"))
        XCTAssertNil(MentionLink.percentDecode("a%zz"))
    }

    // MARK: Escaping

    func testEscapeLabelEscapesBackslashFirst() {
        XCTAssertEqual(MentionLink.escapeLabel("a\\b"), "a\\\\b")
        XCTAssertEqual(MentionLink.escapeLabel("a[b]c"), "a\\[b\\]c")
    }

    // MARK: Safety

    func testIsSafeRejectsUnsafePaths() {
        XCTAssertFalse(MentionLink.isSafe(""))
        XCTAssertFalse(MentionLink.isSafe("/abs/path"))
        XCTAssertFalse(MentionLink.isSafe("src\\win"))
        XCTAssertFalse(MentionLink.isSafe("../a.rs"))
        XCTAssertFalse(MentionLink.isSafe("src/./a.rs"))
        XCTAssertFalse(MentionLink.isSafe("src//a.rs"))
        XCTAssertFalse(MentionLink.isSafe("src/a\nb.rs"))
    }

    func testIsSafeAcceptsOrdinaryRelativePaths() {
        XCTAssertTrue(MentionLink.isSafe("a.rs"))
        XCTAssertTrue(MentionLink.isSafe("src/one/mod.rs"))
        XCTAssertTrue(MentionLink.isSafe("src/a file.rs"))
    }

    // MARK: Serialize

    func testSerializeFile() {
        XCTAssertEqual(MentionLink.serialize(path: "src/a.rs", isDir: false),
                       "[a.rs](zeron-file:src/a.rs)")
    }

    func testSerializeDirectoryCarriesTrailingSlash() {
        XCTAssertEqual(MentionLink.serialize(path: "src/one", isDir: true),
                       "[one](zeron-file:src/one/)")
    }

    func testSerializeEscapesLabelAndEncodesPath() {
        XCTAssertEqual(MentionLink.serialize(path: "src/a b.rs", isDir: false),
                       "[a b.rs](zeron-file:src/a%20b.rs)")
    }

    // MARK: Parse — these mirror the Rust rejection assertions at composer.rs:5955-5961

    func testParseAcceptsAWellFormedLink() {
        let parsed = MentionLink.parse("see [a.rs](zeron-file:src/a.rs) ok")
        XCTAssertEqual(parsed, [ParsedMention(range: 4..<31, basename: "a.rs",
                                              path: "src/a.rs", isDir: false)])
    }

    func testParseRejectsForeignScheme() {
        XCTAssertTrue(MentionLink.parse("[site](https://example.com/a)").isEmpty)
    }

    func testParseRejectsUnsafePath() {
        XCTAssertTrue(MentionLink.parse("[a.rs](zeron-file:../a.rs)").isEmpty)
        XCTAssertTrue(MentionLink.parse("[a.rs](zeron-file:src%5Cfake%5Ca.rs)").isEmpty)
        XCTAssertTrue(MentionLink.parse("[a.rs](zeron-file:src/a%0A.rs)").isEmpty)
    }

    func testParseRejectsUnencodedPath() {
        // percent_encode_path(&target) == encoded — a raw space fails.
        XCTAssertTrue(MentionLink.parse("[a file.rs](zeron-file:src/a file.rs)").isEmpty)
    }

    func testParseRejectsLabelThatIsNotTheBasename() {
        XCTAssertTrue(MentionLink.parse("[other](zeron-file:src/a.rs)").isEmpty)
    }

    func testParseAcceptsADirectory() {
        let parsed = MentionLink.parse("[one](zeron-file:src/one/)")
        XCTAssertEqual(parsed, [ParsedMention(range: 0..<26, basename: "one",
                                              path: "src/one", isDir: true)])
    }

    /// THE REVIEW'S FAILURE CASE. A stray `[` before a chip makes the parser
    /// consume the chip's `](` as the close of the earlier label, and line 792
    /// of the Rust then skips past the whole link. Nothing is found.
    func testStrayOpenBracketSwallowsAFollowingChip() {
        XCTAssertTrue(MentionLink.parse("see [ notes [a.rs](zeron-file:a.rs)").isEmpty)
    }

    func testParseFindsTwoChips() {
        let text = "[a.rs](zeron-file:a.rs) and [b.rs](zeron-file:b.rs)"
        XCTAssertEqual(MentionLink.parse(text).map(\.path), ["a.rs", "b.rs"])
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet \
  -only-testing:ZeronTests/MentionLinkTests
```

Expected: the build fails with "cannot find 'MentionLink' in scope".

- [ ] **Step 3: Implement**

Create `apps/ios/Zeron/Composer/MentionLink.swift`:

```swift
// The mention wire format, ported from crates/ui/src/composer.rs:670-795.
// A private URI scheme keeps file mentions distinguishable from ordinary
// Markdown links pasted into the composer.
//
// This must agree with the Rust byte for byte. The desktop parser rejects a
// link whose label is not the path's basename, whose path is unsafe, or whose
// encoding does not round-trip — and it parses the WHOLE draft, so a stray
// bracket elsewhere can invalidate an otherwise perfect link. ComposerText
// relies on `parse` to notice exactly that.
//
// Offsets count Characters, matching ComposerTrigger.

import Foundation

struct ParsedMention: Equatable {
    let range: Range<Int>
    let basename: String
    let path: String
    let isDir: Bool
}

enum MentionLink {

    static let scheme = "zeron-file:"

    // MARK: Encoding

    static func percentEncode(_ path: String) -> String {
        var out = ""
        for byte in Array(path.utf8) {
            let unreserved = (byte >= 0x30 && byte <= 0x39)   // 0-9
                || (byte >= 0x41 && byte <= 0x5A)             // A-Z
                || (byte >= 0x61 && byte <= 0x7A)             // a-z
                || byte == 0x2D || byte == 0x2E               // - .
                || byte == 0x5F || byte == 0x7E               // _ ~
                || byte == 0x2F                               // /
            if unreserved {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out.append("%")
                out += String(format: "%02X", byte)
            }
        }
        return out
    }

    static func percentDecode(_ encoded: String) -> String? {
        var bytes: [UInt8] = []
        let raw = Array(encoded.utf8)
        var at = 0
        while at < raw.count {
            if raw[at] == UInt8(ascii: "%") {
                guard at + 2 < raw.count,
                      let hex = String(bytes: raw[(at + 1)...(at + 2)], encoding: .utf8),
                      hex.allSatisfy(\.isHexDigit),
                      let byte = UInt8(hex, radix: 16)
                else { return nil }
                bytes.append(byte)
                at += 3
            } else {
                bytes.append(raw[at])
                at += 1
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    // MARK: Labels and safety

    static func escapeLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return false }
        for part in path.split(separator: "/", omittingEmptySubsequences: false)
        where part.isEmpty || part == "." || part == ".." {
            return false
        }
        return true
    }

    static func basename(of path: String) -> String {
        let trimmed = trimTrailingSlashes(path)
        guard let last = trimmed.split(separator: "/").last else { return trimmed }
        return String(last)
    }

    // MARK: Serialize

    static func serialize(path rawPath: String, isDir: Bool) -> String {
        let path = trimTrailingSlashes(rawPath)
        let target = path + (isDir ? "/" : "")
        return "[\(escapeLabel(basename(of: path)))](\(scheme)\(percentEncode(target)))"
    }

    // MARK: Parse

    static func parse(_ text: String) -> [ParsedMention] {
        let chars = Array(text)
        var links: [ParsedMention] = []
        var search = 0

        while search < chars.count {
            guard let start = chars[search...].firstIndex(of: "[") else { break }
            guard let labelEnd = labelClose(chars, from: start + 1) else {
                search = start + 1
                continue
            }
            let targetStart = labelEnd + 2
            guard targetStart <= chars.count,
                  let closeIndex = chars[targetStart...].firstIndex(of: ")") else {
                search = start + 1
                continue
            }
            let end = closeIndex + 1
            let label = String(chars[(start + 1)..<labelEnd])
            let target = String(chars[targetStart..<(end - 1)])

            guard target.hasPrefix(scheme) else {
                search = end
                continue
            }
            let encoded = String(target.dropFirst(scheme.count))

            if let decoded = percentDecode(encoded) {
                let isDir = decoded.hasSuffix("/")
                let path = isDir ? String(decoded.dropLast()) : decoded
                let name = basename(of: path)
                if isSafe(path),
                   percentEncode(decoded) == encoded,
                   escapeLabel(name) == label {
                    links.append(ParsedMention(range: start..<end, basename: name,
                                               path: path, isDir: isDir))
                }
            }
            search = end
        }
        return links
    }

    // MARK: Helpers

    /// The first unescaped `]` that is followed by `(`.
    private static func labelClose(_ chars: [Character], from start: Int) -> Int? {
        var escaped = false
        var at = start
        while at < chars.count {
            if escaped {
                escaped = false
            } else if chars[at] == "\\" {
                escaped = true
            } else if chars[at] == "]", at + 1 < chars.count, chars[at + 1] == "(" {
                return at
            }
            at += 1
        }
        return nil
    }

    private static func trimTrailingSlashes(_ path: String) -> String {
        var out = path
        while out.hasSuffix("/") { out.removeLast() }
        return out
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet \
  -only-testing:ZeronTests/MentionLinkTests
```

Expected: PASS, 19 tests.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/Zeron/Composer/MentionLink.swift apps/ios/ZeronTests/MentionLinkTests.swift
git commit -m "ios: port the zeron-file mention codec and its whole-text parser"
```

---

## Task 3: The attributed text model

**Depends on Task 0 (go), Task 1, and Task 2.**

**Files:**
- Create: `apps/ios/Zeron/Composer/ComposerText.swift`
- Test: `apps/ios/ZeronTests/ComposerTextTests.swift`

**Interfaces:**
- Consumes: `Trigger`, `ComposerTrigger.detect`, `MentionLink.*`, `ParsedMention`.
- Produces:
  - `struct MentionValue: Hashable, Sendable { let path: String; let isDir: Bool }`
  - `enum MentionAttribute: AttributedStringKey`
  - `struct ComposerText: Equatable`, with `init(_ plain: String = "")`, `var attributed: AttributedString`, `var plainText: String`, `var isEmpty: Bool`, `func caretOffset(_:) -> Int?`, `func trigger(at:) -> Trigger?`, `func markdown() -> String`, `mutating func enforceInvariant()`, `mutating func apply(command:over:selection:)`, `mutating func apply(path:isDir:over:selection:)`, `mutating func clear(selection:)`
  - `struct MentionFormatting: AttributedTextFormattingDefinition` — Task 7 applies it to the editor with `.attributedTextFormattingDefinition(MentionFormatting())`.

- [ ] **Step 1: Write the failing tests**

Create `apps/ios/ZeronTests/ComposerTextTests.swift`:

```swift
// The rich-text composer model. These tests pin the two-clause invariant:
// a run keeps its mention attribute only if (1) its visible text is exactly
// "@basename" and (2) the serialized draft re-parses to that mention at that
// position. Neither clause implies the other — see the spec's "round-trip
// invariant" section.

import XCTest
// AttributedTextSelection is a SwiftUI type, and `@testable import` does not
// re-export the module's own imports. Without this the test file will not
// compile.
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

    // MARK: Run splitting

    func testAnUnrelatedAttributeSplittingAChipDoesNotDuplicateItsLink() {
        var text = draftWithChip()          // "see @a.rs "
        // Colour two characters in the middle of the chip. Foundation's plain
        // `runs` view splits at that boundary; the mention-keyed view must not.
        // Iterating the plain view emits the link once PER FRAGMENT, and clause 1
        // then fails on every fragment and kills a visually intact chip.
        let start = text.attributed.index(text.attributed.startIndex, offsetByCharacters: 6)
        let end = text.attributed.index(text.attributed.startIndex, offsetByCharacters: 8)
        text.attributed[start..<end].foregroundColor = .red

        XCTAssertEqual(text.markdown(), "see [a.rs](zeron-file:a.rs) ",
                       "a split chip must serialize to ONE link, not one per fragment")
        text.enforceInvariant()
        XCTAssertEqual(text.markdown(), "see [a.rs](zeron-file:a.rs) ",
                       "a visually intact chip must survive an unrelated attribute")
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet \
  -only-testing:ZeronTests/ComposerTextTests
```

Expected: the build fails with "cannot find 'ComposerText' in scope".

- [ ] **Step 3: Implement**

Create `apps/ios/Zeron/Composer/ComposerText.swift`:

```swift
// The composer's text model. This is the ONLY file that knows AttributedString
// exists: ComposerTrigger, ComposerSuggestions, and ComposerPopover all work on
// plain text and a caret offset. If rich text ever has to be abandoned, the
// blast radius is this file.
//
// A mention chip is styled text, not an embedded view — the desktop defines the
// same look (crates/ui/src/composer.rs:643-647). The PATH lives in the
// attribute, never in the visible text, so editing the label cannot silently
// retarget a mention.

import SwiftUI

struct MentionValue: Hashable, Sendable {
    let path: String
    let isDir: Bool
}

enum MentionAttribute: AttributedStringKey {
    typealias Value = MentionValue
    static let name = "zeronMention"
    /// Text typed beside a chip must never join it.
    static let inheritedByAddedText = false
    /// Ask the framework to drop the attribute when the run's own text
    /// changes. `enforceInvariant` re-checks regardless: this is a fast path,
    /// not the contract.
    static let invalidationConditions: Set<AttributedString.AttributeInvalidationCondition>? = [.textChanged]
}

extension AttributeScopes {
    struct ZeronScope: AttributeScope {
        let zeronMention: MentionAttribute
        let swiftUI: AttributeScopes.SwiftUIAttributes
    }

    var zeron: ZeronScope.Type { ZeronScope.self }
}

// MARK: - Chip paint, derived

/// Chip styling is DERIVED from the mention key. It is never stored on the run.
///
/// The Task 0 spike proved both halves of why, and both are load-bearing:
///
///   - Visual attributes inherit FORWARD. Text typed at a chip's trailing edge
///     picks up a *stored* mono font and wash, because
///     `inheritedByAddedText = false` holds back only the custom key.
///   - `invalidationConditions` strips the custom key without stripping stored
///     paint, so a dead mention would keep looking like a live chip.
///
/// Deriving fixes both ends at once: the paint follows the key, and only the
/// key. Store styling on the run and you reintroduce both bugs.
///
/// A `ValueConstraint` may READ any attribute but may WRITE only its own
/// `AttributeKey` (`SwiftUICore.swiftinterface:9535-9547`), so font and
/// background are two constraints rather than one.
struct MentionFormatting: AttributedTextFormattingDefinition {
    typealias Scope = AttributeScopes.ZeronScope

    var body: some AttributedTextFormattingDefinition<Scope> {
        MentionFont()
        MentionWash()
    }
}

struct MentionFont: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.ZeronScope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.FontAttribute

    func constrain(_ container: inout Attributes) {
        container[AttributeKey.self] = container[MentionAttribute.self] == nil
            ? nil
            : .system(size: 15, design: .monospaced)
    }
}

struct MentionWash: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.ZeronScope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

    func constrain(_ container: inout Attributes) {
        container[AttributeKey.self] = container[MentionAttribute.self] == nil
            ? nil
            : Color.white.opacity(0.10)
    }
}

struct ComposerText: Equatable {

    var attributed: AttributedString

    init(_ plain: String = "") {
        attributed = AttributedString(plain)
    }

    // MARK: Plain projection

    var plainText: String { String(attributed.characters) }

    var isEmpty: Bool { attributed.characters.isEmpty }

    // MARK: Selection

    /// The caret offset in Characters, or nil when the selection covers a
    /// range. `.ranges` can be discontiguous, so both cases fall out here.
    func caretOffset(_ selection: AttributedTextSelection) -> Int? {
        switch selection.indices(in: attributed) {
        case .insertionPoint(let index):
            return attributed.characters.distance(from: attributed.startIndex, to: index)
        case .ranges:
            return nil
        }
    }

    /// A trigger, vetoed when it overlaps an existing chip. A chip's visible
    /// text IS `@basename`, so the pure detector cannot tell one from a token
    /// the user typed. Only this file can see the attribute, so the veto lives
    /// here.
    func trigger(at selection: AttributedTextSelection) -> Trigger? {
        guard let caret = caretOffset(selection),
              let candidate = ComposerTrigger.detect(text: plainText, caret: caret),
              !intersectsMention(candidate.range)
        else { return nil }
        return candidate
    }

    private func intersectsMention(_ range: Range<Int>) -> Bool {
        for (lower, upper) in mentionRuns() where range.lowerBound < upper && lower < range.upperBound {
            return true
        }
        return false
    }

    // MARK: Serialization

    /// The draft as the host sees it. Non-mention runs pass through; each
    /// mention run becomes the canonical link built from its ATTRIBUTE.
    func markdown() -> String {
        var out = ""
        // Iterate the MENTION-KEYED run view, never `attributed.runs`. The plain
        // view splits at EVERY attribute boundary, so an unrelated attribute
        // landing on part of a chip — the iOS 26 editor's own formatting menu can
        // underline half a chip, and pasted styled text does it too — breaks one
        // chip into several runs that each carry the same value. This loop would
        // then emit the same link once per fragment. The keyed view coalesces
        // them back into a single slice.
        for (mention, range) in attributed.runs[MentionAttribute.self] {
            if let mention {
                out += MentionLink.serialize(path: mention.path, isDir: mention.isDir)
            } else {
                out += String(attributed[range].characters)
            }
        }
        return out
    }

    // MARK: The invariant

    /// Strip the mention attribute from every run that fails either clause:
    ///
    ///   1. the run's visible text is exactly `@basename`, and
    ///   2. the serialized draft re-parses to that mention at that position.
    ///
    /// Clause 1 keeps the screen and the wire honest — `markdown()` builds the
    /// label from the attribute, so a mangled run would otherwise serialize to
    /// a perfectly valid link for a path the user can no longer see. Clause 2
    /// catches what clause 1 cannot: an unsafe path, an encoding that does not
    /// round-trip, and surrounding text that swallows the link (the desktop
    /// parser reads the WHOLE draft — crates/ui/src/composer.rs:752-795).
    mutating func enforceInvariant() {
        let serialized = markdown()
        let parsed = MentionLink.parse(serialized)

        var doomed: [Range<AttributedString.Index>] = []
        var offset = 0

        // Keyed run view, for the same reason as `markdown()`: a chip split by
        // an unrelated attribute must be judged as ONE mention, or clause 1 fails
        // on every fragment and a visually intact chip dies for no reason.
        for (mention, range) in attributed.runs[MentionAttribute.self] {
            let visible = String(attributed[range].characters)
            guard let mention else {
                offset += visible.count
                continue
            }

            let link = MentionLink.serialize(path: mention.path, isDir: mention.isDir)
            let expected = offset..<(offset + link.count)
            let clauseOne = visible == "@" + MentionLink.basename(of: mention.path)
            let clauseTwo = parsed.contains { candidate in
                candidate.range == expected
                    && candidate.path == mention.path
                    && candidate.isDir == mention.isDir
            }
            if !clauseOne || !clauseTwo {
                doomed.append(range)
            }
            offset += link.count
        }

        for range in doomed {
            attributed[range][MentionAttribute.self] = nil
        }
    }

    // MARK: Mutation

    mutating func apply(command: String, over range: Range<Int>,
                        selection: inout AttributedTextSelection) {
        replace(range, with: AttributedString("/\(command) "), selection: &selection)
    }

    mutating func apply(path: String, isDir: Bool, over range: Range<Int>,
                        selection: inout AttributedTextSelection) {
        var chip = AttributedString("@" + MentionLink.basename(of: path))
        if MentionLink.isSafe(path) {
            chip[MentionAttribute.self] = MentionValue(path: path, isDir: isDir)
        }
        var replacement = chip
        replacement.append(AttributedString(" "))
        replace(range, with: replacement, selection: &selection)
    }

    mutating func clear(selection: inout AttributedTextSelection) {
        attributed = AttributedString("")
        selection = AttributedTextSelection(insertionPoint: attributed.startIndex)
    }

    /// Every text mutation goes through here so the invariant is re-checked
    /// exactly once per change. `transform(updating:)` keeps `selection` valid
    /// across the edit; the final caret is then placed deliberately after the
    /// inserted text, so that assignment — not the `updating:` argument — is what
    /// determines where the caret ends up.
    private mutating func replace(_ range: Range<Int>, with replacement: AttributedString,
                                  selection: inout AttributedTextSelection) {
        let count = attributed.characters.count
        let lower = max(0, min(count, range.lowerBound))
        let upper = max(lower, min(count, range.upperBound))

        attributed.transform(updating: &selection) { text in
            let start = text.index(text.startIndex, offsetByCharacters: lower)
            let end = text.index(text.startIndex, offsetByCharacters: upper)
            text.replaceSubrange(start..<end, with: replacement)
        }
        enforceInvariant()

        let caret = attributed.index(attributed.startIndex,
                                     offsetByCharacters: lower + replacement.characters.count)
        selection = AttributedTextSelection(insertionPoint: caret)
    }

    // MARK: Helpers

    /// (lowerOffset, upperOffset) for each mention span. The keyed view keeps a
    /// chip that an unrelated attribute has split reported as one span, so the
    /// trigger veto covers the whole chip rather than one fragment of it.
    private func mentionRuns() -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (mention, range) in attributed.runs[MentionAttribute.self] where mention != nil {
            let lower = attributed.characters.distance(from: attributed.startIndex,
                                                       to: range.lowerBound)
            let upper = attributed.characters.distance(from: attributed.startIndex,
                                                       to: range.upperBound)
            out.append((lower, upper))
        }
        return out
    }
}

#if DEBUG
extension ComposerText {
    /// Simulate a raw user edit: replace a character range and re-check the
    /// invariant, exactly as the text view's binding write does. Tests only.
    mutating func replaceForTesting(_ range: Range<Int>, with plain: String) {
        var selection = AttributedTextSelection(insertionPoint: attributed.startIndex)
        replace(range, with: AttributedString(plain), selection: &selection)
    }
}
#endif
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet \
  -only-testing:ZeronTests/ComposerTextTests
```

Expected: PASS, 18 tests.

If `testTextTypedAfterAChipDoesNotInheritTheAttribute` or the merge test behaves differently from the assertion, **do not weaken the test to match**. Check the Task 0 findings first: `inheritedByAddedText` and `invalidationConditions` are the two knobs that change this behavior, and the spike recorded what they actually do.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/Zeron/Composer/ComposerText.swift apps/ios/ZeronTests/ComposerTextTests.swift
git commit -m "ios: composer text model with mention chips and the round-trip invariant"
```

---

## Task 4: The two host RPCs

**Independent of Tasks 0-3. Can be built in parallel.**

**Files:**
- Modify: `apps/ios/Zeron/Models/Entities.swift` (append)
- Modify: `apps/ios/Zeron/Sync/DeviceRelayClient.swift:14-28` (extend `RelayError`)
- Modify: `apps/ios/Zeron/Sync/WorkspaceStore.swift:403-425` (add two methods next to `listModels`)

**Interfaces:**
- Consumes: `DeviceRelayClient.call`, `WorkspaceStore.relay(for:)`.
- Produces:
  - `struct SlashCommand: Decodable, Identifiable, Hashable { let name: String; let description: String; let inputHint: String? }`
  - `struct FileSearchMatch: Decodable, Identifiable, Hashable { let path: String; let isDir: Bool }`
  - `extension RelayError { func isUnknownMethod(_ method: String) -> Bool }`
  - `func listCommands(deviceId: String, harness: String, cwd: String?) async throws -> [SlashCommand]`
  - `func searchFiles(deviceId: String, chatId: String?, spaceId: String?, query: String) async throws -> [FileSearchMatch]`

There is no unit test here: both methods are thin wrappers over a live socket, and the repo has no relay test double. Task 5 tests the logic that sits on top of them, with these injected as closures.

- [ ] **Step 1: Add the two entity types**

Append to `apps/ios/Zeron/Models/Entities.swift`:

```swift
// MARK: - Composer autocomplete

/// One entry from `ListCommands`. Mirrors `SlashCommand`
/// (crates/proto/src/agent.rs:195). `description` is `#[serde(default)]` on the
/// Rust side and always serialized; `inputHint` is skipped when absent.
struct SlashCommand: Decodable, Identifiable, Hashable {
    let name: String
    let description: String
    let inputHint: String?

    var id: String { name }
}

/// One entry from `SearchFiles`. Mirrors `FileSearchMatch`
/// (crates/proto/src/entities.rs:299). Paths are relative to the search root
/// and already ranked and capped by the host (crates/engine/src/repos.rs:1082).
struct FileSearchMatch: Decodable, Identifiable, Hashable {
    let path: String
    let isDir: Bool

    var id: String { path }
}
```

- [ ] **Step 2: Add the version-skew helper**

Append to `apps/ios/Zeron/Sync/DeviceRelayClient.swift`, just after the `RelayError` enum ends (line 28):

```swift
extension RelayError {
    /// True when the host answered "no such method". The relay flattens the
    /// typed Rust error into a plain string (see `handleRpcPayload`), so this
    /// is the only signal on the wire. Matched exactly, not by prefix, the same
    /// way the desktop does it (crates/ui/src/state.rs:406-409).
    ///
    /// A helper rather than a `RelayError` case because `pending` holds only
    /// continuations and does not know which method a reply belongs to. The
    /// caller does.
    func isUnknownMethod(_ method: String) -> Bool {
        guard case .rpc(let message) = self else { return false }
        return message == "unknown method: \(method)"
    }
}
```

- [ ] **Step 3: Add the two calls**

Insert into `apps/ios/Zeron/Sync/WorkspaceStore.swift`, immediately after the existing `listModels` method (which ends around line 425). Match its surrounding style.

```swift
    /// Slash commands for one harness in one workspace. `cwd` is a path on the
    /// HOST device and travels unexpanded — the host expands `~`
    /// (crates/engine/src/commands.rs:109-117). Absent means the host's home,
    /// which is what an engine older than that field always answered.
    func listCommands(deviceId: String, harness: String,
                      cwd: String?) async throws -> [SlashCommand] {
        var params: [String: Any] = ["harness": harness]
        if let cwd, !cwd.isEmpty { params["cwd"] = cwd }
        return try await relay(for: deviceId).call(method: "ListCommands", params: params)
    }

    /// Fuzzy file search inside a chat's checkout or a space. The engine needs
    /// exactly one of `chatId` or `spaceId` (crates/engine/src/rpc.rs:484-493)
    /// and rejects a query longer than 256 characters (rpc.rs:1551). A `chatId`
    /// search only works on the device that owns the chat (rpc.rs:501-502), so
    /// dial the chat's host.
    func searchFiles(deviceId: String, chatId: String?, spaceId: String?,
                     query: String) async throws -> [FileSearchMatch] {
        // Truncate on UNICODE SCALARS, not Characters. The engine's cap is
        // `p.query.chars().count() > 256` (crates/engine/src/rpc.rs:1551), and a
        // Rust `char` is a scalar value, while Swift's `prefix` counts extended
        // grapheme clusters. One flag emoji is 1 Character but 2 scalars, so a
        // Character-based truncation is a no-op on input the engine then
        // rejects with BadParams.
        var params: [String: Any] = [
            "query": String(String.UnicodeScalarView(query.unicodeScalars.prefix(256)))
        ]
        if let chatId { params["chatId"] = chatId }
        if let spaceId { params["spaceId"] = spaceId }
        return try await relay(for: deviceId).call(method: "SearchFiles", params: params)
    }
```

- [ ] **Step 4: Build and confirm it compiles**

```bash
xcodebuild build -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: BUILD SUCCEEDED. If `relay(for:).call` cannot infer the return type, annotate the local: `let reply: [SlashCommand] = try await …; return reply`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/Zeron/Models/Entities.swift apps/ios/Zeron/Sync/DeviceRelayClient.swift apps/ios/Zeron/Sync/WorkspaceStore.swift
git commit -m "ios: ListCommands and SearchFiles over the device relay"
```

---

## Task 5: The suggestion store

**Depends on Task 1 and Task 4.**

**Files:**
- Create: `apps/ios/Zeron/Composer/ComposerSuggestions.swift`
- Test: `apps/ios/ZeronTests/ComposerSuggestionsTests.swift`

**Interfaces:**
- Consumes: `Trigger`, `TriggerKind`, `SlashCommand`, `FileSearchMatch`.
- Produces:
  - `struct SuggestionItem: Identifiable, Equatable { let id: String; let label: String; let detail: String; let payload: Payload }` with `enum Payload: Equatable { case command(String); case path(String, isDir: Bool) }`
  - `struct CommandKey: Hashable { let harness: String; let device: String; let cwd: String }`
  - `@Observable final class ComposerSuggestions`, with `var items: [SuggestionItem]`, `var isLoading: Bool`, `var errorText: String?`, `func update(trigger:context:) async`, `func dismiss(_ trigger: Trigger)`, and injectable `fetchCommands` / `fetchPaths` closures.

- [ ] **Step 1: Write the failing tests**

Create `apps/ios/ZeronTests/ComposerSuggestionsTests.swift`:

```swift
// The suggestion store. Both fetchers are injected closures so these run with
// no socket. The rules pinned here mirror the desktop composer: a cache key
// that includes the device (composer.rs:3236-3241), a dismissal that survives
// caret moves inside one token (composer.rs:3301-3304), and error text that is
// never rendered as "no results" (composer.rs:3296-3300).

import XCTest
@testable import Zeron

@MainActor
final class ComposerSuggestionsTests: XCTestCase {

    private let context = SuggestionContext(harness: "claude-code", deviceId: "dev-a",
                                            cwd: "~/proj", chatId: "chat-1", spaceId: nil)

    private func command(_ name: String) -> SlashCommand {
        SlashCommand(name: name, description: "does \(name)", inputHint: nil)
    }

    func testCommandsAreFetchedOnceAndServedFromCache() async {
        var calls = 0
        let store = ComposerSuggestions()
        store.fetchCommands = { _, _, _ in
            calls += 1
            return [self.command("tdd"), self.command("plan")]
        }

        await store.update(trigger: Trigger(kind: .command, query: "", token: "/", range: 0..<1),
                           context: context)
        XCTAssertEqual(store.items.map(\.label), ["/tdd", "/plan"])

        await store.update(trigger: Trigger(kind: .command, query: "t", token: "/t", range: 0..<2),
                           context: context)
        XCTAssertEqual(store.items.map(\.label), ["/tdd"])
        XCTAssertEqual(calls, 1, "a cached list must not re-fetch on every keystroke")
    }

    func testCommandCacheKeyIncludesTheDevice() async {
        var seen: [String] = []
        let store = ComposerSuggestions()
        store.fetchCommands = { _, device, _ in
            seen.append(device)
            return [self.command("tdd")]
        }
        let trigger = Trigger(kind: .command, query: "", token: "/", range: 0..<1)

        await store.update(trigger: trigger, context: context)
        var other = context
        other.deviceId = "dev-b"
        await store.update(trigger: trigger, context: other)

        XCTAssertEqual(seen, ["dev-a", "dev-b"],
                       "two devices share the path ~ for every project-less chat")
    }

    func testCommandFilterMatchesNameBeforeDescription() async {
        let store = ComposerSuggestions()
        store.fetchCommands = { _, _, _ in
            [SlashCommand(name: "plan", description: "no match", inputHint: nil),
             SlashCommand(name: "zzz", description: "make a plan", inputHint: nil)]
        }
        await store.update(trigger: Trigger(kind: .command, query: "plan", token: "/plan", range: 0..<5),
                           context: context)
        XCTAssertEqual(store.items.map(\.label), ["/plan", "/zzz"])
    }

    func testPathResultsKeepHostOrder() async {
        let store = ComposerSuggestions()
        store.fetchPaths = { _, _ in
            [FileSearchMatch(path: "z.rs", isDir: false),
             FileSearchMatch(path: "a.rs", isDir: false)]
        }
        await store.update(trigger: Trigger(kind: .path, query: "rs", token: "@rs", range: 0..<3),
                           context: context)
        XCTAssertEqual(store.items.map(\.label), ["z.rs", "a.rs"],
                       "the host already ranked these; do not re-sort")
    }

    func testAFailureShowsAnErrorNotAnEmptyList() async {
        let store = ComposerSuggestions()
        store.fetchPaths = { _, _ in throw RelayError.hostOffline }
        await store.update(trigger: Trigger(kind: .path, query: "a", token: "@a", range: 0..<2),
                           context: context)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.errorText, "The session's device is unreachable")
    }

    func testVersionSkewGetsItsOwnMessage() async {
        let store = ComposerSuggestions()
        store.fetchPaths = { _, _ in throw RelayError.rpc("unknown method: SearchFiles") }
        await store.update(trigger: Trigger(kind: .path, query: "a", token: "@a", range: 0..<2),
                           context: context)
        XCTAssertEqual(store.errorText,
                       "The session's device runs an older zeron — update it to search its files")
    }

    func testDismissSurvivesACaretMoveInsideTheSameToken() async {
        let store = ComposerSuggestions()
        store.fetchCommands = { _, _, _ in [self.command("tdd")] }
        let trigger = Trigger(kind: .command, query: "td", token: "/td", range: 0..<3)

        await store.update(trigger: trigger, context: context)
        store.dismiss(trigger)

        // Same token, caret moved back one: still dismissed. `query` changed
        // and `token` did not, which is exactly why the key is `token`.
        await store.update(trigger: Trigger(kind: .command, query: "t", token: "/td", range: 0..<3),
                           context: context)
        XCTAssertTrue(store.items.isEmpty)

        // A same-LENGTH edit: the span is unchanged but the token is not, so
        // this reopens. A range-only key would wrongly stay closed here. The
        // query still matches the fixture, so an empty list would mean the
        // dismissal held — not that the filter came up dry.
        await store.update(trigger: Trigger(kind: .command, query: "Td", token: "/Td", range: 0..<3),
                           context: context)
        XCTAssertEqual(store.items.map(\.label), ["/tdd"])
        store.dismiss(Trigger(kind: .command, query: "Td", token: "/Td", range: 0..<3))

        // The token grew: an edit reopens it.
        await store.update(trigger: Trigger(kind: .command, query: "tdd", token: "/tdd", range: 0..<4),
                           context: context)
        XCTAssertEqual(store.items.map(\.label), ["/tdd"])
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet \
  -only-testing:ZeronTests/ComposerSuggestionsTests
```

Expected: the build fails with "cannot find 'ComposerSuggestions' in scope".

- [ ] **Step 3: Implement**

Create `apps/ios/Zeron/Composer/ComposerSuggestions.swift`:

```swift
// Suggestion state for the composer popover: what to show, whether it is
// loading, and why it failed. Works on plain values only — no AttributedString
// — so it stays testable with no socket and no simulator UI.
//
// Freshness is stale-while-revalidate: a cached list draws at once and one
// request per popover open refreshes it. This type holds NO TTL. The engine's
// command cache owns expiry (crates/engine/src/commands.rs), so there is one
// expiry policy, in one place.

import Foundation

struct SuggestionItem: Identifiable, Equatable {
    enum Payload: Equatable {
        case command(String)
        case path(String, isDir: Bool)
    }

    let id: String
    let label: String
    let detail: String
    let payload: Payload
}

/// Everything the fetchers need that the trigger does not carry.
struct SuggestionContext: Equatable {
    var harness: String
    var deviceId: String
    /// A path on the HOST device. `~` travels unexpanded.
    var cwd: String
    var chatId: String?
    var spaceId: String?
}

/// Cache identity for one command list. The device belongs in the key because
/// every project-less chat, on every device, shares the path `~`
/// (crates/ui/src/composer.rs:3236-3241).
struct CommandKey: Hashable {
    let harness: String
    let device: String
    let cwd: String
}

@Observable
@MainActor
final class ComposerSuggestions {

    private(set) var items: [SuggestionItem] = []
    private(set) var isLoading = false
    private(set) var errorText: String?

    /// Injected so tests run with no socket. Wired to WorkspaceStore at the
    /// call site.
    var fetchCommands: (_ harness: String, _ device: String, _ cwd: String) async throws -> [SlashCommand] = { _, _, _ in [] }
    var fetchPaths: (_ context: SuggestionContext, _ query: String) async throws -> [FileSearchMatch] = { _, _ in [] }

    private var commandCache: [CommandKey: [SlashCommand]] = [:]
    /// The token the user closed the popover on: its span AND its full text.
    /// Keyed on both because a caret move inside a dismissed token must keep it
    /// closed, while any edit reopens it (composer.rs:3301-3304). The span alone
    /// would misread a same-length replacement as "unchanged"; the text alone
    /// would misread the same token typed twice.
    private var dismissed: (range: Range<Int>, token: String)?
    private var generation = 0

    func dismiss(_ trigger: Trigger) {
        dismissed = (trigger.range, trigger.token)
        items = []
        errorText = nil
        isLoading = false
    }

    func update(trigger: Trigger, context: SuggestionContext) async {
        if let dismissed, dismissed.range == trigger.range, dismissed.token == trigger.token {
            items = []
            // Clearing here matters: a superseded in-flight request returns at
            // its own generation guard WITHOUT touching isLoading (correctly —
            // it must not clobber a newer request's state), so any path that
            // ends a request synchronously has to clear the spinner itself.
            isLoading = false
            return
        }
        dismissed = nil

        generation += 1
        let mine = generation
        errorText = nil

        switch trigger.kind {
        case .command:
            await loadCommands(trigger: trigger, context: context, generation: mine)
        case .path:
            await loadPaths(trigger: trigger, context: context, generation: mine)
        }
    }

    // MARK: Commands

    private func loadCommands(trigger: Trigger, context: SuggestionContext,
                              generation mine: Int) async {
        let key = CommandKey(harness: context.harness, device: context.deviceId, cwd: context.cwd)

        if let cached = commandCache[key] {
            items = Self.filter(cached, query: trigger.query)
            // Same reason as the dismissed path: this ends the request without
            // ever awaiting, so it owns clearing the spinner. Omitting it strands
            // isLoading == true forever when this hit supersedes an in-flight miss.
            isLoading = false
            return
        }

        isLoading = true
        do {
            let fetched = try await fetchCommands(context.harness, context.deviceId, context.cwd)
            guard mine == generation else { return }
            commandCache[key] = fetched
            items = Self.filter(fetched, query: trigger.query)
        } catch {
            guard mine == generation else { return }
            items = []
            errorText = Self.commandError(error)
        }
        isLoading = false
    }

    /// Name matches first, then description matches. The host returns the full
    /// list, so filtering is the client's job.
    private static func filter(_ commands: [SlashCommand], query: String) -> [SuggestionItem] {
        let needle = query.lowercased()
        var byName: [SuggestionItem] = []
        var byDescription: [SuggestionItem] = []
        for command in commands {
            let item = SuggestionItem(id: "cmd:\(command.name)",
                                      label: "/\(command.name)",
                                      detail: command.description,
                                      payload: .command(command.name))
            if needle.isEmpty || command.name.lowercased().contains(needle) {
                byName.append(item)
            } else if command.description.lowercased().contains(needle) {
                byDescription.append(item)
            }
        }
        return byName + byDescription
    }

    // MARK: Paths

    private func loadPaths(trigger: Trigger, context: SuggestionContext,
                           generation mine: Int) async {
        isLoading = true
        do {
            let matches = try await fetchPaths(context, trigger.query)
            guard mine == generation else { return }
            // The host already ranked and capped these (repos.rs:1082).
            items = matches.map { match in
                SuggestionItem(id: "path:\(match.path)",
                               label: MentionLink.basename(of: match.path),
                               detail: Self.parentPath(match.path),
                               payload: .path(match.path, isDir: match.isDir))
            }
        } catch {
            guard mine == generation else { return }
            items = []
            errorText = Self.pathError(error)
        }
        isLoading = false
    }

    private static func parentPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    // MARK: Errors
    //
    // A failure must NEVER render as "no matching files": cross-device searches
    // fail for reasons the user can act on, and the empty state hid them
    // (crates/ui/src/composer.rs:3296-3300). These strings are verbatim from
    // the desktop (composer.rs:3311-3335).

    private static func pathError(_ error: Error) -> String {
        guard let relay = error as? RelayError else { return "File search failed" }
        if relay.isUnknownMethod("SearchFiles") {
            return "The session's device runs an older zeron — update it to search its files"
        }
        switch relay {
        case .notConnected, .hostOffline, .timeout:
            return "The session's device is unreachable"
        case .rpc:
            return "File search failed"
        }
    }

    private static func commandError(_ error: Error) -> String {
        guard let relay = error as? RelayError else { return "Couldn't load this agent's commands" }
        if relay.isUnknownMethod("ListCommands") {
            return "The session's device runs an older zeron — update it to list commands"
        }
        switch relay {
        case .notConnected, .hostOffline, .timeout:
            return "The session's device is unreachable"
        case .rpc:
            return "Couldn't load this agent's commands"
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet \
  -only-testing:ZeronTests/ComposerSuggestionsTests
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/Zeron/Composer/ComposerSuggestions.swift apps/ios/ZeronTests/ComposerSuggestionsTests.swift
git commit -m "ios: composer suggestion cache, ranking, and error copy"
```

---

## Task 6: The popover

**Depends on Task 5.**

**Files:**
- Create: `apps/ios/Zeron/Composer/ComposerPopover.swift`

**Interfaces:**
- Consumes: `SuggestionItem`, `TriggerKind`.
- Produces: `struct ComposerPopover: View`, initialized as `ComposerPopover(items:kind:isLoading:errorText:onPick:)`.

No unit test: this is presentation only, and the repo has no SwiftUI view tests. Task 9's manual pass covers it.

- [ ] **Step 1: Implement**

Create `apps/ios/Zeron/Composer/ComposerPopover.swift`:

```swift
// The suggestion list that floats above the composer pill. Presentation only:
// it takes values and hands back a pick. Matching the app's glass language, it
// reuses Theme and the same rounded-surface treatment as ComposerShell.

import SwiftUI

struct ComposerPopover: View {

    let items: [SuggestionItem]
    let kind: TriggerKind
    let isLoading: Bool
    let errorText: String?
    let onPick: (SuggestionItem) -> Void

    private var surfaceShape: RoundedRectangle { RoundedRectangle(cornerRadius: 16) }

    private var header: String {
        switch kind {
        case .command: "Commands"
        case .path: "Files"
        }
    }

    private var emptyText: String {
        if let errorText { return errorText }
        if isLoading { return kind == .path ? "Searching files…" : "Loading…" }
        switch kind {
        case .command: return "No matching commands."
        case .path: return "No matching files or folders."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header.uppercased())
                .font(Theme.sans(10, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            if items.isEmpty {
                Text(emptyText)
                    .font(Theme.sans(12))
                    .foregroundStyle(errorText == nil ? Theme.textFaint : Theme.danger)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, isLast: index == items.count - 1)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(whiteAlpha(0.04), in: surfaceShape)
        .glassEffect(.regular, in: surfaceShape)
        .overlay(surfaceShape.strokeBorder(whiteAlpha(0.05), lineWidth: 1))
    }

    private func row(_ item: SuggestionItem, isLast: Bool) -> some View {
        Button {
            onPick(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: item))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 16)
                Text(item.label)
                    .font(Theme.sans(15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(whiteAlpha(0.06)).frame(height: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func icon(for item: SuggestionItem) -> String {
        switch item.payload {
        case .command: "terminal"
        case .path(_, let isDir): isDir ? "folder" : "doc"
        }
    }
}
```

- [ ] **Step 2: Build and confirm it compiles**

```bash
xcodebuild build -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: BUILD SUCCEEDED. If `Theme.textFaint`, `Theme.danger`, or `whiteAlpha` do not resolve, open `apps/ios/Zeron/Theme/Theme.swift` and use the names that exist there. Do not invent new theme tokens.

- [ ] **Step 3: Commit**

```bash
git add apps/ios/Zeron/Composer/ComposerPopover.swift
git commit -m "ios: composer suggestion popover"
```

---

## Task 7: Swap the composer to a rich text editor

**Depends on Task 0 (go) and Task 3. This is the highest-risk task; it changes a control with hard-won behavior.**

**Files:**
- Modify: `apps/ios/Zeron/Composer/ComposerView.swift:16-200` (`ComposerShell`)

Read the comments at lines 39-48, 55-58, and 120-129 before editing. Each records a bug that was fixed once. Do not delete them; carry them forward.

- [ ] **Step 1: Change the binding and the input control**

In `ComposerShell`, replace line 17:

```swift
    @Binding var draft: ComposerText
```

Add `selection` immediately after `draft`, NOT next to `@FocusState private var focused`.

`chips` is a `@ViewBuilder` property and is passed as a trailing closure at both call sites.
Property order fixes the memberwise initializer's parameter order, so any stored property
declared after `chips` would have to be passed *after* a trailing closure — which Swift does
not allow. Declaring `selection` late compiles here and then makes Task 8's call sites
unwritable.

`measuredHeight` is `@State`, not a parameter, so its placement is free; keep it with the
other private state.

```swift
    @Binding var draft: ComposerText
    @Binding var selection: AttributedTextSelection
```

```swift
    @State private var measuredHeight: CGFloat = 22
```

Replace the `expanded` computed property (line 44-47) so it reads the plain projection:

```swift
    private var expanded: Bool {
        alwaysExpanded || keepExpanded || focused || !attachments.isEmpty
            || draft.plainText.contains("\n") || draft.plainText.count > 26
    }
```

Replace `hasContent` (line 158-160):

```swift
    private var hasContent: Bool {
        !draft.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }
```

Replace the `input` property (lines 132-139) with:

```swift
    // TextEditor, not TextField: only the AttributedString overload can carry
    // mention chips (iOS 26+). It gives up three things TextField had, so each
    // is rebuilt here: the placeholder is an overlay, the 1...7 line limit is
    // an explicit height range, and the opaque background is hidden so the
    // glass shows through.
    private var input: some View {
        TextEditor(text: editorText, selection: $selection)
            .font(Theme.sans(16))
            .foregroundStyle(Theme.text)
            .tint(Theme.text)
            .attributedTextFormattingDefinition(MentionFormatting())
            .scrollContentBackground(.hidden)
            .frame(height: clampedHeight)
            .scrollDisabled(measuredHeight <= lineHeight * 7)
            .focused($focused)
            .background(alignment: .topLeading) { heightMirror }
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(placeholder)
                        .font(Theme.sans(16))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.leading, 4)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
    }

    /// One line of the composer font, used to bound the editor's growth the way
    /// `lineLimit(1...7)` used to.
    private var lineHeight: CGFloat { 22 }

    private var clampedHeight: CGFloat {
        min(max(measuredHeight, lineHeight), lineHeight * 7)
    }

    /// Height measurement, taken from a hidden `Text` MIRROR rather than from
    /// the editor's own content size.
    ///
    /// This distinction is the whole point. The editor's content height depends
    /// on the frame we set from it, so reading one to set the other makes them
    /// chase each other — the oscillation this file's own comments already warn
    /// about. A mirror's height depends only on the text and the available
    /// width, never on the frame we apply to the editor, so the loop is broken.
    ///
    /// It is also what solves WRAPPING. The Task 0 spike verified 1-to-7 growth
    /// from hard newlines only and left wrapped growth unsolved. `Text` wraps at
    /// the same width with the same font, so its height IS the wrapped height.
    ///
    /// Known imprecision, in the safe direction: chips render at mono 15 in the
    /// editor while the mirror measures everything at 16, so a chip-heavy line
    /// is over-measured slightly. Over-measuring adds a hair of padding; the
    /// opposite would clip the last line.
    private var heightMirror: some View {
        Text(draft.plainText.isEmpty ? " " : draft.plainText)
            .font(Theme.sans(16))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 8)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                measuredHeight = height
            }
    }

    /// THE ONLY PATH USER TYPING TAKES. `ComposerText.apply(…)` enforces the
    /// invariant for programmatic picks, but a keystroke never goes through it
    /// — the text view writes straight to the binding. Without this setter, a
    /// chip typed into would keep its attribute on device while the unit tests
    /// still passed, because those drive `apply` instead.
    ///
    /// Enforcing here rather than in an `.onChange` is deliberate: mutating the
    /// binding from inside its own change notification is the re-entrancy the
    /// `clearDraft` comment warns about. The pass settles in one step — a run
    /// that has already lost its attribute is no longer a mention run, so a
    /// second pass finds nothing to strip.
    private var editorText: Binding<AttributedString> {
        Binding(
            get: { draft.attributed },
            set: { next in
                var updated = draft
                updated.attributed = next
                updated.enforceInvariant()
                draft = updated
            }
        )
    }
```

- [ ] **Step 2: Build and confirm it fails at the call sites**

```bash
xcodebuild build -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: FAIL, with type errors at `ComposerView.swift:250` and `NewSessionView.swift:222`. Task 8 fixes both.

- [ ] **Step 3: Commit the shell change**

```bash
git add apps/ios/Zeron/Composer/ComposerView.swift
git commit -m "ios: composer shell takes rich text and a selection binding"
```

Committing a non-building tree is deliberate here: Task 8 is the other half of one change, and splitting them keeps each diff reviewable. Do not push between the two.

---

## Task 8: Wire the popover and the send path

**Depends on Tasks 3, 4, 5, 6, and 7.**

**Files:**
- Modify: `apps/ios/Zeron/Composer/ComposerView.swift:206-405` (`ComposerView`)
- Modify: `apps/ios/Zeron/Views/NewSessionView.swift:21,200,221-230,347,368,415`

- [ ] **Step 1: Update `ComposerView`'s state**

Replace line 212:

```swift
    @State private var text = ComposerText()
    @State private var selection = AttributedTextSelection()
    @State private var suggestions = ComposerSuggestions()
```

- [ ] **Step 2: Wire the fetchers and the popover**

In `ComposerView.body`, wrap the existing `ComposerShell(...)` call in a `ZStack(alignment: .bottom)` overlay so the popover floats above the pill. Add `selection: $selection` to the `ComposerShell` call and change `draft: $text` to stay as-is (the type changed under it).

Add this above the `ComposerShell` call inside the enclosing `VStack`:

```swift
            // `isLoading` belongs in this gate. Without it, a first query against
            // a cold cache has no items and no error, so the popover stays hidden
            // and ComposerPopover's "Loading…" / "Searching files…" states are
            // unreachable — the user gets no feedback at all while the host is
            // being asked.
            if let trigger = text.trigger(at: selection),
               !suggestions.items.isEmpty || suggestions.errorText != nil || suggestions.isLoading {
                ComposerPopover(items: suggestions.items,
                                kind: trigger.kind,
                                isLoading: suggestions.isLoading,
                                errorText: suggestions.errorText) { item in
                    pick(item, over: trigger.range)
                }
                // 10, not 16: ComposerShell narrows its own margins to 10 while
                // focused (ComposerView.swift:68), and the popover only ever shows
                // while focused. 16 would leave its edges visibly inset from the
                // pill directly beneath it.
                .padding(.horizontal, 10)
                .transition(.opacity)
            }
```

Add these methods to `ComposerView`:

```swift
    /// Everything the fetchers need. The chat's own device hosts the run, so it
    /// is the device to dial: a `chatId` search only works there
    /// (crates/engine/src/rpc.rs:501-502).
    private var suggestionContext: SuggestionContext? {
        guard let space = model.space(for: chat) else { return nil }
        return SuggestionContext(harness: harness,
                                 deviceId: space.deviceId,
                                 cwd: chat.cwd ?? space.path,
                                 chatId: chat.id,
                                 spaceId: nil)
    }

    private func pick(_ item: SuggestionItem, over range: Range<Int>) {
        switch item.payload {
        case .command(let name):
            text.apply(command: name, over: range, selection: &selection)
        case .path(let path, let isDir):
            text.apply(path: path, isDir: isDir, over: range, selection: &selection)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func refreshSuggestions() async {
        guard let context = suggestionContext,
              let trigger = text.trigger(at: selection) else { return }
        await suggestions.update(trigger: trigger, context: context)
    }
```

Wire the fetchers once, in the existing `.task(id:)` modifier at line 305:

```swift
        .task(id: "\(chat.id)/\(harness)") {
            guard let space = model.space(for: chat) else { return }
            catalogs[harness] = await model.listModels(space: space, harness: harness)
            // AppModel.workspace is Optional (AppModel.swift:21): signed out or
            // in demo mode there is no store, and so no suggestions.
            suggestions.fetchCommands = { [weak model] harness, device, cwd in
                guard let store = model?.workspace else { return [] }
                return try await store.listCommands(deviceId: device, harness: harness, cwd: cwd)
            }
            suggestions.fetchPaths = { [weak model] context, query in
                guard let store = model?.workspace else { return [] }
                return try await store.searchFiles(deviceId: context.deviceId,
                                                   chatId: context.chatId,
                                                   spaceId: context.spaceId,
                                                   query: query)
            }
        }
```

Add the refresh trigger next to the other modifiers:

```swift
        .onChange(of: text) { _, _ in Task { await refreshSuggestions() } }
        .onChange(of: selection) { _, _ in Task { await refreshSuggestions() } }
```

`AttributedTextSelection` is `Equatable` (`SwiftUI.swiftinterface:14628`), so `.onChange(of: selection)` compiles. If the `[weak model]` capture fights strict concurrency, capture the `WorkspaceStore` itself instead — it is already resolved inside this `.task`.

- [ ] **Step 3: Update the send path**

Replace the body of `send()` (line 348) where it reads the draft. The serialized Markdown is what the host receives:

```swift
        let prompt = text.markdown().trimmingCharacters(in: .whitespacesAndNewlines)
```

Use `prompt` everywhere the old `text` string was used inside `send()` and `deliver(content:paths:)`.

Replace `clearDraft()` (line 392), keeping its comment verbatim:

```swift
    private func clearDraft() {
        text.clear(selection: &selection)
        // The clear above is unconditional, so a prompt left sitting in the
        // composer after a successful send is not this path failing to run —
        // it is the text view writing the pre-send string back. A focused
        // multiline editor commits pending autocorrect/marked text through
        // the binding AFTER a programmatic change, which restores the prompt.
        // Re-clear once that has drained; a keystroke can't land inside the
        // same main-actor turn, so this can never eat real input.
        Task { @MainActor in text.clear(selection: &selection) }
    }
```

- [ ] **Step 4: Update `NewSessionView`**

- Line 21: `@State private var draft = ComposerText()`, and add `@State private var selection = AttributedTextSelection()`.
- Line 200: `draft = ComposerText("Sketch the plan for porting the diff pane.")`
- Line 222: add `selection: $selection` to the `ComposerShell` call.
- Line 347: `!draft.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`
- Line 368: `let prompt = draft.markdown().trimmingCharacters(in: .whitespacesAndNewlines)`
- Line 415: `draft.clear(selection: &selection)`

This view has no chat yet, so it gets no popover in this task. The `@` and `/` triggers there are a follow-up.

- [ ] **Step 5: Make the sent mention inert in the transcript**

A sent mention reaches the transcript as an ordinary Markdown link, and `MarkdownModel.swift:152` already parses it. `MarkdownBlockView.swift:59` then hands the destination to `URL(string:)`, so tapping a chip would send `zeron-file:src/a.rs` to `openURL`, which nothing handles.

In `apps/ios/Zeron/Markdown/MarkdownBlockView.swift`, replace the link branch at lines 56-62:

```swift
            if let link = run.style.link {
                // Monochrome links: primary text + muted hairline underline,
                // never accent (desktop render.rs:536).
                // A zeron-file: mention is styled like a link but carries no
                // destination: the scheme is private to the UI, and openURL
                // has no handler for it. Desktop renders these as chips
                // (transcript.rs:671); that is a follow-up here.
                if !link.hasPrefix(MentionLink.scheme) {
                    piece.link = URL(string: link)
                }
                piece.foregroundColor = baseColor
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.textMuted)
            }
```

- [ ] **Step 6: Build and run the whole test suite**

```bash
xcodebuild test -project apps/ios/Zeron.xcodeproj -scheme Zeron \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: BUILD SUCCEEDED and every test passes, including the four pre-existing test files.

- [ ] **Step 7: Commit**

```bash
git add apps/ios/Zeron/Composer/ComposerView.swift apps/ios/Zeron/Views/NewSessionView.swift apps/ios/Zeron/Markdown/MarkdownBlockView.swift
git commit -m "ios: wire composer autocomplete into the live chat composer"
```

---

## Task 9: Manual end-to-end pass

**Depends on Task 8. Needs a real host device running zeron on branch `mine` (or later), signed in to the same account as the simulator.**

No code. This is the gate before the work is called done.

- [ ] **Step 1: Confirm the host is on a build with the per-workspace command cache**

```bash
git log --oneline -1 6c78309 94f117e
```

Both must be reachable from the host's build. Without them the host answers with its `$HOME` command list and project skills will be missing — which is a correct result, not a bug in this work.

- [ ] **Step 2: Slash commands**

- Open a chat in a project that has skills in `<repo>/.claude/skills`. Type `/`. **Expect** the project's skills in the list.
- Open a chat in a project without them. Type `/`. **Expect** them absent.
- Type `/goal ship it`. **Expect** the popover to close once the caret passes the space.
- Type `hi /td`. **Expect** no popover: a slash command is a whole-prompt prefix.

- [ ] **Step 3: File mentions**

- Type `@`, then a few letters. **Expect** a ranked file list.
- Pick one. **Expect** a chip reading `@name` in the mono font over the code wash, followed by a space.
- Send. **Expect** the host to receive `[name](zeron-file:relative/path)`.
- **Expect** the sent message to render as an underlined basename in the iOS transcript. Tap it. **Expect** nothing to happen.

- [ ] **Step 4: The invariant, by hand**

- Type a character inside a chip. **Expect** the chip to turn into plain text on that keystroke.
- Backspace once at a chip's trailing edge. **Expect** the same.
- Type `[` before a chip. **Expect** the chip to turn into plain text.
- Tap inside an intact chip. **Expect** no popover.

- [ ] **Step 5: The composer still looks and behaves right**

Be picky here. Compare against `main` side by side if anything feels off.

- The 1-to-7 line growth, and the scroll past 7.
- The `"Message"` placeholder: present when empty, gone on the first character, correctly positioned.
- The collapsed-to-expanded morph, and that keyboard focus survives it.
- Tapping anywhere on the glass focuses the editor, including the padding.
- The glass surface: no opaque rectangle behind the text.
- Send, then confirm the composer clears and stays clear.

- [ ] **Step 6: Failure states**

- Put the host device to sleep, then type `@a`. **Expect** "The session's device is unreachable", not "No matching files or folders."

- [ ] **Step 7: Record the results**

Write pass or fail against each check above into this file, under this task. Anything that fails becomes a fix commit before the branch is called done.

---

## Notes for the executor

- **Task 0 is a gate, not a formality.** If it says no-go, stop and report rather than pushing through. Tasks 1, 2, 4, 5, and 6 are still worth shipping on their own.
- **Tasks 1, 2, and 4 have no dependency on the spike** and can be done first, in any order, while the spike question is open.
- **Never edit `project.pbxproj`.** Both groups are filesystem-synchronized.
- **The Rust is the specification** for Tasks 1 and 2. When a Swift test disagrees with `crates/ui/src/composer.rs`, the Rust wins.
- **Do not weaken a test to make it pass.** If behavior differs from an assertion, the Task 0 findings are the first place to look.
