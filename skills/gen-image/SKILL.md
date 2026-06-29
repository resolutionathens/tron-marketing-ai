---
name: gen-image
model: sonnet
effort: low
description: "Generate a new image, optionally matching the visual style of reference photos — color palette, lighting, mood, composition, medium. Use when the user wants to create, generate, or make an image, illustration, or graphic. Trigger on: 'generate an image', 'create an image', 'make an image of X', 'generate an image like these', 'create an image in this style', 'make something that looks like these photos', '/gen-image', 'gen image from folder', or 'generate image like [folder]'."
allowed-tools:
  - Bash
---

# gen-image

Generates a new image matching the visual style of reference images. Three paths in priority: `image_gen.py` CLI (needs `OPENAI_API_KEY`), OpenRouter (needs `OPENROUTER_API_KEY` — active default), or `codex exec` fallback.

## Args

```
tron:gen-image <sources> [subject description]
```

Where `<sources>` is a folder path (auto-samples up to 5) or one or more image file paths.

## Fast path (scripted)

The mechanical pipeline — preflight, resolve refs, build prompt, generate, verify — is one deterministic script.

```bash
name=gen-image
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/gen-image.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/gen-image.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/gen-image.sh" ] || { echo "tron:$name: scripts/gen-image.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }

OUT="$(bash "$SKILL_DIR/scripts/gen-image.sh" "<sources>" "<subject>" "<output.png>")"
```

The script:
1. Samples up to 5 references, builds a prompt that makes the **subject mandatory** and pins the **medium from references**.
2. Uses the deterministic CLI path (`image_gen.py` with `OPENAI_API_KEY`, or OpenRouter with `OPENROUTER_API_KEY`) — fails to the built-in tool only if neither key is available.
3. Verifies a real, fresh, non-trivial image landed (exit 1 otherwise).

**Your judgment:** the subject text and final visual self-verify.

```bash
open -a Preview "$OUT"   # macOS
```

If the result is clearly off (wrong subject or medium), retry once with a tighter subject string, then hand to the user.

## Generating a card from ImageKit references

When generating a toolkit/guide card (no local refs available), download 3 recent cards from ImageKit first, **read them to infer the visual style**, then craft the subject prompt from what you see:

```bash
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"
mkdir -p /tmp/card-refs
node "$IK" list --path toolkit --limit 3 | \
  python3 -c "
import sys, json
for f in json.load(sys.stdin):
    print(f['url'].split('?')[0], f['name'])
" | while read -r url name; do
    curl -sf -o "/tmp/card-refs/$name" "$url"
  done
```

**Prompt strategy (infer from what you Read):**
- **Abstract backgrounds** (geometric shapes, gradients, no literal objects): describe a new abstract variation with the same palette and motifs.
- **Editorial/flat illustrations** (icons, isometric scenes, characters): describe a new scene in the same style.
- **Photographs**: describe a new photograph — same lighting/mood, distinct scene.

Toolkit cards are 1600×901 (landscape). Generate matching aspect:

```bash
GENIMG_SIZE=1536x1024 bash "$SKILL_DIR/scripts/gen-image.sh" \
  /tmp/card-refs "<prompt>" /tmp/card-<slug>.png
```

## Notes

- **OpenRouter default model:** `google/gemini-2.5-flash-image`. Override with `GENIMG_MODEL=<model-id>`. When refs are provided, uses the chat completions endpoint (multimodal) so refs reach the model.
- Default size: `1024x1024`. Quality: `high`. Override via `GENIMG_SIZE` / `GENIMG_QUALITY`.
- **Next step:** generated PNGs are large. Run `tron:optimize-images` before shipping to CDN.