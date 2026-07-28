---
name: guide-item
model: opus
effort: high
fallback:
  cost: high
  skip_when: "Use tron:guide-item only when publishing a full guide. If only a draft or partial update is needed, skip."
  stage_skips:
    - stage: "Stage 1 — Intake"
      skip_when: "Confluence draft already pulled and body.html exists"
    - stage: "Stage 2 — Images"
      skip_when: "Guide has no images or images are already uploaded"
    - stage: "Stage 5 — Verify"
      skip_when: "User wants draft-only output without verification"
description: "Publish a new long-form guide to /resources/guides on the Facilitron marketing site from a Jira ticket whose description links a Confluence draft. A guide is a bespoke Vue PAGE built from section/display components, not a Nuxt-Content markdown file; this skill owns the full pipeline: Confluence fetch, image conversion to webp + ImageKit upload, page composition, guides-index registration, and SEO meta. Use for 'start the guide', 'build out this guide', 'turn this Confluence draft into a guide page', or a Jira 'Guide' or 'Pillar' ticket with a Confluence link. Even if the user describes only one part, this skill owns the whole pipeline."
allowed-tools:
  - Bash
  - Read
  - Write
  - Task
  - AskUserQuestion
scout:
  surface: developer
  effects: [publish, cdn]
  inputs:
    - key: topic
      label: "Guide topic"
      type: text
      required: true
    - key: notes
      label: "Notes"
      type: textarea
      required: false
---

# Facilitron Guide Item

Publish a new guide under `/resources/guides` — a **hand-composed Vue page** (not a Nuxt-Content markdown file), built from section/display components, plus a manual entry in the guides index.

## Checklist

```
- [ ] Preflight: confirm marketing-pages repo (content.sh check-repo) + confirm the repo declares a profile
- [ ] Stage 1: read ticket + fetch Confluence draft + images; confirm slug
- [ ] Stage 2: resolve the guides pipeline against the confirmed slug, then convert body images to webp + upload to the declared body folder; OG image; index card thumbnail
- [ ] Stage 3: compose the guide page from the guide palette
- [ ] Stage 4: register it in the index (the profile says whether this is needed)
- [ ] Stage 5: verify renders, card shows, images + links resolve, prose-lint + a11y-scan
- [ ] Clean up: remove /tmp/guide-<slug> and dropped-in sources
```

## What gets produced

The repo owns the paths — this skill owns the guide. Read every destination from
the consuming repo's content profile rather than typing it:

- The guide page — `pipeline guides → .destination`
- Body images — `image guides body → .uploadFolder` / `.uploadName` (via `<NuxtImg provider="imagekit">`)
- OG image — `image guides og`
- Card thumbnail — `image guides card --index <NN>` (next free number)
- An index entry, when `pipeline guides → .registration.mode` is `manual`
- Source files cleaned up

## Inputs

| Input | Source |
|-------|--------|
| Jira key | Branch name (`<KEY>-<slug>`) |
| Confluence draft + SEO keywords | Ticket description (inlineCard) |
| Images | Confluence draft, or ask for Figma/ImageKit source |
| Slug | Derived from title, lowercase-hyphenated. Confirm before uploading. |

## Shared helper (plugin tools)

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" slug "<title>"
bash "$C" rewrite-links "$DEST"
bash "$C" check-link /product/<path>

GENCARD="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/generate-card.sh"
```

## Preflight — repo guard + profile availability

Two separate things. The guard decides **whether** you may write here; the profile
says **where**. Never skip the guard because the profile resolved.

Neither needs the slug, so both run before Stage 1:

```bash
bash "$C" check-repo | grep -q '"isMarketingPages":true' \
  || { echo "✋ NOT in marketing-pages — switch checkouts first." >&2; exit 1; }
bash "$C" profile >/dev/null || exit 1   # this repo declares a content profile at all
```

**Do not resolve the pipeline yet** — `destination` and `route` are slug-derived, and
the slug is not fixed until Stage 1 confirms it. The resolve step is the top of Stage 2.

## Stage 1 — Intake

```bash
acli jira workitem view <KEY> --json
# Extract Confluence URL + target keywords

TOOLS="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools"
"$TOOLS/confluence/fetch-confluence.sh" <confluence-url> /tmp/guide-<slug>
```

Writes `/tmp/guide-<slug>/body.html` and referenced images in `/tmp/guide-<slug>/raw/`. Delegate the storage→markdown transform to the **`confluence-transformer` agent** — hand it the path to `body.html`. It returns `<markdown>…</markdown>` (extract the body) and `<images>…</images>` (one filename per line, document order). Keep the raw XML out of context.

## Stage 2 — Images

The slug is fixed now, so resolve the pipeline first:

```bash
PIPE_JSON="$(bash "$C" pipeline guides --slug <slug>)" || exit 1   # fails loudly if undeclared
DEST="$(jq -r .destination           <<<"$PIPE_JSON")"  # where the .vue page goes
ROUTE="$(jq -r .route                <<<"$PIPE_JSON")"
REG_MODE="$(jq -r .registration.mode <<<"$PIPE_JSON")"  # auto | manual
REG_FILE="$(jq -r .registration.file <<<"$PIPE_JSON")"  # the index to edit when manual
jq -c '.components' <<<"$PIPE_JSON"                     # allowed / forbidden, with the why
```

The destination is a **Vue page path**, and it is not necessarily `pages/…` — a repo
on Nuxt 4 uses an `app/` srcDir. That is exactly the kind of fact this skill no longer
carries: use `$DEST`. `pipeline` refuses a destination that still contains a literal
`{slug}` or that escapes the repo, so a successful call means `$DEST` is safe to write.

A guide has three image roles, and **they do not use the same reference format** —
this is the single most error-prone step in the skill. The card is numbered, so read
its prefix from the profile (loudly — never assume a default) and find the next index:

```bash
CARD_PREFIX="$(jq -er '(.images[]|select(.role=="card")).indexPrefix' <<<"$PIPE_JSON")" \
  || { echo "profile declares no indexPrefix for the guides card role — cannot number the card" >&2; exit 1; }
CARD_FOLDER="$(jq -r '(.images[]|select(.role=="card")).cdnFolder' <<<"$PIPE_JSON")"
# list existing names in $CARD_FOLDER, then:
NN="$(… | bash "$C" next-index --prefix "$CARD_PREFIX" --suffix .webp | jq -r .next)"
```

Then resolve each role:

```bash
BODY="$(bash "$C" image guides body --slug <slug> --name <name>)"
OG="$(bash "$C" image guides og --slug <slug>)"
CARD="$(bash "$C" image guides card --index "$NN")"
# each → {"uploadFolder":…,"uploadName":…,"reference":…,"url":…,"valueFormat":…,"note":…}
```

Use `reference` verbatim wherever the value is written into the page, and `url` only
when you need to fetch the asset to check it. Do not derive either from the other:
`reference` is relative for the body and card roles, so prefixing it with the CDN base
doubles the folder. Reading the role's `note` is worth the two seconds — one of these
three is stored as a full CDN URL while the others are relative.

- Guide-specific naming: [`reference/images.md`](reference/images.md)
- Convert → upload → verify mechanics: [`../../tools/image/images-to-imagekit.md`](../../tools/image/images-to-imagekit.md)
- Card thumbnail: `"$GENCARD"` with `--folder "$CARD_FOLDER" --prefix "$CARD_PREFIX"` (auto-numbers the next free index); invocation + result parsing live in the "Generate an index/card thumbnail from references" section of the shared doc above

Run the image pipeline for all body images — no per-image subagents needed:

```bash
PIPE="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/image-pipeline.sh"
IMAGES=$(bash "$PIPE" --src /tmp/guide-<slug>/raw --dest "$(jq -r .uploadFolder <<<"$BODY")")
```

The OG image has a specific output name — handle it directly:

```bash
TOWEBP="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/to-webp.sh"
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"
bash "$TOWEBP" <hero-source>.png "/tmp/$(jq -r .uploadName <<<"$OG")"
node "$IK" upload "/tmp/$(jq -r .uploadName <<<"$OG")" \
  --name "$(jq -r .uploadName <<<"$OG")" --folder "$(jq -r .uploadFolder <<<"$OG")"
```

## Stage 3 — Compose the page

Create the page at `$DEST`. This is the **judgment core — do not delegate.** Mirror an existing guide like `preventive-maintenance-strategy.vue` (find its siblings next to `$DEST`).

**Structure:** hero → TOC → intro → 2-5 body sections → optional pull quote + dark "at a glance" → mid-page CTA → conclusion → FAQ.

**Component map:** prose → `BaseSection`; takeaways → `callout`; point lists → `alternative` grids; numbered processes → timeline pattern; FAQs → `SectionAccordion`.

**Wire `useDynamicMeta`** with title, keyword-rich description, `$ROUTE`, and the OG image's `reference` (already the full URL). Keep TOC `id`s in sync with `BaseSection id`s. Use `tron-` tokens only — no arbitrary Tailwind values.

See `reference/components.md` for the full palette — section skeleton, component props, draft-to-component mapping, `<script setup>` conventions, styling rules.

**Stay inside the pipeline's `components.allowed`** and never use anything in
`components.forbidden` (printed in the preflight). For guides that means Vue
components rather than MDC blocks: `<NuxtImg provider="imagekit">`, not `::fImg`.

## Stage 4 — Register in the index

Only when `$REG_MODE` is `manual` (check it — a repo may auto-discover instead).
Append an entry to `$REG_FILE`, in the shape the profile declares:

```bash
jq -c '.registration.entry, .registration.array, .registration.note' <<<"$PIPE_JSON"
```

Fill that template with the guide's title, card description, `$ROUTE` for the link, and
the card image's `reference` value. Skipping this step is the classic guide bug: the page
resolves at its URL but never appears on the index.

## Stage 5 — Verify & clean up

1. **Served-HTML check:** Start a worktree-scoped dev server and confirm the page is served:
   ```bash
   DS="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/dev-server.sh"
   [[ -f "$DS" ]] || { echo "dev-server.sh not found — set CLAUDE_PLUGIN_ROOT or run /plugin update" >&2; exit 1; }
   PORT="$(bash "$DS" start --route "$ROUTE")"
   curl -s "http://localhost:${PORT}${ROUTE}" | grep -oE '<title>[^<]*</title>'
   curl -s "http://localhost:${PORT}${ROUTE}" | grep -oc "$(jq -r .uploadFolder <<<"$BODY")"
   ```
2. **Index card:** Load the pipeline's `indexRoute`, confirm the new card shows.
3. **Images resolve:** Spot-check each role's `.url` — the fetchable CDN address, as
   opposed to `.reference`, which is what you write into the page:
   ```bash
   for spec in "$BODY" "$OG" "$CARD"; do
     curl -sIo /dev/null -w "%{http_code} $(jq -r .url <<<"$spec")\n" "$(jq -r .url <<<"$spec")"
   done
   ```
4. **Links:** Run `bash "$C" rewrite-links "$DEST"` (facilitron.com → relative), then `bash "$C" check-link` each internal path. The repo's declared traps: `bash "$C" profile | jq -r '.internalLinks.exceptions[]? | "\(.wrong) → \(.right)"'`. Full flow: [`../../tools/content/internal-links.md`](../../tools/content/internal-links.md)
5. **Prose & a11y:** `tron:prose-lint`, `tron:a11y-scan`, and the dash grep from [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).
6. **Clean up:** Remove `/tmp/guide-<slug>` and dropped-in sources.

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Using `::fImg` instead of `<NuxtImg>` | Guides are Vue, not content collections (it's in `components.forbidden`) |
| Writing a guide to `pages/…` when the repo uses an `app/` srcDir | Use `$DEST` from `pipeline guides`, never a remembered path |
| Prefixing or stripping a folder on an image value | Copy the role's `reference` verbatim; formats differ per role |
| Forgetting the index entry | Page works at URL but never appears on the index route |
| TOC anchor mismatch | `tocItems.id` must match `BaseSection id`; add `scroll-mt-36` |
| Duplicate H1 | Hero already renders title; don't open body with `#` |
| `content/QuoteSimple` vs `section/QuoteSimple` | Use `<SectionQuoteSimple>` for bgColor/borderBottom props |
| Arbitrary Tailwind values | Add `tron-` token to `tailwind.config.ts` instead |