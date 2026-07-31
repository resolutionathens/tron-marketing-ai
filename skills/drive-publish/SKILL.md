---
name: drive-publish
model: haiku
effort: low
description: Publish finished content deliverables to Google Drive. Use when asked to create a Google Doc from a draft, upload a PDF or file to an explicitly selected Drive folder, or update an explicitly identified Drive file.
allowed-tools:
  - Bash
scout:
  surface: developer
  effects: [publish]
  inputs:
    - key: destination
      label: "Drive folder or file ID"
      type: text
      required: true
    - key: source
      label: "Finished deliverable"
      type: path
      required: true
---

# Google Drive Publisher

Publish a finished local deliverable through the authenticated Google Workspace CLI. The destination must always be explicit. Never search Drive by filename, infer a folder, or fall back from update to create.

When the request provides exactly one matching local deliverable, use that file path directly. Ask for the source only when no deliverable was provided or multiple files make the choice ambiguous; do not stop on a placeholder path when the supplied file is already clear.

## Fast path

```bash
PUBLISH="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/google-workspace/drive-publish.mjs"

# Import a text or markdown draft as a native Google Doc in one folder
node "$PUBLISH" create-doc --folder-id <FOLDER_ID> --name '<DOCUMENT_NAME>' --source-file <FILE>

# Upload a PDF or other completed file into one folder
node "$PUBLISH" upload --folder-id <FOLDER_ID> --name '<FILE_NAME>' --mime-type <MIME_TYPE> --source-file <FILE>

# Replace an existing file only when its exact ID was supplied
node "$PUBLISH" update --file-id <FILE_ID> --name '<FILE_NAME>' --mime-type <MIME_TYPE> --source-file <FILE>
```

The command uses the identity already authenticated in `gws`. Never request, print, or pass OAuth tokens or credential files. If authentication fails, tell the user to run `gws auth login` with the supported Google Workspace identity.

## Destination and result contract

- `create-doc` and `upload` require a folder ID and validate that it is an active Drive folder before publishing.
- `update` requires a file ID. It never accepts a folder ID, searches by name, or creates a replacement.
- `--source-file` remains caller-owned and is never removed.
- The operation-scoped upload copy is removed after success or failure.
- Success prints one JSON object containing `fileId`, `mimeType`, `name`, and the durable Drive `url`. Return those exact values to the user.

For a new Google Doc, choose `create-doc`; do not create a blank Doc and assemble separate Docs API edits. For any other format, supply its actual MIME type to `upload`. Use `update` only when the user has explicitly provided the destination file ID and confirmed replacement.
