---
name: guide-item
model: opus
effort: high
description: 'Publish a new long-form guide to /resources/guides on the Facilitron marketing site from a Jira ticket whose description links a Confluence draft. Unlike news and toolkit items, a guide is a bespoke Vue PAGE composed from section/display components (not a Nuxt-Content markdown file) — this skill handles the full workflow: fetching the Confluence page, downloading and converting its images to webp, uploading them to ImageKit, composing the page from the standard guide component palette, registering it in the guides index, and wiring SEO meta. Use this skill whenever the user wants to "start the guide", "create a new guide", "build out this guide", "turn this Confluence draft into a guide page", "add a guide to /resources/guides", references a Jira "Guide" or "Pillar" ticket with a Confluence link, or says "publish this guide" / "get this guide on the site". Even if they describe only one part ("just do the images", "just scaffold the page"), this skill owns the whole pipeline so the pieces stay consistent.'
---

# Facilitron Guide Item

Publish a new guide under `/resources/guides` on the marketing-pages site, starting
from a Jira ticket that links a Confluence draft.

**A guide is NOT a content collection item.** News (`content/resources/news`) and
toolkit (`content/resources/toolkit`) items are markdown files rendered by a
`[...slug].vue` catch-all. Guides have **no collection, no schema, no catch-all** —
each guide is a hand-composed Vue page at `pages/resources/guides/<slug>.vue`, built
from the site's section/display components, plus a manual entry in the guides index.
The route is just the filename: `pages/resources/guides/preventive-maintenance-strategy.vue`
serves at `/resources/guides/preventive-maintenance-strategy`.

So this pipeline shares the *intake and image* stages with `tron:news-item`,
but its core is **page composition**, not markdown authoring.

## What gets produced

- A Vue page at `pages/resources/guides/<slug>.vue` (layout `news`), composed from the
  standard guide palette, body converted from the Confluence draft
- Body images uploaded to ImageKit at `guides/<slug>/<name>.webp`, referenced via
  `<NuxtImg provider="imagekit" src="guides/<slug>/<name>.webp">`
- An OG image at `og/og-<slug>.webp` (passed to `useDynamicMeta`)
- A card thumbnail at `guides/guide-<NN>.webp` (next free number) for the index card
- A new entry appended to the `guides` array in `pages/resources/guides/index.vue`
- Local source files (Confluence download, dropped-in images) cleaned up

## Inputs you need

1. **Jira ticket key** — usually on the branch name (`<KEY>-<slug>`). Its description
   carries target SEO keywords and a Confluence inline-card link.
2. **Slug** — derive from the ticket/title, lowercase-hyphenated, descriptive
   (`preventive-maintenance-strategy`, `school-facility-management-best-practices`).
   The page filename, the `guides/<slug>/` image folder, the OG image name, and the
   index `link` all use it — confirm with the user before uploading anything.
3. **Hero/illustration images** — pulled from the Confluence draft, or reuse existing
   `product/...` illustrations. If the draft has none, ask whether to source from
   Figma/ImageKit or proceed with a `product/...` placeholder.

## Environment

`JIRA_API_TOKEN` lives in `~/.env` (1Password) and is
usually autosourced. If a command 401s or a token is unset, source them in the *same*
Bash call: `set -a; source ~/.env; set +a`.

---

## Subagents & model tiers

Same principle as the other pipelines: push mechanical/large-payload work to cheaper
subagents, keep design judgment in the orchestrator.

- **Confluence → markdown (Sonnet).** Delegate the storage-format transform to a
  Sonnet subagent per the `tron:confluence` skill's faithful-markdown contract — it returns
  clean markdown + a per-image map (`{ filename, alt, ac:layout, order }`). Keeps the
  raw XML out of the orchestrator while you compose the page.
- **Image convert + upload (Haiku fan-out).** Once you've named each image
  (`guides/<slug>/<descriptive-name>.webp`), the download → webp → upload per image is
  independent and deterministic — fan out one Haiku subagent per image for guides with
  many illustrations. A batched Bash loop is fine for a few.
- **Never delegate the page composition** (Stage 3). Choosing components, section
  order, variants, and styling from the palette is the judgment core — it stays on the
  orchestrator (Opus).

---

## Shared scripted helpers

The deterministic backbone shared with `tron:toolkit-item` and `tron:news-item`
(repo guard, slug, the facilitron.com→relative link rewrite, internal-path
validation) plus the guide-card numbering is one wrapper:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" check-repo                          # marketing-pages guard (below)
bash "$C" slug "<title>"                       # the slug driving the .vue file + ImageKit folders
bash "$C" check-link /product/works            # verify an internal link before it 404s the prerender
# next free guide-card index (Stage 2) — feed the existing names in:
node "$IK" list --path guides --limit 50 | grep -oE 'guide-?[0-9]+\.webp' \
  | bash "$C" next-index --prefix guide --suffix .webp     # → {"ok":true,"next":"05"}
```

Each emits one JSON line. Smoke them with
`bash ${CLAUDE_PLUGIN_ROOT:-…}/tools/content/test-content.sh`. Page composition,
component choices, and card generation below stay judgment.

## Preflight — confirm you're in the marketing-pages repo

The `tron` plugin can be installed in any Facilitron repo, but this skill writes
marketing-pages pages (`pages/resources/guides/`). **Verify the checkout first and
stop if it doesn't match** — `content.sh check-repo` is the guard (worktrees of
marketing-pages still match — shared remote):

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh" check-repo \
  | grep -q '"isMarketingPages":true' \
  || echo "✋ NOT in the marketing-pages repo — switch to that checkout first."
```

If the guard fails, ask the user to switch to the marketing-pages checkout
before continuing — don't write files into the wrong repo.

## Stage 1 — Intake

Read the ticket and the Confluence draft.

```bash
acli jira workitem view <KEY> --json
```

The description's `inlineCard` attr holds the Confluence URL. Capture the target
keywords — they shape the title, the meta description, the H2s, and the TOC labels.

Fetch the page and its referenced images with this skill's bundled script (it
sources `~/.env`, writes the storage body and only the images the body references).
It's the same script `tron:news-item` uses — one shared copy lives in the plugin's
`tools/` dir, resolved via `CLAUDE_PLUGIN_ROOT` (falling back two levels up from the
skill's own `CLAUDE_SKILL_DIR`):

```bash
TOOLS="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools"   # plugin-level shared tools
"$TOOLS/confluence/fetch-confluence.sh" <confluence-url-or-page-id> /tmp/guide-<slug>
```

This writes `/tmp/guide-<slug>/body.html` and `/tmp/guide-<slug>/raw/<name>` per
referenced image, printing them in document order. Then hand `body.html` to a **Sonnet
subagent** for the storage→markdown transform (see Subagents). You compose the page
from the returned markdown + image map.

---

## Stage 2 — Images

Each image becomes a resized webp with a descriptive, slug-scoped name. Convert with
the bundled helper (Bun `Bun.Image`, caps longest edge at 2000px, q82), or
`cwebp`/`sips` directly:

```bash
TOWEBP="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/to-webp.sh"   # shared plugin tool
"$TOWEBP" "/tmp/guide-<slug>/raw/<original>" "/tmp/guide-<slug>/<name>.webp"
```

Upload to ImageKit (CLI keeps `--name` exactly — no random suffix):

```bash
set -a; source ~/.env; set +a
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"

# Body images — one folder per guide
node $IK upload "/tmp/guide-<slug>/<name>.webp" --name <name>.webp --folder guides/<slug>

# OG image (1200×630-ish; reuse the hero illustration or a representative body image)
node $IK upload "/tmp/guide-<slug>/og.webp" --name og-<slug>.webp --folder og
```

Verify names landed clean: `node $IK list --path guides/<slug>`. Body images are
referenced by **relative provider path** (`guides/<slug>/<name>.webp`) — never a full
URL. The OG image IS a full URL in `useDynamicMeta` (Stage 3).

### Card thumbnail — generate to match the index style

The guides index cards share one consistent illustration style (and the toolkit index
cards use a very similar one). Don't hand-pick a random image — **generate the card with
the `tron:gen-image` skill** (codex `image_gen`, set up on this machine) seeded with the
*existing* guide cards so the new one matches the set's palette, framing, and scale.

```bash
# 1. Find the existing cards + the next free number
node $IK list --path guides --limit 50 | grep -oE 'guide-?[0-9]+\.webp' | sort -u

# 2. Download the existing cards from ImageKit as gen-image style references
mkdir -p /tmp/guide-<slug>/card-refs
for n in 01 02 03 04; do
  curl -s -o "/tmp/guide-<slug>/card-refs/guide-$n.webp" \
    "https://ik.imagekit.io/facilitron/guides/guide-$n.webp"
done
```

Then invoke the **`tron:gen-image`** skill with `/tmp/guide-<slug>/card-refs` as the reference
set and a prompt describing this guide's subject (e.g. "flat editorial illustration of a
preventive-maintenance calendar, school-facility theme"). It returns an image styled to
match the references. Convert to webp and upload as the next number:

```bash
"$TOWEBP" <generated.png> "/tmp/guide-<slug>/guide-<NN>.webp"
node $IK upload "/tmp/guide-<slug>/guide-<NN>.webp" --name guide-<NN>.webp --folder guides
```

`<NN>` is the next free index (e.g. `05` if `guide-04.webp` is the highest). This is the
thumbnail the `index.vue` entry references in Stage 4 — distinct from the
`guides/<slug>/` body-image folder. (The toolkit skill's card image uses the same
generate-from-references approach against its own index cards.)

> If codex `image_gen` is ever unavailable, fall back to asking the user for a card image
> or pulling one from Figma — but generate-from-references is the default; it keeps the
> index visually consistent.

---

## Stage 3 — Compose the page

Create `pages/resources/guides/<slug>.vue`. Mirror an existing guide such as
`preventive-maintenance-strategy.vue` for the full pattern. The skeleton, palette, and
conventions below are the reference — follow them rather than re-reading all four
guides each time.

### Canonical section skeleton

```
<NuxtLayout>
  SectionHeroProduct        eyebrow, title, description, cta-text, cta-link,
                            background-color="bg-tron-primary-600",
                            :background-image="IMAGEKIT_BG_GRID",
                            hero-image, hero-image-alt
  NavPillarSubnav           :links="tocItems" aria-label="Guide navigation"

  BaseSection id="introduction" class="scroll-mt-36" padding="pt-16 px-4"
    SectionIntro eyebrow="Introduction" headline headline-tag="h2" headline-style="h1"
    div.mx-auto.max-w-4xl.space-y-4
      <p>…</p>
      DisplayFeatureCard variant="callout" icon="lucide:lightbulb" title="Key Takeaway"
      <p>…</p>

  [2–5 more BaseSection content blocks — alternate no-bg / class="bg-tron-sand-50"]
    each: SectionIntro + prose + DisplayFeatureCard grids as the content needs

  SectionQuoteSimple        quote, quotee, position            (a pull quote, optional)

  <section class="scroll-mt-36 bg-tron-asphalt-800 px-4 py-20 lg:px-32">   ← dark "at a glance"
    div.container.mx-auto → heading (frame-h2 text-white) + grid of v-for cards

  <section class="bg-tron-primary-700 py-24">                  ← mid-page CTA
    3-up grid of NuxtLink cards from a ctaActions array

  BaseSection id="conclusion" padding="py-16 px-4"
    SectionIntro headline="Conclusion" headline-tag="h2" headline-style="h1"
    div.mx-auto.max-w-4xl.space-y-4 → prose + a rounded bg-tron-primary-600 rocket callout

  BaseSection id="faq" class="scroll-mt-36" padding="py-16 px-4"
    SectionIntro headline="Frequently Asked Questions" headline-tag="h2" headline-style="h1"
    div.mx-auto.max-w-4xl → SectionAccordion :items="faqItems"
</NuxtLayout>
```

Hero, TOC, intro, mid-page CTA, conclusion, and FAQ are **universal**. The middle body
sections, pull quote, and dark section flex to the content.

### Component palette (only what guides use)

| Component | Key props | Notes |
|---|---|---|
| `SectionHeroProduct` | `eyebrow`*, `title`*, `description`, `ctaText`, `ctaLink`, `ctaVariant` (`primary-alt`\|`primary`\|`secondary`\|`tertiary`\|`inverse`), `backgroundColor`*, `backgroundImage`, `heroImage`, `heroImageAlt` | Full-bleed hero. Use `background-color="bg-tron-primary-600"` + `:background-image="IMAGEKIT_BG_GRID"`. `heroImage` is a provider path string (component renders it). |
| `NavPillarSubnav` | `links`* (`[{id, label}]`), `ariaLabel` | Sticky TOC; each `id` must match a `BaseSection id`. |
| `SectionIntro` | `headline`*, `eyebrow`, `description`, `headlineTag` (`h1`\|`h2`\|`h3`, default `h2`), `headlineStyle` (`h1`…`h4`), `textAlign` (default `center`) | Section header. Guides always use `headline-tag="h2" headline-style="h1"`. Has a `#description` slot for rich content. |
| `DisplayFeatureCard` | `variant` (`default`\|`product`\|`alternative`\|`compact`\|`callout`), `icon` (lucide name), `title`, `description`, `accentColor`, `titleTag` | Workhorse card. `callout` = highlighted takeaway block (default slot for prose); `alternative` = light-blue grid card; `compact` = inline row (used in timelines/insets); `product` = large brand card with `eyebrow`/`ctaText`/`ctaLink`. |
| `DisplayIconHeading` | `icon`*, `title`*, `tag` (default `h3`) | Icon-badge + heading row. Optional sugar for the inline icon+`h3` pattern. |
| `SectionQuoteSimple` | `quote`*, `quotee`*, `position`, `location`, `backgroundColor`, `borderBottom` (default `true`), `image`, `imageAlt` | Pull quote. Use the `section/` one, NOT `content/QuoteSimple.vue`. |
| `SectionAccordion` | `items`* (`[{question, answer}]`), `name` | FAQ; native `<details>`. Feed it `faqItems`. |
| `SectionCtaProduct` | `title`*, `ctaText`*, `ctaLink`, `description`, `variant` (`dark`\|`dark-split`\|`dark-image`\|`blue`), `backgroundColor`* | A componentized CTA — an alternative to the raw mid-page CTA `<section>`. `title` is `v-html` — no untrusted input. |
| `BaseSection` | `padding` (default `py-12`), `class`, `prose` (default `true`), `grid`, `columns`, `gap` | Section wrapper with prose styling. Standard content padding is `py-16 px-4`; first section `pt-16 px-4`. |
| `BaseButton` | `variant` (`primary`\|`secondary`\|`tertiary`\|`inverse`\|`primary-alt`), `size` (`sm`\|`md`\|`lg`\|`xl`), `link`, `target` | Pill button. `iconOnly` requires an `aria-label`. |
| `BaseEyebrow` | `color` (`primary`\|`primary-light`\|`secondary`\|`secondary-light`\|`accent`), `textAlign` | Standalone uppercase label (usually you get this via `SectionIntro`'s `eyebrow`). |

(`*` = required prop. Icons are `<Icon name="lucide:…" aria-hidden="true" />`.)

### How draft content maps to components

- **A prose section** → `BaseSection` > `SectionIntro` (heading) + `div.mx-auto.max-w-4xl.space-y-4` of `<p>`s.
- **A "key takeaway" callout** → `DisplayFeatureCard variant="callout" icon="lucide:lightbulb" title="Key Takeaway"` with prose in the default slot.
- **A list of benefits/points** → a grid of `DisplayFeatureCard variant="alternative"`:
  `div.mx-auto.mt-10.grid.max-w-5xl.gap-4.sm:grid-cols-2.lg:grid-cols-3`.
- **A numbered process** → a timeline: a `v-for` over a `steps` array rendering numbered
  badges + `DisplayFeatureCard variant="compact"` (see `preventive-maintenance-strategy.vue`).
- **An "at a glance" / best-practices block** → the dark raw `<section class="bg-tron-asphalt-800 …">` with a `v-for` of `bg-white/5` bordered cards (full-bleed, so NOT `BaseSection`).
- **An FAQ** → a `faqItems` array → `SectionAccordion`.
- **Images** → `<NuxtImg provider="imagekit" src="guides/<slug>/<name>.webp" alt="…" class="w-full rounded-lg" sizes="500px md:1200px lg:1800px" />`. `alt` is required (WCAG) — write a real description, never the source filename.

### `<script setup>` conventions

```ts
definePageMeta({
  documentDriven: { page: false, surround: false },
  layout: "news",
});

// Data arrays consumed by the template:
const tocItems = [{ id: "introduction", label: "Introduction" }, /* one per BaseSection id */];
const faqItems = [{ question: "…", answer: "…" }, /* … */];
const ctaActions = [{ icon: "lucide:calendar-check", title: "Schedule a Demo", description: "…", link: "/demo-signup" }, /* 3 */];
// plus any domain arrays for grids/timelines, all flat: { icon, title, description }

const route = useRoute();
const title = "The Complete Guide To …";
const description = "…";   // keyword-rich, ~150–160 chars

useDynamicMeta(
  title,
  description,
  route.path,
  "https://ik.imagekit.io/facilitron/og/og-<slug>.webp",   // full OG URL
);
```

`IMAGEKIT_BG_GRID` (from `utils/imagekit.ts`) and `useDynamicMeta` are auto-imported —
no `import` line needed. Guide detail pages do **not** call `useJsonLd`/`useArticleSchema`
(only the index does). Do **not** add a `#`/H1 in the body — the hero renders the title.

### Styling rules (tron tokens only — no arbitrary values)

- Alternate section backgrounds: white (no bg class) ↔ `class="bg-tron-sand-50"`.
- Dark emphasis sections and the mid-page CTA use **raw `<section>`** (not `BaseSection`)
  for full-bleed: `bg-tron-asphalt-800` / `bg-tron-primary-700`.
- Every `BaseSection` that the TOC links to gets `id="…"` + `class="scroll-mt-36"`.
- Prose column `max-w-4xl`; card grids `max-w-5xl`/`max-w-6xl`. Paragraph rhythm
  `space-y-4`; subsection blocks `space-y-10`; card grids `gap-4`/`gap-6`.
- Colors are `tron-` tokens or Tailwind built-ins — never `bg-[#…]` or `w-[…px]` (see
  the root CLAUDE.md Tailwind discipline).

---

## Stage 4 — Register in the index

Guides are **not** auto-discovered. Append one entry to the `guides` array in
`pages/resources/guides/index.vue` (rendered via `LazyDisplayCard`):

```ts
{
  title: "<Guide title>",
  description: "<short card description>",
  image: "guides/guide-<NN>.webp",   // the card thumbnail uploaded in Stage 2
  imageAlt: "",
  link: "/resources/guides/<slug>",
}
```

`<NN>` is the next free number after the existing entries. The `image` is the flat
`guides/guide-NN.webp` thumbnail (provider path), distinct from the `guides/<slug>/`
body-image folder.

---

## Stage 5 — Verify & clean up

1. **Renders in this worktree's dev server.** Guides are real routes (not the catch-all),
   so a missing file is a hard 404 — but still confirm you're hitting THIS worktree's
   server (ports 4001/4002 are often bound by siblings). Grep the served HTML, not the
   status code:
   ```bash
   URL=http://localhost:<port>/resources/guides/<slug>
   curl -s "$URL" | grep -oE '<title>[^<]*</title>'     # must contain the guide title
   curl -s "$URL" | grep -oc 'guides/<slug>'            # > 0 — body image srcs present
   ```
   If it's the wrong server, start this worktree's on a free port (see the `tron:news-item`
   skill's Stage 4 for the exact dev-server incantation). Have the user confirm the hero,
   TOC anchors, all sections, images, and FAQ render.
2. **Index card** — load `/resources/guides`, confirm the new card shows with its
   thumbnail and links to the guide.
3. **Images resolve** — spot-check `https://ik.imagekit.io/facilitron/guides/<slug>/<name>.webp`
   and the OG `…/og/og-<slug>.webp`.
4. **Links** — lint internal links in the new page; convert any
   `https://www.facilitron.com/...` to relative paths and confirm each target exists
   (`find pages -type f -name "*.vue" | grep -i <keyword>`). Watch the known trap:
   `/product/scheduling-and-reservations/` has no index — use
   `/product/facilitron-scheduling-and-reservations`.
5. **Prose & a11y** — before publish, offer `tron:prose-lint` on the copy and
   `tron:a11y-scan` against the rendered guide route (new pages should clear the WCAG gate).
6. **Clean up** — remove the dropped-in sources and `/tmp/guide-<slug>`. Only the new
   `.vue` page and the `index.vue` edit should end up tracked.

## Common pitfalls

- **Using `::fImg`/`::image-text` or markdown** — those are content-collection (news)
  components. Guides are Vue: use `<NuxtImg provider="imagekit">` and the palette above.
- **Forgetting the index entry** — the page works at its URL but never appears on
  `/resources/guides`. Always do Stage 4.
- **TOC anchor mismatch** — a `tocItems` `id` that doesn't match a `BaseSection id`
  scrolls nowhere. Keep them in sync; add `scroll-mt-36` so the sticky nav doesn't cover
  the heading.
- **Body image referenced by full URL** — use the relative provider path
  (`guides/<slug>/<name>.webp`); only the OG image is a full URL.
- **Duplicate H1** — the hero already renders the title; don't open the body with `#`.
- **`content/QuoteSimple.vue` instead of `section/QuoteSimple.vue`** — the content one
  lacks `backgroundColor`/`borderBottom`/`image`. Use `<SectionQuoteSimple>`.
- **Arbitrary Tailwind values** — `bg-[#…]`/`w-[…]` violate the design system. Add a
  `tron-` token to `tailwind.config.ts` if a needed color is missing.

## Reference: working example

`pages/resources/guides/preventive-maintenance-strategy.vue` is the cleanest end-to-end
example — hero + TOC, `v-for` data arrays (`tocItems`, `faqItems`, `implementationSteps`,
`comparisonTable`), the timeline pattern, the dark section, the mid-page CTA, and the
`useDynamicMeta` call with an OG image.
