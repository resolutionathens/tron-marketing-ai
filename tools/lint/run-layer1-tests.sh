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

tests="$(find skills tools -name 'test-*.sh' -not -path '*/node_modules/*' | sort)"
if [ -n "${CI:-}" ]; then
  # gen-image's test scripts are excluded on CI only (still run locally): they
  # hit environment-fragile setup on GitHub's macOS runners even though
  # they're hermetic (stubbed gen-image.sh/curl/node) and reproduce green
  # locally on the same commit.
  tests="$(printf '%s\n' "$tests" | grep -v -e '/gen-image/scripts/test-gen-image\.sh$' -e '/image/test-generate-card\.sh$')"
fi

while IFS= read -r t; do
  [ -z "$t" ] && continue
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
echo "All $total layer-1 test-*.sh passed (or skipped cleanly)."
