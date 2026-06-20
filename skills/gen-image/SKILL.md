---
name: gen-image
model: sonnet
effort: low
description: "Generate a new image in the style of reference images using codex's built-in image_gen tool. Use when the user wants to create an image that matches the visual style of existing photos — color palette, lighting, mood, composition, medium. Trigger on: 'generate an image like these', 'create an image in this style', 'make something that looks like these photos', '/gen-image', 'gen image from folder', 'generate image like [folder]', or any request to produce a new image matching a reference set."
allowed-tools:
  - Bash
---

# gen-image

Generates a new image that matches the visual style of reference images using `codex exec` with the built-in `image_gen` tool (no `OPENAI_API_KEY` needed — uses codex's own auth).

## Args

```
tron:gen-image <sources> [subject description]
```

Where `<sources>` is one of:
- A folder path — auto-samples up to 5 representative images from it
- One or more image file paths (jpg, jpeg, png, webp)

And `subject description` is optional text describing what the new image should depict. If omitted, codex will generate a scene similar in subject matter to the references.

**Examples:**
```
tron:gen-image ~/Downloads/padma-pics/
tron:gen-image ~/Downloads/padma-pics/ a woman reading at a café
tron:gen-image ref1.jpg ref2.jpg ref3.jpg a dog in a park
```

## What to do

**Step 1 — Resolve the reference images.**

If args point to a folder:
```bash
find "$FOLDER" -maxdepth 1 \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) | sort -R | head -5
```
Pick up to 5 images. If the folder has fewer than 5, use all of them.

If args are explicit image files, use them directly. Validate each path exists.

**Step 2 — Determine the output path.**

Default: `./generated-<timestamp>.png` in the current working directory.
If the user named a specific output path in the args, use that.

```bash
OUTPUT="$(pwd)/generated-$(date +%Y%m%d-%H%M%S).png"
```

**Step 3 — Build and run the codex exec command.**

Construct `-i` flags for each reference image. Pipe the prompt via stdin (required for non-TTY invocation).

Build the prompt:
```
Analyze the visual style of the reference images — color palette, lighting, mood, composition, medium, texture, subject matter.

Then use the built-in image_gen tool to generate a new original image that matches that style.
<IF SUBJECT WAS PROVIDED>
The new image should depict: <subject description>
</IF SUBJECT WAS PROVIDED>
<IF NO SUBJECT>
Generate a scene that is similar in subject matter and feel to the references.
</IF NO SUBJECT>

After generating the image, find the output file in ~/.codex/generated_images/ (most recently modified .png matching ig_*.png), then copy it to: <OUTPUT_PATH>

Confirm the final path and image dimensions.
```

Run it:
```bash
PROMPT="..."  # the prompt above with output path filled in
echo "$PROMPT" | codex exec \
  --skip-git-repo-check \
  -i <ref1> \
  -i <ref2> \
  ...
```

Do NOT use `--dangerously-bypass-approvals-and-sandbox` — the default sandbox already allows writes to `$TMPDIR` and the workspace.

**Step 4 — Report the result.**

When codex finishes, confirm the output path and open it if possible:
```bash
ls -lh "$OUTPUT"
open -a Preview "$OUTPUT"   # macOS — avoids Photoshop hijacking PNGs
```

Tell the user: the output path, what style codex identified, and roughly what was generated.

## Notes

- Codex saves images to `~/.codex/generated_images/<session-id>/ig_*.png` first, then you (or the prompt instructs codex to) `cp` to the target path. The prompt already handles this — don't do it yourself.
- If codex says `image_gen` is unavailable, it will fall back to the CLI path and ask for `OPENAI_API_KEY`. In that case, tell the user to set it: `export OPENAI_API_KEY=sk-...` and rerun.
- Typical generation time: 30–90 seconds.
- Output dimensions vary by the model's defaults (~1400×1100 or 1024×1024).
- The session-id in the generated-images path changes each run, so the `find ~/.codex/generated_images -name 'ig_*.png' -mmin -5` approach in the prompt is the reliable way to locate it.
