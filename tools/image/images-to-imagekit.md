# Images → webp → ImageKit (shared mechanics)

The canonical convert-and-upload pipeline shared by the content skills
(`tron:news-item`, `tron:guide-item`, `tron:toolkit-item`). Each skill keeps its own
**destination** rules (folder names, naming scheme, where the path resolves in the page);
this file holds the **mechanics** that are identical across all of them, so they don't
drift. Paths resolve through the shared plugin tools (`CLAUDE_PLUGIN_ROOT`, falling back
two levels up from `CLAUDE_SKILL_DIR`).

## Contents

- Convert to webp
- Upload to ImageKit
- Verify names landed clean
- Generate an index/card thumbnail from references

## Convert to webp

Convert every source image with the bundled helper. It uses Bun's built-in `Bun.Image`
(libwebp, zero deps — no ImageMagick or cwebp needed), caps the longest edge at 2000px
without ever upscaling, and re-encodes to WebP at quality 82:

```bash
TOWEBP="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/to-webp.sh"
"$TOWEBP" "<source-path>" "<out>/<name>.webp"
```

Source photos from Confluence are often huge (5000-8000px, several MB) and the site never
displays them above ~700px, so this is both a payload win and keeps ImageKit tidy. If Bun
is ever unavailable, `cwebp -q 82 <source> -o <out>.webp` (Homebrew `webp` package) or
`sips` are acceptable fallbacks — but `to-webp.sh` is the default so every asset is sized
and encoded the same way.

## Upload to ImageKit

The ImageKit CLI (bundled at `tools/imagekit/`) keeps filenames exactly as given when you
pass `--name` — no random suffix — so the uploaded paths are predictable:

```bash
set -a; source ~/.env; set +a
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"

node "$IK" upload "<out>/<name>.webp" --name <name>.webp --folder <destination-folder>
```

Always pass `--name`. Without it, older CLI behavior could append a `_aB3xK`-style suffix
and break the exact-filename lookup the slug pages rely on.

## Verify names landed clean

After uploading, confirm the names are exactly what the page will request:

```bash
node "$IK" list --path <destination-folder>
```

If any file picked up a random suffix anyway, `bulk-delete` the bad ones and re-upload
passing `--name <name>.webp` explicitly. A `.png`-vs-`.webp` or suffix mismatch between the
uploaded asset and the front-matter / `src` value renders as a broken image, so fix the
asset rather than editing the reference to match a wrong upload.

## Generate an index/card thumbnail from references

The index cards (guides, toolkit) share one consistent illustration style. Don't hand-pick
a random image — generate the card with the `tron:gen-image` skill, seeded with the
_existing_ index cards so the new one matches the set's palette, framing, and scale.

```bash
# 1. Find the existing cards + the next free number (adjust folder/prefix per skill)
node "$IK" list --path <index-folder> --limit 50 | grep -oE '<prefix>-?[0-9]+\.webp' | sort -u

# 2. Download a few existing cards as gen-image style references
mkdir -p /tmp/card-refs
for n in 01 02 03 04; do
  curl -s -o "/tmp/card-refs/<prefix>-$n.webp" \
    "https://ik.imagekit.io/facilitron/<index-folder>/<prefix>-$n.webp"
done
```

Then invoke `tron:gen-image` with `/tmp/card-refs` as the reference set and a prompt
describing this item's subject (e.g. "flat editorial illustration of a preventive-
maintenance calendar, school-facility theme"). Convert the result to webp and upload as the
next free number:

```bash
"$TOWEBP" <generated.png> "/tmp/<prefix>-<NN>.webp"
node "$IK" upload "/tmp/<prefix>-<NN>.webp" --name <prefix>-<NN>.webp --folder <index-folder>
```

`<NN>` is the next free index (e.g. `05` if `<prefix>-04.webp` is the highest). If codex
`image_gen` is ever unavailable, fall back to asking the user for a card image or pulling
one from Figma — but generate-from-references is the default; it keeps the index visually
consistent.
