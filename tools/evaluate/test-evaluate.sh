#!/usr/bin/env bash
# Hermetic regression coverage for deterministic discovery and the explicit,
# bounded model path. The fake claude process makes no network or model calls.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
RUN="node $HERE/evaluate.mjs"
FIX="tools/evaluate/fixtures"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tron-evaluate-test.XXXXXX")"
trap 'if [ -n "${EVAL_PID:-}" ]; then kill "$EVAL_PID" 2>/dev/null || true; fi; if [ -n "${ORPHAN_PID:-}" ]; then kill "$ORPHAN_PID" 2>/dev/null || true; fi; trash "$ROOT"' EXIT

pass=0 fail=0
check() {
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
  else echo "  ✗ $1 (expected $2, got $3)"; fail=$((fail+1)); fi
}
contains() {
  case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" yes no ;; esac
}

touch "$ROOT/claude.calls"
cat >"$ROOT/fake-claude" <<'EOF'
#!/bin/sh
: "${FAKE_CLAUDE_CALLS:?}" "${FAKE_CLAUDE_ARGS:?}" "${FAKE_CLAUDE_TOKENS:?}"
printf '%s\n' call >>"$FAKE_CLAUDE_CALLS"
printf '<%s>\n' "$@" >"$FAKE_CLAUDE_ARGS"
printf '%s\n' "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-missing}" >"$FAKE_CLAUDE_TOKENS"
if [ "${FAKE_CLAUDE_HANG:-0}" = 1 ]; then
  trap '' TERM
  sleep 300 &
  printf '%s\n' "$!" >"${FAKE_CLAUDE_CHILD_PID:?}"
  wait
fi
printf '%s\n' '{"result":"{\"pass\":true,\"met\":[\"read-only flow\"],\"missing\":[],\"notes\":\"bounded fake verdict\"}"}'
EOF
chmod +x "$ROOT/fake-claude"
export TRON_EVALUATE_CLAUDE_BIN="$ROOT/fake-claude"
export FAKE_CLAUDE_CALLS="$ROOT/claude.calls"
export FAKE_CLAUDE_ARGS="$ROOT/claude.args"
export FAKE_CLAUDE_TOKENS="$ROOT/claude.tokens"

cd "$REPO_ROOT"

set +e
$RUN "$FIX/det-pass.json" --deterministic-only >/dev/null 2>&1; rc=$?
set -e
check "passing deterministic fixture exits 0" 0 "$rc"

set +e
$RUN "$FIX/det-fail.json" --deterministic-only >/dev/null 2>&1; rc=$?
set -e
check "failing deterministic fixture exits 1" 1 "$rc"

set +e
$RUN "$FIX" --deterministic-only >/dev/null 2>&1; rc=$?
set -e
check "discovery ignores model scenarios and reports deterministic failure" 1 "$rc"
check "default discovery makes zero model calls" 0 "$(wc -l <"$FAKE_CLAUDE_CALLS" | tr -d ' ')"

set +e
retired="$($RUN --judge 2>&1)"; rc=$?
set -e
check "retired --judge fails closed" 2 "$rc"
contains "retired flag reports zero calls" "$retired" "Model calls: 0"

set +e
batch="$($RUN --model-eval evaluations 2>&1)"; rc=$?
set -e
check "model evaluation refuses a directory" 2 "$rc"
contains "directory refusal reports zero calls" "$batch" "Model calls: 0"

set +e
unknown="$($RUN --model-eval "$FIX/model-pass.json" --unbounded 2>&1)"; rc=$?
set -e
check "unknown model option fails closed" 2 "$rc"
contains "unknown option reports zero calls" "$unknown" "Model calls: 0"

preview="$($RUN --model-eval "$FIX/model-pass.json" --cache-dir "$ROOT/cache" --dry-run 2>&1)"
contains "dry-run previews exactly one call" "$preview" "Model calls: 1 (hard cap: 1"
check "dry-run makes zero actual calls" 0 "$(wc -l <"$FAKE_CLAUDE_CALLS" | tr -d ' ')"

first="$($RUN --model-eval "$FIX/model-pass.json" --cache-dir "$ROOT/cache" --json 2>"$ROOT/first.err")"
echo "$first" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);if(j.modelCalls!==1||j.hardModelCallCap!==1||!j.results[0].ok)process.exit(1)})'
check "one explicit scenario makes one model call" 0 "$?"
check "fake claude invoked once" 1 "$(wc -l <"$FAKE_CLAUDE_CALLS" | tr -d ' ')"
args="$(sed -n '1,20p' "$FAKE_CLAUDE_ARGS")"
tokens="$(sed -n '1p' "$FAKE_CLAUDE_TOKENS")"
contains "fixed low-cost model is selected" "$args" "<claude-haiku-4-5-20251001>"
contains "tools are mechanically disabled" "$args" "<>"
check "output-token limit reaches subprocess" 1024 "$tokens"

second="$($RUN --model-eval "$FIX/model-pass.json" --cache-dir "$ROOT/cache" --json 2>"$ROOT/second.err")"
echo "$second" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);if(j.modelCalls!==0||!j.results[0].cached)process.exit(1)})'
check "unchanged inputs reuse content-addressed result" 0 "$?"
check "cache hit makes no additional subprocess call" 1 "$(wc -l <"$FAKE_CLAUDE_CALLS" | tr -d ' ')"

export FAKE_CLAUDE_HANG=1
export FAKE_CLAUDE_CHILD_PID="$ROOT/orphan.pid"
$RUN --model-eval "$FIX/model-pass.json" --cache-dir "$ROOT/cancel-cache" >"$ROOT/cancel.out" 2>&1 &
EVAL_PID=$!
i=0
while [ ! -s "$FAKE_CLAUDE_CHILD_PID" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i+1)); done
ORPHAN_PID="$(sed -n '1p' "$FAKE_CLAUDE_CHILD_PID")"
kill -TERM "$EVAL_PID"
set +e
wait "$EVAL_PID"; rc=$?
set -e
EVAL_PID=""
i=0
while kill -0 "$ORPHAN_PID" 2>/dev/null && [ "$i" -lt 40 ]; do sleep 0.05; i=$((i+1)); done
set +e
kill -0 "$ORPHAN_PID" 2>/dev/null; alive=$?
set -e
check "cancellation exits non-zero" 1 "$rc"
check "cancellation leaves no model subprocess orphan" 1 "$alive"
ORPHAN_PID=""

set +e
$RUN --deterministic-only >/dev/null 2>&1; rc=$?
set -e
check "repo deterministic scenarios pass" 0 "$rc"

set +e
out="$($RUN "$FIX" --deterministic-only --json 2>/dev/null)"
set -e
echo "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);if(j.failed<1||j.modelCalls!==0)process.exit(1)})'
check "JSON summary reports failure and zero calls" 0 "$?"

set +e
$RUN --help >/dev/null 2>&1; rc=$?
set -e
check "help exits 0" 0 "$rc"

echo
if [ "$fail" -eq 0 ]; then echo "✅ evaluate harness regression suite PASSED ($pass checks)"; exit 0
else echo "❌ evaluate harness regression suite FAILED ($fail of $((pass+fail)))"; exit 1; fi
