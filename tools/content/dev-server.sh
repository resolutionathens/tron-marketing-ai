#!/usr/bin/env bash
# dev-server: unified background Nuxt dev server runner for marketing-pages
# content pipelines (tron:preview-page, news-item, guide-item). Eliminates the
# ad-hoc port loops and poll code each skill used to hand-roll.
#
# Usage:
#   dev-server.sh start [--port N] [--route /path] [--repo PATH] [--timeout N]
#     Allocate a free port (default: first free in 4001-4010), launch Nuxt in
#     the background, poll until the server accepts connections (or --route is
#     healthy), and print the port to stdout.
#
#   dev-server.sh stop <port>
#     Kill the process listening on <port>. Exits 0 if already gone.
#
#   dev-server.sh status <port>
#     Exits 0 if a process is listening on <port>, 1 if not.
#
# Output: start prints the port on stdout; all narration goes to stderr.
# Exit 0 = success, 1 = failure (server died / timeout), 2 = usage error.
set -euo pipefail

log() { echo "dev-server: $*" >&2; }
usage_err() { echo "dev-server.sh: $*" >&2; exit 2; }

CMD="${1:-}"; [[ $# -gt 0 ]] && shift

# ---- parse flags -------------------------------------------------------
PORT=""; ROUTE=""; REPO="$(pwd)"; TIMEOUT=90
POSITIONALS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)    [[ $# -gt 1 ]] || usage_err "--port requires a value"; PORT="$2"; shift ;;
    --route)   [[ $# -gt 1 ]] || usage_err "--route requires a value"; ROUTE="$2"; shift ;;
    --repo)    [[ $# -gt 1 ]] || usage_err "--repo requires a value"; REPO="$2"; shift ;;
    --timeout) [[ $# -gt 1 ]] || usage_err "--timeout requires a value"; TIMEOUT="$2"; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) POSITIONALS+=("$1") ;;
  esac
  shift
done

# ---- helpers -----------------------------------------------------------

# True if a process is listening on $1.
port_in_use() { lsof -ti:"$1" >/dev/null 2>&1; }

# True if the server responds to an HTTP request on $1 (any status is fine).
server_responds() { curl -s -o /dev/null --max-time 2 "http://localhost:${1}/"; }

# True if --route is healthy on the server at $1.
route_healthy() {
  [[ -z "$ROUTE" ]] && return 0
  curl -s -o /dev/null --max-time 3 "http://localhost:${1}${ROUTE}"
}

# Find the marketing-pages repo root from $REPO upward.
find_marketing_pages_root() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if grep -q '"facilitron-marketing-pages"' "$dir/package.json" 2>/dev/null; then
      printf '%s\n' "$dir"; return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# ---- subcommands -------------------------------------------------------

cmd_start() {
  # Resolve the repo root.
  local root
  if ! root="$(find_marketing_pages_root "$REPO")"; then
    log "not inside the marketing-pages repo (--repo=$REPO)"; exit 1
  fi

  # Allocate a free port.
  local p
  if [[ -n "$PORT" ]]; then
    if port_in_use "$PORT"; then
      log "requested port $PORT is already in use"; exit 1
    fi
    p="$PORT"
  else
    p=""
    for candidate in 4001 4002 4003 4004 4005 4006 4007 4008 4009 4010; do
      if ! port_in_use "$candidate"; then p="$candidate"; break; fi
    done
    [[ -z "$p" ]] && { log "no free port found in 4001-4010"; exit 1; }
  fi

  local log_file="/tmp/dev-server-${p}.log"
  log "starting Nuxt on :$p (repo=$root, log=$log_file)"

  # Launch the server in the background from the repo root.
  (
    cd "$root"
    # shellcheck disable=SC1091
    [[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh" && nvm use >/dev/null 2>&1 || true
    local dotenv=""
    [[ -f "$root/.env.local" ]] && dotenv="--dotenv .env.local"
    # shellcheck disable=SC2086
    nohup ./node_modules/.bin/nuxt dev --port="$p" $dotenv >"$log_file" 2>&1 &
    disown
  )

  # Poll until the server responds or the timeout expires.
  local elapsed=0
  while [[ $elapsed -lt $TIMEOUT ]]; do
    if server_responds "$p"; then
      if route_healthy "$p"; then
        log "server up on :$p${ROUTE:+ (route $ROUTE healthy)}"
        printf '%s\n' "$p"
        return 0
      fi
    fi
    # Die early if Nuxt itself logged a fatal error.
    if grep -Eq "^(Error|error|Failed|SyntaxError|Cannot find)" "$log_file" 2>/dev/null; then
      log "server startup failed; tail of $log_file:"
      tail -20 "$log_file" >&2
      exit 1
    fi
    sleep 2
    (( elapsed += 2 )) || true
  done

  log "server on :$p did not become healthy within ${TIMEOUT}s; see $log_file"
  tail -10 "$log_file" >&2
  exit 1
}

cmd_stop() {
  local p="${1:-}"
  [[ -z "$p" ]] && usage_err "stop requires <port>"
  if port_in_use "$p"; then
    local pids
    pids="$(lsof -ti:"$p" 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
      sleep 1
      # Force-kill any survivors.
      pids="$(lsof -ti:"$p" 2>/dev/null || true)"
      [[ -n "$pids" ]] && kill -9 $pids 2>/dev/null || true
    fi
    log "stopped server on :$p"
  else
    log "nothing listening on :$p — already gone"
  fi
}

cmd_status() {
  local p="${1:-}"
  [[ -z "$p" ]] && usage_err "status requires <port>"
  if port_in_use "$p"; then
    log "server is up on :$p"; exit 0
  else
    log "no server on :$p"; exit 1
  fi
}

case "$CMD" in
  start)  cmd_start ;;
  stop)
    STOP_PORT="${POSITIONALS[0]:-$PORT}"
    cmd_stop "$STOP_PORT" ;;
  status)
    STATUS_PORT="${POSITIONALS[0]:-$PORT}"
    cmd_status "$STATUS_PORT" ;;
  ""|help|-h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) usage_err "unknown subcommand '$CMD' (try: start, stop, status)" ;;
esac
