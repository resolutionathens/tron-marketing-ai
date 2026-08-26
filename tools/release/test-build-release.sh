#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-test.XXXXXX")"
OUT_AGAIN="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-test-again.XXXXXX")"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-fixture.XXXXXX")"
FIXTURE_OUT="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-fixture-out.XXXXXX")"
FIXTURE_OUT_AGAIN="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-fixture-out-again.XXXXXX")"
FIXTURE_OUT_DIRTY="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-fixture-out-dirty.XXXXXX")"

cleanup() {
  trash "$OUT" "$OUT_AGAIN" "$FIXTURE" "$FIXTURE_OUT" "$FIXTURE_OUT_AGAIN" "$FIXTURE_OUT_DIRTY"
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

archive_lacks() {
  ! archive_has "$1" "$2"
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

node - "$OUT/release-manifest.json" "$VERSION" "$COMMIT" "$ROOT/packages/package-map.json" <<'NODE'
const fs = require("fs");
const [path, version, commit, mapPath] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(path, "utf8"));
const map = JSON.parse(fs.readFileSync(mapPath, "utf8"));
// Two monolith harnesses plus every role package and repo bundle, per harness.
const expected = 2 + (Object.keys(map.packages).length + Object.keys(map.repos || {}).length) * 2;
if (release.version !== version || release.commit !== commit || release.packages.length !== expected) {
  throw new Error("release identity does not match the source commit");
}
for (const artifact of release.packages) {
  if (!artifact.sha256.match(/^[a-f0-9]{64}$/) || artifact.inventory.length === 0) {
    throw new Error(`invalid ${artifact.harness} integrity metadata`);
  }
}
for (const repo of Object.keys(map.repos || {})) {
  for (const harness of ["claude", "codex"]) {
    const filename = `tron-repo-${repo}-${harness}-v${version}.tar.gz`;
    if (!release.packages.some((artifact) => artifact.filename === filename)) {
      throw new Error(`release omitted the ${repo} repo bundle for ${harness}`);
    }
  }
}
NODE

for PACKAGE in core engineer designer content seo manager social video; do
  for HARNESS in claude codex; do
    ARCHIVE="$OUT/tron-$PACKAGE-$HARNESS-v$VERSION.tar.gz"
    test -s "$ARCHIVE"
    archive_has "$ARCHIVE" "skills/jira/SKILL.md"
  done
done
archive_has "$OUT/tron-engineer-claude-v$VERSION.tar.gz" "agents/a11y-scan-runner.md"
archive_has "$OUT/tron-content-codex-v$VERSION.tar.gz" "skills/md-to-pdf/template.tex"
for PACKAGE in core engineer designer content seo manager social video; do
  archive_has "$OUT/tron-$PACKAGE-claude-v$VERSION.tar.gz" ".claude-plugin/marketplace.json"
  archive_has "$OUT/tron-$PACKAGE-codex-v$VERSION.tar.gz" ".agents/plugins/marketplace.json"
done

# Repo bundles are release artifacts on the same footing as the role packages.
while IFS= read -r REPO; do
  for HARNESS in claude codex; do
    ARCHIVE="$OUT/tron-repo-$REPO-$HARNESS-v$VERSION.tar.gz"
    test -s "$ARCHIVE"
    archive_has "$ARCHIVE" "skills/jira/SKILL.md"
  done
  archive_has "$OUT/tron-repo-$REPO-claude-v$VERSION.tar.gz" ".claude-plugin/marketplace.json"
  archive_has "$OUT/tron-repo-$REPO-codex-v$VERSION.tar.gz" ".agents/plugins/marketplace.json"
done < <(node -p "Object.keys(require('$ROOT/packages/package-map.json').repos || {}).join('\n')")
for SKILL in guide-item news-item toolkit-item; do
  archive_lacks "$OUT/tron-claude-v$VERSION.tar.gz" "tron-v$VERSION/skills/$SKILL/SKILL.md"
  archive_lacks "$OUT/tron-codex-v$VERSION.tar.gz" "tron-v$VERSION/skills/$SKILL/SKILL.md"
  for HARNESS in claude codex; do
    archive_lacks "$OUT/tron-engineer-$HARNESS-v$VERSION.tar.gz" "skills/$SKILL/SKILL.md"
    archive_lacks "$OUT/tron-repo-marketing-pages-$HARNESS-v$VERSION.tar.gz" "skills/$SKILL/SKILL.md"
  done
done

(cd "$OUT" && shasum -a 256 -c SHA256SUMS)
for ARTIFACT in "$OUT"/*; do
  ARTIFACT="$(basename "$ARTIFACT")"
  cmp "$OUT/$ARTIFACT" "$OUT_AGAIN/$ARTIFACT"
done
printf 'PASS: deterministic dual-harness release artifacts and integrity manifest are valid.\n'

# Fixture-level: builds must be byte-deterministic against a snapshot of the current
# working tree (including uncommitted edits), without requiring a commit on this branch.
FIXTURE_PATHS=(.claude-plugin .codex-plugin .agents skills agents tools hooks packages README.md WORKER_CONTRACT.md)
for PATH_ENTRY in "${FIXTURE_PATHS[@]}"; do
  cp -R "$ROOT/$PATH_ENTRY" "$FIXTURE/$PATH_ENTRY"
done
git -C "$FIXTURE" init -q
git -C "$FIXTURE" add -A
GIT_AUTHOR_NAME="Tron Release Fixture" \
GIT_AUTHOR_EMAIL="release@facilitron.com" \
GIT_AUTHOR_DATE="1970-01-01T00:00:00Z" \
GIT_COMMITTER_NAME="Tron Release Fixture" \
GIT_COMMITTER_EMAIL="release@facilitron.com" \
GIT_COMMITTER_DATE="1970-01-01T00:00:00Z" \
git -C "$FIXTURE" commit -q -m "fixture: working tree snapshot"

node "$FIXTURE/tools/release/build-release.mjs" "$FIXTURE_OUT" >/dev/null
node "$FIXTURE/tools/release/build-release.mjs" "$FIXTURE_OUT_AGAIN" >/dev/null
for ARTIFACT in "$FIXTURE_OUT"/*; do
  ARTIFACT="$(basename "$ARTIFACT")"
  cmp "$FIXTURE_OUT/$ARTIFACT" "$FIXTURE_OUT_AGAIN/$ARTIFACT"
done

# The clean-tree guard must still block a build once the fixture itself goes dirty,
# and must fail for that specific reason (not some unrelated breakage).
echo "fixture edit" >> "$FIXTURE/README.md"
set +e
DIRTY_OUTPUT="$(node "$FIXTURE/tools/release/build-release.mjs" "$FIXTURE_OUT_DIRTY" 2>&1)"
DIRTY_STATUS=$?
set -e
if [ "$DIRTY_STATUS" -eq 0 ]; then
  printf 'FAIL: release build succeeded against a dirty tree.\n' >&2
  exit 1
fi
if ! printf '%s' "$DIRTY_OUTPUT" | grep -Fq 'release fixture requires committed tracked changes'; then
  printf 'FAIL: release build against a dirty tree failed for the wrong reason:\n%s\n' "$DIRTY_OUTPUT" >&2
  exit 1
fi
if ! printf '%s' "$DIRTY_OUTPUT" | grep -Fq 'rerun the release fixture after the atomic commit'; then
  printf 'FAIL: dirty-tree diagnostic did not explain the required verification sequence:\n%s\n' "$DIRTY_OUTPUT" >&2
  exit 1
fi
printf 'PASS: fixture-level release build is deterministic against uncommitted changes and the clean-tree guard still blocks a dirty tree.\n'

WORKFLOW="$ROOT/.github/workflows/release.yml"
if ! grep -Fq 'tools/release/validate-release-boundary.sh' "$WORKFLOW"; then
  printf 'FAIL: release workflow does not enforce an explicit release boundary.\n' >&2
  exit 1
fi
if ! grep -Fq -- '--notes-file "releases/$tag.md"' "$WORKFLOW"; then
  printf 'FAIL: release workflow does not publish the checked-in release summary.\n' >&2
  exit 1
fi
if ! grep -Fq 'gh attestation verify "$verify_dir/$filename" --repo "$GITHUB_REPOSITORY"' "$WORKFLOW"; then
  printf 'FAIL: release workflow does not verify downloaded artifact attestations.\n' >&2
  exit 1
fi
if grep -Fq 'gh release verify "$tag"' "$WORKFLOW"; then
  printf 'FAIL: release workflow verifies a tag instead of attested artifacts.\n' >&2
  exit 1
fi
printf 'PASS: release workflow verifies manifest-listed artifact attestations, not a tag.\n'
