#!/usr/bin/env bash
# Smoke test for optimize-images.sh. Fully hermetic: the PNG fixture is embedded below as
# base64 (a 48x48 noisy-gradient truecolor PNG, chosen so pngquant reliably shrinks it and
# never exits 99), so a fresh checkout needs no bundled sample image, no other plugin, and
# no network. Uses the REAL pngquant/cwebp (fast on tiny inputs); the same-format JPEG path
# is checked for graceful degradation when jpegoptim is absent. Image ops (JPEG creation,
# resizing, dimension reads) prefer ImageMagick (magick/convert/identify) and fall back to
# macOS sips; when neither exists those specific assertions skip with a message.
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

# --- portable image helpers: prefer ImageMagick, fall back to macOS sips ------------------
IM=""
if need magick; then IM="magick"; elif need convert; then IM="convert"; fi
IDENT=""
if need magick; then IDENT="magick identify"; elif need identify; then IDENT="identify"; fi
png_to_jpeg() { # <in.png> <out.jpg>; rc 1 when no converter is available
  if [ -n "$IM" ]; then $IM "$1" "$2" 2>/dev/null
  elif need sips; then sips -s format jpeg "$1" --out "$2" >/dev/null 2>&1
  else return 1; fi
}
upscale_png() { # <in.png> <out.png> <edge-px>; rc 1 when no resizer is available
  if [ -n "$IM" ]; then $IM "$1" -resize "${3}x${3}!" "$2" 2>/dev/null
  elif need sips; then sips -z "$3" "$3" "$1" --out "$2" >/dev/null 2>&1
  else return 1; fi
}
img_wh() { # <file> -> "W H" (empty when no reader is available)
  if [ -n "$IDENT" ]; then $IDENT -format '%w %h' "$1" 2>/dev/null
  elif need sips; then sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{if(w&&h)print w" "h}'
  fi
}

# --- CCAL-2092: rows=() must expand safely when empty under set -u ----------------------
# The savings-table `rows` stays an empty array whenever every input is skipped (no gain) —
# an unguarded "${rows[@]}" expansion there throws "unbound variable" on macOS system bash 3.2
# (bash < 4.4). (do_cwebp's `resize` array has the identical unguarded-empty-array shape but
# always runs inside the per-file `xargs -P ... bash -c` worker, which does NOT inherit this
# script's `set -u` — so it's hardened defensively but isn't reachable as a live crash today.)
# Runs on its own tiny fixture, ahead of the base64-embedded one below, so it isn't gated on
# that fixture's tooling. Explicitly invokes /bin/bash (macOS system bash) since the smoke
# test's own `bash "$SCRIPT"` calls elsewhere may resolve a newer Homebrew bash on PATH.
if [ -n "$IM" ]; then
  ccaldir="$TMP/ccal2092"; mkdir -p "$ccaldir"
  tiny="$ccaldir/tiny.png"
  $IM -size 8x8 xc:red "$tiny" 2>/dev/null
  # Pre-quantize once so the second pass below is a guaranteed no-gain (rc=0, n>=o) skip —
  # i.e. every file is skipped and `rows` never gets an element.
  pngquant --quality=65-80 --speed 1 --strip --force --output "$ccaldir/nogain.png" "$tiny" >/dev/null 2>&1

  rc=0; out="$(/bin/bash "$SCRIPT" "$ccaldir/nogain.png" --mode same-format 2>&1)" || rc=$?
  if printf '%s' "$out" | grep -q 'unbound variable'; then
    echo "FAIL: CCAL-2092 rows=() — unbound variable under bash 3.2 (all files skipped)"; fail=1
  elif [ "$rc" -ne 0 ]; then
    echo "FAIL: CCAL-2092 rows=() — script exited $rc: $out"; fail=1
  else
    echo "ok  : CCAL-2092 rows=() expands safely under set -u when every file is skipped"
  fi
else
  echo "SKIP: CCAL-2092 rows=() check — no ImageMagick to build the fixture"
fi

# --- embedded PNG fixture (48x48 RGB gradient + noise, ~7 KB) -----------------------------
cat > "$TMP/fixture.b64" <<'B64'
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
B64
# decode: GNU/base64 -d first, then BSD/macOS base64 -D
logo="$TMP/fixture.png"
base64 -d "$TMP/fixture.b64" > "$logo" 2>/dev/null || base64 -D "$TMP/fixture.b64" > "$logo" 2>/dev/null
[ -s "$logo" ] || { echo "FAIL: could not decode the embedded PNG fixture"; exit 1; }

# fixture tree: a PNG + a JPEG + a WebP, plus a nested file to prove structure mirroring
src="$TMP/src"; mkdir -p "$src/sub"
cp "$logo" "$src/logo.png"
cwebp -quiet -q 95 "$src/logo.png" -o "$TMP/tmp.webp" >/dev/null 2>&1
if png_to_jpeg "$src/logo.png" "$src/photo.jpg"; then
  :
else
  echo "note: no ImageMagick or sips — skipping JPEG-specific assertions" >&2
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
bigdir="$TMP/big"; mkdir -p "$bigdir"
if upscale_png "$logo" "$bigdir/big.png" 1000; then
  bash "$SCRIPT" "$bigdir" --mode to-webp --max-dim 400 >/dev/null 2>&1
  dims="$(img_wh "$bigdir/optimized/big.webp")"
  longest="$(printf '%s\n' $dims | sort -n | tail -1)"
  if [ "${longest:-9999}" -le 400 ] 2>/dev/null; then echo "ok  : max-dim caps longest edge ($dims)"; else echo "FAIL: max-dim not applied ($dims)"; fail=1; fi
else
  echo "SKIP: max-dim assertion — no ImageMagick or sips to build/measure the upscaled fixture"
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
