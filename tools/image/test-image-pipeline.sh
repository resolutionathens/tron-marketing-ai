#!/usr/bin/env bash
# Hermetic test for image-pipeline.sh — batch webp-convert + ImageKit upload.
#
# The two external legs (to-webp.sh conversion, imagekit.mjs upload) are stubbed:
#   • CLAUDE_PLUGIN_ROOT points at a FAKE plugin root whose tools/image/to-webp.sh
#     is a stub (copies/writes a webp, or fails on demand via $TW_FAIL) and whose
#     tools/imagekit/imagekit.mjs is a placeholder path.
#   • `node` is PATH-shimmed to serve a canned {"url":…} per upload.
#   • python3 (JSON assembly + url parse) runs for real — offline.
#
# Asserts: batch mapping, JSON-stdout / progress-stderr separation, the empty-dir
# {} short-circuit, the duplicate-output-stem fail-fast, --pattern filtering, and
# the arg / exit-code contract (2 = usage, 1 = logical failure).
#
#   bash tools/image/test-image-pipeline.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/image-pipeline.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/image-pipeline-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has()   { grep -qF -- "$2" <<<"$1" || fail "$3 — got: $1"; }
hasnt() { grep -qF -- "$2" <<<"$1" && fail "$3 — unexpectedly got: $1"; return 0; }

echo "image-pipeline smoke: root=$ROOT"

# --- fake plugin root: stub to-webp.sh + placeholder imagekit.mjs ------------
FAKE="$ROOT/plugin"
mkdir -p "$FAKE/tools/image" "$FAKE/tools/imagekit" "$ROOT/bin"
cat > "$FAKE/tools/image/to-webp.sh" <<'SH'
#!/usr/bin/env bash
# $1=src $2=dest.webp ; fail on demand to exercise the convert-failure branch
[[ -n "${TW_FAIL:-}" ]] && { echo "stub to-webp: boom" >&2; exit 1; }
printf 'webp-bytes' > "$2"
echo "$(basename "$2")  10x10  1.0KB"
SH
chmod +x "$FAKE/tools/image/to-webp.sh"
: > "$FAKE/tools/imagekit/imagekit.mjs"

# `node imagekit.mjs upload <path> --name <name> --folder <dest>` → canned url
cat > "$ROOT/bin/node" <<'SH'
#!/usr/bin/env bash
name=""
while [[ $# -gt 0 ]]; do
  case "$1" in --name) name="$2"; shift 2 ;; *) shift ;; esac
done
printf '{"url":"https://ik.stub/%s"}\n' "$name"
SH
chmod +x "$ROOT/bin/node"

run() { PATH="$ROOT/bin:$PATH" CLAUDE_PLUGIN_ROOT="$FAKE" bash "$SCRIPT" "$@"; }

# --- happy path: batch convert + upload, stdout JSON only --------------------
SRC="$ROOT/src"; mkdir -p "$SRC"
: > "$SRC/section-intro.png"
: > "$SRC/diagram.JPG"          # mixed case → default -iname set matches
: > "$SRC/notes.txt"            # non-image → ignored by the default pattern
OUT="$(run --src "$SRC" --dest blog-posts/x 2>"$ROOT/err")"
echo "  → stdout: $(tr '\n' ' ' <<<"$OUT")"
echo "  → stderr: $(tr '\n' ' ' <<<"$(cat "$ROOT/err")")"
# stdout is pure JSON: parse it and assert the exact mapping
printf '%s' "$OUT" > "$ROOT/out.json"
python3 -c "
import json
d=json.load(open('$ROOT/out.json'))
want={'section-intro.webp':'https://ik.stub/section-intro.webp','diagram.webp':'https://ik.stub/diagram.webp'}
assert d==want, f'got {d}'
" || fail "stdout JSON mapping wrong: $OUT"
pass "batch: stdout is valid JSON mapping <name>.webp → CDN url (2 images, .txt ignored)"

# progress narration went to STDERR, never stdout
has "$(cat "$ROOT/err")" '✓ section-intro.webp' "per-file ✓ on stderr"
hasnt "$OUT" '✓' "stdout must not carry progress narration"
pass "stream separation: ✓ progress on stderr, JSON on stdout"

# --- empty dir → {} exit 0 ---------------------------------------------------
EMPTY="$ROOT/empty"; mkdir -p "$EMPTY"
rc=0; OUT="$(run --src "$EMPTY" --dest d 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "empty dir should exit 0 (got $rc)"
[[ "$OUT" == "{}" ]] || fail "empty dir should print {} (got: $OUT)"
pass "empty source dir → {} + exit 0"

# --- duplicate output stem fail-fast (hero.png + hero.jpg → hero.webp) --------
DUP="$ROOT/dup"; mkdir -p "$DUP"; : > "$DUP/hero.png"; : > "$DUP/hero.jpg"
rc=0; OUT="$(run --src "$DUP" --dest d 2>"$ROOT/duperr")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "duplicate stem should exit 1 (got $rc)"
has "$(cat "$ROOT/duperr")" "duplicate output name 'hero.webp'" "names the colliding stem"
[[ -z "$OUT" ]] || fail "duplicate-stem failure must not emit JSON (got: $OUT)"
pass "duplicate output stem → exit 1 before any convert/upload, names collision"

# --- --pattern narrows the file set ------------------------------------------
PAT="$ROOT/pat"; mkdir -p "$PAT"; : > "$PAT/keep.png"; : > "$PAT/skip.jpg"
OUT="$(run --src "$PAT" --dest d --pattern '*.png' 2>/dev/null)"
has "$OUT" 'keep.webp' "--pattern keeps matching file"
hasnt "$OUT" 'skip.webp' "--pattern excludes non-matching file"
pass "--pattern '*.png' → only png converted"

# --- convert failure → nonzero, reported on stderr ---------------------------
FSRC="$ROOT/failsrc"; mkdir -p "$FSRC"; : > "$FSRC/a.png"
rc=0; OUT="$(PATH="$ROOT/bin:$PATH" CLAUDE_PLUGIN_ROOT="$FAKE" TW_FAIL=1 \
            bash "$SCRIPT" --src "$FSRC" --dest d 2>"$ROOT/cfail")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "convert failure should exit 1 (got $rc)"
has "$(cat "$ROOT/cfail")" '✗ convert failed: a.png' "reports the failed convert on stderr"
pass "convert failure → exit 1 + ✗ on stderr"

# --- arg / exit contract -----------------------------------------------------
rc=0; run --dest d >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "missing --src should exit 2 (got $rc)"
rc=0; run --src "$SRC" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "missing --dest should exit 2 (got $rc)"
rc=0; run --src >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "--src with no value should exit 2 (got $rc)"
rc=0; run --bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "unknown flag should exit 2 (got $rc)"
pass "usage contract → exit 2 on missing/dangling/unknown flags"

# not-a-directory → logical error (exit 1), distinct from usage (2)
rc=0; run --src "$ROOT/does-not-exist" --dest d >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] || fail "non-directory --src should exit 1 (got $rc)"
pass "non-directory --src → exit 1 (logical, not usage)"

# missing to-webp.sh under the resolved plugin root → exit 1
BARE="$ROOT/bare"; mkdir -p "$BARE/tools/imagekit"; : > "$BARE/tools/imagekit/imagekit.mjs"
rc=0; OUT="$(PATH="$ROOT/bin:$PATH" CLAUDE_PLUGIN_ROOT="$BARE" \
            bash "$SCRIPT" --src "$SRC" --dest d 2>"$ROOT/toolerr")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "missing to-webp.sh should exit 1 (got $rc)"
has "$(cat "$ROOT/toolerr")" 'to-webp.sh not found' "names the missing bundled tool"
pass "missing bundled to-webp.sh → exit 1 with a clear message"

echo ""
echo "✅ image-pipeline smoke PASSED ($PASS checks)"
