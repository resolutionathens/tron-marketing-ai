#!/usr/bin/env bash
# Run the full layer-1 deterministic-script test suite: every `test-*.sh` under
# skills/ and tools/ (see TESTING.md → "1. Deterministic scripts"). Each test is
# hermetic — it PATH-stubs its externals (gh, acli, curl) or `command -v`-guards
# optional tools and SKIPs when they're absent — so this runs green on a clean
# checkout with only the cheap tool deps installed.
#
# tron:git-pr runs this suite locally before pushing or creating a PR. Running
# on the developer's macOS/Apple Silicon host is intentional: it is the plugin's
# only real target, its /bin/bash is 3.2 and its coreutils are BSD, so this catches
# the bash-3.2 empty-array-expansion bugs (CCAL-2091/CCAL-2092) and BSD/GNU
# coreutils divergence (base64, stat) that an Ubuntu runner would silently mask.
#
#   bash tools/lint/run-layer1-tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
failed=""
total=0
skipped=0
skipped_tests=""

tests="$(find skills tools -name 'test-*.sh' -not -path '*/node_modules/*' | sort)"
if [ -n "${CI:-}" ]; then
  # gen-image test now skips unauthenticated exec tests on CI via CI= guard in the
  # test itself, so it runs cleanly in CI. Only exclude test-generate-card.sh which
  # is image publishing related and requires ImageKit auth.
  tests="$(printf '%s\n' "$tests" | grep -v -e '/image/test-generate-card\.sh$')"
fi

while IFS= read -r t; do
  [ -z "$t" ] && continue
  total=$((total + 1))
  # GitHub Actions folds ::group::/::endgroup:: blocks; harmless locally.
  echo "::group::$t"
  bash "$t"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS: $t"
  elif [ "$rc" -eq 77 ]; then
    echo "SKIP: $t"
    skipped_tests="$skipped_tests  $t"$'\n'
    skipped=$((skipped + 1))
  else
    echo "FAIL: $t (exit $rc)"
    failed="$failed  $t"$'\n'
    fail=1
  fi
  echo "::endgroup::"
done <<< "$tests"

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
passed=$((total - skipped))
echo "All $total layer-1 test-*.sh completed: $passed passed, $skipped skipped."
if [ "$skipped" -ne 0 ]; then
  echo "SKIPPED layer-1 tests:"
  printf '%s' "$skipped_tests"
fi
