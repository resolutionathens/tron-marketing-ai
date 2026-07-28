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
# Repo content profile (.tron/content-profile.json in the consuming repo) — the
# repo declares its own paths/schema/CDN folders; the plugin never hardcodes them:
#   content.sh profile      [--repo PATH]                  → the whole profile
#   content.sh pipeline     <name> [--slug S]              → destination/route/components, {slug} expanded
#   content.sh collection   <name>                         → front-matter schema (required/optional/enums/defaults)
#   content.sh image        <pipeline> <role> [--slug S] [--name N] [--index NN]
#                                                          → {uploadFolder,uploadName,reference} per valueFormat
#
# Output: one JSON line on stdout (narration on stderr). Exit 0 / 1 logical
# failure / 2 usage error.
set -euo pipefail

log() { echo "content: $*" >&2; }
usage_err() { echo "content.sh: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
REPO="$(pwd)"; PREFIX=""; SUFFIX=""; SLUG=""; NAME=""; INDEX=""; ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   [[ $# -gt 1 ]] || usage_err "--repo requires a value";   REPO="$2";   shift ;;
    --prefix) [[ $# -gt 1 ]] || usage_err "--prefix requires a value"; PREFIX="$2"; shift ;;
    --suffix) [[ $# -gt 1 ]] || usage_err "--suffix requires a value"; SUFFIX="$2"; shift ;;
    --slug)   [[ $# -gt 1 ]] || usage_err "--slug requires a value";   SLUG="$2";   shift ;;
    --name)   [[ $# -gt 1 ]] || usage_err "--name requires a value";   NAME="$2";   shift ;;
    --index)  [[ $# -gt 1 ]] || usage_err "--index requires a value";  INDEX="$2";  shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
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

# --- repo content profile -----------------------------------------------------
# Every profile command fails loudly, naming what it needed and where it looked.
# A content pipeline must never fall back to a guessed path: writing an article
# into an invented directory looks like success and is discovered in review.

PROFILE=""

profile_or_die() {
  local wanted="$1" root path
  root="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || echo "$REPO")"
  if ! path="$(ct_profile_path "$REPO")"; then
    jq -nc --arg r "$root" --arg f "$CT_PROFILE_REL" --arg w "$wanted" '{
      ok:false, needed:$w, expected:($r + "/" + $f),
      reason:("no " + $f + " in " + $r + " — needed " + $w +
              ". This checkout declares no content profile, so there is no destination to resolve. " +
              "Add " + $f + " (version 1) to that repo before running a content pipeline against it.")}'
    exit 1
  fi
  if ! PROFILE="$(ct_profile_read "$REPO")"; then
    jq -nc --arg p "$path" --arg w "$wanted" '{
      ok:false, needed:$w, expected:$p,
      reason:($p + " is not a readable version-1 content profile — needed " + $w +
              ". It must be valid JSON with \"version\": 1. If the repo declares a newer version, update the tron plugin.")}'
    exit 1
  fi
}

# Expand {slug}/{name}/{NN} across every string in a JSON blob. Only substitutes
# placeholders the caller supplied a value for — an unfilled one is left intact
# so the caller-side check below can refuse it by name.
profile_expand() {
  jq -c --arg slug "$SLUG" --arg name "$NAME" --arg nn "$INDEX" '
    def fill: if type == "string" then
        (if $slug != "" then gsub("\\{slug\\}"; $slug) else . end)
      | (if $name != "" then gsub("\\{name\\}"; $name) else . end)
      | (if $nn   != "" then gsub("\\{NN\\}";   $nn)   else . end)
      else . end;
    walk(fill)'
}

# Refuse to hand back a value that still carries an unfilled placeholder.
require_filled() {
  local value="$1" what="$2"
  case "$value" in
    *"{slug}"*) usage_err "$what resolves to '$value' — pass --slug" ;;
    *"{name}"*) usage_err "$what resolves to '$value' — pass --name" ;;
    *"{NN}"*)   usage_err "$what resolves to '$value' — pass --index" ;;
  esac
}

cmd_profile() {
  profile_or_die "the repo content profile"
  jq -c '.' <<<"$PROFILE"
}

cmd_pipeline() {
  local n="${ARGS[0]:-}"; [[ -z "$n" ]] && usage_err "pipeline requires a <name> (e.g. news, guides, toolkit)"
  profile_or_die "pipeline '$n'"
  local p; p="$(jq -c --arg n "$n" '.pipelines[$n] // empty' <<<"$PROFILE")"
  if [[ -z "$p" ]]; then
    jq -nc --arg n "$n" --argjson d "$(jq -c '.pipelines | keys' <<<"$PROFILE")" '{
      ok:false, needed:("pipeline \"" + $n + "\""), declared:$d,
      reason:("the content profile for this repo declares no pipeline \"" + $n +
              "\" — it declares " + ($d | join(", ")) + ". Nothing here knows where a \"" + $n +
              "\" belongs, so no file was written.")}'
    exit 1
  fi
  jq -c --arg n "$n" '{ok:true,pipeline:$n} + .' <<<"$(profile_expand <<<"$p")"
}

cmd_collection() {
  local n="${ARGS[0]:-}"; [[ -z "$n" ]] && usage_err "collection requires a <name> (e.g. news, toolkit)"
  profile_or_die "collection '$n'"
  local c; c="$(jq -c --arg n "$n" '.collections[$n] // empty' <<<"$PROFILE")"
  if [[ -z "$c" ]]; then
    jq -nc --arg n "$n" --argjson d "$(jq -c '.collections | keys' <<<"$PROFILE")" '{
      ok:false, needed:("collection \"" + $n + "\""), declared:$d,
      reason:("the content profile for this repo declares no collection \"" + $n +
              "\" — it declares " + ($d | join(", ")) + ". Front-matter fields are unknown, so nothing was written.")}'
    exit 1
  fi
  jq -c --arg n "$n" '{ok:true,collection:$n} + .' <<<"$c"
}

cmd_image() {
  local p="${ARGS[0]:-}" role="${ARGS[1]:-}"
  [[ -z "$p" || -z "$role" ]] && usage_err "image requires <pipeline> <role> (e.g. news featured)"
  profile_or_die "the '$role' asset of pipeline '$p'"
  jq -e --arg n "$p" '.pipelines[$n]' <<<"$PROFILE" >/dev/null 2>&1 \
    || { ARGS=("$p"); cmd_pipeline; }
  # Roles live under images[]; downloadable artifacts (toolkit PDF) under downloads[].
  local a; a="$(jq -c --arg n "$p" --arg r "$role" \
    '[(.pipelines[$n].images // [])[], (.pipelines[$n].downloads // [])[]] | map(select(.role == $r)) | first // empty' <<<"$PROFILE")"
  if [[ -z "$a" ]]; then
    jq -nc --arg n "$p" --arg r "$role" \
      --argjson d "$(jq -c --arg n "$p" '[(.pipelines[$n].images // [])[], (.pipelines[$n].downloads // [])[]] | map(.role)' <<<"$PROFILE")" '{
      ok:false, needed:("role \"" + $r + "\" on pipeline \"" + $n + "\""), declared:$d,
      reason:("pipeline \"" + $n + "\" declares no asset role \"" + $r + "\" — it declares " +
              ($d | join(", ")) + ". Nothing was uploaded; the CDN folder is unknown.")}'
    exit 1
  fi
  a="$(profile_expand <<<"$a")"

  local folder file fmt base ref
  folder="$(jq -r '.cdnFolder' <<<"$a")"
  file="$(jq -r '.fileName' <<<"$a")"
  fmt="$(jq -r '.valueFormat' <<<"$a")"
  require_filled "$folder" "cdnFolder for $p/$role"
  require_filled "$file"   "fileName for $p/$role"

  # valueFormat is the footgun this exists to remove: the same webp is written
  # three different ways depending on how the repo's renderer consumes it.
  case "$fmt" in
    filename)          ref="$file" ;;
    cdn-relative-path) ref="$folder/$file" ;;
    absolute-url)
      base="$(jq -r '.cdn.baseUrl // empty' <<<"$PROFILE")"
      [[ -n "$base" ]] || { echo "content.sh: profile declares valueFormat absolute-url but no cdn.baseUrl" >&2; exit 1; }
      ref="${base%/}/$folder/$file" ;;
    *)
      jq -nc --arg f "$fmt" --arg n "$p" --arg r "$role" '{
        ok:false, needed:("a known valueFormat for " + $n + "/" + $r),
        reason:("profile declares valueFormat \"" + $f +
                "\", which this plugin does not understand (known: filename, cdn-relative-path, absolute-url). " +
                "Refusing to guess how the renderer consumes it.")}'
      exit 1 ;;
  esac

  jq -c --arg folder "$folder" --arg file "$file" --arg ref "$ref" \
    '{ok:true} + . + {uploadFolder:$folder,uploadName:$file,reference:$ref}' <<<"$a"
}

case "$CMD" in
  check-repo)    cmd_check_repo ;;
  profile)       cmd_profile ;;
  pipeline)      cmd_pipeline ;;
  collection)    cmd_collection ;;
  image)         cmd_image ;;
  slug)          cmd_slug ;;
  rewrite-links) cmd_rewrite_links ;;
  check-link)    cmd_check_link ;;
  next-index)    cmd_next_index ;;
  ""|help|-h|--help) sed -n '2,26p' "$0" ;;
  *) usage_err "unknown subcommand '$CMD' (try: check-repo, slug, rewrite-links, check-link, next-index, profile, pipeline, collection, image)" ;;
esac
