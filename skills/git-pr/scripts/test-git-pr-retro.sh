#!/usr/bin/env bash
# Hermetic smoke for git-pr-retro.sh. No network and no real gh: PATH shims fake
# the Scout control-plane POST and the interactive `gh pr comment` fallback.
# Covers the closed retrospective payload contract, exact HTTP request, safe
# retries, refusal passthrough, and preservation of interactive use.
#
#   bash skills/git-pr/scripts/test-git-pr-retro.sh
set -euo pipefail
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/git-pr-retro.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/git-pr-retro-smoke.XXXXXX")"
export TMPDIR="$ROOT"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has() { grep -q "$2" <<<"$1" || fail "$3 — got: $1"; }
not_has() { if grep -q "$2" <<<"$1"; then fail "$3 — got: $1"; fi; }

command -v jq >/dev/null 2>&1 || { echo "git-pr-retro smoke: SKIPPED — jq not on PATH"; exit 0; }

# ---- gh shim: intercepts pr comment ------------------------------------------
# Any other gh subcommand falls through to `exit 1`, which is itself a guard: if
# the script ever regrows a `pr edit --add-reviewer` or a reviews `api` poll, the
# retro tests below start failing rather than silently passing (MD-2746).
SHIM="$ROOT/shim"; mkdir -p "$SHIM"
cat >"$SHIM/gh" <<'EOF'
#!/usr/bin/env bash
# Stub gh for the git-pr-retro smoke. Controlled via env:
#   GH_STUB_LOG      file that `pr comment` writes its --body/--body-file into
#   GH_STUB_COMMENT_ERR  if set, `pr comment` prints this to stderr and exits 1
case "$1 $2" in
  "pr comment")
    if [[ -n "${GH_STUB_COMMENT_ERR:-}" ]]; then
      echo "$GH_STUB_COMMENT_ERR" >&2
      exit 1
    fi
    n="$3"; shift 3
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == --body ]]; then printf '%s' "$2" > "${GH_STUB_LOG:-/dev/null}"; shift; fi
      if [[ "$1" == --body-file ]]; then cat "$2" > "${GH_STUB_LOG:-/dev/null}"; shift; fi
      shift
    done
    echo "https://github.com/o/r/pull/$n#issuecomment-1"
    exit 0 ;;
esac
exit 1
EOF
chmod +x "$SHIM/gh"

# ---- curl shim: intercepts the dispatched Scout POST -------------------------
cat >"$SHIM/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
method=""; content_type=""; data_file=""; output_file=""; url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X|--request) method="${2:-}"; shift ;;
    -H|--header) content_type="${2:-}"; shift ;;
    --data-binary) data_file="${2#@}"; shift ;;
    -o|--output) output_file="${2:-}"; shift ;;
    -w|--write-out) shift ;;
    -s|-S|-sS|--silent|--show-error) ;;
    -*) echo "unexpected curl flag: $1" >&2; exit 97 ;;
    *) url="$1" ;;
  esac
  shift
done
if [[ -n "${CURL_STUB_TRANSPORT_ERR:-}" ]]; then
  echo "$CURL_STUB_TRANSPORT_ERR" >&2
  exit 7
fi
printf '%s\t%s\t%s\n' "$method" "$url" "$content_type" >> "${CURL_STUB_LOG:?}"
cp "$data_file" "${CURL_STUB_PAYLOAD:?}"
body="${CURL_STUB_BODY:-}"
[[ -n "$body" ]] || body='{"ok":true}'
printf '%s' "$body" > "$output_file"
printf '%s' "${CURL_STUB_STATUS:-200}"
EOF
chmod +x "$SHIM/curl"
export PATH="$SHIM:$PATH"

echo "git-pr-retro smoke: root=$ROOT"

# ---- submit-dispatched: exact request and response ---------------------------
PAYLOAD="$ROOT/retro.json"
cat > "$PAYLOAD" <<'EOF'
{"worked":["The focused regression test caught the old path."],"friction":["The producer and consumer contracts had drifted."],"improvements":["Pin the command shape in both repositories."],"followUps":["MD-2996"]}
EOF
export CURL_STUB_LOG="$ROOT/curl.log" CURL_STUB_PAYLOAD="$ROOT/curl-payload.json"
O="$(TRON_API_URL='http://127.0.0.1:8787/' TRON_DISPATCH_ID='dispatch-123' \
  CURL_STUB_BODY='{"ok":true,"report":{"id":"r-1"},"retrospective":{"status":"recorded"}}' \
  bash "$SCRIPT" submit-dispatched --payload-file "$PAYLOAD")"
echo "  → $O"
[[ "$O" == '{"ok":true,"report":{"id":"r-1"},"retrospective":{"status":"recorded"}}' ]] || \
  fail "successful endpoint JSON must pass through exactly — got: $O"
[[ "$(cat "$CURL_STUB_LOG")" == $'POST\thttp://127.0.0.1:8787/api/dispatches/dispatch-123/retrospective\tcontent-type: application/json' ]] || \
  fail "request must use the exact POST URL and content type — got: $(cat "$CURL_STUB_LOG")"
cmp -s "$PAYLOAD" "$CURL_STUB_PAYLOAD" || fail "request payload must equal the authored file byte-for-byte"
pass "submit-dispatched: exact URL, POST method, content type, payload, and response"

# ---- submit-dispatched: retry delegates idempotency to Scout -----------------
: > "$CURL_STUB_LOG"
for attempt in 1 2; do
  TRON_API_URL='http://127.0.0.1:8787' TRON_DISPATCH_ID='dispatch-123' \
    CURL_STUB_BODY='{"ok":true,"retrospective":{"status":"recorded"}}' \
    bash "$SCRIPT" submit-dispatched --payload-file "$PAYLOAD" >/dev/null
done
[[ "$(wc -l < "$CURL_STUB_LOG" | tr -d ' ')" == 2 ]] || fail "retry must issue the same Scout POST again"
pass "submit-dispatched: retry repeats Scout's idempotent upsert with no local state"

# ---- submit-dispatched: malformed payloads fail before curl ------------------
assert_invalid_payload() {
  local name="$1" json="$2" out rc=0
  printf '%s' "$json" > "$ROOT/invalid.json"
  : > "$CURL_STUB_LOG"
  out="$(TRON_API_URL='http://127.0.0.1:8787' TRON_DISPATCH_ID='dispatch-123' \
    bash "$SCRIPT" submit-dispatched --payload-file "$ROOT/invalid.json")" || rc=$?
  [[ "$rc" == 2 ]] || fail "$name should exit 2, got $rc: $out"
  has "$out" '"ok":false' "$name emits JSON failure"
  has "$out" '"code":"retrospective-payload-invalid"' "$name emits stable local validation code"
  [[ ! -s "$CURL_STUB_LOG" ]] || fail "$name must fail before curl"
}
assert_invalid_payload "invalid JSON" '{'
assert_invalid_payload "unknown field" '{"worked":["x"],"friction":["x"],"improvements":["x"],"extra":[]}'
assert_invalid_payload "missing required array" '{"worked":["x"],"friction":["x"]}'
assert_invalid_payload "empty required array" '{"worked":[],"friction":["x"],"improvements":["x"]}'
assert_invalid_payload "blank item" '{"worked":["   "],"friction":["x"],"improvements":["x"]}'
assert_invalid_payload "null followUps" '{"worked":["x"],"friction":["x"],"improvements":["x"],"followUps":null}'
assert_invalid_payload "too many items" "$(jq -nc '{worked:[range(21)|"x"],friction:["x"],improvements:["x"]}')"
assert_invalid_payload "overlong item" "$(jq -nc --arg x "$(printf '%01001d' 0)" '{worked:[$x],friction:["x"],improvements:["x"]}')"
assert_invalid_payload "unfiled follow-up prose" '{"worked":["x"],"friction":["x"],"improvements":["x"],"followUps":["write another test"]}'
pass "submit-dispatched: closed bounded schema rejects malformed payloads and unfiled follow-up prose"

rc=0; O="$(TRON_API_URL='http://127.0.0.1:8787' TRON_DISPATCH_ID='dispatch-123' \
  bash "$SCRIPT" submit-dispatched --payload-file "$ROOT/missing.json")" || rc=$?
[[ "$rc" == 2 ]] || fail "missing payload file should exit 2"
has "$O" '"code":"retrospective-payload-invalid"' "missing payload file emits stable JSON failure"
pass "submit-dispatched: missing payload file is machine-readable"

# ---- submit-dispatched: dispatch environment is mandatory -------------------
rc=0; O="$(TRON_API_URL='http://127.0.0.1:8787' TRON_DISPATCH_ID= bash "$SCRIPT" submit-dispatched --payload-file "$PAYLOAD")" || rc=$?
[[ "$rc" == 2 ]] || fail "missing TRON_DISPATCH_ID should exit 2"
has "$O" '"code":"dispatch-environment-missing"' "missing dispatch id emits stable JSON failure"
rc=0; O="$(TRON_API_URL= TRON_DISPATCH_ID='dispatch-123' bash "$SCRIPT" submit-dispatched --payload-file "$PAYLOAD")" || rc=$?
[[ "$rc" == 2 ]] || fail "missing TRON_API_URL should exit 2"
has "$O" '"code":"dispatch-environment-missing"' "missing API URL emits stable JSON failure"
pass "submit-dispatched: missing Scout dispatch environment is explicit"

# ---- submit-dispatched: control-plane failures remain machine-readable -------
rc=0
O="$(TRON_API_URL='http://127.0.0.1:8787' TRON_DISPATCH_ID='dispatch-123' \
  CURL_STUB_STATUS=409 \
  CURL_STUB_BODY='{"ok":false,"error":"register the PR first","code":"retrospective-pr-required","remedy":"worker"}' \
  bash "$SCRIPT" submit-dispatched --payload-file "$PAYLOAD")" || rc=$?
[[ "$rc" == 1 ]] || fail "control-plane 4xx should exit 1"
[[ "$O" == '{"ok":false,"error":"register the PR first","code":"retrospective-pr-required","remedy":"worker"}' ]] || \
  fail "typed worker remedy must pass through exactly — got: $O"
not_has "$O" 'approval' "worker-repairable refusal must not be translated into an approval gate"
rc=0
O="$(TRON_API_URL='http://127.0.0.1:8787' TRON_DISPATCH_ID='dispatch-123' \
  CURL_STUB_TRANSPORT_ERR='connection refused' \
  bash "$SCRIPT" submit-dispatched --payload-file "$PAYLOAD")" || rc=$?
[[ "$rc" == 1 ]] || fail "curl transport failure should exit 1"
has "$O" '"code":"control-plane-request-failed"' "transport failure emits stable JSON failure"
has "$O" 'connection refused' "transport failure preserves curl detail"
rc=0
O="$(TRON_API_URL='http://127.0.0.1:8787' TRON_DISPATCH_ID='dispatch-123' \
  CURL_STUB_STATUS=502 CURL_STUB_BODY='upstream broke' \
  bash "$SCRIPT" submit-dispatched --payload-file "$PAYLOAD")" || rc=$?
[[ "$rc" == 1 ]] || fail "non-JSON control-plane response should exit 1"
has "$O" '"code":"control-plane-response-invalid"' "non-JSON response emits stable JSON failure"
if find "$ROOT" -maxdepth 1 -type f \( -name 'tron-retro-response.*' -o -name 'tron-retro-error.*' \) -print -quit | grep -q .; then
  fail "submit-dispatched must clean response scratch files on success and failure"
fi
pass "submit-dispatched: typed refusal, transport failure, and invalid response stay machine-readable and clean"

# ---- retro-comment: no token data (helper prints nothing) ---------------------
export GH_STUB_LOG="$ROOT/comment-body.txt"
O="$(CLAUDE_CODE_SESSION_ID= HOME="$ROOT/empty-home" \
     TRON_API_URL= TRON_DISPATCH_ID= bash "$SCRIPT" retro-comment --pr 7 --model claude-test-1 \
       --body $'**What went well:** it worked\nFOLLOW-UP: none')"
echo "  → $O"
has "$O" '"ok":true' "comment posted"
has "$O" '"tokens_included":false' "no token data → tokens_included:false"
B="$(cat "$GH_STUB_LOG")"
has "$B" '<!-- tron-retro -->' "body carries the tron-retro marker"
has "$B" '### Retro' "body carries the Retro header"
has "$B" '\*claude-test-1\*' "body carries the literal model id"
has "$B" 'FOLLOW-UP: none' "body carries the retro sections"
if grep -q 'in .* · out' "$GH_STUB_LOG"; then fail "no-token path must not include a token line"; fi
pass "retro-comment: no token data → posts marker+model, no token line, exit 0"

# ---- retro-comment: with token data (fake plugin root + stub helper) ----------
FAKEROOT="$ROOT/fakeplugin"; mkdir -p "$FAKEROOT/tools/git"
printf '#!/usr/bin/env bash\necho "*in 1k · out 2k · cache 3k read / 4k write*"\n' \
  > "$FAKEROOT/tools/git/token-usage.sh"
O="$(CLAUDE_PLUGIN_ROOT="$FAKEROOT" bash "$SCRIPT" retro-comment --pr 7 \
     --model claude-test-1 --body 'retro body')"
echo "  → $O"
has "$O" '"tokens_included":true' "token line included when the helper yields one"
B="$(cat "$GH_STUB_LOG")"
has "$B" 'in 1k · out 2k' "posted body carries the token line"
pass "retro-comment: token helper output lands in the posted body"

# ---- retro-comment: --body-file --------------------------------------------
BF="$ROOT/body.md"; printf '%s\n' 'from a file' > "$BF"
O="$(CLAUDE_CODE_SESSION_ID= HOME="$ROOT/empty-home" \
     bash "$SCRIPT" retro-comment --pr 9 --model m1 --body-file "$BF")"
has "$O" '"ok":true' "body-file variant posts"
has "$(cat "$GH_STUB_LOG")" 'from a file' "body-file content posted"
pass "retro-comment: --body-file works"

# ---- retro-comment: shell-special characters (backticks) survive inline --body -
O="$(CLAUDE_CODE_SESSION_ID= HOME="$ROOT/empty-home" \
     bash "$SCRIPT" retro-comment --pr 11 --model m1 \
       --body 'has `backticks` and $(command) and "quotes"')"
has "$O" '"ok":true' "backtick/shell-special body posts without breaking"
has "$(cat "$GH_STUB_LOG")" 'has `backticks` and $(command) and "quotes"' \
  "shell-special body content posted verbatim"
pass "retro-comment: shell-special characters in body survive the post"

# ---- retro-comment: gh failure surfaces the real stderr, not a generic fallback
O="$(CLAUDE_CODE_SESSION_ID= HOME="$ROOT/empty-home" \
     GH_STUB_COMMENT_ERR='HTTP 404: Not Found' \
     bash "$SCRIPT" retro-comment --pr 999 --model m1 --body 'x')" || true
has "$O" '"ok":false' "gh failure → ok:false"
has "$O" 'HTTP 404: Not Found' "real gh stderr surfaced, not masked"
pass "retro-comment: gh failure surfaces real stderr instead of generic fallback"

# ---- MD-2746 regression: the Copilot subcommands must stay gone ---------------
# MD-2745 moved code review before the PR and onto this machine. A worker that
# could still reach `request-review`/`await-review` would request a reviewer that
# never speaks and then block on it — the unbounded wait MD-2489 and MD-2536 each
# had to fix once. Removal is the fix, so removal is what gets asserted.
rc_of() { local rc=0; bash "$SCRIPT" "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
for gone in request-review await-review skip-check; do
  [[ "$(rc_of "$gone" --pr 7)" == 2 ]] || fail "'$gone' must be gone (exit 2), not runnable"
done
pass "removed Copilot subcommands (request-review/await-review/skip-check) → exit 2"

# Assert on the live code paths, not the word: the header explains WHY they were
# removed, and that rationale is the thing keeping them from being re-added.
UNCOMMENTED="$(grep -v '^[[:space:]]*#' "$SCRIPT")"
for banned in '@copilot' '--add-reviewer' '/reviews' 'TRON_COPILOT_UNAVAILABLE'; do
  # -e is required: BSD grep parses a leading-dash pattern like `--add-reviewer`
  # as a flag and errors out, which would make this check pass vacuously.
  if grep -qF -e "$banned" <<<"$UNCOMMENTED"; then
    fail "git-pr-retro.sh must carry no live '$banned' code path"
  fi
done
pass "git-pr-retro.sh requests no reviewer and polls no review endpoint"

# ---- usage / error contract ----------------------------------------------------
[[ "$(rc_of bogus)" == 2 ]] || fail "unknown subcommand should exit 2"
[[ "$(rc_of retro-comment --pr 1 --model m)" == 2 ]] || fail "retro-comment without body should exit 2"
[[ "$(rc_of retro-comment --pr 1 --body b)" == 2 ]] || fail "retro-comment without --model should exit 2"
[[ "$(rc_of retro-comment --model m --body b)" == 2 ]] || fail "retro-comment without --pr should exit 2"
pass "usage errors → exit 2"

O="$(bash "$SCRIPT" help)"
has "$O" 'retro-comment' "help lists retro-comment"
has "$O" 'submit-dispatched' "help lists submit-dispatched"
if grep -qiE 'request-review|await-review|skip-check' <<<"$O"; then
  fail "help must not advertise the removed Copilot subcommands"
fi
pass "help → prints dispatched and interactive usage (exit 0)"

echo ""
echo "✅ git-pr-retro smoke PASSED ($PASS checks)"
