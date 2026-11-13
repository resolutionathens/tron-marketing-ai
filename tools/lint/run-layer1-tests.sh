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

# The suite sets up what it depends on instead of inheriting it from the machine
# (MD-3398), so a failure means the code is wrong, not that this host is set up
# differently.
RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/layer1-run.XXXXXX")"
trap 'rm -rf "$RUN_TMP"' EXIT

# node: put a real binary first on PATH. A mise shim with no global version fails as
# soon as a test narrows PATH; node's own execPath is the binary behind it. Where no
# node runs on PATH at all, use the newest node mise already has installed (never
# node@lts, which can name an uninstalled version and trigger a download).
node_real="$(node -p process.execPath 2>/dev/null)" || node_real=""
if [ ! -x "$node_real" ] && command -v mise >/dev/null 2>&1; then
  node_version="$(mise ls --installed node 2>/dev/null | awk '$1=="node"{print $2}' | sort -V | tail -1)" || node_version=""
  if [ -n "$node_version" ]; then
    node_real="$(mise where "node@$node_version" 2>/dev/null)/bin/node" || node_real=""
  fi
fi
if [ -x "$node_real" ]; then
  mkdir -p "$RUN_TMP/bin"
  ln -s "$node_real" "$RUN_TMP/bin/node"
  PATH="$RUN_TMP/bin:$PATH"
  export PATH
else
  echo "WARN: no runnable node found on PATH or through mise; node-based tests will fail or skip" >&2
fi

# git: the tests commit, merge and push in fixture repos. Give them a known identity and
# default branch, and keep the host's global and system git config (hooks, signing,
# insteadOf rewrites, init.defaultBranch) out of them.
cat > "$RUN_TMP/gitconfig" <<'GITCONFIG'
[user]
	name = Layer-1 Test
	email = layer1@example.invalid
[init]
	defaultBranch = master
[commit]
	gpgsign = false
[tag]
	gpgsign = false
GITCONFIG
GIT_CONFIG_GLOBAL="$RUN_TMP/gitconfig"
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

# Backstop: no single test may run longer than this, so a hang reports as a failure
# instead of stalling the suite. The slowest test (the release build) takes ~20s.
LAYER1_TEST_TIMEOUT="${LAYER1_TEST_TIMEOUT:-120}"

# Run one test in its own process group. On timeout (exit 142), or if the runner itself
# is interrupted, the whole group is terminated, so no builder or server a test started
# keeps running into the next test.
run_bounded() {
  perl -e '
    my $limit = shift @ARGV;
    my $pid = fork;
    die "fork: $!\n" unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV or die "exec: $!\n"; }
    sub stop_group { kill "TERM", -$pid; sleep 2; kill "KILL", -$pid; waitpid($pid, 0); exit $_[0]; }
    $SIG{ALRM} = sub { stop_group(142) };
    $SIG{INT}  = sub { stop_group(130) };
    $SIG{TERM} = sub { stop_group(143) };
    alarm $limit;
    waitpid($pid, 0);
    my $status = $?;
    alarm 0;
    kill "KILL", -$pid;   # reap anything the test left running in its group
    exit(($status & 127) ? 128 + ($status & 127) : $status >> 8);
  ' "$LAYER1_TEST_TIMEOUT" "$@"
}

fail=0
failed=""
total=0
skipped=0
skipped_tests=""

tests="$(find skills tools -name 'test-*.sh' -not -path '*/node_modules/*' | sort)"
if [ -n "${CI:-}" ]; then
  # gen-image's test clears or sets every API key it needs and fakes codex, so it runs
  # the same in CI as anywhere (MD-3398). Only exclude test-generate-card.sh, which is
  # image-publishing related and requires ImageKit auth.
  tests="$(printf '%s\n' "$tests" | grep -v -e '/image/test-generate-card\.sh$')"
fi

while IFS= read -r t; do
  [ -z "$t" ] && continue
  total=$((total + 1))
  # GitHub Actions folds ::group::/::endgroup:: blocks; harmless locally.
  echo "::group::$t"
  started="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
  run_bounded bash "$t" </dev/null
  rc=$?
  took="$(perl -MTime::HiRes=time -e 'printf "%.1fs", time - $ARGV[0]' "$started")"
  if [ "$rc" -eq 142 ]; then
    echo "TIMEOUT: $t ran longer than ${LAYER1_TEST_TIMEOUT}s"
  fi
  if [ "$rc" -eq 0 ]; then
    echo "PASS: $t ($took)"
  elif [ "$rc" -eq 77 ]; then
    echo "SKIP: $t ($took)"
    skipped_tests="$skipped_tests  $t"$'\n'
    skipped=$((skipped + 1))
  else
    echo "FAIL: $t (exit $rc, $took)"
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
