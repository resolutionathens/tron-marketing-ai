# Source-type catalog — what metadata each source carries

Identify the source type from the links gathered in steps 1–3 and capture whatever the
implementer will need. A ticket often has more than one source (a spec plus a design, say) —
capture each.

## Design and content sources

- **Figma file** — keep the full URL with its `node-id`. Note the frame or page name from any comment. The implementer builds to this; do not try to render it.
- **Existing or HubSpot page being replaced** — keep the URL as the content/layout reference.
- **Asset location** — an ImageKit folder, a download link, or attachments named in the source ticket.
- **Google Doc** — when accessible, fetch its text export and read fields near the top such as `Meta Title:`, `Meta Description:`, `Slug:`, the H1 title, and Purpose / Scope / Procedure / FAQ sections.

## Spec and code sources

- **Confluence page** — the brief or spec often lives here. Fetch the body with the shared helper so the spec text lands in the description, not just a link:
  ```bash
  "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/confluence/fetch-confluence.sh" <confluence-url-or-id>
  ```
  Pull the goal, scope, and any acceptance criteria already written there.
- **GitHub PR, issue, or code path** — keep the URL, or a `owner/repo` + file path / symbol reference, so the implementer knows exactly where the change or the prior art lives. A linked PR is often the pattern to copy or the thing to revert.
- **Error or monitoring link** (Sentry, logs, dashboard) — keep the issue URL and capture the error message, affected endpoint, and frequency if shown. This is the repro context for a fix.
- **Chat or recording link** (Slack thread, Loom) — keep the URL as provenance, but note it may not be accessible to the implementer; summarize any decision captured in the ticket text rather than relying on the link.

If a source is not directly accessible, still enrich the ticket with its URL and note that the
implementer should use it as the reference.
