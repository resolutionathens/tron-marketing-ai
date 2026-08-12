#!/usr/bin/env bash
# Hermetic smoke for git-pr-retro.sh. No network, no real gh: a PATH shim fakes
# the one gh invocation the script makes (pr comment). Covers the retro-comment
# assembly with and without token data, the usage/error surface, and the MD-2746
# regression: the Copilot subcommands must stay gone, so no worker can request
# or wait for a reviewer that will never speak.
#
#   bash skills/git-pr/scripts/test-git-pr-retro.sh
set -euo pipefail
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/git-pr-retro.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/git-pr-retro-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has() { grep -q "$2" <<<"$1" || fail "$3 — got: $1"; }

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
export PATH="$SHIM:$PATH"

echo "git-pr-retro smoke: root=$ROOT"

# ---- retro-comment: no token data (helper prints nothing) ---------------------
export GH_STUB_LOG="$ROOT/comment-body.txt"
O="$(CLAUDE_CODE_SESSION_ID= HOME="$ROOT/empty-home" \
     bash "$SCRIPT" retro-comment --pr 7 --model claude-test-1 \
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
if grep -qiE 'request-review|await-review|skip-check' <<<"$O"; then
  fail "help must not advertise the removed Copilot subcommands"
fi
pass "help → prints usage listing only retro-comment (exit 0)"

echo ""
echo "✅ git-pr-retro smoke PASSED ($PASS checks)"
