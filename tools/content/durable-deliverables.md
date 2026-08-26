# Durable content deliverables

This contract applies to every content-producing skill. `/tmp` and `$TMPDIR` are scratch space,
never a completed deliverable's destination.

## Resolve before drafting

Before creating copy, a report, brief, or publishing kit, resolve all of these fields:

- **Destination:** for text, either an explicit Google Drive folder/file ID or an explicit
  Confluence space plus parent/page ID. For a PDF or other file, either an explicit Google Drive
  folder/file ID or an explicit non-temporary local folder selected by the user.
- **Review state:** normally `draft`, `pending review`, or `approved`. Never claim approval that was
  not supplied.
- **Owner and approver:** name the person responsible for the deliverable and the person who can
  approve it. Ask when either is unknown.
- **Target surface and Jira key:** use `not applicable` only when the artifact is not website-bound
  or ticket-backed.
- **Asset references:** list source and supporting asset URLs, or `none` when there are none.

Do not draft until the destination is explicit. Reject a local final destination under `/tmp`, the
current `$TMPDIR`, a unique scratch workspace, or a repository checkout. Do not infer a Drive or
Confluence destination by title or filename.

## Scratch workspace and publishing

Create one operation-scoped workspace and install cleanup before writing anything into it:

```bash
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tron-content.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT HUP INT TERM
```

Only intermediate files go in `$WORK`. The trap must remain active through drafting, conversion,
publishing, and error handling so success and failure both remove the workspace.

- Text destined for Drive: draft in `$WORK`, then call `tron:drive-publish` with `create-doc` or an
  explicitly confirmed `update` file ID.
- Text destined for Confluence: draft storage-format HTML in `$WORK`, then call
  `tron:confluence-publish` with an explicit create or update destination.
- PDF or other file destined for Drive: generate in `$WORK`, then call `tron:drive-publish` with
  `upload` or an explicitly confirmed `update` file ID.
- File destined for a durable local folder: generate in `$WORK`, validate the chosen folder again,
  copy the completed file there, and verify the copied path exists before reporting success.

On publishing failure, report the error and no success metadata. Never fall back to another
destination or leave the scratch copy as the deliverable.

## Success response and website handoff

Return every field below, using the exact values returned by the publisher. A local file uses its
verified absolute non-temporary path as `Durable source`.

```text
Durable source: <Drive or Confluence URL, or verified absolute durable path>
Review state: <draft | pending review | approved>
Owner: <person responsible>
Approver: <person who can approve>
Target surface: <website route/channel/destination | not applicable>
Jira: <KEY | not applicable>
Asset references: <URLs/IDs | none>
Website handoff: <engineering publishing skill | not applicable>
```

For website-bound content, `Durable source` is the approved-source URL that the engineering
publishing skill consumes. Set `Website handoff` to the named engineering skill, such as
bare `news-item`, `guide-item`, or `toolkit-item`. The handoff must first create or reopen a
marketing-pages worktree and add that directory to the session because repo-local skills only appear
in the listing after their directory is added. Do not include repository paths, front matter,
component syntax, branches, or deployment instructions: those belong to engineering.

Content skills never create or switch branches, open worktrees, write repository content, commit,
push, or open pull requests.
