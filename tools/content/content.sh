#!/usr/bin/env bash
# content: the shared deterministic helper for the marketing-pages content
# pipelines (tron:toolkit-item, news-item, guide-item). One wrapper over
# content-lib.sh so all three call the same implementation of the steps they
# used to hand-roll. The judgment — writing copy, choosing components, building
# the PDF — stays in each skill.
#
# Usage:
#   content.sh check-repo   [--repo PATH]          → {"ok":true,"isMarketingPages":true,"checkout":"…"}
#   content.sh slug         "<title>"              → {"ok":true,"slug":"…"}
#   content.sh rewrite-links <file>                rewrite facilitron.com→relative in place
#   content.sh check-link   <path> [--repo PATH]   → {"ok":true,"path":"…","exists":true,"resolved":"pages/…"}
#   content.sh next-index   --prefix guide --suffix .webp   (names on stdin) → {"ok":true,"next":"05"}
#
# Output: one JSON line on stdout (narration on stderr). Exit 0 / 1 logical
# failure / 2 usage error.
set -euo pipefail

log() { echo "content: $*" >&2; }
usage_err() { echo "content.sh: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
REPO="$(pwd)"; PREFIX=""; SUFFIX=""; ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   [[ $# -gt 1 ]] || usage_err "--repo requires a value";   REPO="$2";   shift ;;
    --prefix) [[ $# -gt 1 ]] || usage_err "--prefix requires a value"; PREFIX="$2"; shift ;;
    --suffix) [[ $# -gt 1 ]] || usage_err "--suffix requires a value"; SUFFIX="$2"; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
LIB="${ROOT:+$ROOT/tools/content/content-lib.sh}"
[[ -z "$LIB" || ! -f "$LIB" ]] && LIB="$(cd "$(dirname "$0")" && pwd)/content-lib.sh"
# shellcheck source=/dev/null
source "$LIB"

cmd_check_repo() {
  local slug; slug="$(basename "$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || echo "$REPO")")"
  if ct_is_marketing_pages "$REPO"; then
    jq -nc --arg s "$slug" '{ok:true,isMarketingPages:true,checkout:$s}'
  else
    jq -nc --arg s "$slug" '{ok:false,isMarketingPages:false,checkout:$s,reason:"not a marketing-pages checkout — this content belongs in marketing-pages; switch checkouts first"}'
    exit 1
  fi
}

cmd_slug() {
  local title="${ARGS[0]:-}"; [[ -z "$title" ]] && usage_err "slug requires a \"<title>\" argument"
  jq -nc --arg s "$(ct_slug "$title")" '{ok:true,slug:$s}'
}

cmd_rewrite_links() {
  local f="${ARGS[0]:-}"; [[ -z "$f" ]] && usage_err "rewrite-links requires a <file>"
  [[ -f "$f" ]] || usage_err "no such file: $f"
  local n tmp
  n="$(grep -coE 'https?://(www\.)?facilitron\.com/' "$f" || true)"
  tmp="$(mktemp)"; ct_rewrite_links < "$f" > "$tmp" && mv "$tmp" "$f"
  log "rewrote $n absolute facilitron.com link(s) in $f"
  jq -nc --arg f "$f" --argjson n "${n:-0}" '{ok:true,file:$f,rewritten:$n}'
}

cmd_check_link() {
  local p="${ARGS[0]:-}"; [[ -z "$p" ]] && usage_err "check-link requires a </path>"
  local resolved
  if resolved="$(ct_resolve_page "$p" "$REPO")"; then
    jq -nc --arg p "$p" --arg r "${resolved#"$REPO"/}" '{ok:true,path:$p,exists:true,resolved:$r}'
  else
    jq -nc --arg p "$p" '{ok:false,path:$p,exists:false,reason:"no pages/*.vue serves this route — fix the link or it 404s the prerender"}'
    exit 1
  fi
}

cmd_next_index() {
  [[ -z "$PREFIX" ]] && usage_err "next-index requires --prefix"
  [[ -z "$SUFFIX" ]] && usage_err "next-index requires --suffix"
  jq -nc --arg n "$(ct_next_index "$PREFIX" "$SUFFIX")" '{ok:true,next:$n}'
}

case "$CMD" in
  check-repo)    cmd_check_repo ;;
  slug)          cmd_slug ;;
  rewrite-links) cmd_rewrite_links ;;
  check-link)    cmd_check_link ;;
  next-index)    cmd_next_index ;;
  ""|help|-h|--help) sed -n '2,18p' "$0" ;;
  *) usage_err "unknown subcommand '$CMD' (try: check-repo, slug, rewrite-links, check-link, next-index)" ;;
esac
