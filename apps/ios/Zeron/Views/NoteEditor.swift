// The Note Editor — spec §7, and §8's one clamp rule.
//
// The phone authors notes here: a bottom sheet sized to its own content,
// holding a capped text field and the five Colour Slots as dots. Cancel and
// Save sit in the nav bar; Return saves; a swipe down discards.
//
// **The field is a `UIViewRepresentable` around `UITextView`, and this is not
// a preference.** SwiftUI offers no character cap and no view of the input
// method at all — a verified absence, not an omission. Every SwiftUI hook
// runs AFTER the edit lands; `shouldChangeTextInRanges` runs BEFORE it, which
// is the whole difference. This makes the field the app's first
// `UIViewRepresentable` and leaves the app with two text-editing stacks. That
// cost is accepted and recorded in spec §10, limit 13: the composer's
// placeholder overlay, its hidden-`Text` height mirror and its
// `.scrollContentBackground(.hidden)` are all `TextEditor`-shaped and none of
// them port.
//
// Five traps live in this file, and every one of them compiles clean. Each is
// documented where it is implemented.

import SwiftUI

// MARK: - The numbers, and the rules built from them

/// Every measured number the Note Editor is built from (§7), and the two
/// rules that are arithmetic rather than constants: the field's clamped
/// height and the sheet's detent.
///
/// A pure enum with no view in it, because §9's tests 35 and 36 assert the
/// rules directly.
enum NoteEditorMetrics {
    /// **280 characters**, and on this platform it is the only cap there is:
    /// the phone writes registry rows directly, with no engine below it. Every
    /// other iOS surface therefore tolerates any stored length by eliding
    /// (§5's clamp), because storage cannot promise a short note.
    static let cap = 280

    /// The counter appears here and not before. Verified at its real
    /// thresholds: absent at 239, muted at 245, full at 280.
    static let counterFrom = 240

    /// Matching `SheetSelectRow`'s title, so the field reads as the app's own.
    static let fontSize: CGFloat = 15

    static let insetV: CGFloat = 10
    static let insetH: CGFloat = 12

    /// The field floors at three wrapped lines and grows to six, then
    /// scrolls — **both as heights**, per §8's one rule.
    static let floorLines = 3
    static let ceilingLines = 6

    /// The slot row: five 18pt dots in 44pt hit targets, 6pt apart. The
    /// desktop's 14px dot does not port and its 24px target certainly does
    /// not — 24 is under the phone's 44pt minimum.
    static let dot: CGFloat = 18
    static let hitTarget: CGFloat = 44
    static let cellSpacing: CGFloat = 6

    /// The ring is held one cell out from the **dot**, not from the 44pt
    /// target: at 44 it becomes a hoop with the dot rattling inside it.
    static let ringGap: CGFloat = 4
    static let ringWidth: CGFloat = 1
    static let ringOpacity: Double = 0.85
    static var ringDiameter: CGFloat { dot + 2 * ringGap }

    /// The sheet's own padding, and the gap between the field and the slots.
    static let contentPadding: CGFloat = 20
    static let fieldSlotGap: CGFloat = 14

    /// **The nav bar, the grabber above it, and the room under the content —
    /// measured off the frames, not derived.** Re-check it if the nav bar
    /// changes.
    ///
    /// **§7 quotes 60 and this build measures 41.** The number was re-derived
    /// the way §7 says to, on an iPhone 17 Pro at iOS 26.5, by sweeping it and
    /// reading the gap between the slot row's bottom padding and the sheet's
    /// own bottom edge off the frames:
    ///
    ///     chrome 60 → sheet 254.3pt, 17.5pt of void under the content
    ///     chrome 41 → sheet 236.0pt, 0.5pt
    ///     chrome 20 → sheet 216.0pt, content short of the sheet by 20pt
    ///
    /// The relationship is additive in the content height, so one number
    /// holds from the floor to the ceiling. iOS 26 presents the sheet inset
    /// from the screen edges — 386pt wide inside 402 — and scales its content
    /// by that ratio, which is why the sweep is off the rendered frames and
    /// not off the layout's own arithmetic.
    static let chrome: CGFloat = 41

    // MARK: The field's floor and ceiling

    /// The field's font at the **default** text size. The floor and ceiling
    /// are fixed at what their line counts occupy here, whatever the user's
    /// text size is (§8's one rule); the painted font scales, these do not.
    static var measuringFont: UIFont {
        Theme.sansScaledUI(fontSize, category: .large)
    }

    /// **The floor and ceiling must be MEASURED, not multiplied.** This lays
    /// out a probe of n lines in the same font and asks the text system what
    /// it took (test 35).
    ///
    /// §7 gives the reason as `font.lineHeight * n` under-counting, because
    /// TextKit's line fragment is slightly taller. **On Geist at 15pt the two
    /// happen to coincide** — the fragment is 19.5pt and so is
    /// `font.lineHeight` — so that particular clip is not reachable here
    /// today. The measurement stays the rule anyway: it holds for a font whose
    /// leading is not zero, and it is what test 35 pins against the field's
    /// own layout rather than against an assumed constant.
    ///
    /// Rounded up, so a fractional line box cannot clip its last line. The
    /// cost is at most a point of container — the same trade `NoteCardMetrics`
    /// makes.
    static func linesHeight(_ lines: Int) -> CGFloat {
        let probe = Array(repeating: "A", count: max(1, lines)).joined(separator: "\n")
        return NSAttributedString(string: probe, attributes: [.font: measuringFont])
            .boundingRect(
                with: CGSize(width: 10_000, height: 100_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            .height.rounded(.up)
    }

    /// Three laid-out lines plus the text container inset, both edges.
    static var floorHeight: CGFloat { linesHeight(floorLines) + 2 * insetV }

    /// Six, and past it the field scrolls rather than growing. **This is what
    /// keeps the sheet usable**: as a scaled line count the ceiling reaches a
    /// sheet top of 57pt at AX-XXXL, where the fitted detent has silently
    /// become `.large` and the Colour Slots sit behind the keyboard where they
    /// cannot be reached at all.
    static var ceilingHeight: CGFloat { linesHeight(ceilingLines) + 2 * insetV }

    /// The field's height: what its content wants, held between the two.
    static func fieldHeight(content: CGFloat) -> CGFloat {
        min(max(content, floorHeight), ceilingHeight)
    }

    // MARK: The detent

    /// The sheet's content: padding, field, gap, slot row.
    ///
    /// **Measured, and it lands 4pt above §7's estimate.** §7 quotes about
    /// 173pt for a bare note and about 230pt at the ceiling, on a field of
    /// 75pt and a line of about 18.3pt. Geist's line is 19.5pt, so this reads
    /// 177pt and 235pt. The spec makes the detent arithmetic rather than a
    /// number precisely so the drift lands here and not in a clipped sheet.
    static func contentHeight(fieldHeight: CGFloat) -> CGFloat {
        2 * contentPadding + fieldHeight + fieldSlotGap + hitTarget
    }

    /// **`detent = content height + chrome`, and `.medium` is refused on a
    /// measurement rather than on taste**: with the keyboard up it swells to
    /// near-full-screen and leaves roughly 470pt of empty container between
    /// the slot row and the keyboard. A pinned 280pt was the first fix and is
    /// still wrong on a long note (test 36).
    static func detentHeight(fieldHeight: CGFloat) -> CGFloat {
        contentHeight(fieldHeight: fieldHeight) + chrome
    }
}

// MARK: - The cap

/// The clamp, and the two traps that live inside it.
///
/// Split out from the representable so §9's tests 29-33 can drive it the way
/// UIKit does — the delegate is not called by programmatic mutation, so a test
/// that sets `textView.text` proves nothing about the cap.
final class NoteFieldCoordinator: NSObject, UITextViewDelegate {
    /// The edited text, back to SwiftUI.
    var onChange: (String) -> Void = { _ in }
    /// Return. **The newline is refused before it lands.**
    var onSubmit: () -> Void = {}

    /// The last height `sizeThatFits` reported, so the sheet is told about a
    /// change and not about every layout pass.
    var reportedHeight: CGFloat = -1

    // MARK: The pre-edit hook

    /// **The Swift label is `shouldChangeTextInRanges`, and the obvious
    /// spelling silently does nothing.** Swift keeps "Ranges" on the plural so
    /// it does not collide with the singular. Writing
    /// `shouldChangeTextIn ranges: [NSValue]` — which is what the singular's
    /// label looks like — compiles, satisfies no protocol requirement, exports
    /// no selector, and never fires. There is no warning. The cap then holds
    /// only from `textViewDidChange`, which draws the over-cap character and
    /// takes it back, so the failure looks like a design flaw rather than a
    /// typo. **Test 29 is the only test that catches this**, and it catches it
    /// by asking the ObjC runtime for the selector.
    ///
    /// Only the plural is implemented: the target is iOS 26.0, so the
    /// soft-deprecated singular is never needed.
    func textView(
        _ textView: UITextView,
        shouldChangeTextInRanges ranges: [NSValue],
        replacementText text: String
    ) -> Bool {
        // **Return saves and dismisses**, and the price is that the phone
        // cannot author a newline. A multi-line note written on the desktop
        // loads, edits and saves back intact — this refuses only the Return
        // key, never a newline arriving inside a paste.
        if text == "\n" {
            onSubmit()
            return false
        }

        // **Stand down while text is marked.** Every keystroke of a Japanese
        // composition arrives with `markedTextRange` non-nil, and composition
        // CAN exceed the cap — four marked kana against a cap of three,
        // counter reading 4/3. Cutting here would fight the input method; the
        // `textViewDidChange` floor cuts the commit instead (test 33).
        guard textView.markedTextRange == nil else { return true }

        let current = textView.text ?? ""

        // **Room is measured AFTER the deletion.** The plural signature hands
        // this over for free: it passes the ranges to be deleted alongside the
        // text to insert, so a field already at 280 still accepts a paste over
        // a selection (test 32).
        //
        // **Characters, not bytes.** Grapheme-cluster counting is free inside
        // `String` space and stops being free at the `NSRange` to
        // `Range<String.Index>` conversion, which is where it earns test 31.
        let deleted = ranges.reduce(0) { $0 + characterCount(of: $1.rangeValue, in: current) }
        let room = NoteEditorMetrics.cap - (current.count - deleted)
        if text.count <= room { return true }

        // Over the cap. **The clamp refuses rather than trims after the fact —
        // the over-cap character is never drawn** (test 29). So the delegate
        // applies the shortened edit itself and returns false, instead of
        // letting the whole edit land and taking a character back.
        //
        // The exotic multi-range case is refused outright rather than
        // half-applied: UIKit replaces one range and deletes the rest, and
        // choosing which one on the app's behalf would be a guess.
        guard room > 0, ranges.count == 1, let range = ranges.first?.rangeValue,
              let uiRange = textView.uiRange(range)
        else { return false }

        // `String.prefix(_:)` counts grapheme clusters, so **the cut lands on
        // a character boundary** and a split grapheme is impossible. That is
        // why §9 carries it as this comment rather than as a test.
        let clipped = String(text.prefix(room))
        textView.replace(uiRange, withText: clipped)

        // **A clamped edit leaves the caret at offset 0 of what it wrote, and
        // the restore must be deferred one run loop.** "The caret never has to
        // be restored" holds only for an edit the delegate PERMITS — UIKit
        // applies it and moves the caret. On this path the delegate applies
        // the edit itself, and `replace(_:withText:)` leaves the caret before
        // the first character, so a 300-character paste clamped to the cap
        // ends at offset 0. Setting `selectedRange` inline reads back
        // correctly and is then dragged back to 0 by the SwiftUI round trip;
        // posting it to the next run loop holds (test 30).
        let caret = range.location + (clipped as NSString).length
        DispatchQueue.main.async {
            textView.selectedRange = NSRange(location: caret, length: 0)
        }
        return false
    }

    // MARK: The floor under it

    /// **The second clamp, and it is the floor rather than the mechanism.**
    /// The pre-edit hook stands down while text is marked, so an input-method
    /// commit is the one path that can land over the cap. This cuts it, and
    /// only once the composition is over — cutting mid-composition would
    /// fight the input method the stand-down exists to leave alone.
    func textViewDidChange(_ textView: UITextView) {
        let text = textView.text ?? ""
        if textView.markedTextRange == nil, text.count > NoteEditorMetrics.cap {
            textView.text = String(text.prefix(NoteEditorMetrics.cap))
        }
        // Reported even while marked, so the counter reads what the field
        // holds rather than what it will hold.
        onChange(textView.text ?? "")
    }

    /// The characters a UTF-16 `NSRange` covers, in grapheme clusters.
    ///
    /// The one place the character/byte distinction stops being free: an
    /// `NSRange` is UTF-16 and `String.count` is not, so an emoji selection
    /// counted in UTF-16 units would over-report the room a deletion makes.
    private func characterCount(of range: NSRange, in text: String) -> Int {
        guard let swift = Range(range, in: text) else { return 0 }
        return text.distance(from: swift.lowerBound, to: swift.upperBound)
    }
}

extension UITextView {
    /// A `UITextRange` for a UTF-16 `NSRange`. There is no public converter,
    /// and `replace(_:withText:)` takes nothing else.
    func uiRange(_ range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length)
        else { return nil }
        return textRange(from: start, to: end)
    }
}

// MARK: - The field

/// The app's **first** `UIViewRepresentable`, and §7 names the reason: no
/// SwiftUI path can hold the cap without fighting the input method.
///
/// The representable carries this app's glass, so the `TextEditor` fallback is
/// not taken — inside `SheetCard` it is indistinguishable from the composer's
/// `TextEditor` at rest.
struct NoteTextField: UIViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    /// The field's own height, back to the sheet, so the detent can be sized
    /// to it. Reported from `sizeThatFits` because that is the only place the
    /// proposed width is known.
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> NoteFieldCoordinator { NoteFieldCoordinator() }

    func makeUIView(context: Context) -> NoteUITextView {
        let view = NoteUITextView()
        view.delegate = context.coordinator
        view.text = text
        view.refreshPlaceholder()
        return view
    }

    func updateUIView(_ uiView: NoteUITextView, context: Context) {
        context.coordinator.onChange = { text = $0 }
        context.coordinator.onSubmit = onSubmit
        // **Guarded on both halves.** Re-setting the text unconditionally
        // resets the selection, which is exactly what drags the clamped
        // path's caret back to 0; re-setting it mid-composition clobbers the
        // input method's own in-flight text.
        if uiView.text != text, uiView.markedTextRange == nil {
            uiView.text = text
        }
        uiView.refreshPlaceholder()
    }

    /// **Growth belongs here and not in the delegate.** This is the only place
    /// SwiftUI hands over the proposed width, and the height is a function of
    /// it. Measuring off `bounds.width` gives a floor computed at width zero
    /// on the first pass.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: NoteUITextView,
        context: Context
    ) -> CGSize? {
        // **An unspecified width is refused rather than substituted.**
        // `replacingUnspecifiedDimensions()` hands back 10pt, which measures a
        // long note as dozens of lines and reports the ceiling for that pass.
        // Returning nil lets SwiftUI size the view its own way instead.
        guard let width = proposal.width else { return nil }
        let content = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        let height = NoteEditorMetrics.fieldHeight(content: content)
        if context.coordinator.reportedHeight != height {
            context.coordinator.reportedHeight = height
            // Off this layout pass: a `@State` write from inside `sizeThatFits`
            // mutates the view tree that is being measured.
            DispatchQueue.main.async { onHeightChange(height) }
        }
        return CGSize(width: width, height: height)
    }
}

/// The `UITextView` itself: the app's chrome, its placeholder, and the two
/// things UIKit does not give a text view in SwiftUI for free.
final class NoteUITextView: UITextView {
    private let placeholder = UILabel()
    /// `didMoveToWindow` fires on removal too, and more than once. Focus is
    /// asked for exactly once.
    private var hasFocused = false

    init() {
        super.init(frame: .zero, textContainer: nil)

        backgroundColor = .clear
        textContainerInset = UIEdgeInsets(
            top: NoteEditorMetrics.insetV, left: NoteEditorMetrics.insetH,
            bottom: NoteEditorMetrics.insetV, right: NoteEditorMetrics.insetH
        )
        textContainer.lineFragmentPadding = 0
        keyboardAppearance = .dark
        textColor = UIColor(Theme.text)
        tintColor = UIColor(Theme.text)
        font = NoteEditorMetrics.measuringFont
        adjustsFontForContentSizeCategory = true

        // **Horizontal compression resistance must be lowered.** A
        // `UITextView`'s intrinsic content size is its CONTENT size and it
        // resists compression at `.defaultHigh`. Left alone, a long
        // single-paragraph note makes the field hundreds of points wide: the
        // note draws as one clipped line and the slot row is shoved off the
        // sheet entirely (test 34).
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        placeholder.text = "Write a note about this session…"
        placeholder.font = NoteEditorMetrics.measuringFont
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = UIColor(Theme.textMuted)
        placeholder.numberOfLines = 1
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        // Pinned to the FRAME layout guide and not to the view's own edges: a
        // `UITextView` is a scroll view, so its bounds move with the content
        // offset and the placeholder would scroll away with the text.
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(
                equalTo: frameLayoutGuide.leadingAnchor,
                constant: NoteEditorMetrics.insetH),
            placeholder.topAnchor.constraint(
                equalTo: frameLayoutGuide.topAnchor,
                constant: NoteEditorMetrics.insetV),
            placeholder.trailingAnchor.constraint(
                lessThanOrEqualTo: frameLayoutGuide.trailingAnchor,
                constant: -NoteEditorMetrics.insetH),
        ])

        // **The field's name.** Without it VoiceOver reads the note text and
        // then "text field" — a named control instead of an anonymous one
        // (§8).
        accessibilityLabel = "Note"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// **Focus needs `didMoveToWindow`.** `becomeFirstResponder()` from
    /// `makeUIView`, even deferred one run loop, is too early: the view is not
    /// in a window and the keyboard never comes up. The caret appears and the
    /// keyboard does not, which reads as a simulator problem and is not one.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !hasFocused else { return }
        hasFocused = true
        becomeFirstResponder()
    }

    func refreshPlaceholder() {
        placeholder.isHidden = !(text ?? "").isEmpty
    }

    override var text: String! {
        didSet { refreshPlaceholder() }
    }
}

// MARK: - The slot row

/// Five dots and the counter, on one row.
///
/// **The dots do not scale with Dynamic Type and should not.** A Colour Slot
/// is a colour, and a colour is not text.
struct NoteSlotRow: View {
    @Binding var selection: NoteSlot
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: NoteEditorMetrics.cellSpacing) {
                ForEach(NoteSlot.allCases, id: \.self) { slot in
                    cell(slot)
                }
            }
            Spacer(minLength: 8)
            counter
        }
        .frame(height: NoteEditorMetrics.hitTarget)
    }

    private func cell(_ slot: NoteSlot) -> some View {
        let selected = slot == selection
        return Button {
            // **The slot row fires selection feedback; Save fires nothing.**
            // Tapping a slot is a selection and the app already gives
            // selections exactly this (`SheetUI.swift`), so the Note Editor
            // feels like the app's other sheets rather than like a new thing.
            UISelectionFeedbackGenerator().selectionChanged()
            selection = slot
        } label: {
            Circle()
                .fill(slot.color)
                .frame(width: NoteEditorMetrics.dot, height: NoteEditorMetrics.dot)
                .overlay {
                    // Held one cell out from the DOT, not from the 44pt
                    // target: at 44 it becomes a hoop with the dot rattling
                    // inside it. A check mark was refused — a tick sized to
                    // the dot crowds it and eats the colour the row exists to
                    // show — and so was growing the chosen dot, which cannot
                    // be read without a second dot to compare against.
                    Circle()
                        .strokeBorder(Theme.text.opacity(NoteEditorMetrics.ringOpacity),
                                      lineWidth: NoteEditorMetrics.ringWidth)
                        .frame(width: NoteEditorMetrics.ringDiameter,
                               height: NoteEditorMetrics.ringDiameter)
                        .opacity(selected ? 1 : 0)
                }
                .frame(width: NoteEditorMetrics.hitTarget,
                       height: NoteEditorMetrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slot.spokenLabel)
        // **The ring gains an explicit `Selected` value.**
        // `.accessibilityAddTraits(.isSelected)` does not appear in any tree
        // this effort could produce, so the ring's selected state would
        // otherwise be claimed by nothing (§8).
        .accessibilityValue(Self.accessibilityValue(selected: selected))
    }

    /// **The ring gains an explicit `Selected` value.**
    /// `.accessibilityAddTraits(.isSelected)` does not appear in any tree this
    /// effort could produce, so the ring's selected state would otherwise be
    /// claimed by nothing (§8). A named function rather than an inline
    /// ternary, because the string is the only thing that says the ring means
    /// anything and nothing else can assert it.
    static func accessibilityValue(selected: Bool) -> String {
        selected ? "Selected" : ""
    }

    /// **The desktop's rule ports verbatim: hidden until 240,
    /// `Theme.textMuted`, turning `Theme.text` at 280.**
    @ViewBuilder private var counter: some View {
        if count >= NoteEditorMetrics.counterFrom {
            Text("\(count)/\(NoteEditorMetrics.cap)")
                .font(Theme.sans(12))
                .monospacedDigit()
                .foregroundStyle(count >= NoteEditorMetrics.cap ? Theme.text : Theme.textMuted)
        }
    }
}

// MARK: - The sheet

/// The Note Editor. **Field → slot row, and nothing else.**
///
/// **The pill lost, and it was close.** `SheetPrimaryButton` is the app's own
/// shape and `SpaceView` uses it, but it needs a taller detent to hold the
/// pill clear of the keyboard and it puts Save a thumb-stretch from the field.
///
/// **Clear note lives in the menu only**, never here: two Clears for one act,
/// when the in-sheet path is already select-all, delete, Save. And nothing
/// asks for confirmation on either path — a confirm on one path only would
/// make the two disagree.
struct NoteEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let chat: Chat

    @State private var text: String
    @State private var slot: NoteSlot
    @State private var fieldHeight: CGFloat

    init(chat: Chat) {
        self.chat = chat
        _text = State(initialValue: chat.note?.text ?? "")
        // **A new note starts on `rose`, already selected; editing shows the
        // stored slot ringed.** An id no case matches rings `rose` too, which
        // is the same answer `NoteSlot.color(for:)` paints with.
        _slot = State(initialValue: NoteSlot.slot(for: chat.note?.color ?? ""))
        _fieldHeight = State(initialValue: NoteEditorMetrics.floorHeight)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: NoteEditorMetrics.fieldSlotGap) {
                SheetCard {
                    NoteTextField(text: $text, onSubmit: save) { fieldHeight = $0 }
                }
                NoteSlotRow(selection: $slot, count: text.count)
            }
            .padding(NoteEditorMetrics.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SheetStyle.panel)
            // Product copy, carried verbatim; identifiers stay `ChatNote`.
            .navigationTitle("Session note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // **A swipe-down discards, with no prompt** — the
                    // desktop's Escape, unchanged, so Cancel and the drag mean
                    // one thing rather than two.
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        // **Sized to its own content, and growing with the field.**
        .presentationDetents([.height(NoteEditorMetrics.detentHeight(fieldHeight: fieldHeight))])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .preferredColorScheme(.dark)
    }

    /// Save is deliberately silent: the sheet closing and the marker appearing
    /// is the feedback, and the app has no success-haptic anywhere for this to
    /// match. Blank text clears, which is what makes Save and "Clear note" the
    /// same act rather than two.
    /// **`dismiss()` is called inline, and deferring it one run loop was
    /// built and refused.** Return reaches here from inside
    /// `shouldChangeTextInRanges`, so calling it there looks like tearing the
    /// first responder down mid-callback — a fair thing to raise, and it was.
    /// `DispatchQueue.main.async { dismiss() }` was tried on an iPhone 17 Pro:
    /// the note saves, the sheet does NOT close, and it snaps to full screen
    /// with the text still in it. The `DismissAction` is stale by the time the
    /// block runs. The inline call closes cleanly on both paths and on the
    /// swipe, so it stands.
    private func save() {
        model.setChatNote(chatId: chat.id, text: text, color: slot.rawValue)
        dismiss()
    }
}
