#!/usr/bin/env bash
# Enforce the release boundary: ordinary PRs leave versions alone; an explicit
# release PR changes both manifests and adds one matching release record.
set -euo pipefail

ROOT="${TRON_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
BASE_REF="${1:-origin/master}"

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
grep -q '^Previous release: v' "$ROOT/$EXPECTED" || fail "$EXPECTED must name its previous release boundary"
printf 'PASS: explicit release boundary %s advances manifests from %s with %s.\n' "$VERSION" "$BASE_VERSION" "$EXPECTED"
