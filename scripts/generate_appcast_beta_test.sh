#!/usr/bin/env bash
# Tests for generate_appcast_beta.sh: superset ordering, standalone fallback,
# and signature passthrough.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export SPARKLE_EDDSA_SIGNATURE="sig-beta"
export SPARKLE_DMG_LENGTH="1234"
echo "<p>beta notes</p>" > "$TMP/notes.html"

fail() { echo "FAIL: $1"; exit 1; }

# The canonical generator emits TWO items per release: a macOS item whose
# <sparkle:version> is the build number, and a Windows item whose
# <sparkle:version> is the full 4-segment version.

# Case 1: no stable appcast -> the beta feed's own two items only.
OUT=$("$SCRIPT_DIR/generate_appcast_beta.sh" 1.8.0 5601 "Mon, 28 Jul 2026 00:00:00 +0000" \
  https://example.com/beta.dmg https://example.com/beta.exe "$TMP/notes.html")
echo "$OUT" | grep -q "<sparkle:version>5601</sparkle:version>" || fail "beta item missing sparkle:version"
[ "$(echo "$OUT" | grep -c '<item>')" -eq 2 ] || fail "expected exactly 2 items without stable feed"

# Case 2: with a stable appcast -> beta items first, stable items appended, valid XML.
SPARKLE_EDDSA_SIGNATURE="sig-stable" SPARKLE_DMG_LENGTH="999" \
  "$SCRIPT_DIR/generate_appcast.sh" 1.7.0.117 117 "Sun, 27 Jul 2026 00:00:00 +0000" \
  https://example.com/stable.dmg https://example.com/stable.exe "$TMP/notes.html" > "$TMP/stable.xml"
OUT=$("$SCRIPT_DIR/generate_appcast_beta.sh" 1.8.0 5601 "Mon, 28 Jul 2026 00:00:00 +0000" \
  https://example.com/beta.dmg https://example.com/beta.exe "$TMP/notes.html" "$TMP/stable.xml")
[ "$(echo "$OUT" | grep -c '<item>')" -eq 4 ] || fail "expected 4 items in superset feed"
BETA_LINE=$(echo "$OUT" | grep -n "<sparkle:version>5601</sparkle:version>" | head -1 | cut -d: -f1)
STABLE_LINE=$(echo "$OUT" | grep -n "<sparkle:version>117</sparkle:version>" | head -1 | cut -d: -f1)
[ "$BETA_LINE" -lt "$STABLE_LINE" ] || fail "beta item must precede stable item"
echo "$OUT" | grep -q "sig-beta" || fail "beta signature missing"
echo "$OUT" | grep -q "sig-stable" || fail "stable signature not preserved"
echo "$OUT" | python3 -c "import sys,xml.dom.minidom; xml.dom.minidom.parseString(sys.stdin.read())" \
  || fail "output is not well-formed XML"

echo "PASS: generate_appcast_beta_test"
