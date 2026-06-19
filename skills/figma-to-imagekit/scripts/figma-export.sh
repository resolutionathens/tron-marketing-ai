#!/usr/bin/env bash
# figma-export: the DETERMINISTIC per-node leg of tron:figma-to-imagekit (Phase
# B) — the exact pipeline the skill fans out to a Haiku subagent: download an
# already-resolved asset URL → sips resize → pngquant → ImageKit upload, and
# emit one result row. The JUDGMENT stays in the skill/MCP: discovering nodes,
# naming each image, and picking the resize target. This script is given those.
#
# Usage:
#   figma-export.sh parse-url <figma-design-url>
#       → {"ok":true,"fileKey":"…","nodeId":"1166:3012"}   (pure, offline)
#   figma-export.sh run (--url <asset-url> | --file <path>) --name <out.png>
#       [--folder <imagekit-folder>] [--resize 1280] [--quality 65-80]
#       [--no-upload] [--overwrite]
#       → {"ok":true,"name":"hero.png","original":12345,"optimized":3456,
#          "savings":"72%","path":"product/works/main/hero.png","url":"https://ik…"}
#
# Output: one JSON line on stdout (verbose sips/pngquant/curl on stderr). Exit
# 0 success / 1 logical failure / 2 usage error.
set -euo pipefail

log() { echo "figma-export: $*" >&2; }
usage_err() { echo "figma-export.sh: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
URL=""; FILE=""; NAME=""; FOLDER=""; RESIZE=1280; QUALITY="65-80"; NO_UPLOAD=0; OVERWRITE=0
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="${2:-}"; shift ;;
    --file) FILE="${2:-}"; shift ;;
    --name) NAME="${2:-}"; shift ;;
    --folder) FOLDER="${2:-}"; shift ;;
    --resize) RESIZE="${2:-}"; shift ;;
    --quality) QUALITY="${2:-}"; shift ;;
    --no-upload) NO_UPLOAD=1 ;;
    --overwrite) OVERWRITE=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

# Pure: extract fileKey + nodeId from a Figma design/file URL. node-id in a URL
# uses '-' between the two numbers (1166-3012); the API wants ':' (1166:3012).
cmd_parse_url() {
  local in="${ARGS[0]:-}"; [[ -z "$in" ]] && usage_err "parse-url requires a <figma-url>"
  local fileKey="" nodeId=""
  [[ "$in" =~ /(design|file)/([A-Za-z0-9]+) ]] && fileKey="${BASH_REMATCH[2]}"
  [[ -z "$fileKey" ]] && { jq -nc --arg in "$in" '{ok:false,error:"no fileKey in URL",input:$in}'; exit 1; }
  if [[ "$in" =~ [?\&]node-id=([0-9A-Za-z%:_-]+) ]]; then
    nodeId="${BASH_REMATCH[1]}"
    nodeId="${nodeId//%3A/:}"   # decode an encoded colon
    nodeId="${nodeId/-/:}"      # first '-' → ':'  (1166-3012 → 1166:3012)
  fi
  if [[ -n "$nodeId" ]]; then jq -nc --arg f "$fileKey" --arg n "$nodeId" '{ok:true,fileKey:$f,nodeId:$n}'
  else jq -nc --arg f "$fileKey" '{ok:true,fileKey:$f,nodeId:null}'; fi
}

cmd_run() {
  [[ -z "$NAME" ]] && usage_err "run requires --name <out.png>"
  [[ -z "$URL" && -z "$FILE" ]] && usage_err "run requires --url <asset-url> or --file <path>"
  [[ "$NO_UPLOAD" -eq 0 && -z "$FOLDER" ]] && usage_err "run requires --folder (or pass --no-upload)"
  command -v sips >/dev/null 2>&1 || usage_err "sips not found (macOS only) — needed to resize"
  command -v pngquant >/dev/null 2>&1 || usage_err "pngquant not found — needed to optimize"

  work="$(mktemp -d "${TMPDIR:-/tmp}/figma-export.XXXXXX")"   # global so the EXIT trap can see it
  trap 'rm -rf "${work:-}"' EXIT
  local raw="$work/raw.png"

  if [[ -n "$FILE" ]]; then
    [[ -f "$FILE" ]] || { jq -nc --arg f "$FILE" '{ok:false,error:"no such file",file:$f}'; exit 1; }
    cp "$FILE" "$raw"
  else
    log "downloading $URL"
    curl -fsS -o "$raw" "$URL" || { jq -nc --arg u "$URL" '{ok:false,error:"download-failed",url:$u}'; exit 1; }
  fi
  if ! file "$raw" | grep -qi 'PNG image'; then
    jq -nc --arg n "$NAME" '{ok:false,error:"source-not-png","name":$n,hint:"this pipeline handles PNG; for jpg/svg use the format options in the skill prose"}'
    exit 1
  fi

  local orig opt resized="$work/resized.png" final="$work/$NAME"
  orig=$(wc -c < "$raw" | tr -d ' ')
  sips -Z "$RESIZE" "$raw" --out "$resized" >/dev/null 2>&1
  pngquant --quality="$QUALITY" --speed 1 --strip --force --output "$final" "$resized" >&2
  opt=$(wc -c < "$final" | tr -d ' ')
  local pct=0; [[ "$orig" -gt 0 ]] && pct=$(( (orig - opt) * 100 / orig ))
  log "optimized $NAME: ${orig}B → ${opt}B (${pct}% smaller)"

  if [[ "$NO_UPLOAD" -eq 1 ]]; then
    jq -nc --arg n "$NAME" --argjson o "$orig" --argjson p "$opt" --arg s "${pct}%" \
      '{ok:true,name:$n,original:$o,optimized:$p,savings:$s,uploaded:false}'
    return
  fi

  local IK="${CLAUDE_PLUGIN_ROOT:-}"; IK="${IK:+$IK/tools/imagekit/imagekit.mjs}"
  [[ -z "$IK" || ! -f "$IK" ]] && IK="$(cd "$(dirname "$0")/../../../tools/imagekit" && pwd)/imagekit.mjs"
  local up_args=(upload "$final" --folder "$FOLDER" --name "$NAME")
  [[ "$OVERWRITE" -eq 1 ]] && up_args+=(--overwriteFile true)
  local out url
  out="$(node "$IK" "${up_args[@]}" 2>>"$work/ik.err")" \
    || { jq -nc --arg n "$NAME" '{ok:false,error:"imagekit-upload-failed","name":$n}'; exit 1; }
  url="$(jq -r '.url // .filePath // empty' <<<"$out" 2>/dev/null || true)"
  jq -nc --arg n "$NAME" --argjson o "$orig" --argjson p "$opt" --arg s "${pct}%" \
    --arg path "$FOLDER/$NAME" --arg url "$url" \
    '{ok:true,name:$n,original:$o,optimized:$p,savings:$s,path:$path,url:($url|select(.!="")//null),uploaded:true}'
}

case "$CMD" in
  parse-url) cmd_parse_url ;;
  run)       cmd_run ;;
  ""|help|-h|--help) sed -n '2,20p' "$0" ;;
  *) usage_err "unknown subcommand '$CMD' (try: parse-url, run)" ;;
esac
