#!/usr/bin/env bash
# confluence: the deterministic front of tron:confluence (Phase B) — resolve a
# page id from any input shape and fetch the storage-format body via acli. The
# storage-XML → faithful-markdown transform stays a JUDGMENT step delegated to a
# subagent (see the skill's "Storage-XML → markdown" section); this script just gets
# the id and the raw body reliably so that step has clean input.
#
# Usage:
#   confluence.sh resolve <url-or-id>            → {"ok":true,"pageId":"…","source":"raw|url|tiny"}
#   confluence.sh fetch   <url-or-id> [--children] [--labels]
#       resolves the id, runs acli, prints the storage body to stdout
#       (title/version → stderr). Pipe the body into the conversion step.
#   confluence.sh images  <body.html>           list referenced attachment filenames (doc order)
#
# Output: `resolve` emits one JSON line; `fetch`/`images` are passthrough (raw
# text on stdout, narration on stderr). Exit 0 / 1 logical failure / 2 usage.
set -euo pipefail

log() { echo "confluence: $*" >&2; }
usage_err() { echo "confluence.sh: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
EXTRA=(); ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --children) EXTRA+=(--include-direct-children) ;;
    --labels) EXTRA+=(--include-labels --include-version) ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
LIB="${ROOT:+$ROOT/tools/confluence/confluence-lib.sh}"
[[ -z "$LIB" || ! -f "$LIB" ]] && LIB="$(cd "$(dirname "$0")/../../../tools/confluence" && pwd)/confluence-lib.sh"
# shellcheck source=/dev/null
source "$LIB"

# Resolve any input to a numeric page id. Offline for raw/URL; a tiny link does
# one redirect-follow. Echoes the id, or returns 1.
resolve_id() {
  local in="$1" id rc
  id="$(cl_extract_page_id "$in")" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then printf '%s' "$id"; return 0; fi
  if [[ "$rc" -eq 2 ]]; then
    id="$(curl -sIL "$in" | grep -i '^location:' | tail -1 | grep -oE '[0-9]+' | tail -1 || true)"
    [[ -n "$id" ]] && { printf '%s' "$id"; return 0; }
  fi
  return 1
}

cmd_resolve() {
  local in="${ARGS[0]:-}"; [[ -z "$in" ]] && usage_err "resolve requires <url-or-id>"
  local id
  if id="$(resolve_id "$in")"; then
    local src=tiny
    [[ "$in" =~ ^[0-9]+$ ]] && src=raw
    [[ "$in" =~ /pages/[0-9]+ ]] && src=url
    jq -nc --arg id "$id" --arg s "$src" '{ok:true,pageId:$id,source:$s}'
  else
    jq -nc --arg in "$in" '{ok:false,error:"could-not-resolve",input:$in,hint:"pass a raw id, a /pages/<id>/ URL, or a /wiki/x/ tiny link"}'
    exit 1
  fi
}

cmd_fetch() {
  command -v acli >/dev/null 2>&1 || usage_err "acli not found (the Atlassian CLI carries Confluence auth)"
  local in="${ARGS[0]:-}"; [[ -z "$in" ]] && usage_err "fetch requires <url-or-id>"
  local id; id="$(resolve_id "$in")" || { jq -nc --arg in "$in" '{ok:false,error:"could-not-resolve",input:$in}'; exit 1; }
  local out
  out="$(acli confluence page view --id "$id" --body-format storage --json "${EXTRA[@]}")" \
    || { jq -nc --arg id "$id" '{ok:false,error:"acli-fetch-failed","pageId":$id}'; exit 1; }
  log "title: $(jq -r '.title // "?"' <<<"$out")  (v$(jq -r '.version.number // .version // "?"' <<<"$out"))  pageId=$id"
  jq -r '.body.storage.value // ""' <<<"$out"
}

cmd_images() {
  local f="${ARGS[0]:-}"; [[ -z "$f" ]] && usage_err "images requires a <body.html> path"
  [[ -f "$f" ]] || usage_err "no such file: $f"
  cl_referenced_images < "$f"
}

case "$CMD" in
  resolve) cmd_resolve ;;
  fetch)   cmd_fetch ;;
  images)  cmd_images ;;
  ""|help|-h|--help) sed -n '2,18p' "$0" ;;
  *) usage_err "unknown subcommand '$CMD' (try: resolve, fetch, images)" ;;
esac
