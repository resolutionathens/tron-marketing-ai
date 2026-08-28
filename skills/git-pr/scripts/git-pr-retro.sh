#!/usr/bin/env bash
# git-pr-retro: the mechanical post-open step of tron:git-pr (Step 7).
# The worker authors retrospective content. This script only validates and
# transports its structured payload through Scout, or assembles the explicitly
# interactive GitHub-comment fallback.
#
# Usage:
#   git-pr-retro.sh submit-dispatched --payload-file <json-file>
#       Validate the closed retrospective schema and POST the authored file to
#       $TRON_API_URL/api/dispatches/$TRON_DISPATCH_ID/retrospective. Scout owns
#       idempotency, durable storage, and canonical GitHub publication.
#   git-pr-retro.sh retro-comment --pr <N> --model <model-id> (--body-file <f> | --body "...")
#       Interactive-only fallback: post the <!-- tron-retro --> comment. The
#       body is the filled-in retro sections;
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

PR=""; MODEL=""; BODY=""; BODY_FILE=""; PAYLOAD_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr|--number|-n) PR="${2:-}"; shift ;;
    --model) MODEL="${2:-}"; shift ;;
    --body) BODY="${2:-}"; shift ;;
    --body-file) BODY_FILE="${2:-}"; shift ;;
    --payload-file) PAYLOAD_FILE="${2:-}"; shift ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) usage_err "unexpected argument '$1'" ;;
  esac
  shift
done

# ---- submit-dispatched ---------------------------------------------------------
json_failure() {
  local code="$1" error="$2"
  jq -nc --arg code "$code" --arg error "$error" '{ok:false,code:$code,error:$error}'
}

cmd_submit_dispatched() {
  if [[ -z "${TRON_API_URL:-}" || -z "${TRON_DISPATCH_ID:-}" ]]; then
    json_failure "dispatch-environment-missing" \
      "submit-dispatched requires TRON_API_URL and TRON_DISPATCH_ID from Scout"
    exit 2
  fi
  if [[ -z "$PAYLOAD_FILE" ]]; then
    json_failure "retrospective-payload-invalid" "submit-dispatched requires --payload-file <path>"
    exit 2
  fi
  if [[ ! -f "$PAYLOAD_FILE" ]]; then
    json_failure "retrospective-payload-invalid" "--payload-file not found: $PAYLOAD_FILE"
    exit 2
  fi

  # Keep this validation aligned with Scout's bounded arrays, with two producer
  # constraints Scout relies on the plugin to enforce: the schema is closed and
  # followUps contains already-filed Jira keys only. Validation never rewrites
  # the worker-authored file; curl sends its bytes unchanged.
  local validation_filter='
    def bounded(required):
      type == "array" and length <= 20 and
      (if required then length >= 1 else true end) and
      all(.[]; type == "string" and ((gsub("^[[:space:]]+|[[:space:]]+$"; "") | length) > 0) and length <= 1000);
    type == "object" and
    ((keys_unsorted - ["worked", "friction", "improvements", "followUps"]) | length == 0) and
    has("worked") and has("friction") and has("improvements") and
    (.worked | bounded(true)) and
    (.friction | bounded(true)) and
    (.improvements | bounded(true)) and
    ((has("followUps") | not) or (.followUps | bounded(false))) and
    all((.followUps // [])[]; test("^[A-Z][A-Z0-9]+-[0-9]+$"))
  '
  if ! jq -e "$validation_filter" "$PAYLOAD_FILE" >/dev/null 2>&1; then
    json_failure "retrospective-payload-invalid" \
      "payload must contain only worked, friction, improvements, and optional followUps; each required field must have 1 to 20 non-empty strings of at most 1000 characters, and followUps may contain only Jira ticket keys"
    exit 2
  fi

  command -v curl >/dev/null 2>&1 || {
    json_failure "control-plane-request-failed" "curl is required but not on PATH"
    exit 1
  }

  local endpoint response_file error_file status error response
  endpoint="${TRON_API_URL%/}/api/dispatches/${TRON_DISPATCH_ID}/retrospective"
  response_file="$(mktemp "${TMPDIR:-/tmp}/tron-retro-response.XXXXXX")"
  error_file="$(mktemp "${TMPDIR:-/tmp}/tron-retro-error.XXXXXX")"
  trap 'rm -f "$response_file" "$error_file"' RETURN
  if ! status="$(curl -sS -X POST "$endpoint" \
      -H 'content-type: application/json' \
      --data-binary "@$PAYLOAD_FILE" \
      -o "$response_file" -w '%{http_code}' 2>"$error_file")"; then
    error="$(cat "$error_file")"
    json_failure "control-plane-request-failed" "${error:-Scout retrospective request failed}"
    return 1
  fi

  if ! response="$(jq -c . "$response_file" 2>/dev/null)"; then
    json_failure "control-plane-response-invalid" \
      "Scout retrospective endpoint returned HTTP $status with a non-JSON response"
    return 1
  fi
  printf '%s\n' "$response"
  case "$status" in
    2??) return 0 ;;
    *) return 1 ;;
  esac
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
  submit-dispatched) cmd_submit_dispatched ;;
  retro-comment)  cmd_retro_comment ;;
  *) usage_err "unknown subcommand '$CMD' (try: submit-dispatched or retro-comment)" ;;
esac
