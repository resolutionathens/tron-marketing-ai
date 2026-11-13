#!/usr/bin/env bash
# Smoke for confluence.sh + confluence-lib.sh. The real acli fetch needs
# network/auth and isn't asserted. The pure surface is fully testable offline:
# page-id extraction from raw ids, full URLs, and decoded tiny links, the
# referenced-image scan, and the usage/error contract.
#
#   bash skills/confluence/scripts/test-confluence.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/confluence.sh"
LIB="$(cd "$HERE/../../../tools/confluence" && pwd)/confluence-lib.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/confluence-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has() { grep -qF "$2" <<<"$1" || fail "$3 — got: $1"; }

echo "confluence smoke: root=$ROOT"

# --- confluence-lib: cl_extract_page_id (pure) -------------------------------
# shellcheck source=/dev/null
source "$LIB"

ID="$(cl_extract_page_id 3851517965)"; [[ "$ID" == 3851517965 ]] || fail "raw id should pass through (got: $ID)"
pass "cl_extract_page_id raw → same id"

ID="$(cl_extract_page_id 'https://facilitron.atlassian.net/wiki/spaces/kimji/pages/3851517965/Page+Title')"
[[ "$ID" == 3851517965 ]] || fail "full URL should extract the id (got: $ID)"
pass "cl_extract_page_id full /pages/<id>/ URL → id"

ID="$(cl_extract_page_id 'https://facilitron.atlassian.net/wiki/spaces/x/pages/777/T?focusedCommentId=9#frag')"
[[ "$ID" == 777 ]] || fail "query/fragment should be stripped (got: $ID)"
pass "cl_extract_page_id strips ?query and #fragment"

ID="$(cl_extract_page_id 'https://facilitron.atlassian.net/wiki/x/DYCR5Q')"
[[ "$ID" == 3851517965 ]] || fail "tiny link should decode offline (got: $ID)"
pass "cl_extract_page_id tiny link → decoded id, offline"

rc=0; cl_extract_page_id 'just some text' >/dev/null || rc=$?
[[ "$rc" -eq 1 ]] || fail "non-URL garbage should be unparseable (rc 1, got $rc)"
pass "cl_extract_page_id garbage → rc 1 (unparseable)"

# --- confluence-lib: cl_referenced_images (pure) -----------------------------
cat > "$ROOT/body.html" <<'XML'
<p><ac:image><ri:attachment ri:filename="hero.png" /></ac:image></p>
<p><ac:image><ri:attachment ri:filename="diagram.png" /></ac:image></p>
<p>reuse <ac:image><ri:attachment ri:filename="hero.png" /></ac:image></p>
XML
OUT="$(cl_referenced_images < "$ROOT/body.html")"
[[ "$(wc -l <<<"$OUT" | tr -d ' ')" == 2 ]] || fail "should de-dup to 2 images (got: $OUT)"
[[ "$(head -1 <<<"$OUT")" == hero.png ]] || fail "first image should be hero.png in doc order (got: $OUT)"
pass "cl_referenced_images → doc-order, de-duplicated filenames"

# --- script: resolve (offline cases) -----------------------------------------
O="$(bash "$SCRIPT" resolve 3851517965)"; echo "  → $O"
has "$O" '"ok":true' "raw resolve ok"
has "$O" '"pageId":"3851517965"' "raw resolve id"
has "$O" '"source":"raw"' "raw resolve source"
pass "resolve <raw id> → {ok,pageId,source:raw}"

O="$(bash "$SCRIPT" resolve 'https://facilitron.atlassian.net/wiki/spaces/k/pages/42/T')"
has "$O" '"pageId":"42"' "url resolve id"
has "$O" '"source":"url"' "url resolve source"
pass "resolve <full URL> → {ok,pageId,source:url}"

# Tiny links decode offline; curl is shadowed so a redirect follow would fail.
NOCURL="$ROOT/nocurl"; mkdir -p "$NOCURL"
printf '#!/bin/sh\necho "curl called: $*" >&2; exit 99\n' > "$NOCURL/curl"; chmod +x "$NOCURL/curl"
O="$(PATH="$NOCURL:$PATH" bash "$SCRIPT" resolve 'https://facilitron.atlassian.net/wiki/x/K4A-AgE')"
has "$O" '"pageId":"4332683307"' "tiny resolve id (CCAL-2229 regression: was 4)"
has "$O" '"source":"tiny"' "tiny resolve source"
pass "resolve <tiny link> → decoded offline, {ok,pageId,source:tiny}"

rc=0; O="$(PATH="$NOCURL:$PATH" bash "$SCRIPT" resolve 'https://facilitron.atlassian.net/wiki/x/MYA5AgF')" || rc=$?
[[ "$rc" == 1 ]] || fail "undecodable tiny link should exit 1 (got $rc: $O)"
has "$O" '"ok":false' "undecodable tiny link reports failure"
has "$O" '"error":"could-not-resolve"' "undecodable tiny link error code"
pass "resolve <undecodable tiny link> → {ok:false}, exit 1, no guessed id"

# --- script: images subcommand ----------------------------------------------
O="$(bash "$SCRIPT" images "$ROOT/body.html")"
has "$O" 'diagram.png' "images subcommand lists referenced files"
pass "images <body.html> → referenced filenames"

# --- script: fetch (mocked acli, no network/auth) ----------------------------
# Regression for CCAL-2091: EXTRA[@] must not throw "unbound variable" under
# set -u on bash 3.2 (macOS system bash) when no --children/--labels flags
# are passed, i.e. EXTRA is an empty array.
MOCKBIN="$ROOT/mockbin"
mkdir -p "$MOCKBIN"
cat > "$MOCKBIN/acli" <<'EOF'
#!/usr/bin/env bash
echo "$*" >&2
echo '{"title":"Mock Page","version":{"number":1},"body":{"storage":{"value":"<p>mock body</p>"}}}'
EOF
chmod +x "$MOCKBIN/acli"

O="$(PATH="$MOCKBIN:$PATH" bash "$SCRIPT" fetch 3851517965 2>/dev/null)"
has "$O" 'mock body' "fetch with no flags (empty EXTRA) should not throw unbound variable"
pass "fetch <id> with no flags → empty EXTRA[@] expands safely under set -u"

O="$(PATH="$MOCKBIN:$PATH" bash "$SCRIPT" fetch 3851517965 --children --labels 2>/dev/null)"
has "$O" 'mock body' "fetch with --children --labels should still succeed"
pass "fetch <id> --children --labels → succeeds"

ERR="$(PATH="$MOCKBIN:$PATH" bash "$SCRIPT" fetch 3851517965 --children --labels 2>&1 1>/dev/null)"
[[ "$ERR" == *"--include-direct-children"* ]] || fail "EXTRA flags should reach the acli invocation — got: $ERR"
[[ "$ERR" == *"--include-labels"* ]] || fail "EXTRA flags should reach the acli invocation — got: $ERR"
pass "fetch --children --labels → flags passed through to acli"

# --- usage / error contract --------------------------------------------------
rc=0; bash "$SCRIPT" resolve >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "resolve without input should exit 2 (got $rc)"
pass "resolve with no input → exit 2"

rc=0; bash "$SCRIPT" bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "unknown subcommand should exit 2 (got $rc)"
pass "unknown subcommand → exit 2"

echo ""
echo "✅ confluence smoke PASSED ($PASS checks)"
