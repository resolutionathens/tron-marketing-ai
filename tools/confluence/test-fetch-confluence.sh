#!/usr/bin/env bash
# Hermetic test for fetch-confluence.sh — the network-heavy "pull a page's
# storage body + its referenced image attachments" tool. Every network + auth
# leg is faked:
#   • curl is PATH-stubbed to serve canned storage-XML page JSON, an attachment
#     listing, tiny-link redirect headers, and per-attachment download bytes,
#     keyed off the request URL + flags (a -sIL HEAD vs a -o GET). It also
#     routes broker (secrets.facilitron.work/jira/wiki/*) requests, controllable
#     via STUB_BROKER_CODE / STUB_BROKER_DOWN, and logs every host it sees to
#     STUB_HITLOG so tests can assert which path (broker vs direct) was taken.
#   • cloudflared is PATH-stubbed too (STUB_CF_FAIL / STUB_CF_TOKEN), so the
#     org-secret-broker token mint (MD-1995) never shells out for real.
#   • credentials come from the environment (JIRA_API_TOKEN / ATLASSIAN_EMAIL)
#     so ~/.env is never touched; HOME points at an empty dir to prove that.
#   • python3 (body extraction + referenced/unused split) runs for real, offline.
#   • confluence-lib.sh (page-id resolution) is the REAL sibling — no fake root.
#
# Asserts: the three page-id resolution paths (raw id / full URL offline, tiny
# link via the redirect follow), referenced-vs-unused attachment filtering (only
# referenced files are downloaded), netrc temp-file mode 600 + trap cleanup, a
# missing credential fails fast when the broker is unavailable, the broker path
# covers a no-attachment page with zero local credentials, the broker still
# defers the attachment *download* leg to direct auth (MD-2011), and both broker
# failure modes (non-2xx response, connection refused) fall back to direct auth.
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
# Portable octal file mode: GNU stat uses -c '%a', BSD/macOS stat uses -f '%Lp'.
filemode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

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
out=""; url=""; nf=""; head=0; hasw=0
args=("$@"); n=${#args[@]}
for ((i=0;i<n;i++)); do
  a="${args[$i]}"
  case "$a" in
    -o)          out="${args[$((i+1))]}"; i=$((i+1)) ;;
    --netrc-file) nf="${args[$((i+1))]}"; i=$((i+1)) ;;
    -w)          hasw=1; i=$((i+1)) ;;
    -H)          i=$((i+1)) ;;           # header value not needed for routing
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

# Log every host this stub sees, so tests can assert broker-vs-direct routing.
if [[ -n "${STUB_HITLOG:-}" ]]; then
  host="${url#*://}"; host="${host%%/*}"
  echo "$host" >> "$STUB_HITLOG"
fi

case "$url" in
  *secrets.facilitron.work/jira/wiki*)
    [[ "${STUB_BROKER_DOWN:-0}" == 1 ]] && exit 7   # simulate connection refused
    case "$url" in
      *"/attachments"*)   cp "${STUB_ATTACH:?}" "$out" ;;
      *"/api/v2/pages/"*) cp "${STUB_PAGE:?}"   "$out" ;;
      *) echo "curl stub: unhandled broker url: $url" >&2; exit 1 ;;
    esac
    [[ "$hasw" == 1 ]] && printf '%s' "${STUB_BROKER_CODE:-200}"
    exit 0
    ;;
  *secrets.facilitron.work/jira/confluence-attachments*)
    [[ "${STUB_BROKER_DOWN:-0}" == 1 ]] && exit 7   # simulate connection refused
    [[ "${STUB_BROKER_ATTACH_CODE:-0}" != 0 ]] && [[ "$hasw" == 1 ]] && printf '%s' "${STUB_BROKER_ATTACH_CODE}" && exit 0
    printf 'IMGDATA:%s' "$(basename "$out")" > "$out"  # attachment download via broker
    [[ "$hasw" == 1 ]] && printf '%s' "${STUB_BROKER_ATTACH_CODE:-200}"
    exit 0
    ;;
  *api.atlassian.com*) printf 'IMGDATA:%s' "$(basename "$out")" > "$out" ;;  # attachment download (fallback)
  *"/attachments"*)    cp "${STUB_ATTACH:?}" "$out" ;;                        # attachment listing
  *"/api/v2/pages/"*)  cp "${STUB_PAGE:?}"   "$out" ;;                        # page body
  *) echo "curl stub: unhandled url: $url" >&2; exit 1 ;;
esac
SH
chmod +x "$BIN/curl"

# --- cloudflared stub: mints (or refuses to mint) the broker Access token ----
cat > "$BIN/cloudflared" <<'SH'
#!/usr/bin/env bash
[[ "${STUB_CF_FAIL:-0}" == 1 ]] && exit 1
if [[ "$1" == "access" && "$2" == "token" ]]; then
  echo "${STUB_CF_TOKEN:-fake-cf-token}"
  exit 0
fi
exit 1
SH
chmod +x "$BIN/cloudflared"

# Default: broker unavailable (cloudflared "not logged in"), so the original
# suite below exercises the direct-Basic-auth path exactly as before MD-1995.
cfetch() { # <input> <outdir> ; env overridable: JIRA_API_TOKEN, HOME, TMPDIR_OVR, NETRC_COPY
  PATH="$BIN:$PATH" \
  HOME="${HOME_OVR:-$ROOT/home}" \
  JIRA_API_TOKEN="${TOK-faketoken}" ATLASSIAN_EMAIL="${EMAIL_OVR-smoke@tron.local}" \
  TMPDIR="${TMPDIR_OVR:-$ROOT/tmp}" \
  STUB_PAGE="${PAGE_OVR:-$ROOT/page.json}" STUB_ATTACH="${ATTACH_OVR:-$ROOT/attachments.json}" \
  STUB_REDIRECT_ID=123 STUB_NETRC_COPY="${NETRC_COPY:-}" \
  STUB_CF_FAIL="${STUB_CF_FAIL-1}" STUB_CF_TOKEN="${STUB_CF_TOKEN:-}" \
  STUB_BROKER_CODE="${STUB_BROKER_CODE:-}" STUB_BROKER_DOWN="${STUB_BROKER_DOWN:-0}" \
  STUB_HITLOG="${STUB_HITLOG:-}" \
  CONFLUENCE_ACCESS_TOKEN="${CF_TOKEN_OVR:-}" \
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
[[ "$(filemode "$ROOT/netrc.snap")" == 600 ]] || fail "netrc should be mode 600 (got $(filemode "$ROOT/netrc.snap"))"
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

# --- broker fixtures (MD-1995) -------------------------------------------------
# A page with no referenced images, so a fully-broker-served run needs zero
# local Jira credentials (the attachment *download* leg never runs).
cat > "$ROOT/page-noimg.json" <<'JSON'
{"title":"No Image Page","body":{"storage":{"value":"<p>just text, no attachments</p>"}}}
JSON
cat > "$ROOT/attachments-empty.json" <<'JSON'
{"results":[]}
JSON

# --- 6. broker success + no attachments → zero local credentials needed ------
OUT6="$ROOT/out-broker-noimg"
rc=0
TOK= EMAIL_OVR= PAGE_OVR="$ROOT/page-noimg.json" ATTACH_OVR="$ROOT/attachments-empty.json" \
  STUB_CF_FAIL=0 STUB_CF_TOKEN=tok-6 \
  cfetch 123 "$OUT6" > "$ROOT/stdout6" 2>"$ROOT/stderr6" || rc=$?
[[ "$rc" -eq 0 ]] || fail "broker-only run (no images) should succeed with no credentials: $(cat "$ROOT/stderr6")"
has "$(cat "$ROOT/stdout6")" 'TITLE: No Image Page' "broker-only run fetched the page body"
[[ ! -d "$OUT6/raw" ]] || [[ -z "$(ls -A "$OUT6/raw" 2>/dev/null)" ]] || fail "no attachments should have been downloaded"
pass "broker success + no referenced attachments → succeeds with zero local Jira credentials"

# --- 7. broker covers page+listing+attachment-download (MD-2085) ---
OUT7="$ROOT/out-broker-full"
HITLOG7="$ROOT/hitlog7"; : > "$HITLOG7"
STUB_CF_FAIL=0 STUB_CF_TOKEN=tok-7 STUB_HITLOG="$HITLOG7" \
  cfetch 123 "$OUT7" > "$ROOT/stdout7" 2>"$ROOT/stderr7" || fail "broker-full run failed: $(cat "$ROOT/stderr7")"
[[ -f "$OUT7/raw/hero.png" && -f "$OUT7/raw/diagram.png" ]] || fail "referenced attachments not downloaded in broker-full run"
BROKER_HITS7="$(grep -c '^secrets.facilitron.work$' "$HITLOG7" || true)"
[[ "$BROKER_HITS7" -ge 3 ]] || fail "broker should handle page/listing/attachment downloads (got $BROKER_HITS7 broker hits: $(cat "$HITLOG7"))"
! grep -q '^facilitron.atlassian.net$' "$HITLOG7" || fail "should not have fallen back to direct when the broker succeeded (log: $(cat "$HITLOG7"))"
! grep -q '^api.atlassian.com$' "$HITLOG7" || fail "attachment download should now go through broker, not direct to api.atlassian.com (log: $(cat "$HITLOG7"))"
pass "broker covers page+listing+attachment-download via /jira/confluence-attachments (MD-2085)"

# --- 8. broker attachment download fails → falls back to direct auth ------
OUT8="$ROOT/out-broker-attach-fail"
HITLOG8="$ROOT/hitlog8"; : > "$HITLOG8"
STUB_CF_FAIL=0 STUB_CF_TOKEN=tok-8 STUB_BROKER_ATTACH_CODE=401 STUB_HITLOG="$HITLOG8" \
  cfetch 123 "$OUT8" > "$ROOT/stdout8" 2>"$ROOT/stderr8" || fail "broker-attach-401 run should still succeed via fallback: $(cat "$ROOT/stderr8")"
[[ -f "$OUT8/raw/hero.png" && -f "$OUT8/raw/diagram.png" ]] || fail "referenced attachments not downloaded after broker attachment failure"
grep -qi 'falling back to direct Basic auth' "$ROOT/stderr8" || fail "should log the fallback notice for attachment download (stderr: $(cat "$ROOT/stderr8"))"
grep -q '^api.atlassian.com$' "$HITLOG8" || fail "attachment download should fall back to direct api.atlassian.com when broker fails (log: $(cat "$HITLOG8"))"
pass "broker attachment download returns non-2xx → falls back to direct api.atlassian.com"

# --- 9. broker page-fetch returns a non-2xx → falls back to direct Basic auth, and stays
#        down for the rest of the run (latched, not re-tried per call) --------
OUT9="$ROOT/out-broker-401"
HITLOG9="$ROOT/hitlog9"; : > "$HITLOG9"
STUB_CF_FAIL=0 STUB_CF_TOKEN=tok-9 STUB_BROKER_CODE=401 STUB_HITLOG="$HITLOG9" \
  cfetch 123 "$OUT9" > "$ROOT/stdout9" 2>"$ROOT/stderr9" || fail "broker-401 run should still succeed via fallback: $(cat "$ROOT/stderr9")"
grep -qi 'falling back to direct Basic auth' "$ROOT/stderr9" || fail "should log the fallback notice (stderr: $(cat "$ROOT/stderr9"))"
has "$(cat "$ROOT/stdout9")" 'TITLE: My Test Page' "broker-401 run still fetched the page via direct fallback"
BROKER_HITS9="$(grep -c '^secrets.facilitron.work$' "$HITLOG9" || true)"
[[ "$BROKER_HITS9" == 1 ]] || fail "broker should be attempted exactly once per run then latched off (got $BROKER_HITS9 hits: $(cat "$HITLOG9"))"
pass "broker non-2xx response → falls back to direct Basic auth, latched off for the rest of the run (1 broker attempt, not re-tried per call)"

# --- 10. broker unreachable (connection refused) → falls back to direct -------
OUT10="$ROOT/out-broker-down"
STUB_CF_FAIL=0 STUB_CF_TOKEN=tok-10 STUB_BROKER_DOWN=1 \
  cfetch 123 "$OUT10" > "$ROOT/stdout10" 2>"$ROOT/stderr10" || fail "broker-down run should still succeed via fallback: $(cat "$ROOT/stderr10")"
has "$(cat "$ROOT/stdout10")" 'TITLE: My Test Page' "broker-down run still fetched the page via direct fallback"
pass "broker unreachable → falls back to direct Basic auth"

# --- 11. CONFLUENCE_ACCESS_TOKEN override skips cloudflared entirely ---------
OUT11="$ROOT/out-broker-override"
HITLOG11="$ROOT/hitlog11"; : > "$HITLOG11"
STUB_CF_FAIL=1 CF_TOKEN_OVR=explicit-token STUB_HITLOG="$HITLOG11" \
  cfetch 123 "$OUT11" > "$ROOT/stdout11" 2>"$ROOT/stderr11" || fail "access-token override run failed: $(cat "$ROOT/stderr11")"
grep -q '^secrets.facilitron.work$' "$HITLOG11" || fail "override token should have gone straight to the broker (log: $(cat "$HITLOG11"))"
pass "CONFLUENCE_ACCESS_TOKEN override reaches the broker without calling cloudflared"

echo ""
[[ "$PASS" -ge 11 ]] || echo "⚠ WARNING: expected 11 test checks, got $PASS"
echo "✅ fetch-confluence smoke PASSED ($PASS checks)"
