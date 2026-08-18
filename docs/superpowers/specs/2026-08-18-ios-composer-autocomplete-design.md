# iOS composer autocomplete: slash commands and file mentions

Status: DESIGN · 2026-08-18 · revision 2 (adversarial review applied)

## Why

The iOS composer is a plain `TextField` (`apps/ios/Zeron/Composer/ComposerView.swift:132-139`).
It has no autocomplete. A user who types `/tdd` sends the literal text. The agent may still
act on it, but the phone offers no list, no filter, and no completion. A user who wants to
point the agent at a file must type the path from memory.

Desktop has both. The composer popup lists slash commands, and `@` opens a file picker that
inserts a mention chip (`crates/ui/src/composer.rs`).

This spec closes that gap on iOS.

## What already exists

This work is smaller than it looks, because the host side is built.

- **Command discovery is per workspace.** `crates/engine/src/commands.rs` caches slash
  commands by `(harness, cwd)`, and expands `~` on the host (`CommandCache::normalize`, `commands.rs:109-117`). See
  `docs/slash-commands.md`. The commits are `6c78309` and `94f117e`. They are on branch
  `mine` and **not on `main`**.
- **The relay already serves both RPCs to the phone.** `HostRelay::spawn` hands the full
  `RpcService` to every relay client (`crates/rpc/src/device_room.rs:258-263`), and iOS
  dials the device directly. The `forwardable` list in `crates/engine/src/rpc.rs:786-806`
  is **not** the mechanism here: it only gates `targetDeviceId` routing when a desktop
  client calls its own local engine (`rpc.rs:1006-1007`). No engine change is needed for
  iOS.
- **iOS already makes this kind of call.** `WorkspaceStore.swift:403` calls
  `ListHarnesses`, and line 422 calls `ListModels`, over the device relay.
- **iOS already mirrors the inputs.** `Entities.swift:52` holds `chat.cwd`, and line 21
  holds the space `path`.
- **The transcript already renders links.** `MarkdownModel.swift:152` parses
  `Markdown.Link` and `MarkdownBlockView.swift:56` paints it.

## Non-goals

- **A `$` skill trigger.** Comet's `SlashCommand` is `{name, description, inputHint}`
  (`crates/proto/src/agent.rs:195`). `docs/slash-commands.md` measured 34 project skills
  arriving as ordinary slash commands once the session `cwd` is right.
- **Atomic backspace over a chip.** See "Edit policy".
- **A mention chip in the iOS transcript.** A sent mention renders as a link. Desktop
  upgrades it to a chip (`sent_mention_display`, used at `transcript.rs:671`). Follow-up.
- **Disambiguating duplicate basenames.** Desktop renames two `mod.rs` chips to path
  suffixes (`mention_display_labels`, `composer.rs:1011`). The invariant below forces both
  iOS chips to read `@mod.rs`, so they look alike on screen. Serialization stays correct.
  Recorded as a known divergence.
- **CI wiring for `ZeronTests`.** See "Testing".
- **Models.** They keep their `$HOME` probe, as `docs/slash-commands.md` states.

## Architecture

```
        type "/" or "@"
              |
   ComposerText (AttributedString <-> String + offset)
              |  plain text, caret offset
              v
     ComposerTrigger.detect()          pure: no SwiftUI, no I/O
              |  {kind, query, range}
              v
   ComposerText.suppressIfInsideChip()  attribute-aware veto
              |
   +----------+-----------+
   |                      |
 .command               .path
   |                      |
 WorkspaceStore        WorkspaceStore
 .listCommands         .searchFiles
 (harness, cwd)        (chatId | spaceId, query)
   |                      |
   +----------+-----------+
              | relay -> host device -> engine
              v
     ComposerSuggestions (cache, rank, state)
              |
              v
      ComposerPopover (list above the pill)
              |  tap
              v
   ComposerText.apply(pick, over: range)
```

### The boundary that matters

`ComposerTrigger`, `ComposerSuggestions`, and `ComposerPopover` never see an
`AttributedString`. They work on plain text and a caret offset. Only `ComposerText` knows
about the rich text model.

This is deliberate. Rich text rendering is the least verified part of this design. If it
fails on device, everything else is still correct, and the composer falls back to plain text
with the Markdown visible.

One consequence, found in review: because a chip's visible text is literally `@Info.plist`,
a pure trigger detector cannot tell a chip from a token the user typed. Tapping inside an
intact chip would open the file popover. **The veto for that belongs in `ComposerText`**,
the only module that can see the attribute. It is drawn explicitly in the diagram above so
the boundary does not hide it.

## New modules

### `ComposerTrigger.swift`

Pure. It ports **desktop's** rules, not t3code's. Desktop and iOS must agree on what counts
as a trigger, or the same draft behaves differently on two clients.

```swift
enum TriggerKind { case command, path }
struct Trigger { let kind: TriggerKind; let query: String; let range: Range<Int> }

func detect(text: String, caret: Int) -> Trigger?
func replace(_ text: String, range: Range<Int>, with: String) -> (String, Int)
```

**Command rule**, from `slash_token` (`composer.rs:3212-3233`):

- The **whole draft** must start with `/`. Not the line. Slash commands are whole-prompt
  prefixes, so only the first token triggers.
- The token ends at the first whitespace in the draft, or at its end.
- The caret must sit inside that token: `caret > 0 && caret <= end`.
- The query is `text[1..<caret]`. A query containing `/` never triggers, so a typed path
  does not open the popup.
- The range is the whole token, `0..<end`.

**Path rule**, from `mention_token` (`composer.rs:3179-3208`):

- Scan back from the caret to the last whitespace to find the token start.
- Find the last `@` between the token start and the caret. Without one, no trigger.
- The `@` must begin a token: it is at offset 0, or the character before it is whitespace or
  one of `(`, `[`, `{`. This excludes `name@example.com`.
- A query containing a second `@` never triggers.
- The token **ends at the first whitespace at or after the caret**, not at the caret. So
  editing the middle of an existing mention replaces the whole token.
- The range is `at..<end`, and the query is `text[at+1..<caret]`.

The caller suppresses detection when the selection is a range rather than a caret, and
`ComposerText` vetoes any trigger whose range intersects a mention run.

### `ComposerText.swift`

The only module that knows `AttributedString` exists.

**The mention attribute.** One custom `AttributedStringKey` whose value is
`{path: String, isDir: Bool}`. It sets `inheritedByAddedText = false` so text typed beside a
chip never joins it.

It also declares `invalidationConditions = [.textChanged]`
(`AttributedStringKey.invalidationConditions` exists in the SDK; see
`Foundation.tbd:38446`). If that behaves as documented, the framework itself drops the
attribute when the text inside a run changes, which covers the local half of the invariant
below for free. **The spike must confirm this.** If it does not hold, the manual pass below
is the only mechanism, and the spec loses nothing but speed.

The path lives in the attribute, never in the visible text. The run shows `@Info.plist`. The
attribute holds `src/Info.plist`.

**The formatting definition.** An `AttributedTextFormattingDefinition` (protocol at
`SwiftUICore.swiftinterface:9372`, applied with the `attributedTextFormattingDefinition(_:)`
modifier at line 9362) over a small scope. Where the mention key is present, apply the mono
font and the code wash. Where it is absent, apply neither. Desktop defines the same look:
"Chips read as inline code: `@name` in the mono font over the code wash"
(`composer.rs:643-647`). A chip is styled text, not an embedded view.

**The index adapter.**

`AttributedTextSelection.indices(in:)` returns a **frozen enum**, not a range
(`SwiftUI.swiftinterface:14623-14625`):

```swift
@frozen public enum Indices {
    case insertionPoint(AttributedString.Index)
    case ranges(RangeSet<AttributedString.Index>)
}
```

- `.insertionPoint` maps to a character offset into `plainText`. This is the only case that
  produces a trigger.
- `.ranges` counts as a selection and suppresses triggers. `RangeSet` can be discontiguous,
  so the multi-range case falls out of the same branch.
- Every mutation runs inside `transform(updating: &selection)`
  (`SwiftUI.swiftinterface:14644`, a method on `AttributedString`), so the selection stays
  valid and the caret lands after the inserted text.

**`plainText`** is `String(attributed.characters)`. The trigger core and the expansion
heuristic in `ComposerShell` both read it.

**`markdown()`** walks runs and emits desktop's exact form (`composer.rs:713-726`):

```
[escaped-basename](zeron-file:percent-encoded-path)
```

- A directory path carries a trailing `/`.
- The label escapes `\`, `[`, and `]` (`composer.rs:706`).
- The path percent-encodes every byte outside `[A-Za-z0-9-._~/]`, with uppercase hex
  (`composer.rs:676`).
- Non-mention runs pass through as their plain characters.

**The Rust parser, ported.** `ComposerText` also carries a Swift port of
`file_mention_links` (`composer.rs:752-795`), `local_path_is_safe` (`728-736`),
`percent_encode_path` (`670-682`), and `escape_mention_label` (`706-711`). It is needed for
the invariant below, and it gives the format-parity tests a real oracle instead of a list of
hand-written strings.

## The round-trip invariant

Revision 1 said a mention run must read exactly `@basename`. Review showed that is necessary
but **not sufficient**, because desktop parses the whole draft, not one link.

Concrete failure: the user types `see [ notes ` and then picks `a.rs`. iOS emits
`see [ notes [a.rs](zeron-file:a.rs)`. Desktop's parser starts at the first `[`,
`label_close` finds the chip's `](`, the label becomes ` notes [a.rs`, the basename check at
`composer.rs:775-780` fails, and line 792 advances `search` past the chip's `)`. The valid
inner link is never re-scanned. `file_mention_links` returns nothing. The message renders as
raw Markdown.

Every chip in that draft looks intact on the phone.

**The invariant has two clauses. A run keeps its mention attribute only if both hold.**

1. **Visible text.** The run reads exactly `@basename` for its path.
2. **Round trip.** The serialized draft, re-parsed through the ported `file_mention_links`,
   yields a mention at that run's serialized position carrying that run's path.

Both are needed, and neither implies the other. `markdown()` builds the label from the
**attribute**, so a run whose visible text has been mangled still serializes to a
well-formed link. Clause 2 alone would therefore accept it, and the composer would show
`@Info.plis` while sending `Info.plist`. Clause 1 is what keeps the screen and the wire
honest. Clause 2 is what catches everything clause 1 cannot see.

| Concern | Clause that covers it |
|---|---|
| The user typed into or deleted part of a chip | 1 |
| Two same-file chips merged into one run | 1 |
| Path is unsafe (`local_path_is_safe`, `composer.rs:728-736`) | 2 |
| Encoding does not round-trip (`composer.rs:774`) | 2 |
| Surrounding text swallows the link (the whole-text parse) | 2 |

`ComposerText` re-checks after every mutation and strips the attribute from every run that
fails either clause. The draft is one composer message, so a full parse per keystroke is a
short linear scan.

Together they also remove the need for any coalescing rule in `markdown()`. Every surviving
run is valid by construction, so one run is one link.

## Edit policy

`inheritedByAddedText = false` stops attribute bleed. It does not make a chip atomic.

**A run that breaks the invariant loses the attribute at once, on the mutation that broke
it.** The user sees the chip turn into plain text as they break it. What you see is what you
send.

| Action | Result |
|---|---|
| Type inside a chip | The run splits and both fragments fail the invariant. Both drop. |
| Backspace at a chip edge | The run reads `@Info.plis`. It drops. |
| Type `[` before a chip | The whole-text parse fails. That chip drops. |
| Delete the space between two chips for the same file | `AttributedString` merges the runs into one reading `@a.rs@a.rs`. It fails, and both chips drop. |
| Pick a file whose path is unsafe | The link would not re-parse, so no attribute is attached. Plain `@name` is inserted. |

Two chips for **different** files never merge, because their attribute values differ.

The rejected alternative was to serialize the label from the attribute, so every link stays
valid regardless of the visible text. That keeps links valid but sends `Info.plist` while
the composer shows `@Info.plis`. A silent gap between the screen and the wire is worse than
losing a chip the user was already editing.

Atomic backspace is out of scope. It needs the caret-jump behavior of a real text engine,
and getting it half right is worse than leaving it native.

**Scope of the damage.** `zeron-file:` is consumed only by the UI - the composer's chip
projection and `transcript.rs:671`. A repo-wide search finds it nowhere else. No engine or
harness code parses it. A lost chip therefore costs the chip, never the file: the agent
still receives a readable path in the prompt text either way.

## `ComposerSuggestions.swift`

An `@Observable` that owns the request state, the cache, and ranking.

- **Command cache key:** `(harness, deviceId, cwd)`, matching desktop's `SlashCacheKey`
  (`composer.rs:3236-3241`). The device belongs in the key because every project-less chat,
  on every device, shares the path `~`.
- **cwd resolution:** `chat.cwd`, then the space `path`, then `~`. `~` travels unexpanded
  and expands on the host (`CommandCache::normalize`, `commands.rs:109-117`).
- **Device to dial:** the chat's host device. `SearchFiles` with a `chatId` requires the
  dialed device to own that chat (`rpc.rs:501-502`).
- **Freshness:** stale while revalidate. A cached list draws at once with no spinner, and
  one `ListCommands` per popover open refreshes it. This module holds no TTL of its own.
  The engine owns expiry. One policy, in one place.
- **Command ranking:** a client-side filter over the returned list. Name match first, then
  description match.
- **Path results:** the host ranks and caps them (`repos.rs:1082`). The client debounces the
  query and discards a late response for a superseded query.
- **Dismissal:** desktop's `dismissed` rule (`composer.rs:3301-3304`). Dismissing keeps the
  popover closed while the caret moves inside the same token. Any edit reopens it.

## `ComposerPopover.swift`

Presentation only. It takes items, a loading flag, an optional error, and a callback.

A group header ("Commands" or "Files"), a scroll list capped in height, and one row per
item: an icon, the label, and a dim description. It renders above the composer pill.

## Changed modules

### `ComposerShell` (`ComposerView.swift:16`)

`@Binding var draft: String` becomes `@Binding var draft: ComposerText`.
`TextField(placeholder, text:axis:)` becomes
`TextEditor(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>)`
(`SwiftUI.swiftinterface:2943`, iOS 26.0+).

`TextEditor` loses three things `TextField` gave for free:

| Lost | Replacement |
|---|---|
| The `"Message"` placeholder | An overlay, hidden when the text is not empty |
| `lineLimit(1...7)` | Explicit height management for the 1-to-7 line morph |
| A transparent background | `scrollContentBackground(.hidden)` to keep the glass |

Two existing behaviors must be re-verified against `TextEditor`, not assumed:

- The `AnyLayout` trick that holds view identity across the compact-to-expanded morph
  (`ComposerView.swift:55-58`). Its comment says an `if`/`else` there drops keyboard focus
  mid-type.
- The `contentShape` plus masked `TapGesture` that focuses the editor from anywhere on the
  glass (`ComposerView.swift:127-129`).

The expansion heuristic (`draft.count > 26`, `draft.contains("\n")`, line 46) reads
`plainText`.

### `ComposerView` (`ComposerView.swift:206`)

Named explicitly, because it owns the send path that revision 1 left unspecified.

- `@State private var text` (line 212) becomes a `ComposerText`.
- `send()` (line 348) serializes with `draft.markdown()`, trims the **serialized** string,
  and passes it to `withAttachments(text:paths:)`.
- `clearDraft()` (line 392) resets the text and the selection together. Its existing comment
  warns that a focused editor commits pending autocorrect and marked text through the
  binding after a programmatic change, so the async re-clear stays.

### `WorkspaceStore.swift`

Two relay calls, next to `listModels` (line 422):

```swift
func listCommands(deviceId: String, harness: String, cwd: String?) async -> [SlashCommand]
func searchFiles(deviceId: String, chatId: String?, spaceId: String?, query: String) async -> [FileSearchMatch]
```

Both return types are new `Decodable` structs in `Entities.swift`, mirroring the Rust
shapes: `SlashCommand` is `{name, description, inputHint}` (`crates/proto/src/agent.rs:195`)
and `FileSearchMatch` is `{path, isDir}` (`crates/proto/src/entities.rs:299`).

`ListCommandsParams` is `{harness, cwd}` (`rpc.rs:92-98`). `FileSearchParams` needs exactly
one of `chatId` or `spaceId` (`rpc.rs:484-493`), accepts an optional `path` that applies
only to a space (`rpc.rs:491-494`), and caps the query at 256 characters (`rpc.rs:1551`).

### `DeviceRelayClient.swift`

`RelayError` gains an `isUnknownMethod(_ method:)` helper. See "Version skew".

### `NewSessionView.swift`

The second `ComposerShell` caller (line 221). It takes the same text model. Its prefill
(line 200) and its `trimmingCharacters` guard (line 347) move to `plainText`.

## Untouched

`SessionStore`, the sync layer, the transcript, and the engine. Drafts live in `@State`
only, so there is no stored `String` to migrate.

## Error handling

The popover must never show "No results" for a failure. Desktop learned this from a user
report (`composer.rs:3296-3300`). iOS copies the rule and the strings
(`composer.rs:3311-3335`):

| Case | Behavior |
|---|---|
| Host device offline or unreachable | "The session's device is unreachable" |
| Host runs an older zeron | "The session's device runs an older zeron - update it to search its files" |
| Search or discovery failed | "File search failed" / the matching command message |
| Host engine ignores `cwd` | It answers with its `$HOME` list. No error, fewer results. |
| No harness resolved | Empty popover. No request. |
| Chat has no `cwd` | Fall back to the space `path`, then to `~`. |

Tapping a `zeron-file:` link in the iOS transcript is **inert**. `MarkdownBlockView.swift:56`
hands the string to `URL(string:)`, and an unhandled scheme would otherwise reach `openURL`.
The renderer suppresses the tap for this scheme.

### Version skew

The relay flattens the typed Rust error into a plain string. `DeviceRelayClient.swift:225`
reads `err` as a `String`, so iOS cannot switch on an error kind the way desktop does.

`RpcError::UnknownMethod` renders as `"unknown method: {0}"` (`crates/rpc/src/lib.rs:139`).
`RelayError` gains an `isUnknownMethod(_ method:)` helper that matches the existing
`.rpc(message)` case against **the exact string** `"unknown method: \(method)"`, not a
loose prefix. Desktop already does exactly this for the same reason: at `state.rs:406-409`
it matches `RpcError::Failed(message)` against `format!("unknown method: {}", …)`, because
a relayed error arrives flattened there too.

A helper rather than a new case, because the actor's `pending` map holds only continuations
(`DeviceRelayClient.swift:42`) and does not know which method a reply belongs to. The caller
does. This keeps the change to an extension.

This is still a string match, and it is fragile. The alternative is adding a
machine-readable code to the server frame, which changes a shared protocol for one message.
This spec takes the exact match and records the trade.

## Testing

### Pure unit tests, in `ZeronTests`

These need no simulator and no host.

**`ComposerTrigger`** - the desktop rules, each with its own case:
- a `/` anywhere but offset 0 does not trigger
- a caret past the command token does not trigger
- a query containing `/` does not trigger
- `name@example.com` does not trigger
- `(@src` does trigger
- a second `@` in the query does not trigger
- the path token range extends past the caret to the next whitespace
- a range selection suppresses the trigger (a caller rule; it has no t3code equivalent)

**`ComposerText.markdown()`**
- label escaping of `\`, `[`, `]`
- percent encoding, including uppercase hex
- the directory trailing slash
- an intact chip emits exactly `[Info.plist](zeron-file:src/Info.plist)`

**The round-trip invariant** - these pin the edit policy:
- typing inside a chip drops the attribute from both fragments
- one backspace at a chip's trailing edge drops the attribute
- **a stray `[` typed before a chip drops that chip** (the review's failure case)
- deleting the space between two same-file chips drops both
- a picked path that fails `local_path_is_safe` never gets an attribute
- an untouched chip keeps its attribute across unrelated edits elsewhere
- text typed immediately after a chip never inherits the attribute

**The trigger veto**
- a caret inside an intact chip opens no popover
- a caret at either chip edge opens no popover

**Index mapping** - offset to `AttributedString.Index` and back, over text with multibyte
characters and emoji; `.ranges` suppresses; discontiguous `.ranges` suppresses.

**`ComposerSuggestions`**
- the cache key includes harness, device, and cwd
- a stale entry renders and refreshes
- a late response for a superseded query is discarded
- the `dismissed` rule holds across caret moves and breaks on an edit

### Format parity

The Swift port of `file_mention_links` and friends must agree with the Rust original. Lift
the fixtures from the Rust tests in `composer.rs` (including the `%0A` rejection at
`composer.rs:5961`) into the Swift tests as literal expected values.

There is no shared golden-vector file. Building one for four functions is more machinery
than it earns.

### Known gap

The repo has no script that runs `ZeronTests`. `scripts/` holds `e2e-smoke.sh` for the Rust
side only. iOS tests run from Xcode. This epic does not add CI wiring for them, so these
tests gate nothing automatically.

### Manual E2E, against a real host device

- Open a project with installed project skills, type `/`, confirm the skills appear.
- Open a project without them, confirm they do not.
- Type `@`, pick a file, send, confirm the host receives the `zeron-file:` link.
- Confirm the sent message renders as a link in the iOS transcript, and that tapping it does
  nothing.
- Confirm the 1-to-7 line morph, the placeholder, the glass, and tap-to-focus all still look
  and behave as they do today.
- Type into a chip and confirm it turns into plain text at once, on that keystroke.
- Tap inside an intact chip and confirm no popover opens.

## Risks

### 1. Project skills need commits that are not on `main`

`crates/engine/src/commands.rs` is on `mine` and not on `main`.

This is narrower than revision 1 claimed. `main` already serves `LIST_COMMANDS` by parsing
`ListModelsParams`, and serde ignores the extra `cwd` field. So a phone talking to a `main`
host still gets a command list - it gets the `$HOME` list, without project skills. Landing
`6c78309` and `94f117e` is what makes project skills appear. It is step 0 of the epic, and
it is not iOS work.

### 2. The rich text platform surface is unverified

No SDK header proves that a background-styled run paints inside `TextEditor`, nor how the
control behaves under real editing. **The first task in the plan is a throwaway simulator
spike.** Its checklist:

- a chip run paints with the mono font and the code wash
- typing at both chip boundaries
- backspace into a chip
- the 1-to-7 line morph, the placeholder overlay, the glass, and tap-to-focus
- **`invalidationConditions = [.textChanged]`** - does the framework strip the attribute as
  documented?
- **marked text and IME.** Stripping an attribute mid-composition may cancel it. The repo
  already documents this class of bug at `ComposerView.swift:392-402`.
- **undo and redo.** The invariant pass is a second programmatic mutation after each user
  edit. System undo restores states the pass then re-mutates. Desktop needed its own undo
  stack (`composer.rs:635-641`).
- **a programmatic clear while focused**, with a selection binding pointing into the old
  string
- **copy and paste of a chip** - does the custom attribute survive?

If the spike fails, `ComposerTrigger`, `ComposerSuggestions`, `ComposerPopover`, and both
RPC calls are unaffected. The composer falls back to plain text with the Markdown visible.
That fallback is the reason for the module boundary above.

### 3. Two call sites

`ComposerView.swift:249` and `NewSessionView.swift:221` both use `ComposerShell`. The text
model change hits both.

## References

- `docs/slash-commands.md` - the per-workspace discovery design
- `crates/ui/src/composer.rs` - the desktop implementation this mirrors
- t3code `packages/shared/src/composerTrigger.ts` - the trigger shape, though this spec
  ports desktop's rules rather than t3code's
- t3code `apps/mobile/src/features/threads/ComposerCommandPopover.tsx` - the popover shape
