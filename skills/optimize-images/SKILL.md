---
name: optimize-images
description: "Optimize PNG images using pngquant to reduce file size while preserving visual quality. Use this skill whenever the user wants to compress, optimize, shrink, or reduce the size of PNG images. Also trigger when the user mentions pngquant, image optimization, image compression, or says things like 'these PNGs are too large', 'compress these images', 'optimize for web', 'reduce image file size', or 'make these images smaller'. Even if the user just says 'optimize' near image files, this skill applies."
---

# Optimize PNG Images with pngquant

This skill delegates the compression to the **`optimize-images-runner`** subagent (runs on Haiku). Your job is to resolve which images and hand off — **don't run pngquant yourself.**

## What to do

1. **Resolve the target:** a file, list, directory (search recursively — `<dir>/**/*.png`), or glob. Convert to absolute paths. Default quality is web (`65-80`); honor a different quality if the user asks (higher `80-100`, max compression `45-65`).
2. **Delegate to `optimize-images-runner`** (Task tool): "Optimize the PNG(s) at `<target>` (quality `<range>`, default 65-80). Mirror into an `optimized/` dir and return a savings table."
3. **Relay the runner's savings table** (per-file + total + any skipped/already-optimized).

## Notes
- Default output is `optimized/` mirroring source structure; use the user's path if they specify one.
- Already-optimized files (pngquant exit 99) and non-PNG/APNG files are reported as skipped, not errors.
- For designers shipping Figma exports, run this before pushing assets to the CDN via `tron:figma-to-imagekit` (that skill already optimizes its own export leg, but this covers loose PNGs).
