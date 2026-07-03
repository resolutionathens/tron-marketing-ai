#!/usr/bin/env bash
# Hermetic test for fetch-confluence.sh — the network-heavy "pull a page's
# storage body + its referenced image attachments" tool. Every network + auth
# leg is faked:
#   • curl is PATH-stubbed to serve canned storage-XML page JSON, an attachment
#     listing, tiny-link redirect headers, and per-attachment download bytes,
#     keyed off the request URL + flags (a -sIL HEAD vs a -o GET).
#   • credentials come from the environment (JIRA_API_TOKEN / ATLASSIAN_EMAIL)
#     so ~/.env is never touched; HOME points at an empty dir to prove that.
#   • python3 (body extraction + referenced/unused split) runs for real, offline.
#   • confluence-lib.sh (page-id resolution) is the REAL sibling — no fake root.
#
# Asserts: the three page-id resolution paths (raw id / full URL offline, tiny
# link via the redirect follow), referenced-vs-unused attachment filtering (only
# referenced files are downloaded), netrc temp-file mode 600 + trap cleanup, and
# that a missing credential fails fast.
#
#   bash tools/confluence/test-fetch-confluence.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/fetch-confluence.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/fetch-conf-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has()   { grep -qF -- "$2" <<<"$1" || fail "$3 — got: $1"; }
hasnt() { grep -qF -- "$2" <<<"$1" && fail "$3 — unexpectedly got: $1"; return 0; }

echo "fetch-confluence smoke: root=$ROOT"

BIN="$ROOT/bin"; mkdir -p "$BIN" "$ROOT/home" "$ROOT/tmp" "$ROOT/tmp-clean"

# --- canned fixtures ---------------------------------------------------------
# Body references hero.png then diagram.png (doc order); unused.png is an
# attachment the body never references → must be skipped, not downloaded.
cat > "$ROOT/page.json" <<'JSON'
{"title":"My Test Page","body":{"storage":{"value":"<p><ac:image><ri:attachment ri:filename=\"hero.png\" /></ac:image></p><p><ac:image><ri:attachment ri:filename=\"diagram.png\" /></ac:image></p>"}}}
JSON
cat > "$ROOT/attachments.json" <<'JSON'
{"results":[
 {"title":"hero.png","downloadLink":"/download/attachments/123/hero.png?version=1"},
 {"title":"diagram.png","downloadLink":"/download/attachments/123/diagram.png?version=1"},
 {"title":"unused.png","downloadLink":"/download/attachments/123/unused.png?version=1"}
]}
JSON

# --- curl stub: route by URL + flags -----------------------------------------
cat > "$BIN/curl" <<'SH'
#!/usr/bin/env bash
out=""; url=""; nf=""; head=0
args=("$@"); n=${#args[@]}
for ((i=0;i<n;i++)); do
  a="${args[$i]}"
  case "$a" in
    -o)          out="${args[$((i+1))]}"; i=$((i+1)) ;;
    --netrc-file) nf="${args[$((i+1))]}"; i=$((i+1)) ;;
    -*I*)        head=1 ;;               # combined short flags with I (e.g. -sIL) = HEAD
    http://*|https://*) url="$a" ;;
  esac
done

# Snapshot the netrc (mode-preserving) once, so the test can inspect it.
if [[ -n "${STUB_NETRC_COPY:-}" && -n "$nf" && ! -e "$STUB_NETRC_COPY" ]]; then
  cp -p "$nf" "$STUB_NETRC_COPY"
fi

if [[ "$head" == 1 ]]; then
  # tiny-link resolution: emit a redirect Location carrying the numeric page id
  printf 'HTTP/2 302\r\nlocation: https://facilitron.atlassian.net/wiki/spaces/x/pages/%s/Resolved\r\n\r\n' "${STUB_REDIRECT_ID:-123}"
  exit 0
fi

case "$url" in
  *api.atlassian.com*) printf 'IMGDATA:%s' "$(basename "$out")" > "$out" ;;  # attachment download
  *"/attachments"*)    cp "${STUB_ATTACH:?}" "$out" ;;                        # attachment listing
  *"/api/v2/pages/"*)  cp "${STUB_PAGE:?}"   "$out" ;;                        # page body
  *) echo "curl stub: unhandled url: $url" >&2; exit 1 ;;
esac
SH
chmod +x "$BIN/curl"

cfetch() { # <input> <outdir> ; env overridable: JIRA_API_TOKEN, HOME, TMPDIR_OVR, NETRC_COPY
  PATH="$BIN:$PATH" \
  HOME="${HOME_OVR:-$ROOT/home}" \
  JIRA_API_TOKEN="${TOK-faketoken}" ATLASSIAN_EMAIL="${EMAIL_OVR-smoke@tron.local}" \
  TMPDIR="${TMPDIR_OVR:-$ROOT/tmp}" \
  STUB_PAGE="$ROOT/page.json" STUB_ATTACH="$ROOT/attachments.json" \
  STUB_REDIRECT_ID=123 STUB_NETRC_COPY="${NETRC_COPY:-}" \
  bash "$SCRIPT" "$@"
}

# --- 1. raw id: full happy path + referenced/unused split + netrc mode/cleanup
OUT1="$ROOT/out-raw"
NETRC_COPY="$ROOT/netrc.snap" TMPDIR_OVR="$ROOT/tmp-clean" \
  cfetch 123 "$OUT1" > "$ROOT/stdout1" 2>"$ROOT/stderr1" || fail "raw id run failed: $(cat "$ROOT/stderr1")"
S1="$(cat "$ROOT/stdout1")"; echo "  → $(tr '\n' ' ' <<<"$S1")"
has "$S1" 'TITLE: My Test Page' "prints the resolved page title"
has "$S1" 'REFERENCED IMAGES' "lists referenced images"
has "$S1" 'hero.png' "hero.png referenced"
has "$S1" 'diagram.png' "diagram.png referenced"
has "$S1" 'UNUSED ATTACHMENTS' "reports the unused-attachment section"
has "$S1" 'unused.png' "unused.png named as skipped"
has "$S1" 'DONE.' "prints DONE footer"
[[ -s "$OUT1/body.html" ]] || fail "body.html not written"
[[ -f "$OUT1/raw/hero.png" && -f "$OUT1/raw/diagram.png" ]] || fail "referenced attachments not downloaded"
[[ ! -e "$OUT1/raw/unused.png" ]] || fail "unused attachment was downloaded (should be skipped)"
[[ ! -e "$OUT1/_dl.tsv" ]] || fail "_dl.tsv scratch file not cleaned up"
pass "raw id → body.html + only-referenced downloads (unused.png skipped)"

# netrc: mode 600, holds creds for both hosts, and was removed from TMPDIR on exit
[[ -f "$ROOT/netrc.snap" ]] || fail "netrc snapshot not captured (script never wrote one?)"
[[ "$(stat -c '%a' "$ROOT/netrc.snap")" == 600 ]] || fail "netrc should be mode 600 (got $(stat -c '%a' "$ROOT/netrc.snap"))"
grep -q 'machine facilitron.atlassian.net' "$ROOT/netrc.snap" || fail "netrc missing wiki host entry"
grep -q 'machine api.atlassian.com' "$ROOT/netrc.snap" || fail "netrc missing gateway host entry"
grep -q 'faketoken' "$ROOT/netrc.snap" || fail "netrc missing the token"
[[ -z "$(ls -A "$ROOT/tmp-clean")" ]] || fail "netrc temp not cleaned from TMPDIR (leftover: $(ls -A "$ROOT/tmp-clean"))"
pass "netrc: mode 600, both host entries + token, removed from TMPDIR on exit"

# --- 2. full /pages/<id>/ URL resolves OFFLINE (no HEAD redirect needed) ------
OUT2="$ROOT/out-url"
cfetch 'https://facilitron.atlassian.net/wiki/spaces/K/pages/123/Some+Title' "$OUT2" \
  > "$ROOT/stdout2" 2>&1 || fail "full-URL run failed: $(cat "$ROOT/stdout2")"
has "$(cat "$ROOT/stdout2")" 'TITLE: My Test Page' "full URL resolves + fetches"
pass "full /pages/<id>/ URL → resolved offline, page fetched"

# --- 3. tiny link resolves via the -sIL redirect follow ----------------------
OUT3="$ROOT/out-tiny"
cfetch 'https://facilitron.atlassian.net/wiki/x/DYCR5Q' "$OUT3" \
  > "$ROOT/stdout3" 2>&1 || fail "tiny-link run failed: $(cat "$ROOT/stdout3")"
has "$(cat "$ROOT/stdout3")" 'TITLE: My Test Page' "tiny link followed the redirect to id 123"
[[ -f "$OUT3/raw/hero.png" ]] || fail "tiny-link path did not download referenced attachments"
pass "tiny link → redirect followed (id resolved), page + attachments fetched"

# --- 4. missing credential fails fast ----------------------------------------
# Empty token + a HOME with no ~/.env → the JIRA_API_TOKEN guard must abort.
rc=0; TOK= cfetch 123 "$ROOT/out-nocred" >/dev/null 2>"$ROOT/nocred.err" || rc=$?
[[ "$rc" -ne 0 ]] || fail "missing token should exit nonzero (got $rc)"
grep -qF 'JIRA_API_TOKEN' "$ROOT/nocred.err" || fail "credential failure should name JIRA_API_TOKEN (got: $(cat "$ROOT/nocred.err"))"
pass "no credentials → fails fast, names JIRA_API_TOKEN"

# --- 5. usage: missing args ---------------------------------------------------
rc=0; PATH="$BIN:$PATH" bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "no args should exit nonzero (got $rc)"
rc=0; PATH="$BIN:$PATH" bash "$SCRIPT" 123 >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "missing output-dir arg should exit nonzero (got $rc)"
pass "usage: missing page-id/output-dir → nonzero exit"

echo ""
echo "✅ fetch-confluence smoke PASSED ($PASS checks)"
