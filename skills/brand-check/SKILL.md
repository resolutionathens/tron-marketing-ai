---
name: brand-check
model: sonnet
effort: medium
description: "Audit a design asset or a rendered marketing page against Facilitron brand guidelines — color palette / tron- Tailwind tokens, typography, logo usage and clear-space, and WCAG color contrast. Use when a designer wants to verify brand consistency before handoff, or when a ticket is about color/brand correctness: 'does this match our brand', 'brand check this asset', 'is this on-brand', 'check color contrast'. Works on an image file, a Figma frame, or a live/staging URL. Git-free — reports findings; it does not edit code, branch, or open PRs."
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - WebFetch
  - Skill
scout:
  surface: true
  title: "Check brand consistency"
  blurb: "Audits an asset or design against the brand palette, typography, logo rules, and color contrast."
  when: "Before handing off a design or a post visual."
  category: qa
  effects: [report]
  inputs:
    - key: target
      label: "Asset or page"
      type: text
      required: true
      help: "A URL, a route, or a path to the asset to audit against the brand."
---

# /brand-check — Brand & contrast audit

Check a design asset or rendered page against the Facilitron brand system and report what's off —
**before** it ships or goes to print. Read-only and git-free: it produces a findings report, not edits.

## What it checks

1. **Palette** — colors used vs the Facilitron brand palette / `tron-` Tailwind design tokens.
   Flags off-palette colors and near-misses (close-but-not-exact hexes that should snap to a token).
2. **Typography** — type families/weights vs the brand type system; flags non-brand fonts.
3. **Logo usage** — correct lockup, 1-color vs full-color, not stretched/recolored, and measurable
   clear-space: **≥ the logomark height on all sides** (defer to `knowledge/brand/` in tron-os if it
   specifies a different minimum).
4. **WCAG color contrast** — text/UI contrast ratios against AA (4.5:1 body, 3:1 large/UI). This is
   the same lens as the ADA work — for a _live page_, defer to `/a11y-scan` for the full automated pass.

## Inputs

- **Image asset** (PNG/JPG/SVG) — read the file; sample dominant colors.
- **Figma frame** — use the Figma MCP (`get_variable_defs` for bound tokens, `get_screenshot`,
  `get_design_context`) to read actual styles rather than eyeballing.
- **Live / staging URL** — fetch the page; for a full accessibility/contrast pass run `/a11y-scan`
  against it and fold the contrast findings in here.

## Resolve the brand source of truth

Pull the canonical tokens rather than relying on memory:

- **Brand knowledge** in tron-os: `knowledge/brand/` (palette, type, logo rules) if present.
- **`tron-` Tailwind tokens** in the repo that ships the design system. Ask that repo where its
  source tree is rather than assuming a layout — the assets directory moves with the framework's
  srcDir, and grepping a stale root returns nothing while looking like a clean pass:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
ROOTS="$(bash "$C" paths --repo <design-system-checkout>)" || exit 1   # names what it needed
ROOT="$(jq -r .root <<<"$ROOTS")"; SRC="$(jq -r '.srcDirAbs // .root' <<<"$ROOTS")"

# The srcDir is declared; `assets/` and the config filename are Tailwind/Nuxt
# conventions on top of it. Confirm at least one real source before grepping, so a
# repo that arranges them differently is a stated blocker and not an empty result.
FOUND=()
for p in "$ROOT"/tailwind.config.* "$SRC/assets"; do [ -e "$p" ] && FOUND+=("$p"); done
[ ${#FOUND[@]} -gt 0 ] || { echo "brand-check: no tailwind config or $SRC/assets in $ROOT — cannot resolve the token allow-list" >&2; exit 1; }
grep -rEn "tron-[a-z]+" "${FOUND[@]}" | head
```

Two ways this stops rather than guesses, and both matter: if `content.sh paths` fails the checkout
declares no content profile and its layout is unknown; if the roots resolve but neither token
source is there, the repo arranges its design system differently. Either way, say which repo and
which file you needed and stop. Never grep a directory that may not exist and report the empty
result as "no off-palette colors" — a clean audit nobody ran is worse than an error.

Treat the tokens you find as the allow-list. Anything outside it is a finding.

## Sampling colors from an asset

```bash
# Dominant colors from a raster asset (ImageMagick if available)
magick "<asset>" -resize 25% -colors 8 -unique-colors txt: 2>/dev/null | grep -oE '#[0-9A-Fa-f]{6}'
```

For each sampled hex, find the nearest brand token. **Snap threshold:** if every RGB channel is
within **±8** of a `tron-` token (a ΔE-ish tolerance), call it a **snap-to-token** finding — it was
meant to be that token. If any channel is off by more than 8, treat it as an off-palette color and
ask whether it's intentional.

## Contrast math

Don't hand-compute luminance — use the bundled deterministic helper, which implements the full
sRGB relative-luminance formula and prints the ratio plus PASS/FAIL at AA **4.5:1** (normal text)
and **3:1** (large text ≥24px or ≥19px bold, and UI/graphics):

```bash
name=brand-check
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/contrast.sh)"

bash "$SKILL_DIR/scripts/contrast.sh" "<fg-hex>" "<bg-hex>"   # e.g. '#5A6B8C' '#F5F5F5'
```

Call out the specific failing pair (e.g. breadcrumb link on background — cf. MCR-348).

## Output

A findings report grouped by category:

| Category | Finding                                                         | Where    | Severity | Fix                       |
| -------- | --------------------------------------------------------------- | -------- | -------- | ------------------------- |
| Palette  | `#1F4FD8` is not a brand token (nearest: `tron-blue` `#2563EB`) | hero CTA | medium   | snap to `tron-blue`       |
| Contrast | breadcrumb link 3.1:1 on `#F5F5F5` (AA needs 4.5:1)             | /support | high     | darken link to ≥`#5A6B8C` |
| Logo     | logo recolored to white on light bg                             | footer   | high     | use full-color lockup     |

End with a one-line verdict: **on-brand** / **needs fixes (N high, M medium)**. If the user wants the
findings on the ticket, offer `tron:jira-comment` (confirm before posting).
