#!/usr/bin/env bash
# git-pr-retro: the mechanical post-open steps of tron:git-pr (Steps 7–8).
# The judgment (PR title/body, what goes in the retro sections) stays with the
# model; this script owns the arithmetic and assembly that kept being re-derived
# in prose: the doc-only Copilot-skip decision, the retro-comment footer
# (token-usage resolution + marker + model line), and the best-effort Copilot
# reviewer request.
#
# Usage:
#   git-pr-retro.sh skip-check (--pr <N> | --range <base>...HEAD) [--repo-dir <path>]
#       Decide whether the Copilot review request may be skipped (small,
#       doc-only change). Doc = *.md / *.mdx only; small = ≤3 files and ≤40
#       changed lines. Prints {"skip":bool,"reason":"..."} and exits 0 either
#       way — the decision itself is the output.
#   git-pr-retro.sh retro-comment --pr <N> --model <model-id> (--body-file <f> | --body "...")
#       Post the <!-- tron-retro --> comment. The body is the filled-in retro
#       sections (What went well / Friction / Follow-up / FOLLOW-UP: lines);
#       the script adds the marker, "### Retro" header, and the footer
#       (*<model-id>* + the token line from tools/git/token-usage.sh, resolved
#       via CLAUDE_PLUGIN_ROOT with a relative fallback — an unreadable
#       transcript never blocks the comment).
#   git-pr-retro.sh request-review --pr <N>
#       Request @copilot as reviewer. Best-effort: an org without Copilot
#       review still exits 0 with requested:false — never fails the lifecycle.
#   git-pr-retro.sh await-review --pr <N> [--timeout <sec>] [--interval <sec>] [--repo-dir <path>]
#       Poll until Copilot posts its review, then report what landed so the PR
#       isn't declared approval-ready before the review exists. Prints
#       {status, commentCount, comments[], reviewState, waitedSeconds,
#       timeoutSeconds, ...} where status is:
#         skipped     — operator flag TRON_COPILOT_UNAVAILABLE is set; the poll
#                       was skipped entirely, no gh calls made (MD-2194)
#         commented   — Copilot left inline comments (comments[] carries them;
#                       the worker addresses them, pushes, then reports done)
#         no-comments — Copilot reviewed with no inline comments
#         timeout     — no Copilot review within the window (degrade gracefully,
#                       never hang forever)
#       Defaults: timeout 600s (120s when TRON_DISPATCH_ID is set and --timeout
#       wasn't passed explicitly — MD-2194), interval 20s. Best-effort — an
#       API/read failure or a repo without Copilot review exits 0 with a benign
#       status. The operator-unavailable check (TRON_COPILOT_UNAVAILABLE) is
#       fail-open: any error there falls through to the normal poll, never
#       blocks the PR.
#
# Output contract: ONE JSON line on stdout; narration on stderr.
# Exit 0 success / 1 logical failure / 2 usage error.
set -euo pipefail

log() { echo "git-pr-retro: $*" >&2; }
usage_err() { echo "git-pr-retro.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
case "$CMD" in ""|help|-h|--help) sed -n '2,39p' "$0"; exit 0 ;; esac

PR=""; RANGE=""; DIR="$(pwd)"; MODEL=""; BODY=""; BODY_FILE=""; TIMEOUT=""; INTERVAL=20
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr|--number|-n) PR="${2:-}"; shift ;;
    --range) RANGE="${2:-}"; shift ;;
    --repo-dir) DIR="${2:-}"; shift ;;
    --model) MODEL="${2:-}"; shift ;;
    --body) BODY="${2:-}"; shift ;;
    --body-file) BODY_FILE="${2:-}"; shift ;;
    --timeout) TIMEOUT="${2:-}"; shift ;;
    --interval) INTERVAL="${2:-}"; shift ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) usage_err "unexpected argument '$1'" ;;
  esac
  shift
done

# ---- skip-check ---------------------------------------------------------------
# Rows are "<added>\t<deleted>\t<path>" (git --numstat and gh --json files both
# map onto this). Binary files report "-" — they are never doc-only anyway.
cmd_skip_check() {
  local rows=""
  if [[ -n "$PR" ]]; then
    if ! rows="$(gh pr view "$PR" --json files \
        --jq '.files[] | [.additions, .deletions, .path] | @tsv' 2>/dev/null)"; then
      jq -nc '{skip:false,reason:"could not read PR files — default to requesting review"}'; return 0
    fi
  elif [[ -n "$RANGE" ]]; then
    if ! rows="$(git -C "$DIR" diff --numstat "$RANGE" 2>/dev/null)"; then
      jq -nc '{skip:false,reason:"could not diff range — default to requesting review"}'; return 0
    fi
  else
    usage_err "skip-check requires --pr <N> or --range <base>...HEAD"
  fi
  [[ -z "$rows" ]] && { jq -nc '{skip:false,reason:"empty diff — nothing to assess"}'; return 0; }

  local files=0 lines=0 nondoc="" add del path
  while IFS=$'\t' read -r add del path; do
    [[ -z "$path" ]] && continue
    files=$((files + 1))
    case "$path" in
      *.md|*.mdx) ;;
      *) nondoc="${nondoc:+$nondoc, }$path" ;;
    esac
    [[ "$add" =~ ^[0-9]+$ ]] || add=0
    [[ "$del" =~ ^[0-9]+$ ]] || del=0
    lines=$((lines + add + del))
  done <<<"$rows"

  local skip=false reason
  if [[ -n "$nondoc" ]]; then
    reason="non-doc files touched: $nondoc"
  elif (( files > 3 || lines > 40 )); then
    reason="doc-only but too large: $files files, $lines changed lines (limit: 3 files / 40 lines)"
  else
    skip=true
    reason="doc-only and small: $files files, $lines changed lines"
  fi
  jq -nc --argjson s "$skip" --arg r "$reason" '{skip:$s,reason:$r}'
}

# ---- retro-comment --------------------------------------------------------------
cmd_retro_comment() {
  [[ -z "$PR" ]] && usage_err "retro-comment requires --pr <N>"
  [[ -z "$MODEL" ]] && usage_err "retro-comment requires --model <model-id>"
  local body
  if [[ -n "$BODY_FILE" ]]; then
    [[ -f "$BODY_FILE" ]] || usage_err "--body-file not found: $BODY_FILE"
    body="$(cat "$BODY_FILE")"
  elif [[ -n "$BODY" ]]; then
    body="$BODY"
  else
    usage_err "retro-comment requires --body \"...\" or --body-file <path>"
  fi

  # Resolve the shared token-usage helper. Best-effort: missing helper or an
  # unreadable transcript yields an empty token line, never a failure.
  local here root tu tokens=""
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  root="${CLAUDE_PLUGIN_ROOT:-$(cd "$here/../../.." && pwd)}"
  tu="$root/tools/git/token-usage.sh"
  if [[ -f "$tu" ]]; then tokens="$(bash "$tu" 2>/dev/null || true)"
  else log "token-usage.sh not found under $root/tools/git — posting without a token line"; fi

  local full="<!-- tron-retro -->
### Retro
$body

---
*$MODEL*"
  [[ -n "$tokens" ]] && full+=$'\n'"$tokens"

  local url has_tokens=false full_file err_file err
  [[ -n "$tokens" ]] && has_tokens=true
  full_file="$(mktemp)"
  err_file="$(mktemp)"
  trap 'rm -f "$full_file" "$err_file"' RETURN
  printf '%s' "$full" > "$full_file"
  if ! url="$(gh pr comment "$PR" --body-file "$full_file" 2>"$err_file")"; then
    err="$(cat "$err_file")"
    jq -nc --arg n "$PR" --arg e "$err" '{ok:false,pr:($n|tonumber),reason:("gh pr comment failed: " + $e)}'; exit 1
  fi
  jq -nc --arg n "$PR" --arg u "$url" --argjson t "$has_tokens" \
    '{ok:true,pr:($n|tonumber),comment_url:$u,tokens_included:$t}'
}

# ---- request-review -------------------------------------------------------------
cmd_request_review() {
  [[ -z "$PR" ]] && usage_err "request-review requires --pr <N>"
  if gh pr edit "$PR" --add-reviewer "@copilot" >/dev/null 2>&1; then
    jq -nc --arg n "$PR" '{ok:true,pr:($n|tonumber),requested:true}'
  else
    log "Copilot review not enabled for this repo/org — continuing"
    jq -nc --arg n "$PR" '{ok:true,pr:($n|tonumber),requested:false,reason:"copilot-review-unavailable"}'
  fi
}

# ---- await-review ---------------------------------------------------------------
# Poll for Copilot's PR review so the lifecycle doesn't report "approval-ready"
# before the review actually lands. Copilot posts a submitted review (user login
# matching /copilot/i) plus zero or more inline review comments. We wait for that
# review, then classify by inline-comment count. Best-effort throughout: an
# unreadable API, an org without Copilot, or a genuine timeout all exit 0 with a
# status the caller can branch on — this step must never hang or fail the run.
#
# MD-2194: an operator can flag a known Copilot outage so every dispatch skips
# the wait instead of each one burning the full window (TRON_COPILOT_UNAVAILABLE).
# Absent that flag, a dispatched worker (TRON_DISPATCH_ID set) still gets a much
# tighter default window than an interactive run, so a dead Copilot service can't
# stall a dispatch for the full 10 minutes.
is_copilot_unavailable() {
  local v
  v="$(printf '%s' "${TRON_COPILOT_UNAVAILABLE:-}" | tr '[:upper:]' '[:lower:]')" || return 1
  case "$v" in 1|true|yes|on) return 0 ;; *) return 1 ;; esac
}

cmd_await_review() {
  [[ -z "$PR" ]] && usage_err "await-review requires --pr <N>"
  if [[ -n "$TIMEOUT" ]]; then
    [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || usage_err "--timeout must be a non-negative integer of seconds"
  elif [[ -n "${TRON_DISPATCH_ID:-}" ]]; then
    TIMEOUT=120
  else
    TIMEOUT=600
  fi
  [[ "$INTERVAL" =~ ^[0-9]+$ ]] || usage_err "--interval must be a non-negative integer of seconds"

  # Fail-open: any error inside the check falls through to a normal poll below.
  if is_copilot_unavailable; then
    jq -nc '{ok:true,status:"skipped",commentCount:0,waitedSeconds:0,timeoutSeconds:0,
      reason:"operator flag TRON_COPILOT_UNAVAILABLE set — Copilot review unavailable, skipping wait"}'
    return 0
  fi

  # Honor --repo-dir so `gh` runs against the intended checkout even when invoked
  # from elsewhere (this is the last subcommand, so cd'ing the process is fine).
  cd "$DIR" 2>/dev/null || { jq -nc --arg d "$DIR" '{ok:true,status:"error",commentCount:0,waitedSeconds:0,reason:("repo-dir not accessible: " + $d)}'; return 0; }

  # Resolve owner/repo once (from the worktree), so gh api paths are unambiguous.
  local slug
  if ! slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || [[ -z "$slug" ]]; then
    jq -nc --arg n "$PR" '{ok:true,status:"error",commentCount:0,waitedSeconds:0,reason:"could not resolve owner/repo — skipping Copilot wait"}'
    return 0
  fi

  local start now elapsed reviews review_json state review_url comments count
  start="$(date +%s)"
  while true; do
    # A submitted (non-PENDING) review authored by Copilot, latest wins. `gh api
    # --paginate` can emit one JSON array PER PAGE, so slurp (`-s`) and `add` the
    # pages into a single array before filtering — parsing it as one array would
    # miss matches on multi-page PRs and misclassify as timeout.
    if reviews="$(gh api "repos/$slug/pulls/$PR/reviews" --paginate 2>/dev/null)"; then
      review_json="$(jq -cs '(add // []) | [.[] | select((.user.login // "") | test("copilot";"i")) | select((.state // "") != "PENDING")] | last // empty' <<<"$reviews" 2>/dev/null || true)"
    else
      review_json=""
    fi

    if [[ -n "$review_json" ]]; then
      state="$(jq -r '.state // "COMMENTED"' <<<"$review_json")"
      review_url="$(jq -r '.html_url // ""' <<<"$review_json")"
      # Inline review comments authored by Copilot — the actionable items. Same
      # per-page slurp as the reviews query, so many-comment PRs aren't undercounted.
      if comments="$(gh api "repos/$slug/pulls/$PR/comments" --paginate 2>/dev/null)"; then
        comments="$(jq -cs '(add // []) | [.[] | select((.user.login // "") | test("copilot";"i")) | {path:.path, line:(.line // .original_line), body:.body, url:.html_url}]' <<<"$comments" 2>/dev/null || echo '[]')"
      else
        comments='[]'
      fi
      count="$(jq 'length' <<<"$comments")"
      now="$(date +%s)"; elapsed=$((now - start))
      local status; if (( count > 0 )); then status="commented"; else status="no-comments"; fi
      jq -nc --arg s "$status" --arg st "$state" --arg u "$review_url" \
        --argjson c "$count" --argjson cm "$comments" --argjson w "$elapsed" --argjson t "$TIMEOUT" \
        '{ok:true,status:$s,reviewState:$st,reviewUrl:$u,commentCount:$c,waitedSeconds:$w,timeoutSeconds:$t,comments:$cm}'
      return 0
    fi

    now="$(date +%s)"; elapsed=$((now - start))
    if (( elapsed >= TIMEOUT )); then
      jq -nc --argjson w "$elapsed" --argjson t "$TIMEOUT" \
        '{ok:true,status:"timeout",commentCount:0,waitedSeconds:$w,timeoutSeconds:$t,reason:("no Copilot review within " + ($t|tostring) + "s")}'
      return 0
    fi
    (( INTERVAL > 0 )) && sleep "$INTERVAL"
  done
}

case "$CMD" in
  skip-check)     cmd_skip_check ;;
  retro-comment)  cmd_retro_comment ;;
  request-review) cmd_request_review ;;
  await-review)   cmd_await_review ;;
  *) usage_err "unknown subcommand '$CMD' (try: skip-check, retro-comment, request-review, await-review)" ;;
esac
