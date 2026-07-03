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
description: Add a new item (checklist, SOP, or template) to the Facilitron marketing-pages toolkit at /resources/toolkit. Handles the full workflow — reformatting raw markdown into the Nuxt-Content toolkit schema, writing to content/resources/toolkit/, building the branded PDF, uploading the PDF and card image to ImageKit, verifying internal links resolve, and cleaning up source files. Trigger whenever the user wants to "add a toolkit item", "create a new checklist/SOP/template for the toolkit", "publish this checklist", "add this to /resources/toolkit", drops a raw markdown file and references the toolkit, or shares a Confluence/Google Doc-style draft.
---

# Facilitron Toolkit Item

Publish a new item to `/resources/toolkit` on the marketing site — a checklist, SOP, or template with a card image, body content, and downloadable PDF.

## Checklist

```
- [ ] 0. Preflight — confirm marketing-pages repo (content.sh check-repo)
- [ ] 1. Read the source markdown — note title, audience, links, category
- [ ] 2. Reformat into toolkit schema, write content/resources/toolkit/<slug>.md
- [ ] 2.5. Lint links with lychee; rewrite facilitron.com → relative; verify internal paths
- [ ] 3. Build trimmed PDF via tron:md-to-pdf (LaTeX path); open for user sign-off
- [ ] 4. Upload PDF to ImageKit (toolkit/downloads/)
- [ ] 5. Upload card image (convert to .webp) to ImageKit (toolkit/)
- [ ] 6. Clean up source files
- [ ] 7. Verify loop + report paths/URLs
```

## What gets produced

- `content/resources/toolkit/<slug>.md` — Nuxt-Content, toolkit schema
- Branded PDF at `toolkit/downloads/<slug>.pdf`
- Card image at `toolkit/<slug>.webp`
- Source files cleaned up

## Inputs

| Input | Notes |
|-------|-------|
| Source markdown | Path to raw content (repo root, /tmp, Confluence, paste) |
| Card image | Often `.webp`/`.png` dropped in repo root. If absent, ask or generate via `tron:gen-image` |
| Category | `sop`, `checklist`, or `template` |
| Slug | Lowercase-hyphenated from title. Confirm if ambiguous. |

## Schema & component reference

See [`reference/schema.md`](reference/schema.md) for: front-matter options, per-category skeleton, source-to-toolkit conversion rules, internal-link reference table.

## Shared helper (plugin tools)

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" slug "<title>"
bash "$C" rewrite-links content/resources/toolkit/<slug>.md
bash "$C" check-link /product/<path>

GENCARD="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/generate-card.sh"
```

## Step by step

### 0. Preflight — marketing-pages repo guard
```bash
bash "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh" check-repo | grep -q '"isMarketingPages":true' \
  || { echo "✋ NOT in marketing-pages — switch checkouts first." >&2; exit 1; }
```

### 1. Read source
Find and read the source markdown. Note title, audience, links, category.

### 2. Reformat into toolkit schema
Write `content/resources/toolkit/<slug>.md`. Four required front-matter fields: `title`, `description`, `date`, `category`. Follow the per-category skeleton in `reference/schema.md`.

**Internal links — rewrite, then verify each before saving:** run `bash "$C" rewrite-links content/resources/toolkit/<slug>.md` (facilitron.com → relative), then `bash "$C" check-link` each internal path. Known trap: `/product/scheduling-and-reservations/` has no index page — use `/product/facilitron-scheduling-and-reservations`. Full path table: [`../../tools/content/internal-links.md`](../../tools/content/internal-links.md)

### 2.5. Lint links
```bash
lychee --no-progress --cache --max-cache-age 1d --accept 200,206,429 content/resources/toolkit/<slug>.md
```
`--exclude-mail` is **not valid** in the installed lychee — omit it. Internal relative paths report as "Cannot find file" — that's expected; re-run with `--base-url http://localhost:3000` against the dev server for those.

### 3. Build the PDF
The PDF is the **take-away artifact** — actionable content only. Build from a **trimmed** temp file at `/tmp/<slug>.md` containing only the actionable section (procedure steps, checklist body). Strip lead-in paragraphs, "What is...", FAQ, and version-control tables.

Use the **LaTeX path** via `tron:md-to-pdf` (branded template, better tables/forms). Pandoc fallback only for short prose-only SOPs. Output at `/tmp/facilitron-md-to-pdf/<slug>.pdf`. Open it and get user sign-off before uploading.

### 4. Upload PDF to ImageKit
```bash
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"
node "$IK" upload /tmp/facilitron-md-to-pdf/<slug>.pdf --name <slug>.pdf --folder toolkit/downloads
```
Always pass `--name` to avoid ImageKit's random suffix. If you see a broker auth error, the Cloudflare Access session expired — run `cloudflared access login https://secrets.facilitron.work`.

### 5. Upload card image
Run the image pipeline — copy/rename the source to `<slug>.png` so the output is `<slug>.webp`:

```bash
PIPE="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/image-pipeline.sh"
mkdir -p /tmp/toolkit-card
cp <source-image> /tmp/toolkit-card/<slug>.png
CARD=$(bash "$PIPE" --src /tmp/toolkit-card --dest toolkit)
# CARD: {"<slug>.webp": "https://ik.imagekit.io/facilitron/toolkit/<slug>.webp"}
```

If no image was provided, generate one from existing toolkit cards as style references: `"$GENCARD"` with `--folder toolkit --name "<slug>.webp" --size 1536x1024` (toolkit cards are landscape — 1600×901 after webp conversion from the 1536×1024 generation size). Invocation + result parsing live in the "Generate an index/card thumbnail from references" section of [`../../tools/image/images-to-imagekit.md`](../../tools/image/images-to-imagekit.md), which also holds the convert/upload mechanics.

### 6. Clean up
Remove source markdown and source image files. Don't touch `content/resources/toolkit/`.

### 7. Verify & report
Validate → fix → repeat until clean. Check:
- Internal links resolve (lychee + check-link)
- Category is valid enum
- No em-dashes (Facilitron voice)
- `tron:prose-lint` and `tron:a11y-scan` pass
- PDF carries only actionable content
- ImageKit filenames match front-matter values exactly

Report: file path, ImageKit URLs, and a short test plan (load `/resources/toolkit`, click card, click Download PDF). Don't auto-commit.

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Prerender 404 on dev build | Almost always a bad internal link. Fix and push. |
| Double-checkboxes on rendered page | Don't write `- [ ]` inside `::checklist-group` — use plain `- ` bullets |
| Card with no image | Front-matter `image:` value must match uploaded filename exactly |
| Download button missing | No `download:` field in front matter, or PDF didn't upload |
| Random suffix in uploaded filename | Forgot `--name` on upload. Re-upload with `--name`. |
| Card is .png on ImageKit but front matter says .webp | Convert to .webp before upload so they agree |
| PDF bloated with marketing copy | Build from trimmed temp file (actionable section only) |
| Tables in PDF look squished | LaTeX path handles this better than pandoc |