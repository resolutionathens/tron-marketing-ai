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

The featured image is converted from the dropped-in `featuredimg.png` — or, if
none was dropped in, generated via `generate-card.sh` (see SKILL.md Stage 2).
Its output name is whatever the profile declares, not `featuredimg.webp`.

## Destination folders — read them, don't type them

The CDN folders and file names belong to the consuming repo, so ask its profile.
Run the shared convert → upload → verify steps with those values (always pass `--name`):

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" image news featured --slug <slug>
bash "$C" image news body --slug <slug> --name <name>
```

Each returns `uploadFolder` and `uploadName` (the upload arguments) plus
`reference` and `valueFormat`.

## Where each path resolves

`reference` is the value to write into the article, already formatted for the role:

- The **featured** image is referenced from front matter.
- The **body** images are referenced by the `src` on `::image-text` / `::fImg`.

The two do not use the same format — one stores a bare filename because the
renderer prefixes the folder, the other stores a CDN-relative path. That is
exactly why you copy `reference` rather than assembling the string yourself.
