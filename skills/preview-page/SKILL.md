---
name: preview-page
model: haiku
effort: low
description: Open a marketing-pages route in the cmux browser pane so the user can visually inspect it. Spins up the Nuxt dev server on port 4001 if it isn't running, then adds a new browser surface in the browser pane pointing at the requested URL. Use this whenever the user asks to "preview", "open in the browser", "show me the page", "check this in cmux", "load it up", "open that route", or anything similar after creating or editing a `pages/**/*.vue` file. Also trigger when they say "let's both look at it" or "pop it open" right after a page edit — that phrasing implies opening it in the cmux browser pane, not just printing the URL.
---

# Preview Page in cmux Browser

Goal: get a new or edited Nuxt page in front of the user as fast as possible by opening it in the cmux browser pane, starting the dev server first if needed.

**Preflight — confirm you're in the marketing-pages repo.** This skill depends on the
marketing-pages dev script (`bun dev` → port 4001 with `.env.local`) and previews its
routes. The `tron` plugin can be installed in any Facilitron repo, so verify the
checkout first (worktrees of marketing-pages still match — shared remote):

```bash
git remote get-url origin 2>/dev/null | grep -qi 'marketing-pages' \
  || echo "✋ NOT in the marketing-pages repo — preview-page drives the marketing-pages dev server. Switch to that checkout first."
```

If the guard warns, ask the user to switch to the marketing-pages checkout before continuing.

## Workflow

The shortest path:

```bash
bash $CLAUDE_SKILL_DIR/scripts/preview.sh <route-or-file>
```

The script handles everything below. Use it directly when you already know what to preview. The rest of this document is for the cases where you don't, or when something goes wrong.

The script prints two lines on success — the cmux surface ref (e.g. `surface:20`) and the URL — and writes the surface ref to `/tmp/preview-page-surface` for reuse on the next call. Repeated previews navigate the existing tab instead of stacking new ones.

## Self-checking your own work (token-cheap → token-expensive)

The cmux browser exposes a Playwright-style API on the surface. After a preview, you can verify your own work without bothering the user. **Reach for these in order — stop at the first one that answers your question.**

```bash
S=$(cat /tmp/preview-page-surface)
```

1. **`cmux browser --surface $S errors list`** — JS errors on the page. Catches build/runtime regressions immediately. Tiny output. Always run this first after a non-trivial edit.
2. **`cmux browser --surface $S get text --selector h1`** — pull a specific element's text. Verify hero copy, button text, etc. ~100 bytes.
3. **`cmux browser --surface $S eval "Array.from(document.querySelectorAll('h2')).map(h => h.textContent.trim()).join(' | ')"`** — arbitrary JS in the page. Best for "did all four cards render?" / "is the right number of items in this list?" Hundreds of bytes.
4. **`cmux browser --surface $S get count --selector .role-card`** — element counts. Useful for grid integrity checks.
5. **`cmux browser --surface $S snapshot --compact`** — accessibility-tree-ish DOM snapshot. Moderate token cost; use when you need structure, not pixels.
6. **`bash scripts/screenshot.sh /tmp/preview.png`** then `Read` the PNG — most expensive (a long-page PNG can be 50k–200k tokens). Use only when you actually need to look at layout. This wrapper bakes in the blank-capture guard (waits for `readyState`/title, verifies the PNG isn't a blank frame, retries with a reload) and fails fast with guidance if the surface is backgrounded/closed. You _can_ call `cmux browser --surface $S screenshot --out ...` directly, but then you own the blank-frame dance yourself. Read full-resolution; don't re-screenshot if you already have one and haven't changed the page.
7. **`bun scripts/responsive-shot.mjs <url> mobile /tmp/m.png`** (or `tablet`/`desktop`/a raw px width, `--full` for full page) — headless Chromium capture at an arbitrary viewport. This is the **only** way to see mobile/responsive layout: the cmux pane (WKWebView) can't resize below pane width, so CLS / hero-crop / breakpoint work has to be verified here. It's also more robust than the in-pane screenshot because it doesn't depend on the surface being the foreground tab. Run it from inside the skill dir (it uses the skill's own `playwright`).

After editing a Vue file, re-trigger HMR with: **`cmux browser --surface $S reload`**. No need to re-run `preview.sh` for the same URL.

## Figma parity workflow (mandatory when working from a design)

Whenever the task is "build this page/section from Figma," **do not declare a section done until you've gone through this gate.** It exists because eyeballing in isolation reliably misses obvious differences; forcing a structured side-by-side enumeration catches them.

### From a full-page Figma URL (whole-page recipe)

When the user gives you a Figma URL that points at the whole page frame (not a single section), don't dive into `get_design_context` — that returns one giant code dump and you lose the structure. Do this instead:

1. **`mcp__plugin_figma_figma__get_metadata`** on the page node. Returns an XML tree of child frames with names, IDs, positions, sizes. Top-level children under `content` are usually one-per-section, named like `Section/Hero/...`, `Section/Image-Text/Features`, `Section/FAQ`, `Section/CTA`.
2. **Propose a numbered section list back to the user** before building anything: node ID, name, your one-line guess at the component reuse (e.g. "SectionFeatureBestPractices in split mode + SectionCtaCaseStudy below"). Cross-check generic names like `Frame 1` by screenshotting the node. Wait for confirmation/corrections — section granularity in Figma is occasionally off (one Figma frame can hold two visually distinct sections, like a Best Practices grid plus a Case Study CTA).
3. **Loop section-by-section.** For each confirmed section: `get_design_context` on that node → identify reuse from `pages/solutions/**`, `pages/product/**`, `content/resources/toolkit/**` → implement → run the parity gate below. Don't batch — one section per round-trip, so the user can redirect early if something's off.
4. **Commit cadence: wait until the page is done.** Don't commit between sections unless the user asks. One commit per logical chunk (the whole page, or a tightly-scoped group) keeps history clean.

### Autonomous (user-is-away) variant — batch everything

When the user explicitly hands off ("remote control / I'm walking away / ping me when ready"), the round-trip-per-section gate becomes the bottleneck. Use this parallel-batch shape instead — it walks a 9-section page in 2–3 minutes:

1. **One `get_metadata` call** to enumerate sections (same as step 1 above).
2. **One tool turn with N parallel calls:** `get_screenshot` for every section node (their `image_url`s come back together).
3. **One Bash with `&` + `wait`** to curl all Figma PNGs to `/tmp/<page>-diff/figma-N.png`.
4. **Write the whole page scaffold in one `Write` call** — model on the closest existing sibling (e.g. another `pages/solutions/*.vue`). Match items, copy, and section order from the Figma metadata text fields verbatim.
5. **One Bash with `&` + `wait`** to capture every dev section via `section-shot.mjs <url> N /tmp/<page>-diff/dev-N.png`. With 5–9 sections, spawn them all in parallel; backgrounding 3 at a time keeps Chromium from oversubscribing.
6. **Read each `figma-N.png` / `dev-N.png` pair** to spot real diffs. Background-color mismatches and image swaps are the highest-yield checks because they survive font/anti-aliasing noise.
7. **Capture a full-page final shot:** `compare.sh --full /<route> /tmp/<page>-diff/dev-full.png` (or directly `section-shot.mjs <url> full <path>`). Read it. Confirms section order and overall composition.
8. **Surface judgment calls explicitly** in the ping-back, not in the diff. Anything the Figma metadata doesn't pin down (missing CTA targets, missing FAQ copy, ambiguous background color) goes on a flagged list at the end of the report — see [[feedback-figma-stay-literal]].
9. **Commit + push + ping.** One commit per page is fine in autonomous mode.

The trade-off vs. the interactive loop: zero mid-build HITL gates, so any divergence between Figma intent and what you built lands on the user at review time. Mitigate by being more conservative with judgment calls — match Figma literally, list gaps for them to redirect.

### The gate — must do, in order

1. **Pull the Figma node screenshot.** `mcp__plugin_figma_figma__get_screenshot` with the section's node ID, download via curl to `/tmp/figma-<section>.png`.
2. **Open the compare view (it captures dev for you).** `bash $CLAUDE_SKILL_DIR/scripts/compare.sh <figma-png> <route> <section-index>`. The script uses headless Chromium at Figma-native 1440px viewport to clip the dev section to its bounding box, then opens a three-mode compare page: **Side** (side-by-side), **Stack** (opacity slider overlay), **Diff** (mix-blend-mode: difference). The user sees this in the browser pane.

   - `<route>` is the path on the dev server (e.g. `/solutions/maintenance-teams`).
   - `<section-index>` is the 0-based position in the section locator's matches (covers `<main> section`, `section[aria-label]`, and `[class*="py-14/16/20"]`). **Don't count by hand.** Run `bash $CLAUDE_SKILL_DIR/scripts/compare.sh --list <route>` first — it prints a table of `idx | height | aria-label or first heading` so you can pick the right one in one read. Re-run after page edits since adding/removing a section shifts every later index.
   - **Why Playwright not cmux:** macOS WKWebView doesn't support `viewport.set`, so cmux screenshots are stuck at the cmux pane width (~1279px). Figma renders at 1440px. Mismatched viewports give different text wrapping and different responsive layouts — overlay/diff would be noise. Headless Chromium at 1440 matches Figma's render, so element positions overlay cleanly.

3. **Read BOTH PNGs into your context in the same turn.** Use `Read` on `/tmp/cmp-figma.png` and `/tmp/cmp-dev.png` back-to-back so you see them at once. Reading them in separate turns lets the first slip out of working memory.
4. **Enumerate visual diffs against the checklist below.** Write a numbered list. Mark each item: 🔴 real fix, 🟡 trade-off / open question, 🟢 framing artifact (e.g. site header not in Figma node, asset-content delta). Pay extra attention to direction/orientation items (image-left vs image-right, list order) — these are the easiest to miss and the most embarrassing.

   **How to read Diff mode (the primary review tool):**

   - **Doubled text** (title or label appears twice, offset) → real positional miss. Fix.
   - **Solid colored blob** where text or image should be → content is in the wrong place entirely, or one side is missing it.
   - **Ghost halos around crisp edges** → font hinting / sub-pixel anti-aliasing. Ignore.
   - **Faint static across whole regions** → fine, that's rendering noise.

   Don't aim for a percentage — pixel-perfect is unreachable because Figma and Chromium hint fonts differently. The signal is "does each major element appear _once_ in the diff, not twice." If everything appears once, alignment is solid.

   **How to read Stack mode (opacity slider):**

   - Set slider near 50%. Aligned elements stay crisp; misaligned ones show ghosting.
   - Nudge with `←`/`→` keys; toggle to 0%/100% to confirm one element at a time.

5. **STOP and request human-in-the-loop review of the enumeration.** Before applying any fix, share the list with the user and wait for their confirmation/corrections. They see the compare view; you don't have eyes on it the same way. They catch what you miss (layout direction, asset-vs-asset comparisons, "you said this matches but it doesn't"). **Do not skip this step to save a round-trip — the round-trip is the point.**
6. **Autonomous fix-and-verify loop, max 6 iterations.** Don't ping the user between iterations. Run the loop yourself:

   ```
   for iter in 1..6:
     - apply every 🔴 fix you identified
     - re-run compare.sh — it re-captures dev at 1440 via Playwright and refreshes the surface
     - Read both /tmp/cmp-figma.png and /tmp/cmp-dev.png into context this same turn
     - re-enumerate against the parity checklist with 🔴/🟡/🟢 markers
     - if only 🟡/🟢 remain → exit loop, report to the user for HITL review
     - if iter == 6 and 🔴 remain → exit loop, report what's still failing
     - if a 🔴 needs input you don't have (asset swap, copy decision, design choice) → reclassify as 🟡 escalation, exit loop, ask the user
   ```

   Why a cap: a section shouldn't eat hours of iteration. If six rounds haven't converged, something structural is wrong — surface it instead of grinding.

   Why no mid-loop pings: the user is the QA gate, not the inner-loop reviewer. Iterating yourself is cheaper than a round-trip per fix; the trade-off only inverts if you're spinning on the same diff (the cap catches that).

   What counts as "needs the user's input":

   - Image/asset doesn't exist in our CDN and Figma's version isn't exportable as a single asset
   - Copy you'd be inventing (Figma copy and our copy genuinely both seem valid, e.g. Figma has placeholder lorem)
   - A choice between two valid Figma interpretations (e.g. responsive break behavior unspecified)
   - You've made the same fix twice and it's not landing — there's a deeper bug to surface, not iterate around

7. **Get design tokens from Figma, don't eyeball.** This is the single biggest force-multiplier in this loop. `mcp__plugin_figma_figma__get_design_context` returns the exact `font-size`, `line-height`, `gap`, `padding`, `border-radius`, and hex colors as Tailwind-shaped className strings. Use it the moment a size/spacing/color "feels off" — guessing from a downsampled screenshot leads to wrong fixes (e.g. shrinking a box that was actually correct because the _text inside_ was the wrong size).
8. **Flag asset gaps early, don't ship around them.** If a Figma image is a composed mockup we don't have as a single asset, ask the user for an export before iterating on smaller details. The wrong image dominates everything else visually.
9. **Prefer the user's compare-view screenshots over re-pulling Figma.** When the user pastes a screenshot of the compare page, my `Read` tool sees it at a higher resolution than a re-pulled Figma `get_screenshot` (because theirs is a much larger source PNG that downsamples to a still-larger image in my view). If they give you a screenshot, USE THAT for the visual review rather than re-fetching from Figma.

**cmux browser gotcha (verified):** `screenshot` only works on the surface that is the **selected tab** in its pane. Crucially, `eval`/`url`/`get` do **not** share this restriction — a backgrounded or even closed surface keeps answering them with stale-but-plausible values (`url` returns the last URL, `eval "document.readyState"` returns `complete`). So those calls succeeding is **not** proof the surface is live. The tell is `screenshot` erroring with `Failed to capture snapshot` (not a blank PNG) — that means the surface isn't foregrounded. There is **no** `tab switch` / tab-select subcommand on `cmux browser` (the menu actions under `cmux tab-action` are only rename/close); to foreground a surface, re-run `preview.sh` (it opens/selects the surface in the pane) or open a fresh one. `preview.sh` now validates a reused surface is still listed in a pane before handing it back, so a stale `/tmp/preview-page-surface` ref won't silently produce uncapturable screenshots.

Because of all this, prefer `scripts/responsive-shot.mjs` (headless, ignores pane visibility entirely) for self-verification screenshots, and reserve the in-pane `screenshot.sh` for when you specifically want the user to see it live in their pane.

**BaseSection prose gotcha (high-impact):** `components/base/Section.vue` defaults `prose: true`, which adds the `.prose` className from `@tailwindcss/typography`. That plugin re-introduces browser-default margins on `h1`–`h6` (e.g. `margin: 24px 0 8px` on an `h4`) and on `p` tags inside the section. Symptoms: "title top doesn't align with icon top," "items have unexpected vertical spacing between them." Pass `:prose="false"` on `BaseSection` for any section component that styles its own typography via Tailwind utilities. This was the root cause of the section-1 alignment + spacing mismatch — once `prose` was off, the `items-start` flex layout worked correctly with zero further changes.

**Don't assume "smaller is better" when something looks oversized.** A common trap: an icon-box looks "too big" relative to its title, so you shrink the box. The real fix is often that the title text is too big (wrong `text-` size or `font-` weight). Pull `get_design_context` to find out which.

**Verify "alignment is off" with `getBoundingClientRect`, not eyeballing.** A section's PNG asset often has its own internal whitespace, so the visible content can look mis-aligned even when the `<img>` element top is exactly where you want it. Before chasing a layout fix, run `eval` to compare `getBoundingClientRect().top` on the suspect elements. If they match, the "misalignment" is the asset's padding — note it for an asset-trim follow-up rather than refactoring the layout.

**One screenshot is usually enough; only stitch when the section overflows the viewport.** The cmux browser pane captures the full viewport, which is plenty for a single section (~600–800px tall). Stitch top+bottom only when the section is taller than the viewport — otherwise you're doubling tokens for nothing.

**Never accept a blank/white screenshot.** After `reload` (or any navigation), the Nuxt page can take 3–5s to render. Symptoms of a too-early screenshot: PNG file size suspiciously small (<200KB for a marketing page) or visually all-white when Read. Guards in order of preference:

1. `cmux browser --surface $S eval "document.readyState"` — wait for `"complete"`.
2. `cmux browser --surface $S eval "document.title"` — should be the page title, not "Loading" or empty.
3. Check the screenshot's file size (`ls -la /tmp/dev-*.png`) — a real marketing-page section screenshot is typically >500KB; <200KB is a strong signal of a blank/loading frame.
4. As a last resort, `sleep 4` after reload before screenshotting (HMR is usually quicker, but a fresh navigate is slower).

If you ship a blank to the compare view, the user sees blank — that's a wasted round-trip.

**Section-height sanity check (highest-leverage early signal).** After capture, compare `identify -format "%h\n" /tmp/cmp-figma.png /tmp/cmp-dev.png`. If dev is >40px taller than Figma, you have a vertical-rhythm bug somewhere — chase that BEFORE eyeballing finer alignment, because every element will be shifted. The fix is almost always one of: oversized SectionIntro spacing (default `padding: "px-4 pb-6"` + `marginBottom: "mb-8 md:mb-12"` = 72px gap; Figma usually wants 40px → override with `padding="px-4" margin-bottom="mb-10"`), wrong `items-start` vs `items-center` on the grid, or a `prose`-true BaseSection leaking margins.

**Diff-as-metric quick check:**

```
magick /tmp/cmp-figma.png /tmp/cmp-dev.png \
  \( -clone 0 -clone 1 -compose difference -composite -threshold 10% \) \
  -delete 0,1 -format "%[fx:mean*100]%%\n" info:
```

This prints the percentage of pixels where the figma-vs-dev difference exceeds 10% intensity. Useful as a regression signal — if it spikes after a change, something moved. Targets, with the caveat that this is a vibes-metric not a contract:

- **< 6%**: noise floor — text anti-aliasing and sub-pixel positioning differences between Figma and Chromium. Section is done.
- **6–12%**: some real misalignment remaining, but small. Check the Diff view for doubled elements.
- **> 12%**: real structural miss. Layout direction, image position, font size, or section height is off.

**Font/anti-aliasing noise floor is ~5%.** Figma and Chromium hint fonts differently and render image edges slightly differently. Pixel-perfect (0% diff) is unreachable. Don't chase the last ~5% with extreme line-height/letter-spacing tweaks — that's diminishing returns. The structural fixes are where the payoff is.

**Items-center on the grid is the Figma default for image-text layouts.** When Figma uses `items-center` on a horizontal flex with a fixed-height image (e.g. 640px square) and a shorter items column, the image extends both above and below the items column visually. Match this with `lg:items-center` on the grid. Reach for `items-start` only when the image asset is _cropped_ to match the items-column height (e.g. via `aspect-[640/400]` for an asset with internal whitespace).

**When a square image asset has internal whitespace** (panel centered in a 640×640 PNG with transparent borders), use `aspect-[640/N] object-cover object-center` on the NuxtImg, where N is sized so `(640-N)/2` matches the asset's top/bottom whitespace. This crops the empty space without losing the panel content. Section 2's panel had ~120px whitespace top/bottom → `aspect-[640/400]` (crops 120 top + 120 bottom). For edge-bleed assets (Section 4's panel + dollar coin + blue arc that touch the asset edges), don't crop — let it stay square.

### Parity checklist (run through every item, every section)

- **Layout proportions** — column ratio (50/50 vs Figma's actual split), section padding, max-width
- **Layout direction** — image-left vs image-right per section; list order within columns. Easy to miss; high-impact when wrong.
- **Image content** — is the image the same composed asset Figma uses? If not, that's a 🔴 unless explicitly deferred
- **Image alignment** — top vs center vertical alignment in the grid (`items-start` vs `items-center`)
- **Color tokens** — eyebrow, accent text, button background, icon color (use `get_design_context` for hex)
- **Typography** — heading size/weight matches `frame-h*` token; **always pull design context for bullet-item heading sizes** — they're usually `text-base` (16px), not `text-lg` (18px)
- **Spacing** — gap between bullets, gap between intro and grid, button margins. Pull `gap-[XXpx]` from the design context.
- **Bullet/icon style** — bare icon vs padded badge; size of the box; border-radius; size of the icon inside; color
- **Phantom margins** — if `BaseSection` is wrapping content with `prose`, headings and paragraphs inherit margins. Check by running `getComputedStyle(h4).margin` via eval. Fix by `:prose="false"`.
- **Sub-CTAs and ancillary copy** — Figma often has paragraph + button combos; don't collapse them into a single link. Check for bolded sentences within the paragraph.
- **Background colors** — section bg, image bg container
- **Copy** — every word, including secondary "Click here..." sentences that are easy to drop

### What does NOT count as a discrepancy

- Site header (logo + nav) visible in dev screenshot — Figma node screenshots don't include the page header
- Line wrapping differences when our dev pane is narrower than 1440px — same content, different viewport
- Sub-pixel font rendering differences between Figma and Chromium/WKWebView

If the only remaining items are these framing artifacts, the section is done.

## Responsive checks (375 / 1024 / 1440)

`cmux browser viewport <w> <h>` is **not supported on macOS WKWebView**, which is what the cmux pane uses — you cannot resize the cmux browser pane for responsive screenshots. Use the headless helper instead:

```bash
# from inside $CLAUDE_SKILL_DIR (uses the skill's own playwright)
bun scripts/responsive-shot.mjs <url> mobile  /tmp/m.png          # 375px, dsf 2, above-the-fold
bun scripts/responsive-shot.mjs <url> tablet  /tmp/t.png --full   # 768px, full page
bun scripts/responsive-shot.mjs <url> desktop /tmp/d.png          # 1440px
bun scripts/responsive-shot.mjs <url> 414     /tmp/x.png          # any raw px width
```

This is the first-class way to self-verify mobile/CLS/hero-crop/breakpoint work (e.g. MD-1707 / MD-1749-style tickets) — it renders in real Chromium at the requested width, independent of the cmux pane. `Read` the PNG to inspect.

Other options, in rough order of preference:

- **`responsive-shot.mjs`** (above) — autonomous, no round-trip. Default to this.
- **Ask the user to resize** the cmux browser pane and report what they see. Use when you want their eyes on something subjective rather than a PNG.
- **Trust the Tailwind breakpoints** if the page uses standard `md:` / `lg:` / `xl:` classes and you can see the desktop render is correct. Low cost, slightly lower confidence.

### 1. Resolve the URL

Figure out the route path from what the user gave you (or from what you just built):

- **Already a URL** (`http://localhost:4001/...`) — use as-is.
- **Route path** (`/resources/guides/foo`) — prefix with `http://localhost:4001`.
- **File path** (`pages/resources/guides/foo.vue`) — strip the leading `pages/` and the trailing `.vue`, collapse `index` to the parent directory:
  - `pages/index.vue` → `/`
  - `pages/about-facilitron.vue` → `/about-facilitron`
  - `pages/resources/guides/index.vue` → `/resources/guides`
  - `pages/resources/guides/foo.vue` → `/resources/guides/foo`
- **Catch-all routes** (`pages/resources/news/[...slug].vue`) — the user must give you the actual slug; you can't derive it from the file. Ask.

If the user didn't name a page, check the conversation: a Vue file just got created or edited, that's almost certainly the one they want to see.

### 2. Make sure the dev server is up

```bash
lsof -ti:4001 >/dev/null 2>&1 || (
  source ~/.nvm/nvm.sh && nvm use >/dev/null 2>&1
  bun dev > /tmp/preview-page-dev.log 2>&1 &
)
```

Then wait for the "Local:" line so the first request doesn't 502:

```bash
until grep -q "Local:" /tmp/preview-page-dev.log 2>/dev/null; do sleep 1; done
```

If the log fills with errors instead (search for `error` or `Failed`), stop and surface them — don't open the browser to a broken page.

### 3. Find the cmux browser pane

cmux doesn't label pane types. The browser pane is the one whose surfaces have webpage-shaped titles (containing `-` separators and product names like `Confluence`, `JIRA`, `localhost`, a `.com` host, etc.) rather than shell-shaped titles (`cd `, `vim`, `~/code`, command lines).

Iterate panes and pick the one with no shell-shaped surfaces. The helper script does this; do it inline only if the script breaks.

### 4. Open the surface

```bash
cmux new-surface --type browser --pane <pane-ref> --url "<full-url>"
```

A new browser tab opens in the browser pane. Don't focus it — the user usually wants to stay in their current pane. The new tab is auto-selected within the browser pane, which is enough.

### 5. Tell the user

One line, with the URL. They're about to look at it; they don't need a recap of what the page does.

### 6. (Optional) Self-check before handing off

If the change is non-trivial, run `cmux browser --surface $S errors list` and a `get text` for the most important element before saying "preview is up." Catching a broken h1 yourself is cheaper than catching it through the user's eyes — and far cheaper than a screenshot round-trip.

## When things go sideways

- **No browser pane found.** Create one: `cmux new-pane --type browser --direction right --url "<full-url>"`. Tell the user you split a new pane because no browser pane existed.
- **Port 4001 already busy by something else.** `lsof -ti:4001` returns a PID. If the process's command isn't `nuxt`/`node`, ask the user before killing it.
- **Dev server fails to start.** Read `/tmp/preview-page-dev.log`. Common culprits: missing `.env.local`, missing project deps (run `bun i` from the **repo root** — the project's package.json, not the skill's), Node version mismatch (the `nvm use` step needs `.nvmrc` to resolve).
- **Page 404s in the browser but the route file exists.** Nuxt needs a beat to pick up new files; if the user just created the route, refresh after a second.
- **`bun scripts/section-shot.mjs` says `Module not found "playwright"`.** Playwright is a _skill-local_ dep, not a project dep. Install it from inside the skill dir only — never from the repo root:
  ```bash
  (cd $CLAUDE_SKILL_DIR && bun i)
  ```
  `compare.sh` already runs `section-shot.mjs` from inside the skill dir via subshell, so the script picks up the skill's own `node_modules`. The skill's `bun.lock` and `package.json` are checked in.
- **Chromium executable missing.** One-time browser download: `(cd $CLAUDE_SKILL_DIR && bunx playwright install chromium)`.

## Boundary: skill deps vs project deps

The skill manages its own `package.json`, `bun.lock`, and `node_modules` under `$CLAUDE_SKILL_DIR/`. The project (Nuxt app) has its own at the repo root. **Never conflate them:**

- ❌ Do **not** run `bun i playwright`, `bun add playwright`, or any skill-related install from the repo root. That mutates the project's `package.json` and pulls a heavy browser dep into the app.
- ❌ Do **not** `Write` a file named `package.json` without an explicit absolute path under `$CLAUDE_SKILL_DIR/`. The Write tool requires absolute paths, but slip-ups here have clobbered the project's root `package.json` before.
- ✅ Always `cd $CLAUDE_SKILL_DIR` (or use the subshell pattern from `compare.sh`) before any `bun` command for skill deps.
- ✅ Before any commit that touches packaging, run `git diff package.json` at the **repo root** — if it shows the skill's `"name": "preview-page-skill"` content, the project's `package.json` got clobbered and must be restored with `git restore package.json` before committing.

## Why this exists

Without the skill, every preview means: remember the dev command, remember port 4001, look up cmux pane IDs, guess at the right `cmux` subcommand. The helper script collapses all of that into one call so the loop between "I just changed a page" and "I can see the change" stays short.
