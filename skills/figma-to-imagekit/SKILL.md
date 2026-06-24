---
name: figma-to-imagekit
model: sonnet
effort: medium
description: "Export images from Figma designs and upload them to ImageKit CDN. Use this skill when the user wants to export assets from Figma, upload design images to ImageKit, move illustrations from Figma to production, or says things like 'grab that image from Figma', 'export and upload', 'get the images from the design', 'upload to ImageKit from Figma', or 'pull assets from Figma'. Also trigger when the user provides Figma node IDs or URLs and mentions uploading or exporting images."
---

# Figma to ImageKit Export Pipeline

Export design assets from Figma, optimize them with pngquant, and upload to ImageKit CDN in one automated flow.

## Requirements

- `cloudflared` installed (for broker auth via Cloudflare Access tokens)
- `pngquant` installed locally
- ImageKit CLI — bundled in the plugin at `tools/imagekit/imagekit.mjs` (invoked below)
- **Either**: Figma MCP plugin enabled in this session (primary path — no token needed), **or** `FIGMA_ACCESS_TOKEN` env var with `file_content:read` scope (REST fallback for headless/CI runs).

## Subagents & model tiers

A single-node export runs fine inline. **For a multi-node export (the common case —
a whole section's worth of product images), fan out the mechanical leg to one Haiku
subagent per node.** The split:

- **Main thread (Opus, holds the Figma MCP):** identify the nodes, resolve each to a
  raw asset URL (MCP `get_design_context` constants, or the REST `/images` S3 URLs),
  and decide each image's final name, resize target, and ImageKit folder. Naming and
  node discovery are judgment, and the MCP plugin lives in this session.
- **Haiku subagent per node (no MCP needed):** given `{ asset-URL, out-name,
  resize-target, imagekit-folder }`, run download → `sips` resize → `pngquant` →
  ImageKit upload, and return its row for the Step 5 table. This leg is pure Bash
  (curl / sips / pngquant / CLI), independent per node, so the verbose pngquant and
  curl output stays out of the orchestrator's context.

Assemble the Step 5 summary table from the returned rows. Don't fan out a
single-image export — the spawn overhead isn't worth it.

## Fast path (scripted)

The mechanical leg (Steps 2→4: download → `sips` resize → `pngquant` → ImageKit
upload) is bundled as one script — this is exactly what each per-node subagent
runs, given a resolved asset URL and the name/folder/resize you decided:

```bash
# Resolve this skill's bundled dir robustly. $CLAUDE_SKILL_DIR is NOT always exported
# into the agent's Bash (e.g. under the headless worker); never hardcode a version-pinned path.
name=figma-to-imagekit
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
# fall back to the newest INSTALLED copy that actually contains scripts/figma-export.sh
# (skips a stale mirror that lacks it; newest version wins, marketplace breaks ties)
[ -e "$SKILL_DIR/scripts/figma-export.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/figma-export.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/figma-export.sh" ] || { echo "tron:$name: can't find scripts/figma-export.sh — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
# Pure URL parse (Step 1) — fileKey + colon-form nodeId, offline:
bash "$SKILL_DIR/scripts/figma-export.sh" parse-url "<figma-design-url>"

# The per-node pipeline (Steps 2–4), one result row of JSON:
bash "$SKILL_DIR/scripts/figma-export.sh" run \
  --url "<resolved-asset-url>" --name hero.png \
  --folder product/works/main [--resize 1280] [--quality 65-80] [--overwrite]
```

```json
{"ok":true,"name":"hero.png","original":5359283,"optimized":155937,"savings":"97%","path":"product/works/main/hero.png","url":"https://ik…","uploaded":true}
```

`run` accepts `--file <path>` instead of `--url` (already-downloaded source) and
`--no-upload` to stop after optimizing (returns the local savings). It rejects
non-PNG sources up front — for jpg/svg use the format options in the prose below.
Collect each row into the Step 5 table. Smoke it (URL parse + the real
resize/optimize leg, no upload) with `bash "$SKILL_DIR/scripts/test-figma-export.sh"`.
The judgment — node discovery, naming, resize target — stays with the orchestrator;
the prose below is the reference for those decisions and the REST/MCP export paths.

## Workflow

### 1. Identify Figma nodes to export

Get node IDs from Figma URLs or by exploring the design tree. Node IDs look like `1166:3012` or `I1166:3012;1094:1229;1121:284` (instance paths).

**From a Figma URL:**
Extract fileKey and nodeId from `https://figma.com/design/:fileKey/:fileName?node-id=:nodeId` (convert `-` to `:` in nodeId).

**From design exploration:**
Use the Figma MCP `get_design_context` or `get_metadata` tools to find image nodes. Look for nodes named `NuxtImg`, `Hero/*`, `Interface/*`, or image-like frames.

### 2. Export from Figma

**Primary path: MCP asset URLs (no Figma token required).**

When you call `mcp__plugin_figma_figma__get_design_context` on a node that contains images, the response declares the image assets as constants pointing at MCP-hosted URLs:

```js
const imgHero = "https://www.figma.com/api/mcp/asset/741f7c3e-b536-4487-b69c-e14282a0d350";
```

These URLs return raw PNG bytes (4096×4096 at full quality) with `Content-Type: image/png`, no auth header required. They're short-lived (~7 days) but that's fine for a one-shot export. Download with curl:

```bash
curl -s -o /tmp/hero-raw.png "https://www.figma.com/api/mcp/asset/<uuid>"
file /tmp/hero-raw.png   # confirm: PNG image data, NNNN x NNNN
```

If the node is a *frame* (not the image asset itself), call `get_design_context` on the frame and pick the right `img*` constant from the returned code — usually there's only one image per frame, and naming hints (`imgHero`, `imgPlaceholderImage560X490`) help when there are several.

Raw MCP exports are typically 4096×4096 / 10–15 MB. Resize before pngquant — see step 3.

**Fallback: REST API (requires `FIGMA_ACCESS_TOKEN`).**

Use this when the MCP plugin isn't available (headless agents, CI, scripts):

```bash
# Single node
curl -s -H "X-Figma-Token: $FIGMA_ACCESS_TOKEN" \
  "https://api.figma.com/v1/images/FILE_KEY?ids=NODE_ID&format=png&scale=2"

# Multiple nodes (comma-separated, no spaces)
curl -s -H "X-Figma-Token: $FIGMA_ACCESS_TOKEN" \
  "https://api.figma.com/v1/images/FILE_KEY?ids=NODE1,NODE2,NODE3&format=png&scale=2"
```

Response returns temporary S3 URLs:
```json
{
  "err": null,
  "images": {
    "NODE_ID": "https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/..."
  }
}
```

**Batch export pattern** (export + download in one step):
```bash
RESPONSE=$(curl -s -H "X-Figma-Token: $FIGMA_ACCESS_TOKEN" \
  "https://api.figma.com/v1/images/FILE_KEY?ids=NODE_ID&format=png&scale=2")
URL=$(echo "$RESPONSE" | python3 -c "import sys,json; print(list(json.load(sys.stdin)['images'].values())[0])")
curl -s -o /tmp/output.png "$URL"
```

**To find image nodes inside a section via REST:**
```bash
curl -s -H "X-Figma-Token: $FIGMA_ACCESS_TOKEN" \
  "https://api.figma.com/v1/files/FILE_KEY/nodes?ids=NODE_ID&depth=4" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
def find_nodes(node):
    name = node.get('name','')
    nid = node.get('id','')
    ntype = node.get('type','')
    if any(k in name for k in ['NuxtImg', 'Hero', 'Interface', 'mockup', 'illustration']):
        print(f'{nid:45s} {ntype:15s} {name}')
    for child in node.get('children', []):
        find_nodes(child)
for nid, nd in data.get('nodes', {}).items():
    find_nodes(nd.get('document', {}))
"
```

### 3. Resize, then optimize with pngquant

MCP exports come back at 4096×4096 by default — way larger than any marketing-page image needs. Resize first (sips is on every macOS box), then run pngquant:

```bash
mkdir -p /tmp/optimized
sips -Z 1280 /tmp/filename-raw.png --out /tmp/filename-1280.png >/dev/null
pngquant --quality=65-80 --speed 1 --strip --output /tmp/optimized/filename.png /tmp/filename-1280.png
```

Pick the resize target by display size: 1280px for 2x retina at 640px display, 1600px for hero-sized images. A 14 MB raw export typically lands at ~350 KB after this pipeline.

For multiple files:
```bash
for f in /tmp/works-*.png; do
  base=$(basename "$f")
  sips -Z 1280 "$f" --out "/tmp/optimized/_${base}" >/dev/null
  pngquant --quality=65-80 --speed 1 --strip \
    --output "/tmp/optimized/$base" "/tmp/optimized/_${base}" 2>&1
  rm "/tmp/optimized/_${base}"
done
```

### 4. Upload to ImageKit

Upload using the ImageKit CLI. When `--name` is specified, the file will NOT get a random suffix appended.

```bash
node "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs" upload /tmp/optimized/filename.png \
  --folder product/works/main --name filename.png
```

Use `--overwriteFile true` to replace an existing file at the same path.

### 5. Verify and report

After uploading, show a summary:

| Image | Figma Node | Original | Optimized | Savings | ImageKit Path |
|-------|-----------|----------|-----------|---------|---------------|
| hero.png | 3001:8863 | 126 KB | 32 KB | 75% | product/works/main/hero.png |

## Format options

The Figma export API supports these formats via the `format` parameter:
- `png` (default, best for UI mockups and illustrations)
- `jpg` (smaller for photos, no transparency)
- `svg` (vector, good for icons and logos)
- `pdf`

Scale options: `scale=1` (1x), `scale=2` (2x retina, recommended), `scale=4` (4x)

## Cleanup

After uploading, delete any accidentally-suffixed duplicates:
```bash
node "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs" list --path product/works/main --limit 30
node "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs" bulk-delete ID1 ID2 ID3
```

## CDN base URL

All uploaded images are available at: `https://ik.imagekit.io/facilitron/`

In Nuxt components using the ImageKit provider, use the path portion only:
```vue
<SectionFeatureShowcase image="product/works/main/feature-asset-tracking.png" />
```
