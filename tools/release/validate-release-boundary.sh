#!/usr/bin/env bash
# Enforce the release boundary.
#
# Three shapes, decided by the diff alone — no labels, no titles, nothing a human
# has to remember or an agent can assert about itself:
#
#   ordinary  touches neither manifest and adds no release record. Several of these
#             land per release and none of them change a version.
#   release   touches exactly both manifests plus exactly one new releases/vX.Y.Z.md.
#   mixed     anything else. Rejected — see --require-isolated-release.
#
# A mixed commit is why this exists (MD-2913). The publish job can only run at a
# commit whose files are exactly the two manifests and its own record, so bundling a
# bump into a feature PR does not merely break convention: it makes that version
# permanently unpublishable, and — because publication validates the range since the
# last TAG rather than the last merge — it also reds every later unrelated merge until
# someone cuts a clean release.
set -euo pipefail

ROOT="${TRON_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
BASE_REF="${1:-origin/master}"
shift || true
REQUIRE_HEAD_BOUNDARY=false
REQUIRE_ISOLATED_RELEASE=false
for arg in "$@"; do
  case "$arg" in
    --require-head-boundary) REQUIRE_HEAD_BOUNDARY=true ;;
    --require-isolated-release) REQUIRE_ISOLATED_RELEASE=true ;;
    "") ;;
    *) printf 'FAIL: unknown option %s\n' "$arg" >&2; exit 1 ;;
  esac
done

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
if ! git -C "$ROOT" rev-parse --verify -q "$BASE_REF" >/dev/null; then
  BASE_REF="$(git -C "$ROOT" rev-parse HEAD^)"
fi
BASE="$(git -C "$ROOT" merge-base HEAD "$BASE_REF")"
CHANGED="$(git -C "$ROOT" diff --name-only "$BASE...HEAD")"
has() { printf '%s\n' "$CHANGED" | grep -qx "$1"; }
CLAUDE=.claude-plugin/plugin.json
CODEX=.codex-plugin/plugin.json
CLAUDE_CHANGED=false; CODEX_CHANGED=false
has "$CLAUDE" && CLAUDE_CHANGED=true
has "$CODEX" && CODEX_CHANGED=true

# A record still present in HEAD was added or edited; one absent from HEAD was removed.
# The two are not the same act, so they are not judged by the same rule.
RECORDS=""; RECORDS_REMOVED=""
while IFS= read -r record; do
  [ -n "$record" ] || continue
  if git -C "$ROOT" cat-file -e "HEAD:$record" 2>/dev/null; then
    RECORDS="${RECORDS:+$RECORDS
}$record"
  else
    RECORDS_REMOVED="${RECORDS_REMOVED:+$RECORDS_REMOVED
}$record"
  fi
done <<EOF
$(printf '%s\n' "$CHANGED" | grep '^releases/v[0-9][0-9.]*\.md$' || true)
EOF

# Removing a record for a version that was never tagged is cleanup, not history
# rewriting: it documents a release that does not exist. Removing a PUBLISHED one
# would erase the record of something people actually installed.
while IFS= read -r record; do
  [ -n "$record" ] || continue
  removed_tag="$(printf '%s' "$record" | sed 's|^releases/\(v[0-9][0-9.]*\)\.md$|\1|')"
  if git -C "$ROOT" rev-parse -q --verify "refs/tags/$removed_tag" >/dev/null 2>&1; then
    fail "$record documents published release $removed_tag and must not be deleted"
  fi
done <<EOF
$RECORDS_REMOVED
EOF

if [ "$CLAUDE_CHANGED" != "$CODEX_CHANGED" ]; then
  fail 'release changes must update both plugin manifests together'
fi
if [ "$CLAUDE_CHANGED" = false ]; then
  [ -z "$RECORDS" ] || fail 'a release record requires a matching manifest version bump'
  if [ -n "$RECORDS_REMOVED" ]; then
    printf 'PASS: ordinary change leaves plugin release manifests unchanged; removed unpublished record(s): %s\n' "$(printf '%s' "$RECORDS_REMOVED" | tr '\n' ' ')"
  else
    printf 'PASS: ordinary change leaves plugin release manifests unchanged.\n'
  fi
  exit 0
fi

VERSION="$(node -p "require('$ROOT/$CLAUDE').version")"
BASE_VERSION="$(git -C "$ROOT" show "$BASE:$CLAUDE" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).version))')"
CODEX_VERSION="$(node -p "require('$ROOT/$CODEX').version")"
[ "$VERSION" = "$CODEX_VERSION" ] || fail 'Claude and Codex manifest versions must match'
PUBLISHED="$(git -C "$ROOT" describe --tags --abbrev=0 "$BASE" 2>/dev/null || true)"

# Restoring master to the last PUBLISHED version is the documented recovery from a
# bundled bump (MD-2913): the manifests advertise a version that was never tagged and
# can no longer be cut, so they are put back where publication actually stopped. It is
# not a release — it adds no record and lands on a version that already shipped — so it
# is neither held to the increase rule nor to the isolated-release shape.
if [ -n "$PUBLISHED" ] && [ "v$VERSION" = "$PUBLISHED" ] && [ -z "$RECORDS" ]; then
  printf 'PASS: restores the manifests to the last published release %s.\n' "$PUBLISHED"
  exit 0
fi

# `set -e` aborts on a failing command substitution, so testing $? after a bare
# heredoc call meant this script died before it could say WHY (pre-existing bug).
if ! node - "$BASE_VERSION" "$VERSION" <<'NODE'
const [before, after] = process.argv.slice(2).map(v => v.split('.').map(Number));
if (![before, after].every(v => v.length === 3 && v.every(Number.isInteger))) process.exit(1);
for (let i = 0; i < 3; i += 1) { if (after[i] > before[i]) process.exit(0); if (after[i] < before[i]) process.exit(1); }
process.exit(1);
NODE
then
  fail "release version must increase from $BASE_VERSION to $VERSION (to undo a bundled bump, restore the manifests to $PUBLISHED instead)"
fi
EXPECTED="releases/v$VERSION.md"
[ "$RECORDS" = "$EXPECTED" ] || fail "a release PR must add exactly $EXPECTED; ordinary version edits are not releases"

# The shape gate. Checked against the PR's whole diff rather than its individual
# commits, because the squash-merge lands that whole diff as ONE commit — and that
# commit is what publication is later required to run at. A branch that keeps its
# bump in a tidy separate commit still squashes into a mixed one.
if [ "$REQUIRE_ISOLATED_RELEASE" = true ]; then
  EXTRA="$(printf '%s\n' "$CHANGED" | grep -vxF "$CLAUDE" | grep -vxF "$CODEX" | grep -vxF "$EXPECTED" || true)"
  if [ -n "$EXTRA" ]; then
    printf 'FAIL: a release changes ONLY %s, %s and %s. This PR also changes:\n' "$CLAUDE" "$CODEX" "$EXPECTED" >&2
    while IFS= read -r extra_path; do
      [ -n "$extra_path" ] || continue
      printf '  %s\n' "$extra_path" >&2
    done <<EOF
$EXTRA
EOF
    fail 'move the version bump and release record into their own release PR; ordinary work never touches them'
  fi
fi

grep -qx "# Tron v$VERSION" "$ROOT/$EXPECTED" || fail "$EXPECTED must start with '# Tron v$VERSION'"
grep -q '^## Changes$' "$ROOT/$EXPECTED" || fail "$EXPECTED must include a '## Changes' section derived from commits since the prior release"
PREVIOUS="$PUBLISHED"
[ -n "$PREVIOUS" ] || fail 'release validation requires a prior immutable release tag'
grep -qx "Previous release: $PREVIOUS" "$ROOT/$EXPECTED" || fail "$EXPECTED must name the actual prior release boundary ($PREVIOUS)"
while IFS= read -r commit; do
  # GitHub Actions checks out a synthetic merge commit for pull requests. Its
  # generated subject changes whenever the PR head changes, so it is not a
  # release-note-worthy change.
  parent_count="$(git -C "$ROOT" rev-list --parents -n 1 "$commit" | awk '{print NF - 1}')"
  [ "$parent_count" -le 1 ] || continue
  files="$(git -C "$ROOT" diff-tree --no-commit-id --name-only -r "$commit")"
  if ! printf '%s\n' "$files" | grep -qvE '^(\.claude-plugin/plugin\.json|\.codex-plugin/plugin\.json|releases/v[0-9.]+\.md)$'; then continue; fi
  subject="$(git -C "$ROOT" log -1 --format=%s "$commit")"
  grep -Fqx -- "- $subject" "$ROOT/$EXPECTED" || fail "$EXPECTED must summarize '$subject' from $PREVIOUS..HEAD. Generate the list with tools/release/release-notes.sh rather than writing it by hand — a subject is only final once the PR is squashed"
done < <(git -C "$ROOT" rev-list --reverse "$PREVIOUS..HEAD")
if [ "$REQUIRE_HEAD_BOUNDARY" = true ]; then
  HEAD_FILES="$(git -C "$ROOT" diff-tree --no-commit-id --name-only -r HEAD | sort)"
  EXPECTED_FILES="$(printf '%s\n%s\n%s\n' "$CLAUDE" "$CODEX" "$EXPECTED" | sort)"
  [ "$HEAD_FILES" = "$EXPECTED_FILES" ] || fail 'release publication must run at the dedicated boundary commit, not a later ordinary commit'
fi
printf 'PASS: explicit release boundary %s advances manifests from %s with %s.\n' "$VERSION" "$BASE_VERSION" "$EXPECTED"
