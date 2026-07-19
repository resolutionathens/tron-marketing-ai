#!/usr/bin/env bash
# Validate the shared-source Claude/Codex release layout. Both harnesses install
# into isolated homes, then their installed catalogs and bundled files must match
# the monolithic source. Pass --live-smoke to additionally invoke a representative
# installed skill in fresh, authenticated Claude and Codex processes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLAUDE_MANIFEST="$ROOT/.claude-plugin/plugin.json"
CODEX_MANIFEST="$ROOT/.codex-plugin/plugin.json"
CODEX_MARKETPLACE="$ROOT/.agents/plugins/marketplace.json"
LIVE_SMOKE=false

case "${1:-}" in
  '') ;;
  --live-smoke) LIVE_SMOKE=true ;;
  *) printf 'usage: %s [--live-smoke]\n' "$0" >&2; exit 2 ;;
esac

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
need() { [ -e "$1" ] || fail "missing ${1#$ROOT/}"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "$1 is required"; }

need "$CLAUDE_MANIFEST"
need "$CODEX_MANIFEST"
need "$CODEX_MARKETPLACE"
for path in skills agents tools hooks; do need "$ROOT/$path"; done
for cmd in node codex claude trash; do need_cmd "$cmd"; done

node - "$CLAUDE_MANIFEST" "$CODEX_MANIFEST" "$CODEX_MARKETPLACE" <<'NODE'
const fs = require('fs');
const [claudePath, codexPath, marketplacePath] = process.argv.slice(2);
const claude = JSON.parse(fs.readFileSync(claudePath, 'utf8'));
const codex = JSON.parse(fs.readFileSync(codexPath, 'utf8'));
const marketplace = JSON.parse(fs.readFileSync(marketplacePath, 'utf8'));
if (claude.name !== codex.name) throw new Error('Claude and Codex manifest names differ');
if (claude.version !== codex.version) throw new Error('Claude and Codex manifest versions differ');
if (codex.skills !== './skills/') throw new Error('Codex manifest must reference the shared skills directory');
const plugin = marketplace.plugins?.find((entry) => entry.name === codex.name);
if (!plugin || plugin.source?.source !== 'local' || plugin.source?.path !== '.') {
  throw new Error('Codex marketplace must point at the repository root shared source');
}
NODE

claude plugin validate "$ROOT" >/dev/null
VERSION="$(node -p "require('$CODEX_MANIFEST').version")"
TMP_PARENT="${TMPDIR:-/tmp}"
CODEX_HOME="$(mktemp -d "$TMP_PARENT/tron-codex-package.XXXXXX")"
CLAUDE_CONFIG_DIR="$(mktemp -d "$TMP_PARENT/tron-claude-package.XXXXXX")"
ROLE_BUILD_ROOT="$(mktemp -d "$TMP_PARENT/tron-role-build.XXXXXX")"
ROLE_CODEX_HOME="$(mktemp -d "$TMP_PARENT/tron-role-codex.XXXXXX")"
ROLE_CLAUDE_CONFIG_DIR="$(mktemp -d "$TMP_PARENT/tron-role-claude.XXXXXX")"
LIVE_INSTALLED=false

cleanup() {
  if [ "$LIVE_INSTALLED" = true ]; then
    codex plugin remove tron@tron --json >/dev/null 2>&1 || true
    codex plugin marketplace remove tron >/dev/null 2>&1 || true
  fi
  trash "$CODEX_HOME" "$CLAUDE_CONFIG_DIR" "$ROLE_BUILD_ROOT" \
    "$ROLE_CODEX_HOME" "$ROLE_CLAUDE_CONFIG_DIR" || {
    printf 'FAIL: could not trash package validation homes\n' >&2
    return 1
  }
}
trap cleanup EXIT

CODEX_HOME="$CODEX_HOME" codex plugin marketplace add "$ROOT" --json >/dev/null
CODEX_HOME="$CODEX_HOME" codex plugin add tron@tron --json >/dev/null
CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" claude plugin marketplace add "$ROOT" --scope user >/dev/null
CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" claude plugin install tron@tron --scope user >/dev/null

CODEX_LIST="$CODEX_HOME/codex-plugins.json"
CLAUDE_LIST="$CLAUDE_CONFIG_DIR/claude-plugins.json"
CODEX_HOME="$CODEX_HOME" codex plugin list --json > "$CODEX_LIST"
CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" claude plugin list --json > "$CLAUDE_LIST"

node - "$CODEX_LIST" "$CLAUDE_LIST" "$VERSION" <<'NODE'
const fs = require('fs');
const [codexPath, claudePath, version] = process.argv.slice(2);
const codex = JSON.parse(fs.readFileSync(codexPath, 'utf8'));
const claude = JSON.parse(fs.readFileSync(claudePath, 'utf8'));
const codexPlugin = codex.installed?.find((entry) => entry.pluginId === 'tron@tron');
if (!codexPlugin?.installed || !codexPlugin.enabled || codexPlugin.version !== version) {
  throw new Error('fresh Codex process cannot discover enabled tron@tron at the manifest version');
}
const claudePlugin = claude.find((entry) => entry.id === 'tron@tron');
if (!claudePlugin?.enabled || claudePlugin.version !== version || !claudePlugin.installPath) {
  throw new Error('fresh Claude process cannot discover enabled tron@tron at the manifest version');
}
NODE

CODEX_ROOT="$(find "$CODEX_HOME/plugins/cache" -path "*/tron/$VERSION" -type d -print -quit)"
CLAUDE_ROOT="$(node -p "JSON.parse(require('fs').readFileSync('$CLAUDE_LIST')).find(x => x.id === 'tron@tron').installPath")"
[ -n "$CODEX_ROOT" ] || fail "Codex did not install tron at version $VERSION"
[ -d "$CLAUDE_ROOT" ] || fail "Claude did not install tron at version $VERSION"

for installed in "$CODEX_ROOT" "$CLAUDE_ROOT"; do
  for path in skills agents tools hooks; do need "$installed/$path"; done
  while IFS= read -r source; do
    relative="${source#$ROOT/}"
    target="$installed/$relative"
    [ -f "$target" ] || fail "installed package omitted $relative"
    cmp -s "$source" "$target" || fail "installed package changed $relative"
  done < <(find "$ROOT/skills" "$ROOT/agents" "$ROOT/tools" "$ROOT/hooks" -type f -not -path '*/node_modules/*' | sort)
done

node - "$ROOT" "$CODEX_ROOT" "$CLAUDE_ROOT" <<'NODE'
const fs = require('fs');
const path = require('path');
const [source, codex, claude] = process.argv.slice(2);
function catalog(root) {
  return fs.readdirSync(path.join(root, 'skills'), { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && fs.existsSync(path.join(root, 'skills', entry.name, 'SKILL.md')))
    .map((entry) => entry.name).sort();
}
const expected = JSON.stringify(catalog(source));
for (const [name, root] of [['Codex', codex], ['Claude', claude]]) {
  if (JSON.stringify(catalog(root)) !== expected) throw new Error(`${name} installed skill catalog differs from source`);
}
NODE

node "$ROOT/tools/package/build-packages.mjs" "$ROLE_BUILD_ROOT" >/dev/null
ROLE_CODEX_SOURCE="$ROLE_BUILD_ROOT/codex/tron-content"
ROLE_CLAUDE_SOURCE="$ROLE_BUILD_ROOT/claude/tron-content"
CODEX_HOME="$ROLE_CODEX_HOME" codex plugin marketplace add "$ROLE_CODEX_SOURCE" --json >/dev/null
CODEX_HOME="$ROLE_CODEX_HOME" codex plugin add tron-content@tron --json >/dev/null
CLAUDE_CONFIG_DIR="$ROLE_CLAUDE_CONFIG_DIR" \
  claude plugin marketplace add "$ROLE_CLAUDE_SOURCE" --scope user >/dev/null
CLAUDE_CONFIG_DIR="$ROLE_CLAUDE_CONFIG_DIR" \
  claude plugin install tron-content@tron --scope user >/dev/null
CODEX_HOME="$ROLE_CODEX_HOME" codex plugin list --json > "$ROLE_CODEX_HOME/plugins.json"
CLAUDE_CONFIG_DIR="$ROLE_CLAUDE_CONFIG_DIR" \
  claude plugin list --json > "$ROLE_CLAUDE_CONFIG_DIR/plugins.json"
node - "$ROLE_CODEX_HOME/plugins.json" "$ROLE_CLAUDE_CONFIG_DIR/plugins.json" "$VERSION" <<'NODE'
const fs = require('fs');
const [codexPath, claudePath, version] = process.argv.slice(2);
const codex = JSON.parse(fs.readFileSync(codexPath, 'utf8'));
const claude = JSON.parse(fs.readFileSync(claudePath, 'utf8'));
const codexPlugin = codex.installed?.find((entry) => entry.pluginId === 'tron-content@tron');
const claudePlugin = claude.find((entry) => entry.id === 'tron-content@tron');
if (!codexPlugin?.enabled || codexPlugin.version !== version) {
  throw new Error('fresh Codex process cannot install the generated content role package');
}
if (!claudePlugin?.enabled || claudePlugin.version !== version) {
  throw new Error('fresh Claude process cannot install the generated content role package');
}
NODE

if [ "$LIVE_SMOKE" = true ]; then
  claude --plugin-dir "$CLAUDE_ROOT" --print --max-budget-usd 0.50 \
    'Use the installed tron:brainstorm skill. Do not ask a question or call tools. Reply with exactly: CLAUDE-TRON-INSTALLED.' \
    | grep -q 'CLAUDE-TRON-INSTALLED' || fail 'fresh Claude process could not invoke tron:brainstorm'
  if codex plugin list --json | node -e 'let s=""; process.stdin.on("data", d => s += d).on("end", () => process.exit(JSON.parse(s).installed.some(x => x.pluginId === "tron@tron") ? 0 : 1))'; then
    fail 'refusing live Codex smoke because tron@tron is already installed in the user profile'
  fi
  codex plugin marketplace add "$ROOT" --json >/dev/null
  LIVE_INSTALLED=true
  codex plugin add tron@tron --json >/dev/null
  codex exec 'Use $tron:brainstorm. Do not call tools or ask a question. Reply with exactly CODEX-TRON-INSTALLED.' \
    | grep -q 'CODEX-TRON-INSTALLED' || fail 'fresh Codex process could not invoke tron:brainstorm'
fi

printf 'PASS: Claude/Codex manifests share version %s; isolated monolith and role installs are discoverable with complete inventories.\n' "$VERSION"
