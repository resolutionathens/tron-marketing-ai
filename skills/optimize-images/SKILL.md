---
name: optimize-images
model: haiku
effort: low
description: "Compress and convert raster images (PNG, JPEG/JPG, WebP) to reduce file size while preserving visual quality, using pngquant, cwebp, and jpegoptim. Use this skill whenever the user wants to compress, optimize, shrink, or reduce the size of images or photos. Also trigger when the user mentions pngquant, cwebp, image optimization, image compression, 'convert to webp', or says things like 'these PNGs/JPGs are too large', 'compress these images', 'compress these photos', 'optimize for web', 'reduce image file size', or 'make these images smaller'. Even if the user just says 'optimize these images/photos' near image files, this skill applies."
allowed-tools:
  - Task
---

# /optimize-images — image compression (pngquant · cwebp · jpegoptim)

This skill delegates the compression to the **`optimize-images-runner`** subagent (runs on Haiku), which invokes a **deterministic bundled script** — your job is to resolve which images, pick the mode, and hand off. **Don't run the compressors yourself.**

Handles **PNG, JPEG/JPG, and WebP** in a single run, picking the right tool per format:
`pngquant` for PNG, `cwebp` for WebP and (by default) JPEG→WebP, `jpegoptim` for keeping the `.jpg` extension.

## What to do

1. **Resolve the target:** a file, directory (searched recursively for `*.{png,jpg,jpeg,webp}`), or glob. Convert to an absolute path.
2. **Pick the mode** (pass to the runner):
   - **default** — PNG stays PNG (pngquant), JPEG → `.webp` (best savings for photos), WebP re-encoded. This is the right choice for "compress these photos for web."
   - **`to-webp`** — convert _everything_ (incl. PNG) to `.webp`.
   - **`same-format`** — keep every file's original extension (JPEG handled by jpegoptim).
   - Default quality is web (`65-80`); honor a different range if asked.
3. **Delegate to `optimize-images-runner`** (Task tool): "Optimize the images at `<target>` (mode `<default|to-webp|same-format>`, quality `<range>`). Return the savings table."
4. **Relay the runner's savings table** (per-file format + output format + savings, total, any skipped).

## Notes

- Default output is `<source>/optimized/` mirroring source structure; pass `--out` for a different dir.
- **pngquant** is PNG-only; **cwebp** reads JPEG/PNG but only writes `.webp`; keeping a `.jpg` needs **jpegoptim**. A missing tool degrades gracefully (the file is skipped with a `brew install …` hint) — the run never hard-fails.
- Already-optimized PNGs (pngquant exit 99) keep the original and are reported as skipped, not errors.
- For designers shipping Figma exports, run this before pushing assets to the CDN via `tron:figma-to-imagekit` (that skill already optimizes its own export leg, but this covers loose images).
