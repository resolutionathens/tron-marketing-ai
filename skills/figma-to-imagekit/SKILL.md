---
name: figma-to-imagekit
model: sonnet
effort: medium
fallback:
  cost: medium
  skip_when: "Use tron:figma-to-imagekit only when exporting from Figma to ImageKit. For a single-node re-upload, use the ImageKit CLI directly."
  stage_skips:
    - stage: "0 — Check connection"
      skip_when: "Connection was already verified earlier in the same session"
    - stage: "Resize/optimize"
      skip_when: "Images are already webp at the correct size"
description: "Export images from Figma designs and upload them to ImageKit CDN. Use this skill when the user wants to export assets from Figma, upload design images to ImageKit, move illustrations from Figma to production, or says things like 'grab that image from Figma', 'export and upload', 'get the images from the design', 'upload to ImageKit from Figma', or 'pull assets from Figma'."
allowed-tools:
  - Bash
  - Read
  - Write
scout:
  surface: developer
  effects: [cdn]
  inputs:
    - key: figmaUrl
      label: "Figma URL"
      type: text
      required: true
      placeholder: "Figma file or frame URL to export"
---

# Figma to ImageKit Export Pipeline

Export design assets from Figma, optimize with pngquant, upload to ImageKit.

## Requirements

- `cloudflared` (broker auth), `pngquant` (local), ImageKit CLI at `tools/imagekit/imagekit.mjs`
- **Figma MCP plugin** (primary path, no token) **or** the org-secret broker's `/figma/*` proxy (REST fallback — no local `FIGMA_ACCESS_TOKEN` needed)

## Fast path (scripted — per-node pipeline)

The download → resize → optimize → upload leg is deterministic. Your judgment is node discovery, naming, and resize target.

```bash
name=figma-to-imagekit
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/figma-export.sh" ] || SKILL_DIR="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 5 -type d -path "*/skills/$name" 2>/dev/null | while read -r d; do [ -e "$d/scripts/figma-export.sh" ] && echo "$d"; done | sort -V | tail -1 || true)"
[ -e "$SKILL_DIR/scripts/figma-export.sh" ] || { echo "tron:$name: scripts/figma-export.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }

# Parse Figma URL → fileKey + nodeId
bash "$SKILL_DIR/scripts/figma-export.sh" parse-url "<figma-design-url>"

# Once per session: is the caller connected to their own Figma account?
bash "$SKILL_DIR/scripts/figma-export.sh" oauth-status

# Per-node pipeline (download → sips resize → pngquant → ImageKit upload)
bash "$SKILL_DIR/scripts/figma-export.sh" run \
  --url "<asset-url>" --name hero.png \
  --folder product/works/main [--resize 1280] [--quality 65-80] [--overwrite]
```

```json
{"ok":true,"name":"hero.png","original":5359283,"optimized":155937,"savings":"97%","path":"product/works/main/hero.png","url":"https://ik…","uploaded":true}
```

`--file <path>` for already-downloaded sources. `--no-upload` to stop after optimizing. Rejects non-PNG sources — for jpg/svg use the format options below.

**For multi-node exports (common case), fan out to Haiku subagents** — one per node, each runs the `run` command with `{url, name, folder, resize}`. The orchestrator handles node discovery (judgment). Don't fan out a single-image export.

## 0. Check the connection (once per session)

The broker proxies `/figma/*` under the caller's own Figma OAuth token when they've connected
(MD-1991); an unconnected caller silently falls back to the shared org token and still gets images
— nothing breaks. Run `oauth-status` once at the start of an export session. If it comes back
`"connected":false`, print its `prompt` field to the user as a single line before continuing (don't
block the export on it — the shared-token fallback covers the rest of the run):

```
Not connected to your own Figma account — open https://secrets.facilitron.work/figma/oauth/start to connect it (using the shared org token for now).
```

`"connected":null` (broker/`cloudflared` unreachable, or the local Figma MCP path is being used
instead) means the check couldn't run — say nothing and proceed.

## 1. Identify nodes

From a Figma URL, extract: `https://figma.com/design/:fileKey/:fileName?node-id=:nodeId` (convert `-` to `:` in nodeId). Use the Figma MCP `get_design_context` or `get_metadata` to explore the tree — look for nodes named `NuxtImg`, `Hero/*`, `Interface/*`.

## 2. Get asset URLs

**Primary (MCP, no token):** `get_design_context` on a node returns `img*` constants pointing at `https://www.figma.com/api/mcp/asset/<uuid>`. These are raw 4096×4096 PNGs, short-lived (~7 days), no auth. Download:

```bash
curl -s -o /tmp/hero-raw.png "https://www.figma.com/api/mcp/asset/<uuid>"
```

**Fallback (REST, via the org-secret broker):**
```bash
TOKEN="$(cloudflared access token --app=https://secrets.facilitron.work)"
curl -s -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/figma/v1/images/FILE_KEY?ids=NODE_ID&format=png&scale=2"
```
Returns temporary S3 URLs. For batch, comma-separate node IDs. The broker injects the Figma token server-side — no local `FIGMA_ACCESS_TOKEN` needed.

## 3. Resize + optimize

MCP exports are 4096×4096. Resize with `sips` (macOS built-in), then `pngquant`:

```bash
sips -Z 1280 /tmp/hero-raw.png --out /tmp/hero-1280.png >/dev/null
pngquant --quality=65-80 --speed 1 --strip --output /tmp/optimized/hero.png /tmp/hero-1280.png
```

Resize target: 1280px for 2x retina at 640px display, 1600px for hero images. The script handles this.

## 4. Upload to ImageKit

```bash
IK="${CLAUDE_PLUGIN_ROOT:-$SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"   # $SKILL_DIR from the fast-path resolver above
node "$IK" upload /tmp/optimized/filename.png --folder product/works/main --name filename.png
```

CLI passes `useUniqueFileName: false` and `overwriteFile: true` automatically — no random suffix.

## 5. Report

Show a summary table: Image | Figma Node | Original | Optimized | Savings | ImageKit Path.

## Format options

The Figma API supports `png` (default), `jpg`, `svg`, `pdf`. Scale: `1` (1x), `2` (2x retina — recommended), `4` (4x).

## Cleanup

After uploading, remove duplicates from ImageKit that have random suffixes:
```bash
node "$IK" list --path product/works/main --limit 30
node "$IK" bulk-delete ID1 ID2 ID3
```

## CDN

Base URL: `https://ik.imagekit.io/facilitron/`. In Nuxt components, use the path portion only:
```vue
<SectionFeatureShowcase image="product/works/main/feature-asset-tracking.png" />
```