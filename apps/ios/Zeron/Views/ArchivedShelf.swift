// Archived shelf — the desktop sidebar's settled shelf for archived sessions
// (shell/spaces.rs `render_archived_section`), sitting under the active list:
// a hairline header that folds ("Archived" open / "Archived (N)" collapsed,
// open by default, session-transient), slim rows, and Show-more paging
// (10, then +25). The desktop's hover-swapped Unarchive pill becomes
// swipe-to-unarchive here, mirroring the active rows' swipe-to-archive.

import SwiftUI

private extension Chat {
    var shelfRowId: String { "archived-\(id)" }
}

/// Confirm-dialog body. Names the count, and says the delete reaches every
/// device — archived rows are cross-device even under a space scope. Matches
/// the desktop's `clear_confirm_copy`. Pure.
func clearArchivedConfirmCopy(count: Int) -> String {
    let sessions = count == 1 ? "session" : "sessions"
    return "\(count) archived \(sessions) will be permanently deleted from all "
        + "your devices. This can\u{2019}t be undone."
}

struct ArchivedSection: View {
    @Environment(AppModel.self) private var model
    /// Scope, matching the list above it: nil = All.
    var spaceId: String?
    @Binding var path: [Route]

    // spaces.rs INITIAL/PAGE. Both session-transient, like the desktop's.
    @State private var open = true
    @State private var shown = ArchivedSection.initialCount
    /// Count the confirm dialog opened with; nil = closed.
    @State private var confirmCount: Int?
    private static let initialCount = 10
    private static let pageSize = 25

    static let rowInsets = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)

    var body: some View {
        let archived = model.archivedChats(in: spaceId)
        if !archived.isEmpty {
            Section {
                header(count: archived.count)
                if open {
                    // Distinct identity namespace (desktop's "archived-{id}"
                    // vs "c:{id}" FLIP keys): the SAME id in both ForEach made
                    // SwiftUI animate archiving as a cross-section MOVE — the
                    // full-size row flew down through its neighbors and landed
                    // in the shelf before snapping to the slim style. With
                    // separate ids it's a clean exit + entrance.
                    ForEach(archived.prefix(shown), id: \.shelfRowId) { chat in
                        row(chat)
                    }
                    if archived.count > shown {
                        showMore(remaining: archived.count - shown)
                    }
                }
            }
        }
    }

    /// Two tap targets on one hairline row: the fold on the left, Clear on the
    /// trailing edge. They are separate Buttons — a single row-wide
    /// `contentShape` would swallow the Clear tap into the fold.
    private func header(count: Int) -> some View {
        // 14, not the inner 8: at 8 the fold chevron sat as close to "Clear" as
        // to its own rule and read as that button's disclosure arrow.
        HStack(spacing: 14) {
            Button {
                withAnimation(Motion.collapse) {
                    open.toggle()
                    shown = Self.initialCount
                }
            } label: {
                HStack(spacing: 8) {
                    Text(open ? "Archived" : "Archived (\(count))")
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(Theme.textMuted.opacity(0.5))
                        .fixedSize()
                    Rectangle()
                        .fill(Theme.border.opacity(0.6))
                        .frame(height: 1)
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Collapse archived" : "Expand archived, \(count) sessions")

            Button {
                confirmCount = count
            } label: {
                // Quiet, at the header's own weight. Full-strength danger on a
                // bare label (no pill to contain it, unlike the desktop's
                // bordered button) outshouted every session title on screen —
                // the loudest thing in the list was its least-used control.
                Text("Clear")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.danger.opacity(0.7))
                    .fixedSize()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear archived, \(count) sessions")
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(Self.rowInsets)
        .confirmationDialog(
            "Clear archived sessions?",
            isPresented: Binding(get: { confirmCount != nil },
                                 set: { if !$0 { confirmCount = nil } }),
            titleVisibility: .visible
        ) {
            Button("Clear archived", role: .destructive) {
                withAnimation(Motion.resort) {
                    model.clearArchived(in: spaceId)
                }
                confirmCount = nil
            }
            Button("Cancel", role: .cancel) { confirmCount = nil }
        } message: {
            Text(clearArchivedConfirmCopy(count: confirmCount ?? count))
        }
    }

    private func row(_ chat: Chat) -> some View {
        // The location string is handed in, not built by the row: the shelf
        // row never showed one, and the Note Card it opens has to say exactly
        // what the session row's card says (§5).
        ArchivedChatRow(chat: chat, location: model.location(for: chat)) {
            path.append(.chat(chat.id))
        }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(Self.rowInsets)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    withAnimation(Motion.resort) {
                        model.unarchive(chatId: chat.id)
                    }
                } label: {
                    Label("Unarchive", systemImage: "arrow.up.bin")
                }
                .tint(Theme.surfaceRaised)
            }
    }

    private func showMore(remaining: Int) -> some View {
        Button {
            shown = max(shown, Self.initialCount) + Self.pageSize
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textMuted.opacity(0.55))
                Text("Show \(min(remaining, Self.pageSize)) more")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.textMuted.opacity(0.55))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PressWashButtonStyle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(Self.rowInsets)
    }
}

/// Slim row: dimmed harness mark, muted title, time-ago (spaces.rs archived
/// row — h 36, mark 14, title 13, time 11).
///
/// A `struct` and not an inline builder inside `ArchivedShelf`, so that §9's
/// tests can render this row shape on its own — `ArchivedShelf` itself only
/// exists inside a `List`, which no renderer can measure. The shelf keeps the
/// list-level modifiers (insets, swipe) at its own call site.
struct ArchivedChatRow: View {
    let chat: Chat
    /// "space @ device", for the Note Card the long press opens (§5). The row
    /// itself never draws it — the shelf row has no context line.
    let location: String
    let onSelect: () -> Void

    /// The row's own title line box — the resting marker's height rule (§4).
    @State private var titleLine: CGFloat = 0

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                if let harness = chat.config?.harness {
                    HarnessBadge(harness: harness, size: 14, dimmed: true)
                }
                // The resting marker takes this title's line box (§4) — but
                // not the 0.55 dim beside it.
                Text(chat.displayTitle)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.text.opacity(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleLine = $0 }
                Text(relativeTime(chat.lastMessageAt ?? chat.createdAt))
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.textMuted.opacity(0.55))
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PressWashButtonStyle())
        .restingNote(chat.note, titleLine: titleLine)
        // One mechanism on both row shapes: the 36pt row opens the same card
        // from the same gesture, with no degrade (§5, test 27).
        .chatNoteMenu(chat, location: location)
    }
}
