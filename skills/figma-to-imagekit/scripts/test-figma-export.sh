#!/usr/bin/env bash
# Smoke for figma-export.sh. The Figma URL parse and the usage/error contract
# are fully offline. The resize→pngquant leg runs for real when sips + pngquant
# are present (they are, on the target macOS box) against a generated PNG, with
# --no-upload so no ImageKit key/network is needed; it's skipped with a note
# elsewhere. The actual upload is not asserted.
#
#   bash skills/figma-to-imagekit/scripts/test-figma-export.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/figma-export.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/figma-export-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
skip() { echo "  ⊘ $* (skipped)"; }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has() { grep -qF "$2" <<<"$1" || fail "$3 — got: $1"; }

echo "figma-export smoke: root=$ROOT"

# --- parse-url (pure, offline) ----------------------------------------------
O="$(bash "$SCRIPT" parse-url 'https://figma.com/design/abc123XYZ/My-File?node-id=1166-3012')"; echo "  → $O"
has "$O" '"ok":true' "design URL parses"
has "$O" '"fileKey":"abc123XYZ"' "extracts the fileKey"
has "$O" '"nodeId":"1166:3012"' "converts node-id 1166-3012 → 1166:3012"
pass "parse-url design URL → fileKey + colon-form nodeId"

O="$(bash "$SCRIPT" parse-url 'https://www.figma.com/file/KEY999/Name?node-id=12%3A34&t=x')"
has "$O" '"fileKey":"KEY999"' "/file/ URLs work too"
has "$O" '"nodeId":"12:34"' "decodes an encoded colon"
pass "parse-url /file/ URL with encoded colon"

O="$(bash "$SCRIPT" parse-url 'https://figma.com/design/justkey/Name')"
has "$O" '"nodeId":null' "no node-id → null"
pass "parse-url without node-id → nodeId:null"

O="$(bash "$SCRIPT" parse-url 'https://example.com/nope' 2>/dev/null || true)"
has "$O" '"ok":false' "a non-figma URL has no fileKey"
pass "parse-url junk URL → ok:false"

# --- usage / error contract --------------------------------------------------
rc=0; bash "$SCRIPT" run --url http://x/y.png >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "run without --name should exit 2 (got $rc)"
pass "run without --name → exit 2"

rc=0; bash "$SCRIPT" run --name a.png >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "run without a source should exit 2 (got $rc)"
pass "run without --url/--file → exit 2"

rc=0; bash "$SCRIPT" run --name a.png --file /x.png >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "run without --folder (and no --no-upload) should exit 2 (got $rc)"
pass "run without --folder and no --no-upload → exit 2"

rc=0; bash "$SCRIPT" bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "unknown subcommand should exit 2 (got $rc)"
pass "unknown subcommand → exit 2"

# --- non-PNG source rejected -------------------------------------------------
if command -v sips >/dev/null && command -v pngquant >/dev/null; then
  echo "not a png" > "$ROOT/fake.png"
  O="$(bash "$SCRIPT" run --file "$ROOT/fake.png" --name out.png --no-upload 2>/dev/null || true)"; echo "  → $O"
  has "$O" 'source-not-png' "a non-PNG file is rejected before optimizing"
  pass "run --file <not-a-png> → ok:false (source-not-png)"

  # --- real resize+optimize leg, no upload ----------------------------------
  SRC="$ROOT/big.png"
  # A 2000x2000 noisy PNG so pngquant has something to shrink.
  sips -s format png -z 2000 2000 /System/Library/CoreServices/DefaultDesktop.heic --out "$SRC" >/dev/null 2>&1 \
    || sips -s format png --resampleHeightWidth 2000 2000 \
         "$(/bin/ls /System/Library/Desktop\ Pictures/*.heic 2>/dev/null | head -1)" --out "$SRC" >/dev/null 2>&1 || true
  if [[ -f "$SRC" ]] && file "$SRC" | grep -qi 'PNG image'; then
    O="$(bash "$SCRIPT" run --file "$SRC" --name hero.png --resize 640 --no-upload)"; echo "  → $O"
    has "$O" '"ok":true' "optimize leg succeeds"
    has "$O" '"uploaded":false' "--no-upload skips the CDN step"
    has "$O" '"savings":"' "reports a savings percentage"
    pass "run --file --resize --no-upload → real resize+pngquant result"
  else
    skip "real resize+optimize leg (no seed PNG available)"
  fi
else
  skip "PNG-source rejection + resize/optimize leg (sips/pngquant absent)"
fi

echo ""
echo "✅ figma-export smoke PASSED ($PASS checks)"
