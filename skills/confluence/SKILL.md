---
name: confluence
model: haiku
effort: low
description: Fetch and read Confluence pages by URL or page ID. Use this skill whenever the user shares a Confluence link (including tiny links like /wiki/x/XXXXX), mentions a Confluence page, asks to read or pull content from Confluence, or references facilitron.atlassian.net/wiki.
allowed-tools:
  - Bash
scout:
  surface: false
  inputs:
    - key: query
      label: "Page or query"
      type: text
      required: true
      placeholder: "Page title or what to pull from Confluence"
---

# Confluence Page Fetcher

Fetch Confluence page content. Always use `acli` for reading — it carries working auth and avoids token gotchas.

## Fast path (scripted)

```bash
name=confluence
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/confluence.sh)"

bash "$SKILL_DIR/scripts/confluence.sh" resolve <url-or-id>   # → {"ok":true,"pageId":"…","source":"raw|url|tiny"}
bash "$SKILL_DIR/scripts/confluence.sh" fetch   <url-or-id>   # storage body → stdout (title/version → stderr)
bash "$SKILL_DIR/scripts/confluence.sh" images  body.html     # referenced attachment filenames, doc order
```

`resolve` extracts the page ID from a raw ID, full URL, or `/wiki/x/` tiny link. `fetch` runs `acli` and prints the raw storage body — pipe into the "Storage-XML → markdown" section below. `images` lists attachments the body actually references (skips unused uploads).

## Manual resolution (if script unavailable)

- **Tiny link** — follow the redirect: `curl -sIL "https://facilitron.atlassian.net/wiki/x/XXXXX" | grep -i "location:"` and extract the numeric page ID.
- **Full URL** — extract the numeric ID from `/pages/<id>/` in the path.
- **Raw ID** — use directly.

Manual fetch:

```bash
acli confluence page view --id <PAGE_ID> --body-format storage --json \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['body']['storage']['value'])"
```

## Storage-XML → markdown

Delegate the XML-to-markdown transform to the **`confluence-transformer` agent**. Hand it the path to `body.html` — pipe the `fetch` output to a file first if needed:

```bash
bash "$SKILL_DIR/scripts/confluence.sh" fetch <url-or-id> > /tmp/body.html
```

For the repo-local content pipelines (`news-item`, `guide-item`) and any image/attachment downloads, use the shared `tools/confluence/fetch-confluence.sh` instead — it handles the API gateway auth for attachment bytes and writes `body.html` directly. The transformer returns `<markdown>…</markdown>` (extract the body) and `<images>…</images>` (one filename per line, document order). Keep the raw XML out of your context.
