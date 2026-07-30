# Guide images — naming, paths & card thumbnail

Guide-specific image rules for Stage 2. The shared convert → upload → verify mechanics and
the generate-card-from-references workflow live in
[`tools/image/images-to-imagekit.md`](../../../tools/image/images-to-imagekit.md) (linked
directly from SKILL.md too); this file is only the guide-specific naming, paths, and the
extra OG-image step.

## Body images — naming & destination

Each image becomes a resized, descriptive, slug-scoped webp. Run the shared convert →
upload → verify steps, uploading into these guide folders (always pass `--name`):

- Body images → `guides/<slug>` (uploaded as `<name>.webp`)
- OG image → `og` (uploaded as `og-<slug>.webp`; 1200×630-ish — reuse the hero
  illustration or a representative body image)

Body images are referenced by **relative provider path** (`guides/<slug>/<name>.webp`),
never a full URL. The OG image IS a full URL in `useDynamicMeta` (Stage 3).

## Card thumbnail — destination

The index card is **generated to match the existing guide cards** via the shared
generate-from-references workflow (see the shared doc). For guides the parameters are:

- index folder: `guides`
- prefix: `guide` (so the next free number is e.g. `guide-05.webp`)

Upload the result as `guides/guide-<NN>.webp`. This is the thumbnail the `resource-guides.ts`
entry references in Stage 4 — distinct from the `guides/<slug>/` body-image folder.
