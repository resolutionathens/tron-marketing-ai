#!/usr/bin/env bash
# Offline test for jira-link.sh (MD-3397). acli is PATH-stubbed and serves
# Jira responses recorded live on Nov 13 2026 (fixtures/link/, trimmed to the
# issuelinks fields the helper reads):
#
#   view-MD-3397-{before,after}.json, view-MD-3082-{before,after}.json
#     before/after `acli jira workitem link create --out MD-3397 --in MD-3082`
#     with --type Blocks (link 126433) and --type Relates (126434). acli printed
#     "MD-3397 Blocks MD-3082"; Jira stored "MD-3397 is blocked by MD-3082".
#   changelog-MD-3397.json, changelog-MD-3082.json
#     the same links in /rest/api/3/issue/<KEY>/changelog's plain words.
#   view-MD-3268.json
#     the issue where a correction deleted "is blocked by MD-3262" by mistake.
#
# States the recording never reached (after a delete or replace) are derived
# from those files in the test, never hand-typed.
#
#   bash tools/jira/test-jira-link.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLI="$HERE/jira-link.sh"
FIX="$HERE/fixtures/link"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 77; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-jira-link.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# acli stub: `view` serves $STUB/view-<KEY>-<state>.json (or view-<KEY>.json);
# `link create` / `link delete` log their args and advance the state.
cat > "$TMP/bin/acli" <<'STUB'
#!/usr/bin/env bash
set -u
state="$(cat "$STUB/state" 2>/dev/null || echo before)"
case "$1 $2" in
  "jira workitem")
    case "$3" in
      view)
        f="$STUB/view-$4-$state.json"; [ -f "$f" ] || f="$STUB/view-$4.json"
        [ -f "$f" ] || { echo "stub: no fixture for $4 in state $state" >&2; exit 1; }
        cat "$f" ;;
      link)
        shift 4
        echo "$*" >> "$STUB/calls-$(echo "$*" | awk '{print ($1 == "--id") ? "delete" : "create"}')"
        if [ "${1:-}" = --id ]; then
          cat "$STUB/on-delete" > "$STUB/state"
          echo "✓ Link has been successfully deleted ($2)"
        else
          cat "$STUB/on-create" > "$STUB/state"
          echo "✓ Link between issues has been successfully created (acli wording)"
        fi ;;
      *) echo "stub: unexpected $*" >&2; exit 1 ;;
    esac ;;
  *) echo "stub: unexpected $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/acli"
export PATH="$TMP/bin:$PATH"

# setup <initial-state> <on-create> <on-delete>: fresh stub dir with fixtures
setup() {
  export STUB="$TMP/stub.$PASS.$RANDOM"
  mkdir -p "$STUB"; cp "$FIX"/view-*.json "$STUB/"
  echo "$1" > "$STUB/state"; echo "$2" > "$STUB/on-create"; echo "$3" > "$STUB/on-delete"
}
calls() { cat "$STUB/calls-$1" 2>/dev/null || true; }
run() { set +e; OUT="$(bash "$CLI" "$@" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"; set -e; }

echo "jira-link:"

# --- recorded fixtures agree with Jira's changelog wording -------------------
for k in MD-3397 MD-3082; do
  shown="$(jq -r --arg k "$k" '.fields.issuelinks[]
    | "This work item \(if .outwardIssue then .type.outward else .type.inward end) \(.outwardIssue.key // .inwardIssue.key)"' \
    "$FIX/view-$k-after.json" | sort)"
  logged="$(jq -r '.values[].items[] | select(.toString) | .toString' "$FIX/changelog-$k.json" | sort)"
  [ "$shown" = "$logged" ] || fail "$k issuelinks reading disagrees with changelog: [$shown] vs [$logged]"
done
pass "issuelinks orientation reads the same as Jira's changelog (recorded)"

# --- Blocks, both directions -------------------------------------------------
setup before after unused
run create "MD-3082 blocks MD-3397"
[ "$RC" -eq 0 ] || fail "A blocks B: rc=$RC err=$ERR"
[ "$(calls create)" = "--out MD-3397 --in MD-3082 --type Blocks --yes" ] || fail "A blocks B flags: $(calls create)"
case "$OUT" in *"MD-3082 blocks MD-3397 (link 126433"*) ;; *) fail "A blocks B output: $OUT" ;; esac
pass "\"MD-3082 blocks MD-3397\" → --out MD-3397 --in MD-3082, verified as stored"

setup before after unused
run create "MD-3397 is blocked by MD-3082"
[ "$RC" -eq 0 ] || fail "A is blocked by B: rc=$RC err=$ERR"
[ "$(calls create)" = "--out MD-3397 --in MD-3082 --type Blocks --yes" ] || fail "is blocked by flags: $(calls create)"
case "$OUT" in *"MD-3397 is blocked by MD-3082 (link 126433"*) ;; *) fail "is blocked by output: $OUT" ;; esac
pass "\"MD-3397 is blocked by MD-3082\" → --out MD-3397 --in MD-3082, verified as stored"

setup before after unused
run create "md-3397  BLOCKS   md-3082"
[ "$(calls create)" = "--out MD-3082 --in MD-3397 --type Blocks --yes" ] || fail "case/space folding flags: $(calls create)"
# The recorded Jira state holds the opposite of what was asked → reversed.
[ "$RC" -eq 3 ] || fail "reversed store should exit 3, got $RC"
case "$ERR" in *REVERSED*"MD-3397 blocks MD-3082"*"MD-3397 is blocked by MD-3082 (link 126433"*) ;; *) fail "reversed message: $ERR" ;; esac
case "$ERR" in *"delete 126433 \"MD-3397 is blocked by MD-3082\""*) ;; *) fail "reversed fix hint: $ERR" ;; esac
pass "stored direction reversed → exit 3 naming both issues and the link id"

# --- Relates -----------------------------------------------------------------
setup before after unused
run create "MD-3397 relates to MD-3082"
[ "$RC" -eq 0 ] || fail "relates: rc=$RC err=$ERR"
[ "$(calls create)" = "--out MD-3397 --in MD-3082 --type Relates --yes" ] || fail "relates flags: $(calls create)"
case "$OUT" in *"MD-3397 relates to MD-3082 (link 126434, Relates)"*) ;; *) fail "relates output: $OUT" ;; esac
pass "\"MD-3397 relates to MD-3082\" verified (Blocks link on the same pair ignored)"

# --- acli says success, Jira holds nothing new -------------------------------
setup before before unused
run create "MD-3082 blocks MD-3397"
[ "$RC" -eq 1 ] || fail "no new link should exit 1, got $RC"
case "$ERR" in *"no new Blocks link between MD-3082 and MD-3397"*) ;; *) fail "no-link message: $ERR" ;; esac
pass "acli success with no stored link → exit 1"

# --- delete by id: the MD-3268 incident --------------------------------------
setup only unused deleted
jq '.fields.issuelinks |= map(select(.id != "126430"))' "$FIX/view-MD-3268.json" > "$STUB/view-MD-3268-deleted.json"
run delete 126432 "MD-3268 is blocked by MD-3396"
[ "$RC" -eq 4 ] || fail "wrong id should be refused with 4, got $RC"
[ -z "$(calls delete)" ] || fail "refused delete still called acli: $(calls delete)"
case "$ERR" in *"link 126432 is \"MD-3268 is blocked by MD-3262"*) ;; *) fail "refusal names actual link: $ERR" ;; esac
pass "delete refuses an id that is a different link on the same issue (no acli call)"

run delete 126430 "MD-3268 blocks MD-3396"
[ "$RC" -eq 4 ] && [ -z "$(calls delete)" ] || fail "reverse-worded delete should be refused: rc=$RC"
run delete 999 "MD-3268 is blocked by MD-3396"
[ "$RC" -eq 4 ] && [ -z "$(calls delete)" ] || fail "unknown id should be refused: rc=$RC"
pass "delete refuses a mis-stated direction and an id not on the issue"

run delete 126430 "MD-3268 is blocked by MD-3396"
[ "$RC" -eq 0 ] || fail "matching delete: rc=$RC err=$ERR"
[ "$(calls delete)" = "--id 126430 --yes" ] || fail "delete call: $(calls delete)"
pass "delete removes exactly the named link id and checks the others survived"

setup only unused deleted
jq '.fields.issuelinks |= map(select(.id == "125525"))' "$FIX/view-MD-3268.json" > "$STUB/view-MD-3268-deleted.json"
run delete 126430 "MD-3268 is blocked by MD-3396"
[ "$RC" -eq 1 ] || fail "collateral loss should exit 1, got $RC"
case "$ERR" in *"also removed other link(s) from MD-3268: 126432"*) ;; *) fail "collateral message: $ERR" ;; esac
pass "delete fails loudly if any other link disappeared"

# --- replace: correct a reversed link ----------------------------------------
setup after replaced deleted
jq '.fields.issuelinks |= map(select(.id != "126433"))' "$FIX/view-MD-3397-after.json" > "$STUB/view-MD-3397-deleted.json"
jq --slurpfile a "$FIX/view-MD-3397-after.json" \
  '.fields.issuelinks += [$a[0].fields.issuelinks[0] | .id = "126435" | del(.inwardIssue) | .outwardIssue = {key: "MD-3082"}]' \
  "$STUB/view-MD-3397-deleted.json" > "$STUB/view-MD-3397-replaced.json"
run replace 126434 "MD-3397 blocks MD-3268"
[ "$RC" -eq 4 ] && [ -z "$(calls delete)" ] || fail "replace across issues should be refused: rc=$RC"
run replace 126433 "MD-3397 blocks MD-3082"
[ "$RC" -eq 0 ] || fail "replace: rc=$RC err=$ERR"
[ "$(calls delete)" = "--id 126433 --yes" ] || fail "replace delete: $(calls delete)"
[ "$(calls create)" = "--out MD-3082 --in MD-3397 --type Blocks --yes" ] || fail "replace create: $(calls create)"
case "$OUT" in *"MD-3397 blocks MD-3082 (link 126435"*) ;; *) fail "replace output: $OUT" ;; esac
pass "replace deletes the named id only, recreates in the intended direction, verifies"

# --- show + usage ------------------------------------------------------------
setup only unused unused
run show MD-3268
[ "$RC" -eq 0 ] || fail "show rc=$RC"
printf '%s\n' "$OUT" | grep -qF "126432	MD-3268 is blocked by MD-3262	(Blocks)" || fail "show output: $OUT"
pass "show lists each link id in plain words"

for bad in "MD-1 depends on MD-2" "MD-1 blocks MD-1" "blocks MD-2"; do
  run create "$bad"; [ "$RC" -eq 2 ] || fail "bad statement '$bad' should exit 2, got $RC"
done
run delete abc "MD-1 blocks MD-2"; [ "$RC" -eq 2 ] || fail "non-numeric id should exit 2"
run frobnicate; [ "$RC" -eq 2 ] || fail "unknown subcommand should exit 2"
pass "unreadable statements, same-key links, bad ids → exit 2"

echo "jira-link: $PASS checks passed"
