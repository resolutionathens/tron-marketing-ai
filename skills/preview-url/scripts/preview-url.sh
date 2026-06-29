#!/usr/bin/env bash
# preview-url: detect a repo's deploy target from filesystem signals and resolve
# (or route to) the branch's staging/preview URL. The DETERMINISTIC core of
# tron:preview-url. Detection is pure (no network).
#
# Scoped to the Facilitron stack: deploys happen two ways — CircleCI (marketing-pages
# and friends → fixed dev/staging/prod URLs) and Cloudflare Workers (Scout, the broker
# → no per-PR preview). Other targets (Vercel/Netlify/Fly/Pages/GH-Pages) aren't used
# here and are intentionally not detected.
#
# Usage:
#   preview-url.sh [--repo <path>] [--branch <branch>]
#     --repo    repo checkout to inspect (default: cwd)
#     --branch  branch to resolve (default: the repo's current branch)
#
# Output: one JSON line on stdout (narration on stderr). `ok` is true whenever a
# target is determined — including "Workers has no per-PR preview" and "route to
# /circleci", which are real answers, not failures. `ok` is false only for an
# undetectable target.
#   {"ok":true,"target":"cf-workers","branch":"x","url":null,"confidence":"n/a","reason":"workers has no per-PR preview URL"}
#   {"ok":true,"target":"circleci","branch":"x","url":null,"confidence":"low","reason":"consult the branch→URL table"}
#   {"ok":false,"target":"unknown","branch":"x","url":null,"confidence":"none","reason":"no deploy signal — ask the user"}
set -euo pipefail

log() { echo "preview-url: $*" >&2; }

REPO="$(pwd)"; BRANCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift ;;
    --branch) BRANCH="${2:-}"; shift ;;
    -*) echo "preview-url.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) echo "preview-url.sh: unexpected argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

[[ -d "$REPO" ]] || { echo "{\"ok\":false,\"error\":\"no such repo: $REPO\"}"; exit 2; }
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi

# ---- detection: pure filesystem signals, first match wins -------------------
detect_deploy_target() {
  local repo="$1"
  # Cloudflare Workers (Scout, broker). A wrangler config = Workers; no per-PR preview.
  if ls "$repo"/wrangler.* >/dev/null 2>&1; then echo cf-workers; return; fi
  # CircleCI (marketing-pages and friends) — branch deploys to a fixed URL.
  if [[ -f "$repo/.circleci/config.yml" ]]; then echo circleci; return; fi
  echo unknown
}

TARGET="$(detect_deploy_target "$REPO")"
log "detected target: $TARGET (branch=$BRANCH)"

emit() { # ok target url confidence reason
  local url_json="null"; [[ "$3" != "null" ]] && url_json="\"$3\""
  printf '{"ok":%s,"target":"%s","branch":"%s","url":%s,"confidence":"%s","reason":"%s"}\n' \
    "$1" "$2" "$BRANCH" "$url_json" "$4" "$5"
}

case "$TARGET" in
  cf-workers)
    emit true cf-workers null n/a "workers has no per-PR preview URL — each deploy overwrites production; use the dev server or merge to check prod"
    ;;
  circleci)
    emit true circleci null low "branch deploys per-CircleCI config — consult the marketing-pages branch→URL table in this skill (Facilitron branch→URL table) before the CircleCI API; /circleci has the same table plus bucket detail"
    ;;
  *)
    emit false unknown null none "no deploy signal in $REPO — ask the user where this deploys"
    exit 1
    ;;
esac
