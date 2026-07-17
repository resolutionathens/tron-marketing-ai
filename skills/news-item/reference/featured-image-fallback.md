# Featured Image Fallback

Use this only when the user has not supplied `featuredimg.png` in the repository root. Generate a wider news hero, not a square toolkit card:

```bash
GENCARD="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/generate-card.sh"
RESULT=$(bash "$GENCARD" \
  --folder blog-featured \
  --name "<slug>.webp" \
  --size 1792x1024 \
  --prompt "<subject prompt for this article>")
```

`generate-card.sh` samples `blog-featured/` automatically. For editorial or policy posts, specify the house style: abstract navy with electric-blue and purple line art. The shared [image pipeline reference](../../../tools/image/images-to-imagekit.md) documents reference sampling, generation, conversion, upload, and verification.

Generation requires `OPENROUTER_API_KEY` or `OPENAI_API_KEY` in `~/.env`. Surface an authentication failure and ask for a manual `featuredimg.png`; never silently omit the featured image.
