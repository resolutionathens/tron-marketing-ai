---
name: toolkit-item
description: Add a new item (checklist, SOP, or template) to the Facilitron marketing-pages toolkit at /resources/toolkit. Handles the full workflow — reformatting raw markdown into the Nuxt-Content toolkit schema, writing to content/resources/toolkit/, building the branded PDF, uploading the PDF and card image to ImageKit, verifying internal links resolve, and cleaning up source files. Trigger whenever the user wants to "add a toolkit item", "create a new checklist/SOP/template for the toolkit", "publish this checklist", "add this to /resources/toolkit", drops a raw markdown file and references the toolkit, or shares a Confluence/Google Doc-style draft with phrases like "make this a toolkit item" or "let's get this on the resources page". Also trigger when the user mentions adding a downloadable resource for facility managers, schools, or districts where the destination is the marketing site's toolkit section.
---

# Facilitron Toolkit Item

Publish a new item to `/resources/toolkit` on the Facilitron marketing site. This skill exists because the workflow has many small steps that are easy to miss individually but together produce a working toolkit page with a card image, body content, and downloadable PDF.

## What gets produced

- A markdown file at `content/resources/toolkit/<slug>.md` with the correct front-matter schema
- A branded PDF uploaded to ImageKit at `toolkit/downloads/<slug>.pdf` (powers the Download PDF button)
- A card image uploaded to ImageKit at `toolkit/<slug>.webp` (powers the listing card and hero)
- The source markdown and source image cleaned up locally

## Subagents & model tiers

Unlike the `tron:news-item` and `tron:figma-to-imagekit` pipelines, this one is
**intentionally kept inline.** It produces a single document, and the work is
judgment-dominated — reformatting into the toolkit schema, internal-link
verification, deciding what belongs in the trimmed PDF — with only two deterministic
uploads at the end. There's no batch to fan out, so a subagent would add overhead
without saving context or time.

**One exception:** if the source is a large Confluence page rather than a dropped-in
file, reuse the `confluence` skill's Sonnet delegation to turn the storage format
into faithful markdown before you reformat — that keeps the raw XML out of context.
Everything after that (schema, links, PDF, uploads) stays inline.

## Inputs you need from the user

Ask for whichever isn't already obvious:

1. **Source markdown** — path to the raw content. Often dumped in the repo root or `/tmp`. May come from Confluence, a Google Doc, or a chat paste.
2. **Card image** — usually a `.webp` placed at the repo root, but PNG/JPG is common too (the user often drops it there as `img.png`, `unused.webp`, etc.). If absent, ask whether to grab one from Figma/ImageKit or skip the image for now. Non-webp inputs get converted in step 5 — accept whatever the user provides.
3. **Category** — must be one of `sop`, `checklist`, or `template`. Often inferable from the title ("Checklist for…" → `checklist`, "Standard Operating Procedure" → `sop`).
4. **Slug** — derive from the title (lowercase, hyphenated, drop "for", "the", etc. only if length is a problem). Confirm with the user when in doubt.

## Page anatomy & component reference

Don't re-derive this by reading sibling pages each time — the patterns below come
from the existing toolkit items and the slug renderer
(`pages/resources/toolkit/[...slug].vue`).

### What the slug page renders for you — do NOT author these

The page is mostly chrome you must not duplicate in the markdown body:

- **Hero** (`SectionHeroProduct`) shows an **eyebrow** = the category label (auto from
  `category`: `sop` → "Standard Operating Procedure", `checklist` → "Checklist",
  `template` → "Template"), then the `title`, the `description`, and a **Download PDF**
  button (when `download:` is set). So: don't repeat the title as an `#` H1, don't
  restate the category in the title, and don't write a download link in the body.
- A **second Download PDF button** auto-renders after the body, followed by a
  **social-share** row.
- A **"Schedule a Demo" CTA** (`SectionBasicCta`) closes every page — don't author
  your own closing CTA.
- **SEO** — Article JSON-LD and meta tags are emitted automatically from front matter.
- The body renders inside Tailwind **`.prose`** at `max-w-6xl`, so plain markdown
  (headings, tables, lists, bold) is styled automatically — no wrapper classes.

### Components used in toolkit bodies

Only two MDC block components appear in toolkit items — **`::checklist-group`** and
**`::faq`**. Everything else is plain markdown (`##`/`###` headings, paragraphs, `-`
bullets, pipe tables). `::image-text` and `::fImg` are **news-article** components —
do not use them here.

- **`::checklist-group`** (`components/content/ChecklistGroup.vue`) — wraps plain
  `- item` bullets; CSS draws the checkbox via `::before`. Use one group per logical
  checklist section (e.g. one per room or area). Never write `- [ ]` inside it
  (double box — see pitfalls).
- **`::faq`** (`components/content/Faq.vue`) — `faqItems: [{question, answer}, …]`;
  renders its own "FAQ" heading and emits FAQPage JSON-LD. Don't add a `## FAQ`
  heading above it.

### Structure by category

Every page opens with a 1–2 paragraph intro (no heading), then follows a consistent
skeleton:

- **`sop`** → `## What is <X>?` → `## Procedure: How to <X>` with numbered
  `### 1. … ### N.` steps → optional `## Compliance & Regulatory Standards` →
  `::faq`. SOPs use numbered steps — no `::checklist-group`, no tables.
- **`checklist`** → `## What Is / What Does <X> Include?` → a `## … Checklist`
  (often "…by Facility Area") section holding several `### <Area> Checklist`
  subsections, **each wrapping a `::checklist-group`** → usually a "Why it matters"
  or "Tips" section. Checklists typically have **no** `::faq`; a frequency table is
  optional.
- **`template`** → `## What Is <X>?` → `## Free <X> Templates` (or `## <X> Template`)
  presenting one or more **markdown tables** (e.g. `### Template 1/2/3`) →
  `## What to Include` / `## How to Use` → `::faq`. Templates are table-driven, not
  checklist-driven.

(The PDF, by contrast, carries only the actionable section — the procedure steps, the
checklist body, or the fillable grid. See step 3.)

## Step-by-step

### 0. Preflight — confirm you're in the marketing-pages repo

The `tron` plugin can be installed in any Facilitron repo, but this skill writes
marketing-pages content (`content/resources/toolkit/`). **Verify the checkout first and
stop if it doesn't match** — worktrees of marketing-pages still match (shared remote):

```bash
git remote get-url origin 2>/dev/null | grep -qi 'marketing-pages' \
  || echo "✋ NOT in the marketing-pages repo — this skill builds marketing-pages content. Switch to that checkout first."
```

If the guard prints the warning, ask the user to switch to the marketing-pages checkout
before continuing — don't write files into the wrong repo.

### 1. Read the source markdown

Find and read the source file. Note the title, intended audience, and any links it references.

### 2. Reformat into the toolkit schema

Write the destination file at `content/resources/toolkit/<slug>.md`. Use this front matter:

```yaml
---
title: <Title from source, sentence case or title case>
date: <today's date in YYYY-MM-DD>
description: <1–2 sentence summary; shown in the hero AND used as the default meta description>
image: <slug>.webp
category: sop | checklist | template
download: <slug>.pdf
meta_title: <optional SEO <title> override; keep under ~60 chars>
meta_description: <optional SEO meta override; distinct from description, keyword-rich, ~150–160 chars>
---
```

Schema source: `content.config.ts` `toolkit` collection. **Required:** `title`, `description`, `date`, `category` (a Zod enum — `sop`, `checklist`, `template`; invalid values fail the Nuxt build). **Optional:** `image`, `download`, `meta_title`, `meta_description`. The two `meta_*` fields override `title`/`description` for the page `<title>` and meta tags only (`[...slug].vue` falls back to `title`/`description` when they're absent) — set them when you want SEO copy that differs from the on-page hero. Most recent items do; check a sibling for the house style.

**Body conventions** — follow the **Page anatomy & component reference** section above (page chrome, the two components, and the per-category skeleton are documented there, so you don't need to re-read sibling pages each time):

- Open with a 1–2 paragraph intro. The hero on the slug page already shows title + description, so don't repeat the H1.
- Use `## Section` and `### Subsection` headings.
- Wrap checklist items in `::checklist-group` blocks. Inside the block use plain `- item` bullets — the `ChecklistGroup.vue` component renders each `<li>` with a CSS-drawn checkbox. The `tron:md-to-pdf` build script also auto-converts those bullets into task-list checkboxes for the PDF.
- Don't manually write `- [ ]` syntax inside `::checklist-group` — the website renders both the CSS box and the `<input type=checkbox>`, producing a double-box.
- Drop the source's "Choose your format / PDF / Excel" trailing section. The slug page (`pages/resources/toolkit/[...slug].vue`) auto-renders a Download PDF button when the front matter has a `download` field — in two places: in the hero (after the description, above the fold) and at the bottom of the body. You don't author either; they come from the `download:` field.
- Don't put empty fillable grids in the web markdown. Empty pipe-table cells render as faint ghost lines on the page — the fillable grid belongs in the PDF only. On the web, use a populated descriptive table (e.g. a `Field | Purpose` table) or underscore-style bullets instead.
- Drop any "Version Control" table the source contains (a single-row "v1.0 / Initial SOP creation" entry is noise on a public marketing page — git history is the source of truth, and old toolkit items have already had it removed).

**Internal links — verify each one before saving.** This is the #1 build-breaking pitfall. Common landing pages:

| Want to link to | Correct path | Notes |
| --- | --- | --- |
| Facilitron Works product | `/product/works` | has `index.vue` |
| Scheduling & Reservations product | `/product/facilitron-scheduling-and-reservations` | the directory `/product/scheduling-and-reservations/` has **no index page** — linking there is a 404 |
| Building Automation Systems | `/product/scheduling-and-reservations/bas` | exists |
| Facilitron FIT | `/product/facilitron-fit` | |
| Other toolkit items | `/resources/toolkit/<slug>` | |

When unsure, run `find pages -type f -name "*.vue" | grep -i <keyword>` against the marketing-pages repo to confirm.

Convert any `https://www.facilitron.com/...` URLs in the source to relative paths.

### 2.5. Lint links with lychee

Before generating the PDF, scan the new markdown for broken links:

```bash
lychee --no-progress --cache --max-cache-age 1d --accept 200,206,429 content/resources/toolkit/<slug>.md
```

Note on flags: `--exclude-mail` is **not** a valid flag in the installed lychee — it errors out. Mail links aren't a concern for toolkit markdown anyway, so just omit it. `--base` is deprecated; use `--base-url` instead.

Rationale: catches typos in internal paths and dead external links *before* they're embedded in the PDF artifact. Internal `/product/...` and `/resources/...` paths resolve as relative URLs without a base — that's expected and lychee will report them as `Cannot find file` rather than a 404. Either re-run with `--base-url https://www.facilitron.com` to verify those, or rely on the manual check from step 2's link table.

If lychee flags external links as 403/999 (anti-bot blocks), they're usually fine — note them but don't block on them. Hard 404s, DNS failures, and any internal path mistakes must be fixed before continuing.

For a pass that resolves internal links against the local dev server (most accurate):

```bash
# In another terminal: bun run dev
lychee --no-progress --base-url http://localhost:3000 content/resources/toolkit/<slug>.md
```

### 3. Build the PDF

The PDF is the **take-away artifact** — what someone prints and uses on a clipboard or shares with a vendor. It should contain only the actionable content. The web page already shows the title, description, intro paragraphs, FAQs, and version control for SEO and on-page context; repeating all of that in the PDF makes it longer and less useful.

**Don't build the PDF from the full toolkit markdown.** Build it from a trimmed temp file at `/tmp/<slug>.md` that contains:

- Front matter with just `title` (the build script reads it for the H1)
- The actionable section only — for an SOP, that's the `## Procedure: …` section and its numbered steps; for a checklist, it's the `## …Checklist` body with all `::checklist-group` blocks; for a template, it's the structured fillable section.

Strip these from the temp file even though they live on the web page: the lead-in paragraphs, `## What is …?`, `## Compliance & Regulatory Standards`, and the `::faq` block. (Version Control tables shouldn't be in the destination markdown at all — see the body conventions in step 2.)

Build the PDF via the `tron:md-to-pdf` skill. **Default to its LaTeX path** (copy `template.tex`, author the content, run `xelatex`) — for toolkit items in particular it produces a much cleaner artifact than the pandoc-from-markdown path. Templates with fillable forms and checklists with multi-column tables should always go LaTeX; the pandoc path is only worth it for a short prose-only SOP.

The pandoc fallback, if you do use it, is `bun "$CLAUDE_SKILL_DIR/build.ts" /tmp/<slug>.md` run from the `tron:md-to-pdf` skill's context (it resolves its own bundled `build.ts`).

Either way, output lands at `/tmp/facilitron-md-to-pdf/<slug>.pdf`. Open it (`open <pdf-path>`) and ask the user to confirm before uploading. See the `tron:md-to-pdf` skill for the full LaTeX workflow and the branded `template.tex` starter.

### 4. Upload the PDF to ImageKit

Always pass `--name` so ImageKit doesn't append a random suffix.

```bash
node "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs" upload \
  /tmp/facilitron-md-to-pdf/<slug>.pdf \
  --name <slug>.pdf \
  --folder toolkit/downloads
```

If you see `IMAGEKIT_PRIVATE_KEY environment variable is not set`, the user's 1Password agent isn't running. Tell them to start 1Password, then retry — don't try to source other env files.

The `download:` front-matter field stores just the filename — the slug page builds the full URL via `https://ik.imagekit.io/facilitron/toolkit/downloads/<filename>`.

### 5. Upload the card image to ImageKit

**If no card image was provided,** generate one with the `tron:gen-image` skill (codex
`image_gen`) seeded with the existing toolkit cards so it matches the set's style —
download a few references first (`curl -s -o /tmp/ref-N.webp https://ik.imagekit.io/facilitron/toolkit/<existing-slug>.webp`),
then prompt `tron:gen-image` with this item's subject. (Guide cards use the same
generate-from-references approach — see the `tron:guide-item` skill.)

The toolkit naming convention is `.webp` — the list page builds the URL as `toolkit/<image>` and the existing items are all `.webp`. If the user provided a `.webp`, upload as-is. If they provided a PNG or JPG (common — they'll often drop an `img.png` in the repo root), convert first:

```bash
cwebp -q 85 <source-image-path> -o /tmp/<slug>.webp
```

`cwebp` ships with the Homebrew `webp` package (`brew install webp`). Quality 85 lands around 30–60 KB for a 1600px-wide card image, which is well under the listing-page budget.

Then upload:

```bash
node "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs" upload \
  /tmp/<slug>.webp \
  --name <slug>.webp \
  --folder toolkit
```

Same env-var caveat as the PDF upload. The `image:` front-matter field stores just the filename — the toolkit list page prefixes it with `toolkit/` for ImageKit lookup.

### 6. Clean up source files

Remove the original source markdown and source image now that they're published:

```bash
rm <source-markdown-path>
rm <source-image-path>
```

Don't remove anything in `content/resources/toolkit/` — only the unstructured source the user dropped in.

### 7. Verify and report

Tell the user:
- Path of the new toolkit markdown file
- ImageKit URLs for the PDF and image (so they can sanity-check)
- A short test plan they can run on dev: load `/resources/toolkit`, click the new card, click Download PDF

Don't auto-commit or push — leave that to the user (or to a separate `git-commit` invocation).

## Common pitfalls

- **Prerender 404 on dev build.** Almost always a bad internal link. The Nitro error names both the broken URL and the page that linked to it — fix the markdown, push, and the dev build will retry.
- **Double-checkboxes on the rendered page.** Caused by writing `- [ ]` inside a `::checklist-group`. Use plain `- ` bullets — the CSS draws the box.
- **Card with no image.** Image filename mismatch between front matter and ImageKit. The list page builds the URL as `toolkit/<image>`, so the front-matter value is just the filename, not a path.
- **Download button missing.** No `download:` field in front matter, or the PDF didn't actually upload. Check the ImageKit URL by opening it directly.
- **Random suffix in uploaded filename.** Forgot `--name` on the imagekit upload. Re-upload with `--name` set; old file can be deleted from ImageKit if needed.
- **Card image is a .png on ImageKit but front matter says .webp** (or vice versa). The list page does an exact filename lookup. Convert PNG/JPG sources to `.webp` before upload (step 5) so the front matter and the uploaded asset agree — don't paper over a mismatch by editing the front matter to `.png`, since that breaks the visual consistency of the listing.
- **PDF is bloated with marketing copy.** Built from the full toolkit markdown instead of a trimmed temp file. The PDF should be the actionable artifact only (procedure / checklist body) — see step 3.
- **Tables in the PDF look squished or break awkwardly.** That's the pandoc path's ceiling — use the LaTeX path instead (it's the default now; see `tron:md-to-pdf`).
- **Ghost lines where a table should be on the web page.** An empty pipe-table (header row + blank cells) renders as faint horizontal rules with no structure. Fillable grids belong in the PDF only — on the web, replace with a populated `Field | Purpose` table or underscore-style bullets.
- **`lychee: unexpected argument '--exclude-mail'`.** That flag isn't valid in the installed lychee. Omit it (see step 2.5). Use `--base-url`, not the deprecated `--base`.

## Reference: working example

See `content/resources/toolkit/hvac-preventive-maintenance-checklist-for-school-facilities.md` for a recent end-to-end example of the format, including front matter, intro, `::checklist-group` blocks, link conventions, and the final Download section that defers to the auto-rendered button.
