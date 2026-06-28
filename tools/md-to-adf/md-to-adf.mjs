#!/usr/bin/env node
// Convert Markdown (stdin) to Atlassian Document Format JSON (stdout) for Jira.
//
// Usage:  md-to-adf.mjs [--preset story|task|comment] < input.md > out.adf.json
//
// Wraps the `markdown-to-adf` npm package. Default preset is `story` (full
// heading support), matching what the tron:jira skill needs for rich ticket
// descriptions passed to `acli ... --description-file`.

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

// Lazy-install our one dependency on first run. The tool is vendored in the
// plugin but its node_modules is not committed (keeps the repo lean), so the
// first invocation installs markdown-to-adf next to this script. Needs npm +
// network once; later runs find node_modules and skip straight through.
const __dir = path.dirname(fileURLToPath(import.meta.url));
if (!fs.existsSync(path.join(__dir, 'node_modules', 'markdown-to-adf'))) {
  console.error('md-to-adf: installing dependencies (first run, one time)…');
  execSync('npm install --silent --no-audit --no-fund', { cwd: __dir, stdio: ['ignore', 'ignore', 'inherit'] });
}
const { markdownToAdf } = await import('markdown-to-adf');

const args = process.argv.slice(2);
let preset = 'story';
const pi = args.indexOf('--preset');
if (pi !== -1 && args[pi + 1]) preset = args[pi + 1];

const md = fs.readFileSync(0, 'utf8'); // fd 0 = stdin
const adf = markdownToAdf(md, { preset });

// Strip inline `code` marks. They are valid ADF per the Atlassian spec, but the `acli`
// backend this output is fed to (`acli ... --description-file`) rejects them with
// `InvalidPayloadException: INVALID_INPUT` — so any description with backticks (file
// paths, identifiers, flags) would fail to submit. We drop just the `code` mark; the
// text stays (readable as plain text). Fenced code blocks (`codeBlock` nodes) and
// `strong`/`em` marks are accepted by acli and are left intact. (MD-1944)
function stripCodeMarks(node) {
  if (Array.isArray(node)) {
    node.forEach(stripCodeMarks);
    return;
  }
  if (node && typeof node === 'object') {
    if (Array.isArray(node.marks)) {
      node.marks = node.marks.filter((m) => m && m.type !== 'code');
      if (node.marks.length === 0) delete node.marks;
    }
    for (const value of Object.values(node)) stripCodeMarks(value);
  }
}
stripCodeMarks(adf);

process.stdout.write(JSON.stringify(adf));
