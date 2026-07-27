---
name: gen-image
model: sonnet
effort: low
description: "Generate a new image, optionally matching the visual style of reference photos — color palette, lighting, mood, composition, medium. Use for 'generate an image', 'make an image of X', 'create an image in this style', '/gen-image', or 'generate image like [folder]'."
allowed-tools:
  - Bash
scout:
  surface: true
  title: "Generate an image"
  blurb: "Creates a new image or illustration, optionally matching the look of reference photos."
  when: "You need a visual and don't have one."
  category: media
  effects: [local]
  inputs:
    - key: sources
      label: "Reference images"
      type: path
      required: true
      help: "Folder or image files whose visual style the new image should match."
      placeholder: "Pick a folder of reference images"
      accept: ".jpg,.jpeg,.png,.webp"
    - key: subject
      label: "Subject (optional)"
      type: textarea
      required: false
      help: "What the new image should depict. Omit to match the references' subject matter."
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
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/gen-image.sh)"

OUT="$(bash "$SKILL_DIR/scripts/gen-image.sh" "<sources>" "<subject>" "<output.png>")"
```

The script:
1. Samples up to 5 references, builds a prompt that makes the **subject mandatory**, pins the **medium from references**, and demands a **visibly distinct composition** (same visual family, not a re-skin of any single reference).
2. Uses the deterministic CLI path (`image_gen.py` with `OPENAI_API_KEY`, or OpenRouter with `OPENROUTER_API_KEY`) — fails to the built-in tool only if neither key is available.
3. Verifies a real, fresh, non-trivial image landed (exit 1 otherwise).

**Your judgment:** the subject text and final visual self-verify.

```bash
open -a Preview "$OUT"   # macOS
```

When you glance at the result to judge it, check three things in one look:
1. **Subject** — does it depict what you asked for?
2. **Medium** — does it match the references' medium (photo vs illustration vs abstract)?
3. **Not a near-duplicate** — is it a fresh variation, or is it visually almost identical to one specific reference (same composition, same palette, just a relabel)? The prompt already instructs the model to stay in the family while varying the composition, so this should be rare — but the glance costs nothing and catches the case where it slipped through (MD-2014).

If the result is clearly off (wrong subject or medium) **or too close to a single reference**, retry once with a tighter subject string — for the near-duplicate case, add "a visually distinct composition, do not reproduce any single reference's layout" — then hand to the user.

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

In every case, the references are a **family, not a template**. Word the subprompt so the new card is "similar in subject, palette, and motifs to the references, but a visually distinct composition — do not reproduce any single reference's layout." The script bakes this distinctness instruction into every reference-based prompt, so the near-duplicate is stopped at generation time; still glance at the result against the downloaded refs before shipping (see the self-verify above) — this path is exactly where the near-duplicate on CCAL-1469 slipped through to human review (MD-2014).

Toolkit cards are 1600×901 (landscape). Generate matching aspect:

```bash
GENIMG_SIZE=1536x1024 bash "$SKILL_DIR/scripts/gen-image.sh" \
  /tmp/card-refs "<prompt>" /tmp/card-<slug>.png
```

## Notes

- **OpenRouter default model:** `google/gemini-2.5-flash-image`. Override with `GENIMG_MODEL=<model-id>`. When refs are provided, uses the chat completions endpoint (multimodal) so refs reach the model.
- Default size: `1024x1024`. Quality: `high`. Override via `GENIMG_SIZE` / `GENIMG_QUALITY`.
- **Next step:** generated PNGs are large. Run `tron:optimize-images` before shipping to CDN.