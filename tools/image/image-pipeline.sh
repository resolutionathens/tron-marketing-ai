#!/usr/bin/env bash
# tools/image/image-pipeline.sh — batch convert images to webp and upload to ImageKit
#
# Usage:
#   image-pipeline.sh --src <dir> --dest <ik-folder> [--pattern <glob>]
#
# Flags:
#   --src     Directory containing source images (searched at depth 1)
#   --dest    ImageKit folder to upload into (e.g. blog-posts/my-article)
#   --pattern File glob for find -name (default: *.png/jpg/jpeg/gif/webp/avif, case-insensitive)
#
# Output (stdout):  JSON object mapping output filename → ImageKit CDN URL
#                   { "section-intro.webp": "https://ik.imagekit.io/facilitron/…", … }
# Progress (stderr): per-file ✓/✗ lines
#
# Every file is converted to WebP (quality 82, longest edge ≤2000px) via to-webp.sh,
# then uploaded with useUniqueFileName=false and overwriteFile=true so names land exactly.
# Files are processed in parallel; any failure exits nonzero and reports on stderr.
#
# Requires: bun (for to-webp.sh), node + cloudflared (for imagekit.mjs), python3

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

SRC="" DEST="" PATTERN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)     [[ $# -gt 1 ]] || { echo "image-pipeline: --src requires a value" >&2; exit 2; };     SRC="$2";     shift 2 ;;
    --dest)    [[ $# -gt 1 ]] || { echo "image-pipeline: --dest requires a value" >&2; exit 2; };    DEST="$2";    shift 2 ;;
    --pattern) [[ $# -gt 1 ]] || { echo "image-pipeline: --pattern requires a value" >&2; exit 2; }; PATTERN="$2"; shift 2 ;;
    *) echo "image-pipeline: unknown flag: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$SRC"  ]] || { echo "image-pipeline: --src is required" >&2; exit 2; }
[[ -n "$DEST" ]] || { echo "image-pipeline: --dest is required" >&2; exit 2; }
[[ -d "$SRC"  ]] || { echo "image-pipeline: not a directory: $SRC" >&2; exit 1; }

# ── Resolve bundled tool paths ────────────────────────────────────────────────

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$SELF_DIR/../..}"
TOWEBP="$PLUGIN_ROOT/tools/image/to-webp.sh"
IK="$PLUGIN_ROOT/tools/imagekit/imagekit.mjs"

[[ -f "$TOWEBP" ]] || { echo "image-pipeline: to-webp.sh not found: $TOWEBP" >&2; exit 1; }
[[ -f "$IK"     ]] || { echo "image-pipeline: imagekit.mjs not found: $IK"    >&2; exit 1; }

# ── Collect source files ──────────────────────────────────────────────────────

declare -a FIND_ARGS=("$SRC" -maxdepth 1 -type f)
if [[ -n "$PATTERN" ]]; then
  FIND_ARGS+=(-iname "$PATTERN")
else
  FIND_ARGS+=(
    \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg"
       -o -iname "*.gif" -o -iname "*.webp" -o -iname "*.avif" \)
  )
fi

FILES=()
while IFS= read -r line; do
  FILES+=("$line")
done < <(find "${FIND_ARGS[@]}" | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "{}"
  exit 0
fi

# Fail fast on duplicate output stems (e.g. hero.png + hero.jpg both become hero.webp).
_DUP="$(for f in "${FILES[@]}"; do basename "${f%.*}".webp; done | sort | uniq -d | head -1)"
if [[ -n "$_DUP" ]]; then
  echo "image-pipeline: duplicate output name '$_DUP' — rename source files to avoid collision" >&2; exit 1
fi
unset _DUP

# ── Process files in parallel ─────────────────────────────────────────────────

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

declare -a PIDS=()

for FILE in "${FILES[@]}"; do
  BASENAME="$(basename "$FILE")"
  STEM="${BASENAME%.*}"
  WEBP_NAME="${STEM}.webp"
  WEBP_PATH="$WORK/$WEBP_NAME"
  RESULT_FILE="$WORK/${WEBP_NAME}.result"

  (
    bash "$TOWEBP" "$FILE" "$WEBP_PATH" >/dev/null \
      || { echo "image-pipeline: ✗ convert failed: $BASENAME" >&2; exit 1; }

    UPLOAD="$(node "$IK" upload "$WEBP_PATH" --name "$WEBP_NAME" --folder "$DEST")" \
      || { echo "image-pipeline: ✗ upload failed: $WEBP_NAME" >&2; exit 1; }

    URL="$(printf '%s' "$UPLOAD" \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")" \
      || { echo "image-pipeline: ✗ could not parse url: $WEBP_NAME" >&2; exit 1; }

    printf '%s\t%s\n' "$WEBP_NAME" "$URL" > "$RESULT_FILE"
    echo "image-pipeline: ✓ $WEBP_NAME → $URL" >&2
  ) &
  PIDS+=($!)
done

FAILED=0
for PID in "${PIDS[@]}"; do
  wait "$PID" || FAILED=1
done

[[ $FAILED -eq 0 ]] || { echo "image-pipeline: one or more files failed" >&2; exit 1; }

# ── Assemble JSON output ──────────────────────────────────────────────────────

python3 - "$WORK" <<'PYEOF'
import sys, os, json
results = {}
for fname in sorted(os.listdir(sys.argv[1])):
    if fname.endswith('.result'):
        with open(os.path.join(sys.argv[1], fname)) as fh:
            line = fh.read().strip()
        if '\t' in line:
            name, url = line.split('\t', 1)
            results[name] = url
print(json.dumps(results, indent=2))
PYEOF
