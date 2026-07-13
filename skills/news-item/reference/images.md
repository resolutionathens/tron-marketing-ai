# News Item — image naming & paths

News-item-specific image rules. The shared convert → upload → verify mechanics live in
[`tools/image/images-to-imagekit.md`](../../../tools/image/images-to-imagekit.md) (linked
directly from SKILL.md too); this file is only the naming judgment and the destination
paths that are unique to a news article.

## Per-section naming

**Name each image after the section it illustrates**, prefixed so the folder reads
well — e.g. for the maintenance-plan article: `pm-plan-intro.webp`,
`pm-plan-why-matters.webp`, `pm-plan-conclusion.webp`. Walk the `body.html` in
order; each `<ac:image>` sits just before or after the heading it belongs to, and
its `ac:alt` attr is a starting point for both the filename and the `::fImg` alt
text. Descriptive names beat numbered ones here because the article body is
hand-assembled — a meaningful `src` is easier to place correctly than `-07`.

The featured image is named after the slug (`<slug>.webp`), converted from the
dropped-in `featuredimg.png` — or, if none was dropped in, generated via
`generate-card.sh` with `--name <slug>.webp` (see SKILL.md Stage 2).

## Destination folders

Run the shared convert → upload → verify steps, uploading into these news folders
(always pass `--name`):

- Featured image → `blog-featured` (uploaded as `<slug>.webp`)
- Inline images → `blog-posts/<slug>` (uploaded as `<name>.webp`)

## Where each path resolves

- Featured image → `blog-featured/<slug>.webp` (front matter `image:` resolves there)
- Inline images → `blog-posts/<slug>/<name>.webp` (the `src` in `::image-text` / `::fImg`)
