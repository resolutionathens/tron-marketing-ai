---
name: optimize-images
model: haiku
effort: low
description: "Compress and convert raster images (PNG, JPEG/JPG, WebP) to reduce file size while preserving visual quality, using pngquant, cwebp, and jpegoptim. Use for 'compress these images', 'optimize for web', 'convert to webp', 'these PNGs are too large', or 'reduce image file size'. Even a bare 'optimize these images/photos' near image files applies."
allowed-tools:
  - Task
scout:
  surface: true
  title: "Compress images"
  blurb: "Shrinks PNGs and JPEGs for the web without visible quality loss, and reports the savings."
  when: "Image files are too heavy to upload or ship."
  category: media
  effects: [local]
  inputs:
    - key: path
      label: "Images path"
      type: path
      required: true
      placeholder: "Pick a folder/PNG, or type a glob"
      accept: ".png"
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
- For designers shipping Figma exports, run this before pushing assets to the CDN via `tron:figma-to-imagekit` (that skill already optimizes its own export leg, but this covers loose images).
