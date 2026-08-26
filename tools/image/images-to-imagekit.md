# Images → webp → ImageKit (shared mechanics)

The canonical convert-and-upload mechanics retained for plugin media consumers. Destination rules
(folder names, naming scheme, and where the path resolves) belong to the consuming repo. Paths
resolve through the shared plugin tools (`CLAUDE_PLUGIN_ROOT`, falling back two levels up from
`CLAUDE_SKILL_DIR`).

## Contents

- Batch fast path — `image-pipeline.sh`
- Convert to webp (single-file fallback)
- Upload to ImageKit (single-file fallback)
- Verify names landed clean
- Generate an index/card thumbnail from references

## Batch fast path — `image-pipeline.sh`

Consumers can run this for body/card images — it converts every image
in a source directory to webp and uploads the batch in parallel, one command:

```bash
PIPE="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/image-pipeline.sh"
IMAGES=$(bash "$PIPE" --src <source-dir> --dest <ik-folder>)
# stdout: JSON mapping output filename → CDN URL
# {"section-intro.webp": "https://ik.imagekit.io/facilitron/<ik-folder>/section-intro.webp", ...}
```

Each file becomes `<stem>.webp` (name the sources before running), so uploads land with
exact names — no `--name` bookkeeping per file. Use the manual steps below only for a
single file that needs a different output name than its source stem (e.g. a featured/OG
image).

## Convert to webp (single-file fallback)

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

## Upload to ImageKit (single-file fallback)

The ImageKit CLI (bundled at `tools/imagekit/`) always passes `useUniqueFileName: false` and
`overwriteFile: true` on every upload, so filenames keep exactly what `--name` specifies with
no random suffix appended. It authenticates through the cloudflared-backed secrets broker —
no env vars to source (on a broker auth error, run
`cloudflared access login https://secrets.facilitron.work`):

```bash
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"

node "$IK" upload "<out>/<name>.webp" --name <name>.webp --folder <destination-folder>
```

Always pass `--name`. Without it the uploaded asset uses the source filename, which is still
kept exact (no suffix) but may not match what the page template expects.

## Verify names landed clean

After uploading, confirm the names are exactly what the page will request:

```bash
node "$IK" list --path <destination-folder>
```

A `.png`-vs-`.webp` or suffix mismatch between the uploaded asset and the front-matter / `src`
value renders as a broken image, so fix the asset rather than editing the reference to match
a wrong upload.

## Generate an index/card thumbnail from references

The index cards (guides, toolkit) share one consistent illustration style. Use the
shared `generate-card.sh` helper — it fetches reference cards live from ImageKit,
computes the next sequence number if needed, calls `gen-image.sh`, converts to webp,
and uploads, all in one step.

```bash
GENCARD="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/generate-card.sh"
```

**Guides** (sequential `guide-NN.webp` naming — `--prefix` auto-numbers):

```bash
RESULT=$(bash "$GENCARD" \
  --folder guides \
  --prefix guide \
  --prompt "<subject prompt for this guide>" )
# RESULT → {"ok":true,"file":"/tmp/…/guide-06.webp","name":"guide-06.webp","folder":"guides","url":"…","next":"06"}
NAME=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
FILE=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])")
```

**Toolkit** (slug-based naming — `--name` sets the exact filename; landscape cards need `--size`; uses news feature images as style references):

```bash
RESULT=$(bash "$GENCARD" \
  --folder news \
  --name "<slug-temp>.webp" \
  --size 1536x1024 \
  --refs 3 \
  --prompt "<subject prompt for this item>" )
# Move the result from news folder to toolkit folder with final name
# (The prompt automatically applies the style-diversity instruction)
```

The prompt should describe the subject and emphasize Facilitron's abstract geometry
(deep navy, cyan/violet linework, geometric composition). Topic cues may coexist only when
the composition remains strongly abstract and geometric — geometry must be primary, not
secondary. `generate-card.sh` appends the style-diversity instruction automatically
and uses the three most recent news feature images as style references. If card generation
is unavailable, fall back to asking the user for a card image or pulling one from Figma —
but generate-from-references is the default.
