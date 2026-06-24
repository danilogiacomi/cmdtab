#!/usr/bin/env bash
# Creates a stable self-signed code-signing identity named "CmdTab Self-Signed"
# in the login keychain, so the macOS Accessibility / Input Monitoring grant
# persists across rebuilds. Run this ONCE. Safe to re-run (no-op if it exists).
#
# Why: ad-hoc signing keys the TCC permission to the per-build cdhash, so every
# code change re-prompts. A stable certificate keys it to the cert + bundle id.
set -euo pipefail

NAME="CmdTab Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# -v (valid-only) omitted on purpose: a self-signed cert is untrusted but signs.
if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Signing identity '$NAME' already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Generating self-signed code-signing certificate '$NAME'…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# OpenSSL 3 defaults to AES-256/SHA-256 PKCS#12, which macOS `security import`
# cannot MAC-verify ("MAC verification failed"). Use -legacy (3DES/RC2/SHA1)
# when supported so the keychain can read it; older openssl/LibreSSL omit it.
LEGACY=""
if openssl pkcs12 -export -help 2>&1 | grep -q -- "-legacy"; then
  LEGACY="-legacy"
fi
openssl pkcs12 -export $LEGACY -out "$TMP/identity.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout pass:cmdtab >/dev/null 2>&1

# Import into the login keychain and allow codesign to use the key.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P cmdtab \
  -T /usr/bin/codesign -T /usr/bin/security

# Allow apple tools (codesign) to use the private key without a GUI prompt each
# build. This may ask for your login keychain password once.
security set-key-partition-list -S apple-tool:,apple: "$KEYCHAIN" >/dev/null 2>&1 || \
  echo "note: could not set key partition list automatically; codesign may prompt once (click 'Always Allow')."

echo
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "Created signing identity '$NAME' (shows as untrusted — that's fine for signing)."
  echo "Next: clear stale permission entries and re-grant once —"
  echo "  tccutil reset Accessibility com.local.cmdtab"
  echo "  tccutil reset ListenEvent  com.local.cmdtab"
  echo "  ./Scripts/bundle.sh debug && open build/CmdTab.app"
else
  echo "warning: identity not found after import."
  echo "Fallback — create it via Keychain Access:"
  echo "  Keychain Access → Certificate Assistant → Create a Certificate…"
  echo "  Name: $NAME | Identity Type: Self Signed Root | Certificate Type: Code Signing"
  exit 1
fi
