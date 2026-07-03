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
#
# Output contract: ONE JSON line on stdout; narration on stderr.
# Exit 0 success / 1 logical failure / 2 usage error.
set -euo pipefail

log() { echo "git-pr-retro: $*" >&2; }
usage_err() { echo "git-pr-retro.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
case "$CMD" in ""|help|-h|--help) sed -n '2,32p' "$0"; exit 0 ;; esac

PR=""; RANGE=""; DIR="$(pwd)"; MODEL=""; BODY=""; BODY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr|--number|-n) PR="${2:-}"; shift ;;
    --range) RANGE="${2:-}"; shift ;;
    --repo-dir) DIR="${2:-}"; shift ;;
    --model) MODEL="${2:-}"; shift ;;
    --body) BODY="${2:-}"; shift ;;
    --body-file) BODY_FILE="${2:-}"; shift ;;
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

  local url has_tokens=false
  [[ -n "$tokens" ]] && has_tokens=true
  if ! url="$(gh pr comment "$PR" --body "$full" 2>/dev/null)"; then
    jq -nc --arg n "$PR" '{ok:false,pr:($n|tonumber),reason:"gh pr comment failed — check the PR number and gh auth"}'; exit 1
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

case "$CMD" in
  skip-check)     cmd_skip_check ;;
  retro-comment)  cmd_retro_comment ;;
  request-review) cmd_request_review ;;
  *) usage_err "unknown subcommand '$CMD' (try: skip-check, retro-comment, request-review)" ;;
esac
