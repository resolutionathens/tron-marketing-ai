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

# ---- stop on an unused port (idempotent) --------------------------------
out="$(bash "$DS" stop 19999 2>&1 || true)"
if echo "$out" | grep -q "already gone"; then pass "stop on free port is a no-op"; else fail "stop on free port: unexpected output: $out"; fi

# ---- status on an unused port -------------------------------------------
if ! bash "$DS" status 19999 2>/dev/null; then pass "status exits 1 for free port"; else fail "status should exit 1 for free port"; fi

# ---- status on an occupied port -----------------------------------------
# Spin up a tiny TCP listener on 19998
python3 -c "
import socket, time, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 19998)); s.listen(1)
sys.stdout.write('ready\n'); sys.stdout.flush()
time.sleep(5)
" &
PY_PID=$!
sleep 0.5
if bash "$DS" status 19998 2>/dev/null; then pass "status exits 0 for occupied port"; else fail "status should exit 0 for occupied port"; fi
kill "$PY_PID" 2>/dev/null || true
wait "$PY_PID" 2>/dev/null || true

# ---- stop on an occupied port -------------------------------------------
python3 -c "
import socket, time, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 19997)); s.listen(1)
sys.stdout.write('ready\n'); sys.stdout.flush()
time.sleep(10)
" &
PY_PID2=$!
sleep 0.5
out2="$(bash "$DS" stop 19997 2>&1 || true)"
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
# Run start from /tmp — should fail with a clear message.
out_no_repo="$(cd /tmp && bash "$DS" start --port 19996 2>&1 || true)"
if echo "$out_no_repo" | grep -q "marketing-pages"; then pass "start outside repo emits clear error"; else fail "start outside repo: $out_no_repo"; fi

echo ""
if [[ $FAILURES -eq 0 ]]; then
  printf "\033[32mall %d tests passed\033[0m\n" "$PASSES"
else
  printf "\033[31m%d test(s) FAILED\033[0m\n" "$FAILURES"
  exit 1
fi
