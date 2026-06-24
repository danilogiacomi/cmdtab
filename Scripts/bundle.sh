#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CmdTab.app"

swift build -c "$CONFIG" --product CmdTabApp
BIN="$ROOT/.build/$CONFIG/CmdTabApp"

if [ ! -f "$BIN" ]; then
  echo "error: built binary not found at $BIN" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/CmdTab"
cp "$ROOT/Scripts/CmdTab-Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc sign so a stable code identity persists across rebuilds, which keeps
# the granted Accessibility permission attached to the app.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
