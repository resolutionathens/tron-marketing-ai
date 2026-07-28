# Guide page — component & block reference

Reference material for Stage 3 (Compose the page). The SKILL.md owns the workflow and
judgment; this file is the palette, the skeleton, and the mapping/styling rules you
follow when composing the guide page. Its path is `$DEST`, resolved in the SKILL.md
preflight from the repo's content profile — never assume a `pages/…` location. Mirror
an existing guide such as `preventive-maintenance-strategy.vue` (a sibling of `$DEST`)
for the full pattern.

## Contents

- Canonical section skeleton
- Component palette (only what guides use)
- How draft content maps to components
- `<script setup>` conventions
- Styling rules (tron tokens only — no arbitrary values)
- Reference: working example

## Canonical section skeleton

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

## Component palette (only what guides use)

| Component            | Key props                                                                                                                                                                                                   | Notes                                                                                                                                                                                                                                      |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `SectionHeroProduct` | `eyebrow`_, `title`_, `description`, `ctaText`, `ctaLink`, `ctaVariant` (`primary-alt`\|`primary`\|`secondary`\|`tertiary`\|`inverse`), `backgroundColor`\*, `backgroundImage`, `heroImage`, `heroImageAlt` | Full-bleed hero. Use `background-color="bg-tron-primary-600"` + `:background-image="IMAGEKIT_BG_GRID"`. `heroImage` is a provider path string (component renders it).                                                                      |
| `NavPillarSubnav`    | `links`\* (`[{id, label}]`), `ariaLabel`                                                                                                                                                                    | Sticky TOC; each `id` must match a `BaseSection id`.                                                                                                                                                                                       |
| `SectionIntro`       | `headline`\*, `eyebrow`, `description`, `headlineTag` (`h1`\|`h2`\|`h3`, default `h2`), `headlineStyle` (`h1`…`h4`), `textAlign` (default `center`)                                                         | Section header. Guides always use `headline-tag="h2" headline-style="h1"`. Has a `#description` slot for rich content.                                                                                                                     |
| `DisplayFeatureCard` | `variant` (`default`\|`product`\|`alternative`\|`compact`\|`callout`), `icon` (lucide name), `title`, `description`, `accentColor`, `titleTag`                                                              | Workhorse card. `callout` = highlighted takeaway block (default slot for prose); `alternative` = light-blue grid card; `compact` = inline row (used in timelines/insets); `product` = large brand card with `eyebrow`/`ctaText`/`ctaLink`. |
| `DisplayIconHeading` | `icon`_, `title`_, `tag` (default `h3`)                                                                                                                                                                     | Icon-badge + heading row. Optional sugar for the inline icon+`h3` pattern.                                                                                                                                                                 |
| `SectionQuoteSimple` | `quote`_, `quotee`_, `position`, `location`, `backgroundColor`, `borderBottom` (default `true`), `image`, `imageAlt`                                                                                        | Pull quote. Use the `section/` one, NOT `content/QuoteSimple.vue`.                                                                                                                                                                         |
| `SectionAccordion`   | `items`\* (`[{question, answer}]`), `name`                                                                                                                                                                  | FAQ; native `<details>`. Feed it `faqItems`.                                                                                                                                                                                               |
| `SectionCtaProduct`  | `title`_, `ctaText`_, `ctaLink`, `description`, `variant` (`dark`\|`dark-split`\|`dark-image`\|`blue`), `backgroundColor`\*                                                                                 | A componentized CTA — an alternative to the raw mid-page CTA `<section>`. `title` is `v-html` — no untrusted input.                                                                                                                        |
| `BaseSection`        | `padding` (default `py-12`), `class`, `prose` (default `true`), `grid`, `columns`, `gap`                                                                                                                    | Section wrapper with prose styling. Standard content padding is `py-16 px-4`; first section `pt-16 px-4`.                                                                                                                                  |
| `BaseButton`         | `variant` (`primary`\|`secondary`\|`tertiary`\|`inverse`\|`primary-alt`), `size` (`sm`\|`md`\|`lg`\|`xl`), `link`, `target`                                                                                 | Pill button. `iconOnly` requires an `aria-label`.                                                                                                                                                                                          |
| `BaseEyebrow`        | `color` (`primary`\|`primary-light`\|`secondary`\|`secondary-light`\|`accent`), `textAlign`                                                                                                                 | Standalone uppercase label (usually you get this via `SectionIntro`'s `eyebrow`).                                                                                                                                                          |

(`*` = required prop. Icons are `<Icon name="lucide:…" aria-hidden="true" />`.)

## How draft content maps to components

- **A prose section** → `BaseSection` > `SectionIntro` (heading) + `div.mx-auto.max-w-4xl.space-y-4` of `<p>`s.
- **A "key takeaway" callout** → `DisplayFeatureCard variant="callout" icon="lucide:lightbulb" title="Key Takeaway"` with prose in the default slot.
- **A list of benefits/points** → a grid of `DisplayFeatureCard variant="alternative"`:
  `div.mx-auto.mt-10.grid.max-w-5xl.gap-4.sm:grid-cols-2.lg:grid-cols-3`.
- **A numbered process** → a timeline: a `v-for` over a `steps` array rendering numbered
  badges + `DisplayFeatureCard variant="compact"` (see `preventive-maintenance-strategy.vue`).
- **An "at a glance" / best-practices block** → the dark raw `<section class="bg-tron-asphalt-800 …">` with a `v-for` of `bg-white/5` bordered cards (full-bleed, so NOT `BaseSection`).
- **An FAQ** → a `faqItems` array → `SectionAccordion`.
- **Images** → `<NuxtImg provider="imagekit" src="<the `reference` from `content.sh image guides body`>" alt="…" class="w-full rounded-lg" sizes="500px md:1200px lg:1800px" />`. Copy `reference` verbatim — the body role's format differs from the OG role's. `alt` is required (WCAG) — write a real description, never the source filename.

## `<script setup>` conventions

```ts
definePageMeta({
  documentDriven: { page: false, surround: false },
  layout: "news",
});

// Data arrays consumed by the template:
const tocItems = [
  { id: "introduction", label: "Introduction" } /* one per BaseSection id */,
];
const faqItems = [{ question: "…", answer: "…" } /* … */];
const ctaActions = [
  {
    icon: "lucide:calendar-check",
    title: "Schedule a Demo",
    description: "…",
    link: "/demo-signup",
  } /* 3 */,
];
// plus any domain arrays for grids/timelines, all flat: { icon, title, description }

const route = useRoute();
const title = "The Complete Guide To …";
const description = "…"; // keyword-rich, ~150–160 chars

useDynamicMeta(
  title,
  description,
  route.path,
  "<the `reference` from `content.sh image guides og`>", // already the full CDN URL
);
```

`IMAGEKIT_BG_GRID` (from `utils/imagekit.ts`) and `useDynamicMeta` are auto-imported —
no `import` line needed. Guide detail pages do **not** call `useJsonLd`/`useArticleSchema`
(only the index does). Do **not** add a `#`/H1 in the body — the hero renders the title.

## Styling rules (tron tokens only — no arbitrary values)

- Alternate section backgrounds: white (no bg class) ↔ `class="bg-tron-sand-50"`.
- Dark emphasis sections and the mid-page CTA use **raw `<section>`** (not `BaseSection`)
  for full-bleed: `bg-tron-asphalt-800` / `bg-tron-primary-700`.
- Every `BaseSection` that the TOC links to gets `id="…"` + `class="scroll-mt-36"`.
- Prose column `max-w-4xl`; card grids `max-w-5xl`/`max-w-6xl`. Paragraph rhythm
  `space-y-4`; subsection blocks `space-y-10`; card grids `gap-4`/`gap-6`.
- Colors are `tron-` tokens or Tailwind built-ins — never `bg-[#…]` or `w-[…px]` (see
  the root CLAUDE.md Tailwind discipline).

## Reference: working example

`preventive-maintenance-strategy.vue`, alongside `$DEST`, is the cleanest end-to-end
example — hero + TOC, `v-for` data arrays (`tocItems`, `faqItems`, `implementationSteps`,
`comparisonTable`), the timeline pattern, the dark section, the mid-page CTA, and the
`useDynamicMeta` call with an OG image.
