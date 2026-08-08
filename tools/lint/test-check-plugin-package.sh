#!/usr/bin/env bash
# Layer-1 coverage for package invariants. This intentionally does not invoke
# Claude or Codex: the plugin-package CI job owns the real isolated CLI install.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NODE="${NODE_BIN:-$(command -v node)}"

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
if (claudeRaw !== codexRaw) {
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
