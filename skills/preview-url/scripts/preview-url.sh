#!/usr/bin/env bash
# preview-url: detect a repo's deploy target from filesystem signals and, when
# the target registers GitHub deployments, resolve the branch's preview URL.
# The DETERMINISTIC core of tron:preview-url (Phase B). Detection is pure (no
# network); URL resolution is best-effort and degrades to a routing verdict.
#
# Usage:
#   preview-url.sh [--repo <path>] [--branch <branch>]
#     --repo    repo checkout to inspect (default: cwd)
#     --branch  branch to resolve (default: the repo's current branch)
#
# Output: one JSON line on stdout (narration on stderr). `ok` is true whenever a
# target is determined — including "Workers has no per-PR preview" and "route to
# /circleci", which are real answers, not failures. `ok` is false only for an
# undetectable target. `url` is null when this script can't resolve it here.
#   {"ok":true,"target":"cf-pages","branch":"x","url":"https://…pages.dev","confidence":"high","reason":"…"}
#   {"ok":true,"target":"cf-workers","branch":"x","url":null,"confidence":"n/a","reason":"workers has no per-PR preview URL"}
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
# (Ported from the skill's detect_deploy_target — the same top-down order.)
detect_deploy_target() {
  local repo="$1"
  if [[ -f "$repo/vercel.json" ]]; then echo vercel; return; fi
  if [[ -f "$repo/netlify.toml" ]]; then echo netlify; return; fi
  if [[ -f "$repo/fly.toml" ]]; then echo fly; return; fi
  if ls "$repo"/wrangler.* >/dev/null 2>&1; then
    if grep -qE 'pages_build_output_dir|\[env\.preview\]' "$repo"/wrangler.* 2>/dev/null; then
      echo cf-pages
    else
      echo cf-workers
    fi
    return
  fi
  if [[ -f "$repo/.circleci/config.yml" ]]; then echo circleci; return; fi
  if ls "$repo/.github/workflows"/*.yml >/dev/null 2>&1 \
     && grep -lE 'actions/deploy-pages|pages-build-deployment' "$repo/.github/workflows"/*.yml >/dev/null 2>&1; then
    echo github-pages; return
  fi
  echo unknown
}

TARGET="$(detect_deploy_target "$REPO")"
log "detected target: $TARGET (branch=$BRANCH)"

emit() { # ok target url confidence reason
  local url_json="null"; [[ "$3" != "null" ]] && url_json="\"$3\""
  printf '{"ok":%s,"target":"%s","branch":"%s","url":%s,"confidence":"%s","reason":"%s"}\n' \
    "$1" "$2" "$BRANCH" "$url_json" "$4" "$5"
}

# Resolve a URL from a GitHub deployment (Vercel / Netlify / CF Pages / GH Pages).
# Best-effort: any failure (no gh, no remote, no deployment) → empty.
gh_deployment_url() {
  local env="$1" id
  command -v gh >/dev/null 2>&1 || return 0
  ( cd "$REPO" && gh repo view >/dev/null 2>&1 ) || return 0
  id="$(cd "$REPO" && gh api "repos/:owner/:repo/deployments?ref=$BRANCH${env:+&environment=$env}" --jq '.[0].id' 2>/dev/null || true)"
  [[ -z "$id" || "$id" == "null" ]] && return 0
  ( cd "$REPO" && gh api "repos/:owner/:repo/deployments/$id/statuses" --jq '.[0].environment_url' 2>/dev/null || true )
}

case "$TARGET" in
  vercel|netlify|cf-pages|github-pages)
    ENV="Preview"; [[ "$TARGET" == github-pages ]] && ENV="github-pages"
    URL="$(gh_deployment_url "$ENV" | head -1)"
    if [[ -n "$URL" && "$URL" != "null" ]]; then
      emit true "$TARGET" "$URL" high "registered github deployment for $BRANCH"
    else
      emit true "$TARGET" null low "no registered $ENV deployment for $BRANCH yet (CI may be mid-build, or run gh from an authed checkout)"
    fi
    ;;
  fly)
    APP="$(awk -F'\"' '/^app *=/ {print $2}' "$REPO/fly.toml" 2>/dev/null | head -1)"
    if [[ -n "$APP" ]] && command -v flyctl >/dev/null 2>&1; then
      HOST="$(flyctl status -a "$APP" --json 2>/dev/null | grep -oE '"Hostname":"[^"]+"' | head -1 | cut -d'"' -f4 || true)"
      [[ -n "$HOST" ]] && { emit true fly "https://$HOST" medium "fly app $APP hostname"; exit 0; }
    fi
    emit true fly "${APP:+https://$APP.fly.dev}" "${APP:+medium}" "fly app ${APP:-unknown} (default .fly.dev host; per-PR review apps post the URL on the PR)"
    ;;
  cf-workers)
    emit true cf-workers null n/a "workers has no per-PR preview URL — each deploy overwrites production; use the dev server or merge to check prod"
    ;;
  circleci)
    emit true circleci null low "branch deploys per-CircleCI config — route to /circleci for the branch→URL mapping (do not hardcode here)"
    ;;
  *)
    emit false unknown null none "no deploy signal in $REPO — ask the user where this deploys"
    exit 1
    ;;
esac
