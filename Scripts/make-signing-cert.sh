#!/usr/bin/env bash
# Ensures EXACTLY ONE stable self-signed code-signing identity named
# "CmdTab Self-Signed" in the login keychain, so the macOS Accessibility /
# Input Monitoring grant persists across rebuilds (TCC keys the grant on the
# signing certificate, not the per-build cdhash). Safe to re-run: it collapses
# any duplicate certs down to a single one.
set -euo pipefail

NAME="CmdTab Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# SHA-1 hashes of every code-signing identity matching NAME (untrusted is fine).
matching_hashes() {
  security find-identity -p codesigning 2>/dev/null | awk -v n="$NAME" 'index($0, n) {print $2}'
}

hashes="$(matching_hashes || true)"
count="$(printf '%s\n' "$hashes" | grep -c . || true)"

if [ "$count" -eq 1 ]; then
  echo "Signing identity '$NAME' already exists (single, clean) — nothing to do."
  exit 0
fi

if [ "$count" -gt 1 ]; then
  echo "Found $count duplicate '$NAME' certificates — removing all to start clean…"
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    security delete-certificate -Z "$h" "$KEYCHAIN" >/dev/null 2>&1 || true
  done <<EOF
$hashes
EOF
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

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P cmdtab \
  -T /usr/bin/codesign -T /usr/bin/security

# Let codesign use the private key without a GUI prompt on every build.
# Prompts once for your login keychain password.
security set-key-partition-list -S apple-tool:,apple: "$KEYCHAIN" >/dev/null 2>&1 || \
  echo "note: could not set key partition list; codesign may prompt once (click 'Always Allow')."

echo
final="$(matching_hashes || true)"
fcount="$(printf '%s\n' "$final" | grep -c . || true)"
if [ "$fcount" -eq 1 ]; then
  echo "Created a single signing identity '$NAME' (shows as untrusted — fine for signing)."
  echo "Next: clear stale permission entries and re-grant once —"
  echo "  tccutil reset Accessibility com.local.cmdtab"
  echo "  tccutil reset ListenEvent  com.local.cmdtab"
  echo "  ./Scripts/bundle.sh debug && open build/CmdTab.app"
else
  echo "warning: expected 1 identity but found $fcount. Fallback — create via Keychain Access:"
  echo "  Keychain Access → Certificate Assistant → Create a Certificate…"
  echo "  Name: $NAME | Identity Type: Self Signed Root | Certificate Type: Code Signing"
  exit 1
fi
