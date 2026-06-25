---
name: toolkit-item
model: opus
effort: high
allowed-tools:
  - Bash
  - Read
  - Write
  - Task
  - AskUserQuestion
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

## Schema & component reference

The toolkit schema details live in **[`reference/schema.md`](reference/schema.md)** —
load it before authoring the destination markdown. It covers the front-matter options
(required vs optional fields, the `meta_*` SEO overrides), the page chrome the slug
renderer supplies (so you don't duplicate it), the two MDC components
(`::checklist-group`, `::faq`), the per-category skeleton (`sop` / `checklist` /
`template`), the source-to-toolkit conversion rules, and the internal-link reference
table. Don't re-derive any of that by reading sibling pages each time.

## Workflow checklist

Copy this and check off as you go:

```
- [ ] 0. Preflight — confirm you're in the marketing-pages repo (content.sh check-repo)
- [ ] 1. Read the source markdown — note title, audience, links, category
- [ ] 2. Reformat into the toolkit schema (see reference/schema.md) and write content/resources/toolkit/<slug>.md — all four required front-matter fields (title, description, date, category)
- [ ] 2.5. Lint links with lychee; rewrite facilitron.com → relative; verify internal paths
- [ ] 3. Build the trimmed PDF (LaTeX path via tron:md-to-pdf); open it and get user sign-off
- [ ] 4. Upload the PDF to ImageKit (toolkit/downloads/, with --name)
- [ ] 5. Upload (converting to .webp if needed) the card image to ImageKit (toolkit/, with --name)
- [ ] 6. Clean up the dropped-in source markdown and source image
- [ ] 7. Run the verification loop, then report paths + URLs + a dev test plan
```

## Shared scripted helpers

The deterministic backbone every content skill repeats (repo guard, slug, the
facilitron.com→relative link rewrite, internal-path validation) is one shared
wrapper — use it instead of hand-rolling these:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" check-repo                         # → {"ok":true,"isMarketingPages":true} (step 0 guard)
bash "$C" slug "<title>"                      # → {"ok":true,"slug":"…"}              (the slug in step 2)
bash "$C" rewrite-links content/resources/toolkit/<slug>.md   # facilitron.com→relative, in place (step 2)
bash "$C" check-link /product/works           # → {"ok":true,"exists":true,"resolved":"pages/…"} (verify links)
```

Each emits one JSON line; `ok:false` (exit 1) is a real verdict (wrong repo, dead
internal link). Smoke them with `bash ${CLAUDE_PLUGIN_ROOT:-…}/tools/content/test-content.sh`.
The PDF build, schema authoring, and component choices below stay judgment.

## Step-by-step

### 0. Preflight — confirm you're in the marketing-pages repo

The `tron` plugin can be installed in any Facilitron repo, but this skill writes
marketing-pages content (`content/resources/toolkit/`). **Verify the checkout first and
stop if it doesn't match** — `content.sh check-repo` is the guard (worktrees of
marketing-pages still match — shared remote):

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh" check-repo \
  | grep -q '"isMarketingPages":true' \
  || echo "✋ NOT in the marketing-pages repo — switch to that checkout first."
```

If the guard fails, ask the user to switch to the marketing-pages checkout
before continuing — don't write files into the wrong repo.

### 1. Read the source markdown

Find and read the source file. Note the title, intended audience, and any links it references.

### 2. Reformat into the toolkit schema

Write the destination file at `content/resources/toolkit/<slug>.md`. The full schema
spec — front-matter fields (required vs optional, the `meta_*` SEO overrides), the body
conventions, the per-category skeleton, and the internal-link reference table — lives in
**[`reference/schema.md`](reference/schema.md)**. Read it now and apply it.

Judgment calls that stay here:

- Pick `category` (`sop` / `checklist` / `template`) and derive the `slug` (the
  `content.sh slug` helper below). Confirm with the user when ambiguous.
- Match the house style by checking a recent sibling — most recent items set the
  `meta_*` SEO overrides.
- **Verify every internal link before saving** — a bad path is the #1 build-breaking
  pitfall. Use the link table in `reference/schema.md`, and when unsure run
  `find pages -type f -name "*.vue" | grep -i <keyword>` against the marketing-pages
  repo to confirm. Convert any `https://www.facilitron.com/...` URLs to relative paths.

### 2.5. Lint links with lychee

Before generating the PDF, scan the new markdown for broken links:

```bash
lychee --no-progress --cache --max-cache-age 1d --accept 200,206,429 content/resources/toolkit/<slug>.md
```

Note on flags: `--exclude-mail` is **not** a valid flag in the installed lychee — it errors out. Mail links aren't a concern for toolkit markdown anyway, so just omit it. `--base` is deprecated; use `--base-url` instead.

Rationale: catches typos in internal paths and dead external links _before_ they're embedded in the PDF artifact. Internal `/product/...` and `/resources/...` paths resolve as relative URLs without a base — that's expected and lychee will report them as `Cannot find file` rather than a 404. Either re-run with `--base-url https://www.facilitron.com` to verify those, or rely on the manual check from step 2's link table.

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

The pandoc fallback, if you do use it, is the `tron:md-to-pdf` skill's `build.ts` (it lives in the **md-to-pdf** skill dir, not this one). Resolve that dir robustly rather than assuming an env var:

```bash
m=md-to-pdf
MDP_DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$m}"
[ -e "$MDP_DIR/build.ts" ] || MDP_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$m ~/.claude/plugins/marketplaces/*/skills/$m; do [ -e "$d/build.ts" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$MDP_DIR/build.ts" ] || { echo "tron:toolkit-item: can't find md-to-pdf/build.ts — run /plugin update" >&2; exit 1; }
bun "$MDP_DIR/build.ts" /tmp/<slug>.md
```

Either way, output lands at `/tmp/facilitron-md-to-pdf/<slug>.pdf`. Open it (`open <pdf-path>`) and ask the user to confirm before uploading. See the `tron:md-to-pdf` skill for the full LaTeX workflow and the branded `template.tex` starter.

### 4. Upload the PDF to ImageKit

Always pass `--name` so ImageKit doesn't append a random suffix.

```bash
node "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs" upload \
  /tmp/facilitron-md-to-pdf/<slug>.pdf \
  --name <slug>.pdf \
  --folder toolkit/downloads
```

If you see a broker auth error or `cloudflared` is unavailable, the Cloudflare Access session may have expired. Tell them to run `cloudflared access login https://secrets.facilitron.work` and retry.

The `download:` front-matter field stores just the filename — the slug page builds the full URL via `https://ik.imagekit.io/facilitron/toolkit/downloads/<filename>`.

### 5. Upload the card image to ImageKit

The convert → upload → verify mechanics and the generate-card-from-references workflow are
shared — see [`../../tools/image/images-to-imagekit.md`](../../tools/image/images-to-imagekit.md).
Toolkit-specific parameters:

- **If a card image was provided** (often an `img.png` dropped in the repo root), convert it
  to webp with the shared `to-webp.sh` and upload to the `toolkit` folder as `<slug>.webp`.
  A `.webp` source can be uploaded as-is.
- **If no card image was provided,** generate one via the shared generate-from-references
  workflow with index folder `toolkit` and the existing toolkit cards as the reference set,
  then upload as `<slug>.webp`.

The toolkit naming convention is `.webp` — the list page builds the URL as `toolkit/<image>`
and the existing items are all `.webp`. The `image:` front-matter field stores just the
filename; the toolkit list page prefixes it with `toolkit/` for the ImageKit lookup, so the
uploaded filename must match the front-matter value exactly.

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

Before publish, offer a QA pass: `tron:prose-lint` on the markdown, `tron:link-check` on its links, and `tron:a11y-scan` against the rendered toolkit page.

Don't auto-commit or push — leave that to the user (or to a separate `git-commit` invocation).

## Verification loop

Before reporting, run a validate → fix → repeat pass until it's clean. Don't ship on
the first draft.

1. **Internal links resolve.** Run `content.sh check-link` for each internal path and
   the lychee pass (step 2.5). Any `Cannot find file` or hard 404 → fix the path in the
   markdown and re-run. Repeat until zero internal failures.
2. **Schema validity.** Confirm `category` is one of `sop` / `checklist` / `template`
   and the required fields are present (a bad enum fails the Nuxt build). If a local
   dev build is running, watch for prerender 404s and fix the named link.
3. **Content quality + Facilitron voice.** Re-read the body and **strip every em dash**
   — Facilitron voice uses none; rewrite the sentence with a comma, period, or
   parentheses instead. Run `tron:prose-lint` on the markdown; fix flagged issues and
   re-lint until clean. Check no `- [ ]` appears inside a `::checklist-group` (double
   box) and no empty fillable grid leaks onto the web page.
4. **Artifacts match.** Open the built PDF and confirm it carries only the actionable
   section. Confirm the uploaded ImageKit filenames exactly match the `download:` and
   `image:` front-matter values (exact-match lookup — a `.png` vs `.webp` mismatch
   breaks the card).

Only after this loop comes back clean do you move to step 7's report.

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
