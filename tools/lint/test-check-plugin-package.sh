#!/usr/bin/env bash
# Layer-1 coverage for package invariants. This intentionally does not invoke
# Claude or Codex: the plugin-package CI job owns the real isolated CLI install.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Resolve a real node executable, never a version-manager shim (MD-3398). A mise shim
# only works while mise can pick a version: with no global node it falls through to the
# next node on PATH, so it breaks once PATH is narrowed. Ask node for its own execPath on
# the caller's PATH; where no node runs there at all, pin mise's installed LTS explicitly.
resolve_node() {
  local p
  p="$(node -p process.execPath 2>/dev/null)" && [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
  command -v mise >/dev/null 2>&1 \
    && p="$(mise exec node@lts -- node -p process.execPath 2>/dev/null)" && [ -x "$p" ] \
    && { printf '%s\n' "$p"; return 0; }
  echo "FAIL: no runnable node found on PATH or through mise (node@lts)" >&2
  return 1
}
NODE="${NODE_BIN:-$(resolve_node)}"

# Match the general Layer-1 job, which deliberately has no Claude/Codex CLI.
PATH="/usr/bin:/bin"
export PATH

"$NODE" - "$ROOT" <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.argv[2];
const claudeRaw = fs.readFileSync(path.join(root, '.claude-plugin/plugin.json'), 'utf8');
const codexRaw = fs.readFileSync(path.join(root, '.codex-plugin/plugin.json'), 'utf8');
const claude = JSON.parse(claudeRaw);
const codex = JSON.parse(codexRaw);
const marketplace = JSON.parse(fs.readFileSync(path.join(root, '.agents/plugins/marketplace.json'), 'utf8'));
const catalog = (base) => fs.readdirSync(path.join(base, 'skills'), { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && fs.existsSync(path.join(base, 'skills', entry.name, 'SKILL.md')))
  .map((entry) => entry.name)
  .sort();

// The two manifests describe the same plugin for different harnesses; any
// field drifting between them (added, removed, or changed in only one file)
// must fail immediately rather than pass on a hand-picked field subset.
// Line endings are normalized first so a CRLF checkout (e.g. Windows/editor
// defaults) can't produce a false failure on otherwise-identical content.
if (claudeRaw.replace(/\r\n/g, '\n') !== codexRaw.replace(/\r\n/g, '\n')) {
  throw new Error('Claude and Codex manifests must be byte-for-byte identical');
}
if (codex.skills !== './skills/') throw new Error('Codex must reference the shared skill catalog');
const tron = marketplace.plugins?.find((entry) => entry.name === codex.name);
if (!tron || tron.source?.source !== 'local' || tron.source?.path !== '.') {
  throw new Error('Codex marketplace must expose the shared repository source');
}
const skills = catalog(root);
if (skills.length === 0 || new Set(skills).size !== skills.length) {
  throw new Error('shared skill catalog must be non-empty and unique');
}
for (const required of ['agents', 'tools', 'hooks']) {
  if (!fs.existsSync(path.join(root, required))) throw new Error(`missing bundled ${required}`);
}
console.log(`package fixture: ${skills.length} shared skills, manifest version ${codex.version}`);
NODE

printf 'PASS: deterministic package fixture assertions require no host plugin CLIs.\n'
