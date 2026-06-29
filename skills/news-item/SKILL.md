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

Name each image after the section it illustrates. Convert to webp and upload.

- Naming + paths: [`reference/images.md`](reference/images.md)
- Convert → upload → verify: [`../../tools/image/images-to-imagekit.md`](../../tools/image/images-to-imagekit.md)

Fan out image convert+upload to **Haiku subagents** for articles with many images (one per image); a single Bash loop is fine for few.

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
   If ports 4001/4002 are bound by sibling worktrees, start this one on a free port:
   ```bash
   for p in 4001 4002 4003 4004 4005; do lsof -ti:$p >/dev/null 2>&1 || { echo "free: $p"; break; }; done
   source ~/.nvm/nvm.sh && nvm use >/dev/null 2>&1
   ./node_modules/.bin/nuxt dev --port=<free-port> --dotenv .env.local > /tmp/news-dev.log 2>&1 &
   ```
4. **Prose & a11y:** Offer `tron:prose-lint` and `tron:a11y-scan` before publish.
5. **Clean up:** Remove `featuredimg.png` from repo root, `/tmp/news-<slug>`.

## Verification loop

Validate → fix → repeat until clean. Check: SEO keywords in title/description/H2s, no em-dashes (Facilitron voice), alt text on every image, internal links resolve, served-HTML check passed. Then clean up. Only the article file should be tracked in git.