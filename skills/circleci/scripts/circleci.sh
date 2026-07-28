#!/usr/bin/env bash
# circleci: a thin, deterministic wrapper over the CircleCI v2 API + the
# `circleci` CLI — the mechanical core of tron:circleci (Phase B). Every prose
# curl+jq recipe in SKILL.md has a subcommand here so the model calls one
# consistent entry point instead of re-assembling pipelines of curl|jq by hand.
#
# Usage:
#   circleci.sh <subcommand> [flags]
#
# Network subcommands (routed through the org-secret broker at
# secrets.facilitron.work/circleci/* — auth via `cloudflared access token`,
# no local $CIRCLECI_TOKEN required):
#   me                                  auth check → {"ok":true,"login":…}
#   pipelines  [--slug S][--branch B]   latest pipelines on a branch
#   workflows  [--slug S][--branch B]   workflows in the branch's latest pipeline
#              [--pipeline ID]            …or a specific pipeline
#   jobs       --workflow ID            jobs in a workflow
#   status     [--slug S][--branch B]   latest pipeline's workflow statuses (the green/red dots)
#   watch      --workflow ID            poll until terminal [--interval 15] [--once]
#   artifacts  --job N [--slug S]       a finished job's artifacts {path,url}
#   logs       --job N [--slug S]       raw step logs [--tail 250] [--grep-urls]
#   rerun      --workflow ID            POST rerun [--from-failed]
#   trigger    [--slug S][--branch B]   POST a fresh pipeline on a branch
#
# Pure/offline subcommands (no token, no network):
#   slug       [--repo PATH]            derive gh/Org/repo from the origin remote
#   deploy-url <branch> [--repo|--slug] per-branch deploy URL, from the repo's
#                                       declared deploy.branches when present
#
# CLI passthrough (need the `circleci` binary; print the CLI's own output):
#   validate   [-c FILE]                circleci config validate
#   process    [-c FILE]                circleci config process (orbs expanded)
#   local      --job-name NAME [-c F]   circleci local execute
#
# Output contract: verdict-style subcommands emit ONE JSON line on stdout with
# an `ok` boolean; narration goes to stderr. `logs`, `process`, `validate`, and
# `local` are passthrough fetches and print raw text. Exit 0 success / 1 logical
# failure / 2 usage error.
set -euo pipefail

BROKER_API="https://secrets.facilitron.work/circleci/v2"
DIRECT_API="https://circleci.com/api/v2"
BROKER_DOWN=0
log() { echo "circleci: $*" >&2; }
usage_err() { echo "circleci.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

# ---- flags ------------------------------------------------------------------
CMD="${1:-}"; [[ $# -gt 0 ]] && shift
REPO="$(pwd)"; SLUG=""; BRANCH=""; PIPELINE=""; WORKFLOW=""; JOB=""; JOB_NAME=""
INTERVAL=15; TAIL=250; CONFIG=""; FROM_FAILED=0; GREP_URLS=0; ONCE=0
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug) SLUG="${2:-}"; shift ;;
    --branch) BRANCH="${2:-}"; shift ;;
    --repo) REPO="${2:-}"; shift ;;
    --pipeline) PIPELINE="${2:-}"; shift ;;
    --workflow) WORKFLOW="${2:-}"; shift ;;
    --job) JOB="${2:-}"; shift ;;
    --job-name) JOB_NAME="${2:-}"; shift ;;
    --interval) INTERVAL="${2:-}"; shift ;;
    --tail) TAIL="${2:-}"; shift ;;
    --config|-c) CONFIG="${2:-}"; shift ;;
    --from-failed) FROM_FAILED=1 ;;
    --grep-urls) GREP_URLS=1 ;;
    --once) ONCE=1 ;;
    -h|--help) sed -e '1d' -e '/^set -euo pipefail$/,$d' "$0"; exit 0 ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

# ---- broker auth + http with fallback -----------------------------------------------
# A dispatched worker's tmux session gets cloudflared only via $CLOUDFLARED_PATH (MD-2079,
# lib/tmux.ts's brokerSessionEnvArgs) — the tmux server's own PATH is too minimal to resolve
# it. Honor that override before falling back to a bare PATH lookup, same as tron-os's
# lib/broker-access.ts cloudflaredBin().
cloudflared_bin() {
  if [[ -n "${CLOUDFLARED_PATH:-}" ]]; then
    printf '%s' "$CLOUDFLARED_PATH"
  else
    printf 'cloudflared'
  fi
}

resolve_broker_token() {
  local token
  token="$("$(cloudflared_bin)" access token --app=https://secrets.facilitron.work 2>/dev/null)" || true
  [[ -n "$token" ]] && printf '%s' "$token"
}

resolve_circleci_token() {
  if [[ -n "${CIRCLECI_TOKEN:-}" ]]; then printf '%s' "$CIRCLECI_TOKEN"; return; fi
  if [[ -f "$HOME/.env" ]]; then
    grep "^CIRCLECI_TOKEN=" "$HOME/.env" 2>/dev/null | head -1 | sed 's/^CIRCLECI_TOKEN=//' | sed "s/^['\"]//;s/['\"]$//" || true
  fi
}

http() { # METHOD PATH [DATA]
  local m="$1" p="$2" d="${3:-}" token url

  if [[ "$BROKER_DOWN" == 0 ]]; then
    command -v "$(cloudflared_bin)" >/dev/null 2>&1 && {
      token="$(resolve_broker_token)"
      if [[ -n "$token" ]]; then
        url="$BROKER_API/$p"
        if [[ -n "$d" ]]; then
          curl -fsS -X "$m" -H "Cookie: CF_Authorization=$token" -H "Content-Type: application/json" -d "$d" "$url" 2>/dev/null && return 0
        else
          curl -fsS -X "$m" -H "Cookie: CF_Authorization=$token" "$url" 2>/dev/null && return 0
        fi
      fi
    }
    BROKER_DOWN=1
  fi

  token="$(resolve_circleci_token)"
  [[ -z "$token" ]] && { jq -nc '{ok:false,error:"CIRCLECI_TOKEN not set (checked env and ~/.env) — needed for direct CircleCI API fallback"}'; exit 1; }
  url="$DIRECT_API/$p"
  if [[ -n "$d" ]]; then
    curl -fsS -X "$m" -H "Circle-Token: $token" -H "Content-Type: application/json" -d "$d" "$url"
  else
    curl -fsS -X "$m" -H "Circle-Token: $token" "$url"
  fi
}

# ---- pure helpers (offline-testable) ----------------------------------------
# Map an origin remote URL to a CircleCI project slug (vcs/Org/repo).
derive_slug() {
  local repo="$1" url vcs
  url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  [[ -z "$url" ]] && return 1
  url="${url%.git}"
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then vcs=gh
  elif [[ "$url" =~ bitbucket\.org[:/]([^/]+)/([^/]+)$ ]]; then vcs=bb
  else return 1; fi
  printf '%s/%s/%s' "$vcs" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

need_slug() {
  [[ -n "$SLUG" ]] && { printf '%s' "$SLUG"; return; }
  local s; if s="$(derive_slug "$REPO")"; then printf '%s' "$s"
  else jq -nc '{ok:false,error:"could not derive slug from origin remote — pass --slug gh/Org/repo"}'; exit 2; fi
}

need_branch() {
  [[ -n "$BRANCH" ]] && { printf '%s' "$BRANCH"; return; }
  local b; b="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -z "$b" ]] && { jq -nc '{ok:false,error:"no branch — pass --branch <name>"}'; exit 2; }
  printf '%s' "$b"
}

# ---- subcommands ------------------------------------------------------------
cmd_slug() {
  local s; if s="$(derive_slug "$REPO")"; then jq -nc --arg s "$s" '{ok:true,slug:$s}'
  else jq -nc '{ok:false,slug:null,reason:"origin remote is not a github/bitbucket URL — pass --slug"}'; exit 1; fi
}

# Which branch deploys where is the consuming repo's fact, so the repo gets to
# declare it: `deploy.branches` in .tron/content-profile.json, read through the
# shared profile reader rather than a second one. The built-in marketing-pages
# table below is a labelled fallback kept only so this keeps working until that
# repo declares the block; the `source` field says which one answered.
content_sh() {
  local c="${CLAUDE_PLUGIN_ROOT:-}"
  [[ -n "$c" ]] && c="$c/tools/content/content.sh"
  [[ -f "${c:-}" ]] || c="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)/tools/content/content.sh"
  [[ -f "${c:-}" ]] || return 1
  printf '%s' "$c"
}

profile_deploy_branches() {
  local c out
  c="$(content_sh)" || return 1
  # A repo that declares no profile is the ordinary case here and falls through to
  # the built-in. A profile that EXISTS but does not read is not: silently treating
  # a malformed declaration as "undeclared" hands back the built-in table for a repo
  # that was trying to override it. Surface that one.
  # Runs in a command substitution, so it cannot exit the script itself: it emits
  # the refusal JSON and returns 2, and the caller turns that into exit 1.
  if ! out="$(bash "$c" profile --repo "$REPO" 2>/dev/null)"; then
    if [[ -f "$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || echo "$REPO")/.tron/content-profile.json" ]]; then
      jq -nc '{ok:false,error:"this repo has a .tron/content-profile.json that does not read as a version-1 profile — refusing to fall back to the built-in deploy table, since a malformed declaration is not the same as no declaration. Run content.sh profile against the repo for the specific reason."}'
      return 2
    fi
    return 1
  fi
  jq -ce '.deploy.branches // empty' <<<"$out" 2>/dev/null
}

cmd_deploy_url() {
  local branch="${ARGS[0]:-$BRANCH}"
  [[ -z "$branch" ]] && usage_err "deploy-url requires a <branch> argument"
  local slug reponame declared entry prc=0
  slug="${SLUG:-$(derive_slug "$REPO" || true)}"; reponame="${slug##*/}"

  declared="$(profile_deploy_branches)" || prc=$?
  # 2 = the repo declares a profile that does not read. Refuse rather than fall back.
  if [[ "$prc" == 2 ]]; then printf '%s\n' "$declared"; exit 1; fi

  if [[ "$prc" == 0 && -n "$declared" ]]; then
    entry="$(jq -c --arg b "$branch" '.[$b] // empty' <<<"$declared")"
    if [[ -z "$entry" ]]; then
      jq -nc --arg b "$branch" --arg r "${reponame:-unknown}" \
        --argjson d "$(jq -c 'keys' <<<"$declared")" '{
        ok:false, repo:$r, branch:$b, url:null, declared:$d, source:"repo-profile",
        reason:("this repo declares deploy URLs for " + ($d | join(", ")) +
                " — \"" + $b + "\" is not one of them, so it has no preview URL")}'
      exit 1
    fi
    jq -c --arg b "$branch" --arg r "${reponame:-unknown}" \
      '{ok:true,repo:$r,branch:$b,source:"repo-profile"} + .' <<<"$entry"
    return
  fi

  if [[ "$reponame" == "marketing-pages" ]]; then
    local url env
    case "$branch" in
      dev)        url="https://morning-coast.facilitron.com"; env="Development" ;;
      staging)    url="https://staging.facilitron.com";       env="Staging" ;;
      production) url="https://www.facilitron.com";            env="Production" ;;
      *) jq -nc --arg b "$branch" '{ok:false,repo:"marketing-pages",branch:$b,url:null,source:"builtin-fallback",reason:"only dev/staging/production deploy — feature branches have no preview until merged to dev"}'; exit 1 ;;
    esac
    jq -nc --arg b "$branch" --arg u "$url" --arg e "$env" \
      '{ok:true,repo:"marketing-pages",branch:$b,environment:$e,url:$u,source:"builtin-fallback",reason:"canonical per-branch CircleCI→S3+CloudFront URL, from the plugin'"'"'s built-in table — marketing-pages has not yet declared deploy.branches in its content profile"}'
    return
  fi
  jq -nc --arg b "$branch" --arg r "${reponame:-unknown}" \
    '{ok:false,repo:$r,branch:$b,url:null,source:null,reason:"this repo declares no deploy.branches in .tron/content-profile.json and the plugin has no built-in table for it — check the repo'"'"'s README Environments section"}'
  exit 1
}

cmd_me() { http GET "me" | jq -c '{ok:true,login:.login,name:.name,id:.id}'; }

cmd_pipelines() {
  local slug branch; slug="$(need_slug)"; branch="$(need_branch)"
  http GET "project/$slug/pipeline?branch=$branch" \
    | jq -c --arg s "$slug" --arg b "$branch" \
      '{ok:true,slug:$s,branch:$b,items:[.items[]|{id,number,state,revision:.vcs.revision,created_at}]}'
}

cmd_workflows() {
  local slug branch pid; slug="$(need_slug)"
  if [[ -n "$PIPELINE" ]]; then pid="$PIPELINE"
  else
    branch="$(need_branch)"
    pid="$(http GET "project/$slug/pipeline?branch=$branch" | jq -r '.items[0].id // empty')"
    [[ -z "$pid" ]] && { jq -nc --arg b "$branch" '{ok:false,branch:$b,reason:"no pipeline found for branch"}'; exit 1; }
  fi
  http GET "pipeline/$pid/workflow" \
    | jq -c --arg p "$pid" '{ok:true,pipeline:$p,items:[.items[]|{name,status,id,created_at,stopped_at}]}'
}

cmd_jobs() {
  [[ -z "$WORKFLOW" ]] && usage_err "jobs requires --workflow <id>"
  http GET "workflow/$WORKFLOW/job" \
    | jq -c --arg w "$WORKFLOW" '{ok:true,workflow:$w,items:[.items[]|{name,status,job_number,started_at,stopped_at}]}'
}

cmd_status() {
  local slug branch pid; slug="$(need_slug)"; branch="$(need_branch)"
  pid="$(http GET "project/$slug/pipeline?branch=$branch" | jq -r '.items[0].id // empty')"
  [[ -z "$pid" ]] && { jq -nc --arg b "$branch" '{ok:false,branch:$b,reason:"no pipeline found for branch"}'; exit 1; }
  http GET "pipeline/$pid/workflow" \
    | jq -c --arg s "$slug" --arg b "$branch" --arg p "$pid" \
      '{ok:true,slug:$s,branch:$b,pipeline:$p,workflows:[.items[]|{name,status,id}]}'
}

cmd_watch() {
  [[ -z "$WORKFLOW" ]] && usage_err "watch requires --workflow <id>"
  local status
  while true; do
    status="$(http GET "workflow/$WORKFLOW" | jq -r '.status')"
    log "$(date +%H:%M:%S) $status"
    case "$status" in success|failed|canceled|error|unauthorized|not_run) break ;; esac
    [[ "$ONCE" == 1 ]] && break
    sleep "$INTERVAL"
  done
  local ok=false; [[ "$status" == success ]] && ok=true
  jq -nc --arg w "$WORKFLOW" --arg s "$status" --argjson ok "$ok" '{ok:$ok,workflow:$w,status:$s}'
}

cmd_artifacts() {
  local slug; slug="$(need_slug)"
  [[ -z "$JOB" ]] && usage_err "artifacts requires --job <number>"
  http GET "project/$slug/$JOB/artifacts" \
    | jq -c --arg j "$JOB" '{ok:true,job:$j,items:[.items[]|{path,url}]}'
}

cmd_logs() {
  local slug; slug="$(need_slug)"
  [[ -z "$JOB" ]] && usage_err "logs requires --job <number>"
  local urls; urls="$(http GET "project/$slug/job/$JOB" \
    | jq -r '.steps[].actions[] | select(.output_url != null) | .output_url')"
  [[ -z "$urls" ]] && { log "no step logs found for job $JOB"; return; }
  { while IFS= read -r u; do curl -fsS -L "$u" 2>/dev/null || true; echo; done <<<"$urls"; } \
    | { if [[ "$GREP_URLS" == 1 ]]; then grep -iaoE 'https?://[a-z0-9./_-]+' || true; else cat; fi; } \
    | tail -n "$TAIL"
}

cmd_rerun() {
  [[ -z "$WORKFLOW" ]] && usage_err "rerun requires --workflow <id>"
  local body='{}'; [[ "$FROM_FAILED" == 1 ]] && body='{"from_failed": true}'
  http POST "workflow/$WORKFLOW/rerun" "$body" | jq -c '{ok:true,workflow_id:(.workflow_id // null)}'
}

cmd_trigger() {
  local slug branch; slug="$(need_slug)"; branch="$(need_branch)"
  http POST "project/$slug/pipeline" "$(jq -nc --arg b "$branch" '{branch:$b}')" \
    | jq -c '{ok:true,id:(.id // null),number:(.number // null),state:(.state // null)}'
}

cmd_validate() {
  command -v circleci >/dev/null 2>&1 || usage_err "the circleci CLI is not on PATH"
  if [[ -n "$CONFIG" ]]; then circleci config validate -c "$CONFIG"; else circleci config validate; fi
}

cmd_process() {
  command -v circleci >/dev/null 2>&1 || usage_err "the circleci CLI is not on PATH"
  circleci config process "${CONFIG:-.circleci/config.yml}"
}

cmd_local() {
  command -v circleci >/dev/null 2>&1 || usage_err "the circleci CLI is not on PATH"
  [[ -z "$JOB_NAME" ]] && usage_err "local requires --job-name <name>"
  if [[ -n "$CONFIG" ]]; then circleci local execute -c "$CONFIG" --job "$JOB_NAME"
  else circleci local execute --job "$JOB_NAME"; fi
}

case "$CMD" in
  me)         cmd_me ;;
  pipelines)  cmd_pipelines ;;
  workflows)  cmd_workflows ;;
  jobs)       cmd_jobs ;;
  status)     cmd_status ;;
  watch)      cmd_watch ;;
  artifacts)  cmd_artifacts ;;
  logs)       cmd_logs ;;
  rerun)      cmd_rerun ;;
  trigger)    cmd_trigger ;;
  slug)       cmd_slug ;;
  deploy-url) cmd_deploy_url ;;
  validate)   cmd_validate ;;
  process)    cmd_process ;;
  local)      cmd_local ;;
  ""|help|-h|--help) sed -e '1d' -e '/^set -euo pipefail$/,$d' "$0" ;;
  *) usage_err "unknown subcommand '$CMD' (try: me, status, workflows, watch, logs, deploy-url, validate …)" ;;
esac
