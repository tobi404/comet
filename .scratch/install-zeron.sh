#!/bin/bash
# Install the freshly built Zeron over /Applications/Zeron.app.
# RUN THIS FROM A PLAIN TERMINAL WINDOW, NOT FROM A ZERON-HOSTED SESSION.
# Quitting Zeron kills every agent session it hosts.
set -euo pipefail

SRC="/Users/bekademuradze/Documents/AppDev/comet/target/package/Zeron.app"
BACKUP="/Users/bekademuradze/Zeron-backup-20260819-1348.app"

[ -d "$SRC" ] || { echo "missing build: $SRC"; exit 1; }
[ -d "$BACKUP" ] || { echo "missing backup: $BACKUP"; exit 1; }

echo "quitting Zeron..."
osascript -e 'quit app "Zeron"' || true

for i in $(seq 1 30); do
  ps -eo comm | grep -q 'Zeron\.app/Contents/MacOS/zeron' || break
  sleep 1
done

if ps -eo comm | grep -q 'Zeron\.app/Contents/MacOS/zeron'; then
  echo "Zeron is still running after 30s. Quit it by hand, then re-run."
  exit 1
fi

echo "installing..."
rm -rf /Applications/Zeron.app
ditto "$SRC" /Applications/Zeron.app

echo "launching..."
open /Applications/Zeron.app
echo "done. rollback: rm -rf /Applications/Zeron.app && ditto $BACKUP /Applications/Zeron.app"
