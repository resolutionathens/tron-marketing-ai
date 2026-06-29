---
name: confluence
model: haiku
effort: low
description: Fetch and read Confluence pages by URL or page ID. Use this skill whenever the user shares a Confluence link (including tiny links like /wiki/x/XXXXX), mentions a Confluence page, asks to read or pull content from Confluence, or references facilitron.atlassian.net/wiki. For fetching images (downloads), use the shared `tools/confluence/fetch-confluence.sh` instead — it handles the API gateway auth for attachment bytes.
allowed-tools:
  - Bash
---

# Confluence Page Fetcher

Fetch Confluence page content. Always use `acli` for reading — it carries working auth and avoids token gotchas.

## Fast path (scripted)

```bash
name=confluence
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/confluence.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/confluence.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/confluence.sh" ] || { echo "tron:$name: scripts/confluence.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }

bash "$SKILL_DIR/scripts/confluence.sh" resolve <url-or-id>   # → {"ok":true,"pageId":"…","source":"raw|url|tiny"}
bash "$SKILL_DIR/scripts/confluence.sh" fetch   <url-or-id>   # storage body → stdout (title/version → stderr)
bash "$SKILL_DIR/scripts/confluence.sh" images  body.html     # referenced attachment filenames, doc order
```

`resolve` extracts the page ID from a raw ID, full URL, or `/wiki/x/` tiny link. `fetch` runs `acli` and prints the raw storage body — pipe into the faithful-markdown conversion (Step 3 below). `images` lists attachments the body actually references (skips unused uploads).

## Manual resolution (if script unavailable)

- **Tiny link** — follow the redirect: `curl -sIL "https://facilitron.atlassian.net/wiki/x/XXXXX" | grep -i "location:"` and extract the numeric page ID.
- **Full URL** — extract the numeric ID from `/pages/<id>/` in the path.
- **Raw ID** — use directly.

Manual fetch:

```bash
acli confluence page view --id <PAGE_ID> --body-format storage --json \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['body']['storage']['value'])"
```

## Faithful-markdown conversion

The storage format is HTML-like XML (`ac:structured-macro`, `ac:image`, etc.). Convert it to clean markdown with these rules:

- **Lossless — don't summarize, don't drop images.** Downstream pipelines (`tron:news-item`, `tron:toolkit-item`) rebuild pages from this output.
- Preserve heading hierarchy, links, tables, lists, code macros (→ fenced blocks with language), panel/info macros (→ blockquote with label), bold/italic/inline code.
- **Never drop `<ac:image>` attachments** — convert to `![alt](filename)`. Image downloads need the API gateway (use `tools/confluence/fetch-confluence.sh`).
- Strip internal IDs (`local-id`, `ac:macro-id`, etc.).
- Unwrap `ac:inline-comment-marker` to plain text; collect wrapped snippets into a "Recently commented" note at the end.

For large pages, delegate the fetch + convert to a Sonnet subagent — keep only the clean markdown and the list of image filenames in your context.