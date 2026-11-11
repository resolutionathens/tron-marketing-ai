#!/usr/bin/env bash
# MD-3346: dependency setup must keep installed Codex plugins fingerprintable.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/md-to-adf-deps.XXXXXX")"
trap 'trash "$FIXTURE"' EXIT

node - "$HERE" "$FIXTURE" <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const [source, root] = process.argv.slice(2);
const bin = path.join(root, 'bin');
fs.mkdirSync(bin);

// Model npm's executable-link behavior without network access. The converter
// itself runs unchanged, including its first-run install and dynamic import.
fs.writeFileSync(path.join(bin, 'npm'), `#!/usr/bin/env node
const fs = require('node:fs');
fs.appendFileSync('install-calls.jsonl', JSON.stringify(process.argv.slice(2)) + '\\n');
fs.mkdirSync('node_modules/markdown-to-adf', { recursive: true });
fs.writeFileSync('node_modules/markdown-to-adf/package.json', JSON.stringify({
  name: 'markdown-to-adf', type: 'module', exports: './index.mjs'
}));
fs.writeFileSync('node_modules/markdown-to-adf/index.mjs',
  'export const markdownToAdf = text => ({ type: "doc", version: 1, content: [{ type: "paragraph", content: [{ type: "text", text: text.trim() }] }] });');
fs.mkdirSync('node_modules/markdown-it/bin', { recursive: true });
fs.writeFileSync('node_modules/markdown-it/bin/markdown-it.mjs', 'preserve the executable target\\n');
fs.mkdirSync('node_modules/.bin', { recursive: true });
if (!process.argv.includes('--bin-links=false')) {
  fs.symlinkSync('../markdown-it/bin/markdown-it.mjs', 'node_modules/.bin/markdown-it');
}
`, { mode: 0o755 });

const install = path.join(root, 'installed plugin');
fs.mkdirSync(install);
fs.copyFileSync(path.join(source, 'md-to-adf.mjs'), path.join(install, 'md-to-adf.mjs'));
const shortcut = path.join(install, 'node_modules/.bin/markdown-it');
const target = path.join(install, 'node_modules/markdown-it/bin/markdown-it.mjs');
const calls = () => fs.readFileSync(path.join(install, 'install-calls.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
function convert() {
  const result = spawnSync(process.execPath, [path.join(install, 'md-to-adf.mjs')], {
    input: 'Dependency setup regression\n', encoding: 'utf8',
    env: { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}` },
  });
  assert.equal(result.status, 0, result.stderr);
  const adf = JSON.parse(result.stdout);
  assert.equal(adf.type, 'doc');
  assert.equal(adf.version, 1);
  assert.equal(adf.content[0].content[0].text, 'Dependency setup regression');
}
function assertFingerprintable(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    assert.ok(entry.isFile() || entry.isDirectory(), `unsupported plugin entry type: ${path.join(dir, entry.name)}`);
    if (entry.isDirectory()) assertFingerprintable(path.join(dir, entry.name));
  }
}

convert();
assertFingerprintable(install);
assert.ok(calls()[0].includes('--bin-links=false'), 'prevent links during installation, not just afterward');
console.log('  ok  : fresh install produces ADF without executable symlinks');

convert();
assert.equal(calls().length, 1, 'repeat conversion must reuse dependencies');
assertFingerprintable(install);
console.log('  ok  : repeat conversion reuses dependencies and stays fingerprintable');

fs.symlinkSync('../markdown-it/bin/markdown-it.mjs', shortcut);
const targetBefore = fs.readFileSync(target);
const library = path.join(install, 'node_modules/markdown-to-adf/index.mjs');
const libraryBefore = fs.readFileSync(library);
convert();
assert.equal(fs.lstatSync(shortcut, { throwIfNoEntry: false }), undefined);
assert.deepEqual(fs.readFileSync(target), targetBefore);
assert.deepEqual(fs.readFileSync(library), libraryBefore);
assert.equal(calls().length, 1, 'repair must not reinstall existing dependencies');
assertFingerprintable(install);
console.log('  ok  : existing symlink repaired while target and dependency files survive');

fs.symlinkSync('../missing-markdown-it.mjs', shortcut);
convert();
assert.equal(fs.lstatSync(shortcut, { throwIfNoEntry: false }), undefined);
console.log('  ok  : dangling executable shortcut is repaired');

fs.writeFileSync(shortcut, 'keep this regular file\n');
convert();
assert.equal(fs.readFileSync(shortcut, 'utf8'), 'keep this regular file\n');
assert.equal(calls().length, 1);
assertFingerprintable(install);
console.log('  ok  : regular file at shortcut path is preserved');
NODE
