#!/usr/bin/env bash
# Convert an image to web-ready webp: cap the longest edge at 2000px (never
# upscale), quality 82. Uses Bun's built-in Bun.Image (libwebp under the hood,
# zero deps) — no ImageMagick or cwebp required.
#
# Usage: to-webp.sh <input> <output.webp>

set -euo pipefail
IN="${1:?Usage: to-webp.sh <input> <output.webp>}"
OUT="${2:?Usage: to-webp.sh <input> <output.webp>}"

IN="$IN" OUT="$OUT" bun -e '
  const i = process.env.IN, o = process.env.OUT;
  // fit:"inside" preserves aspect ratio; withoutEnlargement matches "2000x2000>".
  await new Bun.Image(i)
    .resize(2000, 2000, { fit: "inside", withoutEnlargement: true })
    .webp({ quality: 82 })
    .write(o);
  const { width, height } = await new Bun.Image(o).metadata();
  const kb = (Bun.file(o).size / 1024).toFixed(1);
  console.log(`${o.split("/").pop()}  ${width}x${height}  ${kb}KB`);
'
