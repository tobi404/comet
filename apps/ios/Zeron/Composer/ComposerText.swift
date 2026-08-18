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
        for (lower, upper, _) in mentionRuns() where range.lowerBound < upper && lower < range.upperBound {
            return true
        }
        return false
    }

    // MARK: Serialization

    /// The draft as the host sees it. Non-mention runs pass through; each
    /// mention run becomes the canonical link built from its ATTRIBUTE.
    func markdown() -> String {
        var out = ""
        for run in attributed.runs {
            if let mention = run[MentionAttribute.self] {
                out += MentionLink.serialize(path: mention.path, isDir: mention.isDir)
            } else {
                out += String(attributed[run.range].characters)
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

        for run in attributed.runs {
            let visible = String(attributed[run.range].characters)
            guard let mention = run[MentionAttribute.self] else {
                offset += visible.count
                continue
            }

            let link = MentionLink.serialize(path: mention.path, isDir: mention.isDir)
            let clauseOne = visible == "@" + MentionLink.basename(of: mention.path)
            let clauseTwo = parsed.contains {
                $0.range == offset..<(offset + link.count)
                    && $0.path == mention.path
                    && $0.isDir == mention.isDir
            }
            if !clauseOne || !clauseTwo {
                doomed.append(run.range)
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

    /// Every text mutation goes through here so the selection survives the edit
    /// and the invariant is re-checked exactly once per change.
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

    /// (lowerOffset, upperOffset, value) for each attributed mention run.
    private func mentionRuns() -> [(Int, Int, MentionValue)] {
        var out: [(Int, Int, MentionValue)] = []
        for run in attributed.runs {
            guard let mention = run[MentionAttribute.self] else { continue }
            let lower = attributed.characters.distance(from: attributed.startIndex,
                                                       to: run.range.lowerBound)
            let upper = attributed.characters.distance(from: attributed.startIndex,
                                                       to: run.range.upperBound)
            out.append((lower, upper, mention))
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
