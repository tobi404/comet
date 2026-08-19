#!/usr/bin/env bash
# Ticket 03 demo (throwaway, .scratch only): reuse ticket 02's seeded workspace
# (six chats, five notes, one archived) and open the app so the Note Editor can
# be driven from the chat row's context menu.
#
#   .scratch/chat-notes-impl/note-editor-demo.sh dark
#   .scratch/chat-notes-impl/note-editor-demo.sh light        # theme
#   ZERON_OPEN_DIALOG=note .scratch/chat-notes-impl/note-editor-demo.sh dark
#
# The daemon and the app both run detached, so the caller can probe the engine
# while the window is up:
#
#   cargo run -q -p zeron-rpc --example rpc_probe -- \
#     ws://127.0.0.1:27941 WatchChats '{}' --stream 1
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
  nohup ./target/debug/zeron headless >/tmp/zeron-note-daemon.log 2>&1 &
for _ in $(seq 1 40); do
  (exec 3<>/dev/tcp/127.0.0.1/$IPC) 2>/dev/null && { exec 3>&-; break; }
  sleep 0.25
done

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
env ZERON_DATA_DIR="$UI_DIR" ZERON_IPC_PORT=$IPC RUST_LOG=warn \
  nohup ./target/debug/zeron >/tmp/zeron-note-ui.log 2>&1 &
echo "▸ ui pid $!"
