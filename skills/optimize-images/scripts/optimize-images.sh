#!/usr/bin/env bash
# optimize-images: the DETERMINISTIC core of tron:optimize-images. Compresses PNG, JPEG,
# and WebP in one pass, picking the right tool per format, and prints one unified savings
# table. The runner invokes THIS with a target instead of hand-typing per-format commands.
#
# Tools (probed at runtime; a missing one degrades gracefully with an install hint):
#   PNG  -> pngquant
#   JPEG -> cwebp (transcode to .webp, default)  OR  jpegoptim (--same-format)
#   WebP -> cwebp (re-encode)
#
# Usage:
#   optimize-images.sh <dir|file|glob> [--mode default|to-webp|same-format]
#                                      [--quality RANGE] [--out DIR]
#     default      : PNG->pngquant(.png) · JPEG->cwebp(.webp) · WebP->cwebp(.webp)
#                    (regression-safe: PNGs behave exactly like the old PNG-only skill)
#     to-webp      : convert EVERYTHING to .webp at -q 80 (best savings for photos)
#     same-format  : keep each file's extension (PNG->pngquant, JPEG->jpegoptim, WebP->cwebp)
#     --quality    : pngquant range (default 65-80). cwebp uses the high end as its -q.
#     --out        : output dir (default: <source-dir>/optimized, mirroring structure)
#     --max-dim N  : cap the longest edge of WebP output at N px (default 2000, web-ready;
#                    0 disables). Only affects the cwebp path; PNGs keep their dimensions.
#     --jobs N     : parallel workers (default: CPU count, capped at 8).
#
# Files that don't get smaller are KEPT AS THE ORIGINAL and reported as skipped (never a
# negative-savings row). A re-run skips its own previous output dir.
# Prints a markdown savings table on stdout; narration on stderr. The runner relays it.
set -euo pipefail

log() { echo "optimize-images: $*" >&2; }

TARGET="${1:?usage: optimize-images.sh <dir|file|glob> [--mode …] [--quality RANGE] [--out DIR] [--max-dim N] [--jobs N]}"
shift || true

MODE="default"
QRANGE="65-80"
OUT=""
MAXDIM="2000"   # web longest-edge cap for WebP output; 0 disables (matches tools/image/to-webp.sh)
JOBS=""         # parallel workers; default = CPU count (capped 8)
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)    MODE="${2:?--mode needs a value}"; shift ;;
    --quality) QRANGE="${2:?--quality needs a range}"; shift ;;
    --out)     OUT="${2:?--out needs a dir}"; shift ;;
    --max-dim) MAXDIM="${2:?--max-dim needs a number}"; shift ;;
    --jobs)    JOBS="${2:?--jobs needs a number}"; shift ;;
    *) log "ignoring unknown arg: $1" ;;
  esac
  shift
done
[ "$MAXDIM" -ge 0 ] 2>/dev/null || MAXDIM=2000
if [ -z "$JOBS" ]; then JOBS="$( (sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4) )"; fi
[ "$JOBS" -ge 1 ] 2>/dev/null || JOBS=4
[ "$JOBS" -le 8 ] || JOBS=8
case "$MODE" in default|to-webp|same-format) ;; *) log "bad --mode '$MODE'"; exit 2 ;; esac
# cwebp -q is a single number: take the high end of the pngquant-style range.
WEBP_Q="${QRANGE##*-}"; [ "$WEBP_Q" -ge 1 ] 2>/dev/null || WEBP_Q=80

# --- probe tools ------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }
HAVE_PNGQUANT=0; have pngquant && HAVE_PNGQUANT=1
HAVE_CWEBP=0;    have cwebp    && HAVE_CWEBP=1
HAVE_JPEGOPTIM=0;have jpegoptim&& HAVE_JPEGOPTIM=1

# --- resolve SRCROOT + OUT first, so the find can prune the output dir -------------------
SRCROOT=""
if [ -d "$TARGET" ]; then SRCROOT="${TARGET%/}"
elif [ -f "$TARGET" ]; then SRCROOT="$(dirname "$TARGET")"
else SRCROOT="$(dirname "$TARGET")"; fi
# Absolutize SRCROOT (when it exists) so the dir-mode `find` below emits absolute paths and the
# `-path "$OUT"` prune can string-match them. Without this, a relative --out never prunes and a
# re-run re-ingests its own output.
[ -d "$SRCROOT" ] && SRCROOT="$(cd "$SRCROOT" && pwd)"
# Default OUT lives under SRCROOT (now absolute); a user-supplied relative --out is resolved
# against cwd so it, too, is absolute and comparable to find's output.
if [ -n "$OUT" ]; then
  case "$OUT" in /*) : ;; *) OUT="$(pwd)/$OUT" ;; esac
else
  OUT="$SRCROOT/optimized"
fi
OUT="${OUT%/}"

# --- resolve input files ----------------------------------------------------------------
files=()
if [ -d "$TARGET" ]; then
  # Prune the output dir so a re-run doesn't re-optimize its own previous output.
  while IFS= read -r f; do files+=("$f"); done < <(
    find "$SRCROOT" -type d -path "$OUT" -prune -o \
      -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print | sort
  )
elif [ -f "$TARGET" ]; then
  files+=("$TARGET")
else
  shopt -s nullglob
  for f in $TARGET; do [ -f "$f" ] && files+=("$f"); done
  shopt -u nullglob
fi
[ "${#files[@]}" -gt 0 ] || { log "no png/jpg/jpeg/webp files found at: $TARGET"; exit 2; }

mkdir -p "$OUT"
log "found ${#files[@]} image(s); mode=$MODE; out=$OUT"

fsize() { wc -c < "$1" | tr -d ' '; }
pct() { # <orig> <new> -> "NN%"  (only called when n < o, so always non-negative)
  local o="$1" n="$2"
  [ "$o" -gt 0 ] 2>/dev/null || { echo "0%"; return; }
  echo "$(( (o - n) * 100 / o ))%"
}
relpath() { # path relative to SRCROOT (best-effort)
  case "$1" in "$SRCROOT"/*) printf '%s' "${1#"$SRCROOT"/}";; *) basename "$1";; esac
}
ext_lc() { printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]'; }
img_dims() { # <file> -> "W H" — prefers ImageMagick (magick/identify), falls back to macOS sips; empty if neither
  if command -v magick >/dev/null 2>&1; then
    magick identify -format '%w %h' "$1" 2>/dev/null
  elif command -v identify >/dev/null 2>&1; then
    identify -format '%w %h' "$1" 2>/dev/null
  elif command -v sips >/dev/null 2>&1; then
    sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null \
      | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{if(w&&h)print w" "h}'
  fi
}

do_pngquant() { # <in> <out.png>
  [ "$HAVE_PNGQUANT" -eq 0 ] && return 90
  if pngquant --quality="$QRANGE" --speed 1 --strip --force --output "$2" "$1" 2>/dev/null; then
    return 0
  else
    local rc=$?
    if [ "$rc" -eq 99 ]; then cp "$1" "$2"; return 99; fi  # already optimized: keep a copy
    return "$rc"
  fi
}
do_cwebp() { # <in> <out.webp> — applies the web longest-edge cap (MAXDIM) when known
  [ "$HAVE_CWEBP" -eq 0 ] && return 90
  local resize=()
  if [ "$MAXDIM" -gt 0 ]; then
    local dims w h; dims="$(img_dims "$1")"; w="${dims% *}"; h="${dims#* }"
    if [ -n "$dims" ]; then
      if [ "$w" -ge "$h" ] && [ "$w" -gt "$MAXDIM" ]; then resize=(-resize "$MAXDIM" 0)
      elif [ "$h" -gt "$w" ] && [ "$h" -gt "$MAXDIM" ]; then resize=(-resize 0 "$MAXDIM"); fi
    fi
  fi
  cwebp -quiet -q "$WEBP_Q" "${resize[@]}" "$1" -o "$2" 2>/dev/null
}
do_jpegoptim() { # <in> <out.jpg> — --stdout avoids the --dest basename-collision dance
  [ "$HAVE_JPEGOPTIM" -eq 0 ] && return 90
  jpegoptim -m85 --strip-all --stdout "$1" > "$2" 2>/dev/null || return $?
}

# Worker: optimize ONE file, writing a single record to a per-file file under $WORKDIR.
# Delimiter is the ASCII Unit Separator (\x1f): unlike '|' it can't appear in a filename,
# and unlike TAB it is NOT IFS-whitespace, so empty fields (e.g. the blank "new" on a skip)
# don't collapse on read-back.
# Record: status<US>rel<US>infmt<US>outfmt<US>orig<US>new<US>note
US=$'\037'
process_one() {
  local in="$1"
  local rel ext o outfmt tool rel_noext outpath rc n
  rel="$(relpath "$in")"; ext="$(ext_lc "$in")"; o="$(fsize "$in")"
  outfmt="$ext"; tool=""
  case "$MODE" in
    to-webp) outfmt="webp"; tool="cwebp" ;;
    same-format)
      case "$ext" in png) tool="pngquant" ;; jpg|jpeg) tool="jpegoptim"; outfmt="$ext" ;; webp) tool="cwebp" ;; esac ;;
    default)
      case "$ext" in png) tool="pngquant"; outfmt="png" ;; jpg|jpeg) tool="cwebp"; outfmt="webp" ;; webp) tool="cwebp"; outfmt="webp" ;; esac ;;
  esac
  rel_noext="${rel%.*}"; outpath="$OUT/${rel_noext}.${outfmt}"
  mkdir -p "$(dirname "$outpath")"

  rc=0
  case "$tool" in
    pngquant)  do_pngquant  "$in" "$outpath" || rc=$? ;;
    cwebp)     do_cwebp     "$in" "$outpath" || rc=$? ;;
    jpegoptim) do_jpegoptim "$in" "$outpath" || rc=$? ;;
    *) rc=91 ;;
  esac

  local recf; recf="$WORKDIR/$(printf '%s' "$in" | cksum | tr -d ' ').rec"
  emit() { printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "$1" "$US" "$rel" "$US" "$ext" "$US" "$outfmt" "$US" "$o" "$US" "${2:-}" "$US" "${3:-}" >> "$recf"; }

  case "$rc" in
    0)
      n="$(fsize "$outpath")"
      # No-gain guard (#7): if optimization didn't shrink the file, keep the ORIGINAL (don't
      # ship a bigger file) and report it as skipped rather than showing negative savings.
      if [ "$n" -ge "$o" ]; then
        rm -f "$outpath"
        local keep="$OUT/$rel"; mkdir -p "$(dirname "$keep")"; cp "$in" "$keep"
        emit skip "" "no gain (kept original)"
      else
        emit ok "$n"
      fi ;;
    99) emit skip "" "already optimized (kept original)" ;;
    90)
      local hint="install the missing tool"
      [ "$tool" = "cwebp" ]     && hint="brew install webp"
      [ "$tool" = "jpegoptim" ] && hint="brew install jpegoptim"
      [ "$tool" = "pngquant" ]  && hint="brew install pngquant"
      emit skip "" "$tool not installed — $hint" ;;
    *) emit skip "" "$tool failed (rc=$rc)" ;;
  esac
}

# --- run the workers in parallel --------------------------------------------------------
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/optimg.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
export MODE QRANGE WEBP_Q MAXDIM OUT SRCROOT WORKDIR US HAVE_PNGQUANT HAVE_CWEBP HAVE_JPEGOPTIM
export -f process_one do_pngquant do_cwebp do_jpegoptim img_dims relpath ext_lc fsize
log "optimizing with $JOBS parallel worker(s)…"
printf '%s\0' "${files[@]}" | xargs -0 -P "$JOBS" -I{} bash -c 'process_one "$1"' _ {}

# --- aggregate the per-file records (serial, order-stable by rel) ------------------------
rows=(); skipped=(); tot_o=0; tot_n=0
while IFS="$US" read -r status rel infmt outfmt o n note; do
  [ -n "$status" ] || continue
  if [ "$status" = "ok" ]; then
    rows+=("$rel$US$infmt$US$outfmt$US$o$US$n")
    tot_o=$((tot_o + o)); tot_n=$((tot_n + n))
  else
    skipped+=("$rel$US$note")
  fi
done < <(cat "$WORKDIR"/*.rec 2>/dev/null | sort -t"$US" -k2,2)

# --- emit the unified savings table -----------------------------------------------------
{
  echo "| File | Format | Output | Original | Optimized | Savings |"
  echo "|------|--------|--------|---------:|----------:|--------:|"
  for r in "${rows[@]}"; do
    IFS="$US" read -r name infmt outfmt o n <<< "$r"
    # escape any literal '|' in the filename so it can't break the markdown table
    printf '| %s | %s | %s | %s B | %s B | %s |\n' "${name//|/\\|}" "$infmt" "$outfmt" "$o" "$n" "$(pct "$o" "$n")"
  done
  if [ "$tot_o" -gt 0 ]; then
    printf '| **Total (%d files)** | | | %s B | %s B | %s |\n' "${#rows[@]}" "$tot_o" "$tot_n" "$(pct "$tot_o" "$tot_n")"
  fi
  if [ "${#skipped[@]}" -gt 0 ]; then
    echo
    echo "**Skipped:**"
    for s in "${skipped[@]}"; do
      IFS="$US" read -r name reason <<< "$s"
      echo "- \`$name\` — $reason"
    done
  fi
  echo
  echo "_Output: ${OUT}_"
}

log "done: ${#rows[@]} optimized, ${#skipped[@]} skipped."
