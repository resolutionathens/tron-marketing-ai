#!/usr/bin/env bash
# Run the full layer-1 deterministic-script test suite: every `test-*.sh` under
# skills/ and tools/ (see TESTING.md → "1. Deterministic scripts"). Each test is
# hermetic — it PATH-stubs its externals (gh, acli, curl) or `command -v`-guards
# optional tools and SKIPs when they're absent — so this runs green on a clean
# checkout with only the cheap tool deps installed.
#
# This is the same suite a developer runs locally; CI (.github/workflows/ci.yml)
# invokes it on macos-latest. We run on macOS/Apple Silicon *on purpose*: it is
# the plugin's only real target, its /bin/bash is 3.2 and its coreutils are BSD,
# so this natively catches the bash-3.2 empty-array-expansion bugs (CCAL-2091/
# CCAL-2092) and BSD/GNU coreutils divergence (base64, stat) that an
# ubuntu-latest runner would silently mask.
#
#   bash tools/lint/run-layer1-tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
failed=""
total=0

while IFS= read -r t; do
  total=$((total + 1))
  # GitHub Actions folds ::group::/::endgroup:: blocks; harmless locally.
  echo "::group::$t"
  if bash "$t"; then
    echo "PASS: $t"
  else
    rc=$?
    echo "FAIL: $t (exit $rc)"
    failed="$failed  $t"$'\n'
    fail=1
  fi
  echo "::endgroup::"
done < <(find skills tools -name 'test-*.sh' -not -path '*/node_modules/*' | sort)

echo "----------------------------------------------------------------------"
# Guard against a false green: if the find matched nothing (missing dirs in a
# partial checkout, a broken pattern), fail loudly rather than report "All 0 …".
if [ "$total" -eq 0 ]; then
  echo "FAIL: found no test-*.sh under skills/ or tools/ — nothing ran." >&2
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  echo "FAILED layer-1 tests:"
  printf '%s' "$failed"
  exit 1
fi
echo "All $total layer-1 test-*.sh passed (or skipped cleanly)."
