#!/usr/bin/env bash
# Throwaway probe (.scratch only): print each seeded chat's title, note and
# last activity from the running demo engine.
set -euo pipefail
cd "$(dirname "$0")/../.."
cargo run -q -p zeron-rpc --example rpc_probe -- ws://127.0.0.1:27941 WatchChats '{}' --stream 1 \
  | python3 -c '
import json, sys
frame = json.loads(sys.stdin.read())
rows = frame.get("chats", frame) if isinstance(frame, dict) else frame
for c in rows:
    note = c.get("note")
    note = f'"'"'{note["color"]}: {note["text"]!r}'"'"' if note else "-"
    print(f'"'"'{c.get("title") or "(untitled)":36} archived={str(c.get("archived")):5} note={note}'"'"')
'
