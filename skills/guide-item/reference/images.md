# Guide images — naming, paths & card thumbnail

Guide-specific image rules for Stage 2. The shared convert → upload → verify mechanics and
the generate-card-from-references workflow live in
[`tools/image/images-to-imagekit.md`](../../../tools/image/images-to-imagekit.md) (linked
directly from SKILL.md too); this file is only the guide-specific naming, paths, and the
extra OG-image step.

## Body images — naming & destination

Each image becomes a resized, descriptive, slug-scoped webp. The folders and file
names belong to the consuming repo, so ask its profile and run the shared convert →
upload → verify steps with those values (always pass `--name`):

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" image guides body --slug <slug> --name <name>
bash "$C" image guides og   --slug <slug>   # 1200×630-ish; reuse the hero or a representative body image
bash "$C" image guides card --index <NN>
```

Each returns `uploadFolder` / `uploadName` for the upload, and `reference` for the
value you write into the page.

**The three roles do not share a reference format.** Body and card images are
referenced by relative provider path; the OG image is a full CDN URL in
`useDynamicMeta`. `reference` has already applied the right rule per role, so copy
it verbatim instead of assembling the string — and check the role's `note`, which
calls out this exact difference.

## Card thumbnail — destination

The index card is **generated to match the existing guide cards** via the shared
generate-from-references workflow (see the shared doc). Take its parameters from the
`card` role rather than hardcoding them:

- index folder → `uploadFolder`
- prefix → `indexPrefix` (drives the next free number, e.g. `guide-05.webp`)

Upload the result as `uploadName`. This is the thumbnail the index entry references
in Stage 4 — a different folder from the body images, which is why they resolve as
two separate roles.
