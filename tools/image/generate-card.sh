#!/usr/bin/env bash
# tools/image/generate-card.sh — centralized thumbnail card generator
#
# Queries ImageKit for reference cards, downloads them, computes the next
# sequence number (for --prefix), generates a new card via gen-image.sh,
# converts to webp, and uploads to ImageKit.
#
# Usage:
#   generate-card.sh --folder <ik-folder> --prompt "<subject>" \
#     (--prefix <guide> | --name <slug.webp>) \
#     [--size <WxH>] [--refs <n>] [--no-upload]
#
# --prefix guide    → auto-numbers: guide-06.webp (next after existing guide-*.webp)
# --name  slug.webp → uses that exact filename (toolkit, news use this)
# --size  1536x1024 → passed to gen-image.sh via GENIMG_SIZE (default: 1024x1024)
# --refs  3         → number of reference images to download (default: 3)
# --no-upload       → generate + convert but skip ImageKit upload (for local testing)
#
# Prints JSON on stdout:
#   {"ok":true,"file":"/tmp/…/name.webp","name":"name.webp","folder":"guides","url":"…"}
# or, for --prefix runs:
#   {"ok":true,"file":"…","name":"guide-06.webp","folder":"guides","url":"…","next":"06"}
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
IK="$PLUGIN_ROOT/tools/imagekit/imagekit.mjs"
TOWEBP="$PLUGIN_ROOT/tools/image/to-webp.sh"

# Shared deterministic primitives (ct_next_index for --prefix numbering)
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/tools/content/content-lib.sh"

# Locate gen-image.sh through the same resolver used by lifecycle launchers.
RESOLVER="$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh"
GENIMG_SKILL_DIR="$(bash "$RESOLVER" gen-image scripts/gen-image.sh)"

# ── parse args ──────────────────────────────────────────────────────────────
FOLDER=""
PROMPT=""
PREFIX=""
NAME=""
SIZE="1024x1024"
REFS_COUNT=3
UPLOAD=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --folder)    [[ $# -gt 1 ]] || { printf '{"ok":false,"error":"--folder requires a value"}\n' >&2; exit 1; };    FOLDER="$2";      shift 2 ;;
    --prompt)    [[ $# -gt 1 ]] || { printf '{"ok":false,"error":"--prompt requires a value"}\n' >&2; exit 1; };    PROMPT="$2";      shift 2 ;;
    --prefix)    [[ $# -gt 1 ]] || { printf '{"ok":false,"error":"--prefix requires a value"}\n' >&2; exit 1; };    PREFIX="$2";      shift 2 ;;
    --name)      [[ $# -gt 1 ]] || { printf '{"ok":false,"error":"--name requires a value"}\n' >&2; exit 1; };      NAME="$2";        shift 2 ;;
    --size)      [[ $# -gt 1 ]] || { printf '{"ok":false,"error":"--size requires a value"}\n' >&2; exit 1; };      SIZE="$2";        shift 2 ;;
    --refs)      [[ $# -gt 1 ]] || { printf '{"ok":false,"error":"--refs requires a value"}\n' >&2; exit 1; };      REFS_COUNT="$2";  shift 2 ;;
    --no-upload) UPLOAD=false;     shift   ;;
    *) printf '{"ok":false,"error":"unknown argument: %s"}\n' "$1" >&2; exit 1 ;;
  esac
done

[[ -n "$FOLDER" ]] || { printf '{"ok":false,"error":"--folder is required"}\n' >&2; exit 1; }
[[ -n "$PROMPT" ]] || { printf '{"ok":false,"error":"--prompt is required"}\n' >&2; exit 1; }
[[ -n "$PREFIX" || -n "$NAME" ]] \
  || { printf '{"ok":false,"error":"--prefix or --name is required"}\n' >&2; exit 1; }
[[ -z "$PREFIX" || -z "$NAME" ]] \
  || { printf '{"ok":false,"error":"--prefix and --name are mutually exclusive"}\n' >&2; exit 1; }
if [[ -n "$NAME" ]]; then
  [[ "$NAME" != */* ]] || { printf '{"ok":false,"error":"--name must be a filename, not a path"}\n' >&2; exit 1; }
  [[ "$NAME" == *.webp ]] || { printf '{"ok":false,"error":"--name must end in .webp"}\n' >&2; exit 1; }
fi

set -a; source ~/.env 2>/dev/null || true; set +a

# ── 1. download reference images ────────────────────────────────────────────
REFS_DIR="$(mktemp -d /tmp/card-refs-XXXXXX)"
trap 'rm -rf "$REFS_DIR"' EXIT

node "$IK" list --path "$FOLDER" --sort DESC_CREATED --limit "$REFS_COUNT" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
for f in data:
    if f.get('type') == 'file':
        print(f['url'].split('?')[0], f['name'])
" | while read -r url fname; do
    curl -sf -o "$REFS_DIR/$fname" "$url" || true
  done

# ── 2. compute next sequence number (--prefix path) ─────────────────────────
NEXT=""
if [[ -n "$PREFIX" ]]; then
  NEXT=$(node "$IK" list --path "$FOLDER" --sort DESC_CREATED --limit 50 | \
    python3 -c "
import sys, json
for f in json.load(sys.stdin):
    if f.get('type') == 'file':
        print(f['name'])
" | ct_next_index "$PREFIX" ".webp")
  NAME="${PREFIX}-${NEXT}.webp"
fi

# ── 3. generate image ────────────────────────────────────────────────────────
WORK_DIR="$(mktemp -d /tmp/generate-card-XXXXXX)"
OUT_PNG="$WORK_DIR/card.png"

# The style-diversity note is baked in so every caller gets it automatically.
FULL_PROMPT="${PROMPT} — similar but visually distinct from the reference images; create a new composition with the same illustration style, palette, and mood"

GENIMG_SIZE="$SIZE" bash "$GENIMG_SKILL_DIR/scripts/gen-image.sh" \
  "$REFS_DIR" "$FULL_PROMPT" "$OUT_PNG" >&2

# ── 4. convert to webp ───────────────────────────────────────────────────────
OUT_WEBP="$WORK_DIR/$NAME"
bash "$TOWEBP" "$OUT_PNG" "$OUT_WEBP" >&2

# ── 5. upload ────────────────────────────────────────────────────────────────
if $UPLOAD; then
  node "$IK" upload "$OUT_WEBP" --name "$NAME" --folder "$FOLDER" >&2
fi

URL="https://ik.imagekit.io/facilitron/${FOLDER}/${NAME}"

if [[ -n "$NEXT" ]]; then
  printf '{"ok":true,"file":"%s","name":"%s","folder":"%s","url":"%s","next":"%s"}\n' \
    "$OUT_WEBP" "$NAME" "$FOLDER" "$URL" "$NEXT"
else
  printf '{"ok":true,"file":"%s","name":"%s","folder":"%s","url":"%s"}\n' \
    "$OUT_WEBP" "$NAME" "$FOLDER" "$URL"
fi
