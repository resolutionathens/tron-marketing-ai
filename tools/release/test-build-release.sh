#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-test.XXXXXX")"
OUT_AGAIN="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-test-again.XXXXXX")"

cleanup() {
  trash "$OUT" "$OUT_AGAIN"
}
trap cleanup EXIT

node "$ROOT/tools/release/build-release.mjs" "$OUT" >/dev/null
node "$ROOT/tools/release/build-release.mjs" "$OUT_AGAIN" >/dev/null

archive_has() {
  local archive="$1"
  local expected="$2"
  local entry
  while IFS= read -r entry; do
    [ "$entry" = "$expected" ] && return 0
  done < <(tar -tzf "$archive")
  return 1
}

VERSION="$(node -p "require('$ROOT/.claude-plugin/plugin.json').version")"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
for HARNESS in claude codex; do
  ARCHIVE="$OUT/tron-$HARNESS-v$VERSION.tar.gz"
  test -s "$ARCHIVE"
  archive_has "$ARCHIVE" "tron-v$VERSION/skills/brainstorm/SKILL.md"
done

archive_has "$OUT/tron-claude-v$VERSION.tar.gz" "tron-v$VERSION/.claude-plugin/plugin.json"
archive_has "$OUT/tron-codex-v$VERSION.tar.gz" "tron-v$VERSION/.codex-plugin/plugin.json"
archive_has "$OUT/tron-codex-v$VERSION.tar.gz" "tron-v$VERSION/.agents/plugins/marketplace.json"

node - "$OUT/release-manifest.json" "$VERSION" "$COMMIT" <<'NODE'
const fs = require("fs");
const [path, version, commit] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(path, "utf8"));
if (release.version !== version || release.commit !== commit || release.packages.length !== 2) {
  throw new Error("release identity does not match the source commit");
}
for (const artifact of release.packages) {
  if (!artifact.sha256.match(/^[a-f0-9]{64}$/) || artifact.inventory.length === 0) {
    throw new Error(`invalid ${artifact.harness} integrity metadata`);
  }
}
NODE

(cd "$OUT" && shasum -a 256 -c SHA256SUMS)
for ARTIFACT in "tron-claude-v$VERSION.tar.gz" "tron-codex-v$VERSION.tar.gz" release-manifest.json SHA256SUMS; do
  cmp "$OUT/$ARTIFACT" "$OUT_AGAIN/$ARTIFACT"
done
printf 'PASS: deterministic dual-harness release artifacts and integrity manifest are valid.\n'
