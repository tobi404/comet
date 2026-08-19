#!/usr/bin/env bash
# Ticket 02 demo (throwaway, .scratch only): seed six chats, put a Chat Note on
# five of them - one per Colour Slot - archive one noted chat, and open the app.
#
#   .scratch/chat-notes-impl/note-bar-demo.sh dark
#   .scratch/chat-notes-impl/note-bar-demo.sh light
set -euo pipefail
cd "$(dirname "$0")/../.."

MODE="${1:-dark}"
DAEMON_DIR=/tmp/zeron-note-daemon
UI_DIR=/tmp/zeron-note-ui
IPC=27941

cargo build -p zeron -q

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

if [[ ! -f "$DAEMON_DIR/.demo-seeded" ]]; then
  echo "▸ seeding six chats, five notes, one archived"
  DEV=$(probe LocalDevice '{}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["deviceId"])')
  SID=$(uuidgen | tr 'A-Z' 'a-z')
  probe Mutate "{\"op\":\"createSpace\",\"spaceId\":\"$SID\",\"deviceId\":\"$DEV\",\"path\":\"$HOME/github/zeron\"}" >/dev/null
  seed() { # title branch age_hours slot note_text archived
    local id; id=$(uuidgen | tr 'A-Z' 'a-z')
    probe Mutate "{\"op\":\"createChat\",\"chatId\":\"$id\",\"spaceId\":\"$SID\",\"config\":{\"harness\":\"mock\",\"model\":\"fable-5\",\"reasoning\":null,\"sandbox\":\"workspace-write\"}}" >/dev/null
    probe Mutate "{\"op\":\"renameChat\",\"chatId\":\"$id\",\"title\":\"$1\"}" >/dev/null
    probe Mutate "{\"op\":\"setChatBranch\",\"chatId\":\"$id\",\"branch\":\"$2\"}" >/dev/null
    probe Mutate "{\"op\":\"setChatActivity\",\"chatId\":\"$id\",\"lastMessageAt\":$(( ($(date +%s) - $3*3600) * 1000 ))}" >/dev/null
    if [[ "$4" != none ]]; then
      probe Mutate "{\"op\":\"setChatNote\",\"chatId\":\"$id\",\"note\":{\"text\":\"$5\",\"color\":\"$4\"}}" >/dev/null
    fi
    if [[ "${6:-}" == archived ]]; then
      probe Mutate "{\"op\":\"setChatArchived\",\"chatId\":\"$id\",\"archived\":true}" >/dev/null
    fi
  }
  seed "Native Zeron Rust Rewrite"       zeron/main                 0  rose   "Ship behind the flag first"
  seed "Rebalance Player Stats Caps"     zeron/rebalance-stats      2  amber  "Waiting on the balance pass"
  seed "Craft Premium TCG Experience"    zeron/craft-premium        4  green  "Approved by design"
  seed "Initial Context Exploration"     zeron/initial-context      6  none   ""
  seed "Sidebar Resort Glide Regression" zeron/sidebar-resort       9  sky    "Repro is in the ticket"
  seed "Loro Registry Row Batching"      zeron/registry-rows        14 violet "Parked until the sync lands" archived
  touch "$DAEMON_DIR/.demo-seeded"
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
