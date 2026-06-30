---
name: news-item
model: opus
effort: high
description: Publish a new article to /resources/news on the Facilitron marketing site from a Jira ticket whose description links a Confluence draft. Owns the full pipeline — Confluence fetch, image conversion to webp + ImageKit upload, and writing the Nuxt-Content markdown file with front matter and ::fImg blocks. Use this skill whenever the user wants to "start the news item", "create the news article", "build out this cluster article", "turn this Confluence draft into a news post", references a Jira "Blog Post" or "Cluster:" ticket with a Confluence link, or drops a featuredimg into the repo root and mentions a news/blog/cluster article. Even if they describe only one part, this skill owns the whole pipeline so the pieces stay consistent.
allowed-tools:
  - Bash
  - Read
  - Write
  - Task
  - AskUserQuestion
---

# Facilitron News Item

Publish a new article under `/resources/news` from a Jira ticket linking a Confluence draft.

## Checklist

```
- [ ] Preflight: confirm marketing-pages repo (content.sh check-repo)
- [ ] Stage 1 — Intake: read ticket, fetch Confluence draft + images, confirm slug
- [ ] Stage 2 — Images: name per-section, convert to webp, upload to ImageKit
- [ ] Stage 3 — Write: front matter, body from body.html, internal links, ::fImg blocks
- [ ] Stage 4 — Verify: links, images resolve, served-HTML check on THIS worktree, prose-lint + a11y-scan
- [ ] Verification loop: re-read against brief, no em-dashes, fix, repeat
- [ ] Clean up: remove dropped-in featured image + /tmp/news-<slug>
```

## What gets produced

- `content/resources/news/<slug>.md` — Nuxt-Content markdown with `::fImg` blocks
- Featured image at `blog-featured/<slug>.webp` (front-matter `image:`)
- Inline images at `blog-posts/<slug>/<name>.webp`
- Local source files cleaned up

## Inputs

| Input | Source |
|-------|--------|
| **Jira key** | Branch name (`<KEY>-<slug>`) |
| **Confluence draft + SEO keywords** | Ticket description (inlineCard → Confluence URL) |
| **Featured image** | User drops in repo root as `featuredimg.png` |
| **Slug** | Derived from ticket summary, lowercase-hyphenated. Confirm before uploading. |

## Shared helper (plugin tools)

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" check-repo                       # → must succeed (marketing-pages guard)
bash "$C" slug "<summary>"                 # → {"ok":true,"slug":"…"}
bash "$C" rewrite-links content/resources/news/<slug>.md
bash "$C" check-link /product/<path>
```

## Stage 1 — Intake

```bash
acli jira workitem view <KEY> --json
```

Extract the Confluence URL and target keywords from the description. Then fetch the draft:

```bash
TOOLS="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools"
"$TOOLS/confluence/fetch-confluence.sh" <confluence-url> /tmp/news-<slug>
```

This writes `/tmp/news-<slug>/body.html` and `/tmp/news-<slug>/raw/<name>` per referenced image (skips unused uploads). Delegate the storage→markdown transform to a **Sonnet subagent** — hand it `body.html` and the confluence skill's faithful-markdown contract. It returns clean markdown + a per-image `{filename, alt, layout, order}` map. Keep the raw XML out of the orchestrator.

**Gotcha:** The Confluence `/wiki/download/` servlet 401s with an API token. The shared script handles this via the API gateway. If going manual, use `curl -L ... "https://api.atlassian.com/ex/confluence/91c1b48f-c272-40fb-9c7f-cc5f23bb74d7/wiki<downloadLink>"`.

## Stage 2 — Images

Name each image after the section it illustrates. Naming + paths: [`reference/images.md`](reference/images.md)

Run the image pipeline to convert and upload all body images in one shot — no per-image subagents needed:

```bash
PIPE="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/image-pipeline.sh"
IMAGES=$(bash "$PIPE" --src /tmp/news-<slug>/raw --dest blog-posts/<slug>)
# IMAGES: {"pm-plan-intro.webp": "https://ik.imagekit.io/facilitron/blog-posts/<slug>/pm-plan-intro.webp", ...}
```

Parse the JSON to get each image's URL: `python3 -c "import sys,json; d=json.load(sys.stdin); print(d['pm-plan-intro.webp'])" <<< "$IMAGES"`

The featured image has a different output name (`<slug>.webp`, not `featuredimg.webp`) — handle it directly:

```bash
TOWEBP="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/to-webp.sh"
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"
bash "$TOWEBP" featuredimg.png /tmp/news-<slug>/<slug>.webp
node "$IK" upload /tmp/news-<slug>/<slug>.webp --name <slug>.webp --folder blog-featured
```

## Stage 3 — Write the article

Create `content/resources/news/<slug>.md`. Front-matter (`news` collection schema), body from markdown + image layout map. Choose components: `::image-text` (wrap-left/right), `::fImg` (centered), `::faq`, `::quote`.

See `reference/components.md` for the full palette, front-matter shape, and MDC block syntax.

**Internal links — verify each before saving.** Convert `https://www.facilitron.com/...` to relative paths:

```bash
find pages -type f -name "*.vue" | grep -i <keyword>
```

Known trap: `/product/scheduling-and-reservations/` has no index page — link to `/product/facilitron-scheduling-and-reservations`. Sub-paths like `/product/scheduling-and-reservations/automated-work-orders` are fine.

Every image needs real `alt` text (WCAG compliance). Never reuse the Pexels source filename.

## Stage 4 — Verify & clean up

1. **Links:** `lychee --no-progress --cache --accept 200,206,429 content/resources/news/<slug>.md`
2. **Images resolve:** Spot-check `https://ik.imagekit.io/facilitron/blog-featured/<slug>.webp`
3. **Served-HTML trap:** News catch-all returns HTTP 200 even without the markdown file. Verify you're on THIS worktree's server by grepping rendered HTML:
   ```bash
   curl -s "http://localhost:<port>/resources/news/<slug>" | grep -oE '<title>[^<]*</title>'
   curl -s "http://localhost:<port>/resources/news/<slug>" | grep -oc 'blog-posts/<slug>'
   ```
   If no server is running yet (or ports are bound by siblings), start one:
   ```bash
   DS="${CLAUDE_PLUGIN_ROOT:-$(ls -d ~/.claude/plugins/cache/tron/tron/*/. 2>/dev/null | sort -V | tail -1 | sed 's|/\.$||')}/tools/content/dev-server.sh"
   [[ -f "$DS" ]] || { echo "dev-server.sh not found — set CLAUDE_PLUGIN_ROOT or run /plugin update" >&2; exit 1; }
   PORT="$(bash "$DS" start --route /resources/news/<slug>)"
   ```
4. **Prose & a11y:** Offer `tron:prose-lint` and `tron:a11y-scan` before publish.
5. **Clean up:** Remove `featuredimg.png` from repo root, `/tmp/news-<slug>`.

## Verification loop

Validate → fix → repeat until clean. Check: SEO keywords in title/description/H2s, no em-dashes (Facilitron voice), alt text on every image, internal links resolve, served-HTML check passed. Then clean up. Only the article file should be tracked in git.