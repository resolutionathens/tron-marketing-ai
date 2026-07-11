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

# --- oauth-status (curl PATH-stubbed, fully offline) -------------------------
# Mirrors tools/confluence/test-fetch-confluence.sh: a fake `curl` ahead of the
# real one on PATH, keyed off STUB_RESP / STUB_FAIL, so no real broker/network
# is touched.
STUB_BIN="$ROOT/bin"; mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/curl" <<'SH'
#!/usr/bin/env bash
if [[ "${STUB_FAIL:-0}" == 1 ]]; then exit 7; fi
printf '%s' "${STUB_RESP:-}"
SH
chmod +x "$STUB_BIN/curl"

O="$(PATH="$STUB_BIN:$PATH" STUB_RESP='{"connected":true,"expiresAt":1999999999}' \
     FIGMA_OAUTH_ACCESS_TOKEN=dummy bash "$SCRIPT" oauth-status)"; echo "  → $O"
has "$O" '"connected":true' "connected:true passes through"
has "$O" '"expiresAt":1999999999' "expiresAt passes through"
pass "oauth-status → connected:true (stubbed broker response)"

O="$(PATH="$STUB_BIN:$PATH" STUB_RESP='{"connected":false}' \
     FIGMA_OAUTH_ACCESS_TOKEN=dummy bash "$SCRIPT" oauth-status)"; echo "  → $O"
has "$O" '"connected":false' "connected:false surfaces"
has "$O" '/figma/oauth/start' "prompt names the connect route"
pass "oauth-status → connected:false includes a one-line connect prompt"

O="$(PATH="$STUB_BIN:$PATH" STUB_FAIL=1 \
     FIGMA_OAUTH_ACCESS_TOKEN=dummy bash "$SCRIPT" oauth-status)"; echo "  → $O"
has "$O" '"connected":null' "unreachable broker degrades to connected:null, not a failure"
has "$O" '"ok":true' "unreachable broker still exits ok — never blocks the export"
pass "oauth-status → broker unreachable degrades gracefully"

# Stub cloudflared as a no-session CLI (prints nothing, like a logged-out box)
# so this doesn't depend on — or hit — whatever real Access session is cached
# on the machine running the tests.
cat > "$STUB_BIN/cloudflared" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$STUB_BIN/cloudflared"
O="$(PATH="$STUB_BIN:$PATH" FIGMA_OAUTH_ACCESS_TOKEN="" bash "$SCRIPT" oauth-status)"; echo "  → $O"
has "$O" '"connected":null' "no token (cloudflared session absent and no override) → connected:null"
pass "oauth-status → no Access token available degrades gracefully"

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
