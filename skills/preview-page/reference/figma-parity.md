# Figma Parity Gate

**Must be followed when building any page/section from a Figma design.** This exists because eyeballing in isolation misses obvious differences.

## Workflow

### Full-page Figma URL (not a single-section frame)

1. **`mcp__plugin_figma_figma__get_metadata`** on the page node → XML tree of child frames (one per section).
2. **Propose a numbered section list** to the user: node ID, name, your guess at component reuse. Wait for confirmation — section granularity in Figma is occasionally off.
3. **Loop section-by-section.** For each: `get_design_context` on that node → identify reuse from `pages/solutions/**` / `pages/product/**` → implement → run parity gate below.
4. **Commit cadence: one commit per page**, not per section.

### Autonomous (user-away) mode

When the user hands off explicitly ("I'm walking away / ping me when ready"):

1. One `get_metadata` call to enumerate sections.
2. One tool turn with parallel `get_screenshot` calls for every section node.
3. One Bash with `&` + `wait` to curl all Figma PNGs to `/tmp/<page>-diff/figma-N.png`.
4. Write the whole page scaffold in one `Write` call — model on the closest existing sibling.
5. One Bash with `&` + `wait` to capture every dev section via `section-shot.mjs`.
6. Read each `figma-N.png` / `dev-N.png` pair. Background-color mismatches and image swaps are the highest-yield checks.
7. Capture full-page final shot. Surface judgment calls in the ping-back.
8. Commit + push + ping. One commit per page.

## The parity gate (mandatory, every section, in order)

### 1. Pull the Figma node screenshot
```bash
# Use MCP get_screenshot, download via curl to /tmp/figma-<section>.png
```

### 2. Open the compare view
```bash
# Captures dev at Figma-native 1440px, opens side-by-side/stack/diff modes in the browser
bash "$SKILL_DIR/scripts/compare.sh" <figma-png> <route> <section-index>
```

`--list` to see available sections: `bash "$SKILL_DIR/scripts/compare.sh" --list <route>`

### 3. Read BOTH PNGs into context in the same turn
Use `Read` on both `/tmp/cmp-figma.png` and `/tmp/cmp-dev.png` together.

### 4. Enumerate visual diffs
Number each item: 🔴 real fix, 🟡 trade-off, 🟢 framing artifact.

- **Diff mode:** doubled text = positional miss; solid colored blob = content missing; ghost halos = font hinting noise; faint static = rendering noise.
- **Stack mode (opacity slider):** set near 50%, use ←/→ to toggle.

### 5. STOP and request human review of the enumeration
Before applying any fix, share the list with the user. **Do not skip this step.**

### 6. Autonomous fix-and-verify loop, max 6 iterations
```
for iter in 1..6:
  - apply every 🔴 fix
  - re-run compare.sh, read both PNGs
  - re-enumerate with 🔴/🟡/🟢
  - if only 🟡/🟢 remain → exit, report to user
  - if iter==6 with 🔴 remaining → exit, report what's still failing
```

### 7. Get design tokens from Figma, don't eyeball
`get_design_context` returns exact font-size, line-height, gap, padding, border-radius as Tailwind className strings. Use it the moment a size/color "feels off."

### 8. Flag asset gaps early
If a Figma image is a composed mockup we don't have as a single asset, ask the user for an export before iterating on details.

## Parity checklist (every item, every section)

- [ ] Layout proportions — column ratio, section padding, max-width
- [ ] Layout direction — image-left vs image-right, list order within columns
- [ ] Image content — same composed asset Figma uses?
- [ ] Image alignment — top vs center in grid (`items-start` vs `items-center`)
- [ ] Color tokens — eyebrow, accent, button, icon (use `get_design_context`)
- [ ] Typography — heading size/weight matches `frame-h*`; bullet headings usually `text-base` not `text-lg`
- [ ] Spacing — gap between bullets, between intro and grid, button margins
- [ ] Bullet/icon style — bare icon vs padded badge; box size, border-radius, icon size
- [ ] Phantom margins — `BaseSection` with `prose: true` adds browser-default margins. Fix with `:prose="false"`
- [ ] Sub-CTAs and ancillary copy — don't collapse paragraph+button combos into a single link
- [ ] Background colors — section bg, image bg container
- [ ] Copy — every word, including secondary sentences

**Does NOT count as a discrepancy:** site header (logo+nav), line-wrapping differences at non-1440px viewports, sub-pixel font rendering differences.

## Responsive checks (375 / 1024 / 1440)

```bash
name=preview-page
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/responsive-shot.mjs" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/responsive-shot.mjs" ] && echo "$d"; done | sort -V | tail -1)"
bun "$SKILL_DIR/scripts/responsive-shot.mjs" <url> mobile  /tmp/m.png          # 375px
bun "$SKILL_DIR/scripts/responsive-shot.mjs" <url> tablet  /tmp/t.png --full   # 768px, full page
bun "$SKILL_DIR/scripts/responsive-shot.mjs" <url> desktop /tmp/d.png          # 1440px
bun "$SKILL_DIR/scripts/responsive-shot.mjs" <url> 414     /tmp/x.png          # raw px width
```

Read the PNG to inspect. Prefer this over asking the user to resize.

## agent-browser self-checks (cheapest first)

```bash
U=$(cat /tmp/preview-page-url); agent-browser open "$U" && agent-browser wait --load networkidle
```

1. `agent-browser errors` — page errors / console output
2. `agent-browser get text h1` — hero copy
3. `agent-browser eval "<js>"` — arbitrary DOM queries
4. `agent-browser get count .<selector>` — element counts
5. `agent-browser snapshot` — accessibility tree
6. `bash scripts/screenshot.sh /tmp/preview.png` → `Read` — only when you need layout

## Known gotchas

- **Items-center is the Figma default** for image-text layouts. Reach for `items-start` only when the image is cropped to match content height.
- **BaseSection with `prose: true`** re-adds browser-default margins on headings. Pass `:prose="false"` for any section that styles its own typography.
- **Square images with internal whitespace** — use `aspect-[640/N] object-cover` to crop without losing content.
- **`getBoundingClientRect` before eyeballing alignment** — a section's PNG may have internal whitespace making visible content look misaligned when the element top is correct.
- **Diff-as-metric quick check:**
  ```bash
  magick /tmp/cmp-figma.png /tmp/cmp-dev.png \
    \( -clone 0 -clone 1 -compose difference -composite -threshold 10% \) \
    -delete 0,1 -format "%[fx:mean*100]%%\n" info:
  ```
  <6%: noise floor. 6-12%: small alignment remaining. >12%: structural miss.
- **Font/anti-aliasing noise floor is ~5%** — don't chase the last 5% with extreme tweaks.
- **Section-height sanity:** compare `identify -format "%h\n" /tmp/cmp-figma.png /tmp/cmp-dev.png`. >40px difference = vertical-rhythm bug.