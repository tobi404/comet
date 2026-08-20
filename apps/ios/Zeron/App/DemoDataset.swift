// Offline demo dataset — realistic spaces/sessions/transcripts so the app can
// be explored (and screenshotted) with no edge deployment. The flagship chat
// streams a reply on demand, exercising the live-row pipeline: incremental
// re-parse, veil fade-in, stick-to-bottom.

import Foundation
import Observation

// MARK: - Chat Note fixtures

/// 779 characters — far past the 280 the Note Editor caps at. The cap is an
/// authoring affordance and not a storage invariant: the phone writes registry
/// rows directly and never passes the engine's Mutate RPC, so a longer note can
/// arrive from any device. Every surface must tolerate it by eliding, and this
/// seed is what makes that true on every launch.
///
/// It was written to match the desktop's own 671-character fixture and does
/// not; it was counted rather than eyeballed, and every finding about the card
/// holds at 779.
private let demoOverCapNote = """
The room generation flip is the part nobody wrote down. When the host seeds a chat2 room it \
stamps roomGen 2 on the chat row, and every peer that was already dialed into the s2 room has \
to notice the stamp, tear the old dial down, and redial against the new room id — but the \
mobile client never dials roomGen 1 at all, so on the phone the flip reads as a room that \
simply appeared. That asymmetry is fine today and will stop being fine the moment a third \
generation exists, because the phone's rule is written as "not 1" rather than as "the \
generation I understand". Rewrite it as an explicit allow-list before the next generation, and \
add a fixture that carries a generation the build has never heard of so the dial refuses \
rather than guesses. Ask Wing about the desktop side.
"""

/// One unbreakable token with no space in it, far wider than the row. Nothing
/// may widen or wrap the layout around it.
///
/// The spec calls this "the 118-character URL". This is that exact fixture,
/// byte for byte — every measurement made against it holds — but it counts
/// **115**, the same class of miscount the spec corrects for the note above.
private let demoUnbreakableURLNote =
    "https://github.com/tobi404/comet/actions/runs/1874553902/jobs/2661104477?pr=173&check_suite_focus=true#step:14:2201"

@MainActor
@Observable
final class DemoDataset {
    var devices: [DeviceRow]
    var spaces: [Space]
    var chats: [Chat]
    var sessions: [String: SessionRow]
    var changeRequests: [String: ChangeRequestSummary]
    private var stores: [String: SessionStore] = [:]
    private var streamTask: Task<Void, Never>?

    private static let dummyConfig = AppConfig(
        edgeURL: URL(string: "http://localhost:8787")!, mode: .dev,
        userId: "demo", orgId: "demo", deviceId: "ios-demo", deviceName: "iPhone")

    init(devices: [DeviceRow], spaces: [Space], chats: [Chat], sessions: [String: SessionRow],
         changeRequests: [String: ChangeRequestSummary] = [:]) {
        self.devices = devices
        self.spaces = spaces
        self.chats = chats
        self.sessions = sessions
        self.changeRequests = changeRequests
    }

    static func standard() -> DemoDataset {
        let now = nowMs()
        let mac = DeviceRow(id: "dev-mac", name: "MacBook Pro", platform: "macos",
                            lastSeenAt: now, createdAt: now - 86_400_000 * 30)
        let vps = DeviceRow(id: "dev-vps", name: "hetzner-01", platform: "linux",
                            lastSeenAt: now - 600_000, createdAt: now - 86_400_000 * 12)
        let zeron = Space(id: "space-zeron", deviceId: "dev-mac",
                          path: "/Users/dev/zeron", name: nil, gitDetected: true,
                          gitCheckedAt: now, checkoutId: nil, createdAt: now - 86_400_000 * 9)
        let edge = Space(id: "space-edge", deviceId: "dev-vps",
                         path: "/srv/deploys/edge", name: nil, gitDetected: true,
                         gitCheckedAt: now, checkoutId: nil, createdAt: now - 86_400_000 * 4)

        let claude = ChatConfig(harness: "claude-code", model: "claude-fable-5",
                                reasoning: "xhigh", sandbox: "workspace-write")
        let codex = ChatConfig(harness: "codex", model: "gpt-5.6-terra",
                               reasoning: "high", sandbox: "workspace-write")

        // Exactly THREE Chat Notes, on three different Colour Slots, and two
        // of the three are the spec's own fixtures — so both are on screen on
        // every launch rather than being a test someone remembers to run.
        // A short note on an active row, the over-cap note on an active row,
        // and the unbreakable URL on the shelf. Do not add a fourth: the
        // fixtures are the reason the seeds exist.
        let chats = [
            Chat(id: "chat-veil", deviceId: "dev-mac", title: "Streaming veil on transcript rows",
                 archived: false, cwd: "/Users/dev/.zeron/worktrees/zeron-veil-fade",
                 branch: "veil-fade", checkoutId: nil,
                 config: claude, lastMessagePreview: "Porting the paint-only fade…",
                 lastMessageAt: now - 40_000, createdAt: now - 3_600_000,
                 spaceId: zeron.id, lastSeenAt: now,
                 note: ChatNote(text: "Ask Dana before this merges", color: "rose")),
            Chat(id: "chat-picker", deviceId: "dev-mac", title: "Model picker catalog sync",
                 archived: false, cwd: zeron.path, branch: "main", checkoutId: nil,
                 config: claude, lastMessagePreview: "Which device owns the catalog?",
                 lastMessageAt: now - 120_000, createdAt: now - 7_200_000,
                 spaceId: zeron.id, lastSeenAt: now - 130_000),
            Chat(id: "chat-tabs", deviceId: "dev-mac", title: "Tool group header colors",
                 archived: false, cwd: zeron.path, branch: "main", checkoutId: nil,
                 config: codex, lastMessagePreview: "Done — failed children stay quiet.",
                 lastMessageAt: now - 900_000, createdAt: now - 86_400_000,
                 spaceId: zeron.id, lastSeenAt: now - 3_600_000,
                 note: ChatNote(text: demoOverCapNote, color: "green")),
            Chat(id: "chat-deploy", deviceId: "dev-vps", title: "Wrangler deploy hygiene",
                 archived: false, cwd: edge.path, branch: nil, checkoutId: nil,
                 config: claude, lastMessagePreview: "Hibernation-safe flush timer",
                 lastMessageAt: now - 86_400_000, createdAt: now - 86_400_000 * 2,
                 spaceId: edge.id, lastSeenAt: now - 86_400_000),
            // Archived — populate the shelf under the active list.
            Chat(id: "chat-oklch", deviceId: "dev-mac", title: "OKLCH conversion drift",
                 archived: true, cwd: zeron.path, branch: "main", checkoutId: nil,
                 config: claude, lastMessagePreview: "Gamma encode matches now.",
                 lastMessageAt: now - 86_400_000 * 3, createdAt: now - 86_400_000 * 4,
                 spaceId: zeron.id, lastSeenAt: now - 86_400_000 * 3,
                 note: ChatNote(text: demoUnbreakableURLNote, color: "sky")),
            Chat(id: "chat-presence", deviceId: "dev-vps", title: "Presence beat coalescing",
                 archived: true, cwd: edge.path, branch: nil, checkoutId: nil,
                 config: codex, lastMessagePreview: "Batched to one beat per 25s.",
                 lastMessageAt: now - 86_400_000 * 6, createdAt: now - 86_400_000 * 7,
                 spaceId: edge.id, lastSeenAt: now - 86_400_000 * 6),
        ]
        let sessions: [String: SessionRow] = [
            "chat-veil": SessionRow(chatId: "chat-veil", deviceId: "dev-mac", status: .working,
                                    startedAt: now - 95_000, updatedAt: now - 5_000),
            "chat-picker": SessionRow(chatId: "chat-picker", deviceId: "dev-mac",
                                      status: .awaitingInput, startedAt: now - 400_000,
                                      updatedAt: now - 10_000),
        ]
        let changeRequests = [
            "chat-veil": ChangeRequestSummary(
                provider: "github", number: 90, title: "Stream pull request status on every client",
                url: "https://github.com/zeron-sh/zeron/pull/90", state: .open,
                baseRef: "main", headRef: "veil-fade"
            ),
            "chat-picker": ChangeRequestSummary(
                provider: "github", number: 84, title: "Synchronize model catalogs",
                url: "https://github.com/zeron-sh/zeron/pull/84", state: .merged,
                baseRef: "main", headRef: "main"
            ),
            "chat-tabs": ChangeRequestSummary(
                provider: "github", number: 77, title: "Refine tool group colors",
                url: "https://github.com/zeron-sh/zeron/pull/77", state: .closed,
                baseRef: "main", headRef: "main"
            ),
        ]
        return DemoDataset(devices: [mac, vps], spaces: [zeron, edge],
                           chats: chats, sessions: sessions, changeRequests: changeRequests)
    }

    // MARK: Fake filesystem (folder browser demo)

    static let fileTree: [String: [String]] = [
        "/Users/dev": ["Documents", "Downloads", "Projects", "scratch"],
        "/Users/dev/Documents": ["notes", "specs"],
        "/Users/dev/Projects": ["zeron", "dotfiles", "blog", "playground"],
        "/Users/dev/Projects/zeron": ["apps", "crates", "docs", "edge"],
        "/Users/dev/Projects/blog": ["content", "public"],
        "/srv": ["deploys", "backups"],
        "/srv/deploys": ["edge", "landing"],
    ]

    func homePath(deviceId: String) -> String {
        deviceId == "dev-vps" ? "/srv" : "/Users/dev"
    }

    private static let repoNames: Set<String> = ["zeron", "dotfiles", "blog", "playground", "edge", "landing"]

    /// What a harness advertises, for the composer's `/` popover. Live mode
    /// asks the host device; demo mode has no host, and an empty answer left
    /// the popover permanently on "No matching commands.". Long enough to
    /// scroll, so the panel's height cap is exercised too.
    static let commands: [SlashCommand] = [
        SlashCommand(name: "review", description: "Review the working tree", inputHint: nil),
        SlashCommand(name: "plan", description: "Write an implementation plan first", inputHint: nil),
        SlashCommand(name: "test", description: "Run the suite and read the failures", inputHint: nil),
        SlashCommand(name: "commit", description: "Stage and commit the current change", inputHint: nil),
        SlashCommand(name: "explain", description: "Explain this file, top to bottom", inputHint: nil),
        SlashCommand(name: "clear", description: "Start the conversation over", inputHint: nil),
    ]

    /// Fuzzy file search over the fake tree — the demo twin of `SearchFiles`.
    /// Directories only, because the tree holds only directories.
    func searchFiles(query: String) -> [FileSearchMatch] {
        let needle = query.lowercased()
        var matches: [FileSearchMatch] = []
        for (parent, children) in Self.fileTree.sorted(by: { $0.key < $1.key }) {
            for child in children where needle.isEmpty || child.lowercased().contains(needle) {
                matches.append(FileSearchMatch(path: "\(parent)/\(child)", isDir: true))
            }
        }
        return Array(matches.prefix(20))
    }

    func listFolders(deviceId: String, path: String) -> FolderListing {
        let entries = (Self.fileTree[path] ?? []).map { name in
            FolderEntry(name: name, isDir: true, isRepo: Self.repoNames.contains(name))
        }
        return FolderListing(path: path, entries: entries, truncated: false)
    }

    private var refsByPath: [String: [RepoRef]] = [:]

    func listRefs(spacePath: String) -> [RepoRef] {
        if let cached = refsByPath[spacePath] { return cached }
        let seeded: [RepoRef]
        if spacePath.contains("zeron") {
            seeded = [
                RepoRef(name: "main", current: true, worktreePath: nil),
                RepoRef(name: "veil-fade", current: false,
                        worktreePath: "/Users/dev/.zeron/worktrees/zeron-veil-fade"),
                RepoRef(name: "feature/diff-pane", current: false, worktreePath: nil),
                RepoRef(name: "fix/tool-colors", current: false, worktreePath: nil),
            ]
        } else {
            seeded = [
                RepoRef(name: "main", current: true, worktreePath: nil),
                RepoRef(name: "staging", current: false, worktreePath: nil),
            ]
        }
        refsByPath[spacePath] = seeded
        return seeded
    }

    /// git checkout simulation: move the `current` marker in the repo at path.
    func switchRef(path: String, refName: String) {
        var refs = listRefs(spacePath: path)
        for ix in refs.indices {
            refs[ix].current = refs[ix].name == refName
        }
        refsByPath[path] = refs
    }

    func createWorktree(spacePath: String, base: String) -> String {
        let slug = base.replacingOccurrences(of: "/", with: "-")
        let path = "/Users/dev/.zeron/worktrees/\((spacePath as NSString).lastPathComponent)-\(slug)"
        var refs = listRefs(spacePath: spacePath)
        if let ix = refs.firstIndex(where: { $0.name == base }), refs[ix].worktreePath == nil {
            refs[ix].worktreePath = path
        }
        refsByPath[spacePath] = refs
        return path
    }

    func sessionStore(for chatId: String) -> SessionStore {
        if let existing = stores[chatId] { return existing }
        let store = SessionStore(chatId: chatId, config: Self.dummyConfig, offline: true)
        store.setEntries(Self.transcript(for: chatId))
        store.demoResponder = { [weak self, weak store] prompt in
            guard let self, let store else { return }
            self.simulateTurn(store: store, chatId: chatId, prompt: prompt)
        }
        stores[chatId] = store
        return store
    }

    // MARK: Scripted transcripts

    private static func transcript(for chatId: String) -> [MessageEntry] {
        let now = nowMs()
        switch chatId {
        case "chat-veil":
            return [
                MessageEntry(id: "m1", role: .user, parts: [
                    .text(id: "t0", text: "Port the streaming fade-in veil from the desktop transcript. It must never affect layout — opacity only, split at chunk boundaries."),
                ], createdAt: now - 3_500_000, deviceId: "ios-demo", status: .complete, continuationOf: nil),
                MessageEntry(id: "m2", role: .assistant, parts: [
                    .text(id: "t0", text: """
                    ## Veil port plan

                    The desktop veil (`veil.rs`) multiplies a fading alpha into each appended \
                    chunk's text color — **paint-layer only**, so shaping and wrapping never change. \
                    Three invariants to carry over:

                    1. Chunk spans keep their *exact* byte length when split
                    2. Fade duration tracks the append cadence: `clamp(ema × 3, 120, 400)` ms
                    3. Re-attach seeds the baseline — only post-switch appends animate

                    | Constant | Value |
                    | --- | --- |
                    | `VEIL_MIN_FADE_MS` | 120 |
                    | `VEIL_MAX_FADE_MS` | 400 |
                    | `VEIL_CURVE_POW` | 1.6 |

                    > The curve is `1 − (1−p)^1.6` — fast attack, soft landing.
                    """),
                    .tool(id: "tool1", call: RenderToolCall(tag: "readFile", fields: ["path": "crates/ui/src/markdown/veil.rs"]), isError: false, resolved: true),
                    .tool(id: "tool2", call: RenderToolCall(tag: "editFile", fields: ["path": "Zeron/Transcript/Veil.swift"]), isError: false, resolved: true),
                    .tool(id: "tool3", call: RenderToolCall(tag: "exec", fields: ["command": "xcodebuild -scheme Zeron build"]), isError: false, resolved: true),
                    .text(id: "t1", text: """
                    Implementation lands in `Veil.swift`:

                    ```swift
                    func veilOpacity(_ p: Double) -> Double {
                        1 - pow(1 - p, 1.6)  // fast attack, soft landing
                    }

                    // Duration follows the streaming cadence EMA.
                    let duration = min(max(ema * 3, 120), 400)
                    ```

                    The row keeps one `RowVeil` while streaming and drops it on the \
                    live→complete flip, exactly like the desktop lifecycle.
                    """),
                ], createdAt: now - 3_400_000, deviceId: "dev-mac", status: .complete, continuationOf: nil),
            ]
        case "chat-picker":
            return [
                MessageEntry(id: "m1", role: .user, parts: [
                    .text(id: "t0", text: "The model picker shows stale catalogs after switching devices — where should the catalog come from?"),
                ], createdAt: now - 400_000, deviceId: "ios-demo", status: .complete, continuationOf: nil),
                MessageEntry(id: "m2", role: .assistant, parts: [
                    .text(id: "t0", text: "Two viable sources — the local device's harness install, or the space's owning device. The desktop recently moved to the latter (`aa128a6`). Before I wire the RPC, one decision:"),
                    .input(id: "req-1", requestId: "req-1", questions: [
                        UserInputQuestion(id: "q1", header: "Catalog source",
                                          question: "Which device should serve harness/model catalogs for the picker?",
                                          options: [
                                            "Space's device (Recommended)",
                                            "Local device",
                                            "Union of both",
                                          ], multiSelect: false),
                    ], resolved: false),
                ], createdAt: now - 380_000, deviceId: "dev-mac", status: .complete, continuationOf: nil),
            ]
        case "chat-tabs":
            return [
                MessageEntry(id: "m1", role: .user, parts: [
                    .text(id: "t0", text: "Tool group headers turn red when any child fails — they should stay quiet, chips carry the error."),
                ], createdAt: now - 1_000_000, deviceId: "ios-demo", status: .complete, continuationOf: nil),
                MessageEntry(id: "m2", role: .assistant, parts: [
                    .tool(id: "tool1", call: RenderToolCall(tag: "search", fields: ["pattern": "group_header_color"]), isError: false, resolved: true),
                    .tool(id: "tool2", call: RenderToolCall(tag: "exec", fields: ["command": "cargo test -p zeron-ui tool_group"]), isError: true, resolved: true),
                    .tool(id: "tool3", call: RenderToolCall(tag: "editFile", fields: ["path": "crates/ui/src/shell/transcript.rs"]), isError: false, resolved: true),
                    .text(id: "t0", text: "Done — the header keeps `text_muted` even on failure; only the chip label and the summary segment (\"1 failed\") pick up `danger`. Matches the desktop fix in `1749890`."),
                ], createdAt: now - 950_000, deviceId: "dev-mac", status: .complete, continuationOf: nil),
            ]
        case "chat-deploy":
            return [
                MessageEntry(id: "m1", role: .user, parts: [
                    .text(id: "t0", text: "Audit the wrangler config for hibernation hygiene."),
                ], createdAt: now - 86_500_000, deviceId: "ios-demo", status: .complete, continuationOf: nil),
                MessageEntry(id: "m2", role: .assistant, parts: [
                    .text(id: "t0", text: "Flush timer now only arms while dirty; ping/pong uses the auto-response path so the DO never wakes for keepalives."),
                ], createdAt: now - 86_400_000, deviceId: "dev-vps", status: .complete, continuationOf: nil),
            ]
        default:
            return []  // freshly minted chats start empty
        }
    }

    // MARK: Streaming simulation

    private func simulateTurn(store: SessionStore, chatId: String, prompt: String) {
        streamTask?.cancel()
        let now = nowMs()
        var entries = store.entries
        entries.append(MessageEntry(id: "u-\(now)", role: .user, parts: [
            .text(id: "t0", text: prompt),
        ], createdAt: now, deviceId: "ios-demo", status: .complete, continuationOf: nil))
        let liveId = "a-\(now)"
        entries.append(MessageEntry(id: liveId, role: .assistant, parts: [
            .text(id: "t0", text: ""),
        ], createdAt: now, deviceId: "dev-mac", status: .streaming, continuationOf: nil))
        store.setEntries(entries)
        sessions[chatId] = SessionRow(chatId: chatId, deviceId: "dev-mac", status: .working,
                                      startedAt: now, updatedAt: now)

        let reply = """
        Here's how the streamed reply renders on this device:

        - Markdown re-parses **only the tail** — the last two top-level blocks
        - New text fades in through the paint-only veil
        - The transcript stays glued to the bottom until you scroll up

        ```rust
        // The desktop constant carries over verbatim.
        const STREAM_COMMIT_MS: u64 = 120;
        ```

        When the turn settles, this entry flips `streaming → complete`, the veil \
        drops, and the row ids stay stable so nothing flickers.
        """
        let words = reply.split(separator: " ", omittingEmptySubsequences: false)

        streamTask = Task { [weak self, weak store] in
            var text = ""
            for (ix, word) in words.enumerated() {
                if Task.isCancelled { return }
                text += (ix == 0 ? "" : " ") + word
                guard let store else { return }
                var current = store.entries
                guard let last = current.indices.last, current[last].id == liveId else { return }
                current[last].parts = [.text(id: "t0", text: text)]
                store.setEntries(current)
                try? await Task.sleep(nanoseconds: UInt64.random(in: 30_000_000...140_000_000))
            }
            guard let self, let store else { return }
            var current = store.entries
            if let last = current.indices.last, current[last].id == liveId {
                current[last].status = .complete
                store.setEntries(current)
            }
            let end = nowMs()
            self.sessions[chatId] = SessionRow(chatId: chatId, deviceId: "dev-mac", status: .idle,
                                               startedAt: nil, updatedAt: end)
            if let ix = self.chats.firstIndex(where: { $0.id == chatId }) {
                self.chats[ix].lastMessageAt = end
                self.chats[ix].lastMessagePreview = "When the turn settles, this entry flips…"
                self.chats[ix].lastSeenAt = end
            }
        }
    }
}
