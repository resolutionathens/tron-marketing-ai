---
name: confluence-publish
model: haiku
effort: low
description: "Create or update authenticated Confluence pages for finished content deliverables. Use when asked to publish, save, send, or update final copy in Confluence, or when a content-producing skill needs a durable Confluence URL instead of a temporary file. Requires an explicit space and parent for create or an explicit page ID for update; never finds overwrite targets by title."
allowed-tools:
  - Bash
scout:
  surface: true
  title: "Publish content to Confluence"
  blurb: "Saves a finished content deliverable to an explicitly selected Confluence destination."
  when: "Final copy needs a durable Confluence page for review or handoff."
  category: drafting
  effects: [publish]
  inputs:
    - key: destination
      label: "Space, parent, or page ID"
      type: text
      required: true
      placeholder: "Space ID + parent ID for new pages, or page ID to update"
    - key: content
      label: "Finished content file"
      type: path
      required: true
---

# Publish a Content Deliverable to Confluence

Create a durable Confluence page or overwrite one explicitly selected existing page. This skill owns Confluence writes; use `tron:confluence` for reads.

## Safety contract

- Treat publishing as an outward-facing action. Confirm the exact destination and completed content before running the command unless the calling workflow already supplied them explicitly.
- Create requires both a numeric space ID and a numeric parent page ID. Never infer either from the current page, a title, or search results.
- Update requires a numeric page ID. Never search by title to choose an overwrite target and never fall back from update to create.
- Pass the completed storage-format HTML from its durable working location. The publisher reads that file directly and creates no `/tmp` copy.
- Authentication goes only through the supported Atlassian broker. The tool keeps the broker credential in process memory and never passes it in command arguments, logs, or temporary files.

## Fast path

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}"
PUBLISH="$ROOT/tools/confluence/publish-confluence.mjs"

node "$PUBLISH" create \
  --space-id <SPACE_ID> --parent-id <PARENT_PAGE_ID> \
  --title "<PAGE_TITLE>" --body-file <STORAGE_HTML_FILE>

node "$PUBLISH" update \
  --page-id <EXISTING_PAGE_ID> \
  --title "<PAGE_TITLE>" --body-file <STORAGE_HTML_FILE>
```

Both commands emit one JSON line:

```json
{"ok":true,"action":"create|update","pageId":"4242","version":1,"title":"Page title","url":"https://facilitron.atlassian.net/wiki/..."}
```

Return the exact `pageId`, `version`, `title`, and durable `url` to the caller. On failure, stop and report the error; do not retry as a different action or destination.
