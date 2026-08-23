#!/usr/bin/env bash
# Enforce the release boundary: ordinary PRs leave versions alone; an explicit
# release PR changes both manifests and adds one matching release record.
set -euo pipefail

ROOT="${TRON_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
BASE_REF="${1:-origin/master}"
REQUIRE_HEAD_BOUNDARY="${2:-}"

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
RECORDS="$(printf '%s\n' "$CHANGED" | grep '^releases/v[0-9][0-9.]*\.md$' || true)"

if [ "$CLAUDE_CHANGED" != "$CODEX_CHANGED" ]; then
  fail 'release changes must update both plugin manifests together'
fi
if [ "$CLAUDE_CHANGED" = false ]; then
  [ -z "$RECORDS" ] || fail 'a release record requires a matching manifest version bump'
  printf 'PASS: ordinary change leaves plugin release manifests unchanged.\n'
  exit 0
fi

VERSION="$(node -p "require('$ROOT/$CLAUDE').version")"
BASE_VERSION="$(git -C "$ROOT" show "$BASE:$CLAUDE" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).version))')"
CODEX_VERSION="$(node -p "require('$ROOT/$CODEX').version")"
[ "$VERSION" = "$CODEX_VERSION" ] || fail 'Claude and Codex manifest versions must match'
node - "$BASE_VERSION" "$VERSION" <<'NODE'
const [before, after] = process.argv.slice(2).map(v => v.split('.').map(Number));
if (![before, after].every(v => v.length === 3 && v.every(Number.isInteger))) process.exit(1);
for (let i = 0; i < 3; i += 1) { if (after[i] > before[i]) process.exit(0); if (after[i] < before[i]) process.exit(1); }
process.exit(1);
NODE
[ "$?" = 0 ] || fail "release version must increase from $BASE_VERSION to $VERSION"
EXPECTED="releases/v$VERSION.md"
[ "$RECORDS" = "$EXPECTED" ] || fail "a release PR must add exactly $EXPECTED; ordinary version edits are not releases"
grep -qx "# Tron v$VERSION" "$ROOT/$EXPECTED" || fail "$EXPECTED must start with '# Tron v$VERSION'"
grep -q '^## Changes$' "$ROOT/$EXPECTED" || fail "$EXPECTED must include a '## Changes' section derived from commits since the prior release"
PREVIOUS="$(git -C "$ROOT" describe --tags --abbrev=0 "$BASE" 2>/dev/null || true)"
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
  grep -Fqx -- "- $subject" "$ROOT/$EXPECTED" || fail "$EXPECTED must summarize '$subject' from $PREVIOUS..HEAD"
done < <(git -C "$ROOT" rev-list --reverse "$PREVIOUS..HEAD")
if [ "$REQUIRE_HEAD_BOUNDARY" = --require-head-boundary ]; then
  HEAD_FILES="$(git -C "$ROOT" diff-tree --no-commit-id --name-only -r HEAD | sort)"
  EXPECTED_FILES="$(printf '%s\n%s\n%s\n' "$CLAUDE" "$CODEX" "$EXPECTED" | sort)"
  [ "$HEAD_FILES" = "$EXPECTED_FILES" ] || fail 'release publication must run at the dedicated boundary commit, not a later ordinary commit'
fi
printf 'PASS: explicit release boundary %s advances manifests from %s with %s.\n' "$VERSION" "$BASE_VERSION" "$EXPECTED"
