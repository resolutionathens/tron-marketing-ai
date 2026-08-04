---
name: news-item
model: opus
effort: high
fallback:
  cost: high
  skip_when: "Use tron:news-item only when publishing a full article. If only a draft or partial update is needed, skip."
  stage_skips:
    - stage: "Stage 1 — Intake"
      skip_when: "Confluence draft already pulled and body.html exists"
    - stage: "Stage 2 — Images"
      skip_when: "Article has no images or images are already uploaded"
    - stage: "Stage 4 — Verify"
      skip_when: "User wants draft-only output without verification"
description: "Publish a new article to /resources/news on the Facilitron marketing site from a Jira ticket whose description links a Confluence draft. Owns the full pipeline: Confluence fetch, image conversion to webp + ImageKit upload, and writing the Nuxt-Content markdown file with front matter and ::fImg blocks. Use for 'start the news item', 'turn this Confluence draft into a news post', a Jira 'Blog Post' or 'Cluster:' ticket with a Confluence link, or dropping a featuredimg into the repo root. Even if the user describes only one part, this skill owns the whole pipeline so the pieces stay consistent."
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
      label: "Topic / headline"
      type: text
      required: true
    - key: notes
      label: "Notes"
      type: textarea
      required: false
---

# Facilitron News Item

Publish a new article under `/resources/news` from a Jira ticket linking a Confluence draft.

## Checklist

```
- [ ] Preflight: confirm marketing-pages repo (content.sh check-repo) + confirm the repo declares a profile
- [ ] Stage 1 — Intake: read ticket, fetch Confluence draft + images, confirm slug
- [ ] Stage 2 — Resolve the news pipeline against the confirmed slug, then images: name per-section, convert to webp, upload to ImageKit; if no featuredimg.png, generate one
- [ ] Stage 3 — Write: front matter, body from body.html, internal links, ::fImg blocks
- [ ] Stage 4 — Verify: links, images resolve, served-HTML check on THIS worktree, prose-lint + a11y-scan
- [ ] Verification loop: re-read against brief, check Facilitron voice, fix, repeat
- [ ] Clean up: remove dropped-in featured image + /tmp/news-<slug>
```

## What gets produced

The repo owns the paths — this skill owns the article. Every destination and CDN
folder below comes from the consuming repo's content profile, so read them rather
than typing them:

- The article file — `pipeline news → .destination`
- The featured image — `image news featured → .uploadFolder` / `.uploadName`
- The inline images — `image news body → .uploadFolder` / `.uploadName`
- Local source files cleaned up

## Inputs

| Input | Source |
|-------|--------|
| **Jira key** | Branch name (`<KEY>-<slug>`) |
| **Confluence draft + SEO keywords** | Ticket description (inlineCard → Confluence URL) |
| **Featured image** | User drops in repo root as `featuredimg.png`. If absent, generate one — see Stage 2. |
| **Slug** | Derived from ticket summary, lowercase-hyphenated. Confirm before uploading. |

## Shared helper (plugin tools)

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" slug "<summary>"                 # → {"ok":true,"slug":"…"}
bash "$C" rewrite-links "$DEST"
bash "$C" check-link /product/<path>
```

## Preflight — repo guard + profile availability

Before local verification in a fresh worktree, follow
[`tools/content/local-qa.md`](../../tools/content/local-qa.md) to bootstrap its
dependencies and interpret local-check limitations.

Two separate things. The guard decides **whether** you may write here; the profile
says **where**. Never skip the guard on the grounds that the profile resolved.

Neither needs the slug, so both run before Stage 1:

```bash
bash "$C" check-repo | grep -q '"isMarketingPages":true' \
  || { echo "✋ NOT in marketing-pages — switch checkouts first." >&2; exit 1; }
bash "$C" profile >/dev/null || exit 1   # this repo declares a content profile at all
```

**Do not resolve the pipeline yet** — `destination` and `route` are slug-derived, and
the slug is not fixed until Stage 1 confirms it. Resolving here means inventing a slug
and re-resolving later. The resolve step is the top of Stage 2, once Stage 1 has one.

If either command fails, **stop and report what was missing** — the message names
the file it looked for and what it needed. Do not fall back to a remembered path:
an article written into a guessed directory looks like success and is only caught
in review.

## Stage 1 — Intake

```bash
acli jira workitem view <KEY> --json
```

Extract the Confluence URL and target keywords from the description. Then fetch the draft:

```bash
TOOLS="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools"
"$TOOLS/confluence/fetch-confluence.sh" <confluence-url> /tmp/news-<slug>
```

This writes `/tmp/news-<slug>/body.html` and `/tmp/news-<slug>/raw/<name>` per referenced image (skips unused uploads). Delegate the storage→markdown transform to the **`confluence-transformer` agent** — hand it the path to `body.html`. It returns `<markdown>…</markdown>` (extract the body) and `<images>…</images>` (one filename per line, document order). Keep the raw XML out of the orchestrator.

**Gotcha:** The Confluence `/wiki/download/` servlet 401s with an API token. The shared script handles this via the API gateway. If going manual, use `curl -L ... "https://api.atlassian.com/ex/confluence/91c1b48f-c272-40fb-9c7f-cc5f23bb74d7/wiki<downloadLink>"`.

## Stage 2 — Resolve the pipeline, then images

The slug is fixed now, so resolve everything this repo declares about news, once:

```bash
PIPE_JSON="$(bash "$C" pipeline news --slug <slug>)" || exit 1   # fails loudly if undeclared
DEST="$(jq -r .destination      <<<"$PIPE_JSON")"                # where the article file goes
ROUTE="$(jq -r .route           <<<"$PIPE_JSON")"                # the URL it will serve at
jq -r '.components.allowed[]'   <<<"$PIPE_JSON"                  # the MDC blocks this repo permits
jq -r '.components.forbidden[]' <<<"$PIPE_JSON"                  # and the ones it does not
bash "$C" collection news | jq -c '{required,optional,enums,defaults}'   # front-matter schema
```

`pipeline` refuses to return a destination that still contains a literal `{slug}`, or
one that escapes the repo, so a successful call means `$DEST` is safe to write to.

Then the images. Name each one after the section it illustrates.

- News-specific naming + paths: [`reference/images.md`](reference/images.md)
- Convert → upload → verify mechanics: [`../../tools/image/images-to-imagekit.md`](../../tools/image/images-to-imagekit.md)

Ask the profile where each role goes and how its value must be written — never
type a CDN folder from memory:

```bash
BODY="$(bash "$C" image news body --slug <slug> --name <name>)"   # per body image
FEAT="$(bash "$C" image news featured --slug <slug>)"
# each → {"uploadFolder":…,"uploadName":…,"reference":…,"url":…,"valueFormat":…,"note":…}
```

Three distinct values, and mixing them up is the classic failure:

- `uploadFolder` / `uploadName` — the **upload** arguments
- `reference` — the exact string to **write into the article** (see Stage 3)
- `url` — the fetchable **CDN address**, for verification only

Never build one from another. `reference` is often a bare filename or a relative
path, so prefixing it with the CDN base gives a URL that 404s or doubles the folder.

Run the image pipeline to convert and upload all body images in one shot — no per-image subagents needed:

```bash
PIPE="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/image-pipeline.sh"
IMAGES=$(bash "$PIPE" --src /tmp/news-<slug>/raw --dest "$(jq -r .uploadFolder <<<"$BODY")")
```

The featured image has a different output name and a different aspect (hero, not
card) from the body images above.

**A user-dropped `featuredimg.png` in the repo root always takes precedence.** If it's present,
convert and upload it directly:

```bash
TOWEBP="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/to-webp.sh"
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"
bash "$TOWEBP" featuredimg.png "/tmp/news-<slug>/$(jq -r .uploadName <<<"$FEAT")"
node "$IK" upload "/tmp/news-<slug>/$(jq -r .uploadName <<<"$FEAT")" \
  --name "$(jq -r .uploadName <<<"$FEAT")" --folder "$(jq -r .uploadFolder <<<"$FEAT")"
```

If no `featuredimg.png` was dropped, use the [featured-image fallback](reference/featured-image-fallback.md).

## Stage 3 — Write the article

Create the file at `$DEST` (resolved in the preflight). Front matter follows the
`news` collection schema you read from `collection news` — write every `required`
field, respect `enums`, and take `defaults` as the starting point. Body comes from
the `<markdown>` block and the `<images>` list. Choose components from the
pipeline's `components.allowed`, and never reach for anything in `components.forbidden`.

**Image values: use `reference` verbatim.** The same webp is written three
different ways depending on how the repo's renderer consumes it, and getting this
wrong is the classic silent failure — the file uploads fine and the page renders a
broken image. `image … → .reference` already applied the right rule (`filename`,
`cdn-relative-path`, or `absolute-url`), so paste that value; do not prepend or
strip a folder to make it "look right", and read the role's `note` when present.

See `reference/components.md` for the MDC block syntax and how to choose between
`::image-text` and `::fImg`.

**Internal links — rewrite, then verify each before saving:**

```bash
bash "$C" rewrite-links "$DEST"        # facilitron.com → relative, in place
bash "$C" check-link /product/<path>   # once per internal path
bash "$C" profile | jq -r '.internalLinks.exceptions[]? | "\(.wrong) → \(.right)  (\(.reason))"'
```

That last line prints the repo's declared link traps. Full flow: [`../../tools/content/internal-links.md`](../../tools/content/internal-links.md)

Every image needs real `alt` text (WCAG compliance). Never reuse the Pexels source filename.

## Stage 4 — Verify & clean up

1. **Links:** `lychee --no-progress --cache --accept 200,206,429 "$DEST"`
2. **Images resolve:** Spot-check the featured image's live URL. Take `.url` — the
   fetchable CDN address — not `.reference`, which is the value you write into the
   article and is usually a bare filename or a relative path:
   ```bash
   curl -sIo /dev/null -w '%{http_code}\n' "$(bash "$C" image news featured --slug <slug> | jq -r .url)"
   ```
3. **Served-HTML trap:** The news catch-all returns HTTP 200 even without the markdown file. Verify you're on THIS worktree's server by grepping rendered HTML:
   ```bash
   curl -s "http://localhost:<port>$ROUTE" | grep -oE '<title>[^<]*</title>'
   curl -s "http://localhost:<port>$ROUTE" | grep -oc "$(bash "$C" image news body --slug <slug> --name x | jq -r .uploadFolder)"
   ```
   If no server is running yet (or ports are bound by siblings), start one:
   ```bash
   DS="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/dev-server.sh"
   [[ -f "$DS" ]] || { echo "dev-server.sh not found — set CLAUDE_PLUGIN_ROOT or run /plugin update" >&2; exit 1; }
   PORT="$(bash "$DS" start --route "$ROUTE")"
   ```
4. **Prose & a11y:** Offer `tron:prose-lint` and `tron:a11y-scan` before publish.
5. **Clean up:** Remove `featuredimg.png` from repo root if it was dropped in, and `/tmp/news-<slug>`.

## Verification loop

Validate → fix → repeat until clean. Check: SEO keywords in title/description/H2s, Facilitron voice ([tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md)) and the brand voice, stance, and proof set ([tools/voice/marketing-copy.md](../../tools/voice/marketing-copy.md)), alt text on every image, internal links resolve, served-HTML check passed. Then clean up. Only the article file should be tracked in git.
