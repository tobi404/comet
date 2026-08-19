#!/usr/bin/env bash
# Ticket 04 demo (throwaway, .scratch only): reuse ticket 02's seeded workspace
# and add the fixtures the Note Card has to survive, then open the app so the
# card can be driven with the pointer.
#
#   .scratch/chat-notes-impl/note-card-demo.sh dark
#   .scratch/chat-notes-impl/note-card-demo.sh light
#
# The fixtures, and what each one is for:
#
#   "Ten Line Fixture"    a note whose own newlines carry it past the card's
#                         ten-line clamp at ANY width. It must elide cleanly on
#                         the tenth line, and the card must neither scroll nor
#                         grow past ten lines.
#   "URL Fixture"         one unbreakable token far wider than the card. It must
#                         CLIP against the card's rounded edge, never widen the
#                         card past 320px.
#   "Capped Note Fixture" exactly 280 characters, the authoring cap. Drag the
#                         window narrow until the card is at its 220px floor:
#                         the whole note must still fit inside ten lines with no
#                         ellipsis. One pixel narrower and the card must refuse
#                         to open at all, rather than being shoved back over the
#                         sidebar.
#
# ONE FIXTURE FROM THE TICKET CANNOT BE SEEDED HERE. The ticket names a
# 671-character note, and no note that long can reach storage through this
# path: `RegistryDoc::set_chat_note` truncates at 280 characters, so the write
# below arrives cut. An over-cap note only exists when iOS writes the registry
# row directly (spec known limit 6 / ADR 0001), which this build does not do.
# The "Ten Line Fixture" stands in for it: it exercises the same clamp, the same
# elide and the same no-scroll rule, with a note the write path really stores.
#
# What to look for, in order:
#
#   1. rest on a noted row  → card after ~350ms, alongside the sidebar,
#                             centred on the row, tinted in the note's colour
#   2. pointer off the row  → gone ~120ms later; jitter inside the row does not
#                             flicker it
#   3. click the row        → gone at once, and it does NOT come back while the
#                             pointer stays on that row
#   4. right-click the row  → context menu, no card under it
#   5. scroll the sidebar / let a row resort → gone at once
#   6. open the archived shelf and rest on the archived noted row → same card
#   7. drag the window narrow → the card shrinks to the room, then stops opening
set -euo pipefail
cd "$(dirname "$0")/../.."

MODE="${1:-dark}"
DAEMON_DIR=/tmp/zeron-note-daemon
UI_DIR=/tmp/zeron-note-ui
IPC=27941

cargo build -p zeron -q

if [[ ! -f "$DAEMON_DIR/.demo-seeded" ]]; then
  echo "▸ no seeded workspace — run note-bar-demo.sh once first" >&2
  exit 1
fi

echo "▸ engine daemon on :$IPC"
env ZERON_DATA_DIR="$DAEMON_DIR" ZERON_IPC_PORT=$IPC ZERON_HARNESS=mock RUST_LOG=warn \
  ./target/debug/zeron headless &
DAEMON_PID=$!
trap 'kill $DAEMON_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 40); do
  (exec 3<>/dev/tcp/127.0.0.1/$IPC) 2>/dev/null && { exec 3>&-; break; }
  sleep 0.25
done

probe() { cargo run -q -p zeron-rpc --example rpc_probe -- "ws://127.0.0.1:$IPC" "$@"; }

if [[ ! -f "$DAEMON_DIR/.card-seeded" ]]; then
  echo "▸ seeding the Note Card fixtures"
  # WatchSpaces streams a bare JSON array of Space rows (verified against a
  # scratch daemon), so the space id is rows[0]["id"].
  SID=$(probe WatchSpaces '{}' --stream 1 | python3 -c '
import json, sys
rows = json.load(sys.stdin)
if not rows:
    sys.exit("no space in the seeded workspace - run note-bar-demo.sh first")
print(rows[0]["id"])')

  seed() { # title slot text
    local id; id=$(uuidgen | tr 'A-Z' 'a-z')
    probe Mutate "{\"op\":\"createChat\",\"chatId\":\"$id\",\"spaceId\":\"$SID\",\"config\":{\"harness\":\"mock\",\"model\":\"fable-5\",\"reasoning\":null,\"sandbox\":\"workspace-write\"}}" >/dev/null
    probe Mutate "{\"op\":\"renameChat\",\"chatId\":\"$id\",\"title\":\"$1\"}" >/dev/null
    # The note goes through python so newlines and slashes survive intact.
    python3 - "$IPC" "$id" "$2" "$3" <<'PY'
import json, subprocess, sys
ipc, chat, slot, text = sys.argv[1:5]
payload = json.dumps({"op": "setChatNote", "chatId": chat, "note": {"text": text, "color": slot}})
subprocess.run(
    ["cargo", "run", "-q", "-p", "zeron-rpc", "--example", "rpc_probe", "--",
     f"ws://127.0.0.1:{ipc}", "Mutate", payload],
    check=True, stdout=subprocess.DEVNULL)
PY
  }

  # Fourteen own lines: four past the clamp at every card width.
  TEN_LINE=$(python3 -c '
print("\n".join(f"line {n:02d} of a note that runs past the clamp" for n in range(1, 15)))')
  CAPPED=$(python3 -c '
body = ("A note written right up against the authoring cap, to check that the whole of "
        "it still fits inside ten lines when the window is dragged down to the narrow "
        "floor and the card has no room left to grow into. Nothing here may elide at "
        "the floor width, and nothing may scroll.")
print(body[:280].ljust(280, "."))')

  seed "Ten Line Fixture" violet "$TEN_LINE"
  seed "URL Fixture" sky "https://github.com/zeronsh/comet/blob/main/crates/ui/src/shell/note_card.rs#L1-L200"
  seed "Capped Note Fixture" amber "$CAPPED"
  touch "$DAEMON_DIR/.card-seeded"
fi

mkdir -p "$UI_DIR"
python3 - "$UI_DIR/ui-settings.json" "$MODE" <<'PY'
import json, os, sys
path, mode = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
data["appearance"] = mode
with open(path, "w") as f:
    json.dump(data, f)
PY

echo "▸ opening zeron - $MODE"
ZERON_DATA_DIR="$UI_DIR" ZERON_IPC_PORT=$IPC RUST_LOG=warn ./target/debug/zeron
