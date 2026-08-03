---
name: figma-inspect
model: sonnet
effort: medium
description: "Inspect a Figma file or linked frame for UI implementation without exporting or uploading assets. Use when a worker needs Figma frame dimensions, auto-layout values, typography, colors, variants, component states, node metadata, or a rendered design reference from a Figma URL. Read-only and separate from figma-to-imagekit."
allowed-tools:
  - Bash
  - Read
scout:
  surface: developer
  effects: [report]
  inputs:
    - key: figmaUrl
      label: "Figma URL"
      type: text
      required: true
      placeholder: "Figma file or frame URL to inspect"
---

# Figma inspection

Read a Figma file or node through the org-secret broker and return the design data needed to implement it. This workflow never mutates a design, exports a local asset, or uploads to ImageKit.

## Fast path

```bash
name=figma-inspect
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | LC_ALL=C sort | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/figma-inspect.mjs)"
node "$SKILL_DIR/scripts/figma-inspect.mjs" inspect "<figma-file-or-node-url>"
```

The command accepts `/design/` and `/file/` URLs. A node link returns the selected node, its implementation-relevant descendants, component and style maps, and a 2x rendered reference URL when Figma can render it. A file link returns the document tree without requesting an image.

## Authentication

The tool mints a short-lived Cloudflare Access token and calls the broker's `/figma/*` routes. The broker applies the caller's connected Figma OAuth identity. If the account is not connected, relay the exact connection URL from the error and stop.

Do not request, read, or suggest a local Figma personal access token. Do not fall back to anonymous Figma requests or the shared-token asset-export behavior. Inspection is explicitly per-user.

## Using the result

Before writing UI code, summarize the selected frame's dimensions, layout direction and spacing, padding, constraints, typography, fills and strokes, effects, component or variant properties, and child hierarchy. Use `renderedReference` for visual comparison when non-null. Preserve uncertainty when a property is absent rather than inferring a design value.

For asset publication, hand off separately to `tron:figma-to-imagekit`. This skill performs no export, optimization, upload, design mutation, git write, or browser interaction.
