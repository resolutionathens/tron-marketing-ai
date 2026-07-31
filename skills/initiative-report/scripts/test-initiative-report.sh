#!/usr/bin/env bash
# Smoke for initiative-report.sh. Real Jira needs auth and isn't touched: acli
# is stubbed via a PATH shim (same approach as test-weekly-activity.sh) that
# dispatches on the JQL it receives, modelling a 3-level tree:
#
#   MCR-355 → {MCR-401, MCR-402} → {MCR-501} → (none)
#
# Asserted: the BFS reaches ALL levels (not just direct children — the whole
# point vs `parent = X`), the csv/JQL assembly is clean (no stray commas), the
# hierarchy is walked with `parent in (…)` (never "Epic Link"), the counts
# digest, and the flag/usage contract.
#
#   bash skills/initiative-report/scripts/test-initiative-report.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/initiative-report.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/initiative-report-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT

echo "initiative-report smoke: root=$ROOT"

# --- stub bin: fake acli dispatching on the JQL, logging its argv --------------
BIN="$ROOT/bin"; mkdir -p "$BIN"
ARGLOG="$ROOT/acli-args.log"
cat >"$BIN/acli" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$ARGLOG"
case "\$*" in
  *"workitem view MCR-355"*)
    echo '{"key":"MCR-355","fields":{"summary":"ADA Compliance","status":{"name":"In Progress"},"issuetype":{"name":"Initiative"}}}' ;;
  *"parent in (MCR-355)"*)
    echo '[{"key":"MCR-401"},{"key":"MCR-402"}]' ;;
  *"parent in (MCR-401,MCR-402)"*)
    echo '[{"key":"MCR-501"}]' ;;
  *"parent in (MCR-501)"*)
    echo '[]' ;;
  *"key in (MCR-401,MCR-402,MCR-501)"*)
    echo '[{"key":"MCR-401","fields":{"summary":"Audit pages","status":{"name":"Done"},"assignee":{"displayName":"Alice"},"duedate":null,"updated":"2026-06-20T10:00:00.000-0700"}},
           {"key":"MCR-402","fields":{"summary":"Fix nav contrast","status":{"name":"In Progress"},"assignee":{"displayName":"Bob"},"duedate":"2026-07-10","updated":"2026-06-30T10:00:00.000-0700"}},
           {"key":"MCR-501","fields":{"summary":"Alt text pass","status":{"name":"To Do"},"assignee":null,"duedate":null,"updated":"2026-06-01T10:00:00.000-0700"}}]' ;;
  *) echo "acli-stub: unexpected call: \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$BIN/acli"

run() { PATH="$BIN:$PATH" bash "$SCRIPT" "$@"; }

# --- full-depth BFS + digest -----------------------------------------------------
O="$(run fetch MCR-355 2>/dev/null)"
jq -e . >/dev/null <<<"$O" || fail "output is not valid JSON"
[[ "$(jq -r '.parent.key' <<<"$O")" == "MCR-355" ]] || fail "parent should be MCR-355"
pass "fetch: valid JSON with the parent resolved"
[[ ! -e "$ROOT/tmp/manager/MCR-355-descendants.json" ]] || fail "raw detail must not be retained without --keep-dir"
KEEP="$ROOT/retained"; run fetch MCR-355 --keep-dir "$KEEP" >/dev/null 2>&1
[[ -s "$KEEP/MCR-355-descendants.json" ]] || fail "--keep-dir should retain explicit detail"
pass "cleanup: raw detail discarded by default and retained only with --keep-dir"

K="$(jq -c '[.descendants[].key] | sort' <<<"$O")"
[[ "$K" == '["MCR-401","MCR-402","MCR-501"]' ]] \
  || fail "BFS should reach grandchildren too (full depth), got $K"
pass "bfs: all 3 descendants across 2 levels collected (not just direct children)"

C="$(jq -c '.counts' <<<"$O")"
[[ "$C" == '{"total":3,"done":1,"in_progress":1,"to_do":1}' ]] \
  || fail "counts should be total 3 / done 1 / in progress 1 / to do 1 — got $C"
pass "digest: counts computed over the FULL descendant set"

[[ "$(jq -r '.truncated' <<<"$O")" == "false" ]] || fail "small tree → truncated:false"
pass "digest: truncated:false when no level hits the limit"

# --- JQL assembly contract --------------------------------------------------------
grep -q 'parent in (MCR-401,MCR-402)' "$ARGLOG" \
  || fail "level-2 JQL should be a clean csv list (no stray commas/spaces)"
grep -qi 'epic link' "$ARGLOG" && fail "must never query Epic Link — MCR hierarchy is parent-based"
grep -q -- '--limit 200' "$ARGLOG" || fail "per-level search should pass --limit 200 by default"
pass "jql: parent-based csv frontier queries, --limit 200, no Epic Link"

# truncation: a level returning exactly --limit rows flags truncated
: > "$ARGLOG"
O="$(run fetch MCR-355 --limit 2 2>/dev/null)"
[[ "$(jq -r '.truncated' <<<"$O")" == "true" ]] \
  || fail "level returning exactly --limit rows should set truncated:true"
grep -q -- '--limit 2 ' "$ARGLOG" || fail "--limit should flow through to the search"
pass "jql: level hitting --limit sets truncated:true"

# --- usage / error contract --------------------------------------------------------
for bad in "" "mcr-355" "MCR-355 MCR-356" "--limit 0" "--bogus"; do
  rc=0; run fetch $bad >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 2 ]] || fail "'fetch $bad' should exit 2 (got $rc)"
done
pass "usage: missing/bad key, two keys, bad flags → exit 2"

rc=0; PATH="/usr/bin:/bin" bash "$SCRIPT" fetch MCR-355 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] || fail "missing acli should exit 1 (got $rc)"
pass "usage: missing acli → exit 1 (with remedy)"

O="$(run help)"; grep -q 'initiative-report.sh fetch' <<<"$O" || fail "help should print usage"
pass "help → prints usage (exit 0)"

echo ""
echo "✅ initiative-report smoke PASSED ($PASS checks)"
