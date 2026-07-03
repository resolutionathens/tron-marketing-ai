#!/usr/bin/env bash
# Smoke for weekly-activity.sh. The Jira/GitHub network pulls need real auth and
# aren't asserted here. What IS deterministic and offline: the window math
# (Monday-anchored, --weeks and --start), flag validation / usage contract, and
# — the point of this skill's Jira-only support — that a missing or
# unauthenticated gh degrades to a stated "skipped" note instead of failing.
#
# We isolate GitHub behaviour with a stub PATH: a fake `gh` (and `acli`) so the
# script's branches are exercised without touching the network.
#
#   bash skills/weekly-update/scripts/test-weekly-activity.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/weekly-activity.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/weekly-activity-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has() { grep -qF -- "$2" <<<"$1" || fail "$3 — got: $1"; }
hasnt() { grep -qF -- "$2" <<<"$1" && fail "$3 — unexpectedly got: $1"; return 0; }

echo "weekly-activity smoke: root=$ROOT"

# --- stub bin: fake acli (always returns [], logs argv) + controllable fake gh
BIN="$ROOT/bin"; mkdir -p "$BIN"
ARGLOG="$ROOT/acli-args.log"
cat >"$BIN/acli" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$ARGLOG"
echo '[]'
EOF
chmod +x "$BIN/acli"

# gh stub honours $GH_MODE: ok | unauth | (absent handled by not being on PATH)
make_gh() { # mode
  cat >"$BIN/gh" <<EOF
#!/usr/bin/env bash
mode="$1"
if [[ "\$1" == "auth" ]]; then
  [[ "\$mode" == "ok" ]] && exit 0 || exit 1
fi
# search prs …
echo '[]'
EOF
  chmod +x "$BIN/gh"
}

run() { PATH="$BIN:$PATH" bash "$SCRIPT" "$@"; }

# --- window math -------------------------------------------------------------
# Anchor everything to an explicit --start so the assertion is stable over time.
O="$(run fetch --start 2026-05-04 --no-github)"; echo "  → $(head -1 <<<"$O")"
has "$O" 'WINDOW_START=2026-05-04  (1 week)' "explicit --start is echoed verbatim"
pass "window: --start passes through unchanged"

# jira_search must cap explicitly — acli's default page truncates silently
grep -q -- '--limit 200' "$ARGLOG" || fail "jira search should pass --limit 200 (got: $(cat "$ARGLOG"))"
pass "jira: search passes --limit 200 to acli"

# default window is a Monday, WEEKS*7 days before this week's Monday
DEF_START="$(run fetch --no-github | sed -n 's/^WINDOW_START=\([0-9-]*\).*/\1/p')"
DOW="$(python3 -c "from datetime import date; print(date.fromisoformat('$DEF_START').weekday())")"
[[ "$DOW" == "0" ]] || fail "default window start should be a Monday (weekday 0), got weekday $DOW for $DEF_START"
pass "window: default start lands on a Monday"

TWO_START="$(run fetch --weeks 2 --no-github | sed -n 's/^WINDOW_START=\([0-9-]*\).*/\1/p')"
DELTA="$(python3 -c "from datetime import date; print((date.fromisoformat('$DEF_START')-date.fromisoformat('$TWO_START')).days)")"
[[ "$DELTA" == "7" ]] || fail "--weeks 2 should start exactly 7 days before --weeks 1, got $DELTA"
O="$(run fetch --weeks 2 --no-github)"; has "$O" '(2 weeks)' "biweekly window labelled plural"
pass "window: --weeks 2 is one week earlier and labelled '2 weeks'"

# --- GitHub-optional degradation (the Jira-only contract) --------------------
make_gh ok
O="$(run fetch --start 2026-05-04)"; echo "  → $(sed -n '2p' <<<"$O")"
has "$O" 'GITHUB: included' "authed gh → GitHub included"
has "$O" 'PRS MERGED in window:' "PR buckets present when included"
pass "github: authed gh → included"

make_gh unauth
O="$(run fetch --start 2026-05-04)"
has "$O" 'gh not authenticated' "unauth gh → skipped with remedy"
has "$O" '(github skipped — gh not authenticated' "PR buckets explain the skip"
hasnt "$O" 'GITHUB: included' "unauth gh is not reported as included"
pass "github: unauthenticated gh → skipped (run: gh auth login)"

# gh entirely absent: build a PATH with only our stub acli + system coreutils,
# no gh. Point at the stub dir for acli, then a clean PATH for the rest.
CLEAN="$ROOT/clean"; mkdir -p "$CLEAN"; cp "$BIN/acli" "$CLEAN/acli"
O="$(PATH="$CLEAN:/usr/bin:/bin" bash "$SCRIPT" fetch --start 2026-05-04)"
has "$O" 'gh not installed' "absent gh → Jira-only note"
has "$O" 'Jira-only mode' "absent gh names Jira-only mode"
pass "github: gh not installed → Jira-only mode (no failure)"

O="$(run fetch --start 2026-05-04 --no-github)"
has "$O" '--no-github' "explicit --no-github is honoured"
pass "github: --no-github → skipped on request"

# --- structure ---------------------------------------------------------------
O="$(run fetch --start 2026-05-04 --no-github)"
for s in "DONE (transitioned to done in window):" "IN FLIGHT" "PRS MERGED in window:" "PRS OPEN:"; do
  has "$O" "$s" "section present: $s"
done
has "$O" '(none)' "empty Jira buckets render (none)"
pass "structure: all four buckets emitted, empties render (none)"

# --- usage / error contract --------------------------------------------------
rc=0; run fetch --weeks 0 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "--weeks 0 should exit 2 (got $rc)"
pass "usage: --weeks 0 → exit 2"

rc=0; run fetch --weeks abc >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "--weeks abc should exit 2 (got $rc)"
pass "usage: non-numeric --weeks → exit 2"

rc=0; run fetch --start 2026/05/04 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "bad --start format should exit 2 (got $rc)"
pass "usage: malformed --start → exit 2"

rc=0; run fetch --bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "unknown flag should exit 2 (got $rc)"
pass "usage: unknown flag → exit 2"

rc=0; run bogus-cmd >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "unknown subcommand should exit 2 (got $rc)"
pass "usage: unknown subcommand → exit 2"

# acli absent → logical failure (exit 1), not a usage error
rc=0; PATH="/usr/bin:/bin" bash "$SCRIPT" fetch --start 2026-05-04 --no-github >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] || fail "missing acli should exit 1 (got $rc)"
pass "usage: missing acli → exit 1 (with remedy)"

O="$(run help)"; has "$O" 'weekly-activity.sh fetch' "help prints usage"
pass "help → prints usage (exit 0)"

echo ""
echo "✅ weekly-activity smoke PASSED ($PASS checks)"
