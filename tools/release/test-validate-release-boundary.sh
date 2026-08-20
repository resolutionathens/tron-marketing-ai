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
if ! grep -A 5 'uses: actions/checkout@v4' "$ROOT/.github/workflows/ci.yml" | grep -q 'fetch-depth: 0'; then
  echo 'FAIL: CI must fetch release-boundary history before validating a PR' >&2
  exit 1
fi
printf 'PASS: release-boundary validator accepts ordinary changes and only explicit, synchronized releases.\n'
