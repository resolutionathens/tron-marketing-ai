#!/usr/bin/env bash
# Smoke test for optimize-images.sh. Builds a tiny mixed-format fixture and exercises every
# mode. Uses the REAL pngquant/cwebp (fast on tiny inputs); the same-format JPEG path is
# checked for graceful degradation when jpegoptim is absent.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/optimize-images.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

fail=0
contains() { if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok  : $1"; else echo "FAIL: $1 — missing '$2'"; fail=1; fi; }
exists()   { if [ -f "$2" ]; then echo "ok  : $1"; else echo "FAIL: $1 — no file $2"; fail=1; fi; }
absent()   { if [ -f "$2" ]; then echo "FAIL: $1 — unexpected file $2"; fail=1; else echo "ok  : $1"; fi; }

need() { command -v "$1" >/dev/null 2>&1; }
need pngquant || { echo "SKIP: pngquant not installed"; exit 0; }
need cwebp   || { echo "SKIP: cwebp not installed"; exit 0; }

# fixture: a PNG + a JPEG + a WebP, plus a nested file to prove structure mirroring
src="$TMP/src"; mkdir -p "$src/sub"
# generate a real PNG with pngquant-friendly content via cwebp? simplest: use ImageMagick if
# present, else fall back to bundled assets.
logo="$HERE/../facilitron-logo.png"
[ -f "$logo" ] || logo="$(ls ~/.claude/plugins/marketplaces/*/skills/md-to-pdf/facilitron-logo.png 2>/dev/null | head -1)"
[ -f "$logo" ] || { echo "SKIP: no sample PNG available"; exit 0; }
cp "$logo" "$src/logo.png"
cwebp -quiet -q 95 "$src/logo.png" -o "$TMP/tmp.webp" >/dev/null 2>&1
# make a "jpeg" by transcoding the png through cwebp then... cwebp can't write jpg; use sips (macOS)
if command -v sips >/dev/null 2>&1; then
  sips -s format jpeg "$src/logo.png" --out "$src/photo.jpg" >/dev/null 2>&1
else
  echo "note: no sips — skipping JPEG-specific assertions" >&2
fi
cp "$TMP/tmp.webp" "$src/sub/pic.webp"

# --- default mode: png stays png, jpg -> webp, webp -> webp ------------------------------
out="$(bash "$SCRIPT" "$src" 2>/dev/null)"
contains "default: table header present"      "| File | Format | Output |" "$out"
contains "default: png stays png"             "| logo.png | png | png |" "$out"
contains "default: webp re-encoded"           "sub/pic.webp | webp | webp" "$out"
exists   "default: png output written"        "$src/optimized/logo.png"
exists   "default: webp output written"       "$src/optimized/sub/pic.webp"
if [ -f "$src/photo.jpg" ]; then
  contains "default: jpg -> webp in table"    "photo.jpg | jpg | webp" "$out"
  exists   "default: jpg produced .webp"      "$src/optimized/photo.webp"
fi
contains "default: has Total row"             "Total" "$out"

# --- to-webp mode: everything becomes webp ----------------------------------------------
rm -rf "$src/optimized"
out="$(bash "$SCRIPT" "$src" --mode to-webp 2>/dev/null)"
exists   "to-webp: png -> webp"               "$src/optimized/logo.webp"
absent   "to-webp: no .png output"            "$src/optimized/logo.png"

# --- same-format mode: png via pngquant; jpg needs jpegoptim ------------------------------
rm -rf "$src/optimized"
out="$(bash "$SCRIPT" "$src" --mode same-format 2>/dev/null)"
exists   "same-format: png stays png"         "$src/optimized/logo.png"
if [ -f "$src/photo.jpg" ]; then
  if command -v jpegoptim >/dev/null 2>&1; then
    exists  "same-format: jpg stays jpg"      "$src/optimized/photo.jpg"
  else
    contains "same-format: jpg degrades w/ hint" "jpegoptim not installed" "$out"
    contains "same-format: hint suggests brew"   "brew install jpegoptim" "$out"
  fi
fi

# --- single file target -----------------------------------------------------------------
rm -rf "$src/optimized"
out="$(bash "$SCRIPT" "$src/logo.png" 2>/dev/null)"
contains "single-file: handled"               "logo.png" "$out"

# --- #4: a filename containing '|' must not corrupt the table row ------------------------
pipedir="$TMP/piped"; mkdir -p "$pipedir"
cp "$logo" "$pipedir/before|after.png"
out="$(bash "$SCRIPT" "$pipedir" 2>/dev/null)"
contains "pipe-name: row intact (escaped)"    'before\|after.png' "$out"

# --- #7: no-gain input is kept as original and reported as skipped (no negative %) -------
# Re-optimizing an already-pngquant'd PNG yields no further gain -> should skip, keep original.
nogdir="$TMP/nogain"; mkdir -p "$nogdir"
pngquant --quality=65-80 --speed 1 --strip --force --output "$nogdir/tiny.png" "$logo" 2>/dev/null || cp "$logo" "$nogdir/tiny.png"
out="$(bash "$SCRIPT" "$nogdir" 2>/dev/null)"
if printf '%s' "$out" | grep -qE -- '-[0-9]+%'; then echo "FAIL: no-gain shows negative %"; fail=1; else echo "ok  : no-gain: no negative % in output"; fi

# --- #8: to-webp respects a max-dim cap (downscale large images) -------------------------
if command -v sips >/dev/null 2>&1; then
  bigdir="$TMP/big"; mkdir -p "$bigdir"
  # upscale the logo to >800px so a --max-dim 400 must shrink it
  sips -z 1000 1000 "$logo" --out "$bigdir/big.png" >/dev/null 2>&1
  bash "$SCRIPT" "$bigdir" --mode to-webp --max-dim 400 >/dev/null 2>&1
  dims="$(sips -g pixelWidth -g pixelHeight "$bigdir/optimized/big.webp" 2>/dev/null | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w" "h}')"
  longest="$(printf '%s\n' $dims | sort -n | tail -1)"
  if [ "${longest:-9999}" -le 400 ] 2>/dev/null; then echo "ok  : max-dim caps longest edge ($dims)"; else echo "FAIL: max-dim not applied ($dims)"; fail=1; fi
fi

# --- re-run does not re-ingest its own optimized/ output --------------------------------
rerundir="$TMP/rerun"; mkdir -p "$rerundir"; cp "$logo" "$rerundir/a.png"
bash "$SCRIPT" "$rerundir" >/dev/null 2>&1
n2="$(bash "$SCRIPT" "$rerundir" 2>/dev/null | grep -c 'optimized/' || true)"
[ "$n2" -eq 0 ] && echo "ok  : re-run prunes the output dir" || { echo "FAIL: re-run re-ingested optimized/ ($n2 rows)"; fail=1; }

# --- re-run prunes even with a RELATIVE --out resolved from a different cwd --------------
# (regression: a relative --out used to never match find's absolute paths, so the prune
#  silently failed and the second run re-ingested its own output.)
relroot="$TMP/relout"; mkdir -p "$relroot"; cp "$logo" "$relroot/a.png"
( cd "$TMP" && bash "$SCRIPT" "relout" --out "relout/opt" >/dev/null 2>&1 )
n3="$( cd "$TMP" && bash "$SCRIPT" "relout" --out "relout/opt" 2>/dev/null | grep -c 'opt/' || true )"
[ "$n3" -eq 0 ] && echo "ok  : re-run prunes a relative --out" || { echo "FAIL: relative --out re-ingested ($n3 rows)"; fail=1; }

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
