---
name: toolkit-item
model: opus
effort: high
fallback:
  cost: high
  skip_when: "Use tron:toolkit-item only when publishing a full toolkit item. Use tron:md-to-pdf for a standalone PDF build."
  stage_skips:
    - stage: "Stage 3 — Build PDF"
      skip_when: "Item needs no downloadable PDF"
    - stage: "Stage 4 — Upload PDF"
      skip_when: "No PDF was built"
    - stage: "Stage 5 — Upload card image"
      skip_when: "Item already has a card image on ImageKit"
allowed-tools:
  - Bash
  - Read
  - Write
  - Task
  - AskUserQuestion
description: "Add a new item (checklist, SOP, or template) to the Facilitron marketing-pages toolkit at /resources/toolkit. Handles the full workflow: reformatting raw markdown into the repo's declared toolkit schema, writing it to the destination the repo's content profile resolves, building the branded PDF, uploading the PDF and card image to ImageKit, verifying internal links resolve, and cleaning up source files. Use for 'add a toolkit item', 'create a new checklist/SOP/template for the toolkit', 'publish this checklist', or dropping a raw markdown file and referencing the toolkit."
scout:
  surface: developer
  effects: [publish, cdn]
  inputs:
    - key: topic
      label: "Toolkit item"
      type: text
      required: true
    - key: notes
      label: "Notes"
      type: textarea
      required: false
---

# Facilitron Toolkit Item

Publish a new item to `/resources/toolkit` on the marketing site — a checklist, SOP, or template with a card image, body content, and downloadable PDF.

## Checklist

```
- [ ] 0. Preflight — confirm marketing-pages repo (content.sh check-repo) + confirm the repo declares a profile
- [ ] 1. Read the source markdown — note title, audience, links, category; derive + confirm the slug
- [ ] 2. Resolve the toolkit pipeline against the confirmed slug, reformat into the profile's schema, write the item at the resolved destination
- [ ] 2.5. Lint links with lychee; rewrite facilitron.com → relative; verify internal paths
- [ ] 3. Build trimmed PDF via tron:md-to-pdf (LaTeX path); open for user sign-off
- [ ] 4. Upload PDF to ImageKit (folder from `image toolkit pdf`)
- [ ] 5. Upload card image (convert to .webp) to ImageKit (folder from `image toolkit card`)
- [ ] 6. Clean up source files
- [ ] 7. Verify loop + report paths/URLs
```

## What gets produced

The repo owns the paths — this skill owns the item. Read every destination from
the consuming repo's content profile rather than typing it:

- The item file — `pipeline toolkit → .destination`
- The branded PDF — `image toolkit pdf → .uploadFolder` / `.uploadName`
- The card image — `image toolkit card → .uploadFolder` / `.uploadName`
- Source files cleaned up

## Inputs

| Input | Notes |
|-------|-------|
| Source markdown | Path to raw content (repo root, /tmp, Confluence, paste) |
| Card image | Often `.webp`/`.png` dropped in repo root. If absent, ask or generate via `tron:gen-image` |
| Category | One of the values in the profile's `collection toolkit → .enums.category` |
| Slug | Lowercase-hyphenated from title. Confirm if ambiguous. |

## Schema & component reference

See [`reference/schema.md`](reference/schema.md) for: front-matter options, per-category skeleton, source-to-toolkit conversion rules, internal-link reference table.

## Shared helper (plugin tools)

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" slug "<title>"
bash "$C" rewrite-links "$DEST"
bash "$C" check-link /product/<path>

GENCARD="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/generate-card.sh"
```

## Step by step

### 0. Preflight — repo guard + profile availability

Two separate things. The guard decides **whether** you may write here; the profile
says **where**. Never skip the guard because the profile resolved.

Neither needs the slug, so both run first:

```bash
bash "$C" check-repo | grep -q '"isMarketingPages":true' \
  || { echo "✋ NOT in marketing-pages — switch checkouts first." >&2; exit 1; }
bash "$C" profile >/dev/null || exit 1   # this repo declares a content profile at all
```

**Do not resolve the pipeline yet** — `destination` is slug-derived, and the slug comes
from the title you read in step 1. The resolve step is the top of step 2.

If either command fails, **stop and report what was missing** — the message names
the file it looked for and what it needed. Never fall back to a remembered path.

### 1. Read source
Find and read the source markdown. Note title, audience, links, category. Derive and
confirm the slug from the title.

### 2. Resolve the pipeline, then reformat into the toolkit schema

The slug is fixed now, so resolve:

```bash
PIPE_JSON="$(bash "$C" pipeline toolkit --slug <slug>)" || exit 1   # fails loudly if undeclared
DEST="$(jq -r .destination <<<"$PIPE_JSON")"
ROUTE="$(jq -r .route      <<<"$PIPE_JSON")"
SCHEMA="$(bash "$C" collection toolkit)" || exit 1
```

`pipeline` refuses a destination that still contains a literal `{slug}` or that escapes
the repo, so a successful call means `$DEST` is safe to write to.

Write the file at `$DEST`. The required front-matter fields, the optional ones, and
the valid `category` values all come from `$SCHEMA` — do not carry them in your head:

```bash
jq -r '.required[]'        <<<"$SCHEMA"
jq -r '.optional[]'        <<<"$SCHEMA"
jq -r '.enums.category[]'  <<<"$SCHEMA"   # an invalid value fails the build
```

Follow the per-category skeleton in `reference/schema.md`.

**Internal links — rewrite, then verify each before saving:** run `bash "$C" rewrite-links "$DEST"` (facilitron.com → relative), then `bash "$C" check-link` each internal path. The repo's declared link traps: `bash "$C" profile | jq -r '.internalLinks.exceptions[]? | "\(.wrong) → \(.right)"'`. Full flow: [`../../tools/content/internal-links.md`](../../tools/content/internal-links.md)

### 2.5. Lint links
```bash
lychee --no-progress --cache --max-cache-age 1d --accept 200,206,429 "$DEST"
```
`--exclude-mail` is **not valid** in the installed lychee — omit it. Internal relative paths report as "Cannot find file" — that's expected; re-run with `--base-url http://localhost:3000` against the dev server for those.

### 3. Build the PDF
The PDF is the **take-away artifact** — actionable content only. Build from a **trimmed** temp file at `/tmp/<slug>.md` containing only the actionable section (procedure steps, checklist body). Strip lead-in paragraphs, "What is...", FAQ, and version-control tables.

Use the **LaTeX path** via `tron:md-to-pdf` (branded template, better tables/forms). Pandoc fallback only for short prose-only SOPs. Output at `/tmp/facilitron-md-to-pdf/<slug>.pdf`. Open it and get user sign-off before uploading.

### 4. Upload PDF to ImageKit
```bash
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"
PDF="$(bash "$C" image toolkit pdf --slug <slug>)" || exit 1
node "$IK" upload /tmp/facilitron-md-to-pdf/<slug>.pdf \
  --name "$(jq -r .uploadName <<<"$PDF")" --folder "$(jq -r .uploadFolder <<<"$PDF")"
```
Always pass `--name` to avoid ImageKit's random suffix. The front-matter `download:` value is `$(jq -r .reference <<<"$PDF")` — copy it verbatim; the renderer may prefix the folder itself, so adding it by hand produces a doubled path and a dead button. If you see a broker auth error, the Cloudflare Access session expired — run `cloudflared access login https://secrets.facilitron.work`.

### 5. Upload card image
Run the image pipeline — copy/rename the source so the output name matches what the profile declares:

```bash
PIPE="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/image-pipeline.sh"
CARD_SPEC="$(bash "$C" image toolkit card --slug <slug>)" || exit 1
mkdir -p /tmp/toolkit-card
cp <source-image> "/tmp/toolkit-card/$(jq -r '.uploadName | sub("\\.webp$";".png")' <<<"$CARD_SPEC")"
CARD=$(bash "$PIPE" --src /tmp/toolkit-card --dest "$(jq -r .uploadFolder <<<"$CARD_SPEC")")
```

The front-matter `image:` value is `$(jq -r .reference <<<"$CARD_SPEC")` — again, verbatim.

If no image was provided, generate one from existing toolkit cards as style references: `"$GENCARD"` with `--folder "$(jq -r .uploadFolder <<<"$CARD_SPEC")" --name "$(jq -r .uploadName <<<"$CARD_SPEC")" --size 1536x1024` (toolkit cards are landscape — 1600×901 after webp conversion from the 1536×1024 generation size). Invocation + result parsing live in the "Generate an index/card thumbnail from references" section of [`../../tools/image/images-to-imagekit.md`](../../tools/image/images-to-imagekit.md), which also holds the convert/upload mechanics.

### 6. Clean up
Remove source markdown and source image files. Don't touch the collection directory (`collection toolkit → .dir`).

### 7. Verify & report
Validate → fix → repeat until clean. Check:
- Internal links resolve (lychee + check-link)
- Category is one of `jq -r '.enums.category[]' <<<"$SCHEMA"`
- Facilitron voice ([tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md)) and the
  brand voice ([tools/voice/marketing-copy.md](../../tools/voice/marketing-copy.md)): second person
  and imperative throughout, never "we"
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