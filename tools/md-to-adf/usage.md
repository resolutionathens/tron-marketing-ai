# md-to-adf — rich Jira descriptions from markdown

Shared usage notes for the vendored converter at `tools/md-to-adf/md-to-adf.mjs`
(lazy-installs its one npm dep on first run). Consumed by `tron:jira` and
`tron:jira-ticket-enricher`.

## The acli plain-text gotcha

`acli` sends `--description` as plain text wrapped in a single ADF paragraph node. Jira Cloud's
REST API v3 requires Atlassian Document Format (ADF) JSON for any structured content, so
**markdown passed via `--description` renders literally** — `##`, `**bold**`, backticks, and
bullets all show up as raw characters. Don't ask the user to paste into the Jira UI as a
workaround; convert instead.

**Rule: never pass raw markdown to `-d`/`--description`.** Any time a description is more than a
line or two, or uses any markdown formatting, go through this helper.

## Invocation (`--description-file`)

```bash
# Write the description as markdown, then convert (default preset: story).
# Two forms work — pass a file path directly, or pipe via stdin:

# Form 1: File path argument
node "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/md-to-adf/md-to-adf.mjs" \
  /tmp/desc.md > /tmp/desc.adf.json

# Form 2: Stdin (pipe or redirect)
node "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/md-to-adf/md-to-adf.mjs" \
  < /tmp/desc.md > /tmp/desc.adf.json

# Create with rich formatting
acli jira workitem create \
  --project MD --type Task \
  --summary "Your summary" \
  --description-file /tmp/desc.adf.json

# Or edit an existing ticket's description
acli jira workitem edit --key MD-1234 --description-file /tmp/desc.adf.json --yes
```

## What converts

The helper uses the `markdown-to-adf` npm package with the `story` preset (full heading support).
It handles: headings, **bold**, _italic_, fenced code blocks, bullet/numbered lists, links,
horizontal rules.

**Code-mark stripping:** inline `code` (backtick) spans are flattened to plain text — `acli`
rejects the ADF `code` mark with `INVALID_INPUT`, so the helper strips it (the text is kept, just
unstyled). Use a fenced code block when you need monospace.

**Blockquote flattening:** `> quoted text` is rewritten as an italicized plain paragraph — `acli`
rejects any ADF document containing a `blockQuote` node with `INVALID_INPUT` (MD-2052), so the
helper drops the `blockQuote` wrapper and italicizes the inner text instead. The quote reads as
plain (but visually distinct) text rather than an indented block.

Tables and images aren't supported — if you need them, edit in the Jira UI afterwards.
