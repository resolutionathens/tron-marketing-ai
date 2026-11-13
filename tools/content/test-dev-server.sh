#!/usr/bin/env bash
# test-dev-server.sh — offline unit tests for dev-server.sh
# No real Nuxt server is started; python3 TCP listeners simulate occupied ports.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DS="$SCRIPT_DIR/dev-server.sh"

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASSES=$(( PASSES + 1 )); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAILURES=$(( FAILURES + 1 )); }
PASSES=0
FAILURES=0

# Everything this test creates lives in one temp dir, removed on exit (MD-3398).
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

# Ports come from the OS, never fixed numbers (MD-3398): `stop` kills whatever holds
# its port, so a hardcoded port could take down an unrelated local process.
free_port() {
  python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1]); s.close()"
}
# Start a TCP listener on an OS-chosen port for $1 seconds; sets LISTEN_PID and
# LISTEN_PORT once it is accepting (bounded wait: 5s).
start_listener() {
  local port_file="$TMPD/listener-port.$RANDOM" i=0
  python3 -c "
import socket, time, sys
s = socket.socket()
s.bind(('127.0.0.1', 0)); s.listen(1)
open(sys.argv[1], 'w').write(str(s.getsockname()[1]))
time.sleep(float(sys.argv[2]))
" "$port_file" "$1" &
  LISTEN_PID=$!
  while [[ ! -s "$port_file" ]] && (( i < 100 )); do sleep 0.05; i=$(( i + 1 )); done
  LISTEN_PORT="$(cat "$port_file" 2>/dev/null || true)"
}

# ---- stop on an unused port (idempotent) --------------------------------
FREE_PORT="$(free_port)"
out="$(bash "$DS" stop "$FREE_PORT" 2>&1 || true)"
if echo "$out" | grep -q "already gone"; then pass "stop on free port is a no-op"; else fail "stop on free port: unexpected output: $out"; fi

# ---- status on an unused port -------------------------------------------
if ! bash "$DS" status "$FREE_PORT" 2>/dev/null; then pass "status exits 1 for free port"; else fail "status should exit 1 for free port"; fi

# ---- status on an occupied port -----------------------------------------
start_listener 5
PY_PID=$LISTEN_PID
if [[ -n "$LISTEN_PORT" ]] && bash "$DS" status "$LISTEN_PORT" 2>/dev/null; then pass "status exits 0 for occupied port"; else fail "status should exit 0 for occupied port"; fi
kill "$PY_PID" 2>/dev/null || true
wait "$PY_PID" 2>/dev/null || true

# ---- stop on an occupied port -------------------------------------------
start_listener 10
PY_PID2=$LISTEN_PID
out2="$( [[ -n "$LISTEN_PORT" ]] && bash "$DS" stop "$LISTEN_PORT" 2>&1 || true)"
if echo "$out2" | grep -q "stopped"; then pass "stop kills an occupied port"; else fail "stop should say 'stopped': got: $out2"; fi
wait "$PY_PID2" 2>/dev/null || true

# ---- usage errors -------------------------------------------------------
out_bad="$(bash "$DS" stop 2>&1 || true)"
if echo "$out_bad" | grep -q "requires"; then pass "stop without port prints usage error"; else fail "stop without port: $out_bad"; fi

out_unk="$(bash "$DS" frobnicate 2>&1 || true)"
if echo "$out_unk" | grep -q "unknown subcommand"; then pass "unknown subcommand prints error"; else fail "unknown subcommand: $out_unk"; fi

# ---- help text ----------------------------------------------------------
out_help="$(bash "$DS" --help 2>&1 || true)"
if echo "$out_help" | grep -q "start"; then pass "help text mentions 'start'"; else fail "help text: $out_help"; fi

# ---- start: no marketing-pages root -------------------------------------
# Run start from a plain temp dir — should fail with a clear message.
mkdir -p "$TMPD/not-a-repo"
out_no_repo="$(cd "$TMPD/not-a-repo" && bash "$DS" start --port "$(free_port)" 2>&1 || true)"
if echo "$out_no_repo" | grep -q "marketing-pages"; then pass "start outside repo emits clear error"; else fail "start outside repo: $out_no_repo"; fi

# ---- select_node_runtime: nvm/mise fallback logic -----------------------
# Stub HOME/.nvm/nvm.sh with a fake `nvm` function controlled by env vars, and
# a fake `mise` on PATH, so the fallback chain can be driven deterministically
# without touching the real nvm/mise installs.
FIXTURE_HOME="$TMPD/home"
mkdir -p "$FIXTURE_HOME/.nvm"
cat > "$FIXTURE_HOME/.nvm/nvm.sh" <<'NVMEOF'
nvm() {
  case "$1" in
    use)
      NVM_USE_CALLS=$(( ${NVM_USE_CALLS:-0} + 1 ))
      [[ "$NVM_USE_CALLS" -ge "${TEST_NVM_USE_SUCCEED_AT:-999}" ]]
      ;;
    install) return "${TEST_NVM_INSTALL_EXIT:-0}" ;;
  esac
}
NVMEOF

FIXTURE_BIN="$TMPD/bin"
mkdir -p "$FIXTURE_BIN"
cat > "$FIXTURE_BIN/mise" <<'MISEEOF'
#!/bin/sh
exit 0
MISEEOF
chmod +x "$FIXTURE_BIN/mise"

run_select_node_runtime() {
  # Each case runs in its own subshell so env/PATH tweaks don't leak.
  (
    HOME="$FIXTURE_HOME"
    export HOME
    # Reset PATH to bare essentials so a real mise/nvm on the dev machine's
    # PATH can't leak into a case that expects them absent.
    PATH="/usr/bin:/bin"
    if [[ "${1:-}" == "with-mise" ]]; then
      PATH="$FIXTURE_BIN:$PATH"
    fi
    export PATH
    # shellcheck disable=SC1090
    source "$DS"
    select_node_runtime
    echo "PREFIX_LEN=${#NODE_RUN_PREFIX[@]}"
    echo "PREFIX=${NODE_RUN_PREFIX[*]:-}"
  )
}

# nvm already has the pinned version: no prefix needed, no install attempted.
out_nvm_ok="$(TEST_NVM_USE_SUCCEED_AT=1 run_select_node_runtime 2>&1)"
if echo "$out_nvm_ok" | grep -q "PREFIX_LEN=0"; then pass "select_node_runtime: nvm use succeeds -> no prefix"; else fail "nvm use succeeds: $out_nvm_ok"; fi

# nvm doesn't have it, but installs it successfully: still no prefix needed.
out_nvm_install="$(TEST_NVM_USE_SUCCEED_AT=2 TEST_NVM_INSTALL_EXIT=0 run_select_node_runtime 2>&1)"
if echo "$out_nvm_install" | grep -q "PREFIX_LEN=0" && echo "$out_nvm_install" | grep -q "installing it"; then
  pass "select_node_runtime: nvm install recovers missing version"
else
  fail "nvm install recovers missing version: $out_nvm_install"
fi

# nvm can't ever select the version, but mise is on PATH: falls back to mise.
out_mise_fallback="$(TEST_NVM_USE_SUCCEED_AT=999 TEST_NVM_INSTALL_EXIT=0 run_select_node_runtime with-mise 2>&1)"
if echo "$out_mise_fallback" | grep -q "PREFIX=mise exec --"; then
  pass "select_node_runtime: falls back to mise exec when nvm can't select the version"
else
  fail "falls back to mise: $out_mise_fallback"
fi

# nvm can't select it and mise isn't available either: no prefix, warns loudly.
out_no_fallback="$(TEST_NVM_USE_SUCCEED_AT=999 TEST_NVM_INSTALL_EXIT=1 run_select_node_runtime 2>&1)"
if echo "$out_no_fallback" | grep -q "PREFIX_LEN=0" && echo "$out_no_fallback" | grep -q "neither nvm nor mise"; then
  pass "select_node_runtime: warns and continues on system Node when nvm and mise both fail"
else
  fail "warns when nvm and mise both fail: $out_no_fallback"
fi

echo ""
if [[ $FAILURES -eq 0 ]]; then
  printf "\033[32mall %d tests passed\033[0m\n" "$PASSES"
else
  printf "\033[31m%d test(s) FAILED\033[0m\n" "$FAILURES"
  exit 1
fi
