#!/usr/bin/env bash
# git-pr-retro: the mechanical post-open step of tron:git-pr (Step 7).
# The judgment (PR title/body, what goes in the retro sections) stays with the
# model; this script owns the assembly that kept being re-derived in prose: the
# retro-comment footer (token-usage resolution + marker + model line).
#
# Usage:
#   git-pr-retro.sh retro-comment --pr <N> --model <model-id> (--body-file <f> | --body "...")
#       Post the <!-- tron-retro --> comment. The body is the filled-in retro
#       sections (What went well / Friction / Follow-up / FOLLOW-UP: lines);
#       the script adds the marker, "### Retro" header, and the footer
#       (*<model-id>* + the token line from tools/git/token-usage.sh, resolved
#       via CLAUDE_PLUGIN_ROOT with a relative fallback — an unreadable
#       transcript never blocks the comment).
#
# Output contract: ONE JSON line on stdout; narration on stderr.
# Exit 0 success / 1 logical failure / 2 usage error.
#
# --- end of `help` output; rationale below --------------------------------------
#
# MD-2746: the three GitHub-reviewer subcommands (skip-check, request-review,
# await-review) are GONE. MD-2745 moved code review off GitHub and onto this
# machine, BEFORE the PR exists (`bun run review:local`). Nothing reviews the PR
# after it opens, so requesting a reviewer would block on a reply that never
# comes — the same unbounded-wait failure MD-2489 and MD-2536 each had to fix
# once. Posting the retro is all that is left to do after `gh pr create`.
set -euo pipefail

log() { echo "git-pr-retro: $*" >&2; }
usage_err() { echo "git-pr-retro.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
case "$CMD" in ""|help|-h|--help) sed -n '2,18p' "$0"; exit 0 ;; esac

PR=""; MODEL=""; BODY=""; BODY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr|--number|-n) PR="${2:-}"; shift ;;
    --model) MODEL="${2:-}"; shift ;;
    --body) BODY="${2:-}"; shift ;;
    --body-file) BODY_FILE="${2:-}"; shift ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) usage_err "unexpected argument '$1'" ;;
  esac
  shift
done

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
  full_file="$(mktemp "${TMPDIR:-/tmp}/tron-pr-retro-body.XXXXXX")"
  err_file="$(mktemp "${TMPDIR:-/tmp}/tron-pr-retro-error.XXXXXX")"
  trap 'rm -f "$full_file" "$err_file"' RETURN
  printf '%s' "$full" > "$full_file"
  if ! url="$(gh pr comment "$PR" --body-file "$full_file" 2>"$err_file")"; then
    err="$(cat "$err_file")"
    jq -nc --arg n "$PR" --arg e "$err" '{ok:false,pr:($n|tonumber),reason:("gh pr comment failed: " + $e)}'; exit 1
  fi
  jq -nc --arg n "$PR" --arg u "$url" --argjson t "$has_tokens" \
    '{ok:true,pr:($n|tonumber),comment_url:$u,tokens_included:$t}'
}

case "$CMD" in
  retro-comment)  cmd_retro_comment ;;
  *) usage_err "unknown subcommand '$CMD' (try: retro-comment)" ;;
esac
