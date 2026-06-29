#!/usr/bin/env bash
# Smoke test for token-usage.sh. Builds a tiny fake transcript and asserts the
# script sums + humanizes the usage records into the expected footer line, and
# that every failure mode degrades to empty output + exit 0 (never breaks the
# lifecycle).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/token-usage.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
check() { # <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then echo "ok: $1"; pass=$((pass+1)); else
    echo "FAIL: $1"; echo "  expected: [$2]"; echo "  actual:   [$3]"; fail=$((fail+1)); fi
}

# --- fixture: three assistant messages with usage at .message.usage ----------
TX="$TMP/session.jsonl"
{
  echo '{"type":"assistant","message":{"usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":20000}}}'
  echo '{"type":"user","message":{"content":"no usage here"}}'
  echo '{"type":"assistant","message":{"usage":{"input_tokens":17000,"output_tokens":7700,"cache_read_input_tokens":200000,"cache_creation_input_tokens":20000}}}'
} > "$TX"

# in 18000 -> 18k ; out 8200 -> 8.2k ; cache 1.2M read / 40k write
out="$(bash "$SCRIPT" --transcript "$TX")"
check "sums + humanizes usage" '*in 18k · out 8.2k · cache 1.2M read / 40k write*' "$out"

# --- top-level .usage fallback (no .message wrapper) -------------------------
TX2="$TMP/flat.jsonl"
echo '{"usage":{"input_tokens":500,"output_tokens":250}}' > "$TX2"
out="$(bash "$SCRIPT" --transcript "$TX2")"
check "flat .usage + sub-1k exact + zero caches" '*in 500 · out 250 · cache 0 read / 0 write*' "$out"

# --- failure modes: all must be empty stdout + exit 0 ------------------------
out="$(bash "$SCRIPT" --transcript "$TMP/does-not-exist.jsonl")"; rc=$?
check "missing transcript -> empty" "" "$out"; check "missing transcript -> exit 0" "0" "$rc"

out="$(CLAUDE_CODE_SESSION_ID="" bash "$SCRIPT")"; rc=$?
check "no session id -> empty" "" "$out"; check "no session id -> exit 0" "0" "$rc"

echo "---"; echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
