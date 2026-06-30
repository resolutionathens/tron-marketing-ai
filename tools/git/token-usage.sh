#!/usr/bin/env bash
# token-usage: sum this session's token usage from the Claude Code transcript and
# print the retro footer's token line. The DETERMINISTIC half of tron:git-pr's
# Step 8 footer — the model CANNOT read its own running token count from context
# (any inline number would be fabricated), so we read the real per-message
# `usage` records out of the session transcript JSONL instead.
#
# Scope caveat: the transcript is SESSION-wide, not scoped to the PR. The figure
# is "tokens this session," which is the honest best available proxy.
#
# Usage:
#   token-usage.sh [--session <id>] [--transcript <path>]
#     --session     session id (default: $CLAUDE_CODE_SESSION_ID)
#     --transcript  explicit transcript path (skips the session-id lookup)
#
# Output: ONE markdown line on stdout, ready to drop under the model-ID line:
#   *in 18k · out 8.2k · cache 1.2M read / 40k write*
# On any failure (no session id, transcript not found, jq missing) it prints
# nothing and exits 0 — a missing token line must never fail the lifecycle.
set -euo pipefail

SID="${CLAUDE_CODE_SESSION_ID:-}"
TX=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SID="${2:-}"; shift ;;
    --transcript) TX="${2:-}"; shift ;;
    -*) echo "token-usage.sh: unknown flag '$1'" >&2; exit 0 ;;
    *) echo "token-usage.sh: unexpected argument '$1'" >&2; exit 0 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || exit 0

# Locate the transcript: explicit path wins, else find <session>.jsonl under the
# Claude projects tree. Newest match wins if a session id somehow appears twice.
if [[ -z "$TX" ]]; then
  [[ -z "$SID" ]] && exit 0
  TX="$(find "${HOME}/.claude/projects" -name "${SID}.jsonl" -type f 2>/dev/null \
        | xargs -I{} stat -f '%m %N' {} 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
fi
[[ -n "$TX" && -f "$TX" ]] || exit 0

# Sum every assistant message's usage. The usage object lives at .message.usage
# in the transcript (fall back to a top-level .usage for safety).
read -r IN OUT CR CC < <(
  jq -rs '
    [ .[] | (.message.usage // .usage) | select(. != null) ] as $u
    | [ ($u | map(.input_tokens // 0)               | add // 0),
        ($u | map(.output_tokens // 0)              | add // 0),
        ($u | map(.cache_read_input_tokens // 0)     | add // 0),
        ($u | map(.cache_creation_input_tokens // 0) | add // 0) ]
    | @tsv' "$TX" 2>/dev/null | tr '\t' ' '
) || exit 0
[[ -n "${IN:-}" ]] || exit 0

# Humanize: <1k exact, <1M as Nk, else N.NM. Keeps the footer compact.
human() {
  local n="${1:-0}"
  if   (( n < 1000 ));    then printf '%d' "$n"
  elif (( n < 1000000 )); then awk -v n="$n" 'BEGIN{ v=n/1000; printf (v==int(v)?"%dk":"%.1fk"), v }'
  else                        awk -v n="$n" 'BEGIN{ v=n/1000000; printf (v==int(v)?"%dM":"%.1fM"), v }'
  fi
}

printf '*in %s · out %s · cache %s read / %s write*\n' \
  "$(human "$IN")" "$(human "$OUT")" "$(human "$CR")" "$(human "$CC")"
