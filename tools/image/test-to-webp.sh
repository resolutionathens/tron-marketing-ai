#!/usr/bin/env bash
# Hermetic test for to-webp.sh — the shared "cap the longest edge at 2000px,
# quality 82, emit webp" converter used by image-pipeline.sh and generate-card.sh.
#
# The resize/quality logic lives entirely in the `bun -e` block (Bun.Image), so
# the real behaviour is only assertable when this bun build actually ships
# Bun.Image. We PROBE for it: if present (and ImageMagick can mint fixtures) we
# convert real PNGs and assert output naming + the 2000px cap + no-upscale; if
# not, those checks SKIP loudly and only the arg/exit contract is asserted (which
# is real and offline regardless).
#
#   bash tools/image/test-to-webp.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/to-webp.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/to-webp-smoke.XXXXXX")"
PASS=0; SKIP=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
skip() { echo "  ⊘ SKIP: $*"; SKIP=$((SKIP+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT

echo "to-webp smoke: root=$ROOT"

# --- arg / exit contract (always offline) ------------------------------------
rc=0; bash "$SCRIPT" >/dev/null 2>"$ROOT/e0" || rc=$?
[[ "$rc" -ne 0 ]] || fail "no args should exit nonzero (got $rc)"
grep -qF 'Usage' "$ROOT/e0" || fail "no-args error should mention Usage (got: $(cat "$ROOT/e0"))"
pass "no args → nonzero exit + Usage on stderr"

rc=0; bash "$SCRIPT" only-input >/dev/null 2>"$ROOT/e1" || rc=$?
[[ "$rc" -ne 0 ]] || fail "missing output arg should exit nonzero (got $rc)"
grep -qF 'Usage' "$ROOT/e1" || fail "one-arg error should mention Usage"
pass "input but no output → nonzero exit + Usage on stderr"

# --- capability probe: real conversion only if Bun.Image + ImageMagick exist --
CAP=0
if command -v bun >/dev/null 2>&1 \
   && bun -e 'process.exit(typeof Bun.Image==="function"?0:3)' >/dev/null 2>&1 \
   && command -v convert >/dev/null 2>&1; then
  CAP=1
fi

if [[ "$CAP" -eq 0 ]]; then
  skip "conversion assertions — this bun build has no Bun.Image (or ImageMagick missing); wrapper/arg contract still asserted above"
  echo ""
  echo "✅ to-webp smoke PASSED ($PASS checks, $SKIP skipped)"
  exit 0
fi

# small.png is well under the 2000px cap → must pass through unchanged (no upscale)
convert -size 100x60 xc:red "$ROOT/small.png"
OUT="$(bash "$SCRIPT" "$ROOT/small.png" "$ROOT/small.webp")"; echo "  → $OUT"
[[ -f "$ROOT/small.webp" ]] || fail "small.webp not written"
grep -qF 'small.webp' <<<"$OUT" || fail "stdout should report the output basename (got: $OUT)"
grep -qE '(^|[[:space:]])100x60([[:space:]]|$)' <<<"$OUT" || fail "sub-cap image must keep 100x60, never upscale (got: $OUT)"
# webp files start with the RIFF....WEBP magic
head -c4 "$ROOT/small.webp" | grep -q 'RIFF' || fail "output is not a RIFF/webp container"
pass "sub-cap image → same dims (no upscale), webp container, basename reported"

# large image: longest edge (3000) must be capped to 2000, aspect ratio kept → 2000x1000
convert -size 3000x1500 xc:blue "$ROOT/big.png"
OUT="$(bash "$SCRIPT" "$ROOT/big.png" "$ROOT/big.webp")"; echo "  → $OUT"
grep -qE '(^|[[:space:]])2000x1000([[:space:]]|$)' <<<"$OUT" || fail "3000x1500 should cap to 2000x1000 (got: $OUT)"
pass "over-cap image → longest edge capped to 2000, aspect ratio preserved"

# output naming is taken verbatim from arg 2 (basename), not derived from input
OUT="$(bash "$SCRIPT" "$ROOT/small.png" "$ROOT/renamed-xyz.webp")"
[[ -f "$ROOT/renamed-xyz.webp" ]] || fail "explicit output name not honoured"
grep -qF 'renamed-xyz.webp' <<<"$OUT" || fail "stdout should echo the explicit output name (got: $OUT)"
pass "output filename honours arg 2 verbatim"

# nonexistent input → bun throws → nonzero exit
rc=0; bash "$SCRIPT" "$ROOT/nope.png" "$ROOT/nope.webp" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "missing input file should exit nonzero (got $rc)"
pass "nonexistent input → nonzero exit"

echo ""
echo "✅ to-webp smoke PASSED ($PASS checks, $SKIP skipped)"
