#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s [--once] <dispatch-id> [<dispatch-id> ...]\n' "${0##*/}" >&2
  exit 2
}

once=0
if [ "${1:-}" = "--once" ]; then
  once=1
  shift
fi
[ "$#" -gt 0 ] || usage
[ -n "${TRON_API_URL:-}" ] || {
  printf 'MONITOR ERROR: TRON_API_URL is required\n' >&2
  exit 3
}
command -v curl >/dev/null 2>&1 || {
  printf 'MONITOR ERROR: curl is required\n' >&2
  exit 3
}
command -v jq >/dev/null 2>&1 || {
  printf 'MONITOR ERROR: jq is required\n' >&2
  exit 3
}

ids_json="$(printf '%s\n' "$@" | jq -R . | jq -s 'unique')"
expected="$(printf '%s' "$ids_json" | jq 'length')"
interval="${TRON_ORCHESTRATE_POLL_SECONDS:-15}"
case "$interval" in
  ''|*[!0-9]*)
    printf 'MONITOR ERROR: TRON_ORCHESTRATE_POLL_SECONDS must be a positive integer\n' >&2
    exit 3
    ;;
  0)
    printf 'MONITOR ERROR: TRON_ORCHESTRATE_POLL_SECONDS must be a positive integer\n' >&2
    exit 3
    ;;
esac

previous=''
while :; do
  if ! payload="$(curl -fsS "${TRON_API_URL%/}/api/dispatches")"; then
    printf 'MONITOR ERROR: could not read %s/api/dispatches\n' "${TRON_API_URL%/}" >&2
    exit 4
  fi
  if ! printf '%s' "$payload" | jq -e 'type == "array"' >/dev/null 2>&1; then
    printf 'MONITOR ERROR: dispatch response is not a JSON array\n' >&2
    exit 4
  fi

  current="$(printf '%s' "$payload" | jq -c --argjson ids "$ids_json" '
    map(select(.id as $id | $ids | index($id)))
    | sort_by(.id)
    | map({
        id,
        status,
        needsHuman,
        requiredChecksState,
        prNumber,
        workerWorking,
        reviewParkedAt,
        park: (if .status == "pr-open" and .workerWorking == false
          then (if .reviewParkedAt == null then "first" else "review" end)
          else "none"
        end)
      })
  ')"
  actual="$(printf '%s' "$current" | jq 'length')"
  if [ "$actual" -ne "$expected" ]; then
    printf 'MONITOR ERROR: expected %s tracked dispatches, found %s\n' "$expected" "$actual" >&2
    exit 4
  fi

  if [ "$current" != "$previous" ]; then
    printf '%s' "$current" | jq -r '.[] |
      "\(.id) status=\(.status // "unknown") needsHuman=\(.needsHuman // false) checks=\(.requiredChecksState // "unknown") pr=\(.prNumber // "-") workerWorking=\(.workerWorking // false) park=\(.park) reviewParkedAt=\(.reviewParkedAt // "-")"'
    previous="$current"
  fi

  [ "$once" -eq 0 ] || exit 0
  nonterminal="$(printf '%s' "$current" | jq '[.[] | select(.status != "done" and .status != "failed" and .status != "cancelled")] | length')"
  [ "$nonterminal" -gt 0 ] || exit 0
  sleep "$interval"
done
