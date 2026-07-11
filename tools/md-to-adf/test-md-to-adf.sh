#!/usr/bin/env bash
# Fixture test for md-to-adf.mjs (MD-1986).
#
# Locks in the MD-1944 fix: inline `code` marks must be stripped (acli's
# --description-file rejects them) while fenced code blocks (codeBlock nodes)
# and other marks (strong/em) survive untouched.
#
#   bash tools/md-to-adf/test-md-to-adf.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLI="$HERE/md-to-adf.mjs"

command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
[ -d "$HERE/node_modules/markdown-to-adf" ] || { echo "SKIP: markdown-to-adf not installed (run once to lazy-install)"; exit 0; }

fail=0
ok()  { echo "  ok  : $1"; }
bad() { echo "  FAIL: $1"; fail=1; }

# --- 1) inline `code` marks are stripped, text is kept ------------------------
out="$(printf 'Run `npm install` in the repo.\n' | node "$CLI")"; rc=$?
[ "$rc" -eq 0 ] && ok "inline code: exits 0" || bad "inline code: exit $rc"
printf '%s' "$out" | grep -q '"type":"code"' && bad "inline code: a code mark survived (got: $out)" || ok "inline code: no code mark in output"
printf '%s' "$out" | grep -q 'npm install' && ok "inline code: text content preserved" || bad "inline code: text content lost (got: $out)"

# --- 2) fenced code blocks are preserved as codeBlock nodes -------------------
out="$(printf '```js\nconst x = 1;\n```\n' | node "$CLI")"; rc=$?
[ "$rc" -eq 0 ] && ok "codeBlock: exits 0" || bad "codeBlock: exit $rc"
printf '%s' "$out" | grep -q '"type":"codeBlock"' && ok "codeBlock: codeBlock node preserved" || bad "codeBlock: codeBlock node missing (got: $out)"
printf '%s' "$out" | grep -q 'const x = 1;' && ok "codeBlock: code content preserved" || bad "codeBlock: code content lost (got: $out)"

# --- 3) other marks (strong/em) survive untouched -----------------------------
out="$(printf '**bold** and *italic* text.\n' | node "$CLI")"; rc=$?
[ "$rc" -eq 0 ] && ok "other marks: exits 0" || bad "other marks: exit $rc"
printf '%s' "$out" | grep -q '"type":"strong"' && ok "other marks: strong mark preserved" || bad "other marks: strong mark missing (got: $out)"
printf '%s' "$out" | grep -q '"type":"em"' && ok "other marks: em mark preserved" || bad "other marks: em mark missing (got: $out)"

# --- 4) blockquotes are flattened to italicized paragraphs, no blockQuote node -
out="$(printf '> quoted text\n' | node "$CLI")"; rc=$?
[ "$rc" -eq 0 ] && ok "blockquote: exits 0" || bad "blockquote: exit $rc"
printf '%s' "$out" | grep -q '"type":"blockQuote"' && bad "blockquote: a blockQuote node survived (got: $out)" || ok "blockquote: no blockQuote node in output"
printf '%s' "$out" | grep -q '"type":"em"' && ok "blockquote: text is italicized" || bad "blockquote: em mark missing (got: $out)"
printf '%s' "$out" | grep -q 'quoted text' && ok "blockquote: text content preserved" || bad "blockquote: text content lost (got: $out)"

# --- 5) output is valid ADF JSON (doc node, version 1) ------------------------
out="$(printf 'Plain text with `inline code` and a heading.\n\n# Heading\n' | node "$CLI")"; rc=$?
printf '%s' "$out" | node -e '
  let data = "";
  process.stdin.on("data", (c) => (data += c));
  process.stdin.on("end", () => {
    const doc = JSON.parse(data);
    if (doc.type !== "doc") throw new Error("root type is not doc: " + doc.type);
    if (doc.version !== 1) throw new Error("unexpected version: " + doc.version);
  });
' <<<"$out" && ok "valid ADF: root is a doc, version 1" || bad "valid ADF: malformed output (got: $out)"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
