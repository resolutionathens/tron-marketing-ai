#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT/tools/release/validate-release-boundary.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-boundary.XXXXXX")"
SHALLOW="$(mktemp -d "${TMPDIR:-/tmp}/tron-release-boundary-shallow.XXXXXX")"
cleanup() { trash "$WORK"; }
cleanup() { trash "$WORK" "$SHALLOW"; }
trap cleanup EXIT

git -C "$WORK" init -q
git -C "$WORK" config user.name test
git -C "$WORK" config user.email test@example.invalid
mkdir -p "$WORK/.claude-plugin" "$WORK/.codex-plugin" "$WORK/releases"
manifest() { printf '{"name":"tron","version":"%s"}\n' "$1"; }
manifest 1.0.0 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
printf 'base\n' > "$WORK/README.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm base && git -C "$WORK" branch -M master
git -C "$WORK" tag v1.0.0
git -C "$WORK" checkout -qb ordinary
printf 'ordinary\n' >> "$WORK/README.md"; git -C "$WORK" add . && git -C "$WORK" commit -qm ordinary
TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master >/dev/null
git clone -q --depth 1 --branch ordinary "file://$WORK" "$SHALLOW"
git -C "$SHALLOW" fetch -q --unshallow origin
TRON_PLUGIN_ROOT="$SHALLOW" bash "$CHECK" origin/master >/dev/null
manifest 1.0.1 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
git -C "$WORK" add . && git -C "$WORK" commit -qm bad-version
if TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master >/dev/null 2>&1; then echo 'FAIL: ordinary manifest bump passed without release record' >&2; exit 1; fi
printf '# Tron v1.0.1\n\nPrevious release: v0.0.0\n\n## Changes\n\n- ordinary\n' > "$WORK/releases/v1.0.1.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm release
if TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master >/dev/null 2>&1; then echo 'FAIL: wrong prior release boundary passed' >&2; exit 1; fi
printf '# Tron v1.0.1\n\nPrevious release: v1.0.0\n\n## Changes\n\n- unrelated\n' > "$WORK/releases/v1.0.1.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm incomplete-summary
if TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master >/dev/null 2>&1; then echo 'FAIL: incomplete change summary passed' >&2; exit 1; fi
printf '# Tron v1.0.1\n\nPrevious release: v1.0.0\n\n## Changes\n\n- ordinary\n' > "$WORK/releases/v1.0.1.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm complete-summary
TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master >/dev/null
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb merge-release
printf 'merge ordinary\n' >> "$WORK/README.md"
manifest 1.0.1 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
mkdir -p "$WORK/releases"
printf '# Tron v1.0.1\n\nPrevious release: v1.0.0\n\n## Changes\n\n- merge ordinary\n' > "$WORK/releases/v1.0.1.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm merge-release
git -C "$WORK" checkout -qb merge-base master
git -C "$WORK" merge --no-ff merge-release -m 'Merge synthetic pull request'
TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" merge-base >/dev/null
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb retry-boundary
printf 'retry ordinary\n' >> "$WORK/README.md"
git -C "$WORK" add README.md && git -C "$WORK" commit -qm retry-ordinary
manifest 1.0.1 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
mkdir -p "$WORK/releases"
printf '# Tron v1.0.1\n\nPrevious release: v1.0.0\n\n## Changes\n\n- retry-ordinary\n' > "$WORK/releases/v1.0.1.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm release-boundary
TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master --require-head-boundary >/dev/null
printf 'later ordinary\n' >> "$WORK/README.md"
git -C "$WORK" add README.md && git -C "$WORK" commit -qm later-ordinary
if TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master --require-head-boundary >/dev/null 2>&1; then
  echo 'FAIL: manual retry accepted an ordinary commit after the release boundary' >&2
  exit 1
fi
if ! grep -A 5 'uses: actions/checkout@v4' "$ROOT/.github/workflows/ci.yml" | grep -q 'fetch-depth: 0'; then
  echo 'FAIL: CI must fetch release-boundary history before validating a PR' >&2
  exit 1
fi
# ── The shape gate (MD-2913) ──────────────────────────────────────────────────
# Three shapes, decided by the diff alone: ordinary touches none of the three files,
# a release touches exactly them, and anything else is mixed and must be rejected
# BEFORE merge — the squash lands the whole diff as one commit, and that commit is
# what publication is later required to run at.
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb mixed-release
printf 'feature\n' >> "$WORK/README.md"
manifest 1.0.1 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
mkdir -p "$WORK/releases"
printf '# Tron v1.0.1\n\nPrevious release: v1.0.0\n\n## Changes\n\n- mixed\n' > "$WORK/releases/v1.0.1.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm mixed
if TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master --require-isolated-release >/dev/null 2>&1; then
  echo 'FAIL: a bundled version bump passed the isolated-release gate' >&2
  exit 1
fi
MIXED_OUTPUT="$(TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master --require-isolated-release 2>&1 || true)"
case "$MIXED_OUTPUT" in
  *README.md*) ;;
  *) echo 'FAIL: the isolated-release rejection must name the offending files' >&2; exit 1 ;;
esac

# The same change, split correctly: the feature PR carries no version at all.
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb split-feature
printf 'feature\n' >> "$WORK/README.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm split-feature
TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master --require-isolated-release >/dev/null
# ...and the release PR carries nothing but the version and its record.
git -C "$WORK" checkout -qb split-release
manifest 1.0.1 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
mkdir -p "$WORK/releases"
printf '# Tron v1.0.1\n\nPrevious release: v1.0.0\n\n## Changes\n\n- split-feature\n' > "$WORK/releases/v1.0.1.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm 'release 1.0.1'
TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" split-feature --require-isolated-release >/dev/null

# ── Removing an unpublished record (MD-2913) ─────────────────────────────────
# The recovery path from a bundled bump. A record for a version that was never tagged
# documents a release that does not exist, so an ordinary PR may delete it; deleting a
# PUBLISHED one would erase the record of something people installed.
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb drop-unpublished
mkdir -p "$WORK/releases"
printf '# Tron v9.9.9\n\nPrevious release: v1.0.0\n\n## Changes\n\n- stranded\n' > "$WORK/releases/v9.9.9.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm strand
git -C "$WORK" rm -q "$WORK/releases/v9.9.9.md"
git -C "$WORK" commit -qm 'drop unpublished record'
TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master >/dev/null
# Deleting a PUBLISHED record is refused. The record must already exist on the BASE,
# or the net diff would show nothing to delete, so master carries it as fixture setup.
git -C "$WORK" checkout -q master
mkdir -p "$WORK/releases"
printf '# Tron v1.0.0\n\nPrevious release: v0.9.0\n\n## Changes\n\n- base\n' > "$WORK/releases/v1.0.0.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm 'fixture: published record'
git -C "$WORK" checkout -qb drop-published
git -C "$WORK" rm -q releases/v1.0.0.md
git -C "$WORK" commit -qm 'drop published record'
if TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" master >/dev/null 2>&1; then
  echo 'FAIL: deleting a published release record was allowed' >&2
  exit 1
fi

# ── The publish workflow no-ops off-boundary (MD-2913) ────────────────────────
if ! grep -q 'is-release-boundary.sh' "$ROOT/.github/workflows/release.yml"; then
  echo 'FAIL: the publish workflow must detect the boundary before doing any release work' >&2
  exit 1
fi
for step in 'Validate package source' 'Attest build provenance' 'Publish complete release'; do
  grep -A 1 "name: $step" "$ROOT/.github/workflows/release.yml" | grep -q "steps.boundary.outputs.is_boundary == 'true'" || {
    echo "FAIL: release step '$step' must be gated on the boundary check" >&2
    exit 1
  }
done
ruby -ryaml -e '
  wf = YAML.load_file(ARGV[0])
  ok = wf["jobs"].any? do |_name, job|
    cond = job["if"].to_s
    next false if cond.include?("!= \x27pull_request\x27")
    (job["steps"] || []).any? { |st| st["run"].to_s.include?("validate-release-boundary.sh") && st["run"].to_s.include?("--require-isolated-release") }
  end
  abort("FAIL: no pull_request-eligible CI job runs the isolated-release gate") unless ok
' "$ROOT/.github/workflows/ci.yml"

# The local git-pr selector is the repo's stated primary pre-PR gate; it must carry the
# flag too, or a bundled bump passes local verification unchallenged.
if ! grep -q -- 'origin/master --require-isolated-release' "$ROOT/skills/git-pr/scripts/select-verification-gates.sh"; then
  echo 'FAIL: the git-pr verification selector must enforce the isolated-release shape' >&2
  exit 1
fi

# ── Restoring the manifests to the last published release (MD-2913) ───────────
# The recovery from a bundled bump: master advertises a version that was never tagged
# and can no longer be cut, so it goes back to where publication actually stopped.
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb stranded-bump
manifest 1.4.0 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
git -C "$WORK" add . && git -C "$WORK" commit -qm 'stranded bump'
git -C "$WORK" checkout -qb restore-published
manifest 1.0.0 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
git -C "$WORK" add . && git -C "$WORK" commit -qm 'restore to last published'
TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" stranded-bump --require-isolated-release >/dev/null
# A restoration may not smuggle in a NEW record — that would be a release in disguise.
mkdir -p "$WORK/releases"
printf '# Tron v1.0.0\n\nPrevious release: v1.0.0\n\n## Changes\n\n- x\n' > "$WORK/releases/v1.0.0.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm 'restore plus record'
if TRON_PLUGIN_ROOT="$WORK" bash "$CHECK" stranded-bump >/dev/null 2>&1; then
  echo 'FAIL: a restoration was allowed to add a release record' >&2
  exit 1
fi

# ── is-release-boundary classifies three outcomes, not two (MD-2913) ──────────
BOUNDARY="$ROOT/tools/release/is-release-boundary.sh"
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb boundary-cases
printf 'ordinary\n' >> "$WORK/README.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm ordinary-for-boundary
set +e
TRON_PLUGIN_ROOT="$WORK" bash "$BOUNDARY" >/dev/null 2>&1; ordinary_code=$?
set -e
[ "$ordinary_code" = 1 ] || { echo "FAIL: an ordinary commit must no-op (got $ordinary_code)" >&2; exit 1; }
# A bump merged WITHOUT its record must never read as 'nothing to publish'.
manifest 1.5.0 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
git -C "$WORK" add . && git -C "$WORK" commit -qm 'bump without record'
set +e
TRON_PLUGIN_ROOT="$WORK" bash "$BOUNDARY" >/dev/null 2>&1; malformed_code=$?
set -e
[ "$malformed_code" = 2 ] || { echo "FAIL: a malformed release must fail loudly (got $malformed_code)" >&2; exit 1; }
# REGRESSION (MD-2913): a restoration merge failed the release job on master. It moves
# the manifests — so it looks like a release attempt — but it moves them BACK onto an
# already-published version, which is recovery, not a broken release. It must no-op.
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb restoration-boundary
manifest 1.9.0 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
git -C "$WORK" add . && git -C "$WORK" commit -qm 'stranded bump on master'
manifest 1.0.0 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
printf 'restoration rides with fixes\n' >> "$WORK/README.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm 'restore manifests to v1.0.0 alongside fixes'
set +e
TRON_PLUGIN_ROOT="$WORK" bash "$BOUNDARY" >/dev/null 2>&1; restore_code=$?
set -e
[ "$restore_code" = 1 ] || { echo "FAIL: a restoration must no-op, not read as a malformed release (got $restore_code)" >&2; exit 1; }

# A release landing as a MERGE commit must still be seen; a bare diff-tree shows nothing.
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb merge-boundary-src
mkdir -p "$WORK/releases"
manifest 1.6.0 > "$WORK/.claude-plugin/plugin.json"; cp "$WORK/.claude-plugin/plugin.json" "$WORK/.codex-plugin/plugin.json"
printf '# Tron v1.6.0\n\nPrevious release: v1.0.0\n\n## Changes\n\n- x\n' > "$WORK/releases/v1.6.0.md"
git -C "$WORK" add . && git -C "$WORK" commit -qm 'release 1.6.0'
git -C "$WORK" checkout -q master
git -C "$WORK" checkout -qb merge-boundary
git -C "$WORK" merge --no-ff merge-boundary-src -m 'Merge release PR' >/dev/null
set +e
TRON_PLUGIN_ROOT="$WORK" bash "$BOUNDARY" >/dev/null 2>&1; merge_code=$?
set -e
[ "$merge_code" = 0 ] || { echo "FAIL: a release merged as a merge commit must publish (got $merge_code)" >&2; exit 1; }

printf 'PASS: release-boundary validator accepts ordinary changes and only explicit, synchronized releases.\n'
