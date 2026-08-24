#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MONITOR="$HERE/monitor-dispatches.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tron-orchestrate-monitor-test.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
cat "$TRON_MONITOR_FIXTURE"
SH
chmod +x "$TMP/bin/curl"

cat > "$TMP/dispatches.json" <<'JSON'
[
  {"id":"d1","status":"working","needsHuman":false,"requiredChecksState":"pending","prNumber":null,"workerWorking":true,"reviewParkedAt":null},
  {"id":"d2","status":"pr-open","needsHuman":true,"requiredChecksState":"passing","prNumber":42,"workerWorking":false,"reviewParkedAt":null},
  {"id":"d3","status":"pr-open","needsHuman":true,"requiredChecksState":"passing","prNumber":43,"workerWorking":false,"reviewParkedAt":"2026-08-24T12:00:00Z"},
  {"id":"d4","status":"failed","needsHuman":true,"requiredChecksState":"failing","prNumber":null,"workerWorking":false,"reviewParkedAt":null},
  {"id":"noise","status":"done","needsHuman":false,"requiredChecksState":"passing","prNumber":7,"workerWorking":false,"reviewParkedAt":null}
]
JSON

out="$(PATH="$TMP/bin:$PATH" TRON_MONITOR_FIXTURE="$TMP/dispatches.json" TRON_API_URL=http://control.test bash "$MONITOR" --once d1 d2 d3 d4)"
printf '%s\n' "$out" | grep -Fq 'd1 status=working' || { printf 'FAIL: working dispatch missing\n' >&2; exit 1; }
printf '%s\n' "$out" | grep -Fq 'd2 status=pr-open' || { printf 'FAIL: parked dispatch missing\n' >&2; exit 1; }
printf '%s\n' "$out" | grep -Fq 'park=first' || { printf 'FAIL: first park not classified\n' >&2; exit 1; }
printf '%s\n' "$out" | grep -Fq 'park=review' || { printf 'FAIL: review re-park not classified\n' >&2; exit 1; }
printf '%s\n' "$out" | grep -Fq 'd4 status=failed' || { printf 'FAIL: terminal failure not emitted\n' >&2; exit 1; }
if printf '%s\n' "$out" | grep -Fq 'noise'; then
  printf 'FAIL: untracked dispatch leaked into output\n' >&2
  exit 1
fi

cat > "$TMP/missing.json" <<'JSON'
[{"id":"noise","status":"done"}]
JSON
set +e
out="$(PATH="$TMP/bin:$PATH" TRON_MONITOR_FIXTURE="$TMP/missing.json" TRON_API_URL=http://control.test bash "$MONITOR" --once d1 2>&1)"
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'FAIL: zero tracked rows returned success\n' >&2; exit 1; }
printf '%s\n' "$out" | grep -Fq 'MONITOR ERROR:' || { printf 'FAIL: missing-row error is not explicit\n' >&2; exit 1; }

set +e
out="$(env -u TRON_API_URL PATH="$TMP/bin:$PATH" TRON_MONITOR_FIXTURE="$TMP/dispatches.json" bash "$MONITOR" --once d1 2>&1)"
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'FAIL: missing TRON_API_URL returned success\n' >&2; exit 1; }
printf '%s\n' "$out" | grep -Fq 'TRON_API_URL' || { printf 'FAIL: missing environment error lacks remediation\n' >&2; exit 1; }

printf 'PASS: dispatch monitor filters tracked ids and fails loudly.\n'
