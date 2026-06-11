---
name: confluence
description: Fetch and read Confluence pages by URL or page ID. Use this skill whenever the user shares a Confluence link (including tiny links like /wiki/x/XXXXX), mentions a Confluence page, asks to read or pull content from Confluence, or references facilitron.atlassian.net/wiki. Also trigger when the user says "check Confluence", "grab that page", "pull the content from wiki", or wants to work with content that lives in Confluence.
allowed-tools:
  - Bash
---

# Confluence Page Fetcher

Fetch Confluence page content. **Always use `acli`** — it carries working auth. Handles both tiny links (`/wiki/x/XXXXX`) and full page URLs.

**Requires:** `acli` (the Atlassian CLI, already authenticated against facilitron.atlassian.net).

> The old `curl` + `JIRA_API_TOKEN` recipe is deprecated — that token is stale and returns `401`. Do not reach for it; use `acli`.

## Step 1: Resolve the page ID

The user may provide:

- **A tiny link** like `https://facilitron.atlassian.net/wiki/x/DYCR5Q` — resolve it by following the redirect:
  ```bash
  curl -sIL "https://facilitron.atlassian.net/wiki/x/DYCR5Q" | grep -i "location:"
  ```
  The final redirect contains the page ID in the URL path (e.g., `/pages/3851517965`). Extract the numeric ID.

- **A full page URL** like `https://facilitron.atlassian.net/wiki/spaces/kimji/pages/3851517965/Page+Title` — extract the numeric ID from the path.

- **A raw page ID** like `3851517965` — use it directly.

## Step 2: Fetch the page (acli)

```bash
acli confluence page view --id <PAGE_ID> --body-format storage --json
```

The response is JSON. The page content is in `.body.storage.value` as Confluence storage format (HTML-like XML); the title is in `.title`. To pull just the body:

```bash
acli confluence page view --id <PAGE_ID> --body-format storage --json \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['body']['storage']['value'])"
```

## Step 3: Transform to faithful markdown

The storage format is HTML-like XML (`ac:structured-macro`, `ac:image`, `ac:inline-comment-marker`, `local-id` attributes, etc.). The job here is a **lossless transform to clean Markdown, not a summary** — downstream pipelines (`tron:news-item`, `tron:toolkit-item`) rebuild pages from this output, so paraphrasing or dropping anything silently breaks them.

### The faithful-markdown contract

Every fetch — inline or delegated — must produce:

1. **Title** (`.title`) and **last-updated / version** from the metadata.
2. **Body as Markdown that losslessly preserves:**
   - Heading hierarchy (`h1`–`h6` → `#`…`######`)
   - **Images & attachments — never drop these.** Convert every `<ac:image>` / `ri:attachment` / `ri:url` to `![alt](X)` where `X` is the `ri:filename` (attached image) or the external `ri:value` URL, **verbatim**. `news-item` downloads images by this filename; a missing reference is a broken article.
   - Links (keep both href and text), tables (→ Markdown tables), ordered/unordered/nested lists
   - Code macros (`ac:structured-macro ac:name="code"`) → fenced block, preserving the `language` param
   - Panel/info/note/warning macros → blockquote with a label, e.g. `> **Note:** …`
   - Bold, italic, inline code, blockquotes
3. **Strip internal IDs:** `local-id`, `ac:local-id`, `ac:macro-id`, and similar noise attributes.
4. **Inline-comment markers** (`ac:inline-comment-marker`): unwrap to plain text in-line, **and** collect the wrapped snippets into a short "Recently commented / under discussion" note at the end. Text in these markers usually has an open comment attached, so it's often the newest / under-revision copy — worth flagging when diffing against an existing page.

When presenting to a human (not a pipeline), lead with the outline/headings, then the full body. When feeding a pipeline, return the full contract above with nothing elided.

## Delegated fetch (large pages / pipeline use)

The raw storage XML is verbose. When the page is large, or you're inside a multi-step workflow where you don't want raw XML bloating the orchestrator's context, **delegate Step 2 + Step 3 to a subagent** and let only the clean markdown come back.

- **Model:** Sonnet for anything with tables, nested lists, or macros (fidelity matters); Haiku only for short, flat pages.
- **The orchestrator resolves the page ID first** (Step 1 is tiny — keep it inline), then spawns the subagent with: the page ID, the `acli … --body-format storage --json` command, and the faithful-markdown contract above.
- **The subagent returns only:** title, last-updated, the markdown body, and a flat list of image attachment filenames (so the caller can download them). The raw XML stays in the subagent and never touches the main thread.

> Note: this primitive's own `allowed-tools` is `Bash`, so the **spawn happens from the calling workflow** (e.g. `tron:news-item`), which carries the subagent tool. Run standalone, `tron:confluence` fetches inline; the contract above is identical either way.

## Other useful acli flags

`acli confluence page` only has the `view` subcommand (there is no `page search`). Use `view` flags to pull extras:

```bash
# Include direct child pages
acli confluence page view --id <PAGE_ID> --include-direct-children --json

# Include labels / version metadata
acli confluence page view --id <PAGE_ID> --include-labels --include-version --json
```

Other Confluence groups: `acli confluence blog`, `acli confluence space`. Run `acli confluence page view --help` to confirm flags if one is rejected.

## Deprecated fallback (REST + curl)

Only if `acli` is unavailable. **The `JIRA_API_TOKEN` / 1Password ATATT token is stale and returns `401`** — this will almost certainly fail; refresh the token before relying on it.

```bash
curl -s -u "ian@facilitron.com:$JIRA_API_TOKEN" \
  "https://facilitron.atlassian.net/wiki/api/v2/pages/<PAGE_ID>?body-format=storage"
```
