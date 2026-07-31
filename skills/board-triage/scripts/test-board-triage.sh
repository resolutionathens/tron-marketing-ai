#!/usr/bin/env bash
# Smoke for board-triage.sh. Real Jira needs auth and isn't touched: acli is
# stubbed via a PATH shim (same approach as test-weekly-activity.sh) serving a
# fixed candidate set + per-key view fixtures, so what IS asserted is the
# deterministic part — flag validation, the search JQL/--limit contract, and
# the bucket math (unassigned / stale / overdue / missing metadata / blocked /
# WIP load) against a known board snapshot with a pinned --now.
#
#   bash skills/board-triage/scripts/test-board-triage.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/board-triage.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/board-triage-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT

echo "board-triage smoke: root=$ROOT"

# --- fixtures: 5-item board snapshot ------------------------------------------
FIX="$ROOT/fix"; mkdir -p "$FIX"
cat >"$FIX/search.json" <<'EOF'
[{"key":"MCR-1"},{"key":"MCR-2"},{"key":"MCR-3"},{"key":"MCR-4"},{"key":"MCR-5"}]
EOF

mkfix() { # key json
  printf '%s\n' "$2" > "$FIX/$1.json"
}
# MCR-1: To Do, unassigned, fully-specced → unassigned only
mkfix MCR-1 '{"key":"MCR-1","fields":{"summary":"Logo filler pages","issuetype":{"name":"Task"},"status":{"name":"To Do"},"assignee":null,"priority":{"name":"High"},"duedate":"2026-07-20","updated":"2026-06-30T10:00:00.000-0700","labels":[],"parent":{"key":"MCR-100","fields":{"summary":"Events & Conferences"}}}}'
# MCR-2: In Progress, Alice, updated long ago, no duedate → stale + missing metadata
mkfix MCR-2 '{"key":"MCR-2","fields":{"summary":"Event projections","issuetype":{"name":"Task"},"status":{"name":"In Progress"},"assignee":{"displayName":"Alice"},"priority":{"name":"Medium"},"duedate":null,"updated":"2026-06-01T10:00:00.000-0700","labels":[],"parent":{"key":"MCR-100","fields":{"summary":"Events & Conferences"}}}}'
# MCR-3: To Do, Bob, overdue, no priority → stale (overdue) + blocked (due) + missing metadata
mkfix MCR-3 '{"key":"MCR-3","fields":{"summary":"Swag order","issuetype":{"name":"Task"},"status":{"name":"To Do"},"assignee":{"displayName":"Bob"},"priority":null,"duedate":"2026-06-20","updated":"2026-06-29T10:00:00.000-0700","labels":[],"parent":{"key":"MCR-100","fields":{"summary":"Events & Conferences"}}}}'
# MCR-4: In Progress, Alice, fresh but labelled blocked → blocked; Alice WIP = 2
mkfix MCR-4 '{"key":"MCR-4","fields":{"summary":"Banner print","issuetype":{"name":"Task"},"status":{"name":"In Progress"},"assignee":{"displayName":"Alice"},"priority":{"name":"High"},"duedate":"2026-08-01","updated":"2026-06-28T10:00:00.000-0700","labels":["blocked-on-vendor"],"parent":{"key":"MCR-100","fields":{"summary":"Events & Conferences"}}}}'
# MCR-5: In Review, unassigned, old — NOT actionable, so no unassigned/stale hit
mkfix MCR-5 '{"key":"MCR-5","fields":{"summary":"Copy review","issuetype":{"name":"Task"},"status":{"name":"In Review"},"assignee":null,"priority":{"name":"Low"},"duedate":null,"updated":"2026-06-01T10:00:00.000-0700","labels":[],"parent":null}}'

# --- stub bin: fake acli serving the fixtures, logging its argv ---------------
BIN="$ROOT/bin"; mkdir -p "$BIN"
ARGLOG="$ROOT/acli-args.log"
cat >"$BIN/acli" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$ARGLOG"
case "\$*" in
  *"workitem search"*) cat "$FIX/search.json" ;;
  *"workitem view"*)   cat "$FIX/\$4.json" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN/acli"

run() { PATH="$BIN:$PATH" bash "$SCRIPT" "$@"; }
NOWFLAGS=(--now 2026-07-01)   # stale cutoff 2026-06-17, due-soon 2026-07-08

# --- bucket math ---------------------------------------------------------------
O="$(run fetch "${NOWFLAGS[@]}" 2>/dev/null)"
jq -e . >/dev/null <<<"$O" || fail "output is not valid JSON"
[[ "$(jq -r '.total' <<<"$O")" == "5" ]] || fail "total should be 5"
[[ "$(jq -r '.truncated' <<<"$O")" == "false" ]] || fail "5 < limit → truncated:false"
pass "fetch: valid JSON, total=5, not truncated"
[[ ! -e "$ROOT/tmp/manager/triage-enriched.json" ]] || fail "raw snapshot must not be retained without --keep-dir"
KEEP="$ROOT/retained"; run fetch "${NOWFLAGS[@]}" --keep-dir "$KEEP" >/dev/null 2>&1
[[ -s "$KEEP/triage-keys.txt" && -s "$KEEP/triage-enriched.json" ]] || fail "--keep-dir should retain explicit snapshots"
pass "cleanup: snapshots discarded by default and retained only with --keep-dir"

[[ "$(jq -c '[.unassigned[].key]' <<<"$O")" == '["MCR-1"]' ]] \
  || fail "unassigned should be exactly MCR-1 (MCR-5 is not actionable) — got $(jq -c '[.unassigned[].key]' <<<"$O")"
pass "lens: unassigned = actionable + no assignee only"

S="$(jq -c '[.stale[].key] | sort' <<<"$O")"
[[ "$S" == '["MCR-2","MCR-3"]' ]] || fail "stale should be MCR-2 (old In Progress) + MCR-3 (overdue To Do) — got $S"
pass "lens: stale = old In Progress + overdue To Do"

M="$(jq -c '[.missing_metadata[].key] | sort' <<<"$O")"
grep -q 'MCR-2' <<<"$M" && grep -q 'MCR-3' <<<"$M" || fail "missing_metadata should include MCR-2 (no duedate) and MCR-3 (no priority) — got $M"
grep -q 'MCR-1' <<<"$M" && fail "MCR-1 is fully specced — should not be in missing_metadata"
pass "lens: missing metadata flags absent priority/duedate, not full items"

B="$(jq -c '[.blocked[].key] | sort' <<<"$O")"
[[ "$B" == '["MCR-3","MCR-4"]' ]] || fail "blocked should be MCR-3 (due soon) + MCR-4 (blocked label) — got $B"
pass "lens: blocked = blocked-label or due within 7 days"

W="$(jq -r '.wip_load[] | select(.assignee=="Alice") | .in_progress' <<<"$O")"
[[ "$W" == "2" ]] || fail "Alice should carry 2 In Progress — got '$W'"
pass "lens: WIP load counts In Progress per assignee"

# --- search contract -----------------------------------------------------------
grep -q -- '--limit 500' "$ARGLOG" || fail "search should pass --limit 500 by default"
grep -q 'project = MCR AND statusCategory != Done' "$ARGLOG" || fail "search JQL should scope to non-Done MCR"
pass "search: default --limit 500 + non-Done JQL passed to acli"

: > "$ARGLOG"
O="$(run fetch "${NOWFLAGS[@]}" --project ABC --limit 5 2>/dev/null)"
grep -q 'project = ABC' "$ARGLOG" || fail "--project should flow into the JQL"
[[ "$(jq -r '.truncated' <<<"$O")" == "true" ]] || fail "count == --limit should set truncated:true"
pass "search: --project honoured; hitting --limit sets truncated:true"

# --- usage / error contract ----------------------------------------------------
for bad in "--limit 0" "--limit abc" "--stale-days x" "--now 2026/07/01" "--project mcr" "--bogus"; do
  rc=0; run fetch $bad >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 2 ]] || fail "'$bad' should exit 2 (got $rc)"
done
pass "usage: bad flags → exit 2"

rc=0; run bogus-cmd >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "unknown subcommand should exit 2 (got $rc)"
pass "usage: unknown subcommand → exit 2"

rc=0; PATH="/usr/bin:/bin" bash "$SCRIPT" fetch >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] || fail "missing acli should exit 1 (got $rc)"
pass "usage: missing acli → exit 1 (with remedy)"

O="$(run help)"; grep -q 'board-triage.sh fetch' <<<"$O" || fail "help should print usage"
pass "help → prints usage (exit 0)"

echo ""
echo "✅ board-triage smoke PASSED ($PASS checks)"
