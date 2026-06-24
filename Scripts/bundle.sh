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

# Sign with a stable self-signed identity when available so the macOS
# Accessibility / Input Monitoring grant persists across rebuilds (TCC keys the
# grant on the signing certificate, not the per-build cdhash). Ad-hoc signing
# does NOT persist — every code change yields a new cdhash and macOS re-prompts.
# Create the identity once with ./Scripts/make-signing-cert.sh
IDENTITY="${CMDTAB_SIGN_IDENTITY:-CmdTab Self-Signed}"
# Note: -v (valid-only) is intentionally omitted — a self-signed cert is
# untrusted (CSSMERR_TP_NOT_TRUSTED) yet signs fine, which is all we need.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Signed with '$IDENTITY'."
else
  codesign --force --deep --sign - "$APP"
  echo "warning: signing identity '$IDENTITY' not found — used ad-hoc signing." >&2
  echo "         Accessibility permission will NOT persist across code changes." >&2
  echo "         Run ./Scripts/make-signing-cert.sh once to fix this." >&2
fi

echo "Built $APP"
