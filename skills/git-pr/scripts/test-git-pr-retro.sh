#!/usr/bin/env bash
# Hermetic smoke for git-pr-retro.sh. No network, no real gh: a PATH shim fakes
# the three gh invocations the script makes (pr view --json files, pr comment,
# pr edit). Covers the doc-only skip decision (both --pr and --range modes),
# the retro-comment assembly with and without token data, the best-effort
# request-review contract, and the usage/error surface.
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

# ---- gh shim: intercepts pr view / pr comment / pr edit ----------------------
SHIM="$ROOT/shim"; mkdir -p "$SHIM"
cat >"$SHIM/gh" <<'EOF'
#!/usr/bin/env bash
# Stub gh for the git-pr-retro smoke. Controlled via env:
#   GH_STUB_FILES    TSV rows returned for `pr view --json files`
#   GH_STUB_LOG      file that `pr comment` writes its --body/--body-file into
#   GH_STUB_EDIT_RC  exit code for `pr edit` (default 0)
#   GH_STUB_COMMENT_ERR  if set, `pr comment` prints this to stderr and exits 1
case "$1 $2" in
  "pr view")
    [[ -n "${GH_STUB_FILES:-}" ]] && printf '%s\n' "$GH_STUB_FILES"
    exit 0 ;;
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
  "pr edit")
    exit "${GH_STUB_EDIT_RC:-0}" ;;
esac
exit 1
EOF
chmod +x "$SHIM/gh"
export PATH="$SHIM:$PATH"

echo "git-pr-retro smoke: root=$ROOT"

# ---- skip-check (--pr mode, files via stubbed gh) -----------------------------
export GH_STUB_FILES=$'10\t5\tREADME.md\n3\t2\tskills/foo/reference/bar.md'
O="$(bash "$SCRIPT" skip-check --pr 12)"; echo "  → $O"
has "$O" '"skip":true' "small doc-only PR skips"
has "$O" '2 files, 20 changed lines' "reason carries the counts"
pass "skip-check --pr: 2 md files / 20 lines → skip:true"

export GH_STUB_FILES=$'4\t1\tREADME.md\n2\t0\tscripts/x.sh'
O="$(bash "$SCRIPT" skip-check --pr 12)"; echo "  → $O"
has "$O" '"skip":false' "non-doc file blocks the skip"
has "$O" 'scripts/x.sh' "reason names the non-doc file"
pass "skip-check --pr: .sh touched → skip:false"

export GH_STUB_FILES=$'80\t30\tguide.md'
O="$(bash "$SCRIPT" skip-check --pr 12)"
has "$O" '"skip":false' "big doc diff blocks the skip"
has "$O" 'too large' "reason says too large"
pass "skip-check --pr: doc-only but 110 lines → skip:false (over 40-line limit)"

export GH_STUB_FILES=$'1\t1\ta.md\n1\t1\tb.md\n1\t1\tc.md\n1\t1\td.md'
O="$(bash "$SCRIPT" skip-check --pr 12)"
has "$O" '"skip":false' "4 files blocks the skip"
pass "skip-check --pr: doc-only but 4 files → skip:false (over 3-file limit)"
unset GH_STUB_FILES

# ---- skip-check (--range mode, real throwaway git repo) -----------------------
REPO="$ROOT/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b master
git -C "$REPO" config user.email s@t.local; git -C "$REPO" config user.name smoke
echo base > "$REPO/README.md"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m init
git -C "$REPO" checkout -q -b MD-1-docs
printf 'one\ntwo\n' >> "$REPO/README.md"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m docs
O="$(bash "$SCRIPT" skip-check --range master...HEAD --repo-dir "$REPO")"; echo "  → $O"
has "$O" '"skip":true' "doc-only range skips"
pass "skip-check --range: doc-only branch → skip:true"

echo 'echo hi' > "$REPO/run.sh"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m script
O="$(bash "$SCRIPT" skip-check --range master...HEAD --repo-dir "$REPO")"
has "$O" '"skip":false' "range with a .sh does not skip"
has "$O" 'run.sh' "reason names run.sh"
pass "skip-check --range: .sh added → skip:false"

O="$(bash "$SCRIPT" skip-check --range HEAD...HEAD --repo-dir "$REPO")"
has "$O" '"skip":false' "empty diff defaults to not skipping"
pass "skip-check --range: empty diff → skip:false (default to review)"

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

# ---- request-review: best-effort contract -------------------------------------
O="$(bash "$SCRIPT" request-review --pr 7)"
has "$O" '"requested":true' "reviewer requested when gh pr edit succeeds"
pass "request-review: success → requested:true"

O="$(GH_STUB_EDIT_RC=1 bash "$SCRIPT" request-review --pr 7)"; rc=$?
[[ "$rc" == 0 ]] || fail "request-review must never fail the lifecycle (rc=$rc)"
has "$O" '"requested":false' "failure degrades to requested:false"
pass "request-review: gh failure → ok:true requested:false exit 0"

# ---- usage / error contract ----------------------------------------------------
rc_of() { local rc=0; bash "$SCRIPT" "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
[[ "$(rc_of bogus)" == 2 ]] || fail "unknown subcommand should exit 2"
[[ "$(rc_of skip-check)" == 2 ]] || fail "skip-check without --pr/--range should exit 2"
[[ "$(rc_of retro-comment --pr 1 --model m)" == 2 ]] || fail "retro-comment without body should exit 2"
[[ "$(rc_of retro-comment --pr 1 --body b)" == 2 ]] || fail "retro-comment without --model should exit 2"
[[ "$(rc_of request-review)" == 2 ]] || fail "request-review without --pr should exit 2"
pass "usage errors → exit 2"

O="$(bash "$SCRIPT" help)"
has "$O" 'skip-check' "help lists skip-check"
has "$O" 'retro-comment' "help lists retro-comment"
has "$O" 'request-review' "help lists request-review"
pass "help → prints usage (exit 0)"

echo ""
echo "✅ git-pr-retro smoke PASSED ($PASS checks)"
